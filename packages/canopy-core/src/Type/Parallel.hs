{-# LANGUAGE OverloadedStrings #-}

-- | Parallel type checking across independent modules.
--
-- Orchestrates type checking of multiple modules by grouping them into
-- dependency levels and checking each level concurrently.  Modules at
-- the same level have no dependencies on each other, so their type
-- checking is naturally isolated (each invocation of 'Type.Solve.run'
-- creates fresh IORef-based pools with no shared mutable state).
--
-- == Architecture
--
-- 1. Build a dependency graph from module import relationships
-- 2. Group modules into topological levels using 'computeCheckLevels'
-- 3. For each level, type-check all modules concurrently
-- 4. After each level completes, store the resulting interfaces in a
--    shared 'InterfaceStore' backed by a 'TVar'
-- 5. Downstream modules read their dependencies' interfaces from the
--    store before beginning type checking
--
-- == Safety
--
-- The solver's mutable state (unification variable pools, mark
-- counters, error accumulators) is entirely local to each
-- 'Type.Solve.run' invocation.  The only shared state is the
-- read-mostly 'InterfaceStore', which is written once per module
-- after its type checking completes and read by downstream modules
-- before they start.
--
-- @since 0.19.2
module Type.Parallel
  ( -- * Interface Store
    InterfaceStore,
    newInterfaceStore,
    lookupInterface,
    storeInterface,
    storedInterfaces,

    -- * Parallel Type Checking
    TypeCheckResult (..),
    typeCheckLevel,
    computeCheckLevels,
    CheckLevel (..),
  )
where

import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Control.Concurrent.Async as Async
import qualified Control.Concurrent.STM as STM
import Control.Concurrent.STM (TVar)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set

-- | Thread-safe store for module interfaces produced during type checking.
--
-- Backed by a 'TVar' so that interfaces can be published atomically
-- by one thread and read by downstream threads without locks.
--
-- @since 0.19.2
newtype InterfaceStore = InterfaceStore
  { _storeVar :: TVar (Map ModuleName.Raw Interface.Interface)
  }

-- | Create a new empty interface store.
--
-- @since 0.19.2
newInterfaceStore :: IO InterfaceStore
newInterfaceStore =
  InterfaceStore <$> STM.newTVarIO Map.empty

-- | Look up a module's interface in the store.
--
-- Returns 'Nothing' if the module has not been type-checked yet.
--
-- @since 0.19.2
lookupInterface :: InterfaceStore -> ModuleName.Raw -> IO (Maybe Interface.Interface)
lookupInterface (InterfaceStore var) modName =
  Map.lookup modName <$> STM.readTVarIO var

-- | Store a module's interface after type checking completes.
--
-- Atomically inserts the interface so downstream modules can
-- read it without race conditions.
--
-- @since 0.19.2
storeInterface :: InterfaceStore -> ModuleName.Raw -> Interface.Interface -> IO ()
storeInterface (InterfaceStore var) modName iface =
  STM.atomically (STM.modifyTVar' var (Map.insert modName iface))

-- | Retrieve all stored interfaces as a snapshot.
--
-- @since 0.19.2
storedInterfaces :: InterfaceStore -> IO (Map ModuleName.Raw Interface.Interface)
storedInterfaces (InterfaceStore var) =
  STM.readTVarIO var

-- | Result of type-checking a single module.
--
-- @since 0.19.2
data TypeCheckResult e a = TypeCheckResult
  { -- | The module that was checked.
    _tcrModule :: !ModuleName.Raw,
    -- | The outcome: either errors or a successfully-typed result.
    _tcrResult :: !(Either e a)
  }
  deriving (Eq, Show)

-- | A group of modules that can be type-checked concurrently.
--
-- All modules in a level have their dependencies satisfied by
-- modules in earlier levels.
--
-- @since 0.19.2
newtype CheckLevel = CheckLevel
  { _levelModules :: [ModuleName.Raw]
  }
  deriving (Eq, Show)

-- | Type-check all modules in a single level concurrently.
--
-- The provided @checkOne@ function is called once per module in
-- the level, each in its own lightweight thread via 'Async.mapConcurrently'.
-- After all modules complete, their results are returned.
--
-- @since 0.19.2
typeCheckLevel ::
  -- | Function to type-check a single module
  (ModuleName.Raw -> IO (TypeCheckResult e a)) ->
  -- | Level to process
  CheckLevel ->
  -- | Results for every module in the level
  IO [TypeCheckResult e a]
typeCheckLevel checkOne (CheckLevel modules) =
  Async.mapConcurrently checkOne modules

-- | Compute the check levels from a set of modules and their dependencies.
--
-- Modules with no dependencies form level 0.  Modules whose
-- dependencies are all in level 0 form level 1, and so on.
-- Returns levels in order from leaves (level 0) to roots.
--
-- If the graph contains cycles, the cyclic modules will be
-- omitted from the result (they should be rejected earlier
-- in the pipeline).
--
-- @since 0.19.2
computeCheckLevels ::
  -- | Map from module name to its direct dependencies
  Map ModuleName.Raw (Set ModuleName.Raw) ->
  -- | Levels in dependency order (leaves first)
  [CheckLevel]
computeCheckLevels depMap =
  buildLevels allModules Set.empty []
  where
    allModules = Map.keysSet depMap

    buildLevels remaining processed acc
      | Set.null remaining = reverse acc
      | Set.null ready = reverse acc
      | otherwise =
          buildLevels
            (Set.difference remaining ready)
            (Set.union processed ready)
            (CheckLevel (Set.toList ready) : acc)
      where
        ready = Set.filter (allDepsReady processed) remaining

    allDepsReady processed modName =
      maybe True (internalDepsReady processed) (Map.lookup modName depMap)

    -- Only check deps that are in the dep map (internal modules).
    -- External deps (not in the map) are considered already satisfied.
    internalDepsReady processed deps =
      Set.isSubsetOf (Set.intersection deps allModules) processed
