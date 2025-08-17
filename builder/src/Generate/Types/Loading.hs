{-# LANGUAGE BangPatterns #-}
{-# OPTIONS_GHC -Wall #-}

-- | Type extraction and loading for the Generate subsystem.
--
-- This module handles the concurrent loading and extraction of type
-- information from compiled interfaces, supporting both fresh and
-- cached modules for debug mode code generation.
--
-- The type loading process follows these phases:
--
-- @
-- Build.Module -> Extract.Types -> Merged Types -> Debug Info
-- @
--
-- === Loading Strategy
--
-- * Fresh modules: Extract types from in-memory interfaces
-- * Cached modules: Load interfaces from .canopyi files concurrently
-- * Foreign types: Extract from dependency interfaces
--
-- === Usage Examples
--
-- @
-- -- Load types for debug mode
-- types <- loadTypes root ifaces modules
-- let mode = Mode.Dev (Just types)
-- @
--
-- === Error Handling
--
-- Type loading can fail due to:
--
-- * Corrupted .canopyi files
-- * Missing cached interfaces
-- * Interface version mismatches
-- * File system errors
--
-- All errors are properly wrapped in the Task monad with
-- appropriate error types for troubleshooting.
--
-- @since 0.19.1
module Generate.Types.Loading
  ( -- * Type Loading Functions
    loadTypes
  , loadTypesHelp
  ) where

import qualified Build
import qualified Canopy.Compiler.Type.Extract as Extract
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import Control.Concurrent (MVar, forkIO, newEmptyMVar, newMVar, putMVar, readMVar)
import Data.Map (Map)
import qualified Data.Map as Map
import qualified File
import Generate.Types (Task)
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Stuff

-- | Load types from modules for debug code generation.
--
-- This function loads type information from all modules, merging
-- foreign types from dependency interfaces with local types
-- extracted from module interfaces.
--
-- === Parameters
--
-- * 'root': Root directory for the project
-- * 'ifaces': Map of dependency interfaces containing foreign types
-- * 'modules': List of modules to extract types from
--
-- === Returns
--
-- A Task containing merged Extract.Types for debug mode generation.
--
-- === Type Sources
--
-- * Dependency interfaces: Foreign types from external packages
-- * Fresh modules: Types extracted from in-memory interfaces
-- * Cached modules: Types loaded from .canopyi files
--
-- === Examples
--
-- @
-- types <- loadTypes root ifaces modules
-- let mode = Mode.Dev (Just types)
-- JS.generate mode graph mains
-- @
--
-- @since 0.19.1
loadTypes 
  :: FilePath
  -- ^ Root directory for the project
  -> Map ModuleName.Canonical I.DependencyInterface
  -- ^ Map of dependency interfaces containing foreign types
  -> [Build.Module]
  -- ^ List of modules to extract types from
  -> Task Extract.Types
  -- ^ Merged types for debug mode generation
loadTypes root ifaces modules =
  Task.eio id $ do
    mvars <- traverse (loadTypesHelp root) modules
    let !foreigns = Extract.mergeMany (Map.elems (Map.mapWithKey Extract.fromDependencyInterface ifaces))
    results <- traverse readMVar mvars
    case sequenceA results of
      Just ts -> return (Right (Extract.merge foreigns (Extract.mergeMany ts)))
      Nothing -> return (Left Exit.GenerateCannotLoadArtifacts)

-- | Load types from a single module.
--
-- This function handles type loading for a single module,
-- dispatching to the appropriate strategy based on whether
-- the module is fresh or cached.
--
-- === Parameters
--
-- * 'root': Root directory for the project
-- * 'modul': Module to extract types from
--
-- === Returns
--
-- IO action producing an MVar containing extracted types.
--
-- === Loading Strategies
--
-- * Fresh modules: Extract types from in-memory interface
-- * Cached with loaded interface: Extract from cached interface
-- * Cached with unloaded interface: Fork thread to load .canopyi file
-- * Cached with corrupted interface: Return Nothing
--
-- @since 0.19.1
loadTypesHelp 
  :: FilePath
  -- ^ Root directory for the project
  -> Build.Module
  -- ^ Module to extract types from
  -> IO (MVar (Maybe Extract.Types))
  -- ^ MVar containing extracted types
loadTypesHelp root modul =
  case modul of
    Build.Fresh name iface _ ->
      newMVar (Just (Extract.fromInterface name iface))
    Build.Cached name _ ciMVar -> do
      cachedInterface <- readMVar ciMVar
      case cachedInterface of
        Build.Unneeded -> do
          mvar <- newEmptyMVar
          _ <- forkIO $ do
            maybeIface <- File.readBinary (Stuff.canopyi root name)
            putMVar mvar (Extract.fromInterface name <$> maybeIface)
          return mvar
        Build.Loaded iface ->
          newMVar (Just (Extract.fromInterface name iface))
        Build.Corrupted ->
          newMVar Nothing