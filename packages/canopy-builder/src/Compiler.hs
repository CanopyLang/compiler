{-# LANGUAGE OverloadedStrings #-}

-- | Pure functional compiler interface for Terminal.
--
-- This module provides the compiler interface that Terminal expects,
-- wrapping the query-based Driver with a clean API. It replaces the
-- old Build.fromPaths and Build.fromExposed functions with pure
-- functional equivalents using the Driver.
--
-- Implementation is split across focused sub-modules:
--
-- * "Compiler.Types" -- SrcDir, ModuleResult, conversions
-- * "Compiler.Cache" -- Incremental cache and ELCO binary format
-- * "Compiler.Discovery" -- Module discovery and path resolution
-- * "Compiler.Parallel" -- Parallel compilation in dependency order
--
-- This facade re-exports their public APIs and provides the top-level
-- compilation entry points.
--
-- @since 0.19.1
module Compiler
  ( -- * Compilation Functions
    compileFromPaths,
    compileFromPathsTimed,
    compileFromExposed,

    -- * Types (re-exported from Compiler.Types)
    SrcDir (..),
    ModuleResult (..),
    fromDriverResult,
    moduleResultToModule,
    srcDirToString,

    -- * Path Types (re-exported)
    Builder.Paths.ProjectRoot (..),
    Builder.Paths.mkProjectRoot,

    -- * Cache (re-exported from Compiler.Cache)
    encodeVersioned,
    decodeVersioned,
    elcoSchemaVersion,

    -- * Re-exports for Terminal
    module Build.Artifacts,

    -- * Re-exports for Bench
    Driver.PhaseTimings (..),
  )
where

import qualified AST.Optimized as Opt
import qualified Build.Artifacts as Build
import Build.Artifacts
import Builder.Paths (ProjectRoot (..))
import qualified Builder.Paths
import qualified Canopy.Data.NonEmptyList as NE
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Compiler.Cache (decodeVersioned, elcoSchemaVersion, encodeVersioned)
import Compiler.Discovery (DiscoveryError (..), discoverModulePaths, discoverTransitiveDeps)
import Compiler.Parallel (assembleArtifacts, compileModulesInOrder, compileModulesInOrderTimed)
import qualified Driver
import Compiler.Types
  ( ModuleResult (..),
    SrcDir (..),
    fromDriverResult,
    moduleResultToModule,
    srcDirToString,
  )
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Exit
import qualified Generate.JavaScript as JS
import qualified Reporting.Diagnostic as Diag
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import qualified PackageCache
import qualified Parse.Module as Parse

-- COMPILATION ENTRY POINTS

-- | Compile from file paths using the query-based compiler.
--
-- This is the primary entry point for building Canopy projects.
-- Discovers transitive dependencies from the given source files,
-- compiles all modules in parallel respecting dependency order,
-- and assembles the final build artifacts.
--
-- @since 0.19.1
compileFromPaths ::
  Pkg.Name ->
  Bool ->
  ProjectRoot ->
  [SrcDir] ->
  [FilePath] ->
  IO (Either Exit.BuildError Build.Artifacts)
compileFromPaths pkg isApp (ProjectRoot root) srcDirs paths = do
  Log.logEvent (BuildStarted (Text.pack "compileFromPaths"))
  maybeArtifacts <- loadDependencyArtifacts root
  let (depInterfaces, depGlobalGraph, depFFIInfo) = extractArtifactTriple maybeArtifacts
  Log.logEvent (BuildModuleQueued (Text.pack ("loaded " ++ show (Map.size depInterfaces) ++ " dependency interfaces")))
  let projectType = if isApp then Parse.Application else Parse.Package pkg
  discoveryResult <- discoverTransitiveDeps root srcDirs paths depInterfaces projectType
  case discoveryResult of
    Left (DiscoveryParseError path msg) ->
      return (Left (Exit.BuildCannotCompile (Exit.CompileError path
        [Diag.stringToDiagnostic Diag.PhaseParse "SYNTAX ERROR" (Text.unpack msg)])))
    Right allModuleInfo -> do
      Log.logEvent (BuildModuleQueued (Text.pack ("discovered " ++ show (Map.size allModuleInfo) ++ " total modules")))
      compileResult <- compileModulesInOrder pkg projectType root depInterfaces allModuleInfo
      either (return . Left) (return . Right . assembleArtifacts pkg depGlobalGraph depFFIInfo) compileResult

-- | Like 'compileFromPaths' but also returns aggregate per-phase timings.
--
-- Used by the bench command to report per-phase compilation breakdown.
-- The timings sum across all compiled modules (cache hits report zero).
--
-- @since 0.19.2
compileFromPathsTimed ::
  Pkg.Name ->
  Bool ->
  ProjectRoot ->
  [SrcDir] ->
  [FilePath] ->
  IO (Either Exit.BuildError (Build.Artifacts, Driver.PhaseTimings))
compileFromPathsTimed pkg isApp (ProjectRoot root) srcDirs paths = do
  Log.logEvent (BuildStarted (Text.pack "compileFromPathsTimed"))
  maybeArtifacts <- loadDependencyArtifacts root
  let (depInterfaces, depGlobalGraph, depFFIInfo) = extractArtifactTriple maybeArtifacts
  let projectType = if isApp then Parse.Application else Parse.Package pkg
  discoveryResult <- discoverTransitiveDeps root srcDirs paths depInterfaces projectType
  case discoveryResult of
    Left (DiscoveryParseError path msg) ->
      return (Left (Exit.BuildCannotCompile (Exit.CompileError path
        [Diag.stringToDiagnostic Diag.PhaseParse "SYNTAX ERROR" (Text.unpack msg)])))
    Right allModuleInfo -> do
      timedResult <- compileModulesInOrderTimed pkg projectType root depInterfaces allModuleInfo
      case timedResult of
        Left err -> return (Left err)
        Right (compilationResult, timings) ->
          return (Right (assembleArtifacts pkg depGlobalGraph depFFIInfo compilationResult, timings))

-- | Compile from exposed modules using the query-based compiler.
--
-- Discovers module file paths from the exposed module names, then
-- delegates to 'compileFromPaths' for the actual compilation.
--
-- @since 0.19.1
compileFromExposed ::
  Pkg.Name ->
  Bool ->
  ProjectRoot ->
  [SrcDir] ->
  NE.List ModuleName.Raw ->
  IO (Either Exit.BuildError Build.Artifacts)
compileFromExposed pkg isApp projectRoot srcDirs exposedModules = do
  Log.logEvent (BuildStarted (Text.pack "compileFromExposed"))
  let root = Builder.Paths.unProjectRoot projectRoot
  paths <- discoverModulePaths root srcDirs (NE.toList exposedModules)
  compileFromPaths pkg isApp projectRoot srcDirs paths

-- DEPENDENCY LOADING

-- | Load all dependency artifacts (interfaces, GlobalGraph, FFI info).
--
-- Reads project dependencies from canopy.json/elm.json using 'Outline.read',
-- then loads cached package artifacts in parallel.
--
-- @since 0.19.1
loadDependencyArtifacts :: FilePath -> IO (Maybe (Map.Map ModuleName.Raw Interface.Interface, Opt.GlobalGraph, Map.Map String JS.FFIInfo))
loadDependencyArtifacts root = do
  eitherOutline <- Outline.read root
  let deps = either (const []) Outline.allDeps eitherOutline
  Log.logEvent (BuildModuleQueued (Text.pack ("loading " ++ show (length deps) ++ " dependencies")))
  loadDepsFromList deps

-- | Load dependencies from a resolved list.
--
-- @since 0.19.1
loadDepsFromList ::
  [(Pkg.Name, Version.Version)] ->
  IO (Maybe (Map.Map ModuleName.Raw Interface.Interface, Opt.GlobalGraph, Map.Map String JS.FFIInfo))
loadDepsFromList [] = do
  Log.logEvent (BuildModuleQueued (Text.pack "no dependencies found"))
  return (Just (Map.empty, Opt.empty, Map.empty))
loadDepsFromList deps = do
  maybeArtifacts <- PackageCache.loadAllPackageArtifacts deps
  return (Just (maybe (Map.empty, Opt.empty, Map.empty) extractPackageArtifacts maybeArtifacts))

-- | Extract the triple from loaded dependency artifacts.
--
-- @since 0.19.1
extractArtifactTriple ::
  Maybe (Map.Map ModuleName.Raw Interface.Interface, Opt.GlobalGraph, Map.Map String JS.FFIInfo) ->
  (Map.Map ModuleName.Raw Interface.Interface, Opt.GlobalGraph, Map.Map String JS.FFIInfo)
extractArtifactTriple (Just triple) = triple
extractArtifactTriple Nothing = (Map.empty, Opt.empty, Map.empty)

-- | Extract interfaces, object graph, and FFI info from loaded package artifacts.
--
-- @since 0.19.1
extractPackageArtifacts :: PackageCache.PackageArtifacts -> (Map.Map ModuleName.Raw Interface.Interface, Opt.GlobalGraph, Map.Map String JS.FFIInfo)
extractPackageArtifacts artifacts =
  (convertedInterfaces, globalGraph, ffiInfo)
  where
    depInterfaces = PackageCache.artifactInterfaces artifacts
    convertedInterfaces = convertDependencyInterfaces depInterfaces
    globalGraph = PackageCache.artifactObjects artifacts
    ffiInfo = PackageCache.artifactFFIInfo artifacts

-- | Convert DependencyInterface map to Interface map.
--
-- @since 0.19.1
convertDependencyInterfaces :: Map.Map ModuleName.Raw Interface.DependencyInterface -> Map.Map ModuleName.Raw Interface.Interface
convertDependencyInterfaces = Map.mapMaybe extractInterface
  where
    extractInterface :: Interface.DependencyInterface -> Maybe Interface.Interface
    extractInterface (Interface.Public iface) = Just iface
    extractInterface (Interface.Private pkg unions aliases) =
      Just (Interface.Interface pkg Map.empty (Map.map Interface.PrivateUnion unions) (Map.map Interface.PrivateAlias aliases) Map.empty Map.empty Map.empty [])
