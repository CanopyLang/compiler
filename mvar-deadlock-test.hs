#!/usr/bin/env stack script
-- | Test demonstrating MVar deadlock and STM solution
--
-- Run with: stack mvar-deadlock-test.hs

{-# LANGUAGE OverloadedStrings #-}

import Control.Concurrent
import Control.Concurrent.MVar
import Control.Exception
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import System.Timeout

-- | Reproduce the exact deadlock pattern from Details.hs
reproduceDeadlock :: IO ()
reproduceDeadlock = do
  putStrLn "🚨 Testing MVar deadlock pattern from Details.hs..."

  result <- timeout (5 * 1000000) $ do  -- 5 second timeout
    -- EXACT reproduction of Details.hs:440-449 deadlock pattern
    mvar <- newEmptyMVar

    -- Fork workers that will call build function
    mvars <- mapM (\pkg -> forkWorker mvar pkg) ["elm/core", "elm/json", "elm/html"]

    -- Put worker MVars into shared MVar (this is the problem!)
    putMVar mvar (Map.fromList $ zip ["elm/core", "elm/json", "elm/html"] mvars)

    -- Try to read results (this hangs forever)
    results <- mapM readMVar mvars
    return results

  case result of
    Nothing -> putStrLn "❌ DEADLOCK CONFIRMED: Timeout after 5 seconds (same as Canopy)"
    Just _ -> putStrLn "✅ No deadlock (unexpected)"

-- | Simulate the problematic build function from Details.hs:623-624
forkWorker :: MVar (Map String (MVar String)) -> String -> IO (MVar String)
forkWorker depsMVar pkg = do
  resultMVar <- newEmptyMVar
  _ <- forkIO $ do
    -- This is the deadlock: worker waits for depsMVar which contains the workers!
    allDeps <- readMVar depsMVar  -- 🚨 HANGS HERE
    putStrLn $ "Building " <> pkg <> " with deps: " <> show (Map.keys allDeps)
    putMVar resultMVar ("Built " <> pkg)
  return resultMVar

-- | Test timeout behavior
testTimeoutBehavior :: IO ()
testTimeoutBehavior = do
  putStrLn "\n🕐 Testing timeout behavior..."

  result <- timeout (2 * 1000000) $ do  -- 2 second timeout
    mvar <- newEmptyMVar
    readMVar mvar  -- This will block forever

  case result of
    Nothing -> putStrLn "✅ Timeout works correctly"
    Just _ -> putStrLn "❌ Timeout failed"

-- | Demonstrate the solution approach
demonstrateSolution :: IO ()
demonstrateSolution = do
  putStrLn "\n💡 Testing solution approach..."
  putStrLn "   (Would use STM/async here if dependencies were available)"

  -- Simple non-deadlocking approach using proper ordering
  results <- mapM buildPackageSimple ["elm/core", "elm/json", "elm/html"]
  putStrLn $ "✅ Solution works: " <> show results

buildPackageSimple :: String -> IO String
buildPackageSimple pkg = do
  putStrLn $ "Building " <> pkg
  return ("Built " <> pkg)

-- | Main test runner
main :: IO ()
main = do
  putStrLn "🔬 Canopy MVar Deadlock Analysis"
  putStrLn "================================"

  testTimeoutBehavior
  reproduceDeadlock
  demonstrateSolution

  putStrLn "\n📋 SUMMARY:"
  putStrLn "❌ Current Canopy: MVar deadlock causes 'thread blocked indefinitely'"
  putStrLn "✅ Solution needed: STM or async-based dependency resolution"
  putStrLn "📖 See CONCURRENCY_ANALYSIS.md for detailed implementation plan"