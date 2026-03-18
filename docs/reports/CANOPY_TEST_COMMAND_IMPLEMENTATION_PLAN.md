# Canopy Test Command Implementation Plan

## Executive Summary

This document outlines the implementation plan for a general-purpose `canopy test` command that extends beyond FFI testing to provide comprehensive testing capabilities for Canopy projects, similar to `elm-test`.

**Status**: Research Complete - Ready for Implementation
**Priority**: High
**Estimated Effort**: 2-3 weeks
**Dependencies**: Existing test infrastructure (tasty, tasty-hunit, tasty-quickcheck, tasty-golden)

---

## 1. Current State Analysis

### 1.1 Existing Testing Infrastructure

The Canopy project has a **production-grade** testing infrastructure with:

| Component | Location | Details | Status |
|-----------|----------|---------|--------|
| Test Entry Point | `/test/Main.hs` | 253 lines, orchestrates 88+ test modules | ✅ Active |
| Unit Tests | `/test/Unit/` | 60+ enabled test suites across 26+ modules | ✅ Active |
| Property Tests | `/test/Property/` | 11 suites (QuickCheck-based) | ⚠️ Disabled (performance) |
| Integration Tests | `/test/Integration/` | 16+ suites | ⚠️ Mostly disabled (slow) |
| Golden Tests | `/test/Golden/` | 5 suites, 180+ golden files | ⚠️ Disabled |
| Test Framework | tasty, tasty-hunit, tasty-quickcheck, tasty-golden | Industry standard | ✅ Active |

**Test Coverage**: 88+ active test modules with comprehensive coverage of compiler subsystems.

### 1.2 Existing Test Commands

#### FFI Test Command (Recently Implemented)

**Command**: `canopy test-ffi`
**Location**: `/packages/canopy-terminal/src/Test/FFI.hs` (902 lines)
**Features**:
- Automatic test generation from FFI declarations
- Property-based testing (configurable runs: 50-500)
- Browser and Node.js execution
- File watching and re-running
- Contract validation
- JavaScript test runner generation

**Flags**:
```bash
--generate         # Generate test files only
--output DIR       # Output directory (default: test-generation/)
--watch            # Watch for changes
--validate-only    # Validate contracts only
--verbose          # Detailed output
--property-runs N  # Number of property test runs
--browser          # Run in browser vs Node.js
```

**Architecture Patterns** (to be reused):
```haskell
data FFITestConfig = FFITestConfig
  { ffiTestGenerate :: !Bool
  , ffiTestOutput :: !(Maybe FilePath)
  , ffiTestWatch :: !Bool
  , ffiTestValidateOnly :: !Bool
  , ffiTestVerbose :: !Bool
  , ffiTestPropertyRuns :: !(Maybe Int)
  , ffiTestBrowser :: !Bool
  }

run :: () -> FFITestConfig -> IO ()
```

### 1.3 CLI Command Structure

**Location**: `/packages/canopy-terminal/src/CLI/Commands.hs` (404 lines)
**Registration**: `/app/Main.hs` (108 lines)

**Command Pattern**:
```haskell
createCommandName :: Command
createCommandName =
  Terminal.Command "command-name" Terminal.Uncommon details example args flags Handler.run
  where
    details = "The `command-name` command does..."
    example = stackDocuments [...]
    args = Terminal.zeroOrMore Terminal.canopyFile
    flags = createCommandFlags
```

### 1.4 Build System Integration

**Makefile** (`/home/quinten/fh/canopy/Makefile`, 94 lines):
```makefile
test:              # Run all tests (stack test)
test-unit:         # Run unit tests only
test-property:     # Run property tests
test-integration:  # Run integration tests
test-golden:       # Run golden tests
test-coverage:     # Run with coverage report
test-watch:        # Continuous testing
test-match:        # Run specific test pattern
```

**Stack Configuration** (`package.yaml`):
```yaml
tests:
  canopy-tests:
    main: Main.hs
    source-dirs: test
    dependencies:
      - tasty
      - tasty-hunit
      - tasty-quickcheck
      - tasty-golden
```

---

## 2. Requirements Analysis

### 2.1 Core Requirements

#### Must Have (P0)
1. **Test Discovery**: Automatically find and run test files in project
2. **Multiple Test Types**: Support unit, property, and integration tests
3. **Test Output**: Clear, actionable test results with failure details
4. **Test Filtering**: Run specific tests by pattern/module/suite
5. **Watch Mode**: Re-run tests on file changes
6. **Exit Codes**: Proper exit codes for CI/CD integration
7. **Coverage Reporting**: Generate coverage reports

#### Should Have (P1)
8. **Test Generation**: Generate test templates for modules
9. **Parallel Execution**: Run tests concurrently for speed
10. **Golden Test Support**: Manage golden files (update, validate)
11. **Custom Test Runners**: Support for user-defined test frameworks
12. **Verbose/Quiet Modes**: Control output verbosity

#### Nice to Have (P2)
13. **Browser Testing**: Run tests in browser environment
14. **Performance Benchmarks**: Integrated benchmark support
15. **Test Statistics**: Track test execution time and history
16. **Interactive Mode**: Select tests interactively (like jest --watch)

### 2.2 User Stories

#### Story 1: Basic Test Running
```bash
# User wants to run all tests in project
$ canopy test
🧪 Canopy Test Suite
📄 Discovering tests in src/, test/, tests/
✅ Found 42 test modules

🚀 Running tests...
  Unit Tests (35 modules)
    ✅ Parser.Expression (12 tests, 0.15s)
    ✅ Type.Inference (23 tests, 0.43s)
    ✅ AST.Canonical (8 tests, 0.08s)
    ...

  Property Tests (7 modules)
    ✅ Version.Properties (100 runs, 0.22s)
    ...

📊 Test Results:
  Total: 342 tests
  Passed: 342
  Failed: 0
  Duration: 3.47s

✅ All tests passed!
```

#### Story 2: Focused Test Running
```bash
# User wants to run specific tests
$ canopy test --pattern "Parser"
🧪 Running tests matching pattern: Parser
  ✅ Parser.Expression (12 tests)
  ✅ Parser.Module (18 tests)
  ✅ Parser.Type (9 tests)

📊 39 tests passed in 0.67s
```

#### Story 3: Watch Mode
```bash
# User wants continuous testing during development
$ canopy test --watch
👀 Watching for changes in src/, test/...
🧪 Running tests...
✅ 342 tests passed

[File changed: src/Parse/Expression.hs]
🔄 Re-running tests...
❌ 1 test failed:
  Parser.Expression.test_parseIf
    Expected: Right (If ...)
    Got: Left (ParseError ...)

[File changed: src/Parse/Expression.hs]
🔄 Re-running tests...
✅ 342 tests passed
```

#### Story 4: Test Generation
```bash
# User wants to generate test template
$ canopy test --generate-template src/MyModule.can
📝 Generating test template...
✅ Created test/Unit/MyModuleTest.hs

Template includes:
  - Test module structure
  - Import statements
  - Example test cases
  - Property test examples
```

#### Story 5: Coverage Report
```bash
# User wants coverage analysis
$ canopy test --coverage
🧪 Running tests with coverage analysis...
✅ 342 tests passed

📊 Coverage Report:
  Overall: 87.3%

  By Module:
    Parser.Expression    95.2%  ████████████████░░░░
    Type.Inference       91.8%  ███████████████████░
    AST.Canonical        78.4%  ████████████████░░░░
    ...

  Detailed report: coverage/hpc_index.html
```

### 2.3 Technical Requirements

#### Test Discovery Algorithm
1. Scan project directories: `test/`, `tests/`, `src/`
2. Identify test files:
   - Pattern: `*Test.hs`, `*Tests.hs`, `*Spec.hs`, `*Props.hs`
   - Contains: `import Test.Tasty`, `tests :: TestTree`
3. Parse module exports to find test tree
4. Build test hierarchy

#### Test Execution Strategy
1. **Compilation**: Compile test modules dynamically or use pre-compiled
2. **Discovery**: Use tasty's `TestTree` discovery
3. **Filtering**: Apply pattern matching to test names
4. **Execution**: Run with tasty ingredients (console, XML, JSON)
5. **Reporting**: Format results for CLI display

#### File Watching Implementation
1. Use `fsnotify` or similar library
2. Watch directories: `src/`, `test/`, `tests/`
3. Debounce file changes (500ms)
4. Re-compile and re-run affected tests
5. Smart invalidation based on dependency graph

---

## 3. Architecture Design

### 3.1 Module Structure

```
packages/canopy-terminal/src/Test/
├── General.hs              -- Main test command implementation (new)
├── Discovery.hs            -- Test discovery logic (new)
├── Runner.hs               -- Test execution engine (new)
├── Watcher.hs              -- File watching and re-running (new)
├── Coverage.hs             -- Coverage analysis (new)
├── Templates.hs            -- Test template generation (new)
├── Types.hs                -- Test command types (new)
└── FFI.hs                  -- Existing FFI testing (902 lines)
```

### 3.2 Core Types

```haskell
-- Test/Types.hs
{-# LANGUAGE OverloadedStrings #-}
module Test.Types where

import qualified Data.Text as Text
import Data.Text (Text)

-- | Configuration for general test command
data TestConfig = TestConfig
  { testPattern :: !(Maybe Text)
    -- ^ Pattern to filter tests (regex or glob)
  , testWatch :: !Bool
    -- ^ Watch for file changes and re-run tests
  , testCoverage :: !Bool
    -- ^ Generate coverage report
  , testVerbose :: !Bool
    -- ^ Verbose output with detailed test information
  , testQuiet :: !Bool
    -- ^ Minimal output (only failures)
  , testParallel :: !Bool
    -- ^ Run tests in parallel (default: True)
  , testJobs :: !(Maybe Int)
    -- ^ Number of parallel test jobs
  , testSeed :: !(Maybe Int)
    -- ^ Random seed for property tests
  , testOutput :: !(Maybe FilePath)
    -- ^ Output directory for reports
  , testGenerateTemplate :: !(Maybe FilePath)
    -- ^ Generate test template for module
  , testUpdateGolden :: !Bool
    -- ^ Update golden files instead of comparing
  , testTimeout :: !(Maybe Int)
    -- ^ Timeout per test in seconds
  , testFailFast :: !Bool
    -- ^ Stop on first failure
  } deriving (Eq, Show)

-- | Test discovery result
data TestModule = TestModule
  { testModulePath :: !FilePath
    -- ^ Path to test file
  , testModuleName :: !Text
    -- ^ Module name
  , testModuleType :: !TestType
    -- ^ Type of tests in module
  , testModuleSuite :: !Text
    -- ^ Test suite name (extracted from tests :: TestTree)
  } deriving (Eq, Show)

-- | Type of test module
data TestType
  = UnitTest      -- ^ Unit tests (tasty-hunit)
  | PropertyTest  -- ^ Property-based tests (tasty-quickcheck)
  | GoldenTest    -- ^ Golden file tests (tasty-golden)
  | IntegrationTest -- ^ Integration tests
  deriving (Eq, Show)

-- | Test execution result
data TestResult = TestResult
  { testResultTotal :: !Int
    -- ^ Total number of tests
  , testResultPassed :: !Int
    -- ^ Number of passed tests
  , testResultFailed :: !Int
    -- ^ Number of failed tests
  , testResultSkipped :: !Int
    -- ^ Number of skipped tests
  , testResultDuration :: !Double
    -- ^ Total duration in seconds
  , testResultFailures :: ![TestFailure]
    -- ^ List of test failures
  } deriving (Eq, Show)

-- | Test failure information
data TestFailure = TestFailure
  { testFailureName :: !Text
    -- ^ Name of failed test
  , testFailureMessage :: !Text
    -- ^ Failure message
  , testFailureLocation :: !(Maybe Text)
    -- ^ Source location (file:line)
  } deriving (Eq, Show)
```

### 3.3 Implementation Plan

#### Module 1: Test/Types.hs (Core Types)
**Lines**: ~150
**Dependencies**: None
**Implementation Time**: 2 hours
**Tests**: Type definitions (no logic to test)

```haskell
module Test.Types
  ( TestConfig(..)
  , TestModule(..)
  , TestType(..)
  , TestResult(..)
  , TestFailure(..)
  , defaultTestConfig
  ) where
```

#### Module 2: Test/Discovery.hs (Test Discovery)
**Lines**: ~300
**Dependencies**: Test.Types
**Implementation Time**: 1 day
**Tests**: Unit tests for discovery logic

```haskell
module Test.Discovery
  ( discoverTests
  , findTestFiles
  , parseTestModule
  , classifyTestType
  ) where

-- | Discover all test modules in project
discoverTests :: FilePath -> IO [TestModule]

-- | Find test files matching patterns
findTestFiles :: [FilePath] -> IO [FilePath]

-- | Parse test module to extract metadata
parseTestModule :: FilePath -> IO (Either Text TestModule)

-- | Classify test type based on imports
classifyTestType :: [Text] -> TestType
```

**Algorithm**:
1. Scan directories: `test/`, `tests/`, `src/`
2. Find files: `*Test.hs`, `*Tests.hs`, `*Spec.hs`, `*Props.hs`
3. Parse imports to determine test type:
   - `Test.Tasty.HUnit` → UnitTest
   - `Test.Tasty.QuickCheck` → PropertyTest
   - `Test.Tasty.Golden` → GoldenTest
4. Extract `tests :: TestTree` definition
5. Build TestModule structure

#### Module 3: Test/Runner.hs (Test Execution)
**Lines**: ~400
**Dependencies**: Test.Types, Test.Discovery
**Implementation Time**: 2 days
**Tests**: Integration tests

```haskell
module Test.Runner
  ( runTests
  , compileTests
  , executeTestTree
  , formatResults
  ) where

-- | Run discovered tests with configuration
runTests :: TestConfig -> [TestModule] -> IO TestResult

-- | Compile test modules
compileTests :: [TestModule] -> IO (Either Text FilePath)

-- | Execute test tree with tasty
executeTestTree :: TestConfig -> TestTree -> IO TestResult

-- | Format test results for display
formatResults :: TestResult -> Doc
```

**Execution Strategy**:
1. **Option A: Dynamic Compilation** (Preferred)
   - Use GHC API to compile test modules dynamically
   - Load compiled modules using `System.Plugins`
   - Extract `tests :: TestTree` from loaded modules
   - Run with tasty ingredients

2. **Option B: Static Compilation** (Fallback)
   - Generate temporary `Main.hs` that imports all test modules
   - Compile with `stack build` or `cabal build`
   - Execute resulting binary
   - Parse output for results

**Recommendation**: Start with Option B (static compilation) for reliability, migrate to Option A if dynamic loading proves necessary.

#### Module 4: Test/Watcher.hs (File Watching)
**Lines**: ~250
**Dependencies**: Test.Types, Test.Runner
**Implementation Time**: 1 day
**Tests**: Integration tests (manual)

```haskell
module Test.Watcher
  ( watchAndRun
  , setupWatcher
  , debounceChanges
  ) where

import qualified System.FSNotify as FSNotify

-- | Watch for file changes and re-run tests
watchAndRun :: TestConfig -> [TestModule] -> IO ()

-- | Set up file system watcher
setupWatcher :: [FilePath] -> (FilePath -> IO ()) -> IO ()

-- | Debounce file changes to avoid rapid re-runs
debounceChanges :: Int -> IO () -> IO (IO ())
```

**Implementation**:
1. Use `fsnotify` library (already used in `Watch.hs`)
2. Watch directories: `src/`, `test/`, `tests/`
3. Filter events: only `.hs`, `.can`, `.canopy` files
4. Debounce: 500ms delay before re-running
5. Smart invalidation: only re-run affected tests (future enhancement)

#### Module 5: Test/Coverage.hs (Coverage Analysis)
**Lines**: ~200
**Dependencies**: Test.Types
**Implementation Time**: 1 day
**Tests**: Unit tests

```haskell
module Test.Coverage
  ( generateCoverage
  , parseCoverageReport
  , formatCoverageReport
  ) where

-- | Generate coverage report using HPC
generateCoverage :: TestConfig -> [TestModule] -> IO (Either Text CoverageReport)

-- | Parse HPC tix/mix files
parseCoverageReport :: FilePath -> IO (Either Text CoverageReport)

-- | Format coverage for CLI display
formatCoverageReport :: CoverageReport -> Doc
```

**Implementation**:
1. Use Haskell Program Coverage (HPC) tool
2. Compile tests with coverage flags: `-fhpc`
3. Run tests to generate `.tix` files
4. Parse `.tix` and `.mix` files
5. Calculate coverage percentages
6. Generate HTML report using `hpc markup`

#### Module 6: Test/Templates.hs (Test Generation)
**Lines**: ~300
**Dependencies**: Test.Types
**Implementation Time**: 1 day
**Tests**: Unit tests

```haskell
module Test.Templates
  ( generateTestTemplate
  , generateUnitTestTemplate
  , generatePropertyTestTemplate
  , parseModuleInfo
  ) where

-- | Generate test template for module
generateTestTemplate :: FilePath -> IO (Either Text FilePath)

-- | Generate unit test template
generateUnitTestTemplate :: ModuleInfo -> Text

-- | Generate property test template
generatePropertyTestTemplate :: ModuleInfo -> Text

-- | Parse module to extract functions
parseModuleInfo :: FilePath -> IO (Either Text ModuleInfo)
```

**Templates**:

```haskell
-- Unit Test Template
module Test.Unit.ModuleNameTest where

import Test.Tasty
import Test.Tasty.HUnit
import qualified ModuleName as ModuleName

tests :: TestTree
tests = testGroup "ModuleName Tests"
  [ testGroup "functionName"
      [ testCase "basic functionality" $
          ModuleName.functionName input @?= expected
      , testCase "edge case: empty input" $
          ModuleName.functionName "" @?= defaultValue
      ]
  ]

-- Property Test Template
module Test.Property.ModuleNameProps where

import Test.Tasty
import Test.Tasty.QuickCheck
import qualified ModuleName as ModuleName

tests :: TestTree
tests = testGroup "ModuleName Properties"
  [ testProperty "roundtrip property" $ \input ->
      ModuleName.inverse (ModuleName.functionName input) == input
  ]
```

#### Module 7: Test/General.hs (Main Command)
**Lines**: ~400
**Dependencies**: All above modules
**Implementation Time**: 2 days
**Tests**: Integration tests

```haskell
module Test.General
  ( run
  , runWithConfig
  , TestConfig(..)
  , defaultTestConfig
  , patternParser
  , jobsParser
  ) where

import qualified Test.Discovery as Discovery
import qualified Test.Runner as Runner
import qualified Test.Watcher as Watcher
import qualified Test.Coverage as Coverage
import qualified Test.Templates as Templates

-- | Main entry point for test command
run :: () -> TestConfig -> IO ()
run _args config = do
  putStrLn "🧪 Canopy Test Suite"
  putStrLn ""

  if isJust (testGenerateTemplate config)
    then Templates.generateTestTemplate (fromJust (testGenerateTemplate config))
    else if testWatch config
      then runWithWatch config
      else runOnce config

-- | Run tests once
runOnce :: TestConfig -> IO Exit.ExitCode

-- | Run tests with file watching
runWithWatch :: TestConfig -> IO Exit.ExitCode
```

### 3.4 CLI Integration

#### CLI/Commands.hs Changes

Add to `/packages/canopy-terminal/src/CLI/Commands.hs`:

```haskell
import qualified Test.General as TestGeneral

-- | Create the test command for running Canopy tests.
createTestCommand :: Command
createTestCommand =
  Terminal.Command "test" Terminal.Uncommon details example Terminal.noArgs flags TestGeneral.run
  where
    details = createTestDetails
    example = createTestExample
    flags = createTestFlags

createTestDetails :: String
createTestDetails =
  "The `test` command runs Canopy tests with support for unit tests, property tests, and integration tests:"

createTestExample :: Doc
createTestExample =
  stackDocuments
    [ reflowText "For example:",
      P.indent 4 $ P.green "canopy test",
      reflowText "This runs all tests in your project.",
      P.indent 4 $ P.green "canopy test --pattern Parser",
      reflowText "This runs only tests matching 'Parser'.",
      P.indent 4 $ P.green "canopy test --watch",
      reflowText "This watches for changes and re-runs tests automatically."
    ]

createTestFlags :: Terminal.Flags TestGeneral.TestConfig
createTestFlags =
  Terminal.flags TestGeneral.TestConfig
    |-- Terminal.flag "pattern" TestGeneral.patternParser "Filter tests by pattern (regex or glob)"
    |-- Terminal.onOff "watch" "Watch for file changes and re-run tests"
    |-- Terminal.onOff "coverage" "Generate coverage report"
    |-- Terminal.onOff "verbose" "Verbose output with detailed test information"
    |-- Terminal.onOff "quiet" "Minimal output (only failures)"
    |-- Terminal.onOff "parallel" "Run tests in parallel (default: true)"
    |-- Terminal.flag "jobs" TestGeneral.jobsParser "Number of parallel test jobs"
    |-- Terminal.flag "seed" TestGeneral.seedParser "Random seed for property tests"
    |-- Terminal.flag "output" TestGeneral.outputParser "Output directory for reports"
    |-- Terminal.flag "generate-template" TestGeneral.templateParser "Generate test template for module"
    |-- Terminal.onOff "update-golden" "Update golden files instead of comparing"
    |-- Terminal.flag "timeout" TestGeneral.timeoutParser "Timeout per test in seconds"
    |-- Terminal.onOff "fail-fast" "Stop on first failure"
```

#### app/Main.hs Changes

Add to `/app/Main.hs`:

```haskell
import CLI.Commands
  ( ...
  , createTestCommand  -- Add this
  )

createAllCommands :: [Terminal.Command]
createAllCommands =
  [ createReplCommand,
    createInitCommand,
    createReactorCommand,
    createMakeCommand,
    createTestCommand,      -- Add this line
    createFFITestCommand,
    createInstallCommand,
    createBumpCommand,
    createDiffCommand,
    createPublishCommand
  ]
```

---

## 4. Implementation Timeline

### Phase 1: Foundation (Week 1)
**Goal**: Core infrastructure and type system

- [ ] Day 1-2: Implement `Test/Types.hs` (core types and configuration)
- [ ] Day 3-5: Implement `Test/Discovery.hs` (test discovery logic)
- [ ] Write unit tests for discovery
- [ ] Integration with existing test infrastructure

**Deliverables**:
- Type definitions with comprehensive Haddock docs
- Test discovery working for existing test suite
- Unit tests with 80%+ coverage

### Phase 2: Test Execution (Week 2)
**Goal**: Basic test running capability

- [ ] Day 1-3: Implement `Test/Runner.hs` (static compilation approach)
- [ ] Day 4: Implement `Test/Templates.hs` (test generation)
- [ ] Day 5: CLI integration (`CLI/Commands.hs`, `app/Main.hs`)
- [ ] Write integration tests

**Deliverables**:
- Working `canopy test` command
- Test filtering by pattern
- Template generation
- Integration tests

**Milestone**: MVP - Basic test command functional

### Phase 3: Advanced Features (Week 3)
**Goal**: Watch mode, coverage, polish

- [ ] Day 1-2: Implement `Test/Watcher.hs` (file watching)
- [ ] Day 3-4: Implement `Test/Coverage.hs` (coverage reporting)
- [ ] Day 5: Polish, documentation, final integration tests

**Deliverables**:
- Watch mode with debouncing
- Coverage reports (text and HTML)
- Complete documentation
- Comprehensive test suite

**Milestone**: Feature Complete

### Phase 4: Testing and Documentation (Week 4, optional)
**Goal**: Production readiness

- [ ] End-to-end testing
- [ ] User documentation
- [ ] Performance optimization
- [ ] Bug fixes and polish

**Deliverables**:
- User guide with examples
- Performance benchmarks
- CI/CD integration examples

---

## 5. Testing Strategy

### 5.1 Unit Tests

Create comprehensive unit tests for each module:

```
test/Unit/Test/
├── TypesTest.hs              -- Test type definitions and defaults
├── DiscoveryTest.hs          -- Test discovery logic
├── RunnerTest.hs             -- Test runner logic
├── WatcherTest.hs            -- Test watcher logic (mock)
├── CoverageTest.hs           -- Test coverage parsing
└── TemplatesTest.hs          -- Test template generation
```

**Coverage Target**: ≥80% for all modules

### 5.2 Integration Tests

Create integration tests:

```
test/Integration/
├── TestCommandIntegrationTest.hs  -- End-to-end test command
├── TestDiscoveryTest.hs           -- Test discovery on real projects
└── TestRunnerTest.hs              -- Test execution on real tests
```

### 5.3 Golden Tests

Create golden tests for:
- Template generation output
- Test result formatting
- Coverage report formatting

---

## 6. Dependencies

### 6.1 Required Dependencies

Add to `package.yaml`:

```yaml
dependencies:
  # Existing dependencies...
  - fsnotify >= 0.4       # File system watching
  - hpc >= 0.6            # Coverage analysis
  - process >= 1.6        # Process execution
  - directory >= 1.3      # File system operations
  - filepath >= 1.4       # File path manipulation
  - unix >= 2.7           # POSIX operations (for timeouts)
```

### 6.2 Optional Dependencies

Consider for future enhancements:

```yaml
  - plugins >= 1.6        # Dynamic module loading
  - ghc >= 9.8            # GHC API for dynamic compilation
  - async >= 2.2          # Async test execution
```

---

## 7. Documentation Plan

### 7.1 User Documentation

Create user guide:

```markdown
# Canopy Test Command Guide

## Quick Start
canopy test                    # Run all tests
canopy test --watch            # Watch mode
canopy test --coverage         # Generate coverage

## Test Discovery
Canopy discovers tests in:
- test/Unit/*.hs
- test/Property/*.hs
- test/Integration/*.hs
- test/Golden/*.hs

## Writing Tests
... (examples for unit, property, integration, golden tests)

## Configuration
... (flags and options)
```

### 7.2 Developer Documentation

Create implementation guide:

```markdown
# Test Command Implementation Guide

## Architecture
... (module structure, design decisions)

## Extending the Test Command
... (adding new test types, custom runners)

## Testing the Test Command
... (meta-testing strategies)
```

---

## 8. Risk Analysis

### 8.1 Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Dynamic compilation complexity | High | High | Use static compilation approach first |
| File watching reliability | Medium | Medium | Use battle-tested `fsnotify` library |
| Test discovery edge cases | Medium | Medium | Comprehensive unit tests |
| Coverage integration issues | Low | Medium | Fallback to manual HPC invocation |
| Performance with large test suites | Medium | High | Implement parallel execution early |

### 8.2 Project Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Scope creep | High | High | Strict MVP definition, phase-based delivery |
| Integration complexity | Medium | High | Early integration with existing CLI |
| User expectations | Medium | Medium | Clear documentation of limitations |
| Breaking existing tests | Low | High | Comprehensive integration testing |

---

## 9. Success Criteria

### 9.1 Functional Requirements

- [ ] Test discovery finds all test modules
- [ ] Test execution runs all test types (unit, property, integration, golden)
- [ ] Test filtering works with patterns
- [ ] Watch mode detects changes and re-runs tests
- [ ] Coverage reports generate correctly
- [ ] Template generation creates valid test files
- [ ] Exit codes work correctly for CI/CD
- [ ] Error messages are clear and actionable

### 9.2 Non-Functional Requirements

- [ ] Performance: Test suite completes in <5 seconds for small projects
- [ ] Reliability: No false positives/negatives
- [ ] Usability: Intuitive CLI with helpful error messages
- [ ] Maintainability: Code follows CLAUDE.md standards
- [ ] Documentation: Complete user and developer guides
- [ ] Test Coverage: ≥80% for all new modules

### 9.3 User Acceptance

- [ ] Users can run tests with zero configuration
- [ ] Watch mode provides fast feedback loop (<1s)
- [ ] Coverage reports are easy to understand
- [ ] Template generation saves significant time
- [ ] Error messages help users fix issues quickly

---

## 10. Future Enhancements

### 10.1 Phase 2 Features (Post-MVP)

1. **Snapshot Testing**: Similar to Jest snapshots
2. **Test Profiling**: Identify slow tests
3. **Interactive Mode**: Select tests interactively (like jest --watch)
4. **Test Splitting**: Split tests across multiple CI jobs
5. **Test Retries**: Retry flaky tests automatically
6. **Custom Test Frameworks**: Support for non-tasty frameworks

### 10.2 Advanced Features

7. **Browser Testing**: Run tests in browser environment (extend FFI approach)
8. **Mutation Testing**: Detect test suite weaknesses
9. **Fuzz Testing**: Automated fuzzing with AFL or similar
10. **Visual Regression Testing**: Screenshot comparison
11. **Test Impact Analysis**: Only run tests affected by changes
12. **Test Prioritization**: Run likely-to-fail tests first

---

## 11. References

### 11.1 Similar Tools

- **elm-test**: Elm's test framework (inspiration)
- **jest**: JavaScript test runner (watch mode inspiration)
- **cargo test**: Rust's test command (pattern matching)
- **pytest**: Python test framework (discovery algorithm)

### 11.2 Documentation

- [Tasty Documentation](https://hackage.haskell.org/package/tasty)
- [HPC Guide](https://wiki.haskell.org/Haskell_program_coverage)
- [FSNotify Documentation](https://hackage.haskell.org/package/fsnotify)

### 11.3 Existing Code

- `/packages/canopy-terminal/src/Test/FFI.hs` - FFI test implementation (902 lines)
- `/test/Main.hs` - Test suite entry point (253 lines)
- `/packages/canopy-terminal/src/CLI/Commands.hs` - CLI commands (404 lines)
- `/packages/canopy-terminal/src/Watch.hs` - File watching example

---

## 12. Questions for User

Before proceeding with implementation, clarify:

1. **Priority**: Is this high priority or can it wait?
2. **Scope**: Should we start with MVP (Phase 1-2) or full implementation?
3. **Integration**: Should `canopy test` replace `canopy test-ffi` or complement it?
4. **Naming**: Is `canopy test` the right name, or should it be `canopy test-run` or similar?
5. **Compatibility**: Should it work with existing `/test/Main.hs` or require new structure?
6. **Coverage**: Is HPC-based coverage acceptable or do we need custom solution?

---

## Conclusion

This implementation plan provides a comprehensive roadmap for implementing a general-purpose `canopy test` command. The phased approach allows for incremental delivery with clear milestones, while the modular architecture ensures maintainability and extensibility.

**Recommendation**: Start with **Phase 1-2 (MVP)** to deliver basic functionality quickly, then iterate based on user feedback.

**Next Steps**:
1. User approval of plan
2. Create implementation tasks in todo list
3. Begin Phase 1 implementation
4. Regular progress reviews

---

**Document Version**: 1.0
**Last Updated**: 2025-11-10
**Author**: Research Agent
**Status**: Ready for Review
