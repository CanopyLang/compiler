module Main (main) where

-- Import test modules

import qualified Golden.JsGenGolden as JsGenGolden
import qualified Golden.SecurityGolden as SecurityGolden
import qualified Golden.ParseAliasGolden as ParseAliasGolden
import qualified Golden.ParseExprGolden as ParseExprGolden
import qualified Golden.ParseModuleGolden as ParseModuleGolden
import qualified Golden.ParseTypeGolden as ParseTypeGolden
import qualified Integration.CanExtensionTest as CanExtensionIT
import qualified Integration.DevelopTest as DevelopIT
import qualified Integration.EndToEndTest as EndToEndIT
import qualified Integration.InitTest as InitIT
import qualified Integration.InstallTest as InstallIT
import qualified Integration.MakeTest as MakeIT
import qualified Integration.Terminal.ChompIntegrationTest as ChompIT
import qualified Integration.TerminalIntegrationTest as TerminalIT
import qualified Integration.WatchIntegrationTest as WatchIT
import qualified Integration.JsonIntegrationTest as JsonIT
import qualified Integration.CodeSplitIntegrationTest as CodeSplitIT
import qualified Integration.PureBuilderIntegrationTest as PureBuilderIT
import Test.Tasty
import qualified Unit.AST.CanonicalArithmeticTest as CanonicalArithmeticTest
import qualified Unit.AST.CanonicalTypeTest as CanonicalTypeTest
import qualified Unit.AST.OptimizedTest as OptimizedTest
import qualified Unit.AST.SourceArithmeticTest as SourceArithmeticTest
import qualified Unit.AST.SourceTest as SourceAstTest
import qualified Unit.AST.Utils.BinopTest as ASTUtilsBinopTest
import qualified Unit.AST.Utils.ShaderTest as ASTUtilsShaderTest
import qualified Unit.AST.Utils.TypeTest as ASTUtilsTypeTest
import qualified Unit.Builder.CacheVersionTest as BuilderCacheVersionTest
import qualified Unit.Builder.GraphTest as BuilderGraphTest
import qualified Unit.Builder.HashTest as BuilderHashTest
import qualified Unit.Builder.IncrementalTest as BuilderIncrementalTest
import qualified Unit.Builder.LockFileTest as BuilderLockFileTest
import qualified Unit.Builder.SolverTest as BuilderSolverTest
import qualified Unit.Builder.StateTest as BuilderStateTest
import qualified Unit.CLI.CommandsTest as CLICommandsTest
import qualified Unit.CLI.DocumentationTest as CLIDocumentationTest
import qualified Unit.CLI.ParsersTest as CLIParsersTest
import qualified Unit.Canopy.LimitsTest as LimitsTest
import qualified Unit.Canopy.VersionTest as VersionTest
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
import qualified Unit.HttpTest as HttpTest
import qualified Unit.DevelopMainTest as DevelopMainTest
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
import qualified Unit.NameReversalTest as NameReversalTest
import qualified Unit.Parse.ExpressionArithmeticTest as ParseExpressionArithmeticTest
import qualified Unit.Parse.ExpressionTest as ParseExpressionTest
import qualified Unit.Parse.LazyImportTest as LazyImportTest
import qualified Unit.Parse.ModuleTest as ParseModuleTest
import qualified Unit.Parse.PatternTest as ParsePatternTest
import qualified Unit.Parse.TypeTest as ParseTypeTest
import qualified Unit.Terminal.ChompTest as ChompTest
import qualified Unit.Terminal.Error.FormattingTest as TerminalErrorFormattingTest
import qualified Unit.Terminal.Error.SuggestionsTest as TerminalErrorSuggestionsTest
import qualified Unit.Terminal.Error.TypesTest as TerminalErrorTypesTest
import qualified Unit.Terminal.ErrorTest as TerminalErrorTest
import qualified Unit.TerminalTest as TerminalTest
import qualified Unit.WatchTest as WatchTest
import qualified Unit.Compiler.DiscoveryTest as CompilerDiscoveryTest
import qualified Unit.New.Compiler.DriverTest as NewCompilerDriverTest
import qualified Unit.NewTest as NewTest
import qualified Unit.Make.ReproducibleTest as ReproducibleTest
import qualified Unit.Query.EngineTest as QueryEngineTest
import qualified Unit.Builder.PackageCacheTest as PackageCacheTest
import qualified Unit.Worker.PoolTest as WorkerPoolTest
import qualified Unit.Builder.WorkspaceTest as WorkspaceTest
import qualified Unit.Watch.LiveReloadTest as LiveReloadTest
import qualified Unit.Queries.ParseModuleTest as ParseModuleQueryTest
import qualified Unit.Generate.CodeSplit.AnalyzeTest as CodeSplitAnalyzeTest
import qualified Unit.Generate.CodeSplit.ManifestTest as CodeSplitManifestTest
import qualified Unit.Generate.CodeSplit.RuntimeTest as CodeSplitRuntimeTest
import qualified Unit.Generate.CodeSplit.TypesTest as CodeSplitTypesTest
import qualified Unit.Generate.ExpressionTest as ExpressionTest
import qualified Unit.Generate.HtmlSecurityTest as HtmlSecurityTest
import qualified Unit.Generate.JavaScript.ExpressionArithmeticTest as JSExpressionArithmeticTest
import qualified Unit.Generate.MinifyTest as MinifyTest
import qualified Unit.Generate.NameTest as GenerateNameTest
import qualified Unit.Generate.CoverageTest as CoverageTest
import qualified Unit.Generate.SourceMapTest as SourceMapTest
import qualified Unit.Generate.StringPoolTest as StringPoolTest
import qualified Unit.Generate.TreeShakeTest as TreeShakeTest
import qualified Unit.Optimize.CaseTest as CaseTest
import qualified Unit.Optimize.ConstantFoldTest as ConstantFoldTest
import qualified Unit.Optimize.DecisionTreeTest as DecisionTreeTest
import qualified Unit.Optimize.ExpressionArithmeticTest as OptExpressionArithmeticTest
import qualified Unit.Optimize.NamesTest as NamesTest
import qualified Unit.Optimize.SimplifyTest as SimplifyTest
import qualified Unit.Logging.ConfigTest as LoggingConfigTest
import qualified Unit.Logging.EventTest as LoggingEventTest
import qualified Unit.Logging.SinkTest as LoggingSinkTest
import qualified Unit.Reporting.DiagnosticJsonTest as DiagnosticJsonTest
import qualified Unit.Reporting.DiagnosticTest as DiagnosticTest
import qualified Unit.Reporting.Doc.ColorQQTest as ColorQQTest
import qualified Unit.Reporting.ErrorCodeTest as ErrorCodeTest
import qualified Unit.Reporting.InternalErrorTest as InternalErrorTest
import qualified Unit.Type.InstantiateTest as InstantiateTest
import qualified Unit.Type.OccursTest as OccursTest
import qualified Unit.Type.GuardNarrowingTest as GuardNarrowingTest
import qualified Unit.Type.OpaqueBoundsTest as OpaqueBoundsTest
import qualified Unit.Type.SolveTest as SolveTest
import qualified Unit.Type.UnifyTest as UnifyTest
import qualified Unit.Type.VarianceTest as VarianceTest
import qualified Unit.Canonicalize.DupsTest as CanonicalizeDupsTest
import qualified Unit.Canonicalize.ExpressionArithmeticTest as CanonicalizeExpressionArithmeticTest
import qualified Unit.Canonicalize.LazyImportValidationTest as LazyImportValidationTest
import qualified Unit.Canonicalize.ModuleTest as CanonicalizeModuleTest
import qualified Unit.Canonicalize.PatternTest as CanonicalizePatternTest
import qualified Unit.Type.UnionFindTest as UnionFindTest
import qualified Unit.FFI.CapabilityEnforcementTest as FFICapEnforceTest
import qualified Unit.FFI.CapabilityTypeTest as FFICapTypeTest
import qualified Unit.FFI.EscapeTest as FFIEscapeTest
import qualified Unit.FFI.ManifestTest as FFIManifestTest
import qualified Unit.FFI.ResolveTest as FFIResolveTest
import qualified Unit.FFI.StaticAnalysisTest as FFIStaticAnalysisTest
import qualified Unit.FFI.ErgonomicsTest as FFIErgonomicsTest
import qualified Unit.FFI.ValidatorTest as FFIValidatorTest
import qualified Unit.Terminal.Lint.ConfigTest as LintConfigTest
import qualified Unit.Terminal.Lint.RulesTest as LintRulesTest
import qualified Unit.Terminal.Lint.NullabilityTest as LintNullabilityTest
import qualified Unit.Docs.RenderTest as DocsRenderTest
import qualified Unit.Docs.CommandTest as DocsCommandTest
import qualified Unit.Repl.CommandsTest as ReplCommandsTest
import qualified Unit.Repl.TypeQueryTest as ReplTypeQueryTest
import qualified Unit.Repl.StateTest as ReplStateTest
import qualified Unit.Repl.TypesTest as ReplTypesTest
import qualified Unit.Deps.AdvisoryTest as AdvisoryTest
import qualified Unit.Deps.RegistryTest as RegistryTest
import qualified Unit.AuditTest as AuditTest
import qualified Unit.VersionCheckTest as VersionCheckTest
import qualified Unit.Plugin.PipelineTest as PluginPipelineTest
import qualified Unit.Reporting.ErrorHierarchyTest as ErrorHierarchyTest
import qualified Unit.Editor.IntegrationTest as EditorIntegrationTest
import qualified Unit.SelfUpdateTest as SelfUpdateTest
import qualified Unit.Builder.ModuleLoaderTest as ModuleLoaderTest
import qualified Unit.WebIDL.CommandTest as WebIDLCommandTest
import qualified Unit.Publish.ArchiveTest as PublishArchiveTest
import qualified Unit.Type.ParallelTest as TypeParallelTest
import qualified Unit.Test.CoverageReportTest as CoverageReportTest
import qualified Unit.Test.EventCoverageTest as EventCoverageTest
import qualified Unit.VendorTest as VendorTest
import qualified Unit.ScriptsTest as ScriptsTest
import qualified Unit.OutlineFormatTest as OutlineFormatTest
import qualified Property.ArithmeticLawsTest as ArithmeticLawsTest
import qualified Property.Type.UnifyProperties as UnifyProperties
import qualified Property.Type.UnionFindProperties as UnionFindProperties
import qualified Property.Data.NameProperties as NameProperties
import qualified Property.Generate.CodeSplitProperties as CodeSplitProperties
import qualified Property.Generate.SourceMapProperties as SourceMapProperties

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
      IndexTest.tests,
      BagTest.tests,
      NonEmptyListTest.tests,
      OneOrMoreTest.tests,
      MapUtilsTest.tests,
      Utf8Test.tests,
      LimitsTest.tests,
      VersionTest.tests,
      JsonDecodeTest.tests,
      JsonEncodeTest.tests,
      JsonStringTest.tests,
      DevelopMainTest.tests,
      DiffTest.tests,
      ParseExpressionArithmeticTest.tests,
      ParseExpressionTest.tests,
      ParsePatternTest.tests,
      ParseTypeTest.tests,
      ParseModuleTest.tests,
      LazyImportTest.tests,
      MakeTest.tests,
      MainTest.tests,
      NameReversalTest.tests,
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
      BuilderHashTest.tests,
      BuilderCacheVersionTest.tests,
      BuilderGraphTest.tests,
      BuilderLockFileTest.tests,
      BuilderStateTest.tests,
      BuilderIncrementalTest.tests,
      BuilderSolverTest.tests,
      CanonicalArithmeticTest.tests,
      CanonicalTypeTest.tests,
      OptimizedTest.tests,
      SourceArithmeticTest.tests,
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
      CompilerDiscoveryTest.tests,
      NewCompilerDriverTest.tests,
      NewTest.tests,
      ReproducibleTest.tests,
      QueryEngineTest.tests,
      PackageCacheTest.tests,
      WorkerPoolTest.tests,
      ParseModuleQueryTest.tests,
      CaseTest.tests,
      ConstantFoldTest.tests,
      DecisionTreeTest.tests,
      OptExpressionArithmeticTest.tests,
      NamesTest.tests,
      SimplifyTest.tests,
      JSExpressionArithmeticTest.tests,
      MinifyTest.tests,
      GenerateNameTest.tests,
      HtmlSecurityTest.tests,
      ExpressionTest.tests,
      SourceMapTest.tests,
      StringPoolTest.tests,
      CodeSplitAnalyzeTest.tests,
      CodeSplitManifestTest.tests,
      CodeSplitRuntimeTest.tests,
      CodeSplitTypesTest.tests,
      TreeShakeTest.tests,
      CoverageTest.tests,
      CoverageReportTest.tests,
      EventCoverageTest.tests,
      ColorQQTest.tests,
      LoggingEventTest.tests,
      LoggingConfigTest.tests,
      LoggingSinkTest.tests,
      DiagnosticTest.tests,
      DiagnosticJsonTest.tests,
      ErrorCodeTest.tests,
      InternalErrorTest.tests,
      InstantiateTest.tests,
      OccursTest.tests,
      GuardNarrowingTest.tests,
      OpaqueBoundsTest.tests,
      SolveTest.tests,
      UnifyTest.tests,
      VarianceTest.tests,
      UnionFindTest.tests,
      CanonicalizeDupsTest.tests,
      CanonicalizeExpressionArithmeticTest.tests,
      CanonicalizePatternTest.tests,
      CanonicalizeModuleTest.tests,
      LazyImportValidationTest.tests,
      FFICapEnforceTest.tests,
      FFICapTypeTest.tests,
      FFIErgonomicsTest.tests,
      FFIEscapeTest.tests,
      FFIManifestTest.tests,
      FFIResolveTest.tests,
      FFIStaticAnalysisTest.tests,
      FFIValidatorTest.tests,
      LintConfigTest.tests,
      LintRulesTest.tests,
      LintNullabilityTest.tests,
      DocsRenderTest.tests,
      DocsCommandTest.tests,
      ReplCommandsTest.tests,
      ReplTypeQueryTest.tests,
      ReplStateTest.tests,
      ReplTypesTest.tests,
      AdvisoryTest.tests,
      RegistryTest.tests,
      AuditTest.tests,
      VersionCheckTest.tests,
      WorkspaceTest.tests,
      LiveReloadTest.tests,
      PluginPipelineTest.tests,
      ErrorHierarchyTest.tests,
      WebIDLCommandTest.tests,
      EditorIntegrationTest.tests,
      SelfUpdateTest.tests,
      ModuleLoaderTest.tests,
      PublishArchiveTest.tests,
      TypeParallelTest.tests,
      VendorTest.tests,
      ScriptsTest.tests,
      OutlineFormatTest.tests
    ]

propertyTests :: TestTree
propertyTests =
  testGroup
    "Property Tests"
    [ ArithmeticLawsTest.tests,
      UnifyProperties.tests,
      UnionFindProperties.tests,
      NameProperties.tests,
      SourceMapProperties.tests,
      CodeSplitProperties.tests
    ]

integrationTests :: TestTree
integrationTests =
  testGroup
    "Integration Tests"
    [ CanExtensionIT.tests,
      InitIT.tests,
      CodeSplitIT.tests,
      PureBuilderIT.tests,
      EndToEndIT.tests,
      DevelopIT.tests,
      InstallIT.tests,
      MakeIT.tests,
      ChompIT.tests,
      TerminalIT.tests,
      WatchIT.tests,
      JsonIT.tests
    ]

goldenTests :: TestTree
goldenTests =
  testGroup
    "Golden Tests"
    [ ParseModuleGolden.tests,
      ParseExprGolden.tests,
      ParseTypeGolden.tests,
      ParseAliasGolden.tests,
      JsGenGolden.tests,
      SecurityGolden.tests
    ]
