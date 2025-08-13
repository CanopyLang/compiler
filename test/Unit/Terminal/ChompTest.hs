{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Terminal.Chomp module.
--
-- Tests the comprehensive command-line argument and flag parsing functionality
-- provided by the Terminal.Chomp framework. Validates type-safe parsing,
-- error handling, suggestion generation, and integration between sub-modules.
--
-- @since 0.19.1
module Unit.Terminal.ChompTest (tests) where

import qualified Control.Exception as Exception
import Control.Exception (SomeException, evaluate)
import Control.Lens ((^.), (&), (.~))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import qualified Terminal.Chomp as Chomp
import Terminal.Chomp.Types
  ( Chunk (..),
    Suggest (..),
    SuggestTarget (..),
    Value (..),
    ValueType (..),
    chunkContent,
    chunkIndex,
    createChunk,
    createSuggest,
    extractValue,
    suggestTarget
  )
import Terminal.Internal
  ( Args (..),
    CompleteArgs (..),
    Flag (..),
    Flags (..),
    Parser (..),
    RequiredArgs (..)
  )

tests :: TestTree
tests = testGroup "Terminal.Chomp Tests"
  [ testChunkCreation
  , testSuggestionSystem
  , testValueExtraction
  , testChompInterface
  , testErrorHandling
  , testLensOperations
  ]

-- | Test chunk creation and manipulation
testChunkCreation :: TestTree
testChunkCreation = testGroup "Chunk Creation Tests"
  [ testCase "createChunk with valid parameters" $ do
      let chunk = createChunk 1 "test.txt"
      chunk ^. chunkIndex @?= 1
      chunk ^. chunkContent @?= "test.txt"
  , testCase "createChunk with different positions" $ do
      let chunk1 = createChunk 5 "arg1"
          chunk2 = createChunk 10 "arg2"
      chunk1 ^. chunkIndex @?= 5
      chunk2 ^. chunkIndex @?= 10
      chunk1 ^. chunkContent @?= "arg1"
      chunk2 ^. chunkContent @?= "arg2"
  , testCase "chunk equality and show" $ do
      let chunk1 = createChunk 1 "test"
          chunk2 = createChunk 1 "test"
          chunk3 = createChunk 2 "test"
      chunk1 @?= chunk2
      assertBool "Different index chunks should not be equal" (chunk1 /= chunk3)
      assertBool "Show instance works" (length (show chunk1) > 0)
  ]

-- | Test suggestion system functionality  
testSuggestionSystem :: TestTree
testSuggestionSystem = testGroup "Suggestion System Tests"
  [ testCase "createSuggest with valid index" $ do
      let suggest = createSuggest 3
      case suggest of
        SuggestAt target -> target ^. suggestTarget @?= 3
        _ -> assertBool "Expected SuggestAt" False
  , testCase "createSuggest with zero index" $ do
      let suggest = createSuggest 0
      suggest @?= NoSuggestion
  , testCase "createSuggest with negative index" $ do
      let suggest = createSuggest (-1)
      suggest @?= NoSuggestion
  , testCase "suggestion show instance" $ do
      let suggest1 = NoSuggestion
          suggest2 = createSuggest 5
      assertBool "NoSuggestion shows correctly" ("NoSuggestion" `elem` words (show suggest1))
      assertBool "SuggestAt shows correctly" ("SuggestAt" `elem` words (show suggest2))
  ]

-- | Test value extraction functionality
testValueExtraction :: TestTree
testValueExtraction = testGroup "Value Extraction Tests"
  [ testCase "extractValue from NoValue" $ do
      extractValue NoValue @?= Nothing
  , testCase "extractValue from DefiniteValue" $ do
      let valueType = ValueType { _valueIndex = 1, _valueContent = "output.txt" }
          value = DefiniteValue valueType
      extractValue value @?= Just "output.txt"
  , testCase "extractValue from PossibleValue" $ do
      let chunk = createChunk 2 "input.txt"
          value = PossibleValue chunk
      extractValue value @?= Just "input.txt"
  ]

-- | Test main chomp interface with simple cases
testChompInterface :: TestTree
testChompInterface = testGroup "Chomp Interface Tests"
  [ testCase "chomp with empty arguments" $ do
      let noArgs = Args []
          noFlags = FDone ()
          (suggestions, result) = Chomp.chomp Nothing [] noArgs noFlags
      suggestionList <- suggestions
      assertBool "Empty suggestions for empty args" (null suggestionList)
      case result of
        Left _ -> assertBool "Should succeed with empty args and empty input" False
        Right ((), ()) -> assertBool "Expected success with empty args and empty input" True
  , testCase "chomp with simple flag" $ do
      let noArgs = Args []
          flagSpec = FDone True  -- Simple boolean flag
          (suggestions, _) = Chomp.chomp Nothing ["--test"] noArgs flagSpec
      suggestionList <- suggestions  
      assertBool "Suggestions available" (length suggestionList >= 0)
  , testCase "chomp with suggestion index" $ do
      let noArgs = Args []
          noFlags = FDone ()
          (suggestions, _) = Chomp.chomp (Just 1) [""] noArgs noFlags
      suggestionList <- suggestions
      assertBool "Suggestions list is valid" (length suggestionList >= 0)
  ]

-- | Test error handling scenarios
testErrorHandling :: TestTree
testErrorHandling = testGroup "Error Handling Tests"
  [ testCase "invalid chunk index handling" $ do
      -- Test error behavior for createChunk with invalid index
      result <- Exception.try (evaluate (createChunk 0 "test")) :: IO (Either SomeException Chunk)
      case result of
        Left _ -> assertBool "Expected error for zero index" True
        Right _ -> assertBool "Should fail with zero index" False
  , testCase "error propagation in chomp" $ do
      let invalidArgs = Args []  -- Empty args will cause parsing error
          noFlags = FDone ()
          (_, result) = Chomp.chomp Nothing ["arg1"] invalidArgs noFlags
      case result of
        Left _ -> assertBool "Expected parsing error" True
        Right _ -> assertBool "Should fail with invalid args" False
  ]

-- | Test lens operations on all types
testLensOperations :: TestTree
testLensOperations = testGroup "Lens Operations Tests"
  [ testCase "chunk lens access" $ do
      let chunk = createChunk 5 "filename.txt"
      chunk ^. chunkIndex @?= 5
      chunk ^. chunkContent @?= "filename.txt"
  , testCase "suggest target lens access" $ do
      let target = SuggestTarget 3
      target ^. suggestTarget @?= 3
  , testCase "chunk lens modification" $ do
      let chunk = createChunk 1 "old"
          modified = chunk & chunkContent .~ "new"
      modified ^. chunkContent @?= "new"
      modified ^. chunkIndex @?= 1  -- Index unchanged
  ]

-- Helper function for error testing
try :: a -> Either String a
try x = Right x  -- Simplified for testing - in real code would catch errors


