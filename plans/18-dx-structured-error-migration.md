# Plan 18: Legacy String Error Types Migration

**Priority:** CRITICAL
**Effort:** Medium (1-2d)
**Risk:** Medium -- Incremental migration path, but touches many call sites

## Problem

The build system uses raw `String` error types in multiple places while a structured `Diagnostic` type already exists. This means errors from the build pipeline lose source locations, error codes, suggestions, and colored rendering -- producing flat, unhelpful messages instead of the rich diagnostics the compiler is capable of.

### String-Based Error Types

**File:** `/home/quinten/fh/canopy/packages/canopy-builder/src/Builder.hs` (lines 97-102)

```haskell
data BuildError
  = BuildErrorSolver !Solver.SolverError
  | BuildErrorCycle ![ModuleName.Raw]
  | BuildErrorMissing ![ModuleName.Raw]
  | BuildErrorCompile !String    -- <-- RAW STRING
  deriving (Show, Eq)
```

`BuildErrorCompile` wraps a raw `String` -- all structured error information from the compiler is flattened via `show`.

**File:** `/home/quinten/fh/canopy/packages/canopy-builder/src/Exit.hs` (lines 42-55)

```haskell
data CompileError
  = CompileParseError FilePath String        -- <-- RAW STRING
  | CompileTypeError FilePath String          -- <-- RAW STRING
  | CompileCanonicalizeError FilePath String  -- <-- RAW STRING
  | CompileOptimizeError FilePath String      -- <-- RAW STRING
  | CompileModuleNotFound FilePath
  | CompileDiagnosticError FilePath [Diagnostic]  -- <-- STRUCTURED (correct!)
  | CompileTimeoutError FilePath
  | CompileFileTooLarge FilePath Int Int
  deriving (Show)
```

Four out of eight `CompileError` constructors use `String` instead of `[Diagnostic]`. The `CompileDiagnosticError` constructor already demonstrates the correct pattern.

**File:** `/home/quinten/fh/canopy/packages/canopy-builder/src/Exit.hs` (lines 58-63)

```haskell
data MakeError
  = MakeBuildError String   -- <-- RAW STRING
  | MakeBadGenerate String  -- <-- RAW STRING
  | MakeNoMain
  | MakeMultipleFilesIntoHtml
  deriving (Show)
```

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Reporting/Exit.hs` (lines 201-214)

```haskell
data Make
  = MakeNoOutline
  | MakeBadDetails FilePath
  | MakeBuildError String     -- <-- RAW STRING
  | MakeBadGenerate String    -- <-- RAW STRING
  | ...
```

**File:** `/home/quinten/fh/canopy/packages/canopy-builder/src/Builder.hs` (lines 214-220)

Error information is discarded via `show` at multiple sites:
```haskell
parseAllModules :: [FilePath] -> IO (Either String [(FilePath, Src.Module)])
-- Returns Either String instead of Either [Diagnostic] ...

Left ("Parse errors: " ++ show (length errors))  -- line 220
```

Line 233: `Left (path ++ ": " ++ show parseErr)` -- structured parse error flattened to string.

Line 211: `BuildErrorCompile (show (length failures) ++ " modules failed")` -- count turned into string.

Line 297-298: `let errStr = show err` followed by `BuildErrorCompile errStr` -- `QueryError` (which may contain diagnostics) flattened.

### The Structured Diagnostic Type (Already Exists)

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Reporting/Diagnostic.hs` (lines 160-171)

```haskell
data Diagnostic = Diagnostic
  { _diagCode :: !ErrorCode,
    _diagSeverity :: !Severity,
    _diagTitle :: !Text,
    _diagSummary :: !Text,
    _diagPrimary :: !LabeledSpan,
    _diagSecondary :: ![LabeledSpan],
    _diagMessage :: !Doc.Doc,
    _diagSuggestions :: ![Suggestion],
    _diagNotes :: ![Text],
    _diagPhase :: !Phase
  }
```

This type supports error codes (`E0401`), multi-span labels, suggestions with confidence levels, JSON encoding, and colored terminal rendering. It is already used in `CompileDiagnosticError`.

### Rendering Side

**File:** `/home/quinten/fh/canopy/packages/canopy-builder/src/Exit.hs` (lines 141-184)

The `compileErrorToDoc` function has separate branches for legacy string errors vs. diagnostic errors:
```haskell
compileErrorToDoc = \case
  CompileParseError path msg ->
    legacyErrorDoc "Parse error" path msg        -- FLAT: no error code, no source snippet
  ...
  CompileDiagnosticError path diags ->
    renderDiagnostics path diags                  -- RICH: error codes, spans, suggestions
```

The `legacyErrorDoc` function (line 178) produces a plain, unstructured error:
```haskell
legacyErrorDoc label path msg =
  Doc.vcat
    [ Doc.reflow (label ++ " in " ++ path ++ ":"),
      "",
      Doc.indent 4 (Doc.dullyellow (Doc.fromChars msg))
    ]
```

## Proposed Solution

### Phase 1: Replace String Constructors with Diagnostic Lists

#### Step 1.1: Update CompileError in Exit.hs

**File:** `/home/quinten/fh/canopy/packages/canopy-builder/src/Exit.hs`

Replace the four string-based constructors with `[Diagnostic]`:

```haskell
-- Before:
data CompileError
  = CompileParseError FilePath String
  | CompileTypeError FilePath String
  | CompileCanonicalizeError FilePath String
  | CompileOptimizeError FilePath String
  | CompileModuleNotFound FilePath
  | CompileDiagnosticError FilePath [Diagnostic]
  | CompileTimeoutError FilePath
  | CompileFileTooLarge FilePath Int Int

-- After:
data CompileError
  = CompileError FilePath [Diagnostic]
  | CompileModuleNotFound FilePath
  | CompileTimeoutError FilePath
  | CompileFileTooLarge FilePath Int Int
```

This unifies all four legacy constructors into the single `CompileError` constructor, mirroring `CompileDiagnosticError` but with a clearer name.

#### Step 1.2: Update BuildError in Builder.hs

**File:** `/home/quinten/fh/canopy/packages/canopy-builder/src/Builder.hs`

```haskell
-- Before:
  | BuildErrorCompile !String

-- After:
  | BuildErrorCompile ![Diagnostic]
```

#### Step 1.3: Update MakeError in Exit.hs

```haskell
-- Before:
  = MakeBuildError String
  | MakeBadGenerate String

-- After:
  = MakeBuildError [Diagnostic]
  | MakeBadGenerate [Diagnostic]
```

### Phase 2: Convert Error Production Sites

#### Step 2.1: Builder.hs Error Sites

**File:** `/home/quinten/fh/canopy/packages/canopy-builder/src/Builder.hs`

Line 220 -- `parseAllModules`:
```haskell
-- Before:
Left ("Parse errors: " ++ show (length errors))

-- After: Convert parse errors to diagnostics
Left (concatMap parseErrorToDiagnostic errors)
```

Line 233 -- `parseModuleFromPath`:
```haskell
-- Before:
Left (path ++ ": " ++ show parseErr)

-- After: Convert syntax error to diagnostic
Left [syntaxErrorToDiagnostic path parseErr]
```

Line 297 -- `compileWithDriver`:
```haskell
-- Before:
let errStr = show err
BuildErrorCompile errStr

-- After: Extract diagnostics from QueryError
BuildErrorCompile (queryErrorToDiagnostics err)
```

#### Step 2.2: Add Conversion Functions

**File:** `/home/quinten/fh/canopy/packages/canopy-builder/src/Exit.hs` (new functions)

```haskell
-- Convert a syntax error to a Diagnostic
syntaxErrorToDiagnostic :: FilePath -> SyntaxError.Error -> Diagnostic
syntaxErrorToDiagnostic path err =
  makeSimpleDiagnostic
    (ErrorCode 100)
    PhaseParse
    "SYNTAX ERROR"
    (extractRegion err)
    (SyntaxError.toDoc path err)

-- Convert QueryError to Diagnostics
queryErrorToDiagnostics :: QueryError -> [Diagnostic]
queryErrorToDiagnostics (ParseError path err) = [syntaxErrorToDiagnostic path err]
queryErrorToDiagnostics (TypeError path err) = [typeErrorToDiagnostic path err]
queryErrorToDiagnostics (TimeoutError path) = [timeoutDiagnostic path]
...
```

### Phase 3: Update Rendering

#### Step 3.1: Simplify compileErrorToDoc

**File:** `/home/quinten/fh/canopy/packages/canopy-builder/src/Exit.hs`

```haskell
-- Before: 7 branches with mixed rendering
compileErrorToDoc = \case
  CompileParseError path msg -> legacyErrorDoc "Parse error" path msg
  CompileTypeError path msg -> legacyErrorDoc "Type error" path msg
  ...

-- After: Unified rendering through Diagnostic
compileErrorToDoc = \case
  CompileError path diags -> renderDiagnostics path diags
  CompileModuleNotFound path -> moduleNotFoundDoc path
  CompileTimeoutError path -> timeoutDoc path
  CompileFileTooLarge path actual limit -> fileTooLargeDoc path actual limit
```

The `legacyErrorDoc` function can then be removed.

### Phase 4: Update Terminal Exit Types

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Reporting/Exit.hs`

Lines 201-228 -- update `Make` and `makeToReport` to use `[Diagnostic]` instead of `String`:

```haskell
-- Before:
  | MakeBuildError String

-- After:
  | MakeBuildError [Diagnostic]
```

Similarly for `Repl`, `Check`, `Docs`, and other terminal error types that wrap `BuildError` or `String`.

## Files to Modify

| File | Change | Lines |
|------|--------|-------|
| `packages/canopy-builder/src/Exit.hs` | Replace 4 String constructors with Diagnostic, remove legacyErrorDoc | 42-184 |
| `packages/canopy-builder/src/Builder.hs` | Change BuildErrorCompile from String to [Diagnostic]; update all error sites | 97-298 |
| `packages/canopy-terminal/src/Reporting/Exit.hs` | Update Make, Repl, Check types from String to [Diagnostic] | 201-243 |
| `packages/canopy-terminal/src/Make.hs` | Update callers that construct MakeBuildError | N/A |
| `packages/canopy-terminal/src/Make/Builder.hs` | Update callers that handle BuildError | N/A |
| `packages/canopy-driver/src/Driver.hs` | Convert QueryError to [Diagnostic] at the boundary | 180-214 |
| `packages/canopy-core/src/Reporting/Diagnostic.hs` | Add helper constructors for common error patterns | 182-226 |

## Verification

```bash
# 1. All code must compile without warnings
make build 2>&1 | grep -c "warning" # should be 0

# 2. All existing tests pass
make test

# 3. Error output quality verification
# Create a file with a deliberate syntax error and verify the output has:
# - Error code (E0xxx)
# - Source snippet with underline
# - Suggestion
echo 'module Main exposing (..)
main = text "hello' > /tmp/err-test.can
# canopy make /tmp/err-test.can 2>&1 | grep -c "E0"  # should find error codes

# 4. JSON error output verification
# canopy make --report=json /tmp/err-test.can 2>&1 | python3 -m json.tool
# Should parse as valid JSON with "code", "severity", "primary" fields

# 5. Grep for remaining String errors
grep -r 'CompileParseError\|CompileTypeError\|CompileCanonicalizeError\|CompileOptimizeError' packages/ --include="*.hs"
# Should return 0 matches after migration
```

## Migration Order

1. Add conversion functions (`syntaxErrorToDiagnostic`, etc.) to `Exit.hs` -- zero breakage
2. Add new `CompileError` constructor alongside old ones -- zero breakage
3. Update `Builder.hs` error production sites one at a time -- incremental
4. Update `compileErrorToDoc` to handle new constructor -- incremental
5. Remove old String constructors once all producers are updated -- final cleanup
6. Update terminal `Exit.hs` types last -- depends on builder changes
