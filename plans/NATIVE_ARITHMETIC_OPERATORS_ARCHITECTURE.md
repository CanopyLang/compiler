# Native Arithmetic Operators Architecture Design

**Version:** 1.0  
**Date:** 2025-10-28  
**Status:** Draft - Design Phase  
**Author:** ARCHITECT Agent

---

## Executive Summary

This document defines the architectural design for adding native arithmetic operator support to the Canopy compiler. The design introduces first-class operator nodes in the AST while maintaining full backwards compatibility with the existing function-based operator system.

### Key Design Goals

1. **Performance**: Native operators compile to direct JavaScript arithmetic operations
2. **Type Safety**: Preserve type inference and checking for operators
3. **Backwards Compatibility**: Existing code continues to work without changes
4. **Clean Architecture**: Clear separation between operators and function calls
5. **Maintainability**: Follow CLAUDE.md standards (≤15 lines, ≤4 params, comprehensive docs)

---

## Current Architecture Analysis

### Source AST (AST/Source.hs)

**Current State:**
```haskell
data Expr_
  = ...
  | Binops [(Expr, A.Located Name)] Expr  -- Generic operator chain
  | ...
```

**Issues:**
- Operators treated identically to user-defined functions
- No distinction between arithmetic operators and custom operators
- Precedence resolution happens during canonicalization
- All operators become function calls in optimized AST

### Canonical AST (AST/Canonical.hs)

**Current State:**
```haskell
data Expr_
  = ...
  | Binop Name ModuleName.Canonical Name Annotation Expr Expr
  | VarOperator Name ModuleName.Canonical Name Annotation
  | ...
```

**Issues:**
- Binop already exists but treats all operators as function references
- Carries annotation for type inference
- No optimization hints for native operators

### Optimized AST (AST/Optimized.hs)

**Current State:**
```haskell
-- Binops become function calls
Can.Binop _ home name _ left right ->
  do
    optFunc <- Names.registerGlobal home name
    optLeft <- optimize cycle left
    optRight <- optimize cycle right
    return (Opt.Call optFunc [optLeft, optRight])
```

**Issues:**
- All operators compile to function calls
- No direct JavaScript operator generation
- Performance overhead from function dispatch

---

## Proposed Architecture

### Phase 1: AST Extensions

#### 1.1 Source AST Enhancement

**File:** `packages/canopy-core/src/AST/Source.hs`

**Addition:**
```haskell
-- | Native arithmetic operator classification.
--
-- Identifies operators that should compile to native JavaScript
-- arithmetic operations for optimal performance.
--
-- @since 0.19.2
data ArithOp
  = -- | Addition operator (+)
    --
    -- Compiles to JavaScript '+' operator
    Add
  | -- | Subtraction operator (-)
    --
    -- Compiles to JavaScript '-' operator
    Sub
  | -- | Multiplication operator (*)
    --
    -- Compiles to JavaScript '*' operator
    Mul
  | -- | Division operator (/)
    --
    -- Compiles to JavaScript '/' operator
    Div
  | -- | Integer division operator (//)
    --
    -- Compiles to JavaScript Math.floor(a / b)
    IntDiv
  | -- | Modulo operator (%)
    --
    -- Compiles to JavaScript '%' operator (with correction)
    Mod
  | -- | Exponentiation operator (^)
    --
    -- Compiles to JavaScript '**' operator or Math.pow
    Pow
  deriving (Eq, Show)
```

**Modification to Expr_:**
```haskell
data Expr_
  = ...
  | Binops [(Expr, A.Located Name)] Expr
  -- ^ Generic operator chain (unchanged for backwards compatibility)
  | ArithBinop ArithOp Expr Expr
  -- ^ Native arithmetic binary operation (NEW)
  | ...
```

**Design Rationale:**
- Keep existing `Binops` constructor for user-defined operators
- Add new `ArithBinop` constructor for recognized arithmetic operators
- Parser can decide which constructor to use based on operator name
- No breaking changes to existing code

#### 1.2 Canonical AST Enhancement

**File:** `packages/canopy-core/src/AST/Canonical.hs`

**Addition:**
```haskell
-- | Native arithmetic operator in canonical form.
--
-- Represents arithmetic operators after canonicalization with
-- type information attached for inference and optimization.
--
-- @since 0.19.2
data ArithOp
  = Add | Sub | Mul | Div | IntDiv | Mod | Pow
  deriving (Eq, Show)

instance Binary ArithOp where
  put op = putWord8 (case op of
    Add -> 0; Sub -> 1; Mul -> 2; Div -> 3
    IntDiv -> 4; Mod -> 5; Pow -> 6)
  get = do
    word <- getWord8
    case word of
      0 -> return Add; 1 -> return Sub; 2 -> return Mul
      3 -> return Div; 4 -> return IntDiv; 5 -> return Mod
      6 -> return Pow
      _ -> fail "binary encoding of ArithOp corrupted"
```

**Modification to Expr_:**
```haskell
data Expr_
  = ...
  | Binop Name ModuleName.Canonical Name Annotation Expr Expr
  -- ^ Generic operator (unchanged)
  | ArithBinop ArithOp Annotation Expr Expr
  -- ^ Native arithmetic operation (NEW)
  | ...
```

**Design Rationale:**
- Mirror Source AST structure for consistency
- Attach Annotation for type inference
- Separate type for clean optimization passes
- Binary instance for efficient module caching

#### 1.3 Optimized AST Enhancement

**File:** `packages/canopy-core/src/AST/Optimized.hs`

**Addition:**
```haskell
-- | Native arithmetic operator in optimized form.
--
-- Represents arithmetic operators ready for direct code generation
-- to native JavaScript arithmetic operations.
--
-- @since 0.19.2
data ArithOp
  = Add | Sub | Mul | Div | IntDiv | Mod | Pow
  deriving (Eq, Show)

instance Binary ArithOp where
  put op = putWord8 (case op of
    Add -> 0; Sub -> 1; Mul -> 2; Div -> 3
    IntDiv -> 4; Mod -> 5; Pow -> 6)
  get = do
    word <- getWord8
    case word of
      0 -> return Add; 1 -> return Sub; 2 -> return Mul
      3 -> return Div; 4 -> return IntDiv; 5 -> return Mod
      6 -> return Pow
      _ -> fail "binary encoding of ArithOp corrupted"
```

**Modification to Expr:**
```haskell
data Expr
  = ...
  | ArithBinop ArithOp Expr Expr
  -- ^ Native arithmetic operation ready for codegen (NEW)
  | ...
```

**Design Rationale:**
- Simplest possible representation for code generation
- No annotations needed (type checking already done)
- Direct mapping to JavaScript operators

---

### Phase 2: Transformation Pipeline

#### 2.1 Parser Phase (Parse/Expression.hs)

**Current Flow:**
```
"a + b * c" → Binops [(a, +), (b, *)] c
```

**New Flow:**
```
"a + b * c" → Detect operators
             → Check if arithmetic operators
             → If yes: ArithBinops structure
             → If no: Binops structure (backwards compat)
```

**Implementation Strategy:**
```haskell
-- | Check if operator is a native arithmetic operator.
--
-- Returns Just ArithOp if the operator should compile to native
-- JavaScript arithmetic, Nothing otherwise.
--
-- @since 0.19.2
isArithOp :: Name -> Maybe Src.ArithOp
isArithOp name
  | name == Name.add = Just Src.Add
  | name == Name.sub = Just Src.Sub
  | name == Name.mul = Just Src.Mul
  | name == Name.div = Just Src.Div
  | otherwise = Nothing

-- Additional operators handled similarly
```

**Parser Integration:**
- Minimal changes to existing parser
- Check operator name during Binops construction
- Build ArithBinop tree if all operators are arithmetic
- Fall back to Binops for mixed or custom operators

#### 2.2 Canonicalization Phase (Canonicalize/Expression.hs)

**Current Flow:**
```haskell
Src.Binops ops final →
  lookup operators in environment →
  resolve precedence →
  Can.Binop (function call)
```

**New Flow:**
```haskell
Src.ArithBinop op left right →
  canonicalize operands →
  verify numeric types →
  Can.ArithBinop op annotation left right

Src.Binops ops final →
  (unchanged - backwards compatibility)
```

**Implementation Strategy:**
```haskell
-- | Canonicalize arithmetic binary operation.
--
-- Validates operand types and preserves native operator structure
-- for optimization phases.
--
-- @since 0.19.2
canonicalizeArithBinop
  :: Env.Env
  -> A.Region
  -> Src.ArithOp
  -> Src.Expr
  -> Src.Expr
  -> Result FreeLocals [W.Warning] Can.Expr_
canonicalizeArithBinop env region op left right =
  buildArithNode op
    <$> canonicalize env left
    <*> canonicalize env right
  where
    buildArithNode = Can.ArithBinop op inferredAnnotation
    inferredAnnotation = -- Type inference integration
```

**Type Inference Integration:**
- Arithmetic operators have well-known type signatures
- `(+)`, `(-)`, `(*)` : `number -> number -> number`
- `(/)` : `Float -> Float -> Float`
- `(//)` : `Int -> Int -> Int`
- Type variables unified during inference

#### 2.3 Optimization Phase (Optimize/Expression.hs)

**Current Flow:**
```haskell
Can.Binop _ home name _ left right →
  Names.registerGlobal home name (function lookup)
  Opt.Call optFunc [optLeft, optRight]
```

**New Flow:**
```haskell
Can.ArithBinop op _ left right →
  optimize left and right →
  Opt.ArithBinop op optLeft optRight (direct operator)
```

**Implementation Strategy:**
```haskell
-- | Optimize arithmetic binary operation.
--
-- Preserves native operator structure and applies constant folding
-- optimizations when both operands are literals.
--
-- @since 0.19.2
optimizeArithBinop
  :: Cycle
  -> Can.ArithOp
  -> Can.Expr
  -> Can.Expr
  -> Names.Tracker Opt.Expr
optimizeArithBinop cycle op left right = do
  optLeft <- optimize cycle left
  optRight <- optimize cycle right
  return (applyConstFold op optLeft optRight)

-- | Apply constant folding to arithmetic operations.
--
-- Evaluates arithmetic operations at compile time when both
-- operands are known constants.
--
-- @since 0.19.2
applyConstFold
  :: Can.ArithOp
  -> Opt.Expr
  -> Opt.Expr
  -> Opt.Expr
applyConstFold op left right =
  case (op, left, right) of
    (Can.Add, Opt.Int a, Opt.Int b) -> Opt.Int (a + b)
    (Can.Mul, Opt.Int a, Opt.Int b) -> Opt.Int (a * b)
    _ -> Opt.ArithBinop (toOptArithOp op) left right
```

**Optimization Opportunities:**
- Constant folding for literal operands
- Strength reduction (e.g., `x * 2` → `x + x`)
- Associativity reordering for better constant folding
- Identity elimination (`x + 0` → `x`, `x * 1` → `x`)

#### 2.4 Code Generation Phase (Generate/JavaScript/Expression.hs)

**Current Flow:**
```haskell
Opt.Call func args →
  generate function reference →
  generate arguments →
  JS function call syntax
```

**New Flow:**
```haskell
Opt.ArithBinop op left right →
  generate left operand →
  generate operator symbol →
  generate right operand →
  JS infix operator syntax
```

**Implementation Strategy:**
```haskell
-- | Generate JavaScript code for arithmetic operations.
--
-- Produces direct JavaScript arithmetic operators for optimal
-- runtime performance with proper operator precedence.
--
-- @since 0.19.2
generateArithBinop
  :: Mode
  -> Opt.ArithOp
  -> Opt.Expr
  -> Opt.Expr
  -> State Int JS.Expr
generateArithBinop mode op left right = do
  jsLeft <- generate mode left
  jsRight <- generate mode right
  return (toJSBinop op jsLeft jsRight)

-- | Convert arithmetic operator to JavaScript operator.
--
-- Maps Canopy arithmetic operators to their JavaScript equivalents
-- with special handling for integer division and modulo.
--
-- @since 0.19.2
toJSBinop :: Opt.ArithOp -> JS.Expr -> JS.Expr -> JS.Expr
toJSBinop op left right =
  case op of
    Opt.Add -> JS.InfixOp "+" left right
    Opt.Sub -> JS.InfixOp "-" left right
    Opt.Mul -> JS.InfixOp "*" left right
    Opt.Div -> JS.InfixOp "/" left right
    Opt.IntDiv -> jsIntDiv left right
    Opt.Mod -> jsModulo left right
    Opt.Pow -> jsPower left right

-- Special cases requiring function calls
jsIntDiv l r = JS.Call (JS.Field (JS.Ref "Math") "floor")
                       [JS.InfixOp "/" l r]
```

---

### Phase 3: Precedence and Associativity

#### 3.1 Operator Table

**File:** `packages/canopy-core/src/AST/Utils/Binop.hs` (No changes needed)

**Existing Precedence Levels:**
```haskell
-- From highest to lowest precedence:
-- 9 - Function application
-- 8 - Exponentiation (^)
-- 7 - Multiplication (*), Division (/), Modulo (%), IntDiv (//)
-- 6 - Addition (+), Subtraction (-)
-- 5 - List cons (::)
-- 4 - Comparison (<, >, <=, >=)
-- 3 - Equality (==, /=)
-- 2 - Logical AND (&&)
-- 1 - Logical OR (||)
-- 0 - Pipeline (|>, <|)
```

**Associativity:**
- Addition, Subtraction: Left
- Multiplication, Division, Modulo: Left
- Exponentiation: Right
- All arithmetic operators: Standard mathematical associativity

#### 3.2 Parser Integration

**Precedence Resolution Strategy:**

1. **During Parsing:**
   - Build flat operator chain: `[(expr, op)]`
   - Detect if all operators are arithmetic
   - If yes, create ArithBinop structure
   - If no, create Binops structure

2. **During Canonicalization:**
   - Resolve precedence using existing algorithm
   - Build nested expression tree
   - ArithBinop remains as ArithBinop
   - Binops resolves to Binop (function call)

3. **Backwards Compatibility:**
   - User-defined operators follow existing path
   - Mixed chains (arithmetic + custom) fall back to Binops
   - No changes to user code required

---

### Phase 4: Type System Integration

#### 4.1 Type Inference

**Arithmetic Operator Type Signatures:**

```haskell
-- Standard numeric operators
(+) : number -> number -> number
(-) : number -> number -> number
(*) : number -> number -> number

-- Division operators
(/)  : Float -> Float -> Float
(//) : Int -> Int -> Int

-- Modulo and power
(%)  : Int -> Int -> Int
(^)  : number -> number -> number
```

**Type Variable `number`:**
- Constrained type variable
- Unifies with Int or Float
- Generates constraint: `number ~ Int | Float`
- Resolved during type checking

#### 4.2 Type Checking Strategy

**File:** `packages/canopy-core/src/Type/Constrain.hs`

**Implementation:**
```haskell
-- | Generate type constraints for arithmetic operations.
--
-- Arithmetic operators require both operands to have numeric types
-- and produce a result of the same type.
--
-- @since 0.19.2
constrainArithBinop
  :: A.Region
  -> Can.ArithOp
  -> Can.Expr
  -> Can.Expr
  -> Expected Type.Type
  -> Constrain.Constraint
constrainArithBinop region op left right expected =
  let
    operandType = typeForArithOp op
    leftConstraint = constrain left (CExpected operandType)
    rightConstraint = constrain right (CExpected operandType)
    resultConstraint = unifyExpected expected operandType
  in
    CAnd [leftConstraint, rightConstraint, resultConstraint]
```

#### 4.3 Error Reporting

**Enhanced Error Messages:**

```
-- Type Mismatch
"The (+) operator expects numeric types, but I found:

    3 + "hello"
        ^^^^^^^
        This is a String

The (+) operator works with Int and Float values only."

-- Operator Type Conflict
"I'm having trouble with this arithmetic operation:

    x / y

The (/) operator requires Float operands, but:
- x has type: Int
- y has type: Int

Hint: Use (//) for integer division, or convert to Float first."
```

---

### Phase 5: Backwards Compatibility Strategy

#### 5.1 Compatibility Matrix

| Scenario | Current Behavior | New Behavior | Compatible? |
|----------|------------------|--------------|-------------|
| `a + b` with numeric args | Function call to `Basics.(+)` | Native JS `+` operator | ✅ Yes (faster) |
| Custom `(+)` operator | Function call to custom impl | Function call (unchanged) | ✅ Yes |
| Operator in operator position `(+)` | Function reference | Function reference or native | ✅ Yes |
| Mixed operators `a + b |> c` | Function calls | Native + then function | ✅ Yes |
| Imported operators | Module lookup | Module lookup | ✅ Yes |

#### 5.2 Migration Path

**Zero-Breaking-Change Approach:**

1. **Phase 1: Detection Only**
   - Parse recognizes arithmetic operators
   - Still canonicalizes to function calls
   - Measure performance baseline

2. **Phase 2: Opt-In Native**
   - Flag: `--native-arithmetic`
   - Enables ArithBinop transformation
   - Test extensively

3. **Phase 3: Gradual Rollout**
   - Default ON for new code
   - Existing code unchanged
   - Module-level opt-in

4. **Phase 4: Full Migration**
   - All code uses native operators
   - Remove compatibility shims
   - Document breaking changes (if any)

#### 5.3 Compatibility Testing

**Test Categories:**

1. **Unit Tests:**
   - Arithmetic with literals
   - Arithmetic with variables
   - Mixed types (Int/Float)
   - Operator precedence
   - Operator associativity

2. **Integration Tests:**
   - Existing codebases
   - Custom operator definitions
   - FFI interaction
   - Type inference

3. **Performance Tests:**
   - Benchmark arithmetic-heavy code
   - Compare function call vs native
   - Measure compilation time impact

4. **Regression Tests:**
   - All existing tests must pass
   - No semantic changes
   - Identical output for non-arithmetic operators

---

## Implementation Roadmap

### Milestone 1: Foundation (Week 1-2)

**Deliverables:**
- [ ] ArithOp data type in all AST modules
- [ ] Binary instances for serialization
- [ ] Unit tests for AST construction
- [ ] Documentation updates

**Files Modified:**
- `AST/Source.hs` - Add ArithOp and ArithBinop constructor
- `AST/Canonical.hs` - Add ArithOp and ArithBinop constructor
- `AST/Optimized.hs` - Add ArithOp and ArithBinop constructor

### Milestone 2: Parser Integration (Week 3)

**Deliverables:**
- [ ] Parser recognizes arithmetic operators
- [ ] Detection function: `isArithOp :: Name -> Maybe ArithOp`
- [ ] Parser tests for arithmetic expressions
- [ ] Precedence resolution tests

**Files Modified:**
- `Parse/Expression.hs` - Add arithmetic operator detection
- `test/Unit/Parse/ExpressionTest.hs` - Add tests

### Milestone 3: Canonicalization (Week 4)

**Deliverables:**
- [ ] Canonicalization for ArithBinop
- [ ] Type inference integration
- [ ] Error message improvements
- [ ] Canonicalization tests

**Files Modified:**
- `Canonicalize/Expression.hs` - Add canonicalizeArithBinop
- `Type/Constrain.hs` - Add constrainArithBinop
- `Reporting/Error/Canonicalize.hs` - Enhanced errors
- `test/Unit/Canonicalize/ExpressionTest.hs` - Add tests

### Milestone 4: Optimization (Week 5)

**Deliverables:**
- [ ] Optimization pass for ArithBinop
- [ ] Constant folding implementation
- [ ] Optimization tests
- [ ] Performance benchmarks

**Files Modified:**
- `Optimize/Expression.hs` - Add optimizeArithBinop
- `test/Unit/Optimize/ExpressionTest.hs` - Add tests
- `test/Benchmark/ArithmeticBench.hs` - New file

### Milestone 5: Code Generation (Week 6)

**Deliverables:**
- [ ] JavaScript code generation
- [ ] Special case handling (intDiv, modulo)
- [ ] Code generation tests
- [ ] Integration tests

**Files Modified:**
- `Generate/JavaScript/Expression.hs` - Add generateArithBinop
- `test/Integration/ArithmeticCodeGenTest.hs` - New file
- `test/Golden/arithmetic/` - Golden test files

### Milestone 6: Polish and Release (Week 7-8)

**Deliverables:**
- [ ] Full test suite passing
- [ ] Performance validation
- [ ] Documentation complete
- [ ] Migration guide
- [ ] Release notes

**Files Modified:**
- `CHANGELOG.md` - Version 0.19.2 notes
- `docs/NATIVE_ARITHMETIC_OPERATORS.md` - User guide
- `docs/MIGRATION_GUIDE.md` - Migration instructions

---

## Risk Assessment

### High Risk

**Risk:** Breaking existing code with custom `(+)` operators  
**Mitigation:** 
- Test extensively with custom operators
- Maintain Binops path for non-arithmetic operators
- Provide clear migration path

**Risk:** Type system changes affect inference  
**Mitigation:**
- Extensive type inference tests
- Maintain existing type signatures
- Add regression tests

### Medium Risk

**Risk:** Performance regression in non-arithmetic code  
**Mitigation:**
- Benchmark all code paths
- Profile compilation time
- Optimize hot paths

**Risk:** Code generation edge cases  
**Mitigation:**
- Comprehensive integration tests
- Golden file tests
- Manual JavaScript inspection

### Low Risk

**Risk:** Documentation gaps  
**Mitigation:**
- Complete Haddock documentation
- User-facing guides
- Internal architecture docs

---

## Code Quality Standards

### CLAUDE.md Compliance

All implementation must follow CLAUDE.md standards:

1. **Function Size:** ≤ 15 lines per function
2. **Parameters:** ≤ 4 parameters per function
3. **Branching:** ≤ 4 branching points
4. **Documentation:** Complete Haddock docs for all public APIs
5. **Testing:** ≥ 80% code coverage
6. **Style:** Qualified imports, lens usage, no duplication

### Example: Compliant Implementation

```haskell
-- | Canonicalize arithmetic binary operation.
--
-- Transforms source-level arithmetic operations into canonical form
-- with type annotations for inference.
--
-- ==== Examples
--
-- >>> canonicalizeArithBinop env region Add leftExpr rightExpr
-- Right (Can.ArithBinop Add annotation canonLeft canonRight)
--
-- @since 0.19.2
canonicalizeArithBinop
  :: Env.Env
  -> A.Region
  -> Src.ArithOp
  -> Src.Expr
  -> Src.Expr
  -> Result FreeLocals [W.Warning] Can.Expr_
canonicalizeArithBinop env region op left right =
  buildCanonical op
    <$> canonicalize env left
    <*> canonicalize env right
  where
    buildCanonical = buildArithNode (inferOpType op)
    buildArithNode tipe = Can.ArithBinop op (annotate tipe)
```

---

## Performance Targets

### Compilation Performance

- **Parser:** < 5% slowdown (operator detection)
- **Canonicalization:** < 3% slowdown (type checking)
- **Optimization:** +10% speedup (constant folding)
- **Code Generation:** +5% speedup (simpler AST)

### Runtime Performance

- **Arithmetic-Heavy Code:** 20-40% faster
- **Mixed Code:** 5-10% faster
- **Non-Arithmetic Code:** No change

### Memory Usage

- **AST Size:** < 2% increase (new constructors)
- **Compilation Memory:** < 5% increase
- **Runtime Memory:** No change

---

## Success Criteria

### Functional Requirements

✅ **Must Have:**
- All arithmetic operators compile to native JavaScript
- Existing code compiles without changes
- Type inference works correctly
- All existing tests pass

✅ **Should Have:**
- Constant folding optimization
- Enhanced error messages
- Performance improvements measurable

✅ **Nice to Have:**
- Strength reduction optimizations
- Associativity reordering
- Dead code elimination for constant expressions

### Non-Functional Requirements

✅ **Performance:**
- 20%+ improvement in arithmetic-heavy benchmarks
- No regression in existing benchmarks
- Compilation time increase < 5%

✅ **Maintainability:**
- Clean separation of concerns
- Comprehensive documentation
- High test coverage (≥ 80%)

✅ **Compatibility:**
- Zero breaking changes
- Clear migration path
- Backwards compatibility maintained

---

## Appendix A: File Structure

```
packages/canopy-core/src/
├── AST/
│   ├── Source.hs           [Modified: Add ArithOp, ArithBinop]
│   ├── Canonical.hs        [Modified: Add ArithOp, ArithBinop]
│   ├── Optimized.hs        [Modified: Add ArithOp, ArithBinop]
│   └── Utils/
│       └── Binop.hs        [Unchanged: Precedence/Associativity]
├── Parse/
│   └── Expression.hs       [Modified: Add arithmetic detection]
├── Canonicalize/
│   └── Expression.hs       [Modified: Add ArithBinop canonicalization]
├── Type/
│   ├── Constrain.hs        [Modified: Add ArithBinop constraints]
│   └── Solve.hs           [Modified: Numeric type handling]
├── Optimize/
│   └── Expression.hs       [Modified: Add ArithBinop optimization]
└── Generate/
    └── JavaScript/
        └── Expression.hs   [Modified: Add ArithBinop codegen]

test/
├── Unit/
│   ├── Parse/
│   │   └── ExpressionTest.hs       [New: Arithmetic parsing tests]
│   ├── Canonicalize/
│   │   └── ExpressionTest.hs       [New: Arithmetic canon tests]
│   ├── Optimize/
│   │   └── ExpressionTest.hs       [New: Arithmetic opt tests]
│   └── Generate/
│       └── JavaScriptTest.hs       [New: Arithmetic codegen tests]
├── Integration/
│   └── ArithmeticTest.hs           [New: End-to-end tests]
├── Golden/
│   └── arithmetic/                 [New: Golden test files]
└── Benchmark/
    └── ArithmeticBench.hs          [New: Performance benchmarks]

docs/
├── NATIVE_ARITHMETIC_OPERATORS.md  [New: User guide]
└── MIGRATION_GUIDE.md              [New: Migration instructions]
```

---

## Appendix B: Type System Details

### Type Variable Resolution

**Numeric Type Variable:**
```haskell
-- During constraint generation:
constrainArithOp :: Can.ArithOp -> Can.Expr -> Can.Expr -> Constraint
constrainArithOp op left right =
  let numberVar = freshTypeVar "number"
      leftCon = constrain left (Expected numberVar)
      rightCon = constrain right (Expected numberVar)
      numericCon = CNumeric numberVar [TInt, TFloat]
  in CAnd [leftCon, rightCon, numericCon]

-- During solving:
solveNumeric :: Type -> [Type] -> Solve ()
solveNumeric var candidates =
  case candidates of
    [TInt] -> unify var TInt
    [TFloat] -> unify var TFloat
    _ -> throwError (AmbiguousNumericType var)
```

### Division Operator Specialization

**Type-Driven Code Generation:**
```haskell
-- (/) always produces Float
(/) : Float -> Float -> Float

-- (//) always produces Int
(//) : Int -> Int -> Int

-- During code generation:
generateDivision :: Can.Expr -> Opt.Expr
generateDivision (Can.ArithBinop Div left right) =
  -- Operands known to be Float from type checking
  Opt.ArithBinop Div (optimize left) (optimize right)

generateDivision (Can.ArithBinop IntDiv left right) =
  -- Operands known to be Int from type checking
  Opt.ArithBinop IntDiv (optimize left) (optimize right)
```

---

## Appendix C: Optimization Opportunities

### Constant Folding Examples

```haskell
-- Integer constant folding
3 + 5           →  8
10 * 2          →  20
15 - 7          →  8

-- Float constant folding
3.14 + 2.86     →  6.0
10.5 / 2.0      →  5.25

-- Mixed folding
(2 + 3) * 4     →  5 * 4  →  20
```

### Strength Reduction Examples

```haskell
-- Multiplication to addition
x * 2           →  x + x
x * 4           →  (x + x) + (x + x)

-- Division to shift (for powers of 2)
x / 2           →  x >> 1   (if x is Int)
x / 4           →  x >> 2   (if x is Int)

-- Power to multiplication
x ^ 2           →  x * x
x ^ 3           →  x * x * x
```

### Associativity Reordering Examples

```haskell
-- Group constants together
x + 3 + 5       →  x + 8
2 * x * 4       →  8 * x

-- Minimize temporary variables
(x + y) + (3 + 4)  →  (x + y) + 7
```

### Identity Elimination Examples

```haskell
-- Addition identity
x + 0           →  x
0 + x           →  x

-- Multiplication identity
x * 1           →  x
1 * x           →  x

-- Multiplication by zero
x * 0           →  0
0 * x           →  0
```

---

## Appendix D: JavaScript Code Generation

### Basic Operator Mapping

```javascript
// Addition
a + b  →  a + b

// Subtraction
a - b  →  a - b

// Multiplication
a * b  →  a * b

// Division
a / b  →  a / b
```

### Special Cases

```javascript
// Integer division
a // b  →  Math.floor(a / b)

// Modulo (corrected for negative numbers)
a % b  →  ((a % b) + b) % b

// Exponentiation (ES6+)
a ^ b  →  a ** b
// OR (ES5 fallback)
a ^ b  →  Math.pow(a, b)
```

### Parenthesization Rules

```javascript
// Preserve precedence
a + b * c  →  a + (b * c)

// Preserve associativity
a - b - c  →  (a - b) - c  // Left associative
a ^ b ^ c  →  a ** (b ** c)  // Right associative
```

### Generated Code Examples

```javascript
// Simple arithmetic
// Canopy: square x = x * x
function square(x) {
  return x * x;
}

// Compound expression
// Canopy: formula a b = (a + b) * (a - b)
function formula(a, b) {
  return (a + b) * (a - b);
}

// With constants
// Canopy: scale x = x * 2 + 10
function scale(x) {
  return x * 2 + 10;
}

// Integer division
// Canopy: halfFloor x = x // 2
function halfFloor(x) {
  return Math.floor(x / 2);
}
```

---

## Conclusion

This architecture provides a clean, maintainable, and performant path to native arithmetic operator support in Canopy. The design:

1. **Maintains Backwards Compatibility:** Existing code continues to work
2. **Follows Best Practices:** Adheres to CLAUDE.md standards
3. **Enables Performance:** Direct JavaScript operator generation
4. **Supports Future Growth:** Clean architecture for additional optimizations

The phased implementation approach allows for careful validation at each stage, ensuring high quality and minimal risk.

**Next Steps:**
1. Review and approve architecture design
2. Begin implementation with Milestone 1 (Foundation)
3. Iterate based on feedback and testing results

---

**Document Version History:**

- v1.0 (2025-10-28): Initial architecture design by ARCHITECT agent
