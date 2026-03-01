# Plan 10: Parallel Module Discovery

**Priority**: HIGH
**Effort**: Medium (2-3 days)
**Risk**: Medium
**Audit Finding**: Module discovery is sequential DFS; becomes the bottleneck at 1000+ modules

---

## Problem

`Compiler/Discovery.hs` performs sequential DFS traversal for module discovery. Each module is:
1. Found on disk (filesystem lookup across source directories)
2. Parsed (to extract imports)
3. Added to the discovery queue

For a project with 1000 modules, this means 1000 sequential parse operations. Parse is 28-35% of total compilation time, and discovery must complete before parallel compilation can begin.

**Estimated impact at scale:**
- 200 modules: ~2s discovery (acceptable)
- 600 modules: ~6s discovery (noticeable)
- 1000 modules: ~10s discovery (bottleneck)

---

## Solution

Parallelize module discovery using bounded concurrency:
1. Parse modules in parallel batches
2. Discover new imports from parsed modules
3. Queue newly-discovered modules for the next batch
4. Continue until no new modules are found

---

## Implementation

### Step 1: Batch-Parallel Discovery

**File: `packages/canopy-builder/src/Compiler/Discovery.hs`**

Replace the sequential DFS with a parallel BFS:

```haskell
-- | Discover all modules in parallel using bounded BFS.
-- Each level of the BFS is processed in parallel, discovering
-- new imports that form the next level.
discoverModulesParallel
  :: FilePath
  -> [FilePath]
  -> [ModuleName.Raw]
  -> IO (Either DiscoveryError ModuleGraph)
discoverModulesParallel root srcDirs entryModules = do
  numCaps <- Conc.getNumCapabilities
  sem <- QSem.newQSem (max 1 numCaps)
  go Set.empty Map.empty entryModules
  where
    go visited graph [] = pure (Right graph)
    go visited graph queue = do
      -- Filter already-visited modules
      let newModules = filter (not . flip Set.member visited) queue
      -- Parse all new modules in parallel
      results <- Async.mapConcurrently (withSemaphore sem . discoverOne root srcDirs) newModules
      -- Collect results and new imports
      case partitionEithers results of
        (err:_, _) -> pure (Left err)
        ([], parsed) -> do
          let newGraph = foldl' addToGraph graph parsed
              newVisited = Set.union visited (Set.fromList (map fst parsed))
              newImports = concatMap (snd . snd) parsed
          go newVisited newGraph newImports

-- | Discover a single module: find file, parse, extract imports.
discoverOne
  :: FilePath
  -> [FilePath]
  -> ModuleName.Raw
  -> IO (Either DiscoveryError (ModuleName.Raw, (FilePath, [ModuleName.Raw])))
discoverOne root srcDirs modName = do
  maybePath <- findModuleInDirs root srcDirs modName
  case maybePath of
    Nothing -> pure (Left (ModuleNotFound modName))
    Just path -> do
      content <- BS.readFile path
      case Parse.fromByteString Parse.Application content of
        Left err -> pure (Left (ParseError modName path err))
        Right modul -> do
          let imports = extractImports modul
          pure (Right (modName, (path, imports)))
```

### Step 2: Preserve DFS Order for Error Reporting

The current DFS order provides deterministic error reporting (first error found is always the same). Maintain this by sorting the final module graph topologically:

```haskell
-- After parallel discovery, sort for deterministic ordering
finalizeGraph :: ModuleGraph -> [ModuleName.Raw]
finalizeGraph graph =
  Graph.topologicalSort (buildDepGraph graph)
```

### Step 3: Cache Filesystem Lookups

**File: `packages/canopy-builder/src/Compiler/Discovery.hs`**

Add a concurrent cache for filesystem lookups to avoid redundant disk operations:

```haskell
-- | Cache for module path resolution.
-- Prevents duplicate filesystem lookups when multiple modules
-- import the same dependency.
type PathCache = IORef (Map ModuleName.Raw (Maybe FilePath))

lookupCached :: PathCache -> FilePath -> [FilePath] -> ModuleName.Raw -> IO (Maybe FilePath)
lookupCached cache root srcDirs modName = do
  cached <- Map.lookup modName <$> readIORef cache
  case cached of
    Just result -> pure result
    Nothing -> do
      result <- findModuleInDirs root srcDirs modName
      atomicModifyIORef' cache (\m -> (Map.insert modName result m, ()))
      pure result
```

### Step 4: Benchmark

Add benchmark for discovery:

```haskell
-- In benchmark suite
benchDiscovery :: Benchmark
benchDiscovery = bgroup "Module Discovery"
  [ bench "sequential/100" $ nfIO (discoverSequential project100)
  , bench "parallel/100" $ nfIO (discoverParallel project100)
  , bench "sequential/500" $ nfIO (discoverSequential project500)
  , bench "parallel/500" $ nfIO (discoverParallel project500)
  ]
```

---

## Validation

```bash
make build
make test

# Benchmark comparison
make bench -- discovery benchmarks
```

---

## Success Criteria

- [ ] Module discovery uses bounded parallel BFS
- [ ] Discovery time scales with `O(levels * parseTime)` instead of `O(modules * parseTime)`
- [ ] Filesystem lookups are cached (no duplicate disk operations)
- [ ] Error reporting order is deterministic (topological sort)
- [ ] Benchmark shows >= 2x improvement for 200+ module projects
- [ ] `make build` passes with zero warnings
- [ ] `make test` passes (3350+ tests)
- [ ] No race conditions (QSem + atomic IORef)
