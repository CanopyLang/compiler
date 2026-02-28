# Plan 31: Error Type Consolidation

## Priority: MEDIUM
## Effort: Medium (2-3 days)
## Risk: Medium — touches error handling across the codebase

## Problem

Error types are scattered across multiple modules with inconsistent patterns:
- `Reporting.Exit` has a flat enum of exit codes
- `Reporting.Error.Syntax` has parse errors
- `Reporting.Error.Type` has type errors
- `Reporting.Error.Canonicalize` has name resolution errors
- Some modules use `Either String` instead of proper error types
- Some use `IOException` catching instead of structured errors

### Key Files
- `packages/canopy-core/src/Reporting/Exit.hs`
- `packages/canopy-core/src/Reporting/Error/Syntax.hs`
- `packages/canopy-core/src/Reporting/Error/Type.hs`
- `packages/canopy-builder/src/Builder/Incremental.hs` (uses `Either String`)

## Implementation Plan

### Step 1: Audit all error types

Map every error type and its usage across the codebase. Create a taxonomy:
- Compiler errors (syntax, type, canonicalize)
- Build errors (dependency, cache, IO)
- CLI errors (argument, configuration)
- FFI errors (validation, runtime)

### Step 2: Create unified error hierarchy

**File**: `packages/canopy-core/src/Reporting/Error.hs`

```haskell
data CompilerError
  = SyntaxError !SyntaxError
  | CanonicalizeError !CanonicalizeError
  | TypeError !TypeError
  | OptimizeError !OptimizeError
  | GenerateError !GenerateError
  | FFIError !FFIError

data BuildError
  = CompileError !CompilerError
  | DependencyError !DependencyError
  | CacheError !CacheError
  | IOError !FilePath !Text
```

### Step 3: Replace Either String with proper types

Find all `Either String` usages and replace with typed errors:

```haskell
-- Before (Builder/Incremental.hs)
safeReadOutline :: FilePath -> IO (Either String Outline)

-- After
safeReadOutline :: FilePath -> IO (Either OutlineError Outline)
```

### Step 4: Ensure all errors have source locations

Every error should carry enough context for a good error message:
- File path
- Source region (line/column)
- Error-specific context

### Step 5: Tests

- Test error rendering for each variant
- Golden tests for error message format
- Test error type coverage (no `String` errors remain)

## Dependencies
- None
