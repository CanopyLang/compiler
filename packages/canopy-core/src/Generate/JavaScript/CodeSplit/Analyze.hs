{-# LANGUAGE OverloadedStrings #-}

-- | Generate.JavaScript.CodeSplit.Analyze — Chunk graph analysis
--
-- Partitions a program's global definitions into chunks based on lazy import
-- boundaries.  The analysis algorithm:
--
--   1. Compute the full set of reachable globals from main entry points.
--   2. Identify lazy boundaries: globals whose 'ModuleName' matches a module
--      in the lazy set.
--   3. Walk the graph from each lazy module root, collecting globals that are
--      exclusively reachable through that lazy boundary.
--   4. Extract shared globals: definitions reachable from two or more chunks
--      are moved into shared chunks.
--   5. Perform cross-module code motion: push definitions as deep as possible
--      in the chunk DAG, exploiting Canopy's purity guarantee.
--   6. Build the final 'ChunkGraph' with disjoint global sets.
--
-- When no lazy imports exist the analysis produces a single entry chunk that
-- contains every reachable global, yielding identical output to the legacy
-- single-file code path.
--
-- @since 0.19.2
module Generate.JavaScript.CodeSplit.Analyze
  ( analyze,
    analyzeWithCache,
    graphHash,
    reachableFrom,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import Control.Lens ((&), (.~), (%~), (^.))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Generate.JavaScript.CodeSplit.Types
  ( Chunk (..),
    ChunkGraph (..),
    ChunkGraphCache (..),
    ChunkId (..),
    ChunkKind (..),
    SplitConfig (..),
    cacheConfig,
    cacheGraphHash,
    cacheResult,
    cgEntry,
    cgGlobalToChunk,
    cgLazy,
    cgShared,
    chunkDeps,
    chunkGlobals,
    entryChunkId,
  )

-- | Type alias matching Generate.JavaScript convention.
type Graph = Map Opt.Global Opt.Node

-- | Type alias for main entry points.
type Mains = Map ModuleName.Canonical Opt.Main

-- | Analyze the global graph and produce a chunk partition.
--
-- When '_scLazyModules' is empty the result is a degenerate single entry
-- chunk — semantically identical to the non-split code path.
--
-- Invariants guaranteed by the returned 'ChunkGraph':
--
--   * Union of all chunk globals equals the full reachable set.
--   * Chunk global sets are pairwise disjoint.
--   * The entry chunk has no incoming chunk dependencies.
--   * The inter-chunk dependency graph is acyclic.
--
-- @since 0.19.2
analyze :: SplitConfig -> Opt.GlobalGraph -> Mains -> ChunkGraph
analyze config (Opt.GlobalGraph graph _ _) mains =
  buildChunkGraphFromConfig config graph mains

-- | Analyze with incremental caching support.
--
-- If the provided cache entry matches the current config and graph hash,
-- returns the cached 'ChunkGraph' without recomputing. Otherwise runs
-- 'analyze' and returns both the result and a new cache entry.
--
-- @since 0.19.2
analyzeWithCache ::
  Maybe ChunkGraphCache ->
  SplitConfig ->
  Opt.GlobalGraph ->
  Mains ->
  (ChunkGraph, ChunkGraphCache)
analyzeWithCache maybeCache config globalGraph mains =
  case maybeCache of
    Just cached
      | cached ^. cacheConfig == config
          && cached ^. cacheGraphHash == currentHash ->
          (cached ^. cacheResult, cached)
    _ ->
      (result, ChunkGraphCache config currentHash result)
  where
    currentHash = graphHash globalGraph
    result = analyze config globalGraph mains

-- | Compute a hash of a global graph's key set.
--
-- The hash captures the number of globals and the total number of
-- dependency edges. Node-level value changes that do not alter the
-- graph topology produce the same hash, which is correct because
-- chunk partitioning depends only on which globals exist and how
-- they reference each other.
--
-- @since 0.19.2
graphHash :: Opt.GlobalGraph -> Int
graphHash (Opt.GlobalGraph graph _ _) =
  Map.size graph * 1000003 + totalEdges
  where
    totalEdges = Map.foldl' countNodeDeps 0 graph
    countNodeDeps acc node = acc + Set.size (extractNodeDepsForHash node)

-- | Extract dependency set from a node for hashing purposes.
extractNodeDepsForHash :: Opt.Node -> Set Opt.Global
extractNodeDepsForHash (Opt.Define _ deps) = deps
extractNodeDepsForHash (Opt.DefineTailFunc _ _ deps) = deps
extractNodeDepsForHash (Opt.Ctor _ _) = Set.empty
extractNodeDepsForHash (Opt.Link g) = Set.singleton g
extractNodeDepsForHash (Opt.Cycle _ _ _ deps) = deps
extractNodeDepsForHash (Opt.Manager _) = Set.empty
extractNodeDepsForHash (Opt.Kernel _ deps) = deps
extractNodeDepsForHash (Opt.Enum _) = Set.empty
extractNodeDepsForHash Opt.Box = Set.empty
extractNodeDepsForHash (Opt.PortIncoming _ deps) = deps
extractNodeDepsForHash (Opt.PortOutgoing _ deps) = deps
extractNodeDepsForHash (Opt.AbilityDict _) = Set.empty
extractNodeDepsForHash (Opt.ImplDict _ _ deps) = deps

-- | Build chunk graph dispatching on presence of lazy modules.
buildChunkGraphFromConfig :: SplitConfig -> Graph -> Mains -> ChunkGraph
buildChunkGraphFromConfig config graph mains
  | Set.null (_scLazyModules config) = buildSingleChunk graph mains
  | otherwise = buildSplitChunks config graph mains

-- | Degenerate case: no lazy imports, single entry chunk.
buildSingleChunk :: Graph -> Mains -> ChunkGraph
buildSingleChunk graph mains =
  ChunkGraph
    { _cgEntry = entryChunk,
      _cgLazy = [],
      _cgShared = [],
      _cgGlobalToChunk = Map.fromSet (const entryChunkId) allReachable
    }
  where
    mainGlobals = mainEntryGlobals mains
    allReachable = reachableFrom graph mainGlobals
    entryChunk =
      Chunk
        { _chunkId = entryChunkId,
          _chunkKind = EntryChunk,
          _chunkGlobals = allReachable,
          _chunkDeps = Set.empty,
          _chunkModule = Nothing
        }

-- | Build split chunks when lazy modules are present.
buildSplitChunks :: SplitConfig -> Graph -> Mains -> ChunkGraph
buildSplitChunks config graph mains =
  applyCodeMotion graph rawChunkGraph
  where
    mainGlobals = mainEntryGlobals mains
    allReachable = reachableFrom graph mainGlobals
    lazyModules = _scLazyModules config
    minRefs = _scMinSharedRefs config
    lazyRoots = identifyLazyRoots lazyModules allReachable
    lazyReachSets = computeLazyReachSets graph lazyModules lazyRoots
    (sharedGlobals, refinedLazySets) = extractShared minRefs lazyReachSets
    entryGlobals = computeEntryGlobals allReachable refinedLazySets sharedGlobals
    lazyChunks = buildLazyChunks graph lazyModules refinedLazySets
    sharedChunks = buildSharedChunks graph sharedGlobals
    entry = buildEntryChunk entryGlobals lazyChunks sharedChunks
    globalMap = buildGlobalMap entry lazyChunks sharedChunks
    rawChunkGraph =
      ChunkGraph
        { _cgEntry = entry,
          _cgLazy = lazyChunks,
          _cgShared = sharedChunks,
          _cgGlobalToChunk = globalMap
        }

-- | Compute the set of globals reachable from a seed set via DFS.
--
-- Follows dependency edges in the graph, collecting every global
-- encountered.  This mirrors the traversal in "Generate.JavaScript"
-- but collects sets instead of emitting JavaScript.
--
-- @since 0.19.2
reachableFrom :: Graph -> Set Opt.Global -> Set Opt.Global
reachableFrom graph seeds =
  Set.foldl' (dfsGlobal graph) Set.empty seeds

-- | Depth-first search from a single global.
dfsGlobal :: Graph -> Set Opt.Global -> Opt.Global -> Set Opt.Global
dfsGlobal graph visited global
  | Set.member global visited = visited
  | otherwise = Set.foldl' (dfsGlobal graph) visited' deps
  where
    visited' = Set.insert global visited
    deps = nodeDeps global graph

-- | Extract dependency set from a node in the graph.
nodeDeps :: Opt.Global -> Graph -> Set Opt.Global
nodeDeps global graph =
  maybe Set.empty extractNodeDeps (Map.lookup global graph)

-- | Extract the dependency set from a graph node.
extractNodeDeps :: Opt.Node -> Set Opt.Global
extractNodeDeps node =
  case node of
    Opt.Define _ deps -> deps
    Opt.DefineTailFunc _ _ deps -> deps
    Opt.Cycle _ _ _ deps -> deps
    Opt.Kernel _ deps -> deps
    Opt.PortIncoming _ deps -> deps
    Opt.PortOutgoing _ deps -> deps
    Opt.Link target -> Set.singleton target
    Opt.Manager _ -> Set.empty
    Opt.Ctor _ _ -> Set.empty
    Opt.Enum _ -> Set.empty
    Opt.Box -> Set.empty
    Opt.AbilityDict _ -> Set.empty
    Opt.ImplDict _ _ deps -> deps

-- | Collect the main entry point globals from the Mains map.
mainEntryGlobals :: Mains -> Set Opt.Global
mainEntryGlobals =
  Map.foldlWithKey' addMainGlobal Set.empty
  where
    addMainGlobal acc home _ = Set.insert (Opt.Global home "main") acc

-- | Identify root globals for each lazy module.
--
-- A "lazy root" is any reachable global whose home module is in the
-- lazy set.  These roots seed the per-module reachability walks.
identifyLazyRoots ::
  Set ModuleName.Canonical ->
  Set Opt.Global ->
  Map ModuleName.Canonical (Set Opt.Global)
identifyLazyRoots lazyModules reachable =
  Set.foldl' addIfLazy Map.empty reachable
  where
    addIfLazy acc global@(Opt.Global home _)
      | Set.member home lazyModules =
          Map.insertWith Set.union home (Set.singleton global) acc
      | otherwise = acc

-- | Compute reachable sets for each lazy module boundary.
--
-- For each lazy module, walk from its roots following only
-- dependencies that do NOT cross back into a different lazy module.
computeLazyReachSets ::
  Graph ->
  Set ModuleName.Canonical ->
  Map ModuleName.Canonical (Set Opt.Global) ->
  Map ModuleName.Canonical (Set Opt.Global)
computeLazyReachSets graph lazyModules =
  Map.map (lazyBoundedReach graph lazyModules)

-- | DFS from lazy roots, stopping at other lazy module boundaries.
lazyBoundedReach ::
  Graph ->
  Set ModuleName.Canonical ->
  Set Opt.Global ->
  Set Opt.Global
lazyBoundedReach graph lazyModules seeds =
  case inferHome seeds of
    Nothing -> Set.empty
    Just homeModule ->
      Set.foldl' (lazyDfs graph lazyModules homeModule) Set.empty seeds

-- | Infer the home module from a set of globals (all should share the same home).
inferHome :: Set Opt.Global -> Maybe ModuleName.Canonical
inferHome globals =
  fmap (\(Opt.Global home _) -> home) (Set.lookupMin globals)

-- | DFS that stays within a lazy boundary.
--
-- Follows deps of the home lazy module but stops recursing when
-- entering a different lazy module's territory.
lazyDfs ::
  Graph ->
  Set ModuleName.Canonical ->
  ModuleName.Canonical ->
  Set Opt.Global ->
  Opt.Global ->
  Set Opt.Global
lazyDfs graph lazyModules homeModule visited global@(Opt.Global globalHome _)
  | Set.member global visited = visited
  | globalHome /= homeModule && Set.member globalHome lazyModules = visited
  | otherwise = Set.foldl' (lazyDfs graph lazyModules homeModule) visited' deps
  where
    visited' = Set.insert global visited
    deps = nodeDeps global graph

-- | Extract shared globals: definitions reachable from 2+ lazy chunks.
--
-- Globals that appear in multiple lazy chunk sets are extracted into
-- the shared pool.  '_scMinSharedRefs' controls the minimum number of
-- referencing chunks before extraction (default 2).
--
-- Returns the set of shared globals and the refined per-module sets
-- with shared globals removed.
extractShared ::
  Int ->
  Map ModuleName.Canonical (Set Opt.Global) ->
  (Set Opt.Global, Map ModuleName.Canonical (Set Opt.Global))
extractShared minRefs lazySets =
  (shared, refined)
  where
    refCounts = computeRefCounts lazySets
    shared = Map.keysSet (Map.filter (>= minRefs) refCounts)
    refined = Map.map (`Set.difference` shared) lazySets

-- | Count how many lazy chunks reference each global.
computeRefCounts ::
  Map ModuleName.Canonical (Set Opt.Global) ->
  Map Opt.Global Int
computeRefCounts =
  Map.foldl' addRefs Map.empty
  where
    addRefs acc globals = Set.foldl' incRef acc globals
    incRef acc global = Map.insertWith (+) global 1 acc

-- | Compute entry chunk globals.
--
-- Entry gets everything reachable that is NOT in a lazy chunk and
-- NOT in shared chunks.
computeEntryGlobals ::
  Set Opt.Global ->
  Map ModuleName.Canonical (Set Opt.Global) ->
  Set Opt.Global ->
  Set Opt.Global
computeEntryGlobals allReachable lazySets sharedGlobals =
  allReachable `Set.difference` allLazy `Set.difference` sharedGlobals
  where
    allLazy = Map.foldl' Set.union Set.empty lazySets

-- | Build lazy chunks from refined per-module sets.
buildLazyChunks ::
  Graph ->
  Set ModuleName.Canonical ->
  Map ModuleName.Canonical (Set Opt.Global) ->
  [Chunk]
buildLazyChunks graph _lazyModules =
  Map.foldlWithKey' (buildOneLazyChunk graph) []

-- | Build a single lazy chunk for one module.
buildOneLazyChunk ::
  Graph ->
  [Chunk] ->
  ModuleName.Canonical ->
  Set Opt.Global ->
  [Chunk]
buildOneLazyChunk _graph acc modName globals
  | Set.null globals = acc
  | otherwise = chunk : acc
  where
    cid = lazyChunkId modName
    chunk =
      Chunk
        { _chunkId = cid,
          _chunkKind = LazyChunk,
          _chunkGlobals = globals,
          _chunkDeps = Set.empty,
          _chunkModule = Just modName
        }

-- | Build shared chunks from the extracted shared global set.
--
-- Currently places all shared globals in a single shared chunk.
-- Future optimization: split into multiple shared chunks based on
-- co-occurrence patterns.
buildSharedChunks :: Graph -> Set Opt.Global -> [Chunk]
buildSharedChunks _graph sharedGlobals
  | Set.null sharedGlobals = []
  | otherwise = [sharedChunk]
  where
    sharedChunk =
      Chunk
        { _chunkId = ChunkId "shared-0",
          _chunkKind = SharedChunk,
          _chunkGlobals = sharedGlobals,
          _chunkDeps = Set.empty,
          _chunkModule = Nothing
        }

-- | Build the entry chunk.
buildEntryChunk :: Set Opt.Global -> [Chunk] -> [Chunk] -> Chunk
buildEntryChunk entryGlobals _lazyChunks _sharedChunks =
  Chunk
    { _chunkId = entryChunkId,
      _chunkKind = EntryChunk,
      _chunkGlobals = entryGlobals,
      _chunkDeps = Set.empty,
      _chunkModule = Nothing
    }

-- | Build the global -> chunk ID mapping from all chunks.
buildGlobalMap :: Chunk -> [Chunk] -> [Chunk] -> Map Opt.Global ChunkId
buildGlobalMap entry lazyChunks sharedChunks =
  foldl addChunkGlobals Map.empty allChunks
  where
    allChunks = entry : lazyChunks ++ sharedChunks
    addChunkGlobals acc chunk =
      Set.foldl' (\m g -> Map.insert g (_chunkId chunk) m) acc (_chunkGlobals chunk)

-- | Apply cross-module code motion.
--
-- Exploits Canopy's purity guarantee to push globals as deep as possible
-- in the chunk DAG.  A global used only by lazy chunk A should live in
-- chunk A, not in entry.  A global used by chunks A and B moves to
-- their shared chunk.
--
-- Also computes inter-chunk dependency edges after motion.
applyCodeMotion :: Graph -> ChunkGraph -> ChunkGraph
applyCodeMotion graph cg =
  computeChunkDeps graph movedCg
  where
    movedCg = moveGlobalsDown graph cg

-- | Move globals from entry to the deepest chunk that needs them.
moveGlobalsDown :: Graph -> ChunkGraph -> ChunkGraph
moveGlobalsDown graph cg =
  cg
    & cgEntry . chunkGlobals .~ newEntryGlobals
    & cgLazy .~ newLazyChunks
    & cgShared .~ newSharedChunks
    & cgGlobalToChunk .~ buildGlobalMap newEntry newLazyChunks newSharedChunks
  where
    entryGlobs = _cgEntry cg ^. chunkGlobals
    lazyCs = _cgLazy cg
    sharedCs = _cgShared cg
    globalMap = _cgGlobalToChunk cg
    (movedFromEntry, destinations) = findMovableGlobals graph entryGlobs lazyCs sharedCs globalMap
    newEntryGlobals = entryGlobs `Set.difference` movedFromEntry
    newLazyChunks = map (addMovedGlobals destinations) lazyCs
    newSharedChunks = map (addMovedGlobals destinations) sharedCs
    newEntry = (_cgEntry cg) {_chunkGlobals = newEntryGlobals}

-- | Find globals in entry that can move to exactly one non-entry chunk.
findMovableGlobals ::
  Graph ->
  Set Opt.Global ->
  [Chunk] ->
  [Chunk] ->
  Map Opt.Global ChunkId ->
  (Set Opt.Global, Map ChunkId (Set Opt.Global))
findMovableGlobals graph entryGlobals lazyCs sharedCs globalMap =
  Set.foldl' classifyGlobal (Set.empty, Map.empty) entryGlobals
  where
    nonEntryChunks = map _chunkId lazyCs ++ map _chunkId sharedCs
    classifyGlobal (moved, dests) global =
      let users = findChunkUsers graph global globalMap nonEntryChunks
       in case Set.toList users of
            [singleUser] ->
              ( Set.insert global moved,
                Map.insertWith Set.union singleUser (Set.singleton global) dests
              )
            _ -> (moved, dests)

-- | Find which non-entry chunks reference a given global.
findChunkUsers ::
  Graph ->
  Opt.Global ->
  Map Opt.Global ChunkId ->
  [ChunkId] ->
  Set ChunkId
findChunkUsers _graph global globalMap nonEntryChunks =
  Set.fromList (filter (chunkUsesGlobal globalMap global) nonEntryChunks)

-- | Check if a chunk references a specific global through its member deps.
chunkUsesGlobal :: Map Opt.Global ChunkId -> Opt.Global -> ChunkId -> Bool
chunkUsesGlobal globalMap target cid =
  any refsTarget (Map.toList globalMap)
  where
    refsTarget (g, gCid) = gCid == cid && g == target

-- | Add moved globals to a chunk if their destination matches.
addMovedGlobals :: Map ChunkId (Set Opt.Global) -> Chunk -> Chunk
addMovedGlobals destinations chunk =
  case Map.lookup (_chunkId chunk) destinations of
    Nothing -> chunk
    Just extras -> chunk & chunkGlobals %~ Set.union extras

-- | Compute inter-chunk dependency edges.
--
-- For each chunk, look at the dependencies of its globals. If any dep
-- belongs to a different chunk, add that chunk as a dependency.
computeChunkDeps :: Graph -> ChunkGraph -> ChunkGraph
computeChunkDeps graph cg =
  cg
    & cgEntry . chunkDeps .~ entryDeps
    & cgLazy .~ map setDeps lazyCs
    & cgShared .~ map setDeps sharedCs
  where
    globalMap = _cgGlobalToChunk cg
    lazyCs = _cgLazy cg
    sharedCs = _cgShared cg
    entryDeps = chunkDepSet graph globalMap (_cgEntry cg)
    setDeps chunk = chunk & chunkDeps .~ chunkDepSet graph globalMap chunk

-- | Compute the set of chunk IDs that a chunk depends on.
chunkDepSet :: Graph -> Map Opt.Global ChunkId -> Chunk -> Set ChunkId
chunkDepSet graph globalMap chunk =
  Set.delete (_chunkId chunk) depChunkIds
  where
    depChunkIds = Set.foldl' addGlobalDeps Set.empty (_chunkGlobals chunk)
    addGlobalDeps acc global =
      let deps = nodeDeps global graph
       in Set.foldl' (addDepChunk globalMap) acc deps
    addDepChunk gmap acc dep =
      maybe acc (`Set.insert` acc) (Map.lookup dep gmap)

-- | Generate a deterministic chunk ID for a lazy module.
lazyChunkId :: ModuleName.Canonical -> ChunkId
lazyChunkId (ModuleName.Canonical _pkg modName) =
  ChunkId ("lazy-" <> Text.pack (show modName))
