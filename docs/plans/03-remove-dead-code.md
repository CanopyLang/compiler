# Plan 03 — Remove Dead Code and Stray Files

**Priority:** Tier 0 (Blocker)
**Effort:** 2 hours
**Risk:** Low (removing unused code)
**Files:** ~12 files

---

## Problem

Multiple files exist in the repo that are never compiled, never imported, or are stale copies from a previous directory layout. These create confusion for contributors and give a false impression of the codebase size and health.

## Inventory of Dead Code

### 1. Stray compiler directory (1 file, 1,109 lines)

**File:** `compiler/src/Generate/JavaScript/Expression.hs`

This is a diverged copy of `packages/canopy-core/src/Generate/JavaScript/Expression.hs`. It is not referenced in `stack.yaml` or any `.cabal` file. It differs from the current version (different exports, missing functions). It is leftover from Elm's original directory structure.

**Action:** Delete `compiler/` directory entirely.

### 2. Dead module: Nitpick.Debug (1 file)

**File:** `packages/canopy-core/src/Nitpick/Debug.hs`

Exports `hasDebugUses :: Opt.LocalGraph -> Bool`. Zero imports of `Nitpick.Debug` exist anywhere in the codebase. Listed in `canopy-core.cabal` as an exposed module but never called.

**Action:** Delete the file and remove from `canopy-core.cabal` exposed-modules list.

### 3. Orphan canopy-core tests (8 files, 2,288 lines)

**Files:**
- `packages/canopy-core/test/NameReversalTest.hs`
- `packages/canopy-core/test/Property/ArithmeticLawsTest.hs`
- `packages/canopy-core/test/Unit/AST/CanonicalArithmeticTest.hs`
- `packages/canopy-core/test/Unit/AST/SourceArithmeticTest.hs`
- `packages/canopy-core/test/Unit/Canonicalize/ExpressionArithmeticTest.hs`
- `packages/canopy-core/test/Unit/Generate/JavaScript/ExpressionArithmeticTest.hs`
- `packages/canopy-core/test/Unit/Optimize/ExpressionArithmeticTest.hs`
- `packages/canopy-core/test/Unit/Parse/ExpressionArithmeticTest.hs`

`canopy-core.cabal` has no test-suite stanza. These tests are never compiled or run.

**Action:** Either wire them into the root `canopy.cabal` test suite (Plan 26) or delete them. For this plan, move them to a holding directory `packages/canopy-core/test-orphaned/` with a README explaining they need wiring.

### 4. Standalone scripts (2 files)

**Files:**
- `scripts/GenerateGoldenFiles.hs`
- `scripts/js_to_ast_debug.hs`

Not in any build target.

**Action:** Verify if they are useful development tools. If yes, add a comment header explaining how to run them. If no, delete.

### 5. Dead Worker.Pool (1 file)

**File:** `packages/canopy-driver/src/Worker/Pool.hs`

The hot compilation path in `Compiler.hs` uses `Async.mapConcurrently` directly. `Worker.Pool` is a `Chan`-based thread pool that is exported but never called from the compilation pipeline.

**Action:** Search for all imports of `Worker.Pool`. If zero, delete. If imported by test code only, note in a comment.

### 6. Dead solveCaseBranchesIsolated function

**File:** `packages/canopy-core/src/Type/Solve.hs` (lines 382-391)

`solveCaseBranchesIsolated` is defined but the `CCaseBranchesIsolated` dispatch at line 116 calls the non-isolating path instead. This is either dead code or a bug (the isolated path was intended but not wired).

**Action:** Investigate which is correct. If dead code, delete with a comment explaining why. If a bug, file it as Plan 16 addendum.

## Implementation

### Step 1: Delete stray compiler directory

```bash
# Verify nothing depends on it
grep -r "compiler/src" stack.yaml canopy.cabal packages/*/canopy-*.cabal
# If clean:
rm -rf compiler/
```

### Step 2: Remove Nitpick.Debug

```bash
# Verify no imports
grep -r "Nitpick.Debug" packages/
# If clean:
rm packages/canopy-core/src/Nitpick/Debug.hs
# Edit canopy-core.cabal to remove Nitpick.Debug from exposed-modules
```

### Step 3: Handle orphan tests

```bash
mkdir -p packages/canopy-core/test-orphaned
mv packages/canopy-core/test/* packages/canopy-core/test-orphaned/
# Write a README in test-orphaned/ explaining status
```

### Step 4: Audit scripts

```bash
# Check if scripts reference current module paths
head -20 scripts/GenerateGoldenFiles.hs scripts/js_to_ast_debug.hs
```

### Step 5: Audit Worker.Pool

```bash
grep -r "Worker.Pool\|Worker\.Pool" packages/*/src/ test/
```

### Step 6: Audit solveCaseBranchesIsolated

```bash
grep -n "solveCaseBranchesIsolated\|CCaseBranchesIsolated" packages/canopy-core/src/Type/Solve.hs
```

## Validation

```bash
make build && make test
```

All 2,376 tests must still pass. The build must produce no new warnings.

## Acceptance Criteria

- `compiler/` directory deleted
- `Nitpick.Debug` removed from source and cabal
- Orphan tests either wired into a test suite or moved to a clearly labeled holding area
- `Worker.Pool` status documented (in-use or deleted)
- `solveCaseBranchesIsolated` status resolved (bug or dead code)
- `make build && make test` passes
