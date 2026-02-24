{-# LANGUAGE BangPatterns #-}
{-# OPTIONS_GHC -Wall #-}

-- | Pure builder state management with single IORef.
--
-- This module implements state management for the pure builder following
-- the NEW query engine pattern. It uses:
--
-- * Single IORef for mutable state (NO MVars/TVars/STM)
-- * Pure data structures (Map, Set) for tracking
-- * Content-hash based invalidation
-- * Comprehensive debug logging
--
-- Replaces the OLD Build system's STM-based StatusDict and ResultDict
-- with pure Maps managed through a single IORef.
--
-- @since 0.19.1
module Builder.State
  ( -- * State Types
    BuilderState (..),
    BuilderEngine (..),
    ModuleStatus (..),
    ModuleResult (..),

    -- * Engine Creation
    initBuilder,
    emptyState,

    -- * State Operations
    getModuleStatus,
    setModuleStatus,
    getModuleResult,
    setModuleResult,
    getAllStatuses,
    getAllResults,
    getCompiledModules,

    -- * Statistics
    getCompletedCount,
    getPendingCount,
    getFailedCount,
  )
where

import qualified Canopy.ModuleName as ModuleName
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Time.Clock (UTCTime, getCurrentTime)
import qualified Data.Text as Text
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log

-- | Status of a module in the build process.
data ModuleStatus
  = StatusPending -- ^ Module discovered but not started
  | StatusInProgress !UTCTime -- ^ Module compilation started
  | StatusCompleted !UTCTime -- ^ Module successfully compiled
  | StatusFailed !String !UTCTime -- ^ Module compilation failed
  deriving (Show, Eq)

-- | Result of module compilation.
data ModuleResult
  = ResultPending -- ^ No result yet
  | ResultSuccess !FilePath !UTCTime -- ^ Compilation succeeded (artifacts path)
  | ResultFailure !String !UTCTime -- ^ Compilation failed (error message)
  deriving (Show, Eq)

-- | Pure builder state with no STM.
data BuilderState = BuilderState
  { builderStatuses :: !(Map ModuleName.Raw ModuleStatus),
    builderResults :: !(Map ModuleName.Raw ModuleResult),
    builderStartTime :: !UTCTime,
    builderCompletedCount :: !Int,
    builderFailedCount :: !Int
  }
  deriving (Show)

-- | Builder engine with single IORef.
newtype BuilderEngine = BuilderEngine
  { builderStateRef :: IORef BuilderState
  }

-- | Create empty builder state.
emptyState :: IO BuilderState
emptyState = do
  now <- getCurrentTime
  return
    BuilderState
      { builderStatuses = Map.empty,
        builderResults = Map.empty,
        builderStartTime = now,
        builderCompletedCount = 0,
        builderFailedCount = 0
      }

-- | Initialize a new builder engine.
initBuilder :: IO BuilderEngine
initBuilder = do
  Log.logEvent (BuildStarted (Text.pack "pure builder engine"))
  state <- emptyState
  stateRef <- newIORef state
  return (BuilderEngine stateRef)

-- | Get status of a specific module.
getModuleStatus :: BuilderEngine -> ModuleName.Raw -> IO (Maybe ModuleStatus)
getModuleStatus (BuilderEngine stateRef) moduleName = do
  state <- readIORef stateRef
  return (Map.lookup moduleName (builderStatuses state))

-- | Set status of a module.
setModuleStatus :: BuilderEngine -> ModuleName.Raw -> ModuleStatus -> IO ()
setModuleStatus (BuilderEngine stateRef) moduleName status = do
  Log.logEvent (BuildModuleQueued (Text.pack (show moduleName ++ " -> " ++ show status)))
  modifyIORef' stateRef updateStatus
  where
    updateStatus state =
      state {builderStatuses = Map.insert moduleName status (builderStatuses state)}

-- | Get result of a specific module.
getModuleResult :: BuilderEngine -> ModuleName.Raw -> IO (Maybe ModuleResult)
getModuleResult (BuilderEngine stateRef) moduleName = do
  state <- readIORef stateRef
  return (Map.lookup moduleName (builderResults state))

-- | Set result of a module.
setModuleResult :: BuilderEngine -> ModuleName.Raw -> ModuleResult -> IO ()
setModuleResult (BuilderEngine stateRef) moduleName result = do
  Log.logEvent (BuildModuleQueued (Text.pack (show moduleName)))
  modifyIORef' stateRef updateResult
  where
    updateResult state =
      let newState = state {builderResults = Map.insert moduleName result (builderResults state)}
       in case result of
            ResultSuccess _ _ ->
              newState {builderCompletedCount = builderCompletedCount state + 1}
            ResultFailure _ _ ->
              newState
                { builderFailedCount = builderFailedCount state + 1,
                  builderCompletedCount = builderCompletedCount state + 1
                }
            ResultPending -> newState

-- | Get all module statuses.
getAllStatuses :: BuilderEngine -> IO (Map ModuleName.Raw ModuleStatus)
getAllStatuses (BuilderEngine stateRef) = do
  state <- readIORef stateRef
  return (builderStatuses state)

-- | Get all module results.
getAllResults :: BuilderEngine -> IO (Map ModuleName.Raw ModuleResult)
getAllResults (BuilderEngine stateRef) = do
  state <- readIORef stateRef
  return (builderResults state)

-- | Get count of completed modules.
getCompletedCount :: BuilderEngine -> IO Int
getCompletedCount (BuilderEngine stateRef) = do
  state <- readIORef stateRef
  return (builderCompletedCount state)

-- | Get count of pending modules.
getPendingCount :: BuilderEngine -> IO Int
getPendingCount (BuilderEngine stateRef) = do
  state <- readIORef stateRef
  let pending = Map.size (Map.filter isPending (builderStatuses state))
  return pending
  where
    isPending StatusPending = True
    isPending _ = False

-- | Get count of failed modules.
getFailedCount :: BuilderEngine -> IO Int
getFailedCount (BuilderEngine stateRef) = do
  state <- readIORef stateRef
  return (builderFailedCount state)

-- | Get compiled modules with their source paths.
--
-- Returns list of (ModuleName, SourcePath) for successfully compiled modules.
-- Note: returns the source path stored during compilation, not the artifact
-- output path. The new Compiler module handles artifact path management
-- separately via 'cacheArtifactPath'.
getCompiledModules :: BuilderEngine -> IO [(ModuleName.Raw, FilePath)]
getCompiledModules (BuilderEngine stateRef) = do
  state <- readIORef stateRef
  let results = builderResults state
      successResults = Map.foldrWithKey extractSuccess [] results
  return successResults
  where
    extractSuccess modName (ResultSuccess path _) acc = (modName, path) : acc
    extractSuccess _ _ acc = acc
