# Canopy Compiler Production Overhaul - Executive Summary

## The Problem

The Canopy compiler currently has:
- **474 instances of STM usage** (MVars/TVars) in the builder causing complexity
- **Tight coupling** between Builder and Compiler components
- **Code generation bug** where not all dependencies are included
- **No modern incremental compilation** strategy
- **Binary interface files** that are slow to parse for IDEs

## The Solution

A complete architectural overhaul based on modern compiler best practices from:
- **Rust** (Salsa query-based architecture)
- **Swift 6.0** (Driver + Worker pattern, fine-grained dependencies)
- **TypeScript 5.x** (Content-hash caching, .tsbuildinfo approach)
- **PureScript** (JSON interfaces, 10x faster IDE)

## What Works (Keep It!)

✅ **New query-based compiler** (`New.Compiler.*`) - 14 files, working great
✅ **Parser modules** - mature, well-tested
✅ **AST definitions** - stable, proven correct
✅ **Package system** - backwards compatible
✅ **Terminal interface** - user-facing API stable

## What Needs Work (Fix It!)

❌ **Builder** - 474 STM usage instances, needs complete rewrite
❌ **Code generation** - global lookup bug, missing dependencies
❌ **Interface format** - binary is slow, switch to JSON
❌ **Orchestration** - STM-based coordination, switch to message passing

## Core Architecture Changes

### 1. Multi-Package Structure (NEW)

```
canopy/
├── packages/
│   ├── canopy-core/        # Core compiler (NO STM)
│   ├── canopy-query/       # Query engine (single IORef only)
│   ├── canopy-driver/      # Compilation driver (NO STM)
│   ├── canopy-builder/     # Pure build system (NO STM)
│   └── canopy-terminal/    # CLI interface
└── old/                    # Archive old implementation
```

### 2. No More STM! (Pure Functions + Message Passing)

**OLD (Build.hs - STM hell):**
```haskell
mvar <- newEmptyMVar        -- ❌
tvar <- newTVar initialState -- ❌
-- Complex STM coordination...
```

**NEW (Pure + IORef):**
```haskell
-- Pure dependency graph
graph :: DependencyGraph
graph = buildGraph config paths

-- Single IORef for engine state
engine <- QueryEngine <$> newIORef emptyState

-- Message passing for workers
pool <- Pool.createPool config compileTask
```

### 3. Content-Hash Based Incremental Compilation

**Like TypeScript's .tsbuildinfo:**
- Hash file contents (not timestamps)
- Invalidate only when content changes
- Persist state to `.canopy-build/state.json`
- 30% faster incremental builds

### 4. JSON Interface Files

**Like PureScript's evolution:**
- Switch from binary `.cani` to JSON
- **10x faster IDE parsing** (proven by PureScript)
- Human-readable for debugging
- Fine-grained dependency tracking

### 5. Driver + Worker Pool Architecture

**Like Swift 6.0:**
- **Driver:** Orchestrates compilation, manages dependencies
- **Workers:** Compile modules in isolation
- **Message passing:** No shared state
- **Parallelization:** Linear scalability to 8 cores

## Key Benefits

### Performance
- ✅ **30% faster** incremental builds
- ✅ **50% faster** cold builds (parallel compilation)
- ✅ **10x faster** IDE interface loading
- ✅ **Sub-second** rebuilds for single file changes

### Code Quality
- ✅ **0 MVars/TVars/STM** in new code
- ✅ **Pure functions** where possible
- ✅ **80%+ test coverage**
- ✅ **Clear data flow** and debugging

### Maintainability
- ✅ **Clean package structure** with clear layers
- ✅ **Single responsibility** per module
- ✅ **Comprehensive documentation**
- ✅ **Modern architecture** following 2024 best practices

### Backwards Compatibility
- ✅ **Same CLI** (`canopy make`, `canopy install`, etc.)
- ✅ **Same Elm source code** compiles unchanged
- ✅ **Same kernel code** works unchanged
- ✅ **Same FFI system** works unchanged
- ✅ **Same package ecosystem** compatibility

## Implementation Plan

### Phase 1: Foundation (Weeks 1-2)
- Create multi-package structure
- Move core modules to canopy-core
- Setup query system in canopy-query
- **Deliverable:** Structure compiles

### Phase 2: Builder Redesign (Weeks 3-4)
- Eliminate ALL 474 STM usage instances
- Pure dependency graph
- Pure constraint solver
- Content-hash incremental builds
- **Deliverable:** Builder has 0 STM

### Phase 3: Driver Integration (Weeks 5-6)
- Fix Generate.JavaScript global lookup bug
- Integrate pure Builder with Driver
- Simplify kernel code handling
- **Deliverable:** Driver generates correct code

### Phase 4: Interface Format (Weeks 7-8)
- Implement JSON interface format
- Backwards compatible with binary
- Migration tooling
- **Deliverable:** 10x faster IDE

### Phase 5: Terminal Integration (Weeks 9-10)
- Update Make command
- Update Install command
- Update REPL command
- **Deliverable:** All CLI commands use new system

### Phase 6: Testing & Validation (Weeks 11-12)
- Comprehensive test suite
- Golden tests (output comparison)
- Performance benchmarks
- **Deliverable:** Production ready

## Migration Strategy

### Gradual Migration (Safe!)

**Week 1-2:** Dual mode operation
```bash
# Default: old compiler
canopy make src/Main.elm

# New compiler via flag
CANOPY_NEW_COMPILER=1 canopy make src/Main.elm
```

**Week 3-10:** Testing period
- CI runs both compilers
- Verify outputs identical
- Performance benchmarks

**Week 11:** Switch default
- New compiler becomes default
- Old available via `CANOPY_OLD_COMPILER=1`

**Week 12:** Production release
- Remove old compiler
- New compiler is the only compiler

## Risk Mitigation

### Risk 1: Breaking Changes
**Mitigation:** Extensive golden tests, gradual migration, rollback plan

### Risk 2: Performance Regression
**Mitigation:** Continuous benchmarking, performance targets, parallel compilation

### Risk 3: Incomplete Migration
**Mitigation:** Incremental phases, feature parity checklist, dual-mode operation

### Risk 4: STM Removal Issues
**Mitigation:** Message passing, pure data structures, extensive concurrency tests

## Success Criteria

### Functional
- ✅ All Elm code compiles unchanged
- ✅ All kernel code works unchanged
- ✅ Same CLI interface
- ✅ Same error messages
- ✅ All tests pass

### Performance
- ✅ 30% faster incremental builds
- ✅ 50% faster cold builds
- ✅ 10x faster IDE loading
- ✅ Sub-second rebuilds

### Quality
- ✅ 0 MVar/TVar/STM usage
- ✅ 80%+ test coverage
- ✅ Functions ≤15 lines
- ✅ Pure functions prioritized

## Timeline

**Total Duration:** 12 weeks (3 months)

| Week | Phase | Focus |
|------|-------|-------|
| 1-2  | Foundation | Multi-package structure |
| 3-4  | Builder | Eliminate STM |
| 5-6  | Driver | Fix codegen, integrate |
| 7-8  | Interface | JSON format |
| 9-10 | Terminal | Update CLI |
| 11-12 | Validation | Production ready |

## The Bottom Line

This plan transforms Canopy from an STM-heavy, tightly-coupled compiler into a modern, query-based, pure functional architecture that:

1. **Is 30-50% faster** (incremental + parallel)
2. **Has 0 MVars/TVars** (pure functions everywhere)
3. **Is 10x faster for IDEs** (JSON interfaces)
4. **Is fully backwards compatible** (same CLI, same code)
5. **Follows 2024 best practices** (Rust, Swift, TypeScript patterns)

The result: A production-quality compiler that's fast, debuggable, maintainable, and ready for Canopy's future.

---

**Next Steps:**
1. Review and approve plan
2. Begin Phase 1: Foundation
3. Systematic implementation over 12 weeks
4. Production release

**Full Plan:** See `CANOPY_PRODUCTION_OVERHAUL_PLAN.md` for complete technical details.
