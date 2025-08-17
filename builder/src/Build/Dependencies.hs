{-# LANGUAGE OverloadedStrings #-}
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
  
  -- * Helper Functions
  , processDep
  , finalizeDepsStatus
  , aggregateDepsState
  ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (MVar, readMVar, takeMVar, putMVar, newEmptyMVar)
import Control.Lens ((^.))
import qualified Canopy.Details as Details
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import Data.Map.Strict (Map, (!))
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
  aggregateDepsState root results deps [] [] [] [] False 0 lastCompile


-- | Aggregate dependency state through recursive processing.
aggregateDepsState :: FilePath -> ResultDict -> [ModuleName.Raw] -> [Dep] -> [Dep] -> [CDep] -> [(ModuleName.Raw, Import.Problem)] -> Bool -> Details.BuildID -> Details.BuildID -> IO DepsStatus
aggregateDepsState root results deps new same cached importProblems blocked lastDepChange lastCompile =
  case deps of
    [] -> finalizeDepsStatus root new same cached importProblems blocked lastDepChange lastCompile
    dep : otherDeps -> do
      result <- readMVar (results ! dep)
      state <- processDep result dep lastDepChange
      aggregateDepsState root results otherDeps
        (updateNew state new)
        (updateSame state same)
        (updateCached state cached)
        (updateProblems state importProblems)
        (updateBlocked state blocked)
        (updateLastChange state)
        lastCompile

-- | State updates for a single dependency.
data DepUpdate = DepUpdate
  { depNew :: ![Dep]
  , depSame :: ![Dep]
  , depCached :: ![CDep]
  , depProblems :: ![(ModuleName.Raw, Import.Problem)]
  , depBlocked :: !Bool
  , depLastChange :: !Details.BuildID
  }

-- | Process a single dependency result.
processDep :: Result -> ModuleName.Raw -> Details.BuildID -> IO DepUpdate
processDep result dep currentLastChange =
  case result of
    RNew (Details.Local _ _ _ _ lastChange _) iface _ _ ->
      pure $ DepUpdate [(dep, iface)] [] [] [] False (max lastChange currentLastChange)
    RSame (Details.Local _ _ _ _ lastChange _) iface _ _ ->
      pure $ DepUpdate [] [(dep, iface)] [] [] False (max lastChange currentLastChange)
    RCached _ lastChange mvar ->
      pure $ DepUpdate [] [] [(dep, mvar)] [] False (max lastChange currentLastChange)
    RNotFound prob ->
      pure $ DepUpdate [] [] [] [(dep, prob)] True currentLastChange
    RProblem _ ->
      pure $ DepUpdate [] [] [] [] True currentLastChange
    RBlocked ->
      pure $ DepUpdate [] [] [] [] True currentLastChange
    RForeign iface ->
      pure $ DepUpdate [] [(dep, iface)] [] [] False currentLastChange
    RKernel ->
      pure $ DepUpdate [] [] [] [] False currentLastChange

-- | Update functions for dependency state.
updateNew :: DepUpdate -> [Dep] -> [Dep]
updateNew state existing = depNew state ++ existing

updateSame :: DepUpdate -> [Dep] -> [Dep]
updateSame state existing = depSame state ++ existing

updateCached :: DepUpdate -> [CDep] -> [CDep]
updateCached state existing = depCached state ++ existing

updateProblems :: DepUpdate -> [(ModuleName.Raw, Import.Problem)] -> [(ModuleName.Raw, Import.Problem)]
updateProblems state existing = depProblems state ++ existing

updateBlocked :: DepUpdate -> Bool -> Bool
updateBlocked state existing = depBlocked state || existing

updateLastChange :: DepUpdate -> Details.BuildID
updateLastChange state = depLastChange state

-- | Finalize dependency status based on aggregated state.
finalizeDepsStatus :: FilePath -> [Dep] -> [Dep] -> [CDep] -> [(ModuleName.Raw, Import.Problem)] -> Bool -> Details.BuildID -> Details.BuildID -> IO DepsStatus
finalizeDepsStatus root new same cached importProblems blocked lastDepChange lastCompile =
  case reverse importProblems of
    p : ps -> pure $ DepsNotFound (NE.List p ps)
    [] -> finalizeValidDeps root new same cached blocked lastDepChange lastCompile

-- | Finalize valid dependencies without import problems.
finalizeValidDeps :: FilePath -> [Dep] -> [Dep] -> [CDep] -> Bool -> Details.BuildID -> Details.BuildID -> IO DepsStatus
finalizeValidDeps root new same cached blocked lastDepChange lastCompile
  | blocked = pure DepsBlock
  | null new && lastDepChange <= lastCompile = pure $ DepsSame same cached
  | otherwise = finalizeWithLoading root new same cached

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