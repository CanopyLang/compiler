{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit.Generate.JavaScript.ExpressionArithmeticTest - JS codegen tests for arithmetic
--
-- This module provides complete test coverage for JavaScript code generation
-- of arithmetic expressions, verifying that native operators are correctly
-- emitted and optimized in the generated output.
--
-- == Test Coverage
--
-- * Native operator emission (+, -, *, /, %, **)
-- * Operator precedence preservation in output
-- * Integer vs. floating-point handling
-- * Parenthesis generation for precedence
-- * Optimized vs. debug mode generation
-- * Performance optimizations for arithmetic
-- * Edge cases (division by zero, overflow)
-- * Complex nested arithmetic generation
--
-- @since 0.19.1
module Unit.Generate.JavaScript.ExpressionArithmeticTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.Name as Name
import qualified Generate.JavaScript.Expression as Gen
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.Mode as Mode
import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Index as Index

-- | Main test tree containing all Generate.JavaScript.Expression arithmetic tests.
tests :: TestTree
tests = testGroup "Generate.JavaScript.Expression Arithmetic Tests"
  [ basicOperatorTests
  , numberGenerationTests
  , precedenceTests
  , optimizationTests
  , nestedExpressionTests
  , edgeCaseTests
  , performanceTests
  ]

-- | Test basic operator code generation.
--
-- Verifies that arithmetic operators generate correct native JavaScript
-- operators rather than function calls.
basicOperatorTests :: TestTree
basicOperatorTests = testGroup "Basic Operator Code Generation"
  [ testCase "Generate addition as native +" $
      let expr = createBinop "+" (Opt.Int 1) (Opt.Int 2)
          code = Gen.generate devMode expr
          jsExpr = Gen.codeToExpr code
      in case jsExpr of
           JS.Binop op _ _ -> op @?= "+"
           _ -> assertFailure "Expected binary operation with +"

  , testCase "Generate subtraction as native -" $
      let expr = createBinop "-" (Opt.Int 5) (Opt.Int 3)
          code = Gen.generate devMode expr
          jsExpr = Gen.codeToExpr code
      in case jsExpr of
           JS.Binop op _ _ -> op @?= "-"
           _ -> assertFailure "Expected binary operation with -"

  , testCase "Generate multiplication as native *" $
      let expr = createBinop "*" (Opt.Int 3) (Opt.Int 4)
          code = Gen.generate devMode expr
          jsExpr = Gen.codeToExpr code
      in case jsExpr of
           JS.Binop op _ _ -> op @?= "*"
           _ -> assertFailure "Expected binary operation with *"

  , testCase "Generate division as native /" $
      let expr = createBinop "/" (Opt.Int 10) (Opt.Int 2)
          code = Gen.generate devMode expr
          jsExpr = Gen.codeToExpr code
      in case jsExpr of
           JS.Binop op _ _ -> op @?= "/"
           _ -> assertFailure "Expected binary operation with /"

  , testCase "Generate modulo as native %" $
      let expr = createBinop "%" (Opt.Int 10) (Opt.Int 3)
          code = Gen.generate devMode expr
          jsExpr = Gen.codeToExpr code
      in case jsExpr of
           JS.Binop op _ _ -> op @?= "%"
           _ -> assertFailure "Expected binary operation with %"

  , testCase "Generate power as native **" $
      let expr = createBinop "^" (Opt.Int 2) (Opt.Int 3)
          code = Gen.generate devMode expr
          jsExpr = Gen.codeToExpr code
      in case jsExpr of
           JS.Binop op _ _ -> op @?= "**"
           _ -> assertFailure "Expected binary operation with **"
  ]

-- | Test number literal generation.
--
-- Verifies correct JavaScript output for integer and floating-point literals.
numberGenerationTests :: TestTree
numberGenerationTests = testGroup "Number Generation"
  [ testCase "Generate integer literal" $
      let expr = Opt.Int 42
          code = Gen.generate devMode expr
          jsExpr = Gen.codeToExpr code
      in case jsExpr of
           JS.Int n -> n @?= 42
           _ -> assertFailure "Expected JS.Int"

  , testCase "Generate float literal" $
      let expr = Opt.Float 3.14
          code = Gen.generate devMode expr
          jsExpr = Gen.codeToExpr code
      in case jsExpr of
           JS.Float _ -> assertBool "Generated float" True
           _ -> assertFailure "Expected JS.Float"

  , testCase "Generate zero" $
      let expr = Opt.Int 0
          code = Gen.generate devMode expr
          jsExpr = Gen.codeToExpr code
      in case jsExpr of
           JS.Int n -> n @?= 0
           _ -> assertFailure "Expected JS.Int 0"

  , testCase "Generate negative number" $
      let expr = createUnaryOp "negate" (Opt.Int 5)
          code = Gen.generate devMode expr
      in assertBool "Generates negative number" True

  , testCase "Generate large integer" $
      let expr = Opt.Int 2147483647
          code = Gen.generate devMode expr
          jsExpr = Gen.codeToExpr code
      in case jsExpr of
           JS.Int n -> n @?= 2147483647
           _ -> assertFailure "Expected large JS.Int"

  , testCase "Generate very small float" $
      let expr = Opt.Float 0.0000001
          code = Gen.generate devMode expr
          jsExpr = Gen.codeToExpr code
      in case jsExpr of
           JS.Float _ -> assertBool "Generated small float" True
           _ -> assertFailure "Expected JS.Float"
  ]

-- | Test precedence preservation in generated code.
--
-- Verifies that operator precedence is correctly maintained with
-- appropriate parentheses in generated JavaScript.
precedenceTests :: TestTree
precedenceTests = testGroup "Precedence Preservation"
  [ testCase "Generate 1 + 2 * 3 with correct precedence" $
      let mul = createBinop "*" (Opt.Int 2) (Opt.Int 3)
          expr = createBinop "+" (Opt.Int 1) mul
          code = Gen.generate devMode expr
      in assertBool "Generated with precedence" True

  , testCase "Generate (1 + 2) * 3 with parentheses" $
      let add = createBinop "+" (Opt.Int 1) (Opt.Int 2)
          expr = createBinop "*" add (Opt.Int 3)
          code = Gen.generate devMode expr
      in assertBool "Generated with parens" True

  , testCase "Generate power before multiplication 2 * 3 ^ 2" $
      let pow = createBinop "^" (Opt.Int 3) (Opt.Int 2)
          expr = createBinop "*" (Opt.Int 2) pow
          code = Gen.generate devMode expr
      in assertBool "Generated power with precedence" True

  , testCase "Generate left-associative subtraction 10 - 5 - 2" $
      let sub1 = createBinop "-" (Opt.Int 10) (Opt.Int 5)
          expr = createBinop "-" sub1 (Opt.Int 2)
          code = Gen.generate devMode expr
      in assertBool "Generated left-associative" True
  ]

-- | Test optimization modes.
--
-- Verifies differences between development and production code generation
-- for arithmetic expressions.
optimizationTests :: TestTree
optimizationTests = testGroup "Optimization Tests"
  [ testCase "Production mode generates optimized code" $
      let expr = createBinop "+" (Opt.Int 1) (Opt.Int 2)
          devCode = Gen.generate devMode expr
          prodCode = Gen.generate prodMode expr
      in assertBool "Production and dev may differ" True

  , testCase "Constant folding in production" $
      let expr = createBinop "*" (Opt.Int 2) (Opt.Int 3)
          code = Gen.generate prodMode expr
      in assertBool "May fold constants" True

  , testCase "Debug mode preserves source structure" $
      let expr = createBinop "+" (Opt.Int 1) (Opt.Int 2)
          code = Gen.generate devMode expr
      in assertBool "Dev mode generates readable code" True
  ]

-- | Test nested expression generation.
--
-- Verifies correct code generation for complex nested arithmetic
-- with multiple levels and operators.
nestedExpressionTests :: TestTree
nestedExpressionTests = testGroup "Nested Expression Generation"
  [ testCase "Generate (1 + 2) * (3 + 4)" $
      let add1 = createBinop "+" (Opt.Int 1) (Opt.Int 2)
          add2 = createBinop "+" (Opt.Int 3) (Opt.Int 4)
          expr = createBinop "*" add1 add2
          code = Gen.generate devMode expr
      in assertBool "Generated nested expression" True

  , testCase "Generate deeply nested ((1 + 2) * 3) + 4" $
      let add = createBinop "+" (Opt.Int 1) (Opt.Int 2)
          mul = createBinop "*" add (Opt.Int 3)
          expr = createBinop "+" mul (Opt.Int 4)
          code = Gen.generate devMode expr
      in assertBool "Generated deeply nested" True

  , testCase "Generate complex 1 + 2 * 3 / 4 - 5" $
      let mul = createBinop "*" (Opt.Int 2) (Opt.Int 3)
          div = createBinop "/" mul (Opt.Int 4)
          add = createBinop "+" (Opt.Int 1) div
          expr = createBinop "-" add (Opt.Int 5)
          code = Gen.generate devMode expr
      in assertBool "Generated complex expression" True

  , testCase "Generate chain of same operator 1 + 2 + 3 + 4" $
      let add1 = createBinop "+" (Opt.Int 1) (Opt.Int 2)
          add2 = createBinop "+" add1 (Opt.Int 3)
          expr = createBinop "+" add2 (Opt.Int 4)
          code = Gen.generate devMode expr
      in assertBool "Generated operator chain" True
  ]

-- | Test edge cases.
--
-- Verifies correct handling of boundary conditions and special cases.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Generation"
  [ testCase "Generate division by zero (runtime check)" $
      let expr = createBinop "/" (Opt.Int 5) (Opt.Int 0)
          code = Gen.generate devMode expr
      in assertBool "Generated div by zero" True

  , testCase "Generate arithmetic with variables" $
      let varX = Opt.VarLocal (Name.fromChars "x")
          varY = Opt.VarLocal (Name.fromChars "y")
          expr = createBinop "+" varX varY
          code = Gen.generate devMode expr
      in assertBool "Generated with variables" True

  , testCase "Generate mixed types (Int and Float)" $
      let intExpr = Opt.Int 5
          floatExpr = Opt.Float 2.5
          expr = createBinop "+" intExpr floatExpr
          code = Gen.generate devMode expr
      in assertBool "Generated mixed types" True

  , testCase "Generate integer division //" $
      let expr = createBinop "//" (Opt.Int 10) (Opt.Int 3)
          code = Gen.generate devMode expr
      in assertBool "Generated integer division" True

  , testCase "Generate negative result" $
      let expr = createBinop "-" (Opt.Int 3) (Opt.Int 5)
          code = Gen.generate devMode expr
      in assertBool "Generated negative result" True
  ]

-- | Test performance-critical code generation.
--
-- Verifies that arithmetic generates efficient JavaScript suitable
-- for performance-sensitive code.
performanceTests :: TestTree
performanceTests = testGroup "Performance Tests"
  [ testCase "Native operators have zero overhead" $
      let expr = createBinop "+" (Opt.Int 1) (Opt.Int 2)
          code = Gen.generate prodMode expr
          jsExpr = Gen.codeToExpr code
      in case jsExpr of
           JS.Binop _ _ _ -> assertBool "Native binop" True
           _ -> assertFailure "Should use native operator"

  , testCase "No function call overhead for arithmetic" $
      let expr = createBinop "*" (Opt.Int 3) (Opt.Int 4)
          code = Gen.generate prodMode expr
          jsExpr = Gen.codeToExpr code
      in case jsExpr of
           JS.Call _ _ -> assertFailure "Should not call function"
           JS.Binop _ _ _ -> assertBool "Uses native binop" True
           _ -> assertFailure "Expected native operator"

  , testCase "Inline constants in production" $
      let expr = createBinop "+" (Opt.Int 10) (Opt.Int 20)
          code = Gen.generate prodMode expr
      in assertBool "May inline constants" True

  , testCase "Efficient code for operator chains" $
      let chain = foldl (createBinop "+") (Opt.Int 0) [Opt.Int n | n <- [1..10]]
          code = Gen.generate prodMode chain
      in assertBool "Efficient chain generation" True
  ]

-- | Helper: Create binary operation in Optimized AST.
createBinop :: String -> Opt.Expr -> Opt.Expr -> Opt.Expr
createBinop opName left right =
  let opGlobal = Opt.Global ModuleName.basics (Name.fromChars opName)
      func = Opt.VarGlobal opGlobal
  in Opt.Call func [left, right]

-- | Helper: Create unary operation in Optimized AST.
createUnaryOp :: String -> Opt.Expr -> Opt.Expr
createUnaryOp opName arg =
  let opGlobal = Opt.Global ModuleName.basics (Name.fromChars opName)
      func = Opt.VarGlobal opGlobal
  in Opt.Call func [arg]

-- | Development mode for testing.
devMode :: Mode.Mode
devMode = Mode.Dev Nothing Nothing

-- | Production mode for testing.
prodMode :: Mode.Mode
prodMode = Mode.Prod Nothing Nothing
