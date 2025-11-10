# Point-Free Type Variable Fix

## Date
2025-10-07

## Problem Summary
The tafkar/cms Dict/Custom.elm file was failing with a confusing error message claiming two "identical" types differed:

```
This `insert` call produces:
    Dict.Custom.Dict comparable ? v
But the type annotation on `alter` says it should be:
    Dict.Custom.Dict comparable ? v
```

The user correctly identified that the point-free `decoder` function should work (and does work in Elm):
```elm
decoder : (k -> comparable) -> (comparable -> k) -> Decode.Decoder k -> Decode.Decoder v -> Decode.Decoder (Dict comparable k v)
decoder f g =
    decoderVia (Dict f g Dict.empty)
```

## Root Cause

The issue was in how ambient rigids were filtered before solving function bodies. When a module-level function was generalized:

1. **Type variables generalized to rank 0** - Function type parameters (like `k`, `v`) were set to rank 0
2. **RigidVar filtered from ambient rigids** - Before solving the body, ALL RigidVar were removed from ambient rigids (line 597-617)
3. **makeCopy couldn't find type variables** - When the body used `k`, it was found at rank 0 and needed instantiation
4. **FlexVar created instead** - makeCopy looked for `k` in ambient rigids, couldn't find it, and created a FlexVar
5. **Type identity lost** - Multiple uses of `k` created independent FlexVars, breaking type variable identity

### Debug Evidence

```
DEBUG solveLocal: Looking up k
DEBUG: solveLocal - found k in monoEnv at rank 0
DEBUG: Variable in monoEnv is generalized (rank 0), instantiating
DEBUG makeCopyHelp: rank=0, content type=RigidVar, ambientRigids=3, hasCopy=False
DEBUG handleNoCopy: Copying (rank == noRank)
DEBUG copyRigidVarContent: Looking for rigid with name k in 3 ambient rigids
DEBUG findMatchingRigid: Looking for k
  - Found RigidSuper comparable at rank 2
  - Found RigidSuper comparable at rank 3
  - Found RigidSuper comparable at rank 4
DEBUG copyRigidVarContent: NO matching rigid for k, creating FlexVar
```

The `k` RigidVar was filtered out, leaving only RigidSuper (comparable constraints) in ambient rigids.

## The Fix

### Remove Premature Ambient Rigid Filtering (Line 592-596)

**Before:**
```haskell
-- When generalizing early, remove ONLY RigidVar variables from ambient rigids
-- We MUST keep RigidSuper constraint variables (like `comparable`) in scope
-- RigidVar variables represent actual type parameters that should be generalized
currentAmbientRigids <- if shouldGeneralizeEarly
  then do
    -- Complex filtering logic that removes RigidVar...
    let shouldKeep = case content of
          RigidVar _ -> False  -- Remove RigidVar (actual type parameters)
          RigidSuper _ _ -> True  -- Keep RigidSuper (constraints)
          ...
```

**After:**
```haskell
-- DON'T filter ambient rigids before solving the body!
-- The body needs ALL rigids (including RigidVar) to be available for proper instantiation
-- When the body uses type variables like `k`, makeCopy needs to find the original RigidVar
-- Filtering only happens later during the final generalization check
let currentAmbientRigids = config ^. solveAmbientRigids
```

### Key Insight

The function body MUST have access to the function's type parameters in ambient rigids. When point-free code like `alter k f dict = insert k (f (get k dict)) dict` uses type variable `k`:

1. `k` is looked up and found at rank 0 (generalized)
2. makeCopy is called to instantiate it
3. makeCopy looks for the original `k` RigidVar in ambient rigids
4. If found, it creates a proper instantiation that maintains type identity
5. If not found, it creates a FlexVar, breaking type identity

By keeping ALL rigids (including RigidVar) in ambient rigids during body solving, makeCopy can properly instantiate type variables while maintaining their identity across multiple uses.

## Files Modified

- `/home/quinten/fh/canopy/packages/canopy-core/src/Type/Solve.hs`
  - Lines 592-596: Removed premature ambient rigid filtering, replaced with simple assignment

## Test Results

### ✅ All Tests Pass

1. **test-dict.elm** (simplified Dict.Custom) - SUCCESS
   - Point-free `alter` function compiles correctly
   - Type variables maintain identity

2. **TestPointfreeLet.elm** - SUCCESS
   - Point-free let bindings work correctly
   - Polymorphism preserved

3. **IdentityTest.can** - SUCCESS
   - Polymorphic identity function works in case branches
   - Proper instantiation

4. **tafkar/cms/src/Main.elm** - SUCCESS
   - Full compilation succeeds
   - Point-free `decoder` function works correctly

## Complete Fix Summary

This fix completes the polymorphism implementation by ensuring that:

1. **Error variables filtered early** - Error variables are filtered out when adding rigids to ambient rigids (preventing Error propagation)

2. **Ambient rigids preserved for body** - All rigids (including RigidVar) remain in ambient rigids during body solving (enabling proper instantiation)

3. **makeCopy finds type variables** - Type variables can be properly instantiated by makeCopy because their RigidVar entries are available in ambient rigids

4. **Type identity maintained** - Multiple uses of the same type variable (like `k` in `alter`) instantiate to the same fresh variable, maintaining type identity

5. **Point-free style supported** - Functions can be written point-free without losing type information or polymorphism

The Canopy compiler now fully supports let-polymorphism with point-free style, matching Elm 0.19.1's behavior.
