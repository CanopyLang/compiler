{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Dependency cycle detection for the Canopy build system.
--
-- This module provides functionality to detect and report cyclic dependencies
-- in module graphs. It uses strongly connected components analysis to identify
-- circular dependencies that would prevent successful compilation.
--
-- === Primary Functionality
--
-- * Cycle detection in module dependency graphs ('checkForCycles')
-- * Dependency graph construction from module statuses ('addToGraph')
-- * SCC analysis for identifying circular dependencies ('checkForCyclesHelp')
--
-- === Algorithm Details
--
-- The cycle detection follows these steps:
--
-- 1. **Graph Construction**: Build dependency graph from module statuses
-- 2. **SCC Analysis**: Compute strongly connected components using Tarjan's algorithm
-- 3. **Cycle Identification**: Find SCCs with multiple elements (cycles)
-- 4. **Error Reporting**: Return first cycle found for user feedback
--
-- === Usage Examples
--
-- @
-- -- Basic cycle detection
-- case checkForCycles moduleStatuses of
--   Nothing -> putStrLn "No cycles detected"
--   Just (NE.List cycle) -> reportCyclicDependency cycle
--
-- -- Graph construction from statuses
-- let graph = Map.foldrWithKey addToGraph [] statuses
--     sccs = Graph.stronglyConnComp graph
-- @
--
-- === Dependency Graph Structure
--
-- Dependencies are extracted from module statuses:
--
-- * **Local modules**: Dependencies from module metadata
-- * **Foreign/Kernel modules**: No dependencies (external)
-- * **Failed modules**: No dependencies (to prevent cascading errors)
--
-- === Performance Characteristics
--
-- * **Time Complexity**: O(V + E) where V = modules, E = dependencies
-- * **Space Complexity**: O(V + E) for graph storage
-- * **SCC Algorithm**: Tarjan's algorithm via Data.Graph
--
-- === Thread Safety
--
-- All functions are pure and thread-safe. The module uses strict evaluation
-- to ensure predictable performance characteristics.
--
-- @since 0.19.1
module Build.Validation.Cycles
  ( -- * Cycle Detection
    checkForCycles
  , checkForCyclesHelp
    -- * Graph Construction  
  , addToGraph
  , Node
  ) where

-- Build system imports
import Build.Types (Status (..))
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName

-- Standard library imports
import Control.Lens ((^.))
import qualified Data.Graph as Graph
import qualified Data.Map.Strict as Map
import qualified Data.NonEmptyList as NE

-- | Graph node type for dependency analysis.
--
-- Represents a node in the dependency graph with the module name
-- as both key and data, plus its list of dependencies.
--
-- The triple structure follows Data.Graph conventions:
-- (nodeData, nodeKey, [dependencyKeys])
--
-- @since 0.19.1
type Node =
  (ModuleName.Raw, ModuleName.Raw, [ModuleName.Raw])

-- | Check for cyclic dependencies in module graph.
--
-- Analyzes the dependency relationships between modules to detect cycles
-- that would prevent successful compilation. Uses strongly connected
-- components analysis to identify circular dependencies.
--
-- ==== Algorithm Steps
--
-- 1. Builds dependency graph from module statuses
-- 2. Computes strongly connected components
-- 3. Identifies cycles (SCCs with multiple elements)
-- 4. Returns first cycle found for error reporting
--
-- ==== Graph Construction Rules
--
-- Dependencies are extracted based on module status:
--
-- * @'SCached' local@: Uses @local ^. Details.deps@
-- * @'SChanged' local _ _ _@: Uses @local ^. Details.deps@ 
-- * @'SBadImport' _@: No dependencies (broken import)
-- * @'SBadSyntax' {}@: No dependencies (syntax error)
-- * @'SForeign' _@: No dependencies (external module)
-- * @'SKernel'@: No dependencies (kernel module)
--
-- ==== Performance Notes
--
-- Uses strict evaluation with BangPatterns to ensure the entire graph
-- is constructed before SCC analysis begins. This prevents space leaks
-- and provides predictable performance.
--
-- @since 0.19.1
checkForCycles :: Map.Map ModuleName.Raw Status -> Maybe (NE.List ModuleName.Raw)
checkForCycles modules =
  let !graph = Map.foldrWithKey addToGraph [] modules
      !sccs = Graph.stronglyConnComp graph
   in checkForCyclesHelp sccs

-- | Process strongly connected components to find cycles.
--
-- Examines the SCC analysis results to identify the first cyclic
-- component. Acyclic components (single nodes) are ignored, and
-- empty cycles are skipped.
--
-- ==== SCC Classification
--
-- * @'Graph.AcyclicSCC' _@: Single node, no cycle - skip
-- * @'Graph.CyclicSCC' []@: Empty cycle - skip  
-- * @'Graph.CyclicSCC' (m : ms)@: Real cycle - return as NonEmptyList
--
-- ==== Error Reporting Strategy
--
-- Returns the first cycle found rather than all cycles to provide
-- focused error messages. Users can fix the first cycle and re-run
-- to find any remaining cycles.
--
-- @since 0.19.1
checkForCyclesHelp :: [Graph.SCC ModuleName.Raw] -> Maybe (NE.List ModuleName.Raw)
checkForCyclesHelp sccs =
  case sccs of
    [] ->
      Nothing
    scc : otherSccs ->
      case scc of
        Graph.AcyclicSCC _ -> checkForCyclesHelp otherSccs
        Graph.CyclicSCC [] -> checkForCyclesHelp otherSccs
        Graph.CyclicSCC (m : ms) -> Just (NE.List m ms)

-- | Add a module to the dependency graph.
--
-- Extracts dependency information from module status and creates
-- a graph node. Only modules with valid local status contribute
-- their actual dependencies to the graph.
--
-- ==== Dependency Extraction Rules
--
-- Different module statuses contribute dependencies as follows:
--
-- * **Local Modules** (@SCached@, @SChanged@): Extract from @Details.deps@
-- * **Error Modules** (@SBadImport@, @SBadSyntax@): Empty dependencies
-- * **External Modules** (@SForeign@, @SKernel@): Empty dependencies
--
-- Error modules are given empty dependency lists to prevent cascading
-- errors in cycle detection. External modules don't participate in
-- local dependency cycles.
--
-- ==== Graph Node Format
--
-- Creates a tuple @(name, name, dependencies)@ where:
--
-- * First @name@: Node data (module being analyzed)
-- * Second @name@: Node key (for graph algorithms)
-- * @dependencies@: List of dependency keys
--
-- @since 0.19.1
addToGraph :: ModuleName.Raw -> Status -> [Node] -> [Node]
addToGraph name status graph =
  let dependencies =
        case status of
          SCached local -> local ^. Details.deps
          SChanged local _ _ _ -> local ^. Details.deps
          SBadImport _ -> []
          SBadSyntax {} -> []
          SForeign _ -> []
          SKernel -> []
   in (name, name, dependencies) : graph