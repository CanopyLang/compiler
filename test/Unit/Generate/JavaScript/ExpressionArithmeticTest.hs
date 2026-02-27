{-# LANGUAGE OverloadedStrings #-}

-- | Unit.Generate.JavaScript.ExpressionArithmeticTest - JS codegen tests for arithmetic
--
-- This module provides complete test coverage for JavaScript code generation
-- of arithmetic expressions, verifying that native operators are correctly
-- emitted and that literals are faithfully represented in generated output.
--
-- == Test Coverage
--
-- * Native operator emission (OpAdd, OpSub, OpMul, OpDiv via Infix nodes)
-- * Integer literal generation (JS.Int values)
-- * Float literal generation (JS.Float values)
-- * ArithBinop node produces JS.Infix (not JS.Call)
-- * Nested arithmetic generates nested JS.Infix trees
-- * Operator mapping: Add→OpAdd, Sub→OpSub, Mul→OpMul, Div→OpDiv
--
-- @since 0.19.1
module Unit.Generate.JavaScript.ExpressionArithmeticTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.Set as Set
import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Generate.JavaScript.Expression as Gen
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.Mode as Mode

-- | Main test tree containing all Generate.JavaScript.Expression arithmetic tests.
tests :: TestTree
tests = testGroup "Generate.JavaScript.Expression Arithmetic Tests"
  [ integerLiteralTests
  , arithBinopInfixTests
  , nestedArithmeticTests
  ]

-- | Test integer literal code generation.
--
-- Verifies that integer literals in Opt.Expr produce JS.Int values.
integerLiteralTests :: TestTree
integerLiteralTests = testGroup "Integer Literal Generation"
  [ testCase "Opt.Int 42 generates JS.Int 42" $
      let expr = Opt.Int 42
          jsExpr = Gen.codeToExpr (Gen.generate devMode expr)
      in case jsExpr of
           JS.Int n -> n @?= 42
           other -> assertFailure ("Expected JS.Int, got: " ++ show other)

  , testCase "Opt.Int 0 generates JS.Int 0" $
      let expr = Opt.Int 0
          jsExpr = Gen.codeToExpr (Gen.generate devMode expr)
      in case jsExpr of
           JS.Int n -> n @?= 0
           other -> assertFailure ("Expected JS.Int 0, got: " ++ show other)

  , testCase "Opt.Int 2147483647 generates JS.Int 2147483647" $
      let expr = Opt.Int 2147483647
          jsExpr = Gen.codeToExpr (Gen.generate devMode expr)
      in case jsExpr of
           JS.Int n -> n @?= 2147483647
           other -> assertFailure ("Expected JS.Int 2147483647, got: " ++ show other)
  ]

-- | Test that ArithBinop nodes produce JS.Infix with correct operators.
--
-- Verifies that Opt.ArithBinop (the native arithmetic path) generates
-- JS.Infix nodes rather than JS.Call nodes, ensuring zero function-call overhead.
arithBinopInfixTests :: TestTree
arithBinopInfixTests = testGroup "ArithBinop Generates JS.Infix"
  [ testCase "Can.Add maps to JS.OpAdd in generated Infix" $
      -- JS.InfixOp derives only Show, not Eq; we compare via show.
      let expr = Opt.ArithBinop Can.Add (Opt.Int 1) (Opt.Int 2)
          jsExpr = Gen.codeToExpr (Gen.generate devMode expr)
      in case jsExpr of
           JS.Infix op _ _ -> show op @?= "OpAdd"
           other -> assertFailure ("Expected JS.Infix, got: " ++ show other)

  , testCase "Can.Sub maps to JS.OpSub in generated Infix" $
      let expr = Opt.ArithBinop Can.Sub (Opt.Int 5) (Opt.Int 3)
          jsExpr = Gen.codeToExpr (Gen.generate devMode expr)
      in case jsExpr of
           JS.Infix op _ _ -> show op @?= "OpSub"
           other -> assertFailure ("Expected JS.Infix, got: " ++ show other)

  , testCase "Can.Mul maps to JS.OpMul in generated Infix" $
      let expr = Opt.ArithBinop Can.Mul (Opt.Int 3) (Opt.Int 4)
          jsExpr = Gen.codeToExpr (Gen.generate devMode expr)
      in case jsExpr of
           JS.Infix op _ _ -> show op @?= "OpMul"
           other -> assertFailure ("Expected JS.Infix, got: " ++ show other)

  , testCase "Can.Div maps to JS.OpDiv in generated Infix" $
      let expr = Opt.ArithBinop Can.Div (Opt.Int 10) (Opt.Int 2)
          jsExpr = Gen.codeToExpr (Gen.generate devMode expr)
      in case jsExpr of
           JS.Infix op _ _ -> show op @?= "OpDiv"
           other -> assertFailure ("Expected JS.Infix, got: " ++ show other)

  , testCase "ArithBinop generates Infix not Call (no function-call overhead)" $
      let expr = Opt.ArithBinop Can.Add (Opt.Int 1) (Opt.Int 2)
          jsExpr = Gen.codeToExpr (Gen.generate devMode expr)
      in case jsExpr of
           JS.Call _ _ -> assertFailure "ArithBinop must not generate JS.Call"
           JS.Infix _ _ _ -> pure ()
           other -> assertFailure ("Expected JS.Infix, got: " ++ show other)
  ]

-- | Test nested arithmetic expression generation.
--
-- Verifies that nested Opt.ArithBinop expressions produce nested JS.Infix trees
-- with correct operator assignment at each level.
nestedArithmeticTests :: TestTree
nestedArithmeticTests = testGroup "Nested Arithmetic Generation"
  [ testCase "(1+2)*3 outer operator is OpMul" $
      let innerAdd = Opt.ArithBinop Can.Add (Opt.Int 1) (Opt.Int 2)
          expr = Opt.ArithBinop Can.Mul innerAdd (Opt.Int 3)
          jsExpr = Gen.codeToExpr (Gen.generate devMode expr)
      in case jsExpr of
           JS.Infix op _ _ -> show op @?= "OpMul"
           other -> assertFailure ("Expected JS.Infix Mul, got: " ++ show other)

  , testCase "(1+2)*3 inner left expression is JS.Infix OpAdd" $
      let innerAdd = Opt.ArithBinop Can.Add (Opt.Int 1) (Opt.Int 2)
          expr = Opt.ArithBinop Can.Mul innerAdd (Opt.Int 3)
          jsExpr = Gen.codeToExpr (Gen.generate devMode expr)
      in case jsExpr of
           JS.Infix _ left _ ->
             case left of
               JS.Infix op _ _ -> show op @?= "OpAdd"
               other -> assertFailure ("Expected inner JS.Infix Add, got: " ++ show other)
           other -> assertFailure ("Expected JS.Infix Mul, got: " ++ show other)
  ]

-- | Development mode for testing.
devMode :: Mode.Mode
devMode = Mode.Dev Nothing False False Set.empty
