{-# LANGUAGE OverloadedStrings #-}

-- | Code generation and building functionality.
--
-- This module handles the core compilation pipeline, including building
-- from source files, generating artifacts, and creating output builders.
-- It coordinates between parsing, type checking, optimization, and
-- code generation phases.
--
-- Key functions:
--   * 'buildFromExposed' - Build from exposed package modules
--   * 'buildFromPaths' - Build from specific file paths
--   * 'createBuilder' - Generate output builder from artifacts
--   * 'extractModuleInfo' - Analyze module metadata
--
-- The module follows CLAUDE.md guidelines with functions ≤15 lines,
-- comprehensive error handling, and lens-based record access.
--
-- @since 0.19.1
module Make.Builder
  ( -- * Building Functions
    buildFromExposed,
    buildFromPaths,

    -- * Builder Creation
    createBuilder,
    createESMBuilder,
    createSplitBuilder,
    shouldSplitOutput,

    -- * Module Analysis
    extractMainModules,
    extractNonMainModules,
    hasExactlyOneMain,

    -- * Helper Functions
    isMainModule,
    getModuleMain,
  )
where

import qualified AST.Optimized as Opt
import qualified Build.Artifacts as Build
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Compiler
import Control.Lens ((^.))
import Data.ByteString.Builder (Builder)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Canopy.Data.Name as Name
import Canopy.Data.NonEmptyList (List)
import qualified Canopy.Data.NonEmptyList as NonEmptyList
import qualified Data.Set as Set
import qualified Generate.JavaScript as JS
import qualified Generate.JavaScript.CodeSplit.Generate as Split
import qualified Generate.JavaScript.CodeSplit.Types as Split
import qualified Generate.JavaScript.ESM as ESM
import Generate.JavaScript.ESM.Types (ESMOutput (..))
import qualified Generate.JavaScript.SourceMap as SourceMap
import qualified Generate.TypeScript as TypeScript
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import Make.Types
  ( BuildContext,
    DesiredMode (..),
    Task,
    bcDesiredMode,
    bcDetails,
    bcFfiDebug,
    bcFfiUnsafe,
    bcPackage,
    bcRoot,
  )
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task

-- | Build project from exposed package modules.
--
-- Compiles all modules listed in the package outline's exposed-modules
-- field. Used for package builds where specific modules are exposed
-- to consumers.
--
-- Uses NEW compiler by default. Set CANOPY_NEW_COMPILER=0 to use old system.
--
-- @
-- artifacts <- buildFromExposed ctx exposedModules maybeDocs
-- @
buildFromExposed ::
  BuildContext ->
  [Compiler.SrcDir] ->
  List ModuleName.Raw ->
  Task Compiler.Artifacts
buildFromExposed ctx srcDirs exposedModules = do
  let pkg = ctx ^. bcPackage
      root = ctx ^. bcRoot
      details = ctx ^. bcDetails
      isApp = isAppOutline (details ^. Details.detailsOutline)

  result <- Task.io (Compiler.compileFromExposed pkg isApp (Compiler.ProjectRoot root) srcDirs exposedModules)
  either (Task.throw . Exit.MakeCannotBuild) pure result

-- | Build project from specific file paths.
--
-- Compiles modules found at the given file paths. Used for application
-- builds and targeted compilation of specific modules.
--
-- Checks CANOPY_NEW_COMPILER environment variable to switch between
-- old and new query-based compiler implementations.
--
-- @
-- artifacts <- buildFromPaths ctx [\"src/Main.hs\", \"src/Utils.hs\"]
-- @
buildFromPaths ::
  BuildContext ->
  List FilePath ->
  Task Compiler.Artifacts
buildFromPaths ctx paths = do
  let pkg = ctx ^. bcPackage
      root = ctx ^. bcRoot
      details = ctx ^. bcDetails
      srcDirs = map Compiler.RelativeSrcDir (Details._detailsSrcDirs details)
      isApp = isAppOutline (details ^. Details.detailsOutline)

  result <- Task.io (Compiler.compileFromPaths pkg isApp (Compiler.ProjectRoot root) srcDirs (NonEmptyList.toList paths))
  either (Task.throw . Exit.MakeCannotBuild) pure result

-- | Create output builder from compiled artifacts.
--
-- Generates the appropriate code builder based on the desired build mode.
-- Returns both JavaScript builder and optional source map (dev mode only).
--
-- Build modes:
--   * 'Debug' - Includes debug information and readable output
--   * 'Dev' - Fast compilation with minimal optimization
--   * 'Prod' - Full optimization for production deployment
createBuilder ::
  BuildContext ->
  Compiler.Artifacts ->
  Task (Builder, Maybe SourceMap.SourceMap)
createBuilder ctx artifacts = do
  let mode = ctx ^. bcDesiredMode
  let ffiUnsafeFlag = ctx ^. bcFfiUnsafe
  let ffiDebugFlag = ctx ^. bcFfiDebug
  generateForMode mode ffiUnsafeFlag ffiDebugFlag artifacts

-- | Create ESM output from compiled artifacts.
--
-- Generates per-module ES module files, a shared runtime module,
-- FFI modules, and an entry point. Returns an 'ESMOutput' containing
-- builders for all output files.
--
-- @since 0.20.0
createESMBuilder ::
  BuildContext ->
  Compiler.Artifacts ->
  Task ESMOutput
createESMBuilder ctx artifacts =
  Task.mapError wrapGenerate (
    return (generateESM (desiredToMode mode ffiUnsafeFlag ffiDebugFlag globalGraph) artifacts))
  where
    mode = ctx ^. bcDesiredMode
    ffiUnsafeFlag = ctx ^. bcFfiUnsafe
    ffiDebugFlag = ctx ^. bcFfiDebug
    globalGraph = extractGlobalGraph artifacts
    wrapGenerate msg = Exit.MakeBadGenerate [Diag.stringToDiagnostic Diag.PhaseGenerate "CODE GENERATION ERROR" msg]

-- | Generate ESM output from artifacts, including @.d.ts@ type declarations.
generateESM :: Mode.Mode -> Compiler.Artifacts -> ESMOutput
generateESM mode artifacts =
  esmBase { _eoTypeDefs = typeDefs }
  where
    esmBase = ESM.generate mode globalGraph mains ffiInfo
    globalGraph = extractGlobalGraph artifacts
    mains = extractMains artifacts
    ffiInfo = artifacts ^. Build.artifactsFFIInfo
    pkgName = artifacts ^. Build.artifactsName
    typeDefs = generateTypeDefs pkgName (artifacts ^. Build.artifactsModules)


-- | Generate TypeScript declarations from module interfaces.
generateTypeDefs :: Pkg.Name -> [Build.Module] -> Map ModuleName.Canonical Builder
generateTypeDefs pkgName modules =
  Map.fromList (map (moduleTypeDef pkgName) modules)


-- | Generate a single module's @.d.ts@ content.
moduleTypeDef :: Pkg.Name -> Build.Module -> (ModuleName.Canonical, Builder)
moduleTypeDef pkgName (Build.Fresh rawName iface _) =
  (ModuleName.Canonical pkgName rawName, TypeScript.generateDts iface)

-- | Check whether code splitting should be used for the given artifacts.
--
-- Returns True when lazy import boundaries exist in the compiled modules.
-- The caller should use 'createSplitBuilder' instead of 'createBuilder'
-- when this returns True (unless @--no-split@ is active).
--
-- @since 0.19.2
shouldSplitOutput :: Compiler.Artifacts -> Bool
shouldSplitOutput artifacts =
  not (Set.null (artifacts ^. Build.artifactsLazyModules))

-- | Create code-split output from compiled artifacts.
--
-- Runs the full code splitting pipeline: analysis, per-chunk generation,
-- content hashing, and manifest creation. Returns a 'Split.SplitOutput'
-- containing all chunk builders and the JSON manifest.
--
-- @since 0.19.2
createSplitBuilder ::
  BuildContext ->
  Compiler.Artifacts ->
  Task Split.SplitOutput
createSplitBuilder ctx artifacts =
  Task.mapError wrapGenerate (
    return (generateSplit (desiredToMode mode ffiUnsafeFlag ffiDebugFlag globalGraph) artifacts))
  where
    mode = ctx ^. bcDesiredMode
    ffiUnsafeFlag = ctx ^. bcFfiUnsafe
    ffiDebugFlag = ctx ^. bcFfiDebug
    globalGraph = extractGlobalGraph artifacts
    wrapGenerate msg = Exit.MakeBadGenerate [Diag.stringToDiagnostic Diag.PhaseGenerate "CODE GENERATION ERROR" msg]

-- | Generate split output for artifacts using the code splitting pipeline.
generateSplit :: Mode.Mode -> Compiler.Artifacts -> Split.SplitOutput
generateSplit mode artifacts =
  Split.generateChunks mode globalGraph mains ffiInfo config
  where
    globalGraph = extractGlobalGraph artifacts
    mains = extractMains artifacts
    ffiInfo = artifacts ^. Build.artifactsFFIInfo
    config = buildSplitConfig artifacts

-- | Build split configuration from artifacts' lazy module set.
buildSplitConfig :: Compiler.Artifacts -> Split.SplitConfig
buildSplitConfig artifacts =
  Split.SplitConfig
    { Split._scLazyModules = artifacts ^. Build.artifactsLazyModules
    , Split._scMinSharedRefs = 2
    }

-- | Convert DesiredMode to Mode.Mode for code generation.
--
-- The ffiUnsafeFlag controls whether FFI validation is disabled.
-- The ffiDebugFlag enables verbose error messages in generated validators.
desiredToMode :: DesiredMode -> Bool -> Bool -> Opt.GlobalGraph -> Mode.Mode
desiredToMode Debug ffiUnsafeFlag ffiDebugFlag _ = Mode.Dev Nothing False ffiUnsafeFlag ffiDebugFlag Set.empty False
desiredToMode Dev ffiUnsafeFlag ffiDebugFlag _ = Mode.Dev Nothing False ffiUnsafeFlag ffiDebugFlag Set.empty False
desiredToMode Prod ffiUnsafeFlag ffiDebugFlag globalGraph =
  Mode.Prod (Mode.shortenFieldNames globalGraph) False ffiUnsafeFlag ffiDebugFlag StringPool.emptyPool Set.empty

-- | Generate builder for specific build mode.
--
-- Delegates to JavaScript generation based on mode.
-- Each mode has different optimization and output characteristics.
-- The ffiUnsafeFlag is passed through to Mode to control FFI validation.
-- The ffiDebugFlag enables verbose debug output in generated validators.
generateForMode ::
  DesiredMode ->
  Bool ->
  Bool ->
  Compiler.Artifacts ->
  Task (Builder, Maybe SourceMap.SourceMap)
generateForMode mode ffiUnsafeFlag ffiDebugFlag artifacts =
  Task.mapError wrapGenerate (
    case mode of
      Debug -> return (generateJS (Mode.Dev Nothing False ffiUnsafeFlag ffiDebugFlag Set.empty False) artifacts)
      Dev -> return (generateJS (Mode.Dev Nothing False ffiUnsafeFlag ffiDebugFlag Set.empty False) artifacts)
      Prod -> return (generateJS (Mode.Prod (Mode.shortenFieldNames globalGraph) False ffiUnsafeFlag ffiDebugFlag StringPool.emptyPool Set.empty) artifacts))
  where
    globalGraph = extractGlobalGraph artifacts
    wrapGenerate msg = Exit.MakeBadGenerate [Diag.stringToDiagnostic Diag.PhaseGenerate "CODE GENERATION ERROR" msg]

-- Helper: Generate JavaScript from artifacts
generateJS :: Mode.Mode -> Compiler.Artifacts -> (Builder, Maybe SourceMap.SourceMap)
generateJS mode artifacts =
  let globalGraph = extractGlobalGraph artifacts
      mains = extractMains artifacts
      ffiInfo = artifacts ^. Build.artifactsFFIInfo
      (jsBuilder, sourceMap, _coverageMap) = JS.generate mode globalGraph mains ffiInfo
   in (jsBuilder, sourceMap)

-- | Extract GlobalGraph from build artifacts.
extractGlobalGraph :: Compiler.Artifacts -> Opt.GlobalGraph
extractGlobalGraph artifacts = artifacts ^. Build.artifactsGlobalGraph

-- Helper: Extract mains from artifacts
extractMains :: Compiler.Artifacts -> Map ModuleName.Canonical Opt.Main
extractMains artifacts =
  let pkg = artifacts ^. Build.artifactsName
      modules = artifacts ^. Build.artifactsModules
      roots = artifacts ^. Build.artifactsRoots
   in gatherMains pkg modules roots

-- Helper: Gather mains from roots and modules
gatherMains ::
  Pkg.Name ->
  [Compiler.Module] ->
  List Compiler.Root ->
  Map ModuleName.Canonical Opt.Main
gatherMains pkg _modules roots =
  let mainList = Maybe.mapMaybe (extractMainFromRoot pkg) (NonEmptyList.toList roots)
   in Map.fromList mainList

-- Helper: Extract main from a single root
extractMainFromRoot ::
  Pkg.Name ->
  Compiler.Root ->
  Maybe (ModuleName.Canonical, Opt.Main)
extractMainFromRoot pkg root = case root of
  Compiler.Inside _name -> Nothing
  Compiler.Outside name _iface (Opt.LocalGraph maybeMain _ _ _) ->
    case maybeMain of
      Just main -> Just (ModuleName.Canonical pkg name, main)
      Nothing -> Nothing

-- | Extract modules that contain main functions.
--
-- Scans build artifacts to find modules with executable main functions.
-- Used to determine output format and entry points for applications.
--
-- @
-- mains <- extractMainModules artifacts
-- case mains of
--   [] -> generateLibrary artifacts
--   [main] -> generateSingleApp main artifacts
--   mains -> generateMultiApp mains artifacts
-- @
extractMainModules :: Compiler.Artifacts -> [ModuleName.Raw]
extractMainModules (Compiler.Artifacts _ _ roots modules _ _ _) =
  Maybe.mapMaybe (getModuleMain modules) (NonEmptyList.toList roots)

-- | Extract modules that do not contain main functions.
--
-- Finds library modules without executable entry points. Used for
-- JavaScript output validation - ensures no main functions are
-- accidentally included in library builds.
extractNonMainModules :: Compiler.Artifacts -> [ModuleName.Raw]
extractNonMainModules (Compiler.Artifacts _ _ roots modules _ _ _) =
  Maybe.mapMaybe (getNonMainModule modules) (NonEmptyList.toList roots)

-- | Check if artifacts contain exactly one main module.
--
-- Validates that HTML output has exactly one entry point. Returns
-- the main module name or throws an appropriate error.
--
-- Errors:
--   * No main functions found
--   * Multiple main functions found (invalid for HTML)
hasExactlyOneMain :: Compiler.Artifacts -> Task ModuleName.Raw
hasExactlyOneMain (Compiler.Artifacts _ _ roots modules _ _ _) =
  case roots of
    NonEmptyList.List root [] ->
      case getModuleMain modules root of
        Just mainName -> pure mainName
        Nothing -> Task.throw Exit.MakeNoMain
    NonEmptyList.List _ (_ : _) ->
      Task.throw Exit.MakeMultipleFilesIntoHtml

-- | Get main function from specific module.
--
-- Checks if a build root contains a main function. Returns the module
-- name if a main function is found, Nothing otherwise.
getModuleMain :: [Compiler.Module] -> Compiler.Root -> Maybe ModuleName.Raw
getModuleMain modules root =
  case root of
    Compiler.Inside name ->
      if any (isMainModule name) modules
        then Just name
        else Nothing
    Compiler.Outside name _ (Opt.LocalGraph maybeMain _ _ _) ->
      case maybeMain of
        Just _ -> Just name
        Nothing -> Nothing

-- | Get non-main module from build root.
--
-- Returns module name if it doesn't contain a main function and
-- isn't named "Main". Used for library module extraction.
getNonMainModule :: [Compiler.Module] -> Compiler.Root -> Maybe ModuleName.Raw
getNonMainModule modules root =
  case root of
    Compiler.Inside name ->
      if any (isMainModule name) modules || Name.toChars name == "Main"
        then Nothing
        else Just name
    Compiler.Outside name _ (Opt.LocalGraph maybeMain _ _ _) ->
      case maybeMain of
        Just _ -> Nothing
        Nothing -> Just name

-- | Check if module contains a main function.
--
-- Examines build module to determine if it defines an executable
-- main function. Works with both fresh and cached modules.
isMainModule :: ModuleName.Raw -> Compiler.Module -> Bool
isMainModule targetName modul =
  case modul of
    Compiler.Fresh name _ (Opt.LocalGraph maybeMain _ _ _) ->
      Maybe.isJust maybeMain && name == targetName

-- | Check whether a validated outline is for an application.
isAppOutline :: Details.ValidOutline -> Bool
isAppOutline (Details.ValidApp _) = True
isAppOutline (Details.ValidPkg _ _ _) = False
