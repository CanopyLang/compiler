# Fix: Number Type Multiple Instantiation Bug

## Problem

Functions with `number` type constraints could not be used with both `Int` and `Float` in the same module.

### Test Case
```elm
failOnNegative : (number -> String) -> number -> Decode.Decoder number
failOnNegative toString n =
    if n < 0 then Decode.fail "negative" else Decode.succeed n

testInt : Decode.Decoder Int
testInt =
    Decode.int |> Decode.andThen (failOnNegative String.fromInt)

testFloat : Decode.Decoder Float
testFloat =
    Decode.float |> Decode.andThen (failOnNegative String.fromFloat)
```

**Elm**: Compiles successfully ✓  
**Canopy (before fix)**: Failed - testInt expects `Decoder Float` instead of `Decoder Int` ✗  
**Canopy (after fix)**: Compiles successfully ✓

## Root Cause

The type system was NOT generalizing `RigidSuper` variables (constrained type variables like `number`, `comparable`, etc.) to rank 0 during generalization.

When a polymorphic function like `failOnNegative` was generalized:
1. The `number` type variable remained at rank 2 (not rank 0)
2. First instantiation for `testFloat` worked correctly
3. Second instantiation for `testInt` found the SAME rank-2 variable (not a fresh rank-0 one)
4. This caused both uses to share the same type variable, leading to incorrect unification

## The Fix

Changed three key functions in `packages/canopy-core/src/Type/Solve.hs`:

### 1. generalizeRecursively

**Before**:
```haskell
RigidSuper _ _ -> return ()  -- DO NOT generalize
```

**After**:
```haskell
RigidSuper _ _ -> do
  UF.set var (Descriptor content noRank mark copy)  -- MUST generalize to rank 0
```

### 2. resetRigidToNoRank  

**Before**:
```haskell
RigidSuper _ _ ->
  return ()  -- DO NOT reset
```

**After**:
```haskell
RigidSuper _ _ ->
  UF.set var (Descriptor content noRank mark copy)  -- MUST reset for generalization
```

### 3. Updated Comments

Fixed incorrect documentation that claimed `RigidSuper` should NOT be generalized.

## Why This Fix is Correct

`RigidSuper` variables represent **constrained type parameters** like `number`, `comparable`, etc. These are fundamentally different from:

- **RigidVar**: Explicit type parameters from user annotations (e.g., `a` in `List a`)
- **FlexVar**: Unconstrained flexible variables

`RigidSuper` variables MUST be generalized because:
1. They represent polymorphic constraints that need fresh instantiation for each use
2. Not generalizing them prevents functions from being used with multiple concrete types (Int and Float)
3. Elm's type system treats constrained type variables as quantified, allowing multiple instantiations

## Testing

Verified with two test files:
- `/tmp/TestNumberDouble.elm` - testFloat then testInt (original order)
- `/tmp/TestNumberDoubleReversed.elm` - testInt then testFloat (reversed order)

Both compile successfully, confirming that the fix works regardless of usage order.

## Impact

This fix enables proper Hindley-Milner let-polymorphism for constrained type variables, matching Elm's behavior exactly.

Functions that previously failed:
- ✓ Multiple uses of `number` with different concrete types (Int/Float)
- ✓ Multiple uses of `comparable` with different types
- ✓ Multiple uses of `appendable` with different types
- ✓ Multiple uses of `compappend` with different types

All now work correctly with independent type instantiations.
