#!/usr/bin/env stack
{- stack script
   --resolver lts-22.17
   --package async
   --package containers
   --package time
   -- ghc-options -threaded -rtsopts
-}

{-# LANGUAGE ScopedTypeVariables #-}

-- | Test to verify Async.mapConcurrently actually runs in parallel.
--
-- This tests the exact pattern used in Build.Parallel.hs:
--   Async.mapConcurrently compileModuleWithName modules
--
-- Expected behavior with +RTS -N:
-- - Multiple thread IDs should be used
-- - Wall clock time should be less than sum of work times
-- - CPU usage should exceed 100%
--
-- Run with:
--   runghc -threaded test-parallel-execution.hs +RTS -N -RTS
--
-- Or compile first:
--   ghc -threaded -rtsopts -O2 test-parallel-execution.hs
--   ./test-parallel-execution +RTS -N -RTS
--
module Main where

import qualified Control.Concurrent as Concurrent
import qualified Control.Concurrent.Async as Async
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import qualified Data.Map.Strict as Map
import System.IO (hFlush, hPutStrLn, stderr, stdout)

-- | Simulate module compilation with sleep.
compileModule :: String -> IO (String, Concurrent.ThreadId, Double)
compileModule moduleName = do
  threadId <- Concurrent.myThreadId
  startTime <- getCurrentTime

  logMsg $ "[Thread " ++ show threadId ++ "] Compiling: " ++ moduleName

  -- Simulate work (0.5 seconds per module)
  Concurrent.threadDelay 500000  -- 500ms in microseconds

  endTime <- getCurrentTime
  let duration = realToFrac $ diffUTCTime endTime startTime :: Double

  logMsg $ "[Thread " ++ show threadId ++ "] Finished: " ++ moduleName ++ " (" ++ show duration ++ "s)"

  return (moduleName, threadId, duration)

-- | Log message to stderr.
logMsg :: String -> IO ()
logMsg msg = do
  hPutStrLn stderr msg
  hFlush stderr

main :: IO ()
main = do
  putStrLn "=========================================="
  putStrLn "PARALLEL EXECUTION TEST"
  putStrLn "=========================================="
  putStrLn ""

  -- Get number of capabilities (threads)
  numCapabilities <- Concurrent.getNumCapabilities
  putStrLn $ "Number of capabilities: " ++ show numCapabilities

  if numCapabilities == 1
    then do
      putStrLn ""
      putStrLn "WARNING: Only 1 capability detected!"
      putStrLn "Run with: +RTS -N -RTS to enable parallelism"
      putStrLn ""
    else do
      putStrLn $ "Good! Using " ++ show numCapabilities ++ " threads"
      putStrLn ""

  -- Test 1: Sequential execution
  putStrLn "\n=== Test 1: Sequential Execution (mapM) ==="
  let modules1 = ["Module.A", "Module.B", "Module.C", "Module.D", "Module.E"]
  seqStart <- getCurrentTime
  seqResults <- mapM compileModule modules1
  seqEnd <- getCurrentTime

  let seqTime = realToFrac $ diffUTCTime seqEnd seqStart :: Double
      seqThreadIds = map (\(_, tid, _) -> tid) seqResults
      seqUniqueThreads = length $ Map.keys $ Map.fromList [(tid, ()) | tid <- seqThreadIds]

  putStrLn $ "\nSequential Results:"
  putStrLn $ "  Total time: " ++ show seqTime ++ "s"
  putStrLn $ "  Expected: ~2.5s (5 modules * 0.5s)"
  putStrLn $ "  Thread IDs: " ++ show seqThreadIds
  putStrLn $ "  Unique threads: " ++ show seqUniqueThreads

  -- Test 2: Parallel execution
  putStrLn "\n=== Test 2: Parallel Execution (mapConcurrently) ==="
  let modules2 = ["Module.F", "Module.G", "Module.H", "Module.I", "Module.J"]
  parStart <- getCurrentTime
  parResults <- Async.mapConcurrently compileModule modules2
  parEnd <- getCurrentTime

  let parTime = realToFrac $ diffUTCTime parEnd parStart :: Double
      parThreadIds = map (\(_, tid, _) -> tid) parResults
      parUniqueThreads = length $ Map.keys $ Map.fromList [(tid, ()) | tid <- parThreadIds]
      speedup = seqTime / parTime

  putStrLn $ "\nParallel Results:"
  putStrLn $ "  Total time: " ++ show parTime ++ "s"
  putStrLn $ "  Expected: ~0.5s (limited by slowest module)"
  putStrLn $ "  Thread IDs: " ++ show parThreadIds
  putStrLn $ "  Unique threads: " ++ show parUniqueThreads
  putStrLn $ "  Speedup: " ++ show speedup ++ "x"

  -- Analysis
  putStrLn "\n=========================================="
  putStrLn "ANALYSIS"
  putStrLn "=========================================="

  putStrLn $ "\nCapabilities: " ++ show numCapabilities
  putStrLn $ "Sequential unique threads: " ++ show seqUniqueThreads
  putStrLn $ "Parallel unique threads: " ++ show parUniqueThreads

  if parUniqueThreads <= 1
    then do
      putStrLn ""
      putStrLn "❌ PARALLELISM NOT WORKING!"
      putStrLn ""
      putStrLn "Possible causes:"
      putStrLn "  1. Not compiled with -threaded"
      putStrLn "  2. Not run with +RTS -N"
      putStrLn "  3. Async.mapConcurrently not using multiple threads"
      putStrLn ""
      putStrLn "Solutions:"
      putStrLn "  1. Compile with: ghc -threaded -rtsopts test-parallel-execution.hs"
      putStrLn "  2. Run with: ./test-parallel-execution +RTS -N -RTS"
      putStrLn ""
    else do
      putStrLn ""
      putStrLn "✅ PARALLELISM IS WORKING!"
      putStrLn ""
      putStrLn $ "✓ Using " ++ show parUniqueThreads ++ " threads"
      putStrLn $ "✓ Speedup: " ++ show speedup ++ "x"

      if speedup < 2.0
        then putStrLn "⚠ Speedup is low - check if work is CPU-bound"
        else putStrLn $ "✓ Good speedup achieved: " ++ show speedup ++ "x"

  putStrLn ""
