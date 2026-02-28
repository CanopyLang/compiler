# Plan 07: O(n) Occurs Check Fix

## Priority: HIGH
## Effort: Small (1-2 hours)
## Risk: Low — isolated type inference change

## Problem

The occurs check in type unification uses `elem` on a list, which is O(n) per lookup. Since the occurs check traverses the entire type recursively, this gives O(n²) worst case for deeply nested types.

### Current Code (packages/canopy-core/src/Type/Occurs.hs, line 21)

```haskell
occurs :: Variable -> [Variable] -> Type -> Bool
occurs var seen typ =
  if var `elem` seen  -- O(n) lookup!
    then True
    else ...
```

## Implementation Plan

### Step 1: Replace list with IntSet

**File**: `packages/canopy-core/src/Type/Occurs.hs`

```haskell
import qualified Data.IntSet as IntSet

occurs :: Variable -> IntSet -> Type -> Bool
occurs var seen typ =
  if varId var `IntSet.member` seen  -- O(log n) lookup
    then True
    else case typ of
      TVar v -> v == var
      TLambda a b -> occurs var seen' a || occurs var seen' b
      TType _ _ args -> any (occurs var seen') args
      ...
  where
    seen' = IntSet.insert (varId var) seen
```

### Step 2: Update all call sites

Search for all callers of `occurs` and update to pass `IntSet.empty` instead of `[]`.

### Step 3: Tests

- Existing type inference tests should continue to pass
- Add a test with deeply nested types (50+ levels) to verify no performance regression
- Property test: occurs check result is same with list vs IntSet implementation

## Dependencies
- None
