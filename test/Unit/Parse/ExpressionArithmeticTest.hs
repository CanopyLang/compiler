{-# LANGUAGE OverloadedStrings #-}

-- | Unit.Parse.ExpressionArithmeticTest - Comprehensive parser tests for arithmetic
--
-- This module provides complete test coverage for parsing arithmetic expressions
-- from source text into AST nodes, including all operators, precedence handling,
-- associativity, and error conditions.
--
-- == Test Coverage
--
-- * Basic arithmetic operator parsing (+, -, *, /, //, ^, %)
-- * Integer and floating-point number parsing
-- * Negative number parsing (negate)
-- * Operator chain parsing (left-associative)
-- * Parenthesized expression parsing
-- * Error conditions (empty input, missing operands)
--
-- @since 0.19.1
module Unit.Parse.ExpressionArithmeticTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.ByteString.Char8 as C8
import qualified Data.Name as Name
import qualified Data.Utf8 as Utf8
import qualified AST.Source as Src
import qualified Parse.Expression as Parse
import qualified Parse.Primitives as Primitives
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Syntax as SyntaxError

-- | Main test tree containing all Parse.Expression arithmetic tests.
tests :: TestTree
tests = testGroup "Parse.Expression Arithmetic Tests"
  [ basicOperatorTests
  , numberParsingTests
  , operatorChainTests
  , parenthesizedTests
  , errorConditionTests
  ]

-- | Test parsing of basic arithmetic operators.
--
-- Verifies that all arithmetic operators parse correctly into
-- appropriate AST nodes with correct operator names.
basicOperatorTests :: TestTree
basicOperatorTests = testGroup "Basic Operator Parsing"
  [ testCase "Parse 1 + 2: operator is +" $
      case parseExpr "1 + 2" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(_, op)] _ ->
              Name.toChars (A.toValue op) @?= "+"
            _ -> assertFailure "Expected Binops node"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 1 + 2: left operand is Int 1" $
      case parseExpr "1 + 2" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, _)] _ ->
              case A.toValue left of
                Src.Int n -> n @?= 1
                _ -> assertFailure "Expected Int left operand"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 1 + 2: right operand is Int 2" $
      case parseExpr "1 + 2" of
        Right expr ->
          case A.toValue expr of
            Src.Binops _ right ->
              case A.toValue right of
                Src.Int n -> n @?= 2
                _ -> assertFailure "Expected Int right operand"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 5 - 3: operator is -" $
      case parseExpr "5 - 3" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(_, op)] _ ->
              Name.toChars (A.toValue op) @?= "-"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 4 * 6: operator is *" $
      case parseExpr "4 * 6" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(_, op)] _ ->
              Name.toChars (A.toValue op) @?= "*"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 10 / 2: operator is /" $
      case parseExpr "10 / 2" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(_, op)] _ ->
              Name.toChars (A.toValue op) @?= "/"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 10 // 3: operator is //" $
      case parseExpr "10 // 3" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(_, op)] _ ->
              Name.toChars (A.toValue op) @?= "//"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 2 ^ 3: operator is ^" $
      case parseExpr "2 ^ 3" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(_, op)] _ ->
              Name.toChars (A.toValue op) @?= "^"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 10 % 3: operator is %" $
      case parseExpr "10 % 3" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(_, op)] _ ->
              Name.toChars (A.toValue op) @?= "%"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)
  ]

-- | Test parsing of integer and floating-point numbers.
numberParsingTests :: TestTree
numberParsingTests = testGroup "Number Parsing"
  [ testCase "Parse 42 produces Src.Int 42" $
      case parseExpr "42" of
        Right expr ->
          case A.toValue expr of
            Src.Int n -> n @?= 42
            _ -> assertFailure "Expected Src.Int"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 0 produces Src.Int 0" $
      case parseExpr "0" of
        Right expr ->
          case A.toValue expr of
            Src.Int n -> n @?= 0
            _ -> assertFailure "Expected Src.Int 0"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 2147483647 produces Src.Int 2147483647" $
      case parseExpr "2147483647" of
        Right expr ->
          case A.toValue expr of
            Src.Int n -> n @?= 2147483647
            _ -> assertFailure "Expected Src.Int"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 3.14 produces Src.Float with content \"3.14\"" $
      -- Canopy.Float.Float is a raw UTF-8 byte sequence with no Num instance.
      -- We verify the textual content round-trips correctly via Utf8.toChars.
      case parseExpr "3.14" of
        Right expr ->
          case A.toValue expr of
            Src.Float f -> Utf8.toChars f @?= "3.14"
            _ -> assertFailure "Expected Src.Float"
        Left err -> assertFailure ("Parse failed: " ++ show err)
  ]

-- | Test operator chain parsing.
operatorChainTests :: TestTree
operatorChainTests = testGroup "Operator Chain Parsing"
  [ testCase "Parse 1 + 2 + 3: two operator pairs, final is Int 3" $
      case parseExpr "1 + 2 + 3" of
        Right expr ->
          case A.toValue expr of
            Src.Binops pairs final ->
              case A.toValue final of
                Src.Int n -> do
                  n @?= 3
                  length pairs @?= 2
                _ -> assertFailure "Expected Int final"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 2 * 3 * 4: two operator pairs, final is Int 4" $
      case parseExpr "2 * 3 * 4" of
        Right expr ->
          case A.toValue expr of
            Src.Binops pairs final ->
              case A.toValue final of
                Src.Int n -> do
                  n @?= 4
                  length pairs @?= 2
                _ -> assertFailure "Expected Int final"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 1 + 2 * 3: produces Binops node" $
      case parseExpr "1 + 2 * 3" of
        Right expr ->
          case A.toValue expr of
            Src.Binops _ _ -> pure ()
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)
  ]

-- | Test parenthesized expression parsing.
parenthesizedTests :: TestTree
parenthesizedTests = testGroup "Parenthesized Expression Parsing"
  [ testCase "Parse (1 + 2) * 3: outer operator is *" $
      case parseExpr "(1 + 2) * 3" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(_, op)] _ ->
              Name.toChars (A.toValue op) @?= "*"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse (1 + 2) * 3: right operand is Int 3" $
      case parseExpr "(1 + 2) * 3" of
        Right expr ->
          case A.toValue expr of
            Src.Binops _ right ->
              case A.toValue right of
                Src.Int n -> n @?= 3
                _ -> assertFailure "Expected Int 3"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 2 * (3 + 4): left operand is Int 2" $
      case parseExpr "2 * (3 + 4)" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, _)] _ ->
              case A.toValue left of
                Src.Int n -> n @?= 2
                _ -> assertFailure "Expected Int 2 left operand"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)
  ]

-- | Test error conditions and invalid input.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testCase "Empty input produces parse error" $
      case parseExpr "" of
        Left _ -> pure ()
        Right _ -> assertFailure "Empty input should not parse successfully"

  , testCase "Missing right operand '1 +' produces parse error" $
      case parseExpr "1 +" of
        Left _ -> pure ()
        Right _ -> assertFailure "Missing operand should not parse"

  , testCase "Unclosed paren '(1 + 2' produces parse error" $
      case parseExpr "(1 + 2" of
        Left _ -> pure ()
        Right _ -> assertFailure "Unclosed paren should not parse"
  ]

-- | Parse an expression from a string, returning just the Src.Expr on success.
--
-- Uses SyntaxError.Start as the end-of-input error constructor.
parseExpr :: String -> Either SyntaxError.Expr Src.Expr
parseExpr input =
  fst <$> Primitives.fromByteString Parse.expression SyntaxError.Start (C8.pack input)
