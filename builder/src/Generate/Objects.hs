{-# LANGUAGE BangPatterns #-}
{-# OPTIONS_GHC -Wall #-}

-- | Object loading and finalization for the Generate subsystem.
--
-- This module handles the concurrent loading of compiled objects from
-- the file system and their finalization into a unified object graph
-- ready for code generation.
--
-- The loading process follows these phases:
--
-- @
-- Build.Module -> LoadingObjects -> Objects -> GlobalGraph
-- @
--
-- === Loading Strategy
--
-- * Fresh modules: Use in-memory graphs directly
-- * Cached modules: Load from .canopyo files concurrently using MVars
-- * Foreign objects: Load global dependencies
--
-- === Usage Examples
--
-- @
-- -- Load objects concurrently
-- loading <- loadObjects root details modules
-- 
-- -- Finalize into unified container
-- objects <- finalizeObjects loading
-- 
-- -- Convert to global graph for generation
-- let graph = objectsToGlobalGraph objects
-- @
--
-- === Error Handling
--
-- Loading can fail due to:
--
-- * Corrupted .canopyo files
-- * Missing cached objects
-- * File system errors
-- * Concurrent access conflicts
--
-- All errors are properly wrapped in the Task monad with
-- appropriate error types for troubleshooting.
--
-- @since 0.19.1
module Generate.Objects
  ( -- * Loading Functions
    loadObjects
  , loadObject
    -- * Finalization Functions
  , finalizeObjects
  , objectsToGlobalGraph
  ) where

import qualified AST.Optimized as Opt
import qualified Build
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import Control.Concurrent (MVar, forkIO, newEmptyMVar, newMVar, putMVar, readMVar)
import Control.Lens ((^.))
import qualified Generate.Types as Types
import Control.Monad (liftM2)
import qualified Data.Map as Map
import qualified File
import Generate.Types (LoadingObjects(..), Objects(..), Task, createLoadingObjects, createObjects)
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Stuff

-- | Load objects concurrently from modules.
--
-- This function initiates concurrent loading of all module objects,
-- including both fresh in-memory graphs and cached objects from
-- the file system.
--
-- === Parameters
--
-- * 'root': Root directory for the project
-- * 'details': Project details containing foreign object information
-- * 'modules': List of modules to load
--
-- === Returns
--
-- A Task containing LoadingObjects with MVars for concurrent access.
--
-- === Examples
--
-- @
-- loading <- loadObjects root details modules
-- objects <- finalizeObjects loading
-- @
--
-- === Concurrency
--
-- Each cached module is loaded in a separate thread for optimal
-- performance. Fresh modules are available immediately.
--
-- @since 0.19.1
loadObjects 
  :: FilePath
  -- ^ Root directory for the project
  -> Details.Details
  -- ^ Project details containing foreign object information
  -> [Build.Module]
  -- ^ List of modules to load
  -> Task LoadingObjects
  -- ^ LoadingObjects with MVars for concurrent access
loadObjects root details modules =
  Task.io $ do
    mvar <- Details.loadObjects root details
    mvars <- traverse (loadObject root) modules
    return $ createLoadingObjects mvar (Map.fromList mvars)

-- | Load a single module object.
--
-- This function handles loading of a single module, dispatching
-- to the appropriate strategy based on whether the module is
-- fresh or cached.
--
-- === Parameters
--
-- * 'root': Root directory for the project
-- * 'modul': Module to load
--
-- === Returns
--
-- IO action producing a tuple of module name and MVar containing
-- the loaded local graph.
--
-- === Loading Strategies
--
-- * Fresh modules: Use in-memory graph directly
-- * Cached modules: Fork thread to load from .canopyo file
--
-- @since 0.19.1
loadObject 
  :: FilePath
  -- ^ Root directory for the project
  -> Build.Module
  -- ^ Module to load
  -> IO (ModuleName.Raw, MVar (Maybe Opt.LocalGraph))
  -- ^ Module name and MVar containing loaded graph
loadObject root modul =
  case modul of
    Build.Fresh name _ graph -> do
      mvar <- newMVar (Just graph)
      return (name, mvar)
    Build.Cached name _ _ -> do
      mvar <- newEmptyMVar
      _ <- forkIO (File.readBinary (Stuff.canopyo root name) >>= putMVar mvar)
      return (name, mvar)

-- | Finalize loading objects into a unified container.
--
-- This function waits for all concurrent loading operations to
-- complete and combines the results into a single Objects container.
--
-- === Parameters
--
-- * 'loading': LoadingObjects with MVars to finalize
--
-- === Returns
--
-- A Task containing finalized Objects ready for code generation.
--
-- === Error Conditions
--
-- Returns GenerateCannotLoadArtifacts if any loading operation fails.
--
-- === Examples
--
-- @
-- loading <- loadObjects root details modules
-- objects <- finalizeObjects loading
-- let graph = objectsToGlobalGraph objects
-- @
--
-- @since 0.19.1
finalizeObjects 
  :: LoadingObjects
  -- ^ LoadingObjects with MVars to finalize
  -> Task Objects
  -- ^ Finalized Objects ready for code generation
finalizeObjects loading =
  Task.eio id $ do
    result <- readMVar (loading ^. Types.foreign_mvarL)
    results <- traverse readMVar (loading ^. Types.local_mvarsL)
    case liftM2 createObjects result (sequenceA results) of
      Just loaded -> return (Right loaded)
      Nothing -> return (Left Exit.GenerateCannotLoadArtifacts)

-- | Convert Objects to a unified GlobalGraph.
--
-- This function combines the foreign global graph with all local
-- graphs to create a single GlobalGraph suitable for code generation.
--
-- === Parameters
--
-- * 'objects': Objects container with foreign and local graphs
--
-- === Returns
--
-- A unified GlobalGraph containing all object information.
--
-- === Examples
--
-- @
-- objects <- finalizeObjects loading
-- let graph = objectsToGlobalGraph objects
-- let mains = gatherMains pkg objects roots
-- JS.generate mode graph mains
-- @
--
-- @since 0.19.1
objectsToGlobalGraph 
  :: Objects
  -- ^ Objects container with foreign and local graphs
  -> Opt.GlobalGraph
  -- ^ Unified GlobalGraph for code generation
objectsToGlobalGraph objects =
  foldr Opt.addLocalGraph (objects ^. Types.foreignGraph) (objects ^. Types.localGraphs)