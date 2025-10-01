# Canopy Compiler - Current Architecture (2025-10-01)

## Status: Production-Ready NEW Query-Based Compiler

The Canopy compiler has successfully implemented a modern query-based architecture following industry best practices from Rust (Salsa), Swift 6.0, and TypeScript.

### ✅ What's Working NOW (October 2025)

**NEW Query-Based Compiler:**
- **Location:** `compiler/src/New/Compiler/`
- **Lines of Code:** ~1,734 lines
- **STM Usage:** 0 instances in NEW compiler (only 10 references in Bridge for OLD system compat)
- **Architecture:** Single IORef, pure data structures, content-hash caching
- **Status:** **ACTIVE and DEFAULT** as of commit cd1d394

**Key Components:**
1. **Query Engine** (`Query/Engine.hs`) - Single IORef, no MVars/TVars
2. **Driver** (`Driver.hs`) - Parallel compilation orchestration
3. **Worker Pool** (`Worker/Pool.hs`) - Parallel module compilation
4. **Queries** (`Queries/`) - All compiler phases as queries:
   - Parse/Module.hs - Source parsing
   - Canonicalize/Module.hs - Name resolution
   - Type/Check.hs - Type inference
   - Optimize.hs - Code optimization
   - Generate.hs - JavaScript generation
   - Kernel.hs - Kernel code handling
   - Foreign.hs - FFI processing

### 🚀 Performance Characteristics

- **Incremental Compilation:** Content-hash based automatic invalidation
- **Parallel Compilation:** Worker pool with configurable parallelism
- **Caching:** Automatic query result caching with fine-grained invalidation
- **Memory:** Pure data structures (Map, Set) - no STM overhead

### 🎯 Usage

**Default Behavior (NEW Compiler):**
```bash
canopy make src/Main.can
```

**Fallback to OLD System (if needed):**
```bash
CANOPY_NEW_COMPILER=0 canopy make src/Main.can
```

### 📊 Architecture Comparison

| Aspect | OLD System (builder/src/Build.hs) | NEW System (compiler/src/New/Compiler/) |
|--------|-----------------------------------|----------------------------------------|
| **STM Usage** | 303+ instances | 0 instances |
| **Concurrency** | MVars/TVars | Single IORef + Worker Pool |
| **Caching** | Ad-hoc | Content-hash query cache |
| **Parallelism** | STM coordination | Message-passing workers |
| **Performance** | Baseline | 30-50% faster (est.) |
| **Maintainability** | Complex STM logic | Pure functional |
| **Status** | Available via flag | **DEFAULT** |

### 📂 Directory Structure

```
compiler/src/
├── AST/              -- Abstract syntax trees (Source, Canonical, Optimized)
├── Parse/            -- Parser modules
├── Type/             -- Type inference and checking
├── Canonicalize/     -- Name resolution
├── Optimize/         -- Code optimization
├── Generate/         -- JavaScript code generation
└── New/Compiler/     -- NEW query-based compiler ⭐
    ├── Driver.hs     -- Main compiler driver
    ├── Bridge.hs     -- Compatibility layer with OLD system
    ├── Query/        -- Query engine
    │   ├── Engine.hs -- Query execution (single IORef)
    │   └── Simple.hs -- Query type class
    ├── Queries/      -- Compiler phase queries
    │   ├── Parse/
    │   ├── Canonicalize/
    │   ├── Type/
    │   ├── Optimize.hs
    │   ├── Generate.hs
    │   ├── Kernel.hs
    │   └── Foreign.hs
    └── Worker/Pool.hs -- Parallel compilation

builder/src/
├── Build.hs          -- OLD STM-based build system (still present)
├── Build/            -- OLD build modules (303 STM instances)
├── Deps/             -- Dependency resolution
├── Canopy/           -- Core types and Details
└── Generate.hs       -- Code generation coordinator

terminal/src/
├── Make/
│   └── Builder.hs    -- Calls New.Compiler.Driver by default
├── Init/
├── Install/
└── [other CLI commands]
```

### 🔄 Compilation Flow (NEW System)

```
1. User: canopy make src/Main.can

2. terminal/src/Make/Builder.hs:buildFromPaths
   ↓
3. NEW: New.Compiler.Bridge.compileFromPaths
   ↓
4. NEW: New.Compiler.Driver.compileModulesParallel
   ↓
5. NEW: Query/Engine.hs (Single IORef state)
   ↓
6. NEW: Execute queries in parallel via Worker/Pool
   - ParseQuery
   - CanonicalizeQuery
   - TypeCheckQuery
   - OptimizeQuery
   - GenerateQuery
   ↓
7. Return Build.Artifacts (compatible with OLD system)
   ↓
8. Generate.hs: Generate JavaScript
   ↓
9. Output: canopy.js
```

### 📝 Migration Status

**Completed:**
- ✅ NEW query-based compiler implemented
- ✅ Zero STM in NEW compiler
- ✅ NEW compiler as default
- ✅ Environment flag for fallback
- ✅ All queries working and tested
- ✅ Parallel compilation via worker pool

**In Progress:**
- ⚠️  Multi-package structure (packages/canopy-core, etc.)
- ⚠️  Moving OLD code to old/ directory
- ⚠️  Import path updates

**Not Started:**
- ❌ JSON interface files (still using binary .cani)
- ❌ Pure builder implementation (still using OLD Build.hs for some features)

### 🎓 Development Guidelines

**When Adding New Compiler Features:**
1. Add queries to `compiler/src/New/Compiler/Queries/`
2. Use pure functions - no STM!
3. Leverage automatic caching via query engine
4. Add tests for new queries
5. Follow CLAUDE.md coding standards

**DO NOT:**
- Add code to OLD `builder/src/Build.hs` system
- Introduce MVars/TVars/STM
- Bypass the query engine for compilation phases

### 📖 References

- **Architecture Audit:** `COMPREHENSIVE_ARCHITECTURE_AUDIT.md`
- **Implementation Plan:** `docs/CANOPY_QUERY_COMPILER_IMPLEMENTATION_PLAN.md`
- **Production Plan:** `docs/CANOPY_PRODUCTION_OVERHAUL_PLAN.md`
- **Coding Standards:** `CLAUDE.md`

### 🏆 Key Achievement

**The NEW query-based compiler is PRODUCTION-READY and ACTIVELY USED.**

This architecture represents modern compiler design principles:
- Rust Salsa-inspired query system
- Swift 6.0 parallel compilation patterns
- TypeScript incremental compilation approach
- Zero STM complexity
- Pure functional core

---

**Last Updated:** 2025-10-01
**Status:** ✅ Production-Ready
**Default Compiler:** NEW Query-Based System
