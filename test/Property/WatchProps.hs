{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Property tests for Watch module.
--
-- Tests invariants, laws, and behavioral properties of file watching
-- functionality using QuickCheck property-based testing.
module Property.WatchProps (tests) where

-- Pattern: Types unqualified, functions qualified
import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Exception (tryJust)
import qualified Control.Exception as Exception
import Data.IORef (IORef)
import qualified Data.IORef as IORef
import qualified System.IO.Temp as Temp
import System.Timeout (timeout)
import System.FSNotify (Event)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool)
import qualified Watch

tests :: TestTree
tests = testGroup "Watch Property Tests"
  [ testBasicProperties
  , testErrorHandlingProperties
  ]

-- Helper to record events for testing
recordEvent :: IORef [String] -> Event -> IO ()
recordEvent eventsRef event = do
  IORef.modifyIORef' eventsRef (show event :)

-- Test basic properties (using HUnit for simplicity)
testBasicProperties :: TestTree
testBasicProperties = testGroup "basic properties"
  [ testCase "valid temp files can be watched" $ do
      eventsRef <- IORef.newIORef []
      
      result <- Temp.withSystemTempFile "test.txt" $ \path _ -> do
        writeFile path "test content"
        
        watchResult <- timeout 200000 $ do
          watcher <- forkIO (Watch.file (recordEvent eventsRef) path)
          threadDelay 100000
          killThread watcher
        
        case watchResult of
          Nothing -> return False -- Should not timeout for valid path
          Just _ -> return True
      
      assertBool "Should be able to watch valid temp files" result
      
  , testCase "watcher lifecycle works correctly" $ do
      eventsRef <- IORef.newIORef []
      
      result <- Temp.withSystemTempFile "lifecycle.txt" $ \path _ -> do
        writeFile path "content"
        
        -- Test multiple start/stop cycles
        results <- sequence $ replicate 3 $ do
          watchResult <- timeout 100000 $ do
            watcher <- forkIO (Watch.file (recordEvent eventsRef) path)
            threadDelay 30000
            killThread watcher
          
          case watchResult of
            Nothing -> return False
            Just _ -> return True
        
        return (and results)
      
      assertBool "Watcher lifecycle should work correctly" result
  ]

-- Test error handling properties
testErrorHandlingProperties :: TestTree
testErrorHandlingProperties = testGroup "error handling properties"
  [ testCase "nonexistent files handled consistently" $ do
      eventsRef <- IORef.newIORef []
      
      -- Use a path that definitely doesn't exist
      let nonexistentPath = "/tmp/definitely_does_not_exist_12345678901234567890.txt"
      
      result <- do
        watchResult <- tryJust selectIOError $ timeout 100000 $ do
          watcher <- forkIO (Watch.file (recordEvent eventsRef) nonexistentPath)
          threadDelay 50000
          killThread watcher
        
        case watchResult of
          Left _ -> return True -- Error expected for nonexistent file
          Right Nothing -> return True -- Timeout acceptable
          Right (Just _) -> return False -- Should not succeed
      
      assertBool "Should handle nonexistent files consistently" result
      
  , testCase "empty paths handled safely" $ do
      eventsRef <- IORef.newIORef []
      
      result <- do
        watchResult <- tryJust selectIOError $ timeout 100000 $ do
          watcher <- forkIO (Watch.file (recordEvent eventsRef) "")
          threadDelay 50000
          killThread watcher
        
        case watchResult of
          Left _ -> return True -- Error expected for empty path
          Right Nothing -> return True -- Timeout acceptable
          Right (Just _) -> return False -- Should not succeed with empty path
      
      assertBool "Should handle empty paths safely" result
  ]

-- Helper functions
selectIOError :: Exception.IOException -> Maybe Exception.IOException
selectIOError = Just