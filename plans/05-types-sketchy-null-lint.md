# Plan 05: Sketchy-Null & Unsafe Operations Lint

**Priority**: HIGH
**Effort**: Small (1-2 days)
**Risk**: Low
**Audit Finding**: No lint-level safety checks for common error patterns that Flow catches

---

## Problem

Flow provides a family of lint rules that catch subtle bugs:
- **sketchy-null**: Truthiness checks on nullable numbers/strings where `0` or `""` are valid
- **unsafe-addition**: `null + number` or `undefined + number`
- **unused-promise**: Floating promises with unhandled errors
- **unnecessary-optional-chain**: `?.` on non-nullable values

Canopy has no equivalent. While Canopy's type system prevents many of these at the language level (no null, Maybe-based), there are Canopy-specific equivalents that should be caught.

---

## Canopy-Specific Lint Targets

### 1. Sketchy Maybe Checks

```elm
-- SKETCHY: Maybe Int where 0 is valid
isActive : Maybe Int -> Bool
isActive count =
  case count of
    Just n -> n /= 0    -- Bug: treats 0 as "inactive"
    Nothing -> False

-- Should warn: "Checking Maybe Int for truthiness may treat 0 as Nothing"
```

### 2. Redundant Maybe Wrapping

```elm
-- UNNECESSARY: wrapping a value that's never Nothing
alwaysJust : Int -> Maybe Int
alwaysJust x = Just x  -- The Maybe adds no information
```

### 3. Unnecessary Pattern Match

```elm
-- REDUNDANT: matching on a type with one constructor
case unit of
  () -> doSomething  -- This case can never fail
```

### 4. Unsafe String Operations

```elm
-- SKETCHY: String.toInt without handling failure
process : String -> Int
process input =
  case String.toInt input of
    Just n -> n
    Nothing -> 0  -- Silent fallback hides bugs
```

### 5. Comparison of Incompatible Types

```elm
-- ALWAYS FALSE: comparing values of different custom types
type Color = Red | Blue
type Size = Small | Large

isSame = (Red == Small)  -- Always False, but compiles in Elm
```

### 6. Dead Code After Case

```elm
-- UNREACHABLE: code after exhaustive case with returns
handleResult result =
  case result of
    Ok val -> val
    Err msg -> defaultValue
  -- This line is unreachable (both branches return)
  Debug.log "done" ()
```

---

## Implementation

### Step 1: Create Lint Infrastructure

**File: `packages/canopy-core/src/Lint/Analysis.hs`** (new)

```haskell
-- | Post-type-check lint analysis.
-- Runs after successful type checking to detect patterns that are
-- technically valid but likely indicate bugs.
module Lint.Analysis
  ( LintWarning (..)
  , LintConfig (..)
  , runLintAnalysis
  ) where

-- | Warning categories with severity levels.
data LintWarning
  = SketchyMaybeCheck !Region !Type
    -- ^ Truthiness check on Maybe where inner type has a meaningful zero
  | RedundantMaybeWrap !Region !Name
    -- ^ Function always returns Just, never Nothing
  | UnnecessaryPatternMatch !Region
    -- ^ Case on a single-constructor type
  | SilentFallback !Region !Text
    -- ^ Error branch returns a default instead of propagating
  | AlwaysFalseComparison !Region !Type !Type
    -- ^ Comparing values of incompatible types
  | UnreachableCode !Region
    -- ^ Code after exhaustive case/if returns
  | RedundantCaseBranch !Region
    -- ^ Branch that can never match
  deriving (Eq, Show)

-- | Lint configuration (which warnings to enable/disable).
data LintConfig = LintConfig
  { _lintSketchyMaybe :: !Bool
  , _lintRedundantWrap :: !Bool
  , _lintUnnecessaryMatch :: !Bool
  , _lintSilentFallback :: !Bool
  , _lintAlwaysFalse :: !Bool
  , _lintUnreachable :: !Bool
  }

-- | Run all enabled lint checks on a type-checked module.
runLintAnalysis :: LintConfig -> Can.Module -> Annotations -> [LintWarning]
```

### Step 2: Implement Each Lint Rule

**Sketchy Maybe Check:**

```haskell
-- | Detect case-on-Maybe where the inner type has a meaningful zero.
-- Types with meaningful zeros: Int (0), Float (0.0), String (""), List ([])
checkSketchyMaybe :: Can.Expr -> Annotations -> [LintWarning]
checkSketchyMaybe expr annotations =
  case expr of
    Can.Case scrutinee branches ->
      maybe [] (checkMaybeScrutinee region branches) (getMaybeInnerType scrutinee annotations)
    _ -> []

hasMeaningfulZero :: Type -> Bool
hasMeaningfulZero = \case
  IntType -> True
  FloatType -> True
  StringType -> True
  ListType _ -> True
  _ -> False
```

**Always-False Comparison:**

```haskell
-- | Detect == between incompatible custom types.
checkAlwaysFalseComparison :: Can.Expr -> Annotations -> [LintWarning]
checkAlwaysFalseComparison expr annotations =
  case expr of
    Can.Binop "==" _ left right ->
      incompatibleCheck (typeOf left) (typeOf right) (regionOf expr)
    _ -> []

incompatibleCheck :: Type -> Type -> Region -> [LintWarning]
incompatibleCheck leftType rightType region
  | isCustomType leftType && isCustomType rightType
  , typeName leftType /= typeName rightType =
      [AlwaysFalseComparison region leftType rightType]
  | otherwise = []
```

**Unreachable Code:**

```haskell
-- | Detect code after exhaustive case/if where all branches return.
checkUnreachableCode :: [Can.Def] -> [LintWarning]
checkUnreachableCode defs =
  concatMap checkDefBody defs

checkDefBody :: Can.Def -> [LintWarning]
checkDefBody def =
  case bodyStatements def of
    stmts | hasExhaustiveReturn stmts -> checkAfterReturn stmts
    _ -> []
```

### Step 3: Integrate Into Pipeline

**File: `packages/canopy-core/src/Canopy/Compiler/Imports.hs`** (or wherever module compilation is orchestrated)

Add lint pass after type checking:

```haskell
compileModule :: ... -> IO (Either [Error] (Module, [Warning]))
compileModule ... = do
  -- Existing pipeline
  canonical <- canonicalize ...
  (annotations, typeWarnings) <- typeCheck canonical
  optimized <- optimize canonical annotations

  -- NEW: lint analysis
  lintWarnings <- runLintAnalysis defaultLintConfig canonical annotations

  pure (Right (optimized, typeWarnings ++ map toLintWarning lintWarnings))
```

### Step 4: Error Formatting

**File: `packages/canopy-core/src/Reporting/Warning/Lint.hs`** (new)

```haskell
-- | Format lint warnings with helpful suggestions.
--
-- Example output:
--
-- @
-- -- LINT WARNING - src/Main.can:23:5
--
-- This case expression on `Maybe Int` may silently treat 0 as Nothing:
--
--   23|  case maybeCount of
--   24|    Just n -> n > 0
--   25|    Nothing -> False
--
-- The value 0 is falsey but may be a valid count. Consider:
--
--   case maybeCount of
--     Just n -> n >= 1  -- explicitly check the threshold
--     Nothing -> False
-- @
formatLintWarning :: LintWarning -> Doc
```

---

## Configuration

Add lint configuration to `canopy.json`:

```json
{
  "lint": {
    "sketchy-maybe": "warning",
    "redundant-wrap": "off",
    "unnecessary-match": "warning",
    "silent-fallback": "warning",
    "always-false": "error",
    "unreachable": "error"
  }
}
```

---

## Validation

```bash
make build
make test

# Run lint on the compiler itself
canopy lint packages/canopy-core/src/
```

---

## Success Criteria

- [ ] 6 lint rules implemented and configurable
- [ ] Each rule has 5+ test cases
- [ ] Lint warnings include suggestions for fixing
- [ ] Lint rules configurable in canopy.json (warning/error/off)
- [ ] `canopy lint` command works on any project
- [ ] `make build` passes with zero warnings
- [ ] `make test` passes
