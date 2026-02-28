{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Parallel compilation worker pool.
--
-- This module provides a thread pool for compiling multiple modules in parallel.
-- Workers communicate via channels and track compilation progress.
--
-- == Usage Examples
--
-- @
-- import qualified Worker.Pool as Pool
--
-- main :: IO ()
-- main = do
--   pool <- Pool.createPool 4  -- 4 workers
--   results <- Pool.compileModules pool tasks
--   Pool.shutdownPool pool
-- @
--
-- @since 0.19.1
module Worker.Pool
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

import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Control.Concurrent as Concurrent
import qualified Control.Concurrent.Chan as Chan
import Control.Concurrent.Chan (Chan)
import Control.Exception (IOException)
import qualified Control.Exception as Exception
import qualified Data.IORef as IORef
import Data.IORef (IORef)
import Data.Map (Map)
import qualified GHC.Conc as GHC
import qualified Data.Text as Text
import Logging.Event (LogEvent (..), Duration (..))
import qualified Logging.Logger as Log
import Query.Simple
import qualified Query.Engine as Engine
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
    taskInterfaces :: !(Map ModuleName.Raw Interface.Interface),
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
  queue <- Chan.newChan
  engine <- Engine.initEngine
  progressRef <- IORef.newIORef (Progress 0 0 0)

  workers <- mapM (startWorker queue engine progressRef compileFn) [1 .. workerCount]

  mapM_ (\wid -> Log.logEvent (WorkerSpawned wid)) [1 .. workerCount]

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
  Log.logEvent (WorkerSpawned workerId)
  loop
  where
    loop = do
      msg <- Chan.readChan queue
      case msg of
        Shutdown -> do
          Log.logEvent (WorkerCompleted workerId (Duration 0))
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
  result <- Exception.try (compileFn engine task)

  case result of
    Left (err :: Exception.IOException) -> do
      Log.logEvent (WorkerFailed workerId (Text.pack (show err)))
      updateProgress progressRef False
      Chan.writeChan resultChan (TaskFailure (OtherError ("IO exception: " ++ show err)))
    Right (Left queryErr) -> do
      Log.logEvent (WorkerFailed workerId (Text.pack (show queryErr)))
      updateProgress progressRef False
      Chan.writeChan resultChan (TaskFailure queryErr)
    Right (Right compileResult) -> do
      Log.logEvent (WorkerCompleted workerId (Duration 0))
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
  setTotalProgress pool (length tasks)

  resultChans <- mapM (submitTask pool) tasks
  results <- mapM Chan.readChan resultChans

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
  mapM_ (\_ -> Chan.writeChan (poolQueue pool) Shutdown) (poolWorkers pool)

  mapM_ Concurrent.killThread (poolWorkers pool)
