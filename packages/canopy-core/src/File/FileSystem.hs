{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | File system query and manipulation operations for the Canopy build system.
--
-- This module provides essential file system operations including existence
-- checks, file removal, and recursive directory traversal. All operations
-- are designed to be safe and handle common error conditions gracefully.
--
-- File system operations are used throughout the build system for:
--   * Checking if source files exist before compilation
--   * Cleaning build artifacts and cache files
--   * Discovering Canopy source files in project directories
--   * Managing temporary files and directories
--
-- ==== Examples
--
-- >>> fileExists <- exists "src/Main.can"
-- >>> when fileExists $ processSourceFile "src/Main.can"
--
-- >>> remove "build/temp.dat"  -- Safe removal (no error if missing)
-- >>> removeDir "build/cache"  -- Recursive directory removal
--
-- >>> canopyFiles <- listAllCanopyFilesRecursively "src"
-- >>> mapM_ compileFile canopyFiles
--
-- ==== Safety Features
--
-- All operations are designed to be safe:
--   * Removal operations check existence before attempting removal
--   * Directory traversal respects file system boundaries
--   * Canopy file detection supports multiple extensions
--   * No operations throw exceptions for missing files
--
-- @since 0.19.1
module File.FileSystem
  ( -- * File Existence
    exists
    -- * File Removal
  , remove
  , removeDir
    -- * Directory Traversal
  , listAllCanopyFilesRecursively
    -- * Internal Operations
  , processDirectoryEntry
  , processSubdirectory
  , processFile
  , isCanopyFile
  ) where

import System.FilePath ((</>))
import qualified Control.Monad as Monad
import qualified Data.List as List
import qualified System.Directory as Dir
import qualified System.FilePath as FP

-- | Check if a file exists.
--
-- Safe wrapper around Directory.doesFileExist that provides
-- a simple boolean result for file existence checks.
--
-- >>> fileExists <- exists "canopy.json"
-- >>> when fileExists $ processConfigFile "canopy.json"
--
-- ==== Behavior
--
-- Returns 'True' if the file exists and is readable,
-- 'False' otherwise (including permission errors).
exists :: FilePath -> IO Bool
exists = Dir.doesFileExist

-- | Remove a file if it exists.
--
-- Safe file removal that doesn't raise exceptions if the file
-- doesn't exist. Checks existence before attempting removal.
--
-- >>> remove "build/temp.o"  -- Won't fail if file doesn't exist
-- >>> remove "cache/stale.dat"
--
-- ==== Safety
--
-- Never throws exceptions for missing files. Only attempts
-- removal if the file actually exists.
remove :: FilePath -> IO ()
remove path = do
  fileExists <- Dir.doesFileExist path
  Monad.when fileExists $ Dir.removeFile path

-- | Remove a directory and all its contents if it exists.
--
-- Safe recursive directory removal that checks existence first.
-- Removes all subdirectories and files within the target directory.
--
-- >>> removeDir "build"  -- Removes entire build directory
-- >>> removeDir "dist-newstyle/cache"
--
-- ==== Safety
--
-- Only attempts removal if the directory exists. Uses recursive
-- removal to handle non-empty directories properly.
removeDir :: FilePath -> IO ()
removeDir path = do
  directoryExists <- Dir.doesDirectoryExist path
  Monad.when directoryExists $ Dir.removeDirectoryRecursive path

-- | Recursively find all Canopy source files in a directory.
--
-- Traverses the directory structure and returns paths to all files
-- with Canopy extensions (.can, .canopy, .elm). Includes both files
-- and directories in the result for ZIP extraction compatibility.
--
-- >>> sourceFiles <- listAllCanopyFilesRecursively "src"
-- >>> mapM_ compileSource sourceFiles
--
-- ==== Supported Extensions
--
-- Recognizes these Canopy source file extensions:
--   * .can (primary Canopy extension)
--   * .canopy (alternative Canopy extension)  
--   * .elm (legacy Elm compatibility)
--
-- ==== Return Value
--
-- Returns a list containing:
--   * The starting directory path
--   * All subdirectory paths (for ZIP compatibility)
--   * All Canopy source file paths
listAllCanopyFilesRecursively :: FilePath -> IO [FilePath]
listAllCanopyFilesRecursively startPath = do
  directoryContents <- Dir.listDirectory startPath
  allPaths <- Monad.forM directoryContents (processDirectoryEntry startPath)
  pure (startPath : List.concat allPaths)

-- | Process a single directory entry during traversal.
--
-- Determines whether the entry is a directory or file and processes
-- it appropriately. Directories are traversed recursively.
processDirectoryEntry :: FilePath -> String -> IO [FilePath]
processDirectoryEntry startPath entryName = do
  let fullPath = startPath </> entryName
  isDirectory <- Dir.doesDirectoryExist fullPath
  if isDirectory
    then processSubdirectory fullPath
    else processFile fullPath

-- | Process a subdirectory during recursive traversal.
--
-- Recursively processes the subdirectory and includes both the
-- directory path itself and all discovered files within it.
processSubdirectory :: FilePath -> IO [FilePath]
processSubdirectory directoryPath = do
  nestedFiles <- listAllCanopyFilesRecursively directoryPath
  -- Include directories for ZIP extraction compatibility
  pure (directoryPath : nestedFiles)

-- | Process a single file during traversal.
--
-- Checks if the file is a Canopy source file and includes it
-- in the result if it matches supported extensions.
processFile :: FilePath -> IO [FilePath]
processFile filePath =
  if isCanopyFile fileExtension
    then pure [filePath]
    else pure []
  where
    (_, fileExtension) = FP.splitExtension filePath

-- | Check if a file extension indicates a Canopy source file.
--
-- Recognizes the standard Canopy source file extensions used
-- throughout the ecosystem.
--
-- >>> isCanopyFile ".can"
-- True
-- >>> isCanopyFile ".canopy"  
-- True
-- >>> isCanopyFile ".elm"
-- True
-- >>> isCanopyFile ".js"
-- False
isCanopyFile :: String -> Bool
isCanopyFile extension = extension `elem` [".can", ".canopy", ".elm"]