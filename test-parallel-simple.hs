{-# LANGUAGE ScopedTypeVariables #-}

-- | Simple test to verify GHC threaded runtime.
--
-- Compile with: ghc -threaded -rtsopts -O2 test-parallel-simple.hs
-- Run with: ./test-parallel-simple +RTS -N -RTS
--
module Main where

import qualified Control.Concurrent as Concurrent
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import System.IO (hFlush, stdout)

main :: IO ()
main = do
  putStrLn "=========================================="
  putStrLn "GHC THREADED RUNTIME TEST"
  putStrLn "=========================================="
  putStrLn ""

  -- Get number of capabilities (threads)
  numCapabilities <- Concurrent.getNumCapabilities
  putStrLn $ "Number of capabilities: " ++ show numCapabilities
  putStrLn ""

  if numCapabilities == 1
    then do
      putStrLn "❌ WARNING: Only 1 capability detected!"
      putStrLn ""
      putStrLn "This means GHC is NOT configured for parallel execution."
      putStrLn ""
      putStrLn "To enable parallelism:"
      putStrLn "  1. Ensure binary is compiled with: -threaded -rtsopts"
      putStrLn "  2. Run with: +RTS -N -RTS"
      putStrLn ""
      putStrLn "Example:"
      putStrLn "  ghc -threaded -rtsopts test.hs"
      putStrLn "  ./test +RTS -N4 -RTS"
      putStrLn ""
    else do
      putStrLn $ "✅ Good! GHC is using " ++ show numCapabilities ++ " capabilities"
      putStrLn "   Threaded runtime is configured correctly."
      putStrLn ""

  -- Test thread creation
  putStrLn "Testing thread creation..."
  threadId <- Concurrent.myThreadId
  putStrLn $ "Main thread ID: " ++ show threadId

  -- Create a few threads
  threads <- mapM createTestThread [1..3]
  mapM_ Concurrent.takeMVar threads

  putStrLn ""
  putStrLn "Thread creation successful!"
  putStrLn "=========================================="

-- | Create a test thread.
createTestThread :: Int -> IO (Concurrent.MVar ())
createTestThread n = do
  mvar <- Concurrent.newEmptyMVar
  _ <- Concurrent.forkIO $ do
    tid <- Concurrent.myThreadId
    putStrLn $ "Thread " ++ show n ++ " ID: " ++ show tid
    hFlush stdout
    Concurrent.threadDelay 100000  -- 100ms
    Concurrent.putMVar mvar ()
  return mvar
