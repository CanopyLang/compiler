
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
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Canopy.Data.Name as Name
import qualified Data.Set as Set
import qualified Canopy.Data.Utf8 as Utf8
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
builderToString :: BB.Builder -> String
builderToString = LChar8.unpack . BB.toLazyByteString

-- BUILD POOL TESTS

buildPoolTests :: TestTree
buildPoolTests =
  testGroup
    "buildPool"
    [ testCase "strings appearing 2+ times are pooled" $
        Maybe.isJust (StringPool.lookupString pool1 (Utf8.fromChars "hello")) @?= True,
      testCase "strings appearing once are NOT pooled" $
        Maybe.isNothing (StringPool.lookupString pool1 (Utf8.fromChars "unique")) @?= True,
      testCase "alpha and beta are pooled, gamma is not" $
        do
          Maybe.isJust (StringPool.lookupString pool2 (Utf8.fromChars "alpha")) @?= True
          Maybe.isJust (StringPool.lookupString pool2 (Utf8.fromChars "beta")) @?= True
          Maybe.isNothing (StringPool.lookupString pool2 (Utf8.fromChars "gamma")) @?= True,
      testCase "strings in nested expressions are counted" $
        Maybe.isJust (StringPool.lookupString pool3 (Utf8.fromChars "nested")) @?= True,
      testCase "empty graph produces empty pool" $
        Maybe.isNothing (StringPool.lookupString emptyGraphPool (Utf8.fromChars "anything")) @?= True
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
    [ testCase "foo pool variable name is _s1" $
        show (StringPool.lookupString pool (Utf8.fromChars "foo"))
          @?= "Just (Name {toBuilder = \"_s1\"})",
      testCase "bar pool variable name is _s0" $
        show (StringPool.lookupString pool (Utf8.fromChars "bar"))
          @?= "Just (Name {toBuilder = \"_s0\"})",
      testCase "looking up unpooled string returns Nothing" $
        show (StringPool.lookupString StringPool.emptyPool (Utf8.fromChars "missing"))
          @?= "Nothing"
    ]
  where
    pool = StringPool.buildPool (mkGraph
      [ ("a", mkStr "foo"),
        ("b", mkStr "foo"),
        ("c", mkStr "bar"),
        ("d", mkStr "bar")
      ])

-- DECLARATION TESTS

declarationTests :: TestTree
declarationTests =
  testGroup
    "poolDeclarations"
    [ testCase "empty pool produces no declarations" $
        builderToString (StringPool.poolDeclarations StringPool.emptyPool) @?= "",
      testCase "pooled strings produce var declarations with correct format" $
        let pool = StringPool.buildPool (mkGraph
              [ ("a", mkStr "repeated"),
                ("b", mkStr "repeated")
              ])
            declStr = builderToString (StringPool.poolDeclarations pool)
        in declStr @?= "var _s0 = \"repeated\";\n"
    ]

-- EMPTY POOL TESTS

emptyPoolTests :: TestTree
emptyPoolTests =
  testGroup
    "emptyPool"
    [ testCase "empty pool has no declarations" $
        builderToString (StringPool.poolDeclarations StringPool.emptyPool) @?= "",
      testCase "empty pool never matches any string" $
        Maybe.isNothing (StringPool.lookupString StringPool.emptyPool (Utf8.fromChars "test"))
          @?= True
    ]
