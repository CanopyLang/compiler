# Canopy Compiler Overhaul - Quick Reference

## 🎯 The Big Picture

**Goal:** Transform Canopy from STM-heavy to pure functional, query-based compiler
**Duration:** 12 weeks
**Key Metric:** 0 MVars/TVars/STM in new code

## 📊 Current State

```
Existing:
- 438 Haskell files total
- 474 STM usage instances in builder/
- 14 files in New.Compiler.* (working great!)
- Code generation bug (missing dependencies)

Problems:
❌ Heavy STM usage (MVars/TVars everywhere)
❌ Tight coupling between components
❌ No modern incremental compilation
❌ Slow binary interface files
```

## 🚀 Target State

```
New Architecture:
✅ 5 clean packages with clear layers
✅ 0 STM usage (pure functions + single IORef)
✅ Query-based compilation with caching
✅ JSON interface files (10x faster)
✅ 30-50% faster compilation
```

## 🏗️ Package Structure

```
packages/
├── canopy-core/        # Core compiler (NO STM)
│   └── AST, Parse, Type, Optimize, etc.
│
├── canopy-query/       # Query engine (single IORef only)
│   └── Engine, Types, Cache, Dependencies
│
├── canopy-driver/      # Compilation driver (NO STM)
│   └── Driver, Queries, Interface, Kernel
│
├── canopy-builder/     # Pure build system (NO STM)
│   └── Graph, Solver, Incremental
│
└── canopy-terminal/    # CLI interface
    └── Make, Install, Repl, Init

Dependency flow: terminal → builder → driver → query → core
```

## 🔑 Key Architecture Patterns

### Pattern 1: No STM! Use Pure + IORef

```haskell
-- ❌ OLD (Don't do this!)
mvar <- newEmptyMVar
tvar <- newTVar state
atomically $ modifyTVar tvar update

-- ✅ NEW (Do this!)
-- Pure data structures
data Graph = Graph { nodes :: Map k v }

-- Single IORef for mutable state
engine <- QueryEngine <$> newIORef emptyState
modifyIORef' (engineState engine) update
```

### Pattern 2: Query-Based Compilation

```haskell
-- Define query
data ParseModuleQuery = ParseModuleQuery FilePath ContentHash

instance Query ParseModuleQuery where
  type Result ParseModuleQuery = Either ParseError Module

  execute query = do
    Logger.debug PARSE ("Parsing: " ++ queryPath query)
    -- Parse with caching
    parseModuleFile (queryPath query)

-- Use in driver
engine <- Engine.initEngine
result <- Engine.runQuery engine (ParseModuleQuery path hash)
```

### Pattern 3: Pure Dependency Graph

```haskell
-- ❌ OLD (STM-based crawling)
crawlDependencies :: Env -> IO (Map ModuleName Status)

-- ✅ NEW (Pure graph construction)
buildGraph :: ProjectConfig -> [FilePath] -> Either GraphError DependencyGraph
buildGraph config paths =
  let nodes = discoverModules config paths
      edges = extractDependencies nodes
  in validateGraph (DependencyGraph nodes edges)
```

### Pattern 4: Content-Hash Caching

```haskell
-- Hash file contents, not timestamps
data SourceHash = SourceHash
  { hashContent :: !ByteString        -- SHA256 of file
  , hashDependencies :: ![ByteString] -- Hashes of deps
  }

-- Incremental build decision
needsRebuild :: SourceHash -> SourceHash -> Bool
needsRebuild prev current =
  hashContent prev /= hashContent current
  || hashDependencies prev /= hashDependencies current
```

### Pattern 5: JSON Interfaces

```haskell
-- Write interface as JSON
data InterfaceFile = InterfaceFile
  { ifPackage :: !PackageName
  , ifModule :: !ModuleName
  , ifContentHash :: !ContentHash
  , ifExports :: !ExportMap
  } deriving (Show, Eq, Generic)

instance ToJSON InterfaceFile
instance FromJSON InterfaceFile

writeInterface path iface =
  BS.writeFile (path <.> "json") (encodePretty (toInterfaceFile iface))
```

## 📋 Quick Command Reference

### Development Commands

```bash
# Build all packages
stack build

# Build specific package
stack build canopy-core
stack build canopy-query
stack build canopy-driver
stack build canopy-builder

# Run tests
stack test                           # All tests
stack test canopy-builder            # Specific package
stack test --ta="--pattern Graph"   # Specific test

# Benchmarks
stack bench
stack bench canopy-driver -- --pattern "interface loading"

# Check for STM usage (should be empty!)
grep -r "STM\|MVar\|TVar" packages/ --include="*.hs" | grep -v "^old/"

# Coverage
stack test --coverage
stack hpc report --all canopy
```

### Testing New Compiler

```bash
# Use new compiler (during development)
CANOPY_NEW_COMPILER=1 canopy make src/Main.elm

# Compare with old compiler
diff <(canopy make src/Main.elm) <(CANOPY_NEW_COMPILER=1 canopy make src/Main.elm)

# Debug logging
CANOPY_DEBUG=1 CANOPY_NEW_COMPILER=1 canopy make src/Main.elm
CANOPY_DEBUG=CODEGEN canopy make src/Main.elm
CANOPY_DEBUG=CACHE_DEBUG canopy make src/Main.elm

# Golden tests
./test/run-golden.sh
```

### Migration Commands

```bash
# Move module to new package
mv compiler/src/AST/ packages/canopy-core/src/AST/

# Update imports in moved files
find packages/canopy-core/src -name "*.hs" -exec sed -i 's/import qualified AST/import qualified Canopy.Core.AST/g' {} \;

# Archive old implementation
mv builder/src/Build/Dependencies.hs old/Build/Dependencies.hs

# Check dependency graph
stack dot --external | dot -Tpng -o deps.png
open deps.png
```

## 🐛 Debugging Guide

### Debug Categories

```haskell
-- Available debug categories (from Logger.hs)
data DebugCategory
  = PARSE              -- Parsing operations
  | TYPE               -- Type checking
  | CODEGEN            -- Code generation
  | BUILD              -- Build system
  | COMPILE_DEBUG      -- General compilation
  | DEPS_SOLVER        -- Dependency resolution
  | CACHE_DEBUG        -- Cache operations
  | QUERY_DEBUG        -- Query execution
  | WORKER_DEBUG       -- Worker pool
  | KERNEL_DEBUG       -- Kernel code handling
  | FFI_DEBUG          -- FFI processing
```

### Debug Commands

```bash
# Enable all debug
CANOPY_DEBUG=1 canopy make src/Main.elm

# Specific category
CANOPY_DEBUG=PARSE canopy make src/Main.elm
CANOPY_DEBUG=TYPE,CODEGEN canopy make src/Main.elm

# Query execution trace
CANOPY_DEBUG=QUERY_DEBUG,CACHE_DEBUG canopy make src/Main.elm

# Worker pool activity
CANOPY_DEBUG=WORKER_DEBUG canopy make src/Main.elm
```

### Common Issues

**Issue:** STM deadlock
```bash
# Check for STM usage
grep -r "atomically\|MVar\|TVar" packages/canopy-builder/src/
# Should be empty! If not, refactor to pure functions
```

**Issue:** Missing dependencies in output
```bash
# Debug code generation
CANOPY_DEBUG=CODEGEN canopy make src/Main.elm
# Check generated code includes all deps
grep -o "elm\$" output.js | wc -l  # Should be > 0
```

**Issue:** Slow incremental builds
```bash
# Check incremental state
cat .canopy-build/state.json
# Verify content hashes, not timestamps
```

## 📈 Performance Targets

### Compilation Speed

```
✅ Cold build:         50% faster (parallel compilation)
✅ Incremental build:  30% faster (content-hash caching)
✅ Single file change: < 1 second (selective recompilation)
✅ Interface loading:  10x faster (JSON vs binary)
```

### Benchmarking

```bash
# Measure cold build
time canopy make src/Main.elm

# Measure incremental (no changes)
touch src/Helper.elm
time canopy make src/Main.elm

# Measure incremental (single change)
echo "-- comment" >> src/Helper.elm
time canopy make src/Main.elm

# Compare old vs new
time canopy make src/Main.elm
time CANOPY_NEW_COMPILER=1 canopy make src/Main.elm
```

## 🔍 Code Quality Checks

### Pre-Commit Checklist

```bash
# 1. No STM usage
grep -r "STM\|MVar\|TVar" packages/ --include="*.hs" | grep -v "^old/"
# Should be empty!

# 2. All tests pass
stack test

# 3. No lint warnings
stack build --ghc-options="-Wall -Werror"

# 4. Functions ≤ 15 lines
# (Use CLAUDE.md linter)

# 5. Coverage ≥ 80%
stack test --coverage
stack hpc report --all canopy
```

### Code Review Checklist

- [ ] No MVar/TVar/STM usage (unless in old/)
- [ ] Pure functions where possible
- [ ] Content-hash for invalidation (not timestamps)
- [ ] Comprehensive debug logging
- [ ] Functions ≤ 15 lines
- [ ] Parameters ≤ 4
- [ ] Tests added/updated
- [ ] Documentation complete

## 🚦 Migration Status

### What Works Now
✅ New.Compiler.* query-based compiler (14 files)
✅ Parser modules (mature)
✅ AST definitions (stable)
✅ Package system (compatible)

### What's In Progress
🔧 Multi-package structure
🔧 Pure Builder (removing STM)
🔧 JSON interfaces
🔧 Code generation fix

### What's Next
⏭️ Driver integration
⏭️ Terminal updates
⏭️ Comprehensive testing
⏭️ Production release

## 📚 Key Files Reference

### Core Files (canopy-core)
- `AST/Source.hs` - Source AST
- `AST/Canonical.hs` - Canonical AST
- `AST/Optimized.hs` - Optimized AST
- `Parse/Module.hs` - Module parser
- `Type/Solve.hs` - Type solver

### Query Files (canopy-query)
- `Query/Engine.hs` - Query engine (single IORef)
- `Query/Types.hs` - Query type class
- `Query/Cache.hs` - Content-hash caching
- `Messages/Types.hs` - Message passing

### Driver Files (canopy-driver)
- `Driver/Main.hs` - Main orchestration
- `Driver/Worker.hs` - Worker pool
- `Queries/Parse.hs` - Parse query
- `Queries/Generate.hs` - Code generation (NEEDS FIX)
- `Interface/JSON.hs` - JSON interfaces

### Builder Files (canopy-builder)
- `Builder/Graph.hs` - Pure dependency graph
- `Builder/Solver.hs` - Pure constraint solver
- `Builder/Incremental.hs` - Incremental strategy

### Terminal Files (canopy-terminal)
- `Make.hs` - Make command
- `Install.hs` - Install command
- `Repl.hs` - REPL command

## 🎓 Learning Resources

### Architecture Patterns
- Rust Salsa: https://github.com/salsa-rs/salsa
- Swift Driver: https://github.com/apple/swift-driver
- TypeScript Incremental: https://www.typescriptlang.org/tsconfig/incremental.html
- PureScript JSON: https://github.com/purescript/purescript

### Best Practices
- Query-based compilation
- Content-hash caching
- Pure dependency graphs
- Message-passing concurrency
- JSON interface files

## 🆘 Getting Help

### Issues
- Migration problems → Create issue with `migration` label
- Performance regression → Create issue with `performance` label
- STM removal questions → See `docs/NO_STM_PATTERNS.md`

### Documentation
- Full plan: `CANOPY_PRODUCTION_OVERHAUL_PLAN.md`
- Summary: `OVERHAUL_SUMMARY.md`
- Checklist: `MIGRATION_CHECKLIST.md`
- This reference: `QUICK_REFERENCE.md`

---

**Remember:** The goal is 0 MVars/TVars/STM. Pure functions everywhere!
