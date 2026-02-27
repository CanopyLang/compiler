{-# LANGUAGE OverloadedStrings #-}

-- | Tests for Source Map V3 generation.
--
-- Validates VLQ encoding, mapping serialization, source registration,
-- and the complete JSON output format per the Source Map V3 specification.
--
-- @since 0.19.2
module Unit.Generate.SourceMapTest (tests) where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Generate.JavaScript.SourceMap as SourceMap
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.SourceMap"
    [ vlqTests
    , mappingTests
    , sourceRegistrationTests
    , jsonSerializationTests
    ]

-- | Helper to render a Builder to a String for assertions.
renderBuilder :: BB.Builder -> String
renderBuilder = LChar8.unpack . BB.toLazyByteString

-- VLQ ENCODING TESTS

vlqTests :: TestTree
vlqTests =
  testGroup
    "VLQ Encoding"
    [ testCase "encodeVLQ 0 produces A" $
        renderBuilder (SourceMap.encodeVLQ 0) @?= "A"
    , testCase "encodeVLQ 1 produces C" $
        renderBuilder (SourceMap.encodeVLQ 1) @?= "C"
    , testCase "encodeVLQ (-1) produces D" $
        renderBuilder (SourceMap.encodeVLQ (-1)) @?= "D"
    , testCase "encodeVLQ 2 produces E" $
        renderBuilder (SourceMap.encodeVLQ 2) @?= "E"
    , testCase "encodeVLQ (-2) produces F" $
        renderBuilder (SourceMap.encodeVLQ (-2)) @?= "F"
    , testCase "encodeVLQ 15 produces e (max single digit)" $
        renderBuilder (SourceMap.encodeVLQ 15) @?= "e"
    , testCase "encodeVLQ 16 produces gB (two digits)" $
        renderBuilder (SourceMap.encodeVLQ 16) @?= "gB"
    , testCase "encodeVLQ (-16) produces hB" $
        renderBuilder (SourceMap.encodeVLQ (-16)) @?= "hB"
    , testCase "encodeVLQ 100 produces oG" $
        renderBuilder (SourceMap.encodeVLQ 100) @?= "oG"
    , testCase "encodeVLQ 0 is single character" $
        length (renderBuilder (SourceMap.encodeVLQ 0)) @?= 1
    , testCase "encodeVLQ small values are single character" $
        all (\n -> length (renderBuilder (SourceMap.encodeVLQ n)) == 1) [-15 .. 15] @?= True
    , testCase "encodeVLQ 16 requires two characters" $
        length (renderBuilder (SourceMap.encodeVLQ 16)) @?= 2
    , testCase "encodeVLQ (-16) requires two characters" $
        length (renderBuilder (SourceMap.encodeVLQ (-16))) @?= 2
    , testCase "encodeVLQ uses only Base64 characters" $
        let result = renderBuilder (SourceMap.encodeVLQ 12345)
         in all (`elem` base64Chars) result @?= True
    , testCase "encodeVLQ large value 1000 produces w+B" $
        renderBuilder (SourceMap.encodeVLQ 1000) @?= "w+B"
    , testCase "positive and negative of same magnitude have equal length" $ do
        let pos = renderBuilder (SourceMap.encodeVLQ 5)
            neg = renderBuilder (SourceMap.encodeVLQ (-5))
        length pos @?= length neg
    ]

base64Chars :: String
base64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- MAPPING ENCODING TESTS

mappingTests :: TestTree
mappingTests =
  testGroup
    "Mapping Encoding"
    [ testCase "empty source map produces empty mappings string" $
        let sm = SourceMap.empty "test.js"
            json = renderBuilder (SourceMap.toBuilder sm)
         in json @?= "{\"version\":3,\"file\":\"test.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"\"}"
    , testCase "single mapping on line 0 produces AAAA mappings" $
        let sm = SourceMap.addMapping (SourceMap.Mapping 0 0 0 0 0 Nothing) (SourceMap.empty "test.js")
            json = renderBuilder (SourceMap.toBuilder sm)
         in json @?= "{\"version\":3,\"file\":\"test.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"AAAA\"}"
    , testCase "mappings on different lines separated by semicolons" $
        let m1 = SourceMap.Mapping 0 0 0 0 0 Nothing
            m2 = SourceMap.Mapping 2 0 0 2 0 Nothing
            sm = SourceMap.addMapping m2 (SourceMap.addMapping m1 (SourceMap.empty "test.js"))
            json = renderBuilder (SourceMap.toBuilder sm)
         in json @?= "{\"version\":3,\"file\":\"test.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"AAAA;;AAEA\"}"
    , testCase "multiple mappings on same line separated by commas" $
        let m1 = SourceMap.Mapping 0 0 0 0 0 Nothing
            m2 = SourceMap.Mapping 0 10 0 0 5 Nothing
            sm = SourceMap.addMapping m2 (SourceMap.addMapping m1 (SourceMap.empty "test.js"))
            json = renderBuilder (SourceMap.toBuilder sm)
         in json @?= "{\"version\":3,\"file\":\"test.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"AAAA,UAAK\"}"
    , testCase "mapping with source column offset" $
        let m = SourceMap.Mapping 0 0 0 5 10 Nothing
            sm = SourceMap.addMapping m (SourceMap.empty "test.js")
            json = renderBuilder (SourceMap.toBuilder sm)
         in json @?= "{\"version\":3,\"file\":\"test.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"AAKU\"}"
    ]

-- SOURCE REGISTRATION TESTS

sourceRegistrationTests :: TestTree
sourceRegistrationTests =
  testGroup
    "Source Registration"
    [ testCase "addSource registers new source" $
        let (idx, sm) = SourceMap.addSource "src/Main.can" Nothing (SourceMap.empty "test.js")
         in do
              idx @?= 0
              SourceMap._smSources sm @?= ["src/Main.can"]
    , testCase "addSource returns existing index for duplicate" $
        let (_, sm1) = SourceMap.addSource "src/Main.can" Nothing (SourceMap.empty "test.js")
            (idx2, sm2) = SourceMap.addSource "src/Main.can" Nothing sm1
         in do
              idx2 @?= 0
              SourceMap._smSources sm2 @?= ["src/Main.can"]
    , testCase "addSource assigns sequential indices" $
        let (idx1, sm1) = SourceMap.addSource "src/Main.can" Nothing (SourceMap.empty "test.js")
            (idx2, sm2) = SourceMap.addSource "src/Utils.can" Nothing sm1
            (idx3, _sm3) = SourceMap.addSource "src/Data.can" Nothing sm2
         in do
              idx1 @?= 0
              idx2 @?= 1
              idx3 @?= 2
    , testCase "addSource stores content when provided" $
        let (_, sm) = SourceMap.addSource "src/Main.can" (Just "module Main") (SourceMap.empty "test.js")
         in SourceMap._smSourcesContent sm @?= ["module Main"]
    , testCase "addSource stores empty text when no content" $
        let (_, sm) = SourceMap.addSource "src/Main.can" Nothing (SourceMap.empty "test.js")
         in SourceMap._smSourcesContent sm @?= [""]
    ]

-- JSON SERIALIZATION TESTS

jsonSerializationTests :: TestTree
jsonSerializationTests =
  testGroup
    "JSON Serialization"
    [ testCase "version field is 3" $
        let json = renderBuilder (SourceMap.toBuilder (SourceMap.empty "test.js"))
         in json @?= "{\"version\":3,\"file\":\"test.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"\"}"
    , testCase "file field matches output filename" $
        let json = renderBuilder (SourceMap.toBuilder (SourceMap.empty "output.js"))
         in json @?= "{\"version\":3,\"file\":\"output.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"\"}"
    , testCase "sources field is array" $
        let (_, sm) = SourceMap.addSource "src/Main.can" Nothing (SourceMap.empty "test.js")
            json = renderBuilder (SourceMap.toBuilder sm)
         in json @?= "{\"version\":3,\"file\":\"test.js\",\"sources\":[\"src/Main.can\"],\"sourcesContent\":[\"\"],\"names\":[],\"mappings\":\"\"}"
    , testCase "empty sources produces empty array" $
        let json = renderBuilder (SourceMap.toBuilder (SourceMap.empty "test.js"))
         in json @?= "{\"version\":3,\"file\":\"test.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"\"}"
    , testCase "names field is empty array" $
        let json = renderBuilder (SourceMap.toBuilder (SourceMap.empty "test.js"))
         in json @?= "{\"version\":3,\"file\":\"test.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"\"}"
    , testCase "JSON output starts with { and ends with }" $
        let json = renderBuilder (SourceMap.toBuilder (SourceMap.empty "test.js"))
         in (head json, last json) @?= ('{', '}')
    , testCase "multiple sources in array" $
        let (_, sm1) = SourceMap.addSource "a.can" Nothing (SourceMap.empty "test.js")
            (_, sm2) = SourceMap.addSource "b.can" Nothing sm1
            json = renderBuilder (SourceMap.toBuilder sm2)
         in json @?= "{\"version\":3,\"file\":\"test.js\",\"sources\":[\"a.can\",\"b.can\"],\"sourcesContent\":[\"\",\"\"],\"names\":[],\"mappings\":\"\"}"
    , testCase "special characters in file path are included verbatim" $
        let json = renderBuilder (SourceMap.toBuilder (SourceMap.empty "path/to/file\"special.js"))
         in json @?= "{\"version\":3,\"file\":\"path/to/file\\\"special.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"\"}"
    , testCase "sourcesContent matches sources" $
        let (_, sm) = SourceMap.addSource "src/Main.can" (Just "module Main exposing (..)") (SourceMap.empty "test.js")
            json = renderBuilder (SourceMap.toBuilder sm)
         in json @?= "{\"version\":3,\"file\":\"test.js\",\"sources\":[\"src/Main.can\"],\"sourcesContent\":[\"module Main exposing (..)\"],\"names\":[],\"mappings\":\"\"}"
    ]
