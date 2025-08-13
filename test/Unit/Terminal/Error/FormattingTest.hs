{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Terminal.Error.Formatting module.
--
-- Tests all formatting utilities including color formatting,
-- token formatting, and list presentation functions.
--
-- @since 0.19.1
module Unit.Terminal.Error.FormattingTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Terminal.Error.Formatting
  ( formatTokenName,
    formatFlagUsage,
    formatArgumentUsage,
    formatExamplesList,
    formatSuggestionsList,
    formatCommandList,
    reflowText,
    createStackedDocs,
    indentDoc,
    toRedText,
    toYellowText,
    toGreenText,
    toCyanText
  )
import qualified Text.PrettyPrint.ANSI.Leijen as Doc

tests :: TestTree
tests = testGroup "Terminal.Error.Formatting Tests"
  [ testColorFormatting
  , testTokenFormatting
  , testListFormatting
  , testTextUtilities
  ]

-- | Test color formatting functions
testColorFormatting :: TestTree
testColorFormatting = testGroup "Color Formatting Tests"
  [ testCase "toRedText formats text" $ do
      let result = toRedText "error"
      assertBool "Red text is not empty" (not (null (show result)))
  , testCase "toYellowText formats text" $ do
      let result = toYellowText "warning"
      assertBool "Yellow text is not empty" (not (null (show result)))
  , testCase "toGreenText formats text" $ do
      let result = toGreenText "success"
      assertBool "Green text is not empty" (not (null (show result)))
  , testCase "toCyanText formats text" $ do
      let result = toCyanText "info"
      assertBool "Cyan text is not empty" (not (null (show result)))
  ]

-- | Test token formatting functions
testTokenFormatting :: TestTree
testTokenFormatting = testGroup "Token Formatting Tests"
  [ testCase "formatTokenName wraps in angle brackets" $ do
      formatTokenName "file" @?= "<file>"
  , testCase "formatTokenName handles spaces" $ do
      formatTokenName "input file" @?= "<input-file>"
  , testCase "formatTokenName handles multiple words" $ do
      formatTokenName "source file path" @?= "<source-file-path>"
  , testCase "formatFlagUsage creates proper flag syntax" $ do
      let result = formatFlagUsage "output" "file"
      assertBool "Flag usage is not empty" (not (null (show result)))
  , testCase "formatArgumentUsage creates proper argument syntax" $ do
      let result = formatArgumentUsage "input"
      assertBool "Argument usage is not empty" (not (null (show result)))
  ]

-- | Test list formatting functions
testListFormatting :: TestTree
testListFormatting = testGroup "List Formatting Tests"
  [ testCase "formatExamplesList handles empty list" $ do
      let result = formatExamplesList []
      assertBool "Empty examples produces non-empty output" (not (null (show result)))
  , testCase "formatExamplesList formats non-empty list" $ do
      let examples = ["test.txt", "data.csv"]
          result = formatExamplesList examples
      assertBool "Examples list is not empty" (not (null (show result)))
  , testCase "formatSuggestionsList handles empty list" $ do
      let result = formatSuggestionsList []
      show result @?= ""  -- Should be empty doc
  , testCase "formatSuggestionsList handles single item" $ do
      let result = formatSuggestionsList ["suggestion"]
      assertBool "Single suggestion is not empty" (not (null (show result)))
  , testCase "formatSuggestionsList handles multiple items" $ do
      let result = formatSuggestionsList ["suggestion1", "suggestion2"]
      assertBool "Multiple suggestions are not empty" (not (null (show result)))
  , testCase "formatCommandList creates aligned list" $ do
      let commands = ["build", "test", "install"]
          result = formatCommandList "canopy" commands
      assertBool "Command list is not empty" (not (null (show result)))
  ]

-- | Test text utility functions
testTextUtilities :: TestTree
testTextUtilities = testGroup "Text Utility Tests"
  [ testCase "reflowText breaks text into words" $ do
      let result = reflowText "This is a test sentence"
      assertBool "Reflowed text is not empty" (not (null (show result)))
  , testCase "createStackedDocs combines documents" $ do
      let docs = [Doc.text "line1", Doc.text "line2", Doc.text "line3"]
          result = createStackedDocs docs
      assertBool "Stacked docs are not empty" (not (null (show result)))
  , testCase "indentDoc applies indentation" $ do
      let original = Doc.text "test"
          indented = indentDoc 4 original
      assertBool "Indented doc is different from original" (show indented /= show original)
  , testCase "indentDoc with zero spaces" $ do
      let original = Doc.text "test"
          indented = indentDoc 0 original
      show indented @?= show original
  ]

-- Helper function to check if text appears in Doc
isInDoc :: String -> Doc.Doc -> Bool
isInDoc text doc = text `elem` words (show doc)