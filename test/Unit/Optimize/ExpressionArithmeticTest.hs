{-# LANGUAGE OverloadedStrings #-}

-- | Unit.Optimize.ExpressionArithmeticTest - Comprehensive tests for arithmetic optimization
--
-- This module provides complete test coverage for arithmetic operator optimization
-- in the Optimize.Expression module, including native operator transformation to
-- ArithBinop nodes, user-defined operator preservation as Call nodes, and correct
-- operand optimization.
--
-- == Test Coverage
--
-- * Native operator optimization (NativeArith → ArithBinop)
-- * User-defined operator preservation (UserDefined → Call)
-- * ArithBinop operator type preservation (Add, Sub, Mul, Div)
-- * Int operand values preserved through optimization
-- * Nested arithmetic optimization
--
-- @since 0.19.1
module Unit.Optimize.ExpressionArithmeticTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Name as Name
import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Package
import qualified Optimize.Expression as OptExpr
import qualified Optimize.Names as Names
import qualified Reporting.Annotation as A

-- | Main test tree containing all Optimize.Expression arithmetic tests.
tests :: TestTree
tests = testGroup "Optimize.Expression Arithmetic Tests"
  [ nativeArithmeticOptimizationTests
  , userDefinedOperatorTests
  , operandValueTests
  , nestedExpressionTests
  ]

-- | Test native arithmetic operator optimization.
--
-- Verifies that native arithmetic operators (NativeArith) are correctly
-- transformed to ArithBinop nodes by the real optimizer.
-- We use Can.VarLocal as operands because the optimizer constant-folds
-- literal-only expressions; non-constant operands prevent folding.
nativeArithmeticOptimizationTests :: TestTree
nativeArithmeticOptimizationTests = testGroup "Native Arithmetic Optimization"
  [ testCase "NativeArith Add → Opt.ArithBinop Can.Add" $
      let expr = mkBinopExpr (Can.NativeArith Can.Add) (Can.VarLocal varX) (Can.VarLocal varY)
      in case runOptimize expr of
           Opt.ArithBinop Can.Add _ _ -> pure ()
           other -> assertFailure ("Expected ArithBinop Add, got: " ++ show other)

  , testCase "NativeArith Sub → Opt.ArithBinop Can.Sub" $
      let expr = mkBinopExpr (Can.NativeArith Can.Sub) (Can.VarLocal varX) (Can.VarLocal varY)
      in case runOptimize expr of
           Opt.ArithBinop Can.Sub _ _ -> pure ()
           other -> assertFailure ("Expected ArithBinop Sub, got: " ++ show other)

  , testCase "NativeArith Mul → Opt.ArithBinop Can.Mul" $
      let expr = mkBinopExpr (Can.NativeArith Can.Mul) (Can.VarLocal varX) (Can.VarLocal varY)
      in case runOptimize expr of
           Opt.ArithBinop Can.Mul _ _ -> pure ()
           other -> assertFailure ("Expected ArithBinop Mul, got: " ++ show other)

  , testCase "NativeArith Div → Opt.ArithBinop Can.Div" $
      let expr = mkBinopExpr (Can.NativeArith Can.Div) (Can.VarLocal varX) (Can.VarLocal varY)
      in case runOptimize expr of
           Opt.ArithBinop Can.Div _ _ -> pure ()
           other -> assertFailure ("Expected ArithBinop Div, got: " ++ show other)
  ]

-- | Test user-defined operator preservation.
--
-- Verifies that user-defined operators remain as Call nodes after optimization,
-- not transformed into ArithBinop.
userDefinedOperatorTests :: TestTree
userDefinedOperatorTests = testGroup "User-Defined Operator Tests"
  [ testCase "UserDefined operator → Opt.Call (not ArithBinop)" $
      let opName = Name.fromChars "+++"
          home = ModuleName.Canonical Package.core "CustomOps"
          funcName = Name.fromChars "concat"
          expr = mkBinopExpr (Can.UserDefined opName home funcName) (Can.Int 1) (Can.Int 2)
      in case runOptimize expr of
           Opt.ArithBinop _ _ _ -> assertFailure "UserDefined must not produce ArithBinop"
           Opt.Call _ args -> length args @?= 2
           other -> assertFailure ("Expected Call with 2 args, got: " ++ show other)
  ]

-- | Test that operand values are preserved through optimization.
--
-- Verifies that non-foldable operands in ArithBinop emerge intact after
-- the optimization pass. We use VarLocal (unknown at compile time) to
-- prevent constant folding, and use non-identity integer constants paired
-- with variables to prevent identity-rule elimination.
operandValueTests :: TestTree
operandValueTests = testGroup "Operand Value Preservation"
  [ testCase "Left Int 42 preserved in ArithBinop Add" $
      -- 42 + x: 42 is not an identity element, and x is a var → ArithBinop preserved
      let expr = mkBinopExpr (Can.NativeArith Can.Add) (Can.Int 42) (Can.VarLocal varX)
      in case runOptimize expr of
           Opt.ArithBinop _ (Opt.Int n) _ -> n @?= 42
           other -> assertFailure ("Expected ArithBinop with Int 42, got: " ++ show other)

  , testCase "Right Int 99 preserved in ArithBinop Add" $
      -- x + 99: 99 is not an identity element → ArithBinop preserved
      let expr = mkBinopExpr (Can.NativeArith Can.Add) (Can.VarLocal varX) (Can.Int 99)
      in case runOptimize expr of
           Opt.ArithBinop _ _ (Opt.Int n) -> n @?= 99
           other -> assertFailure ("Expected ArithBinop with Int 99, got: " ++ show other)

  , testCase "Both VarLocal operands x and y preserved in ArithBinop Mul" $
      -- x * y: both variables, no folding possible → ArithBinop with both vars
      let expr = mkBinopExpr (Can.NativeArith Can.Mul) (Can.VarLocal varX) (Can.VarLocal varY)
      in case runOptimize expr of
           Opt.ArithBinop Can.Mul (Opt.VarLocal lName) (Opt.VarLocal rName) -> do
             Name.toChars lName @?= "x"
             Name.toChars rName @?= "y"
           other -> assertFailure ("Expected ArithBinop Mul(x,y), got: " ++ show other)
  ]

-- | Test nested arithmetic optimization.
--
-- Verifies that nested NativeArith expressions produce nested ArithBinop nodes.
-- We use VarLocal operands to prevent constant folding, ensuring the nested
-- structure is preserved in the optimizer output.
nestedExpressionTests :: TestTree
nestedExpressionTests = testGroup "Nested Arithmetic Optimization"
  [ testCase "(x+y)+z produces nested ArithBinop Add" $
      let innerAdd = mkBinopExpr (Can.NativeArith Can.Add) (Can.VarLocal varX) (Can.VarLocal varY)
          outerAdd = mkBinopExpr (Can.NativeArith Can.Add) innerAdd (Can.VarLocal varZ)
      in case runOptimize outerAdd of
           Opt.ArithBinop Can.Add (Opt.ArithBinop Can.Add _ _) _ -> pure ()
           other -> assertFailure ("Expected nested ArithBinop Add, got: " ++ show other)

  , testCase "(x+y)*z produces ArithBinop Mul with inner ArithBinop Add" $
      let innerAdd = mkBinopExpr (Can.NativeArith Can.Add) (Can.VarLocal varX) (Can.VarLocal varY)
          outerMul = mkBinopExpr (Can.NativeArith Can.Mul) innerAdd (Can.VarLocal varZ)
      in case runOptimize outerMul of
           Opt.ArithBinop Can.Mul (Opt.ArithBinop Can.Add _ _) _ -> pure ()
           other -> assertFailure ("Expected ArithBinop Mul(Add, z), got: " ++ show other)
  ]

-- | Construct a Can.Expr_ BinopOp node with a dummy annotation.
mkBinopExpr :: Can.BinopKind -> Can.Expr_ -> Can.Expr_ -> Can.Expr_
mkBinopExpr kind leftVal rightVal =
  Can.BinopOp kind dummyAnnotation (A.At dummyRegion leftVal) (A.At dummyRegion rightVal)

-- | Run the real optimizer on a Can.Expr_ and return the result Opt.Expr.
runOptimize :: Can.Expr_ -> Opt.Expr
runOptimize expr =
  let (_, _, result) = Names.run (OptExpr.optimize Set.empty (A.At dummyRegion expr))
  in result

-- | Dummy annotation: a rank-0 universally quantified unit type.
dummyAnnotation :: Can.Annotation
dummyAnnotation = Can.Forall Map.empty Can.TUnit

-- | Test variable name "x" for use as a non-foldable operand.
varX :: Name.Name
varX = Name.fromChars "x"

-- | Test variable name "y" for use as a non-foldable operand.
varY :: Name.Name
varY = Name.fromChars "y"

-- | Test variable name "z" for use as a non-foldable operand.
varZ :: Name.Name
varZ = Name.fromChars "z"

-- | Dummy region for test nodes (row 0, col 0 to row 0, col 0).
dummyRegion :: A.Region
dummyRegion = A.Region (A.Position 0 0) (A.Position 0 0)
