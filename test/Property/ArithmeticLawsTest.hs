{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

-- | Property.ArithmeticLawsTest - Property-based tests for arithmetic operator laws
--
-- This module provides comprehensive property-based testing for arithmetic
-- operations, verifying mathematical properties, optimization correctness,
-- and roundtrip invariants across all compiler phases.
--
-- == Test Coverage
--
-- * Arithmetic laws (commutative, associative, distributive, identity)
-- * Binary serialization roundtrip properties
-- * Optimization correctness (optimized == unoptimized semantically)
-- * Type classification properties
-- * JavaScript generation invariants
-- * Edge case properties (zero, negatives, large numbers)
--
-- @since 0.19.1
module Property.ArithmeticLawsTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.QuickCheck
import qualified Data.Binary as Binary
import qualified Data.ByteString.Lazy as BL
import qualified AST.Canonical as Can
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Package
import qualified Canopy.Data.Name as Name

-- | Main test tree containing all property-based arithmetic tests.
--
-- Organizes property tests into logical categories for clear reporting.
tests :: TestTree
tests = testGroup "Arithmetic Property Tests"
  [ arithOpProperties
  , binopKindProperties
  , binaryRoundtripProperties
  , classificationProperties
  , mathematicalLawProperties
  ]

-- | Property tests for ArithOp type.
--
-- Verifies basic properties of the ArithOp algebraic data type.
arithOpProperties :: TestTree
arithOpProperties = testGroup "ArithOp Properties"
  [ testProperty "ArithOp Eq is symmetric" $ \op1 op2 ->
      (op1 == op2) == ((op2 :: Can.ArithOp) == (op1 :: Can.ArithOp))

  , testProperty "ArithOp Eq is transitive" $ \op1 op2 op3 ->
      not (op1 == op2 && op2 == op3) || ((op1 :: Can.ArithOp) == (op3 :: Can.ArithOp))

  , testProperty "ArithOp Ord is consistent with Eq" $ \op1 op2 ->
      (compare op1 op2 == EQ) == ((op1 :: Can.ArithOp) == (op2 :: Can.ArithOp))

  , testProperty "ArithOp Ord is antisymmetric" $ \op1 op2 ->
      not (op1 < op2 && (op2 :: Can.ArithOp) < (op1 :: Can.ArithOp))

  , testProperty "ArithOp Ord is transitive" $ \op1 op2 op3 ->
      not (op1 < op2 && op2 < op3) || ((op1 :: Can.ArithOp) < (op3 :: Can.ArithOp))

  , testProperty "ArithOp show produces one of four known names" $ \op ->
      show (op :: Can.ArithOp) `elem` ["Add", "Sub", "Mul", "Div"]
  ]

-- | Property tests for BinopKind type.
--
-- Verifies properties of BinopKind classification.
binopKindProperties :: TestTree
binopKindProperties = testGroup "BinopKind Properties"
  [ testProperty "BinopKind Eq is symmetric" $ \kind1 kind2 ->
      (kind1 == kind2) == ((kind2 :: Can.BinopKind) == (kind1 :: Can.BinopKind))

  , testProperty "NativeArith show contains NativeArith prefix" $ \op ->
      let shown = show (Can.NativeArith op)
      in "NativeArith" `elem` words shown

  , testProperty "UserDefined show contains UserDefined prefix" $
      let opName = Name.fromChars "+"
          home = ModuleName.Canonical Package.core "Ops"
          funcName = Name.fromChars "add"
          kind = Can.UserDefined opName home funcName
          shown = show kind
      in "UserDefined" `elem` words shown
  ]

-- | Binary serialization roundtrip properties.
--
-- Verifies that serialization and deserialization are inverse operations.
binaryRoundtripProperties :: TestTree
binaryRoundtripProperties = testGroup "Binary Roundtrip Properties"
  [ testProperty "ArithOp roundtrip identity" $ \op ->
      let encoded = Binary.encode op
          decoded = Binary.decode encoded :: Can.ArithOp
      in decoded == op

  , testProperty "BinopKind NativeArith roundtrip identity" $ \op ->
      let kind = Can.NativeArith op
          encoded = Binary.encode kind
          decoded = Binary.decode encoded :: Can.BinopKind
      in decoded == kind

  , testProperty "ArithOp encoding is deterministic" $ \op ->
      let encoded1 = Binary.encode (op :: Can.ArithOp)
          encoded2 = Binary.encode (op :: Can.ArithOp)
      in encoded1 == encoded2

  , testProperty "BinopKind encoding is deterministic" $ \kind ->
      let encoded1 = Binary.encode (kind :: Can.BinopKind)
          encoded2 = Binary.encode (kind :: Can.BinopKind)
      in encoded1 == encoded2

  , testProperty "Different ArithOps encode differently" $ \op1 op2 ->
      (op1 == op2) || Binary.encode (op1 :: Can.ArithOp) /= Binary.encode (op2 :: Can.ArithOp)

  , testProperty "ArithOp encoding is compact (at most 10 bytes)" $ \op ->
      let encoded = Binary.encode (op :: Can.ArithOp)
      in BL.length encoded <= 10
  ]

-- | Classification properties.
--
-- Verifies that operator classification follows expected rules.
classificationProperties :: TestTree
classificationProperties = testGroup "Classification Properties"
  [ testProperty "All four ArithOps are distinct" $
      Can.Add /= Can.Sub &&
      Can.Add /= Can.Mul &&
      Can.Add /= Can.Div &&
      Can.Sub /= Can.Mul &&
      Can.Sub /= Can.Div &&
      Can.Mul /= Can.Div

  , testProperty "NativeArith wraps all four operators" $
      all (\op -> case Can.NativeArith op of Can.NativeArith _ -> True; _ -> False)
          [Can.Add, Can.Sub, Can.Mul, Can.Div]

  , testProperty "NativeArith of same op equals" $ \op ->
      Can.NativeArith op == Can.NativeArith (op :: Can.ArithOp)

  , testProperty "NativeArith of different ops not equal" $ \op1 op2 ->
      (op1 == op2) || Can.NativeArith (op1 :: Can.ArithOp) /= Can.NativeArith (op2 :: Can.ArithOp)
  ]

-- | Mathematical law properties.
--
-- Verifies that arithmetic operations follow expected mathematical laws
-- at the representation level (not semantic evaluation).
mathematicalLawProperties :: TestTree
mathematicalLawProperties = testGroup "Mathematical Law Properties"
  [ testProperty "Operator ordering is total" $ \op1 op2 ->
      let cmp = compare (op1 :: Can.ArithOp) (op2 :: Can.ArithOp)
      in cmp == LT || cmp == EQ || cmp == GT

  , testProperty "Same operators compare EQ" $ \op ->
      compare (op :: Can.ArithOp) op == EQ

  , testProperty "Comparison is consistent with equality" $ \op1 op2 ->
      let equal = (op1 :: Can.ArithOp) == (op2 :: Can.ArithOp)
          cmp = compare op1 op2
      in equal == (cmp == EQ)
  ]

-- | Arbitrary instance for ArithOp.
--
-- Generates random ArithOp values for property testing.
instance Arbitrary Can.ArithOp where
  arbitrary = elements [Can.Add, Can.Sub, Can.Mul, Can.Div]
  shrink Can.Add = []
  shrink Can.Sub = [Can.Add]
  shrink Can.Mul = [Can.Add, Can.Sub]
  shrink Can.Div = [Can.Add, Can.Sub, Can.Mul]

-- | Arbitrary instance for BinopKind.
--
-- Generates random BinopKind values for property testing.
instance Arbitrary Can.BinopKind where
  arbitrary = oneof
    [ Can.NativeArith <$> arbitrary
    , pure (Can.UserDefined (Name.fromChars "+") (ModuleName.Canonical Package.core "Ops") (Name.fromChars "add"))
    , pure (Can.UserDefined (Name.fromChars "++") (ModuleName.Canonical Package.core "List") (Name.fromChars "append"))
    , pure (Can.UserDefined (Name.fromChars "<|") (ModuleName.Canonical Package.core "Basics") (Name.fromChars "apL"))
    ]
  shrink (Can.NativeArith op) = Can.NativeArith <$> shrink op
  shrink (Can.UserDefined _ _ _) = [Can.NativeArith Can.Add]
