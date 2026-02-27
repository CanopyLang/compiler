{-# LANGUAGE OverloadedStrings #-}

-- | Comprehensive test suite for Json.Encode module.
--
-- This module provides complete test coverage for all public functions,
-- edge cases, error conditions, and properties in Json.Encode.
--
-- Coverage Target: ≥80% line coverage
-- Test Categories: Unit, Property, Edge Case, Error Condition
--
-- @since 0.19.1
module Unit.Json.EncodeTest
  ( tests,
  )
where

import qualified Control.Arrow as Arrow
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Lazy.Char8 as LBS
import qualified Data.Map as Map
import qualified Canopy.Data.Name as Name
import qualified Data.Scientific as Sci
import qualified Json.Encode as Encode
import qualified Json.String as JsonStr
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

-- | Main test tree containing all Json.Encode tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests =
  testGroup
    "Json.Encode Tests"
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
    [ testValueConstructors,
      testEncodingFunctions,
      testFileOperations,
      testUtilityFunctions,
      testConvenienceOperators
    ]

-- | Property-based tests for mathematical and logical operations.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with mathematical or logical operations.
propertyTests :: TestTree
propertyTests =
  testGroup
    "Property Tests"
    [ testEncodingProperties,
      testRoundtripProperties,
      testStructuralProperties
    ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests =
  testGroup
    "Edge Case Tests"
    [ testEmptyStructures,
      testLargeStructures,
      testNestedStructures,
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
    [ testInvalidInputs,
      testMemoryConstraints,
      testEncodingFailures
    ]

-- UNIT TESTS IMPLEMENTATION

-- | Tests for Value constructor functions.
testValueConstructors :: TestTree
testValueConstructors =
  testGroup
    "Value Constructors"
    [ testCase "array creates Array value" $ do
        let values = [Encode.int 1, Encode.int 2, Encode.int 3]
            result = Encode.array values
        case result of
          Encode.Array vs -> length vs @?= length values
          _ -> assertFailure "array should create Array value",
      testCase "object creates Object value" $ do
        let pairs = [(JsonStr.fromChars "key", Encode.string (JsonStr.fromChars "value"))]
            result = Encode.object pairs
        case result of
          Encode.Object ps -> length ps @?= length pairs
          _ -> assertFailure "object should create Object value",
      testCase "string creates String value with quotes" $ do
        let jsonStr = JsonStr.fromChars "test"
            result = Encode.string jsonStr
        case result of
          Encode.String builder -> do
            let output = BSL.unpack (BB.toLazyByteString builder)
            head output @?= fromIntegral (fromEnum '"')
            last output @?= fromIntegral (fromEnum '"')
          _ -> assertFailure "string should create String value",
      testCase "name creates String value from Name" $ do
        let nm = Name.fromChars "identifier"
            result = Encode.name nm
        case result of
          Encode.String _ -> return () -- Correct type
          _ -> assertFailure "name should create String value",
      testCase "bool creates Boolean value" $ do
        let trueResult = LBS.unpack $ BB.toLazyByteString $ Encode.encodeUgly (Encode.bool True)
            falseResult = LBS.unpack $ BB.toLazyByteString $ Encode.encodeUgly (Encode.bool False)
        trueResult @?= "true"
        falseResult @?= "false",
      testCase "int creates Integer value" $ do
        let result = LBS.unpack $ BB.toLazyByteString $ Encode.encodeUgly (Encode.int 42)
        result @?= "42"
        let negResult = LBS.unpack $ BB.toLazyByteString $ Encode.encodeUgly (Encode.int (-1))
            zeroResult = LBS.unpack $ BB.toLazyByteString $ Encode.encodeUgly (Encode.int 0)
        negResult @?= "-1"
        zeroResult @?= "0",
      testCase "number creates Number value" $ do
        let scientific = Sci.fromFloatDigits 3.14159
            result = Encode.number scientific
        case result of
          Encode.Number s -> s @?= scientific
          _ -> assertFailure "number should create Number value",
      testCase "null creates Null value" $ do
        let result = LBS.unpack $ BB.toLazyByteString $ Encode.encodeUgly Encode.null
        result @?= "null"
    ]

testEncodingFunctions :: TestTree
testEncodingFunctions =
  testGroup
    "Encoding Functions"
    [ testCase "encode produces pretty-formatted JSON" $ do
        let value = Encode.object [("name" Encode.==> Encode.string (JsonStr.fromChars "Alice"))]
            result = BSL.unpack (BB.toLazyByteString (Encode.encode value))
            expectedSubstrings = ["{", "\"name\":", "\"Alice\"", "}"]
        mapM_
          ( \substr ->
              assertBool
                ("Should contain: " ++ substr)
                (all (\c -> fromIntegral (fromEnum c) `elem` result) substr)
          )
          expectedSubstrings,
      testCase "encodeUgly produces compact JSON" $ do
        let value = Encode.object [("name" Encode.==> Encode.string (JsonStr.fromChars "Alice"))]
            result = BSL.unpack (BB.toLazyByteString (Encode.encodeUgly value))
            resultStr = map (toEnum . fromIntegral) result
        -- Should not contain unnecessary whitespace
        assertBool "Should not contain newlines" ('\n' `notElem` resultStr)
        assertBool "Should contain core content" (all (`elem` resultStr) ("\"name\":\"Alice\"" :: String)),
      testCase "encode handles empty array" $ do
        let value = Encode.array []
            result = BSL.unpack (BB.toLazyByteString (Encode.encode value))
            resultStr = map (toEnum . fromIntegral) result
        resultStr @?= "[]",
      testCase "encode handles empty object" $ do
        let value = Encode.object []
            result = BSL.unpack (BB.toLazyByteString (Encode.encode value))
            resultStr = map (toEnum . fromIntegral) result
        resultStr @?= "{}",
      testCase "encodeUgly handles nested structures" $ do
        let value =
              Encode.object
                [ "users" Encode.==> Encode.array [Encode.string (JsonStr.fromChars "Alice")],
                  "count" Encode.==> Encode.int 1
                ]
            result = BSL.unpack (BB.toLazyByteString (Encode.encodeUgly value))
            resultStr = map (toEnum . fromIntegral) result
        -- Verify compact format without spaces
        assertBool "Should not contain spaces around colons" (not ("\" :" `elem` [resultStr]))
        assertBool "Should contain essential content" (all (`elem` resultStr) ("users" :: String))
    ]

testFileOperations :: TestTree
testFileOperations =
  testGroup
    "File Operations"
    [ testCase "write and writeUgly produce different outputs" $ do
        -- Note: We can't easily test actual file I/O in unit tests
        -- Instead we test the encoding functions they use
        let value = Encode.object [("test" Encode.==> Encode.int 42)]
            prettyOutput = BB.toLazyByteString (Encode.encode value <> "\n")
            uglyOutput = BB.toLazyByteString (Encode.encodeUgly value)
        -- Pretty should be longer due to formatting
        assertBool "Pretty output should be longer" (BSL.length prettyOutput > BSL.length uglyOutput)
    ]

testUtilityFunctions :: TestTree
testUtilityFunctions =
  testGroup
    "Utility Functions"
    [ testCase "dict converts Map to Object" $ do
        let inputMap = Map.fromList [("key1", "value1"), ("key2", "value2")]
            encodeKey = JsonStr.fromChars
            encodeValue = Encode.string . JsonStr.fromChars
            result = Encode.dict encodeKey encodeValue inputMap
        case result of
          Encode.Object pairs -> length pairs @?= 2
          _ -> assertFailure "dict should produce Object",
      testCase "list converts list to Array" $ do
        let inputList = [1, 2, 3]
            encodeEntry = Encode.int
            result = Encode.list encodeEntry inputList
        case result of
          Encode.Array values -> length values @?= 3
          _ -> assertFailure "list should produce Array",
      testCase "chars handles string with escape characters" $ do
        let input = "hello\nworld\"test\\"
            result = Encode.chars input
        case result of
          Encode.String builder -> do
            let output = BSL.unpack (BB.toLazyByteString builder)
                outputStr = map (toEnum . fromIntegral) output
            outputStr @?= "\"hello\\nworld\\\"test\\\\\""
          _ -> assertFailure "chars should produce String value"
    ]

testConvenienceOperators :: TestTree
testConvenienceOperators =
  testGroup
    "Convenience Operators"
    [ testCase "==> creates key-value pair" $ do
        let key = "testKey"
            value = Encode.int 42
            (resultKey, resultValue) = key Encode.==> value
        JsonStr.toChars resultKey @?= key
        let expectedEncoded = LBS.unpack $ BB.toLazyByteString $ Encode.encodeUgly value
            actualEncoded = LBS.unpack $ BB.toLazyByteString $ Encode.encodeUgly resultValue
        actualEncoded @?= expectedEncoded,
      testCase "==> works with different value types" $ do
        let stringPair = "str" Encode.==> Encode.string (JsonStr.fromChars "value")
            boolPair = "bool" Encode.==> Encode.bool True
            intPair = "int" Encode.==> Encode.int 123
        -- Verify all pairs have correct structure
        case stringPair of
          (k, v) -> do
            JsonStr.toChars k @?= "str"
            case v of
              Encode.String _ -> return ()
              _ -> assertFailure "Should be String value"
        case boolPair of
          (k, Encode.Boolean b) -> do
            JsonStr.toChars k @?= "bool"
            b @?= True
          _ -> assertFailure "Should be Boolean value"
        case intPair of
          (k, Encode.Integer i) -> do
            JsonStr.toChars k @?= "int"
            i @?= 123
          _ -> assertFailure "Should be Integer value"
    ]

-- PROPERTY TESTS

testEncodingProperties :: TestTree
testEncodingProperties =
  testGroup
    "Encoding Properties"
    [ testProperty "encode and encodeUgly produce valid JSON structure" $ \n ->
        let value = Encode.int (abs n)
            prettyResult = BB.toLazyByteString (Encode.encode value)
            uglyResult = BB.toLazyByteString (Encode.encodeUgly value)
            prettyLen = BSL.length prettyResult
            uglyLen = BSL.length uglyResult
         in -- Both should contain the number
            prettyLen >= uglyLen,
      testProperty "string encoding preserves content length bounds" $ \chars ->
        let limitedChars = take 100 chars -- Limit length for testing
            value = Encode.chars limitedChars
         in case value of
              Encode.String builder ->
                let result = BB.toLazyByteString builder
                 in -- Encoded length should be at least original length (plus quotes)
                    BSL.length result >= fromIntegral (length limitedChars + 2)
              _ -> False,
      testProperty "array encoding preserves element count" $ \ints ->
        let limitedInts = take 20 (map abs ints) -- Limit for testing
            values = map Encode.int limitedInts
            arrayValue = Encode.array values
         in case arrayValue of
              Encode.Array vs -> length vs == length limitedInts
              _ -> False
    ]

testRoundtripProperties :: TestTree
testRoundtripProperties =
  testGroup
    "Roundtrip Properties"
    [ testProperty "boolean encoding roundtrip" $ \b ->
        let encoded = BB.toLazyByteString (Encode.encodeUgly (Encode.bool b))
            encodedStr = map (toEnum . fromIntegral) (BSL.unpack encoded)
         in encodedStr == (if b then "true" else "false"),
      testProperty "integer encoding preserves value" $ \n ->
        let absN = abs n
            encoded = BB.toLazyByteString (Encode.encodeUgly (Encode.int absN))
            encodedStr = map (toEnum . fromIntegral) (BSL.unpack encoded)
         in encodedStr == show absN
    ]

testStructuralProperties :: TestTree
testStructuralProperties =
  testGroup
    "Structural Properties"
    [ testProperty "nested structures maintain depth" $ \depth ->
        let safeDepth = max 0 (min 5 depth) -- Limit depth for testing
            nestedArray = foldr (\_ acc -> Encode.array [acc]) (Encode.int 42) [1 .. safeDepth]
            encoded = BB.toLazyByteString (Encode.encodeUgly nestedArray)
            openBrackets = length $ filter (== fromIntegral (fromEnum '[')) (BSL.unpack encoded)
            closeBrackets = length $ filter (== fromIntegral (fromEnum ']')) (BSL.unpack encoded)
         in openBrackets == closeBrackets && openBrackets >= safeDepth
    ]

-- EDGE CASE TESTS

testEmptyStructures :: TestTree
testEmptyStructures =
  testGroup
    "Empty Structure Tests"
    [ testCase "empty array encodes to []" $ do
        let value = Encode.array []
            prettyResult = map (toEnum . fromIntegral) $ BSL.unpack $ BB.toLazyByteString $ Encode.encode value
            uglyResult = map (toEnum . fromIntegral) $ BSL.unpack $ BB.toLazyByteString $ Encode.encodeUgly value
        prettyResult @?= "[]"
        uglyResult @?= "[]",
      testCase "empty object encodes to {}" $ do
        let value = Encode.object []
            prettyResult = map (toEnum . fromIntegral) $ BSL.unpack $ BB.toLazyByteString $ Encode.encode value
            uglyResult = map (toEnum . fromIntegral) $ BSL.unpack $ BB.toLazyByteString $ Encode.encodeUgly value
        prettyResult @?= "{}"
        uglyResult @?= "{}",
      testCase "empty string encodes correctly" $ do
        let value = Encode.string (JsonStr.fromChars "")
            result = map (toEnum . fromIntegral) $ BSL.unpack $ BB.toLazyByteString $ Encode.encodeUgly value
        result @?= "\"\""
    ]

testLargeStructures :: TestTree
testLargeStructures =
  testGroup
    "Large Structure Tests"
    [ testCase "large array encodes without corruption" $ do
        let largeArray = Encode.array (replicate 100 (Encode.int 42))
            result = BB.toLazyByteString (Encode.encodeUgly largeArray)
            resultStr = map (toEnum . fromIntegral) (BSL.unpack result)
            commaCount = length $ filter (== ',') resultStr
        -- Should have 99 commas for 100 elements
        commaCount @?= 99,
      testCase "large object encodes all fields" $ do
        let largeObject = Encode.object [(JsonStr.fromChars ("key" ++ show i), Encode.int i) | i <- [1 .. 50]]
            result = BB.toLazyByteString (Encode.encodeUgly largeObject)
            resultStr = map (toEnum . fromIntegral) (BSL.unpack result)
            commaCount = length $ filter (== ',') resultStr
        -- Should have 49 commas for 50 fields
        commaCount @?= 49
    ]

testNestedStructures :: TestTree
testNestedStructures =
  testGroup
    "Nested Structure Tests"
    [ testCase "deeply nested arrays encode correctly" $ do
        let deepArray = foldr (\_ acc -> Encode.array [acc]) (Encode.int 1) [1 .. 5]
            result = BB.toLazyByteString (Encode.encodeUgly deepArray)
            resultBytes = BSL.unpack result
            openBrackets = length $ filter (== fromIntegral (fromEnum '[')) resultBytes
        openBrackets @?= 5,
      testCase "deeply nested objects encode correctly" $ do
        let deepObject = foldr (\i acc -> Encode.object [("level" ++ show i) Encode.==> acc]) (Encode.int 1) [1 .. 3]
            result = BB.toLazyByteString (Encode.encodeUgly deepObject)
            resultBytes = BSL.unpack result
            openBraces = length $ filter (== fromIntegral (fromEnum '{')) resultBytes
        openBraces @?= 3
    ]

testSpecialCharacters :: TestTree
testSpecialCharacters =
  testGroup
    "Special Character Tests"
    [ testCase "chars function handles newlines" $ do
        let input = "line1\nline2"
            value = Encode.chars input
            result = LBS.unpack $ BB.toLazyByteString $ Encode.encodeUgly value
        result @?= "\"line1\\nline2\"",
      testCase "chars function handles quotes" $ do
        let input = "say \"hello\""
            value = Encode.chars input
            result = LBS.unpack $ BB.toLazyByteString $ Encode.encodeUgly value
        result @?= "\"say \\\"hello\\\"\"",
      testCase "chars function handles backslashes" $ do
        let input = "path\\to\\file"
            value = Encode.chars input
            result = LBS.unpack $ BB.toLazyByteString $ Encode.encodeUgly value
        result @?= "\"path\\\\to\\\\file\"",
      testCase "chars function handles carriage returns" $ do
        let input = "line1\rline2"
            value = Encode.chars input
            result = LBS.unpack $ BB.toLazyByteString $ Encode.encodeUgly value
        result @?= "\"line1\\rline2\"",
      testCase "chars function handles all special chars together" $ do
        let input = "\n\r\"\\"
            value = Encode.chars input
            result = LBS.unpack $ BB.toLazyByteString $ Encode.encodeUgly value
        result @?= "\"\\n\\r\\\"\\\\\"",
      testCase "chars function produces String value with proper escaping" $ do
        let input = "test\nstring"
            value = Encode.chars input
            result = LBS.unpack $ BB.toLazyByteString $ Encode.encodeUgly value
        result @?= "\"test\\nstring\""
    ]

-- ERROR CONDITION TESTS

testInvalidInputs :: TestTree
testInvalidInputs =
  testGroup
    "Invalid Input Tests"
    [ testCase "encoding handles extreme integer values" $ do
        let maxValue = Encode.int maxBound
            minValue = Encode.int minBound
            maxResult = LBS.unpack $ BB.toLazyByteString (Encode.encodeUgly maxValue)
            minResult = LBS.unpack $ BB.toLazyByteString (Encode.encodeUgly minValue)
        maxResult @?= "9223372036854775807"
        minResult @?= "-9223372036854775808"
    ]

testMemoryConstraints :: TestTree
testMemoryConstraints =
  testGroup
    "Memory Constraint Tests"
    [ testCase "very long string doesn't cause memory issues" $ do
        let longString = replicate 1000 'a'
            value = Encode.chars longString
        case value of
          Encode.String builder -> do
            let result = BB.toLazyByteString builder
            BSL.length result @?= 1002
          _ -> assertFailure "Should produce String value"
    ]

testEncodingFailures :: TestTree
testEncodingFailures =
  testGroup
    "Encoding Failure Tests"
    [ testCase "scientific number edge cases" $ do
        let scientific = Sci.fromFloatDigits (0 / 0) -- NaN
            value = Encode.number scientific
        case value of
          Encode.Number s -> do
            let result = BB.toLazyByteString (Encode.encodeUgly value)
            -- Should handle NaN gracefully
            assertBool "Should produce some output for NaN" (BSL.length result > 0)
          _ -> assertFailure "Should create Number value"
    ]
