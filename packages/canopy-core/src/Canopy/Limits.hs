{-# LANGUAGE OverloadedStrings #-}

-- | Defensive size limits for the Canopy compiler.
--
-- These limits prevent accidental or malicious resource exhaustion
-- at system boundaries. They are deliberately generous -- a project
-- would need to be enormous to exceed any of them -- but they
-- provide a safety net against unbounded memory consumption.
--
-- All limits are constant and compile-time known. They are checked
-- at IO boundaries (file reads, config parsing) rather than deep
-- in the compilation pipeline, keeping the core logic clean.
--
-- == Rationale
--
-- * 'maxSourceFileBytes' (10 MB): Largest known Elm/Canopy modules
--   in production are under 1 MB. 10 MB covers 10x growth.
-- * 'maxOutlineBytes' (1 MB): A canopy.json with 200 dependencies
--   is typically under 10 KB. 1 MB is extremely generous.
-- * 'maxLockFileBytes' (10 MB): Lock files grow linearly with
--   dependency count. 10 MB covers thousands of packages.
-- * 'maxDependencyCount' (200): Even large frameworks have fewer
--   than 50 direct dependencies.
-- * 'maxModuleCount' (10000): The largest Elm codebases known
--   have around 1000 modules.
-- * 'maxImportsPerModule' (500): Well-structured modules import
--   fewer than 50 modules. 500 covers pathological cases.
--
-- @since 0.19.2
module Canopy.Limits
  ( -- * File Size Limits
    maxSourceFileBytes,
    maxOutlineBytes,
    maxLockFileBytes,

    -- * Count Limits
    maxDependencyCount,
    maxModuleCount,
    maxImportsPerModule,

    -- * Validation
    checkFileSize,
    FileSizeError (..),
  )
where

-- | Maximum source file size in bytes (10 MB).
--
-- Files exceeding this limit are rejected before parsing to prevent
-- out-of-memory conditions during compilation.
--
-- @since 0.19.2
maxSourceFileBytes :: Int
maxSourceFileBytes = 10 * 1024 * 1024

-- | Maximum canopy.json file size in bytes (1 MB).
--
-- Project configuration files should be small. This limit catches
-- corrupted or accidentally-swapped files.
--
-- @since 0.19.2
maxOutlineBytes :: Int
maxOutlineBytes = 1024 * 1024

-- | Maximum canopy.lock file size in bytes (10 MB).
--
-- Lock files contain dependency resolution data. This limit prevents
-- corrupted lock files from consuming excessive memory during parsing.
--
-- @since 0.19.2
maxLockFileBytes :: Int
maxLockFileBytes = 10 * 1024 * 1024

-- | Maximum number of direct dependencies.
--
-- Checked after parsing canopy.json. Projects exceeding this limit
-- likely have a configuration error.
--
-- @since 0.19.2
maxDependencyCount :: Int
maxDependencyCount = 200

-- | Maximum number of modules in a single project.
--
-- Checked during module discovery. Prevents unbounded memory
-- growth in the dependency graph.
--
-- @since 0.19.2
maxModuleCount :: Int
maxModuleCount = 10000

-- | Maximum number of imports per module.
--
-- Checked after parsing a module header. Modules with extremely
-- many imports are likely generated or malformed.
--
-- @since 0.19.2
maxImportsPerModule :: Int
maxImportsPerModule = 500

-- | Result of a file size check.
--
-- @since 0.19.2
data FileSizeError = FileSizeError
  { _filePath :: !FilePath,
    _actualSize :: !Int,
    _maxSize :: !Int
  }
  deriving (Eq, Show)

-- | Check whether a file's byte count exceeds the given limit.
--
-- Returns 'Nothing' if the size is within bounds, or
-- 'Just FileSizeError' with diagnostic information.
--
-- @since 0.19.2
checkFileSize :: FilePath -> Int -> Int -> Maybe FileSizeError
checkFileSize path actualSize limit
  | actualSize > limit = Just (FileSizeError path actualSize limit)
  | otherwise = Nothing
