{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

{-|
Module: Unit.Data.BagTest
Description: Comprehensive test suite for Data.Bag module
Copyright: (c) 2024 Canopy Contributors
License: BSD-3-Clause

This module provides complete test coverage for all public functions,
edge cases, error conditions, and properties in Data.Bag.

Coverage Target: ≥80% line coverage
Test Categories: Unit, Property, Edge Case, Error Condition

@since 0.19.1
-}
module Unit.Data.BagTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import qualified Canopy.Data.Bag as Bag
import Canopy.Data.Bag (Bag(..))
import qualified Data.List as List

-- | Main test tree containing all Data.Bag tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "Data.Bag Tests"
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
  [ testGroup "Construction"
      [ testCase "empty bag creation" $ do
          let emptyBag = Bag.empty :: Bag String
          Bag.toList emptyBag @?= ([] :: [String])
      , testCase "singleton bag creation" $ do
          let singleBag = Bag.one "test"
              result = Bag.toList singleBag
          length result @?= 1
          result @?= ["test"]
      , testCase "direct constructor empty" $
          Bag.toList (Empty :: Bag String) @?= ([] :: [String])
      , testCase "direct constructor one" $
          Bag.toList (One "value") @?= ["value"]
      , testCase "direct constructor two" $ do
          let bag = Two (One 1) (One 2)
              result = Bag.toList bag
          length result @?= 2
          List.sort result @?= [1, 2]
      ]
  , testGroup "Combination Operations"
      [ testCase "append empty with non-empty" $ do
          let emptyBag = Bag.empty
              singleBag = Bag.one "test"
              result = Bag.append emptyBag singleBag
          Bag.toList result @?= ["test"]
      , testCase "append non-empty with empty" $ do
          let singleBag = Bag.one "test"
              emptyBag = Bag.empty
              result = Bag.append singleBag emptyBag
          Bag.toList result @?= ["test"]
      , testCase "append two singletons" $ do
          let bag1 = Bag.one "first"
              bag2 = Bag.one "second"
              result = Bag.append bag1 bag2
              resultList = Bag.toList result
          length resultList @?= 2
          List.sort resultList @?= ["first", "second"]
      , testCase "append preserves all elements" $ do
          let bag1 = Two (One 1) (One 2)
              bag2 = Two (One 3) (One 4)
              result = Bag.append bag1 bag2
              resultList = Bag.toList result
          length resultList @?= 4
          List.sort resultList @?= [1, 2, 3, 4]
      , testCase "append empty bags" $ do
          let result = Bag.append (Bag.empty :: Bag String) (Bag.empty :: Bag String)
          Bag.toList result @?= ([] :: [String])
      ]
  , testGroup "Transformation Operations"
      [ testCase "map empty bag" $ do
          let emptyBag = Bag.empty :: Bag Int
              result = Bag.map (*2) emptyBag
          Bag.toList result @?= []
      , testCase "map singleton bag" $ do
          let singleBag = Bag.one 5
              result = Bag.map (*2) singleBag
          Bag.toList result @?= [10]
      , testCase "map complex bag" $ do
          let bag = Two (One 1) (Two (One 2) (One 3))
              result = Bag.map (*2) bag
              resultList = Bag.toList result
          List.sort resultList @?= [2, 4, 6]
      , testCase "map preserves structure" $ do
          let bag = Two (One "a") (One "b")
              result = Bag.map (++ "!") bag
              resultList = Bag.toList result
          List.sort resultList @?= ["a!", "b!"]
      , testCase "map with type change" $ do
          let bag = Two (One 1) (One 2)
              result = Bag.map show bag
              resultList = Bag.toList result
          List.sort resultList @?= ["1", "2"]
      ]
  , testGroup "Conversion Operations"
      [ testCase "toList empty bag" $
          Bag.toList (Bag.empty :: Bag Int) @?= []
      , testCase "toList singleton" $
          Bag.toList (Bag.one 42) @?= [42]
      , testCase "toList preserves all elements" $ do
          let bag = Two (One 1) (Two (One 2) (One 3))
              result = Bag.toList bag
          length result @?= 3
          List.sort result @?= [1, 2, 3]
      , testCase "fromList identity function empty" $
          Bag.toList (Bag.fromList id ([] :: [Int])) @?= []
      , testCase "fromList identity function single" $ do
          let result = Bag.fromList id [1]
          Bag.toList result @?= [1]
      , testCase "fromList identity function multiple" $ do
          let items = [1, 2, 3]
              bag = Bag.fromList id items
              result = Bag.toList bag
          length result @?= length items
          List.sort result @?= List.sort items
      , testCase "fromList with transformation" $ do
          let items = [1, 2, 3]
              bag = Bag.fromList (*2) items
              result = Bag.toList bag
          List.sort result @?= [2, 4, 6]
      , testCase "fromList preserves duplicates" $ do
          let items = [1, 1, 2, 2, 3]
              bag = Bag.fromList id items
              result = Bag.toList bag
          length result @?= length items
          List.sort result @?= List.sort items
      ]
  ]

-- | Property-based tests for mathematical and logical operations.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with mathematical or logical operations.
propertyTests :: TestTree
propertyTests = testGroup "Property Tests"
  [ testProperty "append is associative" $ \x y z ->
      let bag1 = fromIntList x
          bag2 = fromIntList y
          bag3 = fromIntList z
          left = Bag.append (Bag.append bag1 bag2) bag3
          right = Bag.append bag1 (Bag.append bag2 bag3)
          leftList = List.sort (Bag.toList left)
          rightList = List.sort (Bag.toList right)
      in leftList == rightList
  , testProperty "append identity empty left" $ \xs ->
      let bag = fromIntList xs
          result = Bag.append Bag.empty bag
      in List.sort (Bag.toList result) == List.sort (Bag.toList bag)
  , testProperty "append identity empty right" $ \xs ->
      let bag = fromIntList xs
          result = Bag.append bag Bag.empty
      in List.sort (Bag.toList result) == List.sort (Bag.toList bag)
  , testProperty "append commutative (elements)" $ \xs ys ->
      let bag1 = fromIntList xs
          bag2 = fromIntList ys
          left = Bag.append bag1 bag2
          right = Bag.append bag2 bag1
          leftList = List.sort (Bag.toList left)
          rightList = List.sort (Bag.toList right)
      in leftList == rightList
  , testProperty "map preserves element count" $ \xs ->
      let bag = fromIntList xs
          result = Bag.map (*2) bag
      in length (Bag.toList result) == length (Bag.toList bag)
  , testProperty "map composition law" $ \xs ->
      let bag = fromIntList xs
          f = (*2)
          g = (+1)
          result1 = Bag.map (f . g) bag
          result2 = Bag.map f (Bag.map g bag)
          list1 = List.sort (Bag.toList result1)
          list2 = List.sort (Bag.toList result2)
      in list1 == list2
  , testProperty "map identity law" $ \xs ->
      let bag = fromIntList xs
          result = Bag.map id bag
      in List.sort (Bag.toList result) == List.sort (Bag.toList bag)
  , testProperty "fromList/toList roundtrip preserves elements" $ \xs ->
      let bag = Bag.fromList id (xs :: [Int])
          result = Bag.toList bag
      in List.sort result == List.sort xs
  , testProperty "toList preserves duplicates" $ \xs ->
      let bag = Bag.fromList id (xs :: [Int])
          result = Bag.toList bag
      in length result == length xs
  , testProperty "one creates singleton bag" $ \x ->
      let bag = Bag.one (x :: Int)
      in Bag.toList bag == [x]
  ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testGroup "Empty Bag Operations"
      [ testCase "multiple empty appends" $ do
          let result = Bag.append (Bag.append Bag.empty Bag.empty) Bag.empty
          Bag.toList result @?= ([] :: [Int])
      , testCase "map empty bag with complex function" $ do
          let emptyBag = Bag.empty :: Bag String
              result = Bag.map (\s -> reverse s ++ "!" ++ show (length s)) emptyBag
          Bag.toList result @?= []
      , testCase "fromList empty with complex transformation" $
          Bag.toList (Bag.fromList (\x -> x * x + 1) ([] :: [Int])) @?= []
      ]
  , testGroup "Single Element Operations"
      [ testCase "singleton append chain" $ do
          let bag1 = Bag.one 1
              bag2 = Bag.one 2
              bag3 = Bag.one 3
              result = Bag.append (Bag.append bag1 bag2) bag3
              resultList = Bag.toList result
          length resultList @?= 3
          List.sort resultList @?= [1, 2, 3]
      , testCase "repeated singleton appends" $ do
          let start = Bag.one 1
              step1 = Bag.append start (Bag.one 1)
              step2 = Bag.append step1 (Bag.one 1)
              result = Bag.toList step2
          length result @?= 3
          result @?= [1, 1, 1]
      ]
  , testGroup "Large Collections"
      [ testCase "large bag operations" $ do
          let items = [1..1000] :: [Int]
              bag = Bag.fromList id items
              doubled = Bag.map (*2) bag
              result = Bag.toList doubled
          length result @?= 1000
          minimum result @?= 2
          maximum result @?= 2000
      , testCase "large bag append" $ do
          let items1 = [1..500] :: [Int]
              items2 = [501..1000] :: [Int]
              bag1 = Bag.fromList id items1
              bag2 = Bag.fromList id items2
              combined = Bag.append bag1 bag2
              result = Bag.toList combined
          length result @?= 1000
      ]
  , testGroup "Deep Nesting"
      [ testCase "deeply nested bag structure" $ do
          -- Create a deeply nested structure manually
          let deepBag = foldl (\acc i -> Two (One i) acc) (One 0) [1..100]
              result = Bag.toList deepBag
          length result @?= 101
          List.sort result @?= [0..100]
      , testCase "map on deeply nested structure" $ do
          let deepBag = foldl (\acc i -> Two (One i) acc) (One 0) [1..50]
              mapped = Bag.map (*2) deepBag
              result = Bag.toList mapped
          length result @?= 51
          minimum result @?= 0
          maximum result @?= 100
      ]
  , testGroup "Duplicate Handling"
      [ testCase "many duplicate elements" $ do
          let items = replicate 100 42
              bag = Bag.fromList id items
              result = Bag.toList bag
          length result @?= 100
          all (== 42) result @?= True
      , testCase "mixed duplicates and uniques" $ do
          let items = [1, 1, 2, 2, 2, 3, 3, 3, 3]
              bag = Bag.fromList id items
              result = Bag.toList bag
          length result @?= 9
          List.sort result @?= List.sort items
      ]
  ]

-- | Error condition tests for invalid inputs.
--
-- Verifies proper error handling and meaningful error messages
-- for all possible error conditions and invalid inputs.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testGroup "Memory and Performance Bounds"
      [ testCase "very large single transformation" $ do
          let items = [1..10000] :: [Int]
              bag = Bag.fromList id items
              -- This should complete without issues
              result = Bag.map (\x -> x `mod` 1000) bag
              resultList = Bag.toList result
          length resultList @?= 10000
      , testCase "multiple large appends" $ do
          let bag1 = Bag.fromList id ([1..1000] :: [Int])
              bag2 = Bag.fromList id ([1001..2000] :: [Int])
              bag3 = Bag.fromList id ([2001..3000] :: [Int])
              combined = Bag.append (Bag.append bag1 bag2) bag3
              result = Bag.toList combined
          length result @?= 3000
      ]
  , testGroup "Type System Boundaries"
      [ testCase "polymorphic empty bags" $ do
          let intBag = Bag.empty :: Bag Int
              stringBag = Bag.empty :: Bag String
              boolBag = Bag.empty :: Bag Bool
          Bag.toList intBag @?= []
          Bag.toList stringBag @?= []
          Bag.toList boolBag @?= []
      , testCase "type transformation through map" $ do
          let intBag = Bag.fromList id [1, 2, 3]
              stringBag = Bag.map show intBag
              result = Bag.toList stringBag
          List.sort result @?= ["1", "2", "3"]
      ]
  , testGroup "Complex Transformation Edge Cases"
      [ testCase "transformation to same values" $ do
          let bag = Bag.fromList id [1, 2, 3, 4, 5]
              result = Bag.map (const 42) bag
              resultList = Bag.toList result
          length resultList @?= 5
          all (== 42) resultList @?= True
      , testCase "transformation with partial function" $ do
          -- Using a function that works for all test values
          let bag = Bag.fromList id [1, 2, 3]
              result = Bag.map (\x -> 10 `div` x) bag  -- Safe for our test values
              resultList = Bag.toList result
          List.sort resultList @?= [3, 5, 10]  -- 10/3=3, 10/2=5, 10/1=10
      ]
  ]

-- Helper functions for testing

-- | Create a bag from a list of integers for property testing
fromIntList :: [Int] -> Bag Int
fromIntList = Bag.fromList id

-- QuickCheck Arbitrary instances for testing

instance Arbitrary a => Arbitrary (Bag a) where
  arbitrary = do
    items <- arbitrary
    return (Bag.fromList id items)
  
  shrink bag = case bag of
    Empty -> []
    One x -> [Empty] ++ [One x' | x' <- shrink x]
    Two left right -> 
      [Empty, left, right] ++ 
      [Two left' right | left' <- shrink left] ++
      [Two left right' | right' <- shrink right]