{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Binary file I/O operations for the Canopy build system.
--
-- This module provides robust binary file operations with comprehensive
-- error handling and automatic directory creation. All operations use
-- strict evaluation to prevent memory leaks.
--
-- Binary files are used throughout the build system for:
--   * Compiled interface files
--   * Cached dependency information
--   * Serialized AST representations
--   * Build artifacts and metadata
--
-- ==== Examples
--
-- >>> writeBinary "cache/interfaces.dat" myInterface
-- >>> maybeInterface <- readBinary "cache/interfaces.dat"
-- >>> case maybeInterface of
-- ...   Just interface -> processInterface interface
-- ...   Nothing -> handleMissingInterface
--
-- ==== Error Handling
--
-- Binary operations handle several error conditions:
--   * Missing parent directories (auto-created)
--   * Corrupted files (logged and returned as Nothing)
--   * Encoding/decoding failures (reported with details)
--   * Permission errors (propagated as IOException)
--
-- @since 0.19.1
module File.Binary
  ( -- * Binary File Operations
    writeBinary
  , readBinary
    -- * Internal Operations
  , decodeBinaryFile
  , reportCorruptFile
  ) where

import Data.Vector.Internal.Check (HasCallStack)
import qualified Data.Binary as Binary
import qualified Data.Int as Int
import qualified GHC.Exception as Exception
import qualified GHC.Stack as Stack
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import qualified System.IO as IO

-- | Write a binary-serializable value to a file.
--
-- Automatically creates parent directories if they don't exist.
-- Uses strict evaluation to ensure the value is fully written.
--
-- >>> writeBinary "build/cache/module.dat" compiledModule
--
-- ==== Errors
--
-- Throws 'IOException' if:
--   * Cannot create parent directories
--   * Insufficient permissions to write file
--   * Disk space exhausted during write
writeBinary :: (HasCallStack, Binary.Binary a) => FilePath -> a -> IO ()
writeBinary path value = do
  createParentDirectory path
  Binary.encodeFile path value

-- | Create parent directory for a file path.
createParentDirectory :: FilePath -> IO ()
createParentDirectory path = do
  let parentDir = FP.dropFileName path
  Dir.createDirectoryIfMissing True parentDir

-- | Read a binary-serializable value from a file.
--
-- Returns 'Nothing' if the file doesn't exist or cannot be decoded.
-- Corrupted files are logged but don't throw exceptions.
--
-- >>> maybeValue <- readBinary "cache/data.bin"
-- >>> case maybeValue of
-- ...   Just value -> useValue value
-- ...   Nothing -> regenerateValue
--
-- ==== Behavior
--
-- Returns 'Nothing' for:
--   * Non-existent files
--   * Corrupted or invalid binary data
--   * Files with wrong format versions
readBinary :: (HasCallStack, Binary.Binary a) => FilePath -> IO (Maybe a)
readBinary path = do
  fileExists <- Dir.doesFileExist path
  if fileExists
    then decodeBinaryFile path
    else pure Nothing

-- | Decode a binary file with error handling.
--
-- Attempts to decode the file and handles corruption gracefully.
-- Reports detailed error information for debugging.
decodeBinaryFile :: Binary.Binary a => FilePath -> IO (Maybe a)
decodeBinaryFile path = do
  result <- Binary.decodeFileOrFail path
  case result of
    Right value -> pure (Just value)
    Left (offset, message) -> do
      reportCorruptFile path offset message
      pure Nothing

-- | Report a corrupted binary file to stderr.
--
-- Provides detailed information about the corruption including:
--   * File path and byte offset of error
--   * Error message from Binary decoder
--   * Call stack for debugging
--   * Instructions for reporting issues
reportCorruptFile :: FilePath -> Int.Int64 -> String -> IO ()
reportCorruptFile path offset message = do
  IO.hPutStrLn IO.stderr (formatCorruptionReport path offset message)
  IO.hPutStrLn IO.stderr (Exception.prettyCallStack Stack.callStack)

-- | Format corruption report message.
formatCorruptionReport :: FilePath -> Int.Int64 -> String -> String
formatCorruptionReport path offset message = unlines
  [ "+-------------------------------------------------------------------------------"
  , "|  Corrupt File: " <> path
  , "|   Byte Offset: " <> show offset
  , "|       Message: " <> message
  , "|"
  , "| Please report this to https://github.com/canopy/compiler/issues"
  , "| Trying to continue anyway."
  , "+-------------------------------------------------------------------------------"
  ]