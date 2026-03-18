# Current Operator Implementation Analysis - Canopy Compiler

## Overview

This document analyzes how operators currently work in the Canopy compiler, focusing on the AST representations, canonicalization, optimization, and code generation phases.

## 1. AST Structure

### 1.1 Source AST (Source.hs)

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/AST/Source.hs`

Operators are represented at the source level as chains:

```haskell
data Expr_
  = Op Name                           -- Operator reference like (+) or (*)
  | Binops [(Expr, A.Located Name)] Expr  -- Chain of binary operators
  | Negate Expr                       -- Unary negation
  | ...
```

**Key Points:**
- `Op Name` represents operator references (when used in sections or parentheses)
- `Binops [(Expr, A.Located Name)] Expr` represents operator chains: `a + b * c - d`
  - Each tuple contains (left operand, operator)
  - Final expression is the rightmost operand
  - Precedence resolution happens later (not in parsing)

### 1.2 Canonical AST (Canonical.hs)

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/AST/Canonical.hs`

After canonicalization, operators are fully resolved:

```haskell
data Expr_
  = VarOperator Name ModuleName.Canonical Name Annotation
      -- CACHE real name for optimization
  | Binop Name ModuleName.Canonical Name Annotation Expr Expr
      -- CACHE real name for optimization
  | VarLocal Name
  | VarTopLevel ModuleName.Canonical Name
  | ...
```

**Key Points:**
- `VarOperator` - Operator reference with cached real name and annotation
  - `Name` - Original operator symbol (e.g., "+")
  - `ModuleName.Canonical` - Module where operator is defined
  - `Name` - Real name in that module (e.g., "add")
  - `Annotation` - Type information cached for inference
  
- `Binop` - Binary operation (already resolved from Binops chain)
  - `Name` - Original operator symbol
  - `ModuleName.Canonical` - Module where defined
  - `Name` - Real name
  - `Annotation` - Type annotation
  - `Expr` - Left operand
  - `Expr` - Right operand

- **Module-level storage:**
```haskell
data Module = Module
  { ...
  , _binops :: Map Name Binop  -- Operator definitions with precedence/associativity
  , ...
  }

data Binop = Binop_ Binop.Associativity Binop.Precedence Name
  deriving (Eq)
```

### 1.3 Optimized AST (Optimized.hs)

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/AST/Optimized.hs`

Operators are eliminated and converted to function calls:

```haskell
data Expr
  = VarLocal Name
  | VarGlobal Global
  | VarKernel Name Name
  | Call Expr [Expr]  -- All operators become calls
  | ...
```

**Key Points:**
- **No `Binop` in Optimized AST** - operators are completely eliminated
- `Can.Binop` is converted to `Opt.Call` during optimization
- The function being called is the resolved operator function (VarGlobal with the operator's real name)

## 2. Operator Precedence and Associativity

### 2.1 Binop Utilities (AST/Utils/Binop.hs)

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/AST/Utils/Binop.hs`

```haskell
newtype Precedence = Precedence Int
  deriving (Eq, Ord, Show)

data Associativity
  = Left   -- a + b + c = (a + b) + c
  | Non    -- a < b < c is invalid
  | Right  -- a ^ b ^ c = a ^ (b ^ c)
  deriving (Eq, Show)
```

**Precedence Levels (Higher = Tighter Binding):**
- 9: Function application, record access
- 8: Exponentiation (^)
- 7: Multiplication (*), division (/), remainder (%)
- 6: Addition (+), subtraction (-)
- 5: List construction (::)
- 4: Comparison (<, >, <=, >=)
- 3: Equality (==, /=)
- 2: Logical AND (&&)
- 1: Logical OR (||)
- 0: Pipeline (|>), reverse pipeline (<|)

### 2.2 Operator Definition in Canonical AST

Operators are stored in the module's `_binops` map:

```haskell
data Binop = Binop_ Associativity Precedence Name

-- Stored as: Map Name Binop
-- Where Name is the operator symbol ("+", "*", etc.)
```

## 3. Canonicalization Phase

### 3.1 Expression Canonicalization (Canonicalize/Expression.hs)

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Canonicalize/Expression.hs`

#### Operator Reference (`Op`)
```haskell
Src.Op op ->
  do
    (Env.Binop _ home name annotation _ _) <- Env.findBinop region env op
    return (Can.VarOperator op home name annotation)
```

**Key Points:**
- Looks up operator in environment
- Returns `VarOperator` with resolved home and real name
- Caches type annotation

#### Operator Chain (`Binops`)
```haskell
Src.Binops ops final ->
  A.toValue <$> canonicalizeBinops region env ops final
```

**Process:**
1. Canonicalize each operand and operator separately
2. Use `canonicalizeBinops` to resolve precedence
3. Convert to nested `Can.Binop` calls based on precedence/associativity

#### Binary Operation Resolution
```haskell
canonicalizeBinops :: A.Region -> Env.Env -> [(Src.Expr, A.Located Name.Name)] -> Src.Expr
  -> Result FreeLocals [W.Warning] Can.Expr
canonicalizeBinops overallRegion env ops final =
  let canonicalizeHelp (expr, A.At region op) =
        (,)
          <$> canonicalize env expr
          <*> Env.findBinop region env op
   in runBinopStepper overallRegion
        =<< ( More
                <$> traverse canonicalizeHelp ops
                <*> canonicalize env final
            )
```

**Stepper Algorithm:**
```haskell
data Step
  = Done Can.Expr
  | More [(Can.Expr, Env.Binop)] Can.Expr
  | Error Env.Binop Env.Binop

toBinopStep :: (Can.Expr -> Can.Expr) -> Env.Binop -> [(Can.Expr, Env.Binop)] -> Can.Expr -> Step
```

**Key Points:**
- Uses precedence-climbing algorithm
- Converts left operand into function: `toBinop op expr`
- Respects associativity (left vs right)
- Detects associativity conflicts and rejects them

#### Building the Binop
```haskell
toBinop :: Env.Binop -> Can.Expr -> Can.Expr -> Can.Expr
toBinop (Env.Binop op home name annotation _ _) left right =
  A.merge left right (Can.Binop op home name annotation left right)
```

**Output:** `Can.Binop` with:
- Original operator symbol
- Home module
- Real function name
- Type annotation
- Left and right operands

## 4. Optimization Phase

### 4.1 Binop to Call Conversion (Optimize/Expression.hs)

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Optimize/Expression.hs`

```haskell
Can.Binop _ home name _ left right ->
  do
    optFunc <- Names.registerGlobal home name
    optLeft <- optimize cycle left
    optRight <- optimize cycle right
    return (Opt.Call optFunc [optLeft, optRight])
```

**Key Points:**
- Completely eliminates `Binop` construct
- Converts to `Opt.Call` with:
  - Function: `VarGlobal (home, name)` - the operator function
  - Arguments: [left operand, right operand]
- Type annotation is discarded (already used in type inference)
- Operator symbol is discarded (real name is used)

**Integration Point:** This is where `Opt.Call` replaces operator-specific handling.

### 4.2 Operator Variable Handling
```haskell
Can.VarOperator _ home name _ ->
  Names.registerGlobal home name
```

**Key Points:**
- `VarOperator` becomes `VarGlobal` (a function reference)
- Used when operator appears in sections like `(+)`

## 5. Code Generation Phase

### 5.1 JavaScript Expression Generation (Generate/JavaScript/Expression.hs)

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Generate/JavaScript/Expression.hs`

```haskell
generate :: Mode.Mode -> Opt.Expr -> Code
generate mode expression =
  case expression of
    Opt.Call func args ->
      JsExpr $ generateCall mode func args
    Opt.VarGlobal (Opt.Global home name) ->
      JsExpr $ JS.Ref (JsName.fromGlobal home name)
    ...
```

**Key Points:**
- Since operators are already converted to `Call` in optimization
- Code generation handles them as regular function calls
- No special operator handling needed
- Example: `a + b` becomes `JS.Call (JS.Ref "add") [a, b]`

#### Special FFI Handling
```haskell
Opt.VarGlobal (Opt.Global home name) ->
  let pkg = ModuleName._package home
      moduleName = ModuleName._module home
  in if Pkg._author pkg == Pkg._author Pkg.dummyName
       && Pkg._project pkg == Pkg._project Pkg.dummyName
     then -- FFI function - generate direct JavaScript access
          let moduleStr = Name.toChars moduleName
              nameStr = Name.toChars name
              jsName = Name.fromChars (moduleStr ++ "." ++ nameStr)
          in JsExpr $ JS.Ref (JsName.fromLocal jsName)
     else -- Regular global function
          JsExpr $ JS.Ref (JsName.fromGlobal home name)
```

**Key Points:**
- FFI operators (from dummy package) are mapped to direct JavaScript references
- Example: `Math.add` from FFI becomes `Math.add` in generated JavaScript

## 6. Binary Serialization

### 6.1 Binop Serialization

Not directly serialized - instead, operator definitions from modules are cached:

**Type instances:**
```haskell
instance Binary Precedence where
  get = fmap Precedence get
  put (Precedence n) = put n

instance Binary Associativity where
  get = do { n <- getWord8; ... }
  put assoc = putWord8 $ case assoc of
    Left -> 0
    Non -> 1
    Right -> 2
```

**Module serialization:**
- Operator definitions stored in module interface files
- Type information (`Annotation`) serialized with complete Type instances
- Canonical AST cached (with full type information)

## 7. Integration Points for Native Operators

### 7.1 Where Modifications Are Needed

#### 1. **Operator Definition** (Canonical.hs)
- ✓ Already supports arbitrary operator names and precedence
- ✓ `_binops` map in Module stores all operator info
- Modify: Add native operator type classification

#### 2. **Canonicalization** (Canonicalize/Expression.hs)
- ✓ Already resolves operators to their real names and modules
- Modify: Detect native operators during `Env.findBinop` lookup
- Add: Cache native operator information in `Annotation` or new field

#### 3. **Optimization** (Optimize/Expression.hs)
- ✓ Already converts `Binop` to `Call`
- Modify: Pass native operator information through to codegen
- Option A: Store in `VarGlobal` metadata
- Option B: Create new `Opt.Expr` variant for native operators

#### 4. **Code Generation** (Generate/JavaScript/Expression.hs)
- ✓ Already handles function calls generically
- Modify: Detect native operators and generate inline code
- Current: `generateCall mode func args`
- New: Special handling for operators marked as native

### 7.2 Existing Patterns to Follow

#### Pattern: Binary Serialization for Type Information
Used in `Canonical.hs` for types - same pattern can apply to operator metadata:
```haskell
instance Binary.Binary Type where
  put = putType
  get = getType

-- Specialized serialization for complex types:
putType :: Type -> Binary.Put
putType tipe = case tipe of
  TLambda a b -> Binary.putWord8 0 >> Binary.put a >> Binary.put b
  ...
```

#### Pattern: Annotation Caching
Operators already cache type information:
```haskell
Can.Binop Name ModuleName.Canonical Name Annotation Expr Expr
```

Can extend this to cache operator properties:
```haskell
-- New approach:
Can.Binop Name ModuleName.Canonical Name Annotation OperatorInfo Expr Expr

data OperatorInfo
  = StandardOperator
  | NativeOperator NativeOpType
```

#### Pattern: Mode-Based Code Generation
JavaScript generation already has mode-based branches:
```haskell
case mode of
  Mode.Dev _ _ -> ...
  Mode.Prod _ _ -> ...
```

Can follow same pattern for native operators:
```haskell
case operatorInfo of
  StandardOperator -> generateCall mode func args
  NativeOperator native -> generateNativeOp mode native args
```

#### Pattern: FFI Handling
Already detecting FFI modules by package comparison:
```haskell
if Pkg._author pkg == Pkg._author Pkg.dummyName
   && Pkg._project pkg == Pkg._project Pkg.dummyName
```

Can use similar approach for native operator detection.

## 8. Current Limitations and Opportunities

### Limitations
1. No distinction between standard operators and optimizable ones
2. All operators become function calls (cannot optimize to inline operations)
3. No type-specific optimizations (e.g., integer arithmetic vs floating-point)
4. Operator information lost after optimization phase

### Opportunities for Improvement
1. **Type-aware operator handling** - Preserve type info for optimized operations
2. **Inline operator code** - Generate direct JavaScript for native operations
3. **Operator fusion** - Combine chained operators (e.g., `a + b + c` as single operation)
4. **SIMD operations** - Map operators to vector operations when possible
5. **Compile-time evaluation** - Evaluate operator chains with literal operands

## 9. Summary Table

| Phase | File | Current Behavior | Modification Point |
|-------|------|------------------|-------------------|
| Source | Source.hs | Operator chains as `Binops` | Add metadata |
| Canonicalize | Canonicalize/Expression.hs | Resolve precedence, create `Can.Binop` | Detect native ops |
| Type Check | Type phase | Infer operator types | Cache native info |
| Optimize | Optimize/Expression.hs | Convert `Can.Binop` to `Opt.Call` | Preserve metadata |
| Generate | Generate/JavaScript/Expression.hs | Generate function call | Check for native ops |
| Output | JavaScript | Standard function call | Inline native code |

## 10. File Locations Quick Reference

| Concern | File | Lines |
|---------|------|-------|
| Source operator syntax | `AST/Source.hs` | 204-219 |
| Canonical binop type | `AST/Canonical.hs` | 196, 203, 329-337 |
| Precedence/Associativity | `AST/Utils/Binop.hs` | 106-169 |
| Operator reference | `Canonicalize/Expression.hs` | 72-75 |
| Operator chain resolution | `Canonicalize/Expression.hs` | 172-230 |
| Binop to Call conversion | `Optimize/Expression.hs` | 65-70 |
| JavaScript code generation | `Generate/JavaScript/Expression.hs` | 67-79, 114-115 |
