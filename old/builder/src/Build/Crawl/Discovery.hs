{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Module discovery and file finding functionality for the Build system.
--
-- This module provides comprehensive module discovery capabilities including:
--
-- * File path resolution with extension priority
-- * Source directory traversal and module location
-- * Multi-extension support (.can, .canopy, .elm)
-- * Kernel module detection and validation
--
-- The discovery system follows a hierarchical extension priority:
--
-- @
-- 1. .can files (highest priority)
-- 2. .canopy files  
-- 3. .elm files (lowest priority)
-- @
--
-- === Usage Examples
--
-- @
-- -- Discover module files in source directories
-- paths <- findModuleFile srcDirs "App/Main"
-- case paths of
--   [path] -> processModule path
--   [] -> handleNotFound
--   _ -> handleAmbiguous paths
-- @
--
-- === File Discovery Process
--
-- The discovery process searches through all configured source directories
-- in priority order, attempting to locate module files with supported
-- extensions. This ensures compatibility with legacy .elm files while
-- prioritizing newer .can and .canopy formats.
--
-- === Thread Safety
--
-- All discovery operations are pure and thread-safe. File system access
-- is isolated to specific functions that clearly indicate IO operations.
--
-- @since 0.19.1
module Build.Crawl.Discovery
  ( -- * Module Discovery
    findModuleFile
  , findCanopyOrElm
  , findFilesWithExtension
    -- * Path Utilities
  , addRelative
    -- * Kernel Module Support  
  , checkKernelExists
  ) where

import Control.Monad (filterM)
import qualified Canopy.ModuleName as ModuleName
import qualified File
import System.FilePath ((<.>), (</>))

import Build.Types (AbsoluteSrcDir (..), Status (..))
import qualified Reporting.Error.Import as Import

-- | Find module file with extension priority.
--
-- Searches through source directories for module files, prioritizing
-- extensions in the following order:
--
-- 1. .can files (highest priority)
-- 2. .canopy files
-- 3. .elm files (lowest priority)
--
-- ==== Examples
--
-- >>> findModuleFile [srcDir] "App/Main"
-- ["/src/App/Main.can"]
--
-- >>> findModuleFile [srcDir1, srcDir2] "Utils/Helper"
-- []  -- Not found in any directory
--
-- >>> findModuleFile [srcDir] "Common/Types"
-- ["/src1/Common/Types.canopy", "/src2/Common/Types.canopy"]  -- Multiple matches
--
-- @since 0.19.1
findModuleFile
  :: [AbsoluteSrcDir]
  -- ^ Source directories to search
  -> FilePath
  -- ^ Base module file path (without extension)
  -> IO [FilePath]
  -- ^ List of found module file paths
findModuleFile srcDirs baseName = do
  canPaths <- findFilesWithExtension srcDirs baseName "can"
  case canPaths of
    [] -> findCanopyOrElm srcDirs baseName
    _ -> pure canPaths

-- | Find .canopy or .elm files when .can files not found.
--
-- Continues the extension priority search when no .can files are found.
-- Prioritizes .canopy files over .elm files for better compatibility
-- with the Canopy compiler extensions.
--
-- ==== Examples
--
-- >>> findCanopyOrElm [srcDir] "Legacy/Module"
-- ["/src/Legacy/Module.elm"]
--
-- >>> findCanopyOrElm [srcDir] "New/Feature"  
-- ["/src/New/Feature.canopy"]
--
-- @since 0.19.1
findCanopyOrElm
  :: [AbsoluteSrcDir]
  -- ^ Source directories to search
  -> FilePath
  -- ^ Base module file path (without extension)
  -> IO [FilePath]
  -- ^ List of found module file paths
findCanopyOrElm srcDirs baseName = do
  canopyPaths <- findFilesWithExtension srcDirs baseName "canopy"
  case canopyPaths of
    [] -> findFilesWithExtension srcDirs baseName "elm"
    _ -> pure canopyPaths

-- | Find files with specific extension across source directories.
--
-- Searches all provided source directories for files matching the
-- base name with the specified extension. Returns all found paths
-- to handle potential ambiguities in module resolution.
--
-- ==== Examples
--
-- >>> findFilesWithExtension [srcDir1, srcDir2] "Utils/Text" "can"
-- ["/src1/Utils/Text.can", "/src2/Utils/Text.can"]
--
-- >>> findFilesWithExtension [srcDir] "Missing/Module" "canopy" 
-- []
--
-- ==== Error Conditions
--
-- Returns empty list when:
--   * No source directories provided
--   * Module file not found in any directory
--   * File system access errors occur
--
-- @since 0.19.1
findFilesWithExtension
  :: [AbsoluteSrcDir]
  -- ^ Source directories to search
  -> FilePath
  -- ^ Base file path (without extension)
  -> String
  -- ^ File extension to search for
  -> IO [FilePath]
  -- ^ List of found file paths
findFilesWithExtension srcDirs baseName ext =
  filterM File.exists (fmap (`addRelative` (baseName <.> ext)) srcDirs)

-- | Add relative path to source directory.
--
-- Combines an absolute source directory with a relative file path
-- to create the full path to a potential module file.
--
-- ==== Examples
--
-- >>> addRelative (AbsoluteSrcDir "/project/src") "App/Main.can"
-- "/project/src/App/Main.can"
--
-- >>> addRelative (AbsoluteSrcDir "/lib/src") "Utils.elm"
-- "/lib/src/Utils.elm"
--
-- @since 0.19.1
addRelative
  :: AbsoluteSrcDir
  -- ^ Absolute source directory
  -> FilePath
  -- ^ Relative file path
  -> FilePath
  -- ^ Combined absolute file path
addRelative (AbsoluteSrcDir srcDir) path = srcDir </> path

-- | Check if kernel module exists in file system.
--
-- Verifies that a kernel module has a corresponding JavaScript
-- implementation file in the expected location. Kernel modules
-- require native JavaScript implementations for core functionality.
--
-- ==== Examples
--
-- >>> checkKernelExists "Basics"
-- SKernel  -- File exists at src/Basics.js
--
-- >>> checkKernelExists "CustomKernel"
-- SBadImport Import.NotFound  -- No src/CustomKernel.js found
--
-- ==== Kernel Module Requirements
--
-- Kernel modules must:
--   * Have names that pass 'Name.isKernel' validation
--   * Have corresponding .js files in the src/ directory
--   * Be used only in kernel project types
--
-- @since 0.19.1
checkKernelExists
  :: ModuleName.Raw
  -- ^ Kernel module name to check
  -> IO Status
  -- ^ Status indicating whether kernel module exists
checkKernelExists name = do
  exists <- File.exists ("src" </> ModuleName.toFilePath name <.> "js")
  pure $ if exists then SKernel else SBadImport Import.NotFound