# Test Refactoring Example - Step by Step

This document provides a detailed, worked example of refactoring a test file from anti-patterns to meaningful behavioral tests.

## Example File: OptimizedTest.hs (Before Refactoring)

### Original Code (Anti-Pattern)

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Unit.AST.OptimizedTest (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Name as Name
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests = testGroup "AST.Optimized Tests"
  [ testBoolConstructor
  , testIntConstructor
  , testGlobalConstructor
  ]

-- ❌ ANTI-PATTERN: Testing Show instance
testBoolConstructor :: TestTree
testBoolConstructor =
  testCase "Bool constructor representation" $ do
    let expr = Opt.Bool True
    show expr @?= "Bool True"

-- ❌ ANTI-PATTERN: Testing Show instance
testIntConstructor :: TestTree
testIntConstructor =
  testCase "Int constructor representation" $ do
    let expr = Opt.Int 42
    show expr @?= "Int 42"

-- ❌ ANTI-PATTERN: Testing Show instance
testGlobalConstructor :: TestTree
testGlobalConstructor =
  testCase "Global constructor representation" $ do
    let global = Opt.Global ModuleName.basics Name.true
    show global @?= "Global Basics True"
```

### Problems Identified

1. **Show Instance Testing** - Tests verify `show` output, not behavior
2. **No Behavioral Validation** - Doesn't test what these constructors DO
3. **Brittle Tests** - Will break if Show format changes
4. **No Business Logic** - Tests framework mechanics, not domain logic

## Step 1: Understand Intent

### Questions to Ask:
1. What is this test really trying to verify?
2. What business logic does this type support?
3. How is this type actually used in the compiler?
4. What properties must this type maintain?

### Answers:
1. Tests verify that constructors can be created
2. These types represent optimized AST nodes
3. Compiler pattern matches on these, extracts values, transforms them
4. Must preserve values, support pattern matching, enable extraction

## Step 2: Create Helper Functions

### File: `test/Helpers/Assertions.hs`

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Helpers.Assertions
  ( -- * AST Expression Assertions
    extractBoolValue,
    extractIntValue,
    extractStringValue,
    assertBoolExpr,
    assertIntExpr,
    isConstructor,

    -- * AST Global Assertions
    extractGlobalInfo,
    assertGlobalModule,
    assertGlobalName,
  ) where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Name as Name
import Data.Text (Text)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, (@?=))

-- | Extract boolean value from expression
extractBoolValue :: Opt.Expr -> Maybe Bool
extractBoolValue (Opt.Bool b) = Just b
extractBoolValue _ = Nothing

-- | Extract integer value from expression
extractIntValue :: Opt.Expr -> Maybe Int
extractIntValue (Opt.Int i) = Just i
extractIntValue _ = Nothing

-- | Extract string value from expression
extractStringValue :: Opt.Expr -> Maybe Text
extractStringValue (Opt.Str s) = Just s
extractStringValue _ = Nothing

-- | Assert expression is boolean with specific value
assertBoolExpr :: Bool -> Opt.Expr -> Assertion
assertBoolExpr expected expr = case extractBoolValue expr of
  Just actual -> actual @?= expected
  Nothing -> assertFailure "Expression is not a boolean"

-- | Assert expression is integer with specific value
assertIntExpr :: Int -> Opt.Expr -> Assertion
assertIntExpr expected expr = case extractIntExpr expr of
  Just actual -> actual @?= expected
  Nothing -> assertFailure "Expression is not an integer"

-- | Check if expression is a specific constructor type
isConstructor :: String -> Opt.Expr -> Bool
isConstructor "Bool" (Opt.Bool _) = True
isConstructor "Int" (Opt.Int _) = True
isConstructor "Str" (Opt.Str _) = True
isConstructor "Chr" (Opt.Chr _) = True
isConstructor _ _ = False

-- | Extract module name and identifier from Global
extractGlobalInfo :: Opt.Global -> (ModuleName.ModuleName, Name.Name)
extractGlobalInfo (Opt.Global modName name) = (modName, name)

-- | Assert global has expected module name
assertGlobalModule :: Text -> Opt.Global -> Assertion
assertGlobalModule expected global =
  let (modName, _) = extractGlobalInfo global
  in ModuleName.toChars modName @?= expected

-- | Assert global has expected identifier name
assertGlobalName :: Text -> Opt.Global -> Assertion
assertGlobalName expected global =
  let (_, name) = extractGlobalInfo global
  in Name.toChars name @?= expected
```

## Step 3: Refactor Tests to Use Behavioral Assertions

### File: `test/Unit/AST/OptimizedTest.hs` (After Refactoring)

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Unit.AST.OptimizedTest (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Name as Name
import Helpers.Assertions
  ( assertBoolExpr,
    assertGlobalModule,
    assertGlobalName,
    assertIntExpr,
    extractBoolValue,
    extractGlobalInfo,
    extractIntValue,
    isConstructor,
  )
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests = testGroup "AST.Optimized Tests"
  [ testBoolConstructor
  , testIntConstructor
  , testGlobalConstructor
  ]

-- ✅ BEHAVIORAL: Tests actual value extraction and pattern matching
testBoolConstructor :: TestTree
testBoolConstructor =
  testGroup "Bool constructor"
    [ testCase "creates Bool with True value" $ do
        let expr = Opt.Bool True
        assertBoolExpr True expr
        extractBoolValue expr @?= Just True
        isConstructor "Bool" expr @?= True

    , testCase "creates Bool with False value" $ do
        let expr = Opt.Bool False
        assertBoolExpr False expr
        extractBoolValue expr @?= Just False

    , testCase "Bool can be pattern matched" $ do
        let expr = Opt.Bool True
        case expr of
          Opt.Bool val -> val @?= True
          _ -> assertFailure "Expected Bool constructor"

    , testCase "non-Bool returns Nothing on extraction" $ do
        let expr = Opt.Int 42
        extractBoolValue expr @?= Nothing
    ]

-- ✅ BEHAVIORAL: Tests actual value extraction and operations
testIntConstructor :: TestTree
testIntConstructor =
  testGroup "Int constructor"
    [ testCase "creates Int with positive value" $ do
        let expr = Opt.Int 42
        assertIntExpr 42 expr
        extractIntValue expr @?= Just 42
        isConstructor "Int" expr @?= True

    , testCase "creates Int with negative value" $ do
        let expr = Opt.Int (-10)
        assertIntExpr (-10) expr
        extractIntValue expr @?= Just (-10)

    , testCase "creates Int with zero" $ do
        let expr = Opt.Int 0
        assertIntExpr 0 expr

    , testCase "Int can be pattern matched" $ do
        let expr = Opt.Int 42
        case expr of
          Opt.Int val -> val @?= 42
          _ -> assertFailure "Expected Int constructor"

    , testCase "non-Int returns Nothing on extraction" $ do
        let expr = Opt.Bool True
        extractIntValue expr @?= Nothing
    ]

-- ✅ BEHAVIORAL: Tests actual module and name storage
testGlobalConstructor :: TestTree
testGlobalConstructor =
  testGroup "Global constructor"
    [ testCase "stores module name correctly" $ do
        let global = Opt.Global ModuleName.basics Name.true
        assertGlobalModule "Basics" global

    , testCase "stores identifier name correctly" $ do
        let global = Opt.Global ModuleName.basics Name.true
        assertGlobalName "True" global

    , testCase "extracts both components" $ do
        let global = Opt.Global ModuleName.basics Name.true
            (modName, name) = extractGlobalInfo global
        ModuleName.toChars modName @?= "Basics"
        Name.toChars name @?= "True"

    , testCase "Global can be pattern matched" $ do
        let global = Opt.Global ModuleName.basics Name.true
        case global of
          Opt.Global modName name -> do
            ModuleName.toChars modName @?= "Basics"
            Name.toChars name @?= "True"

    , testCase "different modules are distinguishable" $ do
        let global1 = Opt.Global ModuleName.basics Name.true
            global2 = Opt.Global ModuleName.maybe Name.just
            (mod1, _) = extractGlobalInfo global1
            (mod2, _) = extractGlobalInfo global2
        assertBool "Different modules should be distinguishable"
          (ModuleName.toChars mod1 /= ModuleName.toChars mod2)
    ]
```

## Step 4: Compare Before and After

### Before (Anti-Pattern)
- **3 tests** - Each tests Show output
- **No extraction** - Can't verify values
- **No pattern matching** - Can't verify structure
- **Brittle** - Breaks if Show changes
- **Framework focus** - Tests Show instance

### After (Behavioral)
- **13 tests** - Each tests actual behavior
- **Value extraction** - Verifies stored values
- **Pattern matching** - Verifies constructor structure
- **Robust** - Independent of Show format
- **Business logic** - Tests domain behavior

### Coverage Improvement
- **Before:** Show instance (useless)
- **After:** Constructor creation, value storage, pattern matching, extraction

## Step 5: Additional Improvements

### Add Property Tests

```haskell
-- test/Property/AST/OptimizedProps.hs

module Property.AST.OptimizedProps (tests) where

import qualified AST.Optimized as Opt
import Helpers.Assertions
import Helpers.Generators
import Test.QuickCheck
import Test.Tasty
import Test.Tasty.QuickCheck

tests :: TestTree
tests = testGroup "Optimized Property Tests"
  [ testProperty "Bool roundtrip through extraction" $
      \b -> extractBoolValue (Opt.Bool b) == Just b

  , testProperty "Int roundtrip through extraction" $
      \i -> extractIntValue (Opt.Int i) == Just i

  , testProperty "Global preserves module name" $
      forAll genModuleName $ \modName ->
      forAll genValidIdentifier $ \name ->
        let global = Opt.Global modName (Name.fromChars name)
            (extractedMod, _) = extractGlobalInfo global
        in ModuleName.toChars extractedMod == ModuleName.toChars modName
  ]
```

### Add Integration Tests

```haskell
-- test/Integration/AST/OptimizedIntegrationTest.hs

testCase "optimized expressions work in compilation pipeline" $ do
  let expr = Opt.Bool True
  result <- optimizeExpression expr
  case result of
    Opt.Bool True -> pure ()
    _ -> assertFailure "Optimization should preserve boolean value"
```

## Step 6: Verification

### Test the Tests
Intentionally break code to verify tests catch bugs:

```haskell
-- Temporarily break extractBoolValue
extractBoolValue :: Opt.Expr -> Maybe Bool
extractBoolValue _ = Nothing  -- WRONG: always returns Nothing

-- Run tests: should fail
-- Fix the function, run tests: should pass
```

### Run Full Suite
```bash
make test
make test-coverage
make test-match PATTERN="Optimized"
```

### Check Coverage
```bash
# Should show 100% coverage for tested functions
stack test --coverage
stack hpc report
```

## Lessons Learned

### Do's ✅
1. **Extract testable properties** from types without Eq
2. **Test behavior** - construction, storage, extraction
3. **Test pattern matching** - verify structure
4. **Test edge cases** - boundary values, different inputs
5. **Add helpers** - reusable assertion functions
6. **Test business logic** - how is this used in real code?

### Don'ts ❌
1. **Don't test Show** - tests framework, not logic
2. **Don't test derived instances** - compiler generates these
3. **Don't test library code** - lens, containers, etc.
4. **Don't make reflexive tests** - `x == x` is useless
5. **Don't test constants** - `True /= False` is meaningless

## Template for Other Files

Use this pattern for all refactoring:

1. **Read original test** - understand intent
2. **Identify anti-pattern** - Show, lens, reflexive, etc.
3. **Create helpers** (if needed) - extraction, assertions
4. **Write behavioral tests** - what does this DO?
5. **Test the tests** - break code, verify detection
6. **Add property tests** - invariants and laws
7. **Verify coverage** - 100% for public API

## Checklist for Each Refactoring

- [ ] Understand original test intent
- [ ] Identify anti-pattern type
- [ ] Create helper functions (if needed)
- [ ] Transform tests to behavioral
- [ ] Add edge case tests
- [ ] Add property tests (if applicable)
- [ ] Test the tests (break code)
- [ ] Run full test suite
- [ ] Check coverage
- [ ] Code review
- [ ] Commit with clear message

## Example Commit Messages

```bash
# Good commit messages
git commit -m "refactor(test): eliminate Show anti-patterns in OptimizedTest

- Replace show expr @?= tests with behavioral assertions
- Add value extraction helper functions
- Test constructor creation and pattern matching
- Add edge case tests for extraction failures
- Coverage: 35 violations -> 0 violations"

git commit -m "feat(test): add Assertions helper module

- extractBoolValue, extractIntValue for AST testing
- assertBoolExpr, assertIntExpr for value assertions
- extractGlobalInfo for Global decomposition
- Enables behavioral testing without Eq instances"
```

## Next Steps

Apply this pattern to remaining files:

1. **High Priority:**
   - Init/TypesTest.hs (50 violations)
   - Develop/TypesTest.hs (25 violations)

2. **Medium Priority:**
   - DevelopMainTest.hs (15 violations)
   - DevelopTest.hs (20 violations)

3. **Continue through all files** until zero anti-patterns

---

**Remember:** The goal is to test what the code DOES, not what framework generates. Every test should verify real business logic that could actually break.
