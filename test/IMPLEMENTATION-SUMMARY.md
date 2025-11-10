# Canopy Test Suite Implementation Summary

## Quick Start Guide

This document provides a condensed overview of the test suite improvement plan. For complete details, see [TEST-SUITE-IMPROVEMENT-PLAN.md](./TEST-SUITE-IMPROVEMENT-PLAN.md).

## Current State

- **107 test files** (~13,309 lines)
- **282 source files** to test
- **150+ anti-pattern violations** (Show tests: 37, Lens tests: 113)
- **8+ modules without tests**
- **3 test categories disabled** (Property, Integration, Golden)
- **Sequential execution** (no parallelization)

## Goals

| Metric | Current | Target | Improvement |
|--------|---------|--------|-------------|
| Anti-patterns | 150+ | 0 | -100% |
| Coverage | ~60% | 80%+ | +33% |
| Test Speed | ~5min | ~2.5min | +50% |
| Function Coverage | ~85% | 100% | +15% |

## 8-Week Implementation Plan

### Week 1: Infrastructure Setup
**Create helper modules:**
- `test/Helpers/Assertions.hs` - Custom assertions
- `test/Helpers/Generators.hs` - QuickCheck generators
- `test/Helpers/Fixtures.hs` - Test data management
- `test/Helpers/Integration.hs` - Integration test infrastructure
- `test/Helpers/Golden.hs` - Golden test utilities

**Commands:**
```bash
mkdir -p test/Helpers
# Create files and implement helpers
make test  # Verify nothing broken
```

### Week 2: Show Anti-Pattern Elimination
**Target:** 37 violations across 8 files

**Priority Files:**
1. `Unit/AST/OptimizedTest.hs` (35 violations) - Days 1-2
2. `Unit/AST/Utils/ShaderTest.hs` (15 violations) - Day 3
3. `Unit/AST/Utils/BinopTest.hs` (4 violations) - Day 3
4. `Unit/Data/Utf8Test.hs` (2 violations) - Day 4
5. `Unit/File/Utf8Test.hs` (2 violations) - Day 4

**Pattern:**
```haskell
-- ❌ Before
testCase "Bool constructor" $ do
  let expr = Opt.Bool True
  show expr @?= "Bool True"

-- ✅ After
testCase "Bool expression value" $ do
  let expr = Opt.Bool True
  extractBoolValue expr @?= Just True
```

### Week 3-4: Lens Anti-Pattern Elimination
**Target:** 113 violations across 10 files

**Priority Files:**
1. `Unit/Init/TypesTest.hs` (50 violations) - Week 3, Days 1-2
2. `Unit/Develop/TypesTest.hs` (25 violations) - Week 3, Days 3-4
3. `Unit/DevelopMainTest.hs` (15 violations) - Week 4, Day 1
4. `Unit/DevelopTest.hs` (20 violations) - Week 4, Day 1
5. `Unit/InitTest.hs` (19 violations) - Week 4, Day 2
6. `Integration/InitTest.hs` (13 violations) - Week 4, Day 2
7. `Integration/DevelopTest.hs` (15 violations) - Week 4, Day 3

**Pattern:**
```haskell
-- ❌ Before (mechanical)
testCase "config verbose getter" $ do
  let config = defaultConfig
  config ^. configVerbose @?= False

-- ✅ After (behavioral)
testCase "verbose flag affects output" $ do
  let quiet = defaultConfig
      verbose = defaultConfig & configVerbose .~ True
  length (getCompilerFlags quiet) <
    length (getCompilerFlags verbose) @? "Verbose adds flags"
```

### Week 5: Missing Test Coverage
**Target:** 8 modules without tests

**New Test Files:**
1. `Unit/Parse/NumberTest.hs` - Day 1
2. `Unit/Parse/StringTest.hs` - Day 1
3. `Unit/Parse/KeywordTest.hs` - Day 2
4. `Unit/Parse/DeclarationTest.hs` - Day 2
5. Enhance `Unit/AST/Utils/BinopTest.hs` - Day 3
6. Enhance `Unit/AST/Utils/ShaderTest.hs` - Day 3
7. Enhance `Unit/Json/EncodeTest.hs` - Day 4

**Template:**
```haskell
module Unit.Parse.NumberTest (tests) where

import qualified Parse.Number as Number
import Test.Tasty
import Test.Tasty.HUnit
import Helpers.Assertions

tests :: TestTree
tests = testGroup "Parse.Number Tests"
  [ testGroup "integer parsing"
      [ testCase "positive" $
          Number.parse "42" @?= Right (Number.Integer 42)
      , testCase "negative" $
          Number.parse "-42" @?= Right (Number.Integer (-42))
      ]
  , testGroup "error handling"
      [ testCase "empty" $ assertLeft (Number.parse "")
      ]
  ]
```

### Week 6: Integration Test Optimization
**Implement infrastructure:**
- `withIntegrationEnv` - Test environment management
- `setupTestProject` - Project scaffolding
- `compileTestModule` - Compilation in test env

**Enable integration tests in CI**

### Week 7: Golden Test Enhancement
**Organize golden files:**
- `test/Golden/sources/` - Input files
- `test/Golden/expected/` - Expected outputs

**Add update process:**
```bash
make update-golden  # Update all golden files
```

**Enable golden tests in CI**

### Week 8: Parallel Execution
**Configure parallel execution:**
```bash
stack test --test-arguments "+RTS -N4 -RTS"
```

**Implement resource pooling for expensive operations**

**Benchmark and optimize**

## Key Anti-Pattern Fixes

### 1. Show Instance Testing

**Anti-pattern:** Testing Show output instead of behavior
```haskell
show expr @?= "Bool True"  -- ❌ Tests Show instance
```

**Fix:** Extract and test properties
```haskell
extractBoolValue expr @?= Just True  -- ✅ Tests behavior
```

### 2. Lens Getter/Setter Testing

**Anti-pattern:** Testing lens library mechanics
```haskell
config ^. configVerbose @?= False  -- ❌ Tests lens getter
```

**Fix:** Test business behavior using lenses as tools
```haskell
getCompilerFlags config @?= ["-O2"]  -- ✅ Tests behavior
```

### 3. Missing Function Coverage

**Anti-pattern:** Modules without any tests
```haskell
-- Parse.Number has no tests  -- ❌
```

**Fix:** Add comprehensive test file
```haskell
module Unit.Parse.NumberTest (tests) where  -- ✅
-- Complete test coverage
```

## Helper Module Usage

### Assertions
```haskell
import Helpers.Assertions

-- AST testing without Eq
assertBoolExpr True expr
assertIntExpr 42 expr

-- Result testing
assertRight expected result
assertLeft result
assertJust expected maybeVal
assertNothing maybeVal

-- Collection testing
assertLength 3 list
assertContains item list
```

### Generators
```haskell
import Helpers.Generators

-- Property tests
testProperty "roundtrip" $
  forAll genValidIdentifier $ \name ->
    fromChars (toChars name) == name
```

### Fixtures
```haskell
import Helpers.Fixtures

-- Load test data
module <- loadModuleFixture "Simple.canopy"
package <- loadPackageFixture "core-1.0.0"

-- Temporary files
withTempDirectory "test" $ \dir -> do
  -- Use dir for testing
  -- Automatic cleanup
```

### Integration
```haskell
import Helpers.Integration

-- Integration tests
withIntegrationEnv False $ \env -> do
  setupTestProject env
  result <- compileTestModule env "Main.canopy"
  assertCompiled env result
```

## Makefile Commands

```bash
# Development
make test              # All tests
make test-fast         # Unit + Property only (for dev loop)
make test-watch        # Continuous testing

# Specific categories
make test-unit         # Unit tests
make test-property     # Property tests
make test-integration  # Integration tests

# Coverage and quality
make test-coverage     # Run with coverage report
make coverage-report   # HTML coverage report
make coverage-check    # Verify 80%+ coverage

# Golden tests
make update-golden     # Update golden files
make test-golden       # Run golden tests

# Pattern matching
make test-match PATTERN="Parser"  # Run tests matching pattern
```

## Validation Checklist

After each phase:

- [ ] All tests pass: `make test`
- [ ] Coverage maintained/improved: `make coverage-check`
- [ ] No new anti-patterns: `grep -r "show .* @?=" test/`
- [ ] Code reviewed and approved
- [ ] Documentation updated

## Common Patterns

### Unit Test
```haskell
testCase "descriptive name" $ do
  let input = createInput
  result <- function input
  assertRight expected result
```

### Property Test
```haskell
testProperty "invariant" $
  forAll genInput $ \input ->
    property (function input)
```

### Integration Test
```haskell
testCase "workflow" $
  withIntegrationEnv False $ \env -> do
    setupTestProject env
    result <- workflow env
    assertSuccess result
```

### Golden Test
```haskell
goldenTest "name" "expected.golden" $ do
  output <- generateOutput
  pure (normalize output)
```

## Anti-Pattern Detection

Check for anti-patterns before committing:

```bash
# Show instance tests (should return 0)
grep -r "show .* @?=" test/ | wc -l

# Lens getter tests (review case-by-case)
grep -r "\^\..*@?=" test/ | wc -l

# Reflexive equality (should return 0)
grep -r "== .*" test/ | grep -E "basics == basics|core == core"
```

## Success Metrics

Track these metrics weekly:

- **Anti-pattern count:** Target 0
- **Test coverage:** Target 80%+
- **Test execution time:** Target <3 minutes
- **Test count:** Target 500+ meaningful tests
- **Failed test rate:** Target <1%

## Resources

- **Full Plan:** [TEST-SUITE-IMPROVEMENT-PLAN.md](./TEST-SUITE-IMPROVEMENT-PLAN.md)
- **Standards:** [/home/quinten/fh/canopy/CLAUDE.md](../CLAUDE.md)
- **Anti-patterns:** [Anti-Pattern-Analysis.md](./Anti-Pattern-Analysis.md)
- **Test Helpers:** `test/Helpers/*.hs`

## Getting Help

- Review existing tests in same directory for patterns
- Check helper modules for utilities
- See full plan for detailed examples
- Ask in code review if unsure about pattern

## Quick Decision Tree

**Adding a new test?**
1. Find corresponding source file location
2. Create test file in matching `test/Unit/` location
3. Use helpers from `test/Helpers/`
4. Follow existing patterns in directory
5. Verify with `make test`

**Refactoring existing test?**
1. Identify anti-pattern type (Show/Lens/Other)
2. Find refactoring pattern in full plan
3. Transform one test at a time
4. Run `make test` after each change
5. Commit incrementally

**Fixing failing test?**
1. Understand what behavior test validates
2. Fix the bug in source code (not test)
3. If test is wrong, fix test properly
4. Never simplify test to make it pass
5. Add regression test if needed

---

**Remember:** We're building tests that verify real behavior, not framework mechanics. Every test should answer: "What business logic does this validate?"

**Next Step:** Review [TEST-SUITE-IMPROVEMENT-PLAN.md](./TEST-SUITE-IMPROVEMENT-PLAN.md) for complete details, then start with Week 1 infrastructure setup.
