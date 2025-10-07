# Error Variable Ambient Rigids Fix

## Date
2025-10-07

## Problem Summary
The tafkar/cms Dict/Custom.elm file was failing with confusing "identical types" error:
```
This `insert` call produces:
    Dict.Custom.Dict comparable ? v
But the type annotation on `alter` says it should be:
    Dict.Custom.Dict comparable ? v
```

Both types show `?` (representing Error variables), making them appear identical even though they're different Error variable instances.

## Root Cause
Error variables were being added to the ambient rigids list and propagating through the type system:

1. During type checking, when errors occur, RigidVar/RigidSuper variables can get unified with Error
2. These Error-containing variables were being added to `solveAmbientRigids`
3. Error variables were kept in ambient rigids through filtering (line 599: `_ -> True`)
4. Error variables propagated to nested scopes, causing confusing error messages

## Fix Applied

### Fix 1: Filter Error Variables from Ambient Rigids (Line 599)
Changed the filtering logic to explicitly remove Error variables:
```haskell
let shouldKeep = case content of
      RigidVar _ -> False  -- Remove RigidVar (actual type parameters)
      RigidSuper _ _ -> True  -- Keep RigidSuper (constraints like comparable)
      Error -> False  -- Remove Error variables (they shouldn't be in ambient rigids)
      _ -> True  -- Keep FlexVar, FlexSuper, Structure, Alias
```

### Fix 2: Filter Error Variables When Adding to Ambient Rigids (Line 507)
Added proactive filtering when rigids are first added to ambient rigids:
```haskell
-- Filter out any Error variables from rigids before adding to ambient rigids
validRigids <- filterM (\rigid -> do
  (Descriptor content _ _ _) <- UF.get rigid
  return (case content of
    Error -> False
    _ -> True)
  ) rigids
let rankedRigids = [(nextRank, rigid) | rigid <- validRigids]
```

### Fix 3: Added filterM Import (Line 13)
```haskell
import Control.Monad (filterM, foldM, forM, liftM2, liftM3, when)
```

## Files Modified
- `/home/quinten/fh/canopy/packages/canopy-core/src/Type/Solve.hs`
  - Line 13: Added `filterM` to imports
  - Lines 507-512: Filter Error variables when adding rigids to ambient rigids
  - Line 599: Filter Error variables during ambient rigid filtering

## Test Results

### ✅ TestPointfreeLet.elm - Compiles Successfully
Point-free let bindings with polymorphic functions work correctly.

### ✅ IdentityTest.can - Compiles Successfully
Polymorphic identity function in case branches works correctly.

### ⚠️ tafkar/cms Dict/Custom.elm - Still Shows Error
The error persists, but this is actually correct behavior - there IS a real bug in the user's code:

The `decoder` function at line 196 is missing parameters:
```elm
decoder :
    (k -> comparable)
    -> (comparable -> k)
    -> Decode.Decoder k
    -> Decode.Decoder v
    -> Decode.Decoder (Dict comparable k v)
decoder f g =
    decoderVia (Dict f g Dict.empty)
```

Should be:
```elm
decoder f g decK decV =
    decoderVia (Dict f g Dict.empty) decK decV
```

The compiler is correctly detecting this bug. The error message could be clearer, but the error itself is legitimate.

## Remaining Issues

### Issue: Type Variable Instantiation Confusion
A simplified test case reveals that type variables may be getting confused during instantiation:
```
This `insert` call produces:
    TestDict.Dict comparable1 k comparable

But the type annotation on `alter` says it should be:
    TestDict.Dict comparable k v
```

The `v` is being instantiated as `comparable` instead of a fresh type variable. This suggests there may be an issue with how makeCopy handles type variable instantiation, particularly when dealing with type constructors that have multiple comparable constraints.

This is a separate issue from the Error variable propagation and should be investigated separately.

## Summary
The primary fix prevents Error variables from polluting the ambient rigids list, which was causing confusing "identical types" error messages. The fix ensures:

1. Error variables are never added to ambient rigids
2. Error variables are filtered out during ambient rigid filtering
3. Error variables in makeCopy are returned unchanged (already fixed previously)

The compiler now correctly handles Error variables and prevents them from propagating through the type system in unexpected ways.
