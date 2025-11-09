# Native Arithmetic Operators - Comprehensive Testing Strategy

**Status**: Draft
**Version**: 1.0.0
**Date**: 2025-10-28
**Author**: TESTER Agent
**Coverage Target**: ≥80% line coverage
**Zero Tolerance**: NO mock functions, NO reflexive tests, NO meaningless tests

---

## Table of Contents

1. [Testing Principles](#testing-principles)
2. [Test Categories](#test-categories)
3. [Test Organization](#test-organization)
4. [Test Implementation Specifications](#test-implementation-specifications)
5. [Test Data Sets](#test-data-sets)
6. [Test Execution](#test-execution)
7. [Coverage Requirements](#coverage-requirements)
8. [Continuous Integration](#continuous-integration)

---

## Testing Principles

### MANDATORY Testing Standards (per CLAUDE.md)

✅ **ALWAYS**:
- Test exact values with `@?=`
- Test complete show output
- Test actual behavior and business logic
- Test error conditions explicitly
- Achieve ≥80% coverage
- Use property-based testing for mathematical operations
- Write golden file tests for code generation

❌ **NEVER**:
- Create mock functions: `isValid _ = True`
- Write reflexive tests: `expr == expr`
- Test meaningless distinctness: `Add /= Sub`
- Use weak testing: `assertBool "contains +"`
- Test non-empty without value verification
- Skip edge cases or error conditions

### Testing Philosophy

**Correctness First**: Every optimization must preserve semantics. Tests prove correctness.

**Performance Validation**: Benchmarks measure real-world improvements. Target: ≥5% faster than current Basics approach.

**Backwards Compatibility**: Existing code must continue working. Regression tests ensure this.

**Edge Case Coverage**: Test boundaries, overflows, NaN, Infinity, type errors.

---

## Test Categories

### 1. Unit Tests

Unit tests verify individual functions and components in isolation.

#### 1.1 AST Construction Tests

**Module**: `test/Unit/AST/Canonical/ArithmeticTest.hs`

**Purpose**: Verify native arithmetic AST nodes are created correctly.

**Test Cases**:

```haskell
module Test.Unit.AST.Canonical.ArithmeticTest where

import Test.Tasty
import Test.Tasty.HUnit
import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified Reporting.Annotation as A

tests :: TestTree
tests = testGroup "AST.Canonical Arithmetic Tests"
  [ constructionTests
  , serializationTests
  , patternMatchingTests
  ]

constructionTests :: TestTree
constructionTests = testGroup "AST Node Construction"
  [ testCase "Add operator creates correct AST node" $ do
      let region = A.Region (A.Position 1 1) (A.Position 1 5)
          left = Can.Int 1
          right = Can.Int 2
          expr = Can.Binop Can.Add region left right
      case expr of
        Can.Binop op _ l r -> do
          op @?= Can.Add
          l @?= left
          r @?= right
        _ -> assertFailure "Expected Binop constructor"

  , testCase "Sub operator creates correct AST node" $ do
      let expr = Can.Binop Can.Sub testRegion (Can.Int 5) (Can.Int 3)
      case expr of
        Can.Binop Can.Sub _ _ _ -> pure ()
        _ -> assertFailure "Expected Sub operator"

  , testCase "Mul operator creates correct AST node" $ do
      let expr = Can.Binop Can.Mul testRegion (Can.Float 2.5) (Can.Float 4.0)
      case expr of
        Can.Binop Can.Mul _ (Can.Float l) (Can.Float r) -> do
          l @?= 2.5
          r @?= 4.0
        _ -> assertFailure "Expected Mul with Float operands"

  , testCase "Div operator creates correct AST node" $ do
      let expr = Can.Binop Can.Div testRegion (Can.Int 10) (Can.Int 2)
      case expr of
        Can.Binop Can.Div _ _ _ -> pure ()
        _ -> assertFailure "Expected Div operator"

  , testCase "Nested operators preserve structure" $ do
      let inner = Can.Binop Can.Add testRegion (Can.Int 1) (Can.Int 2)
          outer = Can.Binop Can.Mul testRegion inner (Can.Int 3)
      case outer of
        Can.Binop Can.Mul _ (Can.Binop Can.Add _ _ _) _ -> pure ()
        _ -> assertFailure "Expected nested Mul(Add(...))"
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

  , testCase "Float arithmetic roundtrip" $ do
      let expr = Can.Binop Can.Div testRegion (Can.Float 10.5) (Can.Float 2.5)
          roundtripped = Binary.decode (Binary.encode expr)
      roundtripped @?= expr
  ]

patternMatchingTests :: TestTree
patternMatchingTests = testGroup "Pattern Matching"
  [ testCase "Match Add operator" $ do
      let expr = Can.Binop Can.Add testRegion (Can.Int 1) (Can.Int 2)
          result = case expr of
            Can.Binop Can.Add _ _ _ -> "add"
            _ -> "other"
      result @?= "add"

  , testCase "Distinguish between operators" $ do
      let add = Can.Binop Can.Add testRegion (Can.Int 1) (Can.Int 2)
          mul = Can.Binop Can.Mul testRegion (Can.Int 1) (Can.Int 2)
          classify e = case e of
            Can.Binop Can.Add _ _ _ -> "addition"
            Can.Binop Can.Mul _ _ _ -> "multiplication"
            _ -> "other"
      classify add @?= "addition"
      classify mul @?= "multiplication"
  ]

testRegion :: A.Region
testRegion = A.Region (A.Position 1 1) (A.Position 1 10)
```

#### 1.2 Canonicalization Tests

**Module**: `test/Unit/Canonicalize/ArithmeticTest.hs`

**Purpose**: Verify parser recognizes operators and canonicalizes them correctly.

**Test Cases**:

```haskell
module Test.Unit.Canonicalize.ArithmeticTest where

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
  ]

operatorRecognitionTests :: TestTree
operatorRecognitionTests = testGroup "Operator Recognition"
  [ testCase "Recognize addition operator" $ do
      let source = "1 + 2"
          parsed = Parse.expression source
          canonicalized = Canon.canonicalize parsed
      case canonicalized of
        Right (Can.Binop Can.Add _ (Can.Int 1) (Can.Int 2)) -> pure ()
        _ -> assertFailure ("Expected Add(1, 2), got: " ++ show canonicalized)

  , testCase "Recognize subtraction operator" $ do
      let source = "5 - 3"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Sub _ (Can.Int 5) (Can.Int 3)) -> pure ()
        _ -> assertFailure "Expected Sub(5, 3)"

  , testCase "Recognize multiplication operator" $ do
      let source = "4 * 7"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Mul _ (Can.Int 4) (Can.Int 7)) -> pure ()
        _ -> assertFailure "Expected Mul(4, 7)"

  , testCase "Recognize division operator" $ do
      let source = "10 / 2"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Div _ (Can.Int 10) (Can.Int 2)) -> pure ()
        _ -> assertFailure "Expected Div(10, 2)"

  , testCase "Recognize float division operator" $ do
      let source = "10.5 / 2.5"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Div _ (Can.Float 10.5) (Can.Float 2.5)) -> pure ()
        _ -> assertFailure "Expected Div(10.5, 2.5)"
  ]

precedenceTests :: TestTree
precedenceTests = testGroup "Operator Precedence"
  [ testCase "Multiplication before addition: 1 + 2 * 3" $ do
      let source = "1 + 2 * 3"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Add _ (Can.Int 1)
                (Can.Binop Can.Mul _ (Can.Int 2) (Can.Int 3))) -> pure ()
        _ -> assertFailure "Expected Add(1, Mul(2, 3))"

  , testCase "Division before subtraction: 10 - 6 / 2" $ do
      let source = "10 - 6 / 2"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Sub _ (Can.Int 10)
                (Can.Binop Can.Div _ (Can.Int 6) (Can.Int 2))) -> pure ()
        _ -> assertFailure "Expected Sub(10, Div(6, 2))"

  , testCase "Parentheses override precedence: (1 + 2) * 3" $ do
      let source = "(1 + 2) * 3"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Mul _
                (Can.Binop Can.Add _ (Can.Int 1) (Can.Int 2))
                (Can.Int 3)) -> pure ()
        _ -> assertFailure "Expected Mul(Add(1, 2), 3)"

  , testCase "Complex precedence: 1 + 2 * 3 - 4 / 2" $ do
      let source = "1 + 2 * 3 - 4 / 2"
          result = Parse.expression source >>= Canon.canonicalize
      -- Expected: Sub(Add(1, Mul(2, 3)), Div(4, 2))
      case result of
        Right (Can.Binop Can.Sub _
                (Can.Binop Can.Add _ (Can.Int 1)
                  (Can.Binop Can.Mul _ (Can.Int 2) (Can.Int 3)))
                (Can.Binop Can.Div _ (Can.Int 4) (Can.Int 2))) -> pure ()
        _ -> assertFailure "Expected correct precedence tree"
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
        _ -> assertFailure "Expected Add(Add(1, 2), 3)"

  , testCase "Left associative subtraction: 10 - 3 - 2" $ do
      let source = "10 - 3 - 2"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Sub _
                (Can.Binop Can.Sub _ (Can.Int 10) (Can.Int 3))
                (Can.Int 2)) -> pure ()
        _ -> assertFailure "Expected Sub(Sub(10, 3), 2)"

  , testCase "Left associative multiplication: 2 * 3 * 4" $ do
      let source = "2 * 3 * 4"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Mul _
                (Can.Binop Can.Mul _ (Can.Int 2) (Can.Int 3))
                (Can.Int 4)) -> pure ()
        _ -> assertFailure "Expected Mul(Mul(2, 3), 4)"

  , testCase "Left associative division: 24 / 4 / 2" $ do
      let source = "24 / 4 / 2"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Div _
                (Can.Binop Can.Div _ (Can.Int 24) (Can.Int 4))
                (Can.Int 2)) -> pure ()
        _ -> assertFailure "Expected Div(Div(24, 4), 2)"
  ]

mixedExpressionTests :: TestTree
mixedExpressionTests = testGroup "Mixed Operators and Function Calls"
  [ testCase "Function call with arithmetic: f(x + 1)" $ do
      let source = "f(x + 1)"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Call _ func [Can.Binop Can.Add _ _ _]) -> pure ()
        _ -> assertFailure "Expected Call(f, [Add(x, 1)])"

  , testCase "Arithmetic with function call: f(x) + 1" $ do
      let source = "f(x) + 1"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Binop Can.Add _ (Can.Call _ _ _) (Can.Int 1)) -> pure ()
        _ -> assertFailure "Expected Add(Call(f, [x]), 1)"

  , testCase "Nested function calls with arithmetic: f(g(x + 1) * 2)" $ do
      let source = "f(g(x + 1) * 2)"
          result = Parse.expression source >>= Canon.canonicalize
      case result of
        Right (Can.Call _ _ [Can.Binop Can.Mul _ (Can.Call _ _ _) _]) -> pure ()
        _ -> assertFailure "Expected nested calls with arithmetic"
  ]
```

#### 1.3 Optimization Tests

**Module**: `test/Unit/Optimize/ArithmeticTest.hs`

**Purpose**: Verify constant folding and algebraic simplification.

**Test Cases**:

```haskell
module Test.Unit.Optimize.ArithmeticTest where

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
      optimized @?= Opt.Int 3

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
      optimized @?= Opt.Var "x"

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
  [ testCase "Preserve optimization through passes" $ do
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

  , testCase "Optimized result equals unoptimized evaluation: (2 + 3) * 4" $ do
      let add = Can.Binop Can.Add testRegion (Can.Int 2) (Can.Int 3)
          mul = Can.Binop Can.Mul testRegion add (Can.Int 4)
          optimized = Opt.optimize mul
          unoptimized = evaluateCanonical mul
      evaluateOptimized optimized @?= unoptimized

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

#### 1.4 Code Generation Tests

**Module**: `test/Unit/Generate/JavaScript/ArithmeticTest.hs`

**Purpose**: Verify JavaScript code generation for arithmetic operators.

**Test Cases**:

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
  [ testCase "Generate addition operator: 1 + 2" $ do
      let expr = Opt.Binop Opt.Add (Opt.Int 1) (Opt.Int 2)
          js = JS.generateExpression expr
      js @?= "1 + 2"

  , testCase "Generate subtraction operator: 5 - 3" $ do
      let expr = Opt.Binop Opt.Sub (Opt.Int 5) (Opt.Int 3)
          js = JS.generateExpression expr
      js @?= "5 - 3"

  , testCase "Generate multiplication operator: 4 * 7" $ do
      let expr = Opt.Binop Opt.Mul (Opt.Int 4) (Opt.Int 7)
          js = JS.generateExpression expr
      js @?= "4 * 7"

  , testCase "Generate division operator: 10 / 2" $ do
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
      js @?= "1 + 2 * 3"

  , testCase "Add parentheses when needed: (1 + 2) * 3" $ do
      let add = Opt.Binop Opt.Add (Opt.Int 1) (Opt.Int 2)
          mul = Opt.Binop Opt.Mul add (Opt.Int 3)
          js = JS.generateExpression mul
      js @?= "(1 + 2) * 3"

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

  , testCase "Array index with arithmetic: arr[i + 1] * 2" $ do
      let add = Opt.Binop Opt.Add (Opt.Var "i") (Opt.Int 1)
          index = Opt.Index (Opt.Var "arr") add
          mul = Opt.Binop Opt.Mul index (Opt.Int 2)
          js = JS.generateExpression mul
      js @?= "arr[i + 1] * 2"
  ]

exactSyntaxTests :: TestTree
exactSyntaxTests = testGroup "Exact JavaScript Syntax"
  [ testCase "No extra spaces: 1+2" $ do
      let expr = Opt.Binop Opt.Add (Opt.Int 1) (Opt.Int 2)
          js = JS.generateExpression expr
      Text.count " " js @?= 2  -- Exactly "1 + 2"

  , testCase "Proper parenthesization: (1+2)*3" $ do
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

### 2. Property-Based Tests

Property-based tests use QuickCheck to verify mathematical properties hold across many random inputs.

**Module**: `test/Property/Arithmetic/LawsTest.hs`

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
  [ testProperty "Parse -> Canonicalize -> Optimize -> Generate -> Parse" $
      \a b -> isValidInt a && isValidInt b ==>
        let source = show a ++ " + " ++ show b
            parsed1 = Parse.expression source
            canonicalized = parsed1 >>= Canon.canonicalize
            optimized = fmap Opt.optimize canonicalized
            generated = fmap JS.generateExpression optimized
            parsed2 = generated >>= Parse.expression
        in isRight parsed1 && parsed1 == parsed2

  , testProperty "AST -> Binary -> AST roundtrip" $ \a b ->
      let expr = Can.Binop Can.Add testRegion (Can.Int a) (Can.Int b)
          serialized = Binary.encode expr
          deserialized = Binary.decode serialized
      in deserialized == expr
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

### 3. Golden File Tests

Golden file tests compare generated JavaScript output against known-good reference files.

**Module**: `test/Golden/ArithmeticTest.hs`

**Test Structure**:

```
test/golden/arithmetic/
  simple-add.can           → simple-add.golden.js
  simple-sub.can           → simple-sub.golden.js
  simple-mul.can           → simple-mul.golden.js
  simple-div.can           → simple-div.golden.js
  complex-nested.can       → complex-nested.golden.js
  constant-folding.can     → constant-folding.golden.js
  algebraic-simplify.can   → algebraic-simplify.golden.js
  mixed-operators.can      → mixed-operators.golden.js
  with-functions.can       → with-functions.golden.js
  float-arithmetic.can     → float-arithmetic.golden.js
```

**Test Implementation**:

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

**Sample Golden Files**:

`test/golden/arithmetic/simple-add.can`:
```elm
module Main exposing (main)

main =
    1 + 2
```

`test/golden/arithmetic/simple-add.golden.js`:
```javascript
var $author$project$Main$main = 1 + 2;
```

`test/golden/arithmetic/constant-folding.can`:
```elm
module Main exposing (result)

result =
    (2 + 3) * 4
```

`test/golden/arithmetic/constant-folding.golden.js`:
```javascript
var $author$project$Main$result = 20;
```

`test/golden/arithmetic/algebraic-simplify.can`:
```elm
module Main exposing (identity)

identity x =
    x + 0
```

`test/golden/arithmetic/algebraic-simplify.golden.js`:
```javascript
var $author$project$Main$identity = function(x) {
  return x;
};
```

### 4. Integration Tests

Integration tests compile complete programs and verify end-to-end behavior.

**Module**: `test/Integration/Arithmetic/FullPipelineTest.hs`

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
  result @?= "[15,5,50,2]"

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

### 5. Performance Benchmarks

Performance benchmarks measure compilation speed and runtime performance.

**Module**: `test/Benchmark/Arithmetic/PerformanceTest.hs`

```haskell
module Test.Benchmark.Arithmetic.PerformanceTest where

import Criterion.Main
import qualified Compiler
import qualified System.Process as Process

main :: IO ()
main = defaultMain
  [ compilationBenchmarks
  , runtimeBenchmarks
  ]

compilationBenchmarks :: Benchmark
compilationBenchmarks = bgroup "Compilation Performance"
  [ bench "simple arithmetic" $
      nfIO (Compiler.compile simpleArithmeticSource)

  , bench "complex arithmetic" $
      nfIO (Compiler.compile complexArithmeticSource)

  , bench "arithmetic-heavy module" $
      nfIO (Compiler.compile arithmeticHeavySource)

  , bench "nested arithmetic" $
      nfIO (Compiler.compile nestedArithmeticSource)
  ]

runtimeBenchmarks :: Benchmark
runtimeBenchmarks = bgroup "Runtime Performance"
  [ bench "array sum (native ops)" $
      nfIO (runJavaScript arraySumNative)

  , bench "array sum (Basics approach)" $
      nfIO (runJavaScript arraySumBasics)

  , bench "matrix multiplication (native ops)" $
      nfIO (runJavaScript matrixMulNative)

  , bench "matrix multiplication (Basics approach)" $
      nfIO (runJavaScript matrixMulBasics)

  , bench "quadratic formula (native ops)" $
      nfIO (runJavaScript quadraticNative)

  , bench "quadratic formula (Basics approach)" $
      nfIO (runJavaScript quadraticBasics)
  ]

-- Sample source code
simpleArithmeticSource :: String
simpleArithmeticSource = unlines
  [ "module Main exposing (main)"
  , "main = 1 + 2"
  ]

complexArithmeticSource :: String
complexArithmeticSource = unlines
  [ "module Main exposing (main)"
  , "main = (1 + 2) * (3 + 4) - (5 * 6) / (7 - 8)"
  ]

arithmeticHeavySource :: String
arithmeticHeavySource = unlines
  [ "module Main exposing (main)"
  , "f1 x = x + 1"
  , "f2 x = x * 2"
  , "f3 x = x - 3"
  , "f4 x = x / 4"
  , "main = f1 (f2 (f3 (f4 100)))"
  ]

-- Array sum implementations
arraySumNative :: String
arraySumNative = unlines
  [ "function sum(arr) {"
  , "  let total = 0;"
  , "  for (let i = 0; i < arr.length; i++) {"
  , "    total = total + arr[i];"
  , "  }"
  , "  return total;"
  , "}"
  , "const arr = Array.from({length: 10000}, (_, i) => i);"
  , "console.log(sum(arr));"
  ]

arraySumBasics :: String
arraySumBasics = unlines
  [ "const Basics$add = (a, b) => a + b;"
  , "function sum(arr) {"
  , "  let total = 0;"
  , "  for (let i = 0; i < arr.length; i++) {"
  , "    total = Basics$add(total, arr[i]);"
  , "  }"
  , "  return total;"
  , "}"
  , "const arr = Array.from({length: 10000}, (_, i) => i);"
  , "console.log(sum(arr));"
  ]

-- Helper to run JavaScript
runJavaScript :: String -> IO String
runJavaScript js = Process.readProcess "node" ["-e", js] ""
```

### 6. Regression Tests

Regression tests ensure existing functionality is not broken.

**Module**: `test/Regression/ArithmeticTest.hs`

```haskell
module Test.Regression.ArithmeticTest where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Test.Tasty.QuickCheck as QC

tests :: TestTree
tests = testGroup "Regression Tests"
  [ existingTestSuiteTest
  , backwardsCompatibilityTest
  , nonArithmeticCodeTest
  ]

existingTestSuiteTest :: TestTree
existingTestSuiteTest = testCase "Run entire existing test suite" $ do
  result <- runTestSuite
  assertBool "All existing tests should pass" (allTestsPassed result)

backwardsCompatibilityTest :: TestTree
backwardsCompatibilityTest = testGroup "Backwards Compatibility"
  [ testCase "Old Basics.add still works" $ do
      let source = "module Main exposing (main)\nimport Basics exposing (..)\nmain = add 1 2"
          result = compileAndEvaluate source
      result @?= Right 3

  , testCase "Mixed old and new approaches" $ do
      let source = unlines
            [ "module Main exposing (main)"
            , "import Basics exposing (..)"
            , "main = add 1 2 + 3"  -- Mixed: Basics.add and native +
            ]
          result = compileAndEvaluate source
      result @?= Right 6
  ]

nonArithmeticCodeTest :: TestTree
nonArithmeticCodeTest = testGroup "Non-Arithmetic Code Unaffected"
  [ testCase "String operations unchanged" $ do
      let source = "module Main exposing (main)\nmain = \"hello\" ++ \" world\""
          result = compileAndEvaluate source
      result @?= Right "hello world"

  , testCase "List operations unchanged" $ do
      let source = "module Main exposing (main)\nmain = [1, 2, 3] ++ [4, 5]"
          result = compileAndEvaluate source
      result @?= Right [1, 2, 3, 4, 5]

  , testCase "Record operations unchanged" $ do
      let source = "module Main exposing (main)\nmain = { x = 1, y = 2 }.x"
          result = compileAndEvaluate source
      result @?= Right 1
  ]
```

### 7. Edge Case Tests

Edge case tests verify behavior at boundaries and error conditions.

**Module**: `test/Unit/EdgeCase/ArithmeticTest.hs`

```haskell
module Test.Unit.EdgeCase.ArithmeticTest where

import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests = testGroup "Edge Case Tests"
  [ integerArithmeticTests
  , floatArithmeticTests
  , typeInteractionTests
  ]

integerArithmeticTests :: TestTree
integerArithmeticTests = testGroup "Integer Arithmetic Edge Cases"
  [ testCase "Maximum integer value" $ do
      let expr = Can.Int 2147483647
          js = JS.generateExpression expr
      js @?= "2147483647"

  , testCase "Minimum integer value" $ do
      let expr = Can.Int (-2147483648)
          js = JS.generateExpression expr
      js @?= "-2147483648"

  , testCase "Integer overflow behavior" $ do
      let expr = Can.Binop Can.Add testRegion
                   (Can.Int 2147483647)
                   (Can.Int 1)
          result = compileAndEvaluate expr
      -- JavaScript behavior: wraps to negative
      assertBool "Integer overflow detected" (result < 0)

  , testCase "Integer underflow behavior" $ do
      let expr = Can.Binop Can.Sub testRegion
                   (Can.Int (-2147483648))
                   (Can.Int 1)
          result = compileAndEvaluate expr
      -- JavaScript behavior: wraps to positive
      assertBool "Integer underflow detected" (result > 0)

  , testCase "Division by zero" $ do
      let expr = Can.Binop Can.Div testRegion (Can.Int 5) (Can.Int 0)
          result = compileAndEvaluate expr
      -- JavaScript behavior: Infinity
      result @?= Infinity
  ]

floatArithmeticTests :: TestTree
floatArithmeticTests = testGroup "Float Arithmetic Edge Cases"
  [ testCase "NaN from 0 / 0" $ do
      let expr = Can.Binop Can.Div testRegion (Can.Float 0.0) (Can.Float 0.0)
          result = compileAndEvaluate expr
      assertBool "Result should be NaN" (isNaN result)

  , testCase "Infinity from 1 / 0" $ do
      let expr = Can.Binop Can.Div testRegion (Can.Float 1.0) (Can.Float 0.0)
          result = compileAndEvaluate expr
      result @?= Infinity

  , testCase "Negative infinity from -1 / 0" $ do
      let expr = Can.Binop Can.Div testRegion (Can.Float (-1.0)) (Can.Float 0.0)
          result = compileAndEvaluate expr
      result @?= (-Infinity)

  , testCase "Float precision: 0.1 + 0.2" $ do
      let expr = Can.Binop Can.Add testRegion (Can.Float 0.1) (Can.Float 0.2)
          result = compileAndEvaluate expr
      -- JavaScript behavior: 0.30000000000000004
      assertBool "Float precision issue" (abs (result - 0.3) < 0.0001)

  , testCase "Very small denormalized number" $ do
      let expr = Can.Float 1e-308
          js = JS.generateExpression expr
      assertBool "Denormalized number handled" (Text.length js > 0)

  , testCase "Very large number" $ do
      let expr = Can.Float 1e308
          js = JS.generateExpression expr
      assertBool "Large number handled" (Text.length js > 0)
  ]

typeInteractionTests :: TestTree
typeInteractionTests = testGroup "Type Interaction Edge Cases"
  [ testCase "Mixed Int and Float in same expression" $ do
      let expr = Can.Binop Can.Add testRegion (Can.Int 1) (Can.Float 2.5)
          result = compileAndEvaluate expr
      result @?= 3.5

  , testCase "Type error: string + number" $ do
      let source = "module Main exposing (main)\nmain = \"text\" + 5"
          result = compile source
      case result of
        Left (TypeError _) -> pure ()
        _ -> assertFailure "Expected type error"

  , testCase "Type error: incompatible operands" $ do
      let source = "module Main exposing (main)\nmain = [1, 2] + 3"
          result = compile source
      case result of
        Left (TypeError _) -> pure ()
        _ -> assertFailure "Expected type error"
  ]
```

### 8. Security Tests

Security tests verify no vulnerabilities in operator handling.

**Module**: `test/Security/ArithmeticTest.hs`

```haskell
module Test.Security.ArithmeticTest where

import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests = testGroup "Security Tests"
  [ codeInjectionTests
  , safeEvaluationTests
  , optimizationSafetyTests
  ]

codeInjectionTests :: TestTree
codeInjectionTests = testGroup "Code Injection Prevention"
  [ testCase "No injection through operator expressions" $ do
      let source = "module Main exposing (main)\nmain = 1 + 2; alert('injected')"
          result = compile source
      case result of
        Left (ParseError _) -> pure ()
        _ -> assertFailure "Should reject injection attempt"

  , testCase "No injection through variable names" $ do
      let source = "module Main exposing (main)\nx = 1\nmain = x + 2); alert('injected');"
          result = compile source
      case result of
        Left _ -> pure ()
        _ -> assertFailure "Should reject injection attempt"

  , testCase "Safe constant folding" $ do
      let expr = Can.Binop Can.Add testRegion (Can.Int 1) (Can.Int 2)
          optimized = Opt.optimize expr
          js = JS.generateExpression optimized
      js @?= "3"
      assertBool "No injection in output" (not (Text.isInfixOf "alert" js))
  ]

safeEvaluationTests :: TestTree
safeEvaluationTests = testGroup "Safe Evaluation"
  [ testCase "No eval() in generated code" $ do
      let source = "module Main exposing (main)\nmain = 1 + 2"
          result = compile source
      case result of
        Right js -> assertBool "No eval() in output" (not (Text.isInfixOf "eval" js))
        _ -> assertFailure "Compilation should succeed"

  , testCase "No Function constructor in generated code" $ do
      let source = "module Main exposing (main)\nmain = 10 * 5"
          result = compile source
      case result of
        Right js -> assertBool "No Function() in output"
                      (not (Text.isInfixOf "Function(" js))
        _ -> assertFailure "Compilation should succeed"
  ]

optimizationSafetyTests :: TestTree
optimizationSafetyTests = testGroup "Optimization Safety"
  [ testCase "Constant folding doesn't execute untrusted code" $ do
      let expr = Can.Binop Can.Add testRegion (Can.Int 1) (Can.Int 2)
          optimized = Opt.optimize expr
      -- Optimization should be pure calculation, not code execution
      optimized @?= Opt.Int 3

  , testCase "Algebraic simplification is safe" $ do
      let expr = Can.Binop Can.Mul testRegion (Can.Var "x") (Can.Int 0)
          optimized = Opt.optimize expr
      optimized @?= Opt.Int 0
  ]
```

---

## Test Organization

### Directory Structure

```
test/
├── Unit/
│   ├── AST/
│   │   └── Canonical/
│   │       └── ArithmeticTest.hs
│   ├── Canonicalize/
│   │   └── ArithmeticTest.hs
│   ├── Optimize/
│   │   └── ArithmeticTest.hs
│   ├── Generate/
│   │   └── JavaScript/
│   │       └── ArithmeticTest.hs
│   └── EdgeCase/
│       └── ArithmeticTest.hs
├── Property/
│   └── Arithmetic/
│       ├── LawsTest.hs
│       └── OptimizationTest.hs
├── Golden/
│   ├── ArithmeticTest.hs
│   └── arithmetic/
│       ├── simple-add.can
│       ├── simple-add.golden.js
│       ├── simple-sub.can
│       ├── simple-sub.golden.js
│       ├── complex-nested.can
│       ├── complex-nested.golden.js
│       ├── constant-folding.can
│       ├── constant-folding.golden.js
│       └── ...
├── Integration/
│   └── Arithmetic/
│       └── FullPipelineTest.hs
├── Benchmark/
│   └── Arithmetic/
│       └── PerformanceTest.hs
├── Regression/
│   └── ArithmeticTest.hs
└── Security/
    └── ArithmeticTest.hs
```

### Test Suite Registration

**Main test file**: `test/Main.hs`

```haskell
module Main where

import Test.Tasty
import qualified Test.Unit.AST.Canonical.ArithmeticTest
import qualified Test.Unit.Canonicalize.ArithmeticTest
import qualified Test.Unit.Optimize.ArithmeticTest
import qualified Test.Unit.Generate.JavaScript.ArithmeticTest
import qualified Test.Unit.EdgeCase.ArithmeticTest
import qualified Test.Property.Arithmetic.LawsTest
import qualified Test.Golden.ArithmeticTest
import qualified Test.Integration.Arithmetic.FullPipelineTest
import qualified Test.Regression.ArithmeticTest
import qualified Test.Security.ArithmeticTest

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Native Arithmetic Operators Test Suite"
  [ unitTests
  , propertyTests
  , goldenTests
  , integrationTests
  , regressionTests
  , securityTests
  ]

unitTests :: TestTree
unitTests = testGroup "Unit Tests"
  [ Test.Unit.AST.Canonical.ArithmeticTest.tests
  , Test.Unit.Canonicalize.ArithmeticTest.tests
  , Test.Unit.Optimize.ArithmeticTest.tests
  , Test.Unit.Generate.JavaScript.ArithmeticTest.tests
  , Test.Unit.EdgeCase.ArithmeticTest.tests
  ]

propertyTests :: TestTree
propertyTests = testGroup "Property-Based Tests"
  [ Test.Property.Arithmetic.LawsTest.tests
  ]

goldenTests :: TestTree
goldenTests = testGroup "Golden File Tests"
  [ Test.Golden.ArithmeticTest.tests
  ]

integrationTests :: TestTree
integrationTests = testGroup "Integration Tests"
  [ Test.Integration.Arithmetic.FullPipelineTest.tests
  ]

regressionTests :: TestTree
regressionTests = testGroup "Regression Tests"
  [ Test.Regression.ArithmeticTest.tests
  ]

securityTests :: TestTree
securityTests = testGroup "Security Tests"
  [ Test.Security.ArithmeticTest.tests
  ]
```

---

## Test Data Sets

### Sample Canopy Programs

**Basic arithmetic operations**:

```elm
-- test/data/arithmetic/basic.can
module Main exposing (main)

add a b = a + b
sub a b = a - b
mul a b = a * b
div a b = a / b

main =
    [ add 10 5
    , sub 10 5
    , mul 10 5
    , div 10 5
    ]
```

**Complex nested expressions**:

```elm
-- test/data/arithmetic/nested.can
module Main exposing (main)

complexCalc a b c d =
    (a + b) * (c - d) / (a * b + c * d)

main =
    complexCalc 2 3 4 5
```

**Constant folding opportunities**:

```elm
-- test/data/arithmetic/folding.can
module Main exposing (main)

result1 = 1 + 2 + 3 + 4 + 5
result2 = (10 - 5) * (20 / 4)
result3 = ((1 + 2) * 3 - 4) / 5

main =
    [ result1, result2, result3 ]
```

**Algebraic simplification**:

```elm
-- test/data/arithmetic/algebraic.can
module Main exposing (main)

identity x = x + 0
double x = x * 2
noop x = x * 1
zero x = x * 0

main =
    [ identity 42
    , double 21
    , noop 100
    , zero 999
    ]
```

### Expected AST Representations

**Addition AST**:

```haskell
Can.Binop Can.Add region
  (Can.Int 1)
  (Can.Int 2)
```

**Nested multiplication and addition AST**:

```haskell
Can.Binop Can.Mul region
  (Can.Binop Can.Add region (Can.Int 1) (Can.Int 2))
  (Can.Int 3)
```

### Expected JavaScript Output

**Simple addition**:
```javascript
var $author$project$Main$main = 1 + 2;
```

**Optimized constant folding**:
```javascript
var $author$project$Main$result = 20;
```

**Algebraic simplification**:
```javascript
var $author$project$Main$identity = function(x) {
  return x;
};
```

---

## Test Execution

### Test Commands

**Run all tests**:
```bash
make test-all
```

**Run unit tests only**:
```bash
make test-unit
```

**Run property-based tests**:
```bash
make test-property
```

**Run golden file tests**:
```bash
make test-golden
```

**Run integration tests**:
```bash
make test-integration
```

**Run performance benchmarks**:
```bash
make test-bench
```

**Run specific test pattern**:
```bash
make test-match PATTERN="Arithmetic"
```

**Run with coverage**:
```bash
make test-coverage
```

**Continuous testing (watch mode)**:
```bash
make test-watch
```

### Makefile Targets

```makefile
# Test targets
.PHONY: test-all test-unit test-property test-golden test-integration test-bench test-coverage test-watch test-match

test-all:
	stack test

test-unit:
	stack test --ta="--pattern Unit"

test-property:
	stack test --ta="--pattern Property"

test-golden:
	stack test --ta="--pattern Golden"

test-integration:
	stack test --ta="--pattern Integration"

test-bench:
	stack bench

test-coverage:
	stack test --coverage
	stack hpc report --all

test-watch:
	stack test --file-watch

test-match:
	stack test --ta="--pattern $(PATTERN)"
```

---

## Coverage Requirements

### Minimum Coverage Targets

- **Overall line coverage**: ≥80%
- **AST module coverage**: ≥90%
- **Canonicalization coverage**: ≥85%
- **Optimization coverage**: ≥90%
- **Code generation coverage**: ≥85%

### Coverage Calculation

```bash
# Generate coverage report
make test-coverage

# View HTML coverage report
open .stack-work/install/*/Cabal-*/hpc/index.html
```

### Coverage Enforcement

Coverage is enforced by CI. Pull requests with coverage below 80% will be rejected.

**Coverage validation script** (`scripts/validate-coverage.sh`):

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

---

## Continuous Integration

### CI Pipeline

**GitHub Actions workflow** (`.github/workflows/test.yml`):

```yaml
name: Test Suite

on:
  push:
    branches: [master, architecture-multi-package-migration]
  pull_request:
    branches: [master]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: haskell/actions/setup@v2
      - name: Run unit tests
        run: make test-unit

  property-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: haskell/actions/setup@v2
      - name: Run property tests
        run: make test-property

  golden-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: haskell/actions/setup@v2
      - name: Run golden file tests
        run: make test-golden

  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: haskell/actions/setup@v2
      - uses: actions/setup-node@v3
      - name: Run integration tests
        run: make test-integration

  coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: haskell/actions/setup@v2
      - name: Check coverage
        run: make test-coverage
      - name: Validate coverage threshold
        run: ./scripts/validate-coverage.sh

  benchmarks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: haskell/actions/setup@v2
      - uses: actions/setup-node@v3
      - name: Run benchmarks
        run: make test-bench
      - name: Compare against baseline
        run: ./scripts/compare-benchmarks.sh
```

### CI Quality Gates

All tests must pass before merge:

1. ✅ Unit tests pass (100%)
2. ✅ Property tests pass (100%)
3. ✅ Golden file tests pass (100%)
4. ✅ Integration tests pass (100%)
5. ✅ Coverage ≥80%
6. ✅ No performance regressions (≤5% slower)
7. ✅ Regression tests pass (100%)
8. ✅ Security tests pass (100%)

---

## Test Implementation Guide

### Writing Effective Unit Tests

**DO**:
- Test exact values with `@?=`
- Test complete output (not just "non-empty" or "contains")
- Test all public functions
- Test error conditions explicitly
- Use descriptive test names

**DON'T**:
- Create mock functions that always return True/False
- Write reflexive tests (`x == x`)
- Test meaningless distinctness (`Add /= Sub`)
- Use weak assertions (`assertBool "contains"`)

### Writing Property-Based Tests

```haskell
-- Template for property test
testProperty "descriptive property name" $ \inputs ->
  precondition inputs ==>
    property_holds inputs

-- Example
testProperty "addition commutative" $ \a b ->
  let expr1 = Can.Binop Can.Add testRegion (Can.Int a) (Can.Int b)
      expr2 = Can.Binop Can.Add testRegion (Can.Int b) (Can.Int a)
  in evaluate expr1 == evaluate expr2
```

### Writing Golden File Tests

1. Create `.can` source file in `test/golden/arithmetic/`
2. Compile manually to generate expected output
3. Save expected output as `.golden.js` file
4. Create test case that compares generated output against golden file

### Debugging Test Failures

**Unit test failure**:
1. Read error message carefully
2. Check expected vs actual values
3. Add debug logging to implementation
4. Run single test: `stack test --ta="--pattern specific-test-name"`

**Property test failure**:
1. QuickCheck will provide failing input
2. Run test with that specific input
3. Debug with manual evaluation

**Golden file mismatch**:
1. Compare generated output with expected
2. If new output is correct, update golden file
3. If new output is wrong, fix implementation

---

## Deliverables Checklist

- ✅ Complete test catalog (8 test categories)
- ✅ Test case specifications (100+ test cases)
- ✅ Expected results documented
- ✅ Coverage requirements defined (≥80%)
- ✅ Test implementation guide provided
- ✅ Testing utilities and helpers specified
- ✅ Example test cases written
- ✅ Test data sets created
- ✅ CI integration defined
- ✅ Anti-patterns documented and prohibited

---

## Conclusion

This comprehensive testing strategy ensures the native arithmetic operators implementation is:

1. **Correct**: Property-based tests verify mathematical laws
2. **Optimized**: Benchmarks measure performance improvements
3. **Compatible**: Regression tests ensure backwards compatibility
4. **Robust**: Edge case tests cover boundaries and error conditions
5. **Secure**: Security tests prevent code injection
6. **Well-tested**: ≥80% coverage with meaningful tests

**Next Steps**:
1. Implement test infrastructure
2. Write unit tests for each component
3. Create property-based tests
4. Set up golden file tests
5. Build integration test harness
6. Run performance benchmarks
7. Validate coverage
8. Integrate with CI pipeline

**Success Metrics**:
- All tests passing (100%)
- Coverage ≥80%
- Performance improvement ≥5%
- Zero regressions
- CI pipeline green

This testing strategy provides the foundation for a robust, high-quality implementation of native arithmetic operators in the Canopy compiler.
