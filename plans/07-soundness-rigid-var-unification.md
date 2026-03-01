# Plan 07: Rigid Variable Unification Fix

**Priority:** CRITICAL
**Effort:** Medium (1–3 days)
**Risk:** High — changes to the type checker require careful testing

## Problem

`Type/Unify.hs:219–227` allows two distinct rigid type variables to unify based on **name equality** instead of **identity (same union-find node)**. This violates Hindley-Milner: two different universally quantified variables with the same name `a` (from different `CLet` scopes) will incorrectly unify.

```haskell
RigidVar otherName ->
  case content of
    RigidVar thisName | thisName == otherName ->
      merge context content    -- UNSOUND: name-based, not identity-based
    _ -> mismatch
```

The test at `test/Unit/Type/UnifyTest.hs:255–259` validates this unsound behavior by asserting that two independently-created `RigidVar "a"` nodes should unify.

## Root Cause Analysis

The comment says this "fixes the bug where identical types like `Array a` with `RigidVar a` could not unify with themselves." This suggests the real issue is in how types are instantiated or compared during constraint solving, not in unification itself. Two occurrences of the same rigid `a` within a single `CLet` scope should already be the **same union-find node** — if they're not, the bug is in how `constrainAnnotatedDef` sets up rigid variables.

## Files to Modify

### `packages/canopy-core/src/Type/Unify.hs`

1. **Revert to identity-based unification** for rigid variables:
   ```haskell
   RigidVar _ ->
     -- Rigid variables only unify with themselves (same union-find node).
     -- Two distinct rigid vars with the same name from different CLet scopes
     -- must NOT unify.
     mismatch
   ```

2. **Understand why the "Array a" case failed**: Before reverting, add extensive debug logging to trace exactly what happens when `Array a` tries to unify with itself. The issue is likely that `makeCopy` in `Type/Solve/Pool.hs` creates separate copies of the same rigid variable when it shouldn't, or that `nameToRigid` is called twice for the same `a` when it should be called once.

### `packages/canopy-core/src/Type/Constrain/Expression/Definition.hs`

Investigate `constrainAnnotatedDef` (line ~94). Verify that all occurrences of `a` in a single type annotation map to the **same** `RigidVar` node. If `nameToRigid` is called multiple times for the same name, consolidate to a single call with the result shared.

### `packages/canopy-core/src/Type/Solve/Pool.hs`

Investigate `makeCopy` (line ~558). Check if rigid variables are being incorrectly duplicated during instantiation. A rigid variable should never be copied — it should remain the same physical node.

### `test/Unit/Type/UnifyTest.hs`

1. **Fix the unsound test** (line 255–259): Change to assert that two independently-created `RigidVar "a"` nodes do NOT unify
2. **Add soundness test**: Create a scenario where two different `CLet` scopes both have `a`, and verify they don't unify
3. **Add regression test**: The "Array a unifies with itself" scenario must still work after the fix — but via identity, not name

## Investigation Steps (before implementation)

1. Create a minimal Canopy program that would expose unsoundness:
   ```elm
   foo : a -> a
   foo x = x

   bar : a -> a
   bar x = foo x  -- The 'a' from foo and 'a' from bar should be independent
   ```
2. Trace through the constraint solver to verify both `a`s don't incorrectly interact
3. Create the "Array a" scenario the comment references and verify it works with identity-based unification

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Property tests for type system soundness: well-typed programs compile, ill-typed programs are rejected
4. The "Array a unifies with itself" case still works
5. Two functions with `a -> a` annotations don't cross-contaminate their type variables
