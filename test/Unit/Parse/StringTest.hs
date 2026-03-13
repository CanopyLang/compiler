{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for string and character literal parsing.
--
-- This module tests the string and character parsing logic implemented in
-- @Parse.String@, exercised through the public @Parse.Expression@ parser.
-- It covers simple string literals, escape sequences, unicode escapes,
-- character literals, multi-line (triple-quoted) strings, and the error
-- cases for unterminated or malformed literals.
--
-- The test harness uses 'Parse.fromByteString' with 'Parse.Expression.expression'
-- to drive parsing, matching on the 'Src.Str' and 'Src.Chr' AST constructors.
--
-- @since 0.19.1
module Unit.Parse.StringTest (tests) where

import qualified AST.Source as Src
import qualified Canopy.String as ES
import qualified Data.ByteString.Char8 as C8
import qualified Parse.Expression as Expr
import qualified Parse.Primitives as Parse
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Syntax as SyntaxError
import Test.Tasty
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

-- ---------------------------------------------------------------------------
-- Test harness
-- ---------------------------------------------------------------------------

-- | Parse a Canopy expression from a raw Haskell string.
--
-- Returns the first successful expression or the first syntax error
-- encountered.  Position information is discarded via 'fst'.
parseExpr :: [Char] -> Either SyntaxError.Expr Src.Expr
parseExpr s =
  fst <$> Parse.fromByteString Expr.expression SyntaxError.Start (C8.pack s)

-- ---------------------------------------------------------------------------
-- Top-level test tree
-- ---------------------------------------------------------------------------

-- | All string and character literal parsing tests.
tests :: TestTree
tests =
  testGroup
    "Parse.String"
    [ testSimpleStrings,
      testEscapeSequences,
      testUnicodeEscapes,
      testCharacterLiterals,
      testStringErrors,
      testCharErrors,
      testMultiLineStrings
    ]

-- ---------------------------------------------------------------------------
-- Simple string literals
-- ---------------------------------------------------------------------------

-- | Tests for ordinary double-quoted string literals.
testSimpleStrings :: TestTree
testSimpleStrings =
  testGroup
    "simple strings"
    [ testCase "hello" $ case parseExpr "\"hello\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "hello"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "empty string" $ case parseExpr "\"\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= ""
        other -> assertFailure ("unexpected: " <> show other),
      testCase "with spaces" $ case parseExpr "\"with spaces\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "with spaces"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "single character" $ case parseExpr "\"z\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "z"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "digits" $ case parseExpr "\"123\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "123"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "punctuation" $ case parseExpr "\"hello, world!\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "hello, world!"
        other -> assertFailure ("unexpected: " <> show other)
    ]

-- ---------------------------------------------------------------------------
-- Escape sequences
-- ---------------------------------------------------------------------------

-- | Tests for recognised backslash escape sequences inside string literals.
testEscapeSequences :: TestTree
testEscapeSequences =
  testGroup
    "escape sequences"
    [ testCase "newline escape" $ case parseExpr "\"\\n\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "\\n"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "tab escape" $ case parseExpr "\"\\t\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "\\t"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "backslash escape" $ case parseExpr "\"\\\\\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "\\\\"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "double-quote escape" $ case parseExpr "\"\\\"\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "\\\""
        other -> assertFailure ("unexpected: " <> show other),
      testCase "carriage-return escape" $ case parseExpr "\"\\r\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "\\r"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "single-quote escape in string" $ case parseExpr "\"\\'\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "\\'"
        other -> assertFailure ("unexpected: " <> show other)
    ]

-- ---------------------------------------------------------------------------
-- Unicode escapes
-- ---------------------------------------------------------------------------

-- | Tests for @\\u{XXXX}@ unicode escape sequences inside string literals.
testUnicodeEscapes :: TestTree
testUnicodeEscapes =
  testGroup
    "unicode escapes"
    [ testCase "U+0041 is A" $ case parseExpr "\"\\u{0041}\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "\\u0041"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "U+006F is o" $ case parseExpr "\"\\u{006F}\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "\\u006F"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "U+1F600 is emoji" $ case parseExpr "\"\\u{01F600}\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "\\uD83D\\uDE00"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "bad unicode: no braces" $ case parseExpr "\"\\u0041\"" of
        Left (SyntaxError.String (SyntaxError.StringEscape (SyntaxError.BadUnicodeFormat _)) _ _) ->
          return ()
        other -> assertFailure ("expected BadUnicodeFormat, got: " <> show other),
      testCase "bad unicode: too few digits" $ case parseExpr "\"\\u{041}\"" of
        Left (SyntaxError.String (SyntaxError.StringEscape (SyntaxError.BadUnicodeLength {})) _ _) ->
          return ()
        other -> assertFailure ("expected BadUnicodeLength, got: " <> show other),
      testCase "bad unicode: out of range" $ case parseExpr "\"\\u{110000}\"" of
        Left (SyntaxError.String (SyntaxError.StringEscape (SyntaxError.BadUnicodeCode _)) _ _) ->
          return ()
        other -> assertFailure ("expected BadUnicodeCode, got: " <> show other)
    ]

-- ---------------------------------------------------------------------------
-- Character literals
-- ---------------------------------------------------------------------------

-- | Tests for single-character literals delimited by single quotes.
testCharacterLiterals :: TestTree
testCharacterLiterals =
  testGroup
    "character literals"
    [ testCase "plain char" $ case parseExpr "'x'" of
        Right (Ann.At _ (Src.Chr s)) -> ES.toChars s @?= "x"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "newline escape in char" $ case parseExpr "'\\n'" of
        Right (Ann.At _ (Src.Chr s)) -> ES.toChars s @?= "\\n"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "tab escape in char" $ case parseExpr "'\\t'" of
        Right (Ann.At _ (Src.Chr s)) -> ES.toChars s @?= "\\t"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "backslash escape in char" $ case parseExpr "'\\\\'" of
        Right (Ann.At _ (Src.Chr s)) -> ES.toChars s @?= "\\\\"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "digit char" $ case parseExpr "'7'" of
        Right (Ann.At _ (Src.Chr s)) -> ES.toChars s @?= "7"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "double-quote in char literal" $ case parseExpr "'\"'" of
        Right (Ann.At _ (Src.Chr s)) -> ES.toChars s @?= "\\\""
        other -> assertFailure ("unexpected: " <> show other)
    ]

-- ---------------------------------------------------------------------------
-- String error cases
-- ---------------------------------------------------------------------------

-- | Tests for malformed string literals that the parser must reject.
testStringErrors :: TestTree
testStringErrors =
  testGroup
    "string errors"
    [ testCase "unterminated single-line string" $ case parseExpr "\"hello" of
        Left (SyntaxError.String SyntaxError.StringEndless_Single _ _) -> return ()
        other -> assertFailure ("expected StringEndless_Single, got: " <> show other),
      testCase "bad escape character" $ case parseExpr "\"\\q\"" of
        Left (SyntaxError.String (SyntaxError.StringEscape SyntaxError.EscapeUnknown) _ _) ->
          return ()
        other -> assertFailure ("expected EscapeUnknown, got: " <> show other)
    ]

-- ---------------------------------------------------------------------------
-- Character error cases
-- ---------------------------------------------------------------------------

-- | Tests for malformed character literals that the parser must reject.
testCharErrors :: TestTree
testCharErrors =
  testGroup
    "character errors"
    [ testCase "unterminated char literal" $ case parseExpr "'" of
        Left (SyntaxError.Char SyntaxError.CharEndless _ _) -> return ()
        other -> assertFailure ("expected CharEndless, got: " <> show other),
      testCase "multi-char in char literal" $ case parseExpr "'ab'" of
        Left (SyntaxError.Char (SyntaxError.CharNotString _) _ _) -> return ()
        other -> assertFailure ("expected CharNotString, got: " <> show other),
      testCase "bad escape in char literal" $ case parseExpr "'\\q'" of
        Left (SyntaxError.Char (SyntaxError.CharEscape SyntaxError.EscapeUnknown) _ _) ->
          return ()
        other -> assertFailure ("expected CharEscape EscapeUnknown, got: " <> show other)
    ]

-- ---------------------------------------------------------------------------
-- Multi-line strings
-- ---------------------------------------------------------------------------

-- | Tests for triple-quoted multi-line string literals.
testMultiLineStrings :: TestTree
testMultiLineStrings =
  testGroup
    "multi-line strings"
    [ testCase "simple triple-quoted" $ case parseExpr "\"\"\"hello\"\"\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "hello"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "empty triple-quoted" $ case parseExpr "\"\"\"\"\"\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= ""
        other -> assertFailure ("unexpected: " <> show other),
      testCase "newline preserved in multi-line" $
        case parseExpr "\"\"\"line1\nline2\"\"\"" of
          Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "line1\\nline2"
          other -> assertFailure ("unexpected: " <> show other),
      testCase "unterminated multi-line string" $ case parseExpr "\"\"\"hello" of
        Left (SyntaxError.String SyntaxError.StringEndless_Multi _ _) -> return ()
        other -> assertFailure ("expected StringEndless_Multi, got: " <> show other),
      testCase "escape in multi-line" $ case parseExpr "\"\"\"a\\nb\"\"\"" of
        Right (Ann.At _ (Src.Str s)) -> ES.toChars s @?= "a\\nb"
        other -> assertFailure ("unexpected: " <> show other)
    ]
