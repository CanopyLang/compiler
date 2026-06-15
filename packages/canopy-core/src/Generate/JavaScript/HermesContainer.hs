{-# LANGUAGE OverloadedStrings #-}

-- | The versioned native bundle container (CMP-8): a fixed-layout header that
-- wraps the native payload — a Hermes @.hbc@ bytecode bundle in production, or
-- the plain JS source in the dev fallback — together with the three version
-- numbers the host validates before it will run a byte of it.
--
-- == Why a container at all
--
-- 'Generate.JavaScript.NativeBundle' (CMP-5) emits the booted IIFE + map. The
-- native host then either evaluates that JS directly (dev) or — once a
-- version-matched @hermesc@ has compiled it — a Hermes @.hbc@ bytecode bundle
-- for a fast cold start with no source in the APK (CMP-8). Either way the host
-- needs to know, BEFORE it hands the buffer to Hermes:
--
--   1. that this really is a Canopy native bundle (not a truncated download, a
--      web bundle staged by mistake, or random bytes) — a /magic/;
--   2. which CONTAINER format it is reading, so a future layout change is a
--      readable rejection rather than a misparse — a /container version/;
--   3. what the PAYLOAD is — @.hbc@ bytecode or JS source — so it routes the
--      bytes correctly and never tries to parse bytecode as text or vice versa
--      — a /payload kind/;
--   4. for an @.hbc@ payload, the Hermes BYTECODE version it was compiled for,
--      so a bundle built by a @hermesc@ whose HBC format differs from the linked
--      engine is rejected at load, not mis-executed mid-eval — a /bytecode
--      version/ (the same number 'CanopyAbiGate.h' already gates the raw @.hbc@
--      on); and
--   5. the Canopy extension ABI version (@CANOPY_ABI_VERSION@) the bundle was
--      built against, so a bundle compiled for ABI N never boots on a host
--      speaking ABI ≠ N — the OTA @runtimeVersion@ gate the master plan calls
--      for — an /ABI version/.
--
-- The host rejects on ANY mismatch (wrong magic, unknown container version,
-- payload kind it cannot run, bytecode version ≠ the linked engine, ABI version
-- ≠ the host's), fail-LOUD, BEFORE evaluation — the exact posture
-- 'host/shared/cpp/CanopyAbiGate.h' already takes for the raw @.hbc@ gate. The
-- container hoists those checks to a single self-describing header so the host
-- reads the three versions from fixed offsets instead of reverse-engineering
-- them from the payload (the ABI version, in particular, is NOT recoverable from
-- raw @.hbc@ bytes — it has to be carried).
--
-- == The seam (CMP-5 ratified)
--
-- /Compiler owns/ JS + map + boot hook + .hbc + THIS container. /Host owns/
-- manifest, assets, Fabric codegen, deploy, and the load-time VALIDATION of this
-- container (it reads the header and decides go/no-go). This module is the
-- compiler side: it DEFINES the wire format and BUILDS the header; it does not
-- itself run @hermesc@ (that is an external, version-matched toolchain step —
-- see 'hermescCommand' for the exact invocation the build wires) and it does not
-- validate (that is the host's job, mirrored here only for round-trip tests).
--
-- == Wire format (v1)
--
-- All multi-byte integers are little-endian (matching the Hermes file format and
-- the host's existing readers in 'CanopyAbiGate.h'). The header is a fixed 32
-- bytes, immediately followed by the payload:
--
-- @
--   offset  size  field
--   ------  ----  -----------------------------------------------------------
--      0     8    magic            = kCanopyContainerMagic (0x59_50_4F_4E_41_43 ⋯)
--      8     4    containerVersion = kCanopyContainerVersion (1)
--     12     4    payloadKind      = 0 (JS source) | 1 (HBC bytecode)
--     16     4    bytecodeVersion  = the HBC version the payload targets,
--                                    or 0 for a JS-source payload
--     20     4    abiVersion       = CANOPY_ABI_VERSION the bundle was built for
--     24     4    payloadLength    = byte length of the payload that follows
--     28     4    headerCrc        = CRC-32 of bytes [0,28) (header integrity)
--     32     …    payload          = the .hbc bytecode OR the JS source bytes
-- @
--
-- The magic spells @\"CANOPY\\x01\\x01\"@ read as little-endian bytes:
-- @C A N O P Y@ then two format bytes — chosen so a hexdump of a staged bundle
-- is human-recognizable, and so it can never collide with the raw Hermes magic
-- (which the host distinguishes by reading the SAME first 8 bytes — a real
-- @.hbc@ payload is the container's PAYLOAD, never its first bytes).
--
-- @since 0.20.10
module Generate.JavaScript.HermesContainer
  ( -- * The container format
    PayloadKind (..)
  , ContainerHeader (..)
  , kCanopyContainerMagic
  , kCanopyContainerVersion
  , kCanopyAbiVersion
  , kCanopyEngineBytecodeVersion
  , kHeaderSize

    -- * Building
  , wrap
  , wrapJsSource
  , wrapHbc
  , headerBuilder

    -- * Parsing (host-mirror, for round-trip tests)
  , ParseError (..)
  , parseHeader
  , parseContainer

    -- * Validation (host-mirror)
  , ValidationError (..)
  , validate

    -- * CRC-32
  , crc32

    -- * hermesc invocation (documented; not run here)
  , hermescCommand
  , hermescVersionProbe
  ) where

import Data.Bits (shiftL, shiftR, xor, (.&.), (.|.))
import qualified Data.ByteString as BS
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import Data.Word (Word32, Word64)

-- ── Constants ────────────────────────────────────────────────────────────────

-- | The 64-bit magic that opens every Canopy native container, little-endian on
-- disk. The low six bytes spell @C A N O P Y@ (0x43 0x41 0x4E 0x4F 0x50 0x59),
-- the high two are a format signature (0x01 0x01) — so a hexdump reads
-- @43 41 4E 4F 50 59 01 01@, i.e. @\"CANOPY\\x01\\x01\"@, instantly recognizable
-- and impossible to confuse with the raw Hermes magic
-- (@0x1F1903C103BC1FC6@) the host already knows.
--
-- The host reads these same 8 bytes (see the CMP-8 host gate) and routes:
-- a buffer that opens with THIS magic is a container; one that opens with the
-- Hermes magic is a bare @.hbc@ (the legacy RNV-7 path); anything else is
-- rejected.
kCanopyContainerMagic :: Word64
kCanopyContainerMagic = 0x010159504F4E4143

-- | The current container layout version. Bumped only on a breaking header
-- change; the host rejects a container whose 'chContainerVersion' it does not
-- understand, BEFORE touching the payload.
kCanopyContainerVersion :: Word32
kCanopyContainerVersion = 1

-- | The Canopy extension ABI version this compiler stamps into the container —
-- the build's declared @CANOPY_ABI_VERSION@. MUST track
-- @host/shared/cpp/CanopyAbi.h@'s @CANOPY_ABI_VERSION@ (currently 1); the host
-- rejects a container whose 'chAbiVersion' ≠ the host's, so these move in
-- lockstep on an ABI bump. Mirrored here so the compiler has a single source of
-- truth for the number it writes.
kCanopyAbiVersion :: Word32
kCanopyAbiVersion = 1

-- | The Hermes HBC bytecode version the engine pin speaks — the version a
-- version-matched @hermesc@ must target, stamped into an 'HbcBytecode'
-- container. MUST track @host/shared/cpp/CanopyAbiGate.h@'s
-- @kCanopyExpectedHermesBytecodeVersion@ (96, for the react-native 0.76.9 pin);
-- the host rejects an @.hbc@ container whose 'chBytecodeVersion' ≠ the live
-- engine. Mirrored here so a container the compiler builds for the dev fallback
-- still records the bytecode version the eventual @.hbc@ will carry.
kCanopyEngineBytecodeVersion :: Word32
kCanopyEngineBytecodeVersion = 96

-- | The fixed header size in bytes (see the wire-format table). The payload
-- begins immediately after.
kHeaderSize :: Int
kHeaderSize = 32

-- ── Types ────────────────────────────────────────────────────────────────────

-- | What the container's payload IS — the routing the host needs so it never
-- parses bytecode as text or vice versa.
data PayloadKind
  = -- | The payload is plain JS source (the dev fallback — no @hermesc@ in the
    -- build, or an intentional source build). The host evaluates it as text.
    JsSource
  | -- | The payload is a Hermes @.hbc@ bytecode bundle (production — a
    -- version-matched @hermesc@ compiled the JS). The host hands it to Hermes,
    -- which runs the bytecode directly (no parse) — the fast cold start.
    HbcBytecode
  deriving (Eq, Show)

-- | The numeric tag for a 'PayloadKind' as it travels in the header (offset 12).
payloadKindTag :: PayloadKind -> Word32
payloadKindTag JsSource = 0
payloadKindTag HbcBytecode = 1

-- | Decode a 'PayloadKind' tag; 'Nothing' for an unknown tag (a newer container
-- the host cannot run — rejected).
payloadKindFromTag :: Word32 -> Maybe PayloadKind
payloadKindFromTag 0 = Just JsSource
payloadKindFromTag 1 = Just HbcBytecode
payloadKindFromTag _ = Nothing

-- | The parsed container header — what the host reads from the first
-- 'kHeaderSize' bytes to decide go/no-go.
data ContainerHeader = ContainerHeader
  { chContainerVersion :: !Word32
  -- ^ the container layout version (gated against 'kCanopyContainerVersion')
  , chPayloadKind :: !PayloadKind
  -- ^ JS source or HBC bytecode — how to route the payload
  , chBytecodeVersion :: !Word32
  -- ^ the HBC version an 'HbcBytecode' payload targets (0 for 'JsSource')
  , chAbiVersion :: !Word32
  -- ^ the @CANOPY_ABI_VERSION@ the bundle was built against
  , chPayloadLength :: !Word32
  -- ^ the byte length of the payload that follows the header
  , chHeaderCrc :: !Word32
  -- ^ CRC-32 of the first 28 header bytes (everything before this field)
  } deriving (Eq, Show)

-- ── Building ─────────────────────────────────────────────────────────────────

-- | Wrap a native payload in a versioned container.
--
-- This is the compiler's CMP-8 entry point: given the payload bytes (an @.hbc@
-- from @hermesc@, or the JS source for the dev fallback), the payload kind, the
-- Hermes bytecode version it targets (ignored for 'JsSource' — stamped 0), and
-- the Canopy ABI version, it produces the self-describing container the host
-- validates. The header's CRC is computed over the other 28 header bytes so a
-- truncated or corrupted header is caught before the payload is trusted.
wrap
  :: PayloadKind
  -- ^ JS source (dev fallback) or HBC bytecode (prod)
  -> Word32
  -- ^ the HBC bytecode version (the engine pin); ignored for 'JsSource'
  -> Word32
  -- ^ the Canopy ABI version (@CANOPY_ABI_VERSION@) the bundle was built for
  -> BS.ByteString
  -- ^ the payload bytes
  -> Builder
wrap kind bytecodeVersion abiVersion payload =
  headerBuilder header <> BB.byteString payload
  where
    effectiveBytecode =
      case kind of
        JsSource -> 0 -- a source payload targets no specific bytecode version
        HbcBytecode -> bytecodeVersion
    header =
      ContainerHeader
        { chContainerVersion = kCanopyContainerVersion
        , chPayloadKind = kind
        , chBytecodeVersion = effectiveBytecode
        , chAbiVersion = abiVersion
        , chPayloadLength = fromIntegral (BS.length payload)
        , chHeaderCrc = headerCrcFor effectiveBytecode kind abiVersion (BS.length payload)
        }

-- | Wrap the JS-source dev fallback (no @hermesc@): payload kind 'JsSource',
-- bytecode version 0. The host evaluates the payload as text — the same JS the
-- web path produces, plus the CMP-5 boot trailer.
wrapJsSource :: Word32 -> BL.ByteString -> Builder
wrapJsSource abiVersion js =
  wrap JsSource 0 abiVersion (BL.toStrict js)

-- | Wrap a Hermes @.hbc@ bytecode payload (production): payload kind
-- 'HbcBytecode', stamping the bytecode version @hermesc@ targeted. The caller
-- supplies the version it drove @hermesc@ with (it must equal the engine pin —
-- the host gates exactly this); we do not re-read it from the @.hbc@ here, so
-- the stamp is the build's declared intent, cross-checked by the host against
-- both the raw @.hbc@ header AND the live engine.
wrapHbc :: Word32 -> Word32 -> BS.ByteString -> Builder
wrapHbc = wrap HbcBytecode

-- | Serialize a 'ContainerHeader' to its fixed 'kHeaderSize'-byte little-endian
-- form. Used by 'wrap' and exposed for golden tests.
headerBuilder :: ContainerHeader -> Builder
headerBuilder h =
  le64 kCanopyContainerMagic
    <> le32 (chContainerVersion h)
    <> le32 (payloadKindTag (chPayloadKind h))
    <> le32 (chBytecodeVersion h)
    <> le32 (chAbiVersion h)
    <> le32 (chPayloadLength h)
    <> le32 (chHeaderCrc h)

-- | CRC-32 over the 28 header bytes that precede the CRC field, for a header
-- with the given fields. Factored out so 'wrap' and 'parseHeader' compute the
-- SAME pre-image (magic + version + kind + bytecode + abi + length).
headerCrcFor :: Word32 -> PayloadKind -> Word32 -> Int -> Word32
headerCrcFor bytecodeVersion kind abiVersion payloadLen =
  crc32 . BL.toStrict . BB.toLazyByteString $
    le64 kCanopyContainerMagic
      <> le32 kCanopyContainerVersion
      <> le32 (payloadKindTag kind)
      <> le32 bytecodeVersion
      <> le32 abiVersion
      <> le32 (fromIntegral payloadLen)

-- ── Parsing (host-mirror) ────────────────────────────────────────────────────

-- | Why a container failed to PARSE (structural — distinct from a successful
-- parse that then fails 'validate'). The host produces the analogous rejection.
data ParseError
  = -- | Fewer than 'kHeaderSize' bytes — a truncated download / staging error.
    TooShort Int
  | -- | The first 8 bytes are not 'kCanopyContainerMagic' — not a Canopy
    -- container (maybe a bare @.hbc@, a web bundle, or garbage).
    BadMagic Word64
  | -- | The payload-kind tag (offset 12) is one the reader does not know.
    UnknownPayloadKind Word32
  | -- | The stored 'chHeaderCrc' does not match a recomputation — a corrupted
    -- header. Carries (stored, computed).
    HeaderCrcMismatch Word32 Word32
  | -- | The header's 'chPayloadLength' does not match the bytes that follow.
    -- Carries (declared, actual).
    PayloadLengthMismatch Word32 Int
  deriving (Eq, Show)

-- | Parse just the header from the first 'kHeaderSize' bytes, validating the
-- magic, the payload-kind tag, and the header CRC. Does NOT look at the payload
-- length vs. the actual payload (that is 'parseContainer'). This is the host's
-- first read — enough to know what it is holding.
parseHeader :: BS.ByteString -> Either ParseError ContainerHeader
parseHeader bs
  | BS.length bs < kHeaderSize = Left (TooShort (BS.length bs))
  | magic /= kCanopyContainerMagic = Left (BadMagic magic)
  | otherwise =
      case payloadKindFromTag kindTag of
        Nothing -> Left (UnknownPayloadKind kindTag)
        Just kind ->
          let computedCrc =
                headerCrcFor bytecodeVersion kind abiVersion (fromIntegral payloadLen)
           in if storedCrc /= computedCrc
                then Left (HeaderCrcMismatch storedCrc computedCrc)
                else
                  Right
                    ContainerHeader
                      { chContainerVersion = containerVersion
                      , chPayloadKind = kind
                      , chBytecodeVersion = bytecodeVersion
                      , chAbiVersion = abiVersion
                      , chPayloadLength = payloadLen
                      , chHeaderCrc = storedCrc
                      }
  where
    magic = readLe64 bs 0
    containerVersion = readLe32 bs 8
    kindTag = readLe32 bs 12
    bytecodeVersion = readLe32 bs 16
    abiVersion = readLe32 bs 20
    payloadLen = readLe32 bs 24
    storedCrc = readLe32 bs 28

-- | Parse a full container — header plus the payload it frames — checking that
-- the declared 'chPayloadLength' matches the actual trailing bytes. Returns the
-- header and the payload slice. The host uses this to slice the @.hbc@/JS it
-- then routes to Hermes.
parseContainer :: BS.ByteString -> Either ParseError (ContainerHeader, BS.ByteString)
parseContainer bs = do
  header <- parseHeader bs
  let payload = BS.drop kHeaderSize bs
      actualLen = BS.length payload
      declaredLen = fromIntegral (chPayloadLength header)
  if actualLen /= declaredLen
    then Left (PayloadLengthMismatch (chPayloadLength header) actualLen)
    else Right (header, payload)

-- ── Validation (host-mirror) ─────────────────────────────────────────────────

-- | Why a well-formed container is REJECTED at the host's load gate — the
-- version contract, distinct from the structural 'ParseError'. The host fails
-- LOUD on any of these BEFORE evaluation.
data ValidationError
  = -- | The container layout version is one the host does not understand.
    -- Carries (seen, expected).
    UnsupportedContainerVersion Word32 Word32
  | -- | An 'HbcBytecode' payload was compiled for a bytecode version the linked
    -- engine does not speak. Carries (bundle, engine).
    BytecodeVersionMismatch Word32 Word32
  | -- | The bundle was built for a Canopy ABI the host does not speak.
    -- Carries (bundle, host).
    AbiVersionMismatch Word32 Word32
  deriving (Eq, Show)

-- | Validate a parsed header against the host's own pins — the container
-- version it understands, the engine's bytecode version, and the host's ABI
-- version. Mirrors the host's go/no-go so a round-trip test can prove the
-- compiler emits exactly what the host accepts.
--
-- A 'JsSource' payload's bytecode version is NOT gated (it is 0 and the engine
-- parses source regardless — the dev fallback always loads); an 'HbcBytecode'
-- payload's bytecode version MUST equal the engine's. The ABI version is gated
-- for both kinds.
validate
  :: Word32
  -- ^ the container version the host understands ('kCanopyContainerVersion')
  -> Word32
  -- ^ the bytecode version the linked engine speaks
  -> Word32
  -- ^ the ABI version the host speaks
  -> ContainerHeader
  -> Either ValidationError ()
validate hostContainerVersion engineBytecodeVersion hostAbiVersion h
  | chContainerVersion h /= hostContainerVersion =
      Left (UnsupportedContainerVersion (chContainerVersion h) hostContainerVersion)
  | chAbiVersion h /= hostAbiVersion =
      Left (AbiVersionMismatch (chAbiVersion h) hostAbiVersion)
  | chPayloadKind h == HbcBytecode && chBytecodeVersion h /= engineBytecodeVersion =
      Left (BytecodeVersionMismatch (chBytecodeVersion h) engineBytecodeVersion)
  | otherwise = Right ()

-- ── hermesc invocation (documented; not run here) ────────────────────────────

-- | The exact @hermesc@ command line the native build wires to compile the
-- CMP-5 JS bundle into the @.hbc@ payload — DOCUMENTED here so the one wire is
-- in the compiler tree next to the container it feeds, even though this Linux
-- box has no @hermesc@ to run it for real.
--
-- @hermesc@ MUST be the one whose HBC format matches the linked engine pin
-- (react-native 0.76.9 → bytecode version 96; see 'CanopyAbiGate.h'). The flags:
--
--   * @-emit-binary@ — emit @.hbc@ bytecode, not disassembly;
--   * @-out <out.hbc>@ — the bytecode output the build then 'wrapHbc's;
--   * @-O@ — optimize (production);
--   * @-output-source-map@ — emit the bytecode→source map alongside (the CMP-8
--     "bytecode map" — line/col of the GENERATED JS the @.hbc@ came from, which
--     composes with the CMP-5 JS→.can map to symbolicate a device frame all the
--     way to a @.can@ line);
--   * the input is the assembled CMP-5 JS bundle.
--
-- Given the input JS path and the desired @.hbc@ output path, this returns the
-- argv the build runs (@hermesc@ at the front). The build then reads the @.hbc@
-- bytes back, confirms the Hermes magic + the expected bytecode version (the raw
-- @.hbc@ readers the host shares), and hands them to 'wrapHbc'.
hermescCommand
  :: FilePath
  -- ^ the @hermesc@ binary (version-matched to the engine pin)
  -> FilePath
  -- ^ the assembled CMP-5 JS bundle to compile
  -> FilePath
  -- ^ the @.hbc@ output to write
  -> [String]
hermescCommand hermesc inputJs outputHbc =
  [ hermesc
  , "-emit-binary"
  , "-O"
  , "-output-source-map"
  , "-out"
  , outputHbc
  , inputJs
  ]

-- | The @hermesc@ probe the build runs FIRST to confirm the toolchain is the
-- version-matched one before trusting its output: @hermesc --version@. The build
-- asserts the reported Hermes version corresponds to the engine pin's bytecode
-- version (96 for the 0.76.9 pin); a mismatch means the @.hbc@ would be rejected
-- at load, so the build fails early with a readable error rather than shipping a
-- bundle the host will reject on device.
hermescVersionProbe :: FilePath -> [String]
hermescVersionProbe hermesc = [hermesc, "--version"]

-- ── Little-endian serialization ──────────────────────────────────────────────

-- | A little-endian 'Word64' builder (8 bytes).
le64 :: Word64 -> Builder
le64 = BB.word64LE

-- | A little-endian 'Word32' builder (4 bytes).
le32 :: Word32 -> Builder
le32 = BB.word32LE

-- | Read a little-endian 'Word64' at byte @off@ (caller guarantees the bytes
-- exist): byte @off@ is the least significant.
readLe64 :: BS.ByteString -> Int -> Word64
readLe64 bs off =
  foldr step 0 [0 .. 7]
  where
    step i acc = (acc `shiftL` 8) .|. fromIntegral (BS.index bs (off + i))

-- | Read a little-endian 'Word32' at byte @off@ (caller guarantees the bytes
-- exist): byte @off@ is the least significant.
readLe32 :: BS.ByteString -> Int -> Word32
readLe32 bs off =
  foldr step 0 [0 .. 3]
  where
    step i acc = (acc `shiftL` 8) .|. fromIntegral (BS.index bs (off + i))

-- ── CRC-32 (IEEE 802.3, the zlib/PNG polynomial) ─────────────────────────────

-- | CRC-32 of a 'BS.ByteString' using the standard IEEE reflected polynomial
-- (0xEDB88320), initial value 0xFFFFFFFF, final XOR 0xFFFFFFFF — the same CRC-32
-- zlib/PNG use. Small + dependency-free so the host can re-implement the
-- identical check from these bytes. Used for the header-integrity field so a
-- corrupted/truncated header is caught structurally, before the version gates.
crc32 :: BS.ByteString -> Word32
crc32 = (`xor` 0xFFFFFFFF) . BS.foldl' step 0xFFFFFFFF
  where
    step crc byte =
      let idx = fromIntegral ((crc `xor` fromIntegral byte) .&. 0xFF)
       in (crc `shiftR` 8) `xor` crcTable idx

-- | One entry of the CRC-32 lookup table, computed on demand (no top-level
-- 'Data.Array' dependency; the table is 256 small folds, negligible next to a
-- bundle compile).
crcTable :: Int -> Word32
crcTable n = go 8 (fromIntegral n)
  where
    go :: Int -> Word32 -> Word32
    go 0 c = c
    go k c =
      let c' = if c .&. 1 /= 0 then 0xEDB88320 `xor` (c `shiftR` 1) else c `shiftR` 1
       in go (k - 1) c'
