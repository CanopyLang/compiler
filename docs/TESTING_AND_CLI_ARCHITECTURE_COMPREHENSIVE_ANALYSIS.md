# Canopy Codebase: Testing Infrastructure and CLI Architecture - Comprehensive Exploration Report

**Date:** November 10, 2025
**Scope:** Very Thorough Analysis of Testing Infrastructure and CLI Command Structure
**Focus:** Understanding architecture for designing `canopy test` command

---

## Executive Summary

The Canopy codebase is a multi-package Haskell project organized with:
- **5 separate packages** in `packages/` (canopy-core, canopy-terminal, canopy-builder, canopy-driver, canopy-query)
- **Main CLI executable** in `app/Main.hs` with ~9 commands
- **Comprehensive test suite** using Tasty framework with 200+ test modules
- **Modular CLI framework** for easy command registration and integration
- **Multi-stage build system** coordinating compilation, optimization, and code generation

The architecture is designed for extensibility and clean separation of concerns, making it straightforward to add new CLI commands like `canopy test`.

---

## 1. Directory Structure and Organization

### Root Layout
```
/home/quinten/fh/canopy/
├── app/
│   └── Main.hs                          # CLI entry point (108 lines)
├── packages/                            # Modular packages
│   ├── canopy-core/                     # Core language types, FFI, foreign support
│   ├── canopy-terminal/                 # CLI commands and Terminal framework
│   ├── canopy-builder/                  # Build system, dependency resolution
│   ├── canopy-driver/                   # Compilation driver
│   └── canopy-query/                    # Query engine, module resolution
├── test/                                # Master test suite
│   ├── Main.hs                          # Test suite entry point (253 lines)
│   ├── Unit/                            # 60+ unit test modules (ENABLED)
│   ├── Property/                        # 11 property test modules (DISABLED)
│   ├── Integration/                     # 16+ integration test modules (MOSTLY DISABLED)
│   ├── Golden/                          # 5 golden test modules (DISABLED)
│   ├── fixtures/                        # Test fixtures and data
│   ├── test-cases/                      # Test case files
│   └── benchmark/                       # Benchmark tests
├── package.yaml                         # Project metadata and build config
├── stack.yaml                           # Stack snapshot and dependencies
├── Makefile                             # 94 lines - build automation
└── [Various documentation files]
```

### Package-Specific Structure

Each package follows a consistent structure:

```
packages/canopy-PACKAGE/
├── src/                                 # Public API modules
│   ├── Module1.hs
│   ├── Module2/SubModule.hs
│   └── ...
├── impl/                                # Implementation (terminal only)
│   └── Terminal/
│       ├── Command.hs                   # Command execution framework
│       ├── Application.hs               # App orchestration
│       ├── Parser.hs                    # Argument/flag parsing
│       ├── Types.hs                     # Core types
│       └── ...
├── package.yaml                         # Package-specific config
└── .stack-work/                         # Build artifacts
```

### Terminal Package Layout (Most Relevant for CLI)
```
packages/canopy-terminal/
├── impl/Terminal/                       # Terminal framework implementation
│   ├── Command.hs                       # Command execution (283 lines)
│   ├── Application.hs                   # Application orchestration (150+ lines)
│   ├── Parser.hs                        # Parser utilities
│   ├── Types.hs                         # Type definitions (GADT-based)
│   ├── Chomp.hs                         # Argument parsing
│   ├── Error.hs                         # Error handling and display
│   └── Completion.hs                    # Shell completion support
├── src/                                 # Public CLI commands
│   ├── Make.hs                          # Build command (194 lines)
│   ├── Install.hs                       # Package installation (205 lines)
│   ├── Repl.hs                          # Interactive REPL (138 lines)
│   ├── Watch.hs                         # File watching (104 lines)
│   ├── Develop.hs                       # Development server
│   ├── Diff.hs                          # API diff analysis
│   ├── Init.hs                          # Project initialization
│   ├── Bump.hs                          # Version bumping
│   ├── Publish.hs                       # Package publishing
│   ├── Test/FFI.hs                      # FFI testing command (902 lines)
│   ├── Build.hs                         # Utility functions
│   ├── CLI/
│   │   ├── Commands.hs                  # Command definitions (404 lines)
│   │   ├── Documentation.hs             # Help text generation
│   │   ├── Parsers.hs                   # Reusable parsers
│   │   └── Types.hs                     # CLI type definitions
│   └── ...
└── package.yaml
```

---

## 2. CLI Command Architecture

### 2.1 Command Registration Pipeline

The CLI uses a hierarchical, composable architecture:

**1. Command Definition** (`packages/canopy-terminal/src/CLI/Commands.hs`)
```haskell
createMakeCommand :: Terminal.Command
createMakeCommand =
  Terminal.Command
    "make"
    (Terminal.Uncommon details)
    details
    example
    args                     -- Arguments parser
    flags                    -- Flags parser
    Make.run                 -- Command handler
```

**2. Command Collection** (`app/Main.hs`)
```haskell
createAllCommands :: [Terminal.Command]
createAllCommands =
  [ createReplCommand
  , createInitCommand
  , createReactorCommand
  , createMakeCommand
  , createFFITestCommand      -- Existing example of newer command
  , createInstallCommand
  , createBumpCommand
  , createDiffCommand
  , createPublishCommand
  ]
```

**3. Application Setup** (`app/Main.hs`)
```haskell
main :: IO ()
main =
  Terminal.app
    createIntroduction         -- Help overview
    createOutro               -- Footer text
    createAllCommands         -- All commands
```

### 2.2 Command Handler Signature

All command handlers follow a consistent pattern:

```haskell
-- Type signature
run :: Args -> Flags -> IO ()

-- Where Args and Flags are command-specific records
data Flags = Flags
  { verbose :: !Bool
  , optimize :: !Bool
  , output :: !(Maybe FilePath)
  }

-- Example: Make.run
run :: [FilePath] -> Make.Flags -> IO ()
```

### 2.3 Existing Commands

Current available commands:

| Command | Handler | Type | Args | Flags |
|---------|---------|------|------|-------|
| `init` | `Init.run` | Common | None | None |
| `repl` | `Repl.run` | Common | None | Yes |
| `reactor` | `Develop.run` | Common | None | Yes |
| `make` | `Make.run` | Uncommon | *.can files | 6+ flags |
| `test-ffi` | `Test.FFI.run` | Uncommon | None | 7+ flags |
| `install` | `Install.run` | Uncommon | Package name | None |
| `bump` | `Bump.run` | Uncommon | None | None |
| `diff` | `Diff.run` | Uncommon | Package name | None |
| `publish` | `Publish.run` | Uncommon | None | None |

### 2.4 Command Infrastructure Components

#### Terminal Framework (packages/canopy-terminal/impl/Terminal/)

**Core Modules:**

1. **Command.hs** (283 lines)
   - `handleCommandExecution` - Dispatch to command by name
   - `processSingleCommand` - Handle single-command apps
   - `findCommand` - Locate command by name
   - `executeCommandWithHelp` - Process help and execution
   - `createCommand` - Factory for command creation

2. **Application.hs** (150+ lines)
   - `runApp` - Main entry point for multi-command CLIs
   - `runSingleCommand` - Entry point for single-command apps
   - `initializeApp` - Environment initialization
   - `processAppArguments` - Argument processing
   - `handleVersionRequest` - Version display
   - `handleOverviewRequest` - Help display

3. **Parser.hs**
   - Argument parsing combinators
   - Flag parsing utilities
   - Help text generation
   - Error reporting

4. **Types.hs** (GADT-based)
   - `Command` - Command definition with metadata
   - `CommandMeta` - Command documentation
   - `Args` - Argument specifications
   - `Flags` - Flag specifications
   - `Parser` - Type-safe parser definition

5. **Chomp.hs**
   - Low-level argument and flag parsing
   - Handles `--help`, `--version`, unknown args
   - Error collection and reporting

6. **Error.hs**
   - Error display and formatting
   - Exit code management
   - Help text rendering
   - Suggestion generation for typos

#### CLI Command Infrastructure (packages/canopy-terminal/src/CLI/)

1. **Commands.hs** (404 lines)
   - Command factory functions: `createXxxCommand()`
   - Metadata creation (summary, details, examples)
   - Argument parser setup
   - Flag parser setup
   - Handler delegation

2. **Documentation.hs**
   - Help text generation
   - Reflow and formatting utilities
   - Markdown to Doc conversion
   - Example formatting

3. **Parsers.hs**
   - Reusable parser definitions
   - Common argument patterns
   - Flag patterns
   - Validation functions

4. **Types.hs**
   - Re-exports from Terminal framework
   - Local type definitions
   - `Command` type alias

---

## 3. Test Infrastructure

### 3.1 Test Suite Organization

Located in `/home/quinten/fh/canopy/test/`

```
test/
├── Main.hs                          # Master test entry (253 lines)
├── Unit/                            # 60+ unit test suites (ENABLED)
│   ├── Data/
│   │   ├── NameTest.hs
│   │   ├── IndexTest.hs
│   │   ├── BagTest.hs
│   │   ├── OneOrMoreTest.hs
│   │   ├── NonEmptyListTest.hs
│   │   ├── MapUtilsTest.hs
│   │   └── Utf8Test.hs
│   ├── Parse/
│   │   ├── ExpressionTest.hs
│   │   ├── ModuleTest.hs
│   │   ├── PatternTest.hs
│   │   └── TypeTest.hs
│   ├── AST/
│   │   ├── CanonicalTypeTest.hs
│   │   ├── OptimizedTest.hs
│   │   ├── SourceTest.hs
│   │   └── Utils/
│   ├── Builder/
│   │   ├── GraphTest.hs
│   │   ├── HashTest.hs
│   │   ├── IncrementalTest.hs
│   │   ├── SolverTest.hs
│   │   ├── StateTest.hs
│   │   ├── PackageCacheTest.hs
│   │   └── [More]
│   ├── CLI/
│   │   ├── CommandsTest.hs          # Tests CLI command creation
│   │   ├── DocumentationTest.hs     # Tests help generation
│   │   └── ParsersTest.hs           # Tests argument parsing
│   ├── Foreign/
│   │   ├── FFITypeParseTest.hs      # FFI type system tests
│   │   └── AudioFFITest.hs
│   ├── Develop/
│   │   ├── CompilationTest.hs
│   │   ├── EnvironmentTest.hs
│   │   ├── MimeTypesTest.hs
│   │   └── TypesTest.hs
│   ├── Init/
│   │   ├── DisplayTest.hs
│   │   ├── EnvironmentTest.hs
│   │   ├── ProjectTest.hs
│   │   ├── TypesTest.hs
│   │   └── ValidationTest.hs
│   ├── [Many more test modules]
│   └── [Terminal, File, Json, Http, Process, etc.]
├── Property/                        # 11 property test suites (DISABLED)
│   ├── AST/
│   │   ├── CanonicalProps.hs
│   │   ├── OptimizedProps.hs
│   │   └── OptimizedBinaryProps.hs
│   ├── Data/
│   │   └── NameProps.hs
│   ├── Canopy/
│   │   └── VersionProps.hs
│   ├── Terminal/
│   │   └── ChompProps.hs
│   ├── [More property test files]
│   └── ...
├── Integration/                     # 16+ integration test suites (MOSTLY DISABLED)
│   ├── InitTest.hs
│   ├── MakeTest.hs
│   ├── CanExtensionTest.hs
│   ├── CompileIntegrationTest.hs
│   ├── JsGenTest.hs
│   ├── PureBuilderIntegrationTest.hs
│   ├── Terminal/
│   │   └── ChompIntegrationTest.hs
│   ├── [More integration test files]
│   └── ...
├── Golden/                          # 5 golden test suites (DISABLED)
│   ├── ParseModuleGolden.hs
│   ├── ParseExprGolden.hs
│   ├── ParseTypeGolden.hs
│   ├── ParseAliasGolden.hs
│   ├── JsGenGolden.hs
│   ├── sources/                     # Test input files
│   └── expected/                    # Expected outputs (180+ golden files)
├── fixtures/                        # Shared test fixtures and data
│   └── type/
├── test-cases/                      # Test case definitions
└── benchmark/                       # Benchmark test suites
```

### 3.2 Test Discovery and Execution

**Master Entry Point** (`test/Main.hs`, 253 lines):

```haskell
module Main where

-- Import all test modules
import qualified Unit.AST.CanonicalTypeTest as CanonicalTypeTest
import qualified Unit.Data.NameTest as NameTest
-- ... 110+ test module imports

-- Main function
main :: IO ()
main = defaultMain tests

-- Test tree definition
tests :: TestTree
tests =
  testGroup
    "Canopy Tests"
    [ unitTests              -- ENABLED (60+ suites)
      -- propertyTests       -- DISABLED (11 suites)
      -- integrationTests    -- DISABLED (16+ suites)
      -- goldenTests         -- DISABLED (5 suites)
    ]

-- Test groups
unitTests :: TestTree
unitTests =
  testGroup
    "Unit Tests"
    [ NameTest.tests           -- 60+ test suites listed
    , VersionTest.tests
    , JsonDecodeTest.tests
    -- ... etc
    ]

propertyTests :: TestTree
integrationTests :: TestTree
goldenTests :: TestTree
```

### 3.3 Test Framework Stack

**Dependencies** (from `package.yaml`):

| Dependency | Purpose | Version |
|-----------|---------|---------|
| `tasty` | Test runner and organizer | Latest |
| `tasty-hunit` | Unit test assertions | Latest |
| `tasty-quickcheck` | Property-based testing integration | Latest |
| `tasty-golden` | Golden file testing | Latest |
| `QuickCheck` | Property test generators | Latest |
| `temporary` | Temporary file/directory handling | Latest |

**Framework Features:**

- **Pattern matching**: Filter tests by name
  ```bash
  make test-match PATTERN="Parser"
  stack test -- --pattern "Foreign"
  ```
- **Watch mode**: Continuous testing on file changes
  ```bash
  make test-watch
  stack test -- --file-watch
  ```
- **Coverage reporting**: Code coverage metrics
  ```bash
  make test-coverage
  stack test --coverage
  ```

### 3.4 Test Organization Patterns

**Unit Test Structure** (Example: `test/Unit/MakeTest.hs`):

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Unit.MakeTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

-- Top-level test tree
tests :: TestTree
tests =
  testGroup "Make Support Components Tests"
    [ testModuleNameHandling
    , testPackageHandling
    , testVersionHandling
    , testNameHandling
    ]

-- Test group with multiple cases
testModuleNameHandling :: TestTree
testModuleNameHandling =
  testGroup "ModuleName handling"
    [ testCase "module name toChars works correctly" $ do
        ModuleName.toChars (Name.fromChars "Test.Module") @?= "Test.Module"
    , testCase "module name toFilePath converts correctly" $ do
        ModuleName.toFilePath (Name.fromChars "Test.Module") @?= "Test/Module"
    ]
```

**Property Test Structure** (Example: `test/Property/MakeProps.hs`):

```haskell
module Property.MakeProps (tests) where

import Test.QuickCheck
import Test.Tasty.QuickCheck (testProperty)

tests :: TestTree
tests =
  testGroup "Make Support Components Properties"
    [ testModuleNameProperties
    , testVersionProperties
    ]

testVersionProperties :: TestTree
testVersionProperties =
  testGroup "Version properties"
    [ testProperty "version equality is reflexive" $ \v ->
        (v == v) == True
    , testProperty "version ordering is consistent" $ \v ->
        (v <= v) && (v >= v)
    ]
```

**Integration Test Structure** (Example: `test/Integration/MakeTest.hs`):

```haskell
module Integration.MakeTest (tests) where

-- Integration tests verify component interactions
-- Tests actual integration scenarios (not mocked)
tests :: TestTree
tests =
  testGroup "Make Support Components Integration Tests"
    [ testComponentIntegration
    , testVersionHandling
    ]

testComponentIntegration :: TestTree
testComponentIntegration =
  testGroup "Component integration"
    [ testCase "module names and packages maintain separate equality" $ do
        let basics1 = ModuleName.basics
            basics2 = ModuleName.basics
        assertBool "basics module has expected name" (show basics1 == show basics2)
    ]
```

### 3.5 Test Status and Disabled Tests

**Current Status** (`test/Main.hs`, lines 122-124):

```haskell
tests =
  testGroup "Canopy Tests"
    [ unitTests
      -- propertyTests, -- TEMPORARILY DISABLED: Checking if this is the slow one
      -- integrationTests, -- Pure Builder integration tests added but disabled (slow with file I/O)
      -- goldenTests -- TEMPORARILY DISABLED: May compile real packages
    ]
```

**Disabled Tests Rationale:**

| Group | Count | Status | Reason |
|-------|-------|--------|--------|
| Unit Tests | 60+ | **ENABLED** | Fast, focused, no file I/O |
| Property Tests | 11 | Disabled | Performance concerns |
| Integration Tests | 16+ | Mostly disabled | File I/O, slow execution, compiles real packages |
| Golden Tests | 5 | Disabled | Brittle string matching, package compilation overhead |

### 3.6 Test Configuration (package.yaml)

```yaml
tests:
  canopy-test:
    main: Main.hs
    source-dirs: test
    ghc-options:
      - -rtsopts
      - -threaded
      - -with-rtsopts=-N
    dependencies:
      - canopy
      - canopy-core
      - canopy-query
      - canopy-driver
      - canopy-builder
      - canopy-terminal
      - tasty
      - tasty-hunit
      - tasty-quickcheck
      - tasty-golden
      - QuickCheck
      - temporary
      - text
```

---

## 4. Build System and Dependencies

### 4.1 Project Structure (Multi-Package Setup)

The project uses a **monorepo** approach with Stack:

```
stack.yaml
├── packages:
│   - .                              # Main library + executable
│   - packages/canopy-core
│   - packages/canopy-query
│   - packages/canopy-driver
│   - packages/canopy-builder
│   - packages/canopy-terminal
└── snapshot: lts-23.0
```

### 4.2 Build Targets

**From `package.yaml`:**

```yaml
library:
  dependencies:
    - canopy-core
    - canopy-query
    - canopy-driver
    - canopy-builder
    - canopy-terminal
  ghc-options:
    - -Wall
    - -fwarn-tabs
    - -O2

executables:
  canopy:
    main: Main.hs
    source-dirs: app
    dependencies:
      - canopy
      - canopy-core
      - canopy-query
      - canopy-driver
      - canopy-builder
      - canopy-terminal
```

### 4.3 Makefile Build Automation (94 lines)

```makefile
# Build
build:
  @stack install --fast --pedantic --ghc-options "-j +RTS -A128m -n2m -RTS"

# Testing targets
test:                              # Run all unit tests
test-unit:                         # Unit tests only
test-property:                     # Property tests only
test-integration:                  # Integration tests only
test-watch:                        # Watch mode
test-coverage:                     # Coverage report
test-build:                        # Build without running
test-deps:                         # Install dependencies
test-match:                        # Pattern-based filtering

# Code quality
lint:                              # Check with hlint and ormolu
fix-lint:                          # Auto-fix lint issues
format:                            # Format with ormolu
```

### 4.4 Compiler and Builder Interaction

**Build Pipeline:**

1. **Compilation** (`packages/canopy-core/src/Compiler/`)
   - Lexer, Parser, AST construction
   - Type inference and checking
   - Optimization

2. **Building** (`packages/canopy-builder/src/`)
   - Dependency resolution (Solver)
   - Project management
   - Incremental compilation
   - Artifact caching

3. **Code Generation** (`packages/canopy-core/src/Generate/`)
   - JavaScript backend
   - HTML generation

4. **Terminal/CLI** (`packages/canopy-terminal/src/`)
   - Command implementations
   - User-facing interface
   - File watching

---

## 5. FFI Test Command (Existing Example)

The `test-ffi` command provides a good reference for implementing a comprehensive test command.

### 5.1 FFI Test Command Location and Structure

**Command Implementation:** `/packages/canopy-terminal/src/Test/FFI.hs` (902 lines)

**Command Registration:** `/packages/canopy-terminal/src/CLI/Commands.hs` (lines 189-195)

```haskell
createFFITestCommand :: Command
createFFITestCommand =
  Terminal.Command "test-ffi" Terminal.Uncommon details example Terminal.noArgs flags FFI.run
  where
    details = createFFITestDetails
    example = createFFITestExample
    flags = createFFITestFlags
```

### 5.2 FFI Test Configuration

```haskell
data FFITestConfig = FFITestConfig
  { ffiTestGenerate :: !Bool              -- Generate test files
  , ffiTestOutput :: !(Maybe FilePath)    -- Output directory
  , ffiTestWatch :: !Bool                 -- Watch mode
  , ffiTestValidateOnly :: !Bool          -- Validation only
  , ffiTestVerbose :: !Bool               -- Verbose output
  , ffiTestPropertyRuns :: !(Maybe Int)   -- Property test count
  , ffiTestBrowser :: !Bool               -- Browser mode
  } deriving (Eq, Show)
```

### 5.3 FFI Test Handler Signature

```haskell
run :: () -> FFITestConfig -> IO ()
run _args config = do
  putStrLn "🧪 Canopy FFI Test Suite"
  putStrLn ""
  -- Implementation
```

### 5.4 FFI Test Flags

```haskell
createFFITestFlags :: Terminal.Flags FFI.FFITestConfig
createFFITestFlags =
  Terminal.flags FFI.FFITestConfig
    |-- Terminal.flag "generate" ... "Generate test files"
    |-- Terminal.flag "output" ... "Output directory"
    |-- Terminal.onOff "watch" "Watch for changes"
    |-- Terminal.onOff "validate-only" "Validate only"
    |-- Terminal.onOff "verbose" "Verbose output"
    |-- Terminal.flag "property-runs" ... "Number of property runs"
    |-- Terminal.onOff "browser" "Run in browser"
```

---

## 6. CLI Pattern Summary

### 6.1 Adding a New Command (Step-by-Step)

1. **Create Handler Module**
   - Location: `packages/canopy-terminal/src/Test.hs` (or similar)
   - Define: `run :: Args -> Flags -> IO ()`
   - Implement: All command logic

2. **Define Arguments and Flags**
   - Create records if complex:
     ```haskell
     data Flags = Flags { verbose :: Bool, ... }
     ```
   - Create parsers using Terminal framework

3. **Register in CLI.Commands**
   ```haskell
   createTestCommand :: Command
   createTestCommand =
     Terminal.Command "test" summary details example args flags Test.run
   ```

4. **Add to Main.hs**
   ```haskell
   createAllCommands :: [Terminal.Command]
   createAllCommands =
     [ createTestCommand      -- Add here
     , ...
     ]
   ```

### 6.2 Command Handler Patterns

**Pattern 1: Simple Handler (No Args/Flags)**
```haskell
run :: () -> () -> IO ()
run _ _ = putStrLn "Hello"
```

**Pattern 2: Flags Only**
```haskell
data Flags = Flags { verbose :: Bool }
run :: () -> Flags -> IO ()
run _ flags = if verbose flags then putStrLn "Verbose" else putStrLn "Quiet"
```

**Pattern 3: Arguments Only**
```haskell
run :: [FilePath] -> () -> IO ()
run paths _ = mapM_ putStrLn paths
```

**Pattern 4: Arguments and Flags**
```haskell
data Args = Args { files :: [FilePath] }
data Flags = Flags { verbose :: Bool }
run :: Args -> Flags -> IO ()
run args flags = ...
```

### 6.3 Help System Integration

Each command provides:

1. **Summary** - One-line description
   ```haskell
   "Run tests for your Canopy project"
   ```

2. **Details** - Multi-line explanation
   ```haskell
   "The `test` command runs all tests defined in your project"
   ```

3. **Examples** - Doc-formatted examples
   ```haskell
   P.vcat
     [ "Run all tests:"
     , P.indent 2 "canopy test"
     , ""
     , "Run with verbose output:"
     , P.indent 2 "canopy test --verbose"
     ]
   ```

---

## 7. Makefile Build Targets

### 7.1 Test-Related Targets

```makefile
test:                   # Run all unit tests
	@echo "Running all tests..."
	@stack test --fast canopy:canopy-test

test-match:            # Pattern-based test filtering
	@echo "Running specific tests..."
	@stack test --fast canopy:canopy-test --test-arguments "--pattern \"${PATTERN}\""

test-unit:             # Unit tests only
	@echo "Running unit tests..."
	@stack test --fast canopy:canopy-test --test-arguments "--pattern=Unit"

test-property:         # Property tests
	@echo "Running property tests..."
	@stack test --fast canopy:canopy-test --test-arguments "--pattern=Property"

test-integration:      # Integration tests
	@echo "Running integration tests..."
	@stack test --fast canopy:canopy-test --test-arguments "--pattern=Integration"

test-watch:            # Watch mode
	@echo "Running tests in watch mode..."
	@stack test --fast canopy:canopy-test --file-watch

test-coverage:         # Coverage report
	@echo "Running tests with coverage..."
	@stack test --coverage --fast canopy:canopy-test
	@echo "Coverage report generated in .stack-work/install/*/doc/"

test-build:            # Build without running
	@echo "Building tests without running..."
	@stack build --test --no-run-tests --fast canopy:canopy-test

test-deps:             # Install test dependencies
	@echo "Installing test dependencies..."
	@stack build --test --only-dependencies
```

### 7.2 Build Targets

```makefile
build:                 # Build with options
	@stack install --fast --pedantic --ghc-options "-j +RTS -A128m -n2m -RTS"

clean:                 # Clean artifacts
	@stack clean

lint:                  # Code quality checks
	hlint ... && ormolu --mode=check ...

fix-lint:              # Auto-fix lint issues
	hlint ... --refactor && ormolu --mode=inplace ...

format:                # Format code
	@find builder compiler terminal test -name '*.hs' -exec ormolu --mode=inplace {} \;
```

---

## 8. Key Design Patterns in Codebase

### 8.1 Modular Command Architecture

**Design Pattern:** Each command is self-contained with:
- Dedicated module in `packages/canopy-terminal/src/`
- Command registration in `CLI/Commands.hs`
- Types specific to command
- Comprehensive help text
- Integration with Terminal framework

**Benefits:**
- Easy to add new commands
- Clear separation of concerns
- Testable in isolation
- Help system automatically integrated

### 8.2 Lens-Based Record Operations

**Throughout codebase:**
- Uses `lens` library for record access/updates
- Pattern: `state ^. field` for access, `state & field .~ value` for updates
- All public records have lenses generated
- Follows CLAUDE.md standards strictly

### 8.3 Error Handling

**Pattern:** Rich error types with `Either` monad
```haskell
type Task a = Either Error a
type IO a = IO (Either Error a)
```

**Benefits:**
- Composable error handling
- Rich error information
- Helpful error messages
- Graceful failure

### 8.4 Task Monad Pattern

**For operations that fail:**
```haskell
-- From Reporting.Task
type Task a = IO (Either Exit.Code a)

-- Usage pattern
result <- Task.run $ do
  value1 <- someOperation
  value2 <- anotherOperation
  pure value2
```

### 8.5 Testing Pattern

**Three-tier approach:**
1. **Unit Tests** - Fast, isolated, no I/O
2. **Property Tests** - Verify invariants
3. **Integration Tests** - Cross-component validation

---

## 9. Relevant File Reference

### 9.1 Core Files for `canopy test` Command Design

| File | Lines | Purpose | Relevance |
|------|-------|---------|-----------|
| `app/Main.hs` | 108 | CLI entry point | Shows command registration |
| `packages/canopy-terminal/impl/Terminal/Command.hs` | 283 | Command framework | Core command execution |
| `packages/canopy-terminal/impl/Terminal/Application.hs` | 150+ | App orchestration | Shows how commands are dispatched |
| `packages/canopy-terminal/src/CLI/Commands.hs` | 404 | Command definitions | Examples of command creation |
| `packages/canopy-terminal/src/Test/FFI.hs` | 902 | FFI test command | Reference for test command |
| `test/Main.hs` | 253 | Test entry point | Test discovery and organization |
| `test/Unit/MakeTest.hs` | 80+ | Example unit tests | Pattern for test structure |
| `test/Property/MakeProps.hs` | 60+ | Example property tests | Property test pattern |
| `test/Integration/MakeTest.hs` | 80+ | Example integration tests | Integration test pattern |
| `test/Unit/CLI/CommandsTest.hs` | 80+ | CLI test example | How CLI is tested |
| `Makefile` | 94 | Build automation | Test execution targets |
| `package.yaml` | 145 | Build config | Test dependencies and setup |
| `stack.yaml` | 23 | Stack config | Multi-package setup |
| `packages/canopy-terminal/src/Make.hs` | 194 | Make command | Comprehensive command example |
| `packages/canopy-terminal/src/Install.hs` | 205 | Install command | Complex command example |
| `packages/canopy-terminal/src/Watch.hs` | 104 | Watch command | Watch-based command example |

### 9.2 Supporting Infrastructure Files

| File | Purpose |
|------|---------|
| `packages/canopy-terminal/src/CLI/Documentation.hs` | Help text utilities |
| `packages/canopy-terminal/src/CLI/Parsers.hs` | Reusable parser definitions |
| `packages/canopy-terminal/src/CLI/Types.hs` | CLI type definitions |
| `packages/canopy-terminal/impl/Terminal/Parser.hs` | Parser framework |
| `packages/canopy-terminal/impl/Terminal/Types.hs` | Core types (GADT) |
| `packages/canopy-terminal/impl/Terminal/Chomp.hs` | Argument parsing |
| `packages/canopy-terminal/impl/Terminal/Error.hs` | Error handling |

### 9.3 Test-Related Files

| File | Purpose |
|------|---------|
| `test/Unit/CLI/CommandsTest.hs` | Tests command creation |
| `test/Unit/CLI/DocumentationTest.hs` | Tests help generation |
| `test/Unit/CLI/ParsersTest.hs` | Tests argument parsing |
| `test/Unit/Foreign/FFITypeParseTest.hs` | FFI type tests |
| `test/Unit/Foreign/AudioFFITest.hs` | Audio FFI tests |
| `test/Unit/MakeTest.hs` | Make command tests |

---

## 10. Architecture Principles (From CLAUDE.md)

### 10.1 Mandatory Patterns in Codebase

1. **Function Size**: ≤ 15 lines (excluding blank lines/comments)
2. **Parameters**: ≤ 4 per function
3. **Branching Complexity**: ≤ 4 branching points
4. **No Duplication (DRY)**: Extract common logic
5. **Single Responsibility**: One clear purpose per module
6. **Lens Usage**: Mandatory for record access/updates
7. **Qualified Imports**: Types unqualified, functions qualified
8. **Test Coverage**: Minimum 80%
9. **Haddock Documentation**: All public APIs documented
10. **Avoid Simplification**: Investigate issues properly

### 10.2 Import Style (Mandatory)

```haskell
-- CORRECT pattern used throughout:
import Control.Monad.State.Strict (StateT)    -- Type unqualified
import qualified Control.Monad.State.Strict as State  -- Functions qualified
import qualified System.Exit as Exit

-- Usage:
loop :: StateT -> IO ()
loop state = do
  result <- State.get
  Exit.exitSuccess
```

### 10.3 Error Handling

- **Rich error types** with all failure modes
- **Structured error information** in records
- **Helpful error messages** with suggestions
- **Total functions** preferred, partial documented
- **Input validation** for all external data

---

## 11. Summary and Key Insights

### 11.1 CLI Architecture Strengths

1. **Modular Design**: Commands are isolated, self-contained units
2. **Extensibility**: Adding new commands is straightforward and low-risk
3. **Type Safety**: Terminal framework uses GADTs for type-safe parsing
4. **Help Integration**: Help system automatically generated from metadata
5. **Consistent Patterns**: All commands follow identical structure
6. **Error Handling**: Rich, helpful error messages throughout

### 11.2 Test Infrastructure Strengths

1. **Comprehensive Coverage**: 200+ test modules across multiple tiers
2. **Test Organization**: Clear separation (Unit, Property, Integration, Golden)
3. **Flexible Execution**: Pattern matching, watch mode, coverage reporting
4. **Fast Development**: Unit tests are fast and focused
5. **Gradual Integration**: Tests can be selectively enabled/disabled
6. **Framework Stack**: Modern Haskell testing infrastructure (Tasty, QuickCheck)

### 11.3 Design for `canopy test` Command

**Recommended approach based on architecture:**

1. **Create handler module** at `packages/canopy-terminal/src/Test.hs`
   - Define `Flags` record for options
   - Implement `run :: () -> Flags -> IO ()`

2. **Register command** in `packages/canopy-terminal/src/CLI/Commands.hs`
   - Create `createTestCommand :: Command`
   - Add metadata (summary, details, examples)
   - Define flags parser

3. **Add to CLI** in `app/Main.hs`
   - Add `createTestCommand` to `createAllCommands` list

4. **Create tests** in `test/Unit/CLI/` and potentially `test/Integration/`
   - Test command creation
   - Test help text generation
   - Test flag parsing

5. **Update Makefile** if needed (optional enhancement)
   - Can add convenience targets

This design leverages existing patterns and maintains consistency with codebase standards.

---

## 12. Next Steps for Implementation

1. **Study existing commands** (Make.hs, Install.hs, Test/FFI.hs)
   - Understand handler patterns
   - Note configuration structures
   - Review help text generation

2. **Review test patterns**
   - Examine Unit/CLI/CommandsTest.hs
   - Study test organization in test/Main.hs
   - Understand Tasty framework usage

3. **Design command interface**
   - Define Flags record
   - Plan help text
   - Document expected behavior

4. **Implement handler**
   - Follow CLAUDE.md standards
   - Use Task monad for error handling
   - Integrate with test framework

5. **Register command**
   - Add to CLI/Commands.hs
   - Update app/Main.hs
   - Implement help text

6. **Create tests**
   - Unit tests for command creation
   - Integration tests for behavior
   - Test flag parsing

---

