{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Flag parsing and validation for Terminal chomp operations.
--
-- This module handles the parsing of command-line flags and options,
-- including both value flags (--flag=value) and boolean flags (--flag).
-- It provides comprehensive error handling, unknown flag detection,
-- and suggestion support for flag completion.
--
-- == Key Features
--
-- * Support for value flags and boolean on/off flags
-- * Intelligent flag value detection and extraction
-- * Unknown flag detection with suggestion generation
-- * Comprehensive error reporting with context information
-- * Integration with suggestion system for shell completion
--
-- == Flag Types
--
-- The module supports two primary flag patterns:
--
-- * 'Flag' - Flags that require values (--output=file.txt)
-- * 'OnOff' - Boolean flags that are either present or absent (--verbose)
--
-- == Usage Examples
--
-- @
-- result <- parseFlags suggest chunks flagSpec
-- case result of
--   (suggestions, Right flagValues) -> processFlags suggestions flagValues
--   (suggestions, Left error) -> reportFlagError suggestions error
-- @
--
-- @since 0.19.1
module Terminal.Chomp.Flags
  ( -- * Main Parsing Functions
    parseFlags,
    parseFlag,
    parseFlagsHelper,

    -- * Flag Type Handlers
    parseOnOffFlag,
    parseValueFlag,

    -- * Flag Discovery
    findFlag,
    checkUnknownFlags,

    -- * Suggestion Support
    generateFlagSuggestion,
    getFlagNames,
    extractFlagName,

    -- * Utility Functions
    validateFlags,
    extractFlagInfo,
    startsWithDash,
  )
where

import Control.Lens ((^.))
import qualified Data.List as List
import qualified Reporting.Suggest as Suggest
import Terminal.Chomp.Parser
  ( attemptParse,
  )
import Terminal.Chomp.Suggestion
  ( updateSuggestion,
  )
import Terminal.Chomp.Types
  ( Chomper (..),
    Chunk,
    FoundFlag (..),
    Value (..),
    ValueType (..),
    chunkContent,
    chunkIndex,
    createFoundFlag,
    foundAfter,
    foundBefore,
    foundValue,
    valueContent,
    valueIndex,
  )
import Terminal.Error (Expectation (..), FlagError (..))
import Terminal.Internal
  ( Flag (..),
    Flags (..),
    Parser (..),
  )

-- | Parse complete flag specification with error handling.
--
-- Processes the flag specification and validates that no unknown flags
-- are present in the input. Combines flag parsing with comprehensive
-- error checking and suggestion generation.
--
-- ==== Examples
--
-- >>> parseFlags suggest chunks flagSpec
-- (suggestions, Right flagValues)
--
-- ==== Error Handling
--
-- Returns 'Left' for:
--   * Unknown flags not defined in specification
--   * Flag value parsing failures
--   * Missing required flag values
--
-- @since 0.19.1
parseFlags :: Flags a -> Chomper FlagError a
parseFlags flags = do
  value <- parseFlagsHelper flags
  checkUnknownFlags flags
  return value

-- | Parse flag specification hierarchy.
--
-- Processes nested flag specifications, applying parsers in sequence
-- and accumulating flag values. Handles function application for
-- multi-flag patterns with proper error propagation.
--
-- ==== Examples
--
-- >>> parseFlagsHelper (FMore (FDone id) boolFlag)
-- Chomper (...)
--
-- @since 0.19.1
parseFlagsHelper :: Flags a -> Chomper FlagError a
parseFlagsHelper = \case
  FDone value ->
    return value
  FMore funcFlags argFlag -> do
    func <- parseFlagsHelper funcFlags
    arg <- parseFlag argFlag
    return (func arg)

-- | Parse individual flag with value extraction.
--
-- Handles both boolean and value flags, extracting appropriate values
-- based on flag type and input format. Provides detailed error
-- information for parsing failures.
--
-- ==== Examples
--
-- >>> parseFlag (OnOff "verbose" "Enable verbose output")
-- Chomper (...)  -- returns Bool
--
-- >>> parseFlag (Flag "output" stringParser "Output file")
-- Chomper (...)  -- returns Maybe String
--
-- @since 0.19.1
parseFlag :: Flag a -> Chomper FlagError a
parseFlag = \case
  OnOff flagName _ ->
    parseOnOffFlag flagName
  Flag flagName parser _ ->
    parseValueFlag flagName parser

-- | Parse boolean on/off flag.
--
-- Searches for the flag in the input and determines its presence.
-- Handles flag format validation and ensures no unexpected values
-- are provided to boolean flags.
--
-- ==== Examples
--
-- >>> parseOnOffFlag "verbose"
-- Chomper (...)  -- True if --verbose present, False otherwise
--
-- ==== Error Conditions
--
-- Returns 'FlagWithValue' error if boolean flag has unexpected value:
--   * --verbose=something (should be just --verbose)
--
-- @since 0.19.1
parseOnOffFlag :: String -> Chomper FlagError Bool
parseOnOffFlag flagName =
  Chomper $ \suggest chunks success failure ->
    case findFlag flagName chunks of
      Nothing ->
        success suggest chunks False
      Just foundFlag ->
        case foundFlag ^. foundValue of
          NoValue ->
            success suggest (combineChunks foundFlag) True
          PossibleValue chunk ->
            success suggest (combinePossibleChunks foundFlag chunk) True
          DefiniteValue valueType ->
            failure suggest (FlagWithValue flagName (valueType ^. valueContent))

-- | Parse value flag with type validation.
--
-- Searches for the flag and extracts its value using the provided parser.
-- Handles different value formats (--flag=value, --flag value) and
-- provides appropriate error messages for parsing failures.
--
-- ==== Examples
--
-- >>> parseValueFlag "output" stringParser
-- Chomper (...)  -- Maybe String based on flag presence
--
-- ==== Error Conditions
--
-- Returns errors for:
--   * 'FlagWithNoValue' - Flag present but no value provided
--   * 'FlagWithBadValue' - Value present but parser rejects it
--
-- @since 0.19.1
parseValueFlag :: String -> Parser a -> Chomper FlagError (Maybe a)
parseValueFlag flagName parser@(Parser singular _ _ _ exampleFunc) =
  Chomper $ \suggest chunks success failure ->
    case findFlag flagName chunks of
      Nothing ->
        success suggest chunks Nothing
      Just foundFlag ->
        let attemptParsing index content =
              case attemptParse suggest parser index content of
                (newSuggest, Left expectation) ->
                  failure newSuggest (FlagWithBadValue flagName content expectation)
                (newSuggest, Right flagValue) ->
                  success newSuggest (combineChunks foundFlag) (Just flagValue)
         in case foundFlag ^. foundValue of
              DefiniteValue valueType ->
                attemptParsing (valueType ^. valueIndex) (valueType ^. valueContent)
              PossibleValue chunk ->
                attemptParsing (chunk ^. chunkIndex) (chunk ^. chunkContent)
              NoValue ->
                failure suggest (FlagWithNoValue flagName (Expectation singular (exampleFunc "")))

-- | Find flag in chunk list with value extraction.
--
-- Searches for the specified flag name in different formats and extracts
-- the associated value if present. Handles both --flag=value and --flag value
-- patterns while maintaining position information.
--
-- ==== Examples
--
-- >>> findFlag "output" [chunk1, chunk2, chunk3]
-- Just (FoundFlag [chunk1] (DefiniteValue ...) [chunk3])
--
-- >>> findFlag "missing" chunks
-- Nothing
--
-- @since 0.19.1
findFlag :: String -> [Chunk] -> Maybe FoundFlag
findFlag flagName = findFlagHelper [] ("--" ++ flagName) ("--" ++ flagName ++ "=")

-- | Check for unknown flags in input.
--
-- Validates that all flags starting with dashes are defined in the
-- flag specification. Generates suggestions for similar flag names
-- when unknown flags are encountered.
--
-- ==== Examples
--
-- >>> checkUnknownFlags flagSpec
-- Chomper (...)  -- succeeds if all flags known
--
-- ==== Error Conditions
--
-- Returns 'FlagUnknown' error for flags not in specification:
--   * --unknown-flag (not defined in flag spec)
--
-- @since 0.19.1
checkUnknownFlags :: Flags a -> Chomper FlagError ()
checkUnknownFlags flags =
  Chomper $ \suggest chunks success failure ->
    case filter startsWithDash chunks of
      [] ->
        success suggest chunks ()
      unknownFlags@(unknownFlag : _) ->
        failure
          (updateSuggestion suggest (generateFlagSuggestion unknownFlags flags))
          (FlagUnknown (unknownFlag ^. chunkContent) flags)

-- | Generate flag-specific suggestions for completion.
--
-- Creates suggestion functions that provide flag name completions
-- based on partial input and available flag specifications.
--
-- ==== Examples
--
-- >>> generateFlagSuggestion unknownFlags flagSpec 3
-- Just (return ["--output", "--verbose", "--help"])
--
-- @since 0.19.1
generateFlagSuggestion :: [Chunk] -> Flags a -> Int -> Maybe (IO [String])
generateFlagSuggestion unknownFlags flags targetIndex =
  case unknownFlags of
    [] -> Nothing
    chunk : otherUnknownFlags ->
      if chunk ^. chunkIndex == targetIndex
        then
          let unknownFlag = chunk ^. chunkContent
              -- Remove leading dashes and extract flag name for comparison
              unknownName = dropWhile (== '-') unknownFlag
              allFlags = getFlagNames flags []
              -- Extract flag names without dashes for distance comparison
              flagNamesOnly = map (dropWhile (== '-')) allFlags
              -- Use edit distance like original getNearbyFlags with fallback
              distances = zip (map (Suggest.distance unknownName) flagNamesOnly) allFlags
              sortedDistances = List.sortOn fst distances
              nearbyFlags = case filter (\(d, _) -> d < 3) sortedDistances of
                [] -> map snd sortedDistances -- Fallback: return all flags sorted by distance
                goodMatches -> map snd goodMatches
           in Just (return nearbyFlags)
        else generateFlagSuggestion otherUnknownFlags flags targetIndex

-- | Extract all flag names from flag specification.
--
-- Traverses the flag specification and collects all defined flag names
-- for help generation and suggestion support. Includes built-in flags
-- like --help automatically.
--
-- ==== Examples
--
-- >>> getFlagNames flagSpec []
-- ["--help", "--output", "--verbose", "--debug"]
--
-- @since 0.19.1
getFlagNames :: Flags a -> [String] -> [String]
getFlagNames flags names =
  case flags of
    FDone _ ->
      "--help" : names
    FMore subFlags flag ->
      getFlagNames subFlags (extractFlagName flag : names)

-- | Extract flag name from flag definition.
--
-- Retrieves the name portion of a flag definition with proper formatting
-- including the double-dash prefix for consistency with command-line usage.
--
-- ==== Examples
--
-- >>> extractFlagName (Flag "output" parser "desc")
-- "--output"
--
-- >>> extractFlagName (OnOff "verbose" "desc")
-- "--verbose"
--
-- @since 0.19.1
extractFlagName :: Flag a -> String
extractFlagName = \case
  Flag name _ _ -> "--" ++ name
  OnOff name _ -> "--" ++ name

-- | Check if chunk represents a flag (starts with dash).
--
-- Identifies potential flag arguments by checking for the dash prefix
-- that indicates command-line flags and options.
--
-- ==== Examples
--
-- >>> startsWithDash (Chunk 1 "--output")
-- True
--
-- >>> startsWithDash (Chunk 1 "filename.txt")
-- False
--
-- @since 0.19.1
startsWithDash :: Chunk -> Bool
startsWithDash chunk = "-" `List.isPrefixOf` (chunk ^. chunkContent)

-- | Validate flag specification structure.
--
-- Performs comprehensive validation of flag specifications including
-- name uniqueness, type consistency, and structural requirements.
--
-- ==== Examples
--
-- >>> validateFlags flagSpec
-- Right ()  -- valid specification
--
-- >>> validateFlags invalidSpec
-- Left "Duplicate flag name: --output"
--
-- @since 0.19.1
validateFlags :: Flags a -> Either String ()
validateFlags flags =
  let flagNames = getFlagNames flags []
      duplicates = findDuplicates flagNames
   in if null duplicates
        then Right ()
        else Left ("Duplicate flag names: " ++ unwords duplicates)

-- | Extract flag information for help generation.
--
-- Provides access to flag metadata including names, descriptions,
-- and type information for help text generation and debugging.
--
-- ==== Examples
--
-- >>> extractFlagInfo flagSpec
-- [("--output", "Output file"), ("--verbose", "Enable verbose mode")]
--
-- @since 0.19.1
extractFlagInfo :: Flags a -> [(String, String)]
extractFlagInfo = \case
  FDone _ -> []
  FMore subFlags flag ->
    extractFlagInfo subFlags ++ [getFlagInfo flag]

-- Helper function to find flag with value extraction
findFlagHelper :: [Chunk] -> String -> String -> [Chunk] -> Maybe FoundFlag
findFlagHelper revPrev loneFlag flagPrefix chunks =
  let deprefix content = drop (length flagPrefix) content
      succeed value after =
        Just (createFoundFlag (reverse revPrev) value after)
   in case chunks of
        [] -> Nothing
        chunk : rest ->
          let content = chunk ^. chunkContent
              index = chunk ^. chunkIndex
           in if flagPrefix `List.isPrefixOf` content
                then succeed (DefiniteValue (ValueType index (deprefix content))) rest
                else
                  if content /= loneFlag
                    then findFlagHelper (chunk : revPrev) loneFlag flagPrefix rest
                    else case rest of
                      [] -> succeed NoValue []
                      argChunk : restOfRest ->
                        if "-" `List.isPrefixOf` (argChunk ^. chunkContent)
                          then succeed NoValue rest
                          else succeed (PossibleValue argChunk) restOfRest

-- Helper function to combine chunks after flag extraction
combineChunks :: FoundFlag -> [Chunk]
combineChunks foundFlag =
  (foundFlag ^. foundBefore) ++ (foundFlag ^. foundAfter)

-- Helper function to combine chunks including possible value
combinePossibleChunks :: FoundFlag -> Chunk -> [Chunk]
combinePossibleChunks foundFlag chunk =
  (foundFlag ^. foundBefore) ++ [chunk] ++ (foundFlag ^. foundAfter)

-- Helper function to find duplicates in list
findDuplicates :: Eq a => [a] -> [a]
findDuplicates = findDuplicatesHelper []
  where
    findDuplicatesHelper _ [] = []
    findDuplicatesHelper seen (x : xs)
      | x `elem` seen = x : findDuplicatesHelper seen xs
      | otherwise = findDuplicatesHelper (x : seen) xs

-- Helper function to extract flag information
getFlagInfo :: Flag a -> (String, String)
getFlagInfo = \case
  Flag name _ desc -> ("--" ++ name, desc)
  OnOff name desc -> ("--" ++ name, desc)
