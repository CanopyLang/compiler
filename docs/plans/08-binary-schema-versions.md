# Plan 08 — Add Binary Schema Versions to .elco Cache

**Priority:** Tier 1 (Critical Architecture)
**Effort:** 1 day
**Risk:** Medium (invalidates all existing caches — intentional)
**Files:** ~8 files in `packages/canopy-core/src/`

---

## Problem

Binary serialization of `.elco` cache files uses per-constructor `putWord8`/`getWord8` tags but **no file-format version header**. When the binary encoding changes (new AST constructors, changed field order, added fields), old cache files silently produce corrupt deserializations.

The current mitigation is manual: `MEMORY.md` documents "must be cleared when optimizer output format changes" and users must run `rm -rf canopy-stuff elm-stuff`. This is fragile and will cause confusing "impossible" errors for users who don't know to clear the cache.

## Design

### Schema Version Header

Every `.elco` file will start with a fixed magic number and version:

```
Bytes 0-3:  Magic number (0x43 0x4E 0x50 0x59 = "CNPY")
Bytes 4-5:  Schema version (Word16, big-endian)
Bytes 6+:   Binary payload (existing format)
```

The schema version is a monotonically increasing integer. Any change to any `Binary` instance in the compiler increments it. The version is defined as a constant in a single location.

### Version Mismatch Behavior

When loading a cache file:
1. Read first 6 bytes
2. Check magic number — if wrong, treat as corrupt (delete and recompile)
3. Check version — if different from current, treat as stale (delete and recompile)
4. Proceed with normal binary decode

This is a clean, automatic cache invalidation. Users never need to manually clear caches.

## Implementation

### Step 1: Create a schema version module

```haskell
-- | Binary schema version for .elco cache files.
--
-- Increment 'currentSchemaVersion' whenever ANY Binary instance
-- in the compiler changes. This ensures stale caches are automatically
-- detected and rebuilt.
--
-- @since 0.19.2
module File.SchemaVersion
  ( currentSchemaVersion
  , magicNumber
  , SchemaVersion
  , writeHeader
  , readHeader
  , HeaderResult(..)
  ) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BB

-- | Current schema version. INCREMENT THIS on any Binary instance change.
currentSchemaVersion :: Word16
currentSchemaVersion = 1

-- | Magic bytes: "CNPY" (0x43 0x4E 0x50 0x59)
magicNumber :: BS.ByteString
magicNumber = BS.pack [0x43, 0x4E, 0x50, 0x59]

data HeaderResult
  = HeaderOk
  | HeaderCorrupt
  | HeaderVersionMismatch !Word16  -- ^ found version
  deriving (Show)

writeHeader :: BB.Builder
writeHeader =
  BB.byteString magicNumber <> BB.word16BE currentSchemaVersion

readHeader :: BS.ByteString -> HeaderResult
readHeader bs
  | BS.length bs < 6 = HeaderCorrupt
  | BS.take 4 bs /= magicNumber = HeaderCorrupt
  | foundVersion /= currentSchemaVersion = HeaderVersionMismatch foundVersion
  | otherwise = HeaderOk
  where
    foundVersion = -- decode Word16 from bytes 4-5
```

### Step 2: Update cache write path

In `packages/canopy-builder/src/Compiler.hs`, the `saveToCacheAsync` function that writes `.elco` files:

```haskell
-- Before: Binary.encodeFile path (iface, localGraph, ffiInfo)
-- After:
saveToCacheFile :: FilePath -> (Interface, LocalGraph, FFIInfo) -> IO ()
saveToCacheFile path payload = do
  let headerBytes = BB.toLazyByteString SchemaVersion.writeHeader
  let payloadBytes = Binary.encode payload
  BSL.writeFile path (headerBytes <> payloadBytes)
```

### Step 3: Update cache read path

In `Compiler.hs`, the `decodeCachedModule` function:

```haskell
decodeCachedModule :: FilePath -> IO (Maybe (Interface, LocalGraph, FFIInfo))
decodeCachedModule path = do
  bytes <- BS.readFile path
  case SchemaVersion.readHeader bytes of
    SchemaVersion.HeaderCorrupt -> do
      removeFile path  -- delete corrupt file
      pure Nothing
    SchemaVersion.HeaderVersionMismatch _v -> do
      removeFile path  -- delete stale file
      pure Nothing
    SchemaVersion.HeaderOk ->
      case Binary.decodeOrFail (BSL.fromStrict (BS.drop 6 bytes)) of
        Left _ -> do
          removeFile path
          pure Nothing
        Right (_, _, payload) ->
          pure (Just payload)
```

### Step 4: Update artifacts.dat similarly

The `~/.canopy/packages/<author>/<pkg>/<ver>/artifacts.dat` files should also get the schema version header. Update `Build/Artifacts.hs` read/write paths.

### Step 5: Add to canopy-core.cabal

```yaml
exposed-modules:
  ...
  File.SchemaVersion
```

### Step 6: Document in CHANGELOG

```markdown
### Changed
- Cache files now include a schema version header. Existing caches will be
  automatically rebuilt on first use. No manual cache clearing needed.
```

## Validation

```bash
# Build with new schema
make build

# Clear existing cache to test from scratch
rm -rf canopy-stuff

# Build a test project — should create new-format .elco files
canopy make src/Main.can

# Verify .elco files start with magic bytes
xxd canopy-stuff/cache/*.elco | head -3
# Should show: 434e 5059 0001 ...

# Run all tests
make test
```

## Acceptance Criteria

- Every `.elco` and `artifacts.dat` file starts with `CNPY` + version bytes
- Version mismatch causes automatic rebuild, not crash
- Corrupt files are deleted and rebuilt, not crash
- `currentSchemaVersion` is defined in exactly one place
- `make build && make test` passes
- Manual cache clearing is no longer needed after format changes
