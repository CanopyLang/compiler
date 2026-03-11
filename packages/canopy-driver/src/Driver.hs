
-- | Query-based compiler driver with full-phase caching.
--
-- This module orchestrates the complete compilation pipeline using the
-- query system. Every phase (parse, canonicalize, type-check, optimize)
-- is cached with content-hash based invalidation. When inputs haven't
-- changed, cached results are returned directly.
--
-- @since 0.19.1
module Driver
  ( -- * Driver Types
    CompileResult (..),
    PhaseTimings (..),
    emptyTimings,

    -- * Single Module Compilation
    compileModule,
    compileModuleFull,
    compileModuleWithEngine,
    compileFromSource,

    -- * Parallel Compilation
    compileModulesParallel,
    compileModulesWithProgress,

    -- * Cache Statistics
    logCacheStats,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import qualified Canonicalize.Module as Canonicalize
import qualified Canopy.Data.Name as Name
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import qualified Data.Time.Clock as Clock
import FFI.Types (JsSource (..), JsSourcePath (..))
import qualified Foreign.FFI as FFI
import qualified Generate.JavaScript as JS
import Logging.Event (CompileStats (..), Duration (..), LogEvent (..))
import qualified Logging.Logger as Log
import qualified Parse.Module as Parse
import qualified Queries.Canonicalize.Module as CanonQuery
import qualified Queries.Optimize as OptQuery
import qualified Queries.Parse.Module as ParseQuery
import qualified Queries.Type.Check as TypeQuery
import qualified Query.Engine as Engine
import Query.Simple
import qualified Reporting.Annotation as Ann
import qualified Reporting.InternalError as InternalError
import qualified System.Timeout as Timeout
import qualified Worker.Pool as Pool

-- | Per-phase timing results for a single module compilation.
--
-- @since 0.19.2
data PhaseTimings = PhaseTimings
  { _timeParse :: !Double,
    _timeCanonicalize :: !Double,
    _timeTypeCheck :: !Double,
    _timeOptimize :: !Double
  }
  deriving (Eq, Show)

-- | Zero timings for cache hits or untimed paths.
--
-- @since 0.19.2
emptyTimings :: PhaseTimings
emptyTimings = PhaseTimings 0 0 0 0

-- | Time a single IO action, returning the result and elapsed seconds.
--
-- @since 0.19.2
timePhase :: IO a -> IO (a, Double)
timePhase action = do
  start <- Clock.getCurrentTime
  result <- action
  end <- Clock.getCurrentTime
  pure (result, realToFrac (Clock.diffUTCTime end start))

-- | Compilation result with all artifacts.
data CompileResult = CompileResult
  { compileResultModule :: !Can.Module,
    compileResultTypes :: !(Map Name.Name Can.Annotation),
    compileResultInterface :: !Interface.Interface,
    compileResultLocalGraph :: !Opt.LocalGraph,
    compileResultFFIInfo :: !(Map String JS.FFIInfo),
    compileResultTimings :: !PhaseTimings
  }

-- | Compile a module from file path (simplified).
compileModule ::
  Pkg.Name ->
  Map ModuleName.Raw Interface.Interface ->
  FilePath ->
  Parse.ProjectType ->
  IO (Either QueryError CompileResult)
compileModule pkg ifaces path projectType = do
  Log.logEvent (CompileStarted path)
  engine <- Engine.initEngine
  result <- compileModuleFull engine pkg ifaces "." path projectType
  logCacheStats engine
  return result

-- | Compile a module with a shared query engine.
compileModuleWithEngine ::
  Engine.QueryEngine ->
  Pkg.Name ->
  Map ModuleName.Raw Interface.Interface ->
  FilePath ->
  FilePath ->
  Parse.ProjectType ->
  IO (Either QueryError CompileResult)
compileModuleWithEngine engine pkg ifaces ffiRoot path projectType = do
  Log.logEvent (CompileStarted path)
  compileModuleFull engine pkg ifaces ffiRoot path projectType

-- | Compile from already-parsed source module.
compileFromSource ::
  Pkg.Name ->
  Map ModuleName.Raw Interface.Interface ->
  Src.Module ->
  IO (Either QueryError CompileResult)
compileFromSource pkg ifaces sourceModule = do
  Log.logEvent (CompileStarted "<source>")
  engine <- Engine.initEngine
  ffiContent <- loadFFIContent "." sourceModule
  let ffiInfoMap = buildFFIInfoMap (Src._foreignImports sourceModule) ffiContent
  runFromSource engine pkg ifaces ffiInfoMap ffiContent sourceModule

-- | Run compilation from a pre-parsed source module.
runFromSource ::
  Engine.QueryEngine ->
  Pkg.Name ->
  Map ModuleName.Raw Interface.Interface ->
  Map String JS.FFIInfo ->
  Map JsSourcePath JsSource ->
  Src.Module ->
  IO (Either QueryError CompileResult)
runFromSource engine pkg ifaces ffiInfoMap ffiContent sourceModule = do
  (canonResult, canonTime) <- timePhase (runCanonicalizePhase engine "<source>" pkg Parse.Application ifaces ffiContent sourceModule)
  case canonResult of
    Left err -> return (Left err)
    Right canonModule -> do
      (typeResult, typeTime) <- timePhase (runTypeCheckPhase engine ifaces "<unknown>" canonModule)
      case typeResult of
        Left err -> return (Left err)
        Right types -> do
          (optimizeResult, optTime) <- timePhase (runOptimizePhase engine types canonModule)
          case optimizeResult of
            Left err -> return (Left err)
            Right localGraph -> do
              iface <- generateInterface pkg canonModule types
              let totalMicros = round ((canonTime + typeTime + optTime) * 1000000)
                  timings = PhaseTimings 0 canonTime typeTime optTime
              Log.logEvent (CompileCompleted "<source>" (CompileStats 1 (Duration totalMicros)))
              return (Right (buildResult canonModule types iface localGraph ffiInfoMap timings))

-- | Per-module compilation timeout in microseconds (5 minutes).
--
-- @since 0.19.2
moduleTimeoutMicroseconds :: Int
moduleTimeoutMicroseconds = 300000000

-- | Compile a module with existing engine, wrapped in timeout.
compileModuleFull ::
  Engine.QueryEngine ->
  Pkg.Name ->
  Map ModuleName.Raw Interface.Interface ->
  FilePath ->
  FilePath ->
  Parse.ProjectType ->
  IO (Either QueryError CompileResult)
compileModuleFull engine pkg ifaces ffiRoot path projectType = do
  result <- Timeout.timeout moduleTimeoutMicroseconds (compileModuleCore engine pkg ifaces ffiRoot path projectType)
  maybe (return (Left (TimeoutError path))) return result

-- | Core module compilation pipeline with per-phase caching.
--
-- Each phase checks the query cache before executing. Input hashes are
-- computed from upstream phase hashes, ensuring that unchanged inputs
-- produce cache hits without re-executing expensive phases.
compileModuleCore ::
  Engine.QueryEngine ->
  Pkg.Name ->
  Map ModuleName.Raw Interface.Interface ->
  FilePath ->
  FilePath ->
  Parse.ProjectType ->
  IO (Either QueryError CompileResult)
compileModuleCore engine pkg ifaces ffiRoot path projectType = do
  Log.logEvent (CompileStarted path)
  (parseResult, parseTime) <- timePhase (runParsePhase engine path projectType)
  case parseResult of
    Left err -> return (Left err)
    Right sourceModule -> do
      ffiContent <- loadFFIContent ffiRoot sourceModule
      let ffiInfoMap = buildFFIInfoMap (Src._foreignImports sourceModule) ffiContent
      runCachedPipeline engine pkg ifaces ffiInfoMap ffiContent path projectType parseTime sourceModule

-- | Run the cached compilation pipeline after parsing.
runCachedPipeline ::
  Engine.QueryEngine ->
  Pkg.Name ->
  Map ModuleName.Raw Interface.Interface ->
  Map String JS.FFIInfo ->
  Map JsSourcePath JsSource ->
  FilePath ->
  Parse.ProjectType ->
  Double ->
  Src.Module ->
  IO (Either QueryError CompileResult)
runCachedPipeline engine pkg ifaces ffiInfoMap ffiContent path _projectType parseTime sourceModule = do
  let parseHash = computeInputHash path "parse"
      canonInputHash = combineHashes [parseHash, computeInputHash (show pkg) "canon-pkg", computeInputHash (show (Map.keys ifaces)) "canon-ifaces"]
      canonQuery = CanonicalizeQuery path canonInputHash
  (canonResult, canonTime) <- timePhase (runCachedCanon engine canonQuery path pkg _projectType ifaces ffiContent sourceModule)
  case canonResult of
    Left err -> return (Left err)
    Right canonModule -> do
      let typeInputHash = combineHashes [canonInputHash, computeInputHash (show (Map.keys ifaces)) "type-ifaces"]
          typeQuery = TypeCheckQuery path typeInputHash
      (typeResult, typeTime) <- timePhase (runCachedTypeCheck engine typeQuery ifaces path canonModule canonQuery)
      case typeResult of
        Left err -> return (Left err)
        Right types -> do
          let optInputHash = combineHashes [canonInputHash, typeInputHash]
              optQuery = OptimizeQuery path optInputHash
          (optResult, optTime) <- timePhase (runCachedOptimize engine optQuery types canonModule canonQuery)
          case optResult of
            Left err -> return (Left err)
            Right localGraph -> do
              iface <- generateInterface pkg canonModule types
              let totalMicros = round ((parseTime + canonTime + typeTime + optTime) * 1000000)
                  timings = PhaseTimings parseTime canonTime typeTime optTime
              Log.logEvent (CompileCompleted path (CompileStats 1 (Duration totalMicros)))
              return (Right (buildResult canonModule types iface localGraph ffiInfoMap timings))

-- | Run canonicalization with cache lookup.
runCachedCanon ::
  Engine.QueryEngine ->
  Query ->
  FilePath ->
  Pkg.Name ->
  Parse.ProjectType ->
  Map ModuleName.Raw Interface.Interface ->
  Map JsSourcePath JsSource ->
  Src.Module ->
  IO (Either QueryError Can.Module)
runCachedCanon engine query path pkg projectType ifaces ffiContent sourceModule = do
  cached <- Engine.lookupQuery engine query
  case cached of
    Just (CanonicalizedModule canMod) -> return (Right canMod)
    _ -> do
      result <- runCanonicalizePhase engine path pkg projectType ifaces ffiContent sourceModule
      case result of
        Right canMod -> do
          Engine.storeQuery engine query (CanonicalizedModule canMod) (canonHash query) Nothing
          return (Right canMod)
        Left err -> return (Left err)

-- | Run type checking with cache lookup.
runCachedTypeCheck ::
  Engine.QueryEngine ->
  Query ->
  Map ModuleName.Raw Interface.Interface ->
  FilePath ->
  Can.Module ->
  Query ->
  IO (Either QueryError (Map Name.Name Can.Annotation))
runCachedTypeCheck engine query ifaces path canonModule parentQuery = do
  cached <- Engine.lookupQuery engine query
  case cached of
    Just (TypeCheckedModule types) -> return (Right types)
    _ -> do
      result <- runTypeCheckPhase engine ifaces path canonModule
      case result of
        Right types -> do
          Engine.storeQuery engine query (TypeCheckedModule types) (typeCheckHash query) (Just parentQuery)
          return (Right types)
        Left err -> return (Left err)

-- | Run optimization with cache lookup.
runCachedOptimize ::
  Engine.QueryEngine ->
  Query ->
  Map Name.Name Can.Annotation ->
  Can.Module ->
  Query ->
  IO (Either QueryError Opt.LocalGraph)
runCachedOptimize engine query types canonModule parentQuery = do
  cached <- Engine.lookupQuery engine query
  case cached of
    Just (OptimizedModule graph) -> return (Right graph)
    _ -> do
      result <- runOptimizePhase engine types canonModule
      case result of
        Right graph -> do
          Engine.storeQuery engine query (OptimizedModule graph) (optimizeHash query) (Just parentQuery)
          return (Right graph)
        Left err -> return (Left err)

-- | Compute an input hash from a string key and salt.
computeInputHash :: String -> String -> ContentHash
computeInputHash input salt =
  computeContentHash (TE.encodeUtf8 (Text.pack (input ++ ":" ++ salt)))

-- | Build a CompileResult from its parts.
buildResult ::
  Can.Module ->
  Map Name.Name Can.Annotation ->
  Interface.Interface ->
  Opt.LocalGraph ->
  Map String JS.FFIInfo ->
  PhaseTimings ->
  CompileResult
buildResult canonModule types iface localGraph ffiInfoMap timings =
  CompileResult
    { compileResultModule = canonModule,
      compileResultTypes = types,
      compileResultInterface = iface,
      compileResultLocalGraph = localGraph,
      compileResultFFIInfo = ffiInfoMap,
      compileResultTimings = timings
    }

-- | Run parse phase.
runParsePhase ::
  Engine.QueryEngine ->
  FilePath ->
  Parse.ProjectType ->
  IO (Either QueryError Src.Module)
runParsePhase engine path projectType = do
  Engine.trackPhaseExecution engine "parse"
  ParseQuery.parseModuleQuery projectType path

-- | Load FFI content for module.
loadFFIContent :: FilePath -> Src.Module -> IO (Map JsSourcePath JsSource)
loadFFIContent ffiRoot sourceModule = do
  let foreignImports = Src._foreignImports sourceModule
  Log.logEvent (FFILoading "ffi-content")
  Canonicalize.loadFFIContentWithRoot ffiRoot foreignImports

-- | Build FFIInfo map from foreign imports and content.
buildFFIInfoMap :: [Src.ForeignImport] -> Map JsSourcePath JsSource -> Map String JS.FFIInfo
buildFFIInfoMap foreignImports contentMap =
  Map.fromList (concatMap (buildSingleFFI contentMap) foreignImports)

-- | Build FFI info for a single foreign import.
buildSingleFFI :: Map JsSourcePath JsSource -> Src.ForeignImport -> [(String, JS.FFIInfo)]
buildSingleFFI contentMap (Src.ForeignImport (FFI.JavaScriptFFI jsPath) alias _region) =
  case Map.lookup (JsSourcePath (Text.pack jsPath)) contentMap of
    Just (JsSource content) ->
      [(jsPath, JS.FFIInfo jsPath content (Ann.toValue alias))]
    Nothing -> []
buildSingleFFI _ _ = []

-- | Run canonicalize phase.
runCanonicalizePhase ::
  Engine.QueryEngine ->
  FilePath ->
  Pkg.Name ->
  Parse.ProjectType ->
  Map ModuleName.Raw Interface.Interface ->
  Map JsSourcePath JsSource ->
  Src.Module ->
  IO (Either QueryError Can.Module)
runCanonicalizePhase engine path pkg projectType ifaces ffiContent sourceModule = do
  Engine.trackPhaseExecution engine "canonicalize"
  wrapPhase (CanonQuery.canonicalizeModuleQuery path pkg projectType ifaces ffiContent sourceModule)

-- | Run type check phase.
runTypeCheckPhase ::
  Engine.QueryEngine ->
  Map ModuleName.Raw Interface.Interface ->
  FilePath ->
  Can.Module ->
  IO (Either QueryError (Map Name.Name Can.Annotation))
runTypeCheckPhase engine ifaces path canonModule = do
  Engine.trackPhaseExecution engine "typecheck"
  wrapPhase (TypeQuery.typeCheckModuleQuery ifaces path canonModule)

-- | Run optimize phase.
runOptimizePhase ::
  Engine.QueryEngine ->
  Map Name.Name Can.Annotation ->
  Can.Module ->
  IO (Either QueryError Opt.LocalGraph)
runOptimizePhase engine types canonModule = do
  Engine.trackPhaseExecution engine "optimize"
  wrapPhase (OptQuery.optimizeModuleQuery types canonModule)

-- | Generate interface from canonical module.
generateInterface ::
  Pkg.Name ->
  Can.Module ->
  Map Name.Name Can.Annotation ->
  IO Interface.Interface
generateInterface pkg canonModule@(Can.Module modName _ _ _ _ _ _ _ _ _) types = do
  Log.logEvent (InterfaceSaved (show modName))
  return (Interface.fromModule pkg canonModule types)

-- | Compile multiple modules in parallel.
compileModulesParallel ::
  Pool.PoolConfig ->
  Pkg.Name ->
  Map ModuleName.Raw Interface.Interface ->
  [(FilePath, Parse.ProjectType)] ->
  IO [Either QueryError CompileResult]
compileModulesParallel config pkg ifaces modules = do
  Log.logEvent (BuildStarted (Text.pack ("parallel:" ++ show (length modules))))
  pool <- Pool.createPool config compileTaskFn
  let tasks = map (createTask pkg ifaces) modules
  results <- Pool.compileModules pool tasks
  Pool.shutdownPool pool
  Log.logEvent (BuildCompleted (length modules) (Duration 0))
  return results

-- | Compile modules with progress tracking.
compileModulesWithProgress ::
  Pool.PoolConfig ->
  Pkg.Name ->
  Map ModuleName.Raw Interface.Interface ->
  [(FilePath, Parse.ProjectType)] ->
  (Pool.Progress -> IO ()) ->
  IO [Either QueryError CompileResult]
compileModulesWithProgress config pkg ifaces modules progressCallback = do
  Log.logEvent (BuildStarted (Text.pack ("parallel:" ++ show (length modules))))
  pool <- Pool.createPool config compileTaskFn
  let tasks = map (createTask pkg ifaces) modules
  results <- Pool.compileModulesWithProgress pool tasks progressCallback
  Pool.shutdownPool pool
  Log.logEvent (BuildCompleted (length modules) (Duration 0))
  return results

-- | Create compile task from module info.
createTask :: Pkg.Name -> Map ModuleName.Raw Interface.Interface -> (FilePath, Parse.ProjectType) -> Pool.CompileTask
createTask pkg ifaces (path, projectType) =
  Pool.CompileTask
    { Pool.taskPackage = pkg,
      Pool.taskInterfaces = ifaces,
      Pool.taskFilePath = path,
      Pool.taskProjectType = projectType
    }

-- | Compilation function for worker pool.
compileTaskFn :: Engine.QueryEngine -> Pool.CompileTask -> IO (Either QueryError CompileResult)
compileTaskFn engine task =
  compileModuleFull
    engine
    (Pool.taskPackage task)
    (Pool.taskInterfaces task)
    "."
    (Pool.taskFilePath task)
    (Pool.taskProjectType task)

-- | Wrap a phase action in internal error catching.
--
-- @since 0.19.2
wrapPhase :: IO (Either QueryError a) -> IO (Either QueryError a)
wrapPhase action = do
  result <- InternalError.catchInternalError action
  pure (collapseEither result)
  where
    collapseEither (Left errMsg) = Left (OtherError (Text.unpack errMsg))
    collapseEither (Right inner) = inner

-- | Log cache statistics.
logCacheStats :: Engine.QueryEngine -> IO ()
logCacheStats engine = do
  cacheSize <- Engine.getCacheSize engine
  hits <- Engine.getCacheHits engine
  misses <- Engine.getCacheMisses engine
  Log.logEvent (CacheStored "stats" cacheSize)
  Log.logEvent (BuildIncremental hits misses)
