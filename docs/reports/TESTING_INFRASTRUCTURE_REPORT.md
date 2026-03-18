# Canopy Compiler Testing Infrastructure Analysis

## Executive Summary

The Canopy compiler project has a comprehensive multi-level testing infrastructure with over 100 test suites organized into Unit, Property, Integration, and Golden test categories. Tests are currently managed through Tasty framework and coordinated via Stack and Makefile. There is currently **no general-purpose `canopy test` CLI command**, though a specialized `canopy test-ffi` command exists for FFI validation.

**Key Finding**: The project uses a hybrid testing approach where:
- Main test suite runs via `stack test canopy:canopy-test`
- A separate FFI testing command exists (`Test.FFI`)
- Tests are currently organized in `/test` directory within the root project
- Some tests are also organized within individual packages (e.g., `canopy-core/test/`)

---

## 1. Current Test Setup and Organization

### 1.1 Test Directory Structure

```
test/
├── Unit/                    # Unit tests (enabled)
│   ├── AST/
│   ├── Builder/
│   ├── CLI/
│   ├── Canopy/
│   ├── Data/
│   ├── Develop/
│   ├── Diff/
│   ├── File/
│   ├── Foreign/             # New: FFI type parsing tests
│   ├── Init/
│   ├── Install/
│   ├── Json/
│   ├── Make/
│   ├── New/
│   ├── Parse/
│   ├── Queries/
│   ├── Query/
│   ├── Terminal/
│   └── [50+ test files]
├── Property/                # Property tests (currently disabled)
│   ├── AST/
│   ├── Canopy/
│   ├── Data/
│   └── Terminal/
├── Integration/             # Integration tests (mostly disabled)
│   ├── Terminal/
│   ├── *.hs files          # [17 integration test files]
│   └── [Disabled: slow I/O, real compilation]
├── Golden/                  # Golden tests (disabled)
│   ├── expected/           # Expected output files
│   ├── sources/            # Source input files
│   └── [5 golden test files]
├── benchmark/              # Benchmark infrastructure
│   ├── README.md
│   ├── ArithmeticBench.can
│   ├── analyze-codegen.js
│   └── runtime-benchmark.js
├── fixtures/               # Test fixtures
├── test-cases/            # Test case data
├── Main.hs                # Test suite entry point
└── [Documentation files]
```

### 1.2 Package-Level Tests

The multi-package structure includes separate test suites:

```
packages/
├── canopy-core/
│   └── test/
│       ├── Unit/           # Core compiler unit tests
│       ├── Property/       # Core property tests
│       ├── Golden/         # Core golden tests
│       ├── Benchmark/      # Compiler benchmarks
│       └── NameReversalTest.hs
├── canopy-builder/
├── canopy-driver/
├── canopy-query/
└── canopy-terminal/
    ├── src/
    │   ├── Make.hs
    │   ├── Install.hs
    │   ├── Repl.hs
    │   ├── Test/
    │   │   └── FFI.hs      # FFI testing module
    │   └── CLI/
    │       └── Commands.hs
    └── impl/               # Terminal implementation
```

### 1.3 Test Frameworks and Dependencies

**Primary Test Framework**: Tasty
- Framework for organizing and running tests
- Supports pattern-based test selection
- File watching support

**Test Libraries**:
- `Test.Tasty` - Main test framework
- `Test.Tasty.HUnit` - Unit testing with assertions (`@?=`)
- `Test.Tasty.QuickCheck` - Property-based testing
- `Test.Tasty.Golden` - Golden file comparison tests

**Custom Infrastructure**:
- `Foreign.FFI` - FFI function interfaces
- `Foreign.TestGeneratorNew` - Test generation for FFI
- Custom Test.FFI module for FFI-specific testing

---

## 2. Test Execution Infrastructure

### 2.1 Current Test Commands (via Makefile)

```bash
# Main test targets
make test                   # Run all tests (currently only Unit)
make test-unit              # Unit tests only
make test-property          # Property tests only (disabled)
make test-integration       # Integration tests (mostly disabled)
make test-match PATTERN=    # Pattern-based test selection

# Development workflow
make test-watch             # Watch mode for tests
make test-coverage          # Generate coverage reports

# Build-related
make test-build             # Build without running
make test-deps              # Install dependencies
```

### 2.2 Test Execution Details

**Stack Test Configuration**:
```bash
# Main invocation
stack test --fast canopy:canopy-test

# Pattern-based filtering
stack test --fast canopy:canopy-test --test-arguments "--pattern \"Unit\""
stack test --fast canopy:canopy-test --test-arguments "--pattern \"Parse.Expression\""

# Watch mode
stack test --fast canopy:canopy-test --file-watch

# Coverage
stack test --coverage --fast canopy:canopy-test
```

**Current Status**:
- Unit tests: Fully enabled (~70+ tests across 50+ files)
- Property tests: Disabled (line 122 in Main.hs)
- Integration tests: Mostly disabled (file I/O, real compilation)
- Golden tests: Disabled

### 2.3 Test Discovery and Organization

**Test Suite Entry Point**: `test/Main.hs`

The main test runner imports all test modules and organizes them hierarchically:

```haskell
tests :: TestTree
tests =
  testGroup "Canopy Tests"
    [ unitTests
      -- propertyTests        -- DISABLED
      -- integrationTests     -- DISABLED (slow I/O)
      -- goldenTests          -- DISABLED (may compile packages)
    ]
```

**Test Module Pattern**:
Each test module exports a `tests :: TestTree` function:
```haskell
module Unit.Parse.ExpressionTest (tests) where

tests :: TestTree
tests = testGroup "Parse.Expression" [...]
```

---

## 3. Terminal/CLI Command Structure

### 3.1 CLI Architecture Overview

**Main Entry Point**: `app/Main.hs`
- Orchestrates the entire CLI application
- Registers all available commands
- Delegates to Terminal framework

**Command Registration** (`packages/canopy-terminal/src/CLI/Commands.hs`):
```haskell
createAllCommands :: [Terminal.Command]
createAllCommands =
  [ createReplCommand
  , createInitCommand
  , createReactorCommand
  , createMakeCommand
  , createFFITestCommand        -- Existing FFI test command
  , createInstallCommand
  , createBumpCommand
  , createDiffCommand
  , createPublishCommand
  ]
```

### 3.2 Available CLI Commands

| Command | Module | Purpose | Status |
|---------|--------|---------|--------|
| `repl` | Repl.hs | Interactive programming | Active |
| `init` | Init.hs | Project initialization | Active |
| `reactor` | Develop.hs | Dev server with hot reload | Active |
| `make` | Make.hs | Compile to JS/HTML | Active |
| `test-ffi` | Test.FFI | FFI validation/testing | Active |
| `install` | Install.hs | Package installation | Active |
| `publish` | Publish.hs | Package publishing | Active |
| `bump` | Bump.hs | Version management | Active |
| `diff` | Diff.hs | API change detection | Active |

### 3.3 Command Implementation Pattern

**Standard Command Definition** (from CLI/Commands.hs):
```haskell
createMakeCommand :: Command
createMakeCommand =
  Terminal.Command 
    "make"                      -- Command name
    Terminal.Uncommon           -- Frequency
    details                     -- Help text
    example                     -- Usage example
    args                        -- Argument parser
    flags                       -- Flag parser
    Make.run                    -- Handler function
```

**Command Handler Signature**:
```haskell
run :: Flags -> IO Exit.Code
```

Where `Flags` is specific to each command:
- `Make.Flags` - Build options (output, optimization, etc.)
- `Develop.Flags` - Development server options (port, etc.)
- `FFI.FFITestConfig` - FFI test options

### 3.4 Terminal Framework Components

**Location**: `packages/canopy-terminal/impl/Terminal/`

| Module | Purpose |
|--------|---------|
| `Terminal.hs` | Main entry point |
| `Terminal.Application.hs` | Application lifecycle |
| `Terminal.Command.hs` | Command execution |
| `Terminal.Parser.hs` | Argument parsing |
| `Terminal.Chomp.hs` | Parsing utilities |
| `Terminal.Error.hs` | Error handling |
| `Terminal.Types.hs` | Type definitions |
| `Terminal.Helpers.hs` | Utility functions |

---

## 4. Builder/Compiler Integration with Tests

### 4.1 Compiler Package Structure

**canopy-core** (Compiler):
- Handles parsing, canonicalization, type checking, optimization, code generation
- Has its own test suite: `packages/canopy-core/test/`
- Includes arithmetic operator tests (native operators feature)

**canopy-builder** (Build System):
- Dependency resolution
- Project configuration
- Package management
- Integrated with CLI commands

**canopy-query** (Query System):
- Module querying
- Interface inspection

**canopy-driver** (Driver):
- High-level compilation orchestration

### 4.2 Test-Related Functions

**Make Module** (`packages/canopy-terminal/src/Make.hs`):
```haskell
module Make
  ( Flags(..)
  , Output(..)
  , ReportType(..)
  , run                  -- Main handler
  , reportType           -- Parser
  , output              -- Parser
  , docsFile            -- Parser
  )
```

**Develop Module** (reactor/development server):
- Not directly test-related but used by dev workflow

### 4.3 FFI Testing Infrastructure

**FFI Module** (`packages/canopy-terminal/src/Test/FFI.hs`):
```haskell
data FFITestConfig = FFITestConfig
  { ffiTestGenerate :: Bool      -- Generate test files
  , ffiTestOutput :: Maybe FilePath
  , ffiTestWatch :: Bool         -- Watch mode
  , ffiTestValidateOnly :: Bool  -- Validate contracts only
  , ffiTestVerbose :: Bool
  , ffiTestPropertyRuns :: Maybe Int
  , ffiTestBrowser :: Bool       -- Run in browser
  }

-- Key functions
run :: FFITestConfig -> IO Exit.Code
generateTests :: FilePath -> IO ()
validateContracts :: FilePath -> IO ()
runWithWatch :: FilePath -> IO ()
```

**FFI Dependencies**:
- `Foreign.FFI` - FFI interface definitions
- `Foreign.TestGeneratorNew` - Test generation
- `Make` module - Uses for compilation

### 4.4 canopy.json Project Configuration

Currently, test configuration in `canopy.json` is minimal:

```json
{
  "type": "application",
  "canopy-version": "0.19.1",
  "dependencies": {...},
  "test-dependencies": {
    "direct": {},
    "indirect": {}
  }
}
```

**Note**: No explicit test configuration section exists yet

---

## 5. Coverage and Reporting Infrastructure

### 5.1 Current Coverage Setup

**Command**:
```bash
make test-coverage          # Generates coverage reports
stack test --coverage --fast canopy:canopy-test
```

**Output Location**:
```
.stack-work/install/*/doc/  # Coverage HTML reports
```

**Coverage Tool**: Stack's built-in coverage support (using hpc)

### 5.2 Test Reporting

**Test Status Reporting**:
- Tasty prints test results to stdout
- Standard HUnit assertions: `@?=` for equality checks
- Custom assertions for specific tests

**Performance Metrics**:
- From IMPLEMENTATION-SUMMARY.md: ~5 minutes for full suite (only Unit enabled)
- Target: ~2.5 minutes (50% improvement)

### 5.3 Benchmark Infrastructure

**Location**: `test/benchmark/`

**Components**:
- `ArithmeticBench.can` - Test code for arithmetic operators
- `analyze-codegen.js` - JavaScript codegen analysis
- `runtime-benchmark.js` - Runtime performance benchmarks
- `README.md` - Benchmark documentation

**Purpose**: 
- Validate native arithmetic operator performance
- Analyze generated JavaScript code
- Compare runtime performance

---

## 6. Current Test Statistics

### 6.1 Test Coverage

From `test/Main.hs`:

**Enabled Tests**:
- ~70+ Unit tests across 50+ files
- ~70 total test groups in Main.hs

**Disabled Tests**:
- Property tests (~12 test suites) - Line 122
- Integration tests (~20 test files) - Most disabled due to:
  - Slow file I/O operations
  - Real package compilation
  - Network operations
- Golden tests (~5 test files) - Brittle string matching

**Total Test Modules Imported**: 50+

### 6.2 Known Issues and Limitations

From `test/IMPLEMENTATION-SUMMARY.md`:

| Category | Count | Status |
|----------|-------|--------|
| Total test files | 107 | Active |
| Source files tested | 282 | ~80% coverage needed |
| Anti-pattern violations | 150+ | Refactoring needed |
| Show test violations | 37 | Priority 1 |
| Lens test violations | 113 | Priority 2 |
| Modules without tests | 8+ | Need new tests |

**Test Execution Time**: ~5 minutes (unit tests only)

---

## 7. Test Frameworks and Patterns

### 7.1 Unit Test Pattern

```haskell
module Unit.Parse.ExpressionTest (tests) where

import qualified AST.Source as Src
import qualified Parse.Expression as Expr
import Test.Tasty
import Test.Tasty.HUnit

parseExpr :: String -> Either Error Src.Expr
parseExpr s = -- parsing logic

tests :: TestTree
tests = testGroup "Parse.Expression"
  [ testGroup "literals"
      [ testCase "int" $ case parseExpr "42" of
          Right (At _ (Int 42)) -> return ()
          other -> assertFailure ("unexpected: " <> show other)
      , testCase "float" $ case parseExpr "3.14" of
          Right (At _ (Float _)) -> return ()
          _ -> assertFailure "expected Float"
      ]
  ]
```

### 7.2 Property Test Pattern

**Example**: `test/Property/Canopy/VersionProps.hs`

```haskell
module Property.Canopy.VersionProps (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck as QC

props :: TestTree
props = testGroup "Version Properties"
  [ QC.testProperty "roundtrip property" $ \v ->
      Version.fromChars (Version.toChars v) == Just v
  , QC.testProperty "ordering transitivity" $ \a b c ->
      (a < b && b < c) ==> (a < c)
  ]
```

### 7.3 Integration Test Pattern

**Example**: `test/Integration/InitTest.hs`

Tests that exercise multiple components:
- File system operations
- Project initialization
- Configuration validation
- Build integration

### 7.4 Golden Test Pattern

**Example**: `test/Golden/ParseModuleGolden.hs`

```
Golden tests compare output:
- Input: test/.can file
- Expected: expected/ParseModule/*.hs files
- Test: Parse input, compare to expected output
```

---

## 8. FFI Testing Infrastructure

### 8.1 Existing FFI Test Command

**Command**: `canopy test-ffi`

**Configuration** (from `Test/FFI.hs`):
```haskell
data FFITestConfig = FFITestConfig
  { ffiTestGenerate :: Bool
  , ffiTestOutput :: Maybe FilePath
  , ffiTestWatch :: Bool
  , ffiTestValidateOnly :: Bool
  , ffiTestVerbose :: Bool
  , ffiTestPropertyRuns :: Maybe Int
  , ffiTestBrowser :: Bool
  }
```

**Flags**:
```
--generate              Generate test files
--output DIR           Output directory
--watch PATH           Watch for changes
--validate-only        Only validate contracts
--verbose              Verbose output
--property-runs N      Property test runs
--browser              Run in browser
```

### 8.2 FFI Testing Components

**Parser Functions**:
- `outputParser` - Parse output directory
- `propertyRunsParser` - Parse property run count

**Key Functions**:
- `run :: FFITestConfig -> IO Exit.Code` - Main handler
- `generateTests :: FilePath -> IO ()` - Generate test files
- `validateContracts :: FilePath -> IO ()` - Validate FFI contracts
- `runWithWatch :: FilePath -> IO ()` - Watch mode

**Dependencies**:
- `Foreign.FFI` - FFI definitions
- `Foreign.TestGeneratorNew` - Code generation
- `Make` module - Compilation

---

## 9. Development Workflow and CI Integration

### 9.1 Development Testing Workflow

```bash
# Build project
make build

# Run tests during development
make test                   # Full unit test suite
make test-watch             # Continuous testing
make test-match PATTERN="Expression"  # Specific tests

# Pre-commit validation
make lint                   # HLint + Ormolu
make test                   # Run tests
make test-coverage          # Check coverage
```

### 9.2 Makefile Test Targets

Located in `/Makefile`:

```makefile
test:
	@echo "Running all tests..."
	@stack test --fast canopy:canopy-test

test-match:
	@echo "Running specific tests..."
	@stack test --fast canopy:canopy-test --test-arguments "--pattern \"${PATTERN}\""

test-unit:
	@echo "Running unit tests..."
	@stack test --fast canopy:canopy-test --test-arguments "--pattern=Unit"

test-property:
	@echo "Running property tests..."
	@stack test --fast canopy:canopy-test --test-arguments "--pattern=Property"

test-integration:
	@echo "Running integration tests..."
	@stack test --fast canopy:canopy-test --test-arguments "--pattern=Integration"

test-watch:
	@echo "Running tests in watch mode..."
	@stack test --fast canopy:canopy-test --file-watch

test-coverage:
	@echo "Running tests with coverage..."
	@stack test --coverage --fast canopy:canopy-test
```

### 9.3 CI/CD Considerations

**Current CI Constraints**:
- Property tests disabled (slow)
- Integration tests mostly disabled (I/O intensive)
- Golden tests disabled (brittle)
- Sequential execution (no parallelization)

**Performance Requirements**:
- Build should complete quickly
- Test suite should complete in <5 minutes
- Coverage should remain at 80%+

---

## 10. Comparison: Existing `test-ffi` vs General `test` Command

### Current State

**Existing FFI Testing Command**:
- **Command**: `canopy test-ffi`
- **Scope**: FFI functions only
- **Features**: Generation, validation, watching, browser testing
- **Target Files**: `src/Foreign/` FFI definitions

**Gap**: No general `canopy test` command for:
- Project Canopy code tests
- Integration tests
- Property-based validation
- Custom test suites

### Design Considerations for `canopy test`

The new `canopy test` command should:

1. **Discover and run tests** in Canopy projects
   - Check for `test/` directory
   - Look for `tests/` directory
   - Support standard test file patterns

2. **Support test organization**
   - Unit tests
   - Property tests
   - Integration tests
   - Custom test groups

3. **Provide test configuration**
   - Via `canopy.json` or `test.toml`
   - Command-line overrides
   - Environment variable support

4. **Integrate with existing CLI patterns**
   - Use existing Terminal.Command infrastructure
   - Follow CLI/Commands.hs pattern
   - Consistent flag/arg parsing

5. **Output and reporting**
   - Standard test output (like Tasty)
   - Coverage reports
   - CI-friendly formats

---

## Summary

The Canopy compiler has a sophisticated testing infrastructure with:

- **Multiple test levels**: Unit, Property, Integration, Golden, and Benchmark
- **Framework**: Tasty with HUnit, QuickCheck, and custom utilities
- **CLI commands**: 9 existing commands, FFI testing already integrated
- **Organization**: 100+ test modules, ~70+ active, 150+ disabled for performance
- **Current limitation**: No general `canopy test` command for user projects

The existing `test-ffi` command demonstrates the pattern for implementing a general test command, which would follow the same architectural approach:
1. Define command in CLI.Commands
2. Create handler module with configuration type
3. Integrate with Terminal framework
4. Support flags and arguments
5. Return Exit codes

**Next Steps for Implementation**:
1. Define `canopy test` command structure
2. Determine test discovery mechanism for user projects
3. Design test configuration format (canopy.json extension)
4. Implement test runner integration
5. Add reporting and CI support

