# Plan 03: Nested Case Violation Fixes

**Priority**: HIGH
**Effort**: Small (1 day)
**Risk**: Low
**Audit Finding**: 8+ nested case violations in Generate/JavaScript/Expression/Case.hs, plus violations in Type/Unify.hs, Canonicalize/Expression.hs, Canopy/Docs.hs

---

## Problem

CLAUDE.md line 146 states: "Nested case expressions are strictly forbidden. This rule has no exceptions."

The codebase's most critical modules violate this rule:
- `Generate/JavaScript/Expression/Case.hs`: 8+ violations (lines 79-268)
- `Type/Unify.hs`: 4+ violations (lines 453-470, 539-552)
- `Canonicalize/Expression.hs`: 2 violations (lines 261-268)
- `Canopy/Docs.hs`: 3+ violations (lines 227-278)

The compiler does not follow its own coding standards.

---

## Solution

Extract nested cases into named helper functions, use `maybe`/`either`/`LambdaCase`, or refactor to monadic composition.

---

## Implementation

### File 1: `Generate/JavaScript/Expression/Case.hs`

**Lines 92-98: Nested case in decision tree generation**

Before:
```haskell
case decisionTree of
  Leaf _ -> ...
  Chain _ _ _ -> ...
  FanOut _ edges _ ->
    case edges of
      [] -> ...
      (e:es) -> ...
```

After — extract helper:
```haskell
case decisionTree of
  Leaf _ -> ...
  Chain _ _ _ -> ...
  FanOut _ edges _ -> generateFanOut edges

generateFanOut :: [Edge] -> Builder
generateFanOut = \case
  [] -> ...
  (e:es) -> ...
```

**Lines 112-125: Triple-nested case (mode → opts)**

Before:
```haskell
case test of
  IsBool -> ...
  IsInt -> ...
  IsChr ->
    case mode of
      Dev _ ->
        case opts of
          Nothing -> ...
          Just x -> ...
      Prod -> ...
```

After — extract helper with pattern matching:
```haskell
case test of
  IsBool -> ...
  IsInt -> ...
  IsChr -> generateChrTest mode opts

generateChrTest :: Mode -> Maybe Opts -> Builder
generateChrTest (Dev _) Nothing = ...
generateChrTest (Dev _) (Just x) = ...
generateChrTest Prod _ = ...
```

Apply same pattern to all 8 violations in this file. Each nested case becomes a named function with the outer matches as parameters.

### File 2: `Type/Unify.hs`

**Lines 453-470: Triple-nested case in unifyAliasArgs**

Before:
```haskell
case args1 of
  (_, arg1) : others1 ->
    case args2 of
      (_, arg2) : others2 ->
        case subUnify arg1 arg2 of
          Unify k -> ...
      _ -> err vars ()
  [] ->
    case args2 of
      [] -> ok vars ()
      _ -> err vars ()
```

After — use helper with tuple matching:
```haskell
unifyAliasArgs vars context args1 args2 ok err =
  matchArgPairs vars context (zip' args1 args2) ok err

matchArgPairs vars context pairs ok err =
  case pairs of
    Just ((arg1, arg2), rest1, rest2) ->
      unifyOnePair vars context arg1 arg2 rest1 rest2 ok err
    Nothing
      | null args1 && null args2 -> ok vars ()
      | otherwise -> err vars ()

unifyOnePair vars context arg1 arg2 rest1 rest2 ok err =
  case subUnify arg1 arg2 of
    Unify k ->
      k vars
        (\vs () -> matchArgPairs vs context rest1 rest2 ok err)
        (\vs () -> matchArgPairs vs context rest1 rest2 err err)
```

**Lines 539-552: Same pattern, same fix.**

### File 3: `Canonicalize/Expression.hs`

**Lines 261-268: Nested case in binop handling**

Before:
```haskell
case lookupBinop name env of
  Nothing -> ...
  Just info ->
    case associativity info of
      Left -> ...
      Right -> ...
```

After — use `maybe` + helper:
```haskell
maybe
  (handleMissingBinop name)
  (handleBinopInfo env)
  (lookupBinop name env)

handleBinopInfo :: Env -> BinopInfo -> Result
handleBinopInfo env info =
  case associativity info of
    Left -> ...
    Right -> ...
```

### File 4: `Canopy/Docs.hs`

**Lines 227-278: Nested cases in export validation**

Extract each inner case into a named validation function:

```haskell
-- Before: nested case inside case
checkExport export info =
  case export of
    Value name ->
      case Map.lookup name info of
        Nothing -> ...
        Just val -> ...
    Union name ->
      case Map.lookup name unions of
        Nothing -> ...
        Just union -> ...

-- After: named helpers
checkExport export info =
  case export of
    Value name -> checkValueExport name info
    Union name -> checkUnionExport name unions

checkValueExport :: Name -> Map Name Info -> Either Error Doc
checkValueExport name info =
  maybe (Left (missingValue name)) Right (Map.lookup name info)

checkUnionExport :: Name -> Map Name Union -> Either Error Doc
checkUnionExport name unions =
  maybe (Left (missingUnion name)) Right (Map.lookup name unions)
```

---

## Validation

```bash
# Build
make build

# Tests pass
make test

# Verify no nested cases remain
# Search for case-inside-case patterns (manual review)
grep -n "case " packages/canopy-core/src/Generate/JavaScript/Expression/Case.hs | wc -l
# Should be significantly reduced

grep -n "case " packages/canopy-core/src/Type/Unify.hs | wc -l
# Should be reduced by 6-8 lines
```

---

## Success Criteria

- [ ] Zero nested case expressions in `Generate/JavaScript/Expression/Case.hs`
- [ ] Zero nested case expressions in `Type/Unify.hs`
- [ ] Zero nested case expressions in `Canonicalize/Expression.hs`
- [ ] Zero nested case expressions in `Canopy/Docs.hs`
- [ ] All extracted helper functions are <= 15 lines
- [ ] `make build` passes with zero warnings
- [ ] `make test` passes (3350+ tests)
- [ ] Behavior is identical (no logic changes, only structural refactoring)
