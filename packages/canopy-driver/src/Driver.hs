{-# LANGUAGE StrictData #-}

-- | Query-based compiler driver.
--
-- This module orchestrates the complete compilation pipeline using the
-- query system. It replaces the traditional Build.fromPaths approach
-- with a query-based architecture that provides:
--
-- * Automatic caching and invalidation
-- * Comprehensive debug logging
-- * Better error reporting
-- * Foundation for incremental compilation
-- * Parallel compilation support
--
-- @since 0.19.1
module Driver
  ( -- * Driver Types
    CompileResult (..),

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
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import FFI.Types (JsSourcePath (..), JsSource (..))
import qualified Foreign.FFI as FFI
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Data.Text as Text
import qualified Generate.JavaScript as JS
import Logging.Event (LogEvent (..), CompileStats (..), Duration (..))
import qualified Logging.Logger as Log
import qualified Queries.Canonicalize.Module as CanonQuery
import qualified Queries.Optimize as OptQuery
import qualified Queries.Parse.Module as ParseQuery
import qualified Queries.Type.Check as TypeQuery
import qualified Query.Engine as Engine
import Query.Simple
import qualified System.Timeout as Timeout
import qualified Worker.Pool as Pool
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as Ann

-- | Compilation result with all artifacts.
data CompileResult = CompileResult
  { compileResultModule :: !Can.Module,
    compileResultTypes :: !(Map Name.Name Can.Annotation),
    compileResultInterface :: !Interface.Interface,
    compileResultLocalGraph :: !Opt.LocalGraph,
    compileResultFFIInfo :: !(Map String JS.FFIInfo)
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
  result <- compileModuleFull engine pkg ifaces path projectType

  logCacheStats engine

  return result

-- | Compile a module with a shared query engine for caching across modules.
-- This variant allows cache reuse across multiple module compilations.
compileModuleWithEngine ::
  Engine.QueryEngine ->
  Pkg.Name ->
  Map ModuleName.Raw Interface.Interface ->
  FilePath ->
  Parse.ProjectType ->
  IO (Either QueryError CompileResult)
compileModuleWithEngine engine pkg ifaces path projectType = do
  Log.logEvent (CompileStarted path)

  compileModuleFull engine pkg ifaces path projectType

-- | Compile from already-parsed source module.
--
-- This variant accepts an already-parsed Src.Module instead of a file path.
-- Used when integrating with existing build systems that parse separately.
compileFromSource ::
  Pkg.Name ->
  Map ModuleName.Raw Interface.Interface ->
  Src.Module ->
  IO (Either QueryError CompileResult)
compileFromSource pkg ifaces sourceModule = do
  Log.logEvent (CompileStarted "<source>")

  engine <- Engine.initEngine
  ffiContent <- loadFFIContent sourceModule
  let foreignImports = Src._foreignImports sourceModule
      ffiInfoMap = buildFFIInfoMap foreignImports ffiContent
  canonResult <- runCanonicalizePhase engine "<source>" pkg Parse.Application ifaces ffiContent sourceModule
  case canonResult of
    Left err -> return (Left err)
    Right canonModule -> do
      typeResult <- runTypeCheckPhase engine "<unknown>" canonModule
      case typeResult of
        Left err -> return (Left err)
        Right types -> do
          optimizeResult <- runOptimizePhase engine types canonModule
          case optimizeResult of
            Left err -> return (Left err)
            Right localGraph -> do
              iface <- generateInterface pkg canonModule types
              Log.logEvent (CompileCompleted "<source>" (CompileStats 1 (Duration 0)))
              return
                ( Right
                    ( CompileResult
                        { compileResultModule = canonModule,
                          compileResultTypes = types,
                          compileResultInterface = iface,
                          compileResultLocalGraph = localGraph,
                          compileResultFFIInfo = ffiInfoMap
                        }
                    )
                )

-- | Per-module compilation timeout in microseconds (5 minutes).
--
-- Prevents pathological inputs from hanging the compiler indefinitely.
-- This is a conservative limit — even very large modules should compile
-- well within this window.
--
-- @since 0.19.2
moduleTimeoutMicroseconds :: Int
moduleTimeoutMicroseconds = 300000000

-- | Compile a module with existing engine (for batch compilation).
--
-- Wraps the compilation pipeline with a timeout to prevent pathological
-- inputs from hanging the compiler. Returns 'TimeoutError' if the
-- module exceeds the per-module time limit.
compileModuleFull ::
  Engine.QueryEngine ->
  Pkg.Name ->
  Map ModuleName.Raw Interface.Interface ->
  FilePath ->
  Parse.ProjectType ->
  IO (Either QueryError CompileResult)
compileModuleFull engine pkg ifaces path projectType = do
  result <- Timeout.timeout moduleTimeoutMicroseconds (compileModuleCore engine pkg ifaces path projectType)
  case result of
    Just compilation -> return compilation
    Nothing -> return (Left (TimeoutError path))

-- | Core module compilation pipeline without timeout wrapper.
compileModuleCore ::
  Engine.QueryEngine ->
  Pkg.Name ->
  Map ModuleName.Raw Interface.Interface ->
  FilePath ->
  Parse.ProjectType ->
  IO (Either QueryError CompileResult)
compileModuleCore engine pkg ifaces path projectType = do
  Log.logEvent (CompileStarted path)

  parseResult <- runParsePhase engine path projectType
  case parseResult of
    Left err -> return (Left err)
    Right sourceModule -> do
      ffiContent <- loadFFIContent sourceModule
      let foreignImports = Src._foreignImports sourceModule
          ffiInfoMap = buildFFIInfoMap foreignImports ffiContent
      canonResult <- runCanonicalizePhase engine path pkg projectType ifaces ffiContent sourceModule
      case canonResult of
        Left err -> return (Left err)
        Right canonModule -> do
          typeResult <- runTypeCheckPhase engine path canonModule
          case typeResult of
            Left err -> return (Left err)
            Right types -> do
              optimizeResult <- runOptimizePhase engine types canonModule
              case optimizeResult of
                Left err -> return (Left err)
                Right localGraph -> do
                  iface <- generateInterface pkg canonModule types
                  Log.logEvent (CompileCompleted path (CompileStats 1 (Duration 0)))
                  return
                    ( Right
                        ( CompileResult
                            { compileResultModule = canonModule,
                              compileResultTypes = types,
                              compileResultInterface = iface,
                              compileResultLocalGraph = localGraph,
                              compileResultFFIInfo = ffiInfoMap
                            }
                        )
                    )

-- | Run parse phase.
--
-- Tracks the phase execution through the query engine for accurate
-- compilation statistics, then delegates to the parse module query.
runParsePhase ::
  Engine.QueryEngine ->
  FilePath ->
  Parse.ProjectType ->
  IO (Either QueryError Src.Module)
runParsePhase engine path projectType = do
  Engine.trackPhaseExecution engine "parse"
  ParseQuery.parseModuleQuery projectType path

-- | Load FFI content for module.
loadFFIContent :: Src.Module -> IO (Map JsSourcePath JsSource)
loadFFIContent sourceModule = do
  let foreignImports = Src._foreignImports sourceModule
  Log.logEvent (FFILoading "ffi-content")
  Canonicalize.loadFFIContent foreignImports

-- | Build FFIInfo map from foreign imports and content.
buildFFIInfoMap :: [Src.ForeignImport] -> Map JsSourcePath JsSource -> Map String JS.FFIInfo
buildFFIInfoMap foreignImports contentMap =
  Map.fromList (buildFFIInfoList foreignImports contentMap)

-- | Build list of FFIInfo from imports and content.
buildFFIInfoList :: [Src.ForeignImport] -> Map JsSourcePath JsSource -> [(String, JS.FFIInfo)]
buildFFIInfoList foreignImports contentMap =
  concatMap (buildSingleFFI contentMap) foreignImports

-- | Build FFI info for a single foreign import.
--
-- Returns empty list when the JavaScript file is not in the content map,
-- which indicates a missing FFI file that will be caught during
-- canonicalization with a proper error message.
buildSingleFFI :: Map JsSourcePath JsSource -> Src.ForeignImport -> [(String, JS.FFIInfo)]
buildSingleFFI contentMap (Src.ForeignImport (FFI.JavaScriptFFI jsPath) alias _region) =
  case Map.lookup (JsSourcePath (Text.pack jsPath)) contentMap of
    Just (JsSource content) ->
      [(jsPath, JS.FFIInfo jsPath content (Ann.toValue alias))]
    Nothing -> []
buildSingleFFI _ _ = []

-- | Run canonicalize phase.
--
-- Tracks the phase execution through the query engine for accurate
-- compilation statistics, then delegates to the canonicalization query.
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
  CanonQuery.canonicalizeModuleQuery path pkg projectType ifaces ffiContent sourceModule

-- | Run type check phase.
--
-- Tracks the phase execution through the query engine for accurate
-- compilation statistics, then delegates to the type checking query.
runTypeCheckPhase ::
  Engine.QueryEngine ->
  FilePath ->
  Can.Module ->
  IO (Either QueryError (Map Name.Name Can.Annotation))
runTypeCheckPhase engine path canonModule = do
  Engine.trackPhaseExecution engine "typecheck"
  TypeQuery.typeCheckModuleQuery path canonModule

-- | Run optimize phase.
--
-- Tracks the phase execution through the query engine for accurate
-- compilation statistics, then delegates to the optimization query.
runOptimizePhase ::
  Engine.QueryEngine ->
  Map Name.Name Can.Annotation ->
  Can.Module ->
  IO (Either QueryError Opt.LocalGraph)
runOptimizePhase engine types canonModule = do
  Engine.trackPhaseExecution engine "optimize"
  OptQuery.optimizeModuleQuery types canonModule

-- | Generate interface from canonical module.
generateInterface ::
  Pkg.Name ->
  Can.Module ->
  Map Name.Name Can.Annotation ->
  IO Interface.Interface
generateInterface pkg canonModule@(Can.Module modName _ _ _ _ _ _ _ _) types = do
  Log.logEvent (InterfaceSaved (show modName))
  let iface = Interface.fromModule pkg canonModule types
  return iface

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
    (Pool.taskFilePath task)
    (Pool.taskProjectType task)

-- | Log cache statistics.
logCacheStats :: Engine.QueryEngine -> IO ()
logCacheStats engine = do
  cacheSize <- Engine.getCacheSize engine
  hits <- Engine.getCacheHits engine
  misses <- Engine.getCacheMisses engine

  Log.logEvent (CacheStored "stats" cacheSize)
  Log.logEvent (BuildIncremental hits misses)
