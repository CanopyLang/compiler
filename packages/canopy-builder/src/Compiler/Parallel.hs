{-# LANGUAGE OverloadedStrings #-}

-- | Parallel compilation orchestration in dependency order.
--
-- Compiles modules level-by-level through the dependency graph,
-- executing independent modules within each level concurrently.
-- Integrates with the incremental build cache to skip unchanged
-- modules and with the query engine for fresh compilations.
--
-- @since 0.19.1
module Compiler.Parallel
  ( -- * Parallel Compilation
    compileModulesInOrder,

    -- * Artifact Assembly
    assembleArtifacts,

    -- * Utilities
    mergeGraphs,
    detectRoots,
    extractCompileErrors,
  )
where

import qualified AST.Optimized as Opt
import qualified Build.Artifacts as Build
import qualified Build.Parallel as Parallel
import qualified Builder.Graph as Graph
import qualified Builder.Hash as Hash
import qualified Builder.Incremental as Incremental
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.NonEmptyList as NE
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Compiler.Cache
  ( loadBuildCache,
    logIncrementalStats,
    saveBuildCache,
    saveToCacheAsync,
    tryCacheHit,
  )
import Compiler.Types
  ( ModuleResult (..),
    fromDriverResult,
    moduleResultToModule,
  )
import qualified Control.Concurrent.Async as Async
import qualified Control.Concurrent.QSem as QSem
import qualified Control.Exception as Exception
import qualified Data.Binary as Binary
import qualified Data.ByteString.Lazy as LBS
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
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
import qualified Parse.Module as Parse
import qualified Query.Engine as Engine
import qualified Query.Simple as Query
import Control.Monad (when)

-- | Compile modules in dependency order with parallel execution and
-- incremental caching.
--
-- Takes pre-computed import lists from 'discoverTransitiveDeps' to
-- avoid re-parsing every module just to extract imports for the
-- dependency graph.
--
-- @since 0.19.1
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
  case Parallel.groupByDependencyLevel graph of
    Left (Parallel.CycleDetectedDuringLeveling cycleModules) ->
      return (Left (Exit.BuildCannotCompile (Exit.CompileParseError ""
        ("Dependency cycle detected among modules: " ++ show cycleModules))))
    Right plan -> do
      let levels = Parallel.planLevels plan
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

-- ARTIFACT ASSEMBLY

-- | Assemble final build artifacts from compilation results.
--
-- Merges the local graphs from each compiled module with the
-- dependency global graph and collects all FFI info.
--
-- @since 0.19.1
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

-- HELPERS

-- | Merge dependency GlobalGraph with compiled LocalGraphs.
--
-- @since 0.19.1
mergeGraphs :: Opt.GlobalGraph -> [Opt.LocalGraph] -> Opt.GlobalGraph
mergeGraphs depGlobalGraph localGraphs =
  foldr Opt.addLocalGraph depGlobalGraph localGraphs

-- | Detect root modules for artifact assembly.
--
-- @since 0.19.1
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
--
-- @since 0.19.1
extractCompileErrors :: Exit.BuildError -> [Exit.CompileError]
extractCompileErrors (Exit.BuildCannotCompile err) = [err]
extractCompileErrors (Exit.BuildMultipleErrors errs) = errs
extractCompileErrors _ = []

-- | Bound an IO action with a semaphore for concurrency control.
withSemaphore :: QSem.QSem -> IO a -> IO a
withSemaphore sem = Exception.bracket_ (QSem.waitQSem sem) (QSem.signalQSem sem)

-- | Partition a list of Eithers into separate lists.
partitionEithers :: [Either a b] -> ([a], [b])
partitionEithers = foldr (either left right) ([], [])
  where
    left a (l, r) = (a : l, r)
    right b (l, r) = (l, b : r)
