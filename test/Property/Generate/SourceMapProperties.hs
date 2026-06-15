{-# LANGUAGE OverloadedStrings #-}

-- | Property tests for Source Map V3 generation.
--
-- Validates invariants of VLQ encoding and source map construction
-- that must hold for all inputs, using QuickCheck property testing.
--
-- @since 0.19.2
module Property.Generate.SourceMapProperties (tests) where

import qualified Data.Bits as Bits
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Data.List as List
import qualified Data.Maybe as Maybe
import qualified Generate.JavaScript.SourceMap as SourceMap
import Test.Tasty
import Test.Tasty.QuickCheck

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.SourceMap Properties"
    [ vlqProperties
    , sourceMapProperties
    , breadcrumbProperties
    ]

-- | Helper to render a Builder to a String for assertions.
renderBuilder :: BB.Builder -> String
renderBuilder = LChar8.unpack . BB.toLazyByteString

-- VLQ PROPERTIES

vlqProperties :: TestTree
vlqProperties =
  testGroup
    "VLQ Properties"
    [ testProperty "VLQ output uses only Base64 characters" $
        forAll (chooseInt (-100000, 100000)) $ \n ->
          let result = renderBuilder (SourceMap.encodeVLQ n)
           in all (`elem` base64Chars) result
    , testProperty "VLQ output is non-empty for any integer" $
        forAll (chooseInt (-100000, 100000)) $ \n ->
          not (null (renderBuilder (SourceMap.encodeVLQ n)))
    , testProperty "VLQ of positive and negative same magnitude have equal length" $
        forAll (chooseInt (0, 100000)) $ \n ->
          let posLen = length (renderBuilder (SourceMap.encodeVLQ n))
              negLen = length (renderBuilder (SourceMap.encodeVLQ (negate n)))
           in posLen == negLen
    , testProperty "VLQ of zero is always A" $
        renderBuilder (SourceMap.encodeVLQ 0) === "A"
    , testProperty "VLQ length increases with magnitude" $
        forAll (chooseInt (0, 100)) $ \n ->
          let len1 = length (renderBuilder (SourceMap.encodeVLQ n))
              len2 = length (renderBuilder (SourceMap.encodeVLQ (n * 1000 + 500)))
           in len1 <= len2
    ]

-- SOURCE MAP PROPERTIES

sourceMapProperties :: TestTree
sourceMapProperties =
  testGroup
    "Source Map Properties"
    [ testProperty "addSource index is monotonically increasing" $
        forAll (listOf1 arbitrarySourcePath) $ \paths ->
          let uniquePaths = List.nub paths
              indices = scanSources uniquePaths
           in indices == [0 .. length uniquePaths - 1]
    , testProperty "addSource duplicate returns same index" $
        forAll arbitrarySourcePath $ \path ->
          let (idx1, sm1) = SourceMap.addSource path Nothing (SourceMap.empty "test.js")
              (idx2, _sm2) = SourceMap.addSource path Nothing sm1
           in idx1 == idx2
    , testProperty "toBuilder always produces valid JSON structure" $
        forAll (chooseInt (0, 10)) $ \n ->
          let sm = addNMappings n (SourceMap.empty "test.js")
              json = renderBuilder (SourceMap.toBuilder sm)
           in head json == '{' && last json == '}'
    , testProperty "toBuilder always contains version 3" $
        forAll (chooseInt (0, 5)) $ \n ->
          let sm = addNMappings n (SourceMap.empty "test.js")
              json = renderBuilder (SourceMap.toBuilder sm)
           in "{\"version\":3" `List.isPrefixOf` json
    , testProperty "all source indices in mappings are non-negative" $
        forAll (listOf arbitraryMapping) $ \mappings ->
          all (\m -> SourceMap._mSrcIndex m >= 0) mappings
    ]

-- SUB-LINE BREADCRUMB PROPERTIES (CMP-7B)

-- | Properties for the sub-line breadcrumb path (CMP-7B, Stage B).
--
-- These pin the invariants the per-def breadcrumb threading relies on, for
-- ALL inputs: threaded breadcrumbs encode to a SINGLE generated line whose
-- decoded columns are strictly ascending (so no VLQ delta is negative and no
-- consumer sees a column going backwards), and the decoded set of columns is
-- exactly the de-duplicated set of input generated columns. Each property
-- round-trips through the real V3 wire (encode then decode), not just the
-- Haskell fields.
breadcrumbProperties :: TestTree
breadcrumbProperties =
  testGroup
    "Sub-line breadcrumb properties (CMP-7B)"
    [ testProperty "threaded breadcrumbs decode to strictly ascending columns" $
        forAll arbitraryBreadcrumbs $ \crumbs ->
          let ms = SourceMap.threadBreadcrumbs 0 0 crumbs
              cols = decodeColumnsOnLine0 (serialize ms)
           in strictlyAscending cols
    , testProperty "decoded columns are exactly the de-duplicated input columns, sorted" $
        forAll arbitraryBreadcrumbs $ \crumbs ->
          let ms = SourceMap.threadBreadcrumbs 0 0 crumbs
              decodedCols = decodeColumnsOnLine0 (serialize ms)
              expected = List.sort (List.nub (map breadcrumbCol crumbs))
           in decodedCols === expected
    , testProperty "every threaded breadcrumb lands on the given generated line" $
        forAll (chooseInt (0, 500)) $ \genLine ->
          forAll arbitraryBreadcrumbs $ \crumbs ->
            let ms = SourceMap.threadBreadcrumbs genLine 3 crumbs
             in all (\m -> SourceMap._mGenLine m == genLine) ms
    , testProperty "threadBreadcrumbs stamps the source index on every mapping" $
        forAll (chooseInt (0, 9)) $ \srcIdx ->
          forAll arbitraryBreadcrumbs $ \crumbs ->
            let ms = SourceMap.threadBreadcrumbs 0 srcIdx crumbs
             in all (\m -> SourceMap._mSrcIndex m == srcIdx) ms
    ]

-- | Generate a small list of breadcrumbs with non-negative coordinates.
arbitraryBreadcrumbs :: Gen [SourceMap.Breadcrumb]
arbitraryBreadcrumbs = do
  n <- chooseInt (0, 8)
  vectorOf n arbitraryBreadcrumb

-- | Generate a single breadcrumb with non-negative coordinates.
arbitraryBreadcrumb :: Gen SourceMap.Breadcrumb
arbitraryBreadcrumb = do
  genCol <- chooseInt (0, 300)
  srcLine <- chooseInt (0, 500)
  srcCol <- chooseInt (0, 200)
  return (SourceMap.Breadcrumb genCol srcLine srcCol)

-- | The generated column carried by a breadcrumb.
breadcrumbCol :: SourceMap.Breadcrumb -> Int
breadcrumbCol (SourceMap.Breadcrumb genCol _ _) = genCol

-- | True when a list of integers is strictly increasing.
strictlyAscending :: [Int] -> Bool
strictlyAscending xs = and (zipWith (<) xs (drop 1 xs))

-- | Serialize mappings and extract just the @mappings@ VLQ string.
serialize :: [SourceMap.Mapping] -> String
serialize ms =
  extractMappingsValue
    (renderBuilder (SourceMap.toBuilder (SourceMap.addMappings ms (SourceMap.empty "out.js"))))

-- | Extract the value of the @"mappings"@ field from a source map JSON string.
extractMappingsValue :: String -> String
extractMappingsValue json = takeWhile (/= '"') (dropPrefix "\"mappings\":\"" json)
  where
    dropPrefix _ [] = []
    dropPrefix prefix full@(_ : rest)
      | take (length prefix) full == prefix = drop (length prefix) full
      | otherwise = dropPrefix prefix rest

-- | Decode the generated columns of every segment that sits on generated
-- line 0 (all breadcrumbs threaded with @genLine = 0@ land there).
decodeColumnsOnLine0 :: String -> [Int]
decodeColumnsOnLine0 mappingsStr =
  case splitOn ';' mappingsStr of
    (line0 : _) -> decodeLineCols 0 (filter (not . null) (splitOn ',' line0))
    [] -> []
  where
    decodeLineCols _ [] = []
    decodeLineCols genCol (seg : segs) =
      case decodeVLQs seg of
        (gcD : _) -> let c = genCol + gcD in c : decodeLineCols c segs
        [] -> decodeLineCols genCol segs

-- | Split a string on a delimiter, keeping empty fields.
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
decodeVLQs s = let (v, rest) = decodeOneVLQ s in v : decodeVLQs rest

-- | Decode one signed VLQ value, returning it and the unconsumed suffix.
decodeOneVLQ :: String -> (Int, String)
decodeOneVLQ = consume 0 0
  where
    consume shift acc (c : cs) =
      let digit = base64Index c
          acc' = acc Bits..|. ((digit Bits..&. 0x1F) `Bits.shiftL` shift)
          continues = digit Bits..&. 0x20 /= 0
       in if continues then consume (shift + 5) acc' cs else (fromVLQSigned acc', cs)
    consume _ acc [] = (fromVLQSigned acc, [])
    fromVLQSigned v =
      let magnitude = v `Bits.shiftR` 1
       in if v Bits..&. 1 == 1 then negate magnitude else magnitude

-- | Index of a character in the Base64 VLQ alphabet (0 if absent).
base64Index :: Char -> Int
base64Index c = Maybe.fromMaybe 0 (List.elemIndex c base64Chars)

-- | Generate sequential source indices from a list of paths.
scanSources :: [String] -> [Int]
scanSources = go (SourceMap.empty "test.js")
  where
    go _sm [] = []
    go sm (p : ps) =
      let (idx, sm') = SourceMap.addSource p Nothing sm
       in idx : go sm' ps

-- | Add N mappings at sequential lines to a source map.
addNMappings :: Int -> SourceMap.SourceMap -> SourceMap.SourceMap
addNMappings n sm =
  foldr addOne sm [0 .. n - 1]
  where
    addOne i = SourceMap.addMapping (SourceMap.Mapping i 0 0 i 0 Nothing)

-- | Generate an arbitrary source file path.
arbitrarySourcePath :: Gen String
arbitrarySourcePath = do
  depth <- chooseInt (1, 3)
  parts <- vectorOf depth arbitraryPathComponent
  ext <- elements [".can", ".canopy"]
  return (List.intercalate "/" parts ++ ext)

-- | Generate an arbitrary path component.
arbitraryPathComponent :: Gen String
arbitraryPathComponent = do
  first <- elements ['A' .. 'Z']
  rest <- listOf (elements (['a' .. 'z'] ++ ['A' .. 'Z'] ++ ['0' .. '9']))
  return (first : take 10 rest)

-- | Generate an arbitrary mapping.
arbitraryMapping :: Gen SourceMap.Mapping
arbitraryMapping = do
  genLine <- chooseInt (0, 1000)
  genCol <- chooseInt (0, 200)
  srcIdx <- chooseInt (0, 10)
  srcLine <- chooseInt (0, 1000)
  srcCol <- chooseInt (0, 200)
  return (SourceMap.Mapping genLine genCol srcIdx srcLine srcCol Nothing)

base64Chars :: String
base64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
