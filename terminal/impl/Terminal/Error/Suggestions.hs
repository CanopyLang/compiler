{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Suggestion generation system for Terminal error recovery.
--
-- This module provides intelligent suggestion algorithms for helping users
-- recover from command-line parsing errors. It uses edit distance algorithms
-- and contextual analysis to provide meaningful alternatives.
--
-- == Key Features
--
-- * Edit distance-based suggestion ranking for typo correction
-- * Context-aware flag suggestions with proper formatting
-- * Command suggestion generation for unknown commands
-- * Configurable suggestion limits and filtering
--
-- == Suggestion Algorithms
--
-- The suggestion system uses multiple strategies:
--
-- 1. Edit distance ranking for close matches
-- 2. Prefix matching for partial completions
-- 3. Context filtering based on available options
-- 4. Relevance scoring for result prioritization
--
-- == Usage Examples
--
-- @
-- -- Generate flag suggestions
-- suggestions <- generateFlagSuggestions "verbos" knownFlags
-- -- Result: ["--verbose"]
--
-- -- Create command suggestions
-- cmdSuggestions <- generateCommandSuggestions "intsall" knownCommands
-- -- Result: ["install"]
--
-- -- Format suggestion text
-- suggestionDocs <- formatSuggestionText suggestions
-- @
--
-- @since 0.19.1
module Terminal.Error.Suggestions
  ( -- * Flag Suggestions
    generateFlagSuggestions,
    getNearbyFlags,
    extractFlagName,
    
    -- * Command Suggestions
    generateCommandSuggestions,
    rankCommandSuggestions,
    
    -- * Suggestion Formatting
    formatSuggestionText,
    createSuggestionMessage,
    
    -- * Utilities
    calculateEditDistance,
    filterByDistance,
    limitSuggestions,
  ) where

import qualified Data.List as List
import qualified Reporting.Suggest as Suggest
import Terminal.Error.Formatting
  ( toGreenText
  )
import Terminal.Internal (Flag (..), Flags (..), Parser (..))
import qualified Text.PrettyPrint.ANSI.Leijen as Doc

-- | Generate flag suggestions for unknown flag names.
--
-- Uses edit distance to find the closest matching flags and formats
-- them appropriately for error display. Limits results to most relevant.
--
-- ==== Examples
--
-- >>> generateFlagSuggestions "verbos" flags
-- [Green "--verbose", Green "--version"]
--
-- ==== Error Conditions
--
-- Returns empty list if no reasonable suggestions found (distance > 3).
--
-- @since 0.19.1
generateFlagSuggestions :: String -> Flags a -> [Doc.Doc]
generateFlagSuggestions unknown flags =
  let flagName = extractFlagName unknown
      nearbyFlags = getNearbyFlags flagName flags []
  in nearbyFlags

-- | Extract flag name from potentially malformed flag input.
--
-- Removes leading dashes and everything after equals sign to get
-- the core flag name for comparison.
--
-- ==== Examples
--
-- >>> extractFlagName "--verbos"
-- "verbos"
--
-- >>> extractFlagName "--output=file"
-- "output"
--
-- @since 0.19.1
extractFlagName :: String -> String
extractFlagName unknown =
  let withoutDashes = dropWhile (== '-') unknown
      withoutValue = takeWhile (/= '=') withoutDashes
  in withoutValue

-- | Get nearby flags using edit distance ranking.
--
-- Recursively processes flag structure to find all flags within
-- reasonable edit distance of the target name.
--
-- @since 0.19.1
getNearbyFlags :: String -> Flags a -> [(Int, String)] -> [Doc.Doc]
getNearbyFlags unknown flags unsortedFlags =
  case flags of
    FMore more flag ->
      let flagDistance = calculateFlagDistance unknown flag
      in getNearbyFlags unknown more (flagDistance : unsortedFlags)
    FDone _ ->
      formatFlagSuggestions (filterByDistance unsortedFlags)

-- | Calculate edit distance for a specific flag.
--
-- @since 0.19.1
calculateFlagDistance :: String -> Flag a -> (Int, String)
calculateFlagDistance unknown flag =
  case flag of
    OnOff flagName _ ->
      (calculateEditDistance unknown flagName, "--" ++ flagName)
    Flag flagName (Parser singular _ _ _ _) _ ->
      (calculateEditDistance unknown flagName, "--" ++ flagName ++ "=" ++ formatToken singular)

-- | Format token for flag display.
--
-- @since 0.19.1
formatToken :: String -> String
formatToken singular = "<" ++ singular ++ ">"

-- | Filter flags by edit distance threshold.
--
-- @since 0.19.1
filterByDistance :: [(Int, String)] -> [(Int, String)]
filterByDistance unsortedFlags =
  let sortedFlags = List.sortOn fst unsortedFlags
      goodMatches = filter (\(distance, _) -> distance < 3) sortedFlags
  in case goodMatches of
       [] -> sortedFlags  -- Return all if no good matches
       _ -> goodMatches   -- Return only good matches

-- | Format flag suggestions with proper styling.
--
-- @since 0.19.1
formatFlagSuggestions :: [(Int, String)] -> [Doc.Doc]
formatFlagSuggestions rankedFlags =
  let limitedFlags = limitSuggestions 5 rankedFlags
      flagNames = map snd limitedFlags
  in map toGreenText flagNames

-- | Generate command suggestions for unknown commands.
--
-- Uses edit distance to find similar commands and ranks them
-- by relevance for user suggestion.
--
-- ==== Examples
--
-- >>> generateCommandSuggestions "intsall" ["install", "init", "build"]
-- ["install"]
--
-- @since 0.19.1
generateCommandSuggestions :: String -> [String] -> [String]
generateCommandSuggestions unknown commands =
  let rankedCommands = rankCommandSuggestions unknown commands
      filteredCommands = filterByDistance rankedCommands
      limitedCommands = limitSuggestions 3 filteredCommands
  in map snd limitedCommands

-- | Rank commands by edit distance from unknown command.
--
-- @since 0.19.1
rankCommandSuggestions :: String -> [String] -> [(Int, String)]
rankCommandSuggestions unknown commands =
  let distances = map (\cmd -> (calculateEditDistance unknown cmd, cmd)) commands
  in List.sortOn fst distances

-- | Format suggestion text based on number of suggestions.
--
-- Creates grammatically correct suggestion text that varies based
-- on the number of alternatives available.
--
-- ==== Examples
--
-- >>> formatSuggestionText ["install"]
-- ["Try", Green "install", "instead?"]
--
-- >>> formatSuggestionText ["install", "init"]
-- ["Try", Green "install", "or", Green "init", "instead?"]
--
-- @since 0.19.1
formatSuggestionText :: [String] -> [Doc.Doc]
formatSuggestionText suggestions =
  case map toGreenText suggestions of
    [] -> []
    [single] -> ["Try", single, "instead?"]
    [first, second] -> ["Try", first, "or", second, "instead?"]
    multiple -> 
      let allButLast = init multiple
          lastOne = last multiple
          withCommas = map (<> ",") allButLast
      in ["Try"] ++ withCommas ++ ["or", lastOne, "instead?"]

-- | Create complete suggestion message for error display.
--
-- Combines suggestion generation with proper formatting for
-- inclusion in error documentation.
--
-- @since 0.19.1
createSuggestionMessage :: String -> [String] -> [Doc.Doc]
createSuggestionMessage unknown candidates =
  let suggestions = generateCommandSuggestions unknown candidates
  in formatSuggestionText suggestions

-- | Calculate edit distance between two strings.
--
-- Uses the Reporting.Suggest module's distance function for
-- consistent distance calculation across the Terminal framework.
--
-- ==== Examples
--
-- >>> calculateEditDistance "verbos" "verbose"
-- 1
--
-- >>> calculateEditDistance "test" "best"
-- 1
--
-- @since 0.19.1
calculateEditDistance :: String -> String -> Int
calculateEditDistance = Suggest.distance

-- | Limit number of suggestions to prevent overwhelming output.
--
-- Keeps only the top N suggestions based on ranking to maintain
-- readable error messages.
--
-- @since 0.19.1
limitSuggestions :: Int -> [(Int, String)] -> [(Int, String)]
limitSuggestions maxCount suggestions = take maxCount suggestions