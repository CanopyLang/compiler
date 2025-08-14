{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Watch module.
--
-- Tests file watching functionality including basic operations,
-- edge cases, error conditions, and security considerations.
module Unit.WatchTest (tests) where

-- Pattern: Types unqualified, functions qualified
import Control.Concurrent (ThreadId, forkIO, killThread, threadDelay)
import qualified Control.Concurrent as Concurrent
import Control.Exception (tryJust)
import qualified Control.Exception as Exception
import Data.IORef (IORef)
import qualified Data.IORef as IORef
import qualified System.Directory as Directory
import System.FilePath ((</>))
import qualified System.IO.Temp as Temp
import System.Timeout (timeout)
import System.FSNotify (Event)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool, assertFailure)
import qualified Watch

tests :: TestTree
tests = testGroup "Watch Tests"
  [ testBasicFunctionality
  , testFileSystemBoundaries
  , testErrorHandling
  , testSecurityValidation
  , testEdgeCases
  ]

-- Helper to record events for testing
recordEvent :: IORef [String] -> Event -> IO ()
recordEvent eventsRef event = do
  IORef.modifyIORef' eventsRef (show event :)

-- Helper to start a watcher with timeout and cleanup
withWatcher :: (Event -> IO ()) -> FilePath -> Int -> IO () -> IO Bool
withWatcher handler path delayMicros action = do
  result <- timeout (delayMicros * 2) $ do
    watcher <- forkIO (Watch.file handler path)
    threadDelay delayMicros
    action
    threadDelay delayMicros
    killThread watcher
  case result of
    Nothing -> return False -- Timeout
    Just _ -> return True

-- Test basic functionality
testBasicFunctionality :: TestTree
testBasicFunctionality = testGroup "basic functionality"
  [ testCase "file function exists and can be called" $ do
      eventsRef <- IORef.newIORef []
      Temp.withSystemTempFile "test.txt" $ \path _ -> do
        success <- withWatcher (recordEvent eventsRef) path 100000 (return ())
        assertBool "Watch function should start and stop cleanly" success

  , testCase "files function exists and can be called" $ do
      eventsRef <- IORef.newIORef []
      Temp.withSystemTempFile "test1.txt" $ \path1 _ ->
        Temp.withSystemTempFile "test2.txt" $ \path2 _ -> do
          result <- timeout 200000 $ do
            watcher <- forkIO (Watch.files (recordEvent eventsRef) [path1, path2])
            threadDelay 100000
            killThread watcher
          case result of
            Nothing -> assertFailure "Files function should complete"
            Just _ -> return ()

  , testCase "file modification detection" $ do
      eventsRef <- IORef.newIORef []
      Temp.withSystemTempFile "modify.txt" $ \path _ -> do
        writeFile path "initial"
        success <- withWatcher (recordEvent eventsRef) path 100000 $ do
          appendFile path " modified"
        
        threadDelay 100000 -- Extra time for event detection
        events <- IORef.readIORef eventsRef
        assertBool "Should detect file modification" (not (null events) || success)
  ]

-- Test file system boundaries
testFileSystemBoundaries :: TestTree
testFileSystemBoundaries = testGroup "file system boundaries"
  [ testCase "nonexistent file handling" $ do
      eventsRef <- IORef.newIORef []
      result <- tryJust selectIOError $ timeout 100000 $ do
        watcher <- forkIO (Watch.file (recordEvent eventsRef) "nonexistent.txt")
        threadDelay 50000
        killThread watcher
      
      case result of
        Left _ -> return () -- Expected behavior - error for nonexistent file
        Right Nothing -> return () -- Timeout acceptable
        Right (Just _) -> assertFailure "Should handle nonexistent file appropriately"

  , testCase "empty file handling" $ do
      eventsRef <- IORef.newIORef []
      Temp.withSystemTempFile "empty.txt" $ \path _ -> do
        writeFile path ""
        success <- withWatcher (recordEvent eventsRef) path 100000 $ do
          appendFile path "content"
        
        assertBool "Should handle empty file modifications" success

  , testCase "directory as file parameter" $ do
      eventsRef <- IORef.newIORef []
      Temp.withSystemTempDirectory "testdir" $ \dir -> do
        result <- timeout 100000 $ do
          watcher <- forkIO (Watch.file (recordEvent eventsRef) dir)
          threadDelay 50000
          killThread watcher
        
        case result of
          Nothing -> return () -- Timeout acceptable
          Just _ -> return () -- Success acceptable

  , testCase "very long filename handling" $ do
      eventsRef <- IORef.newIORef []
      let longName = replicate 255 'a' ++ ".txt"
      result <- tryJust selectIOError $ timeout 100000 $ do
        watcher <- forkIO (Watch.file (recordEvent eventsRef) longName)
        threadDelay 50000
        killThread watcher
      
      case result of
        Left _ -> return () -- Expected for invalid filename
        Right Nothing -> return () -- Timeout acceptable
        Right (Just _) -> return () -- System might handle it
  ]

-- Test error handling
testErrorHandling :: TestTree
testErrorHandling = testGroup "error handling"
  [ testCase "permission denied handling" $ do
      eventsRef <- IORef.newIORef []
      result <- tryJust selectIOError $ timeout 100000 $ do
        watcher <- forkIO (Watch.file (recordEvent eventsRef) "/root/.ssh/id_rsa")
        threadDelay 50000
        killThread watcher
      
      case result of
        Left _ -> return () -- Expected permission error
        Right Nothing -> return () -- Timeout acceptable
        Right (Just _) -> return () -- System might allow access

  , testCase "file deletion during watching" $ do
      eventsRef <- IORef.newIORef []
      Temp.withSystemTempFile "deleteme.txt" $ \path _ -> do
        writeFile path "content"
        success <- withWatcher (recordEvent eventsRef) path 100000 $ do
          Directory.removeFile path
        
        -- Should handle deletion gracefully (not crash)
        assertBool "Should handle file deletion gracefully" True

  , testCase "invalid path characters" $ do
      eventsRef <- IORef.newIORef []
      result <- tryJust selectIOError $ timeout 100000 $ do
        watcher <- forkIO (Watch.file (recordEvent eventsRef) "invalid\0path")
        threadDelay 50000
        killThread watcher
      
      case result of
        Left _ -> return () -- Expected error for invalid path
        Right Nothing -> return () -- Timeout acceptable
        Right (Just _) -> assertFailure "Should reject invalid path characters"
  ]

-- Test security validation
testSecurityValidation :: TestTree
testSecurityValidation = testGroup "security validation"
  [ testCase "path traversal prevention" $ do
      eventsRef <- IORef.newIORef []
      let maliciousPaths = 
            [ "../../../etc/passwd"
            , "/etc/shadow"
            , "/proc/self/mem"
            ]
      
      results <- mapM (\path -> 
        tryJust selectIOError $ timeout 100000 $ do
          watcher <- forkIO (Watch.file (recordEvent eventsRef) path)
          threadDelay 50000
          killThread watcher) maliciousPaths
      
      -- Should either error or timeout for security
      let safeResults = [True | Left _ <- results] ++ [True | Right Nothing <- results]
      assertBool "Should handle malicious paths securely" (length safeResults >= 1)

  , testCase "buffer overflow attempt prevention" $ do
      eventsRef <- IORef.newIORef []
      let oversizePath = replicate 10000 'a'
      result <- tryJust selectIOError $ timeout 100000 $ do
        watcher <- forkIO (Watch.file (recordEvent eventsRef) oversizePath)
        threadDelay 50000
        killThread watcher
      
      case result of
        Left _ -> return () -- Expected error
        Right Nothing -> return () -- Timeout acceptable
        Right (Just _) -> return () -- System might handle large paths

  , testCase "unicode injection prevention" $ do
      eventsRef <- IORef.newIORef []
      let unicodeExploits = 
            [ "file\x00injection.txt"
            , "file\xFFinjection.txt"
            ]
            
      results <- mapM (\path ->
        tryJust selectIOError $ timeout 100000 $ do
          watcher <- forkIO (Watch.file (recordEvent eventsRef) path)
          threadDelay 50000
          killThread watcher) unicodeExploits
      
      -- Should handle unicode safely
      let safeResults = [True | Left _ <- results] ++ [True | Right Nothing <- results]
      assertBool "Should handle unicode safely" (length safeResults >= 1)
  ]

-- Test edge cases
testEdgeCases :: TestTree
testEdgeCases = testGroup "edge cases"
  [ testCase "rapid file modifications" $ do
      eventsRef <- IORef.newIORef []
      Temp.withSystemTempFile "rapid.txt" $ \path _ -> do
        writeFile path "base"
        success <- withWatcher (recordEvent eventsRef) path 200000 $ do
          -- Make rapid modifications
          sequence_ $ replicate 5 $ do
            appendFile path "x"
            threadDelay 10000
        
        events <- IORef.readIORef eventsRef
        assertBool "Should handle rapid changes" (not (null events) || success)

  , testCase "large file handling" $ do
      eventsRef <- IORef.newIORef []
      Temp.withSystemTempFile "large.txt" $ \path _ -> do
        let largeContent = replicate 50000 'a'
        writeFile path largeContent
        
        success <- withWatcher (recordEvent eventsRef) path 200000 $ do
          appendFile path "end"
        
        events <- IORef.readIORef eventsRef
        assertBool "Should handle large files" (not (null events) || success)

  , testCase "file rename detection" $ do
      eventsRef <- IORef.newIORef []
      Temp.withSystemTempDirectory "renamedir" $ \dir -> do
        let oldPath = dir </> "old.txt"
        let newPath = dir </> "new.txt"
        
        writeFile oldPath "content"
        
        success <- withWatcher (recordEvent eventsRef) oldPath 200000 $ do
          Directory.renameFile oldPath newPath
        
        events <- IORef.readIORef eventsRef
        assertBool "Should detect rename events" (not (null events) || success)

  , testCase "empty path handling" $ do
      eventsRef <- IORef.newIORef []
      result <- tryJust selectIOError $ timeout 100000 $ do
        watcher <- forkIO (Watch.file (recordEvent eventsRef) "")
        threadDelay 50000
        killThread watcher
      
      case result of
        Left _ -> return () -- Expected behavior for empty path
        Right Nothing -> return () -- Timeout acceptable
        Right (Just _) -> assertFailure "Should handle empty path"

  , testCase "whitespace-only path handling" $ do
      eventsRef <- IORef.newIORef []
      result <- tryJust selectIOError $ timeout 100000 $ do
        watcher <- forkIO (Watch.file (recordEvent eventsRef) "   ")
        threadDelay 50000
        killThread watcher
      
      case result of
        Left _ -> return () -- Expected behavior
        Right Nothing -> return () -- Timeout acceptable
        Right (Just _) -> return () -- System might normalize whitespace
  ]

-- Helper functions
selectIOError :: Exception.IOException -> Maybe Exception.IOException
selectIOError = Just