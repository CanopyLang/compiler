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

import qualified Data.Bits as Bits
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Data.List as List
import qualified Data.Maybe as Maybe
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
    , generatedColumnTests
    , subLineBreadcrumbTests
    , addMappingsTests
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
--
-- Per the Source Map V3 spec, @;@ characters are pure line SEPARATORS:
-- a segment group on 0-based generated line @N@ is preceded by exactly @N@
-- semicolons (line 0 → none, line 1 → one, line 2 → two). The encoder
-- previously emitted @N+1@ for @N >= 1@, which was harmless only because the
-- native IIFE's first mapping happened to sit on line 0 (the line-base bug
-- fixed by CMP-6). With the generated-line base now correct, every mapping
-- lands deep in the runtime and this off-by-one would shift every dev red-box
-- one line down — so these assertions pin the spec-exact semicolon counts.
mappingsOnHigherLinesTests :: TestTree
mappingsOnHigherLinesTests =
  testGroup
    "Mappings starting on line > 0"
    [ testCase "only a line-1 mapping produces ;AAAA (empty line 0 + line-1 segment)" $
        let m = SourceMap.Mapping 1 0 0 0 0 Nothing
            sm = SourceMap.addMapping m (SourceMap.empty "out.js")
            mappingsValue = extractMappingsValue (renderBuilder (SourceMap.toBuilder sm))
         in mappingsValue @?= ";AAAA"
    , testCase "only a line-2 mapping produces exactly two leading semicolons" $
        let m = SourceMap.Mapping 2 0 0 0 0 Nothing
            sm = SourceMap.addMapping m (SourceMap.empty "out.js")
            mappingsValue = extractMappingsValue (renderBuilder (SourceMap.toBuilder sm))
         in mappingsValue @?= ";;AAAA"
    , testCase "line-1-only mapping has exactly 1 semicolon total" $
        let m = SourceMap.Mapping 1 0 0 0 0 Nothing
            sm = SourceMap.addMapping m (SourceMap.empty "out.js")
            mappingsValue = extractMappingsValue (renderBuilder (SourceMap.toBuilder sm))
         in length (filter (== ';') mappingsValue) @?= 1
    , testCase "multiple mappings all on line 1 produce ;AAAA,IAAI" $
        let m1 = SourceMap.Mapping 1 0 0 0 0 Nothing
            m2 = SourceMap.Mapping 1 4 0 0 4 Nothing
            sm = SourceMap.addMapping m2 (SourceMap.addMapping m1 (SourceMap.empty "out.js"))
            mappingsValue = extractMappingsValue (renderBuilder (SourceMap.toBuilder sm))
         in mappingsValue @?= ";AAAA,IAAI"
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

-- GENERATED COLUMN (CMP-7A) TESTS

-- | Tests for def-level generated-column precision (CMP-7A).
--
-- CMP-6 fixed the generated LINE base; CMP-7A makes each def's mapping carry a
-- precise, def-distinguishing generated COLUMN (the byte offset of the def name
-- within its @var \<name\>@ statement, e.g. 4 after the @"var "@ prefix) instead
-- of the hard-coded @0@. A red-box then resolves to the right def + column, not
-- merely the right line.
--
-- These tests encode mappings with non-zero generated columns to a real V3
-- @mappings@ string and DECODE it back with a self-contained Base64-VLQ decoder
-- (so the assertion exercises the on-the-wire encoding, not just the Haskell
-- field), asserting the recovered column equals what was written. This is the
-- "decode the V3 map and assert column accuracy" gate the plan calls for, at the
-- pure-encoding level; 'Integration.Native.SourceMapColumnTest' provides the
-- end-to-end compiler gate.
generatedColumnTests :: TestTree
generatedColumnTests =
  testGroup
    "Generated column precision (CMP-7A)"
    [ testCase "a def at column 4 round-trips to column 4 (not 0)" $
        let m = SourceMap.Mapping 100 4 0 11 0 Nothing
            decoded = decodeColumns (serialize [m])
         in decoded @?= [(100, 4)]
    , testCase "two defs on the SAME line keep distinct, increasing columns" $
        let m1 = SourceMap.Mapping 5 4 0 0 0 Nothing
            m2 = SourceMap.Mapping 5 30 0 1 0 Nothing
            decoded = decodeColumns (serialize [m1, m2])
         in decoded @?= [(5, 4), (5, 30)]
    , testCase "genCol resets to 0 at each new generated line" $
        -- m1 ends on line 0 at column 12; m2 on line 1 at column 4. If the
        -- encoder failed to reset genCol per line, the decoded m2 column would
        -- be 16 (12 + delta) instead of 4 — this pins the per-line reset that
        -- def-column precision relies on.
        let m1 = SourceMap.Mapping 0 12 0 0 0 Nothing
            m2 = SourceMap.Mapping 1 4 0 1 0 Nothing
            decoded = decodeColumns (serialize [m1, m2])
         in decoded @?= [(0, 12), (1, 4)]
    , testCase "a large generated column (multi-VLQ-group) round-trips exactly" $
        let m = SourceMap.Mapping 0 1000 0 0 0 Nothing
            decoded = decodeColumns (serialize [m])
         in decoded @?= [(0, 1000)]
    , testCase "the source column travels alongside the generated column" $
        -- Both columns are encoded per segment; assert the full quadruple so a
        -- regression that swaps or zeroes either column is caught.
        let m = SourceMap.Mapping 7 4 0 6 2 Nothing
            decoded = decodeSegments (serialize [m])
         in decoded @?= [(7, 4, 6, 2)]
    ]

-- SUB-LINE BREADCRUMB (CMP-7B) TESTS

-- | Tests for sub-line / per-expression mappings (CMP-7B, Stage B).
--
-- CMP-7A records ONE mapping per top-level def (the def name's line+column).
-- CMP-7B threads additional breadcrumbs for the expressions emitted on that
-- same generated line, so a red-box can resolve to the specific
-- sub-expression. The seam is 'threadBreadcrumbs' (lift @(genCol, srcPos)@
-- breadcrumbs onto a concrete generated line + source index, no printer fork)
-- plus 'addMappings' (bulk-append the run) plus the encoder's per-line column
-- sort (so breadcrumbs may be supplied in source-traversal order).
--
-- Each test ENCODES to a real V3 @mappings@ string and DECODES it back with
-- the self-contained decoder below, asserting the on-the-wire round-trip — so
-- the assertions exercise the actual VLQ bytes, not just the Haskell fields.
subLineBreadcrumbTests :: TestTree
subLineBreadcrumbTests =
  testGroup
    "Sub-line breadcrumbs (CMP-7B)"
    [ testCase "threadBreadcrumbs lifts each breadcrumb onto the given line + source index" $
        let crumbs =
              [ SourceMap.Breadcrumb 4 10 6
              , SourceMap.Breadcrumb 12 10 14
              , SourceMap.Breadcrumb 20 11 2
              ]
            ms = SourceMap.threadBreadcrumbs 7 0 crumbs
         in ms
              @?= [ SourceMap.Mapping 7 4 0 10 6 Nothing
                  , SourceMap.Mapping 7 12 0 10 14 Nothing
                  , SourceMap.Mapping 7 20 0 11 2 Nothing
                  ]
    , testCase "threadBreadcrumbs carries a non-zero source index onto every mapping" $
        let crumbs = [SourceMap.Breadcrumb 4 0 0, SourceMap.Breadcrumb 8 1 3]
            ms = SourceMap.threadBreadcrumbs 0 2 crumbs
         in map SourceMap._mSrcIndex ms @?= [2, 2]
    , testCase "a run of breadcrumbs on ONE line round-trips to distinct increasing columns" $
        -- The whole point of Stage B: several sub-expression columns on a
        -- single generated line, each recovering its own (genCol, srcLine,
        -- srcCol). Decoding the wire proves the deltas are spec-valid.
        let crumbs =
              [ SourceMap.Breadcrumb 4 0 0
              , SourceMap.Breadcrumb 18 0 10
              , SourceMap.Breadcrumb 42 1 4
              ]
            ms = SourceMap.threadBreadcrumbs 3 0 crumbs
            decoded = decodeSegments (serialize ms)
         in decoded @?= [(3, 4, 0, 0), (3, 18, 0, 10), (3, 42, 1, 4)]
    , testCase "breadcrumbs supplied OUT of column order still encode to monotonic columns" $
        -- Breadcrumbs may be threaded in source-traversal order, which need
        -- not be left-to-right on the generated line. The encoder's per-line
        -- column sort must restore monotonicity so no segment delta is
        -- negative; the decoded columns must come back ascending.
        let crumbs =
              [ SourceMap.Breadcrumb 30 2 0
              , SourceMap.Breadcrumb 4 0 0
              , SourceMap.Breadcrumb 16 1 0
              ]
            ms = SourceMap.threadBreadcrumbs 5 0 crumbs
            decodedCols = map (\(_, gc, _, _) -> gc) (decodeSegments (serialize ms))
         in decodedCols @?= [4, 16, 30]
    , testCase "out-of-order breadcrumbs keep each column paired with its OWN source position" $
        -- Sorting by generated column must move the source position with it —
        -- a regression that sorted columns but not the paired source coords
        -- would mis-attribute tokens. Assert the full quadruples.
        let crumbs =
              [ SourceMap.Breadcrumb 30 2 7
              , SourceMap.Breadcrumb 4 0 1
              , SourceMap.Breadcrumb 16 1 5
              ]
            ms = SourceMap.threadBreadcrumbs 9 0 crumbs
            decoded = decodeSegments (serialize ms)
         in decoded @?= [(9, 4, 0, 1), (9, 16, 1, 5), (9, 30, 2, 7)]
    , testCase "two breadcrumbs at the SAME generated column collapse to the first" $
        -- A single generated position can map to only one source position;
        -- threadBreadcrumbs de-dups by generated column, keeping the first.
        let crumbs =
              [ SourceMap.Breadcrumb 4 0 0
              , SourceMap.Breadcrumb 4 9 9
              , SourceMap.Breadcrumb 8 1 1
              ]
            ms = SourceMap.threadBreadcrumbs 0 0 crumbs
         in ms
              @?= [ SourceMap.Mapping 0 4 0 0 0 Nothing
                  , SourceMap.Mapping 0 8 0 1 1 Nothing
                  ]
    , testCase "empty breadcrumb list yields no mappings" $
        SourceMap.threadBreadcrumbs 0 0 [] @?= []
    , testCase "a def-level mapping plus its sub-line breadcrumbs share one generated line" $
        -- End-to-end Stage-B shape: the def mapping (column 4, the def name)
        -- followed by breadcrumbs for the expressions on the same line. All
        -- segments must land on genLine 7 with ascending columns and recover
        -- their own source positions.
        let defMapping = SourceMap.Mapping 7 4 0 0 0 Nothing
            crumbs =
              [ SourceMap.Breadcrumb 10 0 6
              , SourceMap.Breadcrumb 22 0 18
              ]
            ms = defMapping : SourceMap.threadBreadcrumbs 7 0 crumbs
            decoded = decodeSegments (serialize ms)
         in decoded @?= [(7, 4, 0, 0), (7, 10, 0, 6), (7, 22, 0, 18)]
    ]

-- ADDMAPPINGS (BULK APPEND) TESTS

-- | Tests for 'addMappings', the bulk-append used by the breadcrumb path.
--
-- 'addMappings' must be observationally equivalent to folding 'addMapping'
-- left-to-right, and must serialize identically whether a run is added in
-- bulk or one-by-one.
addMappingsTests :: TestTree
addMappingsTests =
  testGroup
    "addMappings bulk append"
    [ testCase "addMappings equals folding addMapping left-to-right" $
        let ms =
              [ SourceMap.Mapping 0 0 0 0 0 Nothing
              , SourceMap.Mapping 0 8 0 0 4 Nothing
              , SourceMap.Mapping 1 0 0 1 0 Nothing
              ]
            viaBulk = SourceMap.addMappings ms (SourceMap.empty "out.js")
            viaFold = List.foldl' (flip SourceMap.addMapping) (SourceMap.empty "out.js") ms
         in renderBuilder (SourceMap.toBuilder viaBulk)
              @?= renderBuilder (SourceMap.toBuilder viaFold)
    , testCase "addMappings on an empty list leaves the map unchanged" $
        let sm0 = SourceMap.empty "out.js"
         in renderBuilder (SourceMap.toBuilder (SourceMap.addMappings [] sm0))
              @?= renderBuilder (SourceMap.toBuilder sm0)
    , testCase "addMappings accumulates every element in _smMappings" $
        let ms =
              [ SourceMap.Mapping 0 0 0 0 0 Nothing
              , SourceMap.Mapping 0 8 0 0 4 Nothing
              ]
            sm = SourceMap.addMappings ms (SourceMap.empty "out.js")
         in length (SourceMap._smMappings sm) @?= 2
    , testCase "addMappings of threaded breadcrumbs serializes to a sorted same-line run" $
        let crumbs =
              [ SourceMap.Breadcrumb 24 0 12
              , SourceMap.Breadcrumb 4 0 0
              ]
            sm = SourceMap.addMappings (SourceMap.threadBreadcrumbs 0 0 crumbs) (SourceMap.empty "out.js")
            decodedCols = map (\(_, gc, _, _) -> gc) (decodeSegments (extractMappingsValue (renderBuilder (SourceMap.toBuilder sm))))
         in decodedCols @?= [4, 24]
    ]

-- V3 MAPPINGS DECODER (self-contained, for column-accuracy assertions)

-- | Serialize a list of mappings and extract just the @mappings@ VLQ string.
serialize :: [SourceMap.Mapping] -> String
serialize ms =
  extractMappingsValue
    (renderBuilder (SourceMap.toBuilder (foldr SourceMap.addMapping (SourceMap.empty "out.js") (reverse ms))))

-- | Decode the @mappings@ string into @(genLine, genCol)@ pairs, one per
-- segment, applying the V3 relative-delta scheme (genCol resets each line).
decodeColumns :: String -> [(Int, Int)]
decodeColumns = map (\(gl, gc, _, _) -> (gl, gc)) . decodeSegments

-- | Decode the @mappings@ string into @(genLine, genCol, srcLine, srcCol)@ per
-- segment. @genCol@ resets at each generated line; @srcLine@/@srcCol@ carry
-- across the whole stream as relative deltas, per the V3 spec.
decodeSegments :: String -> [(Int, Int, Int, Int)]
decodeSegments mappingsStr =
  concat (goLines 0 0 0 0 (splitOn ';' mappingsStr))
  where
    goLines _ _ _ _ [] = []
    goLines genLine srcIdx srcLine srcCol (lineStr : rest) =
      let (decoded, srcIdx', srcLine', srcCol') =
            goSegs genLine 0 srcIdx srcLine srcCol (filter (not . null) (splitOn ',' lineStr))
       in decoded : goLines (genLine + 1) srcIdx' srcLine' srcCol' rest
    goSegs _ _ srcIdx srcLine srcCol [] = ([], srcIdx, srcLine, srcCol)
    goSegs genLine genCol srcIdx srcLine srcCol (seg : segs) =
      case decodeVLQs seg of
        (gcD : srcIdxD : srcLineD : srcColD : _) ->
          let genCol' = genCol + gcD
              srcIdx' = srcIdx + srcIdxD
              srcLine' = srcLine + srcLineD
              srcCol' = srcCol + srcColD
              (ms, fi, fl, fc) = goSegs genLine genCol' srcIdx' srcLine' srcCol' segs
           in ((genLine, genCol', srcLine', srcCol') : ms, fi, fl, fc)
        (gcD : _) ->
          -- genCol-only segment: advance the running column, emit nothing.
          goSegs genLine (genCol + gcD) srcIdx srcLine srcCol segs
        _ ->
          goSegs genLine genCol srcIdx srcLine srcCol segs

-- | Split a string on a delimiter (keeps empty fields, like the V3 encoding).
splitOn :: Char -> String -> [String]
splitOn delim = foldr step [[]]
  where
    step c acc@(cur : rest)
      | c == delim = [] : acc
      | otherwise = (c : cur) : rest
    step _ [] = [[]]

-- | Decode all Base64-VLQ values packed in one segment.
decodeVLQs :: String -> [Int]
decodeVLQs [] = []
decodeVLQs s =
  let (v, rest) = decodeOneVLQ s in v : decodeVLQs rest

-- | Decode one signed VLQ value, returning it and the unconsumed suffix.
decodeOneVLQ :: String -> (Int, String)
decodeOneVLQ = consume 0 0
  where
    consume shift acc (c : cs) =
      let digit = base64Index c
          acc' = acc Bits..|. ((digit Bits..&. 0x1F) `Bits.shiftL` shift)
          continues = digit Bits..&. 0x20 /= 0
       in if continues
            then consume (shift + 5) acc' cs
            else (fromVLQSigned acc', cs)
    consume _ acc [] = (fromVLQSigned acc, [])
    fromVLQSigned v =
      let magnitude = v `Bits.shiftR` 1
       in if v Bits..&. 1 == 1 then negate magnitude else magnitude

-- | Index of a character in the Base64 VLQ alphabet (0 if absent).
base64Index :: Char -> Int
base64Index c = Maybe.fromMaybe 0 (List.elemIndex c base64Chars)
