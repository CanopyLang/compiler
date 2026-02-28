# Plan 38: unsafePerformIO Audit & Documentation

## Priority: LOW
## Effort: Small (2-4 hours)
## Risk: Low — documentation and verification only

## Problem

Three `unsafePerformIO` usages exist in the codebase. While all three are legitimate (from the audit), they need formal documentation and verification that they're actually safe.

### Current Locations
1. `packages/canopy-core/src/Logging/Logger.hs` — global logger IORef
2. `packages/canopy-core/src/Logging/Config.hs` — global config IORef
3. `packages/canopy-query/src/Query/Simple.hs` — query cache initialization

## Implementation Plan

### Step 1: Document each usage

Add detailed safety justification comments to each `unsafePerformIO`:

```haskell
-- | Global logger reference.
--
-- SAFETY: This is safe because:
-- 1. The IORef is created once at program start (NOINLINE + global)
-- 2. All writes go through atomic modifyIORef'
-- 3. The logger is append-only (no destructive updates)
-- 4. Thread safety is guaranteed by IORef atomicity
{-# NOINLINE globalLogger #-}
globalLogger :: IORef Logger
globalLogger = unsafePerformIO (newIORef defaultLogger)
```

### Step 2: Verify NOINLINE pragmas

Ensure all three usages have `{-# NOINLINE #-}` pragmas to prevent the GHC optimizer from duplicating the computation.

### Step 3: Verify thread safety

For each usage, verify that concurrent access is safe:
- IORef with atomic operations: safe
- MVar: safe
- Raw IORef with non-atomic reads/writes: NOT safe (fix if found)

### Step 4: Consider alternatives

For each usage, document why alternatives were rejected:
- `Logger.hs`: ReaderT would thread through every function
- `Config.hs`: Same — global config avoids parameter passing
- `Query/Simple.hs`: Cache must survive across function calls

### Step 5: Add hlint rule

Add an hlint hint that flags new `unsafePerformIO` usage:

```yaml
- warn: {lhs: unsafePerformIO, note: "Requires safety review. See Plan 38."}
```

## Dependencies
- None
