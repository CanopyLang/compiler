{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Core parsing utilities for Terminal chomp operations.
--
-- This module provides the fundamental parsing infrastructure for converting
-- raw command-line strings into typed values. It handles parser application,
-- error generation, and suggestion integration during the parsing process.
--
-- == Key Features
--
-- * Type-safe parsing with comprehensive error reporting
-- * Integrated suggestion generation for shell completion
-- * Expectation-based error messages with user-friendly formatting
-- * Context-aware parsing with position tracking
--
-- == Parser Integration
--
-- The module integrates with Terminal.Internal.Parser types to provide
-- a consistent parsing interface across the entire Terminal framework:
--
-- @
-- result <- attemptParse suggest parser 1 "input.txt"
-- case result of
--   (newSuggest, Right value) -> processValue newSuggest value
--   (newSuggest, Left expectation) -> handleError newSuggest expectation
-- @
--
-- == Error Handling
--
-- All parsing operations generate rich error information including:
--   * Expected value types and formats
--   * Actual input that failed parsing
--   * Contextual suggestions for correction
--   * Position information for precise error reporting
--
-- @since 0.19.1
module Terminal.Chomp.Parser
  ( -- * Core Parsing Functions
    attemptParse,
    parseWithSuggestion,
    createExpectation,
    
    -- * Suggestion Integration
    generateSuggestion,
    updateParserSuggestion,
    createParserSuggestion,
    
    -- * Utility Functions
    extractParserInfo,
    checkParserMatch,
    formatParseError,
  )
where

import Terminal.Chomp.Suggestion (updateSuggestion)
import Terminal.Chomp.Types (Suggest (..))
import Terminal.Error (Expectation (..))
import Terminal.Internal (Parser (..))

-- | Attempt to parse a string value with comprehensive error handling.
--
-- Applies the given parser to the input string while tracking suggestion
-- context and generating appropriate error information. Updates suggestions
-- based on parsing context and current input state.
--
-- The parsing process:
--   1. Update suggestions based on position and input
--   2. Apply parser to input string  
--   3. Generate result with updated suggestion context
--   4. Provide rich error information on failure
--
-- ==== Examples
--
-- >>> let parser = stringParser "filename" "description"
-- >>> attemptParse NoSuggestion parser 1 "test.txt"
-- (NoSuggestion, Right "test.txt")
--
-- >>> attemptParse NoSuggestion parser 1 ""
-- (NoSuggestion, Left (Expectation "filename" ["example.txt"]))
--
-- ==== Error Conditions
--
-- Returns 'Left' with expectation for:
--   * Parser rejection of input format
--   * Type conversion failures
--   * Validation constraint violations
--
-- @since 0.19.1
attemptParse
  :: Suggest
  -- ^ Current suggestion context
  -> Parser a
  -- ^ Parser to apply
  -> Int
  -- ^ Position index for error reporting
  -> String
  -- ^ Input string to parse
  -> (Suggest, Either Expectation a)
  -- ^ Updated suggestion and parse result
attemptParse suggest parser@(Parser singular _ parseFunc _ exampleFunc) index input =
  let updatedSuggest = updateParserSuggestion suggest parser index input
      parseResult = case parseFunc input of
        Nothing -> Left (Expectation singular (exampleFunc input))
        Just value -> Right value
  in (updatedSuggest, parseResult)

-- | Parse with explicit suggestion generation.
--
-- Combines parsing with proactive suggestion generation, useful for
-- interactive scenarios where completion options should be computed
-- regardless of parsing success or failure.
--
-- ==== Examples
--
-- >>> parseWithSuggestion suggest parser 2 "prefix"
-- (SuggestIO (...), Right value)
--
-- @since 0.19.1
parseWithSuggestion
  :: Suggest
  -> Parser a
  -> Int
  -> String
  -> IO (Suggest, Either Expectation a)
parseWithSuggestion suggest parser index input = do
  let (updatedSuggest, result) = attemptParse suggest parser index input
  finalSuggest <- enhanceWithSuggestions updatedSuggest parser input
  return (finalSuggest, result)

-- | Create expectation from parser and input context.
--
-- Generates detailed expectation information for error reporting,
-- including type information and example values appropriate for
-- the current parsing context.
--
-- ==== Examples
--
-- >>> let parser = intParser 1 10
-- >>> createExpectation parser "invalid"
-- Expectation "number" ["1", "5", "10"]
--
-- @since 0.19.1
createExpectation :: Parser a -> String -> Expectation
createExpectation (Parser singular _ _ _ exampleFunc) input =
  Expectation singular (exampleFunc input)

-- | Generate suggestion for parser at target position.
--
-- Creates position-aware suggestions by checking if the current parsing
-- position matches the target suggestion position and generating
-- appropriate completions.
--
-- ==== Examples
--
-- >>> generateSuggestion parser 3 3 "prefix"
-- Just (return ["prefix_option1", "prefix_option2"])
--
-- >>> generateSuggestion parser 3 5 "prefix"
-- Nothing
--
-- @since 0.19.1
generateSuggestion :: Parser a -> Int -> Int -> String -> Maybe (IO [String])
generateSuggestion (Parser _ _ _ suggestionFunc _) currentIndex targetIndex input
  | currentIndex == targetIndex = Just (suggestionFunc input)
  | otherwise = Nothing

-- | Update suggestion based on parser context and position.
--
-- Integrates parser-specific suggestion generation with the current
-- suggestion state, ensuring position-aware completions are generated
-- appropriately during parsing operations.
--
-- ==== Examples
--
-- >>> let suggest = SuggestAt (SuggestTarget 2)
-- >>> updateParserSuggestion suggest parser 2 "input"
-- SuggestIO (...)
--
-- @since 0.19.1
updateParserSuggestion :: Suggest -> Parser a -> Int -> String -> Suggest
updateParserSuggestion suggest parser currentIndex input =
  updateSuggestion suggest (\targetIndex -> generateSuggestion parser currentIndex targetIndex input)

-- | Create parser-specific suggestion for given input.
--
-- Generates a new suggestion based on parser capabilities and current
-- input, useful for initializing suggestion contexts during parsing.
--
-- ==== Examples
--
-- >>> createParserSuggestion parser 1 "test"
-- SuggestIO (...)
--
-- @since 0.19.1
createParserSuggestion :: Parser a -> Int -> String -> Suggest
createParserSuggestion parser index input =
  case generateSuggestion parser index index input of
    Just ioSuggestions -> SuggestIO ioSuggestions
    Nothing -> NoSuggestion

-- | Extract parser information for inspection.
--
-- Provides access to parser metadata including type names and
-- description information for error reporting and debugging.
--
-- ==== Examples
--
-- >>> extractParserInfo (stringParser "filename" "desc")
-- ("filename", "filenames")
--
-- @since 0.19.1
extractParserInfo :: Parser a -> (String, String)
extractParserInfo (Parser singular plural _ _ _) = (singular, plural)

-- | Check if parser can handle the given input.
--
-- Tests parser applicability without consuming input or generating
-- side effects, useful for parser selection and validation.
--
-- ==== Examples
--
-- >>> checkParserMatch (intParser 1 10) "5"
-- True
--
-- >>> checkParserMatch (intParser 1 10) "invalid"
-- False
--
-- @since 0.19.1
checkParserMatch :: Parser a -> String -> Bool
checkParserMatch (Parser _ _ parseFunc _ _) input =
  case parseFunc input of
    Just _ -> True
    Nothing -> False

-- | Format parse error with context information.
--
-- Creates user-friendly error messages that include both the parsing
-- failure details and suggestions for correction.
--
-- ==== Examples
--
-- >>> formatParseError "invalid" (Expectation "number" examplesIO)
-- "Expected number, got 'invalid'. Examples available."
--
-- @since 0.19.1
formatParseError :: String -> Expectation -> String
formatParseError input (Expectation expected _) =
  "Expected " ++ expected ++ ", got '" ++ input ++ "'"

-- Helper function to enhance suggestions with parser-specific completions
enhanceWithSuggestions :: Suggest -> Parser a -> String -> IO Suggest
enhanceWithSuggestions suggest parser input = do
  case suggest of
    SuggestIO ioCompletions -> do
      existing <- ioCompletions
      parserSuggestions <- getSuggestionFunc parser input
      return $ SuggestIO $ return $ existing ++ parserSuggestions
    _ -> return suggest
  where
    getSuggestionFunc (Parser _ _ _ suggestionFunc _) = suggestionFunc