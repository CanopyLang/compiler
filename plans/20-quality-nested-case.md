# Plan 20: Nested Case Expression Elimination

**Priority:** MEDIUM
**Effort:** Large (3–5 days)
**Risk:** Medium — refactoring complex control flow

## Problem

CLAUDE.md explicitly forbids nested `case` expressions. The codebase has 100+ violations. The worst offenders:

| Nested Cases | File | Description |
|-------------|------|-------------|
| 23 | `Type/Unify.hs` | Deep nesting on type content, super types, merge results |
| 13 | `Optimize/DecisionTree.hs` | Patterns and test types |
| 10 | `Type/Type.hs` | Names, extensions, flat types |
| 10 | `Type/Error.hs` | Error status pairs, record diffs |
| 10 | `Optimize/Expression.hs` | Definitions, paths, expressions |
| 9 | `Canonicalize/Expression.hs` | Types, SCCs, bindings |
| 8 | `Generate/JavaScript/Expression/Call.hs` | Function types, modes, arguments |
| 7 | `Canonicalize/Effects.hs` | 5 levels deep at lines 74–114 |

## Refactoring Strategies

### For simple unwrapping: Use `maybe`, `either`, `bool`

```haskell
-- BEFORE:
case mx of
  Nothing -> default
  Just x -> case ey of
    Left e -> handleError e
    Right y -> process x y

-- AFTER:
maybe default (\x -> either handleError (process x) ey) mx
```

### For monadic composition: Use `MaybeT`, `ExceptT`

```haskell
-- BEFORE (Canonicalize/Effects.hs:74–114):
case reverse tipe of
  ...
    case revArgs of
      ...
        case msg of
          ...
            case checkPayload of ...

-- AFTER:
canonicalizePort env name tipe = runExceptT $ do
  (args, result) <- ExceptT (splitFunctionType tipe)
  msg <- extractMessage result
  ExceptT (validatePayload args msg)
```

### For complex branching: Extract named helper functions

```haskell
-- BEFORE (Type/Unify.hs):
case content of
  RigidVar name -> case otherContent of
    RigidVar otherName -> ...
    FlexVar _ -> ...
    _ -> mismatch

-- AFTER:
unifyWithRigid :: Name -> Content -> UnifyResult
unifyWithRigid name = \case
  RigidVar otherName -> ...
  FlexVar _ -> ...
  _ -> mismatch
```

### For pattern matching: Use `LambdaCase` and `ViewPatterns`

```haskell
-- BEFORE:
case expr of
  Var v -> case lookupVar env v of
    Just info -> ...
    Nothing -> ...

-- AFTER:
processExpr = \case
  Var (lookupVar env -> Just info) -> ...
  Var v -> handleUnknownVar v
  ...
```

## Files to Modify (Priority Order)

1. **`Canonicalize/Effects.hs`** — worst single instance (5 levels deep)
2. **`Type/Unify.hs`** — 23 instances, most impactful
3. **`Type/Type.hs`** — 10 instances
4. **`Type/Error.hs`** — 10 instances
5. **`Optimize/Expression.hs`** — 10 instances
6. **`Canonicalize/Expression.hs`** — 9 instances
7. **`Generate/JavaScript/Expression/Call.hs`** — 8 instances
8. **`Optimize/DecisionTree.hs`** — 13 instances
9. **`Nitpick/PatternMatches.hs`** — 6 instances
10. **`Generate/JavaScript/Expression/Case.hs`** — 5 instances

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Grep for `case.*of.*\n.*case.*of` patterns — count should be dramatically reduced
4. Each refactored function is ≤15 lines
