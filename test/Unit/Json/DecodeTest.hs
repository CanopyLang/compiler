module Unit.Json.DecodeTest (tests) where

import qualified Data.ByteString as BS
import qualified Json.Decode as D
import qualified Json.String as JsonStr
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Json.Decode Tests"
    [ testBasicDecoders,
      testStringDecoder,
      testNumberDecoders,
      testBoolDecoder,
      testFailures
    ]

testBasicDecoders :: TestTree
testBasicDecoders =
  testGroup
    "basic decoder tests"
    [ testCase "decode string" $ do
        let json = "\"hello\""
            expected = JsonStr.fromChars "hello"
        case D.fromByteString D.string (BS.pack $ fmap (fromIntegral . fromEnum) json) of
          Right result -> result @?= expected
          Left _ -> assertFailure "String decoding should succeed",
      testCase "decode empty string" $ do
        let json = "\"\""
            expected = JsonStr.fromChars ""
        case D.fromByteString D.string (BS.pack $ fmap (fromIntegral . fromEnum) json) of
          Right result -> result @?= expected
          Left _ -> assertFailure "Empty string decoding should succeed"
    ]

testStringDecoder :: TestTree
testStringDecoder =
  testGroup
    "string decoder tests"
    [ testCase "simple string" $ do
        let json = "\"test\""
            expected = JsonStr.fromChars "test"
        case D.fromByteString D.string (BS.pack $ fmap (fromIntegral . fromEnum) json) of
          Right result -> result @?= expected
          Left _ -> assertFailure "Simple string should decode"
    ]

testNumberDecoders :: TestTree
testNumberDecoders =
  testGroup
    "number decoder tests"
    [ testCase "decode int" $ do
        let json = "42"
        case D.fromByteString D.int (BS.pack $ fmap (fromIntegral . fromEnum) json) of
          Right result -> result @?= 42
          Left _ -> assertFailure "Integer decoding should succeed",
      testCase "decode negative int" $ do
        let json = "-42"
        case D.fromByteString D.int (BS.pack $ fmap (fromIntegral . fromEnum) json) of
          Right _ -> assertFailure "Negative integer decoding should fail"
          Left _ -> return () -- Expected failure
    ]

testBoolDecoder :: TestTree
testBoolDecoder =
  testGroup
    "bool decoder tests"
    [ testCase "decode true" $ do
        let json = "true"
        case D.fromByteString D.bool (BS.pack $ fmap (fromIntegral . fromEnum) json) of
          Right result -> result @?= True
          Left _ -> assertFailure "True decoding should succeed",
      testCase "decode false" $ do
        let json = "false"
        case D.fromByteString D.bool (BS.pack $ fmap (fromIntegral . fromEnum) json) of
          Right result -> result @?= False
          Left _ -> assertFailure "False decoding should succeed"
    ]

testFailures :: TestTree
testFailures =
  testGroup
    "decode failure tests"
    [ testCase "string decoder on number" $ do
        let json = "42"
        case D.fromByteString D.string (BS.pack $ fmap (fromIntegral . fromEnum) json) of
          Right _ -> assertFailure "String decoder should fail on number"
          Left _ -> return (), -- Expected failure
      testCase "int decoder on string" $ do
        let json = "\"hello\""
        case D.fromByteString D.int (BS.pack $ fmap (fromIntegral . fromEnum) json) of
          Right _ -> assertFailure "Int decoder should fail on string"
          Left _ -> return () -- Expected failure
    ]
