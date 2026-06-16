{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for 'Generate.JavaScript.HermesContainer' (CMP-8, CMP-11).
--
-- The container is the versioned wrapper the host validates before it will run a
-- byte of a native bundle: a fixed 48-byte header (magic + container version +
-- payload kind + bytecode version + ABI version + CMP-11 RN-target + compiler
-- version + runtimeVersion fingerprint + payload length + reserved + header CRC)
-- followed by the payload — a Hermes @.hbc@ in production, or the JS source in
-- the dev fallback. These tests pin the wire format and the build↔host contract
-- at the unit level:
--
--   * the magic is the human-recognizable @\"CANOPY\\x01\\x02\"@ on disk and
--     cannot collide with the raw Hermes @.hbc@ magic;
--   * 'wrap' / 'parseContainer' ROUND-TRIP — every header field and the exact
--     payload bytes survive a write→read cycle (so the host reads back what the
--     compiler stamped);
--   * the CMP-11 stamps round-trip too: 'wrapFor' threads the @--rn-target@ pin
--     and compiler version, 'parseHeader' reads them back, and the
--     runtimeVersion fingerprint is the CRC over the four version fields and is
--     sensitive to a change in any of them;
--   * the header CRC catches a corrupted header, and the declared payload length
--     catches a truncated download;
--   * 'validate' / 'validateAgainst' (the host-mirror gate) reject exactly the
--     mismatches the host rejects — wrong container version, an @.hbc@ bytecode
--     version ≠ the engine, an ABI version ≠ the host, an RN target ≠ the host's
--     pin, or a runtimeVersion fingerprint ≠ the host's — and ACCEPT the
--     JS-source dev fallback regardless of the engine bytecode version; and
--   * the documented @hermesc@ invocation carries the load-bearing flags
--     (@-emit-binary@, @-O@, @-output-source-map@), and the @--rn-target@
--     selector picks the version-matched @hermesc@ path.
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
    "Generate.JavaScript.HermesContainer (CMP-8, CMP-11)"
    [ magicTests
    , roundTripTests
    , integrityTests
    , validateTests
    , crcTests
    , hermescTests
    , rnTargetTests
    , fingerprintTests
    ]

-- MAGIC ---------------------------------------------------------------------

magicTests :: TestTree
magicTests =
  testGroup
    "container magic"
    [ testCase "magic spells CANOPY\\x01\\x02 on disk (little-endian bytes)" $
        let bytes = build (BB.word64LE HC.kCanopyContainerMagic)
         in BS.unpack bytes @?= [0x43, 0x41, 0x4E, 0x4F, 0x50, 0x59, 0x01, 0x02]
    , testCase "the first six magic bytes are the ASCII \"CANOPY\"" $
        let bytes = build (BB.word64LE HC.kCanopyContainerMagic)
         in BS.take 6 bytes @?= BSC.pack "CANOPY"
    , testCase "container magic cannot collide with the raw Hermes .hbc magic" $
        -- The host distinguishes a container (this magic) from a bare .hbc
        -- (the Hermes magic 0x1F1903C103BC1FC6) by reading the SAME 8 bytes.
        assertBool
          "the container magic must differ from the Hermes bytecode magic"
          (HC.kCanopyContainerMagic /= (0x1F1903C103BC1FC6 :: Word64))
    , testCase "the header is the documented fixed size (48 bytes, CMP-11)" $
        HC.kHeaderSize @?= 48
    , testCase "the compiler's pinned constants mirror the host" $ do
        -- These MUST track host/shared/cpp: CanopyAbi.h CANOPY_ABI_VERSION == 1,
        -- CanopyAbiGate.h kCanopyExpectedHermesBytecodeVersion == 96 +
        -- kCanopyExpectedRnVersion == "0.76.9". A drift here ships a container the
        -- host rejects, so it is pinned in a test.
        HC.kCanopyAbiVersion @?= 1
        HC.kCanopyEngineBytecodeVersion @?= 96
        -- CMP-11 bumped the container layout to v2 (new version fields).
        HC.kCanopyContainerVersion @?= 2
        -- the supported RN target pin is react-native 0.76.9
        HC.kCanopyRnTargetPin @?= HC.RnTarget 0 76 9
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
                -- CMP-11: the default wrap stamps the RN-target pin + the
                -- compiler-version default; both round-trip through the header.
                HC.chRnTargetVersion h @?= HC.packVersion HC.kCanopyRnTargetPin
                HC.chCompilerVersion h @?= HC.packVersion HC.kCanopyCompilerVersion
                HC.chRuntimeFingerprint h
                  @?= HC.runtimeFingerprint
                        enginePin
                        hostAbi
                        (HC.packVersion HC.kCanopyRnTargetPin)
                        (HC.packVersion HC.kCanopyCompilerVersion)
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
        -- a bare .hbc (opens with the Hermes magic) is NOT a container; pad to a
        -- full header length so the magic check (not the length check) fires
        let bareHbc = build (BB.word64LE 0x1F1903C103BC1FC6) <> BS.pack (replicate (HC.kHeaderSize - 8) 0)
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
        -- hand-build a v2 header (44 pre-CRC bytes) with payload kind 99 and a
        -- CRC over those bytes; the payload-kind check fires before the CRC, but
        -- a matching CRC proves the rejection is the kind, not a corrupt header.
        let preCrc =
              build
                ( BB.word64LE HC.kCanopyContainerMagic
                    <> BB.word32LE HC.kCanopyContainerVersion
                    <> BB.word32LE 99 -- bogus kind
                    <> BB.word32LE 0 -- bytecode
                    <> BB.word32LE hostAbi
                    <> BB.word32LE 0 -- rn target
                    <> BB.word32LE 0 -- compiler version
                    <> BB.word32LE 0 -- runtime fingerprint
                    <> BB.word32LE 0 -- payload length
                    <> BB.word32LE 0 -- reserved
                )
            crc = HC.crc32 preCrc
            full = preCrc <> build (BB.word32LE crc)
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
          -- host understands version 3, the bundle is the current (v2) layout
          HC.validate 3 enginePin hostAbi h
            @?= Left (HC.UnsupportedContainerVersion HC.kCanopyContainerVersion 3)
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
    , testCase "the --rn-target selector picks the version-matched hermesc path" $ do
        -- The matched hermesc is selected from the RN pin's toolchain dir
        -- (0.76.9), so --rn-target drives the binary, not a stray PATH hermesc.
        let cmd = HC.hermescForTarget "/opt/canopy/hermesc" HC.kCanopyRnTargetPin "b.js" "b.hbc"
        assertBool
          "hermesc path is under the selected RN target's toolchain dir"
          (take 1 cmd == ["/opt/canopy/hermesc/0.76.9/hermesc"])
        assertBool "-emit-binary still carried" ("-emit-binary" `elem` cmd)
        assertBool "the input JS is passed" ("b.js" `elem` cmd)
    ]

-- RN TARGET (CMP-11) --------------------------------------------------------

rnTargetTests :: TestTree
rnTargetTests =
  testGroup
    "rn target (CMP-11 --rn-target knob)"
    [ testCase "the supported --rn-target string resolves to the pin" $
        HC.rnTargetForString "0.76.9" @?= Just HC.kCanopyRnTargetPin
    , testCase "an unsupported --rn-target string is rejected (Nothing)" $ do
        HC.rnTargetForString "0.77.0" @?= Nothing
        HC.rnTargetForString "garbage" @?= Nothing
    , testCase "the pin maps to the engine bytecode version + a named shim set" $ do
        HC.rnTargetBytecodeVersion HC.kCanopyRnTargetPin @?= enginePin
        HC.rnTargetShimSet HC.kCanopyRnTargetPin @?= "hermes-rn-0.76"
    , testCase "packVersion / unpackVersion round-trip a semver" $ do
        HC.unpackVersion (HC.packVersion (HC.RnTarget 0 76 9)) @?= HC.RnTarget 0 76 9
        HC.unpackVersion (HC.packVersion (HC.RnTarget 1 2 3)) @?= HC.RnTarget 1 2 3
    , testCase "packVersion is monotonic in (major, minor, patch)" $ do
        assertBool "major dominates" (HC.packVersion (HC.RnTarget 1 0 0) > HC.packVersion (HC.RnTarget 0 999 999))
        assertBool "minor over patch" (HC.packVersion (HC.RnTarget 0 1 0) > HC.packVersion (HC.RnTarget 0 0 999))
    , testCase "wrapFor stamps the RN target + compiler version; both round-trip" $
        let container =
              build (HC.wrapFor HC.HbcBytecode enginePin hostAbi (HC.RnTarget 0 76 9) (HC.RnTarget 1 2 3) sampleHbc)
         in case HC.parseHeader container of
              Left e -> assertFailure (show e)
              Right h -> do
                HC.unpackVersion (HC.chRnTargetVersion h) @?= HC.RnTarget 0 76 9
                HC.unpackVersion (HC.chCompilerVersion h) @?= HC.RnTarget 1 2 3
    , testCase "a bundle built for a different RN target is rejected (RnTargetMismatch)" $
        -- A bundle compiled for a hypothetical 0.77.0 pin must not boot on the
        -- 0.76.9 host, even though bytecode/abi could coincide.
        let container =
              build (HC.wrapFor HC.HbcBytecode enginePin hostAbi (HC.RnTarget 0 77 0) HC.kCanopyCompilerVersion sampleHbc)
         in withHeaderOf container $ \h ->
              HC.validateAgainst HC.hostPins h
                @?= Left (HC.RnTargetMismatch (HC.packVersion (HC.RnTarget 0 77 0)) (HC.packVersion HC.kCanopyRnTargetPin))
    , testCase "a matching RN-target bundle passes validateAgainst hostPins" $
        let container = build (HC.wrapFor HC.HbcBytecode enginePin hostAbi HC.kCanopyRnTargetPin HC.kCanopyCompilerVersion sampleHbc)
         in withHeaderOf container $ \h ->
              HC.validateAgainst HC.hostPins h @?= Right ()
    ]

-- RUNTIME FINGERPRINT (CMP-11) ----------------------------------------------

fingerprintTests :: TestTree
fingerprintTests =
  testGroup
    "runtimeVersion fingerprint (CMP-11 OTA gate)"
    [ testCase "the fingerprint is the CRC over the four version fields, in order" $
        HC.runtimeFingerprint enginePin hostAbi 7 9
          @?= HC.crc32
                ( build
                    ( BB.word32LE enginePin
                        <> BB.word32LE hostAbi
                        <> BB.word32LE 7
                        <> BB.word32LE 9
                    )
                )
    , testCase "a change in ANY constituent changes the fingerprint" $ do
        let base = HC.runtimeFingerprint enginePin hostAbi 7 9
        assertBool "bytecode" (HC.runtimeFingerprint 95 hostAbi 7 9 /= base)
        assertBool "abi" (HC.runtimeFingerprint enginePin 2 7 9 /= base)
        assertBool "rn target" (HC.runtimeFingerprint enginePin hostAbi 8 9 /= base)
        assertBool "compiler" (HC.runtimeFingerprint enginePin hostAbi 7 10 /= base)
    , testCase "the stamped fingerprint matches a host recompute for a matching bundle" $
        let container = build (HC.wrapFor HC.HbcBytecode enginePin hostAbi HC.kCanopyRnTargetPin HC.kCanopyCompilerVersion sampleHbc)
         in withHeaderOf container $ \h ->
              HC.chRuntimeFingerprint h
                @?= HC.runtimeFingerprint
                      enginePin
                      hostAbi
                      (HC.packVersion HC.kCanopyRnTargetPin)
                      (HC.packVersion HC.kCanopyCompilerVersion)
    , testCase "a bundle from a different compiler version is caught (RuntimeFingerprintMismatch)" $
        -- Same RN target + ABI + bytecode, but a different compiler version: the
        -- field-level gates pass, so the fingerprint is the gate that fires.
        let container = build (HC.wrapFor HC.HbcBytecode enginePin hostAbi HC.kCanopyRnTargetPin (HC.RnTarget 9 9 9) sampleHbc)
         in withHeaderOf container $ \h ->
              case HC.validateAgainst HC.hostPins h of
                Left (HC.RuntimeFingerprintMismatch _ _) -> pure ()
                other -> assertFailure ("expected RuntimeFingerprintMismatch, got: " ++ show other)
    ]

-- HELPERS -------------------------------------------------------------------

-- | Parse a built container's header and hand it to a continuation, failing the
-- test if it does not parse.
withHeader :: BB.Builder -> (HC.ContainerHeader -> Assertion) -> Assertion
withHeader builder k =
  case HC.parseHeader (build builder) of
    Left e -> assertFailure ("expected the header to parse, got: " ++ show e)
    Right h -> k h

-- | 'withHeader' for already-materialized container bytes.
withHeaderOf :: BS.ByteString -> (HC.ContainerHeader -> Assertion) -> Assertion
withHeaderOf bytes k =
  case HC.parseHeader bytes of
    Left e -> assertFailure ("expected the header to parse, got: " ++ show e)
    Right h -> k h

-- | Flip the low bit of the byte at index @i@ (to corrupt a header field).
flipByteAt :: Int -> BS.ByteString -> BS.ByteString
flipByteAt i bs =
  let (before, rest) = BS.splitAt i bs
   in case BS.uncons rest of
        Nothing -> bs
        Just (b, tailBytes) -> before <> BS.singleton (b + 1) <> tailBytes
