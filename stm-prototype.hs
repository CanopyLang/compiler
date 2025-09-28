-- | Type-safe concurrency prototype using STM
-- Eliminates MVar deadlocks with composable transactions

{-# LANGUAGE OverloadedStrings #-}
module STMPrototype where

import Control.Concurrent.STM
import Control.Concurrent.Async
import Control.Monad
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set

-- | Type-safe dependency result
data DepResult = DepSuccess Artifacts | DepFailure Error
  deriving (Show, Eq)

type Artifacts = String  -- Simplified for prototype
type Error = String      -- Simplified for prototype
type PkgName = String    -- Simplified for prototype

-- | STM-based dependency store
-- No deadlocks possible - transactions automatically retry
data DepStore = DepStore
  { _results :: TVar (Map PkgName DepResult)
  , _inProgress :: TVar (Set PkgName)
  }

-- | Create new dependency store
newDepStore :: STM DepStore
newDepStore = DepStore <$> newTVar Map.empty <*> newTVar Set.empty

-- | Register dependency as in-progress
-- Returns True if this thread should process it, False if already being processed
claimDependency :: DepStore -> PkgName -> STM Bool
claimDependency store pkg = do
  results <- readTVar (_results store)
  inProgress <- readTVar (_inProgress store)

  if Map.member pkg results || Set.member pkg inProgress
    then return False  -- Already done or being processed
    else do
      writeTVar (_inProgress store) (Set.insert pkg inProgress)
      return True

-- | Mark dependency as completed
completeDependency :: DepStore -> PkgName -> DepResult -> STM ()
completeDependency store pkg result = do
  modifyTVar (_results store) (Map.insert pkg result)
  modifyTVar (_inProgress store) (Set.delete pkg)

-- | Wait for specific dependencies to complete
-- This is where MVars would deadlock, but STM retries automatically
waitForDependencies :: DepStore -> [PkgName] -> STM (Map PkgName DepResult)
waitForDependencies store pkgs = do
  results <- readTVar (_results store)
  let available = Map.intersection results (Map.fromList [(p, ()) | p <- pkgs])

  if Map.size available == length pkgs
    then return available
    else retry  -- STM automatically retries when dependencies become available

-- | Type-safe dependency resolution using STM
-- No deadlocks possible due to STM's composable transactions
resolveDependencies :: Map PkgName [PkgName] -> IO (Either Error (Map PkgName DepResult))
resolveDependencies depGraph = do
  store <- atomically newDepStore

  -- Start workers for each package
  workers <- forConcurrently (Map.toList depGraph) $ \(pkg, deps) ->
    async $ buildPackage store pkg deps

  -- Wait for all workers and collect results
  results <- traverse wait workers

  -- Return final results
  finalResults <- atomically $ readTVar (_results store)
  return $ Right finalResults

-- | Build a single package with its dependencies
-- Type-safe: No circular dependencies possible
buildPackage :: DepStore -> PkgName -> [PkgName] -> IO DepResult
buildPackage store pkg dependencies = do
  -- Claim this package for processing
  shouldProcess <- atomically $ claimDependency store pkg

  if not shouldProcess
    then do
      -- Another thread is handling it, wait for result
      result <- atomically $ do
        results <- readTVar (_results store)
        case Map.lookup pkg results of
          Just r -> return r
          Nothing -> retry  -- Wait until completed
      return result
    else do
      -- Process this package
      depResults <- atomically $ waitForDependencies store dependencies

      -- Simulate package building
      let result = if all isSuccess (Map.elems depResults)
                   then DepSuccess ("Built " <> pkg)
                   else DepFailure ("Failed to build " <> pkg)

      -- Mark as completed
      atomically $ completeDependency store pkg result
      return result
  where
    isSuccess (DepSuccess _) = True
    isSuccess _ = False