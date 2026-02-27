{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

{-|
Module: Unit.Data.NonEmptyListTest
Description: Comprehensive test suite for Data.NonEmptyList module
Copyright: (c) 2024 Canopy Contributors
License: BSD-3-Clause

This module provides complete test coverage for all public functions,
edge cases, error conditions, and properties in Data.NonEmptyList.

Coverage Target: ≥80% line coverage
Test Categories: Unit, Property, Edge Case, Error Condition

@since 0.19.1
-}
module Unit.Data.NonEmptyListTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import qualified Canopy.Data.NonEmptyList as NEL
import Canopy.Data.NonEmptyList (List(..))
import qualified Data.List as List

-- | Main test tree containing all Data.NonEmptyList tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "Data.NonEmptyList Tests"
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
      [ testCase "singleton creation" $ do
          let single = NEL.singleton "test"
          NEL.head single @?= "test"
          NEL.toList single @?= ["test"]
      , testCase "direct constructor single element" $ do
          let single = List 42 []
          NEL.head single @?= 42
          NEL.toList single @?= [42]
      , testCase "direct constructor multiple elements" $ do
          let multiple = List 1 [2, 3, 4]
          NEL.head multiple @?= 1
          NEL.toList multiple @?= [1, 2, 3, 4]
      ]
  , testGroup "Element Access"
      [ testCase "head of singleton" $
          NEL.head (NEL.singleton "test") @?= "test"
      , testCase "head of multiple elements" $
          NEL.head (List 1 [2, 3]) @?= 1
      , testCase "head never fails" $ do
          -- Test various non-empty lists
          NEL.head (List "a" []) @?= "a"
          NEL.head (List 'x' ['y', 'z']) @?= 'x'
          NEL.head (List True [False]) @?= True
      ]
  , testGroup "Conversion"
      [ testCase "toList singleton" $
          NEL.toList (NEL.singleton 42) @?= [42]
      , testCase "toList multiple elements" $
          NEL.toList (List 1 [2, 3, 4]) @?= [1, 2, 3, 4]
      , testCase "toList preserves order" $ do
          let original = [5, 4, 3, 2, 1]
              nel = List 5 [4, 3, 2, 1]
          NEL.toList nel @?= original
      , testCase "toList always non-empty" $ do
          let nel1 = NEL.singleton "test"
              nel2 = List 1 [2, 3]
          NEL.toList nel1 @?= ["test"]
          NEL.toList nel2 @?= [1, 2, 3]
      ]
  , testGroup "Combination"
      [ testCase "append two singletons" $ do
          let nel1 = NEL.singleton 1
              nel2 = NEL.singleton 2
              result = NEL.append nel1 nel2
          NEL.toList result @?= [1, 2]
          NEL.head result @?= 1
      , testCase "append singleton to multiple" $ do
          let nel1 = NEL.singleton 1
              nel2 = List 2 [3, 4]
              result = NEL.append nel1 nel2
          NEL.toList result @?= [1, 2, 3, 4]
          NEL.head result @?= 1
      , testCase "append multiple to singleton" $ do
          let nel1 = List 1 [2, 3]
              nel2 = NEL.singleton 4
              result = NEL.append nel1 nel2
          NEL.toList result @?= [1, 2, 3, 4]
          NEL.head result @?= 1
      , testCase "append multiple to multiple" $ do
          let nel1 = List 1 [2, 3]
              nel2 = List 4 [5, 6]
              result = NEL.append nel1 nel2
          NEL.toList result @?= [1, 2, 3, 4, 5, 6]
          NEL.head result @?= 1
      , testCase "append preserves head of first list" $ do
          let nel1 = List "first" ["second"]
              nel2 = List "third" ["fourth"]
              result = NEL.append nel1 nel2
          NEL.head result @?= "first"
      ]
  , testGroup "Sorting"
      [ testCase "sortBy identity singleton" $ do
          let nel = NEL.singleton 42
              result = NEL.sortBy id nel
          NEL.toList result @?= [42]
      , testCase "sortBy identity already sorted" $ do
          let nel = List 1 [2, 3, 4]
              result = NEL.sortBy id nel
          NEL.toList result @?= [1, 2, 3, 4]
      , testCase "sortBy identity reverse order" $ do
          let nel = List 4 [3, 2, 1]
              result = NEL.sortBy id nel
          NEL.toList result @?= [1, 2, 3, 4]
      , testCase "sortBy length strings" $ do
          let nel = List "abc" ["a", "ab"] :: List String
              result = NEL.sortBy length nel
          NEL.toList result @?= ["a", "ab", "abc"]
      , testCase "sortBy custom function" $ do
          let nel = List 3 [1, 4, 2]
              result = NEL.sortBy negate nel  -- Sort by negative (descending)
          NEL.toList result @?= [4, 3, 2, 1]
      , testCase "sortBy with duplicates" $ do
          let nel = List 2 [1, 3, 2, 1]
              result = NEL.sortBy id nel
          NEL.toList result @?= [1, 1, 2, 2, 3]
      ]
  ]

-- | Property-based tests for mathematical and logical operations.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with mathematical or logical operations.
propertyTests :: TestTree
propertyTests = testGroup "Property Tests"
  [ testProperty "singleton creates single-element list" $ \x ->
      let nel = NEL.singleton (x :: Int)
      in NEL.toList nel == [x] && NEL.head nel == x
  , testProperty "head is always first element" $ \x xs ->
      let nel = List (x :: Int) xs
      in NEL.head nel == x
  , testProperty "toList always non-empty" $ \x xs ->
      let nel = List (x :: Int) xs
          result = NEL.toList nel
      in not (null result) && head result == x
  , testProperty "toList preserves length" $ \x xs ->
      let nel = List (x :: Int) xs
          result = NEL.toList nel
      in length result == 1 + length xs
  , testProperty "append preserves all elements" $ \x1 xs1 x2 xs2 ->
      let nel1 = List (x1 :: Int) xs1
          nel2 = List (x2 :: Int) xs2
          result = NEL.append nel1 nel2
          resultList = NEL.toList result
          expectedList = NEL.toList nel1 ++ NEL.toList nel2
      in resultList == expectedList
  , testProperty "append preserves head of first" $ \x1 xs1 x2 xs2 ->
      let nel1 = List (x1 :: Int) xs1
          nel2 = List (x2 :: Int) xs2
          result = NEL.append nel1 nel2
      in NEL.head result == NEL.head nel1
  , testProperty "append is associative (elements)" $ \x1 xs1 x2 xs2 x3 xs3 ->
      let nel1 = List (x1 :: Int) xs1
          nel2 = List (x2 :: Int) xs2
          nel3 = List (x3 :: Int) xs3
          left = NEL.append (NEL.append nel1 nel2) nel3
          right = NEL.append nel1 (NEL.append nel2 nel3)
      in NEL.toList left == NEL.toList right
  , testProperty "sortBy preserves all elements" $ \x xs ->
      let nel = List (x :: Int) xs
          result = NEL.sortBy id nel
          originalList = NEL.toList nel
          sortedList = NEL.toList result
      in List.sort originalList == List.sort sortedList
  , testProperty "sortBy produces sorted output" $ \x xs ->
      let nel = List (x :: Int) xs
          result = NEL.sortBy id nel
          sortedList = NEL.toList result
      in sortedList == List.sort sortedList
  , testProperty "sortBy singleton unchanged" $ \x ->
      let nel = NEL.singleton (x :: Int)
          result = NEL.sortBy id nel
      in NEL.toList result == NEL.toList nel
  , testProperty "Functor law: fmap id = id" $ \x xs ->
      let nel = List (x :: Int) xs
      in fmap id nel == nel
  , testProperty "Functor law: composition" $ \x xs ->
      let nel = List (x :: Int) xs
          f = (*2)
          g = (+1)
      in fmap (f . g) nel == fmap f (fmap g nel)
  ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testGroup "Single Element Lists"
      [ testCase "singleton operations chain" $ do
          let start = NEL.singleton 1
              result = NEL.append start (NEL.singleton 2)
          NEL.head result @?= 1
          length (NEL.toList result) @?= 2
      , testCase "singleton fmap" $ do
          let single = NEL.singleton 5
              result = fmap (*2) single
          NEL.toList result @?= [10]
      , testCase "singleton sortBy" $ do
          let single = NEL.singleton "test" :: List String
              result = NEL.sortBy length single
          NEL.toList result @?= ["test"]
      ]
  , testGroup "Large Lists"
      [ testCase "large list operations" $ do
          let largeList = [2..1000]
              nel = List 1 largeList
              result = NEL.sortBy id nel
              sortedList = NEL.toList result
          length sortedList @?= 1000
          head sortedList @?= 1
          last sortedList @?= 1000
      , testCase "large list append" $ do
          let left = List 1 [2..500]
              right = List 501 [502..1000]
              result = NEL.append left right
              resultList = NEL.toList result
          length resultList @?= 1000
          head resultList @?= 1
          last resultList @?= 1000
      ]
  , testGroup "Duplicate Elements"
      [ testCase "many duplicates" $ do
          let nel = List 1 (replicate 100 1)
              result = NEL.sortBy id nel
              resultList = NEL.toList result
          length resultList @?= 101
          all (== 1) resultList @?= True
      , testCase "mixed duplicates and sorting" $ do
          let nel = List 3 [1, 3, 2, 1, 3]
              result = NEL.sortBy id nel
              resultList = NEL.toList result
          resultList @?= [1, 1, 2, 3, 3, 3]
      ]
  , testGroup "Complex Type Transformations"
      [ testCase "fmap type transformation" $ do
          let nel = List 1 [2, 3]
              result = fmap show nel
          NEL.toList result @?= ["1", "2", "3"]
      , testCase "complex sortBy key function" $ do
          let nel = List (1, "b") [(3, "a"), (2, "c")]
              result = NEL.sortBy fst nel
          NEL.toList result @?= [(1, "b"), (2, "c"), (3, "a")]
      ]
  , testGroup "Extreme Values"
      [ testCase "maximum integer values" $ do
          let nel = List maxBound [maxBound - 1, maxBound - 2] :: List Int
              result = NEL.sortBy id nel
              resultList = NEL.toList result
          resultList @?= [maxBound - 2, maxBound - 1, maxBound]
      , testCase "minimum integer values" $ do
          let nel = List minBound [minBound + 1, minBound + 2] :: List Int
              result = NEL.sortBy id nel
              resultList = NEL.toList result
          resultList @?= [minBound, minBound + 1, minBound + 2]
      ]
  ]

-- | Error condition tests for invalid inputs.
--
-- Verifies proper error handling and meaningful error messages
-- for all possible error conditions and invalid inputs.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testGroup "Type Safety Verification"
      [ testCase "head is always safe" $ do
          -- These should never fail at runtime due to type safety
          let nel1 = NEL.singleton ()
              nel2 = List "test" []
              nel3 = List 1 [2, 3, 4, 5]
          NEL.head nel1 @?= ()
          NEL.head nel2 @?= "test"
          NEL.head nel3 @?= 1
      , testCase "toList always produces non-empty result" $ do
          let nel1 = NEL.singleton 42
              nel2 = List "a" ["b", "c"]
          NEL.toList nel1 @?= [42]
          NEL.toList nel2 @?= ["a", "b", "c"]
      ]
  , testGroup "Memory and Performance Bounds"
      [ testCase "very large lists handle correctly" $ do
          let largeList = [1..10000] :: [Int]
              nel = List 0 largeList
              sorted = NEL.sortBy id nel
          length (NEL.toList sorted) @?= 10001
          NEL.head sorted @?= 0
      , testCase "deeply nested append operations" $ do
          let start = NEL.singleton 1
              result = foldl (\acc i -> NEL.append acc (NEL.singleton i)) start [2..100]
          length (NEL.toList result) @?= 100
          NEL.head result @?= 1
      ]
  , testGroup "Functor Law Verification"
      [ testCase "fmap preserves structure" $ do
          let nel = List 1 [2, 3, 4]
              result = fmap (*2) nel
          case result of
            List h t -> do
              h @?= 2
              t @?= [4, 6, 8]
      , testCase "fmap with partial function coverage" $ do
          -- Using safe operations for our test data
          let nel = List 1 [2, 4]  -- Avoiding division by zero
              result = fmap (\x -> 10 `div` x) nel
          NEL.toList result @?= [10, 5, 2]  -- 10/1=10, 10/2=5, 10/4=2
      ]
  , testGroup "Traversable and Foldable Edge Cases"
      [ testCase "traverse with effect success" $ do
          let nel = List 1 [2, 3]
              result = traverse (\x -> Just (x * 2)) nel
          result @?= Just (List 2 [4, 6])
      , testCase "traverse with effect failure" $ do
          let nel = List 1 [2, 3]
              result = traverse (\x -> if x == 2 then Nothing else Just (x * 2)) nel
          result @?= Nothing
      , testCase "foldl1 on singleton" $ do
          let nel = NEL.singleton 42
              result = foldl1 (+) nel
          result @?= 42
      , testCase "foldl1 on multiple elements" $ do
          let nel = List 1 [2, 3, 4]
              result = foldl1 (+) nel
          result @?= 10  -- 1+2+3+4
      ]
  ]

-- QuickCheck Arbitrary instances for testing

instance Arbitrary a => Arbitrary (List a) where
  arbitrary = do
    x <- arbitrary
    xs <- arbitrary
    return (List x xs)
  
  shrink (List x xs) = 
    [List x' xs | x' <- shrink x] ++
    [List x xs' | xs' <- shrink xs]