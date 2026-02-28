{-# LANGUAGE OverloadedStrings #-}

-- | Pure functional compiler interface for Terminal.
--
-- This module provides the NEW compiler interface that Terminal expects,
-- wrapping the query-based Driver with a clean API. It replaces the OLD
-- Build.fromPaths and Build.fromExposed functions with pure functional
-- equivalents using the NEW Driver.
--
-- **Architecture:**
--
-- * Uses Driver for compilation (query-based, no STM)
-- * Returns Build.Artifacts for Terminal compatibility
-- * Pure functional - no MVar/TVar/STM
-- * JSON caching through Driver
--
-- @since 0.19.1
module Compiler
  ( -- * Compilation Functions
    compileFromPaths
  , compileFromExposed

  -- * Types
  , SrcDir (..)

  -- * Path Types (re-exported)
  , Builder.Paths.ProjectRoot (..)
  , Builder.Paths.mkProjectRoot

  -- * Re-exports for Terminal
  , module Build.Artifacts
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import qualified Build.Artifacts as Build
import Build.Artifacts
import qualified Build.Parallel as Parallel
import qualified Builder.Graph as Graph
import qualified Builder.Hash as Hash
import qualified Builder.Incremental as Incremental
import Builder.Paths (ProjectRoot (..))
import qualified Builder.Paths
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Data.Binary as Binary
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import Control.Exception (IOException)
import qualified Control.Exception as Exception
import Data.Word (Word16)
import Control.Monad (filterM)
import qualified Control.Concurrent.Async as Async
import qualified Control.Concurrent.QSem as QSem
import qualified GHC.Conc as Conc
import Data.IORef (IORef, newIORef, readIORef, atomicModifyIORef')
import qualified Data.Maybe as Maybe
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.NonEmptyList as NE
import qualified Data.Set as Set
import qualified Data.ByteString as BS
import Logging.Event (LogEvent (..), Phase (..))
import qualified Logging.Logger as Log
import qualified Driver
import qualified Exit
import qualified Reporting.InternalError as InternalError
import qualified Generate.JavaScript as JS
import qualified Query.Engine as Engine
import qualified Query.Simple as Query
import qualified PackageCache
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as Ann
import qualified Data.Time.Clock as Time
import System.FilePath ((</>), normalise)
import qualified System.Directory as Dir
import qualified Canopy.Limits as Limits

-- | Compile from file paths using NEW compiler.
--
-- This is the NEW replacement for Build.fromPaths.
-- Now includes source directories for transitive import discovery.
compileFromPaths ::
  Pkg.Name ->
  Bool ->
  ProjectRoot ->
  [SrcDir] ->
  [FilePath] ->
  IO (Either Exit.BuildError Build.Artifacts)
compileFromPaths pkg isApp (ProjectRoot root) srcDirs paths = do
  Log.logEvent (BuildStarted (Text.pack "compileFromPaths"))

  -- Load dependency artifacts (interfaces + GlobalGraph + FFI info)
  maybeArtifacts <- loadDependencyArtifacts root
  let (depInterfaces, depGlobalGraph, depFFIInfo) = case maybeArtifacts of
        Just (ifaces, globalGraph, ffi) -> (ifaces, globalGraph, ffi)
        Nothing -> (Map.empty, Opt.empty, Map.empty)

  Log.logEvent (BuildModuleQueued (Text.pack ("loaded " ++ show (Map.size depInterfaces) ++ " dependency interfaces")))

  -- Discover transitive dependencies (returns paths + pre-computed imports)
  let projectType = if isApp then Parse.Application else Parse.Package pkg
  allModuleInfo <- discoverTransitiveDeps root srcDirs paths depInterfaces projectType
  Log.logEvent (BuildModuleQueued (Text.pack ("discovered " ++ show (Map.size allModuleInfo) ++ " total modules")))

  -- Compile in dependency order with growing interface map and incremental caching
  compileResult <- compileModulesInOrder pkg projectType root depInterfaces allModuleInfo
  case compileResult of
    Left err -> return (Left err)
    Right (moduleResults, _finalInterfaces) -> do
      -- Build artifacts from unified ModuleResults
      let modules = map moduleResultToModule moduleResults
          localGraphs = map mrLocalGraph moduleResults
          mergedGlobalGraph = mergeGraphs depGlobalGraph localGraphs
          ffiInfoMap = Map.union (Map.unions (map mrFFIInfo moduleResults)) depFFIInfo
          allLazyModules = Set.unions (map mrLazyImports moduleResults)
          artifacts = Build.Artifacts
            { Build._artifactsName = pkg
            , Build._artifactsDeps = Map.empty
            , Build._artifactsRoots = detectRoots modules
            , Build._artifactsModules = modules
            , Build._artifactsFFIInfo = ffiInfoMap
            , Build._artifactsGlobalGraph = mergedGlobalGraph
            , Build._artifactsLazyModules = allLazyModules
            }
      return (Right artifacts)

-- | Source directory types (pure, no dependencies).
data SrcDir
  = AbsoluteSrcDir FilePath
  | RelativeSrcDir FilePath
  deriving (Show, Eq)

-- | Unified module compilation result.
--
-- Holds everything needed to build final artifacts, whether the module
-- was freshly compiled or loaded from the incremental cache.
data ModuleResult = ModuleResult
  { mrModuleName :: !ModuleName.Raw
  , mrInterface :: !Interface.Interface
  , mrLocalGraph :: !Opt.LocalGraph
  , mrFFIInfo :: !(Map.Map String JS.FFIInfo)
  , mrLazyImports :: !(Set.Set ModuleName.Canonical)
  }

-- | Convert a Driver.CompileResult into a ModuleResult.
fromDriverResult :: Driver.CompileResult -> ModuleResult
fromDriverResult result =
  ModuleResult
    { mrModuleName = extractModuleName canMod
    , mrInterface = Driver.compileResultInterface result
    , mrLocalGraph = Driver.compileResultLocalGraph result
    , mrFFIInfo = Driver.compileResultFFIInfo result
    , mrLazyImports = Can._lazyImports canMod
    }
  where
    canMod = Driver.compileResultModule result

-- | Path to the build cache index file.
cachePath :: FilePath -> FilePath
cachePath root = root </> "canopy-stuff" </> "build-cache.json"

-- | Path to a cached module artifact (Binary-encoded Interface + LocalGraph).
cacheArtifactPath :: FilePath -> ModuleName.Raw -> FilePath
cacheArtifactPath root modName =
  root </> "canopy-stuff" </> "cache" </> Name.toChars modName ++ ".elco"

-- | Compile from exposed modules using NEW compiler.
--
-- This is the NEW replacement for Build.fromExposed.

compileFromExposed ::
  Pkg.Name ->
  Bool ->
  ProjectRoot ->
  [SrcDir] ->
  NE.List ModuleName.Raw ->
  IO (Either Exit.BuildError Build.Artifacts)
compileFromExposed pkg isApp projectRoot srcDirs exposedModules = do
  Log.logEvent (BuildStarted (Text.pack "compileFromExposed"))

  -- Discover module paths
  let root = unProjectRoot projectRoot
  paths <- discoverModulePaths root srcDirs (NE.toList exposedModules)

  compileFromPaths pkg isApp projectRoot srcDirs paths

-- | Discover transitive dependencies, returning both file paths and
-- pre-computed import lists. This avoids a redundant re-parse when
-- building the dependency graph for parallel compilation.
discoverTransitiveDeps ::
  FilePath ->
  [SrcDir] ->
  [FilePath] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  Parse.ProjectType ->
  IO (Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw]))
discoverTransitiveDeps root srcDirs initialPaths depInterfaces projectType = do
  Log.logEvent (BuildStarted (Text.pack ("discoverTransitiveDeps: " ++ root)))
  initialModules <- mapM (parseModuleFile projectType) initialPaths
  Log.logEvent (BuildModuleQueued (Text.pack ("parsed " ++ show (length initialModules) ++ " initial modules")))
  let initialMap = Map.fromList [(Src.getName m, (p, extractImports m)) | (m, p) <- zip initialModules initialPaths]
  result <- discoverImports root srcDirs initialMap Set.empty initialModules depInterfaces projectType
  Log.logEvent (BuildModuleQueued (Text.pack ("discovered " ++ show (Map.size result) ++ " modules total")))
  return result
  where
    parseModuleFile projType path = do
      content <- readSourceWithLimit path
      case Parse.fromByteString projType content of
        Left err -> InternalError.report
          "Compiler.discoverTransitiveDeps.parseModuleFile"
          ("Failed to parse module: " <> Text.pack path)
          ("Parse error while discovering transitive dependencies: " <> Text.pack (show err))
        Right m -> return m

-- | Recursively discover imports using DFS traversal.
--
-- Uses DFS order (prepend new modules) instead of BFS (append) to avoid
-- O(N) list append per step. Also reuses already-resolved paths to
-- eliminate redundant file system lookups.
discoverImports ::
  FilePath ->
  [SrcDir] ->
  Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw]) ->
  Set.Set ModuleName.Raw ->
  [Src.Module] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  Parse.ProjectType ->
  IO (Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw]))
discoverImports root srcDirs found visited modules depInterfaces projectType =
  case modules of
    [] -> do
      Log.logEvent (BuildModuleQueued (Text.pack ("discoverImports complete: " ++ show (Map.size found) ++ " modules")))
      return found
    (modul : rest) -> do
      let modName = Src.getName modul
      if Set.member modName visited || Map.member modName depInterfaces
        then
          discoverImports root srcDirs found (Set.insert modName visited) rest depInterfaces projectType
        else do
          let imports = extractImports modul
              newImports = filter (\imp -> not (Map.member imp found) && not (Map.member imp depInterfaces)) imports
          newPaths <- mapM (findModulePath root srcDirs) newImports
          let validPairs = [(imp, path) | (Just path, imp) <- zip newPaths newImports]
              newFound = foldr (\(imp, path) m -> Map.insert imp (path, []) m) found validPairs
          newModules <- mapM (parseModuleAtPath projectType) validPairs
          -- Backfill import lists for newly parsed modules
          let newFoundWithImports = foldr (\nm acc -> Map.adjust (\(p, _) -> (p, extractImports nm)) (Src.getName nm) acc) newFound newModules
          discoverImports root srcDirs newFoundWithImports (Set.insert modName visited) (newModules ++ rest) depInterfaces projectType

-- | Parse a module at a known file path.
--
-- Unlike 'findModulePath' + parse, this skips path resolution since the
-- caller already resolved the path during import discovery.
parseModuleAtPath :: Parse.ProjectType -> (ModuleName.Raw, FilePath) -> IO Src.Module
parseModuleAtPath projectType (_modName, path) = do
  content <- readSourceWithLimit path
  case Parse.fromByteString projectType content of
    Left err -> InternalError.report
      "Compiler.parseModuleAtPath"
      ("Failed to parse: " <> Text.pack path)
      ("Parse error: " <> Text.pack (show err))
    Right m -> return m

-- | Read a source file with a size limit check.
--
-- Checks the file size on disk against 'Limits.maxSourceFileBytes'
-- before reading. This prevents out-of-memory conditions when
-- encountering accidentally-huge or malicious source files.
--
-- Throws an 'IOError' with a descriptive message if the file exceeds
-- the limit. The error is caught and displayed by the caller's error
-- handling, producing a clear user-facing message.
--
-- @since 0.19.2
readSourceWithLimit :: FilePath -> IO BS.ByteString
readSourceWithLimit path = do
  size <- Dir.getFileSize path
  enforceSourceLimit path (fromIntegral size)
  BS.readFile path

-- | Enforce the source file size limit.
--
-- @since 0.19.2
enforceSourceLimit :: FilePath -> Int -> IO ()
enforceSourceLimit path size =
  case Limits.checkFileSize path size Limits.maxSourceFileBytes of
    Nothing -> pure ()
    Just (Limits.FileSizeError fp actual limit) ->
      ioError (userError (fileTooLargeMessage fp actual limit))

-- | Format a file-too-large error message for source files.
--
-- @since 0.19.2
fileTooLargeMessage :: FilePath -> Int -> Int -> String
fileTooLargeMessage path actual limit =
  "FILE TOO LARGE -- " ++ path ++ "\n\n"
    ++ "    This source file is " ++ showMB actual
    ++ ", which exceeds the " ++ showMB limit ++ " limit.\n\n"
    ++ "    Consider splitting it into smaller modules.\n"
  where
    showMB bytes = show (bytes `div` (1024 * 1024)) ++ " MB"

-- | Extract import names from a parsed module.
extractImports :: Src.Module -> [ModuleName.Raw]
extractImports modul =
  [Ann.toValue (Src._importName imp) | imp <- Src._imports modul]

findModulePath :: FilePath -> [SrcDir] -> ModuleName.Raw -> IO (Maybe FilePath)
findModulePath root srcDirs modName = do
  paths <- findModuleInDirs root srcDirs modName
  return (case paths of
            [] -> Nothing
            (p:_) -> Just p)

-- Helper: Compile modules in dependency order with PARALLEL execution and incremental caching.
--
-- Takes pre-computed import lists from 'discoverTransitiveDeps' to avoid
-- re-parsing every module just to extract imports for the dependency graph.
compileModulesInOrder ::
  Pkg.Name ->
  Parse.ProjectType ->
  FilePath ->
  Map.Map ModuleName.Raw Interface.Interface ->
  Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw]) ->
  IO (Either Exit.BuildError ([ModuleResult], Map.Map ModuleName.Raw Interface.Interface))
compileModulesInOrder pkg projectType root initialInterfaces moduleInfo = do
  Log.logEvent (BuildStarted (Text.pack ("parallel compilation: " ++ show (Map.size moduleInfo) ++ " modules")))

  -- Load incremental build cache
  buildCache <- loadBuildCache root
  cacheRef <- newIORef buildCache
  hitRef <- newIORef (0 :: Int)
  missRef <- newIORef (0 :: Int)

  -- Create shared query engine for all module compilations
  engine <- Engine.initEngine

  -- Build dependency graph from pre-computed imports (no re-parsing needed)
  let modulePaths = Map.map fst moduleInfo
      moduleNames = Map.keysSet modulePaths
      depList = [(modName, filter (`Set.member` moduleNames) imports) | (modName, (_path, imports)) <- Map.toList moduleInfo]
      graph = Graph.buildGraph depList
      importMap = Map.map snd moduleInfo

  Log.logEvent (BuildModuleQueued (Text.pack ("dependency graph: " ++ show (length depList) ++ " modules")))

  -- Compile in parallel with caching
  result <- compileWithCache engine cacheRef hitRef missRef graph modulePaths initialInterfaces importMap

  -- Save updated cache and log stats
  finalCache <- readIORef cacheRef
  saveBuildCache root finalCache
  logIncrementalStats hitRef missRef

  -- Log query engine cache statistics
  Driver.logCacheStats engine

  return result
  where
    -- Compile with incremental cache integration
    compileWithCache ::
      Engine.QueryEngine ->
      IORef Incremental.BuildCache ->
      IORef Int -> IORef Int ->
      Graph.DependencyGraph ->
      Map.Map ModuleName.Raw FilePath ->
      Map.Map ModuleName.Raw Interface.Interface ->
      Map.Map ModuleName.Raw [ModuleName.Raw] ->
      IO (Either Exit.BuildError ([ModuleResult], Map.Map ModuleName.Raw Interface.Interface))
    compileWithCache queryEngine cacheRef hitRef missRef graph statuses initialIfaces modImportMap = do
      let plan = Parallel.groupByDependencyLevel graph
          levels = Parallel.planLevels plan
      Log.logEvent (BuildModuleQueued (Text.pack (show (length levels) ++ " dependency levels")))
      compileLevels queryEngine cacheRef hitRef missRef levels initialIfaces [] statuses modImportMap

    -- Compile levels one by one, accumulating results and interfaces
    compileLevels ::
      Engine.QueryEngine ->
      IORef Incremental.BuildCache ->
      IORef Int -> IORef Int ->
      [[ModuleName.Raw]] ->
      Map.Map ModuleName.Raw Interface.Interface ->
      [ModuleResult] ->
      Map.Map ModuleName.Raw FilePath ->
      Map.Map ModuleName.Raw [ModuleName.Raw] ->
      IO (Either Exit.BuildError ([ModuleResult], Map.Map ModuleName.Raw Interface.Interface))
    -- Accumulates results in reverse order for O(1) prepend, reverses at the end.
    compileLevels _ _ _ _ [] ifaces compiled _ _ = return (Right (reverse compiled, ifaces))
    compileLevels queryEngine cacheRef hitRef missRef (level : restLevels) ifaces compiled statuses modImportMap = do
      levelResult <- compileLevelInParallel queryEngine cacheRef hitRef missRef level ifaces statuses modImportMap
      case levelResult of
        Left err -> return (Left err)
        Right (levelCompiled, levelIfaces) -> do
          let newIfaces = Map.union levelIfaces ifaces
              newCompiled = reverse levelCompiled ++ compiled
          compileLevels queryEngine cacheRef hitRef missRef restLevels newIfaces newCompiled statuses modImportMap

    -- Compile a single level (all modules in parallel)
    compileLevelInParallel ::
      Engine.QueryEngine ->
      IORef Incremental.BuildCache ->
      IORef Int -> IORef Int ->
      [ModuleName.Raw] ->
      Map.Map ModuleName.Raw Interface.Interface ->
      Map.Map ModuleName.Raw FilePath ->
      Map.Map ModuleName.Raw [ModuleName.Raw] ->
      IO (Either Exit.BuildError ([ModuleResult], Map.Map ModuleName.Raw Interface.Interface))
    compileLevelInParallel queryEngine cacheRef hitRef missRef modules ifaces statuses modImportMap = do
      numCaps <- Conc.getNumCapabilities
      sem <- QSem.newQSem (max 1 numCaps)
      results <- Async.mapConcurrently (withSemaphore sem . compileOneModule queryEngine cacheRef hitRef missRef ifaces statuses modImportMap) modules
      let (errors, successes) = partitionEithers results
      case errors of
        [err] -> return (Left err)
        (_ : _) -> return (Left (Exit.BuildMultipleErrors (concatMap extractCompileErrors errors)))
        [] -> do
          let compiled = map fst successes
              newIfaces = Map.fromList [pair | (_, pair) <- successes]
          return (Right (compiled, newIfaces))

    -- Compile a single module with incremental cache check
    compileOneModule ::
      Engine.QueryEngine ->
      IORef Incremental.BuildCache ->
      IORef Int -> IORef Int ->
      Map.Map ModuleName.Raw Interface.Interface ->
      Map.Map ModuleName.Raw FilePath ->
      Map.Map ModuleName.Raw [ModuleName.Raw] ->
      ModuleName.Raw ->
      IO (Either Exit.BuildError (ModuleResult, (ModuleName.Raw, Interface.Interface)))
    compileOneModule queryEngine cacheRef hitRef missRef ifaces statuses modImportMap modName =
      case Map.lookup modName statuses of
        Nothing ->
          return (Left (Exit.BuildCannotCompile (Exit.CompileModuleNotFound errMsg)))
          where errMsg = "Internal error: Module " ++ Name.toChars modName ++ " not found in module paths"
        Just path -> do
          let modImports = Maybe.fromMaybe [] (Map.lookup modName modImportMap)
          -- Check incremental cache
          cached <- tryCacheHit cacheRef root modName path modImports ifaces
          case cached of
            Just moduleResult -> do
              atomicModifyIORef' hitRef (\n -> (n + 1, ()))
              Log.logEvent (CacheHit PhaseBuild (Text.pack (Name.toChars modName)))
              return (Right (moduleResult, (modName, mrInterface moduleResult)))
            Nothing -> do
              atomicModifyIORef' missRef (\n -> (n + 1, ()))
              Log.logEvent (CacheMiss PhaseBuild (Text.pack (Name.toChars modName)))
              compileFresh queryEngine cacheRef root modName path modImports ifaces

    -- Attempt compilation from cache
    compileFresh ::
      Engine.QueryEngine ->
      IORef Incremental.BuildCache ->
      FilePath ->
      ModuleName.Raw ->
      FilePath ->
      [ModuleName.Raw] ->
      Map.Map ModuleName.Raw Interface.Interface ->
      IO (Either Exit.BuildError (ModuleResult, (ModuleName.Raw, Interface.Interface)))
    compileFresh queryEngine cacheRef projRoot modName path modImports ifaces = do
      compilationResult <- Driver.compileModuleWithEngine queryEngine pkg ifaces path projectType
      case compilationResult of
        Left err -> return (Left (Exit.BuildCannotCompile (queryErrorToCompileError path err)))
        Right compiledResult -> do
          let moduleResult = fromDriverResult compiledResult
          -- Save to incremental cache
          saveToCacheAsync cacheRef projRoot modName path modImports ifaces moduleResult
          return (Right (moduleResult, (modName, mrInterface moduleResult)))

    -- Helper to partition Either lists
    partitionEithers :: [Either a b] -> ([a], [b])
    partitionEithers = foldr (either left right) ([], [])
      where
        left a (l, r) = (a : l, r)
        right b (l, r) = (l, b : r)

-- | Extract compile errors from a build error.
--
-- For single errors, wraps in a list. For multiple errors,
-- returns all contained compile errors.
extractCompileErrors :: Exit.BuildError -> [Exit.CompileError]
extractCompileErrors (Exit.BuildCannotCompile err) = [err]
extractCompileErrors (Exit.BuildMultipleErrors errs) = errs
extractCompileErrors _ = []

-- | Bound an IO action with a semaphore for concurrency control.
--
-- Acquires the semaphore before running the action and releases it
-- afterward, even if the action throws an exception. This limits
-- the number of concurrent compilations to prevent file descriptor
-- and memory exhaustion on large projects.
--
-- @since 0.19.2
withSemaphore :: QSem.QSem -> IO a -> IO a
withSemaphore sem = Exception.bracket_ (QSem.waitQSem sem) (QSem.signalQSem sem)

-- Helper: Convert QueryError to CompileError with proper categorization.
--
-- 'DiagnosticError' passes through directly for rich structured output.
-- Legacy string-based errors are wrapped in their respective constructors.
queryErrorToCompileError :: FilePath -> Query.QueryError -> Exit.CompileError
queryErrorToCompileError path qErr =
  case qErr of
    Query.ParseError _ msg -> Exit.CompileParseError path msg
    Query.TypeError msg -> Exit.CompileTypeError path msg
    Query.FileNotFound fpath -> Exit.CompileModuleNotFound fpath
    Query.OtherError msg -> Exit.CompileCanonicalizeError path msg
    Query.DiagnosticError diagPath diags -> Exit.CompileDiagnosticError diagPath diags
    Query.TimeoutError tpath -> Exit.CompileTimeoutError tpath

-- | Load all dependency artifacts (interfaces, GlobalGraph, FFI info).
--
-- Reads project dependencies from canopy.json/elm.json using 'Outline.read',
-- then loads cached package artifacts in parallel.
loadDependencyArtifacts :: FilePath -> IO (Maybe (Map.Map ModuleName.Raw Interface.Interface, Opt.GlobalGraph, Map.Map String JS.FFIInfo))
loadDependencyArtifacts root = do
  eitherOutline <- Outline.read root
  let deps = either (const []) Outline.allDeps eitherOutline
  Log.logEvent (BuildModuleQueued (Text.pack ("loading " ++ show (length deps) ++ " dependencies")))

  case deps of
    [] -> do
      Log.logEvent (BuildModuleQueued (Text.pack "no dependencies found"))
      return (Just (Map.empty, Opt.empty, Map.empty))
    _ -> do
      maybeArtifacts <- PackageCache.loadAllPackageArtifacts deps
      case maybeArtifacts of
        Nothing -> do
          Log.logEvent (BuildModuleQueued (Text.pack "no valid packages loaded"))
          return (Just (Map.empty, Opt.empty, Map.empty))
        Just artifacts -> do
          let depInterfaces = PackageCache.artifactInterfaces artifacts
              convertedInterfaces = convertDependencyInterfaces depInterfaces
              globalGraph = PackageCache.artifactObjects artifacts
              ffiInfo = PackageCache.artifactFFIInfo artifacts
          Log.logEvent (BuildModuleQueued (Text.pack ("loaded " ++ show (Map.size convertedInterfaces) ++ " module interfaces")))
          return (Just (convertedInterfaces, globalGraph, ffiInfo))

-- Helper: Convert DependencyInterface map to Interface map
convertDependencyInterfaces :: Map.Map ModuleName.Raw Interface.DependencyInterface -> Map.Map ModuleName.Raw Interface.Interface
convertDependencyInterfaces = Map.mapMaybe extractInterface
  where
    extractInterface :: Interface.DependencyInterface -> Maybe Interface.Interface
    extractInterface (Interface.Public iface) = Just iface
    extractInterface (Interface.Private pkg unions aliases) =
      -- Convert Private to Interface by wrapping unions and aliases
      Just (Interface.Interface pkg Map.empty (Map.map Interface.PrivateUnion unions) (Map.map Interface.PrivateAlias aliases) Map.empty)

-- | Convert a ModuleResult to Build.Module.
moduleResultToModule :: ModuleResult -> Build.Module
moduleResultToModule mr = Build.Fresh (mrModuleName mr) (mrInterface mr) (mrLocalGraph mr)

-- INCREMENTAL CACHE HELPERS

-- | Load build cache from disk, returning empty cache on failure.
loadBuildCache :: FilePath -> IO Incremental.BuildCache
loadBuildCache root = do
  maybeCache <- Incremental.loadCache (cachePath root)
  maybe Incremental.emptyCache return maybeCache

-- | Save build cache to disk.
saveBuildCache :: FilePath -> Incremental.BuildCache -> IO ()
saveBuildCache root cache = do
  let cacheDir = root </> "canopy-stuff"
  Dir.createDirectoryIfMissing True cacheDir
  Incremental.saveCache (cachePath root) cache

-- | Try to load a module from the incremental cache.
--
-- Checks source hash and dependency hash. If both match, loads
-- the cached Interface and LocalGraph from the binary artifact file.
tryCacheHit ::
  IORef Incremental.BuildCache ->
  FilePath ->
  ModuleName.Raw ->
  FilePath ->
  [ModuleName.Raw] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  IO (Maybe ModuleResult)
tryCacheHit cacheRef root modName path modImports ifaces = do
  cache <- readIORef cacheRef
  sourceHash <- Hash.hashFile path
  let depsHash = computeDepsHash modImports ifaces
  if Incremental.needsRecompile cache modName sourceHash depsHash
    then return Nothing
    else loadCachedArtifact root modName

-- | Load cached module artifact from disk.
loadCachedArtifact :: FilePath -> ModuleName.Raw -> IO (Maybe ModuleResult)
loadCachedArtifact root modName = do
  let artifactFile = cacheArtifactPath root modName
  exists <- Dir.doesFileExist artifactFile
  if not exists
    then return Nothing
    else do
      result <- Exception.try (decodeCachedModule artifactFile)
      handleDecodeResult modName result

-- | Decode a cached module from a binary file.
--
-- Decodes the full triple of (Interface, LocalGraph, FFIInfo) that was
-- saved by 'saveToCacheAsync'. Checks the magic header and schema
-- version before decoding. Falls back to unversioned legacy formats
-- when the magic header is absent.
decodeCachedModule :: FilePath -> IO (Interface.Interface, Opt.LocalGraph, Map.Map String JS.FFIInfo)
decodeCachedModule artifactFile = do
  bytes <- LBS.readFile artifactFile
  case decodeVersioned bytes of
    Right triple -> return triple
    Left _msg -> decodeLegacyBytes bytes

-- | Attempt legacy (unversioned) decoding from already-read bytes.
--
-- Tries triple format first, falls back to pair format (pre-FFI).
-- Avoids re-reading the file by operating on the in-memory bytes.
decodeLegacyBytes :: LBS.ByteString -> IO (Interface.Interface, Opt.LocalGraph, Map.Map String JS.FFIInfo)
decodeLegacyBytes bytes =
  case Binary.decodeOrFail bytes of
    Right (_, _, triple) -> return triple
    Left _ ->
      case Binary.decodeOrFail bytes of
        Right (_, _, (iface, localGraph)) -> return (iface, localGraph, Map.empty)
        Left (_, _, msg) -> fail ("decode error: " ++ msg)

-- | Handle the result of attempting to decode a cached module.
handleDecodeResult ::
  ModuleName.Raw ->
  Either IOException (Interface.Interface, Opt.LocalGraph, Map.Map String JS.FFIInfo) ->
  IO (Maybe ModuleResult)
handleDecodeResult modName result =
  case result of
    Right (iface, localGraph, ffiInfo) ->
      return (Just (ModuleResult modName iface localGraph ffiInfo Set.empty))
    Left _ex -> do
      Log.logEvent (CacheMiss PhaseCache (Text.pack ("decode failed: " ++ Name.toChars modName)))
      return Nothing

-- | Save module artifacts to cache (asynchronous, best-effort).
saveToCacheAsync ::
  IORef Incremental.BuildCache ->
  FilePath ->
  ModuleName.Raw ->
  FilePath ->
  [ModuleName.Raw] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  ModuleResult ->
  IO ()
saveToCacheAsync cacheRef root modName path modImports ifaces mr = do
  sourceHash <- Hash.hashFile path
  let depsHash = computeDepsHash modImports ifaces
      artifactFile = cacheArtifactPath root modName

  -- Ensure cache directory exists
  Dir.createDirectoryIfMissing True (root </> "canopy-stuff" </> "cache")

  -- Write versioned binary artifact (magic + version + Interface + LocalGraph + FFIInfo)
  LBS.writeFile artifactFile (encodeVersioned (mrInterface mr, mrLocalGraph mr, mrFFIInfo mr))

  -- Update cache index
  now <- Time.getCurrentTime
  let entry = Incremental.CacheEntry
        { Incremental.cacheSourceHash = sourceHash
        , Incremental.cacheDepsHash = depsHash
        , Incremental.cacheArtifactPath = artifactFile
        , Incremental.cacheTimestamp = now
        }
  atomicModifyIORef' cacheRef (\c -> (Incremental.insertCache c modName entry, ()))

-- | Compute a combined hash of a module's actual dependency interfaces.
--
-- Only hashes the interfaces of modules this module actually imports,
-- not the entire interface map. This ensures cache invalidation occurs
-- only when a direct dependency changes, preventing excessive recompilation.
computeDepsHash :: [ModuleName.Raw] -> Map.Map ModuleName.Raw Interface.Interface -> Hash.ContentHash
computeDepsHash modImports ifaces =
  Hash.hashDependencies ifaceHashes
  where
    relevantIfaces = Map.restrictKeys ifaces (Set.fromList modImports)
    ifaceHashes = Map.map hashInterface relevantIfaces
    hashInterface iface = Hash.hashBytes (LBS.toStrict (Binary.encode iface))

-- VERSIONED BINARY CACHE
--
-- .elco files use a magic header and schema version to detect format
-- mismatches early, preventing silent decode failures when the Binary
-- instances change across compiler versions.

-- | Magic bytes identifying a versioned .elco file: "ELCO" in ASCII.
elcoMagic :: LBS.ByteString
elcoMagic = LBS.pack [0x45, 0x4C, 0x43, 0x4F]

-- | Current schema version. Bump this when any Binary instance used in
-- .elco files changes (Interface, LocalGraph, FFIInfo, or their transitive
-- dependencies).
elcoSchemaVersion :: Word16
elcoSchemaVersion = 1

-- | Encode a value with the versioned .elco header.
encodeVersioned :: (Binary.Binary a) => a -> LBS.ByteString
encodeVersioned payload =
  elcoMagic <> Binary.encode elcoSchemaVersion <> Binary.encode payload

-- | Decode a versioned .elco file. Returns Left on magic/version mismatch.
decodeVersioned ::
  (Binary.Binary a) => LBS.ByteString -> Either String a
decodeVersioned bytes
  | LBS.length bytes < 6 = Left "file too short for versioned format"
  | LBS.take 4 bytes /= elcoMagic = Left "missing ELCO magic header"
  | otherwise =
      case Binary.decodeOrFail (LBS.drop 4 bytes) of
        Left (_, _, msg) -> Left ("version decode: " ++ msg)
        Right (rest, _, ver)
          | ver /= elcoSchemaVersion ->
              Left ("schema version mismatch: expected " ++ show elcoSchemaVersion ++ ", got " ++ show (ver :: Word16))
          | otherwise ->
              case Binary.decodeOrFail rest of
                Left (_, _, msg) -> Left ("payload decode: " ++ msg)
                Right (_, _, payload) -> Right payload

-- | Log incremental compilation statistics.
logIncrementalStats :: IORef Int -> IORef Int -> IO ()
logIncrementalStats hitRef missRef = do
  hits <- readIORef hitRef
  misses <- readIORef missRef
  Log.logEvent (BuildIncremental hits misses)

-- Helper: Merge dependency GlobalGraph with compiled LocalGraphs
mergeGraphs :: Opt.GlobalGraph -> [Opt.LocalGraph] -> Opt.GlobalGraph
mergeGraphs depGlobalGraph localGraphs =
  foldr Opt.addLocalGraph depGlobalGraph localGraphs

-- Helper: Extract module name from canonical module
extractModuleName :: Can.Module -> ModuleName.Raw
extractModuleName canModule = ModuleName._module (Can._name canModule)

-- Helper: Detect root modules
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

-- Helper: Discover module file paths from module names
discoverModulePaths :: FilePath -> [SrcDir] -> [ModuleName.Raw] -> IO [FilePath]
discoverModulePaths root srcDirs moduleNames = do
  concat <$> mapM (findModuleInDirs root srcDirs) moduleNames

findModuleInDirs :: FilePath -> [SrcDir] -> ModuleName.Raw -> IO [FilePath]
findModuleInDirs root srcDirs moduleName = do
  let basePath = moduleNameToBasePath moduleName
      candidates = concatMap (buildCandidates root basePath) srcDirs
  existing <- filterM Dir.doesFileExist candidates
  return existing
  where
    buildCandidates :: FilePath -> FilePath -> SrcDir -> [FilePath]
    buildCandidates projectRoot base srcDir =
      let dirPath = normalise (projectRoot </> srcDirToString srcDir)
       in [ dirPath </> base ++ ".can"
          , dirPath </> base ++ ".elm"
          ]

moduleNameToBasePath :: ModuleName.Raw -> FilePath
moduleNameToBasePath moduleName =
  let nameStr = Name.toChars moduleName
      parts = splitOn '.' nameStr
   in foldr1 (</>) parts

srcDirToString :: SrcDir -> String
srcDirToString srcDir = case srcDir of
  AbsoluteSrcDir path -> path
  RelativeSrcDir path -> path

splitOn :: Char -> String -> [String]
splitOn _ "" = []
splitOn c s =
  let (chunk, rest) = break (== c) s
   in chunk : case rest of
        [] -> []
        (_:rest') -> splitOn c rest'
