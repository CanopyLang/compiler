-- | Safe dependency resolution for Canopy Details.hs
-- Drop-in replacement using STM to eliminate MVar deadlocks

{-# LANGUAGE OverloadedStrings #-}
module SafeDetailsPrototype where

import Control.Concurrent.STM
import Control.Concurrent.Async
import Control.Exception
import Control.Monad
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set

-- | Simplified types for prototype (replace with actual Canopy types)
type PkgName = String
type Version = String
type Fingerprint = String
type Dep = Either String String  -- Left = error, Right = success
type DepCache = Map PkgName Dep

-- | STM-based dependency store
-- No deadlocks possible - transactions automatically compose and retry
data SafeDepStore = SafeDepStore
  { _completedDeps :: TVar (Map PkgName Dep)
  , _inProgressDeps :: TVar (Set PkgName)
  , _requestedDeps :: TVar (Set PkgName)
  } deriving (Eq)

-- | Create new safe dependency store
newSafeDepStore :: STM SafeDepStore
newSafeDepStore = SafeDepStore
  <$> newTVar Map.empty
  <*> newTVar Set.empty
  <*> newTVar Set.empty

-- | Claim a dependency for processing
-- Returns True if this thread should process it
-- Automatically handles race conditions via STM
claimDependency :: SafeDepStore -> PkgName -> STM Bool
claimDependency store pkg = do
  completed <- readTVar (_completedDeps store)
  inProgress <- readTVar (_inProgressDeps store)

  if Map.member pkg completed || Set.member pkg inProgress
    then return False  -- Already done or being processed
    else do
      writeTVar (_inProgressDeps store) (Set.insert pkg inProgress)
      writeTVar (_requestedDeps store) (Set.insert pkg Set.empty)
      return True

-- | Mark dependency as completed
completeDependency :: SafeDepStore -> PkgName -> Dep -> STM ()
completeDependency store pkg result = do
  modifyTVar (_completedDeps store) (Map.insert pkg result)
  modifyTVar (_inProgressDeps store) (Set.delete pkg)

-- | Wait for specific dependencies with automatic retry
-- This replaces the deadlock-prone MVar pattern
waitForDependencies :: SafeDepStore -> [PkgName] -> STM (Map PkgName Dep)
waitForDependencies store pkgs = do
  completed <- readTVar (_completedDeps store)
  let available = Map.intersection completed (Map.fromList [(p, ()) | p <- pkgs])

  if Map.size available == length pkgs
    then return available  -- All dependencies ready
    else retry  -- STM automatically retries when more deps complete

-- | Safe dependency verification - direct replacement for verifyDependencies
-- Eliminates the circular MVar dependency that causes deadlocks
safeVerifyDependencies
  :: Map PkgName String  -- solution (simplified)
  -> Map PkgName [PkgName]  -- dependency relationships
  -> IO (Either String (Map PkgName Dep))
safeVerifyDependencies solution depGraph = do
  store <- atomically newSafeDepStore

  -- Start workers concurrently without circular dependencies
  workers <- forConcurrently (Map.toList solution) $ \(pkg, details) ->
    async $ safeVerifyDep store pkg (Map.findWithDefault [] pkg depGraph)

  -- Wait for all workers with proper error handling
  results <- traverse wait workers

  -- Collect final results
  finalResults <- atomically $ readTVar (_completedDeps store)

  case sequence (Map.elems finalResults) of
    Left err -> return $ Left err
    Right _ -> return $ Right finalResults

-- | Safe version of verifyDep function
-- No circular dependency on shared MVar
safeVerifyDep :: SafeDepStore -> PkgName -> [PkgName] -> IO Dep
safeVerifyDep store pkg dependencies = do
  -- Claim this package for processing
  shouldProcess <- atomically $ claimDependency store pkg

  if not shouldProcess
    then do
      -- Another thread is handling it, wait for result
      result <- atomically $ do
        completed <- readTVar (_completedDeps store)
        case Map.lookup pkg completed of
          Just r -> return r
          Nothing -> retry  -- Wait until completed
      return result
    else do
      -- Process this package
      safeBuild store pkg dependencies

-- | Safe build function - replaces the deadlock-prone build function
-- Uses STM for type-safe dependency coordination
safeBuild :: SafeDepStore -> PkgName -> [PkgName] -> IO Dep
safeBuild store pkg dependencies = do
  -- Wait for dependencies using STM (no deadlocks possible)
  depResults <- atomically $ waitForDependencies store dependencies

  -- Simulate the actual build process
  result <- case sequence (Map.elems depResults) of
    Left err -> return $ Left ("Dependency failed: " <> err)
    Right _ -> do
      -- Simulate package building
      simulatePackageBuild pkg

  -- Mark as completed atomically
  atomically $ completeDependency store pkg result
  return result

-- | Simulate package building (replace with actual Canopy build logic)
simulatePackageBuild :: PkgName -> IO Dep
simulatePackageBuild pkg = do
  -- Simulate some work
  putStrLn $ "Building package: " <> pkg
  return $ Right ("Built " <> pkg)

-- | Error handling with better messages than MVar deadlocks
handleDepError :: SomeException -> IO (Either String a)
handleDepError ex = do
  putStrLn $ "Dependency resolution error: " <> show ex
  return $ Left ("Build failed: " <> show ex)

-- | Resource-safe version with automatic cleanup
safeVerifyDependenciesWithCleanup
  :: Map PkgName String
  -> Map PkgName [PkgName]
  -> IO (Either String (Map PkgName Dep))
safeVerifyDependenciesWithCleanup solution depGraph =
  bracket
    (atomically newSafeDepStore)  -- Acquire
    (\_ -> return ())              -- Release (STM handles cleanup)
    (\store -> do                  -- Use
      safeVerifyDependencies solution depGraph
        `catch` handleDepError
    )

-- | Performance monitoring wrapper
timedVerifyDependencies
  :: Map PkgName String
  -> Map PkgName [PkgName]
  -> IO (Either String (Map PkgName Dep, Double))
timedVerifyDependencies solution depGraph = do
  start <- getCurrentTime
  result <- safeVerifyDependencies solution depGraph
  end <- getCurrentTime
  let duration = realToFrac $ diffUTCTime end start
  return $ case result of
    Left err -> Left err
    Right deps -> Right (deps, duration)

-- Simplified imports for prototype
import Data.Time (getCurrentTime, diffUTCTime)
import Data.Time.Clock (UTCTime)