{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

{-|
Module: Unit.Data.IndexTest
Description: Comprehensive test suite for Data.Index module
Copyright: (c) 2024 Canopy Contributors
License: BSD-3-Clause

This module provides complete test coverage for all public functions,
edge cases, error conditions, and properties in Data.Index.

Coverage Target: ≥80% line coverage
Test Categories: Unit, Property, Edge Case, Error Condition

@since 0.19.1
-}
module Unit.Data.IndexTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import qualified Canopy.Data.Index as Index
import Canopy.Data.Index (ZeroBased, VerifiedList(..))

-- | Main test tree containing all Data.Index tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "Data.Index Tests"
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
  [ testGroup "Index Constants"
      [ testCase "first index is zero" $
          Index.toMachine Index.first @?= 0
      , testCase "second index is one" $
          Index.toMachine Index.second @?= 1
      , testCase "third index is two" $
          Index.toMachine Index.third @?= 2
      ]
  , testGroup "Index Operations"
      [ testCase "next increments index" $ do
          let start = Index.first
              next1 = Index.next start
              next2 = Index.next next1
          Index.toMachine next1 @?= 1
          Index.toMachine next2 @?= 2
      , testCase "toMachine extracts machine value" $ do
          Index.toMachine Index.first @?= 0
          Index.toMachine Index.second @?= 1
          Index.toMachine Index.third @?= 2
      , testCase "toHuman converts to one-based" $ do
          Index.toHuman Index.first @?= 1
          Index.toHuman Index.second @?= 2
          Index.toHuman Index.third @?= 3
      ]
  , testGroup "Indexed List Operations"
      [ testCase "indexedMap with positions" $ do
          let items = ["apple", "banana", "cherry"]
              result = Index.indexedMap (\i item -> show (Index.toHuman i) <> ": " <> item) items
          result @?= ["1: apple", "2: banana", "3: cherry"]
      , testCase "indexedMap with machine indices" $ do
          let items = [10, 20, 30]
              result = Index.indexedMap (\i x -> Index.toMachine i + x) items
          result @?= [10, 21, 32]
      , testCase "indexedMap empty list" $
          Index.indexedMap (\i x -> (i, x)) ([] :: [Int]) @?= []
      , testCase "indexedTraverse successful" $ do
          let items = [1, 2, 3]
              result = Index.indexedTraverse (\i x -> Just (Index.toMachine i + x)) items
          result @?= Just [1, 3, 5]
      , testCase "indexedTraverse with failure" $ do
          let items = [1, 2, 3]
              result = Index.indexedTraverse (\i x -> if Index.toMachine i == 1 then Nothing else Just x) items
          result @?= Nothing
      , testCase "indexedForA successful" $ do
          let items = ["a", "b"]
              result = Index.indexedForA items (\i val -> Just (show (Index.toHuman i) <> val))
          result @?= Just ["1a", "2b"]
      ]
  , testGroup "Verified Zipping"
      [ testCase "indexedZipWith matching lengths" $ do
          let listX = [1, 2, 3]
              listY = [10, 20, 30] :: [Int]
              result = Index.indexedZipWith (\i x y -> Index.toMachine i + x + y) listX listY
          case result of
            LengthMatch vals -> vals @?= [11, 23, 35]
            LengthMismatch _ _ -> assertFailure "Expected LengthMatch"
      , testCase "indexedZipWith mismatched lengths first longer" $ do
          let listX = [1, 2, 3]
              listY = [10, 20] :: [Int]
              result = Index.indexedZipWith (\_ x y -> x + y) listX listY
          case result of
            LengthMatch _ -> assertFailure "Expected LengthMismatch"
            LengthMismatch lenX lenY -> do
              lenX @?= 3
              lenY @?= 2
      , testCase "indexedZipWith mismatched lengths second longer" $ do
          let listX = [1, 2] :: [Int]
              listY = [10, 20, 30] :: [Int]
              result = Index.indexedZipWith (\_ x y -> x + y) listX listY
          case result of
            LengthMatch _ -> assertFailure "Expected LengthMismatch"
            LengthMismatch lenX lenY -> do
              lenX @?= 2
              lenY @?= 3
      , testCase "indexedZipWith empty lists" $ do
          let result = Index.indexedZipWith (\_ x y -> x + y) ([] :: [Int]) ([] :: [Int])
          case result of
            LengthMatch vals -> vals @?= []
            LengthMismatch _ _ -> assertFailure "Expected LengthMatch"
      , testCase "indexedZipWithA successful" $ do
          let listX = [1, 2] :: [Int]
              listY = [10, 20] :: [Int]
              result = Index.indexedZipWithA (\i x y -> Just (Index.toMachine i + x + y)) listX listY
          result @?= Just (LengthMatch [11, 23])
      , testCase "indexedZipWithA with effect failure" $ do
          let listX = [1, 2] :: [Int]
              listY = [10, 20] :: [Int]
              result = Index.indexedZipWithA (\i x y -> if Index.toMachine i == 1 then Nothing else Just (x + y)) listX listY
          result @?= Nothing
      , testCase "indexedZipWithA length mismatch" $ do
          let listX = [1, 2, 3]
              listY = [10, 20] :: [Int]
              result = Index.indexedZipWithA (\_ x y -> Just (x + y)) listX listY
          result @?= Just (LengthMismatch 3 2)
      ]
  ]

-- | Property-based tests for mathematical and logical operations.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with mathematical or logical operations.
propertyTests :: TestTree
propertyTests = testGroup "Property Tests"
  [ testProperty "next index increment" $ \n ->
      n >= 0 && n < maxBound ==>
      let idx = iterate Index.next Index.first !! n
          nextIdx = Index.next idx
      in Index.toMachine nextIdx == n + 1
  , testProperty "toHuman/toMachine relationship" $ \n ->
      n >= 0 ==>
      let idx = iterate Index.next Index.first !! n
      in Index.toHuman idx == Index.toMachine idx + 1
  , testProperty "indexedMap preserves length" $ \xs ->
      let result = Index.indexedMap (\_ x -> x * 2) (xs :: [Int])
      in length result == length xs
  , testProperty "indexedMap correct indices" $ \xs ->
      let indices = Index.indexedMap (\i _ -> Index.toMachine i) (xs :: [Int])
          expected = [0 .. length xs - 1]
      in indices == expected
  , testProperty "indexedZipWith equal lengths always match" $ \(NonEmpty xs) ->
      let ys = take (length xs) [1..] :: [Int]
       in case Index.indexedZipWith (\_ x y -> x + y) xs ys of
            LengthMatch result -> length result == length xs
            LengthMismatch _ _ -> False
  , testProperty "indexedZipWith unequal lengths always mismatch" $ \xs ys ->
      length xs /= length (ys :: [Int]) ==>
      case Index.indexedZipWith (\_ x y -> x + y) xs ys of
        LengthMatch _ -> False
        LengthMismatch lenX lenY -> lenX == length xs && lenY == length ys
  , testProperty "indexedTraverse composition" $ \xs ->
      let f i x = Just (Index.toMachine i + x)
          result1 = Index.indexedTraverse f (xs :: [Int])
          result2 = sequenceA (Index.indexedMap f xs)
      in result1 == result2
  ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testGroup "Empty Collections"
      [ testCase "indexedMap empty list" $
          Index.indexedMap (\i x -> (Index.toMachine i, x)) ([] :: [Int]) @?= []
      , testCase "indexedTraverse empty list" $
          Index.indexedTraverse (\i x -> Just (Index.toMachine i + x)) ([] :: [Int]) @?= Just []
      , testCase "indexedForA empty list" $
          Index.indexedForA ([] :: [Int]) (\i x -> Just (Index.toMachine i + x)) @?= Just []
      , testCase "indexedZipWith both empty" $ do
          let result = Index.indexedZipWith (\_ x y -> x + y) ([] :: [Int]) ([] :: [Int])
          case result of
            LengthMatch vals -> vals @?= []
            LengthMismatch _ _ -> assertFailure "Expected LengthMatch for empty lists"
      ]
  , testGroup "Single Element Collections"
      [ testCase "indexedMap single element" $ do
          let result = Index.indexedMap (\i x -> (Index.toMachine i, x)) [42]
          result @?= [(0, 42)]
      , testCase "indexedZipWith single elements" $ do
          let result = Index.indexedZipWith (\i x y -> (Index.toMachine i, x, y)) [1] [2]
          case result of
            LengthMatch vals -> vals @?= [(0, 1, 2)]
            LengthMismatch _ _ -> assertFailure "Expected LengthMatch"
      ]
  , testGroup "Large Collections"
      [ testCase "indexedMap large list" $ do
          let largeList = [1..1000] :: [Int]
              result = Index.indexedMap (\i x -> Index.toMachine i + x) largeList
              -- First few: (0+1, 1+2, 2+3, 3+4, ...) = [1, 3, 5, 7, ...]
              -- Last few: (997+998, 998+999, 999+1000) = [1995, 1997, 1999]
          length result @?= 1000
          take 10 result @?= [1, 3, 5, 7, 9, 11, 13, 15, 17, 19]
          drop 990 result @?= [1981, 1983, 1985, 1987, 1989, 1991, 1993, 1995, 1997, 1999]
      ]
  , testGroup "Maximum Index Values"
      [ testCase "large index values" $ do
          -- Test with reasonably large index values to avoid overflow
          let largeIdx = iterate Index.next Index.first !! 1000000
              nextLarge = Index.next largeIdx
          Index.toMachine nextLarge @?= 1000001
          Index.toHuman nextLarge @?= 1000002
      ]
  ]

-- | Error condition tests for invalid inputs.
--
-- Verifies proper error handling and meaningful error messages
-- for all possible error conditions and invalid inputs.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testGroup "Index Boundary Conditions"
      [ testCase "maximum safe index operations" $ do
          -- Test with a reasonably large index value
          let largeIndex = iterate Index.next Index.first !! 10000
              nextIdx = Index.next largeIndex
          Index.toMachine largeIndex @?= 10000
          Index.toMachine nextIdx @?= 10001
          Index.toHuman largeIndex @?= 10001
      ]
  , testGroup "VerifiedList Error Reporting"
      [ testCase "length mismatch reports correct lengths" $ do
          let xs = [1, 2, 3, 4, 5] :: [Int]
              ys = [1, 2] :: [Int]
              result = Index.indexedZipWith (\_ x y -> x + y) xs ys
          case result of
            LengthMatch _ -> assertFailure "Expected LengthMismatch"
            LengthMismatch lenX lenY -> do
              lenX @?= length xs
              lenY @?= length ys
      ]
  , testGroup "Traversal Failure Propagation"
      [ testCase "indexedTraverse failure stops computation" $ do
          let items = [1, 2, 3, 4, 5]
              -- Fail on second element (index 1)
              failingFunc i x = if Index.toMachine i == 1 then Nothing else Just (x * 2)
              result = Index.indexedTraverse failingFunc items
          result @?= Nothing
      , testCase "indexedZipWithA preserves applicative failures" $ do
          let xs = [1, 2] :: [Int]
              ys = [3, 4] :: [Int]
              -- Fail on second element (index 1)
              failingFunc i x y = if Index.toMachine i == 1 then Nothing else Just (x + y)
              result = Index.indexedZipWithA failingFunc xs ys
          result @?= (Nothing :: Maybe (VerifiedList Int))
      ]
  ]

-- Helper instances for testing

-- Note: Eq and Show instances for VerifiedList are provided by Data.Index

-- QuickCheck Arbitrary instances for testing

-- Note: ZeroBased constructor is not exported, so we'll create instances using exported functions
instance Arbitrary ZeroBased where
  arbitrary = do
    n <- choose (0, 10000)
    return $ iterate Index.next Index.first !! n
  shrink idx 
    | Index.toMachine idx == 0 = []
    | otherwise = [iterate Index.next Index.first !! (Index.toMachine idx - 1)]