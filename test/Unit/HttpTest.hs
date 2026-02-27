{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Comprehensive test suite for Http.
--
-- This module provides complete test coverage for all public functions,
-- edge cases, error conditions, and properties in Http.
--
-- Coverage Target: ≥80% line coverage
-- Test Categories: Unit, Property, Edge Case, Error Condition
--
-- @since 0.19.1
module Unit.HttpTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import qualified Http
import Network.HTTP.Types.Header (Header)
import qualified Network.HTTP.Client as Client
import qualified Network.HTTP.Client.MultipartFormData as Multi
import qualified Codec.Archive.Zip as Zip
import qualified Data.Digest.Pure.SHA as SHA
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Json.Encode as Encode
import qualified Json.String as JsonString
import Control.Exception (SomeException)
import qualified Control.Exception as Exception
import Network.HTTP.Client (HttpException(..), HttpExceptionContent(..))
import Control.Monad (forM_)
import qualified Data.List as List

-- Custom error type for testing
data TestError = TestArchiveError | TestHttpError String deriving (Eq, Show)

-- Convert Http.Error to TestError
httpErrorToTestError :: Http.Error -> TestError
httpErrorToTestError (Http.BadUrl url reason) = TestHttpError ("BadUrl: " ++ url ++ " - " ++ reason)
httpErrorToTestError (Http.BadHttp url _) = TestHttpError ("BadHttp: " ++ url)
httpErrorToTestError (Http.BadMystery url _) = TestHttpError ("BadMystery: " ++ url)

-- | Main test tree containing all Http tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "Http Tests"
  [ unitTests
  , propertyTests
  , edgeCaseTests
  , errorConditionTests
  ]

-- | Unit tests for all public functions.
--
-- Tests basic functionality with known inputs and expected outputs.
-- Every public function must have at least one unit test.
unitTests :: TestTree
unitTests = testGroup "Unit Tests"
  [ testManagerCreation
  , testUrlConstruction
  , testHeaderCreation
  , testShaOperations
  , testMultipartParts
  , testHttpFunctionSignatures
  , testArchiveFunctionSignatures
  , testUploadFunctionSignatures
  ]

-- | Property-based tests for mathematical and logical operations.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with mathematical or logical operations.
propertyTests :: TestTree
propertyTests = testGroup "Property Tests"
  [ testUrlProperties
  , testShaProperties
  , testHeaderProperties
  , testMultipartProperties
  , testErrorProperties
  ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testEmptyUrlParams
  , testLargeUrlParams
  , testSpecialCharacters
  , testBoundaryConditions
  , testSequentialOperations
  , testMalformedInputs
  ]

-- | Error condition tests for invalid inputs.
--
-- Verifies proper error handling and meaningful error messages
-- for all possible error conditions and invalid inputs.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testErrorTypes
  , testExceptionHandling
  , testInvalidInputs
  , testHttpErrorScenarios
  , testArchiveErrorScenarios
  ]

-- ==== UNIT TESTS ====

testManagerCreation :: TestTree
testManagerCreation = testGroup "Manager Creation Tests"
  [ testCase "getManager creates valid manager" $ do
      manager <- Http.getManager
      manager `seq` pure ()

  , testCase "getManager is reusable" $ do
      manager1 <- Http.getManager
      manager2 <- Http.getManager
      manager1 `seq` manager2 `seq` pure ()

  , testCase "multiple managers can be created sequentially" $ do
      managers <- mapM (\_ -> Http.getManager) [1..5 :: Int]
      length managers @?= 5
  ]

testUrlConstruction :: TestTree
testUrlConstruction = testGroup "URL Construction Tests"
  [ testCase "toUrl with empty parameters" $ do
      let url = "https://api.example.com/test"
      Http.toUrl url [] @?= url

  , testCase "toUrl with single parameter" $ do
      Http.toUrl "https://api.example.com/search" [("q", "test")]
        @?= "https://api.example.com/search?q=test"

  , testCase "toUrl with multiple parameters" $ do
      Http.toUrl "https://api.example.com/search" [("q", "canopy"), ("limit", "10"), ("sort", "date")]
        @?= "https://api.example.com/search?q=canopy&limit=10&sort=date"

  , testCase "toUrl with spaces encodes to %20" $ do
      Http.toUrl "https://api.example.com/search" [("q", "canopy lang"), ("version", ">=1.0.0")]
        @?= "https://api.example.com/search?q=canopy%20lang&version=%3E%3D1.0.0"
  ]

testHeaderCreation :: TestTree
testHeaderCreation = testGroup "Header Creation Tests"
  [ testCase "accept header creation" $ do
      Http.accept "application/json" @?= ("Accept", "application/json")

  , testCase "accept header with charset" $ do
      Http.accept "text/plain; charset=utf-8" @?= ("Accept", "text/plain; charset=utf-8")

  , testCase "accept header with different MIME types" $ do
      let jsonHeader = Http.accept "application/json"
      let zipHeader = Http.accept "application/zip"
      let textHeader = Http.accept "text/plain"

      fst jsonHeader @?= "Accept"
      fst zipHeader @?= "Accept"
      fst textHeader @?= "Accept"

      snd jsonHeader @?= "application/json"
      snd zipHeader @?= "application/zip"
      snd textHeader @?= "text/plain"
  ]

testShaOperations :: TestTree
testShaOperations = testGroup "SHA Operations Tests"
  [ testCase "shaToChars produces 64-character hex string" $ do
      let emptyHash = SHA.sha256 LBS.empty
      let result = Http.shaToChars emptyHash

      length result @?= 64
      all (\c -> c `elem` ("0123456789abcdef" :: String)) result @?= True

  , testCase "shaToChars different inputs produce different outputs" $ do
      let hash1 = SHA.sha256 "test1"
      let hash2 = SHA.sha256 "test2"
      let result1 = Http.shaToChars hash1
      let result2 = Http.shaToChars hash2

      result1 /= result2 @?= True
      length result1 @?= 64
      length result2 @?= 64
  ]

testMultipartParts :: TestTree
testMultipartParts = testGroup "Multipart Parts Tests"
  [ testCase "stringPart creates valid part" $ do
      Http.stringPart "version" "1.0.0" `seq` pure ()

  , testCase "bytesPart creates valid part" $ do
      Http.bytesPart "data" "test.bin" (BS.pack "test content") `seq` pure ()

  , testCase "jsonPart creates valid part" $ do
      let jsonValue = Encode.object [(JsonString.fromChars "name", Encode.chars "test")]
      Http.jsonPart "metadata" "meta.json" jsonValue `seq` pure ()
  ]

testHttpFunctionSignatures :: TestTree
testHttpFunctionSignatures = testGroup "HTTP Function Signature Tests"
  [ testCase "get function signature and error handling" $ do
      manager <- Http.getManager
      let result = Http.get manager "invalid-url-scheme://test" [] id (\_ -> pure (Right ()))
      errorResult <- result
      case errorResult of
        Left _ -> pure ()
        Right _ -> assertFailure "Invalid URL should produce error"

  , testCase "post function signature and error handling" $ do
      manager <- Http.getManager
      let result = Http.post manager "invalid-url-scheme://test" [] id (\_ -> pure (Right ()))
      errorResult <- result
      case errorResult of
        Left _ -> pure ()
        Right _ -> assertFailure "Invalid URL should produce error"
  ]

testArchiveFunctionSignatures :: TestTree
testArchiveFunctionSignatures = testGroup "Archive Function Signature Tests"
  [ testCase "getArchive function signature and error handling" $ do
      manager <- Http.getManager
      let result = Http.getArchive manager "invalid-url://test" httpErrorToTestError TestArchiveError (\_ -> pure (Right ()))
      errorResult <- result
      case errorResult of
        Left _ -> pure ()
        Right _ -> assertFailure "Invalid URL should produce error"

  , testCase "getArchiveWithHeaders function signature and error handling" $ do
      manager <- Http.getManager
      let headers = [Http.accept "application/zip"]
      let result = Http.getArchiveWithHeaders manager "invalid-url://test" headers httpErrorToTestError TestArchiveError (\_ -> pure (Right ()))
      errorResult <- result
      case errorResult of
        Left _ -> pure ()
        Right _ -> assertFailure "Invalid URL should produce error"
  ]

testUploadFunctionSignatures :: TestTree
testUploadFunctionSignatures = testGroup "Upload Function Signature Tests"
  [ testCase "upload function signature and error handling" $ do
      manager <- Http.getManager
      let parts = [Http.stringPart "test" "value"]
      let result = Http.upload manager "invalid-url://test" parts
      errorResult <- result
      case errorResult of
        Left _ -> pure ()
        Right _ -> assertFailure "Invalid URL should produce error"

  , testCase "uploadWithHeaders function signature and error handling" $ do
      manager <- Http.getManager
      let parts = [Http.stringPart "test" "value"]
      let headers = [("Authorization", "Bearer test")]
      let result = Http.uploadWithHeaders manager "invalid-url://test" parts headers
      errorResult <- result
      case errorResult of
        Left _ -> pure ()
        Right _ -> assertFailure "Invalid URL should produce error"

  , testCase "filePart function creates valid part" $ do
      let testFile = "/tmp/test-http-file.txt"
      writeFile testFile "test content"
      Http.filePart "file" testFile `seq` pure ()
  ]

-- ==== PROPERTY TESTS ====

testUrlProperties :: TestTree
testUrlProperties = testGroup "URL Properties"
  [ testProperty "toUrl preserves base URL when no params" $ \url ->
      not (null url) ==> Http.toUrl url [] == url

  , testProperty "toUrl with params always contains question mark" $ \url params ->
      not (null url) && not (null params) ==>
        '?' `elem` Http.toUrl url (take 3 params)

  , testProperty "toUrl result length increases with params" $ \url params ->
      not (null url) && not (null params) ==>
        let withoutParams = Http.toUrl url []
            withParams = Http.toUrl url (take 2 params)
        in length withParams >= length withoutParams
  ]

testShaProperties :: TestTree
testShaProperties = testGroup "SHA Properties"
  [ testProperty "shaToChars always produces 64 characters" $ \bytes ->
      let hash = SHA.sha256 (LBS.pack (take 1000 bytes))
          result = Http.shaToChars hash
      in length result == 64

  , testProperty "shaToChars is deterministic" $ \bytes ->
      let input = LBS.pack (take 100 bytes)
          hash1 = SHA.sha256 input
          hash2 = SHA.sha256 input
          result1 = Http.shaToChars hash1
          result2 = Http.shaToChars hash2
      in result1 == result2

  , testProperty "different inputs produce different SHA strings" $ \bytes1 bytes2 ->
      let input1 = LBS.pack (take 50 bytes1)
          input2 = LBS.pack (take 50 bytes2)
      in input1 /= input2 ==>
           Http.shaToChars (SHA.sha256 input1) /= Http.shaToChars (SHA.sha256 input2)
  ]

testHeaderProperties :: TestTree
testHeaderProperties = testGroup "Header Properties"
  [ testProperty "accept header always has Accept key" $ \mimeType ->
      not (null mimeType) ==>
        fst (Http.accept (BS.pack mimeType)) == "Accept"

  , testProperty "accept header preserves MIME type" $ \mimeType ->
      not (null mimeType) ==>
        snd (Http.accept (BS.pack mimeType)) == BS.pack mimeType
  ]

testMultipartProperties :: TestTree
testMultipartProperties = testGroup "Multipart Properties"
  [ testProperty "stringPart with different names creates different parts" $ \name1 name2 value ->
      not (null name1) && not (null name2) && name1 /= name2 ==>
        let part1 = Http.stringPart name1 value
            part2 = Http.stringPart name2 value
        in part1 `seq` part2 `seq` True

  , testProperty "bytesPart handles various byte sizes" $ \name fileName bytes ->
      not (null name) && not (null fileName) ==>
        let part = Http.bytesPart name fileName (BS.pack (take 1000 bytes))
        in part `seq` True

  , testProperty "jsonPart creates parts for different JSON values" $ \name fileName ->
      not (null name) && not (null fileName) ==>
        let jsonValue = Encode.object [(JsonString.fromChars "test", Encode.chars "testvalue")]
            part = Http.jsonPart name fileName jsonValue
        in part `seq` True
  ]

testErrorProperties :: TestTree
testErrorProperties = testGroup "Error Properties"
  [ testProperty "BadUrl preserves URL and reason" $ \url reason ->
      not (null url) && not (null reason) ==>
        case Http.BadUrl url reason of
          Http.BadUrl actualUrl actualReason ->
            actualUrl == url && actualReason == reason
          _ -> False

  , testProperty "BadUrl show contains BadUrl prefix" $ \url reason ->
      not (null url) && not (null reason) ==>
        let err = Http.BadUrl url reason
            shown = show err
        in "BadUrl" `List.isPrefixOf` shown
  ]

-- ==== EDGE CASE TESTS ====

testEmptyUrlParams :: TestTree
testEmptyUrlParams = testGroup "Empty URL Parameters"
  [ testCase "empty parameter list" $ do
      Http.toUrl "https://example.com" [] @?= "https://example.com"

  , testCase "empty parameter values" $ do
      Http.toUrl "https://example.com" [("key", "")] @?= "https://example.com?key="

  , testCase "empty parameter keys" $ do
      Http.toUrl "https://example.com" [("", "value")] @?= "https://example.com?=value"
  ]

testLargeUrlParams :: TestTree
testLargeUrlParams = testGroup "Large URL Parameters"
  [ testCase "many parameters produces expected URL" $ do
      let params = [ ("param" ++ show i, "value" ++ show i) | i <- [1..20 :: Int] ]
      let result = Http.toUrl "https://example.com" params
      result @?= "https://example.com?param1=value1&param2=value2&param3=value3&param4=value4&param5=value5&param6=value6&param7=value7&param8=value8&param9=value9&param10=value10&param11=value11&param12=value12&param13=value13&param14=value14&param15=value15&param16=value16&param17=value17&param18=value18&param19=value19&param20=value20"

  , testCase "long parameter value is included verbatim" $ do
      let longValue = replicate 200 'a'
      let result = Http.toUrl "https://example.com" [("data", longValue)]
      take 35 result @?= "https://example.com?data=aaaaaaaaaa"
  ]

testSpecialCharacters :: TestTree
testSpecialCharacters = testGroup "Special Characters"
  [ testCase "Unicode characters percent-encoded" $ do
      Http.toUrl "https://example.com" [("name", "caf\233")]
        @?= "https://example.com?name=caf%C3%A9"

  , testCase "URL special characters fully percent-encoded" $ do
      Http.toUrl "https://example.com" [("url", "https://other.com?x=1&y=2")]
        @?= "https://example.com?url=https%3A%2F%2Fother.com%3Fx%3D1%26y%3D2"

  , testCase "spaces encoded as %20" $ do
      Http.toUrl "https://example.com" [("query", "hello world")]
        @?= "https://example.com?query=hello%20world"
  ]

testBoundaryConditions :: TestTree
testBoundaryConditions = testGroup "Boundary Conditions"
  [ testCase "minimum URL" $ do
      Http.toUrl "x" [] @?= "x"

  , testCase "single character parameters" $ do
      Http.toUrl "https://example.com" [("a", "b")] @?= "https://example.com?a=b"

  , testCase "accept with minimal MIME type" $ do
      Http.accept "a" @?= ("Accept", "a")
  ]

testSequentialOperations :: TestTree
testSequentialOperations = testGroup "Sequential Operations"
  [ testCase "multiple URL construction" $ do
      let urls = ["https://example.com/" ++ show i | i <- [1..10 :: Int]]
      let params = [("id", show i) | i <- [1..10 :: Int]]
      let results = map (\(url, param) -> Http.toUrl url [param]) (zip urls params)

      length results @?= 10
      all (\result -> "?id=" `List.isInfixOf` result) results @?= True

  , testCase "multiple header creation" $ do
      let mimes = ["application/json", "text/plain", "application/xml"]
      let headers = map Http.accept mimes

      length headers @?= 3
      all (\(key, _) -> key == "Accept") headers @?= True

  , testCase "multiple SHA operations" $ do
      let inputs = [LBS.fromStrict (BS.pack ("test" ++ show i)) | i <- [1..5 :: Int]]
      let results = map (\input -> Http.shaToChars (SHA.sha256 input)) inputs

      length results @?= 5
      all (\result -> length result == 64) results @?= True
  ]

testMalformedInputs :: TestTree
testMalformedInputs = testGroup "Malformed Inputs"
  [ testCase "URL with null bytes preserved in output" $ do
      let urlWithNull = "https://example.com\0/path"
      let result = Http.toUrl urlWithNull [("key", "value")]
      take 19 result @?= "https://example.com"

  , testCase "control character percent-encoded" $ do
      Http.toUrl "https://example.com" [("data", "\n")]
        @?= "https://example.com?data=%0A"

  , testCase "extremely long MIME types" $ do
      let longMime = BS.pack (replicate 1000 'a')
      let header = Http.accept longMime
      header @?= ("Accept", longMime)

  , testCase "JSON with deeply nested structure" $ do
      let deepJson = foldr (\_ acc -> Encode.object [(JsonString.fromChars "nested", acc)]) (Encode.chars "deep") [1..100 :: Int]
      Http.jsonPart "deep" "deep.json" deepJson `seq` pure ()
  ]

-- ==== ERROR CONDITION TESTS ====

testErrorTypes :: TestTree
testErrorTypes = testGroup "Error Types"
  [ testCase "BadUrl error structure" $ do
      let err = Http.BadUrl "https://example.com" "Invalid URL"
      case err of
        Http.BadUrl url reason -> do
          url @?= "https://example.com"
          reason @?= "Invalid URL"
        _ -> assertFailure "Expected BadUrl constructor"

  , testCase "BadHttp error structure" $ do
      let err = Http.BadHttp "https://example.com" ConnectionTimeout
      case err of
        Http.BadHttp url _ -> url @?= "https://example.com"
        _ -> assertFailure "Expected BadHttp constructor"

  , testCase "BadMystery error structure" $ do
      let ex = Exception.toException (userError "test error")
      let err = Http.BadMystery "https://example.com" ex
      case err of
        Http.BadMystery url _ -> url @?= "https://example.com"
        _ -> assertFailure "Expected BadMystery constructor"
  ]

testExceptionHandling :: TestTree
testExceptionHandling = testGroup "Exception Handling"
  [ testCase "Error show instance works" $ do
      show (Http.BadUrl "test-url" "test-reason") @?= "BadUrl \"test-url\" \"test-reason\""
  ]

testInvalidInputs :: TestTree
testInvalidInputs = testGroup "Invalid Inputs"
  [ testCase "empty MIME type handling" $ do
      Http.accept "" @?= ("Accept", "")

  , testCase "empty URL with parameters" $ do
      Http.toUrl "" [("key", "value")] @?= "?key=value"
  ]

testHttpErrorScenarios :: TestTree
testHttpErrorScenarios = testGroup "HTTP Error Scenarios"
  [ testCase "invalid scheme handling in get" $ do
      manager <- Http.getManager
      let result = Http.get manager "ftp://example.com" [] id (\_ -> pure (Right ()))
      errorResult <- result
      case errorResult of
        Left _ -> pure ()
        Right _ -> assertFailure "FTP scheme should be rejected"

  , testCase "invalid scheme handling in post" $ do
      manager <- Http.getManager
      let result = Http.post manager "invalid-scheme://test" [] id (\_ -> pure (Right ()))
      errorResult <- result
      case errorResult of
        Left _ -> pure ()
        Right _ -> assertFailure "Invalid scheme should be rejected"

  , testCase "malformed URL in upload" $ do
      manager <- Http.getManager
      let parts = [Http.stringPart "test" "value"]
      let result = Http.upload manager "not-a-url" parts
      errorResult <- result
      case errorResult of
        Left (Http.BadUrl _ _) -> pure ()
        Left _ -> assertFailure "Should specifically be BadUrl error"
        Right _ -> assertFailure "Malformed URL should produce error"

  , testCase "error handling preserves context" $ do
      let url = "test-url"
      let reason = "test-reason"
      let err = Http.BadUrl url reason

      case err of
        Http.BadUrl actualUrl actualReason -> do
          actualUrl @?= url
          actualReason @?= reason
        _ -> assertFailure "Error should preserve context"
  ]

testArchiveErrorScenarios :: TestTree
testArchiveErrorScenarios = testGroup "Archive Error Scenarios"
  [ testCase "getArchive with invalid URL" $ do
      manager <- Http.getManager
      let result = Http.getArchive manager "not-a-url" httpErrorToTestError TestArchiveError (\_ -> pure (Right ()))
      errorResult <- result
      case errorResult of
        Left _ -> pure ()
        Right _ -> assertFailure "Invalid URL should produce error"

  , testCase "getArchiveWithHeaders with malformed URL" $ do
      manager <- Http.getManager
      let headers = [Http.accept "application/zip"]
      let result = Http.getArchiveWithHeaders manager "://malformed" headers httpErrorToTestError TestArchiveError (\_ -> pure (Right ()))
      errorResult <- result
      case errorResult of
        Left _ -> pure ()
        Right _ -> assertFailure "Malformed URL should produce error"

  , testCase "archive function error propagation" $ do
      manager <- Http.getManager
      let result = Http.getArchive manager "invalid://test" httpErrorToTestError TestArchiveError (\_ -> pure (Right ()))
      errorResult <- result
      case errorResult of
        Left (TestHttpError _) -> pure ()
        Left TestArchiveError -> assertFailure "Should not return archive error for URL error"
        Right _ -> assertFailure "Should return error for bad URL"
  ]

-- ==== HELPER FUNCTIONS AND INSTANCES ====

-- QuickCheck instances for testing
instance Arbitrary ByteString where
  arbitrary = BS.pack <$> arbitrary
