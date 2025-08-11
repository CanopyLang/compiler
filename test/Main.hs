module Main (main) where

-- Import test modules

import qualified Property.Canopy.VersionProps as VersionProps
import qualified Property.Data.NameProps as NameProps
import Test.Tasty
import Test.Tasty.Runners
import qualified Unit.Canopy.VersionTest as VersionTest
import qualified Unit.Data.NameTest as NameTest
import qualified Unit.Json.DecodeTest as JsonDecodeTest
import qualified Unit.Parse.ExpressionTest as ParseExpressionTest
import qualified Unit.Parse.PatternTest as ParsePatternTest
import qualified Unit.Parse.TypeTest as ParseTypeTest
import qualified Unit.Parse.ModuleTest as ParseModuleTest
import qualified Integration.CanExtensionTest as CanExtensionIT
import qualified Integration.JsGenTest as JsGenIT
import qualified Unit.AST.SourceTest as SourceAstTest
import qualified Unit.AST.CanonicalTypeTest as CanonicalTypeTest
import qualified Property.AST.CanonicalProps as CanonicalProps
import qualified Property.AST.OptimizedBinaryProps as OptimizedBinaryProps
import qualified Golden.ParseModuleGolden as ParseModuleGolden
import qualified Golden.ParseExprGolden as ParseExprGolden
import qualified Golden.ParseTypeGolden as ParseTypeGolden
import qualified Golden.ParseAliasGolden as ParseAliasGolden
import qualified Golden.JsGenGolden as JsGenGolden

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "Canopy Tests"
    [ unitTests,
      propertyTests,
      goldenTests
      -- , integrationTests  -- TODO: Add when we have integration tests
      -- , goldenTests       -- TODO: Add when we have golden tests
    ]

unitTests :: TestTree
unitTests =
  testGroup
    "Unit Tests"
    [ NameTest.tests,
      VersionTest.tests,
      JsonDecodeTest.tests,
      ParseExpressionTest.tests,
      ParsePatternTest.tests,
      ParseTypeTest.tests,
      ParseModuleTest.tests,
      CanExtensionIT.tests,
      JsGenIT.tests,
      SourceAstTest.tests,
      CanonicalTypeTest.tests
    ]

propertyTests :: TestTree
propertyTests =
  testGroup
    "Property Tests"
    [ NameProps.tests,
      VersionProps.tests,
      CanonicalProps.tests,
      OptimizedBinaryProps.tests
    ]

-- Optionally expose golden separately for clarity
goldenTests :: TestTree
goldenTests =
  testGroup
    "Golden Tests"
    [ ParseModuleGolden.tests
    , ParseExprGolden.tests
    , ParseTypeGolden.tests
    , ParseAliasGolden.tests
    , JsGenGolden.tests
    ]
