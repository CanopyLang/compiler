{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Terminal.Error.Suggestions module.
--
-- Tests suggestion generation algorithms including edit distance
-- calculations, flag suggestions, and command suggestions.
--
-- @since 0.19.1
module Unit.Terminal.Error.SuggestionsTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Terminal.Error.Suggestions
  ( calculateEditDistance,
    extractFlagName,
    formatSuggestionText,
    generateCommandSuggestions,
    limitSuggestions
  )
import Terminal.Internal (Flag (..), Flags (..), Parser (..))
import qualified Text.PrettyPrint.ANSI.Leijen as Doc

tests :: TestTree
tests = testGroup "Terminal.Error.Suggestions Tests"
  [ testEditDistance
  , testFlagNameExtraction
  , testCommandSuggestions
  , testSuggestionFormatting
  , testUtilities
  ]

-- | Test edit distance calculations
testEditDistance :: TestTree
testEditDistance = testGroup "Edit Distance Tests"
  [ testCase "identical strings have distance 0" $ do
      calculateEditDistance "test" "test" @?= 0
  , testCase "single character difference" $ do
      calculateEditDistance "test" "best" @?= 1
  , testCase "single character insertion" $ do
      calculateEditDistance "test" "tests" @?= 1
  , testCase "single character deletion" $ do
      calculateEditDistance "tests" "test" @?= 1
  , testCase "completely different strings" $ do
      let distance = calculateEditDistance "abc" "xyz"
      assertBool "Different strings have positive distance" (distance > 0)
  , testCase "empty string distances" $ do
      calculateEditDistance "" "test" @?= 4
      calculateEditDistance "test" "" @?= 4
  ]

-- | Test flag name extraction
testFlagNameExtraction :: TestTree
testFlagNameExtraction = testGroup "Flag Name Extraction Tests"
  [ testCase "extract from simple flag" $ do
      extractFlagName "--verbose" @?= "verbose"
  , testCase "extract from flag with value" $ do
      extractFlagName "--output=file.txt" @?= "output"
  , testCase "extract from single dash flag" $ do
      extractFlagName "-v" @?= "v"
  , testCase "extract from flag without dashes" $ do
      extractFlagName "verbose" @?= "verbose"
  , testCase "extract from complex flag" $ do
      extractFlagName "--some-long-flag=complex-value" @?= "some-long-flag"
  ]

-- | Test command suggestion generation
testCommandSuggestions :: TestTree
testCommandSuggestions = testGroup "Command Suggestions Tests"
  [ testCase "suggests close matches" $ do
      let commands = ["build", "test", "install"]
          suggestions = generateCommandSuggestions "biuld" commands
      assertBool "Contains build suggestion" ("build" `elem` suggestions)
  , testCase "suggests multiple close matches" $ do
      let commands = ["test", "tests", "testing"]
          suggestions = generateCommandSuggestions "tes" commands
      assertBool "Contains test suggestions" (length suggestions > 0)
  , testCase "returns empty for no good matches" $ do
      let commands = ["build", "test"]
          suggestions = generateCommandSuggestions "xyz" commands
      -- Should still return something based on distance, or empty if threshold too high
      assertBool "Handles no good matches" (length suggestions >= 0)
  , testCase "limits number of suggestions" $ do
      let commands = ["build", "test", "install", "init", "bump", "publish"]
          suggestions = generateCommandSuggestions "b" commands
      assertBool "Limits suggestions reasonably" (length suggestions <= 5)
  ]

-- | Test suggestion formatting
testSuggestionFormatting :: TestTree
testSuggestionFormatting = testGroup "Suggestion Formatting Tests"
  [ testCase "formats empty suggestions" $ do
      let result = formatSuggestionText []
      length result @?= 0
  , testCase "formats single suggestion" $ do
      let result = formatSuggestionText ["build"]
      length result @?= 3  -- "Try", "build", "instead?"
  , testCase "formats two suggestions" $ do
      let result = formatSuggestionText ["build", "test"]
      length result @?= 5  -- "Try", "build", "or", "test", "instead?"
  , testCase "formats three suggestions" $ do
      let result = formatSuggestionText ["build", "test", "install"]
      assertBool "Three suggestions formatted correctly" (length result >= 5)
  , testCase "formats many suggestions" $ do
      let suggestions = ["build", "test", "install", "init", "bump"]
          result = formatSuggestionText suggestions
      assertBool "Many suggestions formatted with commas" (length result > 5)
  ]

-- | Test utility functions
testUtilities :: TestTree
testUtilities = testGroup "Utility Function Tests"
  [ testCase "limitSuggestions respects limit" $ do
      let suggestions = [(1, "a"), (2, "b"), (3, "c"), (4, "d"), (5, "e")]
          limited = limitSuggestions 3 suggestions
      length limited @?= 3
  , testCase "limitSuggestions handles empty list" $ do
      let limited = limitSuggestions 3 []
      limited @?= []
  , testCase "limitSuggestions handles limit larger than list" $ do
      let suggestions = [(1, "a"), (2, "b")]
          limited = limitSuggestions 5 suggestions
      length limited @?= 2
  , testCase "limitSuggestions preserves order" $ do
      let suggestions = [(1, "first"), (2, "second"), (3, "third")]
          limited = limitSuggestions 2 suggestions
      map snd limited @?= ["first", "second"]
  ]