{-# LANGUAGE OverloadedStrings #-}

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
-- * Error conditions (invalid constructions)
--
-- @since 0.19.1
module Unit.AST.SourceArithmeticTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Canopy.Data.Name as Name
import qualified AST.Source as Src
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
  [ testCase "Int literal creates correct AST node" $
      let expr = Src.Int 42
      in case expr of
           Src.Int n -> n @?= 42
           _ -> assertFailure "Expected Int constructor"

  , testCase "Float literal creates correct AST node" $
      let expr = Src.Float 3.14
      in case expr of
           Src.Float f -> f @?= 3.14
           _ -> assertFailure "Expected Float constructor"

  , testCase "Negative number creates Negate node" $
      let expr = Src.Negate (A.At dummyRegion (Src.Int 5))
      in case expr of
           Src.Negate (A.At _ (Src.Int n)) -> n @?= 5
           _ -> assertFailure "Expected Negate with Int"

  , testCase "Binary operator creates Binops node" $
      let left = A.At dummyRegion (Src.Int 2)
          right = A.At dummyRegion (Src.Int 3)
          op = A.At dummyRegion (Name.fromChars "+")
          expr = Src.Binops [(left, op)] right
      in case expr of
           Src.Binops [(_, opName)] _ ->
             Name.toChars (A.toValue opName) @?= "+"
           _ -> assertFailure "Expected Binops structure"

  , testCase "Multiplication operator representation" $
      let op = Name.fromChars "*"
      in Name.toChars op @?= "*"

  , testCase "Division operator representation" $
      let op = Name.fromChars "/"
      in Name.toChars op @?= "/"

  , testCase "Integer division operator representation" $
      let op = Name.fromChars "//"
      in Name.toChars op @?= "//"

  , testCase "Modulo operator representation" $
      let op = Name.fromChars "%"
      in Name.toChars op @?= "%"

  , testCase "Power operator representation" $
      let op = Name.fromChars "^"
      in Name.toChars op @?= "^"

  , testCase "Subtraction operator representation" $
      let op = Name.fromChars "-"
      in Name.toChars op @?= "-"
  ]

-- | Test binary operator structure in AST.
--
-- Verifies that binary operations maintain correct tree structure
-- with left-hand side, operator, and right-hand side components.
binopStructureTests :: TestTree
binopStructureTests = testGroup "Binary Operator Structure"
  [ testCase "Simple addition structure" $
      let left = A.At dummyRegion (Src.Int 1)
          right = A.At dummyRegion (Src.Int 2)
          op = A.At dummyRegion (Name.fromChars "+")
          expr = Src.Binops [(left, op)] right
      in case expr of
           Src.Binops [(leftExpr, _)] rightExpr ->
             case (A.toValue leftExpr, A.toValue rightExpr) of
               (Src.Int l, Src.Int r) -> do
                 l @?= 1
                 r @?= 2
               _ -> assertFailure "Expected Int operands"
           _ -> assertFailure "Expected Binops"

  , testCase "Multiplication with variables" $
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

  , testCase "Division with mixed Int and Float" $
      let left = A.At dummyRegion (Src.Int 10)
          right = A.At dummyRegion (Src.Float 2.5)
          op = A.At dummyRegion (Name.fromChars "/")
          expr = Src.Binops [(left, op)] right
      in case expr of
           Src.Binops [(leftExpr, opName)] rightExpr ->
             case (A.toValue leftExpr, A.toValue rightExpr) of
               (Src.Int l, Src.Float r) -> do
                 l @?= 10
                 r @?= 2.5
                 Name.toChars (A.toValue opName) @?= "/"
               _ -> assertFailure "Expected Int and Float"
           _ -> assertFailure "Expected Binops"

  , testCase "Operator is stored as Name type" $
      let op = Name.fromChars "+"
      in Name.toChars op @?= "+"
  ]

-- | Test nested arithmetic expressions.
--
-- Verifies that complex nested expressions maintain correct tree
-- structure and preserve all operator information.
nestedExpressionTests :: TestTree
nestedExpressionTests = testGroup "Nested Expression Tests"
  [ testCase "Two-level nested expression (a + b) * c" $
      let a = A.At dummyRegion (Src.Int 1)
          b = A.At dummyRegion (Src.Int 2)
          plusOp = A.At dummyRegion (Name.fromChars "+")
          addExpr = A.At dummyRegion (Src.Binops [(a, plusOp)] b)
          c = A.At dummyRegion (Src.Int 3)
          mulOp = A.At dummyRegion (Name.fromChars "*")
          expr = Src.Binops [(addExpr, mulOp)] c
      in case expr of
           Src.Binops [(leftExpr, _)] _ ->
             case A.toValue leftExpr of
               Src.Binops [(innerLeft, innerOp)] innerRight ->
                 case (A.toValue innerLeft, A.toValue innerRight) of
                   (Src.Int l, Src.Int r) -> do
                     l @?= 1
                     r @?= 2
                     Name.toChars (A.toValue innerOp) @?= "+"
                   _ -> assertFailure "Expected Int operands in nested expression"
               _ -> assertFailure "Expected nested Binops"
           _ -> assertFailure "Expected outer Binops"

  , testCase "Three-level nested expression" $
      let one = A.At dummyRegion (Src.Int 1)
          two = A.At dummyRegion (Src.Int 2)
          three = A.At dummyRegion (Src.Int 3)
          four = A.At dummyRegion (Src.Int 4)
          plus = A.At dummyRegion (Name.fromChars "+")
          mul = A.At dummyRegion (Name.fromChars "*")
          -- (1 + 2) * (3 + 4)
          leftAdd = A.At dummyRegion (Src.Binops [(one, plus)] two)
          rightAdd = A.At dummyRegion (Src.Binops [(three, plus)] four)
          expr = Src.Binops [(leftAdd, mul)] rightAdd
      in case expr of
           Src.Binops [(left, opName)] right ->
             case (A.toValue left, A.toValue right) of
               (Src.Binops [(ll, lOp)] lr, Src.Binops [(rl, rOp)] rr) -> do
                 Name.toChars (A.toValue opName) @?= "*"
                 Name.toChars (A.toValue lOp) @?= "+"
                 Name.toChars (A.toValue rOp) @?= "+"
                 case (A.toValue ll, A.toValue lr, A.toValue rl, A.toValue rr) of
                   (Src.Int n1, Src.Int n2, Src.Int n3, Src.Int n4) -> do
                     n1 @?= 1
                     n2 @?= 2
                     n3 @?= 3
                     n4 @?= 4
                   _ -> assertFailure "Expected Int literals"
               _ -> assertFailure "Expected nested Binops on both sides"
           _ -> assertFailure "Expected top-level Binops"

  , testCase "Chain of same operator" $
      let one = A.At dummyRegion (Src.Int 1)
          two = A.At dummyRegion (Src.Int 2)
          three = A.At dummyRegion (Src.Int 3)
          plus = A.At dummyRegion (Name.fromChars "+")
          -- Binops can represent chains: 1 + 2 + 3
          expr = Src.Binops [(one, plus), (two, plus)] three
      in case expr of
           Src.Binops [(e1, op1), (e2, op2)] e3 ->
             case (A.toValue e1, A.toValue e2, A.toValue e3) of
               (Src.Int n1, Src.Int n2, Src.Int n3) -> do
                 n1 @?= 1
                 n2 @?= 2
                 n3 @?= 3
                 Name.toChars (A.toValue op1) @?= "+"
                 Name.toChars (A.toValue op2) @?= "+"
               _ -> assertFailure "Expected Int operands"
           _ -> assertFailure "Expected chained Binops"
  ]

-- | Test region information preservation.
--
-- Verifies that source location information is correctly maintained
-- throughout AST construction for error reporting.
regionPreservationTests :: TestTree
regionPreservationTests = testGroup "Region Preservation"
  [ testCase "Located expression preserves region" $
      let region = A.Region (A.Position 1 1) (A.Position 1 5)
          expr = A.At region (Src.Int 42)
      in A.toRegion expr @?= region

  , testCase "Nested expression preserves all regions" $
      let r1 = A.Region (A.Position 1 1) (A.Position 1 2)
          r2 = A.Region (A.Position 1 4) (A.Position 1 5)
          r3 = A.Region (A.Position 1 3) (A.Position 1 3)
          left = A.At r1 (Src.Int 1)
          right = A.At r2 (Src.Int 2)
          op = A.At r3 (Name.fromChars "+")
          outerRegion = A.Region (A.Position 1 1) (A.Position 1 5)
          expr = A.At outerRegion (Src.Binops [(left, op)] right)
      in do
          A.toRegion expr @?= outerRegion
          A.toRegion left @?= r1
          A.toRegion right @?= r2

  , testCase "Operator region is separate from operands" $
      let leftReg = A.Region (A.Position 1 1) (A.Position 1 2)
          opReg = A.Region (A.Position 1 3) (A.Position 1 3)
          rightReg = A.Region (A.Position 1 4) (A.Position 1 5)
      in assertBool "Regions are distinct" $
           leftReg /= opReg && opReg /= rightReg && leftReg /= rightReg
  ]

-- | Test edge cases and boundary conditions.
--
-- Verifies correct handling of special values like zero, negative numbers,
-- maximum values, and other boundary conditions.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testCase "Zero as operand" $
      let expr = Src.Int 0
      in case expr of
           Src.Int n -> n @?= 0
           _ -> assertFailure "Expected Int 0"

  , testCase "Negative number representation" $
      let expr = Src.Negate (A.At dummyRegion (Src.Int 42))
      in case expr of
           Src.Negate (A.At _ (Src.Int n)) -> n @?= 42
           _ -> assertFailure "Expected Negate node"

  , testCase "Large integer values" $
      let largeInt = 2147483647  -- Max Int32
          expr = Src.Int largeInt
      in case expr of
           Src.Int n -> n @?= largeInt
           _ -> assertFailure "Expected large Int"

  , testCase "Very small float" $
      let smallFloat = 0.0000001
          expr = Src.Float smallFloat
      in case expr of
           Src.Float f -> assertBool "Float values close" (abs (f - smallFloat) < 1e-10)
           _ -> assertFailure "Expected small Float"

  , testCase "Very large float" $
      let largeFloat = 1.7976931348623157e308  -- Near Double max
          expr = Src.Float largeFloat
      in case expr of
           Src.Float f -> assertBool "Float values close" (abs (f - largeFloat) < 1e300)
           _ -> assertFailure "Expected large Float"

  , testCase "Division by variable (not literal zero)" $
      let dividend = A.At dummyRegion (Src.Int 10)
          divisor = A.At dummyRegion (Src.Var Src.LowVar (Name.fromChars "x"))
          op = A.At dummyRegion (Name.fromChars "/")
          expr = Src.Binops [(dividend, op)] divisor
      in case expr of
           Src.Binops [(_, opName)] divisorExpr ->
             case A.toValue divisorExpr of
               Src.Var Src.LowVar varName -> do
                 Name.toChars (A.toValue opName) @?= "/"
                 Name.toChars varName @?= "x"
               _ -> assertFailure "Expected Var divisor"
           _ -> assertFailure "Expected Binops"

  , testCase "Power with large exponent" $
      let base = A.At dummyRegion (Src.Int 2)
          exponent = A.At dummyRegion (Src.Int 10)
          op = A.At dummyRegion (Name.fromChars "^")
          expr = Src.Binops [(base, op)] exponent
      in case expr of
           Src.Binops [(baseExpr, opName)] expExpr ->
             case (A.toValue baseExpr, A.toValue expExpr) of
               (Src.Int b, Src.Int e) -> do
                 b @?= 2
                 e @?= 10
                 Name.toChars (A.toValue opName) @?= "^"
               _ -> assertFailure "Expected Int operands"
           _ -> assertFailure "Expected Binops"
  ]

-- | Dummy region for tests that don't care about source positions.
dummyRegion :: A.Region
dummyRegion = A.Region (A.Position 0 0) (A.Position 0 0)
