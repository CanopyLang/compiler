# Plan 19: God Module Decomposition

**Priority:** MEDIUM
**Effort:** Large (3–5 days)
**Risk:** Medium

## Problem

58 files exceed 300 lines. The worst offenders mix multiple responsibilities:

| Lines | File | Mixed Responsibilities |
|-------|------|----------------------|
| 806 | `Json/String.hs` | UTF-8 encoding + JSON string parsing + comment processing + chunk allocation |
| 804 | `Test.hs` | Discovery + compilation + unit/browser/async execution + file watching + harness dispatch |
| 741 | `Generate/JavaScript.hs` | Main JS gen + FFI content gen + FFI binding gen + FFI validation + graph state + source maps + REPL |
| 747 | `Reporting/Exit.hs` | Error types for 12 different CLI commands |
| 780 | `Canonicalize/Expression.hs` | Contains an 85-line function (limit: 15) |

## Files to Split (Priority Order)

### 1. `Generate/JavaScript.hs` (741 lines) → 3 modules

Extract FFI-related code (lines 96–340) into `Generate/JavaScript/FFI.hs`:
- `extractFFIAliases`
- `generateFFIContent`
- `generateFFIValidators`
- `collectValidators`
- `formatFFIFileFromInfo`
- `generateFFIBindingsFromInfo`
- `extractFFIFunctionBindings`
- `extractCanopyTypeFunctions`
- `extractCanopyType`
- `findFunctionName`
- `generateFunctionBinding`
- `generateSimpleBinding`
- `generateValidatedBinding`
- `extractReturnType`
- `typeToValidator`
- `trim`
- `FFIInfo` type and Binary instance

Extract REPL generation into `Generate/JavaScript/Repl.hs` (if not already separate).

### 2. `Reporting/Exit.hs` (747 lines) → per-command modules

Already partially split (Install/Publish have sub-modules). Complete the split:
- `Reporting/Exit/Make.hs`
- `Reporting/Exit/Check.hs`
- `Reporting/Exit/Repl.hs`
- `Reporting/Exit/Diff.hs`
- `Reporting/Exit/Bump.hs`
- `Reporting/Exit/Init.hs`
- `Reporting/Exit/New.hs`
- `Reporting/Exit/Docs.hs`
- `Reporting/Exit/Setup.hs`
- `Reporting/Exit/Reactor.hs`

`Reporting/Exit.hs` becomes a thin re-export facade.

### 3. `Test.hs` (804 lines) → focused modules

- `Test/Discovery.hs` — test file detection and classification
- `Test/Compilation.hs` — compiling test modules
- `Test/Runner/Unit.hs` — unit test execution
- `Test/Runner/Browser.hs` — Playwright-based browser tests
- `Test/Runner/Async.hs` — Node.js async tests

### 4. `Canonicalize/Expression.hs` (780 lines) → decomposed + refactored

The 85-line `canonicalize` function must be split into helpers. Each pattern match arm should become a separate function:
- `canonicalizeVar`
- `canonicalizeLambda`
- `canonicalizeCall`
- `canonicalizeIf`
- `canonicalizeLet`
- `canonicalizeCase`
- `canonicalizeRecord`
- `canonicalizeAccess`
- `canonicalizeUpdate`

### 5. `Json/String.hs` (806 lines)

If feasible, split into:
- `Json/String/Encode.hs` — UTF-8 encoding
- `Json/String/Parse.hs` — JSON string parsing
- `Json/String/Internal.hs` — shared chunk allocation and byte operations

## Approach

For each split:
1. Create new module with extracted functions
2. Update original module to re-export from new module
3. Update cabal file with new module
4. Run `make build` to verify
5. Run `make test` to verify
6. Remove re-exports if no external consumers depend on the original path

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. No file exceeds 500 lines after this work
4. Each new module has a single clear responsibility
