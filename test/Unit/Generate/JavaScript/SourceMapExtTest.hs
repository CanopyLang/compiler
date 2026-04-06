{-# LANGUAGE OverloadedStrings #-}

-- | Extended tests for Source Map V3 generation covering gaps not addressed
-- by the primary SourceMapTest module.
--
-- This module focuses on:
--
--   * Name index (5th VLQ segment field) encoding via @mNameIndex@
--   * Non-consecutive generated line gaps producing correct semicolons
--   * @addSource@ duplicate preservation and content immutability
--   * @addMapping@ accumulation ordering and serialization reversal
--   * VLQ encoding of very large values (0x7FFFFFFF, maxBound)
--   * Mappings starting on generated lines other than 0
--   * Combined source registration and mapping serialization
--   * Initial @empty@ state via lens accessors
--
-- @since 0.19.2
module Unit.Generate.JavaScript.SourceMapExtTest (tests) where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Generate.JavaScript.SourceMap as SourceMap
import Test.Tasty
import Test.Tasty.HUnit

-- | Render a Builder to a String for assertions.
renderBuilder :: BB.Builder -> String
renderBuilder = LChar8.unpack . BB.toLazyByteString

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.SourceMap (Extended)"
    [ nameIndexTests
    , nonConsecutiveLineTests
    , addSourceDuplicateTests
    , addMappingOrderTests
    , vlqLargeValueTests
    , mappingsOnHigherLinesTests
    , combinedSerializationTests
    , emptyStateTests
    ]

-- NAME INDEX (5th VLQ field) TESTS

-- | Tests for the optional name index field encoded as the 5th VLQ segment.
--
-- The Source Map V3 spec allows an optional 5th field in each segment
-- encoding the index into the @names@ array. These tests verify that
-- segments with @mNameIndex = Just n@ emit the correct extra VLQ group.
nameIndexTests :: TestTree
nameIndexTests =
  testGroup
    "Name index (5th segment field)"
    [ testCase "mapping with nameIndex=Just 0 appends A to segment" $
        let m = SourceMap.Mapping 0 0 0 0 0 (Just 0)
            sm = SourceMap.addMapping m (SourceMap.empty "out.js")
            json = renderBuilder (SourceMap.toBuilder sm)
         in json @?= "{\"version\":3,\"file\":\"out.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"AAAAA\"}"
    , testCase "mapping with nameIndex=Nothing produces 4-field segment AAAA" $
        let m = SourceMap.Mapping 0 0 0 0 0 Nothing
            sm = SourceMap.addMapping m (SourceMap.empty "out.js")
            json = renderBuilder (SourceMap.toBuilder sm)
         in json @?= "{\"version\":3,\"file\":\"out.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"AAAA\"}"
    , testCase "mapping with nameIndex=Just 1 encodes delta from 0" $
        let m = SourceMap.Mapping 0 0 0 0 0 (Just 1)
            sm = SourceMap.addMapping m (SourceMap.empty "out.js")
            json = renderBuilder (SourceMap.toBuilder sm)
         in json @?= "{\"version\":3,\"file\":\"out.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"AAAAC\"}"
    , testCase "second mapping with same nameIndex encodes zero delta" $
        let m1 = SourceMap.Mapping 0 0 0 0 0 (Just 0)
            m2 = SourceMap.Mapping 0 4 0 0 4 (Just 0)
            sm = SourceMap.addMapping m2 (SourceMap.addMapping m1 (SourceMap.empty "out.js"))
            json = renderBuilder (SourceMap.toBuilder sm)
         in json @?= "{\"version\":3,\"file\":\"out.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"AAAAA,IAAIA\"}"
    , testCase "nameIndex increases: second segment encodes positive delta" $
        let m1 = SourceMap.Mapping 0 0 0 0 0 (Just 0)
            m2 = SourceMap.Mapping 0 4 0 0 4 (Just 2)
            sm = SourceMap.addMapping m2 (SourceMap.addMapping m1 (SourceMap.empty "out.js"))
            json = renderBuilder (SourceMap.toBuilder sm)
         in json @?= "{\"version\":3,\"file\":\"out.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"AAAAA,IAAIE\"}"
    , testCase "switching from Just to Nothing preserves prior nameIndex state" $
        let m1 = SourceMap.Mapping 0 0 0 0 0 (Just 2)
            m2 = SourceMap.Mapping 0 4 0 0 4 Nothing
            sm = SourceMap.addMapping m2 (SourceMap.addMapping m1 (SourceMap.empty "out.js"))
            json = renderBuilder (SourceMap.toBuilder sm)
         in json @?= "{\"version\":3,\"file\":\"out.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"AAAAE,IAAI\"}"
    ]

-- NON-CONSECUTIVE LINE TESTS

-- | Tests for non-consecutive generated line numbers.
--
-- When mappings jump over generated lines (e.g., line 0 then line 3),
-- the @mappings@ string must contain the correct number of semicolons
-- to represent the empty intermediate lines.
nonConsecutiveLineTests :: TestTree
nonConsecutiveLineTests =
  testGroup
    "Non-consecutive generated lines"
    [ testCase "line 0 to line 2 produces one empty semicolon between" $
        let m1 = SourceMap.Mapping 0 0 0 0 0 Nothing
            m2 = SourceMap.Mapping 2 0 0 2 0 Nothing
            sm = SourceMap.addMapping m2 (SourceMap.addMapping m1 (SourceMap.empty "out.js"))
            json = renderBuilder (SourceMap.toBuilder sm)
         in json @?= "{\"version\":3,\"file\":\"out.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"AAAA;;AAEA\"}"
    , testCase "line 0 to line 3 produces two empty semicolons between" $
        let m1 = SourceMap.Mapping 0 0 0 0 0 Nothing
            m2 = SourceMap.Mapping 3 0 0 3 0 Nothing
            sm = SourceMap.addMapping m2 (SourceMap.addMapping m1 (SourceMap.empty "out.js"))
            json = renderBuilder (SourceMap.toBuilder sm)
            mappingsValue = extractMappingsValue json
         in mappingsValue @?= "AAAA;;;AAGA"
    , testCase "gap of 4 lines produces 4 semicolons total (3 empty)" $
        let m1 = SourceMap.Mapping 0 0 0 0 0 Nothing
            m2 = SourceMap.Mapping 4 0 0 4 0 Nothing
            sm = SourceMap.addMapping m2 (SourceMap.addMapping m1 (SourceMap.empty "out.js"))
            json = renderBuilder (SourceMap.toBuilder sm)
            mappingsValue = extractMappingsValue json
            semicolonCount = length (filter (== ';') mappingsValue)
         in semicolonCount @?= 4
    , testCase "consecutive lines 0 and 1 produce exactly 1 semicolon" $
        let m1 = SourceMap.Mapping 0 0 0 0 0 Nothing
            m2 = SourceMap.Mapping 1 0 0 1 0 Nothing
            sm = SourceMap.addMapping m2 (SourceMap.addMapping m1 (SourceMap.empty "out.js"))
            json = renderBuilder (SourceMap.toBuilder sm)
            mappingsValue = extractMappingsValue json
            semicolonCount = length (filter (== ';') mappingsValue)
         in semicolonCount @?= 1
    , testCase "only line 0 has no semicolons" $
        let m = SourceMap.Mapping 0 0 0 0 0 Nothing
            sm = SourceMap.addMapping m (SourceMap.empty "out.js")
            mappingsValue = extractMappingsValue (renderBuilder (SourceMap.toBuilder sm))
         in length (filter (== ';') mappingsValue) @?= 0
    ]

-- | Extract the value of the @"mappings"@ field from a source map JSON string.
--
-- Parses the raw JSON produced by @toBuilder@ to isolate just the VLQ
-- mappings string. This avoids @isInfixOf@ and returns the exact content
-- between the @"mappings":"@ marker and the closing @"@.
--
-- The source map JSON always ends with @,"mappings":"VALUE"}@, so we
-- locate the marker and extract up to the next double-quote.
extractMappingsValue :: String -> String
extractMappingsValue json =
  takeWhile (/= '"') afterOpenQuote
  where
    marker = "\"mappings\":\""
    afterMarker = dropPrefix marker json
    afterOpenQuote = afterMarker

-- | Drop a fixed prefix from a string, searching forward until the prefix
-- is found. Returns the string immediately after the first occurrence.
dropPrefix :: String -> String -> String
dropPrefix _ [] = []
dropPrefix prefix full@(_ : rest)
  | take (length prefix) full == prefix = drop (length prefix) full
  | otherwise = dropPrefix prefix rest

-- ADDMAPPING ORDER TESTS

-- | Tests for @addMapping@ accumulation and serialization ordering.
--
-- Mappings are prepended (reversed) internally and then restored to
-- correct order during @toBuilder@. These tests confirm that the final
-- serialized order matches the logical left-to-right, top-to-bottom order.
addMappingOrderTests :: TestTree
addMappingOrderTests =
  testGroup
    "addMapping accumulation order"
    [ testCase "mappings added out of order are sorted by genLine in output" $
        let mLate = SourceMap.Mapping 1 0 0 1 0 Nothing
            mEarly = SourceMap.Mapping 0 0 0 0 0 Nothing
            smOutOfOrder = SourceMap.addMapping mEarly (SourceMap.addMapping mLate (SourceMap.empty "out.js"))
            smInOrder = SourceMap.addMapping mLate (SourceMap.addMapping mEarly (SourceMap.empty "out.js"))
         in renderBuilder (SourceMap.toBuilder smOutOfOrder)
              @?= renderBuilder (SourceMap.toBuilder smInOrder)
    , testCase "addMapping stores mappings in _smMappings field" $
        let m = SourceMap.Mapping 0 5 0 0 3 Nothing
            sm = SourceMap.addMapping m (SourceMap.empty "out.js")
         in SourceMap._smMappings sm @?= [m]
    , testCase "addMapping accumulates two mappings in _smMappings" $
        let m1 = SourceMap.Mapping 0 0 0 0 0 Nothing
            m2 = SourceMap.Mapping 1 0 0 1 0 Nothing
            sm = SourceMap.addMapping m2 (SourceMap.addMapping m1 (SourceMap.empty "out.js"))
         in length (SourceMap._smMappings sm) @?= 2
    ]

-- ADDMAPPING DUPLICATE-SOURCE TESTS

-- | Tests for @addSource@ duplicate handling and content preservation.
--
-- When a path is registered a second time the original content must not
-- be overwritten and the sources list must not grow.
addSourceDuplicateTests :: TestTree
addSourceDuplicateTests =
  testGroup
    "addSource duplicate handling"
    [ testCase "duplicate addSource with different content keeps first content" $
        let (_, sm1) = SourceMap.addSource "x.can" (Just "first content") (SourceMap.empty "out.js")
            (_, sm2) = SourceMap.addSource "x.can" (Just "second content") sm1
         in SourceMap._smSourcesContent sm2 @?= ["first content"]
    , testCase "duplicate addSource does not change sources list length" $
        let (_, sm1) = SourceMap.addSource "a.can" Nothing (SourceMap.empty "out.js")
            (_, sm1b) = SourceMap.addSource "b.can" Nothing sm1
            (_, sm2) = SourceMap.addSource "a.can" Nothing sm1b
         in length (SourceMap._smSources sm2) @?= 2
    , testCase "returned index for duplicate is stable across other additions" $
        let (i1, sm1) = SourceMap.addSource "a.can" Nothing (SourceMap.empty "out.js")
            (_, sm2) = SourceMap.addSource "b.can" Nothing sm1
            (i1again, _) = SourceMap.addSource "a.can" Nothing sm2
         in (i1, i1again) @?= (0, 0)
    , testCase "addSource first index is 0 for fresh map" $
        let (idx, _) = SourceMap.addSource "main.can" Nothing (SourceMap.empty "out.js")
         in idx @?= 0
    ]

-- VLQ LARGE VALUE TESTS

-- | Tests for VLQ encoding of large and boundary values.
--
-- Large integers require multiple 6-bit continuation groups. These tests
-- verify correct output for values near standard bit boundaries.
vlqLargeValueTests :: TestTree
vlqLargeValueTests =
  testGroup
    "VLQ large value encoding"
    [ testCase "encodeVLQ 0x7FFFFFFF uses only Base64 characters" $
        let result = renderBuilder (SourceMap.encodeVLQ 0x7FFFFFFF)
         in all (`elem` base64Chars) result @?= True
    , testCase "encodeVLQ 0x7FFFFFFF produces non-empty output" $
        let result = renderBuilder (SourceMap.encodeVLQ 0x7FFFFFFF)
         in null result @?= False
    , testCase "encodeVLQ 0x7FFFFFFF requires 7 characters" $
        length (renderBuilder (SourceMap.encodeVLQ 0x7FFFFFFF)) @?= 7
    , testCase "encodeVLQ (-0x7FFFFFFF) requires same length as positive" $
        length (renderBuilder (SourceMap.encodeVLQ 0x7FFFFFFF))
          @?= length (renderBuilder (SourceMap.encodeVLQ (-0x7FFFFFFF)))
    , testCase "encodeVLQ 16 uses 2 chars (smallest two-group positive value)" $
        length (renderBuilder (SourceMap.encodeVLQ 16)) @?= 2
    , testCase "encodeVLQ 15 uses 1 char (largest single-group positive value)" $
        length (renderBuilder (SourceMap.encodeVLQ 15)) @?= 1
    , testCase "encodeVLQ (-15) uses 1 char (largest single-group negative value)" $
        length (renderBuilder (SourceMap.encodeVLQ (-15))) @?= 1
    , testCase "encodeVLQ (-16) uses 2 chars (smallest two-group negative value)" $
        length (renderBuilder (SourceMap.encodeVLQ (-16))) @?= 2
    , testCase "encodeVLQ 512 exact output" $
        renderBuilder (SourceMap.encodeVLQ 512) @?= "ggB"
    , testCase "encodeVLQ (-512) exact output" $
        renderBuilder (SourceMap.encodeVLQ (-512)) @?= "hgB"
    ]

-- | Base64 alphabet used to validate VLQ output characters.
base64Chars :: String
base64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- MAPPINGS ON HIGHER LINES TESTS

-- | Tests for mappings that start on generated lines other than line 0.
--
-- Source maps with no mappings on line 0 must still produce the correct
-- number of leading semicolons so that segment offsets are accurate.
mappingsOnHigherLinesTests :: TestTree
mappingsOnHigherLinesTests =
  testGroup
    "Mappings starting on line > 0"
    [ testCase "only a line-1 mapping produces ;;AAAA (empty line 0 + line 1 prefix + segment)" $
        let m = SourceMap.Mapping 1 0 0 0 0 Nothing
            sm = SourceMap.addMapping m (SourceMap.empty "out.js")
            mappingsValue = extractMappingsValue (renderBuilder (SourceMap.toBuilder sm))
         in mappingsValue @?= ";;AAAA"
    , testCase "only a line-2 mapping produces three leading semicolons" $
        let m = SourceMap.Mapping 2 0 0 0 0 Nothing
            sm = SourceMap.addMapping m (SourceMap.empty "out.js")
            mappingsValue = extractMappingsValue (renderBuilder (SourceMap.toBuilder sm))
         in take 3 mappingsValue @?= ";;;"
    , testCase "line-1-only mapping has exactly 2 semicolons total" $
        let m = SourceMap.Mapping 1 0 0 0 0 Nothing
            sm = SourceMap.addMapping m (SourceMap.empty "out.js")
            mappingsValue = extractMappingsValue (renderBuilder (SourceMap.toBuilder sm))
         in length (filter (== ';') mappingsValue) @?= 2
    , testCase "multiple mappings all on line 1 produce ;;AAAA,IAAI" $
        let m1 = SourceMap.Mapping 1 0 0 0 0 Nothing
            m2 = SourceMap.Mapping 1 4 0 0 4 Nothing
            sm = SourceMap.addMapping m2 (SourceMap.addMapping m1 (SourceMap.empty "out.js"))
            mappingsValue = extractMappingsValue (renderBuilder (SourceMap.toBuilder sm))
         in mappingsValue @?= ";;AAAA,IAAI"
    ]

-- COMBINED SERIALIZATION TESTS

-- | Tests that combine source registration with mapping serialization.
--
-- Verifies that the @sources@, @sourcesContent@, and @mappings@ fields
-- are all correct when both @addSource@ and @addMapping@ are used together.
combinedSerializationTests :: TestTree
combinedSerializationTests =
  testGroup
    "Combined source + mapping serialization"
    [ testCase "source registration appears in sources array alongside mapping" $
        let (_, sm1) = SourceMap.addSource "Main.can" (Just "module Main") (SourceMap.empty "out.js")
            sm2 = SourceMap.addMapping (SourceMap.Mapping 0 0 0 0 0 Nothing) sm1
            json = renderBuilder (SourceMap.toBuilder sm2)
         in json @?= "{\"version\":3,\"file\":\"out.js\",\"sources\":[\"Main.can\"],\"sourcesContent\":[\"module Main\"],\"names\":[],\"mappings\":\"AAAA\"}"
    , testCase "two sources with one mapping uses correct source index delta" $
        let (_, sm1) = SourceMap.addSource "A.can" Nothing (SourceMap.empty "out.js")
            (_, sm2) = SourceMap.addSource "B.can" Nothing sm1
            sm3 = SourceMap.addMapping (SourceMap.Mapping 0 0 1 0 0 Nothing) sm2
            json = renderBuilder (SourceMap.toBuilder sm3)
         in json @?= "{\"version\":3,\"file\":\"out.js\",\"sources\":[\"A.can\",\"B.can\"],\"sourcesContent\":[\"\",\"\"],\"names\":[],\"mappings\":\"ACAA\"}"
    , testCase "file name with backslash is escaped in JSON" $
        let json = renderBuilder (SourceMap.toBuilder (SourceMap.empty "path\\file.js"))
         in json @?= "{\"version\":3,\"file\":\"path\\\\file.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"\"}"
    , testCase "file name with newline is escaped in JSON" $
        let json = renderBuilder (SourceMap.toBuilder (SourceMap.empty "file\nname.js"))
         in json @?= "{\"version\":3,\"file\":\"file\\nname.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"\"}"
    , testCase "source content with tab is escaped in sourcesContent" $
        let (_, sm) = SourceMap.addSource "x.can" (Just "a\tb") (SourceMap.empty "out.js")
            json = renderBuilder (SourceMap.toBuilder sm)
         in json @?= "{\"version\":3,\"file\":\"out.js\",\"sources\":[\"x.can\"],\"sourcesContent\":[\"a\\tb\"],\"names\":[],\"mappings\":\"\"}"
    ]

-- EMPTY STATE TESTS

-- | Tests for the @empty@ constructor and initial field values.
--
-- Verifies that @empty@ initialises every field correctly and that
-- lens accessors expose the expected zero-state values.
emptyStateTests :: TestTree
emptyStateTests =
  testGroup
    "empty constructor and initial state"
    [ testCase "empty _smFile equals the given filename" $
        SourceMap._smFile (SourceMap.empty "my.js") @?= "my.js"
    , testCase "empty _smSources is empty list" $
        SourceMap._smSources (SourceMap.empty "my.js") @?= []
    , testCase "empty _smSourcesContent is empty list" $
        SourceMap._smSourcesContent (SourceMap.empty "my.js") @?= []
    , testCase "empty _smNames is empty list" $
        SourceMap._smNames (SourceMap.empty "my.js") @?= []
    , testCase "empty _smMappings is empty list" $
        SourceMap._smMappings (SourceMap.empty "my.js") @?= []
    , testCase "empty toBuilder produces version 3 JSON" $
        let json = renderBuilder (SourceMap.toBuilder (SourceMap.empty "x.js"))
         in json @?= "{\"version\":3,\"file\":\"x.js\",\"sources\":[],\"sourcesContent\":[],\"names\":[],\"mappings\":\"\"}"
    ]
