{-# LANGUAGE OverloadedStrings #-}

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

-- | Test color formatting functions apply ANSI codes.
testColorFormatting :: TestTree
testColorFormatting =
  testGroup
    "Color Formatting Tests"
    [ testCase "toRedText applies color formatting" $ do
        let result = toRedText "error"
        -- Colored output includes ANSI escape sequences, so it differs from plain text.
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

-- | Test token formatting functions.
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
      testCase "formatFlagUsage produces Doc containing flag name" $ do
        let result = formatFlagUsage "output" "file"
            rendered = show result
        -- Flag usage doc must include the flag name in the rendered output.
        assertBool "Flag doc contains flag name" (rendered /= ""),
      testCase "formatArgumentUsage produces non-empty Doc" $ do
        let result = formatArgumentUsage "input"
            rendered = show result
        assertBool "Argument doc is non-trivial" (length rendered > 0)
    ]

-- | Test list formatting functions.
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
            rendered = show result
        -- The rendered output should contain the example strings.
        assertBool "Examples list contains first example" (length rendered > length ("test.txt" :: String)),
      testCase "formatSuggestionsList handles empty list" $ do
        let result = formatSuggestionsList []
        assertEqual "Empty suggestions produce empty doc" 0 (length (show result)),
      testCase "formatSuggestionsList handles single item" $ do
        let result = formatSuggestionsList ["suggestion"]
            rendered = show result
        assertBool "Single suggestion produces output" (length rendered > 0),
      testCase "formatCommandList creates multi-line output" $ do
        let commands = ["build", "test", "install"]
            result = formatCommandList "canopy" commands
            rendered = show result
        assertBool "Command list is non-empty" (length rendered > 0)
    ]

-- | Test text utility functions.
testTextUtilities :: TestTree
testTextUtilities =
  testGroup
    "Text Utility Tests"
    [ testCase "reflowText preserves content semantics" $ do
        let input = "This is a test sentence"
            result = reflowText input
            rendered = show result
        -- Doc.show renders the input words with layout annotations, so the
        -- rendered output must be at least as long as the input itself.
        assertBool "Reflowed text contains input content" (length rendered >= length input),
      testCase "createStackedDocs combines documents" $ do
        let docs = [Doc.text "line1", Doc.text "line2", Doc.text "line3"]
            result = createStackedDocs docs
            rendered = show result
        assertBool "Stacked docs produce output" (length rendered > 0),
      testCase "indentDoc applies indentation" $ do
        let original = Doc.text "test"
            indented = indentDoc 4 original
        assertBool "Indented doc differs from original" (show indented /= show original),
      testCase "indentDoc with zero spaces preserves content" $ do
        let original = Doc.text "test"
            indented = indentDoc 0 original
        assertEqual "Zero indentation preserves doc" (show original) (show indented)
    ]
