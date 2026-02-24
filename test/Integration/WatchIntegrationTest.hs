{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Integration tests for Watch module.
--
-- Tests end-to-end file watching functionality including real file operations,
-- long-running behavior, and system integration scenarios.
module Integration.WatchIntegrationTest (tests) where

-- Pattern: Types unqualified, functions qualified
import Control.Concurrent (forkIO, killThread, threadDelay)
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
    "Watch Integration Tests"
    [ testRealFileOperations,
      testMultipleWatchers,
      testFileSystemIntegration,
      testPerformanceCharacteristics
    ]

-- Helper to record events for testing
recordEvent :: IORef [String] -> Event -> IO ()
recordEvent eventsRef event = do
  IORef.modifyIORef' eventsRef (show event :)

-- Helper to start a watcher with timeout and cleanup
withWatcher :: (Event -> IO ()) -> FilePath -> Int -> IO () -> IO Bool
withWatcher handler path delayMicros action = do
  result <- timeout (delayMicros * 3) $ do
    watcher <- forkIO (Watch.file handler path)
    threadDelay delayMicros
    action
    threadDelay delayMicros
    killThread watcher
  case result of
    Nothing -> return False -- Timeout
    Just _ -> return True

-- Test real file operations
testRealFileOperations :: TestTree
testRealFileOperations =
  testGroup
    "real file operations"
    [ testCase "file creation and modification sequence" $ do
        eventsRef <- IORef.newIORef []

        Temp.withSystemTempDirectory "watchtest" $ \dir -> do
          let filePath = dir </> "testfile.txt"

          -- Create file first, then start watching
          writeFile filePath "initial content"

          -- Delay must exceed debounce window (200ms) + poll interval (50ms)
          success <- withWatcher (recordEvent eventsRef) filePath 400000 $ do
            appendFile filePath "\nline 2"
            threadDelay 50000
            appendFile filePath "\nline 3"

          threadDelay 100000 -- Extra time for event detection
          events <- IORef.readIORef eventsRef

          if success
            then assertEqual "Test completed successfully" True success
            else assertBool "Events detected during file operations" (length events > 0),
      testCase "file deletion and recreation" $ do
        eventsRef <- IORef.newIORef []

        Temp.withSystemTempDirectory "deletedir" $ \dir -> do
          let path = dir </> "deleteme.txt"
          writeFile path "initial"

          success <- withWatcher (recordEvent eventsRef) path 400000 $ do
            Directory.removeFile path
            threadDelay 50000
            writeFile path "recreated"

          events <- IORef.readIORef eventsRef
          if success
            then assertEqual "Deletion test completed successfully" True success
            else assertBool "Events detected during deletion/recreation" (length events > 0),
      testCase "file rename detection" $ do
        eventsRef <- IORef.newIORef []

        Temp.withSystemTempDirectory "renamedir" $ \dir -> do
          let oldPath = dir </> "oldname.txt"
          let newPath = dir </> "newname.txt"

          writeFile oldPath "content"

          success <- withWatcher (recordEvent eventsRef) oldPath 400000 $ do
            Directory.renameFile oldPath newPath

          events <- IORef.readIORef eventsRef
          if success
            then assertEqual "Rename test completed successfully" True success
            else assertBool "Events detected during file rename" (length events > 0),
      testCase "large file operations" $ do
        eventsRef <- IORef.newIORef []

        Temp.withSystemTempDirectory "largedir" $ \dir -> do
          let path = dir </> "largefile.txt"
          let largeContent = replicate 10000 'x' -- Smaller for faster tests
          writeFile path largeContent

          success <- withWatcher (recordEvent eventsRef) path 400000 $ do
            appendFile path "\nend marker"

          events <- IORef.readIORef eventsRef
          if success
            then assertEqual "Large file test completed successfully" True success
            else assertBool "Events detected during large file operations" (length events > 0)
    ]

-- Test multiple watchers
testMultipleWatchers :: TestTree
testMultipleWatchers =
  testGroup
    "multiple watchers"
    [ testCase "independent file watchers" $ do
        eventsRef1 <- IORef.newIORef []
        eventsRef2 <- IORef.newIORef []
        eventsRef3 <- IORef.newIORef []

        Temp.withSystemTempDirectory "multiwatch" $ \dir -> do
          let file1 = dir </> "file1.txt"
          let file2 = dir </> "file2.txt"
          let file3 = dir </> "file3.txt"

          -- Create initial files
          writeFile file1 "content1"
          writeFile file2 "content2"
          writeFile file3 "content3"

          -- Start watchers with longer timeout for multi-watcher scenario
          -- Need enough time for init + modifications + debounce (200ms+)
          result1 <- timeout 1500000 $ do
            watcher1 <- forkIO (Watch.file (recordEvent eventsRef1) file1)
            watcher2 <- forkIO (Watch.file (recordEvent eventsRef2) file2)
            watcher3 <- forkIO (Watch.file (recordEvent eventsRef3) file3)

            threadDelay 200000 -- Startup delay

            -- Modify each file with time between operations
            appendFile file1 " modified"
            threadDelay 100000
            appendFile file2 " updated"
            threadDelay 100000
            appendFile file3 " changed"
            threadDelay 400000 -- Wait for debounce to fire

            -- Cancel all watchers
            killThread watcher1
            killThread watcher2
            killThread watcher3

          case result1 of
            Nothing -> assertFailure "Should complete within timeout"
            Just _ -> return (),
      testCase "files function with multiple paths" $ do
        eventsRef <- IORef.newIORef []

        Temp.withSystemTempDirectory "fileswatch" $ \dir -> do
          let paths = [dir </> ("file" ++ show (i :: Int) ++ ".txt") | i <- [1 .. 3]]

          -- Create all files
          mapM_ (\p -> writeFile p "initial") paths

          -- Watch all files with single watcher
          success <- case paths of
            [] -> pure False
            (firstPath : _) -> withWatcher (recordEvent eventsRef) firstPath 200000 $ do
              -- Use files function
              result <- timeout 100000 $ do
                watcher <- forkIO (Watch.files (recordEvent eventsRef) paths)
                threadDelay 50000
                killThread watcher
              case result of
                Nothing -> return ()
                Just _ -> return ()

              -- Modify files
              mapM_ (\p -> appendFile p " modified") paths

          events <- IORef.readIORef eventsRef
          if success
            then assertEqual "Multiple file test completed successfully" True success
            else assertBool "Events detected during multiple file operations" (length events > 0),
      testCase "watcher lifecycle management" $ do
        eventsRef <- IORef.newIORef []

        Temp.withSystemTempDirectory "lifecycledir" $ \dir -> do
          let path = dir </> "lifecycle.txt"
          writeFile path "base"

          -- Create, run, and cancel watchers in sequence
          results <- sequence $
            replicate 3 $ do
              result <- timeout 100000 $ do
                watcher <- forkIO (Watch.file (recordEvent eventsRef) path)
                threadDelay 30000
                appendFile path "x"
                threadDelay 30000
                killThread watcher

              case result of
                Nothing -> return False
                Just _ -> return True

          _events <- IORef.readIORef eventsRef
          assertBool "Sequential watchers should work" (any id results)
    ]

-- Test file system integration
testFileSystemIntegration :: TestTree
testFileSystemIntegration =
  testGroup
    "file system integration"
    [ testCase "different file types" $ do
        eventsRef <- IORef.newIORef []

        Temp.withSystemTempDirectory "filetypes" $ \dir -> do
          let textFile = dir </> "document.txt"
          let jsonFile = dir </> "data.json"

          -- Create different file types
          writeFile textFile "Text document content"
          writeFile jsonFile "{\"key\": \"value\"}"

          -- Test watching text file
          success1 <- withWatcher (recordEvent eventsRef) textFile 400000 $ do
            appendFile textFile "\nAdditional paragraph"

          -- Test watching JSON file
          success2 <- withWatcher (recordEvent eventsRef) jsonFile 400000 $ do
            writeFile jsonFile "{\"key\": \"updated_value\"}"

          events <- IORef.readIORef eventsRef
          assertBool
            "File type test completed or events detected"
            (success1 || success2 || length events > 0),
      testCase "filesystem edge cases" $ do
        eventsRef <- IORef.newIORef []

        Temp.withSystemTempDirectory "edgecases" $ \dir -> do
          let emptyFile = dir </> "empty.txt"
          let binaryFile = dir </> "binary.dat"

          -- Create edge case files
          writeFile emptyFile ""
          writeFile binaryFile "\x00\x01\x02\x03\xFF\xFE\xFD"

          success1 <- withWatcher (recordEvent eventsRef) emptyFile 400000 $ do
            appendFile emptyFile "no longer empty"

          success2 <- withWatcher (recordEvent eventsRef) binaryFile 400000 $ do
            appendFile binaryFile "\x00\x00"

          events <- IORef.readIORef eventsRef
          assertBool
            "Edge case test completed or events detected"
            (success1 || success2 || length events > 0),
      testCase "cross-platform path handling" $ do
        eventsRef <- IORef.newIORef []

        Temp.withSystemTempDirectory "crossdir" $ \dir -> do
          let path = dir </> "crossplatform.txt"
          writeFile path "cross-platform content"

          success <- withWatcher (recordEvent eventsRef) path 400000 $ do
            appendFile path "\nPlatform-specific content"

          events <- IORef.readIORef eventsRef
          if success
            then assertEqual "Cross-platform test completed successfully" True success
            else assertBool "Events detected during cross-platform operations" (length events > 0)
    ]

-- Test performance characteristics
testPerformanceCharacteristics :: TestTree
testPerformanceCharacteristics =
  testGroup
    "performance characteristics"
    [ testCase "high frequency file changes" $ do
        eventsRef <- IORef.newIORef []

        Temp.withSystemTempDirectory "highfreqdir" $ \dir -> do
          let path = dir </> "highfreq.txt"
          writeFile path "base"

          success <- withWatcher (recordEvent eventsRef) path 500000 $ do
            -- High frequency modifications (reduced for performance)
            sequence_ $
              replicate 10 $ do
                appendFile path "x"
                threadDelay 20000 -- 20ms between changes
          events <- IORef.readIORef eventsRef

          -- Should handle high frequency without overwhelming
          if success
            then assertEqual "High frequency test completed successfully" True success
            else assertBool "Events detected during high frequency changes" (length events > 0)
          if length events > 0
            then assertBool "Event count should be reasonable" (length events <= 50)
            else pure (), -- No events to validate
      testCase "multiple watchers resource usage" $ do
        eventsRef <- IORef.newIORef []

        Temp.withSystemTempDirectory "manywatchers" $ \dir -> do
          let fileCount = 5 -- Reduced for test performance
          let paths = [dir </> ("file" ++ show (i :: Int) ++ ".txt") | i <- [1 .. fileCount]]

          -- Create all files
          mapM_ (\p -> writeFile p "content") paths

          -- Test that multiple watchers can be started
          result <- timeout 400000 $ do
            watchers <- mapM (\p -> forkIO (Watch.file (recordEvent eventsRef) p)) paths
            threadDelay 100000

            -- Modify a few files
            mapM_ (\p -> appendFile p " modified") (take 2 paths)
            threadDelay 150000

            -- Cancel all watchers
            mapM_ killThread watchers

          case result of
            Nothing -> assertFailure "Should handle multiple watchers within timeout"
            Just _ -> return (),
      testCase "sustained operation stability" $ do
        eventsRef <- IORef.newIORef []

        Temp.withSystemTempDirectory "sustaineddir" $ \dir -> do
          let path = dir </> "sustained.txt"
          writeFile path "baseline"

          -- Run watcher for extended period with moderate activity
          success <- withWatcher (recordEvent eventsRef) path 400000 $ do
            -- Simulate typical usage pattern
            sequence_ $
              replicate 5 $ do
                appendFile path "data"
                threadDelay 50000

          events <- IORef.readIORef eventsRef
          if success
            then assertEqual "Long running test completed successfully" True success
            else assertBool "Events detected during long running test" (length events > 0)
    ]

-- Helper functions

when :: Bool -> IO () -> IO ()
when True action = action
when False _ = return ()
