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
--
-- This facade re-exports their public APIs and provides the top-level
-- compilation orchestration (parallel compilation in dependency order).
--
-- @since 0.19.1
module Compiler
  ( -- * Compilation Functions
    compileFromPaths,
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

    -- * Re-exports for Terminal
    module Build.Artifacts,
  )
where

import qualified AST.Optimized as Opt
import qualified Build.Artifacts as Build
import Build.Artifacts
import qualified Build.Parallel as Parallel
import qualified Builder.Graph as Graph
import qualified Builder.Hash as Hash
import qualified Builder.Incremental as Incremental
import Builder.Paths (ProjectRoot (..))
import qualified Builder.Paths
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.NonEmptyList as NE
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Compiler.Cache
  ( encodeVersioned,
    decodeVersioned,
    loadBuildCache,
    saveBuildCache,
    tryCacheHit,
    saveToCacheAsync,
    logIncrementalStats,
  )
import Compiler.Discovery
  ( discoverTransitiveDeps,
    discoverModulePaths,
  )
import Compiler.Types
  ( SrcDir (..),
    ModuleResult (..),
    fromDriverResult,
    moduleResultToModule,
    srcDirToString,
  )
import qualified Control.Concurrent.Async as Async
import qualified Control.Concurrent.QSem as QSem
import qualified Control.Exception as Exception
import qualified Data.Binary as Binary
import qualified Data.ByteString.Lazy as LBS
import Data.IORef (IORef, newIORef, readIORef, atomicModifyIORef')
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Driver
import qualified Exit
import qualified GHC.Conc as Conc
import qualified Generate.JavaScript as JS
import Logging.Event (LogEvent (..), Phase (..))
import qualified Logging.Logger as Log
import qualified PackageCache
import qualified Parse.Module as Parse
import qualified Query.Engine as Engine
import qualified Query.Simple as Query
import Control.Monad (when)

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
  allModuleInfo <- discoverTransitiveDeps root srcDirs paths depInterfaces projectType
  Log.logEvent (BuildModuleQueued (Text.pack ("discovered " ++ show (Map.size allModuleInfo) ++ " total modules")))
  compileResult <- compileModulesInOrder pkg projectType root depInterfaces allModuleInfo
  either (return . Left) (return . Right . assembleArtifacts pkg depGlobalGraph depFFIInfo) compileResult

-- | Extract the triple from loaded dependency artifacts.
extractArtifactTriple ::
  Maybe (Map.Map ModuleName.Raw Interface.Interface, Opt.GlobalGraph, Map.Map String JS.FFIInfo) ->
  (Map.Map ModuleName.Raw Interface.Interface, Opt.GlobalGraph, Map.Map String JS.FFIInfo)
extractArtifactTriple (Just triple) = triple
extractArtifactTriple Nothing = (Map.empty, Opt.empty, Map.empty)

-- | Assemble final build artifacts from compilation results.
assembleArtifacts ::
  Pkg.Name ->
  Opt.GlobalGraph ->
  Map.Map String JS.FFIInfo ->
  ([ModuleResult], Map.Map ModuleName.Raw Interface.Interface) ->
  Build.Artifacts
assembleArtifacts pkg depGlobalGraph depFFIInfo (moduleResults, _finalInterfaces) =
  Build.Artifacts
    { Build._artifactsName = pkg,
      Build._artifactsDeps = Map.empty,
      Build._artifactsRoots = detectRoots modules,
      Build._artifactsModules = modules,
      Build._artifactsFFIInfo = ffiInfoMap,
      Build._artifactsGlobalGraph = mergedGlobalGraph,
      Build._artifactsLazyModules = allLazyModules
    }
  where
    modules = map moduleResultToModule moduleResults
    localGraphs = map mrLocalGraph moduleResults
    mergedGlobalGraph = mergeGraphs depGlobalGraph localGraphs
    ffiInfoMap = Map.union (Map.unions (map mrFFIInfo moduleResults)) depFFIInfo
    allLazyModules = Set.unions (map mrLazyImports moduleResults)

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

-- PARALLEL COMPILATION

-- | Compile modules in dependency order with parallel execution and
-- incremental caching.
--
-- Takes pre-computed import lists from 'discoverTransitiveDeps' to
-- avoid re-parsing every module just to extract imports for the
-- dependency graph.
compileModulesInOrder ::
  Pkg.Name ->
  Parse.ProjectType ->
  FilePath ->
  Map.Map ModuleName.Raw Interface.Interface ->
  Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw]) ->
  IO (Either Exit.BuildError ([ModuleResult], Map.Map ModuleName.Raw Interface.Interface))
compileModulesInOrder pkg projectType root initialInterfaces moduleInfo = do
  Log.logEvent (BuildStarted (Text.pack ("parallel compilation: " ++ show (Map.size moduleInfo) ++ " modules")))
  buildCache <- loadBuildCache root
  cacheRef <- newIORef buildCache
  hitRef <- newIORef (0 :: Int)
  missRef <- newIORef (0 :: Int)
  engine <- Engine.initEngine
  let graph = buildDependencyGraph moduleInfo
  Log.logEvent (BuildModuleQueued (Text.pack ("dependency graph: " ++ show (Map.size moduleInfo) ++ " modules")))
  let plan = Parallel.groupByDependencyLevel graph
      levels = Parallel.planLevels plan
      modulePaths = Map.map fst moduleInfo
      importMap = Map.map snd moduleInfo
  Log.logEvent (BuildModuleQueued (Text.pack (show (length levels) ++ " dependency levels")))
  result <- compileLevels engine cacheRef hitRef missRef pkg projectType root levels initialInterfaces [] modulePaths importMap
  finalCache <- readIORef cacheRef
  saveBuildCache root finalCache
  logIncrementalStats hitRef missRef
  Driver.logCacheStats engine
  return result

-- | Build the dependency graph from pre-computed module info.
buildDependencyGraph ::
  Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw]) ->
  Graph.DependencyGraph
buildDependencyGraph moduleInfo =
  Graph.buildGraph depList
  where
    moduleNames = Map.keysSet (Map.map fst moduleInfo)
    depList = [(modName, filter (`Set.member` moduleNames) imports) | (modName, (_path, imports)) <- Map.toList moduleInfo]

-- | Compile dependency levels one by one, accumulating results.
--
-- Accumulates results in reverse order for O(1) prepend, reverses
-- at the end.
compileLevels ::
  Engine.QueryEngine ->
  IORef Incremental.BuildCache ->
  IORef Int ->
  IORef Int ->
  Pkg.Name ->
  Parse.ProjectType ->
  FilePath ->
  [[ModuleName.Raw]] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  [ModuleResult] ->
  Map.Map ModuleName.Raw FilePath ->
  Map.Map ModuleName.Raw [ModuleName.Raw] ->
  IO (Either Exit.BuildError ([ModuleResult], Map.Map ModuleName.Raw Interface.Interface))
compileLevels _ _ _ _ _ _ _ [] ifaces compiled _ _ = return (Right (reverse compiled, ifaces))
compileLevels engine cacheRef hitRef missRef pkg projType root (level : restLevels) ifaces compiled statuses importMap = do
  levelResult <- compileLevelInParallel engine cacheRef hitRef missRef pkg projType root level ifaces statuses importMap
  case levelResult of
    Left err -> return (Left err)
    Right (levelCompiled, levelIfaces) ->
      compileLevels engine cacheRef hitRef missRef pkg projType root restLevels
        (Map.union levelIfaces ifaces) (reverse levelCompiled ++ compiled) statuses importMap

-- | Compile a single dependency level (all modules in parallel).
compileLevelInParallel ::
  Engine.QueryEngine ->
  IORef Incremental.BuildCache ->
  IORef Int ->
  IORef Int ->
  Pkg.Name ->
  Parse.ProjectType ->
  FilePath ->
  [ModuleName.Raw] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  Map.Map ModuleName.Raw FilePath ->
  Map.Map ModuleName.Raw [ModuleName.Raw] ->
  IO (Either Exit.BuildError ([ModuleResult], Map.Map ModuleName.Raw Interface.Interface))
compileLevelInParallel engine cacheRef hitRef missRef pkg projType root modules ifaces statuses importMap = do
  numCaps <- Conc.getNumCapabilities
  sem <- QSem.newQSem (max 1 numCaps)
  results <- Async.mapConcurrently (withSemaphore sem . compileOneModule engine cacheRef hitRef missRef pkg projType root ifaces statuses importMap) modules
  let (errors, successes) = partitionEithers results
  case errors of
    [err] -> return (Left err)
    (_ : _) -> return (Left (Exit.BuildMultipleErrors (concatMap extractCompileErrors errors)))
    [] -> return (Right (map fst successes, Map.fromList [pair | (_, pair) <- successes]))

-- | Compile a single module with incremental cache check.
compileOneModule ::
  Engine.QueryEngine ->
  IORef Incremental.BuildCache ->
  IORef Int ->
  IORef Int ->
  Pkg.Name ->
  Parse.ProjectType ->
  FilePath ->
  Map.Map ModuleName.Raw Interface.Interface ->
  Map.Map ModuleName.Raw FilePath ->
  Map.Map ModuleName.Raw [ModuleName.Raw] ->
  ModuleName.Raw ->
  IO (Either Exit.BuildError (ModuleResult, (ModuleName.Raw, Interface.Interface)))
compileOneModule engine cacheRef hitRef missRef pkg projType root ifaces statuses importMap modName =
  case Map.lookup modName statuses of
    Nothing ->
      return (Left (Exit.BuildCannotCompile (Exit.CompileModuleNotFound errMsg)))
      where errMsg = "Internal error: Module " ++ Name.toChars modName ++ " not found in module paths"
    Just path -> do
      let modImports = Maybe.fromMaybe [] (Map.lookup modName importMap)
      cached <- tryCacheHit cacheRef root modName path modImports ifaces
      maybe (handleCacheMiss engine cacheRef missRef pkg projType root modName path modImports ifaces)
            (handleCacheHit hitRef modName) cached

-- | Handle a cache hit for a module.
handleCacheHit ::
  IORef Int ->
  ModuleName.Raw ->
  ModuleResult ->
  IO (Either Exit.BuildError (ModuleResult, (ModuleName.Raw, Interface.Interface)))
handleCacheHit hitRef modName moduleResult = do
  atomicModifyIORef' hitRef (\n -> (n + 1, ()))
  Log.logEvent (CacheHit PhaseBuild (Text.pack (Name.toChars modName)))
  return (Right (moduleResult, (modName, mrInterface moduleResult)))

-- | Handle a cache miss: compile fresh and save to cache.
handleCacheMiss ::
  Engine.QueryEngine ->
  IORef Incremental.BuildCache ->
  IORef Int ->
  Pkg.Name ->
  Parse.ProjectType ->
  FilePath ->
  ModuleName.Raw ->
  FilePath ->
  [ModuleName.Raw] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  IO (Either Exit.BuildError (ModuleResult, (ModuleName.Raw, Interface.Interface)))
handleCacheMiss engine cacheRef missRef pkg projType root modName path modImports ifaces = do
  atomicModifyIORef' missRef (\n -> (n + 1, ()))
  Log.logEvent (CacheMiss PhaseBuild (Text.pack (Name.toChars modName)))
  compileFresh engine cacheRef pkg projType root modName path modImports ifaces

-- | Compile a module fresh and save to cache.
compileFresh ::
  Engine.QueryEngine ->
  IORef Incremental.BuildCache ->
  Pkg.Name ->
  Parse.ProjectType ->
  FilePath ->
  ModuleName.Raw ->
  FilePath ->
  [ModuleName.Raw] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  IO (Either Exit.BuildError (ModuleResult, (ModuleName.Raw, Interface.Interface)))
compileFresh engine cacheRef pkg projType root modName path modImports ifaces = do
  compilationResult <- Driver.compileModuleWithEngine engine pkg ifaces path projType
  either
    (return . Left . Exit.BuildCannotCompile . queryErrorToCompileError path)
    (finishCompilation cacheRef root modName path modImports ifaces)
    compilationResult

-- | Finish compilation: check interface stability, save to cache.
finishCompilation ::
  IORef Incremental.BuildCache ->
  FilePath ->
  ModuleName.Raw ->
  FilePath ->
  [ModuleName.Raw] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  Driver.CompileResult ->
  IO (Either Exit.BuildError (ModuleResult, (ModuleName.Raw, Interface.Interface)))
finishCompilation cacheRef root modName path modImports ifaces compiledResult = do
  let moduleResult = fromDriverResult compiledResult
  cache <- readIORef cacheRef
  let newIfaceHash = Hash.hashBytes (LBS.toStrict (Binary.encode (mrInterface moduleResult)))
      stable = Incremental.interfaceUnchanged cache modName newIfaceHash
  when stable $
    Log.logEvent (InterfaceSaved (Name.toChars modName ++ " (interface stable)"))
  saveToCacheAsync cacheRef root modName path modImports ifaces moduleResult
  return (Right (moduleResult, (modName, mrInterface moduleResult)))

-- DEPENDENCY LOADING

-- | Load all dependency artifacts (interfaces, GlobalGraph, FFI info).
--
-- Reads project dependencies from canopy.json/elm.json using 'Outline.read',
-- then loads cached package artifacts in parallel.
loadDependencyArtifacts :: FilePath -> IO (Maybe (Map.Map ModuleName.Raw Interface.Interface, Opt.GlobalGraph, Map.Map String JS.FFIInfo))
loadDependencyArtifacts root = do
  eitherOutline <- Outline.read root
  let deps = either (const []) Outline.allDeps eitherOutline
  Log.logEvent (BuildModuleQueued (Text.pack ("loading " ++ show (length deps) ++ " dependencies")))
  loadDepsFromList deps

-- | Load dependencies from a resolved list.
loadDepsFromList ::
  [(Pkg.Name, Version.Version)] ->
  IO (Maybe (Map.Map ModuleName.Raw Interface.Interface, Opt.GlobalGraph, Map.Map String JS.FFIInfo))
loadDepsFromList [] = do
  Log.logEvent (BuildModuleQueued (Text.pack "no dependencies found"))
  return (Just (Map.empty, Opt.empty, Map.empty))
loadDepsFromList deps = do
  maybeArtifacts <- PackageCache.loadAllPackageArtifacts deps
  return (Just (maybe (Map.empty, Opt.empty, Map.empty) extractPackageArtifacts maybeArtifacts))

-- | Extract interfaces, object graph, and FFI info from loaded package artifacts.
extractPackageArtifacts :: PackageCache.PackageArtifacts -> (Map.Map ModuleName.Raw Interface.Interface, Opt.GlobalGraph, Map.Map String JS.FFIInfo)
extractPackageArtifacts artifacts =
  (convertedInterfaces, globalGraph, ffiInfo)
  where
    depInterfaces = PackageCache.artifactInterfaces artifacts
    convertedInterfaces = convertDependencyInterfaces depInterfaces
    globalGraph = PackageCache.artifactObjects artifacts
    ffiInfo = PackageCache.artifactFFIInfo artifacts

-- | Convert DependencyInterface map to Interface map.
convertDependencyInterfaces :: Map.Map ModuleName.Raw Interface.DependencyInterface -> Map.Map ModuleName.Raw Interface.Interface
convertDependencyInterfaces = Map.mapMaybe extractInterface
  where
    extractInterface :: Interface.DependencyInterface -> Maybe Interface.Interface
    extractInterface (Interface.Public iface) = Just iface
    extractInterface (Interface.Private pkg unions aliases) =
      Just (Interface.Interface pkg Map.empty (Map.map Interface.PrivateUnion unions) (Map.map Interface.PrivateAlias aliases) Map.empty)

-- HELPERS

-- | Convert a QueryError to a CompileError with proper categorization.
queryErrorToCompileError :: FilePath -> Query.QueryError -> Exit.CompileError
queryErrorToCompileError path qErr =
  case qErr of
    Query.ParseError _ msg -> Exit.CompileParseError path msg
    Query.TypeError msg -> Exit.CompileTypeError path msg
    Query.FileNotFound fpath -> Exit.CompileModuleNotFound fpath
    Query.OtherError msg -> Exit.CompileCanonicalizeError path msg
    Query.DiagnosticError diagPath diags -> Exit.CompileDiagnosticError diagPath diags
    Query.TimeoutError tpath -> Exit.CompileTimeoutError tpath

-- | Merge dependency GlobalGraph with compiled LocalGraphs.
mergeGraphs :: Opt.GlobalGraph -> [Opt.LocalGraph] -> Opt.GlobalGraph
mergeGraphs depGlobalGraph localGraphs =
  foldr Opt.addLocalGraph depGlobalGraph localGraphs

-- | Detect root modules for artifact assembly.
detectRoots :: [Build.Module] -> NE.List Build.Root
detectRoots modules =
  case findMainModules modules of
    [] -> case modules of
      [] -> NE.List (Build.Inside (Name.fromChars "Main")) []
      (Build.Fresh modName iface localGraph : _) ->
        NE.List (Build.Outside modName iface localGraph) []
    (mainMod : rest) -> NE.List mainMod rest
  where
    findMainModules :: [Build.Module] -> [Build.Root]
    findMainModules = Maybe.mapMaybe moduleToRootIfMain

    moduleToRootIfMain :: Build.Module -> Maybe Build.Root
    moduleToRootIfMain (Build.Fresh modName iface localGraph@(Opt.LocalGraph maybeMain _ _ _)) =
      case maybeMain of
        Just _ -> Just (Build.Outside modName iface localGraph)
        Nothing -> Nothing

-- | Extract compile errors from a build error.
extractCompileErrors :: Exit.BuildError -> [Exit.CompileError]
extractCompileErrors (Exit.BuildCannotCompile err) = [err]
extractCompileErrors (Exit.BuildMultipleErrors errs) = errs
extractCompileErrors _ = []

-- | Bound an IO action with a semaphore for concurrency control.
--
-- @since 0.19.2
withSemaphore :: QSem.QSem -> IO a -> IO a
withSemaphore sem = Exception.bracket_ (QSem.waitQSem sem) (QSem.signalQSem sem)

-- | Partition a list of Eithers into separate lists.
partitionEithers :: [Either a b] -> ([a], [b])
partitionEithers = foldr (either left right) ([], [])
  where
    left a (l, r) = (a : l, r)
    right b (l, r) = (l, b : r)
