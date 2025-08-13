{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Text formatting utilities for Terminal error display.
--
-- This module provides consistent formatting functions for error messages,
-- including color application, token formatting, and list presentation.
-- All formatting follows Terminal framework conventions for user-friendly
-- error reporting.
--
-- == Key Features
--
-- * Consistent color scheme for different message types
-- * Token formatting for command-line argument representation
-- * List formatting for examples and suggestions
-- * Text transformation utilities for error contexts
--
-- == Color Conventions
--
-- * Red - Error values and problematic input
-- * Yellow - Expected types and format descriptions
-- * Green - Suggestions and correct examples
-- * Cyan - Command syntax and help information
--
-- == Usage Examples
--
-- @
-- -- Format a type token
-- typeDoc = toYellowText (formatTokenName "file")
-- -- Result: "<file>" in yellow
--
-- -- Format example list
-- exampleDocs = formatExamplesList ["input.txt", "data.csv"]
-- -- Result: Green-formatted list with proper indentation
--
-- -- Create suggestion text
-- suggestionDoc = toGreenText "try this instead"
-- @
--
-- @since 0.19.1
module Terminal.Error.Formatting
  ( -- * Color Formatting
    toRedText,
    toYellowText,
    toGreenText,
    toCyanText,
    
    -- * Token Formatting
    formatTokenName,
    formatFlagUsage,
    formatArgumentUsage,
    
    -- * List Formatting
    formatExamplesList,
    formatSuggestionsList,
    formatCommandList,
    
    -- * Text Utilities
    reflowText,
    createStackedDocs,
    indentDoc,
  ) where

import qualified Data.List as List
import qualified Text.PrettyPrint.ANSI.Leijen as Doc

-- | Apply red color formatting to text.
--
-- Used for error values, invalid input, and problematic content
-- that needs to stand out as incorrect or problematic.
--
-- ==== Examples
--
-- >>> toRedText "invalid value"
-- Red-colored "invalid value"
--
-- @since 0.19.1
toRedText :: String -> Doc.Doc
toRedText text = Doc.red (Doc.text text)

-- | Apply yellow color formatting to text.
--
-- Used for type names, format descriptions, and expected value
-- indicators to show what the system is looking for.
--
-- ==== Examples
--
-- >>> toYellowText "<file>"
-- Yellow-colored "<file>"
--
-- @since 0.19.1
toYellowText :: String -> Doc.Doc
toYellowText text = Doc.yellow (Doc.text text)

-- | Apply green color formatting to text.
--
-- Used for suggestions, correct examples, and recommended actions
-- to guide users toward valid input.
--
-- ==== Examples
--
-- >>> toGreenText "input.txt"
-- Green-colored "input.txt"
--
-- @since 0.19.1
toGreenText :: String -> Doc.Doc
toGreenText text = Doc.green (Doc.text text)

-- | Apply cyan color formatting to text.
--
-- Used for command syntax, help information, and structural
-- elements like command names and flag syntax.
--
-- ==== Examples
--
-- >>> toCyanText "--output=<file>"
-- Cyan-colored "--output=<file>"
--
-- @since 0.19.1
toCyanText :: String -> Doc.Doc
toCyanText text = Doc.cyan (Doc.text text)

-- | Format a type name as a command-line token.
--
-- Converts type descriptions into the standard token format used
-- in command-line documentation and error messages.
--
-- ==== Examples
--
-- >>> formatTokenName "file"
-- "<file>"
--
-- >>> formatTokenName "input file"
-- "<input-file>"
--
-- @since 0.19.1
formatTokenName :: String -> String
formatTokenName typeName = 
  "<" ++ transformTokenText typeName ++ ">"

-- | Transform text for use in tokens.
--
-- Replaces spaces with hyphens for consistent token formatting.
--
-- @since 0.19.1
transformTokenText :: String -> String
transformTokenText = map replaceSpace
  where
    replaceSpace ' ' = '-'
    replaceSpace c = c

-- | Format flag usage documentation.
--
-- Creates properly formatted flag usage examples with values
-- and appropriate color coding.
--
-- ==== Examples
--
-- >>> formatFlagUsage "output" "file"
-- Cyan-colored "--output=<file>"
--
-- @since 0.19.1
formatFlagUsage :: String -> String -> Doc.Doc
formatFlagUsage flagName typeName =
  toCyanText ("--" ++ flagName ++ "=" ++ formatTokenName typeName)

-- | Format argument usage documentation.
--
-- Creates argument usage patterns for help text and error messages.
--
-- ==== Examples
--
-- >>> formatArgumentUsage "input"
-- Yellow-colored "<input>"
--
-- @since 0.19.1
formatArgumentUsage :: String -> Doc.Doc
formatArgumentUsage argName = toYellowText (formatTokenName argName)

-- | Format a list of examples with proper indentation and coloring.
--
-- Creates a visually consistent list of examples for error messages
-- and help documentation.
--
-- ==== Examples
--
-- >>> formatExamplesList ["input.txt", "data.csv"]
-- Indented green list of examples
--
-- @since 0.19.1
formatExamplesList :: [String] -> Doc.Doc
formatExamplesList examples =
  case examples of
    [] -> Doc.text "(no examples available)"
    _ -> Doc.indent 4 . Doc.green . Doc.vcat $ map Doc.text examples

-- | Format a list of suggestions with appropriate styling.
--
-- Creates suggestion lists for error recovery and user guidance.
--
-- @since 0.19.1
formatSuggestionsList :: [String] -> Doc.Doc
formatSuggestionsList suggestions =
  case suggestions of
    [] -> Doc.empty
    [single] -> toGreenText single
    multiple -> Doc.indent 4 . Doc.green . Doc.vcat $ map Doc.text multiple

-- | Format a list of commands for overview display.
--
-- Creates properly aligned command lists for help overview.
--
-- @since 0.19.1
formatCommandList :: String -> [String] -> Doc.Doc
formatCommandList exeName commands =
  let maxWidth = case commands of
        [] -> 0
        _ -> maximum (map length commands)
      formatCommand cmd = 
        Doc.text (exeName ++ " " ++ cmd ++ replicate (maxWidth - length cmd) ' ' ++ " --help")
  in Doc.vcat (map formatCommand commands)

-- | Reflow text for proper line wrapping.
--
-- Breaks text into words and reassembles with appropriate spacing
-- for consistent documentation formatting.
--
-- ==== Examples
--
-- >>> reflowText "This is a long sentence that needs wrapping"
-- Properly spaced Doc with fillSep
--
-- @since 0.19.1
reflowText :: String -> Doc.Doc
reflowText text = Doc.fillSep . map Doc.text $ words text

-- | Create a vertically stacked document with spacing.
--
-- Combines multiple documents with consistent spacing for
-- readable error message formatting.
--
-- @since 0.19.1
createStackedDocs :: [Doc.Doc] -> Doc.Doc
createStackedDocs docs = Doc.vcat $ List.intersperse "" docs

-- | Apply consistent indentation to documentation.
--
-- Provides standard indentation for nested content in error
-- messages and help text.
--
-- @since 0.19.1
indentDoc :: Int -> Doc.Doc -> Doc.Doc
indentDoc spaces doc = Doc.indent spaces doc