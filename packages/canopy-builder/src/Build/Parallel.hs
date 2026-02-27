{-# LANGUAGE BangPatterns #-}

-- | Parallel compilation for the pure builder.
--
-- This module implements dependency-aware parallel compilation that:
--
-- * Groups modules by dependency level (topological layers)
-- * Compiles modules within each level concurrently
-- * Ensures all dependencies are compiled before dependents
-- * Maintains deterministic output
--
-- Expected performance: 3-5x improvement on multi-core systems
--
-- Architecture:
--
-- 1. Use Builder.Graph to get topological order
-- 2. Group modules into "levels" - modules with no interdependencies
-- 3. Compile each level in parallel using async
-- 4. Wait for level completion before starting next level
--
-- This ensures deterministic builds while maximizing parallelism.
--
-- @since 0.19.1
module Build.Parallel
  ( -- * Parallel Compilation
    compileParallelWithGraph,
    groupByDependencyLevel,

    -- * Types
    DependencyLevel (..),
    CompilationPlan (..),
  )
where

import qualified Builder.Graph as Graph
import qualified Canopy.ModuleName as ModuleName
import qualified Control.Concurrent.Async as Async
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set

-- | Represents a level in the dependency hierarchy.
-- Level 0: No dependencies (or only foreign/kernel dependencies)
-- Level 1: Depends only on Level 0
-- etc.
newtype DependencyLevel = DependencyLevel Int
  deriving (Eq, Ord, Show)

-- | Compilation plan with modules grouped by dependency level.
data CompilationPlan = CompilationPlan
  { planLevels :: ![[ModuleName.Raw]],
    planTotalModules :: !Int
  }
  deriving (Show, Eq)

-- | Group modules by their dependency level for parallel compilation.
-- This ensures that all dependencies of a module are compiled before the module itself.
groupByDependencyLevel :: Graph.DependencyGraph -> CompilationPlan
groupByDependencyLevel graph =
  let modules = Graph.getAllModules graph
      levels = computeLevels graph modules
      totalCount = sum (map length levels)
   in CompilationPlan
        { planLevels = levels,
          planTotalModules = totalCount
        }

-- | Compute dependency levels for modules.
-- Uses a breadth-first approach to assign levels.
computeLevels :: Graph.DependencyGraph -> [ModuleName.Raw] -> [[ModuleName.Raw]]
computeLevels graph allModules =
  let -- Start with modules that have no dependencies
      initialLevel = filter (hasNoDeps graph) allModules
      -- Build levels iteratively
      levels = buildLevels graph (Set.fromList allModules) (Set.fromList initialLevel) [initialLevel]
   in reverse levels

-- | Check if module has no dependencies (or only missing ones).
hasNoDeps :: Graph.DependencyGraph -> ModuleName.Raw -> Bool
hasNoDeps graph moduleName =
  case Graph.getModuleDeps graph moduleName of
    Nothing -> True
    Just deps -> Set.null deps

-- | Build dependency levels iteratively.
buildLevels ::
  Graph.DependencyGraph ->
  Set ModuleName.Raw -> -- ^ All modules to process
  Set ModuleName.Raw -> -- ^ Modules processed so far
  [[ModuleName.Raw]] -> -- ^ Levels built so far (reversed)
  [[ModuleName.Raw]] -- ^ Final levels (reversed)
buildLevels graph remaining processed levels =
  if Set.null remaining
    then levels
    else
      let -- Find modules whose dependencies are all processed
          nextLevel = Set.toList $ Set.filter (allDepsProcessed graph processed) remaining
       in if null nextLevel
            then levels -- No more progress possible (shouldn't happen with acyclic graph)
            else
              let processed' = Set.union processed (Set.fromList nextLevel)
                  remaining' = Set.difference remaining (Set.fromList nextLevel)
               in buildLevels graph remaining' processed' (nextLevel : levels)

-- | Check if all dependencies of a module have been processed.
allDepsProcessed :: Graph.DependencyGraph -> Set ModuleName.Raw -> ModuleName.Raw -> Bool
allDepsProcessed graph processed moduleName =
  case Graph.getModuleDeps graph moduleName of
    Nothing -> True
    Just deps -> Set.null (Set.difference deps processed)

-- | Compile modules in parallel using the dependency graph.
--
-- This function:
-- 1. Groups modules by dependency level
-- 2. Compiles each level in parallel
-- 3. Waits for level completion before starting next
--
-- Returns a map of module names to results in the same order as compilation.
compileParallelWithGraph ::
  -- | Compilation function for a single module
  (ModuleName.Raw -> status -> IO a) ->
  -- | Map of module names to their statuses
  Map ModuleName.Raw status ->
  -- | Dependency graph
  Graph.DependencyGraph ->
  -- | Results mapped by module name
  IO (Map ModuleName.Raw a)
compileParallelWithGraph compileOne statuses graph =
  do
    let plan = groupByDependencyLevel graph
    results <- compilePlan compileOne statuses plan
    return results

-- | Execute a compilation plan.
compilePlan ::
  (ModuleName.Raw -> status -> IO a) ->
  Map ModuleName.Raw status ->
  CompilationPlan ->
  IO (Map ModuleName.Raw a)
compilePlan compileOne statuses plan =
  do
    levelResults <- mapM (compileLevel compileOne statuses) (planLevels plan)
    return $ Map.unions levelResults

-- | Compile all modules in a single level concurrently.
compileLevel ::
  (ModuleName.Raw -> status -> IO a) ->
  Map ModuleName.Raw status ->
  [ModuleName.Raw] ->
  IO (Map ModuleName.Raw a)
compileLevel compileOne statuses modules =
  do
    -- Compile all modules in parallel
    results <- Async.mapConcurrently
      (\moduleName -> case Map.lookup moduleName statuses of
        Just status -> do
          result <- compileOne moduleName status
          return (moduleName, result)
        Nothing -> error $ "Module " ++ show moduleName ++ " not found in statuses map")
      modules
    return $ Map.fromList results
