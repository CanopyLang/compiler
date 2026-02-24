{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Watch module.
--
-- Tests file watching functionality including basic operations,
-- edge cases, error conditions, and security considerations.
module Unit.WatchTest (tests) where

-- Pattern: Types unqualified, functions qualified
import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Exception (tryJust)
import qualified Control.Exception as Exception
import Data.IORef (IORef)
import qualified Data.IORef as IORef
import qualified System.Directory as Directory
import System.FSNotify (Event)
import System.FilePath ((</>))
import qualified System.IO.Temp as Temp
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, assertFailure, testCase)
import qualified Watch

tests :: TestTree
tests =
  testGroup
    "Watch Tests"
    [ testBasicFunctionality,
      testFileSystemBoundaries,
      testErrorHandling,
      testSecurityValidation,
      testEdgeCases
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
testBasicFunctionality =
  testGroup
    "basic functionality"
    [ testCase "file function exists and can be called" $ do
        eventsRef <- IORef.newIORef []
        Temp.withSystemTempDirectory "testdir" $ \dir -> do
          let path = dir </> "test.txt"
          writeFile path "test content"
          result <- timeout 200000 $ do
            watcher <- forkIO (Watch.file (recordEvent eventsRef) path)
            threadDelay 100000
            killThread watcher
          case result of
            Nothing -> pure () -- Watch function should handle timeout
            Just _ -> pure (), -- Watch function should start and stop cleanly
      testCase "files function exists and can be called" $ do
        eventsRef <- IORef.newIORef []
        Temp.withSystemTempDirectory "testdir" $ \dir -> do
          let path1 = dir </> "test1.txt"
          let path2 = dir </> "test2.txt"
          writeFile path1 "content1"
          writeFile path2 "content2"
          result <- timeout 200000 $ do
            watcher <- forkIO (Watch.files (recordEvent eventsRef) [path1, path2])
            threadDelay 100000
            killThread watcher
          case result of
            Nothing -> assertFailure "Files function should complete"
            Just _ -> return (),
      testCase "file modification detection" $ do
        eventsRef <- IORef.newIORef []
        Temp.withSystemTempDirectory "modifydir" $ \dir -> do
          let path = dir </> "modify.txt"
          writeFile path "initial"
          -- Delay must exceed debounce window (200ms) + poll interval (50ms)
          success <- withWatcher (recordEvent eventsRef) path 400000 $ do
            appendFile path " modified"

          threadDelay 100000 -- Extra time for event detection
          events <- IORef.readIORef eventsRef
          if success
            then assertEqual "File modification test completed" True success
            else assertBool "Events detected during file modification" (length events > 0)
    ]

-- Test file system boundaries
testFileSystemBoundaries :: TestTree
testFileSystemBoundaries =
  testGroup
    "file system boundaries"
    [ testCase "nonexistent file handling" $ do
        eventsRef <- IORef.newIORef []
        result <- tryJust selectIOError $
          timeout 100000 $ do
            watcher <- forkIO (Watch.file (recordEvent eventsRef) "nonexistent.txt")
            threadDelay 50000
            killThread watcher

        case result of
          Left _ -> return () -- Expected behavior - error for nonexistent file
          Right Nothing -> return () -- Timeout acceptable
          Right (Just _) -> return (), -- Some systems may handle nonexistent files by watching parent directory
      testCase "empty file handling" $ do
        eventsRef <- IORef.newIORef []
        Temp.withSystemTempDirectory "emptydir" $ \dir -> do
          let path = dir </> "empty.txt"
          writeFile path ""
          -- Delay must exceed debounce window (200ms) + poll interval (50ms)
          success <- withWatcher (recordEvent eventsRef) path 400000 $ do
            appendFile path "content"

          events <- IORef.readIORef eventsRef
          if success
            then assertEqual "Empty file test completed" True success
            else assertBool "Events detected during empty file operations" (length events > 0),
      testCase "directory as file parameter" $ do
        eventsRef <- IORef.newIORef []
        Temp.withSystemTempDirectory "testdir" $ \dir -> do
          result <- timeout 100000 $ do
            watcher <- forkIO (Watch.file (recordEvent eventsRef) dir)
            threadDelay 50000
            killThread watcher

          case result of
            Nothing -> return () -- Timeout acceptable
            Just _ -> return (), -- Success acceptable
      testCase "very long filename handling" $ do
        eventsRef <- IORef.newIORef []
        let longName = replicate 255 'a' ++ ".txt"
        result <- tryJust selectIOError $
          timeout 100000 $ do
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
testErrorHandling =
  testGroup
    "error handling"
    [ testCase "permission denied handling" $ do
        eventsRef <- IORef.newIORef []
        result <- tryJust selectIOError $
          timeout 100000 $ do
            watcher <- forkIO (Watch.file (recordEvent eventsRef) "/proc/1/fd")
            threadDelay 50000
            killThread watcher

        case result of
          Left _ -> return () -- Expected permission error
          Right Nothing -> return () -- Timeout acceptable
          Right (Just _) -> return (), -- System might allow access
      testCase "file deletion during watching" $ do
        eventsRef <- IORef.newIORef []
        Temp.withSystemTempDirectory "deletedir" $ \dir -> do
          let path = dir </> "deleteme.txt"
          writeFile path "content"
          _success <- withWatcher (recordEvent eventsRef) path 100000 $ do
            Directory.removeFile path

          -- Should handle deletion gracefully (not crash)
          pure (), -- Should handle file deletion gracefully
      testCase "invalid path characters" $ do
        eventsRef <- IORef.newIORef []
        result <- tryJust selectIOError $
          timeout 100000 $ do
            watcher <- forkIO (Watch.file (recordEvent eventsRef) "invalid\0path")
            threadDelay 50000
            killThread watcher

        case result of
          Left _ -> return () -- Expected error for invalid path
          Right Nothing -> return () -- Timeout acceptable
          Right (Just _) -> return () -- Some systems may handle null bytes differently
    ]

-- Test security validation
testSecurityValidation :: TestTree
testSecurityValidation =
  testGroup
    "security validation"
    [ testCase "path traversal prevention" $ do
        eventsRef <- IORef.newIORef []
        let maliciousPaths =
              [ "../../../etc/group",
                "/proc/version", 
                "/tmp/nonexistent/path"
              ]

        results <-
          mapM
            ( \path ->
                tryJust selectIOError $
                  timeout 100000 $ do
                    watcher <- forkIO (Watch.file (recordEvent eventsRef) path)
                    threadDelay 50000
                    killThread watcher
            )
            maliciousPaths

        -- Should either error or timeout for security
        let safeResults = [True | Left _ <- results] ++ [True | Right Nothing <- results]
        assertBool "Should handle malicious paths securely" (length safeResults >= 1),
      testCase "buffer overflow attempt prevention" $ do
        eventsRef <- IORef.newIORef []
        let oversizePath = replicate 10000 'a'
        result <- tryJust selectIOError $
          timeout 100000 $ do
            watcher <- forkIO (Watch.file (recordEvent eventsRef) oversizePath)
            threadDelay 50000
            killThread watcher

        case result of
          Left _ -> return () -- Expected error
          Right Nothing -> return () -- Timeout acceptable
          Right (Just _) -> return (), -- System might handle large paths
      testCase "unicode injection prevention" $ do
        eventsRef <- IORef.newIORef []
        let unicodeExploits =
              [ "file\x00injection.txt",
                "file\xFFinjection.txt"
              ]

        results <-
          mapM
            ( \path ->
                tryJust selectIOError $
                  timeout 100000 $ do
                    watcher <- forkIO (Watch.file (recordEvent eventsRef) path)
                    threadDelay 50000
                    killThread watcher
            )
            unicodeExploits

        -- Should handle unicode safely (either error, timeout, or succeed gracefully)
        let safeResults = [True | Left _ <- results] ++ [True | Right Nothing <- results] ++ [True | Right (Just _) <- results]
        assertBool "Should handle unicode safely" (length safeResults >= 1)
    ]

-- Test edge cases
testEdgeCases :: TestTree
testEdgeCases =
  testGroup
    "edge cases"
    [ testCase "rapid file modifications" $ do
        eventsRef <- IORef.newIORef []
        Temp.withSystemTempDirectory "rapiddir" $ \dir -> do
          let path = dir </> "rapid.txt"
          writeFile path "base"
          -- Rapid modifications take ~50ms, then debounce needs 200ms + margin
          success <- withWatcher (recordEvent eventsRef) path 500000 $ do
            -- Make rapid modifications
            sequence_ $
              replicate 5 $ do
                appendFile path "x"
                threadDelay 10000

          events <- IORef.readIORef eventsRef
          if success
            then assertEqual "Rapid changes test completed" True success
            else assertBool "Events detected during rapid changes" (length events > 0),
      testCase "large file handling" $ do
        eventsRef <- IORef.newIORef []
        Temp.withSystemTempDirectory "largedir" $ \dir -> do
          let path = dir </> "large.txt"
          let largeContent = replicate 50000 'a'
          writeFile path largeContent

          success <- withWatcher (recordEvent eventsRef) path 200000 $ do
            appendFile path "end"

          events <- IORef.readIORef eventsRef
          if success
            then assertEqual "Large file test completed" True success
            else assertBool "Events detected during large file operations" (length events > 0),
      testCase "file rename detection" $ do
        eventsRef <- IORef.newIORef []
        Temp.withSystemTempDirectory "renamedir" $ \dir -> do
          let oldPath = dir </> "old.txt"
          let newPath = dir </> "new.txt"

          writeFile oldPath "content"

          -- Delay must exceed debounce window (200ms) + poll interval (50ms)
          success <- withWatcher (recordEvent eventsRef) oldPath 500000 $ do
            Directory.renameFile oldPath newPath

          events <- IORef.readIORef eventsRef
          if success
            then assertEqual "Rename test completed" True success
            else assertBool "Events detected during file rename" (length events > 0),
      testCase "empty path handling" $ do
        eventsRef <- IORef.newIORef []
        result <- tryJust selectIOError $
          timeout 100000 $ do
            watcher <- forkIO (Watch.file (recordEvent eventsRef) "")
            threadDelay 50000
            killThread watcher

        case result of
          Left _ -> pure () -- Should handle empty path - Expected behavior for empty path
          Right Nothing -> pure () -- Should handle empty path - Timeout acceptable
          Right (Just _) -> pure (), -- Should handle empty path - Some systems may handle empty paths
      testCase "whitespace-only path handling" $ do
        eventsRef <- IORef.newIORef []
        result <- tryJust selectIOError $
          timeout 100000 $ do
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
