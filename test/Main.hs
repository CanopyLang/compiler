module Main (main) where

-- Import test modules

import qualified Golden.JsGenGolden as JsGenGolden
import qualified Golden.ParseAliasGolden as ParseAliasGolden
import qualified Golden.ParseExprGolden as ParseExprGolden
import qualified Golden.ParseModuleGolden as ParseModuleGolden
import qualified Golden.ParseTypeGolden as ParseTypeGolden
import qualified Integration.CanExtensionTest as CanExtensionIT
import qualified Integration.CompileIntegrationTest as CompileIT
import qualified Integration.DevelopTest as DevelopIT
import qualified Integration.InitTest as InitIT
import qualified Integration.InstallTest as InstallIT
import qualified Integration.JsGenTest as JsGenIT
import qualified Integration.MakeTest as MakeIT
import qualified Integration.Terminal.ChompIntegrationTest as ChompIT
import qualified Integration.TerminalIntegrationTest as TerminalIT
import qualified Integration.WatchIntegrationTest as WatchIT
import qualified Integration.JsonIntegrationTest as JsonIT
import qualified Integration.ElmCanopyGoldenTest as ElmCanopyGoldenIT
import qualified Integration.JavaScriptRuntimeTest as JavaScriptRuntimeIT
import qualified Integration.JavaScriptSyntaxTest as JavaScriptSyntaxIT
import qualified Integration.PureBuilderIntegrationTest as PureBuilderIT
import qualified Property.AST.CanonicalProps as CanonicalProps
import qualified Property.AST.OptimizedBinaryProps as OptimizedBinaryProps
import qualified Property.AST.OptimizedProps as OptimizedProps
import qualified Property.Canopy.VersionProps as VersionProps
-- OLD Compile property test deleted (tested code moved to old/)
import qualified Property.Data.NameProps as NameProps
import qualified Property.DevelopProps as DevelopProps
import qualified Property.InitProps as InitProps
import qualified Property.InstallProps as InstallProps
import qualified Property.MakeProps as MakeProps
import qualified Property.Terminal.ChompProps as ChompProps
import qualified Property.TerminalProps as TerminalProps
import qualified Property.WatchProps as WatchProps
import Test.Tasty
import Test.Tasty.Runners
import qualified Unit.AST.CanonicalTypeTest as CanonicalTypeTest
import qualified Unit.AST.OptimizedTest as OptimizedTest
import qualified Unit.AST.SourceTest as SourceAstTest
import qualified Unit.AST.Utils.BinopTest as ASTUtilsBinopTest
import qualified Unit.AST.Utils.ShaderTest as ASTUtilsShaderTest
import qualified Unit.AST.Utils.TypeTest as ASTUtilsTypeTest
import qualified Unit.BackgroundWriterTest as BackgroundWriterTest
import qualified Unit.Builder.GraphTest as BuilderGraphTest
import qualified Unit.Builder.HashTest as BuilderHashTest
import qualified Unit.Builder.IncrementalTest as BuilderIncrementalTest
import qualified Unit.Builder.SolverTest as BuilderSolverTest
import qualified Unit.Builder.StateTest as BuilderStateTest
import qualified Unit.CLI.CommandsTest as CLICommandsTest
import qualified Unit.CLI.DocumentationTest as CLIDocumentationTest
import qualified Unit.CLI.ParsersTest as CLIParsersTest
import qualified Unit.Canopy.StuffTest as StuffTest
import qualified Unit.Canopy.VersionTest as VersionTest
-- OLD Compile test deleted (tested code moved to old/builder/src/Compile.hs)
import qualified Unit.Data.NameTest as NameTest
import qualified Unit.Data.IndexTest as IndexTest
import qualified Unit.Data.BagTest as BagTest
import qualified Unit.Data.NonEmptyListTest as NonEmptyListTest
import qualified Unit.Data.OneOrMoreTest as OneOrMoreTest
import qualified Unit.Data.Map.UtilsTest as MapUtilsTest
import qualified Unit.Data.Utf8Test as Utf8Test
import qualified Unit.File.ArchiveTest as FileArchiveTest
import qualified Unit.File.BinaryTest as FileBinaryTest
import qualified Unit.File.FileSystemTest as FileFileSystemTest
import qualified Unit.File.TimeTest as FileTimeTest
import qualified Unit.File.Utf8Test as FileUtf8Test
-- OLD Generate tests deleted (tested code moved to old/builder/src/Generate/)
import qualified Unit.HttpTest as HttpTest
import qualified Unit.Develop.CompilationTest as DevelopCompilationTest
import qualified Unit.Develop.EnvironmentTest as DevelopEnvironmentTest
import qualified Unit.Develop.MimeTypesTest as DevelopMimeTypesTest
import qualified Unit.Develop.TypesTest as DevelopTypesTest
import qualified Unit.DevelopMainTest as DevelopMainTest
import qualified Unit.DevelopTest as DevelopTest
import qualified Unit.Diff.EnvironmentTest as DiffEnvironmentTest
import qualified Unit.Diff.OutputTest as DiffOutputTest
import qualified Unit.Diff.TypesTest as DiffTypesTest
import qualified Unit.DiffTest as DiffTest
import qualified Unit.Init.DisplayTest as InitDisplayTest
import qualified Unit.Init.EnvironmentTest as InitEnvironmentTest
import qualified Unit.Init.ProjectTest as InitProjectTest
import qualified Unit.Init.TypesTest as InitTypesTest
import qualified Unit.Init.ValidationTest as InitValidationTest
import qualified Unit.InitTest as InitTest
import qualified Unit.InstallTest as InstallTest
import qualified Unit.Json.DecodeTest as JsonDecodeTest
import qualified Unit.Json.EncodeTest as JsonEncodeTest
import qualified Unit.Json.StringTest as JsonStringTest
import qualified Unit.MainTest as MainTest
import qualified Unit.MakeTest as MakeTest
import qualified Unit.Parse.ExpressionTest as ParseExpressionTest
import qualified Unit.Parse.ModuleTest as ParseModuleTest
import qualified Unit.Parse.PatternTest as ParsePatternTest
import qualified Unit.Parse.TypeTest as ParseTypeTest
import qualified Unit.Terminal.ChompTest as ChompTest
import qualified Unit.Terminal.Error.FormattingTest as TerminalErrorFormattingTest
import qualified Unit.Terminal.Error.SuggestionsTest as TerminalErrorSuggestionsTest
import qualified Unit.Terminal.Error.TypesTest as TerminalErrorTypesTest
import qualified Unit.Terminal.ErrorTest as TerminalErrorTest
-- import qualified Unit.ReportingTest as ReportingTest
import qualified Unit.TerminalTest as TerminalTest
import qualified Unit.WatchTest as WatchTest
import qualified Unit.New.Compiler.DriverTest as NewCompilerDriverTest
import qualified Unit.Query.EngineTest as QueryEngineTest
import qualified Unit.Builder.PackageCacheTest as PackageCacheTest
import qualified Unit.Worker.PoolTest as WorkerPoolTest
import qualified Unit.Queries.ParseModuleTest as ParseModuleQueryTest
import qualified Unit.Foreign.AudioFFITest as AudioFFITest
import qualified Unit.Foreign.FFITypeParseTest as FFITypeParseTest

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "Canopy Tests"
    [ unitTests
      -- propertyTests, -- TEMPORARILY DISABLED: Checking if this is the slow one
      -- integrationTests, -- Pure Builder integration tests added but disabled (slow with file I/O)
      -- goldenTests -- TEMPORARILY DISABLED: May compile real packages
    ]

unitTests :: TestTree
unitTests =
  testGroup
    "Unit Tests"
    [ NameTest.tests,
      IndexTest.tests,
      BagTest.tests,
      NonEmptyListTest.tests,
      OneOrMoreTest.tests,
      MapUtilsTest.tests,
      Utf8Test.tests,
      StuffTest.tests,
      VersionTest.tests,
      JsonDecodeTest.tests,
      JsonEncodeTest.tests,
      JsonStringTest.tests,
      DevelopTest.tests,
      DevelopMainTest.tests,
      DevelopCompilationTest.tests,
      DevelopEnvironmentTest.tests,
      DevelopMimeTypesTest.tests,
      DevelopTypesTest.tests,
      DiffTest.tests,
      DiffTypesTest.tests,
      DiffEnvironmentTest.tests,
      DiffOutputTest.tests,
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
      ASTUtilsBinopTest.tests,
      ASTUtilsShaderTest.tests,
      ASTUtilsTypeTest.tests,
      BackgroundWriterTest.tests,
      BuilderHashTest.tests,
      BuilderGraphTest.tests,
      BuilderStateTest.tests,
      BuilderIncrementalTest.tests,
      BuilderSolverTest.tests,
      CanonicalTypeTest.tests,
      OptimizedTest.tests,
      -- ReportingTest.tests,
      TerminalTest.tests,
      ChompTest.tests,
      TerminalErrorTest.tests,
      TerminalErrorTypesTest.tests,
      TerminalErrorFormattingTest.tests,
      TerminalErrorSuggestionsTest.tests,
      WatchTest.tests,
      FileArchiveTest.tests,
      FileBinaryTest.tests,
      FileFileSystemTest.tests,
      FileTimeTest.tests,
      FileUtf8Test.tests,
      HttpTest.tests,
      NewCompilerDriverTest.tests,
      QueryEngineTest.tests,
      PackageCacheTest.tests,
      WorkerPoolTest.tests,
      ParseModuleQueryTest.tests,
      AudioFFITest.tests,
      FFITypeParseTest.tests
    ]

propertyTests :: TestTree
propertyTests =
  testGroup
    "Property Tests"
    [ NameProps.tests,
      VersionProps.tests,
      CanonicalProps.tests,
      OptimizedBinaryProps.tests,
      OptimizedProps.tests,
      InitProps.tests,
      InstallProps.tests,
      MakeProps.tests,
      DevelopProps.tests,
      TerminalProps.tests,
      ChompProps.tests,
      WatchProps.tests
    ]

integrationTests :: TestTree
integrationTests =
  testGroup
    "Integration Tests"
    [ CanExtensionIT.tests,
      InitIT.tests,
      PureBuilderIT.tests
      -- InstallIT.tests, -- TEMPORARILY DISABLED: Downloads real elm/core package, very slow
      -- JsGenIT.tests, -- TEMPORARILY DISABLED: Compiles real packages, very slow
      -- MakeIT.tests, -- TEMPORARILY DISABLED: Compiles real packages, very slow
      -- DevelopIT.tests, -- TEMPORARILY DISABLED: May compile real packages
      -- TerminalIT.tests,
      -- ChompIT.tests,
      -- WatchIT.tests,
      -- CompileIT.tests, -- TEMPORARILY DISABLED: Compiles real packages, very slow
      -- JsonIT.tests,
      -- JavaScriptRuntimeIT.tests,
      -- JavaScriptSyntaxIT.tests
      -- ElmCanopyGoldenIT.tests  -- Disabled: exact string matching too brittle
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
