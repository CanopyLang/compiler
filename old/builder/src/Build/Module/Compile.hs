{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Module compilation and artifact generation for the Canopy compiler.
--
-- This module handles the core compilation process for individual modules,
-- including interface generation, object code production, and documentation
-- processing. It provides the compilation engine that transforms source
-- modules into build artifacts.
--
-- === Primary Responsibilities
--
-- * Module compilation using the core compiler ('compile')
-- * Artifact generation and interface creation
-- * Documentation generation and validation
-- * Project type handling and package resolution
-- * Result processing and caching
--
-- === Usage Examples
--
-- @
-- -- Compile a module with interfaces
-- result <- compile env docsNeed local source interfaces module
-- case result of
--   RNew local iface objects docs -> handleNewModule local iface objects docs
--   RSame local iface objects docs -> handleUnchangedModule local iface objects docs
--   RProblem error -> handleCompilationError error
-- @
--
-- === Compilation Process
--
-- The compilation process follows these steps:
--
-- 1. Package resolution from project type
-- 2. Core compilation to canonical AST and objects
-- 3. Interface generation from canonical representation
-- 4. Documentation generation (if enabled)
-- 5. Artifact writing and caching
-- 6. Result packaging with proper change detection
--
-- === Documentation Integration
--
-- Documentation is generated alongside compilation when enabled through
-- 'DocsNeed'. The module handles both successful documentation generation
-- and graceful fallback when documentation cannot be produced.
--
-- === Interface Caching
--
-- Interfaces are cached and compared to detect changes. When interfaces
-- are identical, the module result is marked as 'RSame' to avoid
-- unnecessary recompilation of dependent modules.
--
-- @since 0.19.1
module Build.Module.Compile
  ( -- * Compilation Functions
    compile,
    compileOutside,

    -- * Configuration Types
    CompileConfig (..),
    OutsideCompileConfig (..),

    -- * Documentation Generation
    makeDocs,
    finalizeDocs,
    toDocs,

    -- * Project Type Utilities
    projectTypeToPkg,
  )
where

-- Core compilation imports

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Source as Src
-- New compiler imports

-- Canopy-specific imports

-- Build system imports
import Build.Types
  ( DocsGoal (..),
    DocsNeed (..),
    Env (..),
    Result (..),
    RootResult (..),
    envBuildID,
    envKey,
    envProject,
    envRoot,
  )
import qualified Canopy.Details as Details
import qualified Canopy.Docs as Docs
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Compile
-- Parser imports

-- Standard library imports
import Control.Lens ((&), (.~), (^.))
import qualified Data.ByteString as B
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified File
import qualified Json.Encode as E
import Debug.Logger (DebugCategory (..))
import qualified Debug.Logger as Logger
import qualified Driver
import qualified Query.Simple as Simple
import qualified Parse.Module as Parse
import qualified Reporting
import qualified Reporting.Error as Error
import qualified Reporting.Error.Docs as EDocs
import qualified Reporting.Error.Syntax as Syntax
import qualified Stuff
import qualified System.Environment as Env

-- | Configuration for module compilation.
--
-- Groups compilation parameters to meet CLAUDE.md requirement of ≤4 parameters.
--
-- @since 0.19.1
data CompileConfig = CompileConfig
  { _ccEnv :: !Env,
    _ccDocsNeed :: !DocsNeed,
    _ccLocal :: !Details.Local,
    _ccSource :: !B.ByteString
  }

-- | Compile a single module with dependency interfaces.
--
-- This is the core compilation function that takes a parsed module and
-- its dependency interfaces, then produces compilation artifacts including
-- objects, interfaces, and optional documentation.
--
-- ==== Compilation Steps
--
-- 1. Resolves project package from environment
-- 2. Invokes core compiler with interfaces and module
-- 3. Generates module interface from canonical AST
-- 4. Creates documentation if requested
-- 5. Writes artifacts to filesystem
-- 6. Detects interface changes for dependency tracking
--
-- ==== Parameters
--
-- [@config@]: Compilation configuration with environment, docs need, local data, and source
-- [@ifaces@]: Dependency interfaces for compilation
-- [@modul@]: Parsed source module to compile
--
-- ==== Returns
--
-- * 'RNew': Module compiled with new interface
-- * 'RSame': Module compiled with unchanged interface
-- * 'RProblem': Compilation failed with error
--
-- ==== Interface Change Detection
--
-- The function compares generated interfaces with cached versions to
-- determine if dependent modules need recompilation. This optimization
-- significantly reduces build times for incremental changes.
--
-- @since 0.19.1
compile :: CompileConfig -> Map ModuleName.Raw I.Interface -> Src.Module -> IO Result
compile (CompileConfig env docsNeed local source) ifaces modul =
  case env of
    Env _ root projectType _ _ _ _ -> do
      let pkg = projectTypeToPkg projectType
          moduleName = Src.getName modul

      -- Check if we should use new compiler
      _useNew <- shouldUseNewCompiler

      compileResult <-
        if True
          then compileWithNewCompiler pkg ifaces modul
          else Compile.compileWithRoot pkg ifaces root modul

      case compileResult of
        Right artifacts -> handleSuccessfulCompilation env docsNeed local source moduleName artifacts
        Left err -> case local of
          Details.Local path time _ _ _ _ ->
            return . RProblem $ Error.Module moduleName path time source err

-- | Handle successful compilation artifacts.
--
-- Processes compilation artifacts and determines if the interface changed.
--
-- @since 0.19.1
handleSuccessfulCompilation :: Env -> DocsNeed -> Details.Local -> B.ByteString -> ModuleName.Raw -> Compile.Artifacts -> IO Result
handleSuccessfulCompilation env docsNeed local source moduleName (Compile.Artifacts canonical annotations objects _ffiInfo) = do
  docsResult <- makeDocs docsNeed canonical
  case docsResult of
    Left err ->
      return . RProblem $ Error.Module moduleName (local ^. Details.path) (local ^. Details.time) source (Error.BadDocs err)
    Right docs -> do
      let pkg = projectTypeToPkg (env ^. envProject)
      let iface = I.fromModule pkg canonical annotations
      processCompiledInterface env local moduleName iface objects docs

-- | Process compiled interface and detect changes.
--
-- @since 0.19.1
processCompiledInterface :: Env -> Details.Local -> ModuleName.Raw -> I.Interface -> Opt.LocalGraph -> Maybe Docs.Module -> IO Result
processCompiledInterface env local moduleName iface objects docs = do
  File.writeBinaryAtomic (Stuff.canopyo (env ^. envRoot) moduleName) objects
  maybeOldi <- File.readBinary (Stuff.canopyi (env ^. envRoot) moduleName)
  case maybeOldi of
    Just oldi
      | oldi == iface ->
        reportUnchangedInterface env local iface objects docs
    _ ->
      reportChangedInterface env local moduleName iface objects docs

-- | Report unchanged interface result.
--
-- @since 0.19.1
reportUnchangedInterface :: Env -> Details.Local -> I.Interface -> Opt.LocalGraph -> Maybe Docs.Module -> IO Result
reportUnchangedInterface env local iface objects docs = do
  Reporting.report (env ^. envKey) Reporting.BDone
  let newLocal = local & Details.lastChange .~ (env ^. envBuildID)
  return (RSame newLocal iface objects docs)

-- | Report changed interface result.
--
-- @since 0.19.1
reportChangedInterface :: Env -> Details.Local -> ModuleName.Raw -> I.Interface -> Opt.LocalGraph -> Maybe Docs.Module -> IO Result
reportChangedInterface env local moduleName iface objects docs = do
  File.writeBinaryAtomic (Stuff.canopyi (env ^. envRoot) moduleName) iface
  Reporting.report (env ^. envKey) Reporting.BDone
  let newLocal =
        local & Details.lastChange .~ (env ^. envBuildID)
          & Details.lastCompile .~ (env ^. envBuildID)
  return (RNew newLocal iface objects docs)

-- | Configuration for outside module compilation.
--
-- Groups compilation parameters to meet CLAUDE.md requirement of ≤4 parameters.
--
-- @since 0.19.1
data OutsideCompileConfig = OutsideCompileConfig
  { _ocEnv :: !Env,
    _ocLocal :: !Details.Local,
    _ocSource :: !B.ByteString,
    _ocModule :: !Src.Module
  }

-- | Compile a module outside the main project structure.
--
-- Used for compiling modules that exist outside the standard source
-- directories, such as individual files specified by path. This variant
-- simplifies the result to just the essential compilation artifacts.
--
-- ==== Parameters
--
-- [@config@]: Outside compilation configuration
-- [@ifaces@]: Dependency interfaces for compilation
--
-- @since 0.19.1
compileOutside :: OutsideCompileConfig -> Map ModuleName.Raw I.Interface -> IO RootResult
compileOutside (OutsideCompileConfig (Env key root projectType _ _ _ _) (Details.Local path time _ _ _ _) source modul) ifaces = do
  let pkg = projectTypeToPkg projectType
      name = Src.getName modul
  compileResult <- Compile.compileWithRoot pkg ifaces root modul
  case compileResult of
    Right (Compile.Artifacts canonical annotations objects _ffiInfo) -> do
      Reporting.report key Reporting.BDone
      return $ ROutsideOk name (I.fromModule pkg canonical annotations) objects
    Left errors ->
      return . ROutsideErr $ Error.Module name path time source errors

-- | Convert project type to package name.
--
-- Resolves the package name used for compilation based on whether this
-- is a package build (which has an explicit package name) or an application
-- build (which uses a dummy package name).
--
-- @since 0.19.1
projectTypeToPkg :: Parse.ProjectType -> Pkg.Name
projectTypeToPkg projectType =
  case projectType of
    Parse.Package pkg -> pkg
    Parse.Application -> Pkg.dummyName

-- | Generate documentation from canonical module.
--
-- Creates documentation artifacts from the canonical AST when documentation
-- generation is enabled. Handles documentation errors gracefully by
-- propagating them as compilation errors.
--
-- ==== Documentation Generation
--
-- * When 'DocsNeed' is @False@: Returns @Nothing@ without processing
-- * When 'DocsNeed' is @True@: Attempts to generate documentation
-- * On success: Returns @Just docs@ with generated documentation
-- * On failure: Returns documentation error for reporting
--
-- @since 0.19.1
makeDocs :: DocsNeed -> Can.Module -> IO (Either EDocs.Error (Maybe Docs.Module))
makeDocs (DocsNeed isNeeded) modul =
  if isNeeded
    then do
      result <- Docs.fromModule modul
      case result of
        Right docs -> pure (Right (Just docs))
        Left err -> pure (Left err)
    else pure (Right Nothing)

-- | Finalize documentation output based on documentation goal.
--
-- Processes compiled results to extract documentation and handle the
-- final documentation output according to the specified goal.
--
-- ==== Documentation Goals
--
-- * 'KeepDocs': Return documentation map for programmatic use
-- * 'WriteDocs': Write documentation to specified file path
-- * 'IgnoreDocs': Return unit, discarding all documentation
--
-- @since 0.19.1
finalizeDocs :: DocsGoal docs -> Map ModuleName.Raw Result -> IO docs
finalizeDocs goal results =
  case goal of
    KeepDocs ->
      return $ Map.mapMaybe toDocs results
    WriteDocs path ->
      E.writeUgly path . Docs.encode $ Map.mapMaybe toDocs results
    IgnoreDocs ->
      return ()

-- | Extract documentation from compilation result.
--
-- Safely extracts documentation from various result types, returning
-- @Nothing@ for results that don't contain documentation.
--
-- @since 0.19.1
toDocs :: Result -> Maybe Docs.Module
toDocs result =
  case result of
    RNew _ _ _ d -> d
    RSame _ _ _ d -> d
    RCached {} -> Nothing
    RNotFound _ -> Nothing
    RProblem _ -> Nothing
    RBlocked -> Nothing
    RForeign _ -> Nothing
    RKernel -> Nothing

-- | Check if new compiler should be used.
--
-- Reads CANOPY_NEW_COMPILER environment variable.
-- Returns True if set to "1", False otherwise.
--
-- @since 0.19.1
shouldUseNewCompiler :: IO Bool
shouldUseNewCompiler = do
  maybeFlag <- Env.lookupEnv "CANOPY_NEW_COMPILER"
  let useNew = maybeFlag == Just "1"
  Logger.debug COMPILE_DEBUG ("shouldUseNewCompiler: " ++ show useNew)
  return useNew

-- | Compile with new query-based compiler.
--
-- Converts Driver.CompileResult to Compile.Artifacts format.
--
-- @since 0.19.1
compileWithNewCompiler ::
  Pkg.Name ->
  Map ModuleName.Raw I.Interface ->
  Src.Module ->
  IO (Either Error.Error Compile.Artifacts)
compileWithNewCompiler pkg ifaces modul = do
  Logger.debug COMPILE_DEBUG "Using new query-based compiler"

  result <- Driver.compileFromSource pkg ifaces modul

  case result of
    Left queryErr -> convertQueryError queryErr
    Right compileResult -> convertToArtifacts compileResult

-- | Convert query error to old error format.
convertQueryError :: Simple.QueryError -> IO (Either Error.Error a)
convertQueryError err = do
  Logger.debug COMPILE_DEBUG ("Query error occurred: " ++ show err)
  Logger.debug COMPILE_DEBUG "Conversion of query errors not yet fully implemented"
  -- For now, just create a generic syntax error
  -- TODO: Proper conversion based on query error type
  return (Left (Error.BadSyntax (Syntax.ModuleNameUnspecified "Unknown")))

-- | Convert CompileResult to Artifacts.
convertToArtifacts ::
  Driver.CompileResult ->
  IO (Either Error.Error Compile.Artifacts)
convertToArtifacts result = do
  Logger.debug COMPILE_DEBUG "Converting CompileResult to Artifacts"

  let canonModule = Driver.compileResultModule result
      types = Driver.compileResultTypes result
      localGraph = Driver.compileResultLocalGraph result

  -- FFI info is not yet extracted by new compiler
  let ffiInfo = Map.empty -- TODO: Extract FFI info
  return
    ( Right
        ( Compile.Artifacts
            { Compile._artifactsModule = canonModule,
              Compile._artifactsTypes = types,
              Compile._artifactsGraph = localGraph,
              Compile._artifactsFFIInfo = ffiInfo
            }
        )
    )

-- Generate lenses for record types
-- TODO: Uncomment when lenses are used in the module
-- makeLenses ''CompileConfig
-- makeLenses ''OutsideCompileConfig
