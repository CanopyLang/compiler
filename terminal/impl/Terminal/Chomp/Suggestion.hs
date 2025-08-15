{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Suggestion and completion handling for Terminal chomp operations.
--
-- This module provides comprehensive shell completion support for command-line
-- parsing, including context-aware suggestions, target tracking, and completion
-- generation based on parsing state and user input patterns.
--
-- == Key Features
--
-- * Context-aware suggestion generation based on parsing state
-- * Target-specific completion for different argument positions
-- * IO-based suggestion computation for dynamic completions
-- * Suggestion combination and merging for complex scenarios
--
-- == Usage Patterns
--
-- @
-- suggest <- updateSuggestion currentSuggest updateFunction
-- completions <- generateCompletions suggest prefix
-- merged <- combineSuggestions [suggest1, suggest2, suggest3]
-- @
--
-- == Integration
--
-- This module integrates with the Terminal parsing framework to provide
-- seamless completion support during argument and flag parsing operations.
--
-- @since 0.19.1
module Terminal.Chomp.Suggestion
  ( -- * Suggestion Updates
    updateSuggestion,
    targetSuggestion,
    ioSuggestion,

    -- * Completion Generation
    generateCompletions,
    combineCompletions,
    addCompletion,

    -- * Suggestion Utilities
    hasSuggestion,
    getSuggestionTarget,
    isTargetSuggestion,

    -- * Conversion Functions
    toMaybeIndex,
    fromMaybeIndex,
  )
where

import Control.Lens ((^.))
import Terminal.Chomp.Types
  ( Suggest (..),
    SuggestTarget (..),
    suggestTarget,
  )

-- | Update suggestion based on optional modification function.
--
-- Applies the given update function if conditions are met, maintaining
-- existing suggestions when updates are not applicable. Preserves
-- IO-based suggestions to avoid losing dynamic completion capabilities.
--
-- ==== Examples
--
-- >>> let suggest = SuggestAt (SuggestTarget 3)
-- >>> let update idx = if idx == 3 then Just (return ["file1", "file2"]) else Nothing
-- >>> updateSuggestion suggest update
-- SuggestIO (...)
--
-- >>> updateSuggestion NoSuggestion (const Nothing)
-- NoSuggestion
--
-- @since 0.19.1
updateSuggestion :: Suggest -> (Int -> Maybe (IO [String])) -> Suggest
updateSuggestion suggest updateFunc =
  case suggest of
    NoSuggestion -> suggest
    SuggestIO _ -> suggest
    SuggestAt target ->
      case updateFunc (target ^. suggestTarget) of
        Nothing -> suggest
        Just ioSuggestions -> SuggestIO ioSuggestions

-- | Create a target-specific suggestion for the given position.
--
-- Generates a suggestion that targets a specific argument position,
-- useful for providing position-aware completions during parsing.
--
-- ==== Examples
--
-- >>> targetSuggestion 2
-- SuggestAt (SuggestTarget {_suggestTarget = 2})
--
-- >>> targetSuggestion 0
-- NoSuggestion
--
-- @since 0.19.1
targetSuggestion :: Int -> Suggest
targetSuggestion index
  | index <= 0 = NoSuggestion
  | otherwise = SuggestAt (SuggestTarget index)

-- | Create an IO-based suggestion with dynamic completion.
--
-- Wraps IO computation for suggestion generation, enabling dynamic
-- completions based on file system state, network resources, or
-- other runtime information.
--
-- ==== Examples
--
-- >>> let completions = return ["option1", "option2", "option3"]
-- >>> ioSuggestion completions
-- SuggestIO (...)
--
-- @since 0.19.1
ioSuggestion :: IO [String] -> Suggest
ioSuggestion = SuggestIO

-- | Generate completion list from suggestion.
--
-- Extracts concrete completion options from different suggestion types,
-- handling both static and dynamic completion scenarios appropriately.
--
-- ==== Examples
--
-- >>> let suggest = SuggestIO (return ["file1.txt", "file2.txt"])
-- >>> generateCompletions suggest
-- ["file1.txt", "file2.txt"]
--
-- >>> generateCompletions NoSuggestion
-- []
--
-- @since 0.19.1
generateCompletions :: Suggest -> IO [String]
generateCompletions = \case
  NoSuggestion -> return []
  SuggestAt _ -> return []
  SuggestIO ioCompletions -> ioCompletions

-- | Combine multiple IO completion sources.
--
-- Merges completion lists from multiple sources, removing duplicates
-- and maintaining consistent ordering for user experience.
--
-- ==== Examples
--
-- >>> let comp1 = return ["file1", "file2"]
-- >>> let comp2 = return ["file2", "file3"]
-- >>> combineCompletions [comp1, comp2]
-- ["file1", "file2", "file3"]
--
-- @since 0.19.1
combineCompletions :: [IO [String]] -> IO [String]
combineCompletions ioLists = do
  lists <- sequence ioLists
  return $ removeDuplicates $ concat lists

-- | Add completion to existing IO completion source.
--
-- Extends an existing completion source with additional options,
-- maintaining consistent ordering and removing duplicates.
--
-- ==== Examples
--
-- >>> let existing = return ["option1", "option2"]
-- >>> addCompletion existing (return ["option3"])
-- ["option1", "option2", "option3"]
--
-- @since 0.19.1
addCompletion :: IO [String] -> IO [String] -> IO [String]
addCompletion existing additional = do
  existingList <- existing
  additionalList <- additional
  return $ removeDuplicates $ existingList ++ additionalList

-- | Check if suggestion contains actionable completion information.
--
-- Determines whether a suggestion can provide meaningful completions
-- for user interaction and shell integration.
--
-- ==== Examples
--
-- >>> hasSuggestion (SuggestIO (return ["test"]))
-- True
--
-- >>> hasSuggestion NoSuggestion
-- False
--
-- @since 0.19.1
hasSuggestion :: Suggest -> Bool
hasSuggestion = \case
  NoSuggestion -> False
  SuggestAt _ -> False
  SuggestIO _ -> True

-- | Extract target position from suggestion if available.
--
-- Retrieves the specific target position for suggestions that are
-- position-aware, enabling context-specific completion behavior.
--
-- ==== Examples
--
-- >>> getSuggestionTarget (SuggestAt (SuggestTarget 3))
-- Just 3
--
-- >>> getSuggestionTarget NoSuggestion
-- Nothing
--
-- @since 0.19.1
getSuggestionTarget :: Suggest -> Maybe Int
getSuggestionTarget = \case
  SuggestAt target -> Just (target ^. suggestTarget)
  _ -> Nothing

-- | Check if suggestion targets a specific position.
--
-- Tests whether a suggestion is configured for position-specific
-- completion rather than general or IO-based completion.
--
-- ==== Examples
--
-- >>> isTargetSuggestion (SuggestAt (SuggestTarget 2))
-- True
--
-- >>> isTargetSuggestion (SuggestIO (return []))
-- False
--
-- @since 0.19.1
isTargetSuggestion :: Suggest -> Bool
isTargetSuggestion = \case
  SuggestAt _ -> True
  _ -> False

-- | Convert Maybe Int to Suggest representation.
--
-- Transforms optional index values into appropriate suggestion types,
-- handling the common pattern of converting parsing contexts to suggestions.
--
-- ==== Examples
--
-- >>> fromMaybeIndex (Just 3)
-- SuggestAt (SuggestTarget {_suggestTarget = 3})
--
-- >>> fromMaybeIndex Nothing
-- NoSuggestion
--
-- @since 0.19.1
fromMaybeIndex :: Maybe Int -> Suggest
fromMaybeIndex = maybe NoSuggestion targetSuggestion

-- | Extract target index from suggestion if available.
--
-- Converts suggestion types back to optional index values for
-- compatibility with legacy code and position-based logic.
--
-- ==== Examples
--
-- >>> toMaybeIndex (SuggestAt (SuggestTarget 3))
-- Just 3
--
-- >>> toMaybeIndex NoSuggestion
-- Nothing
--
-- @since 0.19.1
toMaybeIndex :: Suggest -> Maybe Int
toMaybeIndex = getSuggestionTarget

-- Helper function to remove duplicates while preserving order
removeDuplicates :: Eq a => [a] -> [a]
removeDuplicates = removeDuplicatesHelper []
  where
    removeDuplicatesHelper _ [] = []
    removeDuplicatesHelper seen (x : xs)
      | x `elem` seen = removeDuplicatesHelper seen xs
      | otherwise = x : removeDuplicatesHelper (x : seen) xs
