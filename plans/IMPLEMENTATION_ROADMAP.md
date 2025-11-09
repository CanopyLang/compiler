# Native Arithmetic Operators - Implementation Roadmap

**Version**: 1.0  
**Created**: 2025-10-28  
**Status**: Planning Phase  
**Target**: Canopy Compiler v0.19.2

## Executive Summary

This roadmap provides a detailed, phased implementation plan for adding native arithmetic operator support to the Canopy compiler. The goal is to compile arithmetic operators (+, -, *, /, //, ^, %) directly to JavaScript operators rather than function calls, achieving ≥5% performance improvement and cleaner generated code.

**Key Metrics**:
- **Total Estimated Time**: 29-44 days
- **Phases**: 8 incremental phases
- **Risk Level**: Medium (well-understood changes, good test coverage)
- **Rollback Strategy**: Each phase has clear boundaries for safe rollback

## Table of Contents

1. [Project Goals](#project-goals)
2. [Phase 0: Preparation](#phase-0-preparation-1-2-days)
3. [Phase 1: AST Foundation](#phase-1-ast-foundation-3-5-days)
4. [Phase 2: Optimization Integration](#phase-2-optimization-integration-3-5-days)
5. [Phase 3: Code Generation](#phase-3-code-generation-2-3-days)
6. [Phase 4: Constant Folding](#phase-4-constant-folding-4-6-days)
7. [Phase 5: Algebraic Simplification](#phase-5-algebraic-simplification-4-6-days)
8. [Phase 6: Integration & Testing](#phase-6-integration-testing-5-7-days)
9. [Phase 7: Documentation & Polish](#phase-7-documentation-polish-3-4-days)
10. [Development Guide](#development-guide)
11. [Risk Mitigation](#risk-mitigation)
12. [Appendix: File Modification Checklist](#appendix-file-modification-checklist)

---

## Project Goals

### Primary Objectives

1. **Performance**: Achieve ≥5% improvement in arithmetic-heavy code compilation and runtime
2. **Code Quality**: Generate cleaner, more readable JavaScript output
3. **Optimization**: Enable compile-time arithmetic evaluation (constant folding)
4. **Algebraic Simplification**: Implement identity elimination and absorption rules
5. **Standards Compliance**: Maintain all CLAUDE.md coding standards throughout

### Non-Goals

- Type system changes (arithmetic remains dynamically typed at JS level)
- Breaking changes to existing Canopy code
- Complex algebraic pattern matching beyond basic rules
- Runtime performance profiling (compilation performance only)

### Success Criteria

- ✅ All existing tests pass
- ✅ New test coverage ≥80% for modified modules
- ✅ Performance benchmarks show ≥5% improvement
- ✅ Golden file tests validate output consistency
- ✅ No regressions in error reporting quality
- ✅ Documentation complete and accurate

---

## Phase 0: Preparation (1-2 days)

**Goal**: Establish comprehensive test baseline and documentation before any code changes.

### Tasks

#### 0.1: Test Suite Expansion (4-6 hours)

**Files to Create/Modify**:
- `test/Golden/ArithmeticCompilation.hs` (NEW)
- `test/Unit/Optimize/ExpressionArithmeticTest.hs` (NEW)
- `test/Integration/ArithmeticEndToEndTest.hs` (NEW)

**Actions**:
1. Create golden file tests for current arithmetic compilation output
   - Test cases: `1 + 2`, `x * y`, `(a + b) * c`, nested expressions
   - Capture current JS output as baseline
   - Add tests for all operators: +, -, *, /, //, ^, %

2. Add unit tests for `Optimize.Expression` arithmetic handling
   - Test operator preservation through optimization
   - Test cycle detection with arithmetic
   - Test nested expression optimization

3. Create integration tests for end-to-end compilation
   - Parse → Canonicalize → Optimize → Generate pipeline
   - Verify arithmetic in various contexts (let bindings, case expressions, etc.)

**Test Coverage Goals**:
- Binary operators: All 7 operators (+, -, *, /, //, ^, %)
- Negate unary operator
- Mixed operators with precedence
- Arithmetic in all expression contexts
- Edge cases: zero, negatives, large numbers

**Acceptance Criteria**:
- All new tests pass with current implementation
- Test coverage report shows baseline coverage
- Golden files capture exact current output

#### 0.2: Performance Baseline (2-3 hours)

**Files to Create**:
- `bench/ArithmeticBench.hs` (NEW)
- `test-cases/arithmetic-heavy.can` (NEW)

**Actions**:
1. Create benchmark suite using `criterion` or `tasty-bench`
   - Benchmark compilation time for arithmetic-heavy modules
   - Benchmark generated code size
   - Track memory usage during compilation

2. Create test Canopy modules with varying arithmetic patterns
   - Simple: `add x y = x + y`
   - Medium: `calculate a b c = (a + b) * c - (a / b)`
   - Complex: Nested arithmetic in recursive functions

3. Run baseline benchmarks and record results
   - Document current compilation times
   - Document current output sizes
   - Establish ±2% margin for regression detection

**Acceptance Criteria**:
- Benchmarks run successfully
- Results documented in `bench/BASELINE.md`
- CI integration ready (optional for now)

#### 0.3: Architecture Documentation (3-4 hours)

**Files to Create**:
- `docs/architecture/ARITHMETIC_OPERATORS.md` (NEW)
- `docs/architecture/COMPILER_PIPELINE.md` (UPDATE)

**Actions**:
1. Document current arithmetic compilation flow
   - How Source AST represents arithmetic
   - How Canonical AST handles Binop nodes
   - How Optimize passes through to function calls
   - How Generate creates JavaScript function calls

2. Create dependency graph visualization
   - Module dependencies related to arithmetic
   - Data flow from parser to code generator
   - Identify all touchpoints for modifications

3. Document existing operator infrastructure
   - `Canonicalize.Environment` binop handling
   - `AST.Utils.Binop` precedence and associativity
   - Operator resolution in `findBinop`

**Acceptance Criteria**:
- Architecture docs complete and reviewed
- Dependency graph created (Graphviz/Mermaid)
- All team members understand current implementation

### Phase 0 Deliverables

- [ ] Comprehensive test suite with ≥80% coverage baseline
- [ ] Performance benchmarks with documented baseline
- [ ] Complete architecture documentation
- [ ] Golden file tests capturing current behavior

### Phase 0 Risks & Mitigation

**Risk**: Incomplete test coverage misses edge cases  
**Mitigation**: Review test coverage reports, add tests for <80% modules

**Risk**: Benchmarks not representative of real usage  
**Mitigation**: Use actual Canopy packages (elm/core ports) as test cases

---

## Phase 1: AST Foundation (3-5 days)

**Goal**: Add native operator nodes to Canonical AST and update serialization.

### Tasks

#### 1.1: Extend AST.Canonical.Expr_ (6-8 hours)

**Files to Modify**:
- `packages/canopy-core/src/AST/Canonical.hs`

**Actions**:
1. Add new expression constructors to `Expr_` data type:
```haskell
data Expr_
  = ... (existing constructors)
  | Add Expr Expr      -- Native addition
  | Sub Expr Expr      -- Native subtraction
  | Mul Expr Expr      -- Native multiplication
  | Div Expr Expr      -- Native division (float)
  | IntDiv Expr Expr   -- Native integer division
  | Pow Expr Expr      -- Native power
  | Mod Expr Expr      -- Native modulo
```

2. Update Show instance to include new constructors

3. Add comprehensive Haddock documentation for each operator
   - Explain semantic meaning (Int vs Float)
   - Document precedence expectations
   - Note any special cases (division by zero handling)

**Design Decisions**:
- Use separate constructors per operator (not generic `BinOp Name Expr Expr`)
- Rationale: Type-safe, enables pattern matching optimizations, clearer intent

**Acceptance Criteria**:
- Code compiles without warnings
- Show instance produces correct output
- Haddock documentation complete
- Function size ≤15 lines per CLAUDE.md

#### 1.2: Update Binary Serialization (4-6 hours)

**Files to Modify**:
- `packages/canopy-core/src/AST/Canonical.hs` (Binary instance)

**Actions**:
1. Add serialization cases for new operators to `Binary.Binary Expr_` instance
   - Assign unique Word8 tags (27-33)
   - Follow existing pattern for consistency

2. Update deserialization to handle new tags
   - Add cases to `get` implementation
   - Ensure version compatibility

3. Update serialization documentation
   - Document tag assignments
   - Note version requirements

**Binary Format**:
```haskell
putExpr expr = case expr of
  Add a b -> Binary.putWord8 27 >> Binary.put a >> Binary.put b
  Sub a b -> Binary.putWord8 28 >> Binary.put a >> Binary.put b
  Mul a b -> Binary.putWord8 29 >> Binary.put a >> Binary.put b
  Div a b -> Binary.putWord8 30 >> Binary.put a >> Binary.put b
  IntDiv a b -> Binary.putWord8 31 >> Binary.put a >> Binary.put b
  Pow a b -> Binary.putWord8 32 >> Binary.put a >> Binary.put b
  Mod a b -> Binary.putWord8 33 >> Binary.put a >> Binary.put b
```

**Acceptance Criteria**:
- Serialization round-trips correctly
- Property tests validate binary format
- No breaking changes to existing serialization

#### 1.3: Update Canonicalize.Expression (8-10 hours)

**Files to Modify**:
- `packages/canopy-core/src/Canonicalize/Expression.hs`

**Actions**:
1. Modify `canonicalizeBinops` to detect arithmetic operators
   - Check if operator resolves to `Basics.add`, `Basics.mul`, etc.
   - Create native operator nodes instead of `Can.Binop`

2. Add helper function `isArithmeticOp`:
```haskell
-- | Check if binop is native arithmetic operator.
isArithmeticOp :: Env.Binop -> Maybe ArithOp
isArithmeticOp (Env.Binop op home name _ _ _) =
  if home == ModuleName.basics
    then case Name.toChars name of
      "add" -> Just OpAdd
      "sub" -> Just OpSub
      "mul" -> Just OpMul
      "fdiv" -> Just OpDiv
      "idiv" -> Just OpIntDiv
      "pow" -> Just OpPow
      "remainderBy" -> Just OpMod
      _ -> Nothing
    else Nothing

data ArithOp = OpAdd | OpSub | OpMul | OpDiv | OpIntDiv | OpPow | OpMod
```

3. Update `toBinop` to use native operators:
```haskell
toBinop :: Env.Binop -> Can.Expr -> Can.Expr -> Can.Expr
toBinop binop left right =
  case isArithmeticOp binop of
    Just OpAdd -> A.merge left right (Can.Add left right)
    Just OpSub -> A.merge left right (Can.Sub left right)
    Just OpMul -> A.merge left right (Can.Mul left right)
    Just OpDiv -> A.merge left right (Can.Div left right)
    Just OpIntDiv -> A.merge left right (Can.IntDiv left right)
    Just OpPow -> A.merge left right (Can.Pow left right)
    Just OpMod -> A.merge left right (Can.Mod left right)
    Nothing -> A.merge left right (Can.Binop op home name annotation left right)
```

4. Preserve existing behavior for non-arithmetic operators
   - Keep `Can.Binop` for (==), (||), (<|), etc.
   - No changes to operator precedence/associativity

**Design Considerations**:
- Maintain backward compatibility with custom operators
- Preserve debug information and regions
- Keep function complexity ≤4 branches

**Acceptance Criteria**:
- Arithmetic operators create native nodes
- Non-arithmetic operators unchanged
- All canonicalization tests pass
- New unit tests verify native node creation

#### 1.4: Add Unit Tests (4-6 hours)

**Files to Create/Modify**:
- `test/Unit/AST/CanonicalArithmeticTest.hs` (NEW)
- `test/Unit/Canonicalize/ExpressionArithmeticTest.hs` (UPDATE)

**Actions**:
1. Add AST construction tests
   - Create each native operator node
   - Verify show instances
   - Test region preservation

2. Add canonicalization tests
   - Verify arithmetic detection
   - Test operator resolution
   - Confirm precedence handling
   - Test mixed native/custom operators

3. Add serialization tests
   - Round-trip property tests
   - Test all operator tags
   - Verify version compatibility

**Test Coverage**:
- All 7 arithmetic operators
- Nested expressions
- Mixed with non-arithmetic operators
- Edge cases (variables, literals, complex expressions)

**Acceptance Criteria**:
- Test coverage ≥80% for modified modules
- All tests pass
- No meaningless tests (per CLAUDE.md anti-patterns)

### Phase 1 Deliverables

- [ ] Extended Canonical AST with native operators
- [ ] Updated Binary serialization
- [ ] Modified Canonicalize.Expression for detection
- [ ] Comprehensive unit tests (≥80% coverage)

### Phase 1 Milestone

**Success Criteria**: Can parse and canonicalize native arithmetic operators into Canonical AST with proper serialization.

### Phase 1 Risks & Mitigation

**Risk**: Binary format changes break .elmi cache files  
**Mitigation**: Version bump in cache format, add migration test

**Risk**: Operator detection logic too complex  
**Mitigation**: Use simple pattern matching, extract to helper functions

**Risk**: Precedence/associativity handling breaks  
**Mitigation**: Preserve existing `toBinopStep` logic, only change final node creation

---

## Phase 2: Optimization Integration (3-5 days)

**Goal**: Extend Optimized AST to preserve native operators through optimization passes.

### Tasks

#### 2.1: Extend AST.Optimized.Expr (6-8 hours)

**Files to Modify**:
- `packages/canopy-core/src/AST/Optimized.hs`

**Actions**:
1. Add native operator constructors to `Expr` data type:
```haskell
data Expr
  = ... (existing constructors)
  | Add Expr Expr      -- Optimized addition
  | Sub Expr Expr      -- Optimized subtraction
  | Mul Expr Expr      -- Optimized multiplication
  | Div Expr Expr      -- Optimized division
  | IntDiv Expr Expr   -- Optimized integer division
  | Pow Expr Expr      -- Optimized power
  | Mod Expr Expr      -- Optimized modulo
  deriving (Show)
```

2. Update Show instance

3. Add comprehensive Haddock documentation
   - Explain optimization opportunities
   - Note differences from Canonical AST
   - Document when used vs. `Call`

**Design Decisions**:
- Mirror Canonical AST structure for consistency
- Separate constructors enable optimization pattern matching

**Acceptance Criteria**:
- Code compiles without warnings
- Show instance correct
- Haddock complete

#### 2.2: Update Binary Serialization (4-6 hours)

**Files to Modify**:
- `packages/canopy-core/src/AST/Optimized.hs` (Binary instance)

**Actions**:
1. Add serialization for new operators
   - Use Word8 tags 27-33 (matching Canonical)
   - Follow existing `putExpr` pattern

2. Update deserialization
   - Add cases to `getExpr`
   - Handle new tags in `getExprControl` or new helper

3. Update serialization helpers
   - May need new `putExprArithmetic` helper
   - Keep functions ≤15 lines

**Binary Format**:
```haskell
putExprArithmetic :: Expr -> Binary.Put
putExprArithmetic expr = case expr of
  Add a b -> Binary.putWord8 27 >> Binary.put a >> Binary.put b
  Sub a b -> Binary.putWord8 28 >> Binary.put a >> Binary.put b
  Mul a b -> Binary.putWord8 29 >> Binary.put a >> Binary.put b
  Div a b -> Binary.putWord8 30 >> Binary.put a >> Binary.put b
  IntDiv a b -> Binary.putWord8 31 >> Binary.put a >> Binary.put b
  Pow a b -> Binary.putWord8 32 >> Binary.put a >> Binary.put b
  Mod a b -> Binary.putWord8 33 >> Binary.put a >> Binary.put b
  _ -> error "putExprArithmetic: unexpected expression"
```

**Acceptance Criteria**:
- Serialization round-trips
- Property tests pass
- Compatible with existing cache format (version bump if needed)

#### 2.3: Modify Optimize.Expression (8-10 hours)

**Files to Modify**:
- `packages/canopy-core/src/Optimize/Expression.hs`

**Actions**:
1. Update `optimize` function to handle Canonical arithmetic nodes:
```haskell
optimize cycle (A.At region expression) =
  case expression of
    Can.Add left right ->
      Opt.Add
        <$> optimize cycle left
        <*> optimize cycle right
    Can.Sub left right ->
      Opt.Sub
        <$> optimize cycle left
        <*> optimize cycle right
    -- Similar for Mul, Div, IntDiv, Pow, Mod
    Can.Binop _ home name _ left right ->
      -- Handle non-arithmetic operators
      do
        optFunc <- Names.registerGlobal home name
        optLeft <- optimize cycle left
        optRight <- optimize cycle right
        return (Opt.Call optFunc [optLeft, optRight])
```

2. Extract arithmetic handling to helper:
```haskell
optimizeArithmetic :: 
  Cycle -> 
  (Opt.Expr -> Opt.Expr -> Opt.Expr) -> 
  Can.Expr -> 
  Can.Expr -> 
  Names.Tracker Opt.Expr
optimizeArithmetic cycle constructor left right =
  constructor
    <$> optimize cycle left
    <*> optimize cycle right
```

3. Preserve optimization behavior
   - Keep cycle detection
   - Maintain Names.Tracker usage
   - No changes to other optimization passes

**Design Considerations**:
- Arithmetic operators do NOT need global registration (they're intrinsic)
- No `Names.registerGlobal` calls for arithmetic
- Preserve all existing optimization patterns

**Acceptance Criteria**:
- Native operators flow through optimization unchanged
- Non-arithmetic operators still work
- No performance regression
- Function complexity ≤4 branches

#### 2.4: Add Unit Tests (4-6 hours)

**Files to Create/Modify**:
- `test/Unit/Optimize/ExpressionArithmeticTest.hs` (NEW)
- `test/Property/AST/OptimizedBinaryProps.hs` (UPDATE)

**Actions**:
1. Add optimization tests
   - Test each operator optimizes correctly
   - Verify nested expressions
   - Test with let bindings and case expressions

2. Add property tests
   - Serialization round-trips
   - Optimization preserves semantics
   - Cycle detection still works

3. Add regression tests
   - Ensure non-arithmetic operators still work
   - Test mixed arithmetic and non-arithmetic

**Acceptance Criteria**:
- Test coverage ≥80%
- All tests pass
- Property tests verify invariants

### Phase 2 Deliverables

- [ ] Extended Optimized AST with native operators
- [ ] Updated Binary serialization
- [ ] Modified Optimize.Expression for preservation
- [ ] Comprehensive unit tests (≥80% coverage)

### Phase 2 Milestone

**Success Criteria**: Native arithmetic operators preserved through optimization pass without being converted to function calls.

### Phase 2 Risks & Mitigation

**Risk**: Optimization passes break with new nodes  
**Mitigation**: Thorough testing of all optimization contexts (let, case, etc.)

**Risk**: Global name registration causes issues  
**Mitigation**: Skip registration for arithmetic (they're intrinsic, not imports)

---

## Phase 3: Code Generation (2-3 days)

**Goal**: Generate direct JavaScript operators for native arithmetic nodes.

### Tasks

#### 3.1: Modify Generate.JavaScript.Expression (6-8 hours)

**Files to Modify**:
- `packages/canopy-core/src/Generate/JavaScript/Expression.hs`

**Actions**:
1. Add cases to `generate` function:
```haskell
generate mode expression =
  case expression of
    Opt.Add left right ->
      JsExpr $ JS.InfixOp "+" 
        (generateJsExpr mode left) 
        (generateJsExpr mode right)
    Opt.Sub left right ->
      JsExpr $ JS.InfixOp "-" 
        (generateJsExpr mode left) 
        (generateJsExpr mode right)
    Opt.Mul left right ->
      JsExpr $ JS.InfixOp "*" 
        (generateJsExpr mode left) 
        (generateJsExpr mode right)
    Opt.Div left right ->
      JsExpr $ JS.InfixOp "/" 
        (generateJsExpr mode left) 
        (generateJsExpr mode right)
    Opt.IntDiv left right ->
      -- Special handling: (left / right) | 0 for integer division
      let jsDiv = JS.InfixOp "/" 
            (generateJsExpr mode left) 
            (generateJsExpr mode right)
      in JsExpr $ JS.InfixOp "|" jsDiv (JS.Int 0)
    Opt.Pow left right ->
      JsExpr $ JS.Call 
        (JS.Access (JS.Ref "Math") "pow")
        [generateJsExpr mode left, generateJsExpr mode right]
    Opt.Mod left right ->
      JsExpr $ JS.InfixOp "%" 
        (generateJsExpr mode left) 
        (generateJsExpr mode right)
```

2. Update `Generate.JavaScript.Builder` if needed
   - May need to add `InfixOp` constructor to `JS.Expr` type
   - Or use existing JavaScript AST nodes

3. Add helper functions for operator generation:
```haskell
-- | Generate JavaScript operator with proper precedence.
generateBinaryOp :: 
  Mode.Mode -> 
  String -> 
  Opt.Expr -> 
  Opt.Expr -> 
  JS.Expr
generateBinaryOp mode op left right =
  JS.InfixOp op 
    (generateJsExpr mode left) 
    (generateJsExpr mode right)
```

4. Remove arithmetic pattern matching from `generateCall`
   - Currently handles `Basics.add`, etc. as special cases
   - These should never reach code generation now
   - Keep non-arithmetic function calls

**JavaScript Output Examples**:
```javascript
// Before: F2($elm$core$Basics$add, 1, 2)
// After:  1 + 2

// Before: F2($elm$core$Basics$mul, x, y)
// After:  x * y

// Before: F2($elm$core$Basics$idiv, 10, 3)
// After:  (10 / 3) | 0
```

**Design Considerations**:
- IntDiv requires special handling: `(a / b) | 0` for integer truncation
- Pow uses `Math.pow()` (JavaScript doesn't have ** in older engines)
- Maintain operator precedence in generated code
- Add parentheses when necessary for correctness

**Acceptance Criteria**:
- Direct JavaScript operators generated
- Output is valid JavaScript
- Precedence preserved correctly
- Dev vs Prod mode differences respected

#### 3.2: Update Generate.JavaScript.Builder (3-4 hours)

**Files to Modify**:
- `packages/canopy-core/src/Generate/JavaScript/Builder.hs`

**Actions**:
1. Add `InfixOp` constructor if not present:
```haskell
data Expr
  = ... (existing constructors)
  | InfixOp String Expr Expr  -- Binary infix operator
  deriving (Show)
```

2. Update `exprToBuilder` to handle `InfixOp`:
```haskell
exprToBuilder expr = case expr of
  InfixOp op left right ->
    exprToBuilder left 
      <> BB.fromString " " 
      <> BB.fromString op 
      <> BB.fromString " " 
      <> exprToBuilder right
  -- ... existing cases
```

3. Add parenthesization logic:
```haskell
-- | Add parentheses to expression if needed for precedence.
maybeParens :: Expr -> Builder
maybeParens expr = case expr of
  InfixOp _ _ _ -> 
    BB.fromString "(" 
      <> exprToBuilder expr 
      <> BB.fromString ")"
  _ -> exprToBuilder expr
```

**Acceptance Criteria**:
- InfixOp renders correctly
- Parentheses added when necessary
- Builder efficiency maintained

#### 3.3: Add Code Generation Tests (4-5 hours)

**Files to Modify/Create**:
- `test/Unit/Generate/JavaScript/ExpressionArithmeticTest.hs` (UPDATE)
- `test/Golden/JavaScriptOutput.hs` (NEW)

**Actions**:
1. Add unit tests for each operator
   - Test simple cases: `1 + 2` → `1 + 2`
   - Test with variables: `x * y` → `x * y`
   - Test nested: `(a + b) * c` → `(a + b) * c`

2. Add golden file tests
   - Capture complete module output
   - Test dev vs. prod mode differences
   - Verify no regression in output format

3. Add property tests
   - Roundtrip property: parse → compile → parse should preserve semantics
   - Precedence property: output respects operator precedence

**Golden File Examples**:
```javascript
// test-cases/simple-arithmetic.can
add x y = x + y
mul x y = x * y

// golden/simple-arithmetic.dev.js
var $author$project$Main$add = F2(function(x, y) {
  return x + y;
});

var $author$project$Main$mul = F2(function(x, y) {
  return x * y;
});
```

**Acceptance Criteria**:
- All golden files pass
- Unit tests verify correct output
- Test coverage ≥80%

### Phase 3 Deliverables

- [ ] Direct JavaScript operator generation
- [ ] Updated Builder for infix operators
- [ ] Comprehensive tests with golden files
- [ ] Verified dev vs. prod mode handling

### Phase 3 Milestone

**Success Criteria**: Native arithmetic operators compile directly to JavaScript operators, producing cleaner and more readable output.

### Phase 3 Risks & Mitigation

**Risk**: Operator precedence causes incorrect output  
**Mitigation**: Extensive golden file tests, visual inspection of output

**Risk**: IntDiv implementation incorrect  
**Mitigation**: Test against Elm Basics.idiv semantics, use `| 0` trick

**Risk**: Dev/Prod mode differences break code  
**Mitigation**: Test both modes, ensure both produce valid JS

---

## Phase 4: Constant Folding (4-6 days)

**Goal**: Implement compile-time evaluation of constant arithmetic expressions.

### Tasks

#### 4.1: Create Optimize.Arithmetic Module (8-10 hours)

**Files to Create**:
- `packages/canopy-core/src/Optimize/Arithmetic.hs` (NEW)

**Actions**:
1. Define arithmetic evaluation interface:
```haskell
-- | Optimize.Arithmetic - Compile-time arithmetic evaluation
--
-- This module implements constant folding and algebraic simplification
-- for arithmetic expressions. Evaluates constant expressions at compile
-- time to improve runtime performance.
module Optimize.Arithmetic
  ( foldConstants
  , simplifyArithmetic
  ) where

-- | Fold constant arithmetic expressions.
--
-- Evaluates arithmetic operations on literal values at compile time.
-- Handles Int and Float literals with proper semantics.
foldConstants :: Opt.Expr -> Opt.Expr
foldConstants expr = case expr of
  Opt.Add (Opt.Int a) (Opt.Int b) -> Opt.Int (a + b)
  Opt.Add (Opt.Float a) (Opt.Float b) -> Opt.Float (a + b)
  Opt.Sub (Opt.Int a) (Opt.Int b) -> Opt.Int (a - b)
  Opt.Sub (Opt.Float a) (Opt.Float b) -> Opt.Float (a - b)
  -- ... similar for Mul, Div, IntDiv, Pow, Mod
  _ -> expr
```

2. Implement constant evaluation for Int operations:
```haskell
evalIntBinop :: 
  (Int -> Int -> Int) -> 
  Opt.Expr -> 
  Opt.Expr -> 
  Maybe Opt.Expr
evalIntBinop op (Opt.Int a) (Opt.Int b) =
  Just (Opt.Int (op a b))
evalIntBinop _ _ _ = Nothing
```

3. Implement constant evaluation for Float operations:
```haskell
evalFloatBinop :: 
  (Double -> Double -> Double) -> 
  Opt.Expr -> 
  Opt.Expr -> 
  Maybe Opt.Expr
evalFloatBinop op (Opt.Float a) (Opt.Float b) =
  Just (Opt.Float (op a b))
evalFloatBinop _ _ _ = Nothing
```

4. Handle mixed Int/Float with proper semantics:
```haskell
-- | Evaluate arithmetic with mixed Int/Float operands.
--
-- Follows JavaScript coercion rules:
-- - Int op Int → Int (except division)
-- - Float op anything → Float
-- - Int / Int → Float
evalMixedBinop :: 
  (Double -> Double -> Double) -> 
  Opt.Expr -> 
  Opt.Expr -> 
  Maybe Opt.Expr
evalMixedBinop op left right =
  case (toNumber left, toNumber right) of
    (Just a, Just b) -> Just (Opt.Float (op a b))
    _ -> Nothing

toNumber :: Opt.Expr -> Maybe Double
toNumber expr = case expr of
  Opt.Int n -> Just (fromIntegral n)
  Opt.Float f -> Just f
  _ -> Nothing
```

5. Add special case handling:
   - Division by zero: keep as runtime check
   - Integer overflow: follow JavaScript semantics
   - Float precision: use Double internally

**Design Considerations**:
- Keep functions ≤15 lines each
- Use helper functions for each operator
- Preserve NaN and Infinity semantics
- Document integer overflow behavior

**Acceptance Criteria**:
- All constant expressions fold correctly
- Int and Float handled separately
- Mixed types handled properly
- No invalid transformations

#### 4.2: Integrate into Optimization Pipeline (4-6 hours)

**Files to Modify**:
- `packages/canopy-core/src/Optimize/Expression.hs`
- `packages/canopy-core/src/Optimize/Module.hs`

**Actions**:
1. Add constant folding pass to `optimize`:
```haskell
import qualified Optimize.Arithmetic as Arith

optimize cycle (A.At region expression) =
  case expression of
    Can.Add left right ->
      do
        optLeft <- optimize cycle left
        optRight <- optimize cycle right
        pure $ Arith.foldConstants (Opt.Add optLeft optRight)
    -- Similar for other operators
```

2. Add module-level configuration:
   - Optional flag to enable/disable constant folding
   - Default: enabled for Prod mode, optional for Dev mode

3. Update `Optimize.Module` to track statistics:
   - Count number of constants folded
   - Report optimization effectiveness

**Acceptance Criteria**:
- Constant folding integrated smoothly
- Can be toggled via configuration
- Statistics tracked correctly

#### 4.3: Add Comprehensive Tests (6-8 hours)

**Files to Create**:
- `test/Unit/Optimize/ArithmeticTest.hs` (NEW)
- `test/Property/Optimize/ArithmeticProps.hs` (NEW)
- `test/Golden/ConstantFolding.hs` (NEW)

**Actions**:
1. Add unit tests for constant evaluation
   - Test each operator with Int literals
   - Test each operator with Float literals
   - Test mixed Int/Float operations
   - Test edge cases (zero, negatives, large numbers)

2. Add property tests
   - Folding produces correct results
   - Folding preserves semantics
   - Commutativity and associativity respected

3. Add golden file tests
   - Verify folded output matches expected
   - Test no folding for non-constants
   - Test nested constant expressions

**Test Cases**:
```haskell
-- Simple folding
1 + 2  →  3
3.5 * 2.0  →  7.0

-- Nested folding
(1 + 2) * 3  →  9
2 ^ (3 + 1)  →  16

-- Mixed types
5 / 2  →  2.5
10 // 3  →  3

-- No folding
x + 1  →  x + 1
1 + y  →  1 + y

-- Partial folding
(1 + 2) + x  →  3 + x
```

**Acceptance Criteria**:
- Test coverage ≥80%
- All test cases pass
- Property tests verify correctness
- Golden files capture expected behavior

### Phase 4 Deliverables

- [ ] Optimize.Arithmetic module with constant folding
- [ ] Integration into optimization pipeline
- [ ] Comprehensive test suite (≥80% coverage)
- [ ] Golden file tests verifying output

### Phase 4 Milestone

**Success Criteria**: Constant arithmetic expressions are evaluated at compile time, reducing runtime computation and improving generated code.

### Phase 4 Risks & Mitigation

**Risk**: Incorrect constant evaluation produces wrong results  
**Mitigation**: Extensive testing, cross-reference with JavaScript semantics

**Risk**: Floating-point precision issues  
**Mitigation**: Document precision guarantees, use Double internally

**Risk**: Integer overflow behavior differs from runtime  
**Mitigation**: Follow JavaScript ToInt32 semantics exactly

---

## Phase 5: Algebraic Simplification (4-6 days)

**Goal**: Implement algebraic simplification rules (identity elimination, absorption).

### Tasks

#### 5.1: Implement Identity Elimination (6-8 hours)

**Files to Modify**:
- `packages/canopy-core/src/Optimize/Arithmetic.hs`

**Actions**:
1. Add identity simplification rules:
```haskell
-- | Simplify arithmetic with algebraic identities.
--
-- Applies algebraic simplification rules:
-- - x + 0 → x
-- - 0 + x → x
-- - x * 1 → x
-- - 1 * x → x
-- - x - 0 → x
-- - x / 1 → x
-- - x ^ 1 → x
simplifyArithmetic :: Opt.Expr -> Opt.Expr
simplifyArithmetic expr = case expr of
  Opt.Add left (Opt.Int 0) -> left
  Opt.Add (Opt.Int 0) right -> right
  Opt.Add left (Opt.Float 0.0) -> left
  Opt.Add (Opt.Float 0.0) right -> right
  
  Opt.Mul left (Opt.Int 1) -> left
  Opt.Mul (Opt.Int 1) right -> right
  Opt.Mul left (Opt.Float 1.0) -> left
  Opt.Mul (Opt.Float 1.0) right -> right
  
  Opt.Sub left (Opt.Int 0) -> left
  Opt.Sub left (Opt.Float 0.0) -> left
  
  Opt.Div left (Opt.Int 1) -> left
  Opt.Div left (Opt.Float 1.0) -> left
  
  Opt.Pow left (Opt.Int 1) -> left
  Opt.Pow left (Opt.Float 1.0) -> left
  
  _ -> expr
```

2. Extract helper functions for each simplification:
```haskell
-- | Simplify addition with zero.
simplifyAddZero :: Opt.Expr -> Opt.Expr -> Maybe Opt.Expr
simplifyAddZero left right
  | isZero right = Just left
  | isZero left = Just right
  | otherwise = Nothing

isZero :: Opt.Expr -> Bool
isZero (Opt.Int 0) = True
isZero (Opt.Float 0.0) = True
isZero _ = False
```

3. Add more identities:
```haskell
-- x ^ 0 → 1
-- 0 ^ x → 0 (for x > 0)
-- x * 0 → 0 (absorption)
-- 0 * x → 0
simplifyPowerZero :: Opt.Expr -> Opt.Expr -> Maybe Opt.Expr
simplifyPowerZero left right
  | isZero right = Just (Opt.Int 1)
  | isZero left = Just (Opt.Int 0)
  | otherwise = Nothing
```

**Design Considerations**:
- Apply simplifications recursively to sub-expressions
- Maintain semantics (don't eliminate side effects)
- Handle Float 0.0 and -0.0 correctly
- Don't simplify if it changes behavior (e.g., NaN propagation)

**Acceptance Criteria**:
- All identity rules implemented
- Simplifications preserve semantics
- Functions ≤15 lines each

#### 5.2: Implement Absorption Rules (4-6 hours)

**Files to Modify**:
- `packages/canopy-core/src/Optimize/Arithmetic.hs`

**Actions**:
1. Add absorption rules:
```haskell
-- | Apply absorption simplifications.
--
-- - x * 0 → 0
-- - 0 * x → 0
-- - 0 / x → 0 (for x ≠ 0)
-- - x % y → x (if x < y and both positive)
simplifyAbsorption :: Opt.Expr -> Opt.Expr
simplifyAbsorption expr = case expr of
  Opt.Mul _ (Opt.Int 0) -> Opt.Int 0
  Opt.Mul (Opt.Int 0) _ -> Opt.Int 0
  Opt.Mul _ (Opt.Float 0.0) -> Opt.Float 0.0
  Opt.Mul (Opt.Float 0.0) _ -> Opt.Float 0.0
  
  -- Be careful with division by zero
  Opt.Div (Opt.Int 0) right
    | not (isZero right) -> Opt.Int 0
  Opt.Div (Opt.Float 0.0) right
    | not (isZero right) -> Opt.Float 0.0
  
  _ -> expr
```

2. Add safety checks:
   - Don't simplify if it could hide runtime errors
   - Preserve division by zero checks
   - Document assumptions

**Acceptance Criteria**:
- Absorption rules implemented safely
- No elimination of runtime checks
- Semantics preserved

#### 5.3: Implement Constant Reassociation (6-8 hours)

**Files to Modify**:
- `packages/canopy-core/src/Optimize/Arithmetic.hs`

**Actions**:
1. Collect and combine constants in chains:
```haskell
-- | Reassociate constants in arithmetic chains.
--
-- Transforms: (1 + x) + 2  →  x + 3
--            (x * 2) * 3  →  x * 6
reassociateConstants :: Opt.Expr -> Opt.Expr
reassociateConstants expr = case expr of
  Opt.Add (Opt.Add left (Opt.Int a)) (Opt.Int b) ->
    Opt.Add left (Opt.Int (a + b))
  Opt.Add (Opt.Add (Opt.Int a) left) (Opt.Int b) ->
    Opt.Add left (Opt.Int (a + b))
  
  Opt.Mul (Opt.Mul left (Opt.Int a)) (Opt.Int b) ->
    Opt.Mul left (Opt.Int (a * b))
  Opt.Mul (Opt.Mul (Opt.Int a) left) (Opt.Int b) ->
    Opt.Mul left (Opt.Int (a * b))
  
  _ -> expr
```

2. Handle nested expressions:
```haskell
-- | Recursively reassociate in nested expressions.
deepReassociate :: Opt.Expr -> Opt.Expr
deepReassociate expr = case expr of
  Opt.Add left right ->
    reassociateConstants (Opt.Add 
      (deepReassociate left) 
      (deepReassociate right))
  -- Similar for other operators
  _ -> expr
```

**Design Considerations**:
- Only reassociate commutative and associative operators
- Don't reassociate subtraction or division
- Preserve evaluation order for side effects
- Document when reassociation is safe

**Acceptance Criteria**:
- Constant reassociation works correctly
- Only applies to commutative operators
- Nested expressions handled

#### 5.4: Add Pattern Matching Tests (6-8 hours)

**Files to Create/Modify**:
- `test/Unit/Optimize/ArithmeticSimplificationTest.hs` (NEW)
- `test/Property/Optimize/AlgebraProps.hs` (NEW)

**Actions**:
1. Add identity elimination tests
   - Test x + 0 → x
   - Test 0 + x → x
   - Test x * 1 → x
   - Test all identity rules

2. Add absorption tests
   - Test x * 0 → 0
   - Test 0 * x → 0
   - Test safe cases only

3. Add reassociation tests
   - Test (1 + x) + 2 → x + 3
   - Test (x * 2) * 3 → x * 6
   - Test non-reassociable cases unchanged

4. Add property tests
   - Simplification preserves value
   - No incorrect transformations
   - Idempotent (simplifying twice = simplifying once)

**Test Cases**:
```haskell
-- Identity elimination
x + 0  →  x
0 + x  →  x
x * 1  →  x
1 * x  →  x
x - 0  →  x
x / 1  →  x
x ^ 1  →  x

-- Absorption
x * 0  →  0
0 * x  →  0
0 / x  →  0

-- Power rules
x ^ 0  →  1
0 ^ x  →  0 (for x > 0)
1 ^ x  →  1

-- Reassociation
(1 + x) + 2  →  x + 3
(x * 2) * 3  →  x * 6
(2 * 3) * x  →  6 * x

-- No simplification
x + y  →  x + y (no constants)
x - 0.5  →  x - 0.5 (don't simplify subtract with non-zero)
```

**Acceptance Criteria**:
- Test coverage ≥80%
- All pattern matching tests pass
- Property tests verify correctness

### Phase 5 Deliverables

- [ ] Identity elimination implemented
- [ ] Absorption rules implemented
- [ ] Constant reassociation implemented
- [ ] Comprehensive tests with property validation

### Phase 5 Milestone

**Success Criteria**: Algebraic simplification rules reduce unnecessary arithmetic operations at compile time, further improving generated code.

### Phase 5 Risks & Mitigation

**Risk**: Incorrect simplifications produce wrong results  
**Mitigation**: Extensive testing, verify each rule manually

**Risk**: Simplifications change semantics (NaN, Infinity)  
**Mitigation**: Document IEEE 754 edge cases, test special values

**Risk**: Reassociation breaks in unexpected ways  
**Mitigation**: Only reassociate commutative and associative operators

---

## Phase 6: Integration & Testing (5-7 days)

**Goal**: Run full test suite, fix regressions, validate performance improvements.

### Tasks

#### 6.1: Run Full Test Suite (8-12 hours)

**Actions**:
1. Run all existing tests
   - Unit tests across all modules
   - Property tests for invariants
   - Integration tests end-to-end
   - Golden file tests for output

2. Identify and categorize failures
   - Regression bugs (worked before, broken now)
   - Expected failures (tests need updating)
   - New edge cases discovered

3. Create regression tracking document
   - List all failures with details
   - Prioritize by severity
   - Assign to fix batches

**Commands**:
```bash
# Run all tests
make test

# Run with coverage
make test-coverage

# Run specific suites
make test-unit
make test-property
make test-integration
make test-golden

# Run arithmetic-specific tests
stack test --ta="--pattern Arithmetic"
```

**Acceptance Criteria**:
- Test results documented
- Regressions catalogued
- Zero critical failures

#### 6.2: Fix Regressions (10-15 hours)

**Files to Modify**: TBD based on failures

**Process**:
1. Fix high-priority regressions first
   - Crashes or error messages
   - Incorrect output
   - Type system issues

2. Fix medium-priority regressions
   - Performance regressions
   - Warning messages
   - Suboptimal output

3. Fix low-priority regressions
   - Documentation issues
   - Code style violations
   - Minor optimizations missed

**Common Issues Expected**:
- Operator precedence in generated code
- Integer division edge cases
- Float precision differences
- Error message quality degradation
- Performance regressions in non-arithmetic code

**Acceptance Criteria**:
- All high-priority regressions fixed
- All medium-priority regressions fixed or documented
- Low-priority issues tracked for future

#### 6.3: Update Golden Files (4-6 hours)

**Files to Modify**:
- All golden file test expectations in `test/Golden/`

**Actions**:
1. Review all golden file changes
   - Verify changes are intentional and correct
   - Check that output is cleaner/better
   - Ensure no unexpected differences

2. Update golden files
   - Run `make golden-accept` or equivalent
   - Manually verify critical cases
   - Document significant changes

3. Add new golden file tests
   - Test cases demonstrating improvements
   - Edge cases discovered during testing
   - Regression prevention tests

**Examples**:
```javascript
// OLD: test/Golden/simple-arithmetic.js
var $author$project$Main$add = F2(function(x, y) {
  return F2($elm$core$Basics$add, x, y);
});

// NEW: test/Golden/simple-arithmetic.js
var $author$project$Main$add = F2(function(x, y) {
  return x + y;
});
```

**Acceptance Criteria**:
- All golden files updated and verified
- Changes documented and justified
- New golden tests added

#### 6.4: Performance Benchmarking (6-8 hours)

**Actions**:
1. Run performance benchmarks
   - Compare against Phase 0 baseline
   - Measure compilation time
   - Measure generated code size
   - Measure runtime performance (if applicable)

2. Analyze results
   - Calculate performance improvements
   - Identify any regressions
   - Document findings

3. Create performance report
   - Summary of improvements
   - Breakdown by optimization type
   - Comparison charts/graphs

**Benchmark Suite**:
```bash
# Run benchmarks
make bench

# Compare with baseline
make bench-compare

# Generate report
make bench-report
```

**Metrics to Track**:
- Compilation time (should be similar or faster)
- Generated code size (should be smaller)
- Constant folding effectiveness (% of constants folded)
- Simplification effectiveness (% of operations simplified)

**Performance Goals**:
- ≥5% improvement in compilation time for arithmetic-heavy code
- ≥10% reduction in generated code size for arithmetic-heavy code
- No regression in non-arithmetic code

**Acceptance Criteria**:
- Benchmarks show ≥5% improvement
- Performance report complete
- No significant regressions

#### 6.5: Documentation Review (4-6 hours)

**Files to Review/Update**:
- All Haddock documentation for modified modules
- `docs/architecture/ARITHMETIC_OPERATORS.md`
- `CHANGELOG.md`
- `README.md` if applicable

**Actions**:
1. Review all Haddock documentation
   - Ensure complete and accurate
   - Check examples work correctly
   - Verify @since tags correct

2. Update architecture documentation
   - Reflect new implementation
   - Update diagrams and flowcharts
   - Document optimization strategies

3. Update CHANGELOG.md
   - List all changes under v0.19.2
   - Follow conventional commit format
   - Highlight breaking changes (if any)

**Acceptance Criteria**:
- Haddock builds without warnings
- Architecture docs reflect implementation
- CHANGELOG.md complete

### Phase 6 Deliverables

- [ ] All tests passing
- [ ] All regressions fixed or documented
- [ ] Golden files updated and verified
- [ ] Performance benchmarks show ≥5% improvement
- [ ] Documentation complete and accurate

### Phase 6 Milestone

**Success Criteria**: All tests pass, performance goals met, ready for production deployment.

### Phase 6 Risks & Mitigation

**Risk**: Performance goals not met  
**Mitigation**: Analyze bottlenecks, optimize further, adjust goals if needed

**Risk**: Unforeseen regressions discovered late  
**Mitigation**: Thorough testing in earlier phases, maintain test-first approach

**Risk**: Golden file changes too extensive  
**Mitigation**: Review changes incrementally, phase-by-phase

---

## Phase 7: Documentation & Polish (3-4 days)

**Goal**: Complete documentation, prepare release, ensure production readiness.

### Tasks

#### 7.1: Complete User-Facing Documentation (6-8 hours)

**Files to Create/Update**:
- `docs/optimization/ARITHMETIC_OPTIMIZATION.md` (NEW)
- `docs/guides/PERFORMANCE_GUIDE.md` (UPDATE)
- `docs/CHANGELOG.md` (UPDATE)

**Actions**:
1. Write optimization guide
   - Explain what optimizations are performed
   - When they apply
   - How to write code that optimizes well
   - Examples of before/after

2. Update performance guide
   - Add section on arithmetic optimization
   - Explain performance characteristics
   - Provide benchmarking tips

3. Create migration guide (if needed)
   - Document any breaking changes
   - Explain upgrade process
   - List potential issues

**Example Documentation**:
```markdown
# Arithmetic Optimization Guide

## What Gets Optimized

The Canopy compiler now compiles arithmetic operators directly to 
JavaScript operators for better performance:

- `+`, `-`, `*`, `/` compile to `+`, `-`, `*`, `/`
- `//` compiles to `(a / b) | 0` (integer division)
- `^` compiles to `Math.pow(a, b)`
- `%` compiles to `%`

## Constant Folding

Constant expressions are evaluated at compile time:

```elm
-- Before optimization
x = 1 + 2 + 3

-- After optimization
x = 6
```

## Algebraic Simplification

The compiler applies algebraic rules:

- `x + 0` → `x`
- `x * 1` → `x`
- `x * 0` → `0`
- `(1 + x) + 2` → `x + 3`

## Performance Tips

1. Use constants where possible for compile-time evaluation
2. Factor out common sub-expressions
3. Use native operators instead of function versions
```

**Acceptance Criteria**:
- User documentation complete
- Examples tested and working
- Writing clear and accessible

#### 7.2: Update Internal Documentation (4-6 hours)

**Files to Update**:
- All module-level Haddock comments
- `docs/architecture/COMPILER_PIPELINE.md`
- `docs/architecture/OPTIMIZATION_PASSES.md`

**Actions**:
1. Update module documentation
   - Explain new functionality
   - Document design decisions
   - Update diagrams

2. Update architecture docs
   - Reflect new optimization passes
   - Update pipeline diagrams
   - Document integration points

3. Add developer notes
   - Explain implementation choices
   - Document tricky parts
   - Provide debugging tips

**Acceptance Criteria**:
- All internal docs updated
- Architecture diagrams current
- Developer notes helpful

#### 7.3: Prepare Release Notes (4-5 hours)

**Files to Create**:
- `docs/releases/v0.19.2.md` (NEW)
- `CHANGELOG.md` (UPDATE)

**Actions**:
1. Write release notes
   - Summarize all changes
   - Highlight performance improvements
   - List breaking changes (if any)
   - Provide upgrade instructions

2. Update CHANGELOG.md
   - Add v0.19.2 section
   - List all commits with conventional format
   - Link to issues/PRs

3. Create release checklist
   - Pre-release checks
   - Deployment steps
   - Post-release verification

**Release Notes Template**:
```markdown
# Canopy v0.19.2 - Native Arithmetic Operators

## Overview

This release adds native arithmetic operator support to the Canopy compiler,
resulting in significant performance improvements and cleaner generated code.

## Features

### Native Arithmetic Operators

Arithmetic operators now compile directly to JavaScript operators:

```javascript
// Before
F2($elm$core$Basics$add, 1, 2)

// After
1 + 2
```

### Constant Folding

The compiler now evaluates constant expressions at compile time:

```elm
-- This
x = 1 + 2 + 3

-- Becomes
x = 6
```

### Algebraic Simplification

The compiler applies algebraic simplification rules:
- Identity elimination: `x + 0` → `x`
- Absorption: `x * 0` → `0`
- Constant reassociation: `(1 + x) + 2` → `x + 3`

## Performance

- ≥5% faster compilation for arithmetic-heavy code
- ≥10% smaller generated code
- Constant folding reduces runtime computation

## Breaking Changes

None. This is a fully backward-compatible release.

## Upgrade Guide

No changes required. Recompile your code to benefit from optimizations.

## Contributors

- [List contributors]
```

**Acceptance Criteria**:
- Release notes complete
- CHANGELOG.md updated
- Release checklist ready

#### 7.4: Code Review & Polish (6-8 hours)

**Actions**:
1. Self-review all changes
   - Check for CLAUDE.md compliance
   - Verify function sizes ≤15 lines
   - Check complexity ≤4 branches
   - Ensure qualified imports

2. Run static analysis
   - hlint with no warnings
   - fourmolu formatting
   - -Wall compilation with no warnings

3. Address code review feedback
   - Respond to reviewer comments
   - Make requested changes
   - Update tests as needed

4. Final polish
   - Fix typos in comments
   - Improve variable names
   - Refactor unclear code
   - Add missing documentation

**Code Quality Checks**:
```bash
# Format code
make format

# Lint
make lint

# Check warnings
stack build --ghc-options=-Werror

# Generate Haddock
make docs

# Check documentation coverage
make docs-coverage
```

**Acceptance Criteria**:
- All CLAUDE.md standards met
- No lint warnings
- Code formatted consistently
- Documentation complete

### Phase 7 Deliverables

- [ ] Complete user-facing documentation
- [ ] Updated internal documentation
- [ ] Release notes and changelog
- [ ] Code polished and review-ready

### Phase 7 Milestone

**Success Criteria**: Documentation complete, release notes ready, code polished and ready for production deployment.

### Phase 7 Risks & Mitigation

**Risk**: Documentation doesn't match implementation  
**Mitigation**: Test all examples, review docs alongside code

**Risk**: Release notes miss important changes  
**Mitigation**: Review git log systematically, use conventional commits

---

## Development Guide

### Setup Instructions

1. **Clone and build**:
```bash
git clone https://github.com/your-org/canopy.git
cd canopy
git checkout -b feature/native-arithmetic-operators
stack build
```

2. **Run tests to verify baseline**:
```bash
make test
# All tests should pass before starting
```

3. **Set up development tools**:
```bash
# Install hlint
stack install hlint

# Install fourmolu
stack install fourmolu

# Install haskell-language-server (optional)
stack install haskell-language-server
```

### Development Workflow

1. **Work on one phase at a time**
   - Complete all tasks in a phase before moving to next
   - Commit frequently with descriptive messages
   - Tag milestone completions

2. **Run tests continuously**:
```bash
# Run tests for current work
stack test --ta="--pattern Arithmetic"

# Run full test suite periodically
make test

# Check coverage
make test-coverage
```

3. **Commit with conventional format**:
```bash
git commit -m "feat(ast): add native arithmetic operators to Canonical AST"
git commit -m "test(canonicalize): add tests for arithmetic detection"
git commit -m "docs(optimize): document constant folding algorithm"
```

4. **Review before moving to next phase**:
```bash
# Self-review
git diff origin/master

# Check standards compliance
make lint
make format

# Verify tests pass
make test
```

### Common Pitfalls & Solutions

#### Pitfall 1: Function Too Long

**Problem**: Function exceeds 15 lines  
**Solution**: Extract helper functions with meaningful names

```haskell
-- BAD: 25 lines
canonicalize env expr = do
  -- ... 25 lines of logic

-- GOOD: Extract helpers
canonicalize env expr = do
  case expr of
    Arithmetic op left right -> canonicalizeArithmetic op left right
    _ -> canonicalizeOther expr

canonicalizeArithmetic op left right = do
  -- ... focused logic
```

#### Pitfall 2: Too Many Parameters

**Problem**: Function has >4 parameters  
**Solution**: Use record types to group related parameters

```haskell
-- BAD: 5 parameters
optimize mode env cycle name expr = ...

-- GOOD: Use record
data OptConfig = OptConfig
  { _optMode :: Mode
  , _optEnv :: Env
  , _optCycle :: Cycle
  }

optimize config name expr = ...
```

#### Pitfall 3: Import Conflicts

**Problem**: Name collisions between modules  
**Solution**: Use qualified imports consistently

```haskell
-- BAD: Unqualified imports
import AST.Canonical
import AST.Optimized

-- GOOD: Qualified imports
import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
```

#### Pitfall 4: Binary Format Breaking Changes

**Problem**: Changes break .elmi cache compatibility  
**Solution**: Version bump and migration path

```haskell
-- Add version check
readElmiVersion :: Binary.Get Version
readElmiVersion = do
  ver <- Binary.get
  if ver < requiredVersion
    then fail "Old .elmi format, please recompile"
    else return ver
```

### Debugging Strategies

#### Debug Canonicalization

Add trace statements to understand operator detection:

```haskell
import Debug.Trace (trace)

toBinop binop left right =
  let _ = trace ("DEBUG: Operator " ++ show op ++ " detected as " ++ show (isArithmeticOp binop)) ()
  in case isArithmeticOp binop of
       Just OpAdd -> ...
```

#### Debug Code Generation

Inspect generated JavaScript:

```bash
# Compile with debug output
canopy make --debug src/Main.can

# Check generated JS
cat canopy-stuff/build/Main.js
```

#### Debug Test Failures

Use HUnit assertions for detailed output:

```haskell
-- Good: Clear failure message
case canonicalize env expr of
  Right (Can.Add _ _) -> pure ()
  Right other -> assertFailure $ "Expected Add, got: " ++ show other
  Left err -> assertFailure $ "Failed: " ++ show err
```

### Testing During Development

#### Unit Test Workflow

```bash
# Run only tests you're working on
stack test --ta="--pattern Canonicalize.Expression"

# Watch mode for continuous testing
stack test --file-watch --ta="--pattern Arithmetic"

# Run single test
stack test --ta="--pattern 'canonicalize integer addition'"
```

#### Golden File Workflow

```bash
# Generate new golden files
make golden-generate

# Review changes
git diff test/Golden/

# Accept changes if correct
make golden-accept

# Reject and fix if incorrect
git checkout test/Golden/
```

#### Property Test Workflow

```bash
# Run with more examples
stack test --ta="--quickcheck-tests=1000"

# Replay specific failure
stack test --ta="--quickcheck-replay=12345"
```

---

## Risk Mitigation

### Risk Matrix

| Risk | Probability | Impact | Severity | Mitigation |
|------|-------------|--------|----------|------------|
| Binary format incompatibility | Medium | High | High | Version bump, migration tests |
| Performance goals not met | Low | High | Medium | Early benchmarking, optimization iteration |
| Test coverage gaps | Medium | Medium | Medium | Systematic coverage analysis |
| Incorrect optimizations | Low | Critical | High | Extensive property testing |
| Regression in error messages | Low | Medium | Low | Golden file tests for errors |
| Documentation out of sync | Medium | Low | Low | Review docs with code changes |

### Critical Risks

#### Risk: Incorrect Constant Folding

**Description**: Constant evaluation produces wrong results due to overflow, precision, or semantic differences.

**Impact**: Silent data corruption, incorrect program behavior.

**Mitigation**:
1. Extensive property testing with QuickCheck
2. Cross-reference with JavaScript semantics
3. Test against known edge cases (NaN, Infinity, overflow)
4. Document exact semantics in code comments
5. Add runtime assertions in dev mode

**Detection**:
```haskell
-- Property test
prop_constantFoldingCorrect :: Int -> Int -> Bool
prop_constantFoldingCorrect a b =
  let compiled = foldConstants (Opt.Add (Opt.Int a) (Opt.Int b))
      expected = Opt.Int (a + b)
  in compiled == expected
```

#### Risk: Binary Format Breaking Changes

**Description**: Changes to AST serialization break .elmi cache files.

**Impact**: Users must recompile all packages, potential data loss.

**Mitigation**:
1. Version all binary formats
2. Add migration tests
3. Document format changes in CHANGELOG
4. Provide clear error messages for old formats
5. Test with real-world packages

**Detection**:
```bash
# Test with existing .elmi files
canopy make test-package --reuse-cache
# Should fail gracefully with clear error
```

#### Risk: Performance Regression

**Description**: Changes slow down compilation or runtime performance.

**Impact**: User frustration, rollback required.

**Mitigation**:
1. Establish baseline benchmarks (Phase 0)
2. Run benchmarks after each phase
3. Profile any suspected regressions
4. Set acceptable margins (±2%)
5. Test with large real-world codebases

**Detection**:
```bash
# Continuous benchmarking
make bench-compare
# Alert if >2% slower than baseline
```

### Rollback Strategy

Each phase has clear boundaries for safe rollback:

**Phase 1 Rollback**: Revert AST changes
```bash
git revert HEAD~5..HEAD  # Revert Phase 1 commits
stack build  # Should compile
make test  # Should pass
```

**Phase 2 Rollback**: Revert optimization changes
```bash
git revert <phase2-start>..<phase2-end>
# Canonical AST still has new nodes but they're not used
```

**Phase 3 Rollback**: Revert code generation
```bash
git revert <phase3-start>..<phase3-end>
# Falls back to function call generation
```

**Complete Rollback**: Revert entire feature branch
```bash
git checkout master
# All changes undone
```

### Contingency Plans

#### If Performance Goals Not Met

1. Profile to identify bottlenecks
2. Optimize hot paths
3. Consider partial implementation:
   - Only enable for Prod mode
   - Only optimize constant folding
   - Defer algebraic simplification
4. Adjust goals if necessary (document why)

#### If Critical Bug Discovered

1. Immediately create failing test case
2. Determine scope: single phase or multiple
3. Fix or rollback affected phase
4. Add regression prevention tests
5. Document in CHANGELOG

#### If Timeline Slips

1. Assess which phases complete
2. Consider releasing partial implementation
3. Mark incomplete phases as experimental
4. Document known limitations
5. Plan follow-up releases

---

## Appendix: File Modification Checklist

### Phase 1: AST Foundation

- [ ] `packages/canopy-core/src/AST/Canonical.hs`
  - [ ] Add `Add`, `Sub`, `Mul`, `Div`, `IntDiv`, `Pow`, `Mod` constructors
  - [ ] Update `Show` instance
  - [ ] Add Haddock documentation
  - [ ] Update `Binary` instance (put/get)
  
- [ ] `packages/canopy-core/src/Canonicalize/Expression.hs`
  - [ ] Add `isArithmeticOp` function
  - [ ] Update `toBinop` to create native nodes
  - [ ] Modify `canonicalizeBinops` flow
  
- [ ] `test/Unit/AST/CanonicalArithmeticTest.hs` (NEW)
  - [ ] Test constructor creation
  - [ ] Test Show instances
  - [ ] Test Binary serialization
  
- [ ] `test/Unit/Canonicalize/ExpressionArithmeticTest.hs` (UPDATE)
  - [ ] Test arithmetic detection
  - [ ] Test operator resolution
  - [ ] Test mixed operators

### Phase 2: Optimization Integration

- [ ] `packages/canopy-core/src/AST/Optimized.hs`
  - [ ] Add `Add`, `Sub`, `Mul`, `Div`, `IntDiv`, `Pow`, `Mod` constructors
  - [ ] Update `Show` instance
  - [ ] Add Haddock documentation
  - [ ] Update `Binary` instance
  
- [ ] `packages/canopy-core/src/Optimize/Expression.hs`
  - [ ] Add cases for each arithmetic operator
  - [ ] Add `optimizeArithmetic` helper
  - [ ] Preserve cycle detection
  
- [ ] `test/Unit/Optimize/ExpressionArithmeticTest.hs` (NEW)
  - [ ] Test optimization of each operator
  - [ ] Test nested expressions
  - [ ] Test with cycles

### Phase 3: Code Generation

- [ ] `packages/canopy-core/src/Generate/JavaScript/Expression.hs`
  - [ ] Add cases for each operator
  - [ ] Add `generateBinaryOp` helper
  - [ ] Special handling for IntDiv and Pow
  
- [ ] `packages/canopy-core/src/Generate/JavaScript/Builder.hs`
  - [ ] Add `InfixOp` constructor (if needed)
  - [ ] Update `exprToBuilder`
  - [ ] Add parenthesization logic
  
- [ ] `test/Unit/Generate/JavaScript/ExpressionArithmeticTest.hs` (UPDATE)
  - [ ] Test each operator generation
  - [ ] Test nested expressions
  - [ ] Test dev vs. prod mode
  
- [ ] `test/Golden/JavaScriptOutput.hs` (NEW)
  - [ ] Golden files for simple arithmetic
  - [ ] Golden files for complex nested
  - [ ] Golden files for edge cases

### Phase 4: Constant Folding

- [ ] `packages/canopy-core/src/Optimize/Arithmetic.hs` (NEW)
  - [ ] `foldConstants` function
  - [ ] `evalIntBinop` helper
  - [ ] `evalFloatBinop` helper
  - [ ] `evalMixedBinop` helper
  
- [ ] `packages/canopy-core/src/Optimize/Expression.hs` (UPDATE)
  - [ ] Integrate `Arith.foldConstants`
  - [ ] Add to optimization pipeline
  
- [ ] `packages/canopy-core/src/Optimize/Module.hs` (UPDATE)
  - [ ] Add configuration options
  - [ ] Track optimization statistics
  
- [ ] `test/Unit/Optimize/ArithmeticTest.hs` (NEW)
  - [ ] Test Int constant folding
  - [ ] Test Float constant folding
  - [ ] Test mixed types
  - [ ] Test edge cases
  
- [ ] `test/Property/Optimize/ArithmeticProps.hs` (NEW)
  - [ ] Property: folding preserves value
  - [ ] Property: idempotence
  - [ ] Property: commutativity
  
- [ ] `test/Golden/ConstantFolding.hs` (NEW)
  - [ ] Golden files with constants
  - [ ] Golden files with mixed

### Phase 5: Algebraic Simplification

- [ ] `packages/canopy-core/src/Optimize/Arithmetic.hs` (UPDATE)
  - [ ] `simplifyArithmetic` function
  - [ ] `simplifyAddZero` helper
  - [ ] `simplifyMulOne` helper
  - [ ] `simplifyAbsorption` function
  - [ ] `reassociateConstants` function
  
- [ ] `test/Unit/Optimize/ArithmeticSimplificationTest.hs` (NEW)
  - [ ] Test identity elimination
  - [ ] Test absorption
  - [ ] Test reassociation
  
- [ ] `test/Property/Optimize/AlgebraProps.hs` (NEW)
  - [ ] Property: simplification preserves value
  - [ ] Property: idempotence

### Phase 6: Integration & Testing

- [ ] All test files (run and fix)
- [ ] All golden files (review and update)
- [ ] `bench/ArithmeticBench.hs` (run benchmarks)
- [ ] `bench/RESULTS.md` (NEW - document results)

### Phase 7: Documentation & Polish

- [ ] `docs/optimization/ARITHMETIC_OPTIMIZATION.md` (NEW)
- [ ] `docs/guides/PERFORMANCE_GUIDE.md` (UPDATE)
- [ ] `docs/architecture/ARITHMETIC_OPERATORS.md` (UPDATE)
- [ ] `docs/architecture/COMPILER_PIPELINE.md` (UPDATE)
- [ ] `docs/releases/v0.19.2.md` (NEW)
- [ ] `CHANGELOG.md` (UPDATE)
- [ ] All module Haddock comments (review and update)

---

## Summary

This roadmap provides a detailed, phased approach to implementing native arithmetic operators in the Canopy compiler. Each phase builds incrementally on the previous, with clear milestones and acceptance criteria. The total estimated time is 29-44 days, with comprehensive testing and documentation throughout.

**Key Success Factors**:
1. Test-first development approach
2. Incremental implementation with phase boundaries
3. Comprehensive testing at each stage
4. Continuous benchmarking and performance validation
5. Adherence to CLAUDE.md coding standards
6. Thorough documentation at all levels

**Next Steps**:
1. Review and approve this roadmap
2. Set up development environment
3. Begin Phase 0: Preparation
4. Establish team communication and review processes
5. Track progress against milestones

