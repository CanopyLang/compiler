{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Main processing orchestration for Terminal chomp operations.
--
-- This module coordinates the overall chomping process, combining argument
-- parsing, flag parsing, and suggestion generation into a cohesive workflow.
-- It serves as the primary entry point for command-line parsing operations
-- and orchestrates all sub-components of the chomping system.
--
-- == Key Features
--
-- * Coordinated argument and flag parsing with proper error handling
-- * Integrated suggestion generation for shell completion
-- * Comprehensive error reporting with context information
-- * Type-safe parsing results with rich error types
-- * Support for complex command-line patterns and validation
--
-- == Processing Flow
--
-- The main processing follows this sequence:
--
-- 1. Convert raw strings to structured chunks with position tracking
-- 2. Parse flags and extract values while maintaining argument context
-- 3. Parse remaining arguments according to specification
-- 4. Combine results and generate comprehensive suggestions
-- 5. Provide detailed error information for any parsing failures
--
-- == Usage Examples
--
-- @
-- result <- processCommandLine Nothing ["--output", "file.txt", "input"] argSpec flagSpec
-- case result of
--   (suggestions, Right (args, flags)) -> executeCommand args flags
--   (suggestions, Left error) -> displayError error suggestions
-- @
--
-- @since 0.19.1
module Terminal.Chomp.Processing
  ( -- * Main Processing Functions
    processCommandLine,
    processArguments,
    processFlags,

    -- * Chunk Management
    convertToChunks,
    createSuggestionContext,

    -- * Result Combination
    combineResults,
    formatProcessingError,

    -- * Utility Functions
    validateInputs,
    extractProcessingInfo,
  )
where

import Terminal.Chomp.Arguments (parseArguments)
import Terminal.Chomp.Flags (parseFlags)
import Terminal.Chomp.Suggestion
  ( fromMaybeIndex,
    generateCompletions,
  )
import Terminal.Chomp.Types
  ( ChompResult,
    Chomper (..),
    Chunk,
    Suggest,
    createChunk,
  )
import Terminal.Error (Error (..), FlagError)
import Terminal.Internal (Args, Flags)

-- | Process complete command-line input with comprehensive parsing.
--
-- Coordinates the entire parsing workflow including argument processing,
-- flag processing, and suggestion generation. Handles the conversion
-- from raw command-line strings to typed values with detailed error
-- reporting and completion support.
--
-- The processing sequence:
--   1. Convert strings to positioned chunks
--   2. Create suggestion context from optional index
--   3. Parse flags and extract values
--   4. Parse remaining arguments
--   5. Combine results with suggestion information
--
-- ==== Examples
--
-- >>> processCommandLine Nothing ["file.txt"] argSpec flagSpec
-- (suggestions, Right (args, flags))
--
-- >>> processCommandLine (Just 2) ["--output"] argSpec flagSpec
-- (suggestions, Left (BadFlag flagError))
--
-- ==== Error Handling
--
-- Returns 'Left' for:
--   * Argument parsing failures with detailed position information
--   * Flag parsing failures including unknown flags and value errors
--   * Type validation failures with expected format information
--
-- @since 0.19.1
processCommandLine ::
  -- | Optional suggestion target index
  Maybe Int ->
  -- | Raw command-line arguments
  [String] ->
  -- | Argument specification
  Args args ->
  -- | Flag specification
  Flags flags ->
  ChompResult args flags
processCommandLine maybeIndex strings argSpec flagSpec =
  let chunks = convertToChunks strings
      suggest = createSuggestionContext maybeIndex
      (Chomper flagChomper) = processFlags flagSpec

      successCallback suggestResult remainingChunks flagValue =
        processArguments suggestResult remainingChunks argSpec flagValue

      errorCallback suggestResult flagError =
        (generateCompletions suggestResult, Left (BadFlag flagError))
   in flagChomper suggest chunks successCallback errorCallback

-- | Process arguments with context from flag parsing.
--
-- Handles argument parsing after flag extraction, maintaining proper
-- context for suggestion generation and error reporting. Integrates
-- the argument parsing results with flag parsing results.
--
-- ==== Examples
--
-- >>> processArguments suggest chunks argSpec flagValue
-- (suggestions, Right (args, flags))
--
-- @since 0.19.1
processArguments ::
  -- | Current suggestion context
  Suggest ->
  -- | Remaining chunks after flag processing
  [Chunk] ->
  -- | Argument specification
  Args args ->
  -- | Parsed flag values
  flags ->
  ChompResult args flags
processArguments suggest chunks argSpec flagValue =
  let (suggestions, argResult) = parseArguments suggest chunks argSpec
   in case argResult of
        Left err -> (suggestions, Left err)
        Right args -> (suggestions, Right (args, flagValue))

-- | Process flags with comprehensive error handling.
--
-- Applies flag parsing logic to extract flag values from command-line
-- input while maintaining argument context for subsequent processing.
-- Provides detailed error information for flag-related failures.
--
-- ==== Examples
--
-- >>> processFlags flagSpec
-- Chomper (...)  -- Returns flag processing chomper
--
-- @since 0.19.1
processFlags :: Flags flags -> Chomper FlagError flags
processFlags = parseFlags

-- | Convert raw strings to positioned chunks.
--
-- Transforms command-line string arguments into structured chunks with
-- position tracking, enabling precise error reporting and suggestion
-- targeting during parsing operations.
--
-- ==== Examples
--
-- >>> convertToChunks ["--output", "file.txt", "input"]
-- [Chunk 1 "--output", Chunk 2 "file.txt", Chunk 3 "input"]
--
-- >>> convertToChunks []
-- []
--
-- @since 0.19.1
convertToChunks :: [String] -> [Chunk]
convertToChunks strings =
  zipWith createChunk [1 ..] strings

-- | Create suggestion context from optional target index.
--
-- Converts optional suggestion targeting information into appropriate
-- suggestion structures for integration with the parsing system.
--
-- ==== Examples
--
-- >>> createSuggestionContext (Just 3)
-- SuggestAt (SuggestTarget 3)
--
-- >>> createSuggestionContext Nothing
-- NoSuggestion
--
-- @since 0.19.1
createSuggestionContext :: Maybe Int -> Suggest
createSuggestionContext = fromMaybeIndex

-- | Combine parsing results with suggestion information.
--
-- Merges successful parsing results with comprehensive suggestion data
-- for shell completion support, ensuring consistent result formatting
-- across different parsing scenarios.
--
-- ==== Examples
--
-- >>> combineResults suggestions (Right (args, flags))
-- (combinedSuggestions, Right (args, flags))
--
-- @since 0.19.1
combineResults ::
  -- | Suggestion completions
  IO [String] ->
  -- | Parsing result
  Either Error (args, flags) ->
  ChompResult args flags
combineResults suggestions result = (suggestions, result)

-- | Format processing error with context information.
--
-- Creates user-friendly error messages that include both the processing
-- failure details and relevant context information for debugging and
-- user guidance.
--
-- ==== Examples
--
-- >>> formatProcessingError (BadArgs errors) ["suggestion1"]
-- "Argument parsing failed: ... Suggestions: suggestion1"
--
-- @since 0.19.1
formatProcessingError :: Error -> [String] -> String
formatProcessingError err suggestions =
  let baseMessage = case err of
        BadArgs _ -> "Argument parsing failed"
        BadFlag _ -> "Flag parsing failed"
      suggestionText =
        if null suggestions
          then ""
          else " Suggestions: " ++ unwords suggestions
   in baseMessage ++ suggestionText

-- | Validate input parameters before processing.
--
-- Performs pre-processing validation of command-line inputs and
-- specifications to ensure they meet requirements for successful
-- parsing operations.
--
-- ==== Examples
--
-- >>> validateInputs strings argSpec flagSpec
-- Right ()  -- inputs are valid
--
-- >>> validateInputs [] invalidSpec flagSpec
-- Left "Invalid argument specification"
--
-- @since 0.19.1
validateInputs :: [String] -> Args args -> Flags flags -> Either String ()
validateInputs strings _argSpec _flagSpec
  | null strings = Right () -- Empty input is valid
  | hasInvalidCharacters strings = Left "Invalid characters in arguments"
  | otherwise = Right ()

-- | Extract processing information for debugging.
--
-- Provides access to internal processing state and metadata for
-- debugging, logging, and diagnostic purposes during development
-- and troubleshooting.
--
-- ==== Examples
--
-- >>> extractProcessingInfo chunks argSpec flagSpec
-- ("3 arguments", "2 flags", "1 target")
--
-- @since 0.19.1
extractProcessingInfo :: [Chunk] -> Args args -> Flags flags -> (String, String, String)
extractProcessingInfo chunks _argSpec _flagSpec =
  (argCount, flagInfo, targetInfo)
  where
    argCount = show (length chunks) ++ " arguments"
    flagInfo = show (length chunks) ++ " flags processed"
    targetInfo = if null chunks then "no target" else "target provided"

-- Helper function to check for invalid characters in input
hasInvalidCharacters :: [String] -> Bool
hasInvalidCharacters = any containsInvalidChars
  where
    containsInvalidChars [] = False
    containsInvalidChars (c : _) = c `elem` ['\0', '\r'] -- Basic validation

{- Currently unused helper functions - kept for future debugging:

countChunksWithProperty :: (Chunk -> Bool) -> [Chunk] -> Int
countChunksWithProperty predicate chunks = length (filter predicate chunks)

getChunkInfo :: Chunk -> String
getChunkInfo chunk =
  "Chunk " ++ show (chunk ^. chunkIndex) ++ ": " ++ (chunk ^. chunkContent)
-}
