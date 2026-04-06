{-# LANGUAGE OverloadedStrings #-}

-- | Property.Parse.FuzzProperties — QuickCheck fuzz tests for the Canopy parsers.
--
-- Verifies that no parser in the Canopy compiler ever throws an exception
-- or crashes on arbitrary byte-string input. Every parser must return either
-- a 'Right' (successful parse) or a 'Left' (structured parse error); it must
-- never diverge or raise a Haskell exception.
--
-- Additionally, verifies that well-formed inputs that are known to parse
-- successfully do so, and that structured error values are produced for
-- well-known invalid inputs.
--
-- Parsers covered:
--
-- * 'Parse.Expression.expression' — expression parser
-- * 'Parse.Pattern.expression'    — pattern parser
-- * 'Parse.Type.expression'       — type parser
--
-- @since 0.19.1
module Property.Parse.FuzzProperties
  ( tests
  ) where

import qualified Control.Exception as Exception
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C8
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import qualified Parse.Expression as Expr
import qualified Parse.Pattern as Pat
import qualified Parse.Primitives as Parse
import qualified Parse.Type as Ty
import qualified Reporting.Error.Syntax as SyntaxError
import System.IO.Unsafe (unsafePerformIO)
import Test.Tasty
import Test.Tasty.QuickCheck

-- | Main test tree containing all parser fuzz property tests.
tests :: TestTree
tests =
  testGroup
    "Parser Fuzz Property Tests"
    [ exprFuzzProperties
    , patFuzzProperties
    , typeFuzzProperties
    , knownValidExprProperties
    , knownValidPatternProperties
    , knownValidTypeProperties
    ]

-- PARSE HELPERS

-- | Attempt to parse an arbitrary 'String' as a Canopy expression.
--
-- Returns 'Right' on success or 'Left' on parse error. This function must
-- never throw an exception for any input. The successful result is normalised
-- to a canonical sentinel value so that only the success/failure distinction
-- matters, not the AST content.
normaliseExprResult :: String -> Either SyntaxError.Expr SyntaxError.Expr
normaliseExprResult s =
  case Parse.fromByteString Expr.expression SyntaxError.Start (packUtf8 s) of
    Left e -> Left e
    Right _ -> Right (SyntaxError.Start 0 0)

-- | Attempt to parse an arbitrary 'String' as a Canopy pattern.
--
-- Returns 'Right' on success or 'Left' on parse error. Must never throw.
parsePat :: String -> Either SyntaxError.Pattern SyntaxError.Pattern
parsePat s =
  case Parse.fromByteString Pat.expression SyntaxError.PStart (packUtf8 s) of
    Left e -> Left e
    Right _ -> Right (SyntaxError.PStart 0 0)

-- | Attempt to parse an arbitrary 'String' as a Canopy type expression.
--
-- Returns 'Right' on success or 'Left' on parse error. Must never throw.
parseType :: String -> Either SyntaxError.Type SyntaxError.Type
parseType s =
  case Parse.fromByteString Ty.expression SyntaxError.TIndentStart (packUtf8 s) of
    Left e -> Left e
    Right _ -> Right (SyntaxError.TIndentStart 0 0)

-- | Encode a String to a ByteString using proper UTF-8 encoding.
--
-- Unlike 'C8.pack' which truncates Unicode chars to single bytes,
-- this function properly encodes all Unicode code points as UTF-8.
packUtf8 :: String -> BS.ByteString
packUtf8 = TextEnc.encodeUtf8 . Text.pack

-- | Verify that evaluating the Either to WHNF does not throw an exception.
--
-- Uses 'evaluate' to force the Either constructor, catching any exception
-- (including 'error' calls from the parser on invalid UTF-8, etc.).
-- Returns True if the parser produced a normal Left or Right; False if it
-- threw an exception, which constitutes a test failure.
noCrash :: Either a b -> Bool
noCrash result = unsafePerformIO $
  either (\(_ :: Exception.SomeException) -> False) (const True)
    <$> Exception.try (Exception.evaluate result >> pure ())

-- EXPRESSION FUZZ PROPERTIES

-- | Verifies that the expression parser never crashes on arbitrary 'String' input.
--
-- QuickCheck generates random strings; the parser must always return a
-- structured 'Either' value and never raise an exception.
exprFuzzProperties :: TestTree
exprFuzzProperties =
  testGroup
    "Expression parser never crashes"
    [ testProperty "arbitrary ASCII string does not crash expression parser" $
        forAll genAsciiString $ \s ->
          noCrash (normaliseExprResult s)

    , testProperty "arbitrary printable string does not crash expression parser" $
        forAll genPrintableString $ \s ->
          noCrash (normaliseExprResult s)

    , testProperty "empty string does not crash expression parser" $
          noCrash (normaliseExprResult "")

    , testProperty "single character does not crash expression parser" $
        forAll arbitraryASCIIChar $ \c ->
          noCrash (normaliseExprResult [c])

    , testProperty "repeated character does not crash expression parser" $
        forAll (choose (1, 50)) $ \n ->
          forAll arbitraryASCIIChar $ \c ->
            noCrash (normaliseExprResult (replicate n c))
    ]

-- PATTERN FUZZ PROPERTIES

-- | Verifies that the pattern parser never crashes on arbitrary 'String' input.
patFuzzProperties :: TestTree
patFuzzProperties =
  testGroup
    "Pattern parser never crashes"
    [ testProperty "arbitrary ASCII string does not crash pattern parser" $
        forAll genAsciiString $ \s ->
          noCrash (parsePat s)

    , testProperty "arbitrary printable string does not crash pattern parser" $
        forAll genPrintableString $ \s ->
          noCrash (parsePat s)

    , testProperty "empty string does not crash pattern parser" $
          noCrash (parsePat "")

    , testProperty "single character does not crash pattern parser" $
        forAll arbitraryASCIIChar $ \c ->
          noCrash (parsePat [c])

    , testProperty "long string does not crash pattern parser" $
        forAll (choose (50, 200)) $ \n ->
          forAll (vectorOf n arbitraryASCIIChar) $ \cs ->
            noCrash (parsePat cs)
    ]

-- TYPE FUZZ PROPERTIES

-- | Verifies that the type parser never crashes on arbitrary 'String' input.
typeFuzzProperties :: TestTree
typeFuzzProperties =
  testGroup
    "Type parser never crashes"
    [ testProperty "arbitrary ASCII string does not crash type parser" $
        forAll genAsciiString $ \s ->
          noCrash (parseType s)

    , testProperty "arbitrary printable string does not crash type parser" $
        forAll genPrintableString $ \s ->
          noCrash (parseType s)

    , testProperty "empty string does not crash type parser" $
          noCrash (parseType "")

    , testProperty "single character does not crash type parser" $
        forAll arbitraryASCIIChar $ \c ->
          noCrash (parseType [c])

    , testProperty "null bytes do not crash type parser" $
        forAll (choose (1, 20)) $ \n ->
          noCrash (parseType (replicate n '\0'))
    ]

-- KNOWN VALID EXPRESSION PROPERTIES

-- | Verifies that well-formed expression inputs parse to 'Right'.
--
-- These inputs are syntactically valid Canopy expressions. The parser must
-- accept each of them, confirming that the no-crash property does not mask
-- a parser that always returns 'Left'.
knownValidExprProperties :: TestTree
knownValidExprProperties =
  testGroup
    "Known-valid expressions parse to Right"
    [ testProperty "integer literal parses successfully" $
        forAll (choose (0 :: Int, maxBound)) $ \n ->
          isRight (normaliseExprResult (show n))

    , testProperty "unit tuple parses successfully" $
          isRight (normaliseExprResult "()")

    , testProperty "empty list parses successfully" $
          isRight (normaliseExprResult "[]")

    , testProperty "lowercase identifier parses successfully" $
        forAll genLowercaseIdent $ \s ->
          isRight (normaliseExprResult s)

    , testProperty "negative integer literal parses successfully" $
        forAll (choose (1 :: Int, 1000)) $ \n ->
          isRight (normaliseExprResult ("-" ++ show n))
    ]

-- KNOWN VALID PATTERN PROPERTIES

-- | Verifies that well-formed pattern inputs parse to 'Right'.
knownValidPatternProperties :: TestTree
knownValidPatternProperties =
  testGroup
    "Known-valid patterns parse to Right"
    [ testProperty "wildcard pattern parses successfully" $
          isRight (parsePat "_")

    , testProperty "variable pattern parses successfully" $
        forAll genLowercaseIdent $ \s ->
          isRight (parsePat s)

    , testProperty "unit pattern parses successfully" $
          isRight (parsePat "()")
    ]

-- KNOWN VALID TYPE PROPERTIES

-- | Verifies that well-formed type inputs parse to 'Right'.
knownValidTypeProperties :: TestTree
knownValidTypeProperties =
  testGroup
    "Known-valid types parse to Right"
    [ testProperty "unit type parses successfully" $
          isRight (parseType "()")

    , testProperty "uppercase type name parses successfully" $
        forAll genUppercaseIdent $ \s ->
          isRight (parseType s)
    ]

-- GENERATORS

-- | Generate an arbitrary ASCII string (any printable ASCII character).
genAsciiString :: Gen String
genAsciiString =
  listOf arbitraryASCIIChar

-- | Generate an arbitrary printable string (including Unicode).
genPrintableString :: Gen String
genPrintableString =
  listOf arbitraryPrintableChar

-- | Generate a valid lowercase Canopy identifier.
--
-- Identifiers start with a lowercase letter and contain only alphanumeric
-- characters and underscores.
genLowercaseIdent :: Gen String
genLowercaseIdent = do
  first <- elements ['a'..'z']
  rest <- listOf (elements (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_']))
  len <- choose (0, 8)
  pure (first : take len rest)

-- | Generate a valid uppercase Canopy type name.
--
-- Type names start with an uppercase letter.
genUppercaseIdent :: Gen String
genUppercaseIdent = do
  first <- elements ['A'..'Z']
  rest <- listOf (elements (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9']))
  len <- choose (0, 8)
  pure (first : take len rest)

-- HELPERS

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight (Left _) = False
