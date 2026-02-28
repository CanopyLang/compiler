{-# LANGUAGE OverloadedStrings #-}

-- | Tree-shaking metrics for dead code elimination analysis.
--
-- Provides a 'TreeShakeReport' that quantifies how many definitions
-- from the global dependency graph are actually reachable from the
-- entry points (main functions). This is useful for understanding
-- the effectiveness of dead code elimination and for reporting
-- optimization statistics to users.
--
-- == How Tree-Shaking Works
--
-- The Canopy compiler generates JavaScript by starting from the main
-- function(s) and recursively traversing the dependency graph to emit
-- only reachable definitions. Definitions that are never referenced
-- from any reachable path are simply not emitted. This module provides
-- a way to measure the result of that process without actually
-- performing code generation.
--
-- @since 0.19.2
module Generate.TreeShake
  ( -- * Report Type
    TreeShakeReport (..),

    -- * Analysis
    computeReport,
    reachableGlobals,
  )
where

import AST.Optimized.Expr (Global (..))
import qualified AST.Optimized.Graph as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set

-- | Report summarizing tree-shaking results.
--
-- All counts refer to user-defined globals in the dependency graph.
-- Kernel (runtime) definitions are excluded from the counts since
-- they are always included as needed.
--
-- @since 0.19.2
data TreeShakeReport = TreeShakeReport
  { -- | Total number of definitions in the global graph
    _tsrTotalDefs :: !Int,
    -- | Number of definitions reachable from entry points
    _tsrReachableDefs :: !Int,
    -- | Number of definitions eliminated (total - reachable)
    _tsrEliminatedDefs :: !Int
  }
  deriving (Eq, Show)

-- | Compute a tree-shaking report from a global graph and entry points.
--
-- Traverses the dependency graph starting from the given main modules
-- to determine which definitions are reachable. Returns a report with
-- total, reachable, and eliminated definition counts.
--
-- @since 0.19.2
computeReport :: Opt.GlobalGraph -> Map ModuleName.Canonical Opt.Main -> TreeShakeReport
computeReport graph mains =
  TreeShakeReport totalDefs reachableDefs eliminatedDefs
  where
    totalDefs = Map.size (Opt._g_nodes graph)
    reachable = reachableGlobals graph mains
    reachableDefs = Set.size reachable
    eliminatedDefs = totalDefs - reachableDefs

-- | Compute the set of globals reachable from the entry points.
--
-- Performs a depth-first traversal of the dependency graph starting
-- from each main function's global. Returns the set of all globals
-- encountered during the traversal.
--
-- @since 0.19.2
reachableGlobals :: Opt.GlobalGraph -> Map ModuleName.Canonical Opt.Main -> Set Global
reachableGlobals graph mains =
  Map.foldlWithKey' addMainDeps Set.empty mains
  where
    nodes = Opt._g_nodes graph

    addMainDeps seen home _main =
      addDeps (Global home (Name.fromChars "main")) seen

    addDeps global seen
      | Set.member global seen = seen
      | otherwise =
          case Map.lookup global nodes of
            Nothing -> Set.insert global seen
            Just node ->
              Set.foldl' (flip addDeps) (Set.insert global seen) (nodeDeps node)

-- | Extract the dependency set from a node.
--
-- @since 0.19.2
nodeDeps :: Opt.Node -> Set Global
nodeDeps node =
  case node of
    Opt.Define _ deps -> deps
    Opt.DefineTailFunc _ _ deps -> deps
    Opt.Ctor _ _ -> Set.empty
    Opt.Enum _ -> Set.empty
    Opt.Box -> Set.empty
    Opt.Link global -> Set.singleton global
    Opt.Cycle _ _ _ deps -> deps
    Opt.Manager _ -> Set.empty
    Opt.Kernel _ deps -> deps
    Opt.PortIncoming _ deps -> deps
    Opt.PortOutgoing _ deps -> deps
