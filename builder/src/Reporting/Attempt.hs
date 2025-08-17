{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Attempt - Exception handling and error reporting for Canopy build processes
--
-- This module provides comprehensive exception handling with automatic error
-- reporting and termination. It handles both expected business logic errors
-- and unexpected runtime exceptions, formatting them appropriately for different
-- output styles.
--
-- == Core Functions
--
-- * 'attempt' - Basic error handling with consistent formatting
-- * 'attemptWithStyle' - Style-aware error handling for different environments
--
-- == Exception Handling Strategy
--
-- The module implements a layered exception handling approach:
--
-- 1. **UserInterrupt Preservation** - Ctrl+C behavior is preserved for clean termination
-- 2. **Business Error Formatting** - Expected errors formatted with context and suggestions  
-- 3. **Unexpected Exception Reporting** - Runtime errors captured with diagnostic information
-- 4. **Style-Aware Output** - Error presentation adapts to execution environment
--
-- == Error Reporting Features
--
-- * **Context Preservation** - Maintains error context throughout the call stack
-- * **Community Resources** - Provides links to help and support channels
-- * **Diagnostic Information** - Includes technical details for troubleshooting
-- * **Graceful Termination** - Ensures clean process termination with appropriate exit codes
--
-- == Usage Examples
--
-- === Basic Error Handling
--
-- @
-- -- Handle compilation errors with automatic formatting
-- result <- attempt compileErrorToReport $ do
--   parseAndCompile "src/Main.elm"
-- -- On error: displays formatted error and exits
-- -- On success: returns compiled module
-- @
--
-- === Style-Aware Error Handling
--
-- @
-- -- Terminal mode with colored, interactive output
-- style <- terminal
-- result <- attemptWithStyle style errorToReport $ do
--   buildProject config
-- -- Shows formatted human-readable errors with colors
-- 
-- -- JSON mode for tool integration
-- let style = json
-- result <- attemptWithStyle style errorToReport $ do
--   processFile inputPath
-- -- Outputs structured JSON error objects
-- 
-- -- Silent mode for automation
-- let style = silent  
-- result <- attemptWithStyle style errorToReport $ do
--   runBatchProcess
-- -- No output, only exit codes indicate status
-- @
--
-- == Error Message Design
--
-- Error messages are designed following these principles:
--
-- * **Clear Problem Description** - What went wrong and why
-- * **Contextual Information** - Where the error occurred
-- * **Actionable Guidance** - How to resolve or work around the issue
-- * **Community Resources** - Where to get help if needed
-- * **Technical Details** - Diagnostic information for advanced users
--
-- @since 0.19.1
module Reporting.Attempt
  ( -- * Error Handling
    attempt
  , attemptWithStyle
    -- * Exception Utilities
  , reportExceptionsNicely
  , putException
  ) where

import Control.Concurrent (readMVar)
import Control.Exception (AsyncException (UserInterrupt), SomeException, catch, fromException, throw)
import qualified Data.ByteString.Builder as B
import qualified Json.Encode as Encode
import Reporting.Doc ((<+>))
import qualified Reporting.Doc as D
import qualified Reporting.Exit as Exit
import qualified Reporting.Exit.Help as Help
import Reporting.Style (Style(..))
import qualified System.Exit as Exit
import System.IO (hPutStrLn, stderr)

-- | Execute work with automatic error reporting and termination.
--
-- Runs the provided IO action and handles both success and failure cases.
-- On success, returns the result value. On failure, formats the error
-- using the provided reporting function, displays it to stderr, and
-- terminates the process with failure exit code.
--
-- All exceptions are caught and reported with diagnostic information
-- to help users understand unexpected failures. UserInterrupt exceptions
-- (Ctrl+C) are preserved to allow clean termination.
--
-- ==== Examples
--
-- @
-- -- Compile module with automatic error reporting
-- result <- attempt compileErrorToReport $ do
--   parseAndCompile "src/Main.elm"
-- -- On error: displays formatted error and exits
-- -- On success: returns compiled module
-- @
--
-- @
-- -- Handle package installation errors
-- packages <- attempt packageErrorToReport $ do
--   resolveAndInstallDependencies projectConfig
-- -- Automatically formats dependency resolution errors
-- @
--
-- ==== Error Handling
--
-- The function handles these exception types:
--
-- * 'UserInterrupt' - Re-thrown to preserve Ctrl+C behavior
-- * 'SomeException' - Caught, reported with context, then re-thrown
-- * Business logic errors - Formatted using provided reporter
--
-- ==== Performance
--
-- Error handling adds minimal overhead to successful operations.
-- Exception catching and reporting only impacts failed operations.
--
-- @since 0.19.1
attempt :: (x -> Help.Report) -> IO (Either x a) -> IO a
attempt toReport work =
  do
    result <- work `catch` reportExceptionsNicely
    case result of
      Right a ->
        return a
      Left x ->
        do
          Exit.toStderr (toReport x)
          Exit.exitFailure

-- | Execute work with style-specific error reporting and termination.
--
-- Similar to 'attempt' but allows customization of error output format
-- based on the reporting style. This enables consistent error presentation
-- across different execution environments (interactive, automated, tooling).
--
-- The style determines error output behavior:
--
-- * 'Silent' - No error output, only exit code
-- * 'Json' - Structured JSON error output to stderr
-- * 'Terminal' - Formatted human-readable error with colors
--
-- ==== Examples
--
-- @
-- -- Interactive terminal error reporting
-- style <- terminal
-- result <- attemptWithStyle style compileErrorToReport $ do
--   compileProject config
-- -- Shows colored, formatted errors in terminal
-- @
--
-- @
-- -- JSON output for IDE integration
-- let style = json
-- result <- attemptWithStyle style errorToReport $ do
--   processFile inputPath
-- -- Outputs: {"type":"error","message":"...",...}
-- @
--
-- @
-- -- Silent mode for CI/automation
-- let style = silent
-- result <- attemptWithStyle style errorToReport $ do
--   buildProject
-- -- No output, only exit code indicates success/failure
-- @
--
-- ==== Thread Safety
--
-- When using Terminal style, the MVar ensures thread-safe error output
-- even when multiple concurrent operations might fail simultaneously.
--
-- ==== JSON Error Format
--
-- JSON style produces structured error output:
--
-- @
-- {
--   "type": "build_error",
--   "title": "COMPILATION ERROR",
--   "message": "Detailed error description",
--   "path": "src/Main.elm",
--   "problems": [...]
-- }
-- @
--
-- @since 0.19.1
attemptWithStyle :: Style -> (x -> Help.Report) -> IO (Either x a) -> IO a
attemptWithStyle style toReport work =
  do
    result <- work `catch` reportExceptionsNicely
    case result of
      Right a ->
        return a
      Left x ->
        case style of
          Silent ->
            Exit.exitFailure
          Json ->
            do
              B.hPutBuilder stderr (Encode.encodeUgly (Exit.toJson (toReport x)))
              Exit.exitFailure
          Terminal mvar ->
            do
              _ <- readMVar mvar
              Exit.toStderr (toReport x)
              Exit.exitFailure

-- | Handle exceptions with user-friendly reporting.
--
-- Catches unexpected exceptions and provides helpful diagnostic information
-- before re-throwing them. Special handling for 'UserInterrupt' (Ctrl+C)
-- preserves clean termination behavior.
--
-- This function is used internally by 'attempt' and 'attemptWithStyle' to
-- ensure that even unexpected failures provide useful information to users.
--
-- ==== Exception Handling Strategy
--
-- * 'UserInterrupt' - Re-thrown immediately to preserve Ctrl+C behavior
-- * Other exceptions - Reported with context, then re-thrown
--
-- ==== Error Report Format
--
-- Generates a comprehensive error report including:
--
-- * Clear error header with visual separation
-- * Extracted exception information with context
-- * Community resources for getting help
-- * Instructions for bug reporting
-- * Guidance on creating minimal reproduction cases
--
-- ==== Examples
--
-- @
-- -- Used internally by attempt functions
-- result <- work `catch` reportExceptionsNicely
-- -- On exception: shows diagnostic info, then re-throws
-- @
--
-- ==== Thread Safety
--
-- Uses stderr for output to avoid interfering with normal program output.
-- Multiple threads can safely call this function, though the error reports
-- may be interleaved.
--
-- @since 0.19.1
reportExceptionsNicely :: SomeException -> IO a
reportExceptionsNicely e =
  case fromException e of
    Just UserInterrupt -> throw e
    _ -> putException e >> throw e

-- | Display detailed exception information to stderr.
--
-- Formats unexpected exceptions with comprehensive context to help users
-- understand what went wrong and how to get help. The output includes:
--
-- * Clear visual separation with header bars
-- * Exception details with proper formatting
-- * Community resources and support information
-- * Bug reporting instructions with guidance
-- * Architectural context for resolution expectations
--
-- ==== Output Format
--
-- Produces a structured error report:
--
-- @
-- -- ERROR -----------------------------------------------------------------------
-- I ran into something that bypassed the normal error reporting process!
-- I extracted whatever information I could from the internal error:
-- 
-- >   [exception details]
-- 
-- These errors are usually pretty confusing, so start by asking around...
-- 
-- -- REQUEST ---------------------------------------------------------------------
-- If you are feeling up to it, please try to get your code down to the smallest
-- version that still triggers this message...
-- @
--
-- ==== Design Philosophy
--
-- The error message is designed to:
--
-- * Acknowledge the confusing nature of internal errors
-- * Provide clear next steps for users
-- * Encourage community engagement before bug reports
-- * Guide users toward creating helpful bug reports
-- * Set appropriate expectations about resolution timeframes
--
-- @since 0.19.1
putException :: SomeException -> IO ()
putException e = do
  hPutStrLn stderr ""
  Help.toStderr . D.stack $
    [ D.dullyellow "-- ERROR -----------------------------------------------------------------------",
      D.reflow
        "I ran into something that bypassed the normal error reporting process!\
        \ I extracted whatever information I could from the internal error:",
      D.vcat $ fmap (\line -> D.red ">" <+> "   " <+> D.fromChars line) (lines (show e)),
      D.reflow
        "These errors are usually pretty confusing, so start by asking around on one of\
        \ forums listed at https://canopy-lang.org/community to see if anyone can get you\
        \ unstuck quickly.",
      D.dullyellow "-- REQUEST ---------------------------------------------------------------------",
      D.reflow
        "If you are feeling up to it, please try to get your code down to the smallest\
        \ version that still triggers this message. Ideally in a single Main.canopy and\
        \ canopy.json file.",
      D.reflow
        "From there open a NEW issue at https://github.com/canopy/compiler/issues with\
        \ your reduced example pasted in directly. (Not a link to a repo or gist!) Do not\
        \ worry about if someone else saw something similar. More examples is better!",
      D.reflow
        "This kind of error is usually tied up in larger architectural choices that are\
        \ hard to change, so even when we have a couple good examples, it can take some\
        \ time to resolve in a solid way."
    ]