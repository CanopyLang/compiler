# Canopy Test Command - Quick Reference

## Executive Summary

Implement a general-purpose `canopy test` command for Canopy projects, providing comprehensive testing capabilities beyond FFI testing.

**Status**: ✅ Research Complete - Ready for Implementation
**Effort**: 2-3 weeks
**Priority**: High

---

## Quick Start (MVP Implementation)

### Command Usage

```bash
# Basic usage
canopy test                          # Run all tests
canopy test --pattern "Parser"       # Run filtered tests
canopy test --watch                  # Watch mode
canopy test --coverage               # Generate coverage report
canopy test --generate-template src/Foo.can  # Generate test template
```

### Architecture Overview

```
packages/canopy-terminal/src/Test/
├── General.hs       -- Main command (400 lines)
├── Discovery.hs     -- Test discovery (300 lines)
├── Runner.hs        -- Test execution (400 lines)
├── Watcher.hs       -- File watching (250 lines)
├── Coverage.hs      -- Coverage analysis (200 lines)
├── Templates.hs     -- Test generation (300 lines)
├── Types.hs         -- Core types (150 lines)
└── FFI.hs           -- Existing FFI tests (902 lines)
```

**Total New Code**: ~2000 lines

---

## Implementation Timeline

### Week 1: Foundation
- ✅ Implement `Test/Types.hs` (core types)
- ✅ Implement `Test/Discovery.hs` (test discovery)
- ✅ Write unit tests for discovery

**Deliverable**: Test discovery working

### Week 2: Execution
- ✅ Implement `Test/Runner.hs` (test execution)
- ✅ Implement `Test/Templates.hs` (test generation)
- ✅ CLI integration
- ✅ Integration tests

**Deliverable**: MVP - `canopy test` command functional

### Week 3: Advanced Features
- ✅ Implement `Test/Watcher.hs` (watch mode)
- ✅ Implement `Test/Coverage.hs` (coverage)
- ✅ Polish and documentation

**Deliverable**: Feature complete

---

## Core Types

```haskell
-- Test configuration
data TestConfig = TestConfig
  { testPattern :: !(Maybe Text)      -- Filter pattern
  , testWatch :: !Bool                -- Watch mode
  , testCoverage :: !Bool             -- Coverage report
  , testVerbose :: !Bool              -- Verbose output
  , testQuiet :: !Bool                -- Minimal output
  , testParallel :: !Bool             -- Parallel execution
  , testJobs :: !(Maybe Int)          -- Parallel jobs
  , testSeed :: !(Maybe Int)          -- Random seed
  , testOutput :: !(Maybe FilePath)   -- Output directory
  , testGenerateTemplate :: !(Maybe FilePath)  -- Template generation
  , testUpdateGolden :: !Bool         -- Update golden files
  , testTimeout :: !(Maybe Int)       -- Timeout per test
  , testFailFast :: !Bool             -- Stop on first failure
  }

-- Test discovery result
data TestModule = TestModule
  { testModulePath :: !FilePath
  , testModuleName :: !Text
  , testModuleType :: !TestType
  , testModuleSuite :: !Text
  }

-- Test types
data TestType
  = UnitTest
  | PropertyTest
  | GoldenTest
  | IntegrationTest
```

---

## Test Discovery Algorithm

1. Scan directories: `test/`, `tests/`, `src/`
2. Find files: `*Test.hs`, `*Tests.hs`, `*Spec.hs`, `*Props.hs`
3. Parse imports to classify:
   - `Test.Tasty.HUnit` → UnitTest
   - `Test.Tasty.QuickCheck` → PropertyTest
   - `Test.Tasty.Golden` → GoldenTest
4. Extract `tests :: TestTree` definition
5. Build test hierarchy

---

## Test Execution Strategy

**Approach**: Static Compilation (reliable, simple)

1. Generate temporary `Main.hs` importing all test modules
2. Compile with `stack build` or `cabal build`
3. Execute resulting binary
4. Parse output for results
5. Format for CLI display

**Alternative**: Dynamic compilation with GHC API (future enhancement)

---

## CLI Integration

### Add to CLI/Commands.hs

```haskell
import qualified Test.General as TestGeneral

createTestCommand :: Command
createTestCommand =
  Terminal.Command "test" Terminal.Uncommon details example Terminal.noArgs flags TestGeneral.run
  where
    details = "The `test` command runs Canopy tests..."
    example = stackDocuments [...]
    flags = createTestFlags

createTestFlags :: Terminal.Flags TestGeneral.TestConfig
createTestFlags =
  Terminal.flags TestGeneral.TestConfig
    |-- Terminal.flag "pattern" TestGeneral.patternParser "Filter tests"
    |-- Terminal.onOff "watch" "Watch for file changes"
    |-- Terminal.onOff "coverage" "Generate coverage report"
    |-- Terminal.onOff "verbose" "Verbose output"
    |-- Terminal.onOff "quiet" "Minimal output"
    -- ... (more flags)
```

### Add to app/Main.hs

```haskell
import CLI.Commands (createTestCommand)

createAllCommands :: [Terminal.Command]
createAllCommands =
  [ ...
  , createTestCommand      -- Add this line
  , ...
  ]
```

---

## Dependencies

### Required (add to package.yaml)

```yaml
dependencies:
  - fsnotify >= 0.4       # File system watching
  - hpc >= 0.6            # Coverage analysis
  - process >= 1.6        # Process execution
  - directory >= 1.3      # File system operations
  - filepath >= 1.4       # File path manipulation
  - unix >= 2.7           # POSIX operations
```

---

## Testing Strategy

### Unit Tests (≥80% coverage)

```
test/Unit/Test/
├── TypesTest.hs
├── DiscoveryTest.hs
├── RunnerTest.hs
├── WatcherTest.hs
├── CoverageTest.hs
└── TemplatesTest.hs
```

### Integration Tests

```
test/Integration/
├── TestCommandIntegrationTest.hs
├── TestDiscoveryTest.hs
└── TestRunnerTest.hs
```

---

## Success Criteria

### Functional
- ✅ Test discovery finds all test modules
- ✅ Test execution runs all test types
- ✅ Test filtering works with patterns
- ✅ Watch mode detects changes
- ✅ Coverage reports generate correctly
- ✅ Template generation creates valid files
- ✅ Exit codes work for CI/CD

### Non-Functional
- ✅ Performance: <5s for small projects
- ✅ Reliability: No false positives/negatives
- ✅ Usability: Intuitive CLI
- ✅ Code follows CLAUDE.md standards
- ✅ Documentation complete
- ✅ Test coverage ≥80%

---

## Example User Flow

```bash
# Initialize project with tests
$ canopy init
$ canopy test --generate-template src/Parser.can
📝 Generating test template...
✅ Created test/Unit/ParserTest.hs

# Run tests
$ canopy test
🧪 Canopy Test Suite
📄 Discovering tests...
✅ Found 15 test modules

🚀 Running tests...
  Unit Tests (12 modules)
    ✅ Parser.Expression (8 tests, 0.12s)
    ✅ Parser.Module (12 tests, 0.18s)
    ...

📊 Test Results:
  Total: 156 tests
  Passed: 156
  Failed: 0
  Duration: 2.34s

✅ All tests passed!

# Watch mode for development
$ canopy test --watch
👀 Watching for changes...
✅ 156 tests passed

[File changed: src/Parser.hs]
🔄 Re-running tests...
❌ 1 test failed:
  Parser.Expression.test_parseIf
    Expected: Right (If ...)
    Got: Left (ParseError ...)

# Generate coverage report
$ canopy test --coverage
📊 Coverage Report:
  Overall: 87.3%
  Parser.Expression: 95.2%
  Type.Inference: 91.8%

  Detailed report: coverage/hpc_index.html
```

---

## Key Design Decisions

### 1. Static vs Dynamic Compilation
**Decision**: Start with static compilation
**Rationale**: More reliable, simpler to implement, battle-tested

### 2. Test Discovery Strategy
**Decision**: File-based discovery with pattern matching
**Rationale**: Intuitive, works with existing test structure

### 3. File Watching
**Decision**: Use `fsnotify` library
**Rationale**: Already used in `Watch.hs`, proven reliability

### 4. Coverage Tool
**Decision**: Use HPC (Haskell Program Coverage)
**Rationale**: Standard tool, good IDE integration

### 5. Test Framework
**Decision**: Continue using Tasty
**Rationale**: Already in use, comprehensive feature set

---

## Future Enhancements (Post-MVP)

### Phase 2 Features
1. **Snapshot Testing** - Like Jest snapshots
2. **Test Profiling** - Identify slow tests
3. **Interactive Mode** - Select tests interactively
4. **Test Splitting** - Split across CI jobs
5. **Test Retries** - Retry flaky tests

### Advanced Features
6. **Browser Testing** - Extend FFI approach
7. **Mutation Testing** - Detect weak tests
8. **Fuzz Testing** - Automated fuzzing
9. **Visual Regression** - Screenshot comparison
10. **Impact Analysis** - Only run affected tests

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Dynamic compilation complexity | Use static compilation first |
| File watching reliability | Use battle-tested `fsnotify` |
| Test discovery edge cases | Comprehensive unit tests |
| Performance with large suites | Implement parallel execution |
| Scope creep | Strict MVP, phase-based delivery |

---

## References

### Existing Code
- `/packages/canopy-terminal/src/Test/FFI.hs` - FFI test implementation (902 lines)
- `/test/Main.hs` - Test suite entry (253 lines)
- `/packages/canopy-terminal/src/CLI/Commands.hs` - CLI commands (404 lines)
- `/packages/canopy-terminal/src/Watch.hs` - File watching example

### Similar Tools
- **elm-test** - Elm test framework (inspiration)
- **jest** - JavaScript test runner (watch mode)
- **cargo test** - Rust test command (pattern matching)
- **pytest** - Python test framework (discovery)

### Documentation
- [Tasty Documentation](https://hackage.haskell.org/package/tasty)
- [HPC Guide](https://wiki.haskell.org/Haskell_program_coverage)
- [FSNotify](https://hackage.haskell.org/package/fsnotify)

---

## Next Steps

1. ✅ Review implementation plan
2. ⏳ Get user approval
3. ⏳ Create implementation tasks
4. ⏳ Begin Phase 1 (Foundation)
5. ⏳ Iterate based on feedback

---

## Questions for User

Before implementation:

1. **Priority**: High priority or can it wait?
2. **Scope**: MVP (Phase 1-2) or full implementation?
3. **Integration**: Replace `canopy test-ffi` or complement it?
4. **Naming**: `canopy test` or `canopy test-run`?
5. **Compatibility**: Work with existing `/test/Main.hs`?
6. **Coverage**: HPC-based coverage acceptable?

---

**Document Version**: 1.0
**Last Updated**: 2025-11-10
**Full Plan**: See `CANOPY_TEST_COMMAND_IMPLEMENTATION_PLAN.md`
