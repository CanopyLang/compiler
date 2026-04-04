{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for 'Parse.Variable'.
--
-- Exercises 'lower', 'upper', 'moduleName', and 'reservedWords'.
--
-- Each parser is invoked via 'Parse.fromByteString' with a simple
-- positional error callback.  Tests verify exact 'Name.Name' values for
-- successful parses and confirm that reserved keywords are rejected by
-- 'lower', that identifiers starting with reserved words but continuing
-- with extra characters are accepted, and that 'moduleName' handles
-- dotted paths correctly.
--
-- @since 0.19.2
module Unit.Parse.VariableTest (tests) where

import qualified Canopy.Data.Name as Name
import qualified Data.ByteString.Char8 as C8
import qualified Data.Set as Set
import qualified Data.Word as Word (Word32)
import qualified Parse.Primitives as Parse
import qualified Parse.Variable as Variable
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

-- ---------------------------------------------------------------------------
-- Error type and helpers
-- ---------------------------------------------------------------------------

-- | Positional error value for all variable parser tests.
data VarError = VarError Word.Word32 Word.Word32
  deriving (Eq, Show)

-- | Build a 'VarError' from the row and column reported by the framework.
mkError :: Parse.Row -> Parse.Col -> VarError
mkError = VarError

-- | Run 'Variable.lower' on an ASCII string.
parseLower :: String -> Either VarError Name.Name
parseLower s =
  Parse.fromByteString (Variable.lower mkError) mkError (C8.pack s)

-- | Run 'Variable.upper' on an ASCII string.
parseUpper :: String -> Either VarError Name.Name
parseUpper s =
  Parse.fromByteString (Variable.upper mkError) mkError (C8.pack s)

-- | Run 'Variable.moduleName' on an ASCII string.
parseModuleName :: String -> Either VarError Name.Name
parseModuleName s =
  Parse.fromByteString (Variable.moduleName mkError) mkError (C8.pack s)

-- | Assert that a result is a 'Left' (parse failure).
assertLeft :: (Show a) => Either VarError a -> IO ()
assertLeft (Left _) = pure ()
assertLeft (Right v) =
  assertBool ("expected Left but got Right: " <> show v) False

-- ---------------------------------------------------------------------------
-- Test suite
-- ---------------------------------------------------------------------------

-- | All 'Parse.Variable' tests.
tests :: TestTree
tests =
  testGroup
    "Parse.Variable"
    [ testLower,
      testUpper,
      testModuleName,
      testReservedWords,
      testReservedWordPrefixes
    ]

-- ---------------------------------------------------------------------------
-- lower
-- ---------------------------------------------------------------------------

-- | Valid lowercase identifiers are parsed and their text is preserved.
testLower :: TestTree
testLower =
  testGroup
    "lower"
    [ testCase "single char 'x'" $
        parseLower "x" @?= Right (Name.fromChars "x"),
      testCase "simple word 'foo'" $
        parseLower "foo" @?= Right (Name.fromChars "foo"),
      testCase "camelCase 'myVar'" $
        parseLower "myVar" @?= Right (Name.fromChars "myVar"),
      testCase "long camelCase 'camelCase'" $
        parseLower "camelCase" @?= Right (Name.fromChars "camelCase"),
      testCase "trailing digits 'x1'" $
        parseLower "x1" @?= Right (Name.fromChars "x1"),
      testCase "underscore prefix '_description'" $
        parseLower "_description" @?= Right (Name.fromChars "_description"),
      testCase "uppercase start fails" $
        assertLeft (parseLower "Foo"),
      testCase "digit start fails" $
        assertLeft (parseLower "1x"),
      testCase "empty input fails" $
        assertLeft (parseLower "")
    ]

-- ---------------------------------------------------------------------------
-- upper
-- ---------------------------------------------------------------------------

-- | Valid uppercase identifiers (constructors, modules) are parsed correctly.
testUpper :: TestTree
testUpper =
  testGroup
    "upper"
    [ testCase "single char 'X'" $
        parseUpper "X" @?= Right (Name.fromChars "X"),
      testCase "constructor 'Maybe'" $
        parseUpper "Maybe" @?= Right (Name.fromChars "Maybe"),
      testCase "multi-segment name 'MyType'" $
        parseUpper "MyType" @?= Right (Name.fromChars "MyType"),
      testCase "uppercase with digits 'State2'" $
        parseUpper "State2" @?= Right (Name.fromChars "State2"),
      testCase "lowercase start fails" $
        assertLeft (parseUpper "foo"),
      testCase "digit start fails" $
        assertLeft (parseUpper "1Foo"),
      testCase "empty input fails" $
        assertLeft (parseUpper "")
    ]

-- ---------------------------------------------------------------------------
-- moduleName
-- ---------------------------------------------------------------------------

-- | Module names, including dotted paths, are parsed and text is preserved.
testModuleName :: TestTree
testModuleName =
  testGroup
    "moduleName"
    [ testCase "single segment 'Main'" $
        parseModuleName "Main" @?= Right (Name.fromChars "Main"),
      testCase "two segments 'Data.List'" $
        parseModuleName "Data.List" @?= Right (Name.fromChars "Data.List"),
      testCase "three segments 'My.Module.Name'" $
        parseModuleName "My.Module.Name"
          @?= Right (Name.fromChars "My.Module.Name"),
      testCase "dot without uppercase continuation fails" $
        assertLeft (parseModuleName "Data."),
      testCase "lowercase start fails" $
        assertLeft (parseModuleName "main"),
      testCase "empty input fails" $
        assertLeft (parseModuleName "")
    ]

-- ---------------------------------------------------------------------------
-- reservedWords
-- ---------------------------------------------------------------------------

-- | Every keyword in 'Variable.reservedWords' must be rejected by 'lower'
-- and must be a member of the exported set.
testReservedWords :: TestTree
testReservedWords =
  testGroup
    "reserved words"
    [ testReserved "if",
      testReserved "then",
      testReserved "else",
      testReserved "case",
      testReserved "of",
      testReserved "let",
      testReserved "in",
      testReserved "type",
      testReserved "module",
      testReserved "where",
      testReserved "import",
      testReserved "exposing",
      testReserved "as",
      testReserved "port",
      testReserved "deriving"
    ]

-- | Assert that a single keyword is both in 'reservedWords' and rejected
-- by 'lower'.
testReserved :: String -> TestTree
testReserved word =
  testCase word $ do
    assertBool (word <> " must be in reservedWords set")
      (Set.member (Name.fromChars word) Variable.reservedWords)
    assertLeft (parseLower word)

-- ---------------------------------------------------------------------------
-- Identifiers that start with a reserved word
-- ---------------------------------------------------------------------------

-- | An identifier that has a reserved word as a proper prefix must be
-- accepted, because 'lower' stops only if the full token matches a keyword.
testReservedWordPrefixes :: TestTree
testReservedWordPrefixes =
  testGroup
    "identifiers with reserved-word prefixes"
    [ testCase "ifTrue" $
        parseLower "ifTrue" @?= Right (Name.fromChars "ifTrue"),
      testCase "letting" $
        parseLower "letting" @?= Right (Name.fromChars "letting"),
      testCase "typeOf" $
        parseLower "typeOf" @?= Right (Name.fromChars "typeOf"),
      testCase "caseInsensitive" $
        parseLower "caseInsensitive"
          @?= Right (Name.fromChars "caseInsensitive"),
      testCase "elsewhere" $
        parseLower "elsewhere" @?= Right (Name.fromChars "elsewhere"),
      testCase "infix" $
        parseLower "infix" @?= Right (Name.fromChars "infix"),
      testCase "porter" $
        parseLower "porter" @?= Right (Name.fromChars "porter")
    ]
