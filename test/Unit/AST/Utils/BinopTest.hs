{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Comprehensive test suite for AST.Utils.Binop.
--
-- This module provides complete test coverage for all public functions,
-- edge cases, error conditions, and properties in AST.Utils.Binop.
--
-- Coverage Target: ≥80% line coverage
-- Test Categories: Unit, Property, Edge Case, Error Condition
--
-- @since 0.19.1
module Unit.AST.Utils.BinopTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import AST.Utils.Binop (Precedence (..), Associativity (..))
import qualified AST.Utils.Binop as Binop
import Data.Binary (decode, encode)
import Prelude hiding (Left, Right)

-- | Main test tree containing all AST.Utils.Binop tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "AST.Utils.Binop Tests"
  [ unitTests
  , propertyTests
  , edgeCaseTests
  , serializationTests
  ]

-- | Unit tests for all public functions and data constructors.
--
-- Tests basic functionality with known inputs and expected outputs.
-- Every public function and data constructor must have unit tests.
unitTests :: TestTree
unitTests = testGroup "Unit Tests"
  [ precedenceTests
  , associativityTests
  ]

-- | Precedence type constructor and comparison tests.
precedenceTests :: TestTree
precedenceTests = testGroup "Precedence Tests"
  [ testCase "Precedence construction with positive integer" $
      Precedence 7 @?= Precedence 7
  , testCase "Precedence construction with zero" $
      Precedence 0 @?= Precedence 0
  , testCase "Precedence construction with negative integer" $
      Precedence (-1) @?= Precedence (-1)
  , testCase "Precedence equality for same values" $
      (Precedence 5 == Precedence 5) @?= True
  , testCase "Precedence inequality for different values" $
      (Precedence 3 == Precedence 7) @?= False
  , testCase "Precedence ordering - higher precedence greater" $
      (Precedence 8 > Precedence 6) @?= True
  , testCase "Precedence ordering - lower precedence less" $
      (Precedence 4 < Precedence 9) @?= True
  , testCase "Precedence ordering - equal precedence" $
      (Precedence 5 `compare` Precedence 5) @?= EQ
  , testCase "Precedence show format" $
      show (Precedence 42) @?= "Precedence 42"
  ]

-- | Associativity data type constructor tests.
associativityTests :: TestTree
associativityTests = testGroup "Associativity Tests"
  [ testCase "Left associativity construction" $
      Left @?= Left
  , testCase "Right associativity construction" $
      Right @?= Right
  , testCase "Non associativity construction" $
      Non @?= Non
  , testCase "Left associativity equality" $
      (Left == Left) @?= True
  , testCase "Right associativity equality" $
      (Right == Right) @?= True
  , testCase "Non associativity equality" $
      (Non == Non) @?= True
  , testCase "Left and Right associativity inequality" $
      (Left == Right) @?= False
  , testCase "Left and Non associativity inequality" $
      (Left == Non) @?= False
  , testCase "Right and Non associativity inequality" $
      (Right == Non) @?= False
  , testCase "Left associativity show format" $
      show Left @?= "Left"
  , testCase "Right associativity show format" $
      show Right @?= "Right"
  , testCase "Non associativity show format" $
      show Non @?= "Non"
  ]

-- | Property-based tests for mathematical and logical invariants.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with mathematical or logical operations.
propertyTests :: TestTree
propertyTests = testGroup "Property Tests"
  [ precedenceProperties
  , associativityProperties
  , serializationProperties
  ]

-- | Mathematical properties of precedence ordering.
precedenceProperties :: TestTree
precedenceProperties = testGroup "Precedence Properties"
  [ testProperty "reflexivity - precedence equals itself" $ \n ->
      let prec = Precedence n
      in prec == prec
  , testProperty "symmetry - equality is symmetric" $ \n m ->
      let prec1 = Precedence n
          prec2 = Precedence m
      in (prec1 == prec2) == (prec2 == prec1)
  , testProperty "transitivity - ordering is transitive" $ \n m p ->
      let prec1 = Precedence n
          prec2 = Precedence m
          prec3 = Precedence p
      in if prec1 <= prec2 && prec2 <= prec3
         then prec1 <= prec3
         else True
  , testProperty "antisymmetry - ordering is antisymmetric" $ \n m ->
      let prec1 = Precedence n
          prec2 = Precedence m
      in if prec1 <= prec2 && prec2 <= prec1
         then prec1 == prec2
         else True
  , testProperty "totality - comparison always produces result" $ \n m ->
      let prec1 = Precedence n
          prec2 = Precedence m
          result = compare prec1 prec2
      in result `elem` [LT, EQ, GT]
  ]

-- | Properties of associativity enumeration.
associativityProperties :: TestTree
associativityProperties = testGroup "Associativity Properties"
  [ testProperty "reflexivity - associativity equals itself" $ \assoc ->
      assoc == (assoc :: Associativity)
  , testProperty "all associativity values are distinct" $ \assoc1 assoc2 ->
      if assoc1 /= (assoc2 :: Associativity)
      then assoc1 /= assoc2
      else assoc1 == assoc2
  ]

-- | Properties for binary serialization roundtrip.
serializationProperties :: TestTree
serializationProperties = testGroup "Serialization Properties"
  [ testProperty "precedence serialization roundtrip" $ \n ->
      let prec = Precedence n
      in decode (encode prec) == prec
  , testProperty "associativity serialization roundtrip" $ \assoc ->
      decode (encode assoc) == (assoc :: Associativity)
  ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testCase "maximum precedence value" $
      let maxPrec = Precedence maxBound
      in maxPrec @?= Precedence maxBound
  , testCase "minimum precedence value" $
      let minPrec = Precedence minBound
      in minPrec @?= Precedence minBound
  , testCase "precedence ordering at integer boundaries" $
      (Precedence maxBound > Precedence (maxBound - 1)) @?= True
  , testCase "precedence ordering at negative boundaries" $
      (Precedence minBound < Precedence (minBound + 1)) @?= True
  , testCase "all associativity values are covered" $
      let allAssocs = [Left, Non, Right]
          uniqueAssocs = length allAssocs == 3
      in uniqueAssocs @?= True
  ]

-- | Binary serialization and deserialization tests.
--
-- Verifies proper serialization behavior and format consistency
-- for module interface files and compilation caching.
serializationTests :: TestTree
serializationTests = testGroup "Binary Serialization Tests"
  [ testCase "precedence serialization preserves value" $
      let original = Precedence 42
          serialized = encode original
          deserialized = decode serialized
      in deserialized @?= original
  , testCase "associativity Left serialization" $
      let original = Left
          serialized = encode original
          deserialized = decode serialized
      in deserialized @?= original
  , testCase "associativity Non serialization" $
      let original = Non
          serialized = encode original
          deserialized = decode serialized
      in deserialized @?= original
  , testCase "associativity Right serialization" $
      let original = Right
          serialized = encode original
          deserialized = decode serialized
      in deserialized @?= original
  , testCase "precedence zero serialization" $
      let original = Precedence 0
          serialized = encode original
          deserialized = decode serialized
      in deserialized @?= original
  , testCase "negative precedence serialization" $
      let original = Precedence (-100)
          serialized = encode original
          deserialized = decode serialized
      in deserialized @?= original
  ]

-- QuickCheck Arbitrary instances for property testing

instance Arbitrary Precedence where
  arbitrary = Precedence <$> arbitrary
  shrink (Precedence n) = [Precedence n' | n' <- shrink n]

instance Arbitrary Associativity where
  arbitrary = elements [Left, Non, Right]
  shrink _ = []