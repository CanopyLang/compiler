{-# LANGUAGE OverloadedStrings #-}

-- | Unit + golden tests for 'Generate.JavaScript.NativeMutation' (CMP-12).
--
-- The compact mutation encoder is the COMPILER side of RND-7 Stage B: it pins the
-- string-pooled (columnar) native-mutation wire format and emits the JS encoder
-- the native bundle reaches. Three artifacts must agree on these bytes
-- byte-for-byte (@native.js@, @CanopyFabric.cpp@, @mock-fabric.js@), so this suite
-- is the device-free contract guard:
--
--   * PROTOCOL CONSTANTS are frozen to the exact values the host enums use
--     (opcodes 1..7, handle base 0x40000000, magic 0xCB, version 1);
--   * the STRING POOL interns each distinct string once, in first-appearance
--     order, so a repeated tag/key/event-list collapses to one pool entry + small
--     indices — the CMP-12 "string-pool integers index prop keys" win;
--   * the GOLDEN BYTES pin the full little-endian buffer for a representative op
--     stream (header + pool + ops), so any drift in the wire format is caught here;
--   * the EMITTED JS interpolates the SAME pinned constants (so it can never
--     disagree with the reference encoder) and defines the opt-in entry point.
--
-- @since 0.20.11
module Unit.Generate.JavaScript.NativeMutationTest (tests) where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import Data.List (isInfixOf)
import Data.Word (Word8)
import qualified Generate.JavaScript.NativeMutation as NM
import Test.Tasty
import Test.Tasty.HUnit

-- | The little-endian bytes the reference encoder produced, as a @[Word8]@ for
-- exact golden assertions.
encBytes :: [NM.Op] -> [Word8]
encBytes = BL.unpack . BB.toLazyByteString . NM.encodePooled

-- | A little-endian uint32 as four bytes (golden helper).
u32 :: Int -> [Word8]
u32 n = [b 0, b 8, b 16, b 24]
  where
    b s = fromIntegral ((n `div` (2 ^ s)) `mod` 256)

-- | A length-prefixed UTF-8 ASCII pool entry (golden helper).
poolAscii :: String -> [Word8]
poolAscii s = u32 (length s) ++ map (fromIntegral . fromEnum) s

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.NativeMutation (CMP-12)"
    [ constantTests
    , poolTests
    , goldenTests
    , encoderJsTests
    ]

-- PROTOCOL CONSTANTS --------------------------------------------------------

constantTests :: TestTree
constantTests =
  testGroup
    "frozen protocol constants (mirror the host enums)"
    [ testCase "opcodes are the host's 1..7 in order" $
        map NM.opcodeValue NM.allOpcodes @?= [1, 2, 3, 4, 5, 6, 7]
    , testCase "every opcode is covered exactly once (no gaps/dupes)" $
        length NM.allOpcodes @?= 7
    , testCase "handle base is 0x40000000 (mirrors __fabric_batchHandleBase)" $
        NM.handleBase @?= 0x40000000
    , testCase "pooled magic is 0xCB, outside the opcode range 1..7" $ do
        NM.pooledMagic @?= 0xCB
        assertBool "magic must not collide with any opcode byte"
          (NM.pooledMagic `notElem` map NM.opcodeValue NM.allOpcodes)
    , testCase "protocol version is 1" $
        NM.protocolVersion @?= 1
    ]

-- STRING POOL ---------------------------------------------------------------

poolTests :: TestTree
poolTests =
  testGroup
    "string pool (intern once, first-appearance order)"
    [ testCase "distinct strings are pooled in first-appearance order" $
        -- create visits tag then props; the repeated tag on the 2nd create reuses
        -- index 0, the new props is a fresh entry.
        let ops =
              [ NM.Create 1 "RCTView" "{}"
              , NM.Create 2 "RCTView" "{\"x\":1}"
              ]
            pool = NM.buildPool ops
         in NM.poolStrings pool @?= ["RCTView", "{}", "{\"x\":1}"]
    , testCase "a repeated string collapses to ONE pool entry (the dedup win)" $
        let ops =
              [ NM.Scalar 1 "text" "a"
              , NM.Scalar 2 "text" "b"
              , NM.Scalar 3 "text" "c"
              ]
            pool = NM.buildPool ops
         in do
              -- "text" appears 3x but is pooled once; a/b/c are distinct.
              NM.poolStrings pool @?= ["text", "a", "b", "c"]
              NM.poolIndex pool "text" @?= 0
    , testCase "an op with no strings contributes nothing to the pool" $
        let ops = [NM.Insert 1 2 0, NM.Remove 1 2 0, NM.SetRoot 1]
         in NM.poolStrings (NM.buildPool ops) @?= []
    , testCase "empty op list yields an empty pool" $
        NM.poolStrings (NM.buildPool []) @?= []
    ]

-- GOLDEN BYTES --------------------------------------------------------------

goldenTests :: TestTree
goldenTests =
  testGroup
    "golden wire bytes (the pinned little-endian format)"
    [ testCase "empty batch is just header + zero-count pool" $
        encBytes []
          @?= [0xCB, 0x01] -- magic, version
            ++ u32 0 -- pool count 0
            -- no ops
    , testCase "a single setRoot: header + empty pool + opcode + i32 handle" $
        encBytes [NM.SetRoot 7]
          @?= [0xCB, 0x01]
            ++ u32 0 -- no strings
            ++ [6] -- OpSetRoot
            ++ u32 7 -- handle (LE)
    , testCase "insert/remove carry three raw int32s, no pool entries" $
        encBytes [NM.Insert 10 20 2]
          @?= [0xCB, 0x01]
            ++ u32 0
            ++ [4] -- OpInsert
            ++ u32 10
            ++ u32 20
            ++ u32 2
    , testCase "a scalar: pool has [key,value]; op carries handle + 2 indices" $
        encBytes [NM.Scalar 5 "text" "hi"]
          @?= [0xCB, 0x01]
            ++ u32 2 -- pool count
            ++ poolAscii "text" -- index 0
            ++ poolAscii "hi" -- index 1
            ++ [3] -- OpScalar
            ++ u32 5 -- handle
            ++ u32 0 -- index of "text"
            ++ u32 1 -- index of "hi"
    , testCase "a repeated tag is written ONCE in the pool; both ops index it" $
        -- The dominant-case win in bytes: two creates of the same tag share pool[0].
        encBytes [NM.Create 1 "RCTView" "{}", NM.Create 2 "RCTView" "{}"]
          @?= [0xCB, 0x01]
            ++ u32 2 -- pool: "RCTView", "{}"
            ++ poolAscii "RCTView" -- index 0
            ++ poolAscii "{}" -- index 1
            ++ [1] -- OpCreate #1
            ++ u32 1 -- handle
            ++ u32 0 -- tag -> index 0
            ++ u32 1 -- props -> index 1
            ++ [1] -- OpCreate #2
            ++ u32 2 -- handle
            ++ u32 0 -- tag -> index 0 (SAME, deduped)
            ++ u32 1 -- props -> index 1 (SAME, deduped)
    , testCase "multibyte UTF-8 is length-prefixed by BYTE count (café = 5 bytes)" $
        -- 'é' is 2 UTF-8 bytes, so "café" is 5 bytes, not 4 chars — the trap a
        -- naive char-count length would fail. Pins the framing the host decoder
        -- mirrors (BatchReader::str reads a byte length).
        let bytes = encBytes [NM.Scalar 1 "text" "caf\xe9"]
            -- header + pool count(2) + "text"(4+4) + "café"(4+5)
            poolPart = u32 2 ++ poolAscii "text" ++ (u32 5 ++ [0x63, 0x61, 0x66, 0xC3, 0xA9])
         in bytes @?= [0xCB, 0x01] ++ poolPart ++ [3] ++ u32 1 ++ u32 0 ++ u32 1
    , testCase "setEvents pools its names JSON and indices it" $
        encBytes [NM.SetEvents 9 "[\"press\"]"]
          @?= [0xCB, 0x01]
            ++ u32 1
            ++ poolAscii "[\"press\"]"
            ++ [7] -- OpSetEvents
            ++ u32 9
            ++ u32 0
    ]

-- EMITTED ENCODER JS --------------------------------------------------------

encoderJsTests :: TestTree
encoderJsTests =
  testGroup
    "generated encoder JS (interpolates the pinned constants)"
    [ testCase "defines the opt-in pooled encoder entry point" $
        assertBool "expected __canopy_encodeBatchPooled definition"
          ("g.__canopy_encodeBatchPooled = function (ops)" `isInfixOf` NM.encoderSource)
    , testCase "advertises the handle base it allocates from" $
        assertBool "expected __canopy_batchHandleBase assignment"
          ("g.__canopy_batchHandleBase = HANDLE_BASE" `isInfixOf` NM.encoderSource)
    , testCase "interpolates the magic byte as the pinned 203 (0xCB)" $
        assertBool "expected MAGIC = 203"
          ("var MAGIC = 203;" `isInfixOf` NM.encoderSource)
    , testCase "interpolates the pinned version + handle base" $ do
        assertBool "expected VERSION = 1" ("var VERSION = 1;" `isInfixOf` NM.encoderSource)
        assertBool "expected HANDLE_BASE = 1073741824"
          ("var HANDLE_BASE = 1073741824;" `isInfixOf` NM.encoderSource)
    , testCase "interpolates the frozen opcode values (1..7)" $ do
        assertBool "OP_CREATE = 1" ("OP_CREATE = 1" `isInfixOf` NM.encoderSource)
        assertBool "OP_SCALAR = 3" ("OP_SCALAR = 3" `isInfixOf` NM.encoderSource)
        assertBool "OP_SET_EVENTS = 7" ("OP_SET_EVENTS = 7" `isInfixOf` NM.encoderSource)
    , testCase "reuses the bundle's _Native_utf8 helper (byte-count parity)" $
        assertBool "expected g._Native_utf8 reuse"
          ("g._Native_utf8" `isInfixOf` NM.encoderSource)
    , testCase "is wrapped in a globalThis-or-this IIFE (matches bootHook shape)" $
        assertBool "expected the globalThis/this scope tail"
          ("typeof globalThis !== 'undefined' ? globalThis : this" `isInfixOf` NM.encoderSource)
    , testCase "carries the GENERATED-by-CMP-12 provenance banner" $
        assertBool "expected the CMP-12 provenance comment"
          ("compact (string-pooled) mutation encoder (CMP-12)" `isInfixOf` NM.encoderSource)
    , testCase "the encoder builder renders to the same UTF-8 bytes as the source" $
        -- Compare at the BYTE level (the builder is UTF-8): 'encoder' must be
        -- exactly 'encoderSource' serialized, so the bundle assembler and a
        -- substring test see the same content.
        BB.toLazyByteString NM.encoder @?= BB.toLazyByteString (BB.stringUtf8 NM.encoderSource)
    ]
