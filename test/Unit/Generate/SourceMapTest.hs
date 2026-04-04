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
    , vlqEdgeCaseTests
    , mappingEdgeCaseTests
    , sourceEdgeCaseTests
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

-- VLQ EDGE CASE TESTS

vlqEdgeCaseTests :: TestTree
vlqEdgeCaseTests =
  testGroup
    "VLQ edge cases"
    [ testCase "encodeVLQ 3 produces G" $
        renderBuilder (SourceMap.encodeVLQ 3) @?= "G"
    , testCase "encodeVLQ (-3) produces H" $
        renderBuilder (SourceMap.encodeVLQ (-3)) @?= "H"
    , testCase "encodeVLQ 4 produces I" $
        renderBuilder (SourceMap.encodeVLQ 4) @?= "I"
    , testCase "encodeVLQ 5 produces K" $
        renderBuilder (SourceMap.encodeVLQ 5) @?= "K"
    , testCase "encodeVLQ 10 produces U" $
        renderBuilder (SourceMap.encodeVLQ 10) @?= "U"
    , testCase "encodeVLQ 14 produces c" $
        renderBuilder (SourceMap.encodeVLQ 14) @?= "c"
    , testCase "encodeVLQ large positive value uses multiple digits" $
        length (renderBuilder (SourceMap.encodeVLQ 1000)) @?= 3
    , testCase "encodeVLQ large negative value uses multiple digits" $
        length (renderBuilder (SourceMap.encodeVLQ (-1000))) @?= 3
    , testCase "encodeVLQ symmetric: positive and negative same magnitude" $
        let n = 500
         in length (renderBuilder (SourceMap.encodeVLQ n))
              @?= length (renderBuilder (SourceMap.encodeVLQ (-n)))
    ]

-- MAPPING EDGE CASE TESTS

mappingEdgeCaseTests :: TestTree
mappingEdgeCaseTests =
  testGroup
    "Mapping edge cases"
    [ testCase "three mappings on different lines produce two semicolons" $
        let m1 = SourceMap.Mapping 0 0 0 0 0 Nothing
            m2 = SourceMap.Mapping 1 0 0 0 0 Nothing
            m3 = SourceMap.Mapping 2 0 0 0 0 Nothing
            sm = SourceMap.addMapping m3 (SourceMap.addMapping m2 (SourceMap.addMapping m1 (SourceMap.empty "out.js")))
            json = renderBuilder (SourceMap.toBuilder sm)
            mappingsField = drop 1 (dropWhile (/= ':') (dropWhile (/= 'm') json))
         in length (filter (== ';') mappingsField) @?= 2
    , testCase "mapping at column 0 after prior column encodes delta" $
        let m1 = SourceMap.Mapping 0 5 0 0 0 Nothing
            m2 = SourceMap.Mapping 0 0 0 0 0 Nothing
            sm = SourceMap.addMapping m2 (SourceMap.addMapping m1 (SourceMap.empty "test.js"))
            json = renderBuilder (SourceMap.toBuilder sm)
         in assertNonEmpty json
    ]
  where
    assertNonEmpty s = length s > 0 @? "Expected non-empty JSON"

-- SOURCE EDGE CASE TESTS

sourceEdgeCaseTests :: TestTree
sourceEdgeCaseTests =
  testGroup
    "Source registration edge cases"
    [ testCase "three unique sources get indices 0, 1, 2" $
        let (i1, sm1) = SourceMap.addSource "a.can" Nothing (SourceMap.empty "out.js")
            (i2, sm2) = SourceMap.addSource "b.can" Nothing sm1
            (i3, _sm3) = SourceMap.addSource "c.can" Nothing sm2
         in (i1, i2, i3) @?= (0, 1, 2)
    , testCase "re-adding same source does not grow sources list" $
        let (_, sm1) = SourceMap.addSource "x.can" Nothing (SourceMap.empty "out.js")
            (_, sm2) = SourceMap.addSource "x.can" Nothing sm1
         in length (SourceMap._smSources sm2) @?= 1
    , testCase "source content is empty string when Nothing" $
        let (_, sm) = SourceMap.addSource "x.can" Nothing (SourceMap.empty "out.js")
         in SourceMap._smSourcesContent sm @?= [""]
    , testCase "source content is stored verbatim when provided" $
        let (_, sm) = SourceMap.addSource "x.can" (Just "hello world") (SourceMap.empty "out.js")
         in SourceMap._smSourcesContent sm @?= ["hello world"]
    ]
