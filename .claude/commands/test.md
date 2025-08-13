# Test Creation Prompt — Canopy Compiler Coding Guidelines (Non-Negotiable)

**Task:**

- Please create comprehensive **tests** for the module: `$ARGUMENTS`.
- Follow **CLAUDE.md standards** exactly - all rules are **non-negotiable**.
- Tests must achieve **≥80% coverage** and follow Canopy's testing architecture.
- Use **Haskell Tasty** framework with proper import qualification patterns.
- Check the result of functions, do not just compare 2 of the same arguments. Test that we get the expected and disered outcome from functions.

---

## Test Architecture & Structure

### Directory Organization

```
test/
├── Unit/                    -- Pure function testing
│   ├── AST/                 -- AST module tests
│   ├── Canopy/              -- Core Canopy module tests
│   ├── Data/                -- Data structure tests
│   ├── Json/                -- JSON codec tests
│   └── Parse/               -- Parser tests
├── Property/                -- QuickCheck property tests
│   ├── AST/                 -- AST property tests
│   ├── Canopy/              -- Core property tests
│   └── Data/                -- Data structure properties
├── Integration/             -- End-to-end integration tests
└── Golden/                  -- Output matching tests
    ├── expected/            -- Golden reference files
    └── sources/             -- Test input files
```

### Module Naming Conventions

- **Unit tests**: `test/Unit/<ModulePath>Test.hs` (e.g., `Unit/Parse/PatternTest.hs`)
- **Property tests**: `test/Property/<ModulePath>Props.hs` (e.g., `Property/Data/NameProps.hs`)
- **Golden tests**: `test/Golden/<ModulePath>Golden.hs` (e.g., `Golden/JsGenGolden.hs`)
- **Integration tests**: `test/Integration/<Feature>Test.hs` (e.g., `Integration/CompilerTest.hs`)

---

## Steps

### 1. **Review Module Architecture**

- Analyze the target module's public API, types, and functions
- Identify pure vs. effectful operations
- Map dependencies and integration points
- Document edge cases, error conditions, and invariants

### 2. **Audit Existing Coverage**

- Search test suite for existing coverage: `grep -r "ModuleName" test/`
- Check `test/Main.hs` for registered test modules
- Identify gaps in unit, property, golden, and integration coverage
- Review current test patterns and quality

### 3. **Apply Test Classification Strategy**

**Unit Tests (Primary):**

- Pure function behavior verification
- Type constructor and field validation
- Error condition handling
- Boundary value testing

**Property Tests (Laws & Invariants):**

- Round-trip properties (encode/decode, parse/serialize)
- Algebraic laws (monoid, functor, monad laws)
- Invariant preservation under operations
- Generated input validation

**Golden Tests (Output Verification):**

- Parser output against known-good files
- Code generation consistency
- Documentation generation
- Complex transformation results

**Integration Tests (End-to-End):**

- Module interaction workflows
- File system operations
- Build pipeline testing
- Error propagation chains

### 4. **Follow CLAUDE.md Import Standards**

**Mandatory Pattern (NO EXCEPTIONS):**

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Parse.Pattern module.
--
-- Tests pattern parsing functionality including basic patterns,
-- constructors, lists, tuples, and error conditions.
module Unit.Parse.PatternTest (tests) where

-- Pattern: Types unqualified, functions qualified
import qualified AST.Source as Src
import qualified Data.Name as Name
import qualified Parse.Pattern as Pat
import qualified Reporting.Error.Syntax as E
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertFailure)
import Test.Tasty.QuickCheck (testProperty)
```

### 5. **Implement Comprehensive Test Patterns**

**Unit Test Structure:**

```haskell
tests :: TestTree
tests = testGroup "ModuleName Tests"
  [ testBasicFunctionality
  , testErrorConditions
  , testBoundaryValues
  , testTypeConstructors
  ]
```

**Property Test Structure:**

```haskell
tests :: TestTree
tests = testGroup "ModuleName Properties"
  [ testProperty "roundtrip encode/decode" $ \input ->
      decode (encode input) == Just input
  , testProperty "invariant preservation" $ \input ->
      isValid input ==> isValid (transform input)
  ]
```

**Golden Test Structure:**

```haskell
tests :: TestTree
tests = testGroup "ModuleName Golden"
  [ goldenVsFile
      "test description"
      "test/Golden/expected/output.golden"
      "test/Golden/actual/output.result"
      (generateOutput testInput)
  ]
```

## Anti-Fake Testing Rules

### ❌ FORBIDDEN PATTERNS (Will cause test failure):
- **Mock functions**: `isValid _ = True`, `alwaysPasses _ = False`
- **Reflexive equality**: `version == version`, `name == name`  
- **Meaningless distinctness**: `mainName /= trueName`, `basics /= maybe`
- **Constant comparisons**: Testing that different constants are different
- **Non-empty checks**: `assertBool "shows non-empty" (not (null (show x)))`
- **Weak contains testing**: `assertBool "contains X" ("X" `isInfixOf` result)`
- **Partial string checks**: Using `isInfixOf`, `elem . words` instead of exact equality

### ✅ REQUIRED PATTERNS (Test exact values and behavior):
- **Exact value verification**: `Name.toChars Name._main @?= "main"`
- **Complete show testing**: `show Package.core @?= "Name {_author = elm, _project = core}"`
- **Actual behavior**: `Name.toChars (Name.fromChars "test") @?= "test"`
- **Business logic**: `Version.compare v1 v2 @?= expectedOrder`
- **Error conditions**: `parseInvalid "bad input" @?= Left expectedError`

**Good patterns:**

```haskell
-- ✅ Test exact string values
testCase "name constants have correct string values" $ do
  Name.toChars Name._main @?= "main"
  Name.toChars Name.true @?= "True" 
  Name.toChars Name.false @?= "False"

-- ✅ Test exact show output
testCase "types show with exact format" $ do
  show Version.one @?= "Version {_major = 1, _minor = 0, _patch = 0}"
  show Package.core @?= "Name {_author = elm, _project = core}"

-- ✅ Test actual behavior and transformations  
testCase "name roundtrip works correctly" $ do
  let original = "test"
      name = Name.fromChars original
      result = Name.toChars name
  result @?= original
```

**Bad patterns:**

```haskell
-- ❌ MEANINGLESS: Testing that constants are different
testCase "predefined names have expected properties" $ do
  let mainName = Name._main
      trueName = Name.true
      falseName = Name.false
  assertBool "_main and true are different" (mainName /= trueName)  -- MEANINGLESS!
  assertBool "true and false are different" (trueName /= falseName)  -- MEANINGLESS!

-- ❌ MEANINGLESS: Testing that same constants are equal
testCase "version one has consistent value" $ do
  let v1 = Version.one
      v2 = Version.one
  v1 @?= v2  -- MEANINGLESS!

-- ❌ MEANINGLESS: Testing that show produces output
testCase "version one show instance" $ do
  let version = Version.one
      shown = show version
  assertBool "show produces non-empty result" (not (null shown))  -- MEANINGLESS!
```

### 6. **Ensure CLAUDE.md Compliance**

- **Function Size**: Test functions ≤15 lines, ≤4 params, ≤4 branches
- **Import Qualification**: Types unqualified, functions qualified, meaningful aliases
- **Lens Usage**: Use lenses for record access in test data setup
- **Documentation**: Complete Haddock docs for test module purpose
- **Error Handling**: Test all error paths with rich error types

### 7. **Register Tests in Main.hs**

Add new test module to `test/Main.hs`:

```haskell
import qualified Unit.YourModule.YourModuleTest as YourModuleTest

unitTests :: TestTree
unitTests = testGroup "Unit Tests"
  [ -- ... existing tests
  , YourModuleTest.tests
  ]
```

### 8. **Validate with Build Commands**

```bash
# Build and test
make build
make test

# Specific test suites
make test-unit           # Unit tests only
make test-property       # Property tests only
make test-integration    # Integration tests only
make test-match PATTERN="YourModule"  # Specific tests

# Quality assurance
make lint                # Check style compliance
make format              # Apply code formatting
make test-coverage       # Generate coverage report (≥80% required)

# Watch mode for development
make test-watch          # Continuous testing
```

### 9. **Coverage Analysis & Validation**

- Verify ≥80% coverage: `make test-coverage`
- Check coverage report in `.stack-work/install/*/doc/`
- Identify uncovered branches and add targeted tests
- Ensure all public APIs have corresponding tests

### 10. **Agent Validation & Quality Assurance**

- Use general-purpose agent to validate test completeness
- Verify adherence to CLAUDE.md standards
- Check test naming, structure, and documentation
- Validate integration with existing test suite

### 11. **Version Control & Integration**

**Conventional Commit Format:**

```bash
test(module): add comprehensive unit and property tests for ModuleName

- Add unit tests covering all public functions
- Implement property tests for invariants and laws
- Include golden tests for output verification
- Achieve 90% test coverage
- Follow CLAUDE.md testing standards
```

---

## Quality Benchmarks

### **Required Test Quality Standards:**

1. **Coverage**: Minimum 80% line coverage, aim for 90%+
2. **Completeness**: Every public function, type, and constructor tested
3. **Error Testing**: All error paths and edge cases covered
4. **Property Testing**: Laws and invariants verified with QuickCheck (Do not check if haskell works properly, do not just compare 2 values, the test are there to check if the functions give the expected output. So thats what we need to check)
5. **Documentation**: Clear test purpose and module behavior explanation
6. **Integration**: Proper registration in test suite with clear naming
7. **Performance**: Tests run efficiently without blocking development workflow

### **Reference Implementations:**

**Unit Test Excellence:**

- `test/Unit/Parse/PatternTest.hs` - Comprehensive parser testing
- `test/Unit/Data/NameTest.hs` - Data structure testing

**Property Test Excellence:**

- `test/Property/Data/NameProps.hs` - Invariant testing
- `test/Property/Canopy/VersionProps.hs` - Law verification

**Golden Test Excellence:**

- `test/Golden/JsGenGolden.hs` - Output verification
- `test/Golden/ParseModuleGolden.hs` - Parse result validation

**Integration Test Excellence:**

- `test/Integration/CompilerTest.hs` - End-to-end workflows

---

## Compliance Checklist

- [ ] Module analysis complete with public API mapping
- [ ] Existing test coverage audited and gaps identified
- [ ] Test classification applied (unit/property/golden/integration)
- [ ] CLAUDE.md import patterns followed exactly
- [ ] Test functions meet size/complexity limits
- [ ] Comprehensive test coverage implemented (≥80%)
- [ ] All error paths and edge cases tested
- [ ] Property tests for invariants and laws included
- [ ] Tests registered in Main.hs with proper naming
- [ ] Build commands pass (lint, format, test-coverage)
- [ ] Agent validation confirms completeness and quality
- [ ] Conventional commit message prepared
