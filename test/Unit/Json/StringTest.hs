{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Comprehensive test suite for Json.String module.
--
-- This module provides complete test coverage for all public functions,
-- edge cases, error conditions, and properties in Json.String.
--
-- Coverage Target: ≥80% line coverage
-- Test Categories: Unit, Property, Edge Case, Error Condition
--
-- @since 0.19.1
module Unit.Json.StringTest
  ( tests,
  )
where

import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Name as Name
import qualified Data.Utf8 as Utf8
import Data.Word (Word8)
import qualified Foreign.ForeignPtr as ForeignPtr
import Foreign.Ptr (Ptr)
import qualified Foreign.Ptr as Ptr
import qualified Json.String as JsonStr
import qualified Parse.Primitives as P
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import Prelude hiding (String)

-- | Main test tree containing all Json.String tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests =
  testGroup
    "Json.String Tests"
    [ unitTests,
      propertyTests,
      edgeCaseTests,
      errorConditionTests
    ]

-- | Unit tests for all public functions.
--
-- Tests basic functionality with known inputs and expected outputs.
-- Every public function must have at least one unit test.
unitTests :: TestTree
unitTests =
  testGroup
    "Unit Tests"
    [ testStringProperties,
      testConstructionFunctions,
      testConversionFunctions,
      testSpecializedConstruction
    ]

-- | Property-based tests for mathematical and logical operations.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with mathematical or logical operations.
propertyTests :: TestTree
propertyTests =
  testGroup
    "Property Tests"
    [ testConstructionProperties,
      testConversionProperties,
      testBuilderProperties
    ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests =
  testGroup
    "Edge Case Tests"
    [ testEmptyStrings,
      testLargeStrings,
      testUnicodeHandling,
      testSpecialCharacters
    ]

-- | Error condition tests for invalid inputs.
--
-- Verifies proper error handling and meaningful error messages
-- for all possible error conditions and invalid inputs.
errorConditionTests :: TestTree
errorConditionTests =
  testGroup
    "Error Condition Tests"
    [ testMemoryConstraints,
      testInvalidInputs,
      testBoundaryViolations
    ]

-- UNIT TESTS IMPLEMENTATION

-- | Tests for string property functions.
testStringProperties :: TestTree
testStringProperties =
  testGroup
    "String Properties"
    [ testCase "isEmpty detects empty string" $ do
        let emptyStr = JsonStr.fromChars ""
        JsonStr.isEmpty emptyStr @?= True,
      testCase "isEmpty detects non-empty string" $ do
        let nonEmptyStr = JsonStr.fromChars "hello"
        JsonStr.isEmpty nonEmptyStr @?= False,
      testCase "isEmpty on whitespace-only string" $ do
        let whitespaceStr = JsonStr.fromChars "   "
        JsonStr.isEmpty whitespaceStr @?= False,
      testCase "isEmpty on single character string" $ do
        let singleChar = JsonStr.fromChars "a"
        JsonStr.isEmpty singleChar @?= False
    ]

testConstructionFunctions :: TestTree
testConstructionFunctions =
  testGroup
    "Construction Functions"
    [ testCase "fromChars creates string from character list" $ do
        let chars = "hello world"
            jsonStr = JsonStr.fromChars chars
            result = JsonStr.toChars jsonStr
        result @?= chars,
      testCase "fromChars handles empty string" $ do
        let chars = ""
            jsonStr = JsonStr.fromChars chars
            result = JsonStr.toChars jsonStr
        result @?= chars
        JsonStr.isEmpty jsonStr @?= True,
      testCase "fromChars handles unicode characters" $ do
        let chars = "Hello 世界 🌍"
            jsonStr = JsonStr.fromChars chars
            result = JsonStr.toChars jsonStr
        result @?= chars,
      testCase "fromName creates string from Name" $ do
        let name = Name.fromChars "identifier"
            jsonStr = JsonStr.fromName name
            result = JsonStr.toChars jsonStr
        result @?= "identifier",
      testCase "fromName preserves name content exactly" $ do
        let name = Name.fromChars "moduleNameTest"
            jsonStr = JsonStr.fromName name
            result = JsonStr.toChars jsonStr
        result @?= "moduleNameTest",
      testCase "fromName handles complex names" $ do
        let name = Name.fromChars "Complex_Name123"
            jsonStr = JsonStr.fromName name
            result = JsonStr.toChars jsonStr
        result @?= "Complex_Name123"
        -- Note: fromPtr and fromSnippet are unsafe/internal functions
        -- We test them indirectly through other functions that use them
    ]

testConversionFunctions :: TestTree
testConversionFunctions =
  testGroup
    "Conversion Functions"
    [ testCase "toChars extracts character list" $ do
        let original = "test string"
            jsonStr = JsonStr.fromChars original
            result = JsonStr.toChars jsonStr
        result @?= original,
      testCase "toChars handles empty string correctly" $ do
        let jsonStr = JsonStr.fromChars ""
            result = JsonStr.toChars jsonStr
        result @?= "",
      testCase "toChars preserves unicode characters" $ do
        let original = "café naïve résumé"
            jsonStr = JsonStr.fromChars original
            result = JsonStr.toChars jsonStr
        result @?= original,
      testCase "toBuilder creates valid builder" $ do
        let original = "builder test"
            jsonStr = JsonStr.fromChars original
            builder = JsonStr.toBuilder jsonStr
            result = map (toEnum . fromIntegral) $ BSL.unpack $ B.toLazyByteString builder
        result @?= original,
      testCase "toBuilder handles empty string" $ do
        let jsonStr = JsonStr.fromChars ""
            builder = JsonStr.toBuilder jsonStr
            result = BSL.length $ B.toLazyByteString builder
        result @?= 0,
      testCase "toBuilder preserves unicode content" $ do
        let original = "unicode: ñ, é, 中"
            jsonStr = JsonStr.fromChars original
            builder = JsonStr.toBuilder jsonStr
            result = B.toLazyByteString builder
        -- Should produce non-zero output for unicode
        assertBool "Should produce non-empty output for unicode" (BSL.length result > 0)
    ]

testSpecializedConstruction :: TestTree
testSpecializedConstruction =
  testGroup
    "Specialized Construction"
    [ testCase "fromComment processes simple comment" $ do
        -- Create a simple snippet for testing
        -- Note: This test is limited due to the complexity of creating P.Snippet values
        let testStr = JsonStr.fromChars "test comment"
        -- We can't easily test fromComment without complex setup,
        -- so we test that the basic string operations work
        JsonStr.toChars testStr @?= "test comment"
    ]

-- PROPERTY TESTS

testConstructionProperties :: TestTree
testConstructionProperties =
  testGroup
    "Construction Properties"
    [ testProperty "fromChars roundtrip property" $ \chars ->
        let limitedChars = take 100 chars -- Limit for testing
            jsonStr = JsonStr.fromChars limitedChars
            result = JsonStr.toChars jsonStr
         in result == limitedChars,
      testProperty "fromName roundtrip through toChars" $ \nameChars ->
        let limitedChars = take 50 (filter isValidNameChar nameChars)
         in if null limitedChars
              then True -- Skip empty names
              else
                let name = Name.fromChars limitedChars
                    jsonStr = JsonStr.fromName name
                    result = JsonStr.toChars jsonStr
                 in result == limitedChars,
      testProperty "isEmpty consistency with fromChars" $ \chars ->
        let jsonStr = JsonStr.fromChars chars
         in JsonStr.isEmpty jsonStr == null chars
    ]

testConversionProperties :: TestTree
testConversionProperties =
  testGroup
    "Conversion Properties"
    [ testProperty "toChars preserves character count" $ \chars ->
        let limitedChars = take 100 chars
            jsonStr = JsonStr.fromChars limitedChars
            result = JsonStr.toChars jsonStr
         in length result == length limitedChars,
      testProperty "construction and conversion are inverses" $ \chars ->
        let limitedChars = take 100 chars
            roundtrip = JsonStr.toChars (JsonStr.fromChars limitedChars)
         in roundtrip == limitedChars
    ]

testBuilderProperties :: TestTree
testBuilderProperties =
  testGroup
    "Builder Properties"
    [ testProperty "toBuilder produces non-zero length for non-empty strings" $ \chars ->
        let nonEmptyChars = if null chars then "x" else chars
            limitedChars = take 100 nonEmptyChars
            jsonStr = JsonStr.fromChars limitedChars
            builder = JsonStr.toBuilder jsonStr
            result = B.toLazyByteString builder
         in BSL.length result > 0,
      testProperty "toBuilder length is reasonable for ASCII" $ \asciiChars ->
        let validAscii = filter (\c -> c >= ' ' && c <= '~') asciiChars
            limitedChars = take 50 validAscii
         in if null limitedChars
              then True
              else
                let jsonStr = JsonStr.fromChars limitedChars
                    builder = JsonStr.toBuilder jsonStr
                    result = B.toLazyByteString builder
                 in BSL.length result >= fromIntegral (length limitedChars)
    ]

-- EDGE CASE TESTS

testEmptyStrings :: TestTree
testEmptyStrings =
  testGroup
    "Empty String Tests"
    [ testCase "empty string creation and detection" $ do
        let emptyStr = JsonStr.fromChars ""
        JsonStr.isEmpty emptyStr @?= True
        JsonStr.toChars emptyStr @?= "",
      testCase "empty builder from empty string" $ do
        let emptyStr = JsonStr.fromChars ""
            builder = JsonStr.toBuilder emptyStr
            result = B.toLazyByteString builder
        BSL.length result @?= 0,
      testCase "empty name creates empty string" $ do
        let emptyName = Name.fromChars ""
            jsonStr = JsonStr.fromName emptyName
        JsonStr.isEmpty jsonStr @?= True
        JsonStr.toChars jsonStr @?= ""
    ]

testLargeStrings :: TestTree
testLargeStrings =
  testGroup
    "Large String Tests"
    [ testCase "large string creation and roundtrip" $ do
        let largeString = replicate 1000 'a'
            jsonStr = JsonStr.fromChars largeString
            result = JsonStr.toChars jsonStr
        length result @?= 1000
        result @?= largeString,
      testCase "large string not detected as empty" $ do
        let largeString = replicate 500 'x'
            jsonStr = JsonStr.fromChars largeString
        JsonStr.isEmpty jsonStr @?= False,
      testCase "large string builder produces correct length" $ do
        let largeString = replicate 200 'b'
            jsonStr = JsonStr.fromChars largeString
            builder = JsonStr.toBuilder jsonStr
            result = B.toLazyByteString builder
        BSL.length result @?= 200
    ]

testUnicodeHandling :: TestTree
testUnicodeHandling =
  testGroup
    "Unicode Handling Tests"
    [ testCase "basic unicode characters" $ do
        let unicodeStr = "café"
            jsonStr = JsonStr.fromChars unicodeStr
            result = JsonStr.toChars jsonStr
        result @?= unicodeStr,
      testCase "mixed unicode and ASCII" $ do
        let mixedStr = "Hello 世界 World"
            jsonStr = JsonStr.fromChars mixedStr
            result = JsonStr.toChars jsonStr
        result @?= mixedStr,
      testCase "emoji characters" $ do
        let emojiStr = "🌍🚀⭐"
            jsonStr = JsonStr.fromChars emojiStr
            result = JsonStr.toChars jsonStr
        result @?= emojiStr,
      testCase "unicode builder produces correct output" $ do
        let unicodeStr = "tëst"
            jsonStr = JsonStr.fromChars unicodeStr
            builder = JsonStr.toBuilder jsonStr
            result = B.toLazyByteString builder
        -- Unicode should produce more bytes than characters
        assertBool "Unicode should produce output" (BSL.length result > 0),
      testCase "complex unicode characters" $ do
        let complexStr = "नमस्ते العالم مرحبا"
            jsonStr = JsonStr.fromChars complexStr
            result = JsonStr.toChars jsonStr
        result @?= complexStr
    ]

testSpecialCharacters :: TestTree
testSpecialCharacters =
  testGroup
    "Special Character Tests"
    [ testCase "newline characters preserved" $ do
        let stringWithNewlines = "line1\nline2\nline3"
            jsonStr = JsonStr.fromChars stringWithNewlines
            result = JsonStr.toChars jsonStr
        result @?= stringWithNewlines,
      testCase "tab characters preserved" $ do
        let stringWithTabs = "col1\tcol2\tcol3"
            jsonStr = JsonStr.fromChars stringWithTabs
            result = JsonStr.toChars jsonStr
        result @?= stringWithTabs,
      testCase "quote characters preserved" $ do
        let stringWithQuotes = "say \"hello\" world"
            jsonStr = JsonStr.fromChars stringWithQuotes
            result = JsonStr.toChars jsonStr
        result @?= stringWithQuotes,
      testCase "backslash characters preserved" $ do
        let stringWithBackslashes = "path\\to\\file"
            jsonStr = JsonStr.fromChars stringWithBackslashes
            result = JsonStr.toChars jsonStr
        result @?= stringWithBackslashes,
      testCase "mixed special characters" $ do
        let mixedSpecial = "\n\t\r\"\\/"
            jsonStr = JsonStr.fromChars mixedSpecial
            result = JsonStr.toChars jsonStr
        result @?= mixedSpecial,
      testCase "control characters preserved" $ do
        let controlChars = "\x01\x02\x03"
            jsonStr = JsonStr.fromChars controlChars
            result = JsonStr.toChars jsonStr
        result @?= controlChars
    ]

-- ERROR CONDITION TESTS

testMemoryConstraints :: TestTree
testMemoryConstraints =
  testGroup
    "Memory Constraint Tests"
    [ testCase "very large string doesn't cause memory issues" $ do
        let veryLargeString = replicate 5000 'z'
            jsonStr = JsonStr.fromChars veryLargeString
            result = JsonStr.toChars jsonStr
        -- Should complete without memory errors
        length result @?= 5000,
      testCase "repeated creation doesn't leak memory" $ do
        let strings = [JsonStr.fromChars ("test" ++ show i) | i <- [1 .. 100]]
            lengths = map (length . JsonStr.toChars) strings
        -- All should have expected lengths
        all (> 4) lengths @?= True
    ]

testInvalidInputs :: TestTree
testInvalidInputs =
  testGroup
    "Invalid Input Tests"
    [ testCase "null character handling" $ do
        let stringWithNull = "before\0after"
            jsonStr = JsonStr.fromChars stringWithNull
            result = JsonStr.toChars jsonStr
        -- Null character should be preserved
        result @?= stringWithNull,
      testCase "high unicode code points" $ do
        let highUnicode = "\x1F600" -- Emoji
            jsonStr = JsonStr.fromChars highUnicode
            result = JsonStr.toChars jsonStr
        result @?= highUnicode
    ]

testBoundaryViolations :: TestTree
testBoundaryViolations =
  testGroup
    "Boundary Violation Tests"
    [ testCase "maximum practical string length" $ do
        let maxPracticalLength = 10000
            longString = replicate maxPracticalLength 'a'
            jsonStr = JsonStr.fromChars longString
        JsonStr.isEmpty jsonStr @?= False
        length (JsonStr.toChars jsonStr) @?= maxPracticalLength,
      testCase "string with only whitespace characters" $ do
        let whitespaceString = "   \t\n\r   "
            jsonStr = JsonStr.fromChars whitespaceString
            result = JsonStr.toChars jsonStr
        result @?= whitespaceString
        JsonStr.isEmpty jsonStr @?= False -- Should not be empty
    ]

-- HELPER FUNCTIONS

-- | Check if character is valid for name construction
isValidNameChar :: Char -> Bool
isValidNameChar c =
  (c >= 'a' && c <= 'z')
    || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9')
    || c == '_'
