{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Style - Output style management for Canopy build processes
--
-- This module provides output style configuration that determines how progress
-- updates, errors, and user interactions are presented. Each style is designed
-- for different execution environments and use cases.
--
-- == Supported Styles
--
-- * **Silent** - Suppresses all output for automated builds and CI environments
-- * **Json** - Structured JSON output for tooling integration and IDE support
-- * **Terminal** - Interactive output with real-time progress indicators and colors
--
-- == Style Selection Strategy
--
-- Choose styles based on your execution environment:
--
-- * Use 'silent' in CI/CD pipelines, scripts, or batch processing
-- * Use 'json' for IDE integration, build tools, or machine consumption
-- * Use 'terminal' for interactive development and user-facing operations
--
-- == Thread Safety
--
-- The Terminal style includes MVar synchronization to prevent output corruption
-- during concurrent progress updates. Multiple threads can safely report progress
-- simultaneously without interfering with each other's output.
--
-- == Usage Examples
--
-- === Silent Mode for Automation
--
-- @
-- -- Use in CI environments where output should be minimal
-- let style = silent
-- result <- processWithStyle style compilerWork
-- -- Only exit codes indicate success/failure
-- @
--
-- === JSON for Tool Integration
--
-- @
-- -- Structured output for IDE or build tool consumption
-- let style = json
-- result <- processWithStyle style buildWork
-- -- Errors formatted as JSON objects for machine parsing
-- @
--
-- === Interactive Terminal Mode
--
-- @
-- -- Real-time progress with user interaction
-- style <- terminal
-- result <- processWithStyle style interactiveWork
-- -- Shows progress bars, colored output, prompts
-- @
--
-- @since 0.19.1
module Reporting.Style
  ( -- * Style Types
    Style(..)
    -- * Style Constructors
  , silent
  , json
  , terminal
  ) where

import Control.Concurrent (MVar, newMVar)

-- | Output style configuration for the reporting system.
--
-- Determines how progress updates, errors, and user interactions are
-- presented. Each style is designed for different use cases:
--
-- * 'Silent' - No output, for automated builds
-- * 'Json' - Structured output for tooling integration  
-- * 'Terminal' - Interactive output with progress indicators
--
-- The Terminal style includes an MVar for thread synchronization to prevent
-- output corruption during concurrent progress updates.
--
-- @since 0.19.1
data Style
  = -- | Suppresses all output for automated environments.
    --
    -- Used in CI/CD pipelines, scripts, or when output should be minimal.
    -- Errors still cause process termination but without user-visible messages.
    Silent
  | -- | Structured JSON output for tool integration.
    --
    -- Produces machine-readable JSON for integration with IDEs, build tools,
    -- or other automated systems. Error information is serialized as JSON objects.
    Json
  | -- | Interactive terminal output with progress indicators.
    --
    -- Provides real-time progress updates, colored output, and user interaction
    -- prompts. The MVar ensures thread-safe output in concurrent scenarios.
    Terminal !(MVar ())

-- | Create a silent reporting style that suppresses all output.
--
-- Used in automated builds, CI environments, or when output should be minimal.
-- The process will still exit with appropriate codes on errors, but without
-- user-visible error messages.
--
-- ==== Examples
--
-- @
-- style <- pure silent
-- result <- attemptWithStyle style toReport someWork
-- -- No output produced, but exit codes preserved
-- @
--
-- @since 0.19.1
silent :: Style
silent =
  Silent

-- | Create a JSON reporting style for structured output.
--
-- Produces machine-readable JSON output suitable for IDE integration,
-- build tool consumption, or automated processing. Error information
-- is serialized as JSON objects with consistent structure.
--
-- ==== Examples
--
-- @
-- style <- pure json
-- result <- attemptWithStyle style toReport compileWork
-- -- Errors output as: {"type":"error","message":"...","details":{...}}
-- @
--
-- ==== JSON Error Format
--
-- Errors are serialized with the following structure:
--
-- @
-- {
--   "type": "compile_error",
--   "message": "Type mismatch in function",
--   "location": {"file": "Main.elm", "line": 42},
--   "details": {...}
-- }
-- @
--
-- @since 0.19.1
json :: Style
json =
  Json

-- | Create a terminal reporting style with interactive progress indicators.
--
-- Provides real-time progress updates, colored output, user interaction prompts,
-- and platform-appropriate terminal characters. Uses MVar synchronization to
-- ensure thread-safe output during concurrent operations.
--
-- ==== Examples
--
-- @
-- style <- terminal
-- result <- trackDetails style $ \key -> do
--   report key (DStart 10)
--   -- Shows: "Verifying dependencies (0/10)"
--   processWork key
--   -- Updates in real-time as work progresses
-- @
--
-- ==== Terminal Features
--
-- * Real-time progress bars and counters
-- * Platform-appropriate Unicode characters (Windows fallbacks)
-- * Colored success/failure indicators
-- * Interactive user prompts with validation
-- * Thread-safe concurrent updates
--
-- ==== Thread Safety
--
-- The MVar ensures that multiple threads can safely update progress without
-- corrupting terminal output. Progress updates are serialized through the MVar.
--
-- @since 0.19.1
terminal :: IO Style
terminal =
  Terminal <$> newMVar ()