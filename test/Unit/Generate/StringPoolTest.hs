
-- | Tests for string literal deduplication in production builds.
--
-- Validates that the string pool correctly identifies repeated strings,
-- assigns unique pool variable names, generates valid JS declarations,
-- and returns Nothing for strings appearing only once.
--
-- @since 0.19.2
module Unit.Generate.StringPoolTest (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.Name as Name
import qualified Data.Set as Set
import qualified Data.Utf8 as Utf8
import qualified Generate.JavaScript.StringPool as StringPool
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.StringPool"
    [ buildPoolTests,
      lookupTests,
      declarationTests,
      emptyPoolTests
    ]

-- HELPERS

-- | Create a test Opt.Global from a simple name string.
mkGlobal :: String -> Opt.Global
mkGlobal str =
  Opt.Global (ModuleName.Canonical Pkg.dummyName (Name.fromChars "Test")) (Name.fromChars str)

-- | Create a string expression.
mkStr :: String -> Opt.Expr
mkStr = Opt.Str . Utf8.fromChars

-- | Create a Define node containing a single expression.
mkDefineNode :: Opt.Expr -> Opt.Node
mkDefineNode expr = Opt.Define expr Set.empty

-- | Create a graph from a list of (name, expression) pairs.
mkGraph :: [(String, Opt.Expr)] -> Map.Map Opt.Global Opt.Node
mkGraph entries =
  Map.fromList [(mkGlobal name, mkDefineNode expr) | (name, expr) <- entries]

-- | Convert a Builder to a String for assertion checks.
builderToString :: B.Builder -> String
builderToString = LChar8.unpack . B.toLazyByteString

-- BUILD POOL TESTS

buildPoolTests :: TestTree
buildPoolTests =
  testGroup
    "buildPool"
    [ testCase "strings appearing 2+ times are pooled" $
        assertBool "hello should be in pool"
          (Maybe.isJust (StringPool.lookupString pool1 (Utf8.fromChars "hello"))),
      testCase "strings appearing once are NOT pooled" $
        assertBool "unique should not be in pool"
          (Maybe.isNothing (StringPool.lookupString pool1 (Utf8.fromChars "unique"))),
      testCase "multiple repeated strings are all pooled" $
        do
          assertBool "alpha should be pooled"
            (Maybe.isJust (StringPool.lookupString pool2 (Utf8.fromChars "alpha")))
          assertBool "beta should be pooled"
            (Maybe.isJust (StringPool.lookupString pool2 (Utf8.fromChars "beta")))
          assertBool "gamma should not be pooled"
            (Maybe.isNothing (StringPool.lookupString pool2 (Utf8.fromChars "gamma"))),
      testCase "strings in nested expressions are counted" $
        assertBool "nested string in function body should be counted"
          (Maybe.isJust (StringPool.lookupString pool3 (Utf8.fromChars "nested"))),
      testCase "empty graph produces empty pool" $
        assertBool "empty graph gives empty pool"
          (Maybe.isNothing (StringPool.lookupString emptyGraphPool (Utf8.fromChars "anything")))
    ]
  where
    pool1 = StringPool.buildPool (mkGraph
      [ ("a", mkStr "hello"),
        ("b", mkStr "hello"),
        ("c", mkStr "unique")
      ])
    pool2 = StringPool.buildPool (mkGraph
      [ ("a", mkStr "alpha"),
        ("b", mkStr "alpha"),
        ("c", mkStr "beta"),
        ("d", mkStr "beta"),
        ("e", mkStr "gamma")
      ])
    pool3 = StringPool.buildPool (mkGraph
      [ ("a", Opt.Function [Name.fromChars "x"] (mkStr "nested")),
        ("b", mkStr "nested")
      ])
    emptyGraphPool = StringPool.buildPool Map.empty

-- LOOKUP TESTS

lookupTests :: TestTree
lookupTests =
  testGroup
    "lookupString"
    [ testCase "pooled strings get distinct variable names" $
        do
          assertBool "foo should be pooled" (Maybe.isJust fooName)
          assertBool "bar should be pooled" (Maybe.isJust barName)
          assertBool "foo and bar should have different names"
            (show fooName /= show barName),
      testCase "looking up unpooled string returns Nothing" $
        assertBool "empty pool returns Nothing"
          (Maybe.isNothing (StringPool.lookupString StringPool.emptyPool (Utf8.fromChars "missing")))
    ]
  where
    pool = StringPool.buildPool (mkGraph
      [ ("a", mkStr "foo"),
        ("b", mkStr "foo"),
        ("c", mkStr "bar"),
        ("d", mkStr "bar")
      ])
    fooName = StringPool.lookupString pool (Utf8.fromChars "foo")
    barName = StringPool.lookupString pool (Utf8.fromChars "bar")

-- DECLARATION TESTS

declarationTests :: TestTree
declarationTests =
  testGroup
    "poolDeclarations"
    [ testCase "empty pool produces no declarations" $
        assertEqual "empty pool gives empty builder"
          ""
          (builderToString (StringPool.poolDeclarations StringPool.emptyPool)),
      testCase "pooled strings produce var declarations" $
        do
          assertBool "declarations should contain var keyword"
            ("var " `List.isInfixOf` declStr)
          assertBool "declarations should contain the string literal"
            ("repeated" `List.isInfixOf` declStr)
          assertBool "declarations should end with semicolon-newline"
            (";\n" `List.isInfixOf` declStr)
    ]
  where
    pool = StringPool.buildPool (mkGraph
      [ ("a", mkStr "repeated"),
        ("b", mkStr "repeated")
      ])
    declStr = builderToString (StringPool.poolDeclarations pool)

-- EMPTY POOL TESTS

emptyPoolTests :: TestTree
emptyPoolTests =
  testGroup
    "emptyPool"
    [ testCase "empty pool has no declarations" $
        assertEqual "empty pool decls should be empty string"
          ""
          (builderToString (StringPool.poolDeclarations StringPool.emptyPool)),
      testCase "empty pool never matches any string" $
        assertBool "lookup always returns Nothing"
          (Maybe.isNothing (StringPool.lookupString StringPool.emptyPool (Utf8.fromChars "test")))
    ]
