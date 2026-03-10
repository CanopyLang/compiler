{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

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
    noSplit,
    ffiUnsafe,
    ffiDebug,
    jobs,
    verifyReproducible,
    allowKernel,
    outputFormat,

    -- ** BuildContext Lenses
    bcStyle,
    bcRoot,
    bcDetails,
    bcDesiredMode,
    bcPackage,
    bcFfiUnsafe,
    bcFfiDebug,
    bcOutputFormat,

    -- * Type Aliases
    Task,
  )
where

import qualified Canopy.Details as Details
import Control.Lens.TH (makeLenses)
import Generate.Mode (OutputFormat (..))
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
  { -- | Enable debug mode (disables optimization)
    _debug :: !Bool,
    -- | Enable production optimizations
    _optimize :: !Bool,
    -- | Enable file watching for continuous builds
    _watch :: !Bool,
    -- | Specific output target (overrides default behavior)
    _output :: !(Maybe Output),
    -- | Error reporting format
    _report :: !(Maybe ReportType),
    -- | Documentation output file
    _docs :: !(Maybe FilePath),
    -- | Enable verbose logging
    _verbose :: !Bool,
    -- | Disable code splitting even when lazy imports are present
    _noSplit :: !Bool,
    -- | Disable FFI runtime type validation (unsafe mode)
    _ffiUnsafe :: !Bool,
    -- | Enable verbose FFI debug logging in generated validators
    _ffiDebug :: !Bool,
    -- | Maximum parallel compilation jobs (0 = auto-detect from CPU count)
    _jobs :: !(Maybe Int),
    -- | Build twice and compare output to verify reproducibility
    _verifyReproducible :: !Bool,
    -- | Explicitly allow third-party packages that use kernel code
    _allowKernel :: !Bool,
    -- | Output format: ESM (default) or IIFE. Nothing means ESM.
    _outputFormat :: !(Maybe OutputFormat)
  }
  deriving (Eq, Show)

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
  { -- | Error reporting and output style
    _bcStyle :: !Reporting.Style,
    -- | Project root directory
    _bcRoot :: !FilePath,
    -- | Project configuration and metadata
    _bcDetails :: !Details.Details,
    -- | Target build mode
    _bcDesiredMode :: !DesiredMode,
    -- | Package name
    _bcPackage :: !Details.PkgName,
    -- | FFI unsafe mode (disables runtime validation)
    _bcFfiUnsafe :: !Bool,
    -- | FFI debug mode (verbose validator error messages)
    _bcFfiDebug :: !Bool,
    -- | Output format (ESM or IIFE)
    _bcOutputFormat :: !OutputFormat
  }

-- | Output format and target file.
--
-- Specifies where and how to generate the final build artifacts.
-- Supports JavaScript, HTML, and null output for testing.
data Output
  = -- | Generate JavaScript to specified file
    JS !FilePath
  | -- | Generate HTML to specified file
    Html !FilePath
  | -- | Generate nothing (for testing/benchmarking)
    DevNull
  deriving (Eq, Show)

-- | Error reporting format options.
--
-- Currently supports only JSON format for structured error output,
-- with terminal format as the default.
data ReportType
  = -- | JSON-formatted error output
    Json
  deriving (Eq, Show)

-- | Build mode determining optimization level and debug information.
--
-- Controls the compilation pipeline and output characteristics:
--   * 'Debug' - Maximum debug info, no optimization
--   * 'Dev' - Fast compilation, minimal optimization
--   * 'Prod' - Full optimization, minimal size
data DesiredMode
  = -- | Debug mode with full debug information
    Debug
  | -- | Development mode with fast compilation
    Dev
  | -- | Production mode with full optimization
    Prod
  deriving (Eq, Show)

-- | Task monad for build operations.
--
-- Provides error handling and IO capabilities for build processes.
-- All build operations run within this monad.
type Task a = Task.Task Exit.Make a

-- Generate lenses for record types
makeLenses ''Flags
makeLenses ''BuildContext
