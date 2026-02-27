{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Core data types for the Diff system.
--
-- This module provides the fundamental data structures used throughout
-- the API difference analysis system. It defines the command-line arguments,
-- environment configuration, output formatting types, and associated lenses
-- following CLAUDE.md lens usage patterns.
--
-- == Key Types
--
-- * 'Args' - Command-line argument specification for different diff modes
-- * 'Env' - Runtime environment with package cache, HTTP manager, and registry
-- * 'Chunk' - Formatted output sections with magnitude and content
-- * 'Task' - Specialized task monad for diff operations
--
-- == Lens Usage
--
-- All record types provide lenses following CLAUDE.md patterns:
--
-- @
-- env <- Environment.setup
-- let cache = env ^. envCache
--     updatedEnv = env & envRegistry .~ newRegistry
-- @
--
-- == Design Philosophy
--
-- The types are designed for immutability and lens-based access,
-- eliminating direct record syntax in favor of clean functional updates.
-- Error types provide rich context for debugging and user feedback.
--
-- @since 0.19.1
module Diff.Types
  ( -- * Core Types
    Args (..),
    Env (..),
    Chunk (..),
    Task,

    -- * Lenses
    envMaybeRoot,
    envCache,
    envManager,
    envRegistry,
    chunkTitle,
    chunkMagnitude,
    chunkDetails,
  )
where

import qualified Canopy.Magnitude as Magnitude
import Canopy.Package (Name)
import Canopy.Version (Version)
import Control.Lens (makeLenses)
import qualified Deps.Registry as Registry
import qualified Http
import qualified Reporting.Doc as Doc
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Stuff

-- | Command-line argument specification for diff operations.
--
-- Supports multiple diff modes:
--
-- * 'CodeVsLatest' - Compare local code against latest published version
-- * 'CodeVsExactly' - Compare local code against specific version
-- * 'LocalInquiry' - Compare two specific versions locally
-- * 'GlobalInquiry' - Compare versions from package registry
--
-- @since 0.19.1
data Args
  = CodeVsLatest
  | CodeVsExactly Version
  | LocalInquiry Version Version
  | GlobalInquiry Name Version Version
  deriving (Eq, Show)

-- | Runtime environment for diff operations.
--
-- Contains all necessary resources for performing API difference analysis:
--
-- * Package cache for local storage
-- * HTTP manager for network requests
-- * Registry data for version lookups
-- * Optional project root directory
--
-- @since 0.19.1
data Env = Env
  { _envMaybeRoot :: !(Maybe FilePath),
    _envCache :: !Stuff.PackageCache,
    _envManager :: !Http.Manager,
    _envRegistry :: !Registry.CanopyRegistries
  }

-- | Formatted output section with magnitude classification.
--
-- Represents a section of diff output with:
--
-- * Descriptive title for the section
-- * Semantic versioning magnitude (MAJOR, MINOR, PATCH)
-- * Formatted documentation content
--
-- @since 0.19.1
data Chunk = Chunk
  { _chunkTitle :: !String,
    _chunkMagnitude :: !Magnitude.Magnitude,
    _chunkDetails :: !Doc.Doc
  }

-- | Specialized task monad for diff operations.
--
-- Provides structured error handling and context for diff-related operations.
-- Integrates with the broader Task system while maintaining diff-specific
-- error types and reporting.
--
-- @since 0.19.1
type Task a = Task.Task Exit.Diff a

-- Generate lenses for all record types
makeLenses ''Env
makeLenses ''Chunk
