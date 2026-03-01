# Plan 23: God Module Decomposition (Remaining)

**Priority:** MEDIUM
**Effort:** Medium (1-2d)
**Risk:** Low -- Mechanical refactoring with clear boundaries

## Problem

Several modules exceed the 500-line threshold, making them harder to understand, test, and maintain. The recent `13d8c7d` commit split some god modules (Compiler.hs, LockFile.hs, Setup.hs) and `cfe7787` split Lint/Rules.hs and CLI/Commands.hs. This plan addresses the remaining large modules.

### Modules >500 Lines (Sorted by Size)

| Lines | Module | Package | Decomposable? |
|-------|--------|---------|---------------|
| 806 | `Test.hs` | canopy-terminal | Yes -- multiple responsibilities |
| 806 | `Json/String.hs` | canopy-core | No -- low-level byte manipulation, inherent complexity |
| 800 | `Canonicalize/Expression.hs` | canopy-core | Partial -- algorithmic core, but helpers extractable |
| 798 | `Json/Encode.hs` | canopy-core | No -- single encoding API, inherent complexity |
| 795 | `Test/FFI.hs` | canopy-terminal | Yes -- multiple test helpers |
| 783 | `Reporting/Error/Syntax/Module.hs` | canopy-core | No -- already split from parent, error messages inherently large |
| 776 | `AST/Source.hs` | canopy-core | No -- single data definition module |
| 770 | `WebIDL/Parser.hs` | canopy-webidl | No -- recursive descent parser, inherent complexity |
| 760 | `Generate/JavaScript/Expression.hs` | canopy-core | Partial -- operators/literals extractable |
| 752 | `Reporting/Error/Type/Operators.hs` | canopy-core | No -- error messages inherently large |
| 747 | `Reporting/Exit.hs` | canopy-terminal | Yes -- error types per command |
| 740 | `Reporting/Error/Syntax/Pattern.hs` | canopy-core | No -- already split from parent |
| 725 | `Type/Solve/Pool.hs` | canopy-core | No -- single algorithm |
| 720 | `Reporting/Error/Syntax/Type.hs` | canopy-core | No -- already split from parent |
| 659 | `WebIDL/Transform.hs` | canopy-webidl | Partial |
| 652 | `Type/Solve.hs` | canopy-core | No -- single algorithm |
| 649 | `Reporting/Error/Syntax/Declaration/DeclBody.hs` | canopy-core | No -- already split |
| 638 | `Reporting/Error/Syntax/Expression/Let.hs` | canopy-core | No -- already split |
| 630 | `Format.hs` | canopy-core | Partial -- sections already well-separated |
| 628 | `Type/Unify.hs` | canopy-core | No -- single algorithm |

### Assessment: Feasible Splits

Three modules are clear candidates for decomposition:

## Split 1: Test.hs (806 lines)

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Test.hs`

This module handles the entire `canopy test` command: flag parsing, test discovery, compilation, JS runner generation, process execution, and result reporting. These are distinct responsibilities.

**Current structure (from module header):**
- Flag parsing and configuration
- Test file discovery
- Compilation orchestration
- Node.js runner generation
- Process execution and output parsing
- Result formatting

**Proposed split:**

| New Module | Responsibility | Approx Lines |
|-----------|----------------|-------------|
| `Test.hs` | Top-level `run`, flag definitions, dispatch | ~150 |
| `Test/Discovery.hs` | Finding test files in source directories | ~100 |
| `Test/Compile.hs` | Compiling test modules and generating JS | ~200 |
| `Test/Runner.hs` | Already exists -- Node.js execution | ~150 |
| `Test/Report.hs` | Formatting test results for terminal | ~200 |

## Split 2: Reporting/Exit.hs (747 lines)

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Reporting/Exit.hs`

This module defines error types for every CLI command (Make, Check, Repl, Install, Publish, Diff, Bump, Init, New, Setup, Reactor, Docs) plus shared error message builders. Each command's error type is independent.

**Current structure:**
- Lines 118-157: Shared error formatting helpers (`structuredError`, `errorBar`, `Report`, `toStderr`)
- Lines 158-176: Check errors (5 constructors + report function)
- Lines 177-197: Docs errors (6 constructors + report function)
- Lines 198-228: Make errors (12 constructors + report function)
- Lines 230-243: Repl errors (3 constructors + report function)
- Lines 245-305: Diff, Bump errors
- Lines 307-401: Init, New, Setup, Reactor errors
- Lines 403-499+: Shared error message builders

**Proposed split:**

| New Module | Responsibility | Approx Lines |
|-----------|----------------|-------------|
| `Reporting/Exit.hs` | `Report` type, `toStderr`, shared formatters | ~120 |
| `Reporting/Exit/Make.hs` | `Make` error type + `makeToReport` | ~80 |
| `Reporting/Exit/Install.hs` | Already exists | -- |
| `Reporting/Exit/Publish.hs` | Already exists | -- |
| `Reporting/Exit/Check.hs` | `Check` error type + `checkToReport` | ~40 |
| `Reporting/Exit/Repl.hs` | `Repl` error type + `replToReport` | ~30 |
| `Reporting/Exit/Diff.hs` | `Diff` error type + `diffToReport` | ~60 |
| `Reporting/Exit/Bump.hs` | `Bump` error type + `bumpToReport` | ~60 |
| `Reporting/Exit/Init.hs` | `Init` error type + `initToReport` | ~50 |
| `Reporting/Exit/New.hs` | `New` error type + `newToReport` | ~40 |
| `Reporting/Exit/Setup.hs` | `Setup`, `Reactor`, `Registry`, `Solver` types | ~80 |

Note: `Reporting/Exit/Install.hs` and `Reporting/Exit/Publish.hs` already exist as separate modules (imported at line 107-115).

## Split 3: Generate/JavaScript/Expression.hs (760 lines)

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Generate/JavaScript/Expression.hs`

This module generates JavaScript for all expression forms. The operator generation and literal generation are self-contained.

**Proposed split:**

| New Module | Responsibility | Approx Lines |
|-----------|----------------|-------------|
| `Generate/JavaScript/Expression.hs` | Core expression generation | ~400 |
| `Generate/JavaScript/Expression/Literal.hs` | String, number, char literals | ~150 |
| `Generate/JavaScript/Expression/Operator.hs` | Binary/unary operators, kernel ops | ~200 |

## Partial Split: Canonicalize/Expression.hs (800 lines)

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Canonicalize/Expression.hs`

This is the core canonicalization algorithm. Most of it is a single recursive function over expression forms. However, helper functions for let-bindings and definitions can be extracted.

**Proposed split:**

| New Module | Responsibility | Approx Lines |
|-----------|----------------|-------------|
| `Canonicalize/Expression.hs` | Main `canonicalize` function | ~500 |
| `Canonicalize/Expression/Binding.hs` | `verifyBindings`, `gatherTypedArgs`, def handling | ~300 |

## Files to Modify

### Split 1: Test.hs

| File | Change |
|------|--------|
| `packages/canopy-terminal/src/Test.hs` | Extract discovery, compile, report functions |
| `packages/canopy-terminal/src/Test/Discovery.hs` | New: test file discovery logic |
| `packages/canopy-terminal/src/Test/Compile.hs` | New: test compilation and JS generation |
| `packages/canopy-terminal/src/Test/Report.hs` | New: result formatting |
| `packages/canopy-terminal/canopy-terminal.cabal` | Add new modules to exposed-modules |

### Split 2: Reporting/Exit.hs

| File | Change |
|------|--------|
| `packages/canopy-terminal/src/Reporting/Exit.hs` | Keep shared types, re-export sub-modules |
| `packages/canopy-terminal/src/Reporting/Exit/Make.hs` | New: Make error type |
| `packages/canopy-terminal/src/Reporting/Exit/Check.hs` | New: Check error type |
| `packages/canopy-terminal/src/Reporting/Exit/Repl.hs` | New: Repl error type |
| `packages/canopy-terminal/src/Reporting/Exit/Diff.hs` | New: Diff error type |
| `packages/canopy-terminal/src/Reporting/Exit/Bump.hs` | New: Bump error type |
| `packages/canopy-terminal/src/Reporting/Exit/Init.hs` | New: Init error type |
| `packages/canopy-terminal/src/Reporting/Exit/New.hs` | New: New error type |
| `packages/canopy-terminal/src/Reporting/Exit/Setup.hs` | New: Setup/Reactor/Registry types |
| `packages/canopy-terminal/canopy-terminal.cabal` | Add new modules |

### Split 3: Generate/JavaScript/Expression.hs

| File | Change |
|------|--------|
| `packages/canopy-core/src/Generate/JavaScript/Expression.hs` | Extract literal and operator generation |
| `packages/canopy-core/src/Generate/JavaScript/Expression/Literal.hs` | New: literal code gen |
| `packages/canopy-core/src/Generate/JavaScript/Expression/Operator.hs` | New: operator code gen |
| `packages/canopy-core/canopy-core.cabal` | Add new modules |

## Verification

```bash
# 1. All code compiles
make build

# 2. All tests pass
make test

# 3. No module exceeds 500 lines (target)
find packages/ -name "*.hs" -exec wc -l {} \; | sort -rn | head -20
# Target: no module >500 lines except inherently large ones (Json/String.hs, etc.)

# 4. No circular imports introduced
# Build should succeed -- GHC catches circular imports

# 5. Verify re-exports work
# Modules importing from Reporting.Exit should not need to change their imports
# (the parent module re-exports everything from sub-modules)
```

## Notes on Non-Decomposable Modules

The following modules are >500 lines but should NOT be split:

- **Json/String.hs (806)**: Low-level byte-by-byte UTF-8 string parsing. The entire module is a single tightly coupled parser. Splitting would fragment the character state machine.

- **Json/Encode.hs (798)**: Single encoding API with many format functions. Each function is small; the module is large due to format coverage.

- **AST/Source.hs (776)**: Pure data type definitions. Splitting would scatter related types across modules.

- **Reporting/Error/Syntax/*.hs**: These were already split from a monolithic Syntax error module. Each file handles one syntactic category.

- **Type/Solve.hs (652), Type/Unify.hs (628), Type/Solve/Pool.hs (725)**: Core type inference algorithms. These are single algorithms that cannot be meaningfully decomposed.

- **WebIDL/Parser.hs (770)**: Recursive descent parser for WebIDL -- inherently one big parser.
