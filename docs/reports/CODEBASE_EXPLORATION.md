# Canopy Codebase Exploration Report

## Executive Summary

The Canopy project is a Haskell-based compiler project (Elm language fork) with a well-organized CLI command structure, comprehensive test suite, and modular architecture. The codebase demonstrates professional-grade software engineering practices with clear separation of concerns, proper layering, and extensive testing.

---

## 1. CLI Command Structure

### 1.1 Command Registration and Definition

**Location**: `/home/quinten/fh/canopy/packages/canopy-terminal/src/CLI/Commands.hs`

All CLI commands are centrally defined in `CLI.Commands` module with 8 major commands:

1. **createInitCommand** - Initialize new Canopy projects
   - Summary: "Start an Canopy project"
   - Handler: `Init.run`
   - Args: None
   - Flags: None

2. **createReplCommand** - Interactive REPL session
   - Summary: "Open up an interactive programming session"
   - Handler: `Repl.run`
   - Args: None
   - Flags: `--interpreter` (path), `--no-colors` (boolean)

3. **createReactorCommand** - Development server with hot reload
   - Summary: "Compile code with a click"
   - Handler: `Develop.run`
   - Args: None
   - Flags: `--port` (integer)

4. **createMakeCommand** - Compile Canopy code
   - Summary: "Compile Canopy code into JS or HTML"
   - Handler: `Make.run`
   - Args: Zero or more Canopy files (*.can, *.canopy, *.elm)
   - Flags:
     - `--debug` (boolean) - Time-travelling debugger
     - `--optimize` (boolean) - Code optimization
     - `--watch` (boolean) - File watcher
     - `--output` (string) - Output file location
     - `--report` (enum: json) - Error reporting format
     - `--docs` (string) - Generate documentation JSON
     - `--verbose` (boolean) - Verbose logging

5. **createInstallCommand** - Package installation
   - Summary: "Fetch packages from package repository"
   - Handler: `Install.run`
   - Args: Optional package name (author/project)
   - Flags: None

6. **createPublishCommand** - Package publishing
   - Summary: "Publish package to custom repository"
   - Handler: `Publish.run`
   - Args: Optional repository URL
   - Flags: None

7. **createBumpCommand** - Version bumping
   - Summary: "Determine appropriate version number increment"
   - Handler: `Bump.run`
   - Args: None
   - Flags: None

8. **createDiffCommand** - API change detection
   - Summary: "Detect and display API changes"
   - Handler: `Diff.run`
   - Args: Variable (version, package, versions)
   - Flags: None

9. **createFFITestCommand** - FFI testing and validation
   - Summary: "Test FFI functions including property-based testing"
   - Handler: `Test.FFI.run`
   - Args: None
   - Flags:
     - `--generate` (boolean) - Generate test files
     - `--output` (string) - Output directory
     - `--watch` (boolean) - Watch mode
     - `--validate-only` (boolean) - Validate contracts only
     - `--verbose` (boolean) - Verbose output
     - `--property-runs` (integer) - Number of property runs
     - `--browser` (boolean) - Browser testing

### 1.2 Command Implementation Pattern

Each command follows a consistent structure:

```haskell
createXxxCommand :: Command
createXxxCommand =
  Terminal.Command 
    name 
    (Terminal.Common summary)  -- or Terminal.Uncommon
    details 
    example 
    args 
    flags 
    handler
```

### 1.3 Command Type Definition

**Location**: `/home/quinten/fh/canopy/packages/canopy-terminal/impl/Terminal/Types.hs`

```haskell
data Command = Command
  { _cmdName :: String
  , _cmdMeta :: CommandMeta
  , _cmdHandler :: CommandHandler
  }

data CommandMeta = CommandMeta
  { _cmSummary :: Summary
  , _cmDetails :: String
  , _cmExample :: Doc
  , _cmArgs :: Args
  , _cmFlags :: Flags
  }

data Summary = Common String | Uncommon
```

### 1.4 Argument and Flag Parsing

**Location**: `/home/quinten/fh/canopy/packages/canopy-terminal/src/CLI/Parsers.hs`

Parsers are defined as `Parser` records with four fields:
- `_singular` - Singular form for help text
- `_plural` - Plural form for help text
- `_parser` - Function to parse string to type
- `_suggest` - IO function for suggestions
- `_examples` - Function to generate examples

Standard parsers available:
- `version` - Semantic version parser
- `canopyFile` - Canopy source file parser (*.can, *.canopy, *.elm)
- `package` - Package name parser (author/project format)
- `repositoryLocalName` - Repository name parser

---

## 2. Existing Command Implementations

### 2.1 Make Command

**Location**: `/home/quinten/fh/canopy/packages/canopy-terminal/src/Make.hs`

Structure:
- `Make.hs` - Main entry point (defines `run` function)
- `Make/Types.hs` - Data structures
- `Make/Environment.hs` - Environment setup
- `Make/Parser.hs` - Argument parsers
- `Make/Builder.hs` - Code generation
- `Make/Output.hs` - Output handling
- `Make/Generation.hs` - File generation utilities

Key functions:
- `run :: () -> Flags -> IO ()` - Main entry point
- `buildFromPaths` - Build from file paths
- `buildFromExposed` - Build from exposed modules
- `generateOutput` - Generate output files

### 2.2 Install Command

**Location**: `/home/quinten/fh/canopy/packages/canopy-terminal/src/Install.hs`

Structure:
- `Install.hs` - Main entry point
- `Install/Types.hs` - Data structures
- `Install/Arguments.hs` - Argument parsing
- `Install/AppPlan.hs` - Application installation plan
- `Install/PkgPlan.hs` - Package installation plan
- `Install/Changes.hs` - Change tracking
- `Install/Display.hs` - Display output
- `Install/Execution.hs` - Execution logic

### 2.3 Init Command

**Location**: `/home/quinten/fh/canopy/packages/canopy-terminal/src/Init.hs`

Structure:
- `Init.hs` - Main entry point
- `Init/Types.hs` - Data structures
- `Init/Validation.hs` - Input validation
- `Init/Project.hs` - Project creation
- `Init/Environment.hs` - Environment handling
- `Init/Display.hs` - Display output

### 2.4 REPL Command

**Location**: `/home/quinten/fh/canopy/packages/canopy-terminal/src/Repl.hs`

Structure:
- `Repl.hs` - Main entry point
- `Repl/Types.hs` - Data structures
- `Repl/Commands.hs` - REPL-specific commands
- `Repl/Eval.hs` - Expression evaluation
- `Repl/State.hs` - REPL state management

### 2.5 FFI Test Command

**Location**: `/home/quinten/fh/canopy/packages/canopy-terminal/src/Test/FFI.hs` (902 lines)

Features:
- FFI contract validation
- Property-based testing with configurable runs
- Browser and Node.js testing
- Test file generation
- Watch mode support

Data structure:
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
```

---

## 3. Test Infrastructure

### 3.1 Test Organization

**Root Test Directory**: `/home/quinten/fh/canopy/test/`

Test structure:
```
test/
├── Main.hs                    -- Central test runner
├── Unit/                      -- Unit tests (>80 test files)
├── Integration/               -- Integration tests (18+ test files)
├── Property/                  -- Property-based tests (11+ test files)
├── Golden/                    -- Golden file tests (5 test files)
├── fixtures/                  -- Test fixtures and data
└── test-cases/               -- Test case data
```

### 3.2 Unit Tests

**Location**: `/home/quinten/fh/canopy/test/Unit/`

Sample test files:
- `CLI/CommandsTest.hs` - CLI command creation tests
- `CLI/DocumentationTest.hs` - Documentation tests
- `CLI/ParsersTest.hs` - Parser tests
- `MakeTest.hs` - Make system tests
- `InstallTest.hs` - Install command tests
- `InitTest.hs` - Init command tests
- `DevelopTest.hs` - Development server tests
- `DiffTest.hs` - Diff command tests
- AST tests, Parser tests, Builder tests, etc.

**Test Entry Point**: `/home/quinten/fh/canopy/test/Unit/CLI/CommandsTest.hs`

Example test structure:
```haskell
module Unit.CLI.CommandsTest (tests) where

import CLI.Commands
import qualified Terminal
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup "CLI Commands Tests"
    [ testInitCommand,
      testReplCommand,
      testMakeCommand
    ]

testInitCommand :: TestTree
testInitCommand =
  testGroup "createInitCommand function"
    [ testCase "command has correct name" $ do
        let cmd = createInitCommand
        toName cmd @?= "init"
    ]
```

### 3.3 Property Tests

**Location**: `/home/quinten/fh/canopy/test/Property/`

Sample property test files:
- `MakeProps.hs` - Make system properties
- `TerminalProps.hs` - Terminal properties
- `DevelopProps.hs` - Development server properties
- `InitProps.hs` - Init command properties
- `InstallProps.hs` - Install command properties
- AST property tests

**Test Pattern**:
```haskell
module Property.MakeProps (tests) where

import Test.QuickCheck (Arbitrary(..), elements)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.QuickCheck (testProperty, (==>))

tests :: TestTree
tests =
  testGroup "Make Properties"
    [ testProperty "version equality is reflexive" $ \v ->
        v == (v :: Version.Version)
    ]
```

### 3.4 Integration Tests

**Location**: `/home/quinten/fh/canopy/test/Integration/`

Sample integration test files:
- `MakeTest.hs` - Make system integration
- `InitTest.hs` - Init command integration
- `InstallTest.hs` - Install command integration
- `DevelopTest.hs` - Development server integration
- `WatchIntegrationTest.hs` - Watch mode integration
- `TerminalIntegrationTest.hs` - Terminal integration
- `CompileIntegrationTest.hs` - Compilation integration
- Golden tests for Elm/Canopy compatibility

### 3.5 Golden Tests

**Location**: `/home/quinten/fh/canopy/test/Golden/`

Golden tests for parser output and code generation:
- `ParseExprGolden.hs` - Expression parser golden tests
- `ParseModuleGolden.hs` - Module parser golden tests
- `ParseTypeGolden.hs` - Type parser golden tests
- `ParseAliasGolden.hs` - Alias parser golden tests
- `JsGenGolden.hs` - JavaScript generation golden tests

### 3.6 Test Framework

**Framework**: Tasty with HUnit and QuickCheck backends

- `Test.Tasty` - Main test framework
- `Test.Tasty.HUnit` - Unit testing assertions
- `Test.Tasty.QuickCheck` - Property-based testing

### 3.7 Central Test Runner

**Location**: `/home/quinten/fh/canopy/test/Main.hs`

Structure:
```haskell
main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup "Canopy Tests"
    [ unitTests
    -- propertyTests (TEMPORARILY DISABLED)
    -- integrationTests (TEMPORARILY DISABLED)
    -- goldenTests (TEMPORARILY DISABLED)
    ]

unitTests :: TestTree
unitTests =
  testGroup "Unit Tests"
    [ NameTest.tests
    , IndexTest.tests
    , VersionTest.tests
    , VersionTest.tests
    , MakeTest.tests
    , InstallTest.tests
    , CLICommandsTest.tests
    -- ... 100+ unit tests
    ]
```

### 3.8 Test Cabal Configuration

**Location**: `/home/quinten/fh/canopy/canopy.cabal`

```
test-suite canopy-test
  type: exitcode-stdio-1.0
  main-is: Main.hs
  hs-source-dirs: test
  build-depends:
    canopy
    , canopy-core
    , canopy-builder
    , canopy-driver
    , canopy-query
    , tasty
    , tasty-hunit
    , tasty-quickcheck
    , quickcheck
    , text
    , bytestring
    , containers
    -- ... many more
```

---

## 4. Package Structure

### 4.1 Package Organization

The project is organized into 5 main packages:

1. **canopy-core** (core compiler logic)
   - Located: `/home/quinten/fh/canopy/packages/canopy-core/`
   - Purpose: Core data structures, types, and basic functionality

2. **canopy-builder** (build system)
   - Located: `/home/quinten/fh/canopy/packages/canopy-builder/`
   - Purpose: Dependency resolution and build orchestration

3. **canopy-driver** (compiler driver)
   - Located: `/home/quinten/fh/canopy/packages/canopy-driver/`
   - Purpose: Main compilation pipeline
   - Modules:
     - `Driver.hs` - Main driver
     - `Queries/` - Query system for incremental compilation
     - `Worker/Pool.hs` - Worker pool management

4. **canopy-query** (query system)
   - Located: `/home/quinten/fh/canopy/packages/canopy-query/`
   - Purpose: Query engine for incremental compilation

5. **canopy-terminal** (CLI and tools)
   - Located: `/home/quinten/fh/canopy/packages/canopy-terminal/`
   - Purpose: CLI commands, REPL, development tools
   - Source: `/src/` directory
   - Implementation: `/impl/` directory (Terminal infrastructure)

### 4.2 Terminal Package Structure

Source modules (`src/`):
```
src/
├── CLI/
│   ├── Commands.hs      -- Command definitions
│   ├── Parsers.hs       -- Argument/flag parsers
│   ├── Documentation.hs -- Help text
│   └── Types.hs         -- CLI types
├── Make.hs              -- Build command
├── Install.hs           -- Package installation
├── Init.hs              -- Project initialization
├── Repl.hs              -- Interactive REPL
├── Develop.hs           -- Development server
├── Diff.hs              -- API diff tool
├── Bump.hs              -- Version bumping
├── Publish.hs           -- Package publishing
├── Test/
│   └── FFI.hs          -- FFI testing
├── Watch.hs             -- File watching
└── [subdirectories for each command's implementation]
```

Implementation modules (`impl/`):
```
impl/
└── Terminal/
    ├── Helpers.hs       -- Terminal helpers
    ├── Types.hs         -- Terminal types and lenses
    ├── Parser.hs        -- Terminal parser
    ├── Application.hs   -- CLI application
    ├── Internal.hs      -- Internal utilities
    ├── Chomp/           -- Argument chomping/parsing
    ├── Command.hs       -- Command handling
    ├── Error/           -- Error handling
    └── [other utilities]
```

---

## 5. Command Handler Pattern

### 5.1 Handler Signature

All command handlers follow this pattern:

```haskell
run :: args -> flags -> IO ()
```

Examples:
- `Init.run :: () -> () -> IO ()`
- `Make.run :: () -> Make.Flags -> IO ()`
- `Repl.run :: () -> Repl.Flags -> IO ()`
- `Install.run :: Install.Args -> () -> IO ()`
- `Diff.run :: Diff.Args -> () -> IO ()`
- `Test.FFI.run :: () -> FFI.FFITestConfig -> IO ()`

### 5.2 Flag Record Pattern

Each command with flags has a corresponding `Flags` record:

```haskell
data Flags = Flags
  { debug :: !Bool
  , optimize :: !Bool
  , watch :: !Bool
  , output :: !(Maybe FilePath)
  , report :: !ReportType
  , docs :: !(Maybe FilePath)
  , verbose :: !Bool
  } deriving (Eq, Show)
```

### 5.3 Argument Type Pattern

Commands with arguments have corresponding `Args` types:

```haskell
data Args
  = NoArgs
  | Install Package.Package
  deriving (Eq, Show)
```

---

## 6. Key Testing Insights

### 6.1 Test Organization Standards

Based on CLAUDE.md guidelines:
- Minimum 80% test coverage required
- NO mock functions (all tests use real implementations)
- Tests focus on actual behavior, not reflexive equality
- Unit tests for every public function
- Property tests for invariants and laws
- Golden tests for parser output and code generation

### 6.2 Test Examples

**Unit Test Example** (from `Unit/CLI/CommandsTest.hs`):
```haskell
testCase "command has correct name" $ do
  let cmd = createInitCommand
  toName cmd @?= "init"
```

**Property Test Example** (from `Property/MakeProps.hs`):
```haskell
testProperty "version equality is reflexive" $ \v ->
  v == (v :: Version.Version)
```

### 6.3 Make Command Testing

Since `Make` modules are in the terminal executable (not exposed), tests focus on:
- Library components that Make depends on
- Cross-component compatibility
- Type conversions and data flow
- Edge case handling

Test locations:
- Unit tests: `test/Unit/MakeTest.hs`
- Property tests: `test/Property/MakeProps.hs`
- Integration tests: `test/Integration/MakeTest.hs`

---

## 7. Build System Integration

### 7.1 Stack Build

Build file: `/home/quinten/fh/canopy/stack.yaml`

Run tests:
```bash
stack test --ta="--pattern Make"
```

### 7.2 Cabal Configuration

Main cabal files:
- `/home/quinten/fh/canopy/canopy.cabal` - Main executable and test suite
- `/home/quinten/fh/canopy/packages/canopy-terminal/canopy-terminal.cabal` - Terminal package

### 7.3 Test Execution

**Test Main Entry Point**: `/home/quinten/fh/canopy/test/Main.hs`

Currently enabled:
- ✓ Unit tests (enabled)

Temporarily disabled:
- Property tests
- Integration tests
- Golden tests

---

## 8. Existing Test-Related Functionality

### 8.1 FFI Testing Command

The project already includes a comprehensive `test-ffi` command:

**Location**: `/home/quinten/fh/canopy/packages/canopy-terminal/src/Test/FFI.hs` (902 lines)

**Features**:
- FFI contract validation
- Property-based testing
- Test file generation
- Watch mode for continuous testing
- Browser and Node.js runtime support
- Configurable property run counts

**Command Line Usage**:
```bash
canopy test-ffi                  -- Run all FFI tests
canopy test-ffi --generate       -- Generate test files
canopy test-ffi --watch         -- Watch and re-run
canopy test-ffi --validate-only  -- Validate contracts only
canopy test-ffi --browser       -- Use browser runtime
canopy test-ffi --property-runs 500  -- Custom property runs
```

### 8.2 Test Configuration

Flag-based configuration using `FFITestConfig` record with defaults:
- Output directory: `test-generation/`
- Property runs: 100
- All options optional

---

## 9. Directory Structure Summary

**Key absolute paths**:

CLI Commands:
- `/home/quinten/fh/canopy/packages/canopy-terminal/src/CLI/Commands.hs` - Command definitions
- `/home/quinten/fh/canopy/packages/canopy-terminal/src/CLI/Parsers.hs` - Argument parsers
- `/home/quinten/fh/canopy/packages/canopy-terminal/impl/Terminal/` - Terminal framework

Command Implementations:
- `/home/quinten/fh/canopy/packages/canopy-terminal/src/Make.hs` - Build command
- `/home/quinten/fh/canopy/packages/canopy-terminal/src/Install.hs` - Install command
- `/home/quinten/fh/canopy/packages/canopy-terminal/src/Init.hs` - Init command
- `/home/quinten/fh/canopy/packages/canopy-terminal/src/Repl.hs` - REPL command
- `/home/quinten/fh/canopy/packages/canopy-terminal/src/Test/FFI.hs` - FFI test command
- `/home/quinten/fh/canopy/packages/canopy-terminal/src/Watch.hs` - Watch mode

Tests:
- `/home/quinten/fh/canopy/test/Main.hs` - Test runner
- `/home/quinten/fh/canopy/test/Unit/` - Unit tests
- `/home/quinten/fh/canopy/test/Integration/` - Integration tests
- `/home/quinten/fh/canopy/test/Property/` - Property tests
- `/home/quinten/fh/canopy/test/Golden/` - Golden tests

Packages:
- `/home/quinten/fh/canopy/packages/canopy-core/` - Core library
- `/home/quinten/fh/canopy/packages/canopy-builder/` - Build system
- `/home/quinten/fh/canopy/packages/canopy-driver/` - Compiler driver
- `/home/quinten/fh/canopy/packages/canopy-query/` - Query system
- `/home/quinten/fh/canopy/packages/canopy-terminal/` - CLI and tools

---

## 10. Key Takeaways for Test Implementation

1. **Command Registration**: Commands are centrally defined in `CLI.Commands` and follow a consistent pattern
2. **Flag and Argument System**: Uses `Terminal` framework with parsers and validators
3. **Test Organization**: Three-tier testing (Unit, Property, Integration) with central runner
4. **Test Coverage**: Minimum 80% required, with focus on real behavior not mocks
5. **Existing Patterns**: Make, Install, Init, Repl commands provide implementation examples
6. **FFI Testing**: Already has comprehensive test framework that could serve as template
7. **Build Integration**: Stack-based with Tasty test framework
8. **CLAUDE.md Compliance**: All code must follow strict guidelines for size, complexity, and style

