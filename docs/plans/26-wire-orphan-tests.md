# Plan 26 — Wire Orphan canopy-core Tests into Build

**Priority:** Tier 5 (Hardening)
**Effort:** 2 hours
**Risk:** Low
**Files:** `canopy-core.cabal` or root `canopy.cabal`, 8 test files

---

## Problem

8 test files (2,288 lines) exist in `packages/canopy-core/test/` but `canopy-core.cabal` has no test-suite stanza. These tests are never compiled, never run, and may not even compile against the current codebase. They represent either useful coverage that is being wasted, or dead code that should be deleted.

## Files

```
packages/canopy-core/test/NameReversalTest.hs
packages/canopy-core/test/Property/ArithmeticLawsTest.hs
packages/canopy-core/test/Unit/AST/CanonicalArithmeticTest.hs
packages/canopy-core/test/Unit/AST/SourceArithmeticTest.hs
packages/canopy-core/test/Unit/Canonicalize/ExpressionArithmeticTest.hs
packages/canopy-core/test/Unit/Generate/JavaScript/ExpressionArithmeticTest.hs
packages/canopy-core/test/Unit/Optimize/ExpressionArithmeticTest.hs
packages/canopy-core/test/Unit/Parse/ExpressionArithmeticTest.hs
```

## Implementation

### Step 1: Verify they compile

```bash
# Try compiling each file against canopy-core
cd packages/canopy-core
stack ghc -- -i src test/NameReversalTest.hs -fno-code 2>&1
# Repeat for each file
```

### Step 2: Option A — Add test-suite to canopy-core.cabal

```yaml
test-suite canopy-core-test
  type:             exitcode-stdio-1.0
  hs-source-dirs:   test
  main-is:          Main.hs
  build-depends:
    , canopy-core
    , tasty
    , tasty-hunit
    , tasty-quickcheck
    , base
  default-language: Haskell2010
```

Create a `Main.hs` that imports and runs all test modules.

### Step 2: Option B — Move to root test suite

Move the test files to `test/Unit/Core/` in the root package and import them from the existing test main:

```bash
mv packages/canopy-core/test/Unit/AST/CanonicalArithmeticTest.hs test/Unit/AST/CanonicalArithmeticTest.hs
# etc.
```

Add imports to `test/Main.hs` (or whatever the root test entry point is).

### Step 3: Fix any compilation errors

The tests may reference modules or functions that have been renamed or removed since they were written. Fix as needed.

### Step 4: Verify test quality

Read each test file and check against CLAUDE.md anti-patterns:
- No mock functions (`_ = True`)
- No reflexive equality (`x == x`)
- No weak assertions (`isInfixOf`, `not null`)

Fix or delete tests that violate standards.

## Validation

```bash
make build && make test
# The test count should increase from 2,376 to 2,376 + new tests
```

## Acceptance Criteria

- All 8 test files are compiled and run as part of `make test`
- Test count increases
- All tests pass
- No CLAUDE.md anti-patterns in the tests
