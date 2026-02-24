{-# OPTIONS_GHC -Wall #-}

-- | Pure builder - STM-free build system.
--
-- This module provides a pure functional build system that replaces
-- the OLD Build.hs STM-based system. It uses:
--
-- * Single IORef for state (Builder.State)
-- * Pure dependency graph (Builder.Graph)
-- * Content-hash based incremental compilation (Builder.Incremental)
-- * Pure dependency solver (Builder.Solver)
--
-- === Architecture
--
-- The pure builder follows the NEW query engine pattern:
--
-- 1. **Pure Data**: All build state in pure Maps/Sets
-- 2. **Single IORef**: One IORef for mutable state (no TVars/MVars)
-- 3. **Explicit Dependencies**: Clear dependency tracking
-- 4. **Incremental**: Content-hash based change detection
--
-- === Entry Points
--
-- * 'buildFromPaths': Build from source file paths
-- * 'buildFromExposed': Build from exposed module list
-- * 'buildModule': Build single module
--
-- === Usage
--
-- @
-- -- Initialize builder
-- builder <- initPureBuilder
--
-- -- Build from paths
-- result <- buildFromPaths builder ["src/Main.can"]
-- case result of
--   Left err -> print err
--   Right artifacts -> print "Build successful"
-- @
--
-- @since 0.19.1
module Builder
  ( -- * Builder Types
    PureBuilder (..),
    BuildResult (..),
    BuildError (..),

    -- * Builder Creation
    initPureBuilder,

    -- * Building
    buildFromPaths,
    buildFromExposed,
    -- buildModule,  -- DISABLED: Uses OLD Compile (moved to old/)

    -- * Build Status
    getBuildStatus,
    getBuildProgress,
  )
where

import qualified AST.Source as Src
import qualified Builder.Graph as Graph
import qualified Builder.Hash as Hash
import qualified Builder.Incremental as Incremental
import qualified Builder.Solver as Solver
import qualified Builder.State as State
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.ByteString as BS
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time.Clock (getCurrentTime)
import qualified Driver
import qualified File
import qualified Data.Text as Text
import Logging.Event (LogEvent (..), Duration (..), Phase (..), CompileStats (..))
import qualified Logging.Logger as Log
import qualified Parse.Module as Parse
import System.FilePath (takeDirectory, (</>))

-- | Pure builder with single IORef.
data PureBuilder = PureBuilder
  { builderEngine :: !State.BuilderEngine,
    builderCache :: !(IORef Incremental.BuildCache),
    builderGraph :: !(IORef Graph.DependencyGraph)
  }

-- | Build error.
data BuildError
  = BuildErrorSolver !Solver.SolverError
  | BuildErrorCycle ![ModuleName.Raw]
  | BuildErrorMissing ![ModuleName.Raw]
  | BuildErrorCompile !String
  deriving (Show, Eq)

-- | Build result.
data BuildResult
  = BuildSuccess !Int -- ^ Number of modules compiled
  | BuildFailure !BuildError
  deriving (Show, Eq)

-- | Initialize pure builder.
initPureBuilder :: IO PureBuilder
initPureBuilder = do
  Log.logEvent (BuildStarted (Text.pack "pure builder"))

  engine <- State.initBuilder
  cache <- Incremental.emptyCache >>= newIORef
  graph <- newIORef Graph.emptyGraph

  return
    PureBuilder
      { builderEngine = engine,
        builderCache = cache,
        builderGraph = graph
      }

-- | Build from file paths with dependency resolution.
buildFromPaths :: PureBuilder -> [FilePath] -> IO BuildResult
buildFromPaths builder paths = do
  Log.logEvent (BuildStarted (Text.pack ("from paths: " ++ show (length paths) ++ " files")))

  -- Get project root (parent of first source file)
  let root = case paths of
        (p : _) -> takeDirectory p
        [] -> "."

  -- Parse all modules
  parsedModules <- parseAllModules paths

  case parsedModules of
    Left err -> return (BuildFailure (BuildErrorCompile err))
    Right modules -> do
      Log.logEvent (BuildModuleQueued (Text.pack ("parsed " ++ show (length modules) ++ " modules")))

      -- Build dependency graph
      let deps = extractDependencies modules
      let graph = Graph.buildGraph deps
      writeIORef (builderGraph builder) graph

      -- Check for cycles
      case Graph.topologicalSort graph of
        Nothing -> do
          Log.logEvent (BuildFailed (Text.pack "dependency graph contains cycles"))
          return (BuildFailure (BuildErrorCycle (Graph.getAllModules graph)))

        Just buildOrder -> do
          Log.logEvent (BuildModuleQueued (Text.pack ("build order: " ++ show (length buildOrder) ++ " modules")))

          -- Compile modules in dependency order
          results <- compileInOrder builder root modules buildOrder
          let successCount = length (filter isSuccess results)

          if successCount == length buildOrder
            then do
              Log.logEvent (BuildCompleted successCount (Duration 0))
              return (BuildSuccess successCount)
            else do
              let failures = filter (not . isSuccess) results
              Log.logEvent (BuildFailed (Text.pack (show (length failures) ++ " modules failed")))
              return (BuildFailure (BuildErrorCompile (show (length failures) ++ " modules failed")))

-- | Parse all modules from file paths.
parseAllModules :: [FilePath] -> IO (Either String [(FilePath, Src.Module)])
parseAllModules paths = do
  results <- mapM parseModuleFromPath paths
  let (errors, successes) = partitionEithers results
  if null errors
    then return (Right successes)
    else return (Left ("Parse errors: " ++ show (length errors)))

-- | Parse single module from path.
parseModuleFromPath :: FilePath -> IO (Either String (FilePath, Src.Module))
parseModuleFromPath path = do
  sourceBytes <- BS.readFile path
  case Parse.fromByteString Parse.Application sourceBytes of
    Left parseErr -> return (Left (path ++ ": " ++ show parseErr))
    Right sourceModule -> return (Right (path, sourceModule))

-- | Extract dependencies from parsed modules.
extractDependencies :: [(FilePath, Src.Module)] -> [(ModuleName.Raw, [ModuleName.Raw])]
extractDependencies modules =
  map extractModuleDeps modules
  where
    extractModuleDeps (_, modul) =
      let moduleName = Src.getName modul
          imports = Src._imports modul
          importNames = map Src.getImportName imports
       in (moduleName, importNames)

-- | Compile modules in dependency order.
compileInOrder ::
  PureBuilder ->
  FilePath ->
  [(FilePath, Src.Module)] ->
  [ModuleName.Raw] ->
  IO [BuildResult]
compileInOrder builder root modules buildOrder = do
  -- Create module map for lookup
  let moduleMap = Map.fromList [(Src.getName m, (p, m)) | (p, m) <- modules]

  -- Compile each module in order
  mapM (compileModuleInOrder builder root moduleMap) buildOrder

-- | Compile single module in build order.
compileModuleInOrder ::
  PureBuilder ->
  FilePath ->
  Map ModuleName.Raw (FilePath, Src.Module) ->
  ModuleName.Raw ->
  IO BuildResult
compileModuleInOrder builder _root moduleMap moduleName =
  case Map.lookup moduleName moduleMap of
    Nothing -> do
      Log.logEvent (BuildFailed (Text.pack ("module not found in map: " ++ show moduleName)))
      return (BuildFailure (BuildErrorMissing [moduleName]))

    Just (path, _sourceModule) -> do
      sourceHash <- Hash.hashFile path
      cache <- readIORef (builderCache builder)
      let depsHash = Hash.hashString ""

      if Incremental.needsRecompile cache moduleName sourceHash depsHash
        then compileWithDriver builder moduleName path
        else useCache builder moduleName path

-- | Compile a module via the query-based Driver.
compileWithDriver :: PureBuilder -> ModuleName.Raw -> FilePath -> IO BuildResult
compileWithDriver builder moduleName path = do
  Log.logEvent (CompileStarted path)
  result <- Driver.compileModule Pkg.dummyName Map.empty path Parse.Application
  now <- getCurrentTime
  case result of
    Left err -> do
      Log.logEvent (CompileFailed path PhaseBuild (Text.pack (show err)))
      State.setModuleStatus (builderEngine builder) moduleName (State.StatusFailed (show err) now)
      return (BuildFailure (BuildErrorCompile (show err)))
    Right _compiled -> do
      Log.logEvent (CompileCompleted path (CompileStats 1 (Duration 0)))
      State.setModuleStatus (builderEngine builder) moduleName (State.StatusCompleted now)
      State.setModuleResult (builderEngine builder) moduleName (State.ResultSuccess path now)
      return (BuildSuccess 1)

-- | Check if build result is success.
isSuccess :: BuildResult -> Bool
isSuccess (BuildSuccess _) = True
isSuccess _ = False

-- | Partition list into Left and Right values.
partitionEithers :: [Either a b] -> ([a], [b])
partitionEithers = foldr partitionEither ([], [])
  where
    partitionEither (Left x) (ls, rs) = (x : ls, rs)
    partitionEither (Right x) (ls, rs) = (ls, x : rs)

-- | Build package from exposed modules.
--
-- This builds a complete package by discovering all modules reachable
-- from the exposed modules and compiling them in dependency order.
buildFromExposed ::
  PureBuilder ->
  FilePath ->  -- ^ Project root directory
  [String] ->  -- ^ Source directories (e.g., ["src"])
  [ModuleName.Raw] ->
  IO BuildResult
buildFromExposed builder root srcDirs exposedModules = do
  Log.logEvent (BuildStarted (Text.pack ("from exposed: " ++ show (length exposedModules) ++ " modules")))

  -- Discover source files for exposed modules
  modulePaths <- discoverModulePaths root srcDirs exposedModules

  case modulePaths of
    [] -> do
      Log.logEvent (BuildFailed (Text.pack "no source files found for exposed modules"))
      return (BuildFailure (BuildErrorMissing exposedModules))

    paths -> do
      Log.logEvent (BuildModuleQueued (Text.pack ("found " ++ show (length paths) ++ " source files")))

      -- Parse all modules to discover transitive dependencies
      allPaths <- discoverTransitiveDeps root srcDirs paths

      Log.logEvent (BuildModuleQueued (Text.pack ("building " ++ show (length allPaths) ++ " modules (including dependencies)")))

      -- Build all modules using buildFromPaths
      buildFromPaths builder allPaths

-- | Discover source file paths for module names.
discoverModulePaths ::
  FilePath ->  -- ^ Project root
  [String] ->  -- ^ Source directories
  [ModuleName.Raw] ->
  IO [FilePath]
discoverModulePaths root srcDirs moduleNames = do
  paths <- mapM (findModulePath root srcDirs) moduleNames
  return (concat paths)

-- | Find source file for a single module name.
findModulePath ::
  FilePath ->
  [String] ->
  ModuleName.Raw ->
  IO [FilePath]
findModulePath root srcDirs moduleName = do
  let moduleFilePath = moduleNameToPath moduleName
  foundPaths <- mapM (trySourceDir moduleFilePath) srcDirs
  return (concat foundPaths)
  where
    trySourceDir modPath srcDir = do
      let fullPath = root </> srcDir </> modPath
      exists <- File.exists fullPath
      return (if exists then [fullPath] else [])

-- | Convert module name to relative file path.
moduleNameToPath :: ModuleName.Raw -> FilePath
moduleNameToPath moduleName =
  let nameStr = show moduleName
      parts = splitModuleName nameStr
   in joinPath parts ++ ".can"
  where
    splitModuleName str = map trim (split '.' str)
    split c s = case break (== c) s of
      (l, []) -> [l]
      (l, _ : r) -> l : split c r
    trim = reverse . dropWhile (== ' ') . reverse . dropWhile (== ' ')
    joinPath = foldr1 (</>)

-- | Discover all transitive dependencies.
discoverTransitiveDeps ::
  FilePath ->
  [String] ->
  [FilePath] ->
  IO [FilePath]
discoverTransitiveDeps root srcDirs initialPaths = do
  allPaths <- go Set.empty initialPaths
  return (Set.toList allPaths)
  where
    go visited [] = return visited
    go visited (path : paths)
      | path `Set.member` visited = go visited paths
      | otherwise = do
          deps <- getModuleDependencies root srcDirs path
          go (Set.insert path visited) (paths ++ deps)

-- | Get dependencies for a single module.
getModuleDependencies ::
  FilePath ->
  [String] ->
  FilePath ->
  IO [FilePath]
getModuleDependencies root srcDirs path = do
  sourceBytes <- BS.readFile path
  case Parse.fromByteString Parse.Application sourceBytes of
    Left _ -> return []
    Right sourceModule -> do
      let imports = Src._imports sourceModule
          importNames = map Src.getImportName imports
      discoverModulePaths root srcDirs importNames

-- | Build single module with full compilation pipeline.
-- REMOVED: buildModule function used OLD Compile module (moved to old/)
-- Use buildFromPaths instead for building modules.

-- | Use cached artifacts.
useCache :: PureBuilder -> ModuleName.Raw -> FilePath -> IO BuildResult
useCache builder moduleName path = do
  Log.logEvent (CacheHit PhaseBuild (Text.pack (show moduleName)))
  now <- getCurrentTime
  State.setModuleStatus (builderEngine builder) moduleName
    (State.StatusCompleted now)
  State.setModuleResult (builderEngine builder) moduleName
    (State.ResultSuccess path now)
  return (BuildSuccess 1)

-- | Get current build status.
getBuildStatus :: PureBuilder -> IO String
getBuildStatus builder = do
  completed <- State.getCompletedCount (builderEngine builder)
  pending <- State.getPendingCount (builderEngine builder)
  failed <- State.getFailedCount (builderEngine builder)

  return
    ( "Build Status: "
        ++ show completed
        ++ " completed, "
        ++ show pending
        ++ " pending, "
        ++ show failed
        ++ " failed"
    )

-- | Get build progress (completed / total).
getBuildProgress :: PureBuilder -> IO (Int, Int)
getBuildProgress builder = do
  completed <- State.getCompletedCount (builderEngine builder)
  statuses <- State.getAllStatuses (builderEngine builder)
  let total = length statuses
  return (completed, total)
