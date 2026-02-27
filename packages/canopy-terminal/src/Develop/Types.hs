{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Core types and data structures for the development server.
--
-- This module provides the foundational types used throughout the
-- development server system. It includes configuration types, server
-- state, and various options for controlling development mode behavior.
--
-- == Key Types
--
-- * 'Flags' - Command-line configuration for the development server
-- * 'ServerConfig' - Internal server configuration with runtime settings
-- * 'CompileResult' - Result type for Canopy file compilation
-- * 'FileServeMode' - Different modes for serving files
--
-- == Lens Support
--
-- All types include comprehensive lens support for safe field access
-- and updates. Use the generated lenses instead of record syntax:
--
-- @
-- config <- setupServerConfig defaultFlags
-- let port = config ^. scPort
--     updated = config & scVerbose .~ True
-- @
--
-- == Error Handling
--
-- The module provides rich error types for different failure modes
-- in development server operations, following CLAUDE.md error handling
-- patterns.
--
-- @since 0.19.1
module Develop.Types
  ( -- * Configuration Types
    Flags (..),
    ServerConfig (..),

    -- * Result Types
    CompileResult (..),
    FileServeMode (..),

    -- * Lenses

    -- ** Flags Lenses
    flagsPort,

    -- ** ServerConfig Lenses
    scPort,
    scVerbose,
    scRoot,

    -- * Default Values
    defaultFlags,
    defaultServerConfig,
  )
where

import Control.Lens (makeLenses)
import Data.ByteString (ByteString)
import Data.ByteString.Builder (Builder)
import qualified Reporting.Exit as Exit

-- | Command-line flags for development server configuration.
--
-- Represents user-provided configuration options that control
-- development server behavior and networking setup.
--
-- @since 0.19.1
data Flags = Flags
  { -- | Optional port number for the development server
    _flagsPort :: !(Maybe Int)
  }
  deriving (Eq, Show)

-- | Internal server configuration with resolved settings.
--
-- Contains fully resolved configuration after processing command-line
-- flags and applying defaults. Used internally by server components.
--
-- @since 0.19.1
data ServerConfig = ServerConfig
  { -- | Resolved port number for the server
    _scPort :: !Int,
    -- | Enable verbose logging output
    _scVerbose :: !Bool,
    -- | Project root directory path
    _scRoot :: !(Maybe FilePath)
  }
  deriving (Eq, Show)

-- | Result of Canopy file compilation.
--
-- Represents the outcome of compiling a Canopy source file, either
-- successful compilation to HTML/JavaScript or a compilation error.
--
-- @since 0.19.1
data CompileResult
  = -- | Successful compilation with generated content
    CompileSuccess !Builder
  | -- | Compilation failed with error details
    CompileError !Exit.Reactor

-- | Different modes for serving files in development.
--
-- Controls how files are processed and served by the development server,
-- with different handling for code files, assets, and Canopy sources.
--
-- @since 0.19.1
data FileServeMode
  = -- | Serve file as-is without processing
    ServeRaw !FilePath
  | -- | Serve with syntax highlighting
    ServeCode !FilePath
  | -- | Compile and serve Canopy source file
    ServeCanopy !FilePath
  | -- | Serve static asset with content and MIME type
    ServeAsset !ByteString !ByteString
  deriving (Eq, Show)

-- Generate lenses for all types
makeLenses ''Flags
makeLenses ''ServerConfig

-- | Default command-line flags.
--
-- Provides sensible defaults for development server flags,
-- allowing customization of specific options while maintaining
-- reasonable default behavior.
--
-- @since 0.19.1
defaultFlags :: Flags
defaultFlags =
  Flags
    { _flagsPort = Nothing
    }

-- | Default server configuration.
--
-- Creates default server configuration with standard settings
-- suitable for most development scenarios.
--
-- @since 0.19.1
defaultServerConfig :: ServerConfig
defaultServerConfig =
  ServerConfig
    { _scPort = 8000,
      _scVerbose = False,
      _scRoot = Nothing
    }
