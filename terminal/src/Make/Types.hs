{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Core types and data structures for the Make system.
--
-- This module defines the fundamental data types used throughout the
-- Canopy build system, including flags, build context, output formats,
-- and reporting options. All types support lens-based access patterns
-- for clean record manipulation.
--
-- Key types:
--   * 'Flags' - Command line flags and build options
--   * 'BuildContext' - Shared build environment and configuration  
--   * 'Output' - Target output format (JS, HTML, DevNull)
--   * 'ReportType' - Error reporting format options
--   * 'DesiredMode' - Build mode (Debug, Dev, Prod)
--
-- All record types include generated lenses for field access.
--
-- @since 0.19.1
module Make.Types
  ( -- * Core Types
    Flags (..),
    BuildContext (..),
    Output (..),
    ReportType (..),
    DesiredMode (..),

    -- * Lenses
    -- ** Flags Lenses
    debug,
    optimize,
    watch,
    output,
    report,
    docs,
    verbose,

    -- ** BuildContext Lenses  
    bcStyle,
    bcRoot,
    bcDetails,
    bcDesiredMode,

    -- * Type Aliases
    Task,
  )
where

import Control.Lens.TH (makeLenses)
import qualified Canopy.Details as Details
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task

-- | Command line flags and build options.
--
-- Contains all user-configurable options for the build process,
-- including output format, optimization level, and reporting preferences.
--
-- Use lenses for field access:
--
-- @
-- flags ^. debug        -- Get debug flag
-- flags & optimize .~ True  -- Set optimize flag
-- @
data Flags = Flags
  { _debug :: !Bool
    -- ^ Enable debug mode (disables optimization)
  , _optimize :: !Bool  
    -- ^ Enable production optimizations
  , _watch :: !Bool
    -- ^ Enable file watching for continuous builds
  , _output :: !(Maybe Output)
    -- ^ Specific output target (overrides default behavior)
  , _report :: !(Maybe ReportType)
    -- ^ Error reporting format
  , _docs :: !(Maybe FilePath)
    -- ^ Documentation output file
  , _verbose :: !Bool
    -- ^ Enable verbose logging
  } deriving (Eq, Show)

-- | Build environment and shared configuration.
--
-- Contains the context needed throughout the build process,
-- including project details, file paths, and build settings.
--
-- Use lenses for field access:
--
-- @
-- ctx ^. bcRoot         -- Get project root
-- ctx & bcStyle .~ newStyle  -- Update reporting style
-- @
data BuildContext = BuildContext
  { _bcStyle :: !Reporting.Style
    -- ^ Error reporting and output style
  , _bcRoot :: !FilePath
    -- ^ Project root directory
  , _bcDetails :: !Details.Details
    -- ^ Project configuration and metadata
  , _bcDesiredMode :: !DesiredMode
    -- ^ Target build mode
  }

-- | Output format and target file.
--
-- Specifies where and how to generate the final build artifacts.
-- Supports JavaScript, HTML, and null output for testing.
data Output
  = JS !FilePath
    -- ^ Generate JavaScript to specified file
  | Html !FilePath  
    -- ^ Generate HTML to specified file
  | DevNull
    -- ^ Generate nothing (for testing/benchmarking)
  deriving (Eq, Show)

-- | Error reporting format options.
--
-- Currently supports only JSON format for structured error output,
-- with terminal format as the default.
data ReportType
  = Json
    -- ^ JSON-formatted error output
  deriving (Eq, Show)

-- | Build mode determining optimization level and debug information.
--
-- Controls the compilation pipeline and output characteristics:
--   * 'Debug' - Maximum debug info, no optimization
--   * 'Dev' - Fast compilation, minimal optimization  
--   * 'Prod' - Full optimization, minimal size
data DesiredMode 
  = Debug
    -- ^ Debug mode with full debug information
  | Dev
    -- ^ Development mode with fast compilation
  | Prod  
    -- ^ Production mode with full optimization
  deriving (Eq, Show)

-- | Task monad for build operations.
--
-- Provides error handling and IO capabilities for build processes.
-- All build operations run within this monad.
type Task a = Task.Task Exit.Make a

-- Generate lenses for record types
makeLenses ''Flags
makeLenses ''BuildContext