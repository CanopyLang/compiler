# Plan 09: Incremental Type Checking

## Priority: MEDIUM
## Effort: Large (3-5 days)
## Risk: High — complex interaction with type inference state

## Problem

`Builder/Incremental.hs` caches source and dependency hashes and skips re-parsing, but it still runs full canonicalization and type checking on every rebuild. For large projects, type checking dominates build time.

### Current Code (packages/canopy-builder/src/Builder/Incremental.hs)

```haskell
-- Lines 177-194
needsRecompile :: CacheEntry -> SourceHash -> DepsHash -> Bool
needsRecompile entry srcHash depsHash =
  _cacheSourceHash entry /= srcHash
    || _cacheDepsHash entry /= depsHash
-- Only checks hashes, then does full recompilation
```

## Implementation Plan

### Step 1: Cache type-checked interfaces

**File**: `packages/canopy-builder/src/Builder/Incremental.hs`

Extend `CacheEntry` to store the canonical module and type-checked interface:

```haskell
data CacheEntry = CacheEntry
  { _cacheSourceHash :: !Hash
  , _cacheDepsHash :: !Hash
  , _cacheArtifactPath :: !FilePath
  , _cacheTimestamp :: !UTCTime
  , _cacheInterface :: !(Maybe Interface)  -- NEW: cached type-checked interface
  , _cacheCanonical :: !(Maybe CanonicalModule)  -- NEW: cached canonical AST
  }
```

### Step 2: Skip canonicalization when source unchanged

When `needsRecompile` returns False AND `_cacheCanonical` is `Just`, skip canonicalization entirely and use the cached version.

### Step 3: Skip type checking when interface unchanged

When a module's interface (exported types, values) hasn't changed, downstream modules don't need re-type-checking even if the implementation changed.

Implement interface comparison:

```haskell
interfaceUnchanged :: Interface -> Interface -> Bool
interfaceUnchanged old new =
  _ifaceExports old == _ifaceExports new
    && _ifaceTypes old == _ifaceTypes new
    && _ifaceUnions old == _ifaceUnions new
    && _ifaceAliases old == _ifaceAliases new
```

### Step 4: Propagate interface changes transitively

When a module's interface DOES change, mark all transitive dependents for re-type-checking. Use the existing `invalidateTransitive` (which already uses Set-based O(V+E) traversal).

### Step 5: Binary serialization for cached interfaces

Add `Binary` instances for `Interface` and `CanonicalModule` if not already present. Store in the ELCO cache alongside compilation artifacts.

### Step 6: Cache invalidation on compiler upgrade

When the compiler version changes, invalidate all cached interfaces (the schema version in ELCO header already handles this for artifacts).

### Step 7: Tests

- Test that unchanged modules skip type checking
- Test that interface changes propagate correctly
- Test that implementation-only changes don't trigger downstream recompilation
- Benchmark: measure build time improvement on a 50-module project

## Dependencies
- None (but benefits from Plan 06 bounded parallelism)
