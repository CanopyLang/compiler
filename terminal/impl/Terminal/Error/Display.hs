{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Error display and rendering system for Terminal framework.
--
-- This module handles the conversion of error types into user-friendly
-- documentation with proper formatting, colors, and helpful suggestions.
-- It provides the core display logic for all Terminal error conditions.
--
-- == Key Features
--
-- * Rich error formatting with color support and terminal detection
-- * Context-aware suggestions and examples for each error type
-- * Consistent documentation structure across all error conditions
-- * Support for both terminal and non-terminal output environments
--
-- == Display Architecture
--
-- The display system follows a layered approach:
--
-- 1. 'convertErrorToDocs' - Top-level error routing
-- 2. Type-specific converters ('argErrorToDocs', 'flagErrorToDocs')
-- 3. Formatting utilities for consistent presentation
-- 4. Terminal-aware output with 'exitWithDocs'
--
-- == Usage Examples
--
-- @
-- -- Convert and display an error
-- docs <- convertErrorToDocs (BadFlag flagError)
-- exitWithDocs ExitFailure docs
--
-- -- Direct argument error display
-- argDocs <- argErrorToDocs (ArgMissing expectation)
-- putDocLn (vcat argDocs)
-- @
--
-- @since 0.19.1
module Terminal.Error.Display
  ( -- * Main Display Functions
    convertErrorToDocs,
    exitWithDocs,

    -- * Error Type Converters
    argErrorToDocs,
    flagErrorToDocs,
    processArgErrors,

    -- * Display Utilities
    createErrorContext,
    formatErrorMessage,

    -- * Terminal Output
    exitWithCode,
  )
where

import Control.Lens ((^.))
import GHC.IO.Handle (hIsTerminalDevice)
import qualified System.Exit as Exit
import System.IO (hPutStrLn, stderr)
import Terminal.Error.Formatting
  ( formatExamplesList,
    formatTokenName,
    toGreenText,
    toRedText,
    toYellowText,
  )
import Terminal.Error.Types
  ( ArgError (..),
    Error (..),
    Expectation,
    FlagError (..),
    expectationExamples,
    expectationType,
    getTopArgError,
  )
import Terminal.Internal (CompleteArgs)
import qualified Text.PrettyPrint.ANSI.Leijen as Doc

-- | Convert any Terminal error to formatted documentation.
--
-- Routes errors to appropriate type-specific converters and handles
-- the coordination of complex error scenarios with multiple failures.
--
-- ==== Examples
--
-- >>> docs <- convertErrorToDocs (BadFlag flagError)
-- >>> length docs > 0
-- True
--
-- >>> docs <- convertErrorToDocs (BadArgs [])
-- >>> head docs
-- Doc containing "not expecting any arguments"
--
-- @since 0.19.1
convertErrorToDocs :: Error -> IO [Doc.Doc]
convertErrorToDocs err =
  case err of
    BadFlag flagError ->
      flagErrorToDocs flagError
    BadArgs argErrors ->
      processArgErrors argErrors

-- | Process multiple argument errors into documentation.
--
-- Handles the complexity of multiple failed argument parsing attempts
-- by selecting the most relevant error and formatting it appropriately.
--
-- @since 0.19.1
processArgErrors :: [(CompleteArgs a, ArgError)] -> IO [Doc.Doc]
processArgErrors argErrors =
  case argErrors of
    [] ->
      createNoArgumentsMessage
    [(_, argError)] ->
      argErrorToDocs argError
    _ : _ : _ ->
      argErrorToDocs (getTopArgError argErrors)

-- | Create message for unexpected empty arguments.
--
-- @since 0.19.1
createNoArgumentsMessage :: IO [Doc.Doc]
createNoArgumentsMessage =
  return
    [ Doc.fillSep ["I", "was", "not", "expecting", "any", "arguments", "for", "this", "command."],
      Doc.fillSep ["Try", "removing", "them?"]
    ]

-- | Convert argument error to formatted documentation.
--
-- Generates helpful error messages with examples and suggestions
-- based on the specific argument error type and context.
--
-- @since 0.19.1
argErrorToDocs :: ArgError -> IO [Doc.Doc]
argErrorToDocs argError =
  case argError of
    ArgMissing expectation ->
      createMissingArgMessage expectation
    ArgBad string expectation ->
      createBadArgMessage string expectation
    ArgExtras extras ->
      createExtraArgsMessage extras

-- | Create documentation for missing argument error.
--
-- @since 0.19.1
createMissingArgMessage :: Expectation -> IO [Doc.Doc]
createMissingArgMessage expectation = do
  examples <- expectation ^. expectationExamples
  let typeToken = expectation ^. expectationType
  return
    [ Doc.fillSep
        [ "The",
          "arguments",
          "you",
          "have",
          "are",
          "fine,",
          "but",
          "in",
          "addition,",
          "I",
          "was",
          "expecting",
          "a",
          toYellowText (formatTokenName typeToken),
          "value.",
          "For",
          "example:"
        ],
      formatExamplesList examples
    ]

-- | Create documentation for bad argument value error.
--
-- @since 0.19.1
createBadArgMessage :: String -> Expectation -> IO [Doc.Doc]
createBadArgMessage badValue expectation = do
  examples <- expectation ^. expectationExamples
  let typeToken = expectation ^. expectationType
      exampleLabel = if length examples == 1 then "this:" else "one of these:"
  return
    [ "I am having trouble with this argument:",
      Doc.indent 4 $ toRedText badValue,
      Doc.fillSep
        ( [ "It",
            "is",
            "supposed",
            "to",
            "be",
            "a",
            toYellowText (formatTokenName typeToken),
            "value,",
            "like"
          ]
            ++ [exampleLabel]
        ),
      formatExamplesList examples
    ]

-- | Create documentation for extra arguments error.
--
-- @since 0.19.1
createExtraArgsMessage :: [String] -> IO [Doc.Doc]
createExtraArgsMessage extras =
  let (theseLabel, themLabel) = case extras of
        [_] -> ("this argument", "it")
        _ -> ("these arguments", "them")
   in return
        [ Doc.fillSep ["I", "was", "not", "expecting", theseLabel <> ":"],
          Doc.indent 4 . Doc.red . Doc.vcat $ map Doc.text extras,
          Doc.fillSep ["Try", "removing", themLabel <> "?"]
        ]

-- | Convert flag error to formatted documentation.
--
-- Handles all flag-related error conditions with appropriate context
-- and suggestions for resolution.
--
-- @since 0.19.1
flagErrorToDocs :: FlagError -> IO [Doc.Doc]
flagErrorToDocs flagError =
  case flagError of
    FlagWithValue flagName value ->
      createFlagWithValueMessage flagName value
    FlagWithNoValue flagName expectation ->
      createFlagNoValueMessage flagName expectation
    FlagWithBadValue flagName badValue expectation ->
      createFlagBadValueMessage flagName badValue expectation
    FlagUnknown unknown flags ->
      createUnknownFlagMessage unknown flags

-- | Create message for on/off flag with unexpected value.
--
-- @since 0.19.1
createFlagWithValueMessage :: String -> String -> IO [Doc.Doc]
createFlagWithValueMessage flagName value =
  createFlagError
    "This on/off flag was given a value:"
    ("--" ++ flagName ++ "=" ++ value)
    [ "An on/off flag either exists or not. It cannot have an equals sign and value.",
      "Maybe you want this instead?",
      Doc.indent 4 . toGreenText $ ("--" ++ flagName)
    ]

-- | Create message for flag missing required value.
--
-- @since 0.19.1
createFlagNoValueMessage :: String -> Expectation -> IO [Doc.Doc]
createFlagNoValueMessage flagName expectation = do
  examples <- expectation ^. expectationExamples
  let typeToken = expectation ^. expectationType
      exampleFlags = createFlagExamples flagName typeToken examples
  createFlagError
    "This flag needs more information:"
    ("--" ++ flagName)
    [ Doc.fillSep ["It", "needs", "a", toYellowText (formatTokenName typeToken), "like", "this:"],
      Doc.indent 4 . Doc.vcat . map toGreenText $ exampleFlags
    ]

-- | Create message for flag with invalid value.
--
-- @since 0.19.1
createFlagBadValueMessage :: String -> String -> Expectation -> IO [Doc.Doc]
createFlagBadValueMessage flagName badValue expectation = do
  examples <- expectation ^. expectationExamples
  let typeToken = expectation ^. expectationType
      exampleFlags = createFlagExamples flagName typeToken examples
  createFlagError
    "This flag was given a bad value:"
    ("--" ++ flagName ++ "=" ++ badValue)
    [ Doc.fillSep
        [ "I",
          "need",
          "a",
          "valid",
          toYellowText (formatTokenName typeToken),
          "value.",
          "For",
          "example:"
        ],
      Doc.indent 4 . Doc.vcat . map toGreenText $ exampleFlags
    ]

-- | Create message for unknown flag error.
--
-- @since 0.19.1
createUnknownFlagMessage :: String -> flags -> IO [Doc.Doc]
createUnknownFlagMessage unknown _flags =
  createFlagError
    "I do not recognize this flag:"
    unknown
    [] -- TODO: Add flag suggestions when getNearbyFlags is modularized

-- | Create formatted flag error with consistent structure.
--
-- @since 0.19.1
createFlagError :: String -> String -> [Doc.Doc] -> IO [Doc.Doc]
createFlagError summary original explanation =
  return $
    [ Doc.fillSep (map Doc.text (words summary)),
      Doc.indent 4 (toRedText original)
    ]
      ++ explanation

-- | Create example flag usage from type and examples.
--
-- @since 0.19.1
createFlagExamples :: String -> String -> [String] -> [String]
createFlagExamples flagName typeToken examples =
  case take 4 examples of
    [] -> ["--" ++ flagName ++ "=" ++ formatTokenName typeToken]
    validExamples -> map (\ex -> "--" ++ flagName ++ "=" ++ ex) validExamples

-- | Create error context information for debugging.
--
-- @since 0.19.1
createErrorContext :: Error -> String
createErrorContext err =
  case err of
    BadArgs argErrors -> "BadArgs with " ++ show (length argErrors) ++ " errors"
    BadFlag _ -> "BadFlag error"

-- | Format error message for display.
--
-- @since 0.19.1
formatErrorMessage :: String -> String -> Doc.Doc
formatErrorMessage summary details =
  Doc.vcat
    [ Doc.fillSep (map Doc.text (words summary)),
      Doc.indent 2 (Doc.fillSep (map Doc.text (words details)))
    ]

-- | Exit with formatted documentation and appropriate exit code.
--
-- @since 0.19.1
exitWithDocs :: Exit.ExitCode -> [Doc.Doc] -> IO a
exitWithDocs code docs = do
  isTerminal <- hIsTerminalDevice stderr
  let adjust = if isTerminal then id else Doc.plain
      formattedDocs = Doc.vcat $ concatMap (\d -> [d, ""]) docs
  ((Doc.displayIO stderr . Doc.renderPretty 1 80) . adjust) formattedDocs
  hPutStrLn stderr ""
  Exit.exitWith code

-- | Exit with specific exit code (convenience wrapper).
--
-- @since 0.19.1
exitWithCode :: Exit.ExitCode -> [Doc.Doc] -> IO a
exitWithCode = exitWithDocs
