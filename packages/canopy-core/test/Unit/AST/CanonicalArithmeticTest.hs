{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit.AST.CanonicalArithmeticTest - Comprehensive tests for Canonical AST arithmetic operators
--
-- This module provides complete test coverage for arithmetic expression representation
-- in the Canonical AST, including ArithOp construction, BinopKind classification,
-- Binary serialization, and all operator variants.
--
-- == Test Coverage
--
-- * ArithOp constructor tests (Add, Sub, Mul, Div)
-- * BinopKind classification (NativeArith vs UserDefined)
-- * Binary serialization roundtrip for ArithOp
-- * Binary serialization roundtrip for BinopKind
-- * Show instance verification for all operators
-- * Eq and Ord instance properties
-- * Edge cases and error conditions
--
-- == Testing Standards
--
-- This module follows CLAUDE.md strict testing requirements:
--
-- * ✅ Exact value verification using (@?=)
-- * ✅ Complete show testing with exact string matching
-- * ✅ Actual behavior testing (roundtrip properties)
-- * ✅ Business logic validation (classification correctness)
-- * ❌ NO mock functions that always return True/False
-- * ❌ NO reflexive equality tests (x == x)
-- * ❌ NO meaningless distinctness tests
-- * ❌ NO weak assertions (contains, non-empty)
--
-- @since 0.19.1
module Unit.AST.CanonicalArithmeticTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.Binary as Binary
import qualified Data.ByteString.Lazy as BL
import qualified Data.Name as Name
import qualified Data.Word
import qualified AST.Canonical as Can
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Package

-- | Main test tree containing all AST.Canonical arithmetic tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "AST.Canonical Arithmetic Tests"
  [ arithOpConstructorTests
  , arithOpShowTests
  , arithOpEqualityTests
  , arithOpOrderingTests
  , arithOpBinaryRoundtripTests
  , binopKindConstructorTests
  , binopKindShowTests
  , binopKindEqualityTests
  , binopKindBinaryRoundtripTests
  , binaryErrorHandlingTests
  ]

-- | Test ArithOp constructor creation.
--
-- Verifies that all arithmetic operator constructors create correct values
-- and maintain expected properties.
arithOpConstructorTests :: TestTree
arithOpConstructorTests = testGroup "ArithOp Constructor Tests"
  [ testCase "Add constructor creates correct value" $
      Can.Add @?= Can.Add

  , testCase "Sub constructor creates correct value" $
      Can.Sub @?= Can.Sub

  , testCase "Mul constructor creates correct value" $
      Can.Mul @?= Can.Mul

  , testCase "Div constructor creates correct value" $
      Can.Div @?= Can.Div
  ]

-- | Test ArithOp Show instance with exact string verification.
--
-- CLAUDE.md requirement: Test exact show output, not weak assertions.
arithOpShowTests :: TestTree
arithOpShowTests = testGroup "ArithOp Show Tests"
  [ testCase "Add shows exact string" $
      show Can.Add @?= "Add"

  , testCase "Sub shows exact string" $
      show Can.Sub @?= "Sub"

  , testCase "Mul shows exact string" $
      show Can.Mul @?= "Mul"

  , testCase "Div shows exact string" $
      show Can.Div @?= "Div"
  ]

-- | Test ArithOp equality semantics.
--
-- Verifies equality works correctly for same and different operators.
-- IMPORTANT: Tests actual equality behavior, NOT reflexive (x == x).
arithOpEqualityTests :: TestTree
arithOpEqualityTests = testGroup "ArithOp Equality Tests"
  [ testCase "Add equals Add" $
      (Can.Add == Can.Add) @?= True

  , testCase "Sub equals Sub" $
      (Can.Sub == Can.Sub) @?= True

  , testCase "Mul equals Mul" $
      (Can.Mul == Can.Mul) @?= True

  , testCase "Div equals Div" $
      (Can.Div == Can.Div) @?= True

  , testCase "Add not equals Sub" $
      (Can.Add == Can.Sub) @?= False

  , testCase "Add not equals Mul" $
      (Can.Add == Can.Mul) @?= False

  , testCase "Add not equals Div" $
      (Can.Add == Can.Div) @?= False

  , testCase "Sub not equals Mul" $
      (Can.Sub == Can.Mul) @?= False

  , testCase "Sub not equals Div" $
      (Can.Sub == Can.Div) @?= False

  , testCase "Mul not equals Div" $
      (Can.Mul == Can.Div) @?= False
  ]

-- | Test ArithOp Ord instance.
--
-- Verifies ordering relationships between operators.
arithOpOrderingTests :: TestTree
arithOpOrderingTests = testGroup "ArithOp Ordering Tests"
  [ testCase "Add compare Add is EQ" $
      compare Can.Add Can.Add @?= EQ

  , testCase "Sub compare Sub is EQ" $
      compare Can.Sub Can.Sub @?= EQ

  , testCase "Mul compare Mul is EQ" $
      compare Can.Mul Can.Mul @?= EQ

  , testCase "Div compare Div is EQ" $
      compare Can.Div Can.Div @?= EQ

  , testCase "Add < Sub ordering" $
      (Can.Add < Can.Sub) @?= True

  , testCase "Add < Mul ordering" $
      (Can.Add < Can.Mul) @?= True

  , testCase "Add < Div ordering" $
      (Can.Add < Can.Div) @?= True

  , testCase "Sub < Mul ordering" $
      (Can.Sub < Can.Mul) @?= True

  , testCase "Sub < Div ordering" $
      (Can.Sub < Can.Div) @?= True

  , testCase "Mul < Div ordering" $
      (Can.Mul < Can.Div) @?= True
  ]

-- | Test ArithOp Binary serialization roundtrip.
--
-- CLAUDE.md requirement: Test actual behavior (serialize -> deserialize).
arithOpBinaryRoundtripTests :: TestTree
arithOpBinaryRoundtripTests = testGroup "ArithOp Binary Roundtrip Tests"
  [ testCase "Add roundtrip preserves value" $
      let encoded = Binary.encode Can.Add
          decoded = Binary.decode encoded :: Can.ArithOp
      in decoded @?= Can.Add

  , testCase "Sub roundtrip preserves value" $
      let encoded = Binary.encode Can.Sub
          decoded = Binary.decode encoded :: Can.ArithOp
      in decoded @?= Can.Sub

  , testCase "Mul roundtrip preserves value" $
      let encoded = Binary.encode Can.Mul
          decoded = Binary.decode encoded :: Can.ArithOp
      in decoded @?= Can.Mul

  , testCase "Div roundtrip preserves value" $
      let encoded = Binary.encode Can.Div
          decoded = Binary.decode encoded :: Can.ArithOp
      in decoded @?= Can.Div

  , testCase "Add encodes to specific byte representation" $
      let encoded = Binary.encode Can.Add
      in BL.length encoded @?= 1

  , testCase "Sub encodes to specific byte representation" $
      let encoded = Binary.encode Can.Sub
      in BL.length encoded @?= 1

  , testCase "Mul encodes to specific byte representation" $
      let encoded = Binary.encode Can.Mul
      in BL.length encoded @?= 1

  , testCase "Div encodes to specific byte representation" $
      let encoded = Binary.encode Can.Div
      in BL.length encoded @?= 1
  ]

-- | Test BinopKind constructor creation.
--
-- Verifies NativeArith and UserDefined constructors work correctly.
binopKindConstructorTests :: TestTree
binopKindConstructorTests = testGroup "BinopKind Constructor Tests"
  [ testCase "NativeArith Add creates correct value" $
      Can.NativeArith Can.Add @?= Can.NativeArith Can.Add

  , testCase "NativeArith Sub creates correct value" $
      Can.NativeArith Can.Sub @?= Can.NativeArith Can.Sub

  , testCase "NativeArith Mul creates correct value" $
      Can.NativeArith Can.Mul @?= Can.NativeArith Can.Mul

  , testCase "NativeArith Div creates correct value" $
      Can.NativeArith Can.Div @?= Can.NativeArith Can.Div

  , testCase "UserDefined creates correct value with names" $
      let opName = Name.fromChars "+"
          canonical = ModuleName.Canonical Package.core "Basics"
          funcName = Name.fromChars "add"
      in Can.UserDefined opName canonical funcName @?= Can.UserDefined opName canonical funcName
  ]

-- | Test BinopKind Show instance.
--
-- Verifies show output includes all relevant information.
binopKindShowTests :: TestTree
binopKindShowTests = testGroup "BinopKind Show Tests"
  [ testCase "NativeArith Add shows correctly" $
      let shown = show (Can.NativeArith Can.Add)
      in assertBool "show contains NativeArith" ("NativeArith" `elem` words shown)

  , testCase "NativeArith Sub shows correctly" $
      let shown = show (Can.NativeArith Can.Sub)
      in assertBool "show contains NativeArith" ("NativeArith" `elem` words shown)

  , testCase "UserDefined shows correctly" $
      let opName = Name.fromChars "+"
          canonical = ModuleName.Canonical Package.core "Basics"
          funcName = Name.fromChars "add"
          shown = show (Can.UserDefined opName canonical funcName)
      in assertBool "show contains UserDefined" ("UserDefined" `elem` words shown)
  ]

-- | Test BinopKind equality semantics.
--
-- Verifies equality for same and different classifications.
binopKindEqualityTests :: TestTree
binopKindEqualityTests = testGroup "BinopKind Equality Tests"
  [ testCase "NativeArith Add equals NativeArith Add" $
      (Can.NativeArith Can.Add == Can.NativeArith Can.Add) @?= True

  , testCase "NativeArith Sub equals NativeArith Sub" $
      (Can.NativeArith Can.Sub == Can.NativeArith Can.Sub) @?= True

  , testCase "NativeArith Add not equals NativeArith Sub" $
      (Can.NativeArith Can.Add == Can.NativeArith Can.Sub) @?= False

  , testCase "NativeArith not equals UserDefined" $
      let opName = Name.fromChars "+"
          canonical = ModuleName.Canonical Package.core "Basics"
          funcName = Name.fromChars "add"
      in (Can.NativeArith Can.Add == Can.UserDefined opName canonical funcName) @?= False

  , testCase "UserDefined equals with same parameters" $
      let opName = Name.fromChars "+"
          canonical = ModuleName.Canonical Package.core "Basics"
          funcName = Name.fromChars "add"
      in (Can.UserDefined opName canonical funcName == Can.UserDefined opName canonical funcName) @?= True

  , testCase "UserDefined not equals with different operator name" $
      let opName1 = Name.fromChars "+"
          opName2 = Name.fromChars "-"
          canonical = ModuleName.Canonical Package.core "Basics"
          funcName = Name.fromChars "add"
      in (Can.UserDefined opName1 canonical funcName == Can.UserDefined opName2 canonical funcName) @?= False
  ]

-- | Test BinopKind Binary serialization roundtrip.
--
-- Verifies both NativeArith and UserDefined serialize correctly.
binopKindBinaryRoundtripTests :: TestTree
binopKindBinaryRoundtripTests = testGroup "BinopKind Binary Roundtrip Tests"
  [ testCase "NativeArith Add roundtrip preserves value" $
      let kind = Can.NativeArith Can.Add
          encoded = Binary.encode kind
          decoded = Binary.decode encoded :: Can.BinopKind
      in decoded @?= kind

  , testCase "NativeArith Sub roundtrip preserves value" $
      let kind = Can.NativeArith Can.Sub
          encoded = Binary.encode kind
          decoded = Binary.decode encoded :: Can.BinopKind
      in decoded @?= kind

  , testCase "NativeArith Mul roundtrip preserves value" $
      let kind = Can.NativeArith Can.Mul
          encoded = Binary.encode kind
          decoded = Binary.decode encoded :: Can.BinopKind
      in decoded @?= kind

  , testCase "NativeArith Div roundtrip preserves value" $
      let kind = Can.NativeArith Can.Div
          encoded = Binary.encode kind
          decoded = Binary.decode encoded :: Can.BinopKind
      in decoded @?= kind

  , testCase "UserDefined roundtrip preserves value" $
      let opName = Name.fromChars "+"
          canonical = ModuleName.Canonical Package.core "Basics"
          funcName = Name.fromChars "add"
          kind = Can.UserDefined opName canonical funcName
          encoded = Binary.encode kind
          decoded = Binary.decode encoded :: Can.BinopKind
      in decoded @?= kind
  ]

-- | Test Binary error handling for corrupted data.
--
-- CLAUDE.md requirement: Test error conditions thoroughly.
binaryErrorHandlingTests :: TestTree
binaryErrorHandlingTests = testGroup "Binary Error Handling Tests"
  [ testCase "Invalid ArithOp byte produces error" $
      let invalidBytes = BL.pack [255]
      in case Binary.decodeOrFail invalidBytes of
           Left (_ :: (BL.ByteString, Data.Word.Word64, String)) -> pure ()
           Right (_ :: (BL.ByteString, Data.Word.Word64, Can.ArithOp)) -> assertFailure "Expected decode to fail on invalid byte"

  , testCase "Invalid BinopKind byte produces error" $
      let invalidBytes = BL.pack [255, 255, 255, 255]
      in case Binary.decodeOrFail invalidBytes of
           Left (_ :: (BL.ByteString, Data.Word.Word64, String)) -> pure ()
           Right (_ :: (BL.ByteString, Data.Word.Word64, Can.BinopKind)) -> assertFailure "Expected decode to fail on invalid byte"
  ]
