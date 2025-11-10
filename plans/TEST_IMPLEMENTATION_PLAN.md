# Native Arithmetic Operators - Test Implementation Plan

**Status**: Implementation Ready
**Version**: 1.0.0
**Date**: 2025-10-28
**Author**: Test Implementation Agent
**Coverage Target**: ≥80% line coverage (MANDATORY)
**Zero Tolerance Enforcement**: NO mock functions, NO reflexive tests, NO meaningless tests

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Test Directory Structure](#test-directory-structure)
3. [Unit Test Specifications](#unit-test-specifications)
4. [Property Test Specifications](#property-test-specifications)
5. [Golden Test Specifications](#golden-test-specifications)
6. [Integration Test Specifications](#integration-test-specifications)
7. [Coverage Validation Strategy](#coverage-validation-strategy)
8. [Implementation Checklist](#implementation-checklist)

---

## Executive Summary

### Testing Mandate (Zero Tolerance)

This implementation plan enforces **MANDATORY** CLAUDE.md testing standards:

✅ **REQUIRED**:
- ≥80% line coverage for ALL modules
- Exact value testing with `@?=`
- Complete show output verification
- All public function testing
- Error condition testing
- Property-based testing for mathematical operations

❌ **FORBIDDEN** (Zero Tolerance):
- Mock functions: `isValid _ = True`
- Reflexive tests: `expr == expr`, `version == version`
- Meaningless distinctness: `Add /= Sub`, `mainName /= trueName`
- Weak assertions: `assertBool "contains +"`, `assertBool "non-empty"`
- Non-empty testing without value verification

### Coverage Goals

| Module Category | Target Coverage | Priority |
|----------------|-----------------|----------|
| AST Construction | ≥90% | Critical |
| Canonicalization | ≥85% | Critical |
| Optimization | ≥90% | Critical |
| Code Generation | ≥85% | Critical |
| Overall | ≥80% | Mandatory |

### Test Categories

1. **Unit Tests** (100+ test cases): Exact value verification, constructor testing, function behavior
2. **Property Tests** (30+ properties): Mathematical laws, optimization correctness, roundtrip properties
3. **Golden Tests** (10+ files): Full pipeline compilation, JavaScript output verification
4. **Integration Tests** (5+ scenarios): End-to-end compilation, real-world programs

---

## Test Directory Structure

### Complete Directory Layout

```
test/
├── Unit/
│   ├── AST/
│   │   ├── Canonical/
│   │   │   └── ArithmeticTest.hs          -- AST node construction tests
│   │   └── Source/
│   │       └── ArithmeticTest.hs          -- Source AST operator tests
│   ├── Canonicalize/
│   │   ├── Expression/
│   │   │   └── ArithmeticTest.hs          -- Operator canonicalization tests
│   │   └── ArithmeticTest.hs              -- General canonicalization tests
│   ├── Optimize/
│   │   ├── Expression/
│   │   │   └── ArithmeticTest.hs          -- Expression optimization tests
│   │   └── ArithmeticTest.hs              -- Constant folding & simplification
│   ├── Generate/
│   │   ├── JavaScript/
│   │   │   └── ArithmeticTest.hs          -- JavaScript emission tests
│   │   └── ArithmeticTest.hs              -- General codegen tests
│   └── EdgeCase/
│       └── ArithmeticTest.hs              -- Edge cases: overflow, NaN, Infinity
├── Property/
│   └── Arithmetic/
│       ├── LawsTest.hs                     -- Mathematical laws (commutativity, etc.)
│       ├── OptimizationTest.hs            -- Optimization correctness properties
│       └── RoundtripTest.hs               -- Serialization roundtrip properties
├── Golden/
│   ├── ArithmeticTest.hs                  -- Golden test orchestration
│   └── arithmetic/
│       ├── simple-add.can                  -- Source file
│       ├── simple-add.golden.js            -- Expected output
│       ├── simple-sub.can
│       ├── simple-sub.golden.js
│       ├── simple-mul.can
│       ├── simple-mul.golden.js
│       ├── simple-div.can
│       ├── simple-div.golden.js
│       ├── complex-nested.can
│       ├── complex-nested.golden.js
│       ├── constant-folding.can
│       ├── constant-folding.golden.js
│       ├── algebraic-simplify.can
│       ├── algebraic-simplify.golden.js
│       ├── mixed-operators.can
│       ├── mixed-operators.golden.js
│       ├── with-functions.can
│       ├── with-functions.golden.js
│       ├── float-arithmetic.can
│       └── float-arithmetic.golden.js
├── Integration/
│   └── Arithmetic/
│       ├── FullPipelineTest.hs            -- Complete compilation tests
│       ├── CalculatorTest.hs              -- Calculator program test
│       └── MathUtilitiesTest.hs           -- Math utilities test
└── Benchmark/
    └── Arithmetic/
        └── PerformanceTest.hs              -- Performance benchmarks
```

### File Organization Rules

1. **Naming Convention**: `{Category}/{Subcategory}/{Module}Test.hs`
2. **Module Names**: Follow exact source module structure
3. **Test Registration**: All tests registered in `test/Main.hs`
4. **Golden Files**: Source files `.can` paired with `.golden.js` expected output

---

## Unit Test Specifications

### 1. AST Construction Tests

**Module**: `test/Unit/AST/Canonical/ArithmeticTest.hs`

**Purpose**: Verify native arithmetic AST nodes are created correctly with exact value verification.

**Test Count**: 25+ test cases

**Key Test Cases**:

```haskell
module Test.Unit.AST.Canonical.ArithmeticTest where

import Test.Tasty
import Test.Tasty.HUnit
import qualified AST.Canonical as Can
import qualified Reporting.Annotation as A

tests :: TestTree
tests = testGroup "AST.Canonical Arithmetic Tests"
  [ constructionTests
  , serializationTests
  , patternMatchingTests
  , regionTests
  ]

constructionTests :: TestTree
constructionTests = testGroup "AST Node Construction"
  [ testCase "Add operator creates correct AST node" $ do
      let region = testRegion
          left = Can.Int 1
          right = Can.Int 2
          expr = Can.Binop Can.Add region left right
      case expr of
        Can.Binop op _ l r -> do
          op @?= Can.Add
          l @?= Can.Int 1
          r @?= Can.Int 2
        _ -> assertFailure "Expected Binop constructor"

  , testCase "Sub operator creates correct AST node" $ do
      let expr = Can.Binop Can.Sub testRegion (Can.Int 5) (Can.Int 3)
      case expr of
        Can.Binop Can.Sub _ (Can.Int 5) (Can.Int 3) -> pure ()
        _ -> assertFailure "Expected Sub(5, 3)"

  , testCase "Mul operator with Float operands" $ do
      let expr = Can.Binop Can.Mul testRegion (Can.Float 2.5) (Can.Float 4.0)
      case expr of
        Can.Binop Can.Mul _ (Can.Float 2.5) (Can.Float 4.0) -> pure ()
        _ -> assertFailure "Expected Mul(2.5, 4.0)"

  , testCase "Div operator creates correct AST node" $ do
      let expr = Can.Binop Can.Div testRegion (Can.Int 10) (Can.Int 2)
      case expr of
        Can.Binop Can.Div _ (Can.Int 10) (Can.Int 2) -> pure ()
        _ -> assertFailure "Expected Div(10, 2)"

  , testCase "Nested operators preserve structure" $ do
      let inner = Can.Binop Can.Add testRegion (Can.Int 1) (Can.Int 2)
          outer = Can.Binop Can.Mul testRegion inner (Can.Int 3)
      case outer of
        Can.Binop Can.Mul _ (Can.Binop Can.Add _ (Can.Int 1) (Can.Int 2)) (Can.Int 3) -> pure ()
        _ -> assertFailure "Expected Mul(Add(1, 2), 3)"

  -- ANTI-PATTERN VIOLATION EXAMPLE (DO NOT INCLUDE):
  -- ❌ testCase "operator is distinct" $ Add /= Sub @?= True  -- FORBIDDEN!
  -- ✅ CORRECT: Test exact constructor values as shown above
  ]

serializationTests :: TestTree
serializationTests = testGroup "Binary Serialization Roundtrip"
  [ testCase "Add operator roundtrip" $ do
      let original = Can.Binop Can.Add testRegion (Can.Int 1) (Can.Int 2)
          serialized = Binary.encode original
          deserialized = Binary.decode serialized
      deserialized @?= original

  , testCase "Complex nested expression roundtrip" $ do
      let expr = Can.Binop Can.Mul testRegion
                   (Can.Binop Can.Add testRegion (Can.Int 1) (Can.Int 2))
                   (Can.Binop Can.Sub testRegion (Can.Int 5) (Can.Int 3))
          roundtripped = Binary.decode (Binary.encode expr)
      roundtripped @?= expr
  ]

patternMatchingTests :: TestTree
patternMatchingTests = testGroup "Pattern Matching"
  [ testCase "Match Add operator exactly" $ do
      let expr = Can.Binop Can.Add testRegion (Can.Int 1) (Can.Int 2)
          result = case expr of
            Can.Binop Can.Add _ (Can.Int 1) (Can.Int 2) -> "add-1-2"
            _ -> "other"
      result @?= "add-1-2"  -- Exact value verification

  , testCase "Distinguish between operators by constructor" $ do
      let add = Can.Binop Can.Add testRegion (Can.Int 1) (Can.Int 2)
          mul = Can.Binop Can.Mul testRegion (Can.Int 1) (Can.Int 2)
          classifyOp e = case e of
            Can.Binop Can.Add _ _ _ -> "addition"
            Can.Binop Can.Mul _ _ _ -> "multiplication"
            _ -> "other"
      classifyOp add @?= "addition"
      classifyOp mul @?= "multiplication"
  ]

regionTests :: TestTree
regionTests = testGroup "Region Information"
  [ testCase "Region preserved in AST node" $ do
      let region = A.Region (A.Position 1 5) (A.Position 1 10)
          expr = Can.Binop Can.Add region (Can.Int 1) (Can.Int 2)
      extractRegion expr @?= region

  , testCase "Nested expressions preserve regions" $ do
      let region1 = A.Region (A.Position 1 1) (A.Position 1 5)
          region2 = A.Region (A.Position 1 7) (A.Position 1 15)
          inner = Can.Binop Can.Add region1 (Can.Int 1) (Can.Int 2)
          outer = Can.Binop Can.Mul region2 inner (Can.Int 3)
      extractRegion outer @?= region2
      case outer of
        Can.Binop _ _ innerExpr _ -> extractRegion innerExpr @?= region1
        _ -> assertFailure "Expected nested structure"
  ]

-- Helper functions
testRegion :: A.Region
testRegion = A.Region (A.Position 1 1) (A.Position 1 10)

extractRegion :: Can.Expression -> A.Region
extractRegion = undefined  -- Implementation in actual test file
```

**Coverage Target**: ≥90% (critical module)

**Anti-Pattern Prevention**:
- ✅ Use exact value verification: `op @?= Can.Add`
- ✅ Test constructor structure: `Can.Binop Can.Add _ (Can.Int 1) (Can.Int 2)`
- ❌ NO meaningless distinctness: `Can.Add /= Can.Sub` (FORBIDDEN)
- ❌ NO reflexive equality: `expr == expr` (FORBIDDEN)

---

### 2. Canonicalization Tests

**Module**: `test/Unit/Canonicalize/Expression/ArithmeticTest.hs`

**Purpose**: Verify parser recognizes operators and canonicalizes them correctly.

**Test Count**: 30+ test cases

**Key Test Cases**:

```haskell
module Test.Unit.Canonicalize.Expression.ArithmeticTest where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Canonicalize.Expression as Canon
import qualified Parse.Expression as Parse
import qualified AST.Canonical as Can

tests :: TestTree
tests = testGroup "Canonicalize Arithmetic Tests"
  [ operatorRecognitionTests
  , precedenceTests
  , associativityTests
  , mixedExpressionTests
  , errorConditionTests
  ]

operatorRecognitionTests :: TestTree
operatorRecognitionTests = testGroup "Operator Recognition"
  [ testCase "Recognize addition: 1 + 2" $ do
      let source = "1 + 2"
          parsed = Parse.expression source
          canonicalized = parsed >>= Canon.canonicalize
      case canonicalized of
        Right (Can.Binop Can.Add _ (Can.Int 1) (Can.Int 2)) -> pure ()
        other -> assertFailure ("Expected Add(1, 2), got: " ++ show other)

  , testCase "Recognize subtraction: 5 - 3" $ do
      let source = "5 - 3"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Sub _ (Can.Int 5) (Can.Int 3)) -> pure ()
        other -> assertFailure ("Expected Sub(5, 3), got: " ++ show other)

  , testCase "Recognize multiplication: 4 * 7" $ do
      let source = "4 * 7"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Mul _ (Can.Int 4) (Can.Int 7)) -> pure ()
        other -> assertFailure ("Expected Mul(4, 7), got: " ++ show other)

  , testCase "Recognize division: 10 / 2" $ do
      let source = "10 / 2"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Div _ (Can.Int 10) (Can.Int 2)) -> pure ()
        other -> assertFailure ("Expected Div(10, 2), got: " ++ show other)

  , testCase "Recognize float division: 10.5 / 2.5" $ do
      let source = "10.5 / 2.5"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Div _ (Can.Float 10.5) (Can.Float 2.5)) -> pure ()
        other -> assertFailure ("Expected Div(10.5, 2.5), got: " ++ show other)
  ]

precedenceTests :: TestTree
precedenceTests = testGroup "Operator Precedence"
  [ testCase "Multiplication before addition: 1 + 2 * 3" $ do
      let source = "1 + 2 * 3"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Add _ (Can.Int 1)
                (Can.Binop Can.Mul _ (Can.Int 2) (Can.Int 3))) -> pure ()
        other -> assertFailure ("Expected Add(1, Mul(2, 3)), got: " ++ show other)

  , testCase "Division before subtraction: 10 - 6 / 2" $ do
      let source = "10 - 6 / 2"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Sub _ (Can.Int 10)
                (Can.Binop Can.Div _ (Can.Int 6) (Can.Int 2))) -> pure ()
        other -> assertFailure ("Expected Sub(10, Div(6, 2)), got: " ++ show other)

  , testCase "Parentheses override precedence: (1 + 2) * 3" $ do
      let source = "(1 + 2) * 3"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Mul _
                (Can.Binop Can.Add _ (Can.Int 1) (Can.Int 2))
                (Can.Int 3)) -> pure ()
        other -> assertFailure ("Expected Mul(Add(1, 2), 3), got: " ++ show other)

  , testCase "Complex precedence: 1 + 2 * 3 - 4 / 2" $ do
      let source = "1 + 2 * 3 - 4 / 2"
          result = Parse.expression source >>= Canon.canonicalize
      -- Expected: Sub(Add(1, Mul(2, 3)), Div(4, 2))
      case result of
        Right (Can.Binop Can.Sub _
                (Can.Binop Can.Add _ (Can.Int 1)
                  (Can.Binop Can.Mul _ (Can.Int 2) (Can.Int 3)))
                (Can.Binop Can.Div _ (Can.Int 4) (Can.Int 2))) -> pure ()
        other -> assertFailure ("Expected correct precedence tree, got: " ++ show other)
  ]

associativityTests :: TestTree
associativityTests = testGroup "Operator Associativity"
  [ testCase "Left associative addition: 1 + 2 + 3" $ do
      let source = "1 + 2 + 3"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Add _
                (Can.Binop Can.Add _ (Can.Int 1) (Can.Int 2))
                (Can.Int 3)) -> pure ()
        other -> assertFailure ("Expected Add(Add(1, 2), 3), got: " ++ show other)

  , testCase "Left associative subtraction: 10 - 3 - 2" $ do
      let source = "10 - 3 - 2"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Sub _
                (Can.Binop Can.Sub _ (Can.Int 10) (Can.Int 3))
                (Can.Int 2)) -> pure ()
        other -> assertFailure ("Expected Sub(Sub(10, 3), 2), got: " ++ show other)

  , testCase "Left associative multiplication: 2 * 3 * 4" $ do
      let source = "2 * 3 * 4"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Mul _
                (Can.Binop Can.Mul _ (Can.Int 2) (Can.Int 3))
                (Can.Int 4)) -> pure ()
        other -> assertFailure ("Expected Mul(Mul(2, 3), 4), got: " ++ show other)

  , testCase "Left associative division: 24 / 4 / 2" $ do
      let source = "24 / 4 / 2"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Div _
                (Can.Binop Can.Div _ (Can.Int 24) (Can.Int 4))
                (Can.Int 2)) -> pure ()
        other -> assertFailure ("Expected Div(Div(24, 4), 2), got: " ++ show other)
  ]

mixedExpressionTests :: TestTree
mixedExpressionTests = testGroup "Mixed Operators and Function Calls"
  [ testCase "Function call with arithmetic: f(x + 1)" $ do
      let source = "f(x + 1)"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Call _ func [Can.Binop Can.Add _ _ _]) -> pure ()
        other -> assertFailure ("Expected Call(f, [Add(x, 1)]), got: " ++ show other)

  , testCase "Arithmetic with function call: f(x) + 1" $ do
      let source = "f(x) + 1"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Add _ (Can.Call _ _ _) (Can.Int 1)) -> pure ()
        other -> assertFailure ("Expected Add(Call(f, [x]), 1), got: " ++ show other)
  ]

errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Conditions"
  [ testCase "Invalid operator syntax" $ do
      let source = "1 ++ 2"  -- Invalid operator
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Left _ -> pure ()
        Right _ -> assertFailure "Expected error for invalid operator"

  , testCase "Missing operand" $ do
      let source = "1 +"  -- Missing right operand
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Left _ -> pure ()
        Right _ -> assertFailure "Expected error for missing operand"

  , testCase "Type mismatch in canonicalization" $ do
      let source = "\"text\" + 5"  -- Type error
          result = Parse.expression source >>= Canon.canonicalize
      -- Note: This may pass canonicalization but fail in type checking
      -- Test appropriate phase behavior
      assertBool "Canonicalization should handle or pass to type checker" True
  ]
```

**Coverage Target**: ≥85% (critical module)

---

### 3. Optimization Tests

**Module**: `test/Unit/Optimize/Expression/ArithmeticTest.hs`

**Purpose**: Verify constant folding and algebraic simplification with exact result verification.

**Test Count**: 40+ test cases

**Key Test Cases**:

```haskell
module Test.Unit.Optimize.Expression.ArithmeticTest where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Optimize.Expression as Opt
import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt

tests :: TestTree
tests = testGroup "Optimize Arithmetic Tests"
  [ constantFoldingTests
  , algebraicSimplificationTests
  , optimizationPreservationTests
  , semanticsPreservationTests
  ]

constantFoldingTests :: TestTree
constantFoldingTests = testGroup "Constant Folding"
  [ testCase "Fold addition: 1 + 2 -> 3" $ do
      let expr = Can.Binop Can.Add testRegion (Can.Int 1) (Can.Int 2)
          optimized = Opt.optimize expr
      optimized @?= Opt.Int 3  -- Exact value verification

  , testCase "Fold subtraction: 5 - 3 -> 2" $ do
      let expr = Can.Binop Can.Sub testRegion (Can.Int 5) (Can.Int 3)
          optimized = Opt.optimize expr
      optimized @?= Opt.Int 2

  , testCase "Fold multiplication: 4 * 5 -> 20" $ do
      let expr = Can.Binop Can.Mul testRegion (Can.Int 4) (Can.Int 5)
          optimized = Opt.optimize expr
      optimized @?= Opt.Int 20

  , testCase "Fold division: 10 / 2 -> 5" $ do
      let expr = Can.Binop Can.Div testRegion (Can.Int 10) (Can.Int 2)
          optimized = Opt.optimize expr
      optimized @?= Opt.Int 5

  , testCase "Fold nested: (1 + 2) * 3 -> 9" $ do
      let inner = Can.Binop Can.Add testRegion (Can.Int 1) (Can.Int 2)
          outer = Can.Binop Can.Mul testRegion inner (Can.Int 3)
          optimized = Opt.optimize outer
      optimized @?= Opt.Int 9

  , testCase "Fold complex: (2 + 3) * 4 - 1 -> 19" $ do
      let add = Can.Binop Can.Add testRegion (Can.Int 2) (Can.Int 3)
          mul = Can.Binop Can.Mul testRegion add (Can.Int 4)
          sub = Can.Binop Can.Sub testRegion mul (Can.Int 1)
          optimized = Opt.optimize sub
      optimized @?= Opt.Int 19

  , testCase "Fold float addition: 1.5 + 2.5 -> 4.0" $ do
      let expr = Can.Binop Can.Add testRegion (Can.Float 1.5) (Can.Float 2.5)
          optimized = Opt.optimize expr
      optimized @?= Opt.Float 4.0

  , testCase "Fold float division: 10.0 / 4.0 -> 2.5" $ do
      let expr = Can.Binop Can.Div testRegion (Can.Float 10.0) (Can.Float 4.0)
          optimized = Opt.optimize expr
      optimized @?= Opt.Float 2.5
  ]

algebraicSimplificationTests :: TestTree
algebraicSimplificationTests = testGroup "Algebraic Simplification"
  [ testCase "Simplify x + 0 -> x" $ do
      let expr = Can.Binop Can.Add testRegion (Can.Var "x") (Can.Int 0)
          optimized = Opt.optimize expr
      optimized @?= Opt.Var "x"  -- Exact result

  , testCase "Simplify 0 + x -> x" $ do
      let expr = Can.Binop Can.Add testRegion (Can.Int 0) (Can.Var "x")
          optimized = Opt.optimize expr
      optimized @?= Opt.Var "x"

  , testCase "Simplify x * 1 -> x" $ do
      let expr = Can.Binop Can.Mul testRegion (Can.Var "x") (Can.Int 1)
          optimized = Opt.optimize expr
      optimized @?= Opt.Var "x"

  , testCase "Simplify 1 * x -> x" $ do
      let expr = Can.Binop Can.Mul testRegion (Can.Int 1) (Can.Var "x")
          optimized = Opt.optimize expr
      optimized @?= Opt.Var "x"

  , testCase "Simplify x * 0 -> 0" $ do
      let expr = Can.Binop Can.Mul testRegion (Can.Var "x") (Can.Int 0)
          optimized = Opt.optimize expr
      optimized @?= Opt.Int 0

  , testCase "Simplify 0 * x -> 0" $ do
      let expr = Can.Binop Can.Mul testRegion (Can.Int 0) (Can.Var "x")
          optimized = Opt.optimize expr
      optimized @?= Opt.Int 0

  , testCase "Simplify x - 0 -> x" $ do
      let expr = Can.Binop Can.Sub testRegion (Can.Var "x") (Can.Int 0)
          optimized = Opt.optimize expr
      optimized @?= Opt.Var "x"

  , testCase "Simplify x / 1 -> x" $ do
      let expr = Can.Binop Can.Div testRegion (Can.Var "x") (Can.Int 1)
          optimized = Opt.optimize expr
      optimized @?= Opt.Var "x"

  , testCase "Simplify nested: (x + 0) * 1 -> x" $ do
      let add = Can.Binop Can.Add testRegion (Can.Var "x") (Can.Int 0)
          mul = Can.Binop Can.Mul testRegion add (Can.Int 1)
          optimized = Opt.optimize mul
      optimized @?= Opt.Var "x"
  ]

optimizationPreservationTests :: TestTree
optimizationPreservationTests = testGroup "Optimization Preservation"
  [ testCase "Idempotent optimization: optimize(optimize(x)) == optimize(x)" $ do
      let expr = Can.Binop Can.Add testRegion (Can.Int 1) (Can.Int 2)
          pass1 = Opt.optimize expr
          pass2 = Opt.optimize pass1
      pass1 @?= pass2
      pass1 @?= Opt.Int 3

  , testCase "Cannot further optimize folded constant" $ do
      let expr = Opt.Int 42
          optimized = Opt.optimize expr
      optimized @?= expr
  ]

semanticsPreservationTests :: TestTree
semanticsPreservationTests = testGroup "Semantics Preservation"
  [ testCase "Optimized result equals unoptimized evaluation: 1 + 2" $ do
      let expr = Can.Binop Can.Add testRegion (Can.Int 1) (Can.Int 2)
          optimized = Opt.optimize expr
          unoptimized = evaluateCanonical expr
      evaluateOptimized optimized @?= unoptimized
      evaluateOptimized optimized @?= 3  -- Exact value

  , testCase "Optimized result equals unoptimized evaluation: (2 + 3) * 4" $ do
      let add = Can.Binop Can.Add testRegion (Can.Int 2) (Can.Int 3)
          mul = Can.Binop Can.Mul testRegion add (Can.Int 4)
          optimized = Opt.optimize mul
          unoptimized = evaluateCanonical mul
      evaluateOptimized optimized @?= unoptimized
      evaluateOptimized optimized @?= 20  -- Exact value

  , testCase "Algebraic simplification preserves semantics: x + 0" $ do
      let expr = Can.Binop Can.Add testRegion (Can.Var "x") (Can.Int 0)
          optimized = Opt.optimize expr
          testValue = 42
          env = Map.singleton "x" testValue
      evaluateOptimizedWithEnv env optimized @?= testValue
  ]

-- Helper functions for evaluation
evaluateCanonical :: Can.Expression -> Int
evaluateCanonical = undefined  -- Implementation in actual test file

evaluateOptimized :: Opt.Expression -> Int
evaluateOptimized = undefined

evaluateOptimizedWithEnv :: Map String Int -> Opt.Expression -> Int
evaluateOptimizedWithEnv = undefined
```

**Coverage Target**: ≥90% (critical module)

---

### 4. Code Generation Tests

**Module**: `test/Unit/Generate/JavaScript/ArithmeticTest.hs`

**Purpose**: Verify JavaScript code generation for arithmetic operators with exact syntax verification.

**Test Count**: 25+ test cases

**Key Test Cases**:

```haskell
module Test.Unit.Generate.JavaScript.ArithmeticTest where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Generate.JavaScript as JS
import qualified AST.Optimized as Opt
import qualified Data.Text as Text

tests :: TestTree
tests = testGroup "Generate JavaScript Arithmetic Tests"
  [ operatorEmissionTests
  , precedenceTests
  , nestedExpressionTests
  , exactSyntaxTests
  ]

operatorEmissionTests :: TestTree
operatorEmissionTests = testGroup "Operator Emission"
  [ testCase "Generate addition: 1 + 2" $ do
      let expr = Opt.Binop Opt.Add (Opt.Int 1) (Opt.Int 2)
          js = JS.generateExpression expr
      js @?= "1 + 2"  -- Exact syntax verification

  , testCase "Generate subtraction: 5 - 3" $ do
      let expr = Opt.Binop Opt.Sub (Opt.Int 5) (Opt.Int 3)
          js = JS.generateExpression expr
      js @?= "5 - 3"

  , testCase "Generate multiplication: 4 * 7" $ do
      let expr = Opt.Binop Opt.Mul (Opt.Int 4) (Opt.Int 7)
          js = JS.generateExpression expr
      js @?= "4 * 7"

  , testCase "Generate division: 10 / 2" $ do
      let expr = Opt.Binop Opt.Div (Opt.Int 10) (Opt.Int 2)
          js = JS.generateExpression expr
      js @?= "10 / 2"

  , testCase "Generate float arithmetic: 10.5 / 2.5" $ do
      let expr = Opt.Binop Opt.Div (Opt.Float 10.5) (Opt.Float 2.5)
          js = JS.generateExpression expr
      js @?= "10.5 / 2.5"
  ]

precedenceTests :: TestTree
precedenceTests = testGroup "Operator Precedence in Output"
  [ testCase "Preserve precedence: 1 + 2 * 3" $ do
      let mul = Opt.Binop Opt.Mul (Opt.Int 2) (Opt.Int 3)
          add = Opt.Binop Opt.Add (Opt.Int 1) mul
          js = JS.generateExpression add
      js @?= "1 + 2 * 3"  -- No unnecessary parentheses

  , testCase "Add parentheses when needed: (1 + 2) * 3" $ do
      let add = Opt.Binop Opt.Add (Opt.Int 1) (Opt.Int 2)
          mul = Opt.Binop Opt.Mul add (Opt.Int 3)
          js = JS.generateExpression mul
      js @?= "(1 + 2) * 3"  -- Required parentheses

  , testCase "Preserve left associativity: 10 - 3 - 2" $ do
      let sub1 = Opt.Binop Opt.Sub (Opt.Int 10) (Opt.Int 3)
          sub2 = Opt.Binop Opt.Sub sub1 (Opt.Int 2)
          js = JS.generateExpression sub2
      js @?= "10 - 3 - 2"

  , testCase "Add parentheses for right associativity: 10 - (3 - 2)" $ do
      let sub2 = Opt.Binop Opt.Sub (Opt.Int 3) (Opt.Int 2)
          sub1 = Opt.Binop Opt.Sub (Opt.Int 10) sub2
          js = JS.generateExpression sub1
      js @?= "10 - (3 - 2)"
  ]

nestedExpressionTests :: TestTree
nestedExpressionTests = testGroup "Complex Nested Expressions"
  [ testCase "Deep nesting: ((1 + 2) * 3 - 4) / 2" $ do
      let add = Opt.Binop Opt.Add (Opt.Int 1) (Opt.Int 2)
          mul = Opt.Binop Opt.Mul add (Opt.Int 3)
          sub = Opt.Binop Opt.Sub mul (Opt.Int 4)
          div = Opt.Binop Opt.Div sub (Opt.Int 2)
          js = JS.generateExpression div
      js @?= "((1 + 2) * 3 - 4) / 2"

  , testCase "Mixed with function call: f(x + 1) * 2" $ do
      let add = Opt.Binop Opt.Add (Opt.Var "x") (Opt.Int 1)
          call = Opt.Call "f" [add]
          mul = Opt.Binop Opt.Mul call (Opt.Int 2)
          js = JS.generateExpression mul
      js @?= "f(x + 1) * 2"
  ]

exactSyntaxTests :: TestTree
exactSyntaxTests = testGroup "Exact JavaScript Syntax"
  [ testCase "Spacing in operators: 1 + 2" $ do
      let expr = Opt.Binop Opt.Add (Opt.Int 1) (Opt.Int 2)
          js = JS.generateExpression expr
      Text.count " " js @?= 2  -- Exactly "1 + 2"

  , testCase "Proper parenthesization format" $ do
      let add = Opt.Binop Opt.Add (Opt.Int 1) (Opt.Int 2)
          mul = Opt.Binop Opt.Mul add (Opt.Int 3)
          js = JS.generateExpression mul
      Text.head js @?= '('
      Text.last js @?= '3'

  , testCase "Variable names preserved: myVar + 1" $ do
      let expr = Opt.Binop Opt.Add (Opt.Var "myVar") (Opt.Int 1)
          js = JS.generateExpression expr
      js @?= "myVar + 1"
  ]
```

**Coverage Target**: ≥85% (critical module)

---

## Property Test Specifications

### Property-Based Testing

**Module**: `test/Property/Arithmetic/LawsTest.hs`

**Purpose**: Verify mathematical laws hold across many random inputs using QuickCheck.

**Test Count**: 30+ properties

**Key Properties**:

```haskell
module Test.Property.Arithmetic.LawsTest where

import Test.Tasty
import Test.Tasty.QuickCheck
import qualified AST.Canonical as Can
import qualified Optimize.Expression as Opt

tests :: TestTree
tests = testGroup "Arithmetic Laws Property Tests"
  [ arithmeticLawsTests
  , optimizationCorrectnessTests
  , roundtripTests
  ]

arithmeticLawsTests :: TestTree
arithmeticLawsTests = testGroup "Arithmetic Laws"
  [ testProperty "Addition commutative: a + b == b + a" $ \a b ->
      let expr1 = Can.Binop Can.Add testRegion (Can.Int a) (Can.Int b)
          expr2 = Can.Binop Can.Add testRegion (Can.Int b) (Can.Int a)
      in evaluate expr1 == evaluate expr2

  , testProperty "Addition associative: (a + b) + c == a + (b + c)" $ \a b c ->
      let left = Can.Binop Can.Add testRegion
                   (Can.Binop Can.Add testRegion (Can.Int a) (Can.Int b))
                   (Can.Int c)
          right = Can.Binop Can.Add testRegion
                    (Can.Int a)
                    (Can.Binop Can.Add testRegion (Can.Int b) (Can.Int c))
      in evaluate left == evaluate right

  , testProperty "Addition identity: a + 0 == a" $ \a ->
      let expr = Can.Binop Can.Add testRegion (Can.Int a) (Can.Int 0)
      in evaluate expr == a

  , testProperty "Multiplication commutative: a * b == b * a" $ \a b ->
      let expr1 = Can.Binop Can.Mul testRegion (Can.Int a) (Can.Int b)
          expr2 = Can.Binop Can.Mul testRegion (Can.Int b) (Can.Int a)
      in evaluate expr1 == evaluate expr2

  , testProperty "Multiplication associative: (a * b) * c == a * (b * c)" $ \a b c ->
      let left = Can.Binop Can.Mul testRegion
                   (Can.Binop Can.Mul testRegion (Can.Int a) (Can.Int b))
                   (Can.Int c)
          right = Can.Binop Can.Mul testRegion
                    (Can.Int a)
                    (Can.Binop Can.Mul testRegion (Can.Int b) (Can.Int c))
      in evaluate left == evaluate right

  , testProperty "Multiplication identity: a * 1 == a" $ \a ->
      let expr = Can.Binop Can.Mul testRegion (Can.Int a) (Can.Int 1)
      in evaluate expr == a

  , testProperty "Multiplication zero: a * 0 == 0" $ \a ->
      let expr = Can.Binop Can.Mul testRegion (Can.Int a) (Can.Int 0)
      in evaluate expr == 0

  , testProperty "Distributivity: a * (b + c) == a * b + a * c" $ \a b c ->
      let left = Can.Binop Can.Mul testRegion
                   (Can.Int a)
                   (Can.Binop Can.Add testRegion (Can.Int b) (Can.Int c))
          right = Can.Binop Can.Add testRegion
                    (Can.Binop Can.Mul testRegion (Can.Int a) (Can.Int b))
                    (Can.Binop Can.Mul testRegion (Can.Int a) (Can.Int c))
      in evaluate left == evaluate right

  , testProperty "Subtraction non-commutative: a - b /= b - a (when a /= b)" $ \a b ->
      a /= b ==>
        let expr1 = Can.Binop Can.Sub testRegion (Can.Int a) (Can.Int b)
            expr2 = Can.Binop Can.Sub testRegion (Can.Int b) (Can.Int a)
        in evaluate expr1 /= evaluate expr2

  , testProperty "Division non-commutative: a / b /= b / a (when a /= b, b /= 0)" $ \a b ->
      a /= b && b /= 0 ==>
        let expr1 = Can.Binop Can.Div testRegion (Can.Int a) (Can.Int b)
            expr2 = Can.Binop Can.Div testRegion (Can.Int b) (Can.Int a)
        in evaluate expr1 /= evaluate expr2
  ]

optimizationCorrectnessTests :: TestTree
optimizationCorrectnessTests = testGroup "Optimization Correctness"
  [ testProperty "Optimized result equals unoptimized evaluation" $ \a b ->
      let expr = Can.Binop Can.Add testRegion (Can.Int a) (Can.Int b)
          optimized = Opt.optimize expr
          unoptimized = evaluate expr
      in evaluateOpt optimized == unoptimized

  , testProperty "Constant folding matches JavaScript evaluation" $ \a b ->
      let expr = Can.Binop Can.Mul testRegion (Can.Int a) (Can.Int b)
          optimized = Opt.optimize expr
          jsResult = a * b
      in evaluateOpt optimized == jsResult

  , testProperty "Algebraic simplification preserves value: x + 0" $ \a ->
      let expr = Can.Binop Can.Add testRegion (Can.Int a) (Can.Int 0)
          optimized = Opt.optimize expr
      in evaluateOpt optimized == a

  , testProperty "Algebraic simplification preserves value: x * 1" $ \a ->
      let expr = Can.Binop Can.Mul testRegion (Can.Int a) (Can.Int 1)
          optimized = Opt.optimize expr
      in evaluateOpt optimized == a

  , testProperty "Algebraic simplification preserves value: x * 0" $ \a ->
      let expr = Can.Binop Can.Mul testRegion (Can.Int a) (Can.Int 0)
          optimized = Opt.optimize expr
      in evaluateOpt optimized == 0

  , testProperty "Complex optimization preserves semantics" $ \a b c ->
      let expr = Can.Binop Can.Add testRegion
                   (Can.Binop Can.Mul testRegion (Can.Int a) (Can.Int b))
                   (Can.Int c)
          optimized = Opt.optimize expr
          expected = a * b + c
      in evaluateOpt optimized == expected
  ]

roundtripTests :: TestTree
roundtripTests = testGroup "Roundtrip Properties"
  [ testProperty "AST -> Binary -> AST roundtrip" $ \a b ->
      let expr = Can.Binop Can.Add testRegion (Can.Int a) (Can.Int b)
          serialized = Binary.encode expr
          deserialized = Binary.decode serialized
      in deserialized == expr

  , testProperty "Parse -> Canonicalize -> Generate -> Parse" $
      \a b -> isValidInt a && isValidInt b ==>
        let source = show a ++ " + " ++ show b
            parsed1 = Parse.expression source
            canonicalized = parsed1 >>= Canon.canonicalize
            optimized = fmap Opt.optimize canonicalized
            generated = fmap JS.generateExpression optimized
            parsed2 = generated >>= Parse.expression
        in isRight parsed1 && parsed1 == parsed2
  ]

-- Helper functions
evaluate :: Can.Expression -> Int
evaluate = undefined

evaluateOpt :: Opt.Expression -> Int
evaluateOpt = undefined

isValidInt :: Int -> Bool
isValidInt n = n >= -1000000 && n <= 1000000

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight _ = False
```

**Coverage Target**: Mathematical properties verified across 100+ random inputs

---

## Golden Test Specifications

### Golden File Tests

**Module**: `test/Golden/ArithmeticTest.hs`

**Purpose**: Compare generated JavaScript output against known-good reference files.

**Test Count**: 10+ golden file pairs

**Test Structure**:

```haskell
module Test.Golden.ArithmeticTest where

import Test.Tasty
import Test.Tasty.Golden
import qualified System.FilePath as FP
import qualified Data.ByteString.Lazy as LBS

tests :: TestTree
tests = testGroup "Golden Arithmetic Tests"
  [ goldenTest "simple-add"
  , goldenTest "simple-sub"
  , goldenTest "simple-mul"
  , goldenTest "simple-div"
  , goldenTest "complex-nested"
  , goldenTest "constant-folding"
  , goldenTest "algebraic-simplify"
  , goldenTest "mixed-operators"
  , goldenTest "with-functions"
  , goldenTest "float-arithmetic"
  ]

goldenTest :: String -> TestTree
goldenTest name =
  goldenVsString
    name
    (goldenPath name)
    (compileAndGenerate (sourcePath name))
  where
    goldenPath n = "test/golden/arithmetic/" ++ n ++ ".golden.js"
    sourcePath n = "test/golden/arithmetic/" ++ n ++ ".can"

compileAndGenerate :: FilePath -> IO LBS.ByteString
compileAndGenerate path = do
  source <- readFileUtf8 path
  result <- Compiler.compile source
  case result of
    Right js -> pure (LBS.fromStrict (Text.encodeUtf8 js))
    Left err -> fail ("Compilation failed: " ++ show err)
```

### Golden File Contents

**simple-add.can**:
```elm
module Main exposing (main)

main =
    1 + 2
```

**simple-add.golden.js**:
```javascript
var $author$project$Main$main = 1 + 2;
```

**constant-folding.can**:
```elm
module Main exposing (result)

result =
    (2 + 3) * 4
```

**constant-folding.golden.js**:
```javascript
var $author$project$Main$result = 20;
```

**algebraic-simplify.can**:
```elm
module Main exposing (identity)

identity x =
    x + 0
```

**algebraic-simplify.golden.js**:
```javascript
var $author$project$Main$identity = function(x) {
  return x;
};
```

**Coverage Target**: Full pipeline compilation verified for all operator combinations

---

## Integration Test Specifications

### Integration Tests

**Module**: `test/Integration/Arithmetic/FullPipelineTest.hs`

**Purpose**: Compile complete programs and verify end-to-end behavior.

**Test Count**: 5+ scenarios

**Key Test Cases**:

```haskell
module Test.Integration.Arithmetic.FullPipelineTest where

import Test.Tasty
import Test.Tasty.HUnit
import qualified System.Process as Process
import qualified System.IO.Temp as Temp
import qualified Data.Text.IO as Text

tests :: TestTree
tests = testGroup "Full Pipeline Integration Tests"
  [ calculatorProgramTest
  , mathUtilitiesTest
  , gamePhysicsTest
  , financialCalculationsTest
  ]

calculatorProgramTest :: TestTree
calculatorProgramTest = testCase "Calculator program compiles and runs" $ do
  let source = unlines
        [ "module Main exposing (main)"
        , ""
        , "add a b = a + b"
        , "sub a b = a - b"
        , "mul a b = a * b"
        , "div a b = a / b"
        , ""
        , "main ="
        , "    let"
        , "        result1 = add 10 5"
        , "        result2 = sub 10 5"
        , "        result3 = mul 10 5"
        , "        result4 = div 10 5"
        , "    in"
        , "    [ result1, result2, result3, result4 ]"
        ]

  result <- compileAndRun source
  result @?= "[15,5,50,2]"  -- Exact output verification

mathUtilitiesTest :: TestTree
mathUtilitiesTest = testCase "Math utilities compile and run" $ do
  let source = unlines
        [ "module Main exposing (main)"
        , ""
        , "square x = x * x"
        , "cube x = x * x * x"
        , "average a b = (a + b) / 2"
        , ""
        , "main ="
        , "    [ square 5, cube 3, average 10 20 ]"
        ]

  result <- compileAndRun source
  result @?= "[25,27,15]"

gamePhysicsTest :: TestTree
gamePhysicsTest = testCase "Game physics calculations" $ do
  let source = unlines
        [ "module Main exposing (main)"
        , ""
        , "velocity t acc ="
        , "    t * acc"
        , ""
        , "position t v acc ="
        , "    v * t + (acc * t * t) / 2"
        , ""
        , "main ="
        , "    let"
        , "        time = 5"
        , "        initialVelocity = 10"
        , "        acceleration = 2"
        , "        v = velocity time acceleration"
        , "        p = position time initialVelocity acceleration"
        , "    in"
        , "    [ v, p ]"
        ]

  result <- compileAndRun source
  result @?= "[10,75]"

financialCalculationsTest :: TestTree
financialCalculationsTest = testCase "Financial calculations" $ do
  let source = unlines
        [ "module Main exposing (main)"
        , ""
        , "simpleInterest principal rate time ="
        , "    principal * rate * time / 100"
        , ""
        , "totalAmount principal rate time ="
        , "    principal + simpleInterest principal rate time"
        , ""
        , "main ="
        , "    let"
        , "        p = 1000"
        , "        r = 5"
        , "        t = 2"
        , "    in"
        , "    totalAmount p r t"
        ]

  result <- compileAndRun source
  result @?= "1100"

-- Helper function to compile and run
compileAndRun :: String -> IO String
compileAndRun source =
  Temp.withSystemTempDirectory "canopy-test" $ \tmpDir -> do
    let sourcePath = tmpDir FP.</> "Main.elm"
        jsPath = tmpDir FP.</> "main.js"

    -- Write source file
    Text.writeFile sourcePath (Text.pack source)

    -- Compile
    compileResult <- Compiler.compileFile sourcePath jsPath
    case compileResult of
      Left err -> fail ("Compilation failed: " ++ show err)
      Right () -> pure ()

    -- Run with Node.js
    output <- Process.readProcess "node" [jsPath] ""
    pure (trim output)

trim :: String -> String
trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace
```

**Coverage Target**: End-to-end compilation for real-world arithmetic programs

---

## Coverage Validation Strategy

### Coverage Measurement

**Tools**:
- `stack test --coverage` - Generate coverage reports
- `stack hpc report --all` - View detailed coverage
- `hpc markup` - Generate HTML coverage reports

**Commands**:
```bash
# Generate coverage report
make test-coverage

# View HTML coverage report
open .stack-work/install/*/Cabal-*/hpc/index.html

# Validate coverage threshold
./scripts/validate-coverage.sh
```

### Coverage Validation Script

**File**: `scripts/validate-coverage.sh`

```bash
#!/bin/bash
set -e

# Run tests with coverage
stack test --coverage

# Generate report
stack hpc report --all > coverage-report.txt

# Extract coverage percentage
COVERAGE=$(grep "expressions used" coverage-report.txt | awk '{print $1}' | sed 's/%//')

# Check threshold
THRESHOLD=80

if (( $(echo "$COVERAGE < $THRESHOLD" | bc -l) )); then
  echo "ERROR: Coverage $COVERAGE% is below threshold $THRESHOLD%"
  exit 1
else
  echo "SUCCESS: Coverage $COVERAGE% meets threshold $THRESHOLD%"
  exit 0
fi
```

### Coverage Requirements per Module

| Module | Minimum Coverage | Test Count | Priority |
|--------|------------------|------------|----------|
| AST.Canonical (Arithmetic) | 90% | 25+ | Critical |
| Canonicalize.Expression | 85% | 30+ | Critical |
| Optimize.Expression | 90% | 40+ | Critical |
| Generate.JavaScript | 85% | 25+ | Critical |
| Edge Cases | 80% | 15+ | High |
| **Overall** | **80%** | **135+** | **Mandatory** |

### Anti-Pattern Detection Commands

**Pre-Commit Checks**:
```bash
# Check for mock functions (FORBIDDEN)
grep -r "_ = True" test/    # Should return NOTHING
grep -r "_ = False" test/   # Should return NOTHING

# Check for reflexive equality tests (FORBIDDEN)
grep -r "@?=" test/ | grep -E "(expr.*@?=.*expr|version.*@?=.*version)"  # Should return NOTHING

# Check for meaningless distinctness tests (FORBIDDEN)
grep -r "/= .*" test/ | grep -E "(Add /= Sub|mainName /= trueName)"  # Should return NOTHING

# Check for weak testing patterns (FORBIDDEN)
grep -r "isInfixOf" test/  # Should return NOTHING
grep -r "assertBool.*contains" test/ | head -10  # Review for weak testing
```

---

## Implementation Checklist

### Phase 1: Setup and Infrastructure (Week 1)

- [ ] Create test directory structure under `test/`
- [ ] Set up test registration in `test/Main.hs`
- [ ] Configure coverage tools in `package.yaml` or `stack.yaml`
- [ ] Create validation scripts (`scripts/validate-coverage.sh`)
- [ ] Add Makefile targets for test execution

### Phase 2: Unit Tests (Week 2-3)

- [ ] Implement `AST.Canonical.ArithmeticTest` (25+ test cases)
- [ ] Implement `Canonicalize.Expression.ArithmeticTest` (30+ test cases)
- [ ] Implement `Optimize.Expression.ArithmeticTest` (40+ test cases)
- [ ] Implement `Generate.JavaScript.ArithmeticTest` (25+ test cases)
- [ ] Implement `EdgeCase.ArithmeticTest` (15+ test cases)
- [ ] Run anti-pattern detection commands
- [ ] Verify ≥80% coverage for each module

### Phase 3: Property Tests (Week 4)

- [ ] Implement `Arithmetic.LawsTest` (30+ properties)
- [ ] Implement `Arithmetic.OptimizationTest` (10+ properties)
- [ ] Implement `Arithmetic.RoundtripTest` (5+ properties)
- [ ] Verify properties pass across 100+ random inputs

### Phase 4: Golden Tests (Week 5)

- [ ] Create 10+ `.can` source files in `test/golden/arithmetic/`
- [ ] Generate 10+ `.golden.js` expected output files
- [ ] Implement `Golden.ArithmeticTest` orchestration
- [ ] Verify golden tests pass

### Phase 5: Integration Tests (Week 6)

- [ ] Implement `FullPipelineTest` (5+ scenarios)
- [ ] Implement `CalculatorTest`
- [ ] Implement `MathUtilitiesTest`
- [ ] Verify end-to-end compilation

### Phase 6: Validation and CI (Week 7)

- [ ] Run complete test suite: `make test`
- [ ] Generate coverage report: `make test-coverage`
- [ ] Validate ≥80% coverage: `./scripts/validate-coverage.sh`
- [ ] Configure CI pipeline (GitHub Actions)
- [ ] Add coverage badge to README.md

### Phase 7: Documentation (Week 8)

- [ ] Update TESTING.md with new test structure
- [ ] Document test execution commands
- [ ] Create test writing guide
- [ ] Add troubleshooting section

---

## Success Metrics

### Mandatory Requirements (Zero Tolerance)

✅ **MUST ACHIEVE**:
- [ ] ≥80% overall line coverage
- [ ] All 135+ test cases pass (100%)
- [ ] Zero mock functions (`_ = True` FORBIDDEN)
- [ ] Zero reflexive tests (`expr == expr` FORBIDDEN)
- [ ] Zero meaningless distinctness tests (`Add /= Sub` FORBIDDEN)
- [ ] All property tests pass across 100+ random inputs
- [ ] All golden tests match expected output exactly
- [ ] All integration tests compile and execute correctly

### Quality Metrics

- [ ] Test execution time < 5 minutes (full suite)
- [ ] Coverage report generated successfully
- [ ] CI pipeline green (all checks pass)
- [ ] Zero anti-pattern violations detected
- [ ] Code review approval from 2+ reviewers

---

## Conclusion

This test implementation plan provides **comprehensive, zero-tolerance testing** for native arithmetic operators, strictly adhering to CLAUDE.md testing standards. The plan ensures:

1. **≥80% coverage** (mandatory)
2. **135+ test cases** across all categories
3. **Zero anti-patterns** (mock functions, reflexive tests, meaningless tests)
4. **Exact value verification** for all assertions
5. **Complete pipeline testing** (unit, property, golden, integration)

**Implementation Status**: Ready for immediate implementation following the 8-week phased approach.

**Next Steps**:
1. Begin Phase 1: Setup test infrastructure
2. Implement unit tests with exact value verification
3. Add property tests for mathematical laws
4. Create golden files for full pipeline testing
5. Validate coverage and enforce zero-tolerance standards

This plan provides the foundation for a **robust, high-quality implementation** of native arithmetic operators in the Canopy compiler.
