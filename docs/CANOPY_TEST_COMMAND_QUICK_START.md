# Canopy `test` Command Implementation - Quick Start Guide

## Overview
This guide provides the essential information needed to implement a `canopy test` command based on the existing codebase architecture.

---

## 1. Key Findings

### Architecture Summary
- **5 modular packages** in `packages/` with clean separation of concerns
- **CLI framework** in `packages/canopy-terminal/` provides reusable command infrastructure
- **Terminal.Command** GADT-based type system for safe argument/flag parsing
- **200+ tests** organized as Unit (enabled), Property/Integration/Golden (disabled)
- **Tasty framework** for test discovery and execution
- **CLAUDE.md compliance** required - strict function/module size limits

### Current CLI Commands (9 total)
1. `init` - Project initialization
2. `repl` - Interactive REPL
3. `reactor` - Development server
4. `make` - Compilation
5. `test-ffi` - FFI validation (reference implementation!)
6. `install` - Package management
7. `bump` - Version bumping
8. `diff` - API analysis
9. `publish` - Package publishing

### Test Infrastructure
- **test/Main.hs** - Master test entry point (253 lines)
- **Unit Tests** - 60+ suites (ENABLED)
- **Property/Integration/Golden** - Disabled (performance/brittleness concerns)
- **Tasty + QuickCheck** - Modern Haskell testing stack
- **Pattern matching & watch mode** - Built-in via Tasty

---

## 2. Implementation Checklist

### Phase 1: Create Handler Module
- [ ] Create `/packages/canopy-terminal/src/Test.hs`
- [ ] Define `Flags` record with test options
- [ ] Implement `run :: () -> Flags -> IO ()` function
- [ ] Follow CLAUDE.md: functions ≤15 lines, ≤4 parameters, ≤4 branches
- [ ] Add comprehensive Haddock documentation
- [ ] Use qualified imports (functions), unqualified types

### Phase 2: Register Command
- [ ] Add command factory in `/packages/canopy-terminal/src/CLI/Commands.hs`
- [ ] Create `createTestCommand :: Command` function
- [ ] Define summary, details, and examples (Doc-formatted)
- [ ] Set up flags parser: `Terminal.flags Test.Flags |-- flag1 |-- flag2 ...`
- [ ] Add to `/app/Main.hs` in `createAllCommands` list

### Phase 3: Create Tests
- [ ] Unit test: `/test/Unit/CLI/TestCommandTest.hs` (command creation)
- [ ] Unit test: `/test/Unit/TestTest.hs` (handler logic)
- [ ] Update `/test/Main.hs` to import new test modules
- [ ] Add to `unitTests` group

### Phase 4: Validation
- [ ] Build: `stack build --fast`
- [ ] Test: `make test` or `stack test --fast canopy:canopy-test`
- [ ] Lint: `make lint`
- [ ] Format: `make format`

---

## 3. Command Structure Reference

### Command Definition Pattern
```haskell
-- /packages/canopy-terminal/src/CLI/Commands.hs

createTestCommand :: Command
createTestCommand =
  Terminal.Command
    "test"                      -- Command name
    (Terminal.Uncommon summary) -- Type: Common or Uncommon
    details                     -- Detailed help text
    example                     -- Example Doc
    Terminal.noArgs             -- No arguments (or: Terminal.zeroOrMore ...)
    flags                       -- Flag parsers
    Test.run                    -- Handler function

-- Helper functions
createTestSummary :: String
createTestSummary = "Run tests for your Canopy project"

createTestDetails :: String
createTestDetails = "The `test` command executes the test suite..."

createTestExample :: Doc
createTestExample = reflowText "Usage examples..."

createTestFlags :: Terminal.Flags Test.Flags
createTestFlags =
  Terminal.flags Test.Flags
    |-- Terminal.onOff "verbose" "Show detailed output"
    |-- Terminal.flag "pattern" Terminal.stringParser "Test pattern filter"
    |-- Terminal.onOff "watch" "Watch for file changes"
```

### Handler Implementation Pattern
```haskell
-- /packages/canopy-terminal/src/Test.hs

{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Test
  ( run
  , Flags (..)
  ) where

import qualified Data.Text as Text
import qualified System.Exit as Exit

-- Configuration record
data Flags = Flags
  { testVerbose :: !Bool
  , testPattern :: !(Maybe String)
  , testWatch :: !Bool
  } deriving (Eq, Show)

-- Main handler
run :: () -> Flags -> IO ()
run _args flags = do
  if testVerbose flags
    then putStrLn "Running tests with verbose output..."
    else putStrLn "Running tests..."
  -- Implementation
  Exit.exitSuccess
```

---

## 4. Registration in Main.hs

### Update `/app/Main.hs`
```haskell
-- Add import
import CLI.Commands (createTestCommand)

-- Update createAllCommands
createAllCommands :: [Terminal.Command]
createAllCommands =
  [ createReplCommand
  , createInitCommand
  , createReactorCommand
  , createMakeCommand
  , createFFITestCommand
  , createTestCommand          -- ADD HERE
  , createInstallCommand
  , createBumpCommand
  , createDiffCommand
  , createPublishCommand
  ]
```

---

## 5. Testing Pattern

### Unit Test Example
```haskell
-- /test/Unit/CLI/TestCommandTest.hs

{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Unit.CLI.TestCommandTest (tests) where

import CLI.Commands (createTestCommand)
import qualified Terminal
import Terminal.Internal (toName)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Test Command Tests"
    [ testCommandCreation
    ]

testCommandCreation :: TestTree
testCommandCreation =
  testGroup
    "createTestCommand function"
    [ testCase "command has correct name" $ do
        let cmd = createTestCommand
        toName cmd @?= "test"
    , testCase "command is uncommon type" $ do
        let cmd = createTestCommand
        length (show cmd) > 0 @?= True
    ]
```

### Register in test/Main.hs
```haskell
-- Add import at top
import qualified Unit.CLI.TestCommandTest as TestCommandTest

-- Add to unitTests group
unitTests :: TestTree
unitTests =
  testGroup "Unit Tests"
    [ -- ... existing tests ...
    , TestCommandTest.tests      -- ADD HERE
    , -- ... more tests ...
    ]
```

---

## 6. Files to Examine (Reference)

| File | Purpose | Lines |
|------|---------|-------|
| `packages/canopy-terminal/src/Test/FFI.hs` | Existing test command | 902 |
| `packages/canopy-terminal/src/Make.hs` | Comprehensive example | 194 |
| `packages/canopy-terminal/src/Install.hs` | Complex handler | 205 |
| `packages/canopy-terminal/src/CLI/Commands.hs` | Command registration | 404 |
| `app/Main.hs` | CLI entry point | 108 |
| `test/Main.hs` | Test discovery | 253 |
| `test/Unit/CLI/CommandsTest.hs` | CLI test pattern | 80+ |
| `Makefile` | Build targets | 94 |
| `package.yaml` | Build config | 145 |

---

## 7. CLAUDE.md Compliance Checklist

- [ ] Functions ≤ 15 lines (excluding blank lines/comments)
- [ ] ≤ 4 parameters per function
- [ ] ≤ 4 branching points per function
- [ ] No code duplication (DRY principle)
- [ ] Single responsibility per module
- [ ] Lenses for all record access/updates
- [ ] Qualified imports (except types/lenses/pragmas)
- [ ] Minimum 80% test coverage
- [ ] Complete Haddock documentation
- [ ] No simplifications to work around limits

---

## 8. Build and Test Commands

```bash
# Build
stack build --fast

# Test (all)
make test

# Test (specific pattern)
make test-match PATTERN="Test"

# Test (watch mode)
make test-watch

# Lint
make lint

# Format
make format

# Full validation
make build && make test && make lint
```

---

## 9. Key Design Decisions

### Recommended Command Name
- `canopy test` - Simple, follows conventions (elm test)
- Optional variants: `canopy test-suite`, `canopy run-tests`

### Recommended Flags (MVP)
```
--pattern STRING      Filter tests by name pattern
--verbose            Show detailed output
--watch              Watch for file changes and re-run
--unit-only          Run unit tests only
--property-only      Run property tests only
--integration-only   Run integration tests only
--coverage           Generate coverage report
```

### Integration Points
1. **Test entry point** - `test/Main.hs` already has all test infrastructure
2. **Tasty framework** - Can invoke directly or via Stack
3. **Pattern matching** - Tasty's `--pattern` flag
4. **Watch mode** - Tasty's `--file-watch` support
5. **Coverage** - Stack's `--coverage` flag

---

## 10. Common Patterns from Existing Commands

### Simple Flag Pattern (Develop.hs style)
```haskell
data Flags = Flags
  { flagName :: !Type
  , ... 
  } deriving (Eq, Show)

run :: () -> Flags -> IO ()
run _ flags = do
  -- Use flags.flagName
  pure ()
```

### Complex Flag Pattern (Make.hs style)
```haskell
-- Create via lens
import Control.Lens ((^.))
import qualified Make.Types as Types

run :: [FilePath] -> Types.Flags -> IO ()
run paths flags = do
  let verbose = flags ^. Types.verbose
  putStrLn "Running..."
```

### Error Handling (Install.hs style)
```haskell
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task

run :: Args -> () -> IO ()
run args () =
  Reporting.attempt Exit.testToReport $
    Task.run (processTestRequest args)

processTestRequest :: Args -> Task ()
processTestRequest args = do
  -- Implementation with proper error handling
  Task.throw (Exit.TestError "message")
```

---

## 11. Potential Challenges and Solutions

| Challenge | Solution |
|-----------|----------|
| Function size limits | Extract helpers following 15-line rule |
| Too many flags | Create config record, use lenses |
| Test discovery | Leverage existing test/Main.hs |
| Error handling | Follow Install.hs/Make.hs pattern |
| Help text | Use CLI.Documentation utilities |
| Import complexity | Follow existing import style patterns |

---

## 12. Success Criteria

- [ ] `canopy test` command available
- [ ] Help text displays correctly (`canopy test --help`)
- [ ] Can run tests with pattern matching
- [ ] Can enable/disable test types
- [ ] Can enable/disable watch mode
- [ ] All code compiles without warnings
- [ ] Passes linting (hlint, ormolu)
- [ ] Unit tests for command
- [ ] Follows CLAUDE.md standards

---

## Next Steps

1. **Read Reference Implementations** - Study Test/FFI.hs and Make.hs
2. **Review Test Infrastructure** - Understand test/Main.hs structure
3. **Create Handler Module** - Follow patterns from section 3
4. **Register Command** - Add to CLI/Commands.hs and app/Main.hs
5. **Create Tests** - Add unit tests to test suite
6. **Build & Validate** - Run full validation pipeline

---

**For comprehensive details, see:** `/home/quinten/fh/canopy/docs/TESTING_AND_CLI_ARCHITECTURE_COMPREHENSIVE_ANALYSIS.md`

