# Plan 11: Advanced Optimization Passes

**Priority**: CRITICAL
**Effort**: Large (2-3 weeks)
**Risk**: Medium
**Audit Finding**: Missing constant folding for arithmetic, no identity elimination, no common subexpression elimination, no strength reduction

---

## Problem

Canopy has basic optimization passes (decision tree, expression, names) and a small constant folder, but significant optimization opportunities are missed:

1. **Arithmetic constant folding**: `5 + 3` compiles to `A2($elm$core$Basics$add, 5, 3)` instead of `8`
2. **Identity elimination**: `x + 0`, `x * 1`, `x ++ ""` are not simplified
3. **Dead code elimination**: Unused let-bindings in the generated output
4. **Common subexpression elimination**: Repeated computations not deduplicated
5. **Strength reduction**: `x * 2` could be `x + x` or `x << 1`
6. **Boolean simplification**: `True && x` is not simplified to `x`
7. **String concatenation folding**: `"hello" ++ " " ++ "world"` not folded

**Impact**: For constant-heavy code, the output is 10-100x larger and slower than necessary.

---

## Solution

Implement comprehensive optimization passes in the `Optimize/` directory.

---

## Implementation

### Pass 1: Arithmetic Constant Folding

**File: `packages/canopy-core/src/Optimize/ConstantFold.hs`** (extend existing)

Evaluate pure arithmetic at compile time:

```haskell
-- | Fold constant arithmetic expressions.
foldArithmetic :: Opt.Expr -> Opt.Expr
foldArithmetic expr =
  case expr of
    -- Int operations
    Opt.Call (Opt.VarGlobal basics "add") [Opt.Int a, Opt.Int b] ->
      Opt.Int (a + b)
    Opt.Call (Opt.VarGlobal basics "sub") [Opt.Int a, Opt.Int b] ->
      Opt.Int (a - b)
    Opt.Call (Opt.VarGlobal basics "mul") [Opt.Int a, Opt.Int b] ->
      Opt.Int (a * b)
    -- Float operations
    Opt.Call (Opt.VarGlobal basics "add") [Opt.Float a, Opt.Float b] ->
      Opt.Float (a + b)
    -- Division (guard against divide-by-zero)
    Opt.Call (Opt.VarGlobal basics "idiv") [Opt.Int a, Opt.Int b]
      | b /= 0 -> Opt.Int (a `div` b)
    -- Modulo
    Opt.Call (Opt.VarGlobal basics "modBy") [Opt.Int a, Opt.Int b]
      | a /= 0 -> Opt.Int (b `mod` a)
    -- Negate
    Opt.Call (Opt.VarGlobal basics "negate") [Opt.Int a] ->
      Opt.Int (negate a)
    Opt.Call (Opt.VarGlobal basics "negate") [Opt.Float a] ->
      Opt.Float (negate a)
    -- String concatenation
    Opt.Call (Opt.VarGlobal basics "append") [Opt.Str a, Opt.Str b] ->
      Opt.Str (a <> b)
    -- No match: return unchanged
    _ -> expr
```

### Pass 2: Identity Elimination

```haskell
-- | Eliminate identity operations.
eliminateIdentity :: Opt.Expr -> Opt.Expr
eliminateIdentity expr =
  case expr of
    -- x + 0 = x
    Opt.Call (Opt.VarGlobal basics "add") [x, Opt.Int 0] -> x
    Opt.Call (Opt.VarGlobal basics "add") [Opt.Int 0, x] -> x
    -- x - 0 = x
    Opt.Call (Opt.VarGlobal basics "sub") [x, Opt.Int 0] -> x
    -- x * 1 = x
    Opt.Call (Opt.VarGlobal basics "mul") [x, Opt.Int 1] -> x
    Opt.Call (Opt.VarGlobal basics "mul") [Opt.Int 1, x] -> x
    -- x * 0 = 0
    Opt.Call (Opt.VarGlobal basics "mul") [_, Opt.Int 0] -> Opt.Int 0
    Opt.Call (Opt.VarGlobal basics "mul") [Opt.Int 0, _] -> Opt.Int 0
    -- x ++ "" = x
    Opt.Call (Opt.VarGlobal basics "append") [x, Opt.Str ""] -> x
    Opt.Call (Opt.VarGlobal basics "append") [Opt.Str "", x] -> x
    -- True && x = x
    Opt.Call (Opt.VarGlobal basics "and") [Opt.Bool True, x] -> x
    Opt.Call (Opt.VarGlobal basics "and") [x, Opt.Bool True] -> x
    -- False && x = False
    Opt.Call (Opt.VarGlobal basics "and") [Opt.Bool False, _] -> Opt.Bool False
    -- True || x = True
    Opt.Call (Opt.VarGlobal basics "or") [Opt.Bool True, _] -> Opt.Bool True
    -- False || x = x
    Opt.Call (Opt.VarGlobal basics "or") [Opt.Bool False, x] -> x
    -- not (not x) = x
    Opt.Call (Opt.VarGlobal basics "not") [Opt.Call (Opt.VarGlobal basics "not") [x]] -> x
    -- identity function
    Opt.Call (Opt.VarGlobal basics "identity") [x] -> x
    _ -> expr
```

### Pass 3: Boolean Simplification

```haskell
-- | Simplify boolean-heavy expressions.
simplifyBooleans :: Opt.Expr -> Opt.Expr
simplifyBooleans expr =
  case expr of
    -- if True then a else b = a
    Opt.If [(Opt.Bool True, thenBranch)] _ -> thenBranch
    -- if False then a else b = b
    Opt.If [(Opt.Bool False, _)] elseBranch -> elseBranch
    -- if c then True else False = c
    Opt.If [(cond, Opt.Bool True)] (Opt.Bool False) -> cond
    -- if c then False else True = not c
    Opt.If [(cond, Opt.Bool False)] (Opt.Bool True) ->
      Opt.Call (Opt.VarGlobal basics "not") [cond]
    _ -> expr
```

### Pass 4: Dead Let-Binding Elimination

```haskell
-- | Remove let-bindings whose bound variable is never referenced.
eliminateDeadBindings :: Opt.Expr -> Opt.Expr
eliminateDeadBindings expr =
  case expr of
    Opt.Let def body
      | not (isUsed (defName def) body) && isPure (defBody def) ->
          eliminateDeadBindings body
    _ -> expr

-- | Check if a name is used within an expression.
isUsed :: Name -> Opt.Expr -> Bool
isUsed name = go
  where
    go = \case
      Opt.VarLocal n -> n == name
      Opt.VarGlobal _ _ -> False
      Opt.Call fn args -> go fn || any go args
      Opt.If branches elseExpr ->
        any (\(c, b) -> go c || go b) branches || go elseExpr
      Opt.Let def body -> go (defBody def) || go body
      Opt.Case _ _ branches _ -> any (go . branchBody) branches
      _ -> False

-- | Check if an expression is pure (no side effects).
isPure :: Opt.Expr -> Bool
isPure = \case
  Opt.Int _ -> True
  Opt.Float _ -> True
  Opt.Str _ -> True
  Opt.Chr _ -> True
  Opt.Bool _ -> True
  Opt.VarLocal _ -> True
  Opt.VarGlobal _ _ -> True
  Opt.Call fn args -> isPure fn && all isPure args
  _ -> False
```

### Pass 5: Common Subexpression Elimination (CSE)

```haskell
-- | Detect and eliminate common subexpressions within a function body.
-- If the same pure expression appears multiple times, extract it
-- into a let-binding and reference it.
eliminateCSE :: Opt.Expr -> Opt.Expr
eliminateCSE expr =
  extractCommonSubexprs (findDuplicateExprs expr) expr

-- | Find expressions that appear more than once.
findDuplicateExprs :: Opt.Expr -> Map Opt.Expr Int
findDuplicateExprs = go Map.empty
  where
    go counts expr =
      case expr of
        Opt.Call fn args | isPure expr ->
          let counts' = Map.insertWith (+) expr 1 counts
          in foldl' go counts' (fn : args)
        _ -> foldSubExprs (go counts) expr

-- | Extract duplicated expressions into let-bindings.
extractCommonSubexprs :: Map Opt.Expr Int -> Opt.Expr -> Opt.Expr
extractCommonSubexprs duplicates expr =
  foldr wrapWithLet (replaceWithVars duplicateList expr) duplicateList
  where
    duplicateList = Map.toList (Map.filter (> 1) duplicates)
    wrapWithLet (subExpr, _) body = Opt.Let (freshDef subExpr) body
    replaceWithVars dups e = foldr replaceOne e dups
```

### Pass 6: Orchestration

**File: `packages/canopy-core/src/Optimize/Module.hs`**

Add the new passes to the optimization pipeline:

```haskell
optimizeExpression :: Opt.Expr -> Opt.Expr
optimizeExpression =
  -- Run passes in order, iterated until fixpoint
  fixpoint
    ( foldArithmetic
    . eliminateIdentity
    . simplifyBooleans
    . eliminateDeadBindings
    . eliminateCSE
    )

-- | Iterate passes until the expression stops changing.
fixpoint :: (Opt.Expr -> Opt.Expr) -> Opt.Expr -> Opt.Expr
fixpoint f expr =
  let result = f expr
  in if result == expr then expr else fixpoint f result
```

---

## Testing

### Unit Tests

```haskell
testConstantFolding :: TestTree
testConstantFolding = testGroup "Constant Folding"
  [ testCase "5 + 3 = 8" $
      foldArithmetic (call add [int 5, int 3]) @?= int 8
  , testCase "5 * 0 = 0" $
      eliminateIdentity (call mul [int 5, int 0]) @?= int 0
  , testCase "x + 0 = x" $
      eliminateIdentity (call add [var "x", int 0]) @?= var "x"
  , testCase "\"a\" ++ \"b\" = \"ab\"" $
      foldArithmetic (call append [str "a", str "b"]) @?= str "ab"
  , testCase "if True then a else b = a" $
      simplifyBooleans (ifExpr (bool True) (var "a") (var "b")) @?= var "a"
  ]
```

### Property Tests

```haskell
prop_foldingPreservesSemantics :: Int -> Int -> Property
prop_foldingPreservesSemantics a b =
  evaluate (foldArithmetic (call add [int a, int b])) === a + b

prop_identityIsIdempotent :: Opt.Expr -> Property
prop_identityIsIdempotent expr =
  eliminateIdentity (eliminateIdentity expr) === eliminateIdentity expr
```

### Golden Tests

Update JS generation golden tests to reflect optimized output.

---

## Validation

```bash
make build
make test

# Benchmark optimization impact
make bench

# Verify golden test output
stack test --ta="--pattern JsGen"
```

---

## Success Criteria

- [ ] `5 + 3` compiles to `8` (not `A2($elm$core$Basics$add, 5, 3)`)
- [ ] `x + 0` compiles to `x`
- [ ] `x * 1` compiles to `x`
- [ ] `"a" ++ "b"` compiles to `"ab"`
- [ ] `if True then a else b` compiles to `a`
- [ ] `not (not x)` compiles to `x`
- [ ] Dead let-bindings removed
- [ ] Common subexpressions extracted
- [ ] All existing tests pass (golden tests updated)
- [ ] Benchmark: 10%+ output size reduction on typical programs
- [ ] `make build` passes with zero warnings
