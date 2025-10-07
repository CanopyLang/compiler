# Generalized Type Instantiation Bug Fix

## Problem Summary

When instantiating generalized (polymorphic) types, the type checker was incorrectly unifying quantified type variables with ambient rigids from the generalized function's own definition, rather than creating fresh type variables.

## Symptoms

### Broken Case 1: Endpoint
```elm
endpoint : List String -> Endpoint has
endpoint segments = Endpoint "test"

aiImageEdit : Endpoint (HasPost {})
aiImageEdit =
    endpoint [ "test" ]  -- Error: produces Endpoint has instead of Endpoint (HasPost {})
```

The type variable `has` from `endpoint`'s signature was incorrectly unifying with an ambient rigid named `has` from `endpoint`'s own definition.

### Broken Case 2: Dict.alter
```elm
alter : k -> (Maybe v -> v) -> Dict comparable k v -> Dict comparable k v
alter k f dict =
    insert k (f (get k dict)) dict  -- Error: type mismatch on identical types
```

After the initial fix (passing empty ambient rigids), this case broke because it needs to find its own function parameters in ambient rigids.

## Root Cause

The issue occurred in two places:

1. **During generalization**: When a function with type parameters (rigids) is generalized to rank 0, those rigids are added to the ambient rigids list at their original rank (e.g., rank 2).

2. **During instantiation**: When later instantiating that generalized function (via `makeCopy`), the `copyRigidVarContent` function would find the function's own rigids still in the ambient rigids list and incorrectly unify with them.

The fundamental problem: **After generalizing a function, its own type parameters remained in the ambient rigids list for subsequent module-level code, causing incorrect unification when that function was later instantiated.**

## The Fix

**Location**: `/home/quinten/fh/canopy/packages/canopy-core/src/Type/Solve.hs`, lines 595-607

After early generalization of module-level functions, we filter the ambient rigids list to remove rigids from the generalized function's rank:

```haskell
-- CRITICAL FIX: After generalizing, remove THIS function's rigids from ambient rigids
-- When a function is generalized to rank 0, its type parameters are no longer "ambient"
-- to subsequent code - they're quantified variables of the generalized function.
-- If we keep them in ambient rigids, later instantiations will incorrectly unify with them.
let currentAmbientRigids =
      if shouldGeneralizeEarly
      then
        -- Remove rigids that belong to THIS function (nextRank)
        -- These rigids are now generalized and should not be in ambient rigids for subsequent code
        [(rank, var) | (rank, var) <- config ^. solveAmbientRigids, rank /= nextRank]
      else
        config ^. solveAmbientRigids
```

This ensures that when subsequent code (like `aiImageEdit`) instantiates the generalized function (`endpoint`), the ambient rigids list does NOT contain the generalized function's own type parameters.

## Why This Works

### For the Endpoint case:
- `endpoint` is generalized at rank 2
- Its rigid `has` is at rank 2 in ambient rigids
- **With fix**: When solving `aiImageEdit`, ambient rigids are filtered to exclude rank 2
- Result: `has` becomes a fresh FlexVar ✓

### For the Dict case:
- `alter` function parameters (`comparable`, `k`, `v`) are at rank 4
- When instantiating `get` and `insert` inside `alter`, we need rank 4 rigids
- **With fix**: The current function's rigids (rank 4) are NOT filtered out during the function's own body
- Result: Type parameters correctly unify with function parameters ✓

## Key Insights

1. **Ambient rigids represent the current typing context**: They should only include type variables from OUTER scopes that are currently in effect, not from functions that have been generalized.

2. **Generalization changes the meaning of rigids**: When a function is generalized, its type parameters become quantified variables that should create fresh instances on each use, not unify with the original rigids.

3. **Filtering must happen after generalization**: The fix filters ambient rigids AFTER early generalization but BEFORE solving subsequent code, ensuring clean separation between generalized functions.

## Test Cases

### Test 1: Endpoint (simplified)
```elm
type Endpoint has = Endpoint String

endpoint : List String -> Endpoint has
endpoint segments = Endpoint "test"

aiImageEdit : Endpoint (HasPost {})
aiImageEdit = endpoint [ "test" ]  -- Now works! ✓
```

### Test 2: Dict (simplified)
```elm
type Dict comparable k v = Dict String

get : k -> Dict comparable k v -> Maybe v
insert : k -> v -> Dict comparable k v -> Dict comparable k v

alter : k -> (Maybe v -> v) -> Dict comparable k v -> Dict comparable k v
alter k f dict = insert k (f (get k dict)) dict  -- Now works! ✓
```

### Test 3: Full CMS compilation
The fix allows the CMS project to compile much further, successfully handling both the Api/Endpoint.elm and Dict/Custom.elm modules that were previously failing.

## Related Code

- `finalizeLetSolving`: Where the fix is applied (lines 544-707)
- `copyRigidVarContent`: Where type variable instantiation happens (lines 1347-1360)
- `findMatchingRigid`: Finds matching rigids in ambient rigids list (lines 1364-1387)

## Conclusion

This fix properly implements the semantic distinction between:
1. **Ambient rigids from outer scopes** (should be available for unification)
2. **Quantified variables from generalized types** (should become fresh variables on instantiation)

By filtering out a generalized function's own rigids from the ambient rigids list passed to subsequent code, we ensure correct type variable instantiation semantics matching the Elm compiler's behavior.
