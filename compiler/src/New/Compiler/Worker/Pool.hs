{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Parallel compilation worker pool.
--
-- This module provides a thread pool for compiling multiple modules in parallel.
-- Workers communicate via channels and track compilation progress.
--
-- == Usage Examples
--
-- @
-- import qualified New.Compiler.Worker.Pool as Pool
--
-- main :: IO ()
-- main = do
--   pool <- Pool.createPool 4  -- 4 workers
--   results <- Pool.compileModules pool tasks
--   Pool.shutdownPool pool
-- @
--
-- @since 0.19.1
module New.Compiler.Worker.Pool
  ( -- * Worker Pool
    WorkerPool,
    PoolConfig (..),
    CompileResult,

    -- * Pool Operations
    createPool,
    createPoolDefault,
    shutdownPool,

    -- * Compilation
    CompileTask (..),
    compileModules,
    compileModulesWithProgress,

    -- * Progress Tracking
    Progress (..),
    getProgress,
  )
where

import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Control.Concurrent as Concurrent
import qualified Control.Concurrent.Chan as Chan
import Control.Concurrent.Chan (Chan)
import qualified Control.Exception as Exception
import qualified Data.IORef as IORef
import Data.IORef (IORef)
import Data.Map (Map)
import qualified GHC.Conc as GHC
import qualified New.Compiler.Debug.Logger as Logger
import New.Compiler.Debug.Logger (DebugCategory (..))
import New.Compiler.Query.Simple
import qualified New.Compiler.Query.Engine as Engine
import qualified Parse.Module as Parse

-- | Worker pool configuration.
data PoolConfig = PoolConfig
  { poolConfigWorkers :: !Int,
    poolConfigQueueSize :: !Int
  }

-- | Default pool configuration.
defaultConfig :: PoolConfig
defaultConfig =
  PoolConfig
    { poolConfigWorkers = GHC.numCapabilities,
      poolConfigQueueSize = 100
    }

-- | Opaque compile result type (defined by client).
data CompileResult

-- | Compilation task for a single module.
data CompileTask = CompileTask
  { taskPackage :: !Pkg.Name,
    taskInterfaces :: !(Map ModuleName.Raw I.Interface),
    taskFilePath :: !FilePath,
    taskProjectType :: !Parse.ProjectType
  }

-- | Compilation result for a module.
data TaskResult result
  = TaskSuccess !result
  | TaskFailure !QueryError

-- | Message sent to workers.
data WorkerMessage result
  = CompileModule !CompileTask !(Chan (TaskResult result))
  | Shutdown

-- | Worker pool for parallel compilation.
data WorkerPool result = WorkerPool
  { poolWorkers :: ![Concurrent.ThreadId],
    poolQueue :: !(Chan (WorkerMessage result)),
    poolEngine :: !Engine.QueryEngine,
    poolProgress :: !(IORef Progress),
    poolCompileFn :: !(Engine.QueryEngine -> CompileTask -> IO (Either QueryError result))
  }

-- | Compilation progress.
data Progress = Progress
  { progressCompleted :: !Int,
    progressTotal :: !Int,
    progressFailed :: !Int
  }

-- | Create worker pool with default configuration.
createPoolDefault ::
  (Engine.QueryEngine -> CompileTask -> IO (Either QueryError result)) ->
  IO (WorkerPool result)
createPoolDefault = createPool defaultConfig

-- | Create worker pool with configuration.
createPool ::
  PoolConfig ->
  (Engine.QueryEngine -> CompileTask -> IO (Either QueryError result)) ->
  IO (WorkerPool result)
createPool config compileFn = do
  Logger.debug WORKER_DEBUG ("Creating worker pool with " ++ show workerCount ++ " workers")

  queue <- Chan.newChan
  engine <- Engine.initEngine
  progressRef <- IORef.newIORef (Progress 0 0 0)

  workers <- mapM (startWorker queue engine progressRef compileFn) [1 .. workerCount]

  Logger.debug WORKER_DEBUG ("Worker pool created with " ++ show (length workers) ++ " workers")

  return
    ( WorkerPool
        { poolWorkers = workers,
          poolQueue = queue,
          poolEngine = engine,
          poolProgress = progressRef,
          poolCompileFn = compileFn
        }
    )
  where
    workerCount = poolConfigWorkers config

-- | Start a single worker thread.
startWorker ::
  Chan (WorkerMessage result) ->
  Engine.QueryEngine ->
  IORef Progress ->
  (Engine.QueryEngine -> CompileTask -> IO (Either QueryError result)) ->
  Int ->
  IO Concurrent.ThreadId
startWorker queue engine progressRef compileFn workerId =
  Concurrent.forkIO (workerLoop workerId queue engine progressRef compileFn)

-- | Worker loop that processes tasks.
workerLoop ::
  Int ->
  Chan (WorkerMessage result) ->
  Engine.QueryEngine ->
  IORef Progress ->
  (Engine.QueryEngine -> CompileTask -> IO (Either QueryError result)) ->
  IO ()
workerLoop workerId queue engine progressRef compileFn = do
  Logger.debug WORKER_DEBUG ("Worker " ++ show workerId ++ " started")
  loop
  where
    loop = do
      msg <- Chan.readChan queue
      case msg of
        Shutdown -> do
          Logger.debug WORKER_DEBUG ("Worker " ++ show workerId ++ " shutting down")
        CompileModule task resultChan -> do
          handleTask workerId engine progressRef compileFn task resultChan
          loop

-- | Handle a compilation task.
handleTask ::
  Int ->
  Engine.QueryEngine ->
  IORef Progress ->
  (Engine.QueryEngine -> CompileTask -> IO (Either QueryError result)) ->
  CompileTask ->
  Chan (TaskResult result) ->
  IO ()
handleTask workerId engine progressRef compileFn task resultChan = do
  let path = taskFilePath task
  Logger.debug WORKER_DEBUG ("Worker " ++ show workerId ++ " compiling: " ++ path)

  result <- Exception.try (compileFn engine task)

  case result of
    Left (err :: Exception.SomeException) -> do
      Logger.debug WORKER_DEBUG ("Worker " ++ show workerId ++ " exception: " ++ show err)
      updateProgress progressRef False
      Chan.writeChan resultChan (TaskFailure (OtherError ("Exception: " ++ show err)))
    Right (Left queryErr) -> do
      Logger.debug WORKER_DEBUG ("Worker " ++ show workerId ++ " compile error: " ++ show queryErr)
      updateProgress progressRef False
      Chan.writeChan resultChan (TaskFailure queryErr)
    Right (Right compileResult) -> do
      Logger.debug WORKER_DEBUG ("Worker " ++ show workerId ++ " compile success: " ++ path)
      updateProgress progressRef True
      Chan.writeChan resultChan (TaskSuccess compileResult)

-- | Update progress counters.
updateProgress :: IORef Progress -> Bool -> IO ()
updateProgress progressRef success =
  IORef.atomicModifyIORef' progressRef updateFn
  where
    updateFn progress =
      if success
        then (progress {progressCompleted = progressCompleted progress + 1}, ())
        else (progress {progressCompleted = progressCompleted progress + 1, progressFailed = progressFailed progress + 1}, ())

-- | Get current progress.
getProgress :: WorkerPool result -> IO Progress
getProgress pool = IORef.readIORef (poolProgress pool)

-- | Compile multiple modules in parallel.
compileModules :: WorkerPool result -> [CompileTask] -> IO [Either QueryError result]
compileModules pool tasks = do
  Logger.debug WORKER_DEBUG ("Compiling " ++ show (length tasks) ++ " modules in parallel")

  setTotalProgress pool (length tasks)

  resultChans <- mapM (submitTask pool) tasks
  results <- mapM Chan.readChan resultChans

  Logger.debug WORKER_DEBUG ("Parallel compilation complete")

  return (map resultToEither results)
  where
    resultToEither (TaskSuccess r) = Right r
    resultToEither (TaskFailure e) = Left e

-- | Set total progress count.
setTotalProgress :: WorkerPool result -> Int -> IO ()
setTotalProgress pool total =
  IORef.atomicModifyIORef' (poolProgress pool) (\p -> (p {progressTotal = total}, ()))

-- | Submit a task to the worker pool.
submitTask :: WorkerPool result -> CompileTask -> IO (Chan (TaskResult result))
submitTask pool task = do
  resultChan <- Chan.newChan
  Chan.writeChan (poolQueue pool) (CompileModule task resultChan)
  return resultChan

-- | Compile modules with progress callback.
compileModulesWithProgress ::
  WorkerPool result ->
  [CompileTask] ->
  (Progress -> IO ()) ->
  IO [Either QueryError result]
compileModulesWithProgress pool tasks progressCallback = do
  Logger.debug WORKER_DEBUG ("Starting parallel compilation with progress tracking")

  setTotalProgress pool (length tasks)

  progressThread <- Concurrent.forkIO (progressLoop pool progressCallback)

  results <- compileModules pool tasks

  Concurrent.killThread progressThread

  return results

-- | Progress monitoring loop.
progressLoop :: WorkerPool result -> (Progress -> IO ()) -> IO ()
progressLoop pool callback = loop
  where
    loop = do
      progress <- getProgress pool
      callback progress
      if progressCompleted progress >= progressTotal progress
        then return ()
        else do
          Concurrent.threadDelay 100000 -- 100ms
          loop

-- | Shutdown the worker pool.
shutdownPool :: WorkerPool result -> IO ()
shutdownPool pool = do
  Logger.debug WORKER_DEBUG ("Shutting down worker pool with " ++ show (length (poolWorkers pool)) ++ " workers")

  mapM_ (\_ -> Chan.writeChan (poolQueue pool) Shutdown) (poolWorkers pool)

  mapM_ Concurrent.killThread (poolWorkers pool)

  Logger.debug WORKER_DEBUG "Worker pool shutdown complete"
