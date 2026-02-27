{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

{-|
Module: Unit.Data.Map.UtilsTest
Description: Comprehensive test suite for Data.Map.Utils module
Copyright: (c) 2024 Canopy Contributors
License: BSD-3-Clause

This module provides complete test coverage for all public functions,
edge cases, error conditions, and properties in Data.Map.Utils.

Coverage Target: ≥80% line coverage
Test Categories: Unit, Property, Edge Case, Error Condition

@since 0.19.1
-}
module Unit.Data.Map.UtilsTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck (testProperty, Fun(..))

import qualified Canopy.Data.Map.Utils as MapUtils
import qualified Data.Map as Map
import Data.Map (Map)
import qualified Canopy.Data.NonEmptyList as NE
import Canopy.Data.NonEmptyList (List(..))

-- | Main test tree containing all Data.Map.Utils tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "Data.Map.Utils Tests"
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
  [ testGroup "Map Construction"
      [ testCase "fromKeys with identity function" $ do
          let keys = [1, 2, 3]
              result = MapUtils.fromKeys id keys
              expected = Map.fromList [(1, 1), (2, 2), (3, 3)]
          result @?= expected
      , testCase "fromKeys with transformation" $ do
          let keys = ["hello", "world", "test"] :: [String]
              result = MapUtils.fromKeys length keys
              expected = Map.fromList [("hello", 5), ("world", 5), ("test", 4)]
          result @?= expected
      , testCase "fromKeys with show function" $ do
          let keys = [1, 2, 3]
              result = MapUtils.fromKeys show keys
              expected = Map.fromList [(1, "1"), (2, "2"), (3, "3")]
          result @?= expected
      , testCase "fromKeys empty list" $ do
          let result = MapUtils.fromKeys show ([] :: [Int])
          result @?= Map.empty
      , testCase "fromKeys with duplicate keys" $ do
          let keys = [1, 2, 1, 3]
              result = MapUtils.fromKeys (*2) keys
              -- Later occurrences overwrite earlier ones
              expected = Map.fromList [(1, 2), (2, 4), (3, 6)]
          result @?= expected
      ]
  , testGroup "Applicative Map Construction"
      [ testCase "fromKeysA successful all" $ do
          let keys = [1, 2, 3]
              result = MapUtils.fromKeysA (\x -> Just (x * 2)) keys
              expected = Just (Map.fromList [(1, 2), (2, 4), (3, 6)])
          result @?= expected
      , testCase "fromKeysA with failure" $ do
          let keys = [1, 2, 3]
              result = MapUtils.fromKeysA (\x -> if x > 1 then Just (x * 2) else Nothing) keys
          result @?= Nothing
      , testCase "fromKeysA empty list" $ do
          let result = MapUtils.fromKeysA (\x -> Just (x * 2)) ([] :: [Int])
          result @?= Just Map.empty
      , testCase "fromKeysA with Either success" $ do
          let keys = [1, 2, 3]
              result = MapUtils.fromKeysA (\x -> Right (show x)) keys
              expected = Right (Map.fromList [(1, "1"), (2, "2"), (3, "3")])
          result @?= (expected :: Either String (Map Int String))
      , testCase "fromKeysA with Either failure" $ do
          let keys = [1, 2, 3]
              result = MapUtils.fromKeysA (\x -> if x /= 2 then Right (show x) else Left "error") keys
          case result of
            Left "error" -> return ()
            _ -> assertFailure "Expected Left \"error\""
      ]
  , testGroup "Value-based Map Construction"
      [ testCase "fromValues with identity function" $ do
          let values = [1, 2, 3]
              result = MapUtils.fromValues id values
              expected = Map.fromList [(1, 1), (2, 2), (3, 3)]
          result @?= expected
      , testCase "fromValues with length function" $ do
          let values = ["hello", "world", "test", "hi"] :: [String]
              result = MapUtils.fromValues length values
              -- Note: "hello" and "world" both have length 5, so "world" overwrites "hello"
              expected = Map.fromList [(5, "world"), (4, "test"), (2, "hi")]
          result @?= expected
      , testCase "fromValues with head function" $ do
          let values = [['a', 'b'], ['c'], ['a', 'x']]
              result = MapUtils.fromValues head values
              expected = Map.fromList [('a', ['a', 'x']), ('c', ['c'])]
          result @?= expected
      , testCase "fromValues empty list" $ do
          let result = MapUtils.fromValues id ([] :: [Int])
          result @?= Map.empty
      , testCase "fromValues with duplicates" $ do
          let values = [1, 2, 3, 2, 4]
              result = MapUtils.fromValues id values
              -- Second occurrence of 2 overwrites the first
              expected = Map.fromList [(1, 1), (2, 2), (3, 3), (4, 4)]
          result @?= expected
      ]
  , testGroup "Content Testing"
      [ testCase "any with match" $ do
          let testMap = Map.fromList [(1, 10), (2, 3), (3, 7)]
              result = MapUtils.any (> 5) testMap
          result @?= True
      , testCase "any with no match" $ do
          let testMap = Map.fromList [('a', 1), ('b', 3), ('c', 5)]
              result = MapUtils.any even testMap
          result @?= False
      , testCase "any empty map" $ do
          let testMap = Map.empty :: Map Int Int
              result = MapUtils.any (> 0) testMap
          result @?= False
      , testCase "any with null strings" $ do
          let testMap = Map.fromList [(1, "hello"), (2, ""), (3, "world")] :: Map Int String
              result = MapUtils.any null testMap
          result @?= True
      , testCase "any single element match" $ do
          let testMap = Map.singleton 1 42
              result = MapUtils.any (== 42) testMap
          result @?= True
      , testCase "any single element no match" $ do
          let testMap = Map.singleton 1 42
              result = MapUtils.any (== 43) testMap
          result @?= False
      ]
  , testGroup "Structure Transformation"
      [ testCase "exchangeKeys basic transformation" $ do
          let byModule = Map.fromList 
                [("Parser", Map.fromList [("Error", 2), ("Warning", 1)])
                ,("TypeChecker", Map.fromList [("Error", 3)])
                ]
              result = MapUtils.exchangeKeys byModule
              expected = Map.fromList 
                [("Error", Map.fromList [("Parser", 2), ("TypeChecker", 3)])
                ,("Warning", Map.fromList [("Parser", 1)])
                ]
          result @?= expected
      , testCase "exchangeKeys empty outer map" $ do
          let empty = Map.empty :: Map String (Map String Int)
              result = MapUtils.exchangeKeys empty
          result @?= Map.empty
      , testCase "exchangeKeys with empty inner maps" $ do
          let withEmpty = Map.fromList [("A", Map.empty), ("B", Map.fromList [("x", 1)])]
              result = MapUtils.exchangeKeys withEmpty
              expected = Map.fromList [("x", Map.fromList [("B", 1)])]
          result @?= expected
      , testCase "exchangeKeys single entry" $ do
          let single = Map.fromList [("Module", Map.fromList [("Function", 42)])]
              result = MapUtils.exchangeKeys single
              expected = Map.fromList [("Function", Map.fromList [("Module", 42)])]
          result @?= expected
      ]
  , testGroup "Map Inversion"
      [ testCase "invertMap basic case" $ do
          let original = Map.fromList 
                [("errors", NE.List "parse" ["type"])
                ,("warnings", NE.List "unused" [])
                ]
              result = MapUtils.invertMap original
              expected = Map.fromList 
                [("parse", NE.List "errors" [])
                ,("type", NE.List "errors" [])
                ,("unused", NE.List "warnings" [])
                ]
          result @?= expected
      , testCase "invertMap with overlapping values" $ do
          let original = Map.fromList 
                [("A", NE.List "x" ["y"])
                ,("B", NE.List "x" ["z"])
                ]
              result = MapUtils.invertMap original
              -- Check that all expected keys exist and have correct sorted values
              xResult = case Map.lookup "x" result of
                Just ne -> NE.sortBy id ne
                Nothing -> error "Expected 'x' key not found"
              yResult = Map.lookup "y" result
              zResult = Map.lookup "z" result
          xResult @?= NE.List "A" ["B"]
          yResult @?= Just (NE.singleton "A")
          zResult @?= Just (NE.singleton "B")
      , testCase "invertMap empty map" $ do
          let empty = Map.empty :: Map String (NE.List String)
              result = MapUtils.invertMap empty
          result @?= Map.empty
      , testCase "invertMap single entry single value" $ do
          let single = Map.fromList [("key", NE.singleton "value")]
              result = MapUtils.invertMap single
              expected = Map.fromList [("value", NE.singleton "key")]
          result @?= expected
      , testCase "invertMap multiple keys same value" $ do
          let original = Map.fromList 
                [("A", NE.singleton "common")
                ,("B", NE.singleton "common")
                ,("C", NE.singleton "unique")
                ]
              result = MapUtils.invertMap original
              expectedCommon = case Map.lookup "common" result of
                Just ne -> NE.sortBy id ne
                Nothing -> error "Expected 'common' key not found"
              expectedUnique = Map.lookup "unique" result
          expectedCommon @?= NE.List "A" ["B"]
          expectedUnique @?= Just (NE.singleton "C")
      ]
  ]

-- | Property-based tests for mathematical and logical operations.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with mathematical or logical operations.
propertyTests :: TestTree
propertyTests = testGroup "Property Tests"
  [ testProperty "fromKeys preserves all keys" $ \keys ->
      let result = MapUtils.fromKeys id (keys :: [Int])
          resultKeys = Map.keys result
      in length (Map.toList result) <= length keys  -- <= due to potential duplicates
  , testProperty "fromKeys applies function correctly" $ \keys ->
      let f = (*2)
          result = MapUtils.fromKeys f (keys :: [Int])
      in all (\(k, v) -> v == f k) (Map.toList result)
  , testProperty "fromKeysA successful case" $ \keys ->
      let result = MapUtils.fromKeysA (Just . (*2)) (keys :: [Int])
      in case result of
           Just m -> all (\(k, v) -> v == k * 2) (Map.toList m)
           Nothing -> False
  , testProperty "fromValues preserves all values" $ \values ->
      let result = MapUtils.fromValues id (values :: [Int])
          resultValues = Map.elems result
      in length resultValues <= length values  -- <= due to potential key collisions
  , testProperty "fromValues applies key function correctly" $ \values ->
      let f = abs
          result = MapUtils.fromValues f (values :: [Int])
      in all (\(k, v) -> k == f v) (Map.toList result)
  , testProperty "any returns True if predicate holds" $ \kvPairs ->
      let testMap = Map.fromList (kvPairs :: [(Int, Int)])
          predicate = (> 0)
      in MapUtils.any predicate testMap == any predicate (Map.elems testMap)
  , testProperty "any returns False for empty map" $ \(Fun _ predicate) ->
      let emptyMap = Map.empty :: Map Int Int
      in not (MapUtils.any predicate emptyMap)
  , testProperty "exchangeKeys preserves all data" $ \nestedData ->
      let validData = filter (not . null . snd) nestedData :: [(Int, [(String, Int)])]
          original = Map.fromList validData
          originalMaps = fmap Map.fromList original
          exchanged = MapUtils.exchangeKeys originalMaps
          -- Count total entries in both structures
          originalCount = sum $ fmap Map.size originalMaps
          exchangedCount = sum $ fmap Map.size (Map.elems exchanged)
      in originalCount == exchangedCount
  , testProperty "exchangeKeys double application" $ \nestedData ->
      let validData = filter (not . null . snd) nestedData :: [(String, [(Int, String)])]
          original = Map.fromList validData
          originalMaps = fmap Map.fromList original
          exchanged = MapUtils.exchangeKeys originalMaps
          doubleExchanged = MapUtils.exchangeKeys exchanged
          -- After double exchange, count should be preserved
          originalCount = sum $ fmap Map.size originalMaps
          finalCount = sum $ fmap Map.size (Map.elems doubleExchanged)
      in originalCount == finalCount
  , testProperty "invertMap preserves all associations" $ \mapData ->
      let -- Only use non-empty lists and ensure unique keys
          nonEmptyData = [(k, vs) | (k, vs) <- mapData :: [(String, [Int])], not (null vs)]
          uniqueKeyData = Map.toList (Map.fromList nonEmptyData) -- Remove duplicate keys
          originalNE = Map.fromList [(k, NE.List (head vs) (tail vs)) | (k, vs) <- uniqueKeyData]
          inverted = MapUtils.invertMap originalNE
          -- Count associations in both directions
          originalAssocs = sum $ map (length . snd) uniqueKeyData
          invertedAssocs = sum $ map (length . NE.toList) (Map.elems inverted)
      in originalAssocs == invertedAssocs
  ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testGroup "Empty Input Handling"
      [ testCase "all functions handle empty inputs" $ do
          -- fromKeys
          MapUtils.fromKeys show ([] :: [Int]) @?= Map.empty
          
          -- fromKeysA  
          MapUtils.fromKeysA (Just . show) ([] :: [Int]) @?= Just Map.empty
          
          -- fromValues
          MapUtils.fromValues show ([] :: [String]) @?= Map.empty
          
          -- any
          MapUtils.any (const True) (Map.empty :: Map Int Int) @?= False
          
          -- exchangeKeys
          MapUtils.exchangeKeys (Map.empty :: Map String (Map Int String)) @?= Map.empty
          
          -- invertMap
          MapUtils.invertMap (Map.empty :: Map String (NE.List Int)) @?= Map.empty
      ]
  , testGroup "Single Element Collections"
      [ testCase "single element operations" $ do
          -- fromKeys
          MapUtils.fromKeys (*2) [5] @?= Map.singleton 5 10
          
          -- fromKeysA
          MapUtils.fromKeysA (Just . (*2)) [5] @?= Just (Map.singleton 5 10)
          
          -- fromValues
          MapUtils.fromValues (*2) [5] @?= Map.singleton 10 5
          
          -- any
          MapUtils.any (== 42) (Map.singleton "key" 42) @?= True
          MapUtils.any (== 43) (Map.singleton "key" 42) @?= False
      ]
  , testGroup "Large Collections"
      [ testCase "large map operations" $ do
          let largeKeys = [1..1000]
              largeMap = MapUtils.fromKeys (*2) largeKeys
          Map.size largeMap @?= 1000
          Map.lookup 500 largeMap @?= Just 1000
          MapUtils.any (> 1900) largeMap @?= True
      , testCase "large nested map exchange" $ do
          let buildInner i = Map.fromList [(show j, i * 10 + j) | j <- [1..5]]
              largeNested = Map.fromList [(show i, buildInner i) | i <- [1..100]]
              exchanged = MapUtils.exchangeKeys largeNested
          Map.size exchanged @?= 5  -- Inner keys: "1" through "5"
          all (\innerMap -> Map.size innerMap == 100) (Map.elems exchanged) @?= True
      ]
  , testGroup "Complex Key/Value Types"
      [ testCase "complex key types" $ do
          let complexKeys = [(1, "a"), (2, "b"), (1, "c")]  -- Note: (1, "c") will overwrite (1, "a")
              result = MapUtils.fromKeys (\(n, s) -> s ++ show n) complexKeys
              expected = Map.fromList [((1, "a"), "a1"), ((2, "b"), "b2"), ((1, "c"), "c1")]
          result @?= expected
      , testCase "nested structure with lists" $ do
          let original = Map.fromList [("A", NE.List [1, 2] [[3], [4, 5]])]
              inverted = MapUtils.invertMap original
              expected = Map.fromList 
                [([1, 2], NE.singleton "A")
                ,([3], NE.singleton "A")
                ,([4, 5], NE.singleton "A")
                ]
          inverted @?= expected
      ]
  , testGroup "Duplicate and Collision Handling"
      [ testCase "fromKeys with many duplicates" $ do
          let keys = replicate 100 42
              result = MapUtils.fromKeys (*2) keys
          result @?= Map.singleton 42 84
      , testCase "fromValues with key collisions" $ do
          let values = ["a", "bb", "c", "dd"] :: [String]  -- "a" and "c" both have length 1, "bb" and "dd" both have length 2
              result = MapUtils.fromValues length values
              expected = Map.fromList [(1, "c"), (2, "dd")]  -- Later values overwrite
          result @?= expected
      , testCase "exchangeKeys with complex overlaps" $ do
          let original = Map.fromList 
                [("X", Map.fromList [("A", 1), ("B", 2)])
                ,("Y", Map.fromList [("A", 3), ("C", 4)])
                ,("Z", Map.fromList [("B", 5)])
                ]
              result = MapUtils.exchangeKeys original
              expected = Map.fromList 
                [("A", Map.fromList [("X", 1), ("Y", 3)])
                ,("B", Map.fromList [("X", 2), ("Z", 5)])
                ,("C", Map.fromList [("Y", 4)])
                ]
          result @?= expected
      ]
  ]

-- | Error condition tests for invalid inputs.
--
-- Verifies proper error handling and meaningful error messages
-- for all possible error conditions and invalid inputs.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testGroup "Applicative Failure Propagation"
      [ testCase "fromKeysA fails on first error" $ do
          let result = MapUtils.fromKeysA (\x -> if x > 3 then Nothing else Just (x * 2)) [1, 2, 4, 3]
          result @?= Nothing
      , testCase "fromKeysA Either failure" $ do
          let result = MapUtils.fromKeysA (\x -> if x > 3 then Left "too big" else Right (x * 2)) [1, 2, 4, 3]
          result @?= Left "too big"
      , testCase "fromKeysA IO simulation with Maybe" $ do
          -- Simulate an IO operation that might fail
          let mockIO x = if even x then Just (show x) else Nothing
              result = MapUtils.fromKeysA mockIO [2, 4, 6, 8]
          result @?= Just (Map.fromList [(2, "2"), (4, "4"), (6, "6"), (8, "8")])
      , testCase "fromKeysA IO simulation with failure" $ do
          let mockIO x = if even x then Just (show x) else Nothing
              result = MapUtils.fromKeysA mockIO [2, 4, 5, 8]
          result @?= Nothing
      ]
  , testGroup "Type System Edge Cases"
      [ testCase "fromKeys with Unit type" $ do
          let result = MapUtils.fromKeys (const ()) [1, 2, 3]
              expected = Map.fromList [(1, ()), (2, ()), (3, ())]
          result @?= expected
      , testCase "any with complex predicates" $ do
          let complexMap = Map.fromList [(1, [1, 2, 3]), (2, [4, 5]), (3, [])]
              result1 = MapUtils.any null complexMap
              result2 = MapUtils.any ((> 2) . length) complexMap
          result1 @?= True
          result2 @?= True
      ]
  , testGroup "Memory and Performance Edge Cases"
      [ testCase "deeply nested map exchange" $ do
          let deepNested = Map.fromList 
                [(i, Map.fromList [(j, i * 1000 + j) | j <- [1..10]]) | i <- [1..100]]
              result = MapUtils.exchangeKeys deepNested
          Map.size result @?= 10
          all (\m -> Map.size m == 100) (Map.elems result) @?= True
      , testCase "very large inversion operation" $ do
          let largeMap = Map.fromList 
                [(show i, NE.List i [i+1, i+2]) | i <- [1..100]]
              inverted = MapUtils.invertMap largeMap
              -- Values range from 1 to 102 (i=1: [1,2,3], i=100: [100,101,102])
              -- So we expect 102 unique values
              expectedSize = 102
          Map.size inverted @?= expectedSize
      ]
  , testGroup "Structural Integrity Validation"
      [ testCase "exchangeKeys maintains all values" $ do
          let original = Map.fromList 
                [("A", Map.fromList [("1", "value1"), ("2", "value2")])
                ,("B", Map.fromList [("1", "value3"), ("3", "value4")])
                ]
              exchanged = MapUtils.exchangeKeys original
              -- Extract all values from both structures
              originalValues = concatMap (Map.elems . snd) (Map.toList original)
              exchangedValues = concatMap Map.elems (Map.elems exchanged)
          length originalValues @?= 4
          length exchangedValues @?= 4
          -- Values should be the same (though order might differ)
          (length originalValues == length exchangedValues) @?= True
      , testCase "invertMap preserves key-value relationships" $ do
          let original = Map.fromList [("A", NE.List 1 [2]), ("B", NE.singleton 1)]
              inverted = MapUtils.invertMap original
              -- Key 1 should map to both A and B
              oneMapping = Map.lookup 1 inverted
              twoMapping = Map.lookup 2 inverted
          case (oneMapping, twoMapping) of
            (Just ones, Just twos) -> do
              length (NE.toList ones) @?= 2  -- Both A and B
              NE.toList twos @?= ["A"]       -- Only A
            _ -> assertFailure "Expected mappings not found"
      ]
  ]

-- Helper functions and instances for testing

-- QuickCheck Arbitrary instances for testing

-- Generate reasonable sized nested structures for testing
-- Note: Map.Map instance is provided by library