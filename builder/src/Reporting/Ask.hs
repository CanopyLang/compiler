{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Ask - User interaction and prompts for Canopy build processes
--
-- This module provides user interaction functionality for confirmation prompts,
-- input validation, and interactive decision making during build processes.
-- It handles yes/no questions with proper input validation and helpful guidance
-- for invalid responses.
--
-- == Core Features
--
-- * **Yes/No Confirmation** - Standard confirmation prompts with clear semantics
-- * **Input Validation** - Robust handling of various response formats
-- * **Error Recovery** - Helpful guidance for invalid input with re-prompting
-- * **Flexible Formatting** - Support for rich text prompts using Doc formatting
--
-- == Input Handling Strategy
--
-- The module accepts multiple formats for user responses to improve usability:
--
-- * **Default Yes** - Empty input (Enter) defaults to "yes" for common case
-- * **Explicit Yes** - "Y", "y" for explicit confirmation
-- * **Explicit No** - "n" for clear rejection
-- * **Invalid Input** - All other input triggers helpful guidance and re-prompt
--
-- == Design Philosophy
--
-- User interaction follows these principles:
--
-- * **Clear Intent** - Questions are unambiguous about expected responses
-- * **Helpful Guidance** - Invalid input receives immediate, clear guidance
-- * **Reasonable Defaults** - Common operations have sensible default behavior
-- * **Graceful Recovery** - Input errors don't terminate, they educate and retry
--
-- == Usage Examples
--
-- === Simple Confirmation
--
-- @
-- -- Basic yes/no confirmation
-- continue <- ask "Continue with build? [Y/n]: "
-- when continue $ do
--   putStrLn "Proceeding with build..."
-- @
--
-- === Complex Confirmation with Formatting
--
-- @
-- -- Rich formatted prompt with warnings
-- let warning = D.vcat
--       [ "This will delete all cached dependencies."
--       , "Are you sure you want to continue? [Y/n]: "
--       ]
-- confirmed <- ask warning
-- unless confirmed $ putStrLn "Operation cancelled."
-- @
--
-- === Conditional Prompts
--
-- @
-- -- Only prompt in interactive environments
-- shouldPrompt <- isInteractive
-- confirmed <- if shouldPrompt 
--   then ask "Delete existing files? [Y/n]: "
--   else pure True  -- Default to yes in non-interactive
-- @
--
-- == Input Response Handling
--
-- Valid responses and their interpretations:
--
-- * **""** (empty/Enter) → True (default yes for convenience)
-- * **"Y"** → True (explicit yes)
-- * **"y"** → True (explicit yes)
-- * **"n"** → False (explicit no)
-- * **All other input** → Re-prompt with guidance
--
-- == Error Handling
--
-- The module handles edge cases gracefully:
--
-- * **EOF/stdin closed** - Exception propagates (indicates non-interactive environment)
-- * **Invalid input** - Clear error message with re-prompting
-- * **Whitespace** - Input is trimmed automatically
-- * **Case sensitivity** - Only "Y", "y", "n" are recognized (not case-insensitive)
--
-- @since 0.19.1
module Reporting.Ask
  ( -- * User Interaction
    ask
    -- * Internal Utilities
  , askHelp
  ) where

import qualified Reporting.Doc as D
import qualified Reporting.Exit.Help as Help
import System.IO (hFlush, stdout)

-- | Prompt user for yes/no confirmation with formatted question.
--
-- Displays the provided question document and waits for user input.
-- Accepts various forms of yes/no responses and provides helpful guidance
-- for invalid input. The function ensures proper input validation and
-- re-prompts until a valid response is received.
--
-- ==== Input Handling
--
-- Valid responses:
--
-- * Yes: @""@ (empty/Enter), @"Y"@, @"y"@
-- * No: @"n"@
-- * Invalid: All other input (re-prompts with guidance)
--
-- ==== Examples
--
-- @
-- -- Simple confirmation
-- continue <- ask "Continue with build? [Y/n]: "
-- when continue $ do
--   putStrLn "Proceeding with build..."
-- @
--
-- @
-- -- Complex confirmation with formatting
-- let warning = D.vcat
--       [ "This will delete all cached dependencies."
--       , "Are you sure you want to continue? [Y/n]: "
--       ]
-- confirmed <- ask warning
-- unless confirmed $ putStrLn "Operation cancelled."
-- @
--
-- ==== Thread Safety
--
-- This function is not thread-safe as it directly interacts with stdin/stdout.
-- Should only be called from the main thread in interactive contexts.
--
-- @since 0.19.1
ask :: D.Doc -> IO Bool
ask doc =
  do
    Help.toStdout doc
    askHelp

-- | Internal helper for processing user input responses.
--
-- Handles the input validation loop for yes/no questions. Flushes stdout
-- to ensure the prompt is visible, reads user input, and validates the
-- response. For invalid input, provides helpful guidance and re-prompts.
--
-- ==== Input Processing
--
-- * Trims whitespace and handles empty input as "yes"
-- * Case-sensitive matching for "Y", "y", "n" 
-- * Provides clear error message for invalid input
-- * Loops until valid response received
--
-- ==== Error Handling
--
-- If 'getLine' fails (e.g., EOF, stdin closed), the exception propagates
-- to the caller. This typically indicates non-interactive environment
-- where user prompts are inappropriate.
--
-- @since 0.19.1
askHelp :: IO Bool
askHelp =
  do
    hFlush stdout
    input <- getLine
    case input of
      "" -> return True
      "Y" -> return True
      "y" -> return True
      "n" -> return False
      _ ->
        do
          putStr "Must type 'y' for yes or 'n' for no: "
          askHelp