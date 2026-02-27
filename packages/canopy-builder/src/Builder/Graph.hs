
-- | Pure dependency graph without STM.
--
-- This module implements dependency tracking using pure Map data structures.
-- Replaces the OLD Build/Crawl system's STM-based dependency crawling with
-- pure functional dependency resolution.
--
-- Key differences from OLD system:
--
-- * No TVars - uses pure Maps
-- * No STM transactions - uses IORef for state
-- * Explicit dependency tracking
-- * Topological sorting for build order
--
-- @since 0.19.1
module Builder.Graph
  ( -- * Graph Types
    DependencyGraph (..),
    ModuleNode (..),

    -- * Graph Construction
    emptyGraph,
    addModule,
    addDependency,
    buildGraph,

    -- * Graph Queries
    getModuleDeps,
    getAllModules,
    hasCycle,
    topologicalSort,

    -- * Graph Operations
    transitiveDeps,
    reverseDeps,
  )
where

import qualified Canopy.ModuleName as ModuleName
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set

-- | Node in the dependency graph.
data ModuleNode = ModuleNode
  { nodeModule :: !ModuleName.Raw,
    nodeDeps :: !(Set ModuleName.Raw),
    nodeReverseDeps :: !(Set ModuleName.Raw)
  }
  deriving (Show, Eq)

-- | Pure dependency graph.
data DependencyGraph = DependencyGraph
  { graphNodes :: !(Map ModuleName.Raw ModuleNode)
  }
  deriving (Show, Eq)

-- | Create empty dependency graph.
emptyGraph :: DependencyGraph
emptyGraph = DependencyGraph {graphNodes = Map.empty}

-- | Add module to graph.
addModule :: DependencyGraph -> ModuleName.Raw -> DependencyGraph
addModule graph moduleName =
  case Map.lookup moduleName (graphNodes graph) of
    Just _ -> graph -- Already exists
    Nothing ->
      let node =
            ModuleNode
              { nodeModule = moduleName,
                nodeDeps = Set.empty,
                nodeReverseDeps = Set.empty
              }
       in graph {graphNodes = Map.insert moduleName node (graphNodes graph)}

-- | Add dependency relationship.
addDependency ::
  DependencyGraph ->
  ModuleName.Raw -> -- ^ Module that depends
  ModuleName.Raw -> -- ^ Module being depended on
  DependencyGraph
addDependency graph from to =
  let graph' = addModule (addModule graph from) to
      nodes = graphNodes graph'
      updateFrom node = node {nodeDeps = Set.insert to (nodeDeps node)}
      updateTo node = node {nodeReverseDeps = Set.insert from (nodeReverseDeps node)}
      nodes' = Map.adjust updateFrom from (Map.adjust updateTo to nodes)
   in graph' {graphNodes = nodes'}

-- | Build complete graph from module dependencies.
buildGraph :: [(ModuleName.Raw, [ModuleName.Raw])] -> DependencyGraph
buildGraph moduleDeps =
  foldr addModuleDeps emptyGraph moduleDeps
  where
    addModuleDeps (moduleName, deps) graph =
      let graph' = addModule graph moduleName
       in foldr (\dep g -> addDependency g moduleName dep) graph' deps

-- | Get immediate dependencies of a module.
getModuleDeps :: DependencyGraph -> ModuleName.Raw -> Maybe (Set ModuleName.Raw)
getModuleDeps graph moduleName = do
  node <- Map.lookup moduleName (graphNodes graph)
  return (nodeDeps node)

-- | Get all modules in graph.
getAllModules :: DependencyGraph -> [ModuleName.Raw]
getAllModules graph = Map.keys (graphNodes graph)

-- | Check if graph contains cycles.
hasCycle :: DependencyGraph -> Bool
hasCycle graph =
  any (hasCycleFrom Set.empty) (getAllModules graph)
  where
    hasCycleFrom visited current
      | Set.member current visited = True
      | otherwise =
          case getModuleDeps graph current of
            Nothing -> False
            Just deps ->
              let visited' = Set.insert current visited
               in any (hasCycleFrom visited') (Set.toList deps)

-- | Topological sort for build order.
--
-- Returns Nothing if graph contains cycles.
topologicalSort :: DependencyGraph -> Maybe [ModuleName.Raw]
topologicalSort graph =
  if hasCycle graph
    then Nothing
    else Just (sort' Set.empty [] (getAllModules graph))
  where
    sort' _ result [] = reverse result
    sort' visited result (m : ms)
      | Set.member m visited = sort' visited result ms
      | otherwise =
          case getModuleDeps graph m of
            Nothing -> sort' (Set.insert m visited) (m : result) ms
            Just deps ->
              let unvisitedDeps = filter (`Set.notMember` visited) (Set.toList deps)
                  visited' = Set.insert m visited
                  result' = m : result
               in if null unvisitedDeps
                    then sort' visited' result' ms
                    else sort' visited result (unvisitedDeps ++ [m] ++ ms)

-- | Get transitive dependencies of a module.
transitiveDeps :: DependencyGraph -> ModuleName.Raw -> Set ModuleName.Raw
transitiveDeps graph moduleName =
  transitive Set.empty moduleName
  where
    transitive visited current
      | Set.member current visited = Set.empty
      | otherwise =
          case getModuleDeps graph current of
            Nothing -> Set.empty
            Just deps ->
              let visited' = Set.insert current visited
                  directDeps = deps
                  transitiveDeps' = Set.unions (map (transitive visited') (Set.toList deps))
               in Set.union directDeps transitiveDeps'

-- | Get reverse dependencies (modules that depend on this module).
reverseDeps :: DependencyGraph -> ModuleName.Raw -> Maybe (Set ModuleName.Raw)
reverseDeps graph moduleName = do
  node <- Map.lookup moduleName (graphNodes graph)
  return (nodeReverseDeps node)
