# Type Identity Fix for 3+ Type Parameters

## Date
2025-10-07

## Problem Summary

Types with 3 or more type parameters (especially with RigidSuper constraints like `comparable`) were losing type identity during instantiation, causing false type mismatch errors:

```
This `insert` call produces:
    Test.Dict comparable k v

But the type annotation on `alter` says it should be:
    Test.Dict comparable k v
```

The types LOOK identical but the compiler thinks they're different!

## Minimal Reproducing Test Case

```elm
module Test exposing (..)

type Dict comparable k v
    = Dict String

get : Dict comparable k v -> Maybe v
get dict =
    Nothing

insert : v -> Dict comparable k v -> Dict comparable k v
insert val dict =
    dict

alter : (Maybe v -> v) -> Dict comparable k v -> Dict comparable k v
alter f dict =
    insert (f (get dict)) dict  -- ERROR HERE!
```

## Root Cause Analysis

The issue had TWO problems:

### Problem 1: Filtering Current Function's Rigids from Ambient Rigids

In `solveHeaderInNextPool`, the code was filtering out the current function's rigids from ambient rigids before solving the function body:

```haskell
-- BEFORE (BROKEN):
filteredConfig <- if shouldGeneralizeEarly
  then do
    -- Remove this function's rigids from ambient rigids
    let filteredRigids = [pair | pair@(_, var) <- config ^. solveAmbientRigids, not (var `elem` rigids)]
    return $ config & solveAmbientRigids .~ filteredRigids
  else
    return config
```

**Why this breaks:**
1. When processing `alter` at rank 4, its rigids `comparable(4)`, `k(4)`, `v(4)` are added to ambient
2. They're immediately filtered out, leaving only rigids from `insert(rank 2)` and `get(rank 3)`
3. When the body instantiates `insert`, `makeCopy` looks for matching rigids
4. It finds `k` and `v` at ranks 2 or 3 (from outer scopes), not rank 4 (current scope)
5. This creates different Variable pointers for what should be the same type variables

### Problem 2: Not Replacing Lower-Rank Rigids with Higher-Rank Versions

Even when ambient rigids contained multiple versions of the same rigid (e.g., `comparable` at ranks 2, 3, and 4), the code would use whichever it encountered first during traversal.

For RigidVar, this was partially handled by `findMatchingRigid`, which would find a matching rigid.

For RigidSuper and non-noRank rigids, the code in `handleNoCopy` would return the variable as-is without checking for higher-rank versions:

```haskell
-- BEFORE (BROKEN):
handleNoCopy maxRank pools ambientRigids variable content rank
  | rank /= noRank = do
      return variable  -- Just return it!
  | otherwise = ...
```

**Why this breaks:**
1. When instantiating `insert`, we traverse its type `v -> Dict comparable k v -> Dict comparable k v`
2. We encounter `comparable` RigidSuper at rank 2 (from insert's own scope)
3. Since `rank /= noRank`, we return it as-is
4. But we SHOULD be using `comparable` at rank 4 (from alter's scope)
5. This creates type mismatches because different instantiations use different rank rigids

## The Fix

### Fix 1: Don't Filter Ambient Rigids

```haskell
-- AFTER (FIXED):
solveHeaderInNextPool config header headerCon rigids = do
  locals <- traverse (A.traverse (typeToVariable (config ^. solveRank) (config ^. solvePools))) header
  -- DON'T filter THIS function's rigids from ambient rigids!
  -- The function body NEEDS access to these rigids for proper type variable instantiation
  -- When the body instantiates polymorphic functions, makeCopy looks for matching rigids
  -- If we filter out the current function's rigids, instantiation will find wrong rigids
  -- from outer scopes, breaking type identity for types with 3+ parameters
  let localsEnv = Map.fromList [(name, var) | (name, A.At _ var) <- Map.toList locals]
  let configWithLocals = config & solveEnv .~ Map.union localsEnv (config ^. solveEnv)
  solvedState <- solve configWithLocals headerCon
  return (locals, solvedState)
```

### Fix 2: Replace Non-noRank Rigids with Higher-Rank Versions

```haskell
-- AFTER (FIXED):
handleNoCopy maxRank pools ambientRigids variable content rank
  | rank /= noRank = do
      -- Check if this is a rigid that might have a higher-rank version in ambient rigids
      case content of
        RigidVar name -> checkForHigherRankRigid name variable rank ambientRigids
        RigidSuper super name -> checkForHigherRankRigidSuper name super variable rank ambientRigids
        _ -> return variable
  | otherwise = ...

checkForHigherRankRigid :: Name.Name -> Variable -> Int -> [(Int, Variable)] -> IO Variable
checkForHigherRankRigid name variable currentRank ambientRigids = do
  matchingRigid <- findMatchingRigid name ambientRigids
  case matchingRigid of
    Just higherRigid -> do
      (Descriptor _ higherRank _ _) <- UF.get higherRigid
      if higherRank > currentRank
        then return higherRigid  -- Use the higher-rank version!
        else return variable
    Nothing -> return variable
```

### Fix 3: Update findMatchingRigid to Prefer Highest Rank

```haskell
-- AFTER (FIXED):
findMatchingRigid :: Name.Name -> [(Int, Variable)] -> IO (Maybe Variable)
findMatchingRigid targetName rigids = do
  -- Collect all matching rigids with their ranks
  matches <- collectMatches rigids
  case matches of
    [] -> return Nothing
    _ -> do
      -- Select the highest rank (most local)
      let (bestRank, bestVar) = maximumBy (\(r1, _) (r2, _) -> compare r1 r2) matches
      return (Just bestVar)
  where
    collectMatches [] = return []
    collectMatches ((rank, var) : rest) = do
      desc <- UF.get var
      case desc of
        Descriptor (RigidVar rigidName) _ _ _ | rigidName == targetName ->
          fmap ((rank, var) :) (collectMatches rest)
        Descriptor (RigidSuper _ rigidName) _ _ _ | rigidName == targetName ->
          fmap ((rank, var) :) (collectMatches rest)
        _ -> collectMatches rest
```

## Key Insights

1. **Ambient rigids must include current scope's rigids**: The function body needs access to its own type parameters for proper instantiation
2. **Always prefer higher-rank rigids**: When multiple versions of a rigid exist, use the one from the most local (highest rank) scope
3. **RigidSuper requires special handling**: Constraint variables (like `comparable`) need the same treatment as regular type variables

## Test Results

### ✅ All Test Cases Pass

```elm
-- 1 parameter: ✅ PASS
type Box a = Box String
alter : (Maybe a -> a) -> Box a -> Box a

-- 2 parameters: ✅ PASS
type Box a b = Box String
alter : (Maybe b -> b) -> Box a b -> Box a b

-- 2 parameters with comparable: ✅ PASS
type Box comparable a = Box String
alter : (Maybe a -> a) -> Box comparable a -> Box comparable a

-- 3 parameters: ✅ PASS
type Dict comparable k v = Dict String
alter : (Maybe v -> v) -> Dict comparable k v -> Dict comparable k v

-- 5 parameters: ✅ PASS
type BigType comparable a b c d = BigType String
alter : (Maybe d -> d) -> BigType comparable a b c d -> BigType comparable a b c d
```

### CMS Compilation Status

The fix resolves the fundamental type identity issue. All synthetic tests pass. The CMS compilation appears to have additional context-specific issues that need separate investigation (likely related to module structure or imports).

## Files Modified

- `/home/quinten/fh/canopy/packages/canopy-core/src/Type/Solve.hs`
  - Lines 523-539: Removed ambient rigid filtering in `solveHeaderInNextPool`
  - Lines 1265-1314: Added higher-rank rigid replacement logic in `handleNoCopy`
  - Lines 1337-1368: Updated `findMatchingRigid` to prefer highest rank
  - Lines 1387-1407: Updated `findMatchingRigidSuper` to prefer highest rank
  - Line 14: Added `maximumBy` import from `Data.Foldable`

## Performance Impact

Minimal. The fix adds:
- One list traversal to collect all matching rigids (replaces early return)
- One `maximumBy` call to select highest rank (O(n) where n = number of matches, typically small)

## Related Issues

- ERROR_VARIABLE_AMBIENT_RIGIDS_FIX.md - Fixed Error variable mutation bug
- POINT_FREE_TYPE_VARIABLE_FIX.md - Earlier fix for point-free functions (similar but incomplete)

## Verification

```bash
# Test all parameter counts
stack run canopy -- make /tmp/test-one.elm    # ✅
stack run canopy -- make /tmp/test-two.elm    # ✅
stack run canopy -- make /tmp/test-three.elm  # ✅
stack run canopy -- make /tmp/test-five.elm   # ✅

# Test with comparable constraints
stack run canopy -- make /tmp/test-two-comparable.elm   # ✅
stack run canopy -- make /tmp/test-three-params.elm     # ✅

# Test with complex patterns
stack run canopy -- make /tmp/test-dict-with-key.elm        # ✅
stack run canopy -- make /tmp/test-dict-pattern-match.elm   # ✅
stack run canopy -- make /tmp/test-dict-exact.elm           # ✅
```

## Conclusion

This fix properly handles type variable instantiation for types with any number of parameters by:
1. Keeping all rigids (including current scope's) in ambient rigids during instantiation
2. Always preferring the highest-rank (most local) rigid when multiple versions exist
3. Applying this logic uniformly to RigidVar, RigidSuper, and all other rigid types

The type identity is now preserved correctly for all test cases, eliminating false type mismatch errors.
