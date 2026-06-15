{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for 'Generate.JavaScript.HermesContainer' (CMP-8).
--
-- The container is the versioned wrapper the host validates before it will run a
-- byte of a native bundle: a fixed 32-byte header (magic + container version +
-- payload kind + bytecode version + ABI version + payload length + header CRC)
-- followed by the payload — a Hermes @.hbc@ in production, or the JS source in
-- the dev fallback. These tests pin the wire format and the build↔host contract
-- at the unit level:
--
--   * the magic is the human-recognizable @\"CANOPY\\x01\\x01\"@ on disk and
--     cannot collide with the raw Hermes @.hbc@ magic;
--   * 'wrap' / 'parseContainer' ROUND-TRIP — every header field and the exact
--     payload bytes survive a write→read cycle (so the host reads back what the
--     compiler stamped);
--   * the header CRC catches a corrupted header, and the declared payload length
--     catches a truncated download;
--   * 'validate' (the host-mirror gate) rejects exactly the mismatches the host
--     rejects — wrong container version, an @.hbc@ bytecode version ≠ the engine,
--     an ABI version ≠ the host — and ACCEPTS the JS-source dev fallback
--     regardless of the engine bytecode version; and
--   * the documented @hermesc@ invocation carries the load-bearing flags
--     (@-emit-binary@, @-O@, @-output-source-map@).
--
-- The CRC implementation is cross-checked against the canonical CRC-32 test
-- vector (@crc32("123456789") == 0xCBF43926@) so the host can re-implement the
-- identical check.
--
-- @since 0.20.10
module Unit.Generate.JavaScript.HermesContainerTest (tests) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BL
import Data.Word (Word32, Word64)
import qualified Generate.JavaScript.HermesContainer as HC
import Test.Tasty
import Test.Tasty.HUnit

-- | The engine pin used across the host gate (react-native 0.76.9 → HBC 96).
enginePin :: Word32
enginePin = 96

-- | The Canopy ABI version the host speaks (CANOPY_ABI_VERSION == 1).
hostAbi :: Word32
hostAbi = 1

-- | A small stand-in @.hbc@ payload. The container does not interpret the
-- payload bytes — it only frames them — so any recognizable bytes exercise the
-- contract.
sampleHbc :: BS.ByteString
sampleHbc = BS.pack [0xC6, 0x1F, 0xBC, 0x03, 0xC1, 0x03, 0x19, 0x1F, 0x60, 0x00, 0x00, 0x00, 0xDE, 0xAD]

-- | A JS-source dev-fallback payload.
sampleJs :: BL.ByteString
sampleJs = "(function(scope){'use strict';})(this);\n// __canopy_boot ...\n"

-- | Materialize a 'BB.Builder' container to strict bytes.
build :: BB.Builder -> BS.ByteString
build = BL.toStrict . BB.toLazyByteString

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.HermesContainer (CMP-8)"
    [ magicTests
    , roundTripTests
    , integrityTests
    , validateTests
    , crcTests
    , hermescTests
    ]

-- MAGIC ---------------------------------------------------------------------

magicTests :: TestTree
magicTests =
  testGroup
    "container magic"
    [ testCase "magic spells CANOPY\\x01\\x01 on disk (little-endian bytes)" $
        let bytes = build (BB.word64LE HC.kCanopyContainerMagic)
         in BS.unpack bytes @?= [0x43, 0x41, 0x4E, 0x4F, 0x50, 0x59, 0x01, 0x01]
    , testCase "the first six magic bytes are the ASCII \"CANOPY\"" $
        let bytes = build (BB.word64LE HC.kCanopyContainerMagic)
         in BS.take 6 bytes @?= BSC.pack "CANOPY"
    , testCase "container magic cannot collide with the raw Hermes .hbc magic" $
        -- The host distinguishes a container (this magic) from a bare .hbc
        -- (the Hermes magic 0x1F1903C103BC1FC6) by reading the SAME 8 bytes.
        assertBool
          "the container magic must differ from the Hermes bytecode magic"
          (HC.kCanopyContainerMagic /= (0x1F1903C103BC1FC6 :: Word64))
    , testCase "the header is the documented fixed size (32 bytes)" $
        HC.kHeaderSize @?= 32
    , testCase "the compiler's pinned constants mirror the host" $ do
        -- These MUST track host/shared/cpp: CanopyAbi.h CANOPY_ABI_VERSION == 1,
        -- CanopyAbiGate.h kCanopyExpectedHermesBytecodeVersion == 96. A drift
        -- here ships a container the host rejects, so it is pinned in a test.
        HC.kCanopyAbiVersion @?= 1
        HC.kCanopyEngineBytecodeVersion @?= 96
        HC.kCanopyContainerVersion @?= 1
    ]

-- ROUND TRIP ----------------------------------------------------------------

roundTripTests :: TestTree
roundTripTests =
  testGroup
    "wrap / parse round-trip"
    [ testCase "an HBC container parses back to the exact header + payload" $
        let container = build (HC.wrapHbc enginePin hostAbi sampleHbc)
         in case HC.parseContainer container of
              Left e -> assertFailure ("expected a clean parse, got: " ++ show e)
              Right (h, payload) -> do
                HC.chContainerVersion h @?= HC.kCanopyContainerVersion
                HC.chPayloadKind h @?= HC.HbcBytecode
                HC.chBytecodeVersion h @?= enginePin
                HC.chAbiVersion h @?= hostAbi
                HC.chPayloadLength h @?= fromIntegral (BS.length sampleHbc)
                payload @?= sampleHbc
    , testCase "a JS-source container parses back with kind JsSource + bytecode 0" $
        let container = build (HC.wrapJsSource hostAbi sampleJs)
         in case HC.parseContainer container of
              Left e -> assertFailure ("expected a clean parse, got: " ++ show e)
              Right (h, payload) -> do
                HC.chPayloadKind h @?= HC.JsSource
                -- a source payload targets no specific bytecode version
                HC.chBytecodeVersion h @?= 0
                HC.chAbiVersion h @?= hostAbi
                payload @?= BL.toStrict sampleJs
    , testCase "the container is exactly header (32) + payload bytes" $
        let container = build (HC.wrapHbc enginePin hostAbi sampleHbc)
         in BS.length container @?= HC.kHeaderSize + BS.length sampleHbc
    , testCase "wrapHbc stamps the bytecode version; wrapJsSource zeroes it" $ do
        case HC.parseHeader (build (HC.wrapHbc 200 hostAbi sampleHbc)) of
          Left e -> assertFailure (show e)
          Right h -> HC.chBytecodeVersion h @?= 200
        case HC.parseHeader (build (HC.wrapJsSource hostAbi sampleJs)) of
          Left e -> assertFailure (show e)
          Right h -> HC.chBytecodeVersion h @?= 0
    , testCase "an empty payload still produces a well-formed container" $
        let container = build (HC.wrapHbc enginePin hostAbi BS.empty)
         in case HC.parseContainer container of
              Left e -> assertFailure (show e)
              Right (h, payload) -> do
                HC.chPayloadLength h @?= 0
                payload @?= BS.empty
    ]

-- INTEGRITY -----------------------------------------------------------------

integrityTests :: TestTree
integrityTests =
  testGroup
    "structural integrity (host first-read rejections)"
    [ testCase "fewer than 32 bytes is TooShort" $
        case HC.parseHeader (BS.pack [0x43, 0x41, 0x4E]) of
          Left (HC.TooShort n) -> n @?= 3
          other -> assertFailure ("expected TooShort, got: " ++ show other)
    , testCase "a non-container buffer (no magic) is BadMagic" $
        -- a bare .hbc (opens with the Hermes magic) is NOT a container
        let bareHbc = build (BB.word64LE 0x1F1903C103BC1FC6) <> BS.pack (replicate 24 0)
         in case HC.parseHeader bareHbc of
              Left (HC.BadMagic m) -> m @?= 0x1F1903C103BC1FC6
              other -> assertFailure ("expected BadMagic, got: " ++ show other)
    , testCase "a flipped header byte is caught by the header CRC" $
        let container = build (HC.wrapHbc enginePin hostAbi sampleHbc)
            -- corrupt the ABI-version field (offset 20) without fixing the CRC
            corrupted = flipByteAt 20 container
         in case HC.parseHeader corrupted of
              Left (HC.HeaderCrcMismatch _ _) -> pure ()
              other -> assertFailure ("expected HeaderCrcMismatch, got: " ++ show other)
    , testCase "an unknown payload-kind tag is rejected (UnknownPayloadKind)" $
        -- hand-build a header with payload kind 99 and a CRC over those bytes
        let header =
              build
                ( BB.word64LE HC.kCanopyContainerMagic
                    <> BB.word32LE HC.kCanopyContainerVersion
                    <> BB.word32LE 99 -- bogus kind
                    <> BB.word32LE 0
                    <> BB.word32LE hostAbi
                    <> BB.word32LE 0
                )
            crc = HC.crc32 header
            full = header <> build (BB.word32LE crc)
         in case HC.parseHeader full of
              Left (HC.UnknownPayloadKind tag) -> tag @?= 99
              other -> assertFailure ("expected UnknownPayloadKind, got: " ++ show other)
    , testCase "a truncated payload (length mismatch) is PayloadLengthMismatch" $
        let container = build (HC.wrapHbc enginePin hostAbi sampleHbc)
            -- drop the last 3 payload bytes — header still claims the full length
            truncated = BS.take (BS.length container - 3) container
         in case HC.parseContainer truncated of
              Left (HC.PayloadLengthMismatch declared actual) -> do
                declared @?= fromIntegral (BS.length sampleHbc)
                actual @?= BS.length sampleHbc - 3
              other -> assertFailure ("expected PayloadLengthMismatch, got: " ++ show other)
    ]

-- VALIDATE (host-mirror) ----------------------------------------------------

validateTests :: TestTree
validateTests =
  testGroup
    "validate (host go/no-go mirror)"
    [ testCase "a matching HBC container validates" $
        withHeader (HC.wrapHbc enginePin hostAbi sampleHbc) $ \h ->
          HC.validate HC.kCanopyContainerVersion enginePin hostAbi h @?= Right ()
    , testCase "an HBC bytecode version ≠ the engine is rejected" $
        withHeader (HC.wrapHbc 95 hostAbi sampleHbc) $ \h ->
          HC.validate HC.kCanopyContainerVersion enginePin hostAbi h
            @?= Left (HC.BytecodeVersionMismatch 95 enginePin)
    , testCase "an ABI version ≠ the host is rejected (for HBC)" $
        withHeader (HC.wrapHbc enginePin 2 sampleHbc) $ \h ->
          HC.validate HC.kCanopyContainerVersion enginePin hostAbi h
            @?= Left (HC.AbiVersionMismatch 2 hostAbi)
    , testCase "an unsupported container version is rejected" $
        withHeader (HC.wrapHbc enginePin hostAbi sampleHbc) $ \h ->
          -- host understands version 2, the bundle is version 1
          HC.validate 2 enginePin hostAbi h
            @?= Left (HC.UnsupportedContainerVersion HC.kCanopyContainerVersion 2)
    , testCase "the JS-source dev fallback validates regardless of engine bytecode" $
        -- The dev fallback always loads: its bytecode version is 0 and is NOT
        -- gated against the engine (the engine parses source either way).
        withHeader (HC.wrapJsSource hostAbi sampleJs) $ \h ->
          HC.validate HC.kCanopyContainerVersion 12345 hostAbi h @?= Right ()
    , testCase "the JS-source fallback STILL gates the ABI version" $
        withHeader (HC.wrapJsSource 2 sampleJs) $ \h ->
          HC.validate HC.kCanopyContainerVersion enginePin hostAbi h
            @?= Left (HC.AbiVersionMismatch 2 hostAbi)
    ]

-- CRC-32 --------------------------------------------------------------------

crcTests :: TestTree
crcTests =
  testGroup
    "crc32"
    [ testCase "matches the canonical check vector crc32(\"123456789\")" $
        HC.crc32 (BSC.pack "123456789") @?= 0xCBF43926
    , testCase "crc32 of empty is 0" $
        HC.crc32 BS.empty @?= 0
    , testCase "a one-byte change changes the CRC" $
        assertBool
          "CRC must be sensitive to a single-byte flip"
          (HC.crc32 (BSC.pack "123456789") /= HC.crc32 (BSC.pack "123456788"))
    ]

-- HERMESC INVOCATION (documented) -------------------------------------------

hermescTests :: TestTree
hermescTests =
  testGroup
    "hermesc invocation (documented; not run here)"
    [ testCase "carries the load-bearing flags" $ do
        let cmd = HC.hermescCommand "hermesc" "canopy.bundle.js" "canopy.bundle.hbc"
        assertBool "binary first" (take 1 cmd == ["hermesc"])
        assertBool "-emit-binary (emit .hbc, not disassembly)" ("-emit-binary" `elem` cmd)
        assertBool "-O (optimize for production)" ("-O" `elem` cmd)
        assertBool "-output-source-map (the bytecode→source map)" ("-output-source-map" `elem` cmd)
        assertBool "-out names the .hbc output" ("canopy.bundle.hbc" `elem` cmd)
        assertBool "the input JS bundle is passed" ("canopy.bundle.js" `elem` cmd)
    , testCase "the version probe is hermesc --version" $
        HC.hermescVersionProbe "hermesc" @?= ["hermesc", "--version"]
    ]

-- HELPERS -------------------------------------------------------------------

-- | Parse a built container's header and hand it to a continuation, failing the
-- test if it does not parse.
withHeader :: BB.Builder -> (HC.ContainerHeader -> Assertion) -> Assertion
withHeader builder k =
  case HC.parseHeader (build builder) of
    Left e -> assertFailure ("expected the header to parse, got: " ++ show e)
    Right h -> k h

-- | Flip the low bit of the byte at index @i@ (to corrupt a header field).
flipByteAt :: Int -> BS.ByteString -> BS.ByteString
flipByteAt i bs =
  let (before, rest) = BS.splitAt i bs
   in case BS.uncons rest of
        Nothing -> bs
        Just (b, tailBytes) -> before <> BS.singleton (b + 1) <> tailBytes
