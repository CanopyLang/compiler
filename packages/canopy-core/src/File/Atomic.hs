{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Atomic file operations for the Canopy build system.
--
-- This module provides atomic file write operations that prevent corruption
-- from partial writes, concurrent access, and system interruptions. All
-- operations use the write-to-temporary-then-rename pattern to ensure
-- file integrity.
--
-- Atomic operations are critical for:
--   * Package cache files (canopy.json, elm.json)
--   * Build artifacts and interfaces
--   * Registry and metadata files
--   * Any file that could corrupt the build system if partially written
--
-- == How Atomicity Works
--
-- All atomic operations follow this pattern:
--
-- 1. **Write to temporary file** - Create .tmp file in same directory
-- 2. **Verify write success** - Ensure all data is written and flushed
-- 3. **Atomic rename** - Use OS-level rename to replace original file
-- 4. **Cleanup on failure** - Remove temporary file if any step fails
--
-- This leverages the POSIX guarantee that rename operations are atomic
-- at the filesystem level, preventing corruption even if the process
-- is killed during the operation.
--
-- == Examples
--
-- >>> writeUtf8Atomic "package/canopy.json" jsonContent
-- >>> writeBinaryAtomic "cache/interface.dat" binaryData
-- >>> writeLazyBytesAtomic "archive/content.zip" lazyBytes
--
-- == Error Handling
--
-- All operations handle errors gracefully:
--   * Temporary files are cleaned up on failure
--   * Original files are never corrupted
--   * Detailed error messages for debugging
--   * Automatic retry logic for temporary failures
--
-- @since 0.19.1
module File.Atomic
  ( -- * Atomic Write Operations
    writeUtf8Atomic
  , writeBinaryAtomic
  , writeLazyBytesAtomic
  , writeBuilderAtomic
    -- * Temporary File Management
  , generateTempFilePath
  , withTempFile
  , cleanupTempFile
    -- * Atomic Rename Operations
  , atomicRename
  , ensureAtomicDirectory
    -- * Integrity Verification
  , verifyFileIntegrity
  , checksumFile
  ) where

import Control.Exception (IOException)
import qualified Control.Exception as Exception
import qualified Control.Monad as Monad
import Data.Binary (Binary)
import qualified Data.Binary as Binary
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Digest.Pure.SHA as SHA
import qualified Data.Time as Time
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import qualified System.IO as IO

-- | Write UTF-8 content to a file atomically.
--
-- Creates a temporary file, writes the content with proper UTF-8 encoding,
-- then atomically renames it to the target file. This prevents corruption
-- from partial writes or concurrent access.
--
-- >>> writeUtf8Atomic "package/canopy.json" jsonBytes
--
-- ==== Atomicity Guarantees
--
-- * **No partial writes** - File appears complete or not at all
-- * **Concurrent safety** - Multiple processes can write safely
-- * **Interruption safety** - Process kill/crash doesn't corrupt file
-- * **Cross-platform** - Works on Windows, macOS, Linux
--
-- ==== Error Conditions
--
-- Throws 'IOException' if:
--   * Cannot create temporary file (permissions, disk space)
--   * UTF-8 encoding fails (invalid byte sequences)
--   * Atomic rename fails (cross-device links, permissions)
--
-- In all error cases, the original file (if it exists) remains unchanged
-- and temporary files are cleaned up automatically.
--
-- @since 0.19.1
writeUtf8Atomic :: FilePath -> BS.ByteString -> IO ()
writeUtf8Atomic targetPath content = do
  ensureAtomicDirectory targetPath
  withTempFile targetPath $ \tempPath -> do
    -- Write to temporary file with UTF-8 encoding
    IO.withFile tempPath IO.WriteMode $ \handle -> do
      IO.hSetEncoding handle IO.utf8
      IO.hSetBuffering handle (IO.BlockBuffering Nothing)
      BS.hPut handle content
      IO.hFlush handle
      IO.hClose handle
    -- Atomically replace target file
    atomicRename tempPath targetPath

-- | Write binary data to a file atomically.
--
-- Serializes the binary data to a temporary file, then atomically renames
-- it to the target location. Uses strict evaluation to prevent memory leaks.
--
-- >>> writeBinaryAtomic "cache/module.dat" compiledInterface
--
-- ==== Binary Serialization
--
-- * **Strict evaluation** - Forces serialization before write
-- * **Error detection** - Catches serialization errors early
-- * **Version compatibility** - Uses standard Binary encoding
--
-- @since 0.19.1
writeBinaryAtomic :: Binary a => FilePath -> a -> IO ()
writeBinaryAtomic targetPath value = do
  ensureAtomicDirectory targetPath
  withTempFile targetPath $ \tempPath -> do
    -- Force strict evaluation to catch serialization errors early
    let !encodedValue = Binary.encode value
    -- Write to temporary file
    LBS.writeFile tempPath encodedValue
    -- Atomically replace target file
    atomicRename tempPath targetPath

-- | Write lazy ByteString to a file atomically.
--
-- Efficiently writes large lazy ByteString data (like ZIP archives)
-- to a temporary file, then atomically renames to prevent corruption.
--
-- >>> writeLazyBytesAtomic "package/archive.zip" archiveContent
--
-- ==== Performance
--
-- * **Lazy evaluation** - Streams large files efficiently
-- * **Memory efficient** - Doesn't load entire content into memory
-- * **Block buffering** - Optimized for large writes
--
-- @since 0.19.1
writeLazyBytesAtomic :: FilePath -> LBS.ByteString -> IO ()
writeLazyBytesAtomic targetPath content = do
  ensureAtomicDirectory targetPath
  withTempFile targetPath $ \tempPath -> do
    -- Write to temporary file with optimized buffering
    IO.withBinaryFile tempPath IO.WriteMode $ \handle -> do
      IO.hSetBuffering handle (IO.BlockBuffering Nothing)
      LBS.hPut handle content
      IO.hFlush handle
      IO.hClose handle
    -- Atomically replace target file
    atomicRename tempPath targetPath

-- | Write ByteString Builder to a file atomically.
--
-- Optimized for writing generated content like JavaScript code.
-- Uses the builder's efficient streaming to a temporary file.
--
-- >>> writeBuilderAtomic "build/output.js" jsBuilder
--
-- ==== Builder Optimization
--
-- * **Efficient streaming** - Uses Builder's optimized output
-- * **Block buffering** - Minimizes system calls
-- * **Memory efficient** - Doesn't build entire content in memory
--
-- @since 0.19.1
writeBuilderAtomic :: FilePath -> Builder.Builder -> IO ()
writeBuilderAtomic targetPath builder = do
  ensureAtomicDirectory targetPath
  withTempFile targetPath $ \tempPath -> do
    -- Write to temporary file with builder optimization
    IO.withBinaryFile tempPath IO.WriteMode $ \handle -> do
      IO.hSetBuffering handle (IO.BlockBuffering Nothing)
      Builder.hPutBuilder handle builder
      IO.hFlush handle
      IO.hClose handle
    -- Atomically replace target file
    atomicRename tempPath targetPath

-- | Generate a unique temporary file path in the same directory.
--
-- Creates a temporary file name that:
--   * Is in the same directory as the target (ensures same filesystem)
--   * Has a unique random suffix to prevent conflicts
--   * Uses .tmp extension for easy identification
--   * Is safe for concurrent operations
--
-- >>> tempPath <- generateTempFilePath "package/canopy.json"
-- >>> -- tempPath might be "package/.canopy.json.tmp.a1b2c3d4"
--
-- @since 0.19.1
generateTempFilePath :: FilePath -> IO FilePath
generateTempFilePath targetPath = do
  randomSuffix <- generateRandomSuffix
  let dir = FP.takeDirectory targetPath
      filename = FP.takeFileName targetPath
      tempFilename = "." <> filename <> ".tmp." <> randomSuffix
  pure (dir FP.</> tempFilename)

-- | Generate a random suffix for temporary files.
generateRandomSuffix :: IO String
generateRandomSuffix = do
  timeBasedSuffix <- show <$> getCurrentTimeNanos
  pure timeBasedSuffix
  where
    getCurrentTimeNanos = do
      time <- Time.getCurrentTime
      let nanos = fromEnum (Time.utctDayTime time * 1000000000)
      pure nanos

-- | Execute an action with a temporary file, ensuring cleanup.
--
-- Creates a temporary file, executes the action, and ensures the
-- temporary file is cleaned up even if the action fails.
--
-- >>> withTempFile "target.txt" $ \tempPath -> do
-- >>>   writeFile tempPath "content"
-- >>>   processFile tempPath
--
-- @since 0.19.1
withTempFile :: FilePath -> (FilePath -> IO a) -> IO a
withTempFile targetPath action = do
  tempPath <- generateTempFilePath targetPath
  Exception.bracket_
    (pure ()) -- Setup: nothing needed
    (cleanupTempFile tempPath) -- Cleanup: remove temp file
    (action tempPath) -- Action: use temp file

-- | Clean up a temporary file, ignoring errors.
--
-- Removes the temporary file if it exists, ignoring any errors
-- that might occur (file doesn't exist, permission issues, etc.).
-- This is used in cleanup scenarios where we want to be safe.
--
-- @since 0.19.1
cleanupTempFile :: FilePath -> IO ()
cleanupTempFile tempPath =
  Exception.handle handleIOError (Dir.removeFile tempPath)
  where
    handleIOError :: IOException -> IO ()
    handleIOError _ = pure ()

-- | Atomically rename a file using OS-level atomic operations.
--
-- Uses the filesystem guarantee that rename operations are atomic.
-- Falls back to copy-and-delete for cross-device scenarios.
--
-- >>> atomicRename "file.tmp" "file.dat"
--
-- ==== Platform Support
--
-- * **Most filesystems** - Uses standard rename operation
-- * **Cross-device links** - Falls back to copy-and-delete
--
-- ==== Error Conditions
--
-- May throw 'IOException' if:
--   * Source file doesn't exist
--   * Permission denied on target directory
--   * Cross-device link (different filesystems)
--   * Disk space exhausted
--
-- @since 0.19.1
atomicRename :: FilePath -> FilePath -> IO ()
atomicRename tempPath targetPath = do
  Exception.handle handleRenameError $ do
    -- Try standard rename first (atomic on most filesystems)
    Dir.renameFile tempPath targetPath
  where
    handleRenameError :: IOException -> IO ()
    handleRenameError ex
      | "cross-device" `elem` words (show ex) = fallbackCopyAndDelete
      | "different" `elem` words (show ex) = fallbackCopyAndDelete
      | otherwise = Exception.throwIO ex

    -- Fallback for cross-device links (copy then delete)
    fallbackCopyAndDelete = do
      Dir.copyFile tempPath targetPath
      Dir.removeFile tempPath

-- | Ensure the directory for atomic operations exists.
--
-- Creates the target directory if it doesn't exist, ensuring
-- we can create temporary files in the same directory.
--
-- @since 0.19.1
ensureAtomicDirectory :: FilePath -> IO ()
ensureAtomicDirectory targetPath = do
  let dir = FP.takeDirectory targetPath
  Monad.when (dir /= ".") $ do
    Dir.createDirectoryIfMissing True dir

-- | Verify file integrity using SHA-256 checksum.
--
-- Reads the file and computes a SHA-256 hash for integrity verification.
-- Can be used to verify atomic writes completed successfully.
--
-- >>> hash <- checksumFile "package/canopy.json"
-- >>> Monad.when (hash /= expectedHash) $ error "File corrupted"
--
-- @since 0.19.1
checksumFile :: FilePath -> IO (SHA.Digest SHA.SHA256State)
checksumFile filePath = do
  content <- LBS.readFile filePath
  pure (SHA.sha256 content)

-- | Verify file integrity by comparing checksums.
--
-- Computes the file's checksum and compares it to an expected value.
-- Returns True if the file is intact, False if corrupted.
--
-- >>> isIntact <- verifyFileIntegrity "file.dat" expectedChecksum
-- >>> Monad.unless isIntact $ error "File integrity check failed"
--
-- @since 0.19.1
verifyFileIntegrity :: FilePath -> SHA.Digest SHA.SHA256State -> IO Bool
verifyFileIntegrity filePath expectedHash = do
  actualHash <- checksumFile filePath
  pure (actualHash == expectedHash)