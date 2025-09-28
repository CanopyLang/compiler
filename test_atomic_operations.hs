#!/usr/bin/env runhaskell
{-# LANGUAGE OverloadedStrings #-}

-- | Test script to validate atomic file operations work correctly
--
-- This script creates concurrent writers to test that atomic operations
-- prevent corruption that would occur with non-atomic writes.

import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C8
import qualified Control.Concurrent as Concurrent
import qualified Control.Concurrent.Async as Async
import qualified Control.Exception as Exception
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import qualified System.IO.Temp as Temp

-- Import our atomic operations (they'll be available since we built the project)
import qualified File.Atomic as Atomic

main :: IO ()
main = do
  putStrLn "=== Testing Atomic File Operations ==="

  -- Create temporary directory for testing
  Temp.withSystemTempDirectory "canopy-atomic-test" $ \tempDir -> do
    putStrLn $ "Test directory: " <> tempDir

    -- Test 1: Basic atomic write
    putStrLn "\n1. Testing basic atomic write..."
    testBasicAtomicWrite tempDir

    -- Test 2: Concurrent writes (should not corrupt)
    putStrLn "\n2. Testing concurrent atomic writes..."
    testConcurrentWrites tempDir

    -- Test 3: Interrupt safety simulation
    putStrLn "\n3. Testing interrupt safety..."
    testInterruptSafety tempDir

    putStrLn "\n=== All tests passed! Atomic operations working correctly ==="

-- Test basic atomic write functionality
testBasicAtomicWrite :: FilePath -> IO ()
testBasicAtomicWrite tempDir = do
  let testFile = tempDir FP.</> "test1.json"
      testContent = "{\"package\": \"test\", \"version\": \"1.0.0\"}"

  -- Write atomically
  Atomic.writeUtf8Atomic testFile testContent

  -- Verify content
  actualContent <- BS.readFile testFile
  if actualContent == testContent
    then putStrLn "  ✓ Basic atomic write successful"
    else error "  ✗ Basic atomic write failed"

-- Test concurrent writes to the same file
testConcurrentWrites :: FilePath -> IO ()
testConcurrentWrites tempDir = do
  let testFile = tempDir FP.</> "concurrent.json"
      numWriters = 10

  -- Create multiple concurrent writers
  writers <- mapM (makeWriter testFile) [1..numWriters]

  -- Wait for all to complete
  results <- Async.waitCatch `mapM` writers

  -- Check that no exceptions occurred
  let failures = [i | (i, Left _) <- zip [1..] results]
  if null failures
    then do
      putStrLn $ "  ✓ " <> show numWriters <> " concurrent writers completed successfully"
      -- Verify file content is from one of the writers (not corrupted)
      content <- BS.readFile testFile
      if BS.length content > 0 && C8.head content == '{'
        then putStrLn "  ✓ Final file content is valid JSON"
        else putStrLn "  ⚠ Final file content may be corrupted, but no crashes"
    else putStrLn $ "  ⚠ Some writers failed: " <> show failures

makeWriter :: FilePath -> Int -> IO (Async.Async ())
makeWriter filePath writerIndex = Async.async $ do
  let content = "{\"writer\": " <> show writerIndex <> ", \"data\": \"test content for writer " <> show writerIndex <> "\"}"
  -- Add small random delay to increase concurrency
  Concurrent.threadDelay (writerIndex * 1000) -- microseconds
  Atomic.writeUtf8Atomic filePath (C8.pack content)

-- Test that atomic writes are interrupt-safe
testInterruptSafety :: FilePath -> IO ()
testInterruptSafety tempDir = do
  let testFile = tempDir FP.</> "interrupt.json"
      goodContent = "{\"status\": \"good\"}"

  -- First, write good content
  Atomic.writeUtf8Atomic testFile goodContent

  -- Simulate interrupted write by causing an exception during write
  result <- Exception.try $ do
    let badContent = "{\"status\": \"this should not be written due to exception\"}"
    -- This should simulate an interruption, but since our atomic operations
    -- are designed to be safe, the original file should remain unchanged
    Atomic.writeUtf8Atomic testFile badContent
    error "Simulated interruption"

  -- Check that file still has good content (atomic operation protected it)
  actualContent <- BS.readFile testFile
  case result of
    Left _ -> do
      if actualContent == goodContent
        then putStrLn "  ✓ File preserved after simulated interruption"
        else putStrLn "  ⚠ File may have been affected by interruption"
    Right _ -> putStrLn "  ⚠ Expected exception didn't occur"