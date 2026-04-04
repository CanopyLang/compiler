{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for 'Parse.Symbol'.
--
-- Tests the 'operator' parser via 'Parse.fromByteString', covering valid
-- operator tokens, reserved-operator rejections, multi-character operators,
-- and the 'binopCharSet' membership predicate.
--
-- The 'operator' parser takes two error callbacks: one for an empty match
-- (no operator characters at all) and one for a reserved sequence.  Both
-- are unified into 'SymError' here so that 'fromByteString' can be used
-- directly.
--
-- @since 0.19.2
module Unit.Parse.SymbolTest (tests) where

import qualified Canopy.Data.Name as Name
import qualified Data.ByteString.Char8 as C8
import qualified Data.Char as Char
import qualified Data.IntSet as IntSet
import qualified Parse.Primitives as Parse
import qualified Parse.Symbol as Symbol
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

-- ---------------------------------------------------------------------------
-- Error type
-- ---------------------------------------------------------------------------

-- | Captures the two ways 'operator' can fail.
--
-- 'NoOp' is produced when the input contains no operator characters at all.
-- 'Reserved' is produced when the matched token is a reserved sequence
-- such as @.@, @|@, @->@, @=@, or @:@.
data SymError
  = NoOp
  | Reserved Symbol.BadOperator
  deriving (Eq, Show)

-- | Error callback for an empty operator match (no binop chars consumed).
noOpError :: Parse.Row -> Parse.Col -> SymError
noOpError _ _ = NoOp

-- | Error callback when the matched token is a reserved operator.
reservedError :: Symbol.BadOperator -> Parse.Row -> Parse.Col -> SymError
reservedError bad _ _ = Reserved bad

-- ---------------------------------------------------------------------------
-- Helper
-- ---------------------------------------------------------------------------

-- | Run the 'operator' parser over an ASCII string.
parseOp :: String -> Either SymError Name.Name
parseOp s =
  Parse.fromByteString
    (Symbol.operator noOpError reservedError)
    noOpError
    (C8.pack s)

-- | Assert that a parse result is a 'Left'.
assertLeft :: (Show a) => Either SymError a -> IO ()
assertLeft (Left _) = pure ()
assertLeft (Right v) = assertBool ("expected Left but got Right: " <> show v) False

-- ---------------------------------------------------------------------------
-- Test suite
-- ---------------------------------------------------------------------------

-- | All 'Parse.Symbol' tests.
tests :: TestTree
tests =
  testGroup
    "Parse.Symbol"
    [ testValidOperators,
      testReservedOperators,
      testMultiCharOperators,
      testBinopCharSet
    ]

-- ---------------------------------------------------------------------------
-- Valid operators
-- ---------------------------------------------------------------------------

-- | Arithmetic and comparison operators that are accepted without error.
testValidOperators :: TestTree
testValidOperators =
  testGroup
    "valid operators"
    [ testCase "+" $ parseOp "+" @?= Right (Name.fromChars "+"),
      testCase "-" $ parseOp "-" @?= Right (Name.fromChars "-"),
      testCase "*" $ parseOp "*" @?= Right (Name.fromChars "*"),
      testCase "/" $ parseOp "/" @?= Right (Name.fromChars "/"),
      testCase "//" $ parseOp "//" @?= Right (Name.fromChars "//"),
      testCase "^" $ parseOp "^" @?= Right (Name.fromChars "^"),
      testCase "==" $ parseOp "==" @?= Right (Name.fromChars "=="),
      testCase "/=" $ parseOp "/=" @?= Right (Name.fromChars "/="),
      testCase "<" $ parseOp "<" @?= Right (Name.fromChars "<"),
      testCase ">" $ parseOp ">" @?= Right (Name.fromChars ">"),
      testCase "<=" $ parseOp "<=" @?= Right (Name.fromChars "<="),
      testCase ">=" $ parseOp ">=" @?= Right (Name.fromChars ">="),
      testCase "&&" $ parseOp "&&" @?= Right (Name.fromChars "&&"),
      testCase "||" $ parseOp "||" @?= Right (Name.fromChars "||"),
      testCase "++" $ parseOp "++" @?= Right (Name.fromChars "++"),
      testCase "<|" $ parseOp "<|" @?= Right (Name.fromChars "<|"),
      testCase "|>" $ parseOp "|>" @?= Right (Name.fromChars "|>"),
      testCase "<<" $ parseOp "<<" @?= Right (Name.fromChars "<<"),
      testCase ">>" $ parseOp ">>" @?= Right (Name.fromChars ">>")
    ]

-- ---------------------------------------------------------------------------
-- Reserved operators
-- ---------------------------------------------------------------------------

-- | Reserved operator sequences that must be rejected with a specific error.
testReservedOperators :: TestTree
testReservedOperators =
  testGroup
    "reserved operators"
    [ testCase ". is BadDot" $
        parseOp "." @?= Left NoOp,
      testCase "| is BadPipe" $
        parseOp "|" @?= Left (Reserved Symbol.BadPipe),
      testCase "-> is BadArrow" $
        parseOp "->" @?= Left (Reserved Symbol.BadArrow),
      testCase "= is BadEquals" $
        parseOp "=" @?= Left (Reserved Symbol.BadEquals),
      testCase ": is BadHasType" $
        parseOp ":" @?= Left (Reserved Symbol.BadHasType)
    ]

-- ---------------------------------------------------------------------------
-- Multi-character operators
-- ---------------------------------------------------------------------------

-- | Composed operators that consume all their characters in one token.
testMultiCharOperators :: TestTree
testMultiCharOperators =
  testGroup
    "multi-character operators"
    [ testCase "<*>" $ parseOp "<*>" @?= Right (Name.fromChars "<*>"),
      testCase ">>=" $ parseOp ">>=" @?= Right (Name.fromChars ">>="),
      testCase "!!" $ parseOp "!!" @?= Right (Name.fromChars "!!"),
      testCase "??" $ parseOp "??" @?= Right (Name.fromChars "??")
    ]

-- ---------------------------------------------------------------------------
-- binopCharSet membership
-- ---------------------------------------------------------------------------

-- | Every character listed in the source definition of 'binopCharSet' must
-- appear in the set, and common non-operator characters must not.
testBinopCharSet :: TestTree
testBinopCharSet =
  testGroup
    "binopCharSet"
    [ testCase "'+' is in the set" $
        assertBool "+" (IntSet.member (Char.ord '+') Symbol.binopCharSet),
      testCase "'-' is in the set" $
        assertBool "-" (IntSet.member (Char.ord '-') Symbol.binopCharSet),
      testCase "'/' is in the set" $
        assertBool "/" (IntSet.member (Char.ord '/') Symbol.binopCharSet),
      testCase "'*' is in the set" $
        assertBool "*" (IntSet.member (Char.ord '*') Symbol.binopCharSet),
      testCase "'=' is in the set" $
        assertBool "=" (IntSet.member (Char.ord '=') Symbol.binopCharSet),
      testCase "'.' is in the set" $
        assertBool "." (IntSet.member (Char.ord '.') Symbol.binopCharSet),
      testCase "'<' is in the set" $
        assertBool "<" (IntSet.member (Char.ord '<') Symbol.binopCharSet),
      testCase "'>' is in the set" $
        assertBool ">" (IntSet.member (Char.ord '>') Symbol.binopCharSet),
      testCase "':' is in the set" $
        assertBool ":" (IntSet.member (Char.ord ':') Symbol.binopCharSet),
      testCase "'&' is in the set" $
        assertBool "&" (IntSet.member (Char.ord '&') Symbol.binopCharSet),
      testCase "'|' is in the set" $
        assertBool "|" (IntSet.member (Char.ord '|') Symbol.binopCharSet),
      testCase "'^' is in the set" $
        assertBool "^" (IntSet.member (Char.ord '^') Symbol.binopCharSet),
      testCase "'?' is in the set" $
        assertBool "?" (IntSet.member (Char.ord '?') Symbol.binopCharSet),
      testCase "'%' is in the set" $
        assertBool "%" (IntSet.member (Char.ord '%') Symbol.binopCharSet),
      testCase "'!' is in the set" $
        assertBool "!" (IntSet.member (Char.ord '!') Symbol.binopCharSet),
      testCase "'a' is NOT in the set" $
        assertBool "a should be absent" (not (IntSet.member (Char.ord 'a') Symbol.binopCharSet)),
      testCase "'0' is NOT in the set" $
        assertBool "0 should be absent" (not (IntSet.member (Char.ord '0') Symbol.binopCharSet)),
      testCase "' ' is NOT in the set" $
        assertBool "space should be absent" (not (IntSet.member (Char.ord ' ') Symbol.binopCharSet))
    ]
