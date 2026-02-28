# Plan 40: Binary Cache Schema Evolution

## Priority: MEDIUM
## Effort: Small (4-8 hours)
## Risk: Low — extend existing versioning

## Problem

The ELCO binary cache has a magic header and schema version (Word16), but there's no migration path when the schema changes. Currently, a schema bump invalidates ALL cached artifacts, requiring a full rebuild. For large projects this can mean minutes of recompilation.

### Current Code (packages/canopy-builder/src/Compiler.hs, lines 632-668)

```haskell
elcoMagic :: Word32
elcoMagic = 0x454C434F  -- "ELCO"

elcoSchemaVersion :: Word16
elcoSchemaVersion = 1
```

## Implementation Plan

### Step 1: Add migration support

**File**: `packages/canopy-builder/src/Compiler/Cache.hs` (NEW or extend)

```haskell
data CacheVersion = CacheVersion
  { _cvSchema :: !Word16
  , _cvCompiler :: !Version  -- Compiler version that wrote the cache
  }

-- | Migration from one schema version to the next
type Migration = ByteString -> Either MigrateError ByteString

migrations :: Map (Word16, Word16) Migration
migrations = Map.fromList
  [ ((1, 2), migrateV1toV2)
  -- Add future migrations here
  ]

-- | Try to migrate cache data to current schema
migrateCache :: Word16 -> ByteString -> Either MigrateError ByteString
migrateCache fromVersion bs
  | fromVersion == elcoSchemaVersion = Right bs
  | otherwise = case Map.lookup (fromVersion, fromVersion + 1) migrations of
      Nothing -> Left (NoMigrationPath fromVersion elcoSchemaVersion)
      Just migrate -> migrate bs >>= migrateCache (fromVersion + 1)
```

### Step 2: Partial invalidation

Instead of invalidating all artifacts when schema changes, only invalidate artifacts that use changed schema features:

```haskell
-- | Check if a cached artifact is compatible with current schema
isCompatible :: CacheVersion -> ArtifactType -> Bool
isCompatible cv artType =
  _cvSchema cv >= minimumSchemaFor artType
```

### Step 3: Cache metadata file

Write a `.cache-meta.json` alongside artifacts.dat:

```json
{
    "schema-version": 1,
    "compiler-version": "0.19.1",
    "created": "2026-02-28T12:00:00Z",
    "module-count": 42
}
```

### Step 4: Cache cleanup command

Add `canopy clean --cache` to clear all cached artifacts:

```bash
canopy clean           # Remove canopy-stuff/
canopy clean --cache   # Also remove ~/.canopy/packages/*/artifacts.dat
canopy clean --all     # Remove everything
```

### Step 5: Tests

- Test schema version detection
- Test migration path execution
- Test partial invalidation
- Test cache metadata read/write

## Dependencies
- None
