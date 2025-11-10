# Constant Folding and Algebraic Simplification Design

**Version:** 1.0
**Date:** 2025-10-28
**Status:** Design Phase
**Target:** Canopy Compiler v0.19.2+

## Executive Summary

This document defines a comprehensive constant folding and algebraic simplification system for native arithmetic operators in the Canopy compiler. The optimization pass will evaluate constant arithmetic at compile-time and simplify algebraic patterns while maintaining exact JavaScript semantics and ensuring zero semantic changes.

## Table of Contents

1. [Background and Motivation](#background-and-motivation)
2. [Current Architecture Analysis](#current-architecture-analysis)
3. [Optimization Rules Specification](#optimization-rules-specification)
4. [Implementation Design](#implementation-design)
5. [Safety and Correctness](#safety-and-correctness)
6. [Test Strategy](#test-strategy)
7. [Performance Impact](#performance-impact)
8. [Future Extensions](#future-extensions)

---

## Background and Motivation

### Problem Statement

The Canopy compiler currently generates JavaScript code that calls Basics functions for arithmetic operations:
- `Basics.add 1 2` → `1 + 2` (native operator emission exists)
- However, constant expressions like `1 + 2` are not folded at compile-time
- Algebraic identities like `x + 0` → `x` are not simplified
- Complex constant expressions like `(2 + 3) * 4` compute at runtime

### Goals

1. **Compile-time constant evaluation**: Fold all constant arithmetic to literal values
2. **Algebraic simplification**: Apply identity laws and strength reduction
3. **Zero semantic changes**: Maintain exact JavaScript behavior including edge cases
4. **Performance improvement**: Reduce runtime computation and code size
5. **Maintainability**: Clean, testable, well-documented optimization passes

### Non-Goals

- Floating-point optimizations that violate IEEE 754 semantics
- Cross-function constant propagation (future work)
- Optimizations requiring data flow analysis (future work)
- Auto-parallelization or vectorization

---

## Current Architecture Analysis

### Expression Pipeline

```
Source AST (Parse/Expression.hs)
    ↓ Parse arithmetic as Binop
Canonical AST (AST/Canonical.hs)
    ↓ Can.Binop with resolved home module
Optimized AST (AST/Optimized.hs)
    ↓ Opt.Call to Basics functions
    ↓ [NEW: Constant Folding Pass]
    ↓ Simplified Opt.Expr
Code Generation (Generate/JavaScript/Expression.hs)
    ↓ generateBasicsCall emits native JS operators
JavaScript Output
```

### Current Arithmetic Handling

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Generate/JavaScript/Expression.hs`

**Lines 549-564:** Native operator emission
```haskell
"add" -> JS.Infix JS.OpAdd left right
"sub" -> JS.Infix JS.OpSub left right
"mul" -> JS.Infix JS.OpMul left right
"fdiv" -> JS.Infix JS.OpDiv left right
"idiv" -> JS.Infix JS.OpBitwiseOr (JS.Infix JS.OpDiv left right) (JS.Int 0)
"remainderBy" -> JS.Infix JS.OpMod right left
```

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Optimize/Expression.hs`

**Lines 65-70:** Binop optimization (current - just transforms to Call)
```haskell
Can.Binop _ home name _ left right ->
  do
    optFunc <- Names.registerGlobal home name
    optLeft <- optimize cycle left
    optRight <- optimize cycle right
    return (Opt.Call optFunc [optLeft, optRight])
```

### Key Observations

1. **Operator representation**: Arithmetic is represented as `Opt.Call` to Basics functions
2. **Native emission**: Code generation already emits native JS operators for Basics calls
3. **No constant folding**: Constants are passed through unchanged to codegen
4. **Optimization location**: Best place is in `Optimize.Expression.optimize` before creating `Opt.Call`
5. **Type safety**: Optimized AST has distinct `Opt.Int` and `Opt.Float` constructors

---

## Optimization Rules Specification

### Category 1: Constant Folding

Evaluate constant arithmetic at compile-time. Must exactly match JavaScript semantics.

#### Integer Arithmetic

| Expression | Result | Notes |
|------------|--------|-------|
| `1 + 2` | `3` | Standard addition |
| `10 - 3` | `7` | Standard subtraction |
| `3 * 4` | `12` | Standard multiplication |
| `10 / 2` | `5` (as Int) | Integer division (idiv), truncates |
| `10 // 3` | `3` | Explicit integer division |
| `10 % 3` | `1` | Modulo/remainder |
| `2 ^ 3` | `8` | Power/exponentiation |
| `-5` | `-5` | Unary negation |

**Safety Constraints:**
- Overflow detection: JavaScript numbers are IEEE 754 doubles
  - Safe integer range: -(2^53 - 1) to (2^53 - 1)
  - Beyond this, precision loss occurs
  - Rule: Only fold if result stays within safe range
- Division by zero: Must preserve runtime behavior
  - `x / 0` → Keep as expression (runtime produces `Infinity`)
  - `0 / 0` → Keep as expression (runtime produces `NaN`)
- Modulo by zero: `x % 0` → Keep as expression (runtime produces `NaN`)

#### Float Arithmetic

| Expression | Result | Notes |
|------------|--------|-------|
| `1.5 + 2.5` | `4.0` | Float addition |
| `10.5 - 3.2` | `7.3` | Float subtraction |
| `3.5 * 2.0` | `7.0` | Float multiplication |
| `10.0 / 4.0` | `2.5` | Float division |
| `2.5 ^ 2.0` | `6.25` | Float power |
| `-3.14` | `-3.14` | Float negation |

**Safety Constraints:**
- IEEE 754 compliance: Must exactly match JavaScript floating-point behavior
  - Respect rounding modes (round-to-nearest-even)
  - Preserve special values: `NaN`, `Infinity`, `-Infinity`, `-0.0`
  - Test against Node.js/V8 output for verification
- No "unsafe" optimizations:
  - ❌ `x - x` → `0` (may be NaN if x is NaN)
  - ❌ `x / x` → `1` (may be NaN if x is 0 or NaN)
  - ❌ `x + 0.0` → `x` (doesn't preserve -0.0)

#### Mixed-Type Handling

Canopy is statically typed, so mixed Int/Float expressions shouldn't exist after type checking. However, be defensive:

- If both operands are `Opt.Int`, result is `Opt.Int` (with overflow checking)
- If either operand is `Opt.Float`, result is `Opt.Float`
- Never silently convert types

### Category 2: Algebraic Simplification

Simplify expressions using mathematical identities. Must preserve semantics.

#### Identity Laws (Safe for Integers)

| Pattern | Simplification | Safety Condition |
|---------|----------------|------------------|
| `x + 0` | `x` | Always safe for integers |
| `0 + x` | `x` | Always safe for integers |
| `x - 0` | `x` | Always safe |
| `x * 1` | `x` | Always safe |
| `1 * x` | `x` | Always safe |
| `x / 1` | `x` | Always safe (division by 1) |

#### Absorption Laws

| Pattern | Simplification | Safety Condition |
|---------|----------------|------------------|
| `x * 0` | `0` | Safe for integers |
| `0 * x` | `0` | Safe for integers |
| `0 / x` | `0` | Only if x ≠ 0 (difficult to prove, skip) |

**Decision:** Only apply `x * 0` → `0` and `0 * x` → `0` for integer constants. Skip for floats due to NaN propagation.

#### Negation Laws

| Pattern | Simplification | Safety Condition |
|---------|----------------|------------------|
| `-(-(x))` | `x` | Always safe (double negation) |
| `x - x` | `0` | ❌ Skip (may be NaN for floats) |
| `0 - x` | `-x` | Always safe (negation) |

#### Constant Reassociation

Fold constants when they appear with variables:

| Pattern | Simplification | Safety Condition |
|---------|----------------|------------------|
| `(x + 2) + 3` | `x + 5` | Safe for integers (check overflow) |
| `(x * 2) * 3` | `x * 6` | Safe for integers (check overflow) |
| `(2 + x) + 3` | `5 + x` | Safe for integers (check overflow) |
| `2 + (x + 3)` | `x + 5` | Safe for integers (check overflow) |

**Algorithm:**
1. Detect pattern: `(constant op variable) op constant`
2. Evaluate: `constant1 op constant2`
3. Check: Result within safe range
4. Transform: `variable op result`

### Category 3: Strength Reduction

Replace expensive operations with cheaper equivalents.

#### Power-of-Two Optimizations (Future Work)

| Pattern | Simplification | Safety Condition |
|---------|----------------|------------------|
| `x * 2` | `x + x` | May improve perf (test benchmarks) |
| `x / 2` (float) | `x * 0.5` | Must verify IEEE 754 equivalence |
| `x % (2^n)` | `x & ((2^n) - 1)` | Only for positive integers |

**Decision:** Skip for initial implementation. Requires careful benchmarking and platform testing.

### Category 4: Pattern Recognition

#### Dead Code

| Pattern | Simplification | Safety Condition |
|---------|----------------|------------------|
| `x * 0` | `0` | Safe for integers only |
| `0 * x` | `0` | Safe for integers only |

#### Idempotent Operations

| Pattern | Simplification | Safety Condition |
|---------|----------------|------------------|
| `abs (abs x)` | `abs x` | Always safe |

---

## Implementation Design

### Module Structure

Create new module: `/home/quinten/fh/canopy/packages/canopy-core/src/Optimize/Arithmetic.hs`

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Optimize.Arithmetic
  ( foldConstants
  , simplifyArithmetic
  ) where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Name as Name

-- | Entry point: Try to fold/simplify an arithmetic call.
--
-- Takes a Basics operator call and attempts constant folding
-- and algebraic simplification. Returns simplified expression
-- or original call if no optimization applies.
foldConstants
  :: Opt.Global     -- ^ Operator global reference
  -> [Opt.Expr]     -- ^ Operator arguments
  -> Maybe Opt.Expr -- ^ Simplified result (Nothing = no optimization)

-- | Simplify arithmetic using algebraic identities.
--
-- Applies identity laws, absorption, and reassociation rules.
-- Only performs semantics-preserving transformations.
simplifyArithmetic
  :: Name.Name      -- ^ Operator name (add, mul, etc.)
  -> Opt.Expr       -- ^ Left operand
  -> Opt.Expr       -- ^ Right operand
  -> Maybe Opt.Expr -- ^ Simplified result (Nothing = no optimization)
```

### Integration Point

Modify `/home/quinten/fh/canopy/packages/canopy-core/src/Optimize/Expression.hs`:

```haskell
-- Line 65-70, replace Binop case with:
Can.Binop _ home name _ left right ->
  do
    optLeft <- optimize cycle left
    optRight <- optimize cycle right
    optFunc <- Names.registerGlobal home name

    -- Try constant folding and algebraic simplification
    case Arithmetic.foldConstants optFunc [optLeft, optRight] of
      Just simplified -> pure simplified
      Nothing -> return (Opt.Call optFunc [optLeft, optRight])
```

### Core Implementation Functions

#### 1. Constant Evaluation Engine

```haskell
-- | Evaluate constant integer operation safely.
--
-- Checks for overflow and division by zero.
-- Returns Nothing if result cannot be safely computed.
evalIntOp :: Name.Name -> Int -> Int -> Maybe Int
evalIntOp op x y = case op of
  "add" -> safeAdd x y
  "sub" -> safeSub x y
  "mul" -> safeMul x y
  "idiv" -> safeIdiv x y
  "remainderBy" -> safeRemainder y x  -- Note: reversed args
  _ -> Nothing

-- | Safe integer addition with overflow checking.
safeAdd :: Int -> Int -> Maybe Int
safeAdd x y =
  let result = x + y
  in if inSafeRange result
       then Just result
       else Nothing

-- | Safe range for JavaScript integers (2^53 - 1).
inSafeRange :: Int -> Bool
inSafeRange n =
  n >= -(2^(53::Int) - 1) && n <= (2^(53::Int) - 1)

-- | Safe integer division (truncates toward zero).
safeIdiv :: Int -> Int -> Maybe Int
safeIdiv _ 0 = Nothing  -- Division by zero
safeIdiv x y = Just (x `div` y)
```

#### 2. Float Evaluation Engine

```haskell
-- | Evaluate constant float operation.
--
-- Must exactly match JavaScript IEEE 754 behavior.
evalFloatOp :: Name.Name -> Double -> Double -> Maybe Double
evalFloatOp op x y = case op of
  "add" -> Just (x + y)
  "sub" -> Just (x - y)
  "mul" -> Just (x * y)
  "fdiv" -> Just (x / y)  -- JavaScript allows Infinity
  _ -> Nothing
```

**Critical:** Float operations must be tested against JavaScript output:

```javascript
// Test cases to generate reference values
console.log(1.5 + 2.5);      // 4.0
console.log(Infinity + 1);    // Infinity
console.log(NaN + 1);         // NaN
console.log(0.1 + 0.2);       // 0.30000000000000004 (rounding)
```

#### 3. Pattern Matching Engine

```haskell
-- | Try to simplify using algebraic identities.
simplifyPattern :: Name.Name -> Opt.Expr -> Opt.Expr -> Maybe Opt.Expr
simplifyPattern op left right = case op of
  "add" -> simplifyAdd left right
  "sub" -> simplifySub left right
  "mul" -> simplifyMul left right
  "fdiv" -> simplifyDiv left right
  _ -> Nothing

-- | Simplify addition patterns.
simplifyAdd :: Opt.Expr -> Opt.Expr -> Maybe Opt.Expr
simplifyAdd left right = case (left, right) of
  -- x + 0 = x (integers only)
  (expr, Opt.Int 0) -> Just expr
  (Opt.Int 0, expr) -> Just expr

  -- (x + c1) + c2 = x + (c1 + c2)
  (Opt.Call f [x, Opt.Int c1], Opt.Int c2)
    | isAddOperator f -> safeAdd c1 c2 >>= \sum ->
        Just (Opt.Call f [x, Opt.Int sum])

  _ -> Nothing

-- | Check if global reference is addition operator.
isAddOperator :: Opt.Expr -> Bool
isAddOperator (Opt.VarGlobal (Opt.Global home name)) =
  home == ModuleName.basics && name == Name.fromChars "add"
isAddOperator _ = False
```

### Full Function Signatures

```haskell
-- Main API
foldConstants :: Opt.Global -> [Opt.Expr] -> Maybe Opt.Expr
simplifyArithmetic :: Name.Name -> Opt.Expr -> Opt.Expr -> Maybe Opt.Expr

-- Constant evaluation
evalIntOp :: Name.Name -> Int -> Int -> Maybe Int
evalFloatOp :: Name.Name -> Double -> Double -> Maybe Double

-- Safety checking
inSafeRange :: Int -> Bool
safeAdd :: Int -> Int -> Maybe Int
safeSub :: Int -> Int -> Maybe Int
safeMul :: Int -> Int -> Maybe Int
safeIdiv :: Int -> Int -> Maybe Int
safeRemainder :: Int -> Int -> Maybe Int

-- Pattern matching
simplifyPattern :: Name.Name -> Opt.Expr -> Opt.Expr -> Maybe Opt.Expr
simplifyAdd :: Opt.Expr -> Opt.Expr -> Maybe Opt.Expr
simplifySub :: Opt.Expr -> Opt.Expr -> Maybe Opt.Expr
simplifyMul :: Opt.Expr -> Opt.Expr -> Maybe Opt.Expr
simplifyDiv :: Opt.Expr -> Opt.Expr -> Maybe Opt.Expr

-- Utilities
isBasicsOperator :: Opt.Global -> Name.Name -> Bool
extractConstant :: Opt.Expr -> Maybe (Either Int Double)
isZero :: Opt.Expr -> Bool
isOne :: Opt.Expr -> Bool
```

---

## Safety and Correctness

### Semantic Preservation Guarantee

**Invariant:** `∀ expr. optimize(expr) ≡ expr (semantically)`

Every optimization must preserve exact JavaScript runtime behavior:

1. **Same result**: Optimized code produces identical output
2. **Same side effects**: No change to evaluation order (though arithmetic is pure)
3. **Same edge cases**: NaN, Infinity, -0.0, overflow all preserved
4. **Same types**: No implicit type conversions

### Safety Checklist

For each optimization rule:

- [ ] **Documented**: Rule clearly stated with preconditions
- [ ] **Tested**: Property test + golden test + edge case tests
- [ ] **Proven correct**: Mathematical proof or extensive fuzzing
- [ ] **JavaScript verified**: Reference implementation tested in Node.js
- [ ] **Overflow safe**: Range checking for integer operations
- [ ] **IEEE 754 safe**: Float operations match JavaScript exactly

### Edge Case Handling

#### Division by Zero

```haskell
-- ❌ WRONG: Fold 5 / 0 to error
evalIntOp "fdiv" 5 0 = error "Division by zero"

-- ✅ CORRECT: Keep as expression, let runtime handle
evalIntOp "fdiv" _ 0 = Nothing  -- Don't optimize
```

**Rationale:** JavaScript produces `Infinity` for division by zero. The compiler must not change this runtime behavior.

#### Integer Overflow

```haskell
-- Example: 2^60 overflows safe integer range
safeAdd (2^59) (2^59) = Nothing  -- Don't fold

-- Example: Within range
safeAdd 1000 2000 = Just 3000  -- Safe to fold
```

#### Float Special Values

```haskell
-- Preserve NaN propagation
evalFloatOp "add" x y
  | isNaN x || isNaN y = Just (0/0)  -- Explicit NaN
  | otherwise = Just (x + y)

-- Preserve Infinity
evalFloatOp "mul" x y
  | isInfinite x || isInfinite y = Just (x * y)
  | otherwise = Just (x * y)
```

### Verification Strategy

1. **Property tests**: QuickCheck for arithmetic laws
2. **Golden tests**: Reference JavaScript outputs
3. **Fuzzing**: Random expression generation and comparison
4. **Manual review**: Every rule reviewed by two engineers

---

## Test Strategy

### Test Structure

```
test/Unit/Optimize/ArithmeticTest.hs         -- Unit tests
test/Property/Optimize/ArithmeticProps.hs     -- Property tests
test/Golden/Optimize/Arithmetic/*.golden      -- Golden files
test/Integration/ArithmeticOptimization.hs    -- End-to-end tests
```

### Unit Tests

**File:** `/home/quinten/fh/canopy/test/Unit/Optimize/ArithmeticTest.hs`

```haskell
module Unit.Optimize.ArithmeticTest (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Optimize.Arithmetic as Arith
import qualified AST.Optimized as Opt

tests :: TestTree
tests = testGroup "Optimize.Arithmetic Tests"
  [ constantFoldingTests
  , algebraicSimplificationTests
  , safetyTests
  , edgeCaseTests
  ]

constantFoldingTests :: TestTree
constantFoldingTests = testGroup "Constant Folding"
  [ testCase "Fold 1 + 2 to 3" $ do
      let expr = makeAddCall (Opt.Int 1) (Opt.Int 2)
      foldConstants expr @?= Just (Opt.Int 3)

  , testCase "Fold 10 * 5 to 50" $ do
      let expr = makeMulCall (Opt.Int 10) (Opt.Int 5)
      foldConstants expr @?= Just (Opt.Int 50)

  , testCase "Fold (2 + 3) * 4 to 20" $ do
      let inner = makeAddCall (Opt.Int 2) (Opt.Int 3)
          expr = makeMulCall inner (Opt.Int 4)
      -- After two passes
      foldConstants expr @?= Just (Opt.Int 20)

  , testCase "Don't fold 5 / 0" $ do
      let expr = makeDivCall (Opt.Int 5) (Opt.Int 0)
      foldConstants expr @?= Nothing  -- Keep as expression
  ]

algebraicSimplificationTests :: TestTree
algebraicSimplificationTests = testGroup "Algebraic Simplification"
  [ testCase "Simplify x + 0 to x" $ do
      let varX = Opt.VarLocal (Name.fromChars "x")
          expr = makeAddCall varX (Opt.Int 0)
      simplifyArithmetic "add" varX (Opt.Int 0) @?= Just varX

  , testCase "Simplify x * 1 to x" $ do
      let varX = Opt.VarLocal (Name.fromChars "x")
      simplifyArithmetic "mul" varX (Opt.Int 1) @?= Just varX

  , testCase "Simplify x * 0 to 0" $ do
      let varX = Opt.VarLocal (Name.fromChars "x")
      simplifyArithmetic "mul" varX (Opt.Int 0) @?= Just (Opt.Int 0)
  ]

safetyTests :: TestTree
safetyTests = testGroup "Safety and Correctness"
  [ testCase "Don't fold overflow: 2^60 + 2^60" $ do
      let huge = 2^(60::Int)
          expr = makeAddCall (Opt.Int huge) (Opt.Int huge)
      foldConstants expr @?= Nothing  -- Overflow, don't optimize

  , testCase "Don't fold 0 / 0" $ do
      let expr = makeDivCall (Opt.Int 0) (Opt.Int 0)
      foldConstants expr @?= Nothing  -- Would produce NaN

  , testCase "Don't simplify x - x (may be NaN)" $ do
      let varX = Opt.VarLocal (Name.fromChars "x")
      simplifyArithmetic "sub" varX varX @?= Nothing
  ]
```

### Property Tests

**File:** `/home/quinten/fh/canopy/test/Property/Optimize/ArithmeticProps.hs`

```haskell
module Property.Optimize.ArithmeticProps (props) where

import Test.Tasty
import Test.Tasty.QuickCheck
import qualified Optimize.Arithmetic as Arith

props :: TestTree
props = testGroup "Arithmetic Properties"
  [ testProperty "Constant folding preserves semantics" $
      \(SafeInt x) (SafeInt y) ->
        let folded = evalIntOp "add" x y
            expected = Just (x + y)
        in folded === expected

  , testProperty "Identity: x + 0 = x" $
      \expr -> simplifyArithmetic "add" expr (Opt.Int 0) === Just expr

  , testProperty "Commutativity: fold(x + y) = fold(y + x)" $
      \(SafeInt x) (SafeInt y) ->
        evalIntOp "add" x y === evalIntOp "add" y x

  , testProperty "Associativity: (x + y) + z = x + (y + z)" $
      \(SafeInt x) (SafeInt y) (SafeInt z) ->
        let left = evalIntOp "add" x y >>= \xy -> evalIntOp "add" xy z
            right = evalIntOp "add" y z >>= \yz -> evalIntOp "add" x yz
        in left === right

  , testProperty "Overflow detection works" $
      \(Huge x) (Huge y) ->
        let result = evalIntOp "add" x y
        in isNothing result || maybe False inSafeRange result
  ]

-- Generator for safe integers
newtype SafeInt = SafeInt Int deriving (Show, Eq)

instance Arbitrary SafeInt where
  arbitrary = SafeInt <$> choose (-(2^30), 2^30)

-- Generator for huge integers (likely to overflow)
newtype Huge = Huge Int deriving (Show, Eq)

instance Arbitrary Huge where
  arbitrary = Huge <$> choose (2^50, 2^60)
```

### Golden Tests

**File:** `/home/quinten/fh/canopy/test/golden/arithmetic/constant-folding.golden`

```
-- Input: Canopy source
main = 1 + 2

-- Expected optimized AST
Opt.Int 3

-- Expected JavaScript output
var main = 3;
```

**File:** `/home/quinten/fh/canopy/test/golden/arithmetic/algebraic-simplification.golden`

```
-- Input
addZero x = x + 0

-- Expected optimized AST
Opt.Function ["x"] (Opt.VarLocal "x")

-- Expected JavaScript
var addZero = function(x) { return x; };
```

### Integration Tests

Test end-to-end compilation with optimizations enabled:

```haskell
module Test.Integration.ArithmeticOptimization (tests) where

tests :: TestTree
tests = testGroup "Arithmetic Optimization Integration"
  [ testCase "Compile constant expression" $ do
      let source = "main = (2 + 3) * 4"
      result <- compile source
      assertJavaScriptOutput result "var main = 20;"

  , testCase "Simplify identity in function" $ do
      let source = "addZero x = x + 0"
      result <- compile source
      assertJavaScriptOutput result "var addZero = function(x) { return x; };"
  ]
```

### JavaScript Reference Tests

Verify Haskell float computation matches JavaScript:

**File:** `/home/quinten/fh/canopy/test/reference/arithmetic-float.js`

```javascript
// Generate reference outputs for float operations
const tests = [
  { expr: "1.5 + 2.5", result: 1.5 + 2.5 },
  { expr: "0.1 + 0.2", result: 0.1 + 0.2 },
  { expr: "Infinity + 1", result: Infinity + 1 },
  { expr: "NaN + 1", result: NaN + 1 },
  { expr: "1.0 / 0.0", result: 1.0 / 0.0 },
];

tests.forEach(t => {
  console.log(`${t.expr} => ${t.result}`);
});
```

Run in Node.js and compare to Haskell `evalFloatOp` output.

---

## Performance Impact

### Optimization Benefits

1. **Runtime performance**:
   - Eliminate constant arithmetic at runtime
   - Reduce function call overhead
   - Example: `(2 + 3) * 4` → one integer instead of two operations

2. **Code size reduction**:
   - Fewer AST nodes to process
   - Smaller generated JavaScript
   - Example: `x + 0` → `x` removes operator and zero literal

3. **Downstream optimizations**:
   - Simplification exposes more optimization opportunities
   - Example: `(x + 0) * 1` → `x` after two passes

### Compilation Performance

**Expected overhead:** < 2% compile time increase

1. **Optimization cost**: O(n) where n = number of arithmetic expressions
2. **Pattern matching**: Constant time per expression
3. **Constant evaluation**: Constant time (simple arithmetic)

**Mitigation strategies:**
- Only run on Basics arithmetic operators (filtered by module name)
- Skip optimization for non-constant complex expressions
- Use guards to fail-fast on non-optimizable patterns

### Benchmarks

**Benchmark suite:** `/home/quinten/fh/canopy/bench/ArithmeticOptimization.hs`

```haskell
module Bench.ArithmeticOptimization where

import Criterion.Main

benchmarks :: [Benchmark]
benchmarks =
  [ bench "Constant folding: 1 + 2" $ nf optimize constantExpr
  , bench "Algebraic simp: x + 0" $ nf optimize identityExpr
  , bench "Complex: (2 + 3) * 4" $ nf optimize complexExpr
  , bench "No optimization: x + y" $ nf optimize noOptExpr
  ]
```

**Success criteria:**
- Optimization pass < 5% of total compile time
- Constant folding < 1μs per expression
- No regression in compilation speed for unoptimized code

---

## Future Extensions

### Phase 2: Advanced Optimizations

1. **Cross-function constant propagation**:
   ```haskell
   -- Inline constant functions
   increment = 1
   result = x + increment  -- Becomes: x + 1
   ```

2. **Strength reduction**:
   ```haskell
   -- Power-of-two optimization
   x * 2  -- Becomes: x + x (if faster)
   x / 2  -- Becomes: x * 0.5 (for floats)
   ```

3. **Common subexpression elimination**:
   ```haskell
   -- Reuse computed values
   a = (x + y) * 2
   b = (x + y) * 3
   -- Becomes: temp = x + y; a = temp * 2; b = temp * 3
   ```

### Phase 3: Peephole Optimization

Optimize at JavaScript code generation level:

```javascript
// Before
var x = 1 + 2;
var y = x * 3;

// After
var x = 3;
var y = 9;
```

### Phase 4: Numeric Analysis

Add numeric range analysis for better optimization:

```haskell
-- If x is known to be in [0, 100]
x % 256  -- Can skip modulo (x already in range)
```

---

## Appendix A: Operator Reference

### Basics Module Operators

| Operator | Canopy Name | JS Operator | Associativity | Precedence |
|----------|-------------|-------------|---------------|------------|
| `+` | `add` | `+` | Left | 6 |
| `-` | `sub` | `-` | Left | 6 |
| `*` | `mul` | `*` | Left | 7 |
| `/` | `fdiv` | `/` | Left | 7 |
| `//` | `idiv` | `\|` + `/` | Left | 7 |
| `%` | `remainderBy` | `%` | Left | 7 |
| `^` | `pow` | `**` | Right | 8 |
| `==` | `eq` | `===` | Non | 4 |
| `/=` | `neq` | `!==` | Non | 4 |
| `<` | `lt` | `<` | Non | 4 |
| `>` | `gt` | `>` | Non | 4 |
| `<=` | `le` | `<=` | Non | 4 |
| `>=` | `ge` | `>=` | Non | 4 |

### Type Signatures

```haskell
add : Int -> Int -> Int
add : Float -> Float -> Float

sub : Int -> Int -> Int
sub : Float -> Float -> Float

mul : Int -> Int -> Int
mul : Float -> Float -> Float

fdiv : Float -> Float -> Float
idiv : Int -> Int -> Int

remainderBy : Int -> Int -> Int

pow : Int -> Int -> Int
pow : Float -> Float -> Float
```

---

## Appendix B: Implementation Checklist

### Module Creation
- [ ] Create `Optimize/Arithmetic.hs`
- [ ] Add module exports to `canopy-core.cabal`
- [ ] Import in `Optimize/Expression.hs`

### Core Functions
- [ ] Implement `foldConstants`
- [ ] Implement `evalIntOp` with overflow checking
- [ ] Implement `evalFloatOp` with IEEE 754 compliance
- [ ] Implement `simplifyArithmetic`
- [ ] Implement pattern matchers (simplifyAdd, simplifyMul, etc.)

### Safety Functions
- [ ] Implement `inSafeRange`
- [ ] Implement `safeAdd`, `safeSub`, `safeMul`
- [ ] Implement `safeIdiv` with division-by-zero check

### Utilities
- [ ] Implement `isBasicsOperator`
- [ ] Implement `extractConstant`
- [ ] Implement operator detection helpers

### Integration
- [ ] Modify `Optimize/Expression.hs` binop case
- [ ] Add optimization pass to pipeline
- [ ] Ensure backward compatibility

### Testing
- [ ] Write unit tests (30+ test cases)
- [ ] Write property tests (10+ properties)
- [ ] Create golden test files (5+ examples)
- [ ] Write integration tests (end-to-end)
- [ ] Generate JavaScript reference outputs
- [ ] Run fuzzing tests (1000+ random expressions)

### Documentation
- [ ] Add Haddock documentation to all functions
- [ ] Update CHANGELOG.md
- [ ] Add optimization guide to docs/
- [ ] Document safety invariants

### Validation
- [ ] All tests pass
- [ ] Coverage ≥ 80%
- [ ] Benchmarks show < 5% compile time overhead
- [ ] No semantic changes (differential testing)
- [ ] Code review by 2+ engineers

---

## References

1. **JavaScript Number Semantics**: ECMAScript 2023 Specification, Section 6.1.6.1
2. **IEEE 754 Standard**: IEEE Standard for Floating-Point Arithmetic (2019)
3. **Safe Integer Range**: MDN Web Docs - Number.MAX_SAFE_INTEGER
4. **Compiler Optimizations**: "Engineering a Compiler" by Cooper & Torczon, Chapter 10
5. **Constant Folding**: "Modern Compiler Implementation" by Appel, Section 8.1
6. **Algebraic Simplification**: "Compilers: Principles, Techniques, and Tools" (Dragon Book), Section 8.5

---

**Document Version History:**

- v1.0 (2025-10-28): Initial design document
  - Complete optimization rules specification
  - Implementation design with module structure
  - Comprehensive test strategy
  - Safety and correctness analysis
  - Performance impact assessment
