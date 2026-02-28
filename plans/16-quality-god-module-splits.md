# Plan 16: Remaining God Module Decomposition

## Priority: MEDIUM
## Effort: Large (3-5 days)
## Risk: Medium — extensive refactoring across many files

## Problem

Several modules still exceed the 300-line limit and have multiple responsibilities. The previous round of splits (Plan 29 from prior session) handled some, but more remain.

### Oversized Modules (from audit)
- `Compiler.hs` (741 lines) — compilation orchestration + ELCO serialization + parallel dispatch
- `CLI/Commands.hs` (608 lines) — all command registrations in one file
- `Lint/Rules.hs` (463 lines) — all lint rules in one module
- `Builder/LockFile.hs` (455 lines) — types + serialization + generation + verification
- `Setup.hs` (419 lines) — package location + compilation + reporting

## Implementation Plan

### Step 1: Split Compiler.hs

**Current**: `packages/canopy-builder/src/Compiler.hs` (741 lines)

Split into:
- `Compiler.hs` — public API, orchestration (≤150 lines)
- `Compiler/Pipeline.hs` — compilation pipeline stages
- `Compiler/Parallel.hs` — parallel compilation dispatch
- `Compiler/Cache.hs` — ELCO serialization, binary cache
- `Compiler/Types.hs` — CompileEnv, CompileResult, etc.

### Step 2: Split CLI/Commands.hs

**Current**: `packages/canopy-terminal/src/CLI/Commands.hs` (608 lines)

Split into:
- `CLI/Commands.hs` — command registry, `allCommands` list (≤100 lines)
- `CLI/Commands/Build.hs` — make/build commands
- `CLI/Commands/Package.hs` — install/publish/diff commands
- `CLI/Commands/Dev.hs` — repl/watch/test commands
- `CLI/Commands/Project.hs` — init/new/setup commands

### Step 3: Split Lint/Rules.hs

**Current**: `packages/canopy-terminal/src/Lint/Rules.hs` (463 lines)

Split into:
- `Lint/Rules.hs` — rule registry, `allRules` (≤80 lines)
- `Lint/Rules/Imports.hs` — UnusedImport rule
- `Lint/Rules/Patterns.hs` — BooleanCase rule
- `Lint/Rules/Style.hs` — UnnecessaryParens, MissingTypeAnnotation
- `Lint/Rules/Lists.hs` — DropConcatOfLists, UseConsOverConcat

### Step 4: Split Builder/LockFile.hs

**Current**: `packages/canopy-builder/src/Builder/LockFile.hs` (456 lines)

Split into:
- `Builder/LockFile.hs` — re-exports, public API (≤50 lines)
- `Builder/LockFile/Types.hs` — data types, lenses (already planned in Plan 14)
- `Builder/LockFile/IO.hs` — read/write operations
- `Builder/LockFile/Generate.hs` — lock file generation
- `Builder/LockFile/Verify.hs` — hash and signature verification
- `Builder/LockFile/JSON.hs` — ToJSON/FromJSON instances

### Step 5: Split Setup.hs

**Current**: `packages/canopy-terminal/src/Setup.hs` (420 lines)

Split into:
- `Setup.hs` — entry point, orchestration (≤100 lines)
- `Setup/PackageLocator.hs` — finding and copying packages
- `Setup/Compiler.hs` — local package compilation
- `Setup/Report.hs` — summary reporting

### Step 6: Update all import sites

After each split, update all files that import the original module to import from the new sub-modules.

### Step 7: Verify build

Run `make build && make test` after each split to ensure nothing breaks.

## Dependencies
- Plan 14 (newtypes) should ideally be done before LockFile split
