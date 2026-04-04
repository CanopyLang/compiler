-- | Unit tests for the 'Parse.Number' module.
--
-- Tests cover integer parsing, hexadecimal parsing, float parsing
-- (including scientific notation), error cases such as leading zeros
-- and invalid hex digits, and the single-digit operator precedence parser.
--
-- Each test drives the parser through 'Parse.fromByteString' with a small
-- local error type so that failure modes can be inspected precisely.
--
-- @since 0.19.1
module Unit.Parse.NumberTest (tests) where

import qualified AST.Utils.Binop as Binop
import qualified Data.ByteString.Char8 as C8
import qualified Parse.Number as Number
import qualified Parse.Primitives as Parse
import qualified Reporting.Error.Syntax as SyntaxError
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

-- ERROR TYPE

-- | Thin error wrapper used as the @x@ type variable for 'Parse.fromByteString'.
--
-- 'Expect' is emitted when the parser finds no number at all (empty input or
-- non-digit start). 'NumErr' carries the specific 'SyntaxError.Number'
-- diagnostic produced mid-parse.
data ParseError
  = Expect Parse.Row Parse.Col
  | NumErr SyntaxError.Number Parse.Row Parse.Col
  deriving (Show)

-- TEST HARNESS

-- | Run 'Number.number' against a 'String' and return the parsed 'Number.Number'
-- or a 'ParseError'.
parseNumber :: String -> Either ParseError Number.Number
parseNumber s =
  Parse.fromByteString
    (Number.number Expect toNumErr)
    Expect
    (C8.pack s)
  where
    toNumErr numErr r c = NumErr numErr r c

-- | Run 'Number.precedence' against a 'String' and return the parsed
-- 'Binop.Precedence' or a 'ParseError'.
parsePrecedence :: String -> Either ParseError Binop.Precedence
parsePrecedence s =
  Parse.fromByteString
    (Number.precedence Expect)
    Expect
    (C8.pack s)

-- TESTS

-- | Top-level test tree for 'Parse.Number'.
tests :: TestTree
tests =
  testGroup
    "Parse.Number"
    [ testIntegers,
      testHex,
      testFloats,
      testErrors,
      testPrecedence,
      testLargeIntegers,
      testPreciseFloats,
      testScientificEdgeCases
    ]

-- INTEGER PARSING

testIntegers :: TestTree
testIntegers =
  testGroup
    "integer parsing"
    [ testCase "single digit 1" $ assertIntResult "1" 1,
      testCase "single digit 0" $ assertIntResult "0" 0,
      testCase "multi-digit 42" $ assertIntResult "42" 42,
      testCase "multi-digit 100" $ assertIntResult "100" 100,
      testCase "large number 999999" $ assertIntResult "999999" 999999,
      testCase "single digit 9" $ assertIntResult "9" 9
    ]

-- HEX PARSING

testHex :: TestTree
testHex =
  testGroup
    "hex parsing"
    [ testCase "0xFF is 255" $ assertIntResult "0xFF" 255,
      testCase "0x0 is 0" $ assertIntResult "0x0" 0,
      testCase "0xDEAD" $ assertIntResult "0xDEAD" 0xDEAD,
      testCase "0xdeadBEEF lowercase and upper" $ assertIntResult "0xdeadBEEF" 0xdeadBEEF,
      testCase "0x10 is 16" $ assertIntResult "0x10" 16,
      testCase "0xA is 10" $ assertIntResult "0xA" 10
    ]

-- FLOAT PARSING

testFloats :: TestTree
testFloats =
  testGroup
    "float parsing"
    [ testCase "3.14 parses as Float" $
        isFloat (parseNumber "3.14") @?= True,
      testCase "1.0 parses as Float" $
        isFloat (parseNumber "1.0") @?= True,
      testCase "1e10 scientific notation" $
        isFloat (parseNumber "1e10") @?= True,
      testCase "1E10 uppercase E" $
        isFloat (parseNumber "1E10") @?= True,
      testCase "1.5e+2 positive exponent" $
        isFloat (parseNumber "1.5e+2") @?= True,
      testCase "2.5E-3 negative exponent" $
        isFloat (parseNumber "2.5E-3") @?= True,
      testCase "0.5 zero integer part" $
        isFloat (parseNumber "0.5") @?= True,
      testCase "100.001 many fraction digits" $
        isFloat (parseNumber "100.001") @?= True
    ]

-- ERROR CASES

testErrors :: TestTree
testErrors =
  testGroup
    "error cases"
    [ testCase "empty input returns Expect" $
        isExpect (parseNumber "") @?= True,
      testCase "abc (non-digit start) returns Expect" $
        isExpect (parseNumber "abc") @?= True,
      testCase "01 leading zero error" $ case parseNumber "01" of
        Left (NumErr SyntaxError.NumberNoLeadingZero _ _) -> return ()
        Left err -> assertFailure ("expected NumberNoLeadingZero, got: " <> show err)
        Right _ -> assertFailure "expected error, got success",
      testCase "0x bare hex prefix with no digits" $ case parseNumber "0x" of
        Left (NumErr SyntaxError.NumberHexDigit _ _) -> return ()
        Left err -> assertFailure ("expected NumberHexDigit, got: " <> show err)
        Right _ -> assertFailure "expected error, got success",
      testCase "0xGG invalid hex digits" $ case parseNumber "0xGG" of
        Left (NumErr SyntaxError.NumberHexDigit _ _) -> return ()
        Left err -> assertFailure ("expected NumberHexDigit, got: " <> show err)
        Right _ -> assertFailure "expected error, got success",
      testCase "1. trailing dot with no fraction" $ case parseNumber "1." of
        Left (NumErr (SyntaxError.NumberDot 1) _ _) -> return ()
        Left err -> assertFailure ("expected NumberDot 1, got: " <> show err)
        Right _ -> assertFailure "expected error, got success",
      testCase "1e bare exponent with no digits" $ case parseNumber "1e" of
        Left (NumErr SyntaxError.NumberEnd _ _) -> return ()
        Left err -> assertFailure ("expected NumberEnd, got: " <> show err)
        Right _ -> assertFailure "expected error, got success",
      testCase "1e+ exponent sign with no digits" $ case parseNumber "1e+" of
        Left (NumErr SyntaxError.NumberEnd _ _) -> return ()
        Left err -> assertFailure ("expected NumberEnd, got: " <> show err)
        Right _ -> assertFailure "expected error, got success"
    ]

-- PRECEDENCE PARSING

testPrecedence :: TestTree
testPrecedence =
  testGroup
    "precedence parsing"
    [ testCase "digit 0 gives Precedence 0" $ case parsePrecedence "0" of
        Right (Binop.Precedence 0) -> return ()
        other -> assertFailure ("expected Precedence 0, got: " <> show other),
      testCase "digit 1 gives Precedence 1" $ case parsePrecedence "1" of
        Right (Binop.Precedence 1) -> return ()
        other -> assertFailure ("expected Precedence 1, got: " <> show other),
      testCase "digit 5 gives Precedence 5" $ case parsePrecedence "5" of
        Right (Binop.Precedence 5) -> return ()
        other -> assertFailure ("expected Precedence 5, got: " <> show other),
      testCase "digit 9 gives Precedence 9" $ case parsePrecedence "9" of
        Right (Binop.Precedence 9) -> return ()
        other -> assertFailure ("expected Precedence 9, got: " <> show other),
      testCase "non-digit returns Expect" $
        isExpect (parsePrecedence "a") @?= True,
      testCase "empty returns Expect" $
        isExpect (parsePrecedence "") @?= True
    ]

-- HELPERS

-- | Assert that the given input parses as an 'Int' equal to the expected value.
assertIntResult :: String -> Int -> IO ()
assertIntResult input expected = case parseNumber input of
  Right (Number.Int n) -> n @?= expected
  Left err -> assertFailure ("expected Int " <> show expected <> ", got error: " <> show err)
  Right (Number.Float _) -> assertFailure ("expected Int " <> show expected <> ", got Float")

-- | Return 'True' when the parse result is a 'Number.Float'.
isFloat :: Either ParseError Number.Number -> Bool
isFloat (Right (Number.Float _)) = True
isFloat _ = False

-- | Return 'True' when the parse result is an 'Expect' error.
isExpect :: Either ParseError a -> Bool
isExpect (Left (Expect _ _)) = True
isExpect _ = False

-- LARGE INTEGERS

-- | Tests for large integer values within the parser's range.
testLargeIntegers :: TestTree
testLargeIntegers =
  testGroup
    "large integers"
    [ testCase "1000000 parses as Int" $ assertIntResult "1000000" 1000000,
      testCase "2147483647 (max Int32) parses as Int" $ assertIntResult "2147483647" 2147483647,
      testCase "0xFFFFFF is 16777215" $ assertIntResult "0xFFFFFF" 0xFFFFFF
    ]

-- PRECISE FLOATS

-- | Tests for floats with many decimal places and small magnitudes.
testPreciseFloats :: TestTree
testPreciseFloats =
  testGroup
    "precise floats"
    [ testCase "0.000001 parses as Float" $
        isFloat (parseNumber "0.000001") @?= True,
      testCase "1.23456789 parses as Float" $
        isFloat (parseNumber "1.23456789") @?= True,
      testCase "9.99999999 parses as Float" $
        isFloat (parseNumber "9.99999999") @?= True
    ]

-- SCIENTIFIC NOTATION EDGE CASES

-- | Tests for edge cases in scientific notation parsing.
testScientificEdgeCases :: TestTree
testScientificEdgeCases =
  testGroup
    "scientific edge cases"
    [ testCase "1e0 is Float" $ isFloat (parseNumber "1e0") @?= True,
      testCase "1E0 uppercase E is Float" $ isFloat (parseNumber "1E0") @?= True,
      testCase "1e+0 explicit positive exponent is Float" $
        isFloat (parseNumber "1e+0") @?= True,
      testCase "1e-0 explicit zero negative exponent is Float" $
        isFloat (parseNumber "1e-0") @?= True,
      testCase "1e-1 is Float" $ isFloat (parseNumber "1e-1") @?= True
    ]
