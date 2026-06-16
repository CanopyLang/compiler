{-# LANGUAGE OverloadedStrings #-}

-- | Compact native mutation encoding (CMP-12 — the compiler side of RND-7 Stage B).
--
-- == Why this module exists
--
-- The Canopy native host applies a STREAM OF MUTATIONS each frame: create a
-- view, set a scalar prop, insert a child, … . RND-7 already collapsed a frame's
-- N per-mutation JSI crossings into ONE @__fabric_applyBatch@ call carrying a
-- flat little-endian buffer (Stage B), so the dominant per-frame mutations cost a
-- memcpy on the seam instead of a @JSON.stringify@/@parse@ per op. That buffer is
-- encoded by @_Native_encodeBatch@ in @package/external/native.js@ and decoded by
-- @BatchReader@/@applyBinaryBatch@ in @host/shared/cpp/CanopyFabric.cpp@ (and the
-- device-free mock in @harness/mock-fabric.js@).
--
-- The Stage-B buffer is compact for the INTS but still REPEATS every string
-- INLINE: a 200-row list re-emits @"RCTView"@ 200 times, a per-frame text update
-- re-emits the key @"text"@ every frame, and a screenful of identical event-name
-- arrays re-emits @["press"]@ for each. The strings dominate the buffer, and they
-- are overwhelmingly a TINY, REPEATED set (a handful of Fabric component names, a
-- handful of scalar keys, a handful of event-name lists).
--
-- CMP-12 is the compiler co-design of the COMPACT (string-pooled, columnar) form
-- of that stream: each DISTINCT string is written ONCE into a per-frame string
-- pool, and every op that used to carry an inline string now carries a small
-- integer that INDEXES the pool. This is the unanimous shape every serious
-- columnar UI protocol uses (Flutter's @SerializationCache@, RN's
-- @ShadowNode@-tag interning), and it is the exact "string-pool integers index
-- prop keys" the CMP-12 plan calls for.
--
-- == Why it lives in the compiler (the NativeBundle seam)
--
-- The encoding is HOST-FACING wire bytes, but — like the @__canopy_boot@ hook in
-- 'Generate.JavaScript.NativeBundle' — it is a single, frozen contract three
-- artifacts must agree on byte-for-byte:
--
--   * the JS encoder in @package/external/native.js@,
--   * the C++ decoder in @host/shared/cpp/CanopyFabric.cpp@, and
--   * the device-free decoder in @harness/mock-fabric.js@.
--
-- Hand-maintaining the same magic byte, opcode set, handle base, and framing in
-- three places is exactly the brittleness the CMP-5 boot-hook splice removed by
-- folding the contract into the compiler. This module makes the COMPILER the
-- single source of truth: it pins every protocol constant ('protocolVersion',
-- the @k*@ opcodes, 'handleBase', 'pooledMagic') and EMITS the string-pooled
-- encoder JS ('encoderSource') the native bundle reaches. The host's decoders are
-- written to this module's pinned constants; the golden test ('encoderSource' +
-- the constant accessors) is the device-free proof that the contract did not
-- drift.
--
-- This module emits ONLY the encoder + constants. It does not touch packaging,
-- hashing, or the per-platform mount logic (that stays behind @CanopyHost@), and
-- it changes no behaviour on its own — the encoder it emits is OPT-IN, taken only
-- when the host advertises @__fabric_batchPooled === true@ (the same
-- feature-detect shape as @__fabric_batchBinary@), so a host that predates the
-- pool keeps the inline Stage-B path BYTE-FOR-BYTE unchanged.
--
-- == The wire format (pinned here; mirrored by the host decoders)
--
-- A pooled batch is, in byte order (all integers little-endian):
--
--   1. one MAGIC byte ('pooledMagic') — distinguishes a pooled buffer from the
--      inline Stage-B buffer whose first byte is an opcode in @1..7@; the magic
--      is @0xCB@, outside that range, so a decoder can branch on byte 0.
--   2. one VERSION byte ('protocolVersion').
--   3. a @uint32@ POOL COUNT, then that many length-prefixed UTF-8 strings
--      (@uint32@ length + bytes) — the per-frame string pool, index 0..count-1.
--   4. the OP STREAM: each op is one opcode byte + its fields, where every field
--      that was an inline string in Stage B is now a @uint32@ POOL INDEX, and
--      every handle/parent/child/index stays a raw @int32@.
--
-- The opcodes and field order are IDENTICAL to inline Stage B (so the host
-- replays through the exact same per-op @CanopyHost@ calls); only the string
-- FIELDS change from inline-bytes to pool-index. A pooled op for a repeated
-- string is thus 5 bytes (opcode + index) where inline Stage B paid
-- @1 + 4 + len@.
--
-- @since 0.20.11
module Generate.JavaScript.NativeMutation
  ( -- * Protocol constants (the single source of truth)
    protocolVersion,
    handleBase,
    pooledMagic,
    Opcode (..),
    opcodeValue,
    allOpcodes,

    -- * Generated encoder JS
    encoderSource,
    encoder,

    -- * Reference encoder (golden / cross-check)
    Op (..),
    encodePooled,
    StringPool,
    buildPool,
    poolStrings,
    poolIndex,
  )
where

import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Word (Word8)

-- PROTOCOL CONSTANTS --------------------------------------------------------

-- | The mutation-stream protocol version. Bumped only on an INCOMPATIBLE wire
-- change (a new field order, a removed opcode). A purely additive opcode does not
-- bump it, mirroring the @CANOPY_ABI_VERSION@ survival rule the @__fabric_*@
-- surface follows: additive seams stay version-stable so an older host keeps
-- working. The version travels in byte 1 of a pooled buffer so a host can reject a
-- buffer it cannot decode rather than misread it.
protocolVersion :: Int
protocolVersion = 1

-- | The high base from which the WALKER allocates JS-owned handles in batch mode,
-- mirrored verbatim from @__fabric_batchHandleBase@ (@host/shared/cpp/CanopyFabric.cpp@
-- and @package/external/native.js@). A batched @createView@ cannot block on a host
-- return, so the walker mints handles itself from this base — far above the small
-- ints a host mints for its boot-time root — and the host populates its view map
-- from the JS-chosen handle. Pinned here so the one number lives in one place.
handleBase :: Int
handleBase = 0x40000000

-- | The MAGIC first byte of a pooled buffer (@0xCB@ — "Canopy Batch").
--
-- It is deliberately OUTSIDE the opcode range @1..7@: an inline Stage-B buffer
-- begins with an opcode byte, so a decoder that sees byte 0 == 'pooledMagic' knows
-- it is the pooled form and byte 0 in @1..7@ knows it is inline — one buffer kind
-- per advertised host capability, but the magic makes the two self-describing so a
-- shared decoder can branch defensively.
pooledMagic :: Word8
pooledMagic = 0xCB

-- | One mutation opcode. Values are FROZEN and MUST equal @_NB_*@ in
-- @package/external/native.js@, @BatchOp@ in @host/shared/cpp/CanopyFabric.cpp@,
-- and @NB_*@ in @harness/mock-fabric.js@. The set and order are identical to
-- inline Stage B; the pooled form changes only how the string fields are carried.
data Opcode
  = OpCreate -- ^ @createView(handle, tag, propsJson)@ — tag + propsJson pooled.
  | OpUpdate -- ^ @updateProps(handle, propsJson)@ — propsJson pooled.
  | OpScalar -- ^ @updatePropScalar(handle, key, value)@ — key + value pooled.
  | OpInsert -- ^ @insertChild(parent, child, index)@ — all ints, no string.
  | OpRemove -- ^ @removeChild(parent, child, index)@ — all ints, no string.
  | OpSetRoot -- ^ @setRoot(handle)@ — one int, no string.
  | OpSetEvents -- ^ @setEvents(handle, namesJson)@ — namesJson pooled.
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The frozen byte value of an opcode (1-based, matching the host enums).
opcodeValue :: Opcode -> Word8
opcodeValue op = case op of
  OpCreate -> 1
  OpUpdate -> 2
  OpScalar -> 3
  OpInsert -> 4
  OpRemove -> 5
  OpSetRoot -> 6
  OpSetEvents -> 7

-- | Every opcode, low-to-high — for exhaustive golden coverage and the JS
-- constant emit.
allOpcodes :: [Opcode]
allOpcodes = [minBound .. maxBound]

-- STRING POOL (reference model) ---------------------------------------------

-- | A per-frame string pool: distinct strings in FIRST-APPEARANCE order, plus the
-- index lookup. Mirrors the JS encoder's pool exactly, so the Haskell reference
-- encoder ('encodePooled') and the emitted JS encoder produce byte-identical
-- buffers for the same op list — the property the golden test pins.
data StringPool = StringPool
  { _spOrder :: [String] -- ^ strings, index 0..n-1, in first-appearance order
  , _spIndex :: Map String Int -- ^ string -> its pool index
  }

-- | The pooled strings in index order.
poolStrings :: StringPool -> [String]
poolStrings = _spOrder

-- | The pool index of a string (assumes it was interned; total via lookup).
poolIndex :: StringPool -> String -> Int
poolIndex (StringPool _ ix) s = Map.findWithDefault (-1) s ix

-- | A single decoded mutation, the reference shape the encoder consumes. Strings
-- are the raw values (tag, propsJson, key, value, namesJson); the encoder interns
-- them. Mirrors the @[opcode, ...args]@ tuples the JS walker records.
data Op
  = Create Int String String -- ^ handle, tag, propsJson
  | Update Int String -- ^ handle, propsJson
  | Scalar Int String String -- ^ handle, key, value
  | Insert Int Int Int -- ^ parent, child, index
  | Remove Int Int Int -- ^ parent, child, index
  | SetRoot Int -- ^ handle
  | SetEvents Int String -- ^ handle, namesJson
  deriving (Eq, Show)

-- | Build the per-frame pool by interning every string field of every op in
-- first-appearance order (the order the JS encoder visits them: create's tag then
-- props, scalar's key then value, …). First-appearance order is what makes the two
-- encoders agree, so it is part of the contract, not an implementation detail.
buildPool :: [Op] -> StringPool
buildPool ops = foldl intern (StringPool [] Map.empty) (concatMap opStrings ops)
  where
    intern pool@(StringPool order ix) s
      | Map.member s ix = pool
      | otherwise = StringPool (order ++ [s]) (Map.insert s (Map.size ix) ix)

-- | The string fields of an op, in the order the encoder emits them. Pure data —
-- both encoders key off this list.
opStrings :: Op -> [String]
opStrings op = case op of
  Create _ tag props -> [tag, props]
  Update _ props -> [props]
  Scalar _ key val -> [key, val]
  Insert {} -> []
  Remove {} -> []
  SetRoot _ -> []
  SetEvents _ names -> [names]

-- REFERENCE ENCODER (golden / cross-check) ----------------------------------

-- | The reference Haskell encoder: turn an op list into the pooled little-endian
-- buffer. This is the AUTHORITATIVE byte layout the emitted JS encoder
-- ('encoderSource') and the host decoders must match; the golden test pins its
-- output for a representative op stream, so any drift in the JS string or the wire
-- format is caught at @stack test@ time (device-free).
--
-- Layout: magic, version, pool (count + length-prefixed UTF-8 strings), then the
-- op stream (opcode + int32 ints + uint32 pool indices for strings).
encodePooled :: [Op] -> Builder
encodePooled ops =
  BB.word8 pooledMagic
    <> BB.word8 (fromIntegral protocolVersion)
    <> u32 (length pool)
    <> mconcat (map poolEntry pool)
    <> mconcat (map (encodeOp sp) ops)
  where
    sp = buildPool ops
    pool = poolStrings sp
    poolEntry s = let bs = utf8Bytes s in u32 (length bs) <> mconcat (map BB.word8 bs)

-- | Encode one op: its opcode byte, then its int fields (raw int32) and its string
-- fields (uint32 pool index), in the frozen field order.
encodeOp :: StringPool -> Op -> Builder
encodeOp sp op = BB.word8 (opcodeValue (opcodeOf op)) <> body
  where
    idx s = u32 (poolIndex sp s)
    body = case op of
      Create h tag props -> i32 h <> idx tag <> idx props
      Update h props -> i32 h <> idx props
      Scalar h key val -> i32 h <> idx key <> idx val
      Insert p c i -> i32 p <> i32 c <> i32 i
      Remove p c i -> i32 p <> i32 c <> i32 i
      SetRoot h -> i32 h
      SetEvents h names -> i32 h <> idx names

-- | The opcode of a reference op.
opcodeOf :: Op -> Opcode
opcodeOf op = case op of
  Create {} -> OpCreate
  Update {} -> OpUpdate
  Scalar {} -> OpScalar
  Insert {} -> OpInsert
  Remove {} -> OpRemove
  SetRoot {} -> OpSetRoot
  SetEvents {} -> OpSetEvents

-- | A little-endian @int32@.
i32 :: Int -> Builder
i32 = BB.int32LE . fromIntegral

-- | A little-endian @uint32@.
u32 :: Int -> Builder
u32 = BB.word32LE . fromIntegral

-- | UTF-8 bytes of a string, matching the JS @_Native_utf8@ encoder (and Node's
-- TextEncoder) byte-for-byte: 1/2/3/4-byte sequences with surrogate-pair
-- combination, so the size pass and the fill pass agree across Haskell, JS, and
-- C++.
utf8Bytes :: String -> [Word8]
utf8Bytes = concatMap encodeChar
  where
    encodeChar c =
      let n = fromEnum c
       in if n < 0x80
            then [fromIntegral n]
            else
              if n < 0x800
                then [fromIntegral (0xC0 + (n `div` 0x40)), cont n]
                else
                  if n < 0x10000
                    then
                      [ fromIntegral (0xE0 + (n `div` 0x1000)),
                        cont (n `div` 0x40),
                        cont n
                      ]
                    else
                      [ fromIntegral (0xF0 + (n `div` 0x40000)),
                        cont (n `div` 0x1000),
                        cont (n `div` 0x40),
                        cont n
                      ]
    cont x = fromIntegral (0x80 + (x `mod` 0x40))

-- GENERATED ENCODER JS ------------------------------------------------------

-- | The string-pooled encoder, as a 'Builder' ready to splice into the native
-- bundle (the same way 'Generate.JavaScript.NativeBundle.bootHook' is). It defines
-- @_Native_encodeBatchPooled(ops)@: given the SAME @[opcode, ...args]@ op tuples
-- the walker already records for inline Stage B, it produces the pooled
-- little-endian @ArrayBuffer@ this module pins. The native bundle takes this path
-- ONLY when the host advertises @__fabric_batchPooled === true@; otherwise the
-- existing inline @_Native_encodeBatch@ runs unchanged.
encoder :: Builder
encoder = BB.stringUtf8 encoderSource

-- | The generated encoder, as a 'String' (so tests can substring-assert it and the
-- bundle assembler can embed it). All protocol constants are interpolated from the
-- pinned Haskell values above, so the JS can NEVER disagree with the reference
-- encoder or the host decoders — the single-source-of-truth property.
--
-- The op tuples are @[opcode, handle?, str?, str?]@, identical to inline Stage B:
--
--   * pass 1 builds the per-frame pool (a @Map@ string->index, first-appearance
--     order) and sizes the buffer;
--   * pass 2 writes magic, version, the pool (count + length-prefixed UTF-8), then
--     the ops with int32 ints and uint32 pool indices.
--
-- It reuses the bundle's existing @_Native_utf8@ helper for byte counts, so the
-- pool's size pass and fill pass agree byte-for-byte with inline Stage B and with
-- 'utf8Bytes' here.
encoderSource :: String
encoderSource =
  unlines
    [ ""
    , "// GENERATED by canopy make --target native — compact (string-pooled) mutation encoder (CMP-12)."
    , "// Single source of truth: host decoders (CanopyFabric.cpp, mock-fabric.js) mirror these bytes."
    , "(function (g) {"
    , "  // Frozen protocol constants (pinned in Generate.JavaScript.NativeMutation)."
    , "  var MAGIC = " ++ show (fromIntegral pooledMagic :: Int) ++ ";"
    , "  var VERSION = " ++ show protocolVersion ++ ";"
    , "  var HANDLE_BASE = " ++ show handleBase ++ ";"
    , "  var OP_CREATE = " ++ opc OpCreate ++ ", OP_UPDATE = " ++ opc OpUpdate
        ++ ", OP_SCALAR = " ++ opc OpScalar ++ ", OP_INSERT = " ++ opc OpInsert ++ ";"
    , "  var OP_REMOVE = " ++ opc OpRemove ++ ", OP_SET_ROOT = " ++ opc OpSetRoot
        ++ ", OP_SET_EVENTS = " ++ opc OpSetEvents ++ ";"
    , "  g.__canopy_batchHandleBase = HANDLE_BASE;"
    , ""
    , "  // The string fields of an op, in emit order — the SAME order the reference"
    , "  // encoder interns, so the pools (and therefore the indices) agree exactly."
    , "  function opStrings(op) {"
    , "    switch (op[0]) {"
    , "      case OP_CREATE: return [op[2], op[3]];"
    , "      case OP_UPDATE: return [op[2]];"
    , "      case OP_SCALAR: return [op[2], op[3]];"
    , "      case OP_SET_EVENTS: return [op[2]];"
    , "      default: return [];"
    , "    }"
    , "  }"
    , ""
    , "  // Encode an op list into ONE pooled little-endian ArrayBuffer. Two passes so we"
    , "  // allocate exactly once: pass 1 builds the pool + sizes the buffer; pass 2 fills it."
    , "  g.__canopy_encodeBatchPooled = function (ops) {"
    , "    var utf8 = g._Native_utf8;"
    , "    // Pass 1a: intern every string field, first-appearance order."
    , "    var index = Object.create(null);"
    , "    var pool = [];        // pooled strings, in index order"
    , "    var poolBytes = [];   // their cached utf8 byte arrays (so pass 2 reuses them)"
    , "    var i, j, op, strs, s;"
    , "    for (i = 0; i < ops.length; i++) {"
    , "      strs = opStrings(ops[i]);"
    , "      for (j = 0; j < strs.length; j++) {"
    , "        s = strs[j] == null ? '' : String(strs[j]);"
    , "        if (index[s] === undefined) { index[s] = pool.length; pool.push(s); poolBytes.push(utf8(s)); }"
    , "      }"
    , "    }"
    , "    // Pass 1b: total bytes. header (magic+version) + pool (count + each len-prefixed) + ops."
    , "    var total = 1 + 1 + 4;"
    , "    for (i = 0; i < poolBytes.length; i++) { total += 4 + poolBytes[i].length; }"
    , "    for (i = 0; i < ops.length; i++) {"
    , "      op = ops[i];"
    , "      total += 1; // opcode"
    , "      switch (op[0]) {"
    , "        case OP_CREATE: total += 4 + 4 + 4; break;            // handle + 2 indices"
    , "        case OP_UPDATE: total += 4 + 4; break;                // handle + 1 index"
    , "        case OP_SCALAR: total += 4 + 4 + 4; break;            // handle + 2 indices"
    , "        case OP_INSERT: case OP_REMOVE: total += 12; break;   // 3 ints"
    , "        case OP_SET_ROOT: total += 4; break;                  // 1 int"
    , "        case OP_SET_EVENTS: total += 4 + 4; break;            // handle + 1 index"
    , "      }"
    , "    }"
    , "    // Pass 2: fill."
    , "    var buf = new ArrayBuffer(total);"
    , "    var dv = new DataView(buf);"
    , "    var u8 = new Uint8Array(buf);"
    , "    var off = 0;"
    , "    function putI32(x) { dv.setInt32(off, x | 0, true); off += 4; }"
    , "    function putU32(x) { dv.setUint32(off, x >>> 0, true); off += 4; }"
    , "    function putBytes(bytes) { putU32(bytes.length); u8.set(bytes, off); off += bytes.length; }"
    , "    u8[off++] = MAGIC;"
    , "    u8[off++] = VERSION;"
    , "    putU32(pool.length);"
    , "    for (i = 0; i < poolBytes.length; i++) { putBytes(poolBytes[i]); }"
    , "    for (i = 0; i < ops.length; i++) {"
    , "      op = ops[i];"
    , "      u8[off++] = op[0];"
    , "      switch (op[0]) {"
    , "        case OP_CREATE: putI32(op[1]); putU32(index[norm(op[2])]); putU32(index[norm(op[3])]); break;"
    , "        case OP_UPDATE: putI32(op[1]); putU32(index[norm(op[2])]); break;"
    , "        case OP_SCALAR: putI32(op[1]); putU32(index[norm(op[2])]); putU32(index[norm(op[3])]); break;"
    , "        case OP_INSERT: case OP_REMOVE: putI32(op[1]); putI32(op[2]); putI32(op[3]); break;"
    , "        case OP_SET_ROOT: putI32(op[1]); break;"
    , "        case OP_SET_EVENTS: putI32(op[1]); putU32(index[norm(op[2])]); break;"
    , "      }"
    , "    }"
    , "    return buf;"
    , "  };"
    , ""
    , "  // Normalise a string field exactly as the interning pass did, so the lookup key matches."
    , "  function norm(s) { return s == null ? '' : String(s); }"
    , "})(typeof globalThis !== 'undefined' ? globalThis : this);"
    ]
  where
    opc = show . (fromIntegral :: Word8 -> Int) . opcodeValue
