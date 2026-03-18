# Canopy Testing Infrastructure - Code References

This document provides direct code references for understanding and implementing testing in Canopy.

## Core Test Files (Absolute Paths)

### Test Framework Entry Point
- **File**: `/home/quinten/fh/canopy/test/Main.hs`
- **Purpose**: Master test suite coordinator
- **Key exports**: `tests :: TestTree`, `unitTests`, `propertyTests`, `integrationTests`, `goldenTests`
- **Status**: Lines 114-253 - Unit tests enabled, others disabled

### CLI Command Registration
- **File**: `/home/quinten/fh/canopy/app/Main.hs`
- **Purpose**: Main application entry point
- **Key function**: `main :: IO ()` (line 77-82)
- **Key function**: `createAllCommands :: [Terminal.Command]` (line 97-108)
- **Pattern**: Shows how to register new commands

### CLI Commands Module
- **File**: `/home/quinten/fh/canopy/packages/canopy-terminal/src/CLI/Commands.hs`
- **Purpose**: Command definitions and configurations
- **Size**: 400 lines
- **Key exports**: `createMakeCommand`, `createInstallCommand`, `createFFITestCommand`, etc.
- **Pattern**: Shows command creation pattern for implementation
- **Line 189-195**: `createFFITestCommand` - blueprint for general test command

### Existing FFI Test Command (REFERENCE IMPLEMENTATION)
- **File**: `/home/quinten/fh/canopy/packages/canopy-terminal/src/Test/FFI.hs`
- **Purpose**: FFI testing and validation
- **Size**: ~550+ lines (check with `wc -l`)
- **Key types**:
  - `FFITestConfig` (lines 59-74)
  - `defaultFFITestConfig` (lines 77-86)
- **Key functions**:
  - `run :: FFITestConfig -> IO Exit.Code` (main handler)
  - `generateTests :: FilePath -> IO ()`
  - `validateContracts :: FilePath -> IO ()`
  - `runWithWatch :: FilePath -> IO ()`
- **Pattern**: This is the exact pattern to follow for `canopy test`

### Test Unit Examples
- **File**: `/home/quinten/fh/canopy/test/Unit/Parse/ExpressionTest.hs`
- **Purpose**: Example unit test structure
- **Pattern**: 
  ```haskell
  module Unit.Parse.ExpressionTest (tests) where
  tests :: TestTree
  tests = testGroup "Parse.Expression" [...]
  ```

- **File**: `/home/quinten/fh/canopy/test/Unit/Canopy/VersionTest.hs`
- **Purpose**: Version testing example
- **Size**: Medium, good for reference

### Property Tests
- **File**: `/home/quinten/fh/canopy/test/Property/Canopy/VersionProps.hs`
- **Purpose**: Property-based testing pattern
- **Pattern**: QuickCheck properties with `testProperty`

### Integration Tests
- **File**: `/home/quinten/fh/canopy/test/Integration/InitTest.hs`
- **Purpose**: Multi-component integration testing
- **Pattern**: Tests involving file I/O and system operations

### Golden Tests
- **File**: `/home/quinten/fh/canopy/test/Golden/ParseModuleGolden.hs`
- **Purpose**: Output comparison testing
- **Pattern**: Uses `tasty-golden` for file comparison

## Build and Configuration Files

### Makefile Test Targets
- **File**: `/home/quinten/fh/canopy/Makefile`
- **Test targets**: Lines 54-90
- **Key targets**:
  - Line 54-56: `test` - all tests
  - Line 58-60: `test-match` - pattern-based
  - Line 62-64: `test-unit` - unit tests only
  - Line 66-68: `test-property` - property tests
  - Line 70-72: `test-integration` - integration tests
  - Line 74-76: `test-watch` - watch mode
  - Line 78-81: `test-coverage` - coverage reports

### Stack Configuration
- **File**: `/home/quinten/fh/canopy/stack.yaml`
- **Purpose**: Haskell build configuration
- **Packages**: Lines 3-9 list all packages including test packages

### Cabal Package Configuration
- **File**: `/home/quinten/fh/canopy/canopy.cabal`
- **Purpose**: Build dependencies and test configuration
- **Size**: 100+ lines
- **Test executables**: Defined in sections after library

### Project Configuration
- **File**: `/home/quinten/fh/canopy/canopy.json`
- **Current test config**: Lines 16-20 - empty test-dependencies
- **Note**: No test configuration section yet

## Terminal Framework Files

### Terminal Command Definition
- **File**: `/home/quinten/fh/canopy/packages/canopy-terminal/impl/Terminal/Command.hs`
- **Purpose**: Command execution management
- **Key functions**:
  - `handleCommandExecution` - Execute command with args
  - `findCommand` - Locate command by name
  - `executeCommand` - Parse and execute

### Terminal Types
- **File**: `/home/quinten/fh/canopy/packages/canopy-terminal/impl/Terminal/Types.hs`
- **Key types**:
  - `Command` - Command definition
  - `CommandMeta` - Command metadata
  - `AppConfig` - Application configuration

### Terminal Parser
- **File**: `/home/quinten/fh/canopy/packages/canopy-terminal/impl/Terminal/Parser.hs`
- **Purpose**: Argument and flag parsing

### Terminal Application
- **File**: `/home/quinten/fh/canopy/packages/canopy-terminal/impl/Terminal/Application.hs`
- **Purpose**: Application lifecycle management

## Other Important Files

### Make Command Module
- **File**: `/home/quinten/fh/canopy/packages/canopy-terminal/src/Make.hs`
- **Purpose**: Compilation command implementation
- **Pattern**: Similar structure to what `Test` command needs
- **Key exports**: `Flags`, `Output`, `ReportType`, `run`

### Init Command Module
- **File**: `/home/quinten/fh/canopy/packages/canopy-terminal/src/Init.hs`
- **Purpose**: Project initialization
- **Pattern**: Good example of command structure

### Compiler Driver
- **File**: `/home/quinten/fh/canopy/packages/canopy-driver/src/`
- **Purpose**: High-level compilation orchestration
- **Integration**: Likely where test runner would hook in

### Test Documentation
- **File**: `/home/quinten/fh/canopy/test/IMPLEMENTATION-SUMMARY.md`
- **Purpose**: Test suite improvement plan
- **Content**: Statistics, anti-patterns, refactoring guide

## Key Code Patterns

### Command Definition Pattern (from CLI/Commands.hs)

```haskell
-- Location: /home/quinten/fh/canopy/packages/canopy-terminal/src/CLI/Commands.hs

createFFITestCommand :: Command
createFFITestCommand =
  Terminal.Command 
    "test-ffi"                    -- Command name
    Terminal.Uncommon             -- Frequency (Common/Uncommon)
    details                       -- Help text
    example                       -- Usage example  
    Terminal.noArgs               -- Argument parser
    flags                         -- Flag parser
    FFI.run                       -- Handler function
  where
    details = createFFITestDetails
    example = createFFITestExample
    flags = createFFITestFlags
```

### Handler Function Pattern (from Test/FFI.hs)

```haskell
-- Location: /home/quinten/fh/canopy/packages/canopy-terminal/src/Test/FFI.hs

-- Configuration type
data FFITestConfig = FFITestConfig
  { ffiTestGenerate :: !Bool
  , ffiTestOutput :: !(Maybe FilePath)
  , ffiTestWatch :: !Bool
  , ffiTestValidateOnly :: !Bool
  , ffiTestVerbose :: !Bool
  , ffiTestPropertyRuns :: !(Maybe Int)
  , ffiTestBrowser :: !Bool
  } deriving (Eq, Show)

-- Main handler
run :: FFITestConfig -> IO Exit.Code
run config = do
  -- Implementation
  pure Exit.ExitSuccess

-- Component functions
generateTests :: FilePath -> IO ()
validateContracts :: FilePath -> IO ()
runWithWatch :: FilePath -> IO ()
```

### Test Module Pattern (from Unit/*/Test.hs)

```haskell
module Unit.Parse.ExpressionTest (tests) where

import Test.Tasty
import Test.Tasty.HUnit

parseExpr :: String -> Either E.Expr Src.Expr
parseExpr s = -- implementation

tests :: TestTree
tests = testGroup "Parse.Expression"
  [ testGroup "literals"
      [ testCase "int" $ -- test
      , testCase "float" $ -- test
      ]
  , testGroup "operators"
      [ testCase "addition" $ -- test
      ]
  ]
```

## Key Modules and Imports

### For Creating a Test Command

```haskell
-- Required imports for new Test command

import qualified Exit                      -- Exit codes
import qualified Terminal                  -- CLI framework
import qualified Terminal.Helpers as Terminal -- Helpers
import Text.PrettyPrint.ANSI.Leijen (Doc)  -- Documentation

-- For running tests
import qualified System.Process as Process  -- External processes
import qualified System.Directory as Dir    -- File operations
import System.Exit (ExitCode)               -- Exit codes

-- For configuration
import Data.Text (Text)
import qualified Data.Map.Strict as Map
```

### For Integration with Terminal

```haskell
-- Terminal.Command structure
data Command = Command
  { cmdName :: String
  , cmdMeta :: CommandMeta
  , cmdHandler :: Flags -> IO Exit.Code
  }

-- Create command helper
Terminal.Command :: String -> CommandMeta -> ...
                   -> Args -> Flags -> Handler -> Command

-- Frequency markers
Terminal.Common      -- Frequently used (init, repl, etc.)
Terminal.Uncommon    -- Less frequently used (test, publish, etc.)

-- Argument/flag parsers
Terminal.noArgs      -- No positional arguments
Terminal.noFlags     -- No flags
Terminal.zeroOrMore  -- Zero or more arguments
Terminal.oneOrMore   -- One or more arguments
```

## File Discovery Checklist

For understanding the testing infrastructure:

- [ ] Review test/Main.hs (master test coordinator)
- [ ] Review app/Main.hs (CLI entry point)
- [ ] Review CLI/Commands.hs (command registration)
- [ ] Review Test/FFI.hs (reference implementation)
- [ ] Review test/Unit/Parse/ExpressionTest.hs (unit test example)
- [ ] Review Makefile (test targets)
- [ ] Review stack.yaml (build configuration)
- [ ] Review canopy.json (project config)

For implementing `canopy test` command:

- [ ] Create Test.hs module (follow Test/FFI.hs pattern)
- [ ] Add createTestCommand to CLI/Commands.hs
- [ ] Define TestConfig type
- [ ] Implement test discovery
- [ ] Implement test runner integration
- [ ] Add flags and argument parsers
- [ ] Add help text and documentation
- [ ] Register in app/Main.hs

## Performance Metrics

From test analysis:
- Current test suite: ~5 minutes (unit tests only)
- Target: ~2.5 minutes
- Test count: 70+ enabled, 150+ disabled
- Coverage target: 80%+

## Related Documentation

- `/home/quinten/fh/canopy/test/IMPLEMENTATION-SUMMARY.md` - Test suite plan
- `/home/quinten/fh/canopy/test/TEST-SUITE-IMPROVEMENT-PLAN.md` - Detailed plan
- `/home/quinten/fh/canopy/CLAUDE.md` - Development standards (test requirements)
- `/home/quinten/fh/canopy/TESTING_INFRASTRUCTURE_REPORT.md` - Detailed analysis
- `/home/quinten/fh/canopy/TESTING_QUICK_SUMMARY.txt` - Quick reference
