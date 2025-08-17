{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Archive and package extraction operations for the Canopy build system.
--
-- This module provides functionality for extracting ZIP archives containing
-- Canopy packages, with security checks and selective file extraction.
-- Operations support both regular extraction and extraction with metadata
-- collection.
--
-- Archive operations are used for:
--   * Package installation from ZIP files
--   * Extracting dependencies from package registry
--   * Processing canopy.json metadata during extraction
--   * Selective file filtering for security
--
-- ==== Security Features
--
-- All extraction operations include security checks:
--   * Path traversal prevention (no .. in paths)
--   * Allowed file filtering (only src/, LICENSE, README.md, canopy.json)
--   * Safe directory creation
--   * Logging of all operations
--
-- ==== Examples
--
-- >>> writePackage "/tmp/package" zipArchive
-- >>> maybeCanopyJson <- writePackageReturnCanopyJson "/tmp/package" zipArchive
-- >>> case maybeCanopyJson of
-- ...   Just json -> parseCanopyJson json
-- ...   Nothing -> error "No canopy.json found"
--
-- @since 0.19.1
module File.Archive
  ( -- * Archive Operations
    writePackage
  , writePackageReturnCanopyJson
    -- * Entry Processing
  , writeEntry
  , writeEntryReturnCanopyJson
    -- * Path Utilities
  , extractRelativePath
  , isAllowedPath
  , isDirectoryPath
    -- * File Operations
  , createEntryDirectory
  , writeEntryFile
  , processAllowedEntry
  , createEntryDirectoryForJson
  , writeEntryFileForJson
    -- * Logging
  , logPackageWrite
  ) where

import qualified System.FilePath as FP
import System.FilePath ((</>))
import qualified Codec.Archive.Zip as Zip
import qualified Control.Monad as Monad
import qualified Data.Foldable as Foldable
import qualified Data.Traversable as Traversable
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.List as List
import qualified Logging.Logger as Logger
import qualified System.Directory as Dir

-- | Extract a ZIP archive to a destination directory.
--
-- Extracts all allowed files from the archive with security filtering.
-- Creates necessary directories and writes files with proper structure.
-- Skips empty archives gracefully.
--
-- >>> writePackage "/home/user/.canopy/packages/author/package/1.0.0" archive
--
-- ==== Security
--
-- Only extracts files matching security criteria:
--   * Files in src/ directory
--   * LICENSE file
--   * README.md file  
--   * canopy.json file
--
-- ==== Errors
--
-- Throws 'IOException' if:
--   * Cannot create destination directories
--   * Insufficient permissions to write files
--   * Disk space exhausted during extraction
writePackage :: FilePath -> Zip.Archive -> IO ()
writePackage destination archive =
  case Zip.zEntries archive of
    [] -> Monad.return ()
    allEntries@(firstEntry : _) -> do
      checkDestinationExists destination
      let rootDepth = calculateRootDepth firstEntry
      Foldable.traverse_ (writeEntry destination rootDepth) allEntries

-- | Check if destination directory exists (for logging).
checkDestinationExists :: FilePath -> IO ()
checkDestinationExists destination = Monad.void (Dir.doesDirectoryExist destination)

-- | Calculate root directory depth from first entry.
calculateRootDepth :: Zip.Entry -> Int
calculateRootDepth _ = 
  -- For most ZIP files, we want to remove one level of directory nesting
  -- e.g., "package/src/Main.can" becomes "src/Main.can" with depth 1
  1

-- | Extract archive and return canopy.json content if found.
--
-- Similar to 'writePackage' but additionally captures and returns
-- the content of canopy.json file during extraction.
--
-- >>> maybeJson <- writePackageReturnCanopyJson "/tmp/package" archive
-- >>> case maybeJson of
-- ...   Just jsonBytes -> parseCanopyMetadata jsonBytes  
-- ...   Nothing -> handleMissingMetadata
--
-- ==== Return Value
--
-- Returns 'Just' ByteString content if canopy.json was found and extracted,
-- 'Nothing' if no canopy.json file exists in the archive.
writePackageReturnCanopyJson :: FilePath -> Zip.Archive -> IO (Maybe BS.ByteString)
writePackageReturnCanopyJson destination archive =
  case Zip.zEntries archive of
    [] -> pure Nothing
    allEntries@(firstEntry : _) -> do
      logPackageWrite destination
      let rootDepth = calculateRootDepth firstEntry
      canopyJsonResults <- Traversable.traverse (writeEntryReturnCanopyJson destination rootDepth) allEntries
      pure (Monad.msum canopyJsonResults)

-- | Log package extraction operation.
logPackageWrite :: FilePath -> IO ()
logPackageWrite destination = do
  Logger.printLog ("writePackageReturnCanopyJson to " <> destination)
  destinationExists <- Dir.doesDirectoryExist destination
  let existsMessage = destination <> " exists: " <> show destinationExists
  Logger.printLog ("writePackageReturnCanopyJson destination: " <> existsMessage)

-- | Extract a single ZIP entry to the destination.
--
-- Processes one entry from the ZIP archive, checking security constraints
-- and creating appropriate files or directories.
writeEntry :: FilePath -> Int -> Zip.Entry -> IO ()
writeEntry destination rootDepth entry = do
  let relativePath = extractRelativePath rootDepth entry
  Monad.when (isAllowedPath relativePath) $ do
    if isDirectoryPath relativePath
      then createEntryDirectory destination relativePath
      else writeEntryFile destination relativePath entry

-- | Extract relative path from ZIP entry.
--
-- Removes the root directory component based on the calculated depth
-- to get the actual relative path for extraction.
extractRelativePath :: Int -> Zip.Entry -> FilePath
extractRelativePath rootDepth entry = 
  let pathComponents = FP.splitDirectories (Zip.eRelativePath entry)
      droppedComponents = List.drop rootDepth pathComponents
  in FP.joinPath droppedComponents

-- | Check if a path is allowed for extraction.
--
-- Security function that only permits extraction of safe files:
--   * Source files in src/ directory
--   * Standard documentation files
--   * Package metadata files
isAllowedPath :: FilePath -> Bool
isAllowedPath path =
  -- Reject paths with null characters for security
  not (List.elem '\0' path) &&
  -- Reject path traversal attempts
  not (List.isInfixOf "../" path) &&
  -- Allow specific files and src/ directory contents
  (List.isPrefixOf "src/" path
    || path == "LICENSE"
    || path == "README.md"
    || path == "canopy.json")

-- | Check if a path represents a directory.
--
-- Determines if the path is a directory by checking for trailing slash,
-- following ZIP archive conventions.
isDirectoryPath :: FilePath -> Bool
isDirectoryPath path = not (List.null path) && List.last path == '/'

-- | Create a directory for a ZIP entry.
--
-- Creates the directory structure needed for the entry with logging.
-- Handles nested directory creation automatically.
createEntryDirectory :: FilePath -> FilePath -> IO ()
createEntryDirectory destination relativePath = do
  Logger.printLog ("writeEntry 0: " <> relativePath)
  Dir.createDirectoryIfMissing True (destination </> relativePath)

-- | Write a file from a ZIP entry.
--
-- Extracts the file content and writes it to the destination with logging.
-- Preserves file content exactly as stored in the ZIP.
writeEntryFile :: FilePath -> FilePath -> Zip.Entry -> IO ()
writeEntryFile destination relativePath entry = do
  Logger.printLog ("writeEntry 1: " <> relativePath)
  let fullPath = destination </> relativePath
  -- Create parent directories if they don't exist
  Dir.createDirectoryIfMissing True (FP.takeDirectory fullPath)
  LBS.writeFile fullPath (Zip.fromEntry entry)

-- | Extract entry and return canopy.json content if applicable.
--
-- Similar to 'writeEntry' but returns the content of canopy.json
-- files for metadata processing.
writeEntryReturnCanopyJson :: FilePath -> Int -> Zip.Entry -> IO (Maybe BS.ByteString)
writeEntryReturnCanopyJson destination rootDepth entry = do
  let relativePath = extractRelativePath rootDepth entry
  if isAllowedPath relativePath
    then processAllowedEntry destination relativePath entry
    else pure Nothing

-- | Process an allowed entry and return canopy.json content.
--
-- Handles both directory and file entries, returning canopy.json
-- content when encountered.
processAllowedEntry :: FilePath -> FilePath -> Zip.Entry -> IO (Maybe BS.ByteString)
processAllowedEntry destination relativePath entry =
  if isDirectoryPath relativePath
    then do
      createEntryDirectoryForJson destination relativePath
      pure Nothing
    else writeEntryFileForJson destination relativePath entry

-- | Create directory for JSON extraction operation.
createEntryDirectoryForJson :: FilePath -> FilePath -> IO ()
createEntryDirectoryForJson destination relativePath = do
  Logger.printLog ("writeEntryReturnCanopyJson 0: " <> relativePath)
  Dir.createDirectoryIfMissing True (destination </> relativePath)

-- | Write file and return content if it's canopy.json.
--
-- Writes the file to disk and additionally returns its content
-- if the file is canopy.json for metadata processing.
writeEntryFileForJson :: FilePath -> FilePath -> Zip.Entry -> IO (Maybe BS.ByteString)
writeEntryFileForJson destination relativePath entry = do
  Logger.printLog ("writeEntryReturnCanopyJson 1: " <> relativePath)
  let fileContent = Zip.fromEntry entry
      fullPath = destination </> relativePath
  -- Create parent directories if they don't exist
  Dir.createDirectoryIfMissing True (FP.takeDirectory fullPath)
  LBS.writeFile fullPath fileContent
  pure (if relativePath == "canopy.json" 
        then Just (BS.toStrict fileContent) 
        else Nothing)