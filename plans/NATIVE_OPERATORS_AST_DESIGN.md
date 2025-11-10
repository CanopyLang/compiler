# Native Arithmetic Operators - AST Architecture Design

**Version:** 2.0  
**Date:** 2025-10-28  
**Status:** Architecture Design  
**Author:** ARCHITECT Agent

---

## Executive Summary

This document provides a comprehensive architectural design for native arithmetic operator support in the Canopy compiler AST. The design enables arithmetic operators (`+`, `-`, `*`, `/`) to compile directly to JavaScript operators instead of function calls through `Basics` module indirection, significantly improving performance while maintaining type safety and backwards compatibility.

### Design Principles

1. **Zero Runtime Overhead**: Native operators map directly to JS operators (`+`, `-`, `*`, `/`)
2. **Type Safety First**: Full integration with type inference and constraint solving
3. **Backwards Compatibility**: Existing code works unchanged; user-defined operators unaffected
4. **Clean Separation**: Clear distinction between native operators and function calls
5. **CLAUDE.md Compliance**: All functions ≤15 lines, ≤4 parameters, comprehensive Haddock docs

### Performance Impact

**Current:**
```javascript
// 1 + 2 compiles to:
A2($elm$core$Basics$add, 1, 2)  // Function call overhead
```

**After Implementation:**
```javascript
// 1 + 2 compiles to:
(1 + 2)  // Direct JavaScript operator
```

---

## Current Architecture Analysis

### Expression Flow Through Pipeline

```
Source AST (parsing)
    ↓
    | Binops [(Expr, Located Name)] Expr
    ↓
Canonical AST (name resolution + type inference)
    ↓
    | Binop Name ModuleName.Canonical Name Annotation Expr Expr
    ↓
Optimized AST (optimization + code gen prep)
    ↓
    | Call (VarGlobal (Global ModuleName.basics "add")) [left, right]
    ↓
JavaScript Generation
    ↓
    | A2($elm$core$Basics$add, left, right)
```

### Current Implementation Analysis

#### Source AST (`AST/Source.hs`)
```haskell
data Expr_
  = Binops [(Expr, A.Located Name)] Expr  -- All operators (user + native)
  | Negate Expr                            -- Special case for unary minus
```

**Characteristics:**
- No operator classification at parse time
- All operators handled uniformly
- Precedence resolution deferred to canonicalization

#### Canonical AST (`AST/Canonical.hs`)
```haskell
data Expr_
  = Binop Name ModuleName.Canonical Name Annotation Expr Expr
  | VarOperator Name ModuleName.Canonical Name Annotation
  | Negate Expr
```

**Characteristics:**
- `Binop` carries full type annotation for inference
- Caches operator name and home module (CACHE for optimization)
- `Annotation` contains `Forall FreeVars Type` for constraint solving
- `Negate` handled separately (becomes `Basics.negate` call)

#### Optimized AST (`AST/Optimized.hs`)
```haskell
-- In Optimize/Expression.hs:
Can.Binop _ home name _ left right ->
  do
    optFunc <- Names.registerGlobal home name
    optLeft <- optimize cycle left
    optRight <- optimize cycle right
    return (Opt.Call optFunc [optLeft, optRight])
```

**Current Code Generation:**
```haskell
-- In Generate/JavaScript/Expression.hs:
Opt.Call func args ->
  JsExpr $ generateCall mode func args
  -- Becomes: A2($elm$core$Basics$add, left, right)
```

---

## Proposed Architecture

### Design Choice: Option B - Unified BinopOp Constructor

After analyzing all three approaches, **Option B** provides the optimal balance:

**Selected Approach:**
```haskell
-- Canonical AST
data Expr_
  = BinopOp BinopKind Annotation Expr Expr  -- NEW: Replaces Binop
  | VarOperator Name ModuleName.Canonical Name Annotation
  | Negate Expr

data BinopKind
  = NativeArith ArithOp      -- Native arithmetic: +, -, *, /
  | UserDefined Name ModuleName.Canonical Name  -- User operators: |>, <|, etc.

data ArithOp
  = Add   -- (+)
  | Sub   -- (-)
  | Mul   -- (*)
  | Div   -- (/)
```

#### Why Option B Wins

**Type Safety:**
- Strong typing prevents mixing native and user operators
- Compiler catches operator kind mismatches at compile time
- Pattern matching is exhaustive by construction

**Code Clarity:**
- Single `BinopOp` constructor makes all binops uniform
- `BinopKind` provides clear semantic distinction
- Easy to extend with new operator classes (e.g., `NativeComparison`, `NativeBitwise`)

**Backwards Compatibility:**
- User-defined operators unchanged in `UserDefined` variant
- Existing canonicalization logic adapts cleanly
- Migration path is straightforward

**Performance:**
- Pattern matching on `BinopKind` is efficient
- No extra indirection in hot paths
- Code generation can optimize per-kind

**Maintainability:**
- Functions stay under 15 lines (pattern match 2 cases)
- Clear separation of concerns
- Easy to add new operator categories

#### Rejected Alternatives

**Option A (Separate Constructors):**
```haskell
data Expr_
  = Add Expr Expr
  | Sub Expr Expr
  | Mul Expr Expr
  | Div Expr Expr
  | Binop Name ModuleName.Canonical Name Annotation Expr Expr
```

**Why Rejected:**
- Violates DRY principle (4 identical constructors)
- Pattern matching becomes verbose (4 nearly identical cases)
- Hard to extend (need new constructor for each operator)
- Annotation handling duplicated 4+ times

**Option C (Flag-Based):**
```haskell
data Expr_
  = Binop BinopFlags Name ModuleName.Canonical Name Annotation Expr Expr

data BinopFlags = BinopFlags
  { _isNative :: !Bool
  , _opKind :: !OpKind
  }
```

**Why Rejected:**
- Runtime checks instead of compile-time safety
- Boolean flags are error-prone
- Harder to extend (need to update flags for new operators)
- Less clear intent in code

---

## Detailed Design Specification

### Phase 1: AST Data Type Extensions

#### 1.1 Source AST (No Changes)

**File:** `packages/canopy-core/src/AST/Source.hs`

**Rationale:** Source AST remains unchanged because:
- Parser doesn't need to classify operators
- All operators look identical at parse time (`Binops` chain)
- Classification happens during canonicalization with full scope information

#### 1.2 Canonical AST Extensions

**File:** `packages/canopy-core/src/AST/Canonical.hs`

**New Types:**

```haskell
-- | Native arithmetic operator classification.
--
-- Represents arithmetic operators that compile to native JavaScript
-- operations for optimal performance. These operators have special
-- type constraints (number -> number -> number) and generate direct
-- JavaScript operators instead of function calls.
--
-- === Semantics
--
-- * 'Add': JavaScript '+' operator
-- * 'Sub': JavaScript '-' operator  
-- * 'Mul': JavaScript '*' operator
-- * 'Div': JavaScript '/' operator
--
-- === Type Constraints
--
-- All arithmetic operators have the type:
-- @
-- forall number. number -> number -> number
-- @
-- where @number@ is constrained to Int or Float.
--
-- @since 0.19.2
data ArithOp
  = Add   -- ^ Addition: a + b
  | Sub   -- ^ Subtraction: a - b
  | Mul   -- ^ Multiplication: a * b
  | Div   -- ^ Division: a / b (always Float result in Canopy)
  deriving (Eq, Ord, Show)

-- | Binary operator classification.
--
-- Distinguishes between native operators (which compile to JavaScript
-- operators) and user-defined operators (which remain function calls).
-- This classification enables the optimizer and code generator to
-- apply appropriate transformations.
--
-- === Native Operators
--
-- 'NativeArith' operators:
-- * Type: @number -> number -> number@
-- * Codegen: Direct JavaScript operators
-- * Optimization: Constant folding, algebraic simplification
--
-- === User-Defined Operators
--
-- 'UserDefined' operators:
-- * Type: Arbitrary function type from definition
-- * Codegen: Standard function calls
-- * Optimization: Standard function optimizations
--
-- @since 0.19.2
data BinopKind
  = NativeArith !ArithOp
    -- ^ Native arithmetic operators with direct JavaScript codegen
  | UserDefined !Name !ModuleName.Canonical !Name
    -- ^ User-defined operators as function references
  deriving (Eq, Show)
```

**Modified Expr_:**

```haskell
data Expr_
  = VarLocal Name
  | VarTopLevel ModuleName.Canonical Name
  | VarKernel Name Name
  | VarForeign ModuleName.Canonical Name Annotation
  | VarCtor CtorOpts ModuleName.Canonical Name Index.ZeroBased Annotation
  | VarDebug ModuleName.Canonical Name Annotation
  | VarOperator Name ModuleName.Canonical Name Annotation
  | Chr ES.String
  | Str ES.String
  | Int Int
  | Float EF.Float
  | List [Expr]
  | Negate Expr
  | BinopOp BinopKind Annotation Expr Expr  -- CHANGED: Replaces Binop
  | Lambda [Pattern] Expr
  | Call Expr [Expr]
  | If [(Expr, Expr)] Expr
  | Let Def Expr
  | LetRec [Def] Expr
  | LetDestruct Pattern Expr Expr
  | Case Expr [CaseBranch]
  | Accessor Name
  | Access Expr (A.Located Name)
  | Update Name Expr (Map Name FieldUpdate)
  | Record (Map Name Expr)
  | Unit
  | Tuple Expr Expr (Maybe Expr)
  | Shader Shader.Source Shader.Types
  deriving (Show)
```

**Binary Serialization:**

```haskell
instance Binary.Binary ArithOp where
  put op = Binary.putWord8 (arithOpToWord op)
  get = arithOpFromWord Binary.getWord8

-- | Encode ArithOp to Word8.
--
-- Compact binary encoding for arithmetic operators.
--
-- @since 0.19.2
arithOpToWord :: ArithOp -> Word8
arithOpToWord Add = 0
arithOpToWord Sub = 1
arithOpToWord Mul = 2
arithOpToWord Div = 3

-- | Decode Word8 to ArithOp.
--
-- Handles deserialization with error checking.
--
-- @since 0.19.2
arithOpFromWord :: Binary.Get Word8 -> Binary.Get ArithOp
arithOpFromWord getWord = do
  w <- getWord
  case w of
    0 -> pure Add
    1 -> pure Sub
    2 -> pure Mul
    3 -> pure Div
    _ -> fail ("Invalid ArithOp encoding: " ++ show w)

instance Binary.Binary BinopKind where
  put kind = case kind of
    NativeArith op -> Binary.putWord8 0 >> Binary.put op
    UserDefined op home name ->
      Binary.putWord8 1 >> Binary.put op >> Binary.put home >> Binary.put name

  get = do
    tag <- Binary.getWord8
    case tag of
      0 -> NativeArith <$> Binary.get
      1 -> UserDefined <$> Binary.get <*> Binary.get <*> Binary.get
      _ -> fail ("Invalid BinopKind encoding: " ++ show tag)
```

#### 1.3 Optimized AST Extensions

**File:** `packages/canopy-core/src/AST/Optimized.hs`

**New Type:**

```haskell
-- | Optimized expression for efficient code generation.
--
-- (All existing constructors remain...)
--
-- @since 0.19.1
data Expr
  = Bool Bool
  | Chr ES.String
  | Str ES.String
  | Int Int
  | Float EF.Float
  | VarLocal Name
  | VarGlobal Global
  | VarEnum Global Index.ZeroBased
  | VarBox Global
  | VarCycle ModuleName.Canonical Name
  | VarDebug Name ModuleName.Canonical A.Region (Maybe Name)
  | VarKernel Name Name
  | List [Expr]
  | Function [Name] Expr
  | Call Expr [Expr]
  | ArithBinop !ArithOp Expr Expr  -- NEW: Native arithmetic operators
  | TailCall Name [(Name, Expr)]
  | If [(Expr, Expr)] Expr
  | Let Def Expr
  | Destruct Destructor Expr
  | Case Name Name (Decider Choice) [(Int, Expr)]
  | Accessor Name
  | Access Expr Name
  | Update Expr (Map Name Expr)
  | Record (Map Name Expr)
  | Unit
  | Tuple Expr Expr (Maybe Expr)
  | Shader Shader.Source (Set Name) (Set Name)
  deriving (Show)
```

**Why ArithOp Reused:**
- Same 4 operators (Add, Sub, Mul, Div)
- Same semantics (native JavaScript operators)
- Reduces code duplication
- Import from Canonical: `import qualified AST.Canonical as Can`

**Binary Serialization:**

```haskell
putExpr :: Expr -> Binary.Put
putExpr expr = case expr of
  -- Existing cases 0-26...
  ArithBinop op left right -> 
    Binary.putWord8 27 >> Binary.put op >> Binary.put left >> Binary.put right
  -- Update error case to handle 27

getExpr :: Binary.Get Expr
getExpr = do
  word <- Binary.getWord8
  case word of
    n | n <= 4 -> getExprSimple n
    n | n <= 11 -> getExprVar n
    n | n <= 19 -> getExprControl n
    n | n <= 26 -> getExprData n
    27 -> ArithBinop <$> Binary.get <*> Binary.get <*> Binary.get
    _ -> fail "problem getting Opt.Expr binary"
```

---

### Phase 2: Canonicalization Integration

#### 2.1 Operator Classification Logic

**File:** `packages/canopy-core/src/Canonicalize/Expression.hs`

**Function:** `canonicalizeBinops`

**Current Code:**
```haskell
toBinop :: Env.Binop -> Can.Expr -> Can.Expr -> Can.Expr
toBinop (Env.Binop op home name annotation _ _) left right =
  A.merge left right (Can.Binop op home name annotation left right)
```

**New Code:**
```haskell
-- | Convert operator to canonical binary operation.
--
-- Classifies operators as either native arithmetic (which compile to
-- JavaScript operators) or user-defined (which remain function calls).
-- Classification is based on operator name and home module.
--
-- === Native Operators
--
-- Operators from @Basics@ module with names "+", "-", "*", "/" are
-- classified as native arithmetic and receive special codegen.
--
-- === User-Defined Operators
--
-- All other operators (including custom ones like "|>", "<|", ">>")
-- remain as function references and compile to normal function calls.
--
-- @since 0.19.1
toBinop :: Env.Binop -> Can.Expr -> Can.Expr -> Can.Expr
toBinop (Env.Binop op home name annotation _ _) left right =
  let kind = classifyBinop home name
  in A.merge left right (Can.BinopOp kind annotation left right)

-- | Classify binary operator for optimization.
--
-- Determines whether an operator should compile to native JavaScript
-- operations or remain a function call based on its home module and name.
--
-- === Classification Rules
--
-- * Basics.+ → NativeArith Add
-- * Basics.- → NativeArith Sub
-- * Basics.* → NativeArith Mul
-- * Basics./ → NativeArith Div
-- * Other → UserDefined with full reference
--
-- @since 0.19.2
classifyBinop :: ModuleName.Canonical -> Name -> Can.BinopKind
classifyBinop home name
  | home == ModuleName.basics = classifyBasicsOp name
  | otherwise = Can.UserDefined name home name

-- | Classify operator from Basics module.
--
-- Maps operator names to native arithmetic operations.
-- Only operators with direct JavaScript equivalents are native.
--
-- @since 0.19.2
classifyBasicsOp :: Name -> Can.BinopKind
classifyBasicsOp name
  | name == Name.fromChars "+" = Can.NativeArith Can.Add
  | name == Name.fromChars "-" = Can.NativeArith Can.Sub
  | name == Name.fromChars "*" = Can.NativeArith Can.Mul
  | name == Name.fromChars "/" = Can.NativeArith Can.Div
  | otherwise = Can.UserDefined name ModuleName.basics name
```

**Name Constants Required:**

Add to `packages/canopy-core/src/Data/Name/Constants.hs`:

```haskell
{-# NOINLINE add #-}
add :: Name
add = fromChars "+"

{-# NOINLINE sub #-}
sub :: Name  
sub = fromChars "-"

{-# NOINLINE mul #-}
mul :: Name
mul = fromChars "*"

{-# NOINLINE div_ #-}
div_ :: Name
div_ = fromChars "/"
```

Usage in classification:
```haskell
classifyBasicsOp :: Name -> Can.BinopKind
classifyBasicsOp name
  | name == Name.add = Can.NativeArith Can.Add
  | name == Name.sub = Can.NativeArith Can.Sub
  | name == Name.mul = Can.NativeArith Can.Mul
  | name == Name.div_ = Can.NativeArith Can.Div
  | otherwise = Can.UserDefined name ModuleName.basics name
```

#### 2.2 Type Constraint Generation

**File:** `packages/canopy-core/src/Type/Constrain/Expression.hs`

**Current Pattern:**
```haskell
Can.Binop _ home name annotation expected region ->
  constrainBinop region home name annotation expected
```

**New Pattern:**
```haskell
Can.BinopOp kind annotation left right region ->
  constrainBinopOp region kind annotation expected left right
```

**New Function:**

```haskell
-- | Generate type constraints for binary operator.
--
-- Handles both native arithmetic operators (with number constraints)
-- and user-defined operators (with arbitrary function types).
--
-- === Native Arithmetic
--
-- For operators like +, -, *, / generates constraints:
-- @
-- left :: number
-- right :: number  
-- result :: number
-- @
-- where number unifies with Int or Float.
--
-- === User-Defined
--
-- For operators like |>, <| generates standard function constraints:
-- @
-- op :: a -> b -> c
-- left :: a
-- right :: b
-- result :: c
-- @
--
-- @since 0.19.2
constrainBinopOp
  :: A.Region
  -> Can.BinopKind
  -> Can.Annotation
  -> Type.Expected Type.Type
  -> Can.Expr
  -> Can.Expr
  -> IO Type.Constraint
constrainBinopOp region kind annotation expected left right =
  case kind of
    Can.NativeArith _ ->
      constrainNativeArith region annotation expected left right
    Can.UserDefined _ home name ->
      constrainUserDefined region home name annotation expected left right

-- | Constrain native arithmetic operator.
--
-- Generates number constraints for both operands and result.
--
-- @since 0.19.2
constrainNativeArith
  :: A.Region
  -> Can.Annotation
  -> Type.Expected Type.Type
  -> Can.Expr
  -> Can.Expr
  -> IO Type.Constraint
constrainNativeArith region annotation expected left right = do
  leftType <- Type.mkFlexNumber
  rightType <- Type.mkFlexNumber
  resultType <- Type.mkFlexNumber
  
  leftCon <- constrain left (Type.NoExpectation leftType)
  rightCon <- constrain right (Type.NoExpectation rightType)
  resultCon <- Type.mkExpectedConstraint region expected resultType
  
  pure (Type.CAnd [leftCon, rightCon, resultCon])
```

---

### Phase 3: Optimization Pass

#### 3.1 Expression Optimization

**File:** `packages/canopy-core/src/Optimize/Expression.hs`

**Current Code:**
```haskell
Can.Binop _ home name _ left right ->
  do
    optFunc <- Names.registerGlobal home name
    optLeft <- optimize cycle left
    optRight <- optimize cycle right
    return (Opt.Call optFunc [optLeft, optRight])
```

**New Code:**
```haskell
Can.BinopOp kind _ left right ->
  optimizeBinop cycle kind left right

-- | Optimize binary operator expression.
--
-- Native arithmetic operators compile to direct operations.
-- User-defined operators compile to function calls.
--
-- @since 0.19.2
optimizeBinop
  :: Cycle
  -> Can.BinopKind
  -> Can.Expr
  -> Can.Expr
  -> Names.Tracker Opt.Expr
optimizeBinop cycle kind left right =
  case kind of
    Can.NativeArith op -> optimizeNativeArith cycle op left right
    Can.UserDefined _ home name -> optimizeUserDefined cycle home name left right

-- | Optimize native arithmetic operator.
--
-- Creates ArithBinop node for direct JavaScript codegen.
--
-- @since 0.19.2
optimizeNativeArith
  :: Cycle
  -> Can.ArithOp
  -> Can.Expr
  -> Can.Expr
  -> Names.Tracker Opt.Expr
optimizeNativeArith cycle op left right = do
  optLeft <- optimize cycle left
  optRight <- optimize cycle right
  pure (Opt.ArithBinop op optLeft optRight)

-- | Optimize user-defined operator.
--
-- Compiles to standard function call.
--
-- @since 0.19.2
optimizeUserDefined
  :: Cycle
  -> ModuleName.Canonical
  -> Name
  -> Can.Expr
  -> Can.Expr
  -> Names.Tracker Opt.Expr
optimizeUserDefined cycle home name left right = do
  optFunc <- Names.registerGlobal home name
  optLeft <- optimize cycle left
  optRight <- optimize cycle right
  pure (Opt.Call optFunc [optLeft, optRight])
```

#### 3.2 Constant Folding (Future Enhancement)

**Location:** New file `packages/canopy-core/src/Optimize/ConstantFold.hs`

**Design (not implemented in Phase 1):**

```haskell
-- | Fold constant arithmetic operations at compile time.
--
-- Evaluates arithmetic on literal values during optimization.
--
-- === Examples
--
-- @
-- 1 + 2        → 3
-- 3.0 * 4.0    → 12.0
-- 10 - 5       → 5
-- @
--
-- @since 0.19.3
foldArithBinop :: Can.ArithOp -> Opt.Expr -> Opt.Expr -> Maybe Opt.Expr
foldArithBinop Can.Add (Opt.Int a) (Opt.Int b) = Just (Opt.Int (a + b))
foldArithBinop Can.Sub (Opt.Int a) (Opt.Int b) = Just (Opt.Int (a - b))
foldArithBinop Can.Mul (Opt.Int a) (Opt.Int b) = Just (Opt.Int (a * b))
-- Division always produces Float in Canopy
foldArithBinop Can.Div (Opt.Int a) (Opt.Int b)
  | b /= 0 = Just (Opt.Float (fromIntegral a / fromIntegral b))
foldArithBinop Can.Add (Opt.Float a) (Opt.Float b) = Just (Opt.Float (a + b))
-- ... etc
foldArithBinop _ _ _ = Nothing
```

---

### Phase 4: Code Generation

#### 4.1 JavaScript Expression Generation

**File:** `packages/canopy-core/src/Generate/JavaScript/Expression.hs`

**Addition to `generate` function:**

```haskell
generate :: Mode.Mode -> Opt.Expr -> Code
generate mode expression =
  case expression of
    -- ... existing cases ...
    
    Opt.ArithBinop op left right ->
      generateArithBinop mode op left right
    
    -- ... rest of existing cases ...

-- | Generate JavaScript for native arithmetic operator.
--
-- Compiles to direct JavaScript arithmetic operators for performance.
-- Handles both integer and float operations.
--
-- === Generated Code
--
-- @
-- Add  → (left + right)
-- Sub  → (left - right)
-- Mul  → (left * right)
-- Div  → (left / right)
-- @
--
-- Parentheses ensure correct precedence in generated code.
--
-- @since 0.19.2
generateArithBinop :: Mode.Mode -> Can.ArithOp -> Opt.Expr -> Opt.Expr -> Code
generateArithBinop mode op left right =
  let leftExpr = generateJsExpr mode left
      rightExpr = generateJsExpr mode right
      jsOp = arithOpToJs op
  in JsExpr (JS.Infix jsOp leftExpr rightExpr)

-- | Map ArithOp to JavaScript operator.
--
-- @since 0.19.2
arithOpToJs :: Can.ArithOp -> JS.InfixOp
arithOpToJs Can.Add = JS.OpAdd
arithOpToJs Can.Sub = JS.OpSub
arithOpToJs Can.Mul = JS.OpMul
arithOpToJs Can.Div = JS.OpDiv
```

#### 4.2 JavaScript Builder Support

**File:** `packages/canopy-core/src/Generate/JavaScript/Builder.hs`

**Add infix operator support:**

```haskell
-- | JavaScript infix operators.
--
-- Binary operators used in expression generation.
--
-- @since 0.19.2
data InfixOp
  = OpAdd  -- ^ Addition (+)
  | OpSub  -- ^ Subtraction (-)
  | OpMul  -- ^ Multiplication (*)
  | OpDiv  -- ^ Division (/)
  | OpEq   -- ^ Equality (===)
  | OpNeq  -- ^ Inequality (!==)
  | OpLt   -- ^ Less than (<)
  | OpGt   -- ^ Greater than (>)
  | OpAnd  -- ^ Logical AND (&&)
  | OpOr   -- ^ Logical OR (||)
  deriving (Eq, Show)

-- | JavaScript expression with infix operators.
data Expr
  = -- ... existing constructors ...
  | Infix InfixOp Expr Expr  -- NEW: Binary infix operations
  deriving (Eq, Show)

-- | Serialize infix operation to JavaScript.
--
-- Generates parenthesized infix expressions for correct precedence.
--
-- @since 0.19.2
stmtToBuilder :: Expr -> Builder
stmtToBuilder expr = case expr of
  -- ... existing cases ...
  
  Infix op left right ->
    "(" <> exprToBuilder left <> " " <> opToBuilder op <> " " <> exprToBuilder right <> ")"

-- | Convert operator to JavaScript symbol.
--
-- @since 0.19.2
opToBuilder :: InfixOp -> Builder
opToBuilder OpAdd = "+"
opToBuilder OpSub = "-"
opToBuilder OpMul = "*"
opToBuilder OpDiv = "/"
opToBuilder OpEq = "==="
opToBuilder OpNeq = "!=="
opToBuilder OpLt = "<"
opToBuilder OpGt = ">"
opToBuilder OpAnd = "&&"
opToBuilder OpOr = "||"
```

---

## Migration Strategy

### Backwards Compatibility

**Guaranteed Compatibility:**

1. **User-defined operators unchanged**
   - Custom operators like `|>`, `<|`, `>>` remain function calls
   - No behavior changes for existing code
   - All existing operator definitions work

2. **Arithmetic operator semantics unchanged**
   - `1 + 2` still evaluates to `3`
   - Type inference unchanged (still `number -> number -> number`)
   - Error messages unchanged

3. **Module interface unchanged**
   - Canonical AST serialization includes `BinopKind`
   - Optimized AST serialization includes `ArithBinop`
   - Old compiled modules remain valid (loaded as `UserDefined`)

### Migration Path

**Phase 1: Foundation (This Document)**
- [ ] Define AST types (Canonical + Optimized)
- [ ] Add binary serialization
- [ ] Update type signatures

**Phase 2: Canonicalization**
- [ ] Implement `classifyBinop` logic
- [ ] Add Name constants for operators
- [ ] Update `toBinop` function
- [ ] Modify constraint generation

**Phase 3: Optimization**
- [ ] Implement `optimizeBinop` logic
- [ ] Add `optimizeNativeArith` function
- [ ] Update optimization tests

**Phase 4: Code Generation**
- [ ] Add `ArithBinop` case to `generate`
- [ ] Implement `generateArithBinop`
- [ ] Add `InfixOp` to JavaScript builder
- [ ] Update codegen tests

**Phase 5: Testing**
- [ ] Unit tests for AST construction
- [ ] Type inference tests
- [ ] Optimization tests
- [ ] Golden tests for JavaScript output
- [ ] Integration tests

---

## Testing Strategy

### Test Coverage Requirements

Per CLAUDE.md, minimum 80% coverage required across:

1. **AST Construction Tests**
   - Canonical AST node creation
   - BinopKind classification
   - ArithOp serialization/deserialization

2. **Canonicalization Tests**
   - Operator classification logic
   - Native vs user-defined distinction
   - Type annotation preservation

3. **Optimization Tests**
   - Native operator optimization
   - User operator preservation
   - Constant folding (future)

4. **Code Generation Tests**
   - JavaScript operator emission
   - Correct parenthesization
   - Mode handling (Dev vs Prod)

5. **Integration Tests**
   - End-to-end compilation
   - Runtime correctness
   - Performance validation

### Example Test Cases

**Test:** Canonical AST Construction
```haskell
testNativeArithClassification :: TestTree
testNativeArithClassification = testGroup "Native arithmetic classification"
  [ testCase "addition operator" $
      classifyBinop ModuleName.basics (Name.fromChars "+")
        @?= Can.NativeArith Can.Add
  
  , testCase "user-defined operator" $
      let home = ModuleName.canonical Pkg.core "MyModule"
      in classifyBinop home (Name.fromChars "|>")
        @?= Can.UserDefined (Name.fromChars "|>") home (Name.fromChars "|>")
  ]
```

**Test:** JavaScript Generation
```haskell
testArithBinopCodegen :: TestTree
testArithBinopCodegen = testGroup "Arithmetic binop codegen"
  [ testCase "addition generates +" $ do
      let expr = Opt.ArithBinop Can.Add (Opt.Int 1) (Opt.Int 2)
          code = generate Mode.dev expr
          js = codeToExpr code
      js @?= JS.Infix JS.OpAdd (JS.Int 1) (JS.Int 2)
  ]
```

**Golden Test:** Full Pipeline
```canopy
-- Input: test/Golden/input/arithmetic-native.can
module Main exposing (main)

add : Int -> Int -> Int
add a b = a + b

multiply : Float -> Float -> Float  
multiply x y = x * y

main = 
  let sum = add 1 2
      product = multiply 3.0 4.0
  in sum + product
```

Expected output:
```javascript
// test/Golden/expected/arithmetic-native.js
var $author$project$Main$add = F2(function(a, b) {
  return (a + b);
});

var $author$project$Main$multiply = F2(function(x, y) {
  return (x * y);
});

var $author$project$Main$main = (function() {
  var sum = A2($author$project$Main$add, 1, 2);
  var product = A2($author$project$Main$multiply, 3.0, 4.0);
  return (sum + product);
})();
```

---

## Performance Analysis

### Expected Improvements

**Benchmark:** Arithmetic-heavy code (1M iterations)

**Before:**
```javascript
// Function call overhead per operation
for (var i = 0; i < 1000000; i++) {
  result = A2($elm$core$Basics$add, result, i);
  result = A2($elm$core$Basics$mul, result, 2);
}
// Estimated: ~500ms
```

**After:**
```javascript
// Direct operators
for (var i = 0; i < 1000000; i++) {
  result = (result + i);
  result = (result * 2);
}
// Estimated: ~50ms (10x faster)
```

### Optimization Opportunities

**Future Enhancements:**

1. **Constant Folding**
   - `1 + 2` → `3` at compile time
   - `3.0 * 4.0` → `12.0` at compile time

2. **Algebraic Simplification**
   - `x + 0` → `x`
   - `x * 1` → `x`
   - `x * 0` → `0`

3. **Strength Reduction**
   - `x * 2` → `x + x` (potentially faster)
   - `x / 2` → `x * 0.5` (avoiding division)

4. **Dead Code Elimination**
   - Remove unused arithmetic (already supported by dependency analysis)

---

## Security Considerations

### Type Safety

**Constraint:** Arithmetic operators only work on numbers

```haskell
-- Type error (as expected):
main = "hello" + "world"  
-- Error: String does not unify with number

-- Type error (as expected):
main = [1,2,3] + [4,5,6]
-- Error: List a does not unify with number
```

### Division by Zero

**Runtime Behavior:** Follows JavaScript semantics

```javascript
// Division by zero produces Infinity (JavaScript standard)
1 / 0  // → Infinity
0 / 0  // → NaN
```

**Design Decision:** No compile-time division-by-zero checking
- JavaScript handles gracefully
- Runtime behavior well-defined
- Matches existing Basics.div behavior

---

## Documentation Requirements

### Haddock Documentation

All new types and functions require comprehensive Haddock docs per CLAUDE.md:

```haskell
-- | Short one-line summary.
--
-- Detailed explanation of purpose and behavior.
--
-- === Subsection
--
-- Additional details, examples, or notes.
--
-- ==== Examples
--
-- @
-- example :: Type
-- example = implementation
-- @
--
-- @since 0.19.2
```

### Module-Level Documentation

Each modified module needs updated documentation explaining native operator support.

---

## Implementation Checklist

### Phase 1: Foundation
- [ ] Add `ArithOp` to Canonical AST
- [ ] Add `BinopKind` to Canonical AST
- [ ] Replace `Binop` with `BinopOp` in `Expr_`
- [ ] Implement Binary serialization for new types
- [ ] Add `ArithBinop` to Optimized AST
- [ ] Update Optimized AST Binary serialization

### Phase 2: Canonicalization
- [ ] Implement `classifyBinop` function
- [ ] Implement `classifyBasicsOp` helper
- [ ] Add operator Name constants
- [ ] Update `toBinop` to use `BinopOp`
- [ ] Update constraint generation (`constrainBinopOp`)
- [ ] Implement `constrainNativeArith`

### Phase 3: Optimization
- [ ] Implement `optimizeBinop` function
- [ ] Implement `optimizeNativeArith` helper
- [ ] Implement `optimizeUserDefined` helper
- [ ] Update pattern matching in `optimize`

### Phase 4: Code Generation
- [ ] Add `InfixOp` type to JavaScript builder
- [ ] Implement `generateArithBinop`
- [ ] Add `arithOpToJs` helper
- [ ] Update `generate` pattern matching
- [ ] Implement `opToBuilder` serialization

### Phase 5: Testing
- [ ] Unit tests for AST types
- [ ] Unit tests for canonicalization
- [ ] Unit tests for optimization
- [ ] Unit tests for code generation
- [ ] Property tests for roundtrip serialization
- [ ] Golden tests for JavaScript output
- [ ] Integration tests for full pipeline
- [ ] Performance benchmarks

### Phase 6: Documentation
- [ ] Haddock docs for all new types
- [ ] Haddock docs for all new functions
- [ ] Update module-level documentation
- [ ] Add examples to documentation
- [ ] Update architecture documentation

---

## Code Examples

### Complete Example: Addition Operator

**Source Code:**
```canopy
add : Int -> Int -> Int
add a b = a + b

result = add 1 2
```

**Source AST:**
```haskell
Src.Binops 
  [(A.At region (Src.Var Src.LowVar "a"), A.At region "+")]
  (A.At region (Src.Var Src.LowVar "b"))
```

**Canonical AST:**
```haskell
Can.BinopOp
  (Can.NativeArith Can.Add)
  (Can.Forall freeVars (Can.TVar "number"))
  (A.At region (Can.VarLocal "a"))
  (A.At region (Can.VarLocal "b"))
```

**Optimized AST:**
```haskell
Opt.ArithBinop
  Can.Add
  (Opt.VarLocal "a")
  (Opt.VarLocal "b")
```

**Generated JavaScript:**
```javascript
var $author$project$Main$add = F2(function(a, b) {
  return (a + b);
});

var $author$project$Main$result = A2($author$project$Main$add, 1, 2);
```

---

## Future Enhancements

### Phase 2: Additional Native Operators

**Comparison Operators:**
```haskell
data CompareOp
  = Eq   -- (==)
  | Neq  -- (/=)
  | Lt   -- (<)
  | Gt   -- (>)
  | Lte  -- (<=)
  | Gte  -- (>=)
```

**Logical Operators:**
```haskell
data LogicOp
  = And  -- (&&)
  | Or   -- (||)
```

### Phase 3: Advanced Optimizations

1. **Constant Folding**
2. **Algebraic Simplification**
3. **Strength Reduction**
4. **Loop Invariant Code Motion**

---

## Conclusion

This architecture provides a clean, performant, and maintainable solution for native arithmetic operators in Canopy. The design:

✅ Achieves zero runtime overhead (direct JavaScript operators)
✅ Maintains complete type safety (full constraint generation)
✅ Preserves backwards compatibility (user operators unchanged)
✅ Follows CLAUDE.md standards (≤15 lines, ≤4 params, comprehensive docs)
✅ Enables future optimizations (constant folding, algebraic simplification)

**Next Steps:**
1. Review and approve this design
2. Implement Phase 1 (Foundation)
3. Add comprehensive tests
4. Validate with golden test suite
5. Benchmark performance improvements

---

**Document Version:** 2.0  
**Last Updated:** 2025-10-28  
**Approved By:** _Pending Review_
