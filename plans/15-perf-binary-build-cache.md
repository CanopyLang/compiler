# Plan 15: Incremental Build Cache Binary Format

**Priority:** HIGH
**Effort:** Medium (1-2 days)
**Risk:** Low (cache format migration is graceful -- old format falls back to empty cache)

## Problem

The incremental build cache index (`canopy-stuff/build-cache.json`) uses JSON
(via `aeson`) for serialization. This is unnecessarily slow for a cache that is
read at startup and written after every build. The per-module artifact files
(`.elco`) already use an efficient versioned binary format, but the cache index
that tracks which modules are up-to-date does not.

### Current Implementation

**`/home/quinten/fh/canopy/packages/canopy-builder/src/Builder/Incremental.hs`:**

The `BuildCache` type (line 103-108) stores a `Map ModuleName.Raw CacheEntry` with
entries for each compiled module:

```haskell
data BuildCache = BuildCache
  { cacheEntries :: !(Map ModuleName.Raw CacheEntry),
    cacheVersion :: !String,
    cacheCreated :: !UTCTime
  }
```

Each `CacheEntry` (lines 65-71) stores:
```haskell
data CacheEntry = CacheEntry
  { cacheSourceHash :: !Hash.ContentHash,
    cacheDepsHash :: !Hash.ContentHash,
    cacheArtifactPath :: !FilePath,
    cacheTimestamp :: !UTCTime,
    cacheInterfaceHash :: !(Maybe Hash.ContentHash)
  }
```

**JSON serialization overhead (lines 74-142):**

The `ToJSON`/`FromJSON` instances convert hashes to hex strings (`toHexString` line 77),
module names to `show` strings (line 122), and wrap everything in JSON objects. This
creates massive overhead:

1. **`toHexString`** converts 32-byte SHA-256 digests to 64-character hex strings
2. **`Aeson.object`** allocates a HashMap per entry
3. **`Aeson.encode`** pretty-prints to lazy ByteString via text-building
4. **`Aeson.eitherDecode`** parses JSON from lazy ByteString, allocating Value tree

**Load path (lines 156-172):**
```haskell
loadCache :: FilePath -> IO (Maybe BuildCache)
loadCache path = do
  exists <- Dir.doesFileExist path
  if exists
    then do
      contents <- BSL.readFile path
      case Aeson.eitherDecode contents of  -- JSON parse: allocates full Value tree
        Left err -> return Nothing
        Right cache -> return (Just cache)
    else return Nothing
```

**Save path (lines 174-180):**
```haskell
saveCache :: FilePath -> BuildCache -> IO ()
saveCache path cache = do
  let json = Aeson.encode cache  -- JSON encode: allocates lazy ByteString
  BSL.writeFile path json
```

### ELCO Binary Format as a Model

**`/home/quinten/fh/canopy/packages/canopy-builder/src/Compiler/Cache.hs`:**

The `.elco` artifact format (lines 207-239) demonstrates the correct approach:

```haskell
-- Magic header: "ELCO" (4 bytes)
-- Schema version: Word16 (2 bytes)
-- Compiler version: 3x Word16 (6 bytes)
-- Payload: Binary-encoded
elcoMagic :: LBS.ByteString
elcoMagic = LBS.pack [0x45, 0x4C, 0x43, 0x4F]

elcoSchemaVersion :: Word16
elcoSchemaVersion = 2

encodeVersioned :: (Binary.Binary a) => a -> LBS.ByteString
encodeVersioned payload =
  elcoMagic <> Binary.encode elcoSchemaVersion
    <> Binary.encode (_major Version.compiler)
    <> Binary.encode (_minor Version.compiler)
    <> Binary.encode (_patch Version.compiler)
    <> Binary.encode payload
```

This is compact, fast, and self-validating.

### Performance Impact

For a 200-module project, the cache index contains ~200 entries. Each entry has:
- 2 hash strings (128 chars each as hex) -> JSON strings
- 1 file path -> JSON string
- 1 timestamp -> JSON string (ISO 8601)
- 1 optional hash -> JSON string or null

The JSON representation is ~50KB for 200 modules. The binary representation
would be ~8KB (32 bytes per hash * 5 + FilePath + 8 bytes timestamp per entry).
JSON parsing allocates the full Value tree plus intermediate Text/String values.

## Solution

### Phase 1: Add Binary instances for cache types

```haskell
-- In Builder/Incremental.hs, add Binary instances

instance Binary.Binary HashValue where
  put (HashValue sbs) = Binary.put (SBS.fromShort sbs)
  get = HashValue . SBS.toShort <$> Binary.get

instance Binary.Binary ContentHash where
  put (ContentHash hv src) = Binary.put hv >> Binary.put src
  get = ContentHash <$> Binary.get <*> Binary.get

instance Binary.Binary CacheEntry where
  put (CacheEntry srcHash depsHash artPath ts ifaceHash) = do
    Binary.put srcHash
    Binary.put depsHash
    Binary.put artPath
    Binary.put ts
    Binary.put ifaceHash
  get = CacheEntry <$> Binary.get <*> Binary.get <*> Binary.get
                   <*> Binary.get <*> Binary.get

instance Binary.Binary BuildCache where
  put (BuildCache entries version created) = do
    Binary.put entries
    Binary.put version
    Binary.put created
  get = BuildCache <$> Binary.get <*> Binary.get <*> Binary.get
```

Note: `ModuleName.Raw` (which is `Utf8.Utf8 CANOPY_NAME`) already has a `Binary`
instance via `Utf8.putUnder256`/`Utf8.getUnder256` (see `Canopy/Data/Name/Core.hs`
line 80-82). `UTCTime` needs a manual instance since it is not in `Data.Binary` by
default -- use `Data.Time.Clock.POSIX.utcTimeToPOSIXSeconds` for compact encoding.

### Phase 2: Use versioned binary format for cache index

Reuse the ELCO header format from `Compiler.Cache`:

```haskell
-- New magic for build cache: "BCCH"
buildCacheMagic :: LBS.ByteString
buildCacheMagic = LBS.pack [0x42, 0x43, 0x43, 0x48]

buildCacheSchemaVersion :: Word16
buildCacheSchemaVersion = 1

loadCache :: FilePath -> IO (Maybe BuildCache)
loadCache path = do
  exists <- Dir.doesFileExist path
  if not exists
    then return Nothing
    else do
      contents <- LBS.readFile path
      case decodeBuildCache contents of
        Right cache -> return (Just cache)
        Left _msg -> tryLegacyJsonLoad path contents

saveCache :: FilePath -> BuildCache -> IO ()
saveCache path cache =
  LBS.writeFile path (encodeBuildCache cache)

encodeBuildCache :: BuildCache -> LBS.ByteString
encodeBuildCache cache =
  buildCacheMagic
    <> Binary.encode buildCacheSchemaVersion
    <> Binary.encode cache

decodeBuildCache :: LBS.ByteString -> Either String BuildCache
decodeBuildCache bytes
  | LBS.length bytes < 6 = Left "too short"
  | LBS.take 4 bytes /= buildCacheMagic = Left "not binary cache"
  | otherwise =
      case Binary.decodeOrFail (LBS.drop 4 bytes) of
        Left (_, _, msg) -> Left msg
        Right (rest, _, ver)
          | ver /= buildCacheSchemaVersion -> Left "schema mismatch"
          | otherwise ->
              case Binary.decodeOrFail rest of
                Left (_, _, msg) -> Left msg
                Right (_, _, cache) -> Right cache
```

### Phase 3: Graceful migration from JSON

On first load after the change, the binary decode will fail (no magic header),
so `tryLegacyJsonLoad` falls back to JSON parsing. On the next save, the binary
format is written. This provides seamless migration with no user action required.

```haskell
tryLegacyJsonLoad :: FilePath -> LBS.ByteString -> IO (Maybe BuildCache)
tryLegacyJsonLoad _path contents =
  case Aeson.eitherDecode contents of
    Right cache -> return (Just cache)
    Left _ -> return Nothing
```

### Phase 4: Remove Aeson dependency (optional)

After one release cycle, remove the JSON fallback and the `aeson` import from
`Builder.Incremental`. This removes the `ToJSON`/`FromJSON` instances and the
`Data.Aeson` import.

## Files to Modify

| File | Change |
|------|--------|
| `packages/canopy-builder/src/Builder/Incremental.hs` | Replace Aeson with Binary instances; add versioned binary encode/decode; keep JSON fallback for migration |
| `packages/canopy-builder/src/Builder/Hash.hs` | Add `Binary` instance for `HashValue` and `ContentHash` |
| `packages/canopy-builder/canopy-builder.cabal` | (Optional) Remove `aeson` from build-depends after migration period |

## Verification

```bash
# Build the project
stack build --fast

# Run incremental cache tests
stack test --ta="--pattern Incremental"

# Test migration: build with old format, upgrade, rebuild
cd /path/to/sample-project
canopy make   # creates JSON cache
# ... apply changes ...
canopy make   # should load JSON cache, save binary cache
canopy make   # should load binary cache directly

# Benchmark load/save
stack bench --ba="--match prefix Bench.Cache"
```

## Expected Impact

- **Load time**: 5-10x faster cache loading (Binary decode vs JSON parse)
- **Save time**: 3-5x faster cache saving (Binary encode vs JSON encode)
- **File size**: 4-6x smaller cache file (binary vs JSON text)
- **Allocation**: 80-90% less allocation during cache load (no intermediate Value tree)
- **Practical impact**: 50-100ms savings per build on 200-module project (cache load + save)
