{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

{-|
Module: Unit.Data.OneOrMoreTest
Description: Comprehensive test suite for Data.OneOrMore module
Copyright: (c) 2024 Canopy Contributors
License: BSD-3-Clause

This module provides complete test coverage for all public functions,
edge cases, error conditions, and properties in Data.OneOrMore.

Coverage Target: ≥80% line coverage
Test Categories: Unit, Property, Edge Case, Error Condition

@since 0.19.1
-}
module Unit.Data.OneOrMoreTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import qualified Data.OneOrMore as OOM
import Data.OneOrMore (OneOrMore(..))

-- | Main test tree containing all Data.OneOrMore tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "Data.OneOrMore Tests"
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
      [ testCase "one creates single element" $ do
          let result = OOM.one "test"
          case result of
            One val -> val @?= "test"
            More _ _ -> assertFailure "Expected One constructor"
      , testCase "more combines two elements" $ do
          let left = OOM.one 1
              right = OOM.one 2
              result = OOM.more left right
          case result of
            More l r -> do
              l @?= left
              r @?= right
            One _ -> assertFailure "Expected More constructor"
      , testCase "nested more operations" $ do
          let a = OOM.one 1
              b = OOM.one 2
              c = OOM.one 3
              combined1 = OOM.more a b
              combined2 = OOM.more combined1 c
          case combined2 of
            More (More _ _) (One 3) -> return ()
            _ -> assertFailure "Expected nested More structure"
      ]
  , testGroup "Transformation"
      [ testCase "map single element" $ do
          let original = OOM.one 5
              result = OOM.map (*2) original
          case result of
            One val -> val @?= 10
            More _ _ -> assertFailure "Expected One after mapping One"
      , testCase "map combined elements" $ do
          let left = OOM.one 1
              right = OOM.one 2
              combined = OOM.more left right
              result = OOM.map (*3) combined
          case result of
            More (One 3) (One 6) -> return ()
            _ -> assertFailure "Expected More (One 3) (One 6)"
      , testCase "map preserves structure" $ do
          let original = OOM.more (OOM.one "a") (OOM.more (OOM.one "b") (OOM.one "c"))
              result = OOM.map (++ "!") original
          case result of
            More (One "a!") (More (One "b!") (One "c!")) -> return ()
            _ -> assertFailure "Structure not preserved during mapping"
      , testCase "map type transformation" $ do
          let original = OOM.more (OOM.one 1) (OOM.one 2)
              result = OOM.map show original
          case result of
            More (One "1") (One "2") -> return ()
            _ -> assertFailure "Type transformation failed"
      ]
  , testGroup "Deconstruction"
      [ testCase "destruct single element" $ do
          let original = OOM.one "single"
              result = OOM.destruct (\h t -> h : t) original
          result @?= ["single"]
      , testCase "destruct two elements" $ do
          let original = OOM.more (OOM.one 1) (OOM.one 2)
              result = OOM.destruct (\h t -> h : t) original
          result @?= [1, 2]
      , testCase "destruct three elements" $ do
          let original = OOM.more (OOM.one 'a') (OOM.more (OOM.one 'b') (OOM.one 'c'))
              result = OOM.destruct (\h t -> h : t) original
          result @?= ['a', 'b', 'c']
      , testCase "destruct with custom function" $ do
          let original = OOM.more (OOM.one 1) (OOM.one 2)
              result = OOM.destruct (\h t -> (h, t)) original
          result @?= (1, [2])
      , testCase "destruct complex structure" $ do
          let original = OOM.more 
                          (OOM.more (OOM.one 1) (OOM.one 2))
                          (OOM.more (OOM.one 3) (OOM.one 4))
              result = OOM.destruct (\h t -> h : t) original
          result @?= [1, 2, 3, 4]
      , testCase "destruct left-to-right order" $ do
          let original = OOM.more (OOM.one "first") 
                                  (OOM.more (OOM.one "second") (OOM.one "third"))
              result = OOM.destruct (\h t -> h : t) original
          result @?= ["first", "second", "third"]
      ]
  , testGroup "Element Access"
      [ testCase "getFirstTwo from two singles" $ do
          let left = OOM.one "a"
              right = OOM.one "b"
              result = OOM.getFirstTwo left right
          result @?= ("a", "b")
      , testCase "getFirstTwo left complex right simple" $ do
          let left = OOM.more (OOM.one 1) (OOM.one 2)
              right = OOM.one 10
              result = OOM.getFirstTwo left right
          result @?= (1, 10)
      , testCase "getFirstTwo left simple right complex" $ do
          let left = OOM.one 'x'
              right = OOM.more (OOM.one 'y') (OOM.one 'z')
              result = OOM.getFirstTwo left right
          result @?= ('x', 'y')
      , testCase "getFirstTwo both complex" $ do
          let left = OOM.more (OOM.one 1) (OOM.one 2)
              right = OOM.more (OOM.one 10) (OOM.one 20)
              result = OOM.getFirstTwo left right
          result @?= (1, 10)
      , testCase "getFirstTwo deeply nested left" $ do
          let left = OOM.more (OOM.more (OOM.one 1) (OOM.one 2)) (OOM.one 3)
              right = OOM.one 100
              result = OOM.getFirstTwo left right
          result @?= (1, 100)
      ]
  ]

-- | Property-based tests for mathematical and logical operations.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with mathematical or logical operations.
propertyTests :: TestTree
propertyTests = testGroup "Property Tests"
  [ testProperty "one creates single-element collection" $ \x ->
      let result = OOM.one (x :: Int)
      in case result of
           One val -> val == x
           More _ _ -> False
  , testProperty "more preserves both inputs" $ \x y ->
      let left = OOM.one (x :: Int)
          right = OOM.one (y :: Int)
          result = OOM.more left right
      in case result of
           More l r -> l == left && r == right
           One _ -> False
  , testProperty "map preserves element count" $ \oom ->
      let original = getElements (oom :: OneOrMore Int)
          mapped = getElements (OOM.map (*2) oom)
      in length original == length mapped
  , testProperty "map applies function to all elements" $ \oom ->
      let original = getElements (oom :: OneOrMore Int)
          mapped = getElements (OOM.map (*2) oom)
      in mapped == map (*2) original
  , testProperty "map composition law" $ \oom ->
      let f = (*2)
          g = (+1)
          result1 = OOM.map (f . g) (oom :: OneOrMore Int)
          result2 = OOM.map f (OOM.map g oom)
      in getElements result1 == getElements result2
  , testProperty "map identity law" $ \oom ->
      let original = oom :: OneOrMore Int
          mapped = OOM.map id original
      in getElements original == getElements mapped
  , testProperty "destruct preserves all elements" $ \oom ->
      let elements = getElements (oom :: OneOrMore Int)
          reconstructed = OOM.destruct (\h t -> h : t) oom
      in elements == reconstructed
  , testProperty "destruct head is first element" $ \oom ->
      let elements = getElements (oom :: OneOrMore Int)
          (h, _) = OOM.destruct (\head tail -> (head, tail)) oom
      in h == head elements
  , testProperty "getFirstTwo gets leftmost elements" $ \oom1 oom2 ->
      let elem1 = head (getElements (oom1 :: OneOrMore Int))
          elem2 = head (getElements (oom2 :: OneOrMore Int))
          (first, second) = OOM.getFirstTwo oom1 oom2
      in first == elem1 && second == elem2
  , testProperty "more is associative (elements)" $ \x y z ->
      let a = OOM.one (x :: Int)
          b = OOM.one (y :: Int)
          c = OOM.one (z :: Int)
          left = OOM.more (OOM.more a b) c
          right = OOM.more a (OOM.more b c)
      in getElements left == getElements right
  ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testGroup "Single Element Operations"
      [ testCase "map on single element preserves structure" $ do
          let original = OOM.one 42
              result = OOM.map show original
          case result of
            One "42" -> return ()
            _ -> assertFailure "Single element map should preserve One structure"
      , testCase "destruct single element" $ do
          let original = OOM.one "only"
              (h, t) = OOM.destruct (\head tail -> (head, tail)) original
          h @?= "only"
          t @?= []
      , testCase "getFirstTwo with singles" $ do
          let result = OOM.getFirstTwo (OOM.one 1) (OOM.one 2)
          result @?= (1, 2)
      ]
  , testGroup "Deeply Nested Structures"
      [ testCase "deep left nesting" $ do
          let deepLeft = foldl (\acc i -> OOM.more acc (OOM.one i)) (OOM.one 0) [1..10]
              elements = OOM.destruct (\h t -> h : t) deepLeft
          length elements @?= 11
          head elements @?= 0
          last elements @?= 10
      , testCase "deep right nesting" $ do
          let deepRight = foldr (\i acc -> OOM.more (OOM.one i) acc) (OOM.one 10) [0..9]
              elements = OOM.destruct (\h t -> h : t) deepRight
          length elements @?= 11
          head elements @?= 0
          last elements @?= 10
      , testCase "balanced deep structure" $ do
          let buildBalanced 0 x = OOM.one x
              buildBalanced n x = OOM.more (buildBalanced (n-1) (x*2)) (buildBalanced (n-1) (x*2+1))
              balanced = buildBalanced 4 1  -- Creates structure with 2^4 = 16 elements
              elements = OOM.destruct (\h t -> h : t) balanced
          length elements @?= 16
      , testCase "getFirstTwo on deeply nested structures" $ do
          let deepLeft = foldl (\acc i -> OOM.more acc (OOM.one i)) (OOM.one 0) [1..100]
              deepRight = foldr (\i acc -> OOM.more (OOM.one i) acc) (OOM.one 200) [100..199]
              result = OOM.getFirstTwo deepLeft deepRight
          result @?= (0, 100)
      ]
  , testGroup "Large Collections"
      [ testCase "large linear structure" $ do
          let large = foldl (\acc i -> OOM.more acc (OOM.one i)) (OOM.one 1) [2..1000]
              elements = OOM.destruct (\h t -> h : t) large
          length elements @?= 1000
          head elements @?= 1
          last elements @?= 1000
      , testCase "map on large structure" $ do
          let large = foldl (\acc i -> OOM.more acc (OOM.one i)) (OOM.one 1) [2..500]
              doubled = OOM.map (*2) large
              elements = OOM.destruct (\h t -> h : t) doubled
          length elements @?= 500
          head elements @?= 2  -- 1 * 2
          last elements @?= 1000  -- 500 * 2
      ]
  , testGroup "Complex Type Transformations"
      [ testCase "map with complex transformation function" $ do
          let original = OOM.more (OOM.one (1, "a")) (OOM.one (2, "b"))
              result = OOM.map (\(n, s) -> show n ++ s) original
              elements = OOM.destruct (\h t -> h : t) result
          elements @?= ["1a", "2b"]
      , testCase "destruct with complex combination function" $ do
          let original = OOM.more (OOM.one 1) (OOM.more (OOM.one 2) (OOM.one 3))
              result = OOM.destruct (\h t -> (h, sum t, length t)) original
          result @?= (1, 5, 2)  -- head=1, sum of tail=[2,3]=5, length=2
      ]
  , testGroup "Extreme Values"
      [ testCase "maximum integer values" $ do
          let original = OOM.more (OOM.one (maxBound :: Int)) (OOM.one (maxBound - 1))
              elements = OOM.destruct (\h t -> h : t) original
          elements @?= [maxBound, maxBound - 1]
      , testCase "minimum integer values" $ do
          let original = OOM.more (OOM.one (minBound :: Int)) (OOM.one (minBound + 1))
              elements = OOM.destruct (\h t -> h : t) original
          elements @?= [minBound, minBound + 1]
      ]
  ]

-- | Error condition tests for invalid inputs.
--
-- Verifies proper error handling and meaningful error messages
-- for all possible error conditions and invalid inputs.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testGroup "Type Safety Verification"
      [ testCase "one constructor type safety" $ do
          let intOne = OOM.one (42 :: Int)
              stringOne = OOM.one ("test" :: String)
              boolOne = OOM.one (True :: Bool)
          -- These should compile and work correctly
          case intOne of
            One 42 -> return ()
            _ -> assertFailure "Int one failed"
          case stringOne of
            One "test" -> return ()
            _ -> assertFailure "String one failed"
          case boolOne of
            One True -> return ()
            _ -> assertFailure "Bool one failed"
      , testCase "more constructor type safety" $ do
          let combined = OOM.more (OOM.one 1) (OOM.one 2)
          case combined of
            More (One 1) (One 2) -> return ()
            _ -> assertFailure "Combined structure incorrect"
      ]
  , testGroup "Memory and Performance Bounds"
      [ testCase "very large structures handle correctly" $ do
          let veryLarge = foldl (\acc i -> OOM.more acc (OOM.one i)) (OOM.one 1) [2..5000]
              first = OOM.getFirstTwo veryLarge (OOM.one 99999)
          first @?= (1, 99999)
      , testCase "deeply nested map operations" $ do
          let deep = foldl (\acc i -> OOM.more acc (OOM.one i)) (OOM.one 1) [2..1000]
              transformed = OOM.map (\x -> x * x) deep
              (first, _) = OOM.destruct (\h t -> (h, t)) transformed
          first @?= 1  -- 1 * 1 = 1
      ]
  , testGroup "Complex Structural Operations"
      [ testCase "nested more operations preserve structure" $ do
          let a = OOM.one 1
              b = OOM.one 2
              c = OOM.one 3
              d = OOM.one 4
              ab = OOM.more a b
              cd = OOM.more c d
              abcd = OOM.more ab cd
              elements = OOM.destruct (\h t -> h : t) abcd
          elements @?= [1, 2, 3, 4]
      , testCase "alternating construction patterns" $ do
          let result = OOM.more 
                        (OOM.more (OOM.one 1) (OOM.one 2))
                        (OOM.more (OOM.one 3) (OOM.one 4))
              elements = OOM.destruct (\h t -> h : t) result
          elements @?= [1, 2, 3, 4]
      ]
  , testGroup "Edge Cases in Element Access"
      [ testCase "getFirstTwo with identical structures" $ do
          let structure = OOM.more (OOM.one 1) (OOM.one 2)
              result = OOM.getFirstTwo structure structure
          result @?= (1, 1)
      , testCase "destruct with immediate return" $ do
          let original = OOM.more (OOM.one "a") (OOM.one "b")
              result = OOM.destruct (\h _ -> h) original
          result @?= "a"
      ]
  , testGroup "Functor Law Verification"
      [ testCase "map preserves tree structure shape" $ do
          let original = OOM.more (OOM.one 1) (OOM.more (OOM.one 2) (OOM.one 3))
              mapped = OOM.map (*2) original
          case (original, mapped) of
            (More (One _) (More (One _) (One _)), 
             More (One _) (More (One _) (One _))) -> return ()
            _ -> assertFailure "Tree structure not preserved"
      ]
  ]

-- Helper functions for testing

-- | Extract all elements from OneOrMore in left-to-right order
getElements :: OneOrMore a -> [a]
getElements = OOM.destruct (\h t -> h : t)

-- QuickCheck Arbitrary instances for testing

instance Arbitrary a => Arbitrary (OneOrMore a) where
  arbitrary = sized $ \n -> 
    if n <= 1
    then OOM.one <$> arbitrary
    else do
      k <- choose (1, n)
      left <- resize k arbitrary
      right <- resize (n - k) arbitrary
      return (OOM.more left right)
  
  shrink (One x) = [OOM.one x' | x' <- shrink x]
  shrink (More left right) = 
    [left, right] ++ 
    [OOM.more left' right | left' <- shrink left] ++
    [OOM.more left right' | right' <- shrink right]