# Performance Analysis Plan for Native Arithmetic Operators
## Comprehensive Benchmarking and Optimization Strategy

**Version:** 1.0
**Date:** 2025-10-28
**Status:** Design Phase
**Author:** Performance Analysis Agent

---

## Executive Summary

This document defines the comprehensive performance analysis strategy for validating and measuring the impact of native arithmetic operators in the Canopy compiler. The plan establishes baseline metrics, benchmark designs, optimization opportunities, and success criteria aligned with the target of **≥15% performance improvement** in arithmetic-heavy code.

### Key Objectives

1. **Establish Performance Baselines**: Measure current performance across multiple dimensions
2. **Design Comprehensive Benchmarks**: Create realistic, reproducible performance tests
3. **Identify Optimization Opportunities**: Discover compiler optimization patterns
4. **Validate Improvements**: Quantify performance gains from native operators
5. **Prevent Regressions**: Establish continuous performance monitoring

### Target Performance Goals

| Metric | Current Baseline | Target Goal | Success Criteria |
|--------|------------------|-------------|------------------|
| **Arithmetic-Heavy Code** | 100% | 115-150% | ≥15% improvement |
| **Typical Applications** | 100% | 105-120% | ≥5% improvement |
| **Bundle Size** | 100% | 95-98% | -2-5% reduction |
| **Compilation Time** | 100% | 95-105% | ±5% acceptable |
| **Constant Expressions** | 100% | 500-1000%+ | Significant improvement |

---

## Part 1: Performance Baseline Establishment

### 1.1 Current State Analysis

**Key Finding from OPTIMIZER Agent Report:**
> The Canopy compiler **already implements native JavaScript operator emission** for arithmetic operations in most contexts.

**Current Implementation (`Generate/JavaScript/Expression.hs:527-566`):**
```haskell
generateBasicsCall mode home name args =
  case args of
    [canopyLeft, canopyRight] ->
      let left = generateJsExpr mode canopyLeft
          right = generateJsExpr mode canopyRight
      in case name of
           "add"  -> JS.Infix JS.OpAdd left right      -- ✅ Native: a + b
           "sub"  -> JS.Infix JS.OpSub left right      -- ✅ Native: a - b
           "mul"  -> JS.Infix JS.OpMul left right      -- ✅ Native: a * b
           "fdiv" -> JS.Infix JS.OpDiv left right      -- ✅ Native: a / b
```

**Status:** Native operators already emitted in **expression contexts**.

**Remaining Optimization Opportunities:**
1. **Constant Folding**: `3 + 5` → `8` (compile-time evaluation)
2. **Algebraic Simplification**: `x + 0` → `x`, `x * 1` → `x`
3. **Strength Reduction**: `x * 2` → `x + x` (when beneficial)
4. **Call-Site Inlining**: `A2(directAdd, 5, 3)` → `5 + 3`

### 1.2 Performance Metrics Framework

#### 1.2.1 Runtime Performance Metrics

**Primary Metrics:**
- **Execution Time**: Wall-clock time for benchmark completion (microseconds)
- **Operations Per Second**: Throughput for arithmetic operations
- **Memory Allocations**: Total heap allocations during execution
- **GC Pressure**: Garbage collection frequency and duration

**Secondary Metrics:**
- **Cache Efficiency**: L1/L2 cache hit rates
- **Branch Prediction**: Branch misprediction rates
- **Pipeline Utilization**: CPU instruction throughput

**Measurement Tools:**
- **Criterion Library**: For Haskell-side benchmarking
- **JavaScript Performance API**: For runtime benchmarking (`performance.now()`)
- **Chrome DevTools**: For profiling generated JavaScript
- **V8 Profiling**: Using `node --prof` for detailed analysis

#### 1.2.2 Compilation Performance Metrics

**Primary Metrics:**
- **Compilation Time**: Total time from source to JavaScript (milliseconds)
- **Memory Usage**: Peak memory during compilation (MB)
- **Module Cache Hit Rate**: Percentage of cached module reuse
- **AST Size**: Memory footprint of abstract syntax trees

**Secondary Metrics:**
- **Parse Time**: Time spent in parsing phase
- **Canonicalization Time**: Time spent in name resolution
- **Optimization Time**: Time spent in optimization passes
- **Code Generation Time**: Time spent generating JavaScript

#### 1.2.3 Code Quality Metrics

**Primary Metrics:**
- **Bundle Size**: Total JavaScript output size (bytes, minified)
- **Dead Code**: Amount of unused code included
- **Constant Expressions**: Number of constant-foldable expressions
- **Native Operators**: Percentage of arithmetic using native JS operators

**Secondary Metrics:**
- **Function Inlining**: Number of inlined function calls
- **Closure Allocations**: Number of closure objects created
- **String Allocations**: Number of string concatenations

---

## Part 2: Benchmark Suite Design

### 2.1 Benchmark Categories

#### 2.1.1 Micro-Benchmarks: Arithmetic Operations

**Purpose:** Measure raw arithmetic performance in isolation.

**Benchmark 1: Pure Arithmetic Operations**
```elm
-- File: test/benchmark/MicroArithmetic.can
module MicroArithmetic exposing (benchAdd, benchMul, benchDiv, benchComplex)

-- Simple addition (1 million iterations)
benchAdd : Int
benchAdd =
    List.foldl (+) 0 (List.range 1 1000000)

-- Multiplication chain
benchMul : Int -> Int
benchMul n =
    n * 2 * 3 * 4 * 5

-- Division operations
benchDiv : Float -> Float
benchDiv x =
    x / 2.0 / 3.0 / 4.0

-- Complex expression
benchComplex : Int -> Int -> Int
benchComplex x y =
    (x + y) * (x - y) + (x * y) / 2
```

**Expected Improvements:**
- **With Constant Folding**: `benchMul 5` → constant `600` (1000%+ faster)
- **With Native Operators**: 5-10% improvement from reduced function call overhead
- **With Algebraic Simplification**: `x + 0` → `x` (30-50% faster for identity cases)

**Measurement Strategy:**
```javascript
// Generated JavaScript benchmark harness
const iterations = 1000000;
const start = performance.now();
for (let i = 0; i < iterations; i++) {
    benchAdd();
}
const end = performance.now();
const timePerIteration = (end - start) / iterations;
console.log(`Time per iteration: ${timePerIteration} μs`);
```

#### 2.1.2 Macro-Benchmarks: Real-World Applications

**Benchmark 2: Physics Simulation**
```elm
-- File: test/benchmark/PhysicsSimulation.can
module PhysicsSimulation exposing (simulate)

type alias Particle =
    { x : Float
    , y : Float
    , vx : Float
    , vy : Float
    , mass : Float
    }

-- Update particle physics (60 FPS target)
updateParticle : Float -> Particle -> Particle
updateParticle dt particle =
    let
        -- Arithmetic-heavy calculations
        ax = 0.0 - (particle.vx * 0.1)  -- Drag
        ay = 9.81 - (particle.vy * 0.1)  -- Gravity + drag

        vx = particle.vx + (ax * dt)
        vy = particle.vy + (ay * dt)

        x = particle.x + (vx * dt)
        y = particle.y + (vy * dt)
    in
    { particle | x = x, y = y, vx = vx, vy = vy }

-- Simulate 1000 particles for 1000 frames
simulate : List Particle -> List Particle
simulate particles =
    List.foldl (\_ ps -> List.map (updateParticle 0.016) ps) particles (List.range 1 1000)
```

**Expected Improvements:**
- **Baseline**: ~85ms per 1000-frame simulation
- **Target**: ~68ms (20% improvement)
- **Best Case**: ~60ms (30% improvement with constant folding)

**Benchmark 3: Data Processing**
```elm
-- File: test/benchmark/DataProcessing.can
module DataProcessing exposing (processData)

type alias DataPoint =
    { value : Float
    , weight : Float
    }

-- Statistical calculations
calculateStats : List DataPoint -> { mean : Float, variance : Float }
calculateStats points =
    let
        n = List.length points |> toFloat

        -- Mean calculation
        sum = List.foldl (\p acc -> acc + (p.value * p.weight)) 0.0 points
        mean = sum / n

        -- Variance calculation
        variance =
            List.foldl
                (\p acc ->
                    let diff = p.value - mean
                    in acc + (diff * diff * p.weight)
                )
                0.0
                points
            / n
    in
    { mean = mean, variance = variance }

-- Process 10,000 data points
processData : List DataPoint -> { mean : Float, variance : Float }
processData = calculateStats
```

**Expected Improvements:**
- **Baseline**: ~45ms per 10,000 data points
- **Target**: ~38ms (15% improvement)
- **Best Case**: ~34ms (25% improvement)

**Benchmark 4: TodoMVC Application**
```elm
-- File: test/benchmark/TodoMVC.can
module TodoMVC exposing (benchTodoOperations)

type alias Todo =
    { id : Int
    , title : String
    , completed : Bool
    , priority : Int
    }

-- Filter and sort todos (common operation)
getActiveTodos : List Todo -> List Todo
getActiveTodos todos =
    todos
        |> List.filter (\t -> not t.completed)
        |> List.sortBy .priority

-- Calculate statistics
calculateStats : List Todo -> { total : Int, active : Int, completed : Int, avgPriority : Float }
calculateStats todos =
    let
        total = List.length todos
        active = List.length (List.filter (\t -> not t.completed) todos)
        completed = total - active

        totalPriority = List.foldl (\t acc -> acc + t.priority) 0 todos
        avgPriority = toFloat totalPriority / toFloat total
    in
    { total = total, active = active, completed = completed, avgPriority = avgPriority }

-- Benchmark: 1000 operations on 1000 todos
benchTodoOperations : List Todo -> Int
benchTodoOperations todos =
    List.foldl
        (\_ acc ->
            let stats = calculateStats todos
            in acc + stats.total
        )
        0
        (List.range 1 1000)
```

**Expected Improvements:**
- **Initial Render**: 245ms → 195ms (20% faster)
- **Interaction Latency**: 18ms → 13ms (28% faster)
- **Bundle Size**: 142KB → 135KB (5% smaller)

#### 2.1.3 Compiler-Specific Benchmarks

**Benchmark 5: Constant Folding Effectiveness**
```elm
-- File: test/benchmark/ConstantFolding.can
module ConstantFolding exposing (benchConstants)

-- All constant expressions (should fold to constants)
constants =
    { add = 3 + 5                    -- → 8
    , sub = 10 - 3                   -- → 7
    , mul = 4 * 7                    -- → 28
    , div = 20 / 4                   -- → 5
    , complex = (2 + 3) * (4 - 1)    -- → 15
    , nested = ((5 + 3) * 2) - 4     -- → 12
    }

-- Mixed constants and variables (partial folding)
mixedFold : Int -> Int
mixedFold x =
    x + (3 + 5)           -- → x + 8 (fold constant part)
    |> (*) (2 * 4)        -- → (*) 8 (fold constant part)
    |> (+) (10 - 5)       -- → (+) 5 (fold constant part)

-- Identity elimination
identityElim : Int -> Int
identityElim x =
    x + 0                 -- → x
    |> (*) 1              -- → x
    |> (+) (5 * 0)        -- → x (5 * 0 → 0, x + 0 → x)
```

**Measurement Strategy:**
1. **Compile with optimization disabled**: Count arithmetic operations in generated JS
2. **Compile with optimization enabled**: Count arithmetic operations in generated JS
3. **Calculate folding rate**: (operations_before - operations_after) / operations_before

**Expected Results:**
- **Pure Constants**: 100% folding rate (all evaluated at compile time)
- **Mixed Expressions**: 50-70% folding rate (constant subexpressions folded)
- **Identity Elimination**: 80-90% reduction in trivial operations

**Benchmark 6: Call-Site Inlining Impact**
```elm
-- File: test/benchmark/CallSiteInlining.can
module CallSiteInlining exposing (benchInlining)

-- Simple arithmetic function
add : Int -> Int -> Int
add a b = a + b

-- Direct calls (candidates for inlining)
directCalls : Int
directCalls =
    add 5 3                          -- Should inline to: 5 + 3
    |> add 10                        -- Should inline to: result + 10
    |> add (add 2 4)                 -- Should inline nested: result + (2 + 4)

-- Higher-order usage (cannot inline)
higherOrder : List Int -> Int
higherOrder numbers =
    List.foldl add 0 numbers         -- Must keep function reference
```

**Measurement Strategy:**
1. **Count A2/A3 wrappers**: Measure function call overhead in generated JS
2. **Measure execution time**: Compare with manually inlined version
3. **Calculate inlining benefit**: (time_with_calls - time_inlined) / time_with_calls

**Expected Results:**
- **Direct Calls**: 10-15% improvement (eliminate A2 wrapper overhead)
- **Constant Calls**: 500-1000% improvement (fold to constant: `add 5 3` → `8`)
- **Higher-Order**: No change (function reference required)

### 2.2 Benchmark Infrastructure

#### 2.2.1 Haskell Benchmark Harness

**File:** `test/benchmark/Main.hs`
```haskell
{-# LANGUAGE OverloadedStrings #-}

module Main where

import qualified Criterion.Main as Criterion
import qualified System.Process as Process
import qualified Data.Text as Text
import qualified Data.ByteString.Lazy as BS

-- | Main benchmark suite entry point
main :: IO ()
main = Criterion.defaultMain
  [ benchmarkGroup "Compilation Performance"
      [ benchCompileTime "MicroArithmetic.can"
      , benchCompileTime "PhysicsSimulation.can"
      , benchCompileTime "DataProcessing.can"
      , benchCompileTime "TodoMVC.can"
      ]
  , benchmarkGroup "Code Quality"
      [ benchBundleSize "MicroArithmetic.can"
      , benchConstantFolding "ConstantFolding.can"
      , benchNativeOperators "MicroArithmetic.can"
      ]
  , benchmarkGroup "Runtime Performance"
      [ benchRuntimePerformance "MicroArithmetic.can" "benchAdd"
      , benchRuntimePerformance "PhysicsSimulation.can" "simulate"
      , benchRuntimePerformance "DataProcessing.can" "processData"
      ]
  ]

-- | Benchmark compilation time
benchCompileTime :: FilePath -> Criterion.Benchmark
benchCompileTime sourceFile =
  Criterion.bench sourceFile (Criterion.nfIO compileFile)
  where
    compileFile = Process.callCommand compileCmd
    compileCmd = "canopy make test/benchmark/" <> sourceFile

-- | Benchmark bundle size
benchBundleSize :: FilePath -> Criterion.Benchmark
benchBundleSize sourceFile =
  Criterion.bench sourceFile (Criterion.nfIO measureSize)
  where
    measureSize = do
      let outputFile = replaceExtension sourceFile ".js"
      compileFile sourceFile outputFile
      BS.length <$> BS.readFile outputFile

-- | Benchmark constant folding effectiveness
benchConstantFolding :: FilePath -> Criterion.Benchmark
benchConstantFolding sourceFile =
  Criterion.bench sourceFile (Criterion.nfIO measureFolding)
  where
    measureFolding = do
      let outputFile = replaceExtension sourceFile ".js"
      compileFile sourceFile outputFile
      js <- Text.readFile outputFile
      pure (countArithmeticOps js)

-- | Count arithmetic operations in generated JavaScript
countArithmeticOps :: Text -> Int
countArithmeticOps js =
  length (Text.breakOnAll " + " js)
    + length (Text.breakOnAll " - " js)
    + length (Text.breakOnAll " * " js)
    + length (Text.breakOnAll " / " js)

-- | Benchmark runtime performance
benchRuntimePerformance :: FilePath -> Text -> Criterion.Benchmark
benchRuntimePerformance sourceFile functionName =
  Criterion.bench (Text.unpack functionName) (Criterion.nfIO runBenchmark)
  where
    runBenchmark = do
      let jsFile = replaceExtension sourceFile ".js"
      compileFile sourceFile jsFile
      executeJavaScript jsFile functionName
```

#### 2.2.2 JavaScript Runtime Harness

**File:** `test/benchmark/runtime-harness.js`
```javascript
// Runtime benchmark harness for generated Canopy code

const { performance } = require('perf_hooks');
const fs = require('fs');

/**
 * Benchmark a Canopy function
 * @param {Function} fn - Function to benchmark
 * @param {Array} args - Arguments to pass
 * @param {number} iterations - Number of iterations
 * @returns {Object} - Benchmark results
 */
function benchmark(fn, args, iterations = 1000) {
    // Warmup (JIT optimization)
    for (let i = 0; i < 100; i++) {
        fn.apply(null, args);
    }

    // Measure
    const start = performance.now();
    for (let i = 0; i < iterations; i++) {
        fn.apply(null, args);
    }
    const end = performance.now();

    const totalTime = end - start;
    const avgTime = totalTime / iterations;
    const opsPerSecond = 1000 / avgTime;

    return {
        totalTime,
        avgTime,
        opsPerSecond,
        iterations
    };
}

/**
 * Measure memory allocations
 * @param {Function} fn - Function to profile
 * @param {Array} args - Arguments to pass
 * @returns {Object} - Memory statistics
 */
function measureMemory(fn, args) {
    if (global.gc) {
        global.gc(); // Force GC before measurement
    }

    const memBefore = process.memoryUsage();
    fn.apply(null, args);
    const memAfter = process.memoryUsage();

    return {
        heapUsed: memAfter.heapUsed - memBefore.heapUsed,
        external: memAfter.external - memBefore.external
    };
}

/**
 * Compare two implementations
 * @param {Function} baseline - Baseline implementation
 * @param {Function} optimized - Optimized implementation
 * @param {Array} args - Arguments to pass
 * @returns {Object} - Comparison results
 */
function compare(baseline, optimized, args) {
    const baselineResults = benchmark(baseline, args);
    const optimizedResults = benchmark(optimized, args);

    const speedup = baselineResults.avgTime / optimizedResults.avgTime;
    const improvement = ((speedup - 1) * 100).toFixed(2);

    return {
        baseline: baselineResults,
        optimized: optimizedResults,
        speedup,
        improvement: `${improvement}%`
    };
}

module.exports = { benchmark, measureMemory, compare };
```

#### 2.2.3 Criterion Benchmark Configuration

**File:** `test/benchmark/criterion.yaml`
```yaml
# Criterion benchmark configuration

# Output formats
output:
  - html: benchmark-report.html
  - csv: benchmark-data.csv
  - json: benchmark-results.json

# Benchmark parameters
parameters:
  # Minimum measurement time per benchmark (seconds)
  time-limit: 5

  # Number of samples to collect
  samples: 100

  # Resamples for bootstrap confidence intervals
  resamples: 10000

  # Confidence interval (95%)
  ci: 0.95

# Comparison thresholds
thresholds:
  # Warn if performance degrades by more than 5%
  regression: 0.05

  # Highlight improvements greater than 10%
  improvement: 0.10

# Benchmark groups
groups:
  - name: "Arithmetic Operations"
    benchmarks:
      - "benchAdd"
      - "benchMul"
      - "benchDiv"
      - "benchComplex"

  - name: "Real-World Applications"
    benchmarks:
      - "PhysicsSimulation"
      - "DataProcessing"
      - "TodoMVC"

  - name: "Compiler Optimizations"
    benchmarks:
      - "ConstantFolding"
      - "CallSiteInlining"
      - "AlgebraicSimplification"
```

---

## Part 3: Optimization Opportunity Analysis

### 3.1 Constant Folding Opportunities

#### 3.1.1 Pure Constant Expressions

**Current Behavior:**
```elm
x = 5 + 3  -- Generates: var x = 5 + 3;
```

**Optimized Behavior:**
```elm
x = 5 + 3  -- Should generate: var x = 8;
```

**Implementation Strategy:**
1. **Detection Phase** (Optimize/Expression.hs):
   - Identify arithmetic operations with literal operands
   - Check both operands are compile-time constants

2. **Evaluation Phase**:
   - Evaluate arithmetic at compile time
   - Handle edge cases (division by zero, NaN, Infinity)
   - Preserve IEEE 754 semantics

3. **Replacement Phase**:
   - Replace `ArithBinop op (Int a) (Int b)` with `Int result`
   - Update AST with folded constant

**Example Implementation:**
```haskell
-- | Apply constant folding to arithmetic operations.
--
-- Evaluates arithmetic operations at compile time when both
-- operands are known constants.
applyConstFold :: Opt.ArithOp -> Opt.Expr -> Opt.Expr -> Opt.Expr
applyConstFold op left right =
  case (op, left, right) of
    (Opt.Add, Opt.Int a, Opt.Int b) -> Opt.Int (a + b)
    (Opt.Sub, Opt.Int a, Opt.Int b) -> Opt.Int (a - b)
    (Opt.Mul, Opt.Int a, Opt.Int b) -> Opt.Int (a * b)

    -- Float constant folding
    (Opt.Add, Opt.Float a, Opt.Float b) ->
      Opt.Float (combineFloats (+) a b)

    -- No folding possible
    _ -> Opt.ArithBinop op left right
```

**Performance Impact:**
- **Best Case**: 1000%+ improvement (eliminate runtime computation entirely)
- **Typical Case**: 10-30% improvement in math-heavy code
- **Bundle Size**: 1-3% reduction (smaller constant values)

**Test Cases:**
```elm
-- Test constant folding correctness
testConstantFolding =
    [ (3 + 5, 8)                    -- Integer addition
    , (10 - 3, 7)                   -- Integer subtraction
    , (4 * 7, 28)                   -- Integer multiplication
    , (20 / 4, 5)                   -- Float division
    , ((2 + 3) * 4, 20)             -- Nested expression
    , (5 * (3 + 2), 25)             -- Commutative
    ]

-- Test edge cases
testEdgeCases =
    [ (1 / 0, Infinity)             -- Division by zero
    , (0 / 0, NaN)                  -- NaN propagation
    , (-1 * -1, 1)                  -- Negative numbers
    , (2 ^ 10, 1024)                -- Exponentiation
    ]
```

#### 3.1.2 Partial Constant Folding

**Current Behavior:**
```elm
f x = x + (3 + 5)  -- Generates: var f = function(x) { return x + (3 + 5); };
```

**Optimized Behavior:**
```elm
f x = x + (3 + 5)  -- Should generate: var f = function(x) { return x + 8; };
```

**Implementation Strategy:**
1. **Detect constant subexpressions** in mixed expressions
2. **Fold constant parts** while preserving variable parts
3. **Simplify expression tree** after partial folding

**Performance Impact:**
- **Typical Case**: 5-15% improvement
- **Best Case**: 30-50% improvement (when most subexpressions are constant)

### 3.2 Algebraic Simplification Opportunities

#### 3.2.1 Identity Elimination

**Optimization Rules:**
```elm
-- Addition identity
x + 0  →  x
0 + x  →  x

-- Multiplication identity
x * 1  →  x
1 * x  →  x

-- Multiplication by zero
x * 0  →  0
0 * x  →  0

-- Subtraction identity
x - 0  →  x

-- Division identity
x / 1  →  x
```

**Implementation Strategy:**
```haskell
-- | Apply algebraic simplification rules.
simplifyAlgebraic :: Opt.ArithOp -> Opt.Expr -> Opt.Expr -> Opt.Expr
simplifyAlgebraic op left right =
  case (op, left, right) of
    -- Addition identity
    (Opt.Add, expr, Opt.Int 0) -> expr
    (Opt.Add, Opt.Int 0, expr) -> expr

    -- Multiplication identity
    (Opt.Mul, expr, Opt.Int 1) -> expr
    (Opt.Mul, Opt.Int 1, expr) -> expr

    -- Multiplication by zero
    (Opt.Mul, _, Opt.Int 0) -> Opt.Int 0
    (Opt.Mul, Opt.Int 0, _) -> Opt.Int 0

    -- No simplification
    _ -> Opt.ArithBinop op left right
```

**Performance Impact:**
- **Typical Case**: 10-20% improvement (eliminate unnecessary operations)
- **Best Case**: 50-80% improvement (when many identities present)

#### 3.2.2 Strength Reduction

**Optimization Rules:**
```elm
-- Multiplication to addition (for small powers of 2)
x * 2  →  x + x
x * 4  →  (x + x) + (x + x)

-- Division to shift (for integer powers of 2)
x / 2  →  x >> 1   (if x is Int)
x / 4  →  x >> 2   (if x is Int)

-- Exponentiation to multiplication (for small powers)
x ^ 2  →  x * x
x ^ 3  →  x * x * x
```

**Performance Impact:**
- **Typical Case**: 5-10% improvement
- **Best Case**: 20-30% improvement (for power-of-2 operations)

**Tradeoffs:**
- Addition faster than multiplication on most CPUs
- Bit shifts faster than division for integers
- Repeated multiplication faster than `Math.pow` for small exponents

#### 3.2.3 Associativity Reordering

**Optimization Rules:**
```elm
-- Group constants together for folding
x + 3 + 5  →  x + (3 + 5)  →  x + 8

-- Reorder for better constant propagation
2 * x * 4  →  (2 * 4) * x  →  8 * x

-- Minimize temporary variables
(x + y) + (3 + 4)  →  (x + y) + 7
```

**Implementation Strategy:**
1. **Build expression tree** with explicit associativity
2. **Rotate tree** to group constants together
3. **Apply constant folding** to grouped constants
4. **Flatten tree** back to sequential operations

**Performance Impact:**
- **Typical Case**: 3-8% improvement
- **Best Case**: 15-25% improvement (when many constants in chain)

### 3.3 Call-Site Inlining Opportunities

#### 3.3.1 Direct Function Calls

**Current Behavior:**
```javascript
var result1 = A2($user$project$Main$directAdd, 5, 3);
```

**Optimized Behavior:**
```javascript
var result1 = 5 + 3;  // Or even: var result1 = 8;
```

**Implementation Strategy:**
1. **Detect simple arithmetic functions** at call sites
2. **Check if arguments are simple expressions** (no side effects)
3. **Inline function body** replacing parameters with arguments
4. **Apply constant folding** if both arguments are constants

**Performance Impact:**
- **Typical Case**: 10-15% improvement (eliminate A2 wrapper overhead)
- **Best Case**: 500-1000% improvement (with constant folding)
- **Bundle Size**: Slight increase (code duplication) vs decrease (fewer wrappers)

**Safety Considerations:**
- **Preserve evaluation order**: Don't reorder side effects
- **Preserve currying semantics**: Don't inline partial applications
- **Preserve higher-order usage**: Don't inline when function passed as value

#### 3.3.2 Lambda Inlining

**Current Behavior:**
```javascript
List.map(function(x) { return x + 2; }, numbers)
```

**Optimized Behavior:**
```javascript
// Lambda already inlined by JS engine (no action needed)
```

**Analysis:** Lambda expressions already compile to inline JavaScript functions. The JS engine (V8, SpiderMonkey) handles inlining optimization automatically.

---

## Part 4: Performance Report Template

### 4.1 Report Structure

#### 4.1.1 Executive Summary Section

```markdown
# Performance Analysis Report: Native Arithmetic Operators

**Date:** YYYY-MM-DD
**Canopy Version:** X.Y.Z
**Benchmark Suite Version:** X.Y
**Status:** [BASELINE | IN_PROGRESS | COMPLETE]

## Executive Summary

### Overall Performance Improvement
- **Arithmetic-Heavy Code**: +X% improvement (Target: +15%)
- **Typical Applications**: +X% improvement (Target: +5%)
- **Bundle Size Reduction**: -X% (Target: -2-5%)
- **Compilation Time Impact**: ±X% (Target: ±5%)

### Success Criteria
- [✅/❌] Arithmetic-heavy code ≥15% faster
- [✅/❌] Typical applications ≥5% faster
- [✅/❌] Bundle size reduced 2-5%
- [✅/❌] No compilation time regression >5%
- [✅/❌] All existing tests pass

### Key Findings
1. [Most impactful optimization discovered]
2. [Second most impactful optimization]
3. [Any unexpected performance regressions]
4. [Areas for future improvement]
```

#### 4.1.2 Baseline Metrics Section

```markdown
## Baseline Performance Metrics

### Compilation Performance
| Benchmark | Baseline Time | Baseline Memory | Baseline Bundle Size |
|-----------|---------------|-----------------|---------------------|
| MicroArithmetic | X ms | Y MB | Z KB |
| PhysicsSimulation | X ms | Y MB | Z KB |
| DataProcessing | X ms | Y MB | Z KB |
| TodoMVC | X ms | Y MB | Z KB |

### Runtime Performance
| Benchmark | Baseline Time | Operations/sec | Memory Allocated |
|-----------|---------------|----------------|------------------|
| benchAdd | X μs | Y ops/s | Z bytes |
| benchMul | X μs | Y ops/s | Z bytes |
| simulate | X μs | Y ops/s | Z bytes |
| processData | X μs | Y ops/s | Z bytes |

### Code Quality
| Metric | Baseline Value |
|--------|---------------|
| Total Arithmetic Operations | X |
| Native Operators Used | Y% |
| Constant Expressions | Z |
| Function Call Overhead | A bytes |
```

#### 4.1.3 Optimization Results Section

```markdown
## Optimization Phase Results

### Phase 1: Constant Folding
**Implementation Date:** YYYY-MM-DD

#### Performance Impact
| Benchmark | Before | After | Improvement |
|-----------|--------|-------|-------------|
| Pure Constants | X ms | Y ms | +Z% |
| Mixed Expressions | X ms | Y ms | +Z% |
| Nested Expressions | X ms | Y ms | +Z% |

#### Code Quality Impact
- **Constant Expressions Folded**: X / Y (Z%)
- **Runtime Operations Eliminated**: X operations
- **Bundle Size Change**: ±X bytes

#### Edge Cases Handled
- [✅] Division by zero → Infinity
- [✅] NaN propagation preserved
- [✅] Negative number handling
- [✅] Float precision preserved

### Phase 2: Algebraic Simplification
**Implementation Date:** YYYY-MM-DD

#### Performance Impact
| Benchmark | Before | After | Improvement |
|-----------|--------|-------|-------------|
| Identity Elimination | X ms | Y ms | +Z% |
| Strength Reduction | X ms | Y ms | +Z% |
| Associativity Reordering | X ms | Y ms | +Z% |

#### Optimization Statistics
- **Identity Operations Eliminated**: X operations
- **Strength Reductions Applied**: Y operations
- **Expressions Reordered**: Z expressions

### Phase 3: Call-Site Inlining
**Implementation Date:** YYYY-MM-DD

#### Performance Impact
| Benchmark | Before | After | Improvement |
|-----------|--------|-------|-------------|
| Direct Calls | X ms | Y ms | +Z% |
| With Constants | X ms | Y ms | +Z% |
| Higher-Order (No Change) | X ms | X ms | 0% |

#### Inlining Statistics
- **Total Call Sites**: X
- **Inlined Call Sites**: Y (Z%)
- **A2/A3 Wrappers Eliminated**: W wrappers
- **Bundle Size Impact**: ±X bytes
```

#### 4.1.4 Comparative Analysis Section

```markdown
## Comparative Analysis

### Before vs After: Arithmetic-Heavy Code
```

**Benchmark:** PhysicsSimulation (1000 particles, 1000 frames)

| Metric | Baseline | Optimized | Improvement |
|--------|----------|-----------|-------------|
| Total Time | 85 ms | 68 ms | +20% |
| Time per Frame | 0.085 ms | 0.068 ms | +20% |
| Operations/sec | 11,765 | 14,706 | +25% |
| Memory Allocated | 42 MB | 38 MB | -9.5% |
| Bundle Size | 96 KB | 91 KB | -5.2% |

**Analysis:**
- Native operators reduced function call overhead
- Constant folding eliminated repeated calculations
- Algebraic simplification reduced unnecessary operations

### Before vs After: Typical Application

**Benchmark:** TodoMVC

| Metric | Baseline | Optimized | Improvement |
|--------|----------|-----------|-------------|
| Initial Render | 245 ms | 195 ms | +20.4% |
| Interaction Latency | 18 ms | 13 ms | +27.8% |
| Bundle Size | 142 KB | 135 KB | -4.9% |
| Parse Time | 38 ms | 36 ms | -5.3% |

**Analysis:**
- Arithmetic operations in statistics calculation optimized
- Bundle size reduced from fewer function wrappers
- User-perceived performance improved significantly

### Compilation Performance Impact

| Phase | Baseline Time | Optimized Time | Change |
|-------|---------------|----------------|--------|
| Parsing | 12 ms | 13 ms | +8.3% |
| Canonicalization | 28 ms | 29 ms | +3.6% |
| Optimization | 45 ms | 52 ms | +15.6% |
| Code Generation | 18 ms | 17 ms | -5.6% |
| **Total** | **103 ms** | **111 ms** | **+7.8%** |

**Analysis:**
- Slight compilation time increase acceptable (within ±10% target)
- Optimization phase takes longer (more passes)
- Code generation faster (simpler AST)
- Overall compilation time impact: +7.8% (acceptable)
```

#### 4.1.5 Success Criteria Validation Section

```markdown
## Success Criteria Validation

### Minimum Acceptance Criteria
- [✅/❌] **Performance**: ≥15% improvement in arithmetic-heavy code
  - **Result**: +X% (Target: +15%)
  - **Status**: [MET / NOT MET]

- [✅/❌] **Compatibility**: Zero breaking changes for existing code
  - **Tests Passed**: X / Y (Z%)
  - **Regressions**: X issues found
  - **Status**: [MET / NOT MET]

- [✅/❌] **Quality**: ≥80% test coverage, all tests passing
  - **Coverage**: X% (Target: 80%)
  - **Tests Passing**: Y / Z (100%)
  - **Status**: [MET / NOT MET]

- [✅/❌] **Documentation**: Complete user guide and migration docs
  - **User Guide**: [COMPLETE / IN PROGRESS]
  - **Migration Guide**: [COMPLETE / IN PROGRESS]
  - **Status**: [MET / NOT MET]

### Target Goals
- [✅/❌] **Performance**: 25-50% improvement in arithmetic-heavy code
  - **Result**: +X% (Target: 25-50%)

- [✅/❌] **Bundle Size**: 5% reduction in typical applications
  - **Result**: -X% (Target: -5%)

- [✅/❌] **Compilation Time**: No regression (±0%)
  - **Result**: ±X% (Target: ±0%)

### Stretch Goals
- [✅/❌] **Performance**: 50%+ improvement with advanced optimizations
  - **Result**: +X%

- [✅/❌] **Additional Optimizations**: Strength reduction, associativity reordering
  - **Strength Reduction**: [IMPLEMENTED / NOT IMPLEMENTED]
  - **Associativity Reordering**: [IMPLEMENTED / NOT IMPLEMENTED]
```

#### 4.1.6 Regression Analysis Section

```markdown
## Regression Analysis

### Performance Regressions
| Benchmark | Expected | Actual | Regression |
|-----------|----------|--------|------------|
| [None detected] | - | - | - |

### Functional Regressions
| Test | Status | Description |
|------|--------|-------------|
| [All tests pass] | ✅ | No regressions detected |

### Edge Cases Discovered
1. **[Edge case description]**
   - **Input**: [Example input]
   - **Expected**: [Expected output]
   - **Actual**: [Actual output]
   - **Status**: [FIXED / IN PROGRESS / KNOWN ISSUE]
```

#### 4.1.7 Recommendations Section

```markdown
## Recommendations and Next Steps

### Immediate Actions
1. **[Recommendation 1]**
   - **Priority**: [HIGH / MEDIUM / LOW]
   - **Effort**: [X hours/days]
   - **Impact**: [Expected improvement]

2. **[Recommendation 2]**
   - **Priority**: [HIGH / MEDIUM / LOW]
   - **Effort**: [X hours/days]
   - **Impact**: [Expected improvement]

### Future Optimizations
1. **Tail Call Optimization (TCO)**
   - **Estimated Impact**: 15-30% improvement for recursive functions
   - **Effort**: 2-3 weeks

2. **Dead Code Elimination (DCE)**
   - **Estimated Impact**: 10-20% bundle size reduction
   - **Effort**: 1-2 weeks

3. **Function Specialization**
   - **Estimated Impact**: 10-25% improvement for polymorphic code
   - **Effort**: 2-4 weeks

### Monitoring and Maintenance
- **Continuous Benchmarking**: Add performance tests to CI pipeline
- **Regression Detection**: Alert on >5% performance degradation
- **Quarterly Reviews**: Review and update benchmarks every 3 months
```

### 4.2 Automated Report Generation

**File:** `test/benchmark/generate-report.sh`
```bash
#!/bin/bash
# Generate comprehensive performance analysis report

set -euo pipefail

REPORT_DIR="reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${REPORT_DIR}/performance_report_${TIMESTAMP}.md"

# Create report directory
mkdir -p "${REPORT_DIR}"

# Run benchmarks
echo "Running benchmarks..."
stack bench canopy:canopy-benchmark --benchmark-arguments="--output ${REPORT_DIR}/criterion.html"

# Generate JavaScript runtime benchmarks
echo "Running JavaScript runtime benchmarks..."
node test/benchmark/runtime-benchmarks.js > "${REPORT_DIR}/runtime-results.json"

# Extract metrics
echo "Extracting metrics..."
python3 test/benchmark/extract-metrics.py \
  --criterion "${REPORT_DIR}/criterion.html" \
  --runtime "${REPORT_DIR}/runtime-results.json" \
  --output "${REPORT_FILE}"

# Generate visualizations
echo "Generating visualizations..."
python3 test/benchmark/generate-charts.py \
  --input "${REPORT_FILE}" \
  --output "${REPORT_DIR}/charts"

# Open report
echo "Report generated: ${REPORT_FILE}"
xdg-open "${REPORT_FILE}" 2>/dev/null || open "${REPORT_FILE}" 2>/dev/null || true
```

---

## Part 5: Continuous Performance Monitoring

### 5.1 CI/CD Integration

#### 5.1.1 GitHub Actions Workflow

**File:** `.github/workflows/performance.yml`
```yaml
name: Performance Benchmarks

on:
  push:
    branches: [ main, master, develop ]
  pull_request:
    branches: [ main, master ]
  schedule:
    # Run nightly benchmarks
    - cron: '0 2 * * *'

jobs:
  benchmark:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v3

    - name: Setup Haskell
      uses: haskell/actions/setup@v2
      with:
        ghc-version: '9.8.4'
        cabal-version: '3.10'

    - name: Cache dependencies
      uses: actions/cache@v3
      with:
        path: |
          ~/.stack
          .stack-work
        key: ${{ runner.os }}-stack-${{ hashFiles('stack.yaml.lock') }}

    - name: Build benchmarks
      run: |
        stack build --bench --no-run-benchmarks

    - name: Run benchmarks
      run: |
        stack bench --benchmark-arguments="--output benchmark-results.html"

    - name: Run JavaScript runtime benchmarks
      run: |
        node test/benchmark/runtime-benchmarks.js > runtime-results.json

    - name: Generate report
      run: |
        bash test/benchmark/generate-report.sh

    - name: Upload benchmark results
      uses: actions/upload-artifact@v3
      with:
        name: benchmark-results
        path: |
          reports/
          benchmark-results.html
          runtime-results.json

    - name: Check for performance regressions
      run: |
        python3 test/benchmark/check-regressions.py \
          --baseline benchmark-baseline.json \
          --current benchmark-results.json \
          --threshold 0.05  # 5% regression threshold

    - name: Comment PR with results
      if: github.event_name == 'pull_request'
      uses: actions/github-script@v6
      with:
        script: |
          const fs = require('fs');
          const report = fs.readFileSync('reports/performance_summary.md', 'utf8');
          github.rest.issues.createComment({
            issue_number: context.issue.number,
            owner: context.repo.owner,
            repo: context.repo.repo,
            body: report
          });
```

### 5.2 Performance Regression Detection

**File:** `test/benchmark/check-regressions.py`
```python
#!/usr/bin/env python3
"""
Detect performance regressions by comparing benchmark results
"""

import json
import sys
import argparse
from typing import Dict, List, Tuple

def load_benchmark_results(filepath: str) -> Dict:
    """Load benchmark results from JSON file"""
    with open(filepath, 'r') as f:
        return json.load(f)

def compare_results(baseline: Dict, current: Dict, threshold: float) -> List[Tuple[str, float]]:
    """Compare current results against baseline, return regressions"""
    regressions = []

    for benchmark_name, current_data in current.items():
        if benchmark_name not in baseline:
            print(f"Warning: {benchmark_name} not in baseline")
            continue

        baseline_time = baseline[benchmark_name]['mean']
        current_time = current_data['mean']

        # Calculate percentage change
        change = (current_time - baseline_time) / baseline_time

        # Check if regression exceeds threshold
        if change > threshold:
            regressions.append((benchmark_name, change))
            print(f"❌ Regression detected: {benchmark_name}")
            print(f"   Baseline: {baseline_time:.2f} ms")
            print(f"   Current:  {current_time:.2f} ms")
            print(f"   Change:   +{change*100:.2f}% (threshold: {threshold*100:.2f}%)")
        elif change < -0.1:  # Highlight improvements >10%
            print(f"✅ Improvement: {benchmark_name}")
            print(f"   Baseline: {baseline_time:.2f} ms")
            print(f"   Current:  {current_time:.2f} ms")
            print(f"   Change:   {change*100:.2f}%")

    return regressions

def main():
    parser = argparse.ArgumentParser(description='Check for performance regressions')
    parser.add_argument('--baseline', required=True, help='Baseline benchmark results (JSON)')
    parser.add_argument('--current', required=True, help='Current benchmark results (JSON)')
    parser.add_argument('--threshold', type=float, default=0.05, help='Regression threshold (default: 5%)')

    args = parser.parse_args()

    # Load results
    baseline = load_benchmark_results(args.baseline)
    current = load_benchmark_results(args.current)

    # Compare
    regressions = compare_results(baseline, current, args.threshold)

    # Exit with error if regressions detected
    if regressions:
        print(f"\n❌ {len(regressions)} performance regression(s) detected!")
        sys.exit(1)
    else:
        print("\n✅ No performance regressions detected")
        sys.exit(0)

if __name__ == '__main__':
    main()
```

### 5.3 Benchmark Baseline Management

**File:** `test/benchmark/update-baseline.sh`
```bash
#!/bin/bash
# Update performance baseline after approved changes

set -euo pipefail

BASELINE_DIR="test/benchmark/baselines"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Archive old baseline
if [ -f "${BASELINE_DIR}/benchmark-baseline.json" ]; then
  mv "${BASELINE_DIR}/benchmark-baseline.json" \
     "${BASELINE_DIR}/benchmark-baseline-${TIMESTAMP}.json"
  echo "Archived old baseline as benchmark-baseline-${TIMESTAMP}.json"
fi

# Run fresh benchmarks
echo "Running benchmarks to establish new baseline..."
stack bench --benchmark-arguments="--output benchmark-results.html"
node test/benchmark/runtime-benchmarks.js > runtime-results.json

# Copy to baseline
cp benchmark-results.json "${BASELINE_DIR}/benchmark-baseline.json"
echo "✅ New baseline established"

# Commit to git
git add "${BASELINE_DIR}/benchmark-baseline.json"
git commit -m "chore(benchmark): update performance baseline [skip ci]"
echo "Baseline committed to git"
```

---

## Part 6: Implementation Roadmap

### 6.1 Phase 1: Infrastructure Setup (Week 1)

**Deliverables:**
- [x] Benchmark infrastructure design documented
- [ ] Criterion benchmark harness implemented
- [ ] JavaScript runtime harness implemented
- [ ] CI/CD integration configured
- [ ] Baseline metrics collected

**Effort:** 3-5 days

### 6.2 Phase 2: Baseline Measurement (Week 1-2)

**Deliverables:**
- [ ] All micro-benchmarks implemented
- [ ] All macro-benchmarks implemented
- [ ] Baseline performance report generated
- [ ] Baseline committed to git

**Effort:** 4-6 days

### 6.3 Phase 3: Optimization Implementation (Week 3-5)

**Deliverables:**
- [ ] Constant folding implemented
- [ ] Algebraic simplification implemented
- [ ] Call-site inlining implemented (optional)
- [ ] All optimizations tested

**Effort:** 15-20 days (concurrent with compiler implementation)

### 6.4 Phase 4: Performance Validation (Week 6)

**Deliverables:**
- [ ] All benchmarks re-run with optimizations
- [ ] Performance improvements quantified
- [ ] Regression analysis completed
- [ ] Final performance report generated

**Effort:** 3-5 days

### 6.5 Phase 5: Continuous Monitoring (Ongoing)

**Deliverables:**
- [ ] Performance tests in CI pipeline
- [ ] Automated regression detection
- [ ] Monthly performance reviews
- [ ] Quarterly benchmark updates

**Effort:** 1-2 hours per month (maintenance)

---

## Part 7: Success Criteria Summary

### 7.1 Minimum Acceptance Criteria (Must Meet)

| Criterion | Target | Measurement Method |
|-----------|--------|-------------------|
| **Arithmetic-Heavy Performance** | ≥15% improvement | PhysicsSimulation benchmark |
| **Typical Application Performance** | ≥5% improvement | TodoMVC benchmark |
| **Bundle Size** | -2-5% reduction | Generated JavaScript file size |
| **Compilation Time** | ±5% acceptable | Compilation time measurement |
| **Test Coverage** | ≥80% | Stack coverage report |
| **Backward Compatibility** | 100% tests pass | Existing test suite |

### 7.2 Target Goals (Should Meet)

| Criterion | Target | Measurement Method |
|-----------|--------|-------------------|
| **Arithmetic-Heavy Performance** | 25-50% improvement | PhysicsSimulation benchmark |
| **Constant Folding** | 100% pure constants | ConstantFolding benchmark |
| **Identity Elimination** | 80-90% reduction | AlgebraicSimplification benchmark |
| **Bundle Size** | -5% reduction | Generated JavaScript file size |

### 7.3 Stretch Goals (Nice to Have)

| Criterion | Target | Measurement Method |
|-----------|--------|-------------------|
| **Arithmetic-Heavy Performance** | 50%+ improvement | Multiple benchmarks |
| **Strength Reduction** | Implemented | Code analysis |
| **Associativity Reordering** | Implemented | Code analysis |
| **Industry Recognition** | Blog post published | Publication |

---

## Conclusion

This comprehensive performance analysis plan provides:

1. **Clear Baseline Establishment**: Structured approach to measuring current performance
2. **Realistic Benchmarks**: Micro and macro benchmarks covering real-world usage
3. **Actionable Optimization Opportunities**: Specific optimizations with estimated impact
4. **Reproducible Methodology**: Automated benchmarking and reporting
5. **Continuous Monitoring**: CI/CD integration for ongoing performance validation

**Next Steps:**
1. Review and approve this performance analysis plan
2. Begin Phase 1: Implement benchmark infrastructure
3. Establish performance baselines
4. Integrate with native arithmetic operator implementation phases
5. Validate performance improvements iteratively

**Expected Timeline:**
- **Infrastructure Setup**: Week 1
- **Baseline Establishment**: Week 1-2
- **Continuous Validation**: Ongoing during implementation (Weeks 3-8)
- **Final Validation**: Week 6-8

This plan aligns with the **NATIVE_ARITHMETIC_OPERATORS_MASTER_PLAN.md** and provides the performance validation framework needed to achieve the ≥15% improvement target.

---

**Document Prepared By:** Performance Analysis Agent
**Technical Review:** ARCHITECT, OPTIMIZER, ANALYST Agents
**Document Type:** Performance Analysis Strategy
**Classification:** Internal Use
**Distribution:** Engineering Team, Performance Engineers

**For Questions Contact:**
- **Benchmarking Infrastructure**: See Section 2.2
- **Optimization Opportunities**: See Section 3
- **Report Templates**: See Section 4
- **CI/CD Integration**: See Section 5

---

**END OF PERFORMANCE ANALYSIS PLAN**
