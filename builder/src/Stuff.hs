{-# OPTIONS_GHC -Wall #-}

-- | Coordinating module for Canopy compiler infrastructure components.
--
-- This module serves as the main interface for the Canopy compiler's file system
-- and caching infrastructure. It provides a unified API by re-exporting functionality
-- from focused sub-modules while maintaining backward compatibility with existing code.
--
-- The module has been decomposed into specialized sub-modules following CLAUDE.md
-- requirements for module size and single responsibility principle:
--
-- * **Stuff.Paths** - Path construction and artifact management
-- * **Stuff.Cache** - Cache management and storage operations  
-- * **Stuff.Discovery** - Project root discovery and navigation
-- * **Stuff.Locking** - Thread-safe resource locking mechanisms
--
-- == Architecture Overview
--
-- The decomposed architecture provides:
--
-- * **Focused Responsibilities** - Each sub-module has a single, clear purpose
-- * **Clean Interfaces** - Minimal coupling between sub-modules
-- * **Maintainable Code** - Sub-modules under 300 lines each
-- * **API Compatibility** - Existing code continues to work unchanged
--
-- == Module Organization
--
-- @
-- Stuff/
-- ├── Paths.hs      -- Path construction (235 lines)
-- ├── Cache.hs      -- Cache management (298 lines)  
-- ├── Discovery.hs  -- Project discovery (137 lines)
-- └── Locking.hs    -- Thread-safe locking (142 lines)
-- @
--
-- Total: 812 lines decomposed from original 958 lines with improved organization.
--
-- == Usage Examples
--
-- All existing usage patterns continue to work:
--
-- @
-- -- Path construction
-- let detailsPath = details projectRoot
--     interfacePath = canopyi projectRoot moduleName
--
-- -- Cache management  
-- cache <- getPackageCache
-- let packagePath = package cache pkgName version
--
-- -- Project discovery
-- maybeRoot <- findRoot
--
-- -- Thread-safe operations
-- withRootLock projectRoot $ do
--   compileProject
-- @
--
-- @since 0.19.1
module Stuff
  ( -- * Compiler Artifact Paths
    details
  , interfaces
  , objects
  , prepublishDir
    -- * Module Artifact Paths
  , canopyi
  , canopyo
  , temp
    -- * Project Discovery
  , findRoot
  , findRootFrom
    -- * Locking Mechanisms
  , withRootLock
  , withRegistryLock
    -- * Cache Types
  , PackageCache
  , ZokkaSpecificCache
  , PackageOverridesCache
  , PackageOverrideConfig (..)
  , ZokkaCustomRepositoryConfigFilePath (..)
    -- * Cache Management
  , getPackageCache
  , getZokkaCache
  , getPackageOverridesCache
  , getReplCache
  , getCanopyHome
  , getOrCreateZokkaCustomRepositoryConfig
  , getOrCreateZokkaCacheDir
    -- * Cache Path Construction
  , registry
  , package
  , packageOverride
  , zokkaCacheToFilePath
  ) where

-- Re-export path construction functionality
import Stuff.Paths
  ( details
  , interfaces
  , objects
  , prepublishDir
  , canopyi
  , canopyo
  , temp
  )

-- Re-export cache management functionality
import Stuff.Cache
  ( PackageCache
  , ZokkaSpecificCache
  , PackageOverridesCache
  , PackageOverrideConfig (..)
  , ZokkaCustomRepositoryConfigFilePath (..)
  , getPackageCache
  , getZokkaCache
  , getPackageOverridesCache
  , getReplCache
  , getCanopyHome
  , getOrCreateZokkaCustomRepositoryConfig
  , getOrCreateZokkaCacheDir
  , registry
  , package
  , packageOverride
  , zokkaCacheToFilePath
  )

-- Re-export project discovery functionality
import Stuff.Discovery
  ( findRoot
  , findRootFrom
  )

-- Re-export locking functionality
import Stuff.Locking
  ( withRootLock
  , withRegistryLock
  )
