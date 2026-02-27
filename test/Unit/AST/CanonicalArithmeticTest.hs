{-# LANGUAGE OverloadedStrings #-}

-- | Unit.AST.CanonicalArithmeticTest - Comprehensive tests for Canonical AST arithmetic operators
--
-- This module provides complete test coverage for arithmetic expression representation
-- in the Canonical AST, including ArithOp construction, BinopKind classification,
-- Binary serialization, and all operator variants.
--
-- == Test Coverage
--
-- * ArithOp show values for all four operators
-- * BinopKind classification (NativeArith vs UserDefined)
-- * Binary serialization roundtrip for ArithOp
-- * Binary serialization roundtrip for BinopKind
-- * Eq and Ord instance properties
-- * Binary error handling for invalid bytes
--
-- @since 0.19.1
module Unit.AST.CanonicalArithmeticTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.Binary as Binary
import qualified Data.ByteString.Lazy as BL
import qualified Canopy.Data.Name as Name
import qualified AST.Canonical as Can
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Package

-- | Main test tree containing all AST.Canonical arithmetic tests.
tests :: TestTree
tests = testGroup "AST.Canonical Arithmetic Tests"
  [ arithOpShowTests
  , arithOpEqualityTests
  , arithOpOrderingTests
  , arithOpBinaryRoundtripTests
  , binopKindShowTests
  , binopKindEqualityTests
  , binopKindBinaryRoundtripTests
  , binaryErrorHandlingTests
  ]

-- | Test ArithOp Show instance with exact string verification.
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
-- Tests actual cross-operator inequality behavior.
arithOpEqualityTests :: TestTree
arithOpEqualityTests = testGroup "ArithOp Equality Tests"
  [ testCase "Add not equals Sub" $
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
  [ testCase "Add < Sub ordering" $
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
arithOpBinaryRoundtripTests :: TestTree
arithOpBinaryRoundtripTests = testGroup "ArithOp Binary Roundtrip Tests"
  [ testCase "Add roundtrip preserves value" $
      Binary.decode (Binary.encode Can.Add) @?= (Can.Add :: Can.ArithOp)

  , testCase "Sub roundtrip preserves value" $
      Binary.decode (Binary.encode Can.Sub) @?= (Can.Sub :: Can.ArithOp)

  , testCase "Mul roundtrip preserves value" $
      Binary.decode (Binary.encode Can.Mul) @?= (Can.Mul :: Can.ArithOp)

  , testCase "Div roundtrip preserves value" $
      Binary.decode (Binary.encode Can.Div) @?= (Can.Div :: Can.ArithOp)

  , testCase "All four operators encode to exactly 1 byte" $ do
      BL.length (Binary.encode Can.Add) @?= 1
      BL.length (Binary.encode Can.Sub) @?= 1
      BL.length (Binary.encode Can.Mul) @?= 1
      BL.length (Binary.encode Can.Div) @?= 1

  , testCase "Different operators encode to different bytes" $ do
      let enc op = Binary.encode (op :: Can.ArithOp)
      assertBool "Add /= Sub encoding" (enc Can.Add /= enc Can.Sub)
      assertBool "Add /= Mul encoding" (enc Can.Add /= enc Can.Mul)
      assertBool "Add /= Div encoding" (enc Can.Add /= enc Can.Div)
      assertBool "Sub /= Mul encoding" (enc Can.Sub /= enc Can.Mul)
  ]

-- | Test BinopKind Show instance.
binopKindShowTests :: TestTree
binopKindShowTests = testGroup "BinopKind Show Tests"
  [ testCase "NativeArith Add shows NativeArith Add" $
      show (Can.NativeArith Can.Add) @?= "NativeArith Add"

  , testCase "NativeArith Sub shows NativeArith Sub" $
      show (Can.NativeArith Can.Sub) @?= "NativeArith Sub"

  , testCase "NativeArith Mul shows NativeArith Mul" $
      show (Can.NativeArith Can.Mul) @?= "NativeArith Mul"

  , testCase "NativeArith Div shows NativeArith Div" $
      show (Can.NativeArith Can.Div) @?= "NativeArith Div"
  ]

-- | Test BinopKind equality semantics.
binopKindEqualityTests :: TestTree
binopKindEqualityTests = testGroup "BinopKind Equality Tests"
  [ testCase "NativeArith Add not equals NativeArith Sub" $
      (Can.NativeArith Can.Add == Can.NativeArith Can.Sub) @?= False

  , testCase "NativeArith not equals UserDefined" $
      let opName = Name.fromChars "+"
          canonical = ModuleName.Canonical Package.core "Basics"
          funcName = Name.fromChars "add"
      in (Can.NativeArith Can.Add == Can.UserDefined opName canonical funcName) @?= False

  , testCase "UserDefined not equals with different operator name" $
      let opName1 = Name.fromChars "+"
          opName2 = Name.fromChars "-"
          canonical = ModuleName.Canonical Package.core "Basics"
          funcName = Name.fromChars "add"
      in (Can.UserDefined opName1 canonical funcName == Can.UserDefined opName2 canonical funcName) @?= False

  , testCase "UserDefined equals with same parameters" $
      let opName = Name.fromChars "+"
          canonical = ModuleName.Canonical Package.core "Basics"
          funcName = Name.fromChars "add"
      in (Can.UserDefined opName canonical funcName == Can.UserDefined opName canonical funcName) @?= True
  ]

-- | Test BinopKind Binary serialization roundtrip.
binopKindBinaryRoundtripTests :: TestTree
binopKindBinaryRoundtripTests = testGroup "BinopKind Binary Roundtrip Tests"
  [ testCase "NativeArith Add roundtrip preserves value" $
      let kind = Can.NativeArith Can.Add
      in (Binary.decode (Binary.encode kind) :: Can.BinopKind) @?= kind

  , testCase "NativeArith Sub roundtrip preserves value" $
      let kind = Can.NativeArith Can.Sub
      in (Binary.decode (Binary.encode kind) :: Can.BinopKind) @?= kind

  , testCase "NativeArith Mul roundtrip preserves value" $
      let kind = Can.NativeArith Can.Mul
      in (Binary.decode (Binary.encode kind) :: Can.BinopKind) @?= kind

  , testCase "NativeArith Div roundtrip preserves value" $
      let kind = Can.NativeArith Can.Div
      in (Binary.decode (Binary.encode kind) :: Can.BinopKind) @?= kind

  , testCase "UserDefined roundtrip preserves value" $
      let opName = Name.fromChars "+"
          canonical = ModuleName.Canonical Package.core "Basics"
          funcName = Name.fromChars "add"
          kind = Can.UserDefined opName canonical funcName
      in (Binary.decode (Binary.encode kind) :: Can.BinopKind) @?= kind
  ]

-- | Test Binary error handling for corrupted data.
binaryErrorHandlingTests :: TestTree
binaryErrorHandlingTests = testGroup "Binary Error Handling Tests"
  [ testCase "Invalid ArithOp byte 255 produces decode error" $
      case Binary.decodeOrFail (BL.pack [255]) of
        Left _ -> pure ()
        Right (_, _, _ :: Can.ArithOp) -> assertFailure "Expected decode to fail on invalid byte"

  , testCase "Invalid BinopKind bytes produce decode error" $
      case Binary.decodeOrFail (BL.pack [255, 255, 255, 255]) of
        Left _ -> pure ()
        Right (_, _, _ :: Can.BinopKind) -> assertFailure "Expected decode to fail on invalid bytes"
  ]
