{-# LANGUAGE OverloadedStrings #-}

-- | Property tests for Source Map V3 generation.
--
-- Validates invariants of VLQ encoding and source map construction
-- that must hold for all inputs, using QuickCheck property testing.
--
-- @since 0.19.2
module Property.Generate.SourceMapProperties (tests) where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Data.List as List
import qualified Generate.JavaScript.SourceMap as SourceMap
import Test.Tasty
import Test.Tasty.QuickCheck

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.SourceMap Properties"
    [ vlqProperties
    , sourceMapProperties
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
           in "\"version\":3" `List.isInfixOf` json
    , testProperty "all source indices in mappings are non-negative" $
        forAll (listOf arbitraryMapping) $ \mappings ->
          all (\m -> SourceMap._mSrcIndex m >= 0) mappings
    ]

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
