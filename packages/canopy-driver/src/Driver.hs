{-# OPTIONS_GHC -Wall #-}

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
    FFIInfo (..),

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
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Foreign.FFI as FFI
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Name as Name
import qualified Debug.Logger as Logger
import Debug.Logger (DebugCategory (..))
import qualified Queries.Canonicalize.Module as CanonQuery
import qualified Queries.Optimize as OptQuery
import qualified Queries.Parse.Module as ParseQuery
import qualified Queries.Type.Check as TypeQuery
import qualified Query.Engine as Engine
import Query.Simple
import qualified Worker.Pool as Pool
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as A

-- | Compilation result with all artifacts.
data CompileResult = CompileResult
  { compileResultModule :: !Can.Module,
    compileResultTypes :: !(Map Name.Name Can.Annotation),
    compileResultInterface :: !I.Interface,
    compileResultLocalGraph :: !Opt.LocalGraph,
    compileResultFFIInfo :: !(Map String FFIInfo)
  }

-- | FFI information for JavaScript generation
data FFIInfo = FFIInfo
  { ffiFilePath :: !String,
    ffiContent :: !String,
    ffiAlias :: !String
  }
  deriving (Eq, Show)

-- | Compile a module from file path (simplified).
compileModule ::
  Pkg.Name ->
  Map ModuleName.Raw I.Interface ->
  FilePath ->
  Parse.ProjectType ->
  IO (Either QueryError CompileResult)
compileModule pkg ifaces path projectType = do
  Logger.debug COMPILE_DEBUG ("Compiling module: " ++ path)
  Logger.debug COMPILE_DEBUG ("Package: " ++ show pkg)

  engine <- Engine.initEngine
  result <- compileModuleFull engine pkg ifaces path projectType

  logCacheStats engine

  return result

-- | Compile a module with a shared query engine for caching across modules.
-- This variant allows cache reuse across multiple module compilations.
compileModuleWithEngine ::
  Engine.QueryEngine ->
  Pkg.Name ->
  Map ModuleName.Raw I.Interface ->
  FilePath ->
  Parse.ProjectType ->
  IO (Either QueryError CompileResult)
compileModuleWithEngine engine pkg ifaces path projectType = do
  Logger.debug COMPILE_DEBUG ("Compiling module: " ++ path)
  Logger.debug COMPILE_DEBUG ("Package: " ++ show pkg)

  compileModuleFull engine pkg ifaces path projectType

-- | Compile from already-parsed source module.
--
-- This variant accepts an already-parsed Src.Module instead of a file path.
-- Used when integrating with existing build systems that parse separately.
compileFromSource ::
  Pkg.Name ->
  Map ModuleName.Raw I.Interface ->
  Src.Module ->
  IO (Either QueryError CompileResult)
compileFromSource pkg ifaces sourceModule = do
  Logger.debug COMPILE_DEBUG "Compiling from parsed source"
  Logger.debug COMPILE_DEBUG ("Package: " ++ show pkg)

  engine <- Engine.initEngine
  ffiContent <- loadFFIContent sourceModule
  let foreignImports = Src._foreignImports sourceModule
      ffiInfoMap = buildFFIInfoMap foreignImports ffiContent
  canonResult <- runCanonicalizePhase engine pkg ifaces ffiContent sourceModule
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
              Logger.debug COMPILE_DEBUG "Compilation complete"
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

-- | Compile a module with existing engine (for batch compilation).
compileModuleFull ::
  Engine.QueryEngine ->
  Pkg.Name ->
  Map ModuleName.Raw I.Interface ->
  FilePath ->
  Parse.ProjectType ->
  IO (Either QueryError CompileResult)
compileModuleFull engine pkg ifaces path projectType = do
  Logger.debug COMPILE_DEBUG "Starting compilation pipeline"

  parseResult <- runParsePhase engine path projectType
  case parseResult of
    Left err -> return (Left err)
    Right sourceModule -> do
      ffiContent <- loadFFIContent sourceModule
      let foreignImports = Src._foreignImports sourceModule
          ffiInfoMap = buildFFIInfoMap foreignImports ffiContent
      canonResult <- runCanonicalizePhase engine pkg ifaces ffiContent sourceModule
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
                  Logger.debug COMPILE_DEBUG "Compilation complete"
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
loadFFIContent :: Src.Module -> IO (Map String String)
loadFFIContent sourceModule = do
  let foreignImports = Src._foreignImports sourceModule
  Logger.debug FFI_DEBUG ("Loading FFI content for " ++ show (length foreignImports) ++ " imports")
  Canonicalize.loadFFIContent foreignImports

-- | Build FFIInfo map from foreign imports and content.
buildFFIInfoMap :: [Src.ForeignImport] -> Map String String -> Map String FFIInfo
buildFFIInfoMap foreignImports contentMap =
  Map.fromList (buildFFIInfoList foreignImports contentMap)

-- | Build list of FFIInfo from imports and content.
buildFFIInfoList :: [Src.ForeignImport] -> Map String String -> [(String, FFIInfo)]
buildFFIInfoList foreignImports contentMap =
  concatMap (buildSingleFFI contentMap) foreignImports

-- | Build FFIInfo for a single import.
--
-- | Build FFI info for a single foreign import.
--
-- Returns empty list when the JavaScript file is not in the content map,
-- which indicates a missing FFI file that will be caught during
-- canonicalization with a proper error message.
buildSingleFFI :: Map String String -> Src.ForeignImport -> [(String, FFIInfo)]
buildSingleFFI contentMap (Src.ForeignImport (FFI.JavaScriptFFI jsPath) alias _region) =
  case Map.lookup jsPath contentMap of
    Just content ->
      let aliasStr = Name.toChars (A.toValue alias)
       in [(jsPath, FFIInfo jsPath content aliasStr)]
    Nothing -> []
buildSingleFFI _ _ = []

-- | Run canonicalize phase.
--
-- Tracks the phase execution through the query engine for accurate
-- compilation statistics, then delegates to the canonicalization query.
runCanonicalizePhase ::
  Engine.QueryEngine ->
  Pkg.Name ->
  Map ModuleName.Raw I.Interface ->
  Map String String ->
  Src.Module ->
  IO (Either QueryError Can.Module)
runCanonicalizePhase engine pkg ifaces ffiContent sourceModule = do
  Engine.trackPhaseExecution engine "canonicalize"
  CanonQuery.canonicalizeModuleQuery pkg ifaces ffiContent sourceModule

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
  IO I.Interface
generateInterface pkg canonModule@(Can.Module modName _ _ _ _ _ _ _) types = do
  Logger.debug COMPILE_DEBUG ("Generating interface for: " ++ show modName)
  let iface = I.fromModule pkg canonModule types
  Logger.debug COMPILE_DEBUG "Interface generated"
  return iface

-- | Compile multiple modules in parallel.
compileModulesParallel ::
  Pool.PoolConfig ->
  Pkg.Name ->
  Map ModuleName.Raw I.Interface ->
  [(FilePath, Parse.ProjectType)] ->
  IO [Either QueryError CompileResult]
compileModulesParallel config pkg ifaces modules = do
  Logger.debug COMPILE_DEBUG ("Compiling " ++ show (length modules) ++ " modules in parallel")

  pool <- Pool.createPool config compileTaskFn

  let tasks = map (createTask pkg ifaces) modules
  results <- Pool.compileModules pool tasks

  Pool.shutdownPool pool

  Logger.debug COMPILE_DEBUG "Parallel compilation complete"
  return results

-- | Compile modules with progress tracking.
compileModulesWithProgress ::
  Pool.PoolConfig ->
  Pkg.Name ->
  Map ModuleName.Raw I.Interface ->
  [(FilePath, Parse.ProjectType)] ->
  (Pool.Progress -> IO ()) ->
  IO [Either QueryError CompileResult]
compileModulesWithProgress config pkg ifaces modules progressCallback = do
  Logger.debug COMPILE_DEBUG ("Compiling " ++ show (length modules) ++ " modules with progress tracking")

  pool <- Pool.createPool config compileTaskFn

  let tasks = map (createTask pkg ifaces) modules
  results <- Pool.compileModulesWithProgress pool tasks progressCallback

  Pool.shutdownPool pool

  Logger.debug COMPILE_DEBUG "Parallel compilation complete"
  return results

-- | Create compile task from module info.
createTask :: Pkg.Name -> Map ModuleName.Raw I.Interface -> (FilePath, Parse.ProjectType) -> Pool.CompileTask
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
  let total = hits + misses
      hitRate =
        if total > 0
          then (fromIntegral hits / fromIntegral total * 100 :: Double)
          else 0.0

  Logger.debug CACHE_DEBUG ("Cache size: " ++ show cacheSize)
  Logger.debug CACHE_DEBUG ("Cache hits: " ++ show hits)
  Logger.debug CACHE_DEBUG ("Cache misses: " ++ show misses)
  Logger.debug CACHE_DEBUG ("Hit rate: " ++ show hitRate ++ "%")
