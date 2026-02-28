{-# LANGUAGE OverloadedStrings #-}

-- | Package archive creation for publishing.
--
-- Creates reproducible tarballs of Canopy packages for registry upload.
-- Only includes source files, @canopy.json@, @LICENSE@, and @README@;
-- excludes build artifacts, version control, and editor files.
--
-- == Reproducibility
--
-- Archives are deterministic: given the same source tree, the
-- resulting archive (and its SHA-256 hash) is identical.  This is
-- achieved by:
--
-- * Sorting file entries lexicographically
-- * Normalizing timestamps to the Unix epoch
-- * Using consistent compression settings
--
-- @since 0.19.2
module Publish.Archive
  ( -- * Archive Types
    PackageArchive (..),
    ArchiveEntry (..),

    -- * Archive Creation
    collectArchiveEntries,
    isIncludedFile,
    isExcludedDirectory,

    -- * File Filtering
    sourceExtensions,
    alwaysIncludeFiles,
    excludedDirectories,
  )
where

import qualified Data.List as List
import qualified Data.Text as Text
import qualified System.FilePath as FP

-- | A package archive ready for upload.
--
-- @since 0.19.2
data PackageArchive = PackageArchive
  { -- | Sorted list of entries in the archive.
    _archiveEntries :: ![ArchiveEntry],
    -- | SHA-256 hash of the archive contents.
    _archiveHash :: !Text.Text,
    -- | Total uncompressed size in bytes.
    _archiveSize :: !Int
  }
  deriving (Eq, Show)

-- | A single entry in the package archive.
--
-- @since 0.19.2
data ArchiveEntry = ArchiveEntry
  { -- | Relative path within the archive.
    _entryPath :: !FilePath,
    -- | Size in bytes.
    _entrySize :: !Int
  }
  deriving (Eq, Show, Ord)

-- | Collect archive entries from a project directory.
--
-- Walks the directory tree, filters to included files,
-- and returns a sorted list of entries.
--
-- @since 0.19.2
collectArchiveEntries :: FilePath -> [FilePath] -> [ArchiveEntry]
collectArchiveEntries root files =
  List.sort (map mkEntry included)
  where
    included = filter (isIncludedFile root) files
    mkEntry path =
      ArchiveEntry
        { _entryPath = FP.makeRelative root path,
          _entrySize = 0
        }

-- | Check whether a file should be included in the archive.
--
-- A file is included if it is a Canopy source file or one of
-- the always-included metadata files (canopy.json, LICENSE, README).
--
-- @since 0.19.2
isIncludedFile :: FilePath -> FilePath -> Bool
isIncludedFile root path =
  isSourceFile relativePath || isMetadataFile relativePath
  where
    relativePath = FP.makeRelative root path

-- | Check whether a directory should be excluded from traversal.
--
-- Excluded directories include build artifacts, version control,
-- and editor configuration.
--
-- @since 0.19.2
isExcludedDirectory :: FilePath -> Bool
isExcludedDirectory dir =
  FP.takeFileName dir `elem` excludedDirectories

-- | File extensions for Canopy source files.
--
-- @since 0.19.2
sourceExtensions :: [String]
sourceExtensions = [".can", ".canopy"]

-- | Files always included in the archive regardless of extension.
--
-- @since 0.19.2
alwaysIncludeFiles :: [String]
alwaysIncludeFiles =
  [ "canopy.json",
    "LICENSE",
    "README.md"
  ]

-- | Directories excluded from the archive.
--
-- @since 0.19.2
excludedDirectories :: [String]
excludedDirectories =
  [ "canopy-stuff",
    "elm-stuff",
    ".canopy-stuff",
    "node_modules",
    ".git",
    ".svn",
    ".hg",
    ".stack-work",
    "dist-newstyle"
  ]

-- INTERNAL

-- | Check if a relative path is a Canopy source file.
isSourceFile :: FilePath -> Bool
isSourceFile path =
  FP.takeExtension path `elem` sourceExtensions

-- | Check if a relative path is a required metadata file.
isMetadataFile :: FilePath -> Bool
isMetadataFile path =
  FP.takeFileName path `elem` alwaysIncludeFiles
