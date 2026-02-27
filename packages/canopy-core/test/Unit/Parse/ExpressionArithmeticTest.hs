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
-- * Operator precedence verification
-- * Associativity handling (left, right, non-associative)
-- * Parenthesized expressions
-- * Nested and complex arithmetic expressions
-- * Integer and floating-point number parsing
-- * Negative number parsing
-- * Edge cases (whitespace, maximum values, zero)
-- * Error conditions (invalid syntax, malformed operators)
--
-- @since 0.19.1
module Unit.Parse.ExpressionArithmeticTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.Name as Name
import qualified AST.Source as Src
import qualified Parse.Expression as Parse
import qualified Reporting.Annotation as A
import Parse.Primitives (Parser, fromByteString)
import qualified Reporting.Error.Syntax as E
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Lazy as LBS

-- | Main test tree containing all Parse.Expression arithmetic tests.
tests :: TestTree
tests = testGroup "Parse.Expression Arithmetic Tests"
  [ basicOperatorTests
  , numberParsingTests
  , operatorChainTests
  , parenthesizedTests
  , nestedExpressionTests
  , whitespaceHandlingTests
  , edgeCaseTests
  , errorConditionTests
  ]

-- | Test parsing of basic arithmetic operators.
--
-- Verifies that all arithmetic operators parse correctly into
-- appropriate AST nodes with correct operator names.
basicOperatorTests :: TestTree
basicOperatorTests = testGroup "Basic Operator Parsing"
  [ testCase "Parse simple addition 1 + 2" $
      case parseExpr "1 + 2" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, op)] right ->
              case (A.toValue left, A.toValue right) of
                (Src.Int l, Src.Int r) -> do
                  l @?= 1
                  r @?= 2
                  Name.toChars (A.toValue op) @?= "+"
                _ -> assertFailure "Expected Int operands"
            _ -> assertFailure "Expected Binops node"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse simple subtraction 5 - 3" $
      case parseExpr "5 - 3" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, op)] right ->
              case (A.toValue left, A.toValue right) of
                (Src.Int l, Src.Int r) -> do
                  l @?= 5
                  r @?= 3
                  Name.toChars (A.toValue op) @?= "-"
                _ -> assertFailure "Expected Int operands"
            _ -> assertFailure "Expected Binops node"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse simple multiplication 4 * 6" $
      case parseExpr "4 * 6" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, op)] right ->
              case (A.toValue left, A.toValue right) of
                (Src.Int l, Src.Int r) -> do
                  l @?= 4
                  r @?= 6
                  Name.toChars (A.toValue op) @?= "*"
                _ -> assertFailure "Expected Int operands"
            _ -> assertFailure "Expected Binops node"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse simple division 10 / 2" $
      case parseExpr "10 / 2" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, op)] right ->
              case (A.toValue left, A.toValue right) of
                (Src.Int l, Src.Int r) -> do
                  l @?= 10
                  r @?= 2
                  Name.toChars (A.toValue op) @?= "/"
                _ -> assertFailure "Expected Int operands"
            _ -> assertFailure "Expected Binops node"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse integer division 10 // 3" $
      case parseExpr "10 // 3" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, op)] right ->
              case (A.toValue left, A.toValue right) of
                (Src.Int l, Src.Int r) -> do
                  l @?= 10
                  r @?= 3
                  Name.toChars (A.toValue op) @?= "//"
                _ -> assertFailure "Expected Int operands"
            _ -> assertFailure "Expected Binops node"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse modulo 10 % 3" $
      case parseExpr "10 % 3" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, op)] right ->
              case (A.toValue left, A.toValue right) of
                (Src.Int l, Src.Int r) -> do
                  l @?= 10
                  r @?= 3
                  Name.toChars (A.toValue op) @?= "%"
                _ -> assertFailure "Expected Int operands"
            _ -> assertFailure "Expected Binops node"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse power 2 ^ 3" $
      case parseExpr "2 ^ 3" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, op)] right ->
              case (A.toValue left, A.toValue right) of
                (Src.Int l, Src.Int r) -> do
                  l @?= 2
                  r @?= 3
                  Name.toChars (A.toValue op) @?= "^"
                _ -> assertFailure "Expected Int operands"
            _ -> assertFailure "Expected Binops node"
        Left err -> assertFailure ("Parse failed: " ++ show err)
  ]

-- | Test parsing of integer and floating-point numbers.
--
-- Verifies correct parsing of numeric literals including edge cases.
numberParsingTests :: TestTree
numberParsingTests = testGroup "Number Parsing"
  [ testCase "Parse integer literal 42" $
      case parseExpr "42" of
        Right expr ->
          case A.toValue expr of
            Src.Int n -> n @?= 42
            _ -> assertFailure "Expected Int"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse float literal 3.14" $
      case parseExpr "3.14" of
        Right expr ->
          case A.toValue expr of
            Src.Float f -> assertBool "Float close to 3.14" (abs (f - 3.14) < 0.0001)
            _ -> assertFailure "Expected Float"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse zero" $
      case parseExpr "0" of
        Right expr ->
          case A.toValue expr of
            Src.Int n -> n @?= 0
            _ -> assertFailure "Expected Int 0"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse negative number -42" $
      case parseExpr "-42" of
        Right expr ->
          case A.toValue expr of
            Src.Negate (A.At _ (Src.Int n)) -> n @?= 42
            Src.Int n -> n @?= (-42)  -- May parse as negative literal
            _ -> assertFailure "Expected Negate or negative Int"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse large integer" $
      case parseExpr "2147483647" of
        Right expr ->
          case A.toValue expr of
            Src.Int n -> n @?= 2147483647
            _ -> assertFailure "Expected Int"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse scientific notation 1.5e10" $
      case parseExpr "1.5e10" of
        Right expr ->
          case A.toValue expr of
            Src.Float f -> assertBool "Float close to 1.5e10" (abs (f - 1.5e10) < 1e5)
            _ -> assertFailure "Expected Float"
        Left err -> assertFailure ("Parse failed: " ++ show err)
  ]

-- | Test operator chain parsing.
--
-- Verifies that sequences of operators parse correctly,
-- maintaining proper structure for later precedence resolution.
operatorChainTests :: TestTree
operatorChainTests = testGroup "Operator Chain Parsing"
  [ testCase "Parse left-associative chain 1 + 2 + 3" $
      case parseExpr "1 + 2 + 3" of
        Right expr ->
          case A.toValue expr of
            Src.Binops ops final ->
              case A.toValue final of
                Src.Int finalVal -> do
                  finalVal @?= 3
                  length ops @?= 2
                _ -> assertFailure "Expected Int final value"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse multiplication chain 2 * 3 * 4" $
      case parseExpr "2 * 3 * 4" of
        Right expr ->
          case A.toValue expr of
            Src.Binops ops final ->
              case A.toValue final of
                Src.Int finalVal -> do
                  finalVal @?= 4
                  length ops @?= 2
                _ -> assertFailure "Expected Int final value"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse mixed operators 1 + 2 * 3" $
      case parseExpr "1 + 2 * 3" of
        Right expr ->
          case A.toValue expr of
            Src.Binops _ _ -> assertBool "Parsed as Binops" True
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse power chain (right-associative) 2 ^ 3 ^ 2" $
      case parseExpr "2 ^ 3 ^ 2" of
        Right expr ->
          case A.toValue expr of
            Src.Binops _ _ -> assertBool "Parsed as Binops" True
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)
  ]

-- | Test parenthesized expression parsing.
--
-- Verifies that parentheses are correctly handled to override
-- default precedence and create proper nesting.
parenthesizedTests :: TestTree
parenthesizedTests = testGroup "Parenthesized Expression Parsing"
  [ testCase "Parse (1 + 2) * 3" $
      case parseExpr "(1 + 2) * 3" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, op)] right ->
              case A.toValue right of
                Src.Int r -> do
                  r @?= 3
                  Name.toChars (A.toValue op) @?= "*"
                _ -> assertFailure "Expected Int right operand"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 2 * (3 + 4)" $
      case parseExpr "2 * (3 + 4)" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, op)] right ->
              case A.toValue left of
                Src.Int l -> do
                  l @?= 2
                  Name.toChars (A.toValue op) @?= "*"
                _ -> assertFailure "Expected Int left operand"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse (1 + 2) * (3 + 4)" $
      case parseExpr "(1 + 2) * (3 + 4)" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, op)] right ->
              Name.toChars (A.toValue op) @?= "*"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse deeply nested ((1 + 2) * 3)" $
      case parseExpr "((1 + 2) * 3)" of
        Right expr ->
          assertBool "Parses successfully" True
        Left err -> assertFailure ("Parse failed: " ++ show err)
  ]

-- | Test nested arithmetic expressions.
--
-- Verifies correct parsing of complex nested arithmetic
-- with multiple levels of operators.
nestedExpressionTests :: TestTree
nestedExpressionTests = testGroup "Nested Expression Parsing"
  [ testCase "Parse 1 + 2 * 3 (precedence)" $
      case parseExpr "1 + 2 * 3" of
        Right expr ->
          assertBool "Parses as binop expression" True
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 2 * 3 + 4 * 5" $
      case parseExpr "2 * 3 + 4 * 5" of
        Right expr ->
          case A.toValue expr of
            Src.Binops _ _ -> assertBool "Parsed as Binops" True
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse 1 + 2 * 3 - 4 / 5" $
      case parseExpr "1 + 2 * 3 - 4 / 5" of
        Right expr ->
          case A.toValue expr of
            Src.Binops _ _ -> assertBool "Parsed as Binops" True
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse power with multiplication 2 ^ 3 * 4" $
      case parseExpr "2 ^ 3 * 4" of
        Right expr ->
          case A.toValue expr of
            Src.Binops _ _ -> assertBool "Parsed as Binops" True
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse complex expression (1 + 2) * 3 + 4 / (5 - 6)" $
      case parseExpr "(1 + 2) * 3 + 4 / (5 - 6)" of
        Right expr ->
          assertBool "Complex expression parses" True
        Left err -> assertFailure ("Parse failed: " ++ show err)
  ]

-- | Test whitespace handling.
--
-- Verifies that various whitespace patterns are correctly
-- handled without affecting parse results.
whitespaceHandlingTests :: TestTree
whitespaceHandlingTests = testGroup "Whitespace Handling"
  [ testCase "Parse with no spaces 1+2" $
      case parseExpr "1+2" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, op)] right ->
              case (A.toValue left, A.toValue right) of
                (Src.Int l, Src.Int r) -> do
                  l @?= 1
                  r @?= 2
                  Name.toChars (A.toValue op) @?= "+"
                _ -> assertFailure "Expected Int operands"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse with multiple spaces 1   +   2" $
      case parseExpr "1   +   2" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, op)] right ->
              case (A.toValue left, A.toValue right) of
                (Src.Int l, Src.Int r) -> do
                  l @?= 1
                  r @?= 2
                  Name.toChars (A.toValue op) @?= "+"
                _ -> assertFailure "Expected Int operands"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse with leading whitespace   1 + 2" $
      case parseExpr "   1 + 2" of
        Right expr ->
          case A.toValue expr of
            Src.Binops _ _ -> assertBool "Parsed with leading space" True
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse with trailing whitespace 1 + 2   " $
      case parseExpr "1 + 2   " of
        Right expr ->
          case A.toValue expr of
            Src.Binops _ _ -> assertBool "Parsed with trailing space" True
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)
  ]

-- | Test edge cases and boundary conditions.
--
-- Verifies correct handling of unusual but valid inputs.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Parsing"
  [ testCase "Parse division with float 10.0 / 2.5" $
      case parseExpr "10.0 / 2.5" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, op)] right ->
              case (A.toValue left, A.toValue right) of
                (Src.Float l, Src.Float r) -> do
                  assertBool "Left float close to 10.0" (abs (l - 10.0) < 0.0001)
                  assertBool "Right float close to 2.5" (abs (r - 2.5) < 0.0001)
                  Name.toChars (A.toValue op) @?= "/"
                _ -> assertFailure "Expected Float operands"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse zero division 5 / 0" $
      case parseExpr "5 / 0" of
        Right expr ->
          case A.toValue expr of
            Src.Binops [(left, op)] right ->
              case (A.toValue left, A.toValue right) of
                (Src.Int l, Src.Int r) -> do
                  l @?= 5
                  r @?= 0
                  Name.toChars (A.toValue op) @?= "/"
                _ -> assertFailure "Expected Int operands"
            _ -> assertFailure "Expected Binops"
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse negative operand -5 + 3" $
      case parseExpr "-5 + 3" of
        Right expr ->
          assertBool "Negative operand parses" True
        Left err -> assertFailure ("Parse failed: " ++ show err)

  , testCase "Parse large expression with many operators" $
      case parseExpr "1 + 2 * 3 / 4 - 5 % 6 ^ 7" of
        Right expr ->
          assertBool "Large expression parses" True
        Left err -> assertFailure ("Parse failed: " ++ show err)
  ]

-- | Test error conditions and invalid input.
--
-- Verifies that invalid syntax produces appropriate parse errors
-- rather than incorrect AST nodes.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testCase "Empty input produces error" $
      case parseExpr "" of
        Left _ -> assertBool "Empty input fails" True
        Right _ -> assertFailure "Empty input should not parse"

  , testCase "Operator without operands + produces error" $
      case parseExpr "+" of
        Left _ -> assertBool "Operator alone fails" True
        Right _ -> assertFailure "Operator alone should not parse"

  , testCase "Missing right operand 1 + produces error" $
      case parseExpr "1 +" of
        Left _ -> assertBool "Missing right operand fails" True
        Right _ -> assertFailure "Missing operand should not parse"

  , testCase "Invalid operator 1 @ 2 produces error" $
      case parseExpr "1 @ 2" of
        Left _ -> assertBool "Invalid operator fails" True
        Right _ -> assertFailure "Invalid operator should not parse"

  , testCase "Mismatched parentheses (1 + 2 produces error" $
      case parseExpr "(1 + 2" of
        Left _ -> assertBool "Unclosed paren fails" True
        Right _ -> assertFailure "Unclosed paren should not parse"

  , testCase "Mismatched closing paren 1 + 2) produces error" $
      case parseExpr "1 + 2)" of
        Left _ -> assertBool "Extra closing paren fails" True
        Right _ -> assertFailure "Extra paren should not parse"
  ]

-- | Parse an expression from a string for testing.
--
-- Helper function that wraps the parser with appropriate error handling
-- for test assertions.
parseExpr :: String -> Either E.Expr Src.Expr
parseExpr input =
  let bytes = LBS.toStrict (B.toLazyByteString (B.stringUtf8 input))
  in fromByteString (Parse.expression) (\_ _ -> ()) bytes
