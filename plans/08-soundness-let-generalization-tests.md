# Plan 08: Deferred Let-Generalization Property Tests

**Priority:** HIGH
**Effort:** Medium (1-2d)
**Risk:** Low -- purely additive test infrastructure, no production code changes

## Problem

The type solver's let-generalization has two paths -- standard and deferred --
governed by intricate boolean conditions.  The deferred path
(`finalizeDeferredLet`, `checkAndGeneralizeWithParent`) contains at least seven
distinct boolean predicates that interact in non-obvious ways, yet the existing
test suite (`test/Unit/Type/SolveTest.hs`) only exercises trivial cases: empty
`CLet`, single flex var, and `CTrue` bodies.  No existing test constructs a
`CLet` with rigid variables, ambient rigids, or expected types, so the deferred
path is effectively untested.

### Complex Boolean Logic Requiring Coverage

#### `finalizeLetSolving` (lines 450-458)

```haskell
-- /home/quinten/fh/canopy/packages/canopy-core/src/Type/Solve.hs:452-455
let hasAmbientRigids = not (null ambientRigids)
let hasExpectedType = maybe False (const True) expectedType
let shouldDefer = (config ^. solveDeferAllGeneralization)
               || hasAmbientRigids
               || hasExpectedType
```

Three independent conditions trigger deferral.  The standard path only runs
when all three are false.

#### `finalizeDeferredLet` (lines 464-497)

```haskell
-- /home/quinten/fh/canopy/packages/canopy-core/src/Type/Solve.hs:466-469
let hasOwnRigids = not (null rigids)
let isAtModuleLevel = null ambientRigids
let hasLocals = not (Map.null locals)
let isOriginalDefer = hasOwnRigids || isAtModuleLevel || hasLocals
```

Then `shouldGeneralizeEarly = isOriginalDefer` controls whether early
generalization occurs (lines 474-482), ambient rigid filtering (lines 483-486),
and the three-way branch at lines 493-497:

```haskell
if shouldGeneralizeEarly
  then finalizeEarlyGeneralized ...
  else if isOriginalDefer
    then finalizeOriginalDeferred ...
    else return bodyState
```

Note: since `shouldGeneralizeEarly = isOriginalDefer`, the `else if` branch
is dead code (if `shouldGeneralizeEarly` is false, `isOriginalDefer` is also
false).  This is either a latent bug or accidental dead code.

#### `checkAndGeneralizeWithParent` (lines 604-629)

```haskell
-- /home/quinten/fh/canopy/packages/canopy-core/src/Type/Solve.hs:609-628
let isLocal = Map.member name locals
let rigidRankThreshold = if isLocal then parentRank else actualRank
...
let isUnifiedWithRigid = any id (concat equivalences)
let hasOuterRigids = not (null outerRigids)
let isModuleLevel = isLocal
if actualRank == noRank                                  -- (1)
  then return ((name, var) : acc)
  else if isUnifiedWithRigid && not isModuleLevel        -- (2)
    then return acc
  else if actualRank <= parentRank                       -- (3)
    then return acc
  else if hasOuterRigids && actualRank /= youngRank      -- (4)
         && not isModuleLevel
    then return acc
    else do                                              -- (5)
      generalizeRecursively actualVar
      return ((name, var) : acc)
```

Five branches, each with different generalization behavior.  The tests must
exercise all five branches to verify correctness.

### Current Test Coverage Gaps

The existing `Unit.Type.SolveTest` (261 lines) tests only:

- `CTrue`, `CSaveTheEnvironment` -- trivial constraints
- `CEqual` with matching/mismatching primitive types
- `CCaseBranchesIsolated` with simple pass/fail
- `CLet` with empty rigids/flexs or single flex var, body always `CTrue`
- `CPattern` with matching/mismatching types
- Composite `CAnd` constraints

**Not tested at all:**

- `CLet` with rigid variables (triggers deferred path)
- `CLet` with ambient rigids from parent scope
- `CLet` with `expectedType` set
- Nested `CLet` (inner let uses outer's generalized bindings)
- `CLet` where flex vars escape to outer scope
- `CLet` where bindings should be polymorphic (used at multiple types)
- `CLet` where bindings should remain monomorphic (value restriction)

## Files to Modify

### 1. `test/Unit/Type/SolveTest.hs` -- add deferred-path unit tests

Add new test groups that construct `CLet` constraints exercising the deferred
generalization path:

```haskell
-- New test groups to add to the tests list:

deferredLetTests :: TestTree
deferredLetTests =
  testGroup
    "CLet deferred generalization"
    [ testDeferredWithRigids,
      testDeferredWithAmbientRigids,
      testDeferredWithExpectedType,
      testNestedLetGeneralization,
      testPolymorphicLetBinding,
      testMonomorphicRestriction
    ]
```

**Test: CLet with rigid variables**

Construct a `CLet` with `_rigidVars = [r]` where `r` is a rigid variable.
This forces `shouldDefer = True` via `hasAmbientRigids` in the outer scope.
Verify the solver succeeds and the binding is generalized.

```haskell
testDeferredWithRigids :: TestTree
testDeferredWithRigids =
  testCase "CLet with rigid vars triggers deferred path and succeeds" $ do
    rigidVar <- Type.nameToRigid "a"
    flexVar <- Type.mkFlexVar
    let header = Map.singleton "identity"
          (Ann.At testRegion (FunN (VarN flexVar) (VarN flexVar)))
    let headerCon = CTrue
    let bodyCon = CTrue
    let constraint = CLet
          { _rigidVars = [rigidVar]
          , _flexVars = [flexVar]
          , _header = header
          , _headerCon = headerCon
          , _bodyCon = bodyCon
          , _expectedType = Nothing
          }
    result <- Solve.run constraint
    assertSolveSuccess result
```

**Test: Nested let where inner uses outer's polymorphic binding**

Construct an outer `CLet` that generalizes `id : a -> a`, then an inner `CLet`
body that uses `id` at two different types (Int and String).  Verify both
uses are accepted.

```haskell
testNestedLetGeneralization :: TestTree
testNestedLetGeneralization =
  testCase "nested CLet: inner body uses outer polymorphic binding at two types" $ do
    flexA <- Type.mkFlexVar
    let idType = FunN (VarN flexA) (VarN flexA)
    let header = Map.singleton "id" (Ann.At testRegion idType)
    -- Body: id Int == Int, id String == String
    let useAtInt = CLocal testRegion "id"
          (Error.NoExpectation (FunN Type.int Type.int))
    let useAtString = CLocal testRegion "id"
          (Error.NoExpectation (FunN Type.string Type.string))
    let bodyCon = CAnd [useAtInt, useAtString]
    let constraint = CLet
          { _rigidVars = []
          , _flexVars = [flexA]
          , _header = header
          , _headerCon = CTrue
          , _bodyCon = bodyCon
          , _expectedType = Nothing
          }
    result <- Solve.run constraint
    assertSolveSuccess result
```

**Test: CLet where binding should remain monomorphic (value restriction)**

When a binding unifies with an outer rigid, it must not be generalized in the
body.  Using it at a conflicting type should produce an error.

### 2. New file: `test/Property/Type/SolveProps.hs` -- property tests

Create property-based tests using QuickCheck/Hedgehog that generate random
`Constraint` trees and verify solver invariants:

**Property 1: Symmetry of `CEqual`**

If `CEqual a b` succeeds, then `CEqual b a` also succeeds.

```haskell
propEqualSymmetric :: Property
propEqualSymmetric = property $ do
  tipe <- forAll genSimpleType
  tipe2 <- forAll genSimpleType
  result1 <- liftIO (Solve.run (mkCEqual tipe tipe2))
  result2 <- liftIO (Solve.run (mkCEqual tipe2 tipe))
  isRight result1 === isRight result2
```

**Property 2: CLet identity -- empty header, CTrue body**

For any well-formed header constraint, wrapping it in `CLet [] flexs Map.empty headerCon CTrue Nothing` should produce the same success/failure as solving `headerCon` alone (modulo the flex var introduction).

**Property 3: Generalized bindings are polymorphic**

When a `CLet` generalizes a binding (no rigid constraints, no escaping), the
binding can be used at any compatible type in the body.  Generate a flex-only
`CLet` with identity-type binding, and verify that using it at two different
concrete types both succeed.

**Property 4: Monomorphic restriction holds**

When a binding's type variable escapes (unified with outer scope), using it
at two incompatible types should fail.

### Type Generator

```haskell
genSimpleType :: Gen Type
genSimpleType = Gen.choice
  [ pure Type.int
  , pure Type.float
  , pure Type.string
  , pure Type.bool
  , pure Type.char
  , pure UnitN
  , pure EmptyRecordN
  , FunN <$> genSimpleType <*> genSimpleType  -- bounded recursion
  , TupleN <$> genSimpleType <*> genSimpleType <*> pure Nothing
  ]
```

### 3. `test/Main.hs` -- register new test modules

Add imports and entries for the new test modules:

```haskell
import qualified Property.Type.SolveProps as SolveProps
-- ...
, SolveProps.props
```

### 4. `canopy.cabal` or `package.yaml` -- add test dependencies

Ensure `tasty-hedgehog` or `tasty-quickcheck` is in the test dependencies if
not already present.

## Detailed Test Matrix for `checkAndGeneralizeWithParent`

| Branch | Condition | Expected behavior | Test scenario |
|--------|-----------|-------------------|---------------|
| (1) | `actualRank == noRank` | Already generic, include in result | Binding already generalized by standard path |
| (2) | `isUnifiedWithRigid && not isModuleLevel` | Exclude (stays mono) | Inner let-binding unified with outer rigid var |
| (3) | `actualRank <= parentRank` | Exclude (escaped to outer) | Binding used in outer scope constraint |
| (4) | `hasOuterRigids && actualRank /= youngRank && not isModuleLevel` | Exclude (ambiguous) | Binding at intermediate rank with outer rigids |
| (5) | Otherwise | Generalize | Local binding with no escaping |

## Verification

### Run Tests

```bash
# Run solver unit tests
stack test --ta="--pattern Solve"

# Run property tests
stack test --ta="--pattern SolveProps"

# Run all type-related tests
stack test --ta="--pattern Type"

# Full test suite
stack test
```

### Coverage Check

```bash
# Generate coverage report for the solver
stack test --coverage --ta="--pattern Type"

# Verify finalizeDeferredLet and checkAndGeneralizeWithParent are covered
# Look for Type.Solve module in the HPC report
```

### Dead Code Investigation

During implementation, verify whether the `else if isOriginalDefer` branch
at line 495 is actually dead code.  If `shouldGeneralizeEarly = isOriginalDefer`
(line 474), then `shouldGeneralizeEarly == False` implies
`isOriginalDefer == False`, making line 495-496 unreachable.  If confirmed dead,
file a follow-up issue to simplify the logic.

## Rollback Plan

All changes are test-only additions.  Removing the new test files and reverting
`test/Main.hs` fully rolls back this plan.
