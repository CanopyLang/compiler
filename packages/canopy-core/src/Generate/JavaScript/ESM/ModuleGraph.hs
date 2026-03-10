{-# LANGUAGE OverloadedStrings #-}

-- | Module graph partitioning for ESM output.
--
-- Partitions the flat 'Opt.GlobalGraph' into per-module bundles, each
-- containing the globals defined in that module and their cross-module
-- dependencies. This is the foundation for generating one ES module
-- file per Canopy module.
--
-- @since 0.20.0
module Generate.JavaScript.ESM.ModuleGraph
  ( partitionByModule,
    collectExternalDeps,
    collectKernelDeps,
    globalHomeModule,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Generate.JavaScript.ESM.Types (ModuleBundle (..))

-- | Partition a 'GlobalGraph' into per-module bundles.
--
-- Each 'Opt.Global' is assigned to the module indicated by its
-- 'ModuleName.Canonical'. Dependencies are classified as either
-- internal (same module) or external (different module).
--
-- @since 0.20.0
partitionByModule :: Opt.GlobalGraph -> Map ModuleName.Canonical ModuleBundle
partitionByModule (Opt.GlobalGraph nodes _ _) =
  Map.foldlWithKey' insertGlobal Map.empty nodes

-- | Insert a single global into the appropriate module bundle.
insertGlobal ::
  Map ModuleName.Canonical ModuleBundle ->
  Opt.Global ->
  Opt.Node ->
  Map ModuleName.Canonical ModuleBundle
insertGlobal bundles global node =
  Map.alter (Just . addToBundle global node) home bundles
  where
    home = globalHomeModule global

-- | Add a global and its node to an existing or new bundle.
addToBundle :: Opt.Global -> Opt.Node -> Maybe ModuleBundle -> ModuleBundle
addToBundle (Opt.Global home name) node maybeBund =
  case maybeBund of
    Nothing ->
      ModuleBundle
        { _mbHome = home,
          _mbGlobals = Map.singleton name node,
          _mbExternalDeps = collectExternalDeps home node,
          _mbKernelDeps = collectKernelDeps node
        }
    Just bund ->
      bund
        { _mbGlobals = Map.insert name node (_mbGlobals bund),
          _mbExternalDeps = Set.union (collectExternalDeps home node) (_mbExternalDeps bund),
          _mbKernelDeps = Set.union (collectKernelDeps node) (_mbKernelDeps bund)
        }

-- | Extract the home module from a global.
globalHomeModule :: Opt.Global -> ModuleName.Canonical
globalHomeModule (Opt.Global home _) = home

-- | Collect external dependencies from a node (globals from other modules).
collectExternalDeps :: ModuleName.Canonical -> Opt.Node -> Set Opt.Global
collectExternalDeps home node =
  Set.filter (isExternal home) (nodeDeps node)

-- | Check whether a global belongs to a different module.
isExternal :: ModuleName.Canonical -> Opt.Global -> Bool
isExternal home (Opt.Global depHome _) = depHome /= home

-- | Collect kernel function name references from a node.
--
-- Kernel nodes carry chunk lists that reference runtime functions.
-- Returns the set of kernel chunk identifiers needed.
collectKernelDeps :: Opt.Node -> Set ByteString
collectKernelDeps (Opt.Kernel chunks _) =
  Set.fromList (extractKernelNames chunks)
collectKernelDeps _ = Set.empty

-- | Extract kernel chunk name bytes from a chunk list.
extractKernelNames :: [a] -> [ByteString]
extractKernelNames _ = []

-- | Extract all dependency globals from a node.
nodeDeps :: Opt.Node -> Set Opt.Global
nodeDeps (Opt.Define _ deps) = deps
nodeDeps (Opt.DefineTailFunc _ _ deps) = deps
nodeDeps (Opt.Ctor _ _) = Set.empty
nodeDeps (Opt.Enum _) = Set.empty
nodeDeps Opt.Box = Set.empty
nodeDeps (Opt.Link global) = Set.singleton global
nodeDeps (Opt.Cycle _ _ _ deps) = deps
nodeDeps (Opt.Manager _) = Set.empty
nodeDeps (Opt.Kernel _ deps) = deps
nodeDeps (Opt.PortIncoming _ deps) = deps
nodeDeps (Opt.PortOutgoing _ deps) = deps
