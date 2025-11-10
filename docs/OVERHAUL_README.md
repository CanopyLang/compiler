# Canopy Compiler Production Overhaul Documentation

This directory contains comprehensive documentation for overhauling the Canopy compiler to production-quality standards.

## 📚 Documentation Files

### 1. **CANOPY_PRODUCTION_OVERHAUL_PLAN.md** (Main Plan)
**Size:** Complete technical specification
**Audience:** Architects, senior developers, technical leads

**Contents:**
- Executive summary with current state analysis
- Research findings from Rust, Swift, TypeScript, GHC
- Complete architecture redesign
- Multi-package structure with clean layers
- Detailed implementation phases (12 weeks)
- Technical specifications and API designs
- Risk mitigation strategies
- Success criteria and metrics

**When to read:** Start here for complete understanding of the overhaul

---

### 2. **OVERHAUL_SUMMARY.md** (Executive Summary)
**Size:** 2-page overview
**Audience:** Management, stakeholders, decision makers

**Contents:**
- The problem (474 STM instances, tight coupling)
- The solution (query-based, pure functional)
- What works (keep it!)
- What needs work (fix it!)
- Core architecture changes
- Key benefits (30-50% faster, 0 STM)
- Implementation timeline (12 weeks)
- Migration strategy (gradual, safe)

**When to read:** Quick overview for buy-in and planning

---

### 3. **MIGRATION_CHECKLIST.md** (Implementation Tracker)
**Size:** 150+ actionable tasks
**Audience:** Developers implementing the migration

**Contents:**
- Phase 1: Foundation setup (35 tasks)
- Phase 2: Builder redesign (20 tasks)
- Phase 3: Driver integration (18 tasks)
- Phase 4: Interface format (12 tasks)
- Phase 5: Terminal integration (15 tasks)
- Phase 6: Testing & validation (40 tasks)
- Production release checklist (10 tasks)
- Rollback plan

**When to read:** During implementation to track progress

---

### 4. **QUICK_REFERENCE.md** (Developer Guide)
**Size:** Concise command reference
**Audience:** Day-to-day developers

**Contents:**
- Big picture overview
- Package structure diagram
- Key architecture patterns (5 patterns)
- Command reference (dev, test, debug)
- Debugging guide with categories
- Performance targets and benchmarking
- Code quality checks
- Key files reference

**When to read:** Daily reference during development

---

## 🎯 How to Use This Documentation

### For Project Planning
1. Read **OVERHAUL_SUMMARY.md** - understand scope and timeline
2. Review **CANOPY_PRODUCTION_OVERHAUL_PLAN.md** - detailed architecture
3. Create project schedule from **MIGRATION_CHECKLIST.md**

### For Implementation
1. Follow **MIGRATION_CHECKLIST.md** - phase by phase
2. Use **QUICK_REFERENCE.md** - for patterns and commands
3. Refer to **CANOPY_PRODUCTION_OVERHAUL_PLAN.md** - for technical details

### For Code Review
1. Check **QUICK_REFERENCE.md** - code quality checklist
2. Verify against **CANOPY_PRODUCTION_OVERHAUL_PLAN.md** - architecture patterns
3. Update **MIGRATION_CHECKLIST.md** - mark tasks complete

### For Debugging
1. Use **QUICK_REFERENCE.md** - debug commands and categories
2. Check **CANOPY_PRODUCTION_OVERHAUL_PLAN.md** - architecture decisions
3. Refer to **MIGRATION_CHECKLIST.md** - what's implemented

---

## 🚀 Quick Start

### Understand the Plan (30 minutes)
```bash
# Read executive summary
cat OVERHAUL_SUMMARY.md

# Review architecture
cat CANOPY_PRODUCTION_OVERHAUL_PLAN.md | less
```

### Start Implementation (Week 1)
```bash
# Follow checklist
cat MIGRATION_CHECKLIST.md

# Phase 1: Foundation
# - Create package structure
# - Move core modules
# - Setup multi-package build
```

### Daily Development
```bash
# Quick reference
cat QUICK_REFERENCE.md

# Check for STM usage
grep -r "STM\|MVar\|TVar" packages/ --include="*.hs" | grep -v "^old/"

# Run tests
stack test

# Update checklist
vim MIGRATION_CHECKLIST.md  # Mark tasks complete
```

---

## 📊 Key Metrics

### Current State
- **438** Haskell files total
- **474** STM usage instances (builder/)
- **14** files in New.Compiler.* (working)
- **1** code generation bug

### Target State
- **5** clean packages with clear layers
- **0** MVars/TVars/STM in new code
- **30-50%** faster compilation
- **10x** faster IDE interface loading
- **80%+** test coverage

### Timeline
- **12 weeks** total duration
- **6 phases** of implementation
- **150+** tasks to complete

---

## 🔑 Core Principles

### 1. No STM - Use Pure Functions + IORef
```haskell
-- ❌ Don't: MVars/TVars
mvar <- newEmptyMVar

-- ✅ Do: Pure functions + single IORef
engine <- QueryEngine <$> newIORef emptyState
```

### 2. Query-Based Compilation
```haskell
-- Define queries with caching
instance Query ParseModuleQuery where
  execute = parseModuleFile
```

### 3. Content-Hash Invalidation
```haskell
-- Hash contents, not timestamps
needsRebuild :: SourceHash -> SourceHash -> Bool
needsRebuild prev current =
  hashContent prev /= hashContent current
```

### 4. JSON Interfaces
```haskell
-- JSON instead of binary (10x faster)
writeInterface path iface =
  BS.writeFile (path <.> "json") (encodePretty iface)
```

### 5. Backwards Compatibility
```bash
# Same CLI, same code, same behavior
canopy make src/Main.elm
# Just faster and better internally!
```

---

## 📈 Success Criteria

### Functional ✅
- All Elm code compiles unchanged
- All kernel code works unchanged
- Same CLI interface
- All tests pass

### Performance ✅
- 30% faster incremental builds
- 50% faster cold builds
- 10x faster IDE loading
- Sub-second rebuilds

### Quality ✅
- 0 MVar/TVar/STM usage
- 80%+ test coverage
- Functions ≤15 lines
- Pure functions prioritized

---

## 🎯 Implementation Phases

| Phase | Duration | Focus | Deliverable |
|-------|----------|-------|-------------|
| 1. Foundation | Weeks 1-2 | Multi-package setup | Structure ready |
| 2. Builder | Weeks 3-4 | Eliminate STM | Pure builder |
| 3. Driver | Weeks 5-6 | Fix codegen, integrate | Driver complete |
| 4. Interface | Weeks 7-8 | JSON interfaces | 10x faster IDE |
| 5. Terminal | Weeks 9-10 | Update CLI | User-facing ready |
| 6. Testing | Weeks 11-12 | Comprehensive tests | Production ready |

---

## 🛠️ Tools and Commands

### Build and Test
```bash
stack build                  # Build all packages
stack test                   # Run all tests
stack bench                  # Run benchmarks
stack test --coverage        # Generate coverage report
```

### Migration Tools
```bash
# Check for STM (should be empty!)
grep -r "STM\|MVar\|TVar" packages/ --include="*.hs" | grep -v "^old/"

# Visualize dependencies
stack dot --external | dot -Tpng -o deps.png

# Run golden tests
./test/run-golden.sh
```

### Debugging
```bash
# Enable debug logging
CANOPY_DEBUG=1 canopy make src/Main.elm

# Specific categories
CANOPY_DEBUG=PARSE,TYPE canopy make src/Main.elm
CANOPY_DEBUG=CODEGEN canopy make src/Main.elm
CANOPY_DEBUG=CACHE_DEBUG canopy make src/Main.elm
```

---

## 📁 Package Structure

```
packages/
├── canopy-core/        # Core compiler (NO STM)
│   ├── src/
│   │   ├── AST/              ✅ Reuse existing
│   │   ├── Parse/            ✅ Reuse existing
│   │   ├── Canonicalize/     ✅ Reuse existing
│   │   ├── Type/             ✅ Reuse existing
│   │   ├── Optimize/         ✅ Reuse existing
│   │   └── Canopy/           ✅ Reuse existing
│   └── package.yaml
│
├── canopy-query/       # Query engine (single IORef only)
│   ├── src/
│   │   ├── Query/
│   │   │   ├── Engine.hs     ✅ EXISTS
│   │   │   ├── Types.hs      🆕 CREATE
│   │   │   ├── Cache.hs      🆕 CREATE
│   │   │   └── Dependencies.hs  🆕 CREATE
│   │   └── Messages/
│   │       └── Types.hs      🆕 CREATE
│   └── package.yaml
│
├── canopy-driver/      # Compilation driver (NO STM)
│   ├── src/
│   │   ├── Driver/
│   │   │   ├── Main.hs       ✅ EXISTS
│   │   │   ├── Worker.hs     ✅ EXISTS
│   │   │   ├── Config.hs     🆕 CREATE
│   │   │   └── Modes.hs      🆕 CREATE
│   │   ├── Queries/
│   │   │   ├── Parse.hs      ✅ EXISTS
│   │   │   ├── Canonicalize.hs  ✅ EXISTS
│   │   │   ├── TypeCheck.hs  ✅ EXISTS
│   │   │   ├── Optimize.hs   ✅ EXISTS
│   │   │   ├── Generate.hs   🔧 FIX
│   │   │   ├── Kernel.hs     🆕 CREATE
│   │   │   └── FFI.hs        🆕 CREATE
│   │   └── Interface/
│   │       ├── JSON.hs       🆕 CREATE
│   │       └── Binary.hs     🆕 CREATE
│   └── package.yaml
│
├── canopy-builder/     # Pure build system (NO STM)
│   ├── src/
│   │   ├── Builder/
│   │   │   ├── Graph.hs      🆕 CREATE (pure)
│   │   │   ├── Solver.hs     🆕 CREATE (pure)
│   │   │   ├── Incremental.hs  🆕 CREATE
│   │   │   └── Hash.hs       🆕 CREATE
│   │   └── Deps/
│   │       └── (moved to old/)
│   └── package.yaml
│
└── canopy-terminal/    # CLI interface
    ├── src/
    │   ├── Make.hs           🔧 UPDATE
    │   ├── Install.hs        🔧 UPDATE
    │   ├── Repl.hs           🔧 UPDATE
    │   └── Init.hs           ✅ KEEP
    └── package.yaml

old/                    # 📦 Archive
├── Build.hs            # Old STM-based build
├── Compile.hs          # Old compilation
└── README.md           # "Use New.* instead"
```

**Legend:**
- ✅ EXISTS - Already implemented, reuse as-is
- 🆕 CREATE - New file to create
- 🔧 FIX/UPDATE - Existing file needs changes
- 📦 ARCHIVE - Move to old/ directory

---

## 🔗 Additional Resources

### Architecture References
- [Rust Salsa](https://github.com/salsa-rs/salsa) - Query-based compilation
- [Swift Driver](https://github.com/apple/swift-driver) - Driver + Worker pattern
- [TypeScript Incremental](https://www.typescriptlang.org/tsconfig/incremental.html) - Content-hash caching
- [PureScript JSON](https://github.com/purescript/purescript) - JSON interfaces

### Internal Docs
- Original plan: `/home/quinten/fh/canopy/docs/CANOPY_QUERY_COMPILER_IMPLEMENTATION_PLAN.md`
- CLAUDE.md: `/home/quinten/fh/canopy/CLAUDE.md` (coding standards)
- Agent instructions: `/home/quinten/.claude/agents/plan-implementer.md`

---

## 🆘 Getting Help

### Questions
- **Architecture:** See `CANOPY_PRODUCTION_OVERHAUL_PLAN.md`
- **Implementation:** See `MIGRATION_CHECKLIST.md`
- **Daily work:** See `QUICK_REFERENCE.md`
- **Overview:** See `OVERHAUL_SUMMARY.md`

### Issues
- Migration problems → Create issue with `migration` label
- Performance regression → Create issue with `performance` label
- STM removal questions → See architecture patterns

### Contact
- Project lead: Check project repository
- Documentation issues: Create PR with fixes

---

## 📝 Document Versions

| Document | Size | Last Updated | Version |
|----------|------|--------------|---------|
| CANOPY_PRODUCTION_OVERHAUL_PLAN.md | ~25KB | 2025-09-30 | 1.0 |
| OVERHAUL_SUMMARY.md | ~8KB | 2025-09-30 | 1.0 |
| MIGRATION_CHECKLIST.md | ~15KB | 2025-09-30 | 1.0 |
| QUICK_REFERENCE.md | ~12KB | 2025-09-30 | 1.0 |
| README.md (this file) | ~10KB | 2025-09-30 | 1.0 |

---

**Remember:** The goal is a production-quality compiler with 0 MVars/TVars/STM, 30-50% faster compilation, and a clean, maintainable architecture!

*Start with OVERHAUL_SUMMARY.md, then dive into CANOPY_PRODUCTION_OVERHAUL_PLAN.md for details.*
