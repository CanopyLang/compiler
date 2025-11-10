# Type System Bug Fix Summary: Variable Mutation on Unification Failure

## Quick Summary

**Problem:** Type variables were being mutated to `Error` content with rank `0` when unification failed, causing valid code to fail type checking when the same variable was used multiple times.

**Solution:** Removed the destructive `UF.union v1 v2 errorDescriptor` call after failed unification. Error information is already extracted via `Type.toErrorType`, so mutation serves no purpose except to corrupt variables for subsequent use.

**Impact:** Parameters and variables can now be used multiple times without corruption. This fixes issues where valid code like `insert k (f (get k dict)) dict` would fail because `dict` was mutated after the first use.

## The Bug in One Picture

```
Before Fix:
First use of 'dict':  rank=4, content=Structure  ✓
Second use of 'dict': rank=0, content=Error      ✗ CORRUPTED!

After Fix:
First use of 'dict':  rank=4, content=Structure  ✓
Second use of 'dict': rank=4, content=Structure  ✓
```

## Code Change

**File:** `packages/canopy-core/src/Type/Unify.hs`

**Before:**
```haskell
t1 <- Type.toErrorType v1
t2 <- Type.toErrorType v2
UF.union v1 v2 errorDescriptor  -- ← Mutates variables!
return (Err vars t1 t2)
```

**After:**
```haskell
t1 <- Type.toErrorType v1
t2 <- Type.toErrorType v2
-- DON'T mutate - error info already extracted!
return (Err vars t1 t2)
```

## Why This Works

1. Error types are extracted BEFORE the mutation point
2. Returning `Err vars t1 t2` provides all necessary error information
3. Original variables remain valid for subsequent type checking
4. No side effects on error reporting or successful unification

## What Was Wrong

The `UF.union v1 v2 errorDescriptor` call was setting both variables to:
```haskell
Descriptor Error noRank noMark Nothing  -- rank forced to 0!
```

This broke subsequent uses of the same variable because:
1. Content changed from valid type to `Error`
2. Rank changed to `noRank` (0), breaking rank-based algorithms
3. Variable became unusable for further type checking

## Testing

All these now compile correctly:

```elm
-- Test 1: Parameter used twice
testTwice : a -> (a, a)
testTwice x = (f x, f x)

-- Test 2: Dict with repeated parameter
alter : k -> v -> Dict k v -> Dict k v
alter k v dict = insert k v dict

-- Test 3: Complex nested usage
alter : k -> (Maybe v -> v) -> Dict k v -> Dict k v
alter k f dict =
    let oldVal = get k dict
    in insert k (f oldVal) dict
```

## Related Documentation

See `DESCRIPTOR_ERROR_MUTATION_FIX.md` for comprehensive analysis, including:
- Detailed root cause analysis
- Complete validation strategy
- Impact on other error handling code
- Technical implementation details

## Key Insight

**Failed unification should NOT mutate variables!**

Error information is already captured via `Type.toErrorType`. Mutating the original variables only causes problems when they're used again, without providing any benefit for error reporting.
