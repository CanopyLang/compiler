{-# LANGUAGE OverloadedStrings #-}

-- | Wire-format golden for the CMP-8 native bundle container.
--
-- == Why this exists
--
-- 'Unit.Generate.JavaScript.HermesContainerTest' pins the container's BEHAVIOR
-- (round-trip, integrity, validation). This suite pins its BYTES: it snapshots a
-- hex dump of the exact header the compiler emits for a representative HBC
-- container and a JS-source container, so the on-disk layout the HOST reads from
-- fixed offsets ('host/shared/cpp' container gate) cannot drift silently. A
-- field reorder, an endianness slip, or a size change moves the golden the
-- instant it happens — which is exactly the cross-language wire contract a
-- behavior test alone cannot guard (the host is not in this test process).
--
-- The golden is a stable, hand-auditable table: the header bytes, annotated by
-- field, plus the byte offsets a host reader keys on. Regenerate with
-- @stack test --test-arguments=--accept@ ONLY when the container format is
-- intentionally bumped (and then 'host/shared/cpp's reader + 'kHeaderSize' move
-- in lockstep).
--
-- @since 0.20.10
module Integration.Native.HermesContainerWireTest (tests) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as LBS8
import Data.Word (Word8)
import qualified Generate.JavaScript.HermesContainer as HC
import Numeric (showHex)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Golden (goldenVsString)

tests :: TestTree
tests =
  testGroup
    "Native.HermesContainerWire (CMP-8)"
    [ goldenVsString
        "native container header wire layout"
        "test/Golden/expected/HermesContainerWire.golden"
        (pure wireSnapshot)
    ]

-- | A fixed HBC payload (the first bytes happen to be the Hermes magic — to make
-- the point that the container FRAMES an .hbc, it is not itself the .hbc).
hbcPayload :: BS.ByteString
hbcPayload = BS.pack [0xC6, 0x1F, 0xBC, 0x03, 0xC1, 0x03, 0x19, 0x1F]

-- | A fixed JS-source payload.
jsPayload :: BL.ByteString
jsPayload = "var x=1;"

-- | The whole snapshot: the two header dumps + the offset table.
wireSnapshot :: BL.ByteString
wireSnapshot =
  LBS8.pack . unlines $
    [ "== CMP-8 native bundle container wire format (v1) =="
    , ""
    , "magic (u64 LE)  : " ++ hexBytes (le64Bytes HC.kCanopyContainerMagic) ++ "  (\"CANOPY\\x01\\x01\")"
    , "container ver   : " ++ show HC.kCanopyContainerVersion
    , "header size     : " ++ show HC.kHeaderSize ++ " bytes"
    , ""
    , "field offsets (a host reads these fixed positions):"
    , "  [ 0..8)  magic            u64 LE"
    , "  [ 8..12) containerVersion u32 LE"
    , "  [12..16) payloadKind      u32 LE   (0=JsSource, 1=HbcBytecode)"
    , "  [16..20) bytecodeVersion  u32 LE   (0 for JsSource)"
    , "  [20..24) abiVersion       u32 LE"
    , "  [24..28) payloadLength    u32 LE"
    , "  [28..32) headerCrc        u32 LE   (CRC-32 of bytes [0,28))"
    , ""
    , "-- HBC container (bytecodeVersion=96, abiVersion=1, payload=8 bytes) --"
    , "header bytes : " ++ hexBytes (headerOf (HC.wrapHbc 96 1 hbcPayload))
    , ""
    , "-- JS-source container (abiVersion=1, payload=8 bytes) --"
    , "header bytes : " ++ hexBytes (headerOf (HC.wrapJsSource 1 jsPayload))
    ]

-- | The first 'HC.kHeaderSize' bytes of a built container — its header.
headerOf :: BB.Builder -> BS.ByteString
headerOf = BS.take HC.kHeaderSize . BL.toStrict . BB.toLazyByteString

-- | The little-endian bytes of a 'Word64' (for the magic dump).
le64Bytes :: (Integral a) => a -> BS.ByteString
le64Bytes = BL.toStrict . BB.toLazyByteString . BB.word64LE . fromIntegral

-- | A space-separated uppercase hex dump of a byte string.
hexBytes :: BS.ByteString -> String
hexBytes = unwords . map hex2 . BS.unpack
  where
    hex2 :: Word8 -> String
    hex2 b =
      let s = showHex b ""
       in (if length s < 2 then '0' : s else s)
