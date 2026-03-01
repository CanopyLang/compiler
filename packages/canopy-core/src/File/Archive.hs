{-# LANGUAGE OverloadedStrings #-}

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
--   * Allowed file filtering (only src/, LICENSE, README.md, canopy.json, elm.json)
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
  , isWithinDestination
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
import qualified Data.Text as Text
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import qualified System.Directory as Dir
import qualified File.Atomic as Atomic

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

-- | Extract archive and return config file content if found.
--
-- Similar to 'writePackage' but additionally captures and returns
-- the content of config file (canopy.json or elm.json) during extraction.
--
-- >>> maybeJson <- writePackageReturnCanopyJson "/tmp/package" archive
-- >>> case maybeJson of
-- ...   Just jsonBytes -> parseCanopyMetadata jsonBytes  
-- ...   Nothing -> handleMissingMetadata
--
-- ==== Return Value
--
-- Returns 'Just' ByteString content if config file was found and extracted,
-- 'Nothing' if no config file (canopy.json or elm.json) exists in the archive.
writePackageReturnCanopyJson :: FilePath -> Zip.Archive -> IO (Maybe BS.ByteString)
writePackageReturnCanopyJson destination archive = do
  case Zip.zEntries archive of
    [] -> do
      pure Nothing
    allEntries@(firstEntry : _) -> do
      logPackageWrite destination
      let rootDepth = calculateRootDepth firstEntry
      canopyJsonResults <- Traversable.traverse (writeEntryReturnCanopyJson destination rootDepth) allEntries
      pure (Monad.msum canopyJsonResults)

-- | Log package extraction operation.
logPackageWrite :: FilePath -> IO ()
logPackageWrite destination = do
  Log.logEvent (ArchiveOperation "extract" (Text.pack ("writePackageReturnCanopyJson to " <> destination)))
  destinationExists <- Dir.doesDirectoryExist destination
  Log.logEvent (ArchiveOperation "extract" (Text.pack (destination <> " exists: " <> show destinationExists)))

-- | Extract a single ZIP entry to the destination.
--
-- Processes one entry from the ZIP archive, checking security constraints
-- and creating appropriate files or directories.
writeEntry :: FilePath -> Int -> Zip.Entry -> IO ()
writeEntry destination rootDepth entry = do
  let relativePath = extractRelativePath rootDepth entry
      allowed = isAllowedPath relativePath && isWithinDestination destination relativePath
  Monad.when allowed $ do
    if isDirectoryPath relativePath
      then do
        Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("EXTRACT_DIRECTORY: " <> relativePath)
        createEntryDirectory destination relativePath
      else do
        Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("EXTRACT_FILE: " <> relativePath)
        writeEntryFile destination relativePath entry

-- | Extract relative path from ZIP entry.
--
-- Removes the root directory component based on the calculated depth
-- to get the actual relative path for extraction. Preserves trailing
-- slashes to maintain directory/file distinction.
extractRelativePath :: Int -> Zip.Entry -> FilePath
extractRelativePath rootDepth entry =
  let originalPath = Zip.eRelativePath entry
      pathComponents = FP.splitDirectories originalPath
      droppedComponents = List.drop rootDepth pathComponents
      joinedPath = FP.joinPath droppedComponents
   in if List.null droppedComponents
        then ""
        else if endsWithSlash originalPath && not (List.null joinedPath) && not (endsWithSlash joinedPath)
          then joinedPath ++ "/"
          else joinedPath

-- | Check if a path string ends with a forward slash.
endsWithSlash :: String -> Bool
endsWithSlash [] = False
endsWithSlash [c] = c == '/'
endsWithSlash (_ : rest) = endsWithSlash rest

-- | Check if a path is allowed for extraction.
--
-- Security function that only permits extraction of safe files:
--   * Source files in src/ directory
--   * Standard documentation files
--   * Package metadata files
--
-- Rejects paths containing:
--   * Null characters (path injection attacks)
--   * Path traversal attempts (../)
isAllowedPath :: FilePath -> Bool
isAllowedPath path =
  -- Reject null characters (security issue)
  not (List.elem '\0' path) &&
  -- Reject path traversal attempts (platform-independent check)
  not (".." `elem` FP.splitDirectories path) &&
  -- Allow specific files and src/ directory contents
  (List.isPrefixOf "src/" path
    || path == "LICENSE"
    || path == "README.md"
    || path == "canopy.json"
    || path == "elm.json")

-- | Verify the resolved extraction path stays within the destination directory.
--
-- Defence-in-depth check: splits the combined @destination \</\> relativePath@
-- into directory components and rejects any containing @..@. This catches
-- edge cases where the relative path could escape the extraction root,
-- even on platforms where @FP.normalise@ does not resolve @..@ components.
--
-- @since 0.19.2
isWithinDestination :: FilePath -> FilePath -> Bool
isWithinDestination destination relativePath =
  not (".." `elem` FP.splitDirectories resolvedPath)
  where
    resolvedPath = destination </> relativePath

-- | Check if a path represents a directory.
--
-- Determines if the path is a directory by checking for trailing slash,
-- following ZIP archive conventions.
isDirectoryPath :: FilePath -> Bool
isDirectoryPath = endsWithSlash

-- | Check if a file is critical and needs atomic writes.
--
-- Critical files are those that could corrupt the build system if
-- partially written or corrupted. These files receive special treatment
-- with atomic write operations to prevent corruption.
--
-- Critical files include:
--   * Package metadata (canopy.json, elm.json)
--   * License files (important for legal compliance)
--   * Documentation (README.md for package information)
--
-- @since 0.19.1
isCriticalFile :: FilePath -> Bool
isCriticalFile path =
  path == "canopy.json"
    || path == "elm.json"
    || path == "LICENSE"
    || path == "README.md"

-- | Create a directory for a ZIP entry.
--
-- Creates the directory structure needed for the entry with logging.
-- Handles nested directory creation automatically.
createEntryDirectory :: FilePath -> FilePath -> IO ()
createEntryDirectory destination relativePath = do
  Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("writeEntry 0: " <> relativePath)
  Dir.createDirectoryIfMissing True (destination </> relativePath)

-- | Write a file from a ZIP entry.
--
-- Extracts the file content and writes it to the destination with logging.
-- Uses atomic writes for critical files to prevent corruption.
writeEntryFile :: FilePath -> FilePath -> Zip.Entry -> IO ()
writeEntryFile destination relativePath entry = do
  Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("writeEntry 1: " <> relativePath)
  let fullPath = destination </> relativePath
      fileContent = Zip.fromEntry entry
  -- Create parent directories if they don't exist
  Dir.createDirectoryIfMissing True (FP.takeDirectory fullPath)
  -- Use atomic writes for critical package files
  if isCriticalFile relativePath
    then Atomic.writeLazyBytesAtomic fullPath fileContent
    else LBS.writeFile fullPath fileContent

-- | Extract entry and return canopy.json content if applicable.
--
-- Similar to 'writeEntry' but returns the content of canopy.json
-- files for metadata processing.
writeEntryReturnCanopyJson :: FilePath -> Int -> Zip.Entry -> IO (Maybe BS.ByteString)
writeEntryReturnCanopyJson destination rootDepth entry = do
  let relativePath = extractRelativePath rootDepth entry
      allowed = isAllowedPath relativePath && isWithinDestination destination relativePath
  if allowed
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
  Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("writeEntryReturnCanopyJson 0: " <> relativePath)
  Dir.createDirectoryIfMissing True (destination </> relativePath)

-- | Write file and return content if it's a config file.
--
-- Writes the file to disk and additionally returns its content
-- if the file is a config file (canopy.json or elm.json) for metadata processing.
-- Uses atomic writes for critical files to prevent corruption.
writeEntryFileForJson :: FilePath -> FilePath -> Zip.Entry -> IO (Maybe BS.ByteString)
writeEntryFileForJson destination relativePath entry = do
  Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("writeEntryReturnCanopyJson 1: " <> relativePath)
  let fileContent = Zip.fromEntry entry
      fullPath = destination </> relativePath
      contentSize = LBS.length fileContent

  -- Log detailed extraction information
  Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("EXTRACT: " <> relativePath <> " -> " <> fullPath <> " (size: " <> show contentSize <> " bytes)")

  -- Create parent directories if they don't exist
  Dir.createDirectoryIfMissing True (FP.takeDirectory fullPath)

  -- Use atomic writes for critical package files
  if isCriticalFile relativePath
    then do
      Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("ATOMIC_WRITE: " <> fullPath <> " (critical file)")
      Atomic.writeLazyBytesAtomic fullPath fileContent
      Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("ATOMIC_WRITE_COMPLETE: " <> fullPath)
    else do
      Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("REGULAR_WRITE: " <> fullPath <> " (non-critical file)")
      LBS.writeFile fullPath fileContent
      Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("REGULAR_WRITE_COMPLETE: " <> fullPath)

  -- Return content for JSON files with detailed logging and integrity validation
  if relativePath == "canopy.json" || relativePath == "elm.json"
    then do
      let strictContent = BS.toStrict fileContent
          strictSize = BS.length strictContent
      Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("JSON_RETURN: " <> relativePath <> " returning content (size: " <> show strictSize <> " bytes)")
      -- Log first 100 chars for debugging
      let preview = BS.take 100 strictContent
          previewText = show preview
      Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("JSON_PREVIEW: " <> relativePath <> " content preview: " <> previewText)

      -- Verify file integrity by reading back what was written
      if isCriticalFile relativePath
        then do
          Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("INTEGRITY_CHECK: Verifying " <> fullPath)
          writtenContent <- BS.readFile fullPath
          if writtenContent == strictContent
            then do
              Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("INTEGRITY_SUCCESS: " <> fullPath <> " matches extracted content")
              pure (Just strictContent)
            else do
              Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("INTEGRITY_FAILURE: " <> fullPath <> " does not match extracted content!")
              Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("WRITTEN_SIZE: " <> show (BS.length writtenContent) <> " bytes")
              Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("EXPECTED_SIZE: " <> show strictSize <> " bytes")
              Log.logEvent . ArchiveOperation "extract" . Text.pack $ ("WRITTEN_PREVIEW: " <> show (BS.take 100 writtenContent))
              pure (Just strictContent) -- Return original content, let parser handle corruption
        else pure (Just strictContent)
    else pure Nothing