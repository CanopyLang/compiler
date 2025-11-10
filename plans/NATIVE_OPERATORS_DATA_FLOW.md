# Native Arithmetic Operators - Data Flow Diagram

**Companion to:** NATIVE_OPERATORS_AST_DESIGN.md  
**Date:** 2025-10-28

---

## Complete Data Flow Through Compiler Pipeline

```
┌────────────────────────────────────────────────────────────────────┐
│                         INPUT: SOURCE CODE                         │
│                                                                    │
│  add : Int -> Int -> Int                                          │
│  add a b = a + b                                                  │
└────────────────────────────────────────────────────────────────────┘
                                ↓
┌────────────────────────────────────────────────────────────────────┐
│                    PHASE 1: PARSING → SOURCE AST                   │
│                   (AST/Source.hs - UNCHANGED)                      │
│                                                                    │
│  Src.Binops                                                        │
│    [ (Src.Var LowVar "a", Located "+")                            │
│    ]                                                               │
│    (Src.Var LowVar "b")                                           │
│                                                                    │
│  NOTE: Parser doesn't classify operators yet                       │
└────────────────────────────────────────────────────────────────────┘
                                ↓
┌────────────────────────────────────────────────────────────────────┐
│          PHASE 2: CANONICALIZATION → CANONICAL AST                 │
│         (Canonicalize/Expression.hs - MODIFIED)                    │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ canonicalizeBinops :: ... -> Can.Expr                        │ │
│  │   ↓                                                          │ │
│  │ toBinop :: Env.Binop -> Can.Expr -> Can.Expr -> Can.Expr    │ │
│  │   ↓                                                          │ │
│  │ classifyBinop :: ModuleName.Canonical -> Name -> BinopKind  │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                    │
│  Can.BinopOp                                                       │
│    (Can.NativeArith Can.Add)  ← CLASSIFIED AS NATIVE              │
│    (Can.Forall freeVars numberType)                               │
│    (Can.VarLocal "a")                                             │
│    (Can.VarLocal "b")                                             │
│                                                                    │
│  Classification Logic:                                             │
│    home == Basics && name == "+" → NativeArith Add                │
│    otherwise                     → UserDefined name home name     │
└────────────────────────────────────────────────────────────────────┘
                                ↓
┌────────────────────────────────────────────────────────────────────┐
│                   PHASE 3: TYPE INFERENCE                          │
│           (Type/Constrain/Expression.hs - MODIFIED)                │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ constrainBinopOp :: Region -> BinopKind -> ... -> Constraint│ │
│  │   ↓                                                          │ │
│  │ Pattern Match on BinopKind:                                 │ │
│  │   NativeArith op → constrainNativeArith                     │ │
│  │   UserDefined .. → constrainUserDefined                     │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                    │
│  Constraints Generated:                                            │
│    a :: number                                                     │
│    b :: number                                                     │
│    result :: number                                                │
│                                                                    │
│  NOTE: number unifies with Int or Float                            │
└────────────────────────────────────────────────────────────────────┘
                                ↓
┌────────────────────────────────────────────────────────────────────┐
│              PHASE 4: OPTIMIZATION → OPTIMIZED AST                 │
│             (Optimize/Expression.hs - MODIFIED)                    │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ optimize :: Cycle -> Can.Expr -> Tracker Opt.Expr           │ │
│  │   ↓                                                          │ │
│  │ Pattern: Can.BinopOp kind _ left right                      │ │
│  │   ↓                                                          │ │
│  │ optimizeBinop :: Cycle -> BinopKind -> ... -> Opt.Expr      │ │
│  │   ↓                                                          │ │
│  │ Pattern Match on BinopKind:                                 │ │
│  │   NativeArith op → optimizeNativeArith   (returns ArithBinop)│ │
│  │   UserDefined .. → optimizeUserDefined   (returns Call)     │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                    │
│  Opt.ArithBinop                                                    │
│    Can.Add            ← NATIVE OPERATOR NODE                       │
│    (Opt.VarLocal "a")                                             │
│    (Opt.VarLocal "b")                                             │
│                                                                    │
│  NOTE: No function call - direct operator representation           │
└────────────────────────────────────────────────────────────────────┘
                                ↓
┌────────────────────────────────────────────────────────────────────┐
│                 PHASE 5: CODE GENERATION → JAVASCRIPT              │
│           (Generate/JavaScript/Expression.hs - MODIFIED)           │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ generate :: Mode -> Opt.Expr -> Code                        │ │
│  │   ↓                                                          │ │
│  │ Pattern: Opt.ArithBinop op left right                       │ │
│  │   ↓                                                          │ │
│  │ generateArithBinop :: Mode -> ArithOp -> ... -> Code        │ │
│  │   ↓                                                          │ │
│  │ arithOpToJs :: ArithOp -> JS.InfixOp                        │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                    │
│  JS.Infix                                                          │
│    JS.OpAdd                                                        │
│    (JS.Ref (JsName.fromLocal "a"))                                │
│    (JS.Ref (JsName.fromLocal "b"))                                │
│                                                                    │
│  Serialized to:                                                    │
│    "(a + b)"          ← NATIVE JAVASCRIPT OPERATOR                 │
└────────────────────────────────────────────────────────────────────┘
                                ↓
┌────────────────────────────────────────────────────────────────────┐
│                   OUTPUT: JAVASCRIPT CODE                          │
│                                                                    │
│  var $author$project$Main$add = F2(function(a, b) {               │
│    return (a + b);    ← DIRECT OPERATOR, NO FUNCTION CALL         │
│  });                                                               │
└────────────────────────────────────────────────────────────────────┘
```

---

## Comparison: Native vs User-Defined Operators

### Native Arithmetic Operator Flow

```
SOURCE:     a + b
    ↓
CANONICAL:  BinopOp (NativeArith Add) annotation a b
    ↓
OPTIMIZED:  ArithBinop Add a b
    ↓
JAVASCRIPT: (a + b)
```

### User-Defined Operator Flow

```
SOURCE:     a |> f
    ↓
CANONICAL:  BinopOp (UserDefined "|>" home "|>") annotation a f
    ↓
OPTIMIZED:  Call (VarGlobal (Global home "|>")) [a, f]
    ↓
JAVASCRIPT: A2($elm$core$Basics$pipe, a, f)
```

---

## Key Integration Points

### 1. Canonicalize/Expression.hs

**Function:** `toBinop`
**Change:** Add classification logic
**Line Count:** ~10 lines (within 15 line limit)

```haskell
toBinop :: Env.Binop -> Can.Expr -> Can.Expr -> Can.Expr
toBinop (Env.Binop op home name annotation _ _) left right =
  let kind = classifyBinop home name
  in A.merge left right (Can.BinopOp kind annotation left right)
```

**Function:** `classifyBinop`
**Change:** New function
**Line Count:** ~4 lines (within 15 line limit)

```haskell
classifyBinop :: ModuleName.Canonical -> Name -> Can.BinopKind
classifyBinop home name
  | home == ModuleName.basics = classifyBasicsOp name
  | otherwise = Can.UserDefined name home name
```

**Function:** `classifyBasicsOp`
**Change:** New function
**Line Count:** ~7 lines (within 15 line limit)

```haskell
classifyBasicsOp :: Name -> Can.BinopKind
classifyBasicsOp name
  | name == Name.add = Can.NativeArith Can.Add
  | name == Name.sub = Can.NativeArith Can.Sub
  | name == Name.mul = Can.NativeArith Can.Mul
  | name == Name.div_ = Can.NativeArith Can.Div
  | otherwise = Can.UserDefined name ModuleName.basics name
```

### 2. Type/Constrain/Expression.hs

**Function:** `constrainBinopOp`
**Change:** New function (replaces old `Binop` pattern)
**Line Count:** ~8 lines (within 15 line limit)

```haskell
constrainBinopOp region kind annotation expected left right =
  case kind of
    Can.NativeArith _ ->
      constrainNativeArith region annotation expected left right
    Can.UserDefined _ home name ->
      constrainUserDefined region home name annotation expected left right
```

### 3. Optimize/Expression.hs

**Function:** `optimizeBinop`
**Change:** New function
**Line Count:** ~8 lines (within 15 line limit)

```haskell
optimizeBinop cycle kind left right =
  case kind of
    Can.NativeArith op -> optimizeNativeArith cycle op left right
    Can.UserDefined _ home name -> optimizeUserDefined cycle home name left right
```

**Function:** `optimizeNativeArith`
**Change:** New function
**Line Count:** ~5 lines (within 15 line limit)

```haskell
optimizeNativeArith cycle op left right = do
  optLeft <- optimize cycle left
  optRight <- optimize cycle right
  pure (Opt.ArithBinop op optLeft optRight)
```

### 4. Generate/JavaScript/Expression.hs

**Function:** `generateArithBinop`
**Change:** New function
**Line Count:** ~7 lines (within 15 line limit)

```haskell
generateArithBinop mode op left right =
  let leftExpr = generateJsExpr mode left
      rightExpr = generateJsExpr mode right
      jsOp = arithOpToJs op
  in JsExpr (JS.Infix jsOp leftExpr rightExpr)
```

**Function:** `arithOpToJs`
**Change:** New function
**Line Count:** ~5 lines (within 15 line limit)

```haskell
arithOpToJs Can.Add = JS.OpAdd
arithOpToJs Can.Sub = JS.OpSub
arithOpToJs Can.Mul = JS.OpMul
arithOpToJs Can.Div = JS.OpDiv
```

---

## Binary Serialization Flow

### Canonical AST Serialization

```
BinopKind Encoding:
  NativeArith op  → byte 0, then ArithOp encoding
  UserDefined ... → byte 1, then 3 fields

ArithOp Encoding:
  Add → byte 0
  Sub → byte 1
  Mul → byte 2
  Div → byte 3
```

### Optimized AST Serialization

```
Expr Encoding (word 27 = new):
  ArithBinop op left right → byte 27, then:
    - ArithOp encoding (1 byte)
    - left Expr encoding (recursive)
    - right Expr encoding (recursive)
```

### Roundtrip Property

```haskell
-- Property test
prop_binopRoundtrip :: BinopKind -> Bool
prop_binopRoundtrip kind =
  let encoded = Binary.encode kind
      decoded = Binary.decode encoded
  in decoded == kind

prop_arithBinopRoundtrip :: Opt.Expr -> Bool
prop_arithBinopRoundtrip expr@(Opt.ArithBinop _ _ _) =
  let encoded = Binary.encode expr
      decoded = Binary.decode encoded
  in decoded == expr
```

---

## Performance Characteristics

### Before (Current Implementation)

```
Operation: 1 + 2
Canonical AST size: ~80 bytes (Binop node + annotations)
Optimized AST size: ~120 bytes (Call node + VarGlobal + args)
JavaScript size: ~30 bytes ("A2($elm$core$Basics$add, 1, 2)")
Runtime cost: Function call + currying overhead
```

### After (Native Operators)

```
Operation: 1 + 2
Canonical AST size: ~60 bytes (BinopOp node + tag)
Optimized AST size: ~40 bytes (ArithBinop node + args)
JavaScript size: ~7 bytes ("(1 + 2)")
Runtime cost: Direct CPU instruction
```

**Improvements:**
- AST size: ~50% reduction
- JavaScript size: ~77% reduction
- Runtime: ~10x faster (no function call overhead)

---

## Type Inference Flow

### Native Arithmetic

```
Expression: a + b

Constraint Generation:
  a :: number         (fresh type variable)
  b :: number         (fresh type variable)
  result :: number    (fresh type variable)

Unification:
  number ~ Int    OR    number ~ Float
  (polymorphic until usage determines concrete type)

Error Example:
  "hello" + "world"
  → Error: String does not unify with number
```

### User-Defined Operator

```
Expression: a |> f

Constraint Generation:
  (|>) :: a -> (a -> b) -> b    (from operator definition)
  a :: freshVar1
  f :: freshVar1 -> freshVar2
  result :: freshVar2

Unification:
  Standard Hindley-Milner unification
```

---

## Error Messages

### Type Error Examples

**Before and After (unchanged):**

```canopy
-- Error case 1: Wrong type
add : String -> String -> String
add a b = a + b

Error: Type mismatch
  Expected: number -> number -> number
  Actual: String -> String -> String
  Hint: The (+) operator only works on numbers (Int or Float)
```

```canopy
-- Error case 2: Mixed types
mixed a = a + "hello"

Error: Type mismatch
  The left argument has type: number
  The right argument has type: String
  Hint: Both arguments to (+) must be numbers
```

---

## Module Dependencies

### Files Modified

1. `AST/Canonical.hs` - Add ArithOp, BinopKind, modify Expr_
2. `AST/Optimized.hs` - Add ArithBinop constructor
3. `Canonicalize/Expression.hs` - Add classification logic
4. `Type/Constrain/Expression.hs` - Add constraint generation
5. `Optimize/Expression.hs` - Add optimization logic
6. `Generate/JavaScript/Expression.hs` - Add code generation
7. `Generate/JavaScript/Builder.hs` - Add InfixOp support
8. `Data/Name/Constants.hs` - Add operator name constants

### Import Graph

```
Data/Name/Constants.hs
    ↓ (imports)
Canonicalize/Expression.hs
    ↓ (imports)
AST/Canonical.hs
    ↓ (imports)
Type/Constrain/Expression.hs
    ↓ (imports)
Optimize/Expression.hs
    ↓ (imports)
AST/Optimized.hs
    ↓ (imports)
Generate/JavaScript/Expression.hs
    ↓ (imports)
Generate/JavaScript/Builder.hs
```

---

## Testing Matrix

| Test Type | Coverage | Files |
|-----------|----------|-------|
| Unit - AST | BinopKind construction | `test/Unit/AST/CanonicalTest.hs` |
| Unit - AST | ArithBinop construction | `test/Unit/AST/OptimizedTest.hs` |
| Unit - Canonicalize | Operator classification | `test/Unit/Canonicalize/ExpressionTest.hs` |
| Unit - Optimize | Native optimization | `test/Unit/Optimize/ExpressionTest.hs` |
| Unit - Generate | JavaScript emission | `test/Unit/Generate/JavaScript/ExpressionTest.hs` |
| Property | Binary roundtrip | `test/Property/AST/SerializationProps.hs` |
| Golden | Full pipeline | `test/Golden/input/arithmetic-native.can` |
| Integration | Runtime behavior | `test/Integration/ArithmeticRuntimeTest.hs` |
| Performance | Benchmark | `bench/ArithmeticBench.hs` |

---

## Next Steps

1. **Review this design with team**
2. **Approve NATIVE_OPERATORS_AST_DESIGN.md**
3. **Create implementation tasks:**
   - Task 1: AST type definitions
   - Task 2: Binary serialization
   - Task 3: Canonicalization logic
   - Task 4: Type constraint generation
   - Task 5: Optimization logic
   - Task 6: Code generation
   - Task 7: Comprehensive testing
4. **Assign to implementer agent**
5. **Execute with TDD approach**

---

**Document Status:** Design Complete  
**Next Phase:** Implementation  
**Estimated Effort:** 3-4 days (with testing)
