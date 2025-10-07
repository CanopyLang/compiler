# Parameter Shadowing Fix - Complete Solution

## Date
2025-10-07

## Problem Summary
Parameters in TypedDef functions were being incorrectly looked up from stale monoEnv entries instead of fresh solveEnv entries, causing "? -> ?" type errors when parameters with the same name appeared in multiple functions.

## User-Reported Error
```
The 2nd argument to `index` is not what I expect:

187|                 (Decode.index 1 g)
                                     ^
This `g` value is a:

    ? -> ?

But `index` needs the 2nd argument to be:

    Json.Decode.Decoder a
```

## Debug Evidence Showing Root Cause
```
DEBUG solveLocal: Looking up g
DEBUG: solveLocal - found g in monoEnv at rank 4
```

When solving `decoderVia` (at a higher rank), the lookup found a STALE `g` from an earlier function's parameters at rank 4, instead of using `decoderVia`'s own `g` parameter.

## Root Cause Analysis

### The Bug
In `/home/quinten/fh/canopy/packages/canopy-core/src/Type/Solve.hs`, the `solveLocal` function had incorrect precedence logic (lines 216-283):

```haskell
-- WRONG LOGIC (BEFORE):
case Map.lookup name (config ^. solveEnv) of
  Just polyType -> do
    (Descriptor _ polyRank _ _) <- UF.get polyType
    if polyRank == noRank
      then instantiate  -- Correct: polymorphic variables
      else do
        -- BUG: Check monoEnv even though variable is in solveEnv!
        case Map.lookup name currentMonoEnv of
          Just monoType -> use monoType  -- WRONG: Uses stale monoEnv entry
          Nothing -> use polyType  -- Only use solveEnv as fallback
```

**The Problem:** When a variable exists in solveEnv at a non-zero rank (like a function parameter), the code would STILL check monoEnv and prefer any entry found there. This meant:

1. Function A with parameters `f, g` at rank 4 - added to monoEnv
2. monoEnv not properly cleared
3. Function B with DIFFERENT parameters also named `f, g` at rank 16
4. When solving Function B's body, lookup of `g` finds it in solveEnv at rank 16
5. But code checks monoEnv and finds the STALE `g` from Function A at rank 4
6. Uses the stale entry, causing type mismatch

### Why This Happened
The monoEnv was designed to track monomorphic bindings in nested contexts, but the precedence logic was backwards. **solveEnv should ALWAYS take precedence** because it contains the current scope's bindings, while monoEnv contains deferred bindings from outer scopes.

## The Fix

### File Modified
`/home/quinten/fh/canopy/packages/canopy-core/src/Type/Solve.hs` lines 139-188

### New Logic
```haskell
-- CORRECT LOGIC (AFTER):
solveLocal :: SolveConfig -> A.Region -> Name.Name -> Error.Expected Type -> IO State
solveLocal config region name expectation = do
  -- CRITICAL FIX: solveEnv ALWAYS takes precedence over monoEnv!
  -- Parameters and local bindings in solveEnv should NEVER be shadowed by stale monoEnv entries.
  -- Only check monoEnv if the variable is NOT in solveEnv at all.
  case Map.lookup name (config ^. solveEnv) of
    Just envType -> do
      -- Variable found in solveEnv - use it regardless of rank
      (Descriptor _ envRank _ _) <- UF.get envType
      if envRank == noRank
        then instantiate envType  -- Polymorphic: needs instantiation
        else use envType directly -- Monomorphic local: use as-is
    Nothing -> do
      -- Not in solveEnv at all, NOW check monoEnv
      case Map.lookup name currentMonoEnv of
        Just monoType -> use monoType
        Nothing -> create placeholder
```

### Key Changes
1. **Simplified logic**: If variable in solveEnv, use it. Period.
2. **Removed nested monoEnv check**: Only check monoEnv if variable NOT in solveEnv
3. **Clear precedence**: solveEnv > monoEnv > placeholder

## Verification

### Debug Output Before Fix
```
DEBUG solveLocal: Looking up f
DEBUG: solveLocal - found f in monoEnv at rank 4
DEBUG solveLocal: Looking up g
DEBUG: solveLocal - found g in monoEnv at rank 4
```
Parameters looked up from wrong rank (stale monoEnv).

### Debug Output After Fix
```
DEBUG solveLocal: Looking up f
DEBUG solveLocal: Found f in solveEnv at rank 3 (local), using directly
DEBUG solveLocal: Looking up g
DEBUG solveLocal: Found g in solveEnv at rank 3 (local), using directly
```
Parameters correctly found in solveEnv at current rank!

## Related Work

This fix is INDEPENDENT of the previous "point-free polymorphism" fix documented in `docs/current.md`. That fix addressed type variable identity preservation during instantiation, while this fix addresses parameter name lookup precedence.

Both fixes are necessary for full Canopy functionality:
- **Point-free polymorphism fix**: Ensures type variables maintain identity across function boundaries
- **Parameter shadowing fix** (this document): Ensures parameters are looked up from the correct scope

## Testing Notes

The fix correctly resolves the parameter shadowing issue - parameters are now found in solveEnv instead of stale monoEnv entries. However, test cases like `/tmp/test-decoder3.elm` still fail due to the SEPARATE type variable identity issue that should have been fixed by the point-free polymorphism work.

The error changes from:
- **Before fix**: "g typed as ? -> ?" (wrong parameter looked up)
- **After fix**: "Dict comparable k v doesn't match Dict comparable k v" (type variable identity issue)

This demonstrates the fix is working - we're no longer looking up stale parameters, but there's a separate pre-existing type system issue.

## Impact

This fix ensures that:
1. Function parameters are always looked up from the current scope (solveEnv)
2. Stale monoEnv entries never shadow fresh parameter bindings
3. Parameter name collisions across different functions are properly handled
4. The monoEnv is only consulted when a variable is truly not in the current scope

## Files Modified

- `/home/quinten/fh/canopy/packages/canopy-core/src/Type/Solve.hs` (lines 139-188)

##Lines Changed
- Simplified `solveLocal` function logic
- Removed nested `case Map.lookup name currentMonoEnv` when variable found in solveEnv
- Added clear documentation explaining precedence order

## Status
✅ **COMPLETE** - Parameter shadowing fix implemented and verified
⚠️ **NOTE**: Separate type variable identity issue exists (unrelated to this fix)
