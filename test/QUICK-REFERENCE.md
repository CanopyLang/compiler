# Test Suite Quick Reference Card

One-page reference for common testing patterns in the Canopy compiler test suite.

## Test File Locations

```
Source File:                        Test File:
packages/canopy-core/src/           test/Unit/
  Parse/Number.hs          →         Parse/NumberTest.hs
  AST/Optimized.hs         →         AST/OptimizedTest.hs
  Data/Name.hs             →         Data/NameTest.hs
```

## Import Pattern

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Unit.Parse.NumberTest (tests) where

-- Test libraries
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck  -- For property tests

-- Helper modules
import Helpers.Assertions
import Helpers.Generators
import Helpers.Fixtures

-- Module under test
import qualified Parse.Number as Number
```

## Basic Test Structure

```haskell
tests :: TestTree
tests = testGroup "Module.Name Tests"
  [ testGroup "feature group 1"
      [ testCase "specific behavior 1" $ ...
      , testCase "specific behavior 2" $ ...
      ]
  , testGroup "feature group 2"
      [ testCase "edge case 1" $ ...
      ]
  ]
```

## Common Test Patterns

### Unit Test
```haskell
testCase "parse simple number" $ do
  let result = Number.parse "42"
  result @?= Right (Number.Integer 42)
```

### Error Test
```haskell
testCase "reject invalid input" $ do
  case Number.parse "invalid" of
    Left _ -> pure ()
    Right _ -> assertFailure "Should reject invalid"
```

### Property Test
```haskell
testProperty "roundtrip" $
  forAll genNumber $ \n ->
    let text = Number.toText n
    in Number.parse text == Right n
```

### Integration Test
```haskell
testCase "compile workflow" $
  withIntegrationEnv False $ \env -> do
    setupTestProject env
    result <- compileModule env "Main.canopy"
    assertCompileSuccess result
```

## Helper Functions

### Assertions
```haskell
-- Value assertions
result @?= expected
assertBool "message" condition
assertFailure "message"

-- Custom assertions
assertRight expected result
assertLeft result
assertJust expected maybe
assertNothing maybe
assertLength 3 list
assertContains item list

-- AST assertions
assertBoolExpr True expr
assertIntExpr 42 expr
extractBoolValue expr @?= Just True
```

### Generators
```haskell
-- Basic generators
genValidIdentifier :: Gen Text
genModuleName :: Gen ModuleName
genVersion :: Gen Version

-- Usage
testProperty "test name" $
  forAll genValidIdentifier $ \name ->
    property (function name)
```

### Fixtures
```haskell
-- Load fixtures
module <- loadModuleFixture "Simple.canopy"
package <- loadPackageFixture "core-1.0.0"

-- Temp files
withTempDirectory "test" $ \dir -> do
  -- Test using dir
  -- Auto cleanup
```

## Anti-Patterns to Avoid

### ❌ Don't Test Show Output
```haskell
-- BAD
show expr @?= "Bool True"

-- GOOD
extractBoolValue expr @?= Just True
```

### ❌ Don't Test Lens Mechanics
```haskell
-- BAD
config ^. configVerbose @?= False

-- GOOD
getCompilerFlags config @?= ["-O2"]
```

### ❌ Don't Write Reflexive Tests
```haskell
-- BAD
version == version @? "reflexive"

-- GOOD
version1 < version2 @? "ordering"
```

### ❌ Don't Test Constants Are Different
```haskell
-- BAD
Name._main /= Name.true @? "different"

-- GOOD
Name.toChars Name._main @?= "main"
```

## Test Naming

```haskell
-- Pattern: test + What + Action
testParseNumber       -- Function under test
testParseRejects      -- Error condition
testNumberRoundtrip   -- Property/invariant

-- Test case names: describe behavior
"parses positive integers"
"rejects invalid format"
"preserves value in roundtrip"
```

## Running Tests

```bash
# All tests
make test

# Fast tests (dev loop)
make test-fast

# Specific category
make test-unit
make test-property
make test-integration

# Pattern matching
make test-match PATTERN="Parser"

# Coverage
make test-coverage
make coverage-report

# Watch mode
make test-watch

# Golden tests
make update-golden
```

## Test Categories

| Category | Speed | Purpose | Isolation |
|----------|-------|---------|-----------|
| Unit | Fast (~seconds) | Single function | Pure/isolated |
| Property | Fast (~seconds) | Laws/invariants | Generated inputs |
| Integration | Slow (~minutes) | End-to-end | Full environment |
| Golden | Medium (~seconds) | Output correctness | File comparison |

## Decision Tree

### Writing New Test?
1. Find source file: `packages/*/src/Foo/Bar.hs`
2. Create test: `test/Unit/Foo/BarTest.hs`
3. Use helpers from `test/Helpers/`
4. Follow patterns in same directory
5. Run: `make test-match PATTERN="Bar"`

### Fixing Failing Test?
1. Understand what it validates
2. Fix bug in source (not test!)
3. If test wrong, fix properly
4. Never simplify to pass
5. Add regression test

### Refactoring Test?
1. Identify anti-pattern
2. Check REFACTORING-EXAMPLE.md
3. Transform incrementally
4. Test after each change
5. Commit when working

## Coverage Goals

| Module Type | Target Coverage |
|-------------|-----------------|
| Parser | 90%+ |
| AST | 85%+ |
| Builder | 80%+ |
| Utilities | 90%+ |
| CLI | 70%+ |

## Common Mistakes

1. ❌ Testing Show output
2. ❌ Testing lens getters/setters
3. ❌ Testing reflexive equality
4. ❌ No assertions (test passes trivially)
5. ❌ Tests depend on execution order
6. ❌ Shared mutable state
7. ❌ Using magic numbers
8. ❌ Unclear test names

## Best Practices

1. ✅ Test behavior, not implementation
2. ✅ One assertion per test case
3. ✅ Clear, descriptive names
4. ✅ Independent tests
5. ✅ Fast unit tests
6. ✅ Use helpers to reduce duplication
7. ✅ Test edge cases
8. ✅ Add tests for bugs

## Example Test File

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Unit.Parse.NumberTest (tests) where

import Helpers.Assertions
import qualified Parse.Number as Number
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests = testGroup "Parse.Number Tests"
  [ testIntegerParsing
  , testFloatParsing
  , testErrorHandling
  ]

testIntegerParsing :: TestTree
testIntegerParsing = testGroup "integer parsing"
  [ testCase "positive integer" $
      Number.parse "42" @?= Right (Number.Integer 42)

  , testCase "negative integer" $
      Number.parse "-42" @?= Right (Number.Integer (-42))

  , testCase "zero" $
      Number.parse "0" @?= Right (Number.Integer 0)
  ]

testFloatParsing :: TestTree
testFloatParsing = testGroup "float parsing"
  [ testCase "simple decimal" $
      Number.parse "3.14" @?= Right (Number.Float 3.14)

  , testCase "scientific notation" $
      Number.parse "1e-10" @?= Right (Number.Float 1e-10)
  ]

testErrorHandling :: TestTree
testErrorHandling = testGroup "error handling"
  [ testCase "empty string" $
      assertLeft (Number.parse "")

  , testCase "invalid format" $
      assertLeft (Number.parse "12.34.56")
  ]
```

## Git Workflow

```bash
# Create branch
git checkout -b test/improve-parser-coverage

# Make changes
# ... edit test files ...

# Run tests
make test

# Commit
git add test/Unit/Parse/NumberTest.hs
git commit -m "test(parser): add comprehensive number parsing tests

- Add integer parsing tests (positive, negative, zero)
- Add float parsing tests (decimal, scientific)
- Add error handling tests
- Coverage: Parse.Number now 95%"

# Push and PR
git push origin test/improve-parser-coverage
```

## When in Doubt

1. Read CLAUDE.md testing section
2. Check TEST-SUITE-IMPROVEMENT-PLAN.md
3. Look at REFACTORING-EXAMPLE.md
4. Review existing tests in same directory
5. Ask in code review

## Resources

- **Full Plan:** TEST-SUITE-IMPROVEMENT-PLAN.md
- **Summary:** IMPLEMENTATION-SUMMARY.md
- **Example:** REFACTORING-EXAMPLE.md
- **Standards:** ../CLAUDE.md (sections on testing)
- **Anti-patterns:** Anti-Pattern-Analysis.md

---

**Remember:** Test what the code DOES, not what the framework generates!
