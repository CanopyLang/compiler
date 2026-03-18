# Canopy Testing and CLI - Quick Reference

## Key Directories and Files

### Project Structure
```
/home/quinten/fh/canopy/
├── test/Main.hs                          (253 lines - test suite entry point)
├── packages/canopy-terminal/src/Test/FFI.hs  (902 lines - FFI test command)
├── packages/canopy-core/src/Foreign/FFI.hs   (882 lines - FFI type system)
├── packages/canopy-terminal/src/CLI/Commands.hs (404 lines - CLI definitions)
├── app/Main.hs                           (108 lines - CLI app entry)
├── package.yaml                          (test suite config)
├── stack.yaml                            (build config)
├── Makefile                              (94 lines - build automation)
```

## Test Organization

### Test Suite Structure
- **Unit Tests** - 60+ suites in `/test/Unit/` (enabled)
- **Property Tests** - 11 suites in `/test/Property/` (disabled)
- **Integration Tests** - 16+ suites in `/test/Integration/` (mostly disabled)
- **Golden Tests** - 5 suites in `/test/Golden/` (disabled)

### FFI Testing
- **FFI Type Parse Tests** - `/test/Unit/Foreign/FFITypeParseTest.hs`
- **Audio FFI Tests** - `/test/Unit/Foreign/AudioFFITest.hs`
- **FFI Command** - `/packages/canopy-terminal/src/Test/FFI.hs`

## CLI Commands

### Available Commands
```
canopy init           # Start a new project
canopy repl           # Interactive session
canopy reactor        # Development server
canopy make           # Compile code
canopy test-ffi       # Test FFI functions (NEW)
canopy install        # Install packages
canopy bump           # Version bumping
canopy diff           # API changes
canopy publish        # Publish packages
```

### FFI Test Command Details
```bash
canopy test-ffi [FLAGS]

Flags:
  --generate          Generate test files instead of running
  --output <dir>      Output directory (default: test-generation/)
  --watch             Watch for changes and re-run
  --validate-only     Only validate FFI contracts
  --verbose           Show detailed progress
  --property-runs <n> Number of property tests (default: 100)
  --browser           Run in browser instead of Node.js
```

## Running Tests

### Via Makefile
```bash
make test                    # All unit tests
make test-unit               # Unit tests only
make test-property           # Property tests
make test-integration        # Integration tests
make test-watch              # Watch mode
make test-match PATTERN="FFI" # Pattern matching
make test-coverage           # Coverage report
make test-deps               # Install test deps
```

### Via Stack
```bash
# Build project
stack build --fast

# Run all tests
stack test --fast canopy:canopy-test

# Run with pattern
stack test --fast canopy:canopy-test -- --pattern "Foreign"

# Watch mode
stack test --fast canopy:canopy-test --file-watch

# Coverage
stack test --coverage --fast canopy:canopy-test
```

## Test Module Locations

### Unit Tests (enabled - 60+ suites)
- `/test/Unit/Data/` - NameTest, IndexTest, BagTest, etc.
- `/test/Unit/Parse/` - ExpressionTest, ModuleTest, TypeTest, PatternTest
- `/test/Unit/AST/` - CanonicalTypeTest, OptimizedTest, SourceAstTest
- `/test/Unit/Builder/` - HashTest, GraphTest, StateTest, SolverTest
- `/test/Unit/CLI/` - CommandsTest, ParsersTest, DocumentationTest
- `/test/Unit/Foreign/` - FFITypeParseTest, AudioFFITest
- `/test/Unit/Develop/`, `/test/Unit/Diff/`, `/test/Unit/Init/`, etc.

### Property Tests (disabled - 11 suites)
- `/test/Property/Data/NameProps.hs`
- `/test/Property/Canopy/VersionProps.hs`
- `/test/Property/AST/CanonicalProps.hs`
- `/test/Property/AST/OptimizedProps.hs`
- `/test/Property/AST/OptimizedBinaryProps.hs`
- `/test/Property/InitProps.hs`, etc.

### Integration Tests (mostly disabled)
- `/test/Integration/InitTest.hs`
- `/test/Integration/MakeTest.hs`
- `/test/Integration/CompileIntegrationTest.hs`
- `/test/Integration/PureBuilderIntegrationTest.hs`

### Golden Tests (disabled)
- `/test/Golden/ParseModuleGolden.hs`
- `/test/Golden/ParseExprGolden.hs`
- `/test/Golden/ParseTypeGolden.hs`
- `/test/Golden/ParseAliasGolden.hs`
- `/test/Golden/JsGenGolden.hs`
- Expected outputs in `/test/Golden/expected/elm-canopy/` (180+ files)

## Code Quality

### Linting and Formatting
```bash
make format              # Format code with ormolu
make lint                # Check with hlint and ormolu
make fix-lint            # Auto-fix lint issues
make fix-lint-folder FOLDER=test  # Fix specific folder
```

## FFI System Details

### FFI Type Support
- `FFIBasic "String"`     - Basic types
- `FFIOpaque "AudioContext"` - Opaque JS types
- `FFIMaybe FFIType`      - Optional types
- `FFIList FFIType`       - List types
- `FFIResult e v`         - Union types
- `FFITask e v`           - Async operations
- `FFIFunction params ret` - Function types

### FFI Test Configuration
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

## Test Framework Stack

- **Tasty** - Test runner and organizer
- **Tasty-HUnit** - Unit test assertions
- **Tasty-QuickCheck** - Property testing
- **Tasty-Golden** - Golden file testing
- **QuickCheck** - Property generation
- **Temporary** - Temp file handling

## Packages Overview

### canopy-terminal
- CLI commands and interfaces
- FFI testing command
- Terminal UI utilities
- **Test file:** `/test/Unit/Terminal/`, `/test/Unit/CLI/`

### canopy-core
- Core language types
- FFI type system
- Foreign function support
- **Test files:** `/test/Unit/Foreign/`, `/test/Unit/Data/`

### canopy-query
- Query engine
- Module resolution
- **Test files:** `/test/Unit/Query/`, `/test/Unit/Queries/`

### canopy-driver
- Compilation driver
- Build orchestration
- **Test files:** `/test/Unit/New/Compiler/`

### canopy-builder
- Build system
- Artifact management
- Solver and dependency resolution
- **Test files:** `/test/Unit/Builder/`

## Build Commands

### Main Makefile Targets
```makefile
build              # Build project
clean              # Clean build artifacts
test               # Run all tests
test-unit          # Unit tests only
test-property      # Property tests
test-integration   # Integration tests
test-watch         # Watch mode
test-coverage      # Coverage report
test-build         # Build without running
test-deps          # Install dependencies
test-match         # Pattern-based test running
lint               # Check code quality
fix-lint           # Auto-fix lint issues
format             # Format code
```

## Important Notes

### Disabled Tests
- **Property tests** - Performance concerns
- **Most integration tests** - File I/O overhead
- **Golden tests** - Brittle string matching, package compilation
- See `/test/Main.hs` lines 122-124 for disabled test groups

### FFI Type Ordering
- Parameters are parsed left-to-right
- Crucial for correct function signatures
- Tests verify this in `FFITypeParseTest.hs`

### Test Entry Point
All tests controlled from `/test/Main.hs`:
```haskell
tests :: TestTree
tests = testGroup "Canopy Tests" [ unitTests ]
-- propertyTests, integrationTests, goldenTests are commented out
```

---

**For comprehensive details, see:** `TESTING_INFRASTRUCTURE_AND_CLI_COMPREHENSIVE_REPORT.md`
