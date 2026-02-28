# Plan 50: Strict Data Structure Audit

## Priority: MEDIUM
## Effort: Small (4-8 hours)
## Risk: Low — targeted strictness annotations

## Problem

Some data structures lack strictness annotations, potentially causing thunk accumulation in long-running compilation. The CLAUDE.md mandates strict fields but not all records comply.

## Implementation Plan

### Step 1: Audit all data types in hot paths

Check for missing bang patterns on:
- All fields in `CompileEnv`, `CompileState`, `CacheEntry`
- Builder task types
- Type inference state
- Parser state

### Step 2: Add {-# UNPACK #-} where beneficial

For small fields (Int, Word, Bool, Char), add UNPACK:

```haskell
data CacheEntry = CacheEntry
  { _cacheSize :: {-# UNPACK #-} !Int
  , _cacheTimestamp :: {-# UNPACK #-} !Word64
  , _cacheValid :: !Bool
  }
```

### Step 3: Replace lazy containers with strict variants

Verify all Map/Set usages use strict variants:
- `Data.Map.Strict` not `Data.Map.Lazy`
- `Data.IntMap.Strict` not `Data.IntMap.Lazy`
- `Data.HashMap.Strict` not `Data.HashMap.Lazy`

### Step 4: Enable StrictData pragma

Consider adding `{-# LANGUAGE StrictData #-}` to performance-critical modules instead of individual bang patterns.

### Step 5: Tests

- Existing tests should continue to pass
- Memory benchmarks (Plan 21) should show improvement

## Dependencies
- Plan 21 (memory profiling) for measurement
