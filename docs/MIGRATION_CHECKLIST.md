# Canopy Compiler Overhaul - Migration Checklist

## Phase 1: Foundation (Weeks 1-2)

### Package Structure Setup
- [ ] Create `packages/canopy-core/` directory
- [ ] Create `packages/canopy-query/` directory
- [ ] Create `packages/canopy-driver/` directory
- [ ] Create `packages/canopy-builder/` directory
- [ ] Create `packages/canopy-terminal/` directory
- [ ] Create `old/` archive directory

### Package Configuration
- [ ] Create `packages/canopy-core/package.yaml`
- [ ] Create `packages/canopy-query/package.yaml`
- [ ] Create `packages/canopy-driver/package.yaml`
- [ ] Create `packages/canopy-builder/package.yaml`
- [ ] Create `packages/canopy-terminal/package.yaml`
- [ ] Update `stack.yaml` for multi-package build

### Move Core Modules (canopy-core)
- [ ] Move `compiler/src/AST/` → `packages/canopy-core/src/AST/`
- [ ] Move `compiler/src/Parse/` → `packages/canopy-core/src/Parse/`
- [ ] Move `compiler/src/Canonicalize/` → `packages/canopy-core/src/Canonicalize/`
- [ ] Move `compiler/src/Type/` → `packages/canopy-core/src/Type/`
- [ ] Move `compiler/src/Optimize/` → `packages/canopy-core/src/Optimize/`
- [ ] Move `compiler/src/Canopy/` → `packages/canopy-core/src/Canopy/`
- [ ] Move `compiler/src/Data/` → `packages/canopy-core/src/Data/`
- [ ] Move `compiler/src/Reporting/` → `packages/canopy-core/src/Reporting/`
- [ ] Move `compiler/src/Json/` → `packages/canopy-core/src/Json/`

### Move Query System (canopy-query)
- [ ] Move `New/Compiler/Query/Engine.hs` → `packages/canopy-query/src/Query/Engine.hs`
- [ ] Move `New/Compiler/Query/Simple.hs` → `packages/canopy-query/src/Query/Simple.hs`
- [ ] Move `New/Compiler/Debug/Logger.hs` → `packages/canopy-query/src/Query/Logger.hs`
- [ ] Create `packages/canopy-query/src/Query/Types.hs`
- [ ] Create `packages/canopy-query/src/Query/Cache.hs`
- [ ] Create `packages/canopy-query/src/Query/Dependencies.hs`
- [ ] Create `packages/canopy-query/src/Messages/Types.hs`

### Move Driver (canopy-driver)
- [ ] Move `New/Compiler/Driver.hs` → `packages/canopy-driver/src/Driver/Main.hs`
- [ ] Move `New/Compiler/Bridge.hs` → `packages/canopy-driver/src/Driver/Bridge.hs`
- [ ] Move `New/Compiler/Worker/Pool.hs` → `packages/canopy-driver/src/Driver/Worker.hs`
- [ ] Move `New/Compiler/Queries/Parse/Module.hs` → `packages/canopy-driver/src/Queries/Parse.hs`
- [ ] Move `New/Compiler/Queries/Canonicalize/Module.hs` → `packages/canopy-driver/src/Queries/Canonicalize.hs`
- [ ] Move `New/Compiler/Queries/Type/Check.hs` → `packages/canopy-driver/src/Queries/TypeCheck.hs`
- [ ] Move `New/Compiler/Queries/Optimize.hs` → `packages/canopy-driver/src/Queries/Optimize.hs`
- [ ] Move `New/Compiler/Queries/Generate.hs` → `packages/canopy-driver/src/Queries/Generate.hs`

### Validation
- [ ] Run `stack build` - all packages compile
- [ ] Run `stack test` - all tests pass
- [ ] Verify no STM in canopy-core: `grep -r "STM\|MVar\|TVar" packages/canopy-core/src/` (should be empty)
- [ ] Verify clean dependency graph: `stack dot --external | dot -Tpng -o deps.png`

## Phase 2: Builder Redesign (Weeks 3-4)

### Pure Dependency Graph
- [ ] Create `packages/canopy-builder/src/Builder/Graph.hs` (pure graph construction)
- [ ] Create `packages/canopy-builder/src/Builder/Cycles.hs` (pure cycle detection)
- [ ] Create `packages/canopy-builder/src/Builder/Discovery.hs` (pure module discovery)
- [ ] Implement `buildGraph :: ProjectConfig -> [FilePath] -> Either GraphError DependencyGraph`
- [ ] Implement `detectCycles :: DependencyGraph -> Maybe CycleError`
- [ ] Implement `topologicalSort :: DependencyGraph -> Either GraphError [ModuleName.Raw]`

### Pure Package Solver
- [ ] Create `packages/canopy-builder/src/Builder/Solver.hs` (pure solver)
- [ ] Create `packages/canopy-builder/src/Builder/Registry.hs` (pure registry)
- [ ] Create `packages/canopy-builder/src/Builder/Constraints.hs` (constraint types)
- [ ] Implement `solve :: Registry -> Constraints -> Either SolverError Solution`
- [ ] Implement pure backtracking search (no IO, no STM)

### Incremental Compilation
- [ ] Create `packages/canopy-builder/src/Builder/Incremental.hs`
- [ ] Create `packages/canopy-builder/src/Builder/Hash.hs` (content hashing)
- [ ] Create `packages/canopy-builder/src/Builder/State.hs` (state persistence)
- [ ] Implement `computeRebuildPlan :: IncrementalState -> DependencyGraph -> IO RebuildPlan`
- [ ] Implement `saveIncrementalState :: IncrementalState -> IO ()` (to `.canopy-build/state.json`)
- [ ] Implement `loadIncrementalState :: IO IncrementalState`

### Archive Old Code
- [ ] Move `builder/src/Build/Dependencies.hs` → `old/Build/Dependencies.hs`
- [ ] Move `builder/src/Build/Crawl.hs` → `old/Build/Crawl.hs`
- [ ] Move `builder/src/Deps/Solver.hs` → `old/Deps/Solver.hs`
- [ ] Move `builder/src/Deps/Registry.hs` → `old/Deps/Registry.hs`
- [ ] Create `old/README.md` explaining deprecation

### Validation
- [ ] Verify 0 STM in canopy-builder: `grep -r "STM\|MVar\|TVar" packages/canopy-builder/src/` (should be empty)
- [ ] Run `stack test canopy-builder`
- [ ] Test pure solver: verify constraint solving works
- [ ] Benchmark incremental builds: verify 30% improvement

## Phase 3: Driver Integration (Weeks 5-6)

### Driver Orchestration
- [ ] Update `packages/canopy-driver/src/Driver/Main.hs` to use pure Builder
- [ ] Implement `compilePaths :: CompileConfig -> [FilePath] -> IO (Either CompileError Artifacts)`
- [ ] Integrate `Builder.buildGraph` for dependency resolution
- [ ] Integrate `Builder.computeRebuildPlan` for incremental compilation
- [ ] Create `packages/canopy-driver/src/Driver/Config.hs` (project configuration)
- [ ] Create `packages/canopy-driver/src/Driver/Modes.hs` (compilation modes)

### Fix Code Generation Bug
- [ ] Update `packages/canopy-driver/src/Queries/Generate.hs`
- [ ] Implement `buildCompleteGraph :: [Module] -> DependencyInterfaces -> Opt.GlobalGraph`
- [ ] Ensure ALL dependencies included (not just mains)
- [ ] Test with `examples/with-kernel/` - verify elm/core code included
- [ ] Test with `examples/audio-ffi/` - verify elm/html code included

### Simplified Kernel Handling
- [ ] Create `packages/canopy-driver/src/Queries/Kernel.hs`
- [ ] Create `packages/canopy-driver/src/Kernel/Parser.hs` (language-javascript integration)
- [ ] Create `packages/canopy-driver/src/Kernel/CodeGen.hs` (generate from AST)
- [ ] Implement `ParseKernelQuery` with content-hash caching
- [ ] Test with existing kernel code - verify backwards compatibility

### Validation
- [ ] Run `CANOPY_DEBUG=CODEGEN canopy make examples/with-kernel/src/Main.elm`
- [ ] Verify ALL dependencies in output: `grep -o "elm\$" output.js | wc -l` (should be >0)
- [ ] Run golden tests: `make test-golden`
- [ ] Compare old vs new output: `diff old-output.js new-output.js` (should be identical or better)

## Phase 4: Interface Format (Weeks 7-8)

### JSON Interface Implementation
- [ ] Create `packages/canopy-driver/src/Interface/JSON.hs`
- [ ] Implement `InterfaceFile` data type with ToJSON/FromJSON instances
- [ ] Implement `writeInterface :: FilePath -> Interface -> IO ()`
- [ ] Implement `readInterface :: FilePath -> IO (Either InterfaceError Interface)`
- [ ] Create `packages/canopy-driver/src/Interface/Binary.hs` (legacy reader)
- [ ] Create `packages/canopy-driver/src/Interface/Migration.hs` (migration tool)

### Integration
- [ ] Update all interface write calls to use JSON format
- [ ] Update all interface read calls to try JSON first, fallback to binary
- [ ] Generate `.canopy/interfaces/*.json` files
- [ ] Maintain backwards compatibility with `.canopy/interfaces/*.cani`

### Validation
- [ ] Compile project, verify JSON interfaces generated: `ls -la .canopy/interfaces/*.json`
- [ ] Benchmark interface loading: `stack bench canopy-driver -- --pattern "interface loading"`
- [ ] Verify 10x improvement over binary format
- [ ] Test backwards compatibility: `canopy make --use-binary-interfaces examples/hello/src/Main.elm`
- [ ] Human-readable: `cat .canopy/interfaces/Main.json` (should be readable)

## Phase 5: Terminal Integration (Weeks 9-10)

### Update Make Command
- [ ] Update `packages/canopy-terminal/src/Make.hs`
- [ ] Replace `Build.fromPaths` with `Driver.compilePaths`
- [ ] Create driver config from build context
- [ ] Handle errors appropriately
- [ ] Update `packages/canopy-terminal/src/Make/Builder.hs`

### Update Install Command
- [ ] Update `packages/canopy-terminal/src/Install.hs`
- [ ] Replace `Deps.Solver.solve` with `Builder.solve` (pure)
- [ ] Load registry without STM
- [ ] Handle constraint solving results

### Update REPL Command
- [ ] Update `packages/canopy-terminal/src/Repl.hs`
- [ ] Replace `Build.fromRepl` with `Driver.compileSource`
- [ ] Integrate with query engine
- [ ] Maintain REPL interaction semantics

### Validation
- [ ] Test `canopy make examples/hello/src/Main.elm` - should work
- [ ] Test `canopy install elm/html` - should work
- [ ] Test `canopy repl` - should work
- [ ] Test `canopy init test-project` - should work
- [ ] Run CLI compatibility tests: `./test/cli-compat.sh`

## Phase 6: Testing & Validation (Weeks 11-12)

### Test Suite Creation
- [ ] Create `packages/canopy-query/test/Test/Query/Engine.hs`
- [ ] Create `packages/canopy-query/test/Test/Query/Cache.hs`
- [ ] Create `packages/canopy-driver/test/Test/Driver/Main.hs`
- [ ] Create `packages/canopy-driver/test/Test/Queries/Generate.hs`
- [ ] Create `packages/canopy-builder/test/Test/Builder/Graph.hs`
- [ ] Create `packages/canopy-builder/test/Test/Builder/Solver.hs`
- [ ] Create `packages/canopy-builder/test/Test/Builder/Incremental.hs`
- [ ] Create `packages/canopy-terminal/test/Test/Make.hs`

### Golden Tests
- [ ] Create `test/golden/hello-world/` - basic example
- [ ] Create `test/golden/with-kernel/` - kernel code example
- [ ] Create `test/golden/with-ffi/` - FFI example
- [ ] Create `test/golden/large-app/` - complex application
- [ ] Create golden test runner: `test/run-golden.sh`
- [ ] Verify old vs new outputs identical

### Performance Benchmarks
- [ ] Create `bench/Bench/Incremental.hs` (incremental compilation benchmarks)
- [ ] Create `bench/Bench/Parallel.hs` (parallel compilation benchmarks)
- [ ] Create `bench/Bench/Interface.hs` (interface loading benchmarks)
- [ ] Run benchmarks: `stack bench`
- [ ] Compare with baseline: `./bench/compare.sh baseline current`
- [ ] Verify performance targets met:
  - [ ] 30% faster incremental builds
  - [ ] 50% faster cold builds
  - [ ] 10x faster IDE interface loading
  - [ ] Sub-second rebuilds

### Final Validation
- [ ] Run full test suite: `make test`
- [ ] Run golden tests: `make test-golden`
- [ ] Run benchmarks: `make bench`
- [ ] Generate coverage report: `make coverage` (should be >80%)
- [ ] Verify 0 STM usage: `grep -r "STM\|MVar\|TVar" packages/ --include="*.hs" | grep -v "^old/"` (should be empty)
- [ ] Test all examples compile: `for ex in examples/*/src/Main.elm; do canopy make "$ex"; done`
- [ ] Stress test with large projects
- [ ] Memory leak testing: `canopy make +RTS -h -s`

### Documentation
- [ ] Create migration guide for users
- [ ] Create architecture documentation
- [ ] Update README with new structure
- [ ] Document performance improvements
- [ ] Create troubleshooting guide
- [ ] Update contribution guidelines

## Production Release Checklist

### Pre-Release
- [ ] All tests pass (100%)
- [ ] All benchmarks meet targets
- [ ] No STM usage in new code (verified)
- [ ] Coverage >80%
- [ ] All examples compile correctly
- [ ] Backwards compatibility verified

### Release Process
- [ ] Tag release: `git tag v0.20.0`
- [ ] Update CHANGELOG.md
- [ ] Build release artifacts
- [ ] Test release build
- [ ] Publish to package registry

### Post-Release
- [ ] Monitor for issues
- [ ] Performance monitoring
- [ ] User feedback collection
- [ ] Bug fix backlog

## Rollback Plan (If Needed)

### Emergency Rollback
- [ ] Disable new compiler: `export CANOPY_NEW_COMPILER=0`
- [ ] Restore old Build system from `old/`
- [ ] Identify and fix critical issues
- [ ] Re-enable when ready

### Issue Tracking
- [ ] Create issue tracker for migration problems
- [ ] Prioritize critical bugs
- [ ] Document workarounds
- [ ] Plan fixes in next iteration

---

## Progress Tracking

**Overall Progress:** 0/150 tasks completed

**Phase 1 (Foundation):** 0/35 ☐
**Phase 2 (Builder):** 0/20 ☐
**Phase 3 (Driver):** 0/18 ☐
**Phase 4 (Interface):** 0/12 ☐
**Phase 5 (Terminal):** 0/15 ☐
**Phase 6 (Testing):** 0/40 ☐
**Production:** 0/10 ☐

---

*Update this checklist as you complete tasks. Mark items with ✅ when done.*
