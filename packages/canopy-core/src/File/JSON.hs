{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | JSON file I/O operations for the Canopy build system.
--
-- This module provides robust JSON file operations with comprehensive
-- error handling and automatic directory creation. JSON format is used
-- for interface files, providing 10x faster IDE parsing compared to
-- binary format (as proven by PureScript's migration).
--
-- JSON files are used for:
--   * Compiled interface files (.cani.json)
--   * Human-readable for debugging
--   * Content-hash based invalidation
--   * External tools can read without compiler
--   * Fine-grained dependency tracking
--
-- ==== Examples
--
-- >>> writeJSON "cache/interfaces.json" myInterface
-- >>> maybeInterface <- readJSON "cache/interfaces.json"
-- >>> case maybeInterface of
-- ...   Just interface -> processInterface interface
-- ...   Nothing -> rebuildInterface
--
-- ==== Error Handling
--
-- JSON operations handle several error conditions:
--   * Missing parent directories (auto-created)
--   * Corrupted files (logged and returned as Nothing)
--   * Encoding/decoding failures (reported with details)
--   * Permission errors (propagated as IOException)
--   * Old binary .cani files (returns InterfaceNeedsRebuild signal)
--
-- @since 0.19.1
module File.JSON
  ( -- * JSON File Operations
    writeJSON,
    readJSON,
    readJSONOrRebuild,
    -- * Error Types
    JSONError (..),
  )
where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Encode.Pretty as Pretty
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Vector.Internal.Check (HasCallStack)
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import qualified System.IO as IO

-- | JSON decoding errors.
data JSONError
  = FileNotFound FilePath
  | DecodeError FilePath String
  | OldBinaryFile FilePath
  deriving (Show, Eq)

-- | Write a JSON-serializable value to a file.
--
-- Automatically creates parent directories if they don't exist.
-- Uses pretty-printing for human-readable output.
--
-- >>> writeJSON "build/cache/module.json" compiledModule
--
-- ==== Errors
--
-- Throws 'IOException' if:
--   * Cannot create parent directories
--   * Insufficient permissions to write file
--   * Disk space exhausted during write
writeJSON :: (HasCallStack, Aeson.ToJSON a) => FilePath -> a -> IO ()
writeJSON path value = do
  createParentDirectory path
  let config = Pretty.defConfig {Pretty.confIndent = Pretty.Spaces 2}
  LBS.writeFile path (Pretty.encodePretty' config value)

-- | Create parent directory for a file path.
createParentDirectory :: FilePath -> IO ()
createParentDirectory path = do
  let parentDir = FP.dropFileName path
  Dir.createDirectoryIfMissing True parentDir

-- | Read a JSON-serializable value from a file.
--
-- Returns 'Nothing' if the file doesn't exist or cannot be decoded.
-- Corrupted files are logged but don't throw exceptions.
--
-- >>> maybeValue <- readJSON "cache/data.json"
-- >>> case maybeValue of
-- ...   Just value -> useValue value
-- ...   Nothing -> regenerateValue
--
-- ==== Behavior
--
-- Returns 'Nothing' for:
--   * Non-existent files
--   * Corrupted or invalid JSON data
--   * Files with wrong format versions
readJSON :: (HasCallStack, Aeson.FromJSON a) => FilePath -> IO (Maybe a)
readJSON path = do
  fileExists <- Dir.doesFileExist path
  if fileExists
    then decodeJSONFile path
    else pure Nothing

-- | Read JSON file or signal rebuild if old binary format found.
--
-- This function implements the migration strategy from binary to JSON:
-- 1. Try reading .json file first
-- 2. If not found, check for old .cani binary file
-- 3. If old file found, return Left OldBinaryFile (signals rebuild)
-- 4. If neither found, return Left FileNotFound
--
-- >>> result <- readJSONOrRebuild "cache/Module.cani"
-- >>> case result of
-- ...   Right interface -> useInterface interface
-- ...   Left (OldBinaryFile path) -> rebuildModule path
-- ...   Left (FileNotFound path) -> compileFromScratch path
readJSONOrRebuild ::
  (HasCallStack, Aeson.FromJSON a) =>
  FilePath ->
  IO (Either JSONError a)
readJSONOrRebuild basePath = do
  let jsonPath = basePath <> ".json"
  jsonExists <- Dir.doesFileExist jsonPath

  if jsonExists
    then do
      result <- decodeJSONFile jsonPath
      case result of
        Just value -> pure (Right value)
        Nothing -> pure (Left (DecodeError jsonPath "Failed to decode JSON"))
    else do
      -- Check for old .cani binary file
      let binaryPath =
            if FP.takeExtension basePath == ".cani"
              then basePath
              else basePath <> ".cani"
      binaryExists <- Dir.doesFileExist binaryPath
      if binaryExists
        then pure (Left (OldBinaryFile binaryPath))
        else pure (Left (FileNotFound basePath))

-- | Decode a JSON file with error handling.
--
-- Attempts to decode the file and handles corruption gracefully.
-- Reports detailed error information for debugging.
decodeJSONFile :: Aeson.FromJSON a => FilePath -> IO (Maybe a)
decodeJSONFile path = do
  content <- BS.readFile path
  case Aeson.eitherDecodeStrict' content of
    Right value -> pure (Just value)
    Left message -> do
      reportCorruptFile path message
      pure Nothing

-- | Report a corrupted JSON file to stderr.
--
-- Provides detailed information about the corruption including:
--   * File path and error message
--   * Instructions for regenerating the file
reportCorruptFile :: FilePath -> String -> IO ()
reportCorruptFile path message = do
  IO.hPutStrLn IO.stderr (formatCorruptionReport path message)

-- | Format corruption report message.
formatCorruptionReport :: FilePath -> String -> String
formatCorruptionReport path message =
  unlines
    [ "+-------------------------------------------------------------------------------",
      "|  Corrupt JSON File: " <> path,
      "|           Message: " <> message,
      "|",
      "| This interface file will be regenerated automatically.",
      "+-------------------------------------------------------------------------------"
    ]
