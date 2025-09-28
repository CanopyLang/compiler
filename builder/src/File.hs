{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Comprehensive file operations for the Canopy build system.
--
-- This module provides a unified interface for all file-related operations
-- used throughout the Canopy compiler and build system. It coordinates
-- functionality from specialized sub-modules to provide a clean,
-- comprehensive API.
--
-- The module is organized into several functional areas:
--   * Time operations - File timestamps and modification times
--   * Binary I/O - Serialization and deserialization of binary data
--   * UTF-8 text - Text file reading and writing with proper encoding
--   * Archive operations - ZIP file extraction and package handling
--   * File system - Basic file/directory queries and operations
--
-- ==== Examples
--
-- >>> -- Time operations
-- >>> time <- getTime "src/Main.can"
-- >>> when (time > zeroTime) $ compileIfNewer "src/Main.can"
--
-- >>> -- Binary operations
-- >>> writeBinary "cache/interface.dat" compiledInterface
-- >>> maybeInterface <- readBinary "cache/interface.dat"
--
-- >>> -- UTF-8 text operations
-- >>> sourceCode <- readUtf8 "src/Main.can"
-- >>> writeUtf8 "build/Main.js" generatedJS
--
-- >>> -- Archive operations
-- >>> writePackage "/tmp/package" zipArchive
-- >>> maybeJson <- writePackageReturnCanopyJson "/tmp/package" zipArchive
--
-- >>> -- File system operations
-- >>> fileExists <- exists "canopy.json"
-- >>> canopyFiles <- listAllCanopyFilesRecursively "src"
--
-- ==== Module Organization
--
-- This coordinating module re-exports functionality from:
--   * "File.Time" - Time and timestamp operations
--   * "File.Binary" - Binary file I/O with error handling
--   * "File.Utf8" - UTF-8 text file operations
--   * "File.Archive" - ZIP archive and package extraction
--   * "File.FileSystem" - File system queries and manipulation
--
-- @since 0.19.1
module File
  ( -- * Time Operations
    -- | File modification time handling and comparison
    Time(..)
  , getTime
  , zeroTime
    -- * Binary File Operations
    -- | Binary serialization and deserialization with error handling
  , writeBinary
  , readBinary
    -- * UTF-8 Text Operations
    -- | Text file I/O with proper UTF-8 encoding
  , writeUtf8
  , readUtf8
  , writeBuilder
    -- * Atomic File Operations
    -- | Atomic writes that prevent corruption from partial writes or interruption
  , writeUtf8Atomic
  , writeBinaryAtomic
  , writeLazyBytesAtomic
  , writeBuilderAtomic
    -- * Archive Operations
    -- | ZIP file extraction and package handling
  , writePackage
  , writePackageReturnCanopyJson
    -- * File System Operations
    -- | Basic file and directory queries and manipulation
  , exists
  , remove
  , removeDir
  , listAllCanopyFilesRecursively
  ) where

-- Re-export time operations
import File.Time
  ( Time(..)
  , getTime
  , zeroTime
  )

-- Re-export binary file operations
import File.Binary
  ( writeBinary
  , readBinary
  )

-- Re-export UTF-8 text operations
import File.Utf8
  ( writeUtf8
  , readUtf8
  , writeBuilder
  )

-- Re-export archive operations
import File.Archive
  ( writePackage
  , writePackageReturnCanopyJson
  )

-- Re-export atomic operations
import File.Atomic
  ( writeUtf8Atomic
  , writeBinaryAtomic
  , writeLazyBytesAtomic
  , writeBuilderAtomic
  )

-- Re-export file system operations
import File.FileSystem
  ( exists
  , remove
  , removeDir
  , listAllCanopyFilesRecursively
  )
