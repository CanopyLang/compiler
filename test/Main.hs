module Main (main) where

-- Import test modules

import qualified Golden.JsGenGolden as JsGenGolden
import qualified Golden.ParseAliasGolden as ParseAliasGolden
import qualified Golden.ParseExprGolden as ParseExprGolden
import qualified Golden.ParseModuleGolden as ParseModuleGolden
import qualified Golden.ParseTypeGolden as ParseTypeGolden
import qualified Integration.CanExtensionTest as CanExtensionIT
import qualified Integration.InitTest as InitIT
import qualified Integration.InstallTest as InstallIT
import qualified Integration.JsGenTest as JsGenIT
import qualified Integration.MakeTest as MakeIT
import qualified Property.AST.CanonicalProps as CanonicalProps
import qualified Property.AST.OptimizedBinaryProps as OptimizedBinaryProps
import qualified Property.Canopy.VersionProps as VersionProps
import qualified Property.Data.NameProps as NameProps
import qualified Property.InitProps as InitProps
import qualified Property.InstallProps as InstallProps
import qualified Property.MakeProps as MakeProps
import Test.Tasty
import Test.Tasty.Runners
import qualified Unit.AST.CanonicalTypeTest as CanonicalTypeTest
import qualified Unit.AST.SourceTest as SourceAstTest
import qualified Unit.Canopy.VersionTest as VersionTest
import qualified Unit.CLI.CommandsTest as CLICommandsTest
import qualified Unit.CLI.DocumentationTest as CLIDocumentationTest
import qualified Unit.CLI.ParsersTest as CLIParsersTest
import qualified Unit.Data.NameTest as NameTest
import qualified Unit.Init.DisplayTest as InitDisplayTest
import qualified Unit.Init.EnvironmentTest as InitEnvironmentTest
import qualified Unit.Init.ProjectTest as InitProjectTest
import qualified Unit.Init.TypesTest as InitTypesTest
import qualified Unit.Init.ValidationTest as InitValidationTest
import qualified Unit.InitTest as InitTest
import qualified Unit.InstallTest as InstallTest
import qualified Unit.Json.DecodeTest as JsonDecodeTest
import qualified Unit.MainTest as MainTest
import qualified Unit.MakeTest as MakeTest
import qualified Unit.Parse.ExpressionTest as ParseExpressionTest
import qualified Unit.Parse.ModuleTest as ParseModuleTest
import qualified Unit.Parse.PatternTest as ParsePatternTest
import qualified Unit.Parse.TypeTest as ParseTypeTest

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "Canopy Tests"
    [ unitTests,
      propertyTests,
      integrationTests,
      goldenTests
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
      MakeTest.tests,
      MainTest.tests,
      InstallTest.tests,
      InitTest.tests,
      InitTypesTest.tests,
      InitValidationTest.tests,
      InitProjectTest.tests,
      InitEnvironmentTest.tests,
      InitDisplayTest.tests,
      CLIDocumentationTest.tests,
      CLIParsersTest.tests,
      CLICommandsTest.tests,
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
      OptimizedBinaryProps.tests,
      InitProps.tests,
      InstallProps.tests,
      MakeProps.tests
    ]

integrationTests :: TestTree
integrationTests =
  testGroup
    "Integration Tests"
    [ CanExtensionIT.tests,
      InitIT.tests,
      InstallIT.tests,
      JsGenIT.tests,
      MakeIT.tests
    ]

-- Optionally expose golden separately for clarity
goldenTests :: TestTree
goldenTests =
  testGroup
    "Golden Tests"
    [ ParseModuleGolden.tests,
      ParseExprGolden.tests,
      ParseTypeGolden.tests,
      ParseAliasGolden.tests,
      JsGenGolden.tests
    ]
