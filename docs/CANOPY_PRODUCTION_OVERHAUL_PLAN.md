# Canopy Compiler Production Overhaul Plan
## Complete Architecture Redesign to Modern Standards

**Version:** 1.0
**Date:** 2025-09-30
**Status:** Comprehensive Implementation Plan

---

## Executive Summary

This plan provides a complete roadmap for overhauling the Canopy compiler to production-quality standards, leveraging the successful query-based compiler implementation (New.Compiler.*) while eliminating all STM/MVar/TVar usage and adopting modern compiler architecture best practices from Rust, Swift, TypeScript, and GHC.

### Current State Analysis

**Working Well (438 total Haskell files):**
- ✅ New query-based compiler (`New.Compiler.*`) - 14 files, working great
- ✅ Parser modules (`Parse/`) - mature, well-tested
- ✅ AST definitions (`AST/`) - stable, proven correct
- ✅ Package system (`Canopy/`) - backwards compatible
- ✅ Terminal interface (`terminal/`) - user-facing API stable

**Critical Problems (474 STM usage instances in builder/):**
- ❌ Builder uses MVars/TVars extensively (474 instances)
- ❌ Heavy STM usage for coordination (Build.Orchestration, Build.Types)
- ❌ Code generation bug (Generate.JavaScript global lookup issue)
- ❌ Tight coupling between Builder and Compiler
- ❌ No modern incremental compilation strategy

### Goals

1. **Speed**: Query-based incremental compilation with fine-grained caching
2. **Debuggability**: Pure functions, comprehensive logging, clear data flow
3. **Backwards Compatibility**: Same CLI, same Elm code, same kernel requirements
4. **Modern Architecture**: Following 2024 compiler design best practices
5. **Production Quality**: Clean, maintainable, well-tested codebase

---

## Architecture Philosophy

### Core Principle: External Compatibility, Internal Revolution

**MAINTAIN (External):**
- CLI interface (`canopy make`, `canopy install`, etc.)
- Source file formats (`.elm`, `.can`, `elm.json`, `canopy.json`)
- Kernel JavaScript files (`src/Elm/Kernel/*.js`, `src/Canopy/Kernel/*.js`)
- FFI system (`foreign import javascript`)
- Package ecosystem compatibility
- Generated JavaScript runtime behavior

**REDESIGN (Internal):**
- Build orchestration (eliminate ALL MVars/TVars/STM)
- Interface file format (binary → JSON like PureScript/TypeScript)
- Kernel code integration (simplified query-based)
- Compilation pipeline (query-based with caching)
- Dependency resolution (pure functional)
- Code generation (fix global lookup, ensure completeness)

---

## Research Findings: Modern Compiler Best Practices

### 1. Query-Based Architecture (Rust, GHC, Swift)

**Rust Salsa Approach:**
- Automatic incremental compilation with precise invalidation
- Natural memoization of expensive computations
- Easy parallelization without complex state management
- Simple mental model with clear dependency graphs
- Excellent debugging - trace query execution

**Key Insight:** No major modern compiler uses STM. All use either:
- Query-based systems (Rust Salsa)
- Driver + Worker pools (Swift 6.0)
- Project references with caching (TypeScript)
- Demand-driven with explicit tracking (GHC)

### 2. Fine-Grained Dependency Tracking (Swift 6.0, TypeScript 5.x)

**Swift 2024 Evolution:**
- Track changes at function/type level, not module level
- Selective recompilation based on actual changes
- 30% performance improvement for incremental builds
- Precise invalidation prevents unnecessary recompilation

**TypeScript .tsbuildinfo:**
- Content-addressed caching with .tsbuildinfo files
- Incremental flag saves project graph information
- Detects least costly way to type-check on next invocation

### 3. Driver + Worker Architecture (Swift, TypeScript)

**Successful Pattern:**
- **Driver:** Orchestrates work, manages dependencies, schedules compilation
- **Workers:** Perform actual compilation in isolation
- **Clean separation** of concerns
- **Natural parallelization** without shared state

### 4. Content-Hash Based Invalidation

**TypeScript/PureScript Approach:**
- Hash file contents, not timestamps
- Invalidate only when actual content changes
- Whitespace/comment changes don't trigger recompilation
- Deterministic builds across machines

### 5. JSON Interface Files (PureScript Success Story)

**PureScript Evolution:**
- Switched from binary externs to JSON
- **10x faster IDE parsing**
- Human-readable for debugging
- External tools can read without compiler
- Fine-grained dependency tracking

---

## Proposed Architecture

### High-Level System Design

```
┌─────────────────────────────────────────────────────────────┐
│                      Terminal Interface                      │
│  (canopy make, canopy install, canopy repl)                 │
│                 ✅ KEEP - User-facing API                    │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   🆕 Canopy Driver                           │
│  • Orchestrates compilation workflow                         │
│  • Manages query engine and worker pool                      │
│  • NO MVars/TVars - pure orchestration                       │
│  • Message-passing for coordination                          │
└──────────────────────────┬──────────────────────────────────┘
                           │
           ┌───────────────┴───────────────┐
           ▼                               ▼
┌─────────────────────┐         ┌──────────────────────────┐
│   Query Engine      │         │    Worker Pool           │
│  • Content-hash     │         │  • Parallel compilation  │
│    caching          │         │  • Isolated workers      │
│  • Dependency       │         │  • Message-based tasks   │
│    tracking         │         │  • NO shared state       │
│  • Single IORef     │         │  • Chan for messages     │
│  • NO STM           │         │  • Pure functions        │
└─────────────────────┘         └──────────────────────────┘
           │                               │
           ▼                               ▼
┌─────────────────────────────────────────────────────────────┐
│              Compilation Queries (New.Compiler.*)           │
│  • ParseModuleQuery      ✅ WORKS                            │
│  • CanonicalizeQuery     ✅ WORKS                            │
│  • TypeCheckQuery        ✅ WORKS                            │
│  • OptimizeQuery         ✅ WORKS                            │
│  • GenerateQuery         🔧 FIX global lookup bug           │
│  • KernelQuery           🆕 Simplified kernel handling       │
│  • FFIQuery              🆕 Enhanced FFI support             │
└─────────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────┐
│                  Core Components (Reuse)                    │
│  • AST (Source, Canonical, Optimized)  ✅ REUSE             │
│  • Package, Version, ModuleName        ✅ REUSE             │
│  • Parser modules                       ✅ REUSE             │
│  • Type system                          ✅ REUSE             │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow: Pure Functional Pipeline

```haskell
-- OLD (Build.hs - STM-heavy):
Build.fromPaths style root details paths = do
  env <- makeEnv key root details
  statuses <- Build.Dependencies.crawlDependencies env
  dtvar <- forkIO loadDependencies  -- MVar/TVar hell
  results <- forkWithKey compileModule statusMap  -- More MVars
  -- Complex STM coordination...

-- NEW (Canopy.Driver - Pure):
Driver.compilePaths config paths = do
  -- 1. Pure project analysis
  let project = analyzeProject config paths

  -- 2. Query-based compilation with caching
  engine <- Engine.initEngine
  results <- compileWithQueries engine project

  -- 3. Parallel execution via worker pool (message passing)
  pool <- Pool.createPool poolConfig compileTask
  artifacts <- Pool.compileModules pool tasks

  -- 4. Code generation with complete dependency graph
  code <- Generate.fromArtifacts artifacts

  return code
```

---

## Package Structure Redesign

### Current Structure (Single Package - Problematic)

```
canopy/
├── compiler/src/    -- 200+ files, tightly coupled
├── builder/src/     -- 30+ files, STM-heavy
├── terminal/src/    -- 20+ files, CLI interface
└── package.yaml     -- Single package
```

**Problems:**
- Tight coupling between layers
- Can't compile terminal without builder STM code
- Hard to test components in isolation
- Unclear dependency boundaries

### New Structure (Multi-Package - Clean Layers)

```
canopy/
├── packages/
│   ├── canopy-core/              -- Core compiler functionality
│   │   ├── src/
│   │   │   ├── AST/              ✅ Reuse existing
│   │   │   ├── Parse/            ✅ Reuse existing
│   │   │   ├── Canonicalize/     ✅ Reuse existing
│   │   │   ├── Type/             ✅ Reuse existing
│   │   │   ├── Optimize/         ✅ Reuse existing
│   │   │   ├── Canopy/           ✅ Reuse (Package, Version, etc.)
│   │   │   └── Data/             ✅ Reuse (Name, Utf8, etc.)
│   │   └── package.yaml          -- No STM dependency!
│   │
│   ├── canopy-query/             -- 🆕 Query engine (NEW)
│   │   ├── src/
│   │   │   ├── Query/
│   │   │   │   ├── Engine.hs     ✅ EXISTS (single IORef)
│   │   │   │   ├── Types.hs      🆕 Query type class
│   │   │   │   ├── Cache.hs      🆕 Content-hash caching
│   │   │   │   └── Dependencies.hs  🆕 Dependency tracking
│   │   │   └── Messages/
│   │   │       └── Types.hs      🆕 Message passing
│   │   └── package.yaml          -- Depends: canopy-core
│   │
│   ├── canopy-driver/            -- 🆕 Compilation driver (NEW)
│   │   ├── src/
│   │   │   ├── Driver/
│   │   │   │   ├── Main.hs       ✅ EXISTS (orchestration)
│   │   │   │   ├── Config.hs     🆕 Project configuration
│   │   │   │   ├── Worker.hs     ✅ EXISTS (worker pool)
│   │   │   │   └── Modes.hs      🆕 Compilation modes
│   │   │   ├── Queries/
│   │   │   │   ├── Parse.hs      ✅ EXISTS
│   │   │   │   ├── Canonicalize.hs  ✅ EXISTS
│   │   │   │   ├── TypeCheck.hs  ✅ EXISTS
│   │   │   │   ├── Optimize.hs   ✅ EXISTS
│   │   │   │   ├── Generate.hs   🔧 FIX (global lookup bug)
│   │   │   │   ├── Kernel.hs     🆕 Simplified kernel
│   │   │   │   └── FFI.hs        🆕 Enhanced FFI
│   │   │   └── Interface/
│   │   │       ├── JSON.hs       🆕 JSON interface format
│   │   │       └── Binary.hs     ✅ Legacy reader
│   │   └── package.yaml          -- Depends: canopy-query
│   │
│   ├── canopy-builder/           -- 🆕 Pure build system (REWRITE)
│   │   ├── src/
│   │   │   ├── Builder/
│   │   │   │   ├── Graph.hs      🆕 Pure dependency graph
│   │   │   │   ├── Incremental.hs  🆕 Incremental strategy
│   │   │   │   ├── Packages.hs   🔧 Pure package resolution
│   │   │   │   └── Paths.hs      ✅ Reuse (path utilities)
│   │   │   └── Deps/
│   │   │       ├── Solver.hs     🔧 Pure solver (no STM)
│   │   │       └── Registry.hs   🔧 Pure registry (no STM)
│   │   └── package.yaml          -- Depends: canopy-driver
│   │
│   └── canopy-terminal/          -- ✅ CLI interface (MINIMAL CHANGES)
│       ├── src/
│       │   ├── Make.hs           🔧 Use new Driver
│       │   ├── Install.hs        🔧 Use new Builder
│       │   ├── Repl.hs           🔧 Use new Driver
│       │   └── Init.hs           ✅ Keep as-is
│       └── package.yaml          -- Depends: canopy-builder
│
├── old/                          -- 📦 Archive old implementation
│   ├── Build.hs                  -- Old STM-based build
│   ├── Compile.hs                -- Old compilation
│   └── README.md                 -- "Use New.* instead"
│
└── stack.yaml                    -- Multi-package config
```

### Dependency Graph (Clean Layers)

```
canopy-terminal
    ↓
canopy-builder
    ↓
canopy-driver
    ↓
canopy-query
    ↓
canopy-core
```

**Benefits:**
- ✅ Clear separation of concerns
- ✅ No circular dependencies
- ✅ Test each layer independently
- ✅ canopy-core has NO STM dependency
- ✅ canopy-query uses single IORef only
- ✅ Incremental migration possible

---

## Module Migration Plan

### Phase 1: Foundation (Weeks 1-2)

#### 1.1 Setup Multi-Package Structure

**Action:** Create package structure

```bash
# Create new package directories
mkdir -p packages/{canopy-core,canopy-query,canopy-driver,canopy-builder,canopy-terminal}/src

# Create package.yaml for each package
# Move files to appropriate packages
```

**Files to Create:**
- `packages/canopy-core/package.yaml`
- `packages/canopy-query/package.yaml`
- `packages/canopy-driver/package.yaml`
- `packages/canopy-builder/package.yaml`
- `packages/canopy-terminal/package.yaml`
- `stack.yaml` (multi-package config)

#### 1.2 Move Core Compiler to canopy-core

**Action:** Move stable, proven modules

**KEEP AS-IS (Move to canopy-core/src/):**
```
compiler/src/AST/                  → packages/canopy-core/src/AST/
compiler/src/Parse/                → packages/canopy-core/src/Parse/
compiler/src/Canonicalize/         → packages/canopy-core/src/Canonicalize/
compiler/src/Type/                 → packages/canopy-core/src/Type/
compiler/src/Optimize/             → packages/canopy-core/src/Optimize/
compiler/src/Canopy/               → packages/canopy-core/src/Canopy/
compiler/src/Data/                 → packages/canopy-core/src/Data/
compiler/src/Reporting/            → packages/canopy-core/src/Reporting/
compiler/src/Json/                 → packages/canopy-core/src/Json/
```

**Total:** ~200 files moved, 0 files changed

#### 1.3 Extract Query System to canopy-query

**Action:** Move existing query implementation

**MOVE (from compiler/src/New/Compiler/):**
```
New/Compiler/Query/Engine.hs       → packages/canopy-query/src/Query/Engine.hs
New/Compiler/Query/Simple.hs       → packages/canopy-query/src/Query/Simple.hs
New/Compiler/Debug/Logger.hs       → packages/canopy-query/src/Query/Logger.hs
```

**CREATE NEW:**
```
packages/canopy-query/src/Query/Types.hs       -- Query type class
packages/canopy-query/src/Query/Cache.hs       -- Content-hash caching
packages/canopy-query/src/Query/Dependencies.hs  -- Dependency tracking
packages/canopy-query/src/Messages/Types.hs    -- Message passing
```

#### 1.4 Setup Driver Package

**Action:** Create driver infrastructure

**MOVE (from compiler/src/New/Compiler/):**
```
New/Compiler/Driver.hs             → packages/canopy-driver/src/Driver/Main.hs
New/Compiler/Bridge.hs             → packages/canopy-driver/src/Driver/Bridge.hs
New/Compiler/Worker/Pool.hs       → packages/canopy-driver/src/Driver/Worker.hs
```

**MOVE (Compilation Queries):**
```
New/Compiler/Queries/Parse/Module.hs          → packages/canopy-driver/src/Queries/Parse.hs
New/Compiler/Queries/Canonicalize/Module.hs   → packages/canopy-driver/src/Queries/Canonicalize.hs
New/Compiler/Queries/Type/Check.hs            → packages/canopy-driver/src/Queries/TypeCheck.hs
New/Compiler/Queries/Optimize.hs              → packages/canopy-driver/src/Queries/Optimize.hs
New/Compiler/Queries/Generate.hs              → packages/canopy-driver/src/Queries/Generate.hs (FIX)
```

### Phase 2: Builder Redesign (Weeks 3-4)

#### 2.1 Create Pure Dependency Graph

**Action:** Replace STM-based crawling with pure graph

**OLD (builder/src/Build/Dependencies.hs - 474 STM uses):**
```haskell
crawlDependencies :: Env -> IO (Map ModuleName.Raw Status)
crawlDependencies env = do
  mvar <- newEmptyMVar  -- ❌ MVar
  -- Complex STM coordination...
```

**NEW (packages/canopy-builder/src/Builder/Graph.hs - PURE):**
```haskell
-- | Pure dependency graph construction
data DependencyGraph = DependencyGraph
  { graphNodes :: !(Map ModuleName.Raw Node)
  , graphEdges :: !(Map ModuleName.Raw [ModuleName.Raw])
  , graphRoots :: ![ModuleName.Raw]
  } deriving (Show, Eq)

-- | Build dependency graph from project
buildGraph :: ProjectConfig -> [FilePath] -> Either GraphError DependencyGraph
buildGraph config paths =
  let nodes = discoverModules config paths
      edges = extractDependencies nodes
      roots = findRoots paths nodes
  in validateGraph (DependencyGraph nodes edges roots)

-- | Pure cycle detection
detectCycles :: DependencyGraph -> Maybe CycleError
detectCycles graph = runTarjan (graphEdges graph)

-- | Pure topological sort for compilation order
topologicalSort :: DependencyGraph -> Either GraphError [ModuleName.Raw]
topologicalSort graph =
  case detectCycles graph of
    Just cycle -> Left (CycleError cycle)
    Nothing -> Right (kahn (graphEdges graph))
```

**Files to Create:**
- `packages/canopy-builder/src/Builder/Graph.hs` (pure graph)
- `packages/canopy-builder/src/Builder/Cycles.hs` (pure cycle detection)
- `packages/canopy-builder/src/Builder/Discovery.hs` (pure module discovery)

**Files to MOVE TO old/:**
- `builder/src/Build/Dependencies.hs` (STM-based)
- `builder/src/Build/Crawl.hs` (STM-based)

#### 2.2 Pure Package Solver

**Action:** Rewrite dependency solver without STM

**OLD (builder/src/Deps/Solver.hs - Uses STM):**
```haskell
solve :: Deps.Registry -> Constraints -> IO (Either Error Solution)
solve registry constraints = do
  stateVar <- newTVar initialState  -- ❌ TVar
  -- STM-based backtracking...
```

**NEW (packages/canopy-builder/src/Builder/Solver.hs - PURE):**
```haskell
-- | Pure constraint solving
data SolverState = SolverState
  { solverAssignments :: !(Map PackageName Version)
  , solverBacktrack :: ![Choice]
  , solverConstraints :: !Constraints
  } deriving (Show, Eq)

-- | Pure solver with explicit state passing
solve :: Registry -> Constraints -> Either SolverError Solution
solve registry constraints =
  runSolver registry initialState constraints

-- | Pure backtracking search
runSolver :: Registry -> SolverState -> Constraints -> Either SolverError Solution
runSolver registry state constraints =
  case selectNextPackage constraints state of
    Nothing -> Right (extractSolution state)
    Just pkg ->
      let versions = getCompatibleVersions registry pkg constraints
      in tryVersions registry state constraints pkg versions

-- No IO, no STM, pure backtracking!
```

**Files to Create:**
- `packages/canopy-builder/src/Builder/Solver.hs` (pure solver)
- `packages/canopy-builder/src/Builder/Registry.hs` (pure registry)
- `packages/canopy-builder/src/Builder/Constraints.hs` (constraint types)

**Files to MOVE TO old/:**
- `builder/src/Deps/Solver.hs` (STM-based)
- `builder/src/Deps/Registry.hs` (STM-based)

#### 2.3 Incremental Compilation Strategy

**Action:** Implement content-hash based incremental builds

**NEW (packages/canopy-builder/src/Builder/Incremental.hs):**
```haskell
-- | Content-hash based change detection
data SourceHash = SourceHash
  { hashContent :: !ByteString     -- SHA256 of file content
  , hashDependencies :: ![ByteString]  -- Hashes of dependencies
  } deriving (Show, Eq)

-- | Incremental build state (persisted to disk)
data IncrementalState = IncrementalState
  { stateHashes :: !(Map FilePath SourceHash)
  , stateInterfaces :: !(Map ModuleName InterfaceHash)
  , stateTimestamp :: !UTCTime
  } deriving (Show, Eq)

-- | Determine what needs recompilation
computeRebuildPlan :: IncrementalState -> DependencyGraph -> IO RebuildPlan
computeRebuildPlan prevState graph = do
  -- 1. Hash all source files
  currentHashes <- hashAllSources graph

  -- 2. Compare with previous state
  let changed = detectChanges prevState currentHashes

  -- 3. Propagate changes through dependency graph
  let affected = propagateChanges graph changed

  -- 4. Create rebuild plan
  return (RebuildPlan affected (stateHashes prevState))

-- | Persist incremental state to .canopy-build/state.json
saveIncrementalState :: IncrementalState -> IO ()
saveIncrementalState state =
  BS.writeFile ".canopy-build/state.json" (encode state)
```

**Files to Create:**
- `packages/canopy-builder/src/Builder/Incremental.hs`
- `packages/canopy-builder/src/Builder/Hash.hs` (content hashing)
- `packages/canopy-builder/src/Builder/State.hs` (state persistence)

### Phase 3: Driver Integration (Weeks 5-6)

#### 3.1 Unified Driver Interface

**Action:** Create single entry point replacing Build.fromPaths

**NEW (packages/canopy-driver/src/Driver/Main.hs):**
```haskell
-- | Main driver entry point (replaces Build.fromPaths)
compilePaths :: CompileConfig -> [FilePath] -> IO (Either CompileError Artifacts)
compilePaths config paths = do
  Logger.debug COMPILE_DEBUG "Starting compilation with new driver"

  -- 1. Build pure dependency graph
  graph <- case Builder.buildGraph (configProject config) paths of
    Left err -> return (Left (GraphError err))
    Right g -> return (Right g)

  case graph of
    Left err -> return (Left err)
    Right depGraph -> do
      -- 2. Load incremental state
      prevState <- Builder.loadIncrementalState

      -- 3. Compute what needs rebuilding
      rebuildPlan <- Builder.computeRebuildPlan prevState depGraph

      -- 4. Initialize query engine
      engine <- Engine.initEngine

      -- 5. Compile modules (parallel via worker pool)
      artifacts <- compileModules engine config rebuildPlan

      -- 6. Save incremental state
      Builder.saveIncrementalState (extractState artifacts)

      return (Right artifacts)

-- | Parallel compilation via worker pool (NO STM!)
compileModules :: QueryEngine -> CompileConfig -> RebuildPlan -> IO Artifacts
compileModules engine config plan = do
  -- Create worker pool with message-passing
  pool <- Pool.createPool (configWorkers config) (compileTask engine)

  -- Submit compilation tasks
  let tasks = createCompileTasks plan
  results <- Pool.submitTasks pool tasks

  -- Collect artifacts
  Pool.shutdownPool pool
  return (collectArtifacts results)
```

**Files to Update:**
- `packages/canopy-driver/src/Driver/Main.hs` (orchestration)
- `packages/canopy-driver/src/Driver/Config.hs` (configuration)
- `packages/canopy-driver/src/Driver/Worker.hs` (worker pool)

#### 3.2 Fix Code Generation Bug

**Action:** Fix Generate.JavaScript global lookup issue

**CURRENT PROBLEM (compiler/src/Generate/JavaScript.hs):**
```haskell
-- BUG: Doesn't include all dependency code
generate :: Opt.GlobalGraph -> Mode.Mode -> Output.Output -> IO B.ByteString
generate (Opt.GlobalGraph mains _) mode output =
  -- Only generates code for mains, missing dependencies!
```

**FIX (packages/canopy-driver/src/Queries/Generate.hs):**
```haskell
-- | Generate query with complete dependency graph
data GenerateQuery = GenerateQuery
  { generateArtifacts :: !Artifacts      -- All modules
  , generateMode :: !Mode
  , generateOutput :: !Output
  } deriving (Show, Eq)

instance Query GenerateQuery where
  type Result GenerateQuery = ByteString

  execute query = do
    Logger.debug CODEGEN "Generating JavaScript"

    let artifacts = generateArtifacts query
        allModules = _artifactsModules artifacts  -- ALL modules
        depInterfaces = _artifactsDeps artifacts  -- ALL dependencies

    -- 1. Build complete global graph (including ALL dependencies)
    let completeGraph = buildCompleteGraph allModules depInterfaces

    -- 2. Generate code for ALL modules
    code <- Generate.fromGraph completeGraph (generateMode query) (generateOutput query)

    Logger.debug CODEGEN "Code generation complete"
    return (Right code)

-- | Build complete global graph including ALL dependencies
buildCompleteGraph :: [Module] -> DependencyInterfaces -> Opt.GlobalGraph
buildCompleteGraph modules depInterfaces =
  let moduleGraphs = map extractLocalGraph modules
      depGraphs = map (loadDepGraph depInterfaces) (getDependencies modules)
      allGraphs = moduleGraphs ++ depGraphs
  in Opt.GlobalGraph (mergeGraphs allGraphs) Map.empty
```

**Files to Update:**
- `packages/canopy-driver/src/Queries/Generate.hs` (fix)
- Test with examples to verify all dependencies included

### Phase 4: Interface Format Redesign (Weeks 7-8)

#### 4.1 JSON Interface Format

**Action:** Switch from binary .cani to JSON format

**OLD (Binary - compiler/src/Canopy/Interface.hs):**
```haskell
-- Binary instance for Interface (opaque)
instance Binary Interface where
  put (Interface pkg vals unions aliases binops) = ...
  get = ...
```

**NEW (packages/canopy-driver/src/Interface/JSON.hs):**
```haskell
-- | JSON interface format (inspired by PureScript)
data InterfaceFile = InterfaceFile
  { ifVersion :: !Text               -- "2.0.0"
  , ifPackage :: !PackageName        -- "elm/core"
  , ifModule :: !ModuleName          -- "List"
  , ifContentHash :: !ContentHash    -- SHA256 of source
  , ifExports :: !ExportMap          -- What's exported
  , ifDependencies :: !DependencyMap -- What's imported
  } deriving (Show, Eq, Generic)

instance ToJSON InterfaceFile
instance FromJSON InterfaceFile

-- | Export map with fine-grained hashes
data ExportMap = ExportMap
  { exportValues :: !(Map Name ValueExport)
  , exportTypes :: !(Map Name TypeExport)
  , exportAliases :: !(Map Name AliasExport)
  } deriving (Show, Eq, Generic)

data ValueExport = ValueExport
  { valueType :: !Text           -- "(a -> b) -> List a -> List b"
  , valueHash :: !ContentHash    -- Hash of value implementation
  } deriving (Show, Eq, Generic)

-- | Write interface to JSON
writeInterface :: FilePath -> Interface -> IO ()
writeInterface path iface = do
  let jsonFile = toInterfaceFile iface
  BS.writeFile (path <.> "json") (encodePretty jsonFile)

-- | Read interface from JSON (or legacy binary)
readInterface :: FilePath -> IO (Either InterfaceError Interface)
readInterface path = do
  -- Try JSON first
  jsonExists <- doesFileExist (path <.> "json")
  if jsonExists
    then decodeFileStrict (path <.> "json") >>= \case
      Just iface -> return (Right (fromInterfaceFile iface))
      Nothing -> tryBinary
    else tryBinary
  where
    -- Fallback to legacy binary for backwards compatibility
    tryBinary = Binary.decodeFileOrFail (path <.> "cani") >>= \case
      Right iface -> return (Right iface)
      Left err -> return (Left (BinaryError err))
```

**Benefits:**
- 10x faster IDE parsing (proven by PureScript)
- Human-readable for debugging
- Content-hash based invalidation
- External tools can read without compiler
- Fine-grained dependency tracking

**Files to Create:**
- `packages/canopy-driver/src/Interface/JSON.hs`
- `packages/canopy-driver/src/Interface/Binary.hs` (legacy reader)
- `packages/canopy-driver/src/Interface/Migration.hs` (migrate old to new)

#### 4.2 Simplified Kernel Handling

**Action:** Redesign kernel code integration

**CURRENT (Complex - compiler/src/Canopy/Kernel.hs):**
```haskell
-- Complex chunk-based representation
data Chunk
  = JS B.ByteString
  | CanopyVar ModuleName.Canonical Name.Name
  | JsVar Name.Name Name.Name
  | CanopyField Name.Name
  | JsField Int
  | JsEnum Int
  | Debug
  | Prod
```

**NEW (Simplified - packages/canopy-driver/src/Queries/Kernel.hs):**
```haskell
-- | Kernel code as structured source (not string chunks!)
data KernelSource = KernelSource
  { kernelModule :: !ModuleName
  , kernelFilePath :: !FilePath
  , kernelFunctions :: !(Map Name KernelFunction)
  , kernelContentHash :: !ContentHash
  } deriving (Show, Eq)

-- | Kernel function with parsed JavaScript
data KernelFunction = KernelFunction
  { kernelFuncName :: !Name
  , kernelFuncType :: !Type
  , kernelFuncJS :: !JSAST.Expression    -- Parsed with language-javascript
  , kernelFuncDependencies :: ![Name]
  } deriving (Show, Eq)

-- | Parse kernel module query
data ParseKernelQuery = ParseKernelQuery
  { kernelQueryModule :: !ModuleName
  , kernelQueryHash :: !ContentHash
  } deriving (Show, Eq)

instance Query ParseKernelQuery where
  type Result ParseKernelQuery = KernelSource

  execute query = do
    Logger.debug KERNEL_DEBUG ("Parsing kernel: " ++ show (kernelQueryModule query))

    -- Read kernel JS file
    let path = kernelModuleToPath (kernelQueryModule query)
    content <- BS.readFile path

    -- Parse with language-javascript (REQUIRED for accuracy)
    case JSAST.parse content (kernelQueryModule query) of
      Left err -> return (Left (KernelParseError err))
      Right ast -> do
        -- Extract kernel functions
        let functions = extractKernelFunctions ast

        return (Right (KernelSource
          { kernelModule = kernelQueryModule query
          , kernelFilePath = path
          , kernelFunctions = functions
          , kernelContentHash = kernelQueryHash query
          }))
```

**Benefits:**
- Simpler internal representation
- Query-based with caching
- Content-hash invalidation
- Same external behavior (backwards compatible)
- Easier to optimize

**Files to Create:**
- `packages/canopy-driver/src/Queries/Kernel.hs`
- `packages/canopy-driver/src/Kernel/Parser.hs` (language-javascript integration)
- `packages/canopy-driver/src/Kernel/CodeGen.hs` (generate from AST)

### Phase 5: Terminal Integration (Weeks 9-10)

#### 5.1 Update Make Command

**Action:** Use new Driver instead of old Build

**OLD (terminal/src/Make.hs - Uses Build.fromPaths):**
```haskell
executeBuildStrategy ctx (p : ps) _maybeDocs maybeOutput = do
  -- OLD: Uses Build.fromPaths (STM-based)
  artifacts <- buildFromPaths ctx (NE.List p ps)
  generateOutput ctx artifacts maybeOutput
```

**NEW (packages/canopy-terminal/src/Make.hs - Uses Driver):**
```haskell
executeBuildStrategy ctx (p : ps) _maybeDocs maybeOutput = do
  Logger.debug MAKE "Using new driver for compilation"

  -- Create driver config from context
  let driverConfig = contextToConfig ctx

  -- Use new driver (no STM!)
  result <- Driver.compilePaths driverConfig (p : ps)

  case result of
    Left err -> Task.throw (Exit.MakeDriverError err)
    Right artifacts -> do
      -- Generate output (same as before)
      generateOutput ctx artifacts maybeOutput
```

**Files to Update:**
- `packages/canopy-terminal/src/Make.hs`
- `packages/canopy-terminal/src/Make/Builder.hs` (use Driver)

#### 5.2 Update Install Command

**Action:** Use new pure Solver

**OLD (terminal/src/Install.hs - Calls old Solver):**
```haskell
installDependencies deps = do
  -- Uses Deps.Solver (STM-based)
  solution <- Deps.Solver.solve registry constraints
```

**NEW (packages/canopy-terminal/src/Install.hs):**
```haskell
installDependencies deps = do
  Logger.debug INSTALL "Using pure solver"

  -- Load registry (pure)
  registry <- Builder.loadRegistry

  -- Solve constraints (pure, no IO!)
  let solution = Builder.solve registry constraints

  case solution of
    Left err -> Task.throw (Exit.InstallSolverError err)
    Right packages -> installPackages packages
```

**Files to Update:**
- `packages/canopy-terminal/src/Install.hs`

#### 5.3 Update REPL Command

**Action:** Use new Driver for REPL compilation

**Files to Update:**
- `packages/canopy-terminal/src/Repl.hs`
- Use Driver.compileSource instead of old Build.fromRepl

### Phase 6: Testing & Validation (Weeks 11-12)

#### 6.1 Comprehensive Test Suite

**Action:** Create tests for all new components

**Test Structure:**
```
packages/
├── canopy-core/test/
│   ├── Test/AST/          -- AST tests (existing)
│   ├── Test/Parse/        -- Parser tests (existing)
│   └── Test/Type/         -- Type tests (existing)
│
├── canopy-query/test/
│   ├── Test/Query/Engine.hs      -- Query engine tests
│   ├── Test/Query/Cache.hs       -- Caching tests
│   └── Test/Query/Dependencies.hs -- Dependency tests
│
├── canopy-driver/test/
│   ├── Test/Driver/Main.hs       -- Driver orchestration
│   ├── Test/Queries/Generate.hs  -- Code generation (verify fix)
│   └── Test/Interface/JSON.hs    -- JSON interface tests
│
├── canopy-builder/test/
│   ├── Test/Builder/Graph.hs     -- Dependency graph tests
│   ├── Test/Builder/Solver.hs    -- Pure solver tests
│   └── Test/Builder/Incremental.hs -- Incremental build tests
│
└── canopy-terminal/test/
    ├── Test/Make.hs               -- Make command tests
    └── Test/Install.hs            -- Install command tests
```

**Golden Tests:**
```bash
# Test new compiler produces identical output to old compiler
test/golden/
├── hello-world/           -- Basic example
├── with-kernel/           -- Kernel code example
├── with-ffi/              -- FFI example
└── large-app/             -- Complex application

# Run golden tests
for example in test/golden/*/; do
  # Compile with old compiler (baseline)
  OLD_OUTPUT=$(canopy make "$example/src/Main.elm" 2>&1)

  # Compile with new compiler
  NEW_OUTPUT=$(CANOPY_NEW_COMPILER=1 canopy make "$example/src/Main.elm" 2>&1)

  # Compare outputs (should be identical)
  diff <(echo "$OLD_OUTPUT") <(echo "$NEW_OUTPUT")
done
```

#### 6.2 Performance Benchmarks

**Action:** Measure and validate performance improvements

**Benchmark Suite:**
```haskell
-- bench/Bench/Incremental.hs
benchIncrementalCompilation :: Benchmark
benchIncrementalCompilation = bgroup "incremental"
  [ bench "cold build" $ nfIO (compileFresh largeProject)
  , bench "no changes" $ nfIO (compileNoChanges largeProject)
  , bench "single file change" $ nfIO (compileSingleChange largeProject)
  , bench "dependency change" $ nfIO (compileDepChange largeProject)
  ]

-- bench/Bench/Parallel.hs
benchParallelCompilation :: Benchmark
benchParallelCompilation = bgroup "parallel"
  [ bench "1 worker" $ nfIO (compileWithWorkers 1 largeProject)
  , bench "2 workers" $ nfIO (compileWithWorkers 2 largeProject)
  , bench "4 workers" $ nfIO (compileWithWorkers 4 largeProject)
  , bench "8 workers" $ nfIO (compileWithWorkers 8 largeProject)
  ]
```

**Performance Targets:**
- ✅ 30% faster incremental builds (like Swift 6.0)
- ✅ 50% faster cold builds (parallel compilation)
- ✅ 10x faster IDE interface loading (JSON vs binary)
- ✅ Sub-second rebuilds for single file changes

---

## Implementation Phases

### Phase 1: Foundation (Weeks 1-2)

**Goal:** Setup multi-package structure and migrate core modules

**Tasks:**
1. Create package structure (5 packages)
2. Move canopy-core files (200 files, no changes)
3. Move canopy-query files (14 files, minimal changes)
4. Move canopy-driver files (driver + queries)
5. Setup stack.yaml for multi-package build
6. Verify everything compiles

**Deliverables:**
- ✅ Multi-package structure working
- ✅ All existing tests pass
- ✅ No functionality changes
- ✅ Clear dependency layers

**Validation:**
```bash
# Build all packages
stack build

# Run all existing tests
stack test

# Verify no regressions
make test
```

### Phase 2: Builder Redesign (Weeks 3-4)

**Goal:** Eliminate all STM usage from Builder

**Tasks:**
1. Create pure dependency graph (Builder/Graph.hs)
2. Implement pure cycle detection (Builder/Cycles.hs)
3. Rewrite dependency solver (Builder/Solver.hs - pure)
4. Create incremental compilation strategy (Builder/Incremental.hs)
5. Content-hash based change detection (Builder/Hash.hs)
6. Move old STM-based code to old/

**Deliverables:**
- ✅ 0 STM usage in canopy-builder
- ✅ Pure functional dependency graph
- ✅ Content-hash based incremental builds
- ✅ State persisted to .canopy-build/state.json

**Validation:**
```bash
# Verify no STM imports
grep -r "STM\|MVar\|TVar" packages/canopy-builder/src/
# Should return nothing!

# Test pure solver
stack test canopy-builder

# Benchmark incremental builds
stack bench canopy-builder
```

### Phase 3: Driver Integration (Weeks 5-6)

**Goal:** Integrate new Builder with Driver, fix code generation

**Tasks:**
1. Update Driver.Main to use pure Builder
2. Fix Generate.JavaScript global lookup bug
3. Implement GenerateQuery with complete dependency graph
4. Simplify kernel code handling
5. Test with all examples

**Deliverables:**
- ✅ Driver uses pure Builder (no STM)
- ✅ Code generation includes ALL dependencies
- ✅ Kernel code works with new system
- ✅ All examples compile correctly

**Validation:**
```bash
# Test code generation fix
CANOPY_DEBUG=CODEGEN canopy make examples/with-kernel/src/Main.elm

# Verify all dependencies included
grep -o "elm\$html" output.js  # Should find elm/html code
grep -o "elm\$core" output.js  # Should find elm/core code

# Run golden tests
make test-golden
```

### Phase 4: Interface Format (Weeks 7-8)

**Goal:** Switch to JSON interface format

**Tasks:**
1. Implement JSON serialization (Interface/JSON.hs)
2. Create binary reader for backwards compat (Interface/Binary.hs)
3. Migration tool (Interface/Migration.hs)
4. Update all interface read/write calls
5. Benchmark performance improvement

**Deliverables:**
- ✅ JSON interface format working
- ✅ Backwards compatible with binary .cani
- ✅ 10x faster IDE loading (verified)
- ✅ Human-readable interface files

**Validation:**
```bash
# Generate JSON interface
canopy make examples/hello/src/Main.elm
ls -la .canopy/interfaces/  # Should see .json files

# Benchmark interface loading
stack bench canopy-driver -- --pattern "interface loading"

# Verify backwards compatibility
canopy make --use-binary-interfaces examples/hello/src/Main.elm
```

### Phase 5: Terminal Integration (Weeks 9-10)

**Goal:** Update CLI commands to use new system

**Tasks:**
1. Update Make command (use Driver)
2. Update Install command (use pure Solver)
3. Update REPL command (use Driver)
4. Update Init command (minimal changes)
5. CLI backwards compatibility tests

**Deliverables:**
- ✅ All CLI commands use new system
- ✅ Same command-line interface
- ✅ Same error messages
- ✅ Same behavior (externally)

**Validation:**
```bash
# Test all CLI commands
canopy make examples/hello/src/Main.elm
canopy install elm/html
canopy repl
canopy init test-project

# Verify backwards compatibility
./test/cli-compat.sh  # Runs all CLI tests
```

### Phase 6: Testing & Validation (Weeks 11-12)

**Goal:** Comprehensive testing and performance validation

**Tasks:**
1. Create comprehensive test suite
2. Golden tests (output comparison)
3. Performance benchmarks
4. Stress testing (large projects)
5. Migration guide
6. Documentation

**Deliverables:**
- ✅ 80%+ test coverage
- ✅ All golden tests pass
- ✅ Performance targets met
- ✅ Migration guide complete
- ✅ Production-ready

**Validation:**
```bash
# Run full test suite
make test

# Run golden tests
make test-golden

# Run benchmarks
make bench

# Generate coverage report
make coverage
```

---

## Risk Mitigation

### Risk 1: Breaking Changes

**Risk:** New compiler produces different output

**Mitigation:**
- Extensive golden tests comparing old vs new
- Gradual migration with feature flags
- Backwards compatibility layer
- Rollback plan

**Rollback Plan:**
```bash
# If new compiler has issues, disable it
export CANOPY_NEW_COMPILER=0

# Old compiler remains in old/ directory
# Can restore old build system if needed
```

### Risk 2: Performance Regression

**Risk:** New system is slower than old

**Mitigation:**
- Continuous benchmarking
- Performance targets defined upfront
- Query-based caching should improve speed
- Parallel compilation with worker pool

**Performance Monitoring:**
```bash
# Benchmark every commit
make bench

# Compare with baseline
./bench/compare.sh baseline current

# Alert if regression > 10%
```

### Risk 3: Incomplete Migration

**Risk:** Some functionality works with old, not new

**Mitigation:**
- Incremental migration by phase
- Feature parity checklist
- Extensive testing at each phase
- Dual-mode operation (old/new toggle)

**Feature Parity Checklist:**
- [ ] Parse all Elm syntax
- [ ] Canonicalize modules
- [ ] Type check correctly
- [ ] Optimize expressions
- [ ] Generate correct JavaScript
- [ ] Handle kernel code
- [ ] Process FFI declarations
- [ ] Resolve dependencies
- [ ] Install packages
- [ ] REPL interaction

### Risk 4: STM Removal Issues

**Risk:** Concurrency bugs from removing STM

**Mitigation:**
- Replace STM with message-passing (Chan)
- Single IORef per engine (not MVars/TVars)
- Pure data structures (Map, Set)
- Worker pool with explicit coordination
- Extensive concurrency testing

**Testing Strategy:**
```haskell
-- Test concurrent compilation
testConcurrentCompilation :: Spec
testConcurrentCompilation = do
  it "compiles modules in parallel correctly" $ do
    pool <- Pool.createPool 4 compileTask
    results <- Pool.submitTasks pool tasks
    -- Verify all results correct
    -- Verify no race conditions
```

---

## Technical Specifications

### Query System API

```haskell
-- packages/canopy-query/src/Query/Types.hs

-- | Query type class (inspired by Rust Salsa)
class Query q where
  type Key q :: *
  type Result q :: *

  -- Execute query
  execute :: Key q -> IO (Either QueryError (Result q))

  -- Query dependencies (for invalidation)
  dependencies :: Key q -> [SomeQuery]

  -- Description for debugging
  description :: Key q -> String

-- | Query engine with single IORef (NO STM!)
newtype QueryEngine = QueryEngine
  { engineState :: IORef EngineState
  }

data EngineState = EngineState
  { engineCache :: !(Map SomeQuery CacheEntry)     -- Pure Map
  , engineRunning :: !(Set SomeQuery)              -- Pure Set
  , engineStats :: !QueryStats
  , engineConfig :: !QueryConfig
  } deriving (Show, Eq)

-- | Content-hash for cache invalidation
newtype ContentHash = ContentHash ByteString
  deriving (Eq, Ord, Show)

-- | Cache entry with dependencies
data CacheEntry = CacheEntry
  { entryResult :: !QueryResult
  , entryDependencies :: ![ContentHash]    -- Hash of dependencies
  , entryTimestamp :: !UTCTime
  , entryHash :: !ContentHash             -- Hash of this result
  } deriving (Show)

-- | Run query with caching
runQuery :: QueryEngine -> SomeQuery -> IO (Either QueryError QueryResult)
runQuery engine query = do
  state <- readIORef (engineState engine)

  -- Check cache
  case Map.lookup query (engineCache state) of
    Just entry | isValid entry state -> return (Right (entryResult entry))
    _ -> do
      -- Execute query
      result <- executeQuery query

      -- Update cache (single IORef modification)
      modifyIORef' (engineState engine) (cacheResult query result)

      return result
```

### Driver API

```haskell
-- packages/canopy-driver/src/Driver/Main.hs

-- | Driver configuration
data CompileConfig = CompileConfig
  { configProject :: !ProjectConfig
  , configMode :: !CompilationMode
  , configWorkers :: !Int
  , configOutput :: !OutputConfig
  } deriving (Show, Eq)

-- | Main driver entry point
compilePaths :: CompileConfig -> [FilePath] -> IO (Either CompileError Artifacts)

-- | Compile with incremental state
compileIncremental :: CompileConfig -> IncrementalState -> [FilePath] -> IO (Either CompileError Artifacts)

-- | Compilation modes
data CompilationMode
  = DebugMode DebugConfig
  | ReleaseMode ReleaseConfig
  | LSPMode LSPConfig
  deriving (Show, Eq)
```

### Builder API

```haskell
-- packages/canopy-builder/src/Builder/Graph.hs

-- | Build pure dependency graph
buildGraph :: ProjectConfig -> [FilePath] -> Either GraphError DependencyGraph

-- | Detect cycles (pure)
detectCycles :: DependencyGraph -> Maybe CycleError

-- | Topological sort (pure)
topologicalSort :: DependencyGraph -> Either GraphError [ModuleName.Raw]

-- packages/canopy-builder/src/Builder/Solver.hs

-- | Solve package constraints (pure, no IO!)
solve :: Registry -> Constraints -> Either SolverError Solution

-- | Check constraint satisfaction (pure)
satisfies :: Version -> Constraint -> Bool

-- packages/canopy-builder/src/Builder/Incremental.hs

-- | Compute rebuild plan (content-hash based)
computeRebuildPlan :: IncrementalState -> DependencyGraph -> IO RebuildPlan

-- | Load incremental state from disk
loadIncrementalState :: IO IncrementalState

-- | Save incremental state to disk
saveIncrementalState :: IncrementalState -> IO ()
```

### Interface API

```haskell
-- packages/canopy-driver/src/Interface/JSON.hs

-- | Write interface as JSON
writeInterface :: FilePath -> Interface -> IO ()

-- | Read interface (JSON or legacy binary)
readInterface :: FilePath -> IO (Either InterfaceError Interface)

-- | Interface file format
data InterfaceFile = InterfaceFile
  { ifVersion :: !Text
  , ifPackage :: !PackageName
  , ifModule :: !ModuleName
  , ifContentHash :: !ContentHash
  , ifExports :: !ExportMap
  , ifDependencies :: !DependencyMap
  } deriving (Show, Eq, Generic)

instance ToJSON InterfaceFile
instance FromJSON InterfaceFile
```

---

## Migration Strategy

### Gradual Migration Path

**Step 1: Dual Mode Operation (Week 1-2)**
```bash
# Default: Use old compiler
canopy make src/Main.elm

# Enable new compiler via environment variable
CANOPY_NEW_COMPILER=1 canopy make src/Main.elm

# Compare outputs
diff <(canopy make src/Main.elm) <(CANOPY_NEW_COMPILER=1 canopy make src/Main.elm)
```

**Step 2: Testing Period (Week 3-10)**
```bash
# CI runs both compilers
make test-old
CANOPY_NEW_COMPILER=1 make test-new

# Verify outputs identical
./test/golden-compare.sh
```

**Step 3: Switch Default (Week 11)**
```bash
# New compiler becomes default
# Old compiler available via flag
CANOPY_OLD_COMPILER=1 canopy make src/Main.elm
```

**Step 4: Deprecate Old (Week 12)**
```bash
# Remove old compiler
rm -rf old/

# New compiler is the only compiler
canopy make src/Main.elm
```

### User Migration Guide

**For Package Authors:**
1. No changes required - packages compile unchanged
2. Kernel code works as-is
3. FFI declarations unchanged
4. Published packages compatible

**For Application Developers:**
1. No changes to source code
2. No changes to elm.json/canopy.json
3. CLI commands identical
4. May see faster compilation!

**For Tool Developers:**
1. Interface files now JSON (easier to parse)
2. Content-hash based invalidation
3. Better incremental compilation
4. Same compiler output format

---

## Success Criteria

### Functional Requirements

- ✅ All Elm source code compiles unchanged
- ✅ All kernel code works unchanged
- ✅ All FFI declarations work unchanged
- ✅ Same CLI interface
- ✅ Same error messages
- ✅ Same generated JavaScript
- ✅ All existing packages compile
- ✅ All tests pass

### Performance Requirements

- ✅ 30% faster incremental builds (vs old compiler)
- ✅ 50% faster cold builds (parallel compilation)
- ✅ 10x faster IDE interface loading (JSON vs binary)
- ✅ Sub-second rebuilds for single file changes
- ✅ Linear scalability with worker pool (up to 8 cores)

### Code Quality Requirements

- ✅ 0 MVar/TVar/STM usage in new code
- ✅ 80%+ test coverage
- ✅ All functions ≤15 lines
- ✅ All functions ≤4 parameters
- ✅ Comprehensive documentation
- ✅ Pure functions where possible
- ✅ Clear data flow

### Technical Requirements

- ✅ Multi-package structure
- ✅ Query-based compilation
- ✅ Content-hash caching
- ✅ JSON interface format
- ✅ Worker pool parallelization
- ✅ Pure dependency graph
- ✅ Incremental state persistence

---

## Timeline

**Total Duration:** 12 weeks (3 months)

| Phase | Weeks | Focus | Deliverable |
|-------|-------|-------|------------|
| 1. Foundation | 1-2 | Multi-package setup | Structure ready |
| 2. Builder Redesign | 3-4 | Eliminate STM | Pure builder |
| 3. Driver Integration | 5-6 | Fix codegen, integrate | Driver complete |
| 4. Interface Format | 7-8 | JSON interfaces | 10x faster IDE |
| 5. Terminal Integration | 9-10 | Update CLI | User-facing ready |
| 6. Testing & Validation | 11-12 | Comprehensive tests | Production ready |

**Milestones:**
- **Week 2:** Multi-package structure compiles
- **Week 4:** Builder has 0 STM usage
- **Week 6:** Driver generates correct code
- **Week 8:** JSON interfaces working
- **Week 10:** All CLI commands updated
- **Week 12:** Production release

---

## Conclusion

This plan provides a complete roadmap for overhauling the Canopy compiler to production-quality standards. The approach:

1. **Leverages Success:** Uses working New.Compiler.* query-based implementation
2. **Eliminates Problems:** Removes all STM/MVar/TVar usage (474 instances)
3. **Follows Best Practices:** Adopts patterns from Rust, Swift, TypeScript, GHC
4. **Maintains Compatibility:** Same CLI, same Elm code, same kernel requirements
5. **Improves Performance:** 30-50% faster compilation, 10x faster IDE
6. **Ensures Quality:** Pure functions, comprehensive tests, clear architecture

The result will be a modern, maintainable, high-performance compiler that serves as the foundation for Canopy's future development.

**Next Steps:**
1. Review and approve plan
2. Setup initial multi-package structure (Week 1)
3. Begin Phase 1: Foundation (Week 1-2)
4. Iterate through phases systematically
5. Achieve production-ready compiler (Week 12)

---

*This plan is a living document and will be updated as implementation progresses.*
