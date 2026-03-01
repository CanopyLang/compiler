# Plan 02: InternalError Crash Site Remediation

**Priority**: CRITICAL
**Effort**: Medium (2-3 days)
**Risk**: Low
**Audit Finding**: 88 `InternalError.report` crash sites; 45+ are recoverable dict-lookup errors

---

## Problem

`InternalError.report` calls `error` internally, which terminates the process. When the compiler encounters a state it doesn't expect (e.g., a module name not found in a dict), it crashes instead of producing an error message.

In CI pipelines, a compiler crash is catastrophic — it provides no actionable diagnostic, and the user sees a Haskell stack trace instead of a compiler error.

**88 total crash sites. ~45 are dict-lookup failures that should be recoverable.**

---

## Solution

Convert recoverable crash sites from `InternalError.report` to `Either`/`ExceptT` error propagation. Keep truly impossible states as crashes (with improved diagnostics).

---

## Classification

### Category A: Keep as Crashes (22 sites) — Truly Impossible States

These represent violated compiler invariants that indicate bugs in the compiler itself:

| File | Lines | Reason |
|------|-------|--------|
| `Parse/Primitives.hs` | 325, 332 | Invalid UTF-8 byte (already validated) |
| `Type/UnionFind.hs` | 198 | repr() returning Link (impossible by construction) |
| `Type/Type.hs` | 316, 343, 455 | Type variable binding invariants |
| `Optimize/Case.hs` | 62, 84, 123, 147, 168 | Empty decision tree edges |
| `AST/Canonical/Binary.hs` | 100 | Unknown binary tag |
| `AST/Optimized/Expr.hs` | 300 | Invalid optimized expression |
| `AST/Optimized/Graph.hs` | 290 | Invalid graph node |
| `Parse/Shader.hs` | 153 | Unexpected shader state |
| `Canonicalize/Module.hs` | 251 | Cycle detection invariant |
| `Terminal/Chomp/Types.hs` | 252 | Index invariant |

**Action:** Keep these as-is. Improve their diagnostic messages to include the actual invalid value.

### Category B: Convert to Recoverable Errors (45+ sites)

These are dict-lookup failures where a module, name, or type is expected to be in a map but isn't:

**Canopy/Docs.hs (6 sites):**
- Lines 442, 453, 463, 473, 492, 502
- Pattern: `maybe (InternalError.report ...) id (Map.lookup name info)`
- Fix: Return `Left DocError` instead of crashing

**Canopy/Compiler/Type/Extract.hs (4 sites):**
- Lines 147, 152, 165, 170
- Pattern: Module/alias/union not found in types dict
- Fix: Return `Left ExtractionError`

**Canopy/Interface.hs (2 sites):**
- Lines 89, 110
- Pattern: Binop annotation missing from values map
- Fix: Return `Left InterfaceError`

**Canopy/Kernel.hs (6 sites):**
- Lines 279, 310, 322, 341, 347, 380
- Pattern: Various kernel module lookups
- Fix: Return `Left KernelError`

**Optimize/Module.hs (2 sites):**
- Lines 183, 198
- Pattern: Annotation missing for definition
- Fix: Return `Left OptimizeError`

**Optimize/Port.hs (8 sites):**
- Lines 30, 35, 56, 61, 141, 146, 169, 174
- Pattern: Port type validation failures
- Fix: Return `Left PortError`

**Type/Instantiate.hs (2 sites):**
- Lines 33, 62
- Pattern: Type variable not in substitution map
- Fix: Return `Left InstantiateError`

**Type/Solve/Pool.hs (3 sites):**
- Lines 146, 219, 249
- Pattern: Pool state inconsistencies
- Fix: Return `Left SolveError`

**Generate/JavaScript/Expression.hs (2 sites):**
- Lines 372, 570
- Pattern: Field shortener map lookup failure
- Fix: Return `Left GenerateError`

**Generate/JavaScript/Expression/Case.hs (10 sites):**
- Lines 94, 145, 176, 181, 186, 191, 228, 233, 238, 243
- Pattern: Decision tree inconsistencies during JS generation
- Fix: Return `Left CaseGenerationError`

**Nitpick/PatternMatches.hs (5 sites):**
- Lines 316, 448, 453, 469, 474
- Pattern: Pattern analysis state assumptions
- Fix: Return `Left PatternAnalysisError`

---

## Implementation

### Step 1: Create Recoverable Error Types

Add error constructors to existing error types or create new ones:

```haskell
-- In Reporting/Error/Internal.hs (new module)
module Reporting.Error.Internal
  ( RecoverableError (..)
  , toReport
  ) where

-- | Errors that were previously crashes but are now recoverable.
-- These indicate compiler bugs but produce user-friendly diagnostics
-- instead of process termination.
data RecoverableError
  = MissingModuleInDict !Text !ModuleName.Canonical
  | MissingNameInDict !Text !Name.Name
  | MissingTypeInDict !Text !Name.Name !ModuleName.Canonical
  | InvalidDecisionTree !Text
  | PortValidationFailure !Text !Name.Name
  | PoolStateInconsistency !Text
  deriving (Eq, Show)

-- | Convert to a user-facing report with bug report instructions.
toReport :: RecoverableError -> Report.Report
toReport err =
  Report.Report "INTERNAL ERROR" region suggestions doc
  where
    ...
```

### Step 2: Convert Each Category B Site

For each site, the pattern is:

**Before:**
```haskell
processExport name info =
  maybe
    (InternalError.report "Canopy.Docs" "Binop missing" "...")
    processBinop
    (Map.lookup name info)
```

**After:**
```haskell
processExport :: Name -> Map Name Info -> Either RecoverableError Result
processExport name info =
  maybe
    (Left (MissingNameInDict "Canopy.Docs.processExport" name))
    (Right . processBinop)
    (Map.lookup name info)
```

### Step 3: Propagate Either Through Call Chains

Each converted function's callers must handle the `Either`. Use `ExceptT` for monadic chains:

```haskell
-- Before: IO Result
generateModule :: Module -> IO CompiledModule

-- After: IO (Either RecoverableError CompiledModule)
generateModule :: Module -> IO (Either RecoverableError CompiledModule)
```

At the top-level entry points (Make.hs, Build.hs), convert `RecoverableError` to a user-facing error message:

```haskell
case result of
  Left internalErr ->
    Reporting.report (Internal.toReport internalErr)
  Right compiled ->
    writeOutput compiled
```

### Step 4: Improve Category A Diagnostics

For the 22 true-impossible-state crashes, improve the messages to include the actual invalid value:

**Before:**
```haskell
InternalError.report
  "Type.UnionFind"
  "repr returning Link"
  "This should never happen."
```

**After:**
```haskell
InternalError.report
  "Type.UnionFind.repr"
  ("repr returned Link for variable " <> Text.pack (show varId))
  "Union-Find repr() should always return Root after path compression. This indicates a bug in the Union-Find implementation."
```

---

## Validation

```bash
# Build
make build

# All tests pass
make test

# Verify crash site count reduced
grep -rn "InternalError.report" packages/canopy-core/src/ | wc -l
# Should be ~22 (Category A only)

# Verify new error handling
grep -rn "RecoverableError\|Either.*RecoverableError" packages/canopy-core/src/ | wc -l
# Should be ~45+
```

---

## Success Criteria

- [ ] Category B sites (45+) converted from crash to `Either RecoverableError`
- [ ] Category A sites (22) have improved diagnostic messages with actual values
- [ ] All callers properly handle the new `Either` return types
- [ ] Top-level entry points display recoverable errors as user-friendly messages
- [ ] `make build` passes with zero warnings
- [ ] `make test` passes (3350+ tests)
- [ ] No compiler crash on any input that previously triggered a Category B site
