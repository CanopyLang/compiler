# Operator Flow Comparison Diagram

## Current Architecture (Inefficient)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          SOURCE CODE: x + y                              │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                        ┌────────▼────────┐
                        │  PARSER         │
                        │  Src.Binops     │
                        │  [(x, "+")]  y  │
                        └────────┬────────┘
                                 │
                    ┌────────────▼────────────┐
                    │  CANONICALIZE           │
                    │  Env.findBinop "+"      │
                    │  → Basics.add           │
                    │  Can.Binop "+" Basics   │
                    │    "add" annotation x y │
                    └────────┬────────────────┘
                             │
                             │ ❌ LOSES OPERATOR IDENTITY
                             │
                ┌────────────▼────────────────┐
                │  OPTIMIZE                   │
                │  Can.Binop → Opt.Call       │
                │  Opt.Call                   │
                │    (VarGlobal Basics "add") │
                │    [x, y]                   │
                │                             │
                │  ❌ NO constant folding     │
                │  ❌ NO algebraic simplify   │
                │  ❌ NO strength reduction   │
                └────────────┬────────────────┘
                             │
                ┌────────────▼──────────────────┐
                │  CODE GENERATION              │
                │  Pattern match on "add"       │
                │  if name == "add" →           │
                │    JS.Infix OpAdd left right  │
                │  (15 string comparisons!)     │
                └────────────┬──────────────────┘
                             │
                    ┌────────▼────────┐
                    │  JAVASCRIPT     │
                    │  x + y          │
                    └─────────────────┘
```

**Performance Issues**:
- 🔴 O(log n) operator lookup in canonicalization
- 🔴 Lost semantic information in optimization
- 🔴 15 string comparisons per operator in codegen
- 🔴 Zero optimization opportunities (folding, simplification, CSE)

---

## Proposed Architecture (Efficient)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          SOURCE CODE: x + y                              │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                        ┌────────▼────────┐
                        │  PARSER         │
                        │  Src.Binops     │
                        │  [(x, "+")]  y  │
                        └────────┬────────┘
                                 │
                    ┌────────────▼────────────┐
                    │  CANONICALIZE           │
                    │  Env.findBinop "+"      │
                    │  → Basics.add           │
                    │  Can.Binop "+" Basics   │
                    │    "add" annotation x y │
                    └────────┬────────────────┘
                             │
                             │ ✅ PRESERVES OPERATOR IDENTITY
                             │
                ┌────────────▼────────────────┐
                │  OPTIMIZE                   │
                │  Can.Binop → Opt.Binop      │
                │  Opt.Binop OpAdd x y        │
                │                             │
                │  ✅ Constant folding        │
                │     Int 1 + Int 2 → Int 3   │
                │  ✅ Algebraic simplify      │
                │     x + 0 → x               │
                │  ✅ Strength reduction      │
                │     x * 2 → x + x           │
                │  ✅ CSE detection           │
                └────────────┬────────────────┘
                             │
                ┌────────────▼──────────────────┐
                │  CODE GENERATION              │
                │  Direct enum match            │
                │  OpAdd → JS.Infix OpAdd       │
                │  (1 comparison, O(1) lookup)  │
                └────────────┬──────────────────┘
                             │
                    ┌────────▼────────┐
                    │  JAVASCRIPT     │
                    │  x + y          │
                    │  or             │
                    │  3 (if folded)  │
                    └─────────────────┘
```

**Performance Improvements**:
- 🟢 Same O(log n) canonicalization (unchanged)
- 🟢 **Semantic information preserved** in IR
- 🟢 O(1) enum comparison in codegen (vs 15 string comparisons)
- 🟢 **Multiple optimization passes enabled**

---

## Example: Constant Folding Impact

### Current Compilation

```
Source:  area = 3.14 * 10 * 10

Parse:   Src.Binops [(3.14, "*"), (10, "*")] 10

Canonical:
  Can.Binop "*" Basics "mul" ...
    (Can.Binop "*" Basics "mul" ...
      (Can.Float 3.14)
      (Can.Int 10))
    (Can.Int 10)

Optimize:
  Opt.Call (VarGlobal Basics "mul")
    [Opt.Call (VarGlobal Basics "mul")
      [Opt.Float 3.14, Opt.Int 10],
     Opt.Int 10]
  ❌ No optimization (generic Call nodes)

CodeGen: 3.14 * 10 * 10

Runtime: JavaScript computes 3.14 * 10 = 31.4, then 31.4 * 10 = 314.0
         ^^^^^^^^^^^^^^^^^^^^^^^^ WASTED WORK
```

### With Native Operators

```
Source:  area = 3.14 * 10 * 10

Parse:   (same)

Canonical: (same)

Optimize:
  Opt.Binop OpMul (Opt.Float 3.14) (Opt.Int 10)
  ✅ Fold: Opt.Float 31.4
  
  Opt.Binop OpMul (Opt.Float 31.4) (Opt.Int 10)
  ✅ Fold: Opt.Float 314.0

CodeGen: 314.0

Runtime: (no computation needed!)
         ^^^^^^^^^^^^^^^^^^^ OPTIMAL
```

**Improvement**: ∞ (no runtime operations vs 2 multiplications)

---

## Implementation Strategy

### Phase 1: Add Opt.Binop Node (Week 1)

```diff
  -- File: AST/Optimized.hs
  data Expr
    = ...
    | Call Expr [Expr]
+   | Binop BinopKind Expr Expr

+ data BinopKind
+   = OpAdd | OpSub | OpMul | OpFDiv | OpIDiv
+   | OpEq | OpNeq | OpLt | OpGt | OpLe | OpGe
+   | OpAnd | OpOr | OpXor | OpAppend | OpPow
```

### Phase 2: Modify Optimization (Week 1)

```diff
  -- File: Optimize/Expression.hs
  optimize cycle (Can.Binop _ home name _ left right) = do
    optLeft <- optimize cycle left
    optRight <- optimize cycle right
-   optFunc <- Names.registerGlobal home name
-   return (Opt.Call optFunc [optLeft, optRight])
+   if isBuiltinOp home name
+     then return (Opt.Binop (toNativeOp name) optLeft optRight)
+     else do
+       optFunc <- Names.registerGlobal home name
+       return (Opt.Call optFunc [optLeft, optRight])
```

### Phase 3: Add Constant Folding (Week 2)

```diff
+ -- After creating Opt.Binop, try to fold
+ case (optLeft, optRight) of
+   (Opt.Int a, Opt.Int b) | op == OpAdd -> Opt.Int (a + b)
+   (Opt.Int a, Opt.Int b) | op == OpMul -> Opt.Int (a * b)
+   _ -> Opt.Binop op optLeft optRight
```

### Phase 4: Update Code Generation (Week 1)

```diff
  -- File: Generate/JavaScript/Expression.hs
  generate mode expression =
    case expression of
+     Opt.Binop op left right ->
+       JS.Infix (toJSOperator op) (generate left) (generate right)
      Opt.Call func args ->
-       -- Remove pattern matching for Basics operators
        generateCall mode func args
```

**Total Implementation Time**: 4 weeks

---

**Diagram Version**: 1.0  
**Created**: 2025-10-28
