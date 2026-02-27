{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Terminal error handling and help display system.
--
-- This module provides comprehensive error reporting and help text
-- generation for the Terminal framework. It handles all error conditions
-- that can occur during command-line argument parsing and provides
-- user-friendly error messages with intelligent suggestions.
--
-- == Architecture
--
-- The module follows a modular design pattern with specialized sub-modules:
--
-- * 'Terminal.Error.Types' - Core error types and data structures with lenses
-- * 'Terminal.Error.Display' - Error rendering and terminal output formatting
-- * 'Terminal.Error.Formatting' - Text formatting utilities and color schemes
-- * 'Terminal.Error.Suggestions' - Intelligent suggestion generation algorithms
-- * 'Terminal.Error.Help' - Help text generation and command documentation
--
-- == Key Features
--
-- * Rich error types with comprehensive context information
-- * Intelligent suggestion generation using edit distance algorithms
-- * Terminal-aware formatting with color support and plain text fallback
-- * Comprehensive help generation for commands and application overviews
-- * Modular architecture enabling focused testing and maintenance
--
-- == Error Handling Philosophy
--
-- All errors are designed to be maximally helpful to users:
--
-- 1. **Context-Rich** - Errors include sufficient information for diagnosis
-- 2. **Actionable** - Every error suggests concrete steps for resolution
-- 3. **Consistent** - Uniform formatting and presentation across error types
-- 4. **Intelligent** - Smart suggestions based on available alternatives
--
-- == Usage Examples
--
-- @
-- -- Display command help
-- exitWithHelp (Just "build") details examples args flags
--
-- -- Handle argument error
-- case parseResult of
--   Left error -> exitWithError error
--   Right result -> processResult result
--
-- -- Show application overview
-- exitWithOverview intro outro allCommands
--
-- -- Handle unknown command with suggestions
-- exitWithUnknown "biuld" ["build", "test", "install"]
-- @
--
-- == Error Recovery
--
-- The error system provides multiple recovery mechanisms:
--
-- * **Typo correction** - Edit distance-based suggestions for misspelled commands/flags
-- * **Format guidance** - Examples and type expectations for invalid values
-- * **Usage patterns** - Complete usage documentation for commands
-- * **Alternative suggestions** - Context-aware alternatives for unknown options
--
-- @since 0.19.1
module Terminal.Error
  ( -- * Core Error Types (re-exported from Types)
    Error (..),
    ArgError (..),
    FlagError (..),
    Expectation (..),

    -- * Lenses (re-exported from Types)
    expectationType,
    expectationExamples,

    -- * Main Exit Functions
    exitWithError,
    exitWithHelp,
    exitWithOverview,
    exitWithUnknown,

    -- * Error Processing (re-exported from Display)
    convertErrorToDocs,
    argErrorToDocs,
    flagErrorToDocs,

    -- * Suggestion Generation (re-exported from Suggestions)
    generateFlagSuggestions,
    generateCommandSuggestions,

    -- * Help Generation (re-exported from Help)
    generateCommandHelp,
    generateAppOverview,
  )
where

import qualified System.Exit as Exit
import Terminal.Error.Display
  ( argErrorToDocs,
    convertErrorToDocs,
    exitWithCode,
    flagErrorToDocs,
  )
import Terminal.Error.Help
  ( generateAppOverview,
    generateCommandHelp,
  )
import Terminal.Error.Suggestions
  ( createSuggestionMessage,
    generateCommandSuggestions,
    generateFlagSuggestions,
  )
import Terminal.Error.Types
  ( ArgError (..),
    Error (..),
    Expectation (..),
    FlagError (..),
    expectationExamples,
    expectationType,
  )
import Terminal.Internal (Args, Command, Flags)
import qualified Text.PrettyPrint.ANSI.Leijen as Doc

-- | Exit with error display and failure code.
--
-- Converts any Terminal error to user-friendly documentation and
-- exits with appropriate failure code. This is the main entry point
-- for error handling in Terminal applications.
--
-- ==== Examples
--
-- >>> exitWithError (BadFlag flagError)
-- -- Exits with formatted flag error message
--
-- >>> exitWithError (BadArgs [(args, ArgMissing expectation)])
-- -- Exits with argument error and examples
--
-- ==== Error Display
--
-- All errors are displayed with:
--   * Clear problem description
--   * Specific error context (bad values, missing items)
--   * Helpful suggestions and examples
--   * Consistent formatting and colors
--
-- @since 0.19.1
exitWithError :: Error -> IO a
exitWithError err = do
  errorDocs <- convertErrorToDocs err
  exitWithCode (Exit.ExitFailure 1) errorDocs

-- | Exit with comprehensive command help display.
--
-- Generates and displays complete help documentation for a command
-- including description, usage patterns, argument documentation,
-- and flag information.
--
-- ==== Examples
--
-- >>> exitWithHelp Nothing "Build Canopy projects" examples args flags
-- -- Shows help for main command
--
-- >>> exitWithHelp (Just "install") "Install packages" examples args flags
-- -- Shows help for install subcommand
--
-- ==== Help Structure
--
-- Generated help includes:
--   * Command description and detailed information
--   * Usage patterns with argument placeholders
--   * Flag documentation with examples and descriptions
--   * Usage examples and additional guidance
--
-- @since 0.19.1
exitWithHelp :: Maybe String -> String -> Doc.Doc -> Args args -> Flags flags -> IO a
exitWithHelp maybeCommand details example args flags = do
  helpDocs <- generateCommandHelp maybeCommand details example args flags
  exitWithCode Exit.ExitSuccess helpDocs

-- | Exit with application overview display.
--
-- Shows comprehensive overview of multi-command application including
-- introduction, common commands with descriptions, complete command list,
-- and usage guidance.
--
-- ==== Examples
--
-- >>> exitWithOverview intro outro allCommands
-- -- Shows complete application overview
--
-- ==== Overview Structure
--
-- Generated overview includes:
--   * Application introduction and description
--   * Common commands with usage patterns and descriptions
--   * Complete alphabetical command list with help references
--   * Application outro and additional guidance
--
-- @since 0.19.1
exitWithOverview :: Doc.Doc -> Doc.Doc -> [Command] -> IO a
exitWithOverview intro outro commands = do
  overviewDocs <- generateAppOverview intro outro commands
  exitWithCode Exit.ExitSuccess overviewDocs

-- | Exit with unknown command error and suggestions.
--
-- Handles unknown command errors by generating intelligent suggestions
-- based on edit distance from known commands and displaying helpful
-- recovery information.
--
-- ==== Examples
--
-- >>> exitWithUnknown "biuld" ["build", "test", "install"]
-- -- Shows "build" suggestion for "biuld" typo
--
-- >>> exitWithUnknown "xyz" ["build", "test"]
-- -- Shows general help guidance when no good suggestions
--
-- ==== Suggestion Algorithm
--
-- Uses intelligent suggestion generation:
--   * Edit distance ranking for typo correction
--   * Threshold filtering to avoid bad suggestions
--   * Grammatically correct suggestion formatting
--   * Fallback to general help when no good matches
--
-- @since 0.19.1
exitWithUnknown :: String -> [String] -> IO a
exitWithUnknown unknown knowns = do
  let suggestions = createSuggestionMessage unknown knowns
      errorDocs = createUnknownErrorDocs unknown suggestions
  exitWithCode (Exit.ExitFailure 1) errorDocs

-- | Create error documentation for unknown commands.
--
-- @since 0.19.1
createUnknownErrorDocs :: String -> [Doc.Doc] -> [Doc.Doc]
createUnknownErrorDocs unknown suggestions = do
  let errorMessage = createUnknownCommandMessage unknown suggestions
      helpGuidance = createHelpGuidance
  [errorMessage, helpGuidance]

-- | Create main unknown command message.
--
-- @since 0.19.1
createUnknownCommandMessage :: String -> [Doc.Doc] -> Doc.Doc
createUnknownCommandMessage unknown suggestions =
  let baseMessage = ["There", "is", "no", Doc.red (Doc.text unknown), "command."]
   in Doc.fillSep (baseMessage ++ suggestions)

-- | Create help guidance message.
--
-- @since 0.19.1
createHelpGuidance :: Doc.Doc
createHelpGuidance =
  Doc.fillSep
    [ "Run",
      "the",
      "command",
      "with",
      "no",
      "arguments",
      "to",
      "get",
      "more",
      "hints."
    ]
