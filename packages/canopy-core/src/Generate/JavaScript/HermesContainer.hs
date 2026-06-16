{-# LANGUAGE OverloadedStrings #-}

-- | The versioned native bundle container (CMP-8, extended by CMP-11): a
-- fixed-layout header that wraps the native payload — a Hermes @.hbc@ bytecode
-- bundle in production, or the plain JS source in the dev fallback — together
-- with the version numbers the host validates before it will run a byte of it.
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
--      on);
--   5. the Canopy extension ABI version (@CANOPY_ABI_VERSION@) the bundle was
--      built against, so a bundle compiled for ABI N never boots on a host
--      speaking ABI ≠ N — the OTA @runtimeVersion@ gate the master plan calls
--      for — an /ABI version/;
--   6. (CMP-11) the react-native / Hermes TARGET the bundle was compiled for
--      (the @--rn-target=0.76.9@ knob), which selects the matched @hermesc@ +
--      Hermes-shim set — so a bundle built for one RN pin never boots on a host
--      linked against another, even if the bytecode version happened to coincide
--      — an /RN-target fingerprint/;
--   7. (CMP-11) the Canopy COMPILER version that built the bundle, carried for
--      provenance + a forward-compatibility floor (a host may refuse a bundle
--      from a compiler newer than it knows how to host) — a /compiler version/;
--      and
--   8. (CMP-11) a single /runtimeVersion fingerprint/ that folds (ABI version,
--      bytecode version, RN target, compiler version) into one 32-bit number, so
--      the host's OTA gate is a SINGLE integer comparison — the
--      @runtimeVersion@ an OTA bundle manifest binds to (see @CanopyAbi.h@), made
--      machine-checkable. Any drift in any of the four constituents changes the
--      fingerprint, so an incompatible runtime is one loud comparison away
--      instead of four separate ones that could each be forgotten.
--
-- The host rejects on ANY mismatch (wrong magic, unknown container version,
-- payload kind it cannot run, bytecode version ≠ the linked engine, ABI version
-- ≠ the host's, RN target ≠ the host's pin, or — the umbrella check —
-- runtimeVersion fingerprint ≠ the host's own), fail-LOUD, BEFORE evaluation —
-- the exact posture 'host/shared/cpp/CanopyAbiGate.h' already takes for the raw
-- @.hbc@ gate. The container hoists those checks to a single self-describing
-- header so the host reads the versions from fixed offsets instead of
-- reverse-engineering them from the payload (the ABI version, the RN target, and
-- the compiler version, in particular, are NOT recoverable from raw @.hbc@ bytes
-- — they have to be carried).
--
-- == The seam (CMP-5 ratified)
--
-- /Compiler owns/ JS + map + boot hook + .hbc + THIS container. /Host owns/
-- manifest, assets, Fabric codegen, deploy, and the load-time VALIDATION of this
-- container (it reads the header and decides go/no-go). This module is the
-- compiler side: it DEFINES the wire format and BUILDS the header; it does not
-- itself run @hermesc@ (that is an external, version-matched toolchain step —
-- see 'hermescCommand' for the exact invocation the build wires, now selected by
-- the @--rn-target@ pin) and it does not validate (that is the host's job,
-- mirrored here only for round-trip tests).
--
-- == Wire format (v2 — CMP-11)
--
-- All multi-byte integers are little-endian (matching the Hermes file format and
-- the host's existing readers in 'CanopyAbiGate.h'). The header is a fixed 48
-- bytes, immediately followed by the payload:
--
-- @
--   offset  size  field
--   ------  ----  -----------------------------------------------------------
--      0     8    magic              = kCanopyContainerMagic ("CANOPY\\x01\\x02")
--      8     4    containerVersion   = kCanopyContainerVersion (2)
--     12     4    payloadKind        = 0 (JS source) | 1 (HBC bytecode)
--     16     4    bytecodeVersion    = the HBC version the payload targets,
--                                      or 0 for a JS-source payload
--     20     4    abiVersion         = CANOPY_ABI_VERSION the bundle was built for
--     24     4    rnTargetVersion    = the --rn-target pin, packed (CMP-11):
--                                      major<<20 | minor<<10 | patch
--     28     4    compilerVersion    = the canopy compiler version, packed the
--                                      same way (CMP-11)
--     32     4    runtimeFingerprint = the single OTA runtimeVersion gate number,
--                                      a CRC-32 over the four version fields above
--                                      (CMP-11)
--     36     4    payloadLength      = byte length of the payload that follows
--     40     4    reserved           = 0 (kept for a future field without a v-bump)
--     44     4    headerCrc          = CRC-32 of bytes [0,44) (header integrity)
--     48     …    payload            = the .hbc bytecode OR the JS source bytes
-- @
--
-- The magic spells @\"CANOPY\\x01\\x02\"@ read as little-endian bytes: @C A N O
-- P Y@ then two format bytes (@0x01 0x02@ — the @0x02@ tracks the v2 layout) —
-- chosen so a hexdump of a staged bundle is human-recognizable, and so it can
-- never collide with the raw Hermes magic (which the host distinguishes by
-- reading the SAME first 8 bytes — a real @.hbc@ payload is the container's
-- PAYLOAD, never its first bytes).
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

    -- * RN target + version stamps (CMP-11)
  , RnTarget (..)
  , kCanopyRnTargetPin
  , kCanopyCompilerVersion
  , rnTargetForString
  , rnTargetBytecodeVersion
  , rnTargetShimSet
  , packVersion
  , unpackVersion
  , runtimeFingerprint

    -- * Building
  , wrap
  , wrapJsSource
  , wrapHbc
  , wrapFor
  , headerBuilder

    -- * Parsing (host-mirror, for round-trip tests)
  , ParseError (..)
  , parseHeader
  , parseContainer

    -- * Validation (host-mirror)
  , ValidationError (..)
  , HostPins (..)
  , hostPins
  , validate
  , validateAgainst

    -- * CRC-32
  , crc32

    -- * hermesc invocation (documented; not run here)
  , hermescCommand
  , hermescVersionProbe
  , hermescForTarget
  ) where

import qualified Canopy.Version as Version
import Data.Bits (shiftL, shiftR, xor, (.&.), (.|.))
import qualified Data.ByteString as BS
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import Data.List (intercalate)
import Data.Word (Word32, Word64)

-- ── Constants ────────────────────────────────────────────────────────────────

-- | The 64-bit magic that opens every Canopy native container, little-endian on
-- disk. The low six bytes spell @C A N O P Y@ (0x43 0x41 0x4E 0x4F 0x50 0x59),
-- the high two are a format signature (0x01 0x02) — so a hexdump reads
-- @43 41 4E 4F 50 59 01 02@, i.e. @\"CANOPY\\x01\\x02\"@, instantly recognizable
-- and impossible to confuse with the raw Hermes magic
-- (@0x1F1903C103BC1FC6@) the host already knows. The trailing @0x02@ tracks the
-- v2 (CMP-11) layout — a hexdump alone tells which container generation it is.
--
-- The host reads these same 8 bytes (see the CMP-8 host gate) and routes:
-- a buffer that opens with THIS magic is a container; one that opens with the
-- Hermes magic is a bare @.hbc@ (the legacy RNV-7 path); anything else is
-- rejected.
kCanopyContainerMagic :: Word64
kCanopyContainerMagic = 0x020159504F4E4143

-- | The current container layout version. Bumped only on a breaking header
-- change; the host rejects a container whose 'chContainerVersion' it does not
-- understand, BEFORE touching the payload. CMP-11 bumped this from 1 to 2 (the
-- header grew the RN-target, compiler-version, and runtimeVersion-fingerprint
-- fields), so a host that only speaks v1 cleanly rejects a v2 bundle rather than
-- misreading its longer header.
kCanopyContainerVersion :: Word32
kCanopyContainerVersion = 2

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
-- begins immediately after. CMP-11 grew this from 32 to 48 (three new u32
-- version fields + a reserved word).
kHeaderSize :: Int
kHeaderSize = 48

-- ── RN target + version stamps (CMP-11) ──────────────────────────────────────

-- | A react-native / Hermes deployment target — the @--rn-target@ knob the build
-- selects (CMP-11). It pins, together: the @hermesc@ whose HBC format the
-- @.hbc@ is compiled for, the Hermes-shim set spliced into the JS bundle, and
-- the bytecode version the host's engine must speak. Carried in the container so
-- a bundle built for one RN pin is rejected on a host linked against another —
-- even if the raw bytecode version coincided, the shim set could differ.
--
-- It is held as the three semver components so it packs losslessly into the
-- header's 32-bit 'chRnTargetVersion' field (each component < 1024).
data RnTarget = RnTarget
  { rtMajor :: !Word32
  , rtMinor :: !Word32
  , rtPatch :: !Word32
  } deriving (Eq, Ord, Show)

-- | The supported RN target pin: react-native @0.76.9@ — the one the host
-- vendors (@host/vendor.lock.json@) and gates on
-- (@CanopyAbiGate.h@'s @kCanopyExpectedRnVersion@). The build defaults
-- @--rn-target@ to this; the host rejects a container whose 'chRnTargetVersion'
-- ≠ this pin. Moving the pin (an RN upgrade) is the "single declared knob" the
-- CMP-11 plan calls for: bump THIS (and the engine bytecode version + the host
-- constants) in lockstep.
kCanopyRnTargetPin :: RnTarget
kCanopyRnTargetPin = RnTarget 0 76 9

-- | The Canopy compiler version stamped into the container — THE single source
-- of truth, derived from 'Canopy.Version.compiler' (so it tracks the cabal
-- version automatically and never drifts from what the build actually is). Both
-- the build's stamp (via 'wrapFor') and the host-mirror gate default
-- ('hostPins') use this, so a bundle the compiler builds carries the same
-- compiler version the gate expects, and the runtimeVersion fingerprint matches
-- on a same-version host. Carried for provenance and as a fingerprint
-- constituent — a host MAY additionally refuse a compiler version it predates.
kCanopyCompilerVersion :: RnTarget
kCanopyCompilerVersion =
  let Version.Version major minor patch = Version.compiler
   in RnTarget (fromIntegral major) (fromIntegral minor) (fromIntegral patch)

-- | Resolve an @--rn-target@ string (e.g. @"0.76.9"@) to a 'RnTarget'. Only the
-- supported pins are accepted; an unknown target is 'Nothing', which the build
-- surfaces as a readable error rather than silently producing a bundle no host
-- can run. (Today there is exactly one supported pin; the function is written so
-- adding a second is a single list entry.)
rnTargetForString :: String -> Maybe RnTarget
rnTargetForString s = lookup s supportedRnTargets

-- | The supported @--rn-target@ strings and the 'RnTarget' each selects. The
-- single source of truth for which RN pins the build accepts.
supportedRnTargets :: [(String, RnTarget)]
supportedRnTargets =
  [ ("0.76.9", kCanopyRnTargetPin)
  ]

-- | The Hermes HBC bytecode version a given RN target's @hermesc@ emits — the
-- number the @.hbc@ carries and the host's engine must speak. For the supported
-- @0.76.9@ pin this is 96 ('kCanopyEngineBytecodeVersion'); the mapping is
-- explicit so an added RN target declares its bytecode version next to its pin.
rnTargetBytecodeVersion :: RnTarget -> Word32
rnTargetBytecodeVersion t
  | t == kCanopyRnTargetPin = kCanopyEngineBytecodeVersion
  | otherwise = 0

-- | The Hermes-shim set identifier the JS bundle must splice for a given RN
-- target — the @--rn-target@ "shim set" the CMP-11 plan names. The shim set is
-- the collection of @window@/@document@/timer/@globalThis@ polyfills the bundle
-- needs on the BARE Hermes that RN pin links (CMP-10/CMP-8b). It is a stable
-- string (here, @"hermes-rn-0.76"@) so the build and the host can name the same
-- set; a future RN pin whose Hermes needs a different polyfill set gets a new
-- identifier, and a bundle carrying the wrong one is caught by the RN-target
-- gate (which moves in lockstep with the shim set).
rnTargetShimSet :: RnTarget -> String
rnTargetShimSet t
  | t == kCanopyRnTargetPin = "hermes-rn-0.76"
  | otherwise = "hermes-rn-unknown"

-- | Pack a 'RnTarget' / compiler version into the 32-bit field the header
-- carries: @major \<\< 20 | minor \<\< 10 | patch@. Each component must be < 1024
-- (10 bits) — true for every plausible RN / Canopy version; a component that
-- overflows is masked to its low 10 bits (the build never produces one, and the
-- mask keeps the function total). The packing is monotonic in (major, minor,
-- patch) so a host can compare packed values directly for a
-- "compiler at least X" floor.
packVersion :: RnTarget -> Word32
packVersion (RnTarget major minor patch) =
  ((major .&. 0x3FF) `shiftL` 20)
    .|. ((minor .&. 0x3FF) `shiftL` 10)
    .|. (patch .&. 0x3FF)

-- | Inverse of 'packVersion' — recover (major, minor, patch) from the packed
-- 32-bit field. Used by 'parseHeader' and the round-trip tests.
unpackVersion :: Word32 -> RnTarget
unpackVersion w =
  RnTarget
    ((w `shiftR` 20) .&. 0x3FF)
    ((w `shiftR` 10) .&. 0x3FF)
    (w .&. 0x3FF)

-- | The single OTA @runtimeVersion@ fingerprint (CMP-11): a CRC-32 over the four
-- version fields that together define runtime compatibility — payload kind's
-- effective bytecode version, ABI version, RN target, and compiler version — in
-- a FIXED order. The host computes the SAME fingerprint from its own pins and
-- rejects a container whose 'chRuntimeFingerprint' differs, so an incompatible
-- runtime is ONE integer comparison rather than four. Any drift in any
-- constituent changes the fingerprint by construction (CRC-32 is sensitive to
-- every input byte), so no compatibility-relevant change can slip past the gate.
--
-- It is a fingerprint, not a counter: it does not order older/newer, it only
-- answers "same runtime contract or not". The constituent fields remain in the
-- header for a precise, field-level rejection MESSAGE (which axis mismatched);
-- the fingerprint is the fast umbrella check.
runtimeFingerprint
  :: Word32  -- ^ effective bytecode version (0 for a JS-source payload)
  -> Word32  -- ^ ABI version
  -> Word32  -- ^ packed RN target
  -> Word32  -- ^ packed compiler version
  -> Word32
runtimeFingerprint bytecode abiVersion rnTarget compilerVersion =
  crc32 . BL.toStrict . BB.toLazyByteString $
    le32 bytecode <> le32 abiVersion <> le32 rnTarget <> le32 compilerVersion

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
  , chRnTargetVersion :: !Word32
  -- ^ the packed @--rn-target@ pin the bundle was compiled for (CMP-11)
  , chCompilerVersion :: !Word32
  -- ^ the packed Canopy compiler version that built the bundle (CMP-11)
  , chRuntimeFingerprint :: !Word32
  -- ^ the single OTA @runtimeVersion@ fingerprint over the four fields (CMP-11)
  , chPayloadLength :: !Word32
  -- ^ the byte length of the payload that follows the header
  , chHeaderCrc :: !Word32
  -- ^ CRC-32 of the first 44 header bytes (everything before this field)
  } deriving (Eq, Show)

-- ── Building ─────────────────────────────────────────────────────────────────

-- | Wrap a native payload in a versioned container, with the full CMP-11 version
-- stamp threaded explicitly.
--
-- This is the compiler's CMP-8/CMP-11 entry point: given the payload bytes (an
-- @.hbc@ from @hermesc@, or the JS source for the dev fallback), the payload
-- kind, the Hermes bytecode version it targets (ignored for 'JsSource' — stamped
-- 0), the Canopy ABI version, the @--rn-target@ pin, and the compiler version,
-- it produces the self-describing container the host validates. The
-- runtimeVersion fingerprint is computed from those four version fields. The
-- header's CRC is computed over the other 44 header bytes so a truncated or
-- corrupted header is caught before the payload is trusted.
--
-- 'wrap', 'wrapJsSource', and 'wrapHbc' delegate here with the default pin +
-- compiler version for the back-compatible call sites; the production build
-- threads the real values through 'wrapFor'.
wrapFor
  :: PayloadKind
  -- ^ JS source (dev fallback) or HBC bytecode (prod)
  -> Word32
  -- ^ the HBC bytecode version (the engine pin); ignored for 'JsSource'
  -> Word32
  -- ^ the Canopy ABI version (@CANOPY_ABI_VERSION@) the bundle was built for
  -> RnTarget
  -- ^ the @--rn-target@ pin the bundle was compiled for (CMP-11)
  -> RnTarget
  -- ^ the Canopy compiler version that built the bundle (CMP-11)
  -> BS.ByteString
  -- ^ the payload bytes
  -> Builder
wrapFor kind bytecodeVersion abiVersion rnTarget compilerVersion payload =
  headerBuilder header <> BB.byteString payload
  where
    effectiveBytecode =
      case kind of
        JsSource -> 0 -- a source payload targets no specific bytecode version
        HbcBytecode -> bytecodeVersion
    packedRn = packVersion rnTarget
    packedCompiler = packVersion compilerVersion
    -- The header with a placeholder CRC; we serialize its pre-CRC bytes and CRC
    -- THOSE literal bytes, so the stored CRC is over exactly what lands on disk.
    headerNoCrc =
      ContainerHeader
        { chContainerVersion = kCanopyContainerVersion
        , chPayloadKind = kind
        , chBytecodeVersion = effectiveBytecode
        , chAbiVersion = abiVersion
        , chRnTargetVersion = packedRn
        , chCompilerVersion = packedCompiler
        , chRuntimeFingerprint =
            runtimeFingerprint effectiveBytecode abiVersion packedRn packedCompiler
        , chPayloadLength = fromIntegral (BS.length payload)
        , chHeaderCrc = 0 -- filled in below
        }
    header = headerNoCrc {chHeaderCrc = crc32 (headerPreCrcBytes headerNoCrc)}

-- | Wrap a native payload in a versioned container, defaulting the CMP-11
-- @--rn-target@ pin and compiler version to the build's own constants
-- ('kCanopyRnTargetPin', 'kCanopyCompilerVersion').
--
-- Kept as the CMP-8 entry point so existing call sites (and tests) that only
-- care about the kind / bytecode / ABI triple need not name the new fields; the
-- production build that wants the LIVE compiler version uses 'wrapFor'.
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
wrap kind bytecodeVersion abiVersion =
  wrapFor kind bytecodeVersion abiVersion kCanopyRnTargetPin kCanopyCompilerVersion

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
-- form. Used by 'wrapFor' and exposed for golden tests.
headerBuilder :: ContainerHeader -> Builder
headerBuilder h = headerPreCrc h <> le32 (chHeaderCrc h)

-- | Serialize the 44 header bytes that precede the CRC field — magic, the
-- version block, payload length, and the reserved word. The header CRC is taken
-- over EXACTLY these bytes (both on write, in 'wrapFor', and on read, in
-- 'parseHeader', which CRCs the literal on-disk @'BS.take' 44@). Taking the CRC
-- over the literal bytes — rather than re-deriving any field — is what makes the
-- CRC catch a single flipped byte: the 'chRuntimeFingerprint' is a function of
-- other fields, so re-deriving it during the check would let a flip in (say) the
-- ABI field be masked by the matching fingerprint change (CRC-32 is linear, so
-- the two changes can cancel). Hashing the raw bytes closes that.
headerPreCrc :: ContainerHeader -> Builder
headerPreCrc h =
  le64 kCanopyContainerMagic
    <> le32 (chContainerVersion h)
    <> le32 (payloadKindTag (chPayloadKind h))
    <> le32 (chBytecodeVersion h)
    <> le32 (chAbiVersion h)
    <> le32 (chRnTargetVersion h)
    <> le32 (chCompilerVersion h)
    <> le32 (chRuntimeFingerprint h)
    <> le32 (chPayloadLength h)
    <> le32 0 -- reserved

-- | The strict bytes of 'headerPreCrc' — the CRC pre-image.
headerPreCrcBytes :: ContainerHeader -> BS.ByteString
headerPreCrcBytes = BL.toStrict . BB.toLazyByteString . headerPreCrc

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
          -- The CRC is recomputed over the LITERAL on-disk pre-CRC bytes
          -- ([0,44)), not over a re-derivation of the fields, so a single flipped
          -- byte anywhere in the header is always caught (re-deriving the
          -- fingerprint would let an ABI flip be masked by the matching
          -- fingerprint change — CRC-32 is linear).
          let computedCrc = crc32 (BS.take 44 bs)
           in if storedCrc /= computedCrc
                then Left (HeaderCrcMismatch storedCrc computedCrc)
                else
                  Right
                    ContainerHeader
                      { chContainerVersion = containerVersion
                      , chPayloadKind = kind
                      , chBytecodeVersion = bytecodeVersion
                      , chAbiVersion = abiVersion
                      , chRnTargetVersion = rnTargetVersion
                      , chCompilerVersion = compilerVersion
                      , chRuntimeFingerprint = runtimeFp
                      , chPayloadLength = payloadLen
                      , chHeaderCrc = storedCrc
                      }
  where
    magic = readLe64 bs 0
    containerVersion = readLe32 bs 8
    kindTag = readLe32 bs 12
    bytecodeVersion = readLe32 bs 16
    abiVersion = readLe32 bs 20
    rnTargetVersion = readLe32 bs 24
    compilerVersion = readLe32 bs 28
    runtimeFp = readLe32 bs 32
    payloadLen = readLe32 bs 36
    -- offset 40 is the reserved word (folded into the header CRC, read back 0)
    storedCrc = readLe32 bs 44

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
  | -- | (CMP-11) The bundle was compiled for an @--rn-target@ pin the host is
    -- not linked against. Carries (bundle packed, host packed).
    RnTargetMismatch Word32 Word32
  | -- | (CMP-11) The single runtimeVersion fingerprint differs from the host's
    -- own — the umbrella OTA gate. Carries (bundle, host). This is implied by one
    -- of the field-level mismatches above, but is checked independently so a host
    -- can gate on the fingerprint ALONE and still reject every incompatibility.
    RuntimeFingerprintMismatch Word32 Word32
  deriving (Eq, Show)

-- | The host's own pins — what it validates an incoming container AGAINST. The
-- host fills these from its linked engine + vendored RN pin + its own
-- ABI/compiler floor; mirrored here so a round-trip test can prove the compiler
-- emits exactly what the host accepts.
data HostPins = HostPins
  { hpContainerVersion :: !Word32
  -- ^ the container layout version the host understands
  , hpEngineBytecodeVersion :: !Word32
  -- ^ the bytecode version the linked engine speaks
  , hpAbiVersion :: !Word32
  -- ^ the ABI version the host speaks
  , hpRnTarget :: !RnTarget
  -- ^ the RN pin the host is vendored against
  , hpCompilerVersion :: !RnTarget
  -- ^ the compiler version the host expects bundles to carry (the fingerprint
  -- constituent — the host gates the fingerprint, not an ordering on this)
  } deriving (Eq, Show)

-- | The default host pins — the compiler's mirror of @host/shared/cpp@'s
-- constants. A bundle the compiler builds with the matching defaults passes this
-- gate, which is what the round-trip tests assert.
hostPins :: HostPins
hostPins =
  HostPins
    { hpContainerVersion = kCanopyContainerVersion
    , hpEngineBytecodeVersion = kCanopyEngineBytecodeVersion
    , hpAbiVersion = kCanopyAbiVersion
    , hpRnTarget = kCanopyRnTargetPin
    , hpCompilerVersion = kCanopyCompilerVersion
    }

-- | Validate a parsed header against the host's own pins (the four legacy
-- positional arguments of the CMP-8 gate, plus the CMP-11 RN target). Kept as
-- the CMP-8 signature for existing call sites; the CMP-11 fingerprint gate is
-- exercised through 'validateAgainst'.
--
-- A 'JsSource' payload's bytecode version is NOT gated (it is 0 and the engine
-- parses source regardless — the dev fallback always loads); an 'HbcBytecode'
-- payload's bytecode version MUST equal the engine's. The ABI version and RN
-- target are gated for both kinds.
validate
  :: Word32
  -- ^ the container version the host understands ('kCanopyContainerVersion')
  -> Word32
  -- ^ the bytecode version the linked engine speaks
  -> Word32
  -- ^ the ABI version the host speaks
  -> ContainerHeader
  -> Either ValidationError ()
validate hostContainerVersion engineBytecodeVersion hostAbiVersion =
  validateAgainst
    hostPins
      { hpContainerVersion = hostContainerVersion
      , hpEngineBytecodeVersion = engineBytecodeVersion
      , hpAbiVersion = hostAbiVersion
      }

-- | Validate a parsed header against full 'HostPins' (CMP-11) — the host's
-- go/no-go, mirrored. Checks, in order, the container version, the ABI version,
-- the @--rn-target@ pin, the bytecode version (HBC only), and finally the single
-- runtimeVersion fingerprint (the umbrella). The field-level checks come first so
-- the rejection message names the precise axis that mismatched; the fingerprint
-- check is last and catches anything the field checks did not (it cannot pass if
-- a field check failed, but a host that ONLY computes the fingerprint still
-- rejects every incompatibility through it).
validateAgainst :: HostPins -> ContainerHeader -> Either ValidationError ()
validateAgainst pins h
  | chContainerVersion h /= hpContainerVersion pins =
      Left (UnsupportedContainerVersion (chContainerVersion h) (hpContainerVersion pins))
  | chAbiVersion h /= hpAbiVersion pins =
      Left (AbiVersionMismatch (chAbiVersion h) (hpAbiVersion pins))
  | chRnTargetVersion h /= hostRnPacked =
      Left (RnTargetMismatch (chRnTargetVersion h) hostRnPacked)
  | chPayloadKind h == HbcBytecode && chBytecodeVersion h /= hpEngineBytecodeVersion pins =
      Left (BytecodeVersionMismatch (chBytecodeVersion h) (hpEngineBytecodeVersion pins))
  | chRuntimeFingerprint h /= hostFingerprint =
      Left (RuntimeFingerprintMismatch (chRuntimeFingerprint h) hostFingerprint)
  | otherwise = Right ()
  where
    hostRnPacked = packVersion (hpRnTarget pins)
    hostCompilerPacked = packVersion (hpCompilerVersion pins)
    -- The host recomputes the fingerprint from the header's effective bytecode
    -- (a JS-source payload's is 0, exactly as stamped) and ITS OWN abi/rn/
    -- compiler pins, so a matching bundle's fingerprint equals this.
    hostFingerprint =
      runtimeFingerprint
        (chBytecodeVersion h)
        (hpAbiVersion pins)
        hostRnPacked
        hostCompilerPacked

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

-- | The version-matched @hermesc@ command for a given @--rn-target@ (CMP-11):
-- resolve the target's toolchain directory to its @hermesc@ binary, then build
-- the standard 'hermescCommand'. The build computes the @hermesc@ path from the
-- selected RN target's vendored toolchain (so @--rn-target=0.76.9@ drives the
-- @0.76.9@ @hermesc@, never a stray one on @PATH@), keeping the "matched
-- hermesc" selection a function of the single declared knob.
hermescForTarget
  :: FilePath
  -- ^ the toolchain root that holds each RN target's @hermesc@
  -> RnTarget
  -- ^ the selected @--rn-target@ pin
  -> FilePath
  -- ^ the assembled CMP-5 JS bundle to compile
  -> FilePath
  -- ^ the @.hbc@ output to write
  -> [String]
hermescForTarget toolchainRoot target =
  hermescCommand (toolchainRoot <> "/" <> rnTargetDir target <> "/hermesc")

-- | The per-target subdirectory under the toolchain root that holds that RN
-- pin's @hermesc@ — @"0.76.9"@ for the supported pin. A dotted version string so
-- the on-disk layout reads the same as the @--rn-target@ knob.
rnTargetDir :: RnTarget -> FilePath
rnTargetDir (RnTarget major minor patch) =
  intercalate "." (map show [major, minor, patch])

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
