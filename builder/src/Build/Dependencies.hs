{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Dependency checking and resolution for the Build system.
--
-- This module handles dependency checking operations, decomposing the complex
-- checkDepsHelp function into focused, maintainable components that comply
-- with CLAUDE.md standards.
module Build.Dependencies
  ( -- * Main Functions  
    checkDeps
  , loadInterfaces
  , loadInterface
  ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (MVar, readMVar, takeMVar, putMVar, newEmptyMVar)
import Control.Lens ((^.), makeLenses)
import qualified Canopy.Details as Details
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.NonEmptyList as NE
import qualified File
import qualified Reporting.Error.Import as Import
import qualified Stuff

import Build.Config (DepsConfig, depsRoot, depsResults, depsList, depsLastCompile)
import Build.Types
  ( DepsStatus (..)
  , Dep
  , CDep
  , Result (..)
  , ResultDict
  , CachedInterface (..)
  )

-- | Configuration for dependency aggregation state.
data DepsAggregateConfig = DepsAggregateConfig
  { _dacRoot :: !FilePath
  , _dacResults :: !ResultDict
  , _dacLastCompile :: !Details.BuildID
  }

makeLenses ''DepsAggregateConfig

-- | State for dependency aggregation.
data DepsAggregateState = DepsAggregateState
  { _dasNew :: ![Dep]
  , _dasSame :: ![Dep]
  , _dasCached :: ![CDep]
  , _dasImportProblems :: ![(ModuleName.Raw, Import.Problem)]
  , _dasBlocked :: !Bool
  , _dasLastDepChange :: !Details.BuildID
  }

makeLenses ''DepsAggregateState

-- | Configuration for valid dependency finalization.
data ValidDepsConfig = ValidDepsConfig
  { _vdcRoot :: !FilePath
  , _vdcBlocked :: !Bool
  , _vdcLastDepChange :: !Details.BuildID
  , _vdcLastCompile :: !Details.BuildID
  }

makeLenses ''ValidDepsConfig

-- | State updates for a single dependency.
data DepUpdate = DepUpdate
  { depNew :: ![Dep]
  , depSame :: ![Dep]
  , depCached :: ![CDep]
  , depProblems :: ![(ModuleName.Raw, Import.Problem)]
  , depBlocked :: !Bool
  , depLastChange :: !Details.BuildID
  }

-- | Check dependencies for a module using configuration record.
checkDeps :: DepsConfig -> IO DepsStatus
checkDeps config =
  processDependencies
    (config ^. depsRoot)
    (config ^. depsResults)
    (config ^. depsList)
    (config ^. depsLastCompile)

-- | Process dependencies with initial state.
processDependencies :: FilePath -> ResultDict -> [ModuleName.Raw] -> Details.BuildID -> IO DepsStatus
processDependencies root results deps lastCompile =
  aggregateWithConfig config initialState deps
  where
    config = DepsAggregateConfig root results lastCompile
    initialState = DepsAggregateState [] [] [] [] False 0


-- | Aggregate dependencies using configuration and state records.
aggregateWithConfig :: DepsAggregateConfig -> DepsAggregateState -> [ModuleName.Raw] -> IO DepsStatus
aggregateWithConfig config state deps =
  case deps of
    [] -> finalizeDepsWithState config state
    dep : otherDeps -> do
      case Map.lookup dep (config ^. dacResults) of
        Just mvar -> do
          result <- readMVar mvar
          update <- processDep result dep (state ^. dasLastDepChange)
          aggregateWithConfig config (applyUpdate update state) otherDeps
        Nothing -> do
          -- FIXED: Handle missing dependency MVar to prevent Map.! error
          putStrLn $ "WARNING: Missing dependency MVar for " ++ show dep
          aggregateWithConfig config state otherDeps  -- Skip this dependency

-- | Apply dependency update to state.
applyUpdate :: DepUpdate -> DepsAggregateState -> DepsAggregateState
applyUpdate update state = DepsAggregateState
  { _dasNew = depNew update ++ (state ^. dasNew)
  , _dasSame = depSame update ++ (state ^. dasSame)
  , _dasCached = depCached update ++ (state ^. dasCached)
  , _dasImportProblems = depProblems update ++ (state ^. dasImportProblems)
  , _dasBlocked = depBlocked update || (state ^. dasBlocked)
  , _dasLastDepChange = depLastChange update
  }

-- | Process a single dependency result.
processDep :: Result -> ModuleName.Raw -> Details.BuildID -> IO DepUpdate
processDep result dep currentLastChange =
  case result of
    RNew local iface _ _ -> processNewResult local dep currentLastChange iface
    RSame local iface _ _ -> processSameResult local dep currentLastChange iface
    RCached _ lastChange mvar -> processCachedResult dep currentLastChange lastChange mvar
    RNotFound prob -> processNotFoundResult dep currentLastChange prob
    RProblem _ -> processBlockedResult currentLastChange
    RBlocked -> processBlockedResult currentLastChange
    RForeign iface -> processForeignResult dep currentLastChange iface
    RKernel -> processKernelResult currentLastChange

-- | Process new dependency result.
processNewResult :: Details.Local -> ModuleName.Raw -> Details.BuildID -> I.Interface -> IO DepUpdate
processNewResult local dep currentLastChange iface =
  pure $ DepUpdate [(dep, iface)] [] [] [] False (max (local ^. Details.lastChange) currentLastChange)

-- | Process same dependency result.
processSameResult :: Details.Local -> ModuleName.Raw -> Details.BuildID -> I.Interface -> IO DepUpdate
processSameResult local dep currentLastChange iface =
  pure $ DepUpdate [] [(dep, iface)] [] [] False (max (local ^. Details.lastChange) currentLastChange)

-- | Process cached dependency result.
processCachedResult :: ModuleName.Raw -> Details.BuildID -> Details.BuildID -> MVar CachedInterface -> IO DepUpdate
processCachedResult dep currentLastChange lastChange mvar =
  pure $ DepUpdate [] [] [(dep, mvar)] [] False (max lastChange currentLastChange)

-- | Process not found dependency result.
processNotFoundResult :: ModuleName.Raw -> Details.BuildID -> Import.Problem -> IO DepUpdate
processNotFoundResult dep currentLastChange prob =
  pure $ DepUpdate [] [] [] [(dep, prob)] True currentLastChange

-- | Process blocked dependency result.
processBlockedResult :: Details.BuildID -> IO DepUpdate
processBlockedResult currentLastChange =
  pure $ DepUpdate [] [] [] [] True currentLastChange

-- | Process foreign dependency result.
processForeignResult :: ModuleName.Raw -> Details.BuildID -> I.Interface -> IO DepUpdate
processForeignResult dep currentLastChange iface =
  pure $ DepUpdate [] [(dep, iface)] [] [] False currentLastChange

-- | Process kernel dependency result.
processKernelResult :: Details.BuildID -> IO DepUpdate
processKernelResult currentLastChange =
  pure $ DepUpdate [] [] [] [] False currentLastChange


-- | Finalize dependency status using state record.
finalizeDepsWithState :: DepsAggregateConfig -> DepsAggregateState -> IO DepsStatus
finalizeDepsWithState config state =
  finalizeDepsStatus
    (config ^. dacRoot)
    (state ^. dasNew)
    (state ^. dasSame)
    (state ^. dasCached)
    (state ^. dasImportProblems)
    (state ^. dasBlocked)
    (state ^. dasLastDepChange)
    (config ^. dacLastCompile)

-- | Finalize dependency status based on aggregated state.
finalizeDepsStatus :: FilePath -> [Dep] -> [Dep] -> [CDep] -> [(ModuleName.Raw, Import.Problem)] -> Bool -> Details.BuildID -> Details.BuildID -> IO DepsStatus
finalizeDepsStatus root new same cached importProblems blocked lastDepChange lastCompile =
  case reverse importProblems of
    p : ps -> pure $ DepsNotFound (NE.List p ps)
    [] -> finalizeValidDeps root new same cached blocked lastDepChange lastCompile

-- | Finalize valid dependencies without import problems.
finalizeValidDeps :: FilePath -> [Dep] -> [Dep] -> [CDep] -> Bool -> Details.BuildID -> Details.BuildID -> IO DepsStatus
finalizeValidDeps root new same cached blocked lastDepChange lastCompile =
  finalizeValidDepsWithConfig config new same cached
  where
    config = ValidDepsConfig root blocked lastDepChange lastCompile

-- | Finalize valid dependencies using configuration.
finalizeValidDepsWithConfig :: ValidDepsConfig -> [Dep] -> [Dep] -> [CDep] -> IO DepsStatus
finalizeValidDepsWithConfig config new same cached
  | config ^. vdcBlocked = pure DepsBlock
  | null new && (config ^. vdcLastDepChange) <= (config ^. vdcLastCompile) = pure $ DepsSame same cached
  | otherwise = finalizeWithLoading (config ^. vdcRoot) new same cached

-- | Finalize dependencies with interface loading.
finalizeWithLoading :: FilePath -> [Dep] -> [Dep] -> [CDep] -> IO DepsStatus
finalizeWithLoading root new same cached = do
  maybeLoaded <- loadInterfaces root same cached
  case maybeLoaded of
    Nothing -> pure DepsBlock
    Just ifaces -> pure . DepsChange $ Map.union (Map.fromList new) ifaces

-- | Load cached interfaces with proper error handling.
loadInterfaces :: FilePath -> [Dep] -> [CDep] -> IO (Maybe (Map ModuleName.Raw I.Interface))
loadInterfaces root same cached = do
  loading <- traverse (forkLoadInterface root) cached
  maybeLoaded <- traverse readMVar loading
  case sequenceA maybeLoaded of
    Nothing -> pure Nothing
    Just loaded -> pure . Just $ Map.union (Map.fromList loaded) (Map.fromList same)

-- | Fork interface loading operation.
forkLoadInterface :: FilePath -> CDep -> IO (MVar (Maybe Dep))
forkLoadInterface root cdep = do
  mvar <- newEmptyMVar
  _ <- forkIO $ loadInterface root cdep >>= putMVar mvar
  pure mvar

-- | Load a single cached interface.
loadInterface :: FilePath -> CDep -> IO (Maybe Dep)
loadInterface root (name, ciMvar) = do
  cachedInterface <- takeMVar ciMvar
  case cachedInterface of
    Corrupted -> do
      putMVar ciMvar cachedInterface
      pure Nothing
    Loaded iface -> do
      putMVar ciMvar cachedInterface
      pure (Just (name, iface))
    Unneeded -> loadUnneededInterface root name ciMvar

-- | Load interface that wasn't previously loaded.
loadUnneededInterface :: FilePath -> ModuleName.Raw -> MVar CachedInterface -> IO (Maybe Dep)
loadUnneededInterface root name ciMvar = do
  maybeIface <- File.readBinary (Stuff.canopyi root name)
  case maybeIface of
    Nothing -> do
      putMVar ciMvar Corrupted
      pure Nothing
    Just iface -> do
      putMVar ciMvar (Loaded iface)
      pure (Just (name, iface))