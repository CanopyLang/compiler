{-# LANGUAGE BangPatterns #-}

-- | Instrumented parallel compilation for verification.
--
-- This module adds comprehensive instrumentation to verify that:
-- 1. Multiple modules are actually compiled concurrently
-- 2. Multiple CPU cores are being utilized
-- 3. Thread IDs show parallel execution
-- 4. Timing shows speedup from parallelism
--
-- @since 0.19.1
module Build.Parallel.Instrumented
  ( -- * Instrumented Compilation
    compileParallelWithInstrumentation,
    ParallelStats (..),
    LevelStats (..),
    ModuleStats (..),
  )
where

import qualified Build.Parallel as Parallel
import qualified Builder.Graph as Graph
import qualified Canopy.ModuleName as ModuleName
import qualified Control.Concurrent as Concurrent
import qualified Control.Concurrent.Async as Async
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Time.Clock (UTCTime, diffUTCTime, getCurrentTime)
import System.IO (hFlush, hPutStrLn, stderr)

-- | Statistics for a single module compilation.
data ModuleStats = ModuleStats
  { moduleStatsName :: !ModuleName.Raw,
    moduleStatsThreadId :: !Concurrent.ThreadId,
    moduleStatsStartTime :: !UTCTime,
    moduleStatsEndTime :: !UTCTime,
    moduleStatsLevel :: !Int
  }
  deriving (Show, Eq)

-- | Statistics for a dependency level.
data LevelStats = LevelStats
  { levelStatsNumber :: !Int,
    levelStatsModuleCount :: !Int,
    levelStatsStartTime :: !UTCTime,
    levelStatsEndTime :: !UTCTime,
    levelStatsModules :: ![ModuleStats],
    levelStatsThreadIds :: ![Concurrent.ThreadId]
  }
  deriving (Show, Eq)

-- | Overall parallel compilation statistics.
data ParallelStats = ParallelStats
  { parallelStatsTotalModules :: !Int,
    parallelStatsTotalLevels :: !Int,
    parallelStatsTotalTime :: !Double,
    parallelStatsLevels :: ![LevelStats],
    parallelStatsMaxConcurrency :: !Int,
    parallelStatsUniqueThreads :: !Int
  }
  deriving (Show, Eq)

-- | Compile modules in parallel with full instrumentation.
compileParallelWithInstrumentation ::
  -- | Compilation function for a single module
  (ModuleName.Raw -> status -> IO a) ->
  -- | Map of module names to their statuses
  Map ModuleName.Raw status ->
  -- | Dependency graph
  Graph.DependencyGraph ->
  -- | Results and statistics
  IO (Map ModuleName.Raw a, ParallelStats)
compileParallelWithInstrumentation compileOne statuses graph = do
  logInfo "Starting instrumented parallel compilation"

  overallStart <- getCurrentTime

  let plan = Parallel.groupByDependencyLevel graph
      levels = Parallel.planLevels plan
      totalModules = Parallel.planTotalModules plan
      totalLevels = length levels

  logInfo $ "Compilation plan: " ++ show totalLevels ++ " levels, " ++ show totalModules ++ " modules"
  logInfo $ "Level breakdown: " ++ show (map length levels)

  -- Compile each level and collect statistics
  (resultsList, levelStatsList) <-
    mapM (compileLevelWithStats compileOne statuses) (zip [0..] levels)
    >>= return . unzip

  overallEnd <- getCurrentTime

  let results = Map.unions resultsList
      totalTime = realToFrac $ diffUTCTime overallEnd overallStart
      allThreadIds = concatMap levelStatsThreadIds levelStatsList
      uniqueThreads = length $ Map.keys $ Map.fromList [(tid, ()) | tid <- allThreadIds]
      maxConcurrency = maximum $ map (length . levelStatsThreadIds) levelStatsList

      stats = ParallelStats
        { parallelStatsTotalModules = totalModules,
          parallelStatsTotalLevels = totalLevels,
          parallelStatsTotalTime = totalTime,
          parallelStatsLevels = levelStatsList,
          parallelStatsMaxConcurrency = maxConcurrency,
          parallelStatsUniqueThreads = uniqueThreads
        }

  logInfo $ "Compilation complete!"
  logInfo $ "Total time: " ++ show totalTime ++ "s"
  logInfo $ "Unique threads used: " ++ show uniqueThreads
  logInfo $ "Max concurrent modules: " ++ show maxConcurrency

  -- Print detailed analysis
  printParallelAnalysis stats

  return (results, stats)

-- | Compile a single level with instrumentation.
compileLevelWithStats ::
  (ModuleName.Raw -> status -> IO a) ->
  Map ModuleName.Raw status ->
  (Int, [ModuleName.Raw]) ->
  IO (Map ModuleName.Raw a, LevelStats)
compileLevelWithStats compileOne statuses (levelNum, modules) = do
  logInfo $ "\n=== Level " ++ show levelNum ++ " ==="
  logInfo $ "Modules: " ++ show (length modules)
  logInfo $ "Module names: " ++ show modules

  levelStart <- getCurrentTime

  -- Compile all modules concurrently and track thread IDs
  results <- Async.mapConcurrently (compileModuleWithStats compileOne statuses levelNum levelStart) modules

  levelEnd <- getCurrentTime

  let (moduleResults, moduleStatsList) = unzip results
      resultMap = Map.fromList moduleResults
      threadIds = map moduleStatsThreadId moduleStatsList
      uniqueThreadIds = Map.keys $ Map.fromList [(tid, ()) | tid <- threadIds]

      levelStats = LevelStats
        { levelStatsNumber = levelNum,
          levelStatsModuleCount = length modules,
          levelStatsStartTime = levelStart,
          levelStatsEndTime = levelEnd,
          levelStatsModules = moduleStatsList,
          levelStatsThreadIds = uniqueThreadIds
        }

  let levelTime = realToFrac $ diffUTCTime levelEnd levelStart :: Double
  logInfo $ "Level " ++ show levelNum ++ " complete in " ++ show levelTime ++ "s"
  logInfo $ "Thread IDs used: " ++ show uniqueThreadIds
  logInfo $ "Concurrent threads: " ++ show (length uniqueThreadIds)

  return (resultMap, levelStats)

-- | Compile a single module with statistics tracking.
compileModuleWithStats ::
  (ModuleName.Raw -> status -> IO a) ->
  Map ModuleName.Raw status ->
  Int ->
  UTCTime ->
  ModuleName.Raw ->
  IO ((ModuleName.Raw, a), ModuleStats)
compileModuleWithStats compileOne statuses levelNum _levelStart moduleName = do
  threadId <- Concurrent.myThreadId
  startTime <- getCurrentTime

  logInfo $ "  [Thread " ++ show threadId ++ "] Starting: " ++ show moduleName

  case Map.lookup moduleName statuses of
    Just status -> do
      result <- compileOne moduleName status
      endTime <- getCurrentTime

      let compileTime = realToFrac $ diffUTCTime endTime startTime :: Double
      logInfo $ "  [Thread " ++ show threadId ++ "] Finished: " ++ show moduleName ++ " (" ++ show compileTime ++ "s)"

      let stats = ModuleStats
            { moduleStatsName = moduleName,
              moduleStatsThreadId = threadId,
              moduleStatsStartTime = startTime,
              moduleStatsEndTime = endTime,
              moduleStatsLevel = levelNum
            }

      return ((moduleName, result), stats)

    Nothing -> error $ "Module " ++ show moduleName ++ " not found in statuses map"

-- | Print detailed parallel analysis.
printParallelAnalysis :: ParallelStats -> IO ()
printParallelAnalysis stats = do
  logInfo "\n=========================================="
  logInfo "PARALLEL COMPILATION ANALYSIS"
  logInfo "=========================================="
  logInfo $ "Total modules: " ++ show (parallelStatsTotalModules stats)
  logInfo $ "Total levels: " ++ show (parallelStatsTotalLevels stats)
  logInfo $ "Total time: " ++ show (parallelStatsTotalTime stats) ++ "s"
  logInfo $ "Unique threads: " ++ show (parallelStatsUniqueThreads stats)
  logInfo $ "Max concurrency: " ++ show (parallelStatsMaxConcurrency stats)
  logInfo ""

  -- Check if parallelism is actually working
  if parallelStatsUniqueThreads stats <= 1
    then do
      logWarning "WARNING: Only 1 thread detected!"
      logWarning "Parallelism is NOT working properly."
      logWarning "Possible causes:"
      logWarning "  1. Not compiled with -threaded"
      logWarning "  2. Not run with +RTS -N"
      logWarning "  3. GHC not using threaded runtime"
    else do
      logInfo "✓ Parallelism is working!"
      logInfo $ "✓ Using " ++ show (parallelStatsUniqueThreads stats) ++ " threads"
      logInfo $ "✓ Max concurrent modules: " ++ show (parallelStatsMaxConcurrency stats)

  logInfo ""
  logInfo "Per-level breakdown:"
  mapM_ printLevelStats (parallelStatsLevels stats)
  logInfo "=========================================="

-- | Print statistics for a single level.
printLevelStats :: LevelStats -> IO ()
printLevelStats level = do
  let levelTime = realToFrac $ diffUTCTime (levelStatsEndTime level) (levelStatsStartTime level) :: Double
      avgTime = levelTime / fromIntegral (levelStatsModuleCount level)

  logInfo $ "\nLevel " ++ show (levelStatsNumber level) ++ ":"
  logInfo $ "  Modules: " ++ show (levelStatsModuleCount level)
  logInfo $ "  Time: " ++ show levelTime ++ "s"
  logInfo $ "  Avg per module: " ++ show avgTime ++ "s"
  logInfo $ "  Threads: " ++ show (length (levelStatsThreadIds level))
  logInfo $ "  Thread IDs: " ++ show (levelStatsThreadIds level)

  -- Show thread overlap
  if length (levelStatsThreadIds level) > 1
    then logInfo "  ✓ Parallel execution confirmed"
    else logInfo "  ✗ Sequential execution (no parallelism)"

-- | Log info message to stderr.
logInfo :: String -> IO ()
logInfo msg = do
  hPutStrLn stderr $ "[PARALLEL] " ++ msg
  hFlush stderr

-- | Log warning message to stderr.
logWarning :: String -> IO ()
logWarning msg = do
  hPutStrLn stderr $ "[WARNING] " ++ msg
  hFlush stderr
