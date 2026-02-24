{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Package creation and ZIP archive generation for the Canopy build system.
--
-- This module provides functionality for creating ZIP archives from Canopy
-- packages for local development and package overrides. Complements the
-- extraction functionality in "File.Archive".
--
-- Package creation is used for:
--   * Local package development with canopy-package-overrides
--   * Creating distributable package archives
--   * Building dependency ZIP files for package registry
--   * Testing package structure and metadata
--
-- ==== Security Features
--
-- All archive creation operations include security checks:
--   * Path validation (no .. in paths, no absolute paths)
--   * File filtering (only src/, LICENSE, README.md, canopy.json)
--   * Safe file reading with error handling
--   * Logging of all operations
--
-- ==== Examples
--
-- >>> createPackageZip "/home/user/my-package" "/tmp/my-package.zip"
-- >>> archive <- createPackageArchive "/home/user/my-package"
-- >>> zipBytes <- packageToZipBytes "/home/user/my-package"
--
-- @since 0.19.1
module File.Package
  ( -- * Package Archive Creation
    createPackageZip
  , createPackageArchive
  , packageToZipBytes
    -- * Directory Processing
  , collectPackageFiles
  , isPackageFile
  , createZipEntry
    -- * Path Utilities
  , validatePackagePath
  , makeRelativeToPackage
  , isAllowedPackageFile
    -- * Archive Building
  , addFileToArchive
  , addDirectoryToArchive
  , buildArchiveFromFiles
    -- * Logging
  , logPackageCreation
  ) where

import qualified System.FilePath as FP
import System.FilePath ((</>))
import qualified Codec.Archive.Zip as Zip
import qualified Control.Monad as Monad
import qualified Data.Foldable as Foldable
import qualified Data.ByteString.Lazy as LBS
import qualified Data.List as List
import qualified Data.Text as Text
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import qualified System.Directory as Dir
import qualified Control.Exception as Exception
import qualified Data.Time.Clock.POSIX as Time

-- | Create a ZIP archive from a package directory.
--
-- Creates a complete ZIP archive containing all package files
-- (src/, LICENSE, README.md, canopy.json) and writes it to the
-- specified output path.
--
-- >>> createPackageZip "/home/user/my-package" "/tmp/my-package.zip"
--
-- ==== Package Structure Expected
--
-- The source directory should contain:
--   * canopy.json - Package metadata
--   * src/ - Source files (*.can)
--   * LICENSE - License file (optional)
--   * README.md - Documentation (optional)
--
-- ==== Errors
--
-- Throws 'IOException' if:
--   * Source directory doesn't exist
--   * Cannot read package files
--   * Cannot write output ZIP file
--   * Insufficient disk space
createPackageZip :: FilePath -> FilePath -> IO ()
createPackageZip packageDir outputPath = do
  logPackageCreation packageDir outputPath
  archive <- createPackageArchive packageDir
  LBS.writeFile outputPath (Zip.fromArchive archive)
  Log.logEvent . PackageOperation "create" . Text.pack $ ("Created ZIP archive: " <> outputPath)

-- | Log package creation operation.
logPackageCreation :: FilePath -> FilePath -> IO ()
logPackageCreation packageDir outputPath = do
  Log.logEvent . PackageOperation "create" . Text.pack $ ("Creating package ZIP from: " <> packageDir)
  Log.logEvent . PackageOperation "create" . Text.pack $ ("Output ZIP file: " <> outputPath)
  packageDirExists <- Dir.doesDirectoryExist packageDir
  Log.logEvent . PackageOperation "create" . Text.pack $ ("Package directory exists: " <> show packageDirExists)

-- | Create a ZIP archive from a package directory.
--
-- Returns an in-memory ZIP archive containing all package files
-- without writing to disk. Useful for package override processing.
--
-- >>> archive <- createPackageArchive "/home/user/my-package"
-- >>> let archiveBytes = Zip.fromArchive archive
--
-- ==== Security
--
-- Only includes files matching security criteria:
--   * Files in src/ directory (*.can files)
--   * LICENSE file
--   * README.md file
--   * canopy.json file
createPackageArchive :: FilePath -> IO Zip.Archive
createPackageArchive packageDir = do
  files <- collectPackageFiles packageDir
  buildArchiveFromFiles packageDir files

-- | Convert a package directory to ZIP bytes.
--
-- Creates a ZIP archive in memory and returns the raw bytes.
-- Convenient for HTTP uploads or direct processing.
--
-- >>> zipBytes <- packageToZipBytes "/home/user/my-package"
-- >>> BS.writeFile "package.zip" zipBytes
packageToZipBytes :: FilePath -> IO LBS.ByteString
packageToZipBytes packageDir = do
  archive <- createPackageArchive packageDir
  pure (Zip.fromArchive archive)

-- | Collect all files that should be included in the package.
--
-- Recursively scans the package directory and returns a list of
-- file paths that should be included in the ZIP archive.
collectPackageFiles :: FilePath -> IO [FilePath]
collectPackageFiles packageDir = do
  allFiles <- getAllFilesRecursive packageDir
  let filteredFiles = List.filter (isPackageFileSimple packageDir) allFiles
  pure filteredFiles

-- | Get all files recursively from a directory.
getAllFilesRecursive :: FilePath -> IO [FilePath]
getAllFilesRecursive = getAllFilesRecursiveInternal True
  where
    getAllFilesRecursiveInternal checkAllowed dir = do
      contents <- Dir.listDirectory dir
      files <- Monad.foldM (processEntry checkAllowed) [] contents
      pure files
      where
        processEntry isTopLevel acc entry = do
          let fullPath = dir </> entry
          isFile <- Dir.doesFileExist fullPath
          isDir <- Dir.doesDirectoryExist fullPath
          if isFile
            then pure (fullPath : acc)
            else if isDir && (not isTopLevel || isAllowedDirectory entry)
              then do
                subFiles <- getAllFilesRecursiveInternal False fullPath
                pure (subFiles <> acc)
              else pure acc

    isAllowedDirectory name = name `elem` ["src", "tests", "docs"]

-- | Simple package file check with direct relative path calculation.
--
-- More straightforward file filtering that avoids complex path manipulation.
isPackageFileSimple :: FilePath -> FilePath -> Bool
isPackageFileSimple packageDir filePath =
  let relativePath = FP.makeRelative packageDir filePath
      normalizedPath = FP.normalise relativePath
  in isAllowedPackageFile normalizedPath

-- | Check if a file should be included in the package.
--
-- Security function that only permits safe package files:
--   * Source files in src/ directory
--   * Standard documentation files
--   * Package metadata files
isPackageFile :: FilePath -> Bool
isPackageFile path =
  let normalizedPath = FP.normalise path
      relativePath = makeRelativeToPackageUnsafe normalizedPath
  in isAllowedPackageFile relativePath

-- | Make a path relative to the package root (unsafe version).
makeRelativeToPackageUnsafe :: FilePath -> FilePath
makeRelativeToPackageUnsafe path =
  let components = FP.splitDirectories path
      -- Find the last component that looks like a package directory
      -- and make everything after it relative
      dropCount = findPackageRoot components
  in FP.joinPath (List.drop dropCount components)
  where
    findPackageRoot [] = 0
    findPackageRoot (_ : rest) =
      if List.any (`List.elem` ["src", "canopy.json"]) (List.take 2 (List.map FP.takeFileName rest))
        then 1
        else 1 + findPackageRoot rest

-- | Check if a relative path is allowed in packages.
--
-- Security function that validates file paths for package inclusion:
--   * Source files in src/ directory (*.can files)
--   * Standard documentation files
--   * Package metadata
isAllowedPackageFile :: FilePath -> Bool
isAllowedPackageFile path =
  -- Reject path traversal attempts
  not (List.isInfixOf "../" path) &&
  -- Only allow relative paths
  FP.isRelative path &&
  -- Allow specific files and src/ directory contents
  (List.isPrefixOf "src/" path &&
    (FP.takeExtension path == ".can" ||
     (List.isInfixOf "/Kernel/" path && FP.takeExtension path == ".js"))
    || path == "LICENSE"
    || path == "README.md"
    || path == "canopy.json")

-- | Validate a package path for security.
--
-- Ensures the path is safe for package operations and doesn't
-- contain security vulnerabilities.
validatePackagePath :: FilePath -> Either String FilePath
validatePackagePath path
  | List.isInfixOf "../" path = Left "Path traversal not allowed"
  | FP.isAbsolute path = Left "Absolute paths not allowed"
  | otherwise = Right (FP.normalise path)

-- | Make a file path relative to the package root.
--
-- Converts an absolute or relative path to be relative to the
-- package directory for ZIP archive creation.
makeRelativeToPackage :: FilePath -> FilePath -> FilePath
makeRelativeToPackage packageDir filePath =
  let absolutePackageDir = FP.normalise packageDir
      absoluteFilePath = if FP.isAbsolute filePath
                          then filePath
                          else packageDir </> filePath
      normalizedFilePath = FP.normalise absoluteFilePath
  in FP.makeRelative absolutePackageDir normalizedFilePath

-- | Build a ZIP archive from a list of files.
--
-- Creates a ZIP archive containing all specified files with
-- proper directory structure and timestamps.
buildArchiveFromFiles :: FilePath -> [FilePath] -> IO Zip.Archive
buildArchiveFromFiles packageDir files = do
  entries <- Monad.mapM (createZipEntry packageDir) files
  let archive = Foldable.foldl' (flip Zip.addEntryToArchive) Zip.emptyArchive entries
  pure archive

-- | Create a ZIP entry from a file path.
--
-- Reads the file content and creates a properly formatted
-- ZIP entry with correct timestamps and paths.
createZipEntry :: FilePath -> FilePath -> IO Zip.Entry
createZipEntry packageDir filePath = do
  let relativePath = FP.makeRelative (FP.normalise packageDir) (FP.normalise filePath)
  content <- Exception.catch
    (LBS.readFile filePath)
    (\e -> do
      Log.logEvent . PackageOperation "create" . Text.pack $ ("Error reading file " <> filePath <> ": " <> show (e :: Exception.IOException))
      pure LBS.empty)
  currentTime <- Time.getPOSIXTime
  pure $ Zip.toEntry relativePath (round currentTime) content

-- | Add a single file to an archive.
--
-- Helper function for incrementally building archives by
-- adding individual files with proper error handling.
addFileToArchive :: Zip.Archive -> FilePath -> FilePath -> IO Zip.Archive
addFileToArchive archive packageDir filePath = do
  entry <- createZipEntry packageDir filePath
  Log.logEvent . PackageOperation "create" . Text.pack $ ("Adding file to archive: " <> filePath)
  pure (Zip.addEntryToArchive entry archive)

-- | Add all files from a directory to an archive.
--
-- Recursively adds all allowed files from a directory to
-- the ZIP archive with proper structure preservation.
addDirectoryToArchive :: Zip.Archive -> FilePath -> FilePath -> IO Zip.Archive
addDirectoryToArchive archive packageDir dirPath = do
  files <- collectPackageFiles dirPath
  Log.logEvent . PackageOperation "create" . Text.pack $ ("Adding directory to archive: " <> dirPath <> " (" <> show (List.length files) <> " files)")
  Monad.foldM (\acc file -> addFileToArchive acc packageDir file) archive files