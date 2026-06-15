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

    -- * Effect-manager glue
    managerFnDeps,
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

    addDeps global@(Global home _) seen
      | Set.member global seen = seen
      | otherwise =
          case Map.lookup global nodes of
            Nothing -> Set.insert global seen
            Just node ->
              Set.foldl' (flip addDeps) (Set.insert global seen) (depsOf home node)

    -- Effect-manager nodes (Opt.Manager) carry no deps in 'nodeDeps', but the JS
    -- emitter (generateManager) recurses into the manager's init/onEffects/onSelfMsg/
    -- cmdMap/subMap functions (see Generate.JavaScript.Kernel.generateManagerHelp).
    -- Mirror that here so those functions — and the FFI bindings they reach (e.g.
    -- Native.Module.callStreaming -> NM.callStreaming) — count as reachable. Otherwise
    -- the FFI tree-shaker (computeFFIUsage, driven by this set) drops them and the
    -- bundle throws "Cannot read property 'a' of undefined" at the first subscription.
    -- The fn-name knowledge lives in the single exported 'managerFnDeps' below so it
    -- cannot drift from the code-split walk in Generate.JavaScript.CodeSplit.Analyze.
    depsOf home node =
      case node of
        Opt.Manager effectsType -> managerFnDeps home effectsType
        _ -> nodeDeps node

-- | The globals an effect manager of each kind references through the functions
-- the JS emitter generates for it.
--
-- An @Opt.Manager@ node carries no dependencies of its own, yet
-- 'Generate.JavaScript.Kernel.generateManagerHelp' (the source of truth) emits and
-- recurses into @init@/@onEffects@/@onSelfMsg@ plus @cmdMap@ and/or @subMap@. Both
-- reachability walks — tree-shaking here and code-splitting in
-- 'Generate.JavaScript.CodeSplit.Analyze' — must mirror that emission, so this single
-- exported function is the shared source of truth for the fn-name lists. Keeping it in
-- one place stops the two walks from drifting apart and dropping TEA Cmd/Sub glue (and
-- the FFI bindings it reaches) under @--optimize@.
--
-- @since 0.20.0
managerFnDeps :: ModuleName.Canonical -> Opt.EffectsType -> Set Global
managerFnDeps home effectsType =
  Set.fromList
    [ Global home (Name.fromChars n)
    | n <- case effectsType of
             Opt.Cmd -> ["init", "onEffects", "onSelfMsg", "cmdMap"]
             Opt.Sub -> ["init", "onEffects", "onSelfMsg", "subMap"]
             Opt.Fx -> ["init", "onEffects", "onSelfMsg", "cmdMap", "subMap"]
    ]

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
    Opt.AbilityDict _ -> Set.empty
    Opt.ImplDict _ _ deps -> deps
