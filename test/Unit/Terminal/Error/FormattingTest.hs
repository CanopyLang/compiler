{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Terminal.Error.Formatting module.
--
-- Tests all formatting utilities including color formatting,
-- token formatting, and list presentation functions.
--
-- @since 0.19.1
module Unit.Terminal.Error.FormattingTest (tests) where

import Terminal.Error.Formatting
  ( createStackedDocs,
    formatArgumentUsage,
    formatCommandList,
    formatExamplesList,
    formatFlagUsage,
    formatSuggestionsList,
    formatTokenName,
    indentDoc,
    reflowText,
    toCyanText,
    toGreenText,
    toRedText,
    toYellowText,
  )
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, testCase, (@?=))
import qualified Text.PrettyPrint.ANSI.Leijen as Doc

tests :: TestTree
tests =
  testGroup
    "Terminal.Error.Formatting Tests"
    [ testColorFormatting,
      testTokenFormatting,
      testListFormatting,
      testTextUtilities
    ]

-- | Test color formatting functions
testColorFormatting :: TestTree
testColorFormatting =
  testGroup
    "Color Formatting Tests"
    [ testCase "toRedText applies color formatting" $ do
        let result = toRedText "error"
        -- Test that colored output differs from plain text
        assertBool "Red formatting changes output" (show result /= "error"),
      testCase "toYellowText applies color formatting" $ do
        let result = toYellowText "warning"
        assertBool "Yellow formatting changes output" (show result /= "warning"),
      testCase "toGreenText applies color formatting" $ do
        let result = toGreenText "success"
        assertBool "Green formatting changes output" (show result /= "success"),
      testCase "toCyanText applies color formatting" $ do
        let result = toCyanText "info"
        assertBool "Cyan formatting changes output" (show result /= "info")
    ]

-- | Test token formatting functions
testTokenFormatting :: TestTree
testTokenFormatting =
  testGroup
    "Token Formatting Tests"
    [ testCase "formatTokenName wraps in angle brackets" $ do
        formatTokenName "file" @?= "<file>",
      testCase "formatTokenName handles spaces" $ do
        formatTokenName "input file" @?= "<input-file>",
      testCase "formatTokenName handles multiple words" $ do
        formatTokenName "source file path" @?= "<source-file-path>",
      testCase "formatFlagUsage creates readable flag syntax" $ do
        let result = formatFlagUsage "output" "file"
        -- Test that flag formatting produces structured output
        assertBool "Flag formatting produces documentation" (length (show result) > length ("output" ++ "file")),
      testCase "formatArgumentUsage creates readable argument syntax" $ do
        let result = formatArgumentUsage "input"
        assertBool "Argument formatting enhances readability" (length (show result) > length ("input" :: String))
    ]

-- | Test list formatting functions
testListFormatting :: TestTree
testListFormatting =
  testGroup
    "List Formatting Tests"
    [ testCase "formatExamplesList handles empty list" $ do
        let result = formatExamplesList []
        assertEqual "Empty examples produce placeholder" "(no examples available)" (show result),
      testCase "formatExamplesList formats non-empty list" $ do
        let examples = ["test.txt", "data.csv"]
            result = formatExamplesList examples
        assertBool "Examples list produces structured output" (length (show result) > sum (map length examples)),
      testCase "formatSuggestionsList handles empty list" $ do
        let result = formatSuggestionsList []
        assertBool "Empty suggestions produce minimal output" (length (show result) == 0),
      testCase "formatSuggestionsList handles single item" $ do
        let result = formatSuggestionsList ["suggestion"]
        assertBool "Single suggestion produces readable output" (length (show result) > length ("suggestion" :: String)),
      testCase "formatSuggestionsList handles multiple items" $ do
        let result = formatSuggestionsList ["suggestion1", "suggestion2"]
        let expectedMinLength = length ("suggestion1" :: String) + length ("suggestion2" :: String)
        assertBool "Multiple suggestions produce structured output" (length (show result) > expectedMinLength),
      testCase "formatCommandList creates aligned list" $ do
        let commands = ["build", "test", "install"]
            result = formatCommandList "canopy" commands
        let expectedMinLength = sum (map length commands) + length ("canopy" :: String)
        assertBool "Command list produces comprehensive output" (length (show result) > expectedMinLength)
    ]

-- | Test text utility functions
testTextUtilities :: TestTree
testTextUtilities =
  testGroup
    "Text Utility Tests"
    [ testCase "reflowText processes text appropriately" $ do
        let input = "This is a test sentence"
            result = reflowText input
        assertBool "Reflowed text maintains content" (length (show result) >= length input),
      testCase "createStackedDocs combines documents" $ do
        let docs = [Doc.text "line1", Doc.text "line2", Doc.text "line3"]
            result = createStackedDocs docs
        let expectedMinLength = sum (map (length . show) docs)
        assertBool "Stacked docs combine content" (length (show result) >= expectedMinLength),
      testCase "indentDoc applies indentation" $ do
        let original = Doc.text "test"
            indented = indentDoc 4 original
        assertBool "Indented doc is different from original" (show indented /= show original),
      testCase "indentDoc with zero spaces" $ do
        let original = Doc.text "test"
            indented = indentDoc 0 original
        assertBool "Zero indentation preserves content" (show indented == show original)
    ]
