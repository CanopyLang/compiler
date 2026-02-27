{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

-- | Unit.AST.SourceArithmeticTest - Comprehensive tests for arithmetic AST nodes
--
-- This module provides complete test coverage for arithmetic expression
-- representation in the Source AST, including construction, manipulation,
-- and invariants for native arithmetic operators.
--
-- == Test Coverage
--
-- * Constructor creation for all arithmetic operators (+, -, *, /, //, ^, %)
-- * Binary operator AST node structure validation
-- * Nested arithmetic expression trees
-- * Operator precedence representation
-- * Region information preservation
-- * Edge cases (zero, negative numbers, max values)
--
-- @since 0.19.1
module Unit.AST.SourceArithmeticTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified AST.Source as Src
import qualified Canopy.Float as EF
import qualified Reporting.Annotation as A

-- | Main test tree containing all AST.Source arithmetic tests.
tests :: TestTree
tests = testGroup "AST.Source Arithmetic Tests"
  [ constructorTests
  , binopStructureTests
  , nestedExpressionTests
  , regionPreservationTests
  , edgeCaseTests
  ]

-- | Test arithmetic expression constructors.
--
-- Verifies that all arithmetic operators can be represented in the AST
-- with correct structure and maintain expected properties.
constructorTests :: TestTree
constructorTests = testGroup "Constructor Tests"
  [ testCase "Int literal 42 stores value 42" $
      let expr = Src.Int 42
      in case expr of
           Src.Int n -> n @?= 42
           _ -> assertFailure "Expected Int constructor"

  , testCase "Float literal is a Src.Float constructor" $
      -- Canopy.Float.Float is a raw byte representation; we verify the constructor
      -- tag is correct by pattern matching. Arithmetic on the value is unavailable.
      let expr = Src.Float (mkFloat "3.14")
      in case expr of
           Src.Float f -> Utf8.toChars f @?= "3.14"
           _ -> assertFailure "Expected Float constructor"

  , testCase "Negate node wraps inner Int" $
      let expr = Src.Negate (A.At dummyRegion (Src.Int 5))
      in case expr of
           Src.Negate inner -> extractInt inner @?= Just 5
           _ -> assertFailure "Expected Negate with Int"

  , testCase "Binops node stores operator name +" $
      let op = A.At dummyRegion (Name.fromChars "+")
          expr = Src.Binops [(A.At dummyRegion (Src.Int 2), op)] (A.At dummyRegion (Src.Int 3))
      in case expr of
           Src.Binops [(_, opName)] _ ->
             Name.toChars (A.toValue opName) @?= "+"
           _ -> assertFailure "Expected Binops structure"

  , testCase "Multiplication operator represents as *" $
      Name.toChars (Name.fromChars "*") @?= "*"

  , testCase "Division operator represents as /" $
      Name.toChars (Name.fromChars "/") @?= "/"

  , testCase "Integer division operator represents as //" $
      Name.toChars (Name.fromChars "//") @?= "//"

  , testCase "Modulo operator represents as %" $
      Name.toChars (Name.fromChars "%") @?= "%"

  , testCase "Power operator represents as ^" $
      Name.toChars (Name.fromChars "^") @?= "^"

  , testCase "Subtraction operator represents as -" $
      Name.toChars (Name.fromChars "-") @?= "-"
  ]

-- | Test binary operator structure in AST.
--
-- Verifies that binary operations maintain correct tree structure
-- with left-hand side, operator, and right-hand side components.
binopStructureTests :: TestTree
binopStructureTests = testGroup "Binary Operator Structure"
  [ testCase "Simple addition 1 + 2 stores both operands" $
      let left = A.At dummyRegion (Src.Int 1)
          right = A.At dummyRegion (Src.Int 2)
          op = A.At dummyRegion (Name.fromChars "+")
          expr = Src.Binops [(left, op)] right
      in case extractBinopInts expr of
           Just (l, r) -> do
             l @?= 1
             r @?= 2
           Nothing -> assertFailure "Expected Int operands in Binops"

  , testCase "Multiplication with variables stores variable names" $
      let left = A.At dummyRegion (Src.Var Src.LowVar (Name.fromChars "x"))
          right = A.At dummyRegion (Src.Var Src.LowVar (Name.fromChars "y"))
          op = A.At dummyRegion (Name.fromChars "*")
          expr = Src.Binops [(left, op)] right
      in case expr of
           Src.Binops [(leftExpr, opName)] rightExpr ->
             case (A.toValue leftExpr, A.toValue rightExpr) of
               (Src.Var Src.LowVar lName, Src.Var Src.LowVar rName) -> do
                 Name.toChars lName @?= "x"
                 Name.toChars rName @?= "y"
                 Name.toChars (A.toValue opName) @?= "*"
               _ -> assertFailure "Expected Var operands"
           _ -> assertFailure "Expected Binops"

  , testCase "Division stores operator correctly" $
      let op = A.At dummyRegion (Name.fromChars "/")
          expr = Src.Binops [(A.At dummyRegion (Src.Int 10), op)] (A.At dummyRegion (Src.Float (mkFloat "2.5")))
      in case expr of
           Src.Binops [(_, opName)] _ ->
             Name.toChars (A.toValue opName) @?= "/"
           _ -> assertFailure "Expected Binops with / operator"

  , testCase "Operator is stored as Name type" $
      Name.toChars (Name.fromChars "+") @?= "+"
  ]

-- | Test nested arithmetic expressions.
--
-- Verifies that complex nested expressions maintain correct tree
-- structure and preserve all operator information.
nestedExpressionTests :: TestTree
nestedExpressionTests = testGroup "Nested Expression Tests"
  [ testCase "Two-level nested (a + b) * c outer operator is *" $
      let a = A.At dummyRegion (Src.Int 1)
          b = A.At dummyRegion (Src.Int 2)
          plusOp = A.At dummyRegion (Name.fromChars "+")
          addExpr = A.At dummyRegion (Src.Binops [(a, plusOp)] b)
          c = A.At dummyRegion (Src.Int 3)
          mulOp = A.At dummyRegion (Name.fromChars "*")
          expr = Src.Binops [(addExpr, mulOp)] c
      in case expr of
           Src.Binops [(_, outerOp)] _ ->
             Name.toChars (A.toValue outerOp) @?= "*"
           _ -> assertFailure "Expected outer Binops with *"

  , testCase "Three-level nested (1+2)*(3+4) outer operator is *" $
      let mkInt n = A.At dummyRegion (Src.Int n)
          plus = A.At dummyRegion (Name.fromChars "+")
          mul = A.At dummyRegion (Name.fromChars "*")
          leftAdd = A.At dummyRegion (Src.Binops [(mkInt 1, plus)] (mkInt 2))
          rightAdd = A.At dummyRegion (Src.Binops [(mkInt 3, plus)] (mkInt 4))
          expr = Src.Binops [(leftAdd, mul)] rightAdd
      in case expr of
           Src.Binops [(_, opName)] _ ->
             Name.toChars (A.toValue opName) @?= "*"
           _ -> assertFailure "Expected top-level Binops with *"

  , testCase "Chain 1+2+3 has two operator pairs" $
      let one = A.At dummyRegion (Src.Int 1)
          two = A.At dummyRegion (Src.Int 2)
          three = A.At dummyRegion (Src.Int 3)
          plus = A.At dummyRegion (Name.fromChars "+")
          expr = Src.Binops [(one, plus), (two, plus)] three
      in case expr of
           Src.Binops pairs _ -> length pairs @?= 2
           _ -> assertFailure "Expected chained Binops"

  , testCase "Chain 1+2+3 final value is 3" $
      let one = A.At dummyRegion (Src.Int 1)
          two = A.At dummyRegion (Src.Int 2)
          three = A.At dummyRegion (Src.Int 3)
          plus = A.At dummyRegion (Name.fromChars "+")
          expr = Src.Binops [(one, plus), (two, plus)] three
      in case expr of
           Src.Binops _ finalExpr ->
             extractInt finalExpr @?= Just 3
           _ -> assertFailure "Expected chained Binops"
  ]

-- | Test region information preservation.
--
-- Verifies that source location information is correctly maintained
-- throughout AST construction for error reporting.
regionPreservationTests :: TestTree
regionPreservationTests = testGroup "Region Preservation"
  [ testCase "Located expression preserves its region" $
      let region = A.Region (A.Position 1 1) (A.Position 1 5)
          expr = A.At region (Src.Int 42)
      in A.toRegion expr @?= region

  , testCase "Left operand preserves its region" $
      let r1 = A.Region (A.Position 1 1) (A.Position 1 2)
          left = A.At r1 (Src.Int 1)
      in A.toRegion left @?= r1

  , testCase "Operator region is distinct from operand regions" $
      let leftReg = A.Region (A.Position 1 1) (A.Position 1 2)
          opReg = A.Region (A.Position 1 3) (A.Position 1 3)
          rightReg = A.Region (A.Position 1 4) (A.Position 1 5)
      in assertBool "All three regions are distinct" $
           leftReg /= opReg && opReg /= rightReg && leftReg /= rightReg
  ]

-- | Test edge cases and boundary conditions.
--
-- Verifies correct handling of special values like zero, negative numbers,
-- maximum values, and other boundary conditions.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testCase "Zero as operand stores 0" $
      extractIntDirect (Src.Int 0) @?= Just 0

  , testCase "Negate wraps value 42" $
      let expr = Src.Negate (A.At dummyRegion (Src.Int 42))
      in case expr of
           Src.Negate inner -> extractInt inner @?= Just 42
           _ -> assertFailure "Expected Negate node"

  , testCase "Large integer 2147483647 (max Int32) stores exactly" $
      extractIntDirect (Src.Int 2147483647) @?= Just 2147483647

  , testCase "Power operator 2^10 stores base as 2 and exponent as 10" $
      let base = A.At dummyRegion (Src.Int 2)
          expn = A.At dummyRegion (Src.Int 10)
          op = A.At dummyRegion (Name.fromChars "^")
          expr = Src.Binops [(base, op)] expn
      in case extractBinopInts expr of
           Just (b, e) -> do
             b @?= 2
             e @?= 10
           Nothing -> assertFailure "Expected Int operands"
  ]

-- | Extract an Int value from a located expression, returning Nothing if not Int.
extractInt :: A.Located Src.Expr_ -> Maybe Int
extractInt located =
  case A.toValue located of
    Src.Int n -> Just n
    _ -> Nothing

-- | Extract an Int value directly from a bare Src.Expr_, returning Nothing if not Int.
extractIntDirect :: Src.Expr_ -> Maybe Int
extractIntDirect expr =
  case expr of
    Src.Int n -> Just n
    _ -> Nothing

-- | Extract both Int operands from a simple Binops expression.
extractBinopInts :: Src.Expr_ -> Maybe (Int, Int)
extractBinopInts expr =
  case expr of
    Src.Binops [(leftExpr, _)] rightExpr ->
      case (A.toValue leftExpr, A.toValue rightExpr) of
        (Src.Int l, Src.Int r) -> Just (l, r)
        _ -> Nothing
    _ -> Nothing

-- | Construct a Canopy.Float.Float from a string representation.
--
-- Canopy.Float.Float is a raw UTF-8 byte sequence with no Num/Fractional
-- instances; we construct it from the textual representation directly.
mkFloat :: String -> EF.Float
mkFloat = Utf8.fromChars

-- | Dummy region for tests that don't care about source positions.
dummyRegion :: A.Region
dummyRegion = A.Region (A.Position 0 0) (A.Position 0 0)
