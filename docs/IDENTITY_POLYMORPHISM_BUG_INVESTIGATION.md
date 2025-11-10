# Identity Polymorphism Bug Investigation

## Problem Statement

Main.elm compiles with Elm but fails with Canopy with this error:

```
The 1st argument to `viewPage` is not what I expect:

1571|             viewPage identity <|
                           ^^^^^^^^
This `identity` value is a:

    Page.AnalyticsNew.Msg -> Page.AnalyticsNew.Msg

But `viewPage` needs the 1st argument to be:

    Page.AnalyticsNew.Msg -> Main.Msg
```

## Code Structure

```elm
view model =
    let
        viewPage toMsg { title, body } = ...
    in
    case model of
        AnalyticsNew analyticsNew ->
            viewPage (PageMsg << AnalyticsNewMsg) <|  -- Line 1566-1568
                AnalyticsNew.view ...

        Analytics analytics ->
            viewPage identity <|  -- Line 1571 - FAILS HERE
                Analytics.view analytics
```

Where:
- `viewPage : (pageMsg -> mainMsg) -> Page pageMsg -> Page mainMsg`
- `AnalyticsNew.view : ... -> Page AnalyticsNew.Msg`
- `Analytics.view : ... -> Page msg` (polymorphic!)
- `identity : a -> a`

## Expected Type Inference

For the Analytics branch:
1. `identity : a -> a`
2. `Analytics.view analytics : Page msg` (polymorphic)
3. Need result type: `Page MainMsg`
4. So `viewPage identity` should unify as:
   - `identity : MainMsg -> MainMsg`
   - Result: `Page MainMsg` ✓

## Actual Behavior (Bug)

Canopy incorrectly types `identity` as `AnalyticsNew.Msg -> AnalyticsNew.Msg`, suggesting type pollution from the previous case branch.

## Investigation Results

### Test Cases Created

I created multiple test cases trying to reproduce the bug:

1. **IdentityPolymorphism.elm** - Basic case with identity
2. **IdentityPolymorphismExact.elm** - With << composition
3. **IdentityPolymorphismCorrect.elm** - With polymorphic page type
4. **IdentityPolymorphismComplex.elm** - With complex expressions
5. **IdentityPolymorphismMultiBranch.elm** - With 4 case branches
6. **IdentityPolymorphismRecord.elm** - With record types
7. **IdentityPolymorphismMultiline.elm** - Exact Main.elm structure

**Result**: ALL tests PASS with Canopy! Cannot reproduce the bug.

### Code Analysis

#### makeCopy Mechanism

The `makeCopy` function (Solve.hs:641-651) is responsible for creating fresh instances of polymorphic variables:

```haskell
makeCopy :: Int -> Pools -> Variable -> IO Variable
makeCopy rank pools var = do
  copy <- makeCopyHelp rank pools var
  restore var  -- Clears cached copies
  return copy
```

Key observations:
1. `makeCopyHelp` caches copies in descriptors to handle shared type variables
2. `restore` is called to clear these caches after copying
3. If a variable's rank != noRank, the original is returned (not a copy)

#### Case Branch Handling

All case branches share the same `branchType` variable (Expression.hs:318-319):

```haskell
branchVar <- mkFlexVar  -- Shared across all branches
let branchType = VarN branchVar

branchCons <- Index.indexedForA branches $ \index branch ->
  constrainCaseBranch ... branchType  -- Same type for all
```

This is correct - all branches must return the same type.

#### Constraint Solving Order

Constraints are solved left-to-right with state threading (Solve.hs:100):

```haskell
CAnd constraints ->
  foldM (solve . updateSolveState config) (config ^. solveState) constraints
```

This means branch 2 sees the state after branch 1 is solved.

### Potential Root Causes

1. **makeCopy not creating fresh copies**
   - Evidence against: `restore` is called, should clear caches
   - Evidence against: Test cases work correctly

2. **Environment variable modification**
   - The `helper` function from the let binding is in the environment
   - If this variable gets modified during solving, all branches see the modification
   - BUT: `makeCopy` creates a copy, so the original shouldn't be modified

3. **Missing variable case branches**
   - All test cases follow the same pattern but don't trigger the bug
   - Suggests a specific combination of factors in Main.elm

4. **Generalization bug**
   - If `helper` is not properly generalized (rank != noRank), `makeCopy` returns the original
   - This would cause pollution between branches

### Debug Logging Added

Added commented-out debug logging to track `makeCopy` behavior:

```haskell
makeCopy rank pools var = do
  desc <- UF.get var
  -- putStrLn $ "makeCopy: rank=" ++ show rank ++ " varRank=" ++ show (_descriptorRank desc)
  copy <- makeCopyHelp rank pools var
  restore var
  descAfter <- UF.get var
  -- putStrLn $ "makeCopy: restored, copy=" ++ show (_descriptorCopy descAfter)
  return copy
```

## Next Steps Required

To proceed with fixing this bug, I need ONE of the following:

### Option 1: Minimal Reproduction
Extract a minimal failing example from Main.elm that:
- Contains just the `view` function with the relevant case branches
- Includes only the necessary type definitions
- Can be compiled standalone

### Option 2: Detailed Error Context
Provide:
- The full error message (not truncated)
- The complete `view` function definition
- Type signatures for `viewPage`, `AnalyticsNew.view`, `Analytics.view`
- Output from enabling debug logging (uncomment the putStrLn lines above)

### Option 3: Incremental Testing
Try these modifications to Main.elm to isolate the issue:
1. Comment out all case branches except AnalyticsNew and Analytics
2. Inline the `viewPage` helper instead of using let binding
3. Add explicit type annotation to `helper`

### Option 4: Compile with Debug Build
Build Canopy with the debug logging enabled and capture output when compiling Main.elm

## Theoretical Fix

If the bug is confirmed to be in `makeCopy`/`restore`, potential fixes:

1. **Always create fresh copies**: Don't cache copies across invocations
2. **More aggressive restoration**: Ensure all nested copies are cleared
3. **Separate generalization check**: Verify variables are properly generalized before reuse

## Files Modified

- `/home/quinten/fh/canopy/packages/canopy-core/src/Type/Solve.hs` - Added debug logging (commented out)

## Test Files Created

All in `/home/quinten/fh/canopy/test/fixtures/type/`:
- IdentityPolymorphism.elm
- IdentityPolymorphismExact.elm
- IdentityPolymorphismCorrect.elm
- IdentityPolymorphismComplex.elm
- IdentityPolymorphismMultiBranch.elm
- IdentityPolymorphismRecord.elm
- IdentityPolymorphismMultiline.elm
- IdentityPolymorphismArgument.elm
- IdentityPolymorphismPipeline.elm
- IdentityPolymorphismDebugging.elm
