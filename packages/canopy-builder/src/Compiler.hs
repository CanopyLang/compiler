{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

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
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import qualified Data.Aeson as Json
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import Control.Monad (filterM)
import qualified Control.Concurrent.Async as Async
import qualified Data.Maybe as Maybe
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified Data.NonEmptyList as NE
import qualified Data.Set as Set
import qualified Data.ByteString as BS
import qualified Data.Utf8 as Utf8
import qualified Debug.Logger as Logger
import Debug.Logger (DebugCategory (..))
import qualified Driver
import qualified Exit
import qualified Reporting.InternalError as InternalError
import qualified Generate.JavaScript as JS
import qualified Query.Engine as Engine
import qualified Query.Simple as Query
import qualified PackageCache
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as A
import System.FilePath ((</>), normalise)
import qualified System.Directory as Dir

-- | Compile from file paths using NEW compiler.
--
-- This is the NEW replacement for Build.fromPaths.
-- Now includes source directories for transitive import discovery.
compileFromPaths ::
  Pkg.Name ->
  Bool -> -- Is this an application (True) or package (False)?
  FilePath ->
  [SrcDir] ->
  [FilePath] ->
  IO (Either Exit.BuildError Build.Artifacts)
compileFromPaths pkg isApp root srcDirs paths = do
  Logger.debug COMPILE_DEBUG "Compiler: compileFromPaths (NEW pure compiler)"
  Logger.debug COMPILE_DEBUG ("Package: " ++ show pkg)
  Logger.debug COMPILE_DEBUG ("IsApplication: " ++ show isApp)
  Logger.debug COMPILE_DEBUG ("Paths: " ++ show paths)

  -- Load dependency artifacts (interfaces + GlobalGraph)
  maybeArtifacts <- loadDependencyArtifacts root
  let (depInterfaces, depGlobalGraph) = case maybeArtifacts of
        Just (ifaces, globalGraph) -> (ifaces, globalGraph)
        Nothing -> (Map.empty, Opt.empty)

  Logger.debug COMPILE_DEBUG ("Loaded dependency interfaces: " ++ show (Map.size depInterfaces))

  -- Discover transitive dependencies
  let projectType = if isApp then Parse.Application else Parse.Package pkg
  allModulePaths <- discoverTransitiveDeps root srcDirs paths depInterfaces projectType
  Logger.debug COMPILE_DEBUG ("Discovered " ++ show (Map.size allModulePaths) ++ " total modules to compile")

  -- Compile in dependency order with growing interface map
  compileResult <- compileModulesInOrder pkg projectType root depInterfaces allModulePaths
  case compileResult of
    Left err -> return (Left err)
    Right (compiledModules, _finalInterfaces) -> do
      -- Build artifacts with merged GlobalGraph
      let modules = map driverResultToModule compiledModules
          localGraphs = map extractLocalGraph compiledModules
          mergedGlobalGraph = mergeGraphs depGlobalGraph localGraphs
          ffiInfoMap = collectFFIInfo compiledModules
          artifacts = Build.Artifacts
            { Build._artifactsName = pkg
            , Build._artifactsDeps = Map.empty
            , Build._artifactsRoots = detectRoots modules
            , Build._artifactsModules = modules
            , Build._artifactsFFIInfo = ffiInfoMap
            , Build._artifactsGlobalGraph = mergedGlobalGraph
            }
      return (Right artifacts)

-- | Compile from exposed modules using NEW compiler.
--
-- This is the NEW replacement for Build.fromExposed.
-- | Source directory types (pure, no dependencies).
data SrcDir
  = AbsoluteSrcDir FilePath
  | RelativeSrcDir FilePath
  deriving (Show, Eq)

compileFromExposed ::
  Pkg.Name ->
  Bool -> -- Is this an application (True) or package (False)?
  FilePath ->
  [SrcDir] ->
  NE.List ModuleName.Raw ->
  IO (Either Exit.BuildError Build.Artifacts)
compileFromExposed pkg isApp root srcDirs exposedModules = do
  Logger.debug COMPILE_DEBUG "Compiler: compileFromExposed (NEW pure compiler)"
  Logger.debug COMPILE_DEBUG ("Package: " ++ show pkg)
  Logger.debug COMPILE_DEBUG ("Exposed: " ++ show (NE.toList exposedModules))

  -- Discover module paths
  paths <- discoverModulePaths root srcDirs (NE.toList exposedModules)

  compileFromPaths pkg isApp root srcDirs paths

-- Helper: Discover transitive dependencies
discoverTransitiveDeps ::
  FilePath ->
  [SrcDir] ->
  [FilePath] ->
  Map.Map ModuleName.Raw I.Interface ->
  Parse.ProjectType ->
  IO (Map.Map ModuleName.Raw FilePath)
discoverTransitiveDeps root srcDirs initialPaths depInterfaces projectType = do
  Logger.debug COMPILE_DEBUG ("discoverTransitiveDeps: root=" ++ root)
  Logger.debug COMPILE_DEBUG ("discoverTransitiveDeps: srcDirs=" ++ show srcDirs)
  Logger.debug COMPILE_DEBUG ("discoverTransitiveDeps: initialPaths=" ++ show initialPaths)
  -- Parse initial modules to get their names and imports
  initialModules <- mapM (parseModuleFile projectType) initialPaths
  Logger.debug COMPILE_DEBUG ("discoverTransitiveDeps: parsed " ++ show (length initialModules) ++ " initial modules")
  let initialMap = Map.fromList [(Src.getName m, p) | (m, p) <- zip initialModules initialPaths]
  Logger.debug COMPILE_DEBUG ("discoverTransitiveDeps: initialMap keys=" ++ show (Map.keys initialMap))
  -- Recursively discover imports
  result <- discoverImports root srcDirs initialMap Set.empty initialModules depInterfaces projectType
  Logger.debug COMPILE_DEBUG ("discoverTransitiveDeps: final result keys=" ++ show (Map.keys result))
  return result
  where
    parseModuleFile projType path = do
      content <- BS.readFile path
      case Parse.fromByteString projType content of
        Left err -> InternalError.report
          "Compiler.discoverTransitiveDeps.parseModuleFile"
          ("Failed to parse module: " <> Text.pack path)
          ("Parse error while discovering transitive dependencies: " <> Text.pack (show err))
        Right m -> return m

-- Helper: Recursively discover imports
discoverImports ::
  FilePath ->
  [SrcDir] ->
  Map.Map ModuleName.Raw FilePath ->
  Set.Set ModuleName.Raw ->
  [Src.Module] ->
  Map.Map ModuleName.Raw I.Interface ->
  Parse.ProjectType ->
  IO (Map.Map ModuleName.Raw FilePath)
discoverImports root srcDirs found visited modules depInterfaces projectType =
  case modules of
    [] -> do
      Logger.debug COMPILE_DEBUG ("discoverImports: no more modules, returning found=" ++ show (Map.keys found))
      return found
    (modul : rest) -> do
      let modName = Src.getName modul
      Logger.debug COMPILE_DEBUG ("discoverImports: processing module=" ++ Name.toChars modName)
      if Set.member modName visited || Map.member modName depInterfaces
        then do
          Logger.debug COMPILE_DEBUG ("discoverImports: skipping " ++ Name.toChars modName ++ " (already visited or dep)")
          discoverImports root srcDirs found (Set.insert modName visited) rest depInterfaces projectType
        else do
          let imports = [A.toValue (Src._importName imp) | imp <- Src._imports modul]
          Logger.debug COMPILE_DEBUG ("discoverImports: found " ++ show (length imports) ++ " imports in " ++ Name.toChars modName)
          Logger.debug COMPILE_DEBUG ("discoverImports: imports=" ++ show (map Name.toChars imports))
          let newImports = filter (\imp -> not (Map.member imp found) && not (Map.member imp depInterfaces)) imports
          Logger.debug COMPILE_DEBUG ("discoverImports: newImports=" ++ show (map Name.toChars newImports))
          -- Find paths for new imports
          newPaths <- mapM (findModulePath root srcDirs) newImports
          Logger.debug COMPILE_DEBUG ("discoverImports: newPaths=" ++ show newPaths)
          let validPairs = [(imp, path) | (Just path, imp) <- zip newPaths newImports]
          Logger.debug COMPILE_DEBUG ("discoverImports: validPairs count=" ++ show (length validPairs))
          let newFound = foldr (\(imp, path) m -> Map.insert imp path m) found validPairs
          -- Parse new modules
          newModules <- mapM (parseModuleFromPath root srcDirs projectType) [imp | (imp, _) <- validPairs]
          Logger.debug COMPILE_DEBUG ("discoverImports: parsed " ++ show (length newModules) ++ " new modules")
          discoverImports root srcDirs newFound (Set.insert modName visited) (rest ++ newModules) depInterfaces projectType

parseModuleFromPath :: FilePath -> [SrcDir] -> Parse.ProjectType -> ModuleName.Raw -> IO Src.Module
parseModuleFromPath root srcDirs projectType modName = do
  maybePath <- findModulePath root srcDirs modName
  case maybePath of
    Nothing -> InternalError.report
      "Compiler.parseModuleFromPath"
      ("Module not found: " <> Text.pack (Name.toChars modName))
      "Failed to locate source file for imported module during transitive dependency discovery."
    Just path -> do
      content <- BS.readFile path
      case Parse.fromByteString projectType content of
        Left err -> InternalError.report
          "Compiler.parseModuleFromPath"
          ("Failed to parse: " <> Text.pack path)
          ("Parse error: " <> Text.pack (show err))
        Right m -> return m

findModulePath :: FilePath -> [SrcDir] -> ModuleName.Raw -> IO (Maybe FilePath)
findModulePath root srcDirs modName = do
  paths <- findModuleInDirs root srcDirs modName
  return (case paths of
            [] -> Nothing
            (p:_) -> Just p)

-- Helper: Compile modules in dependency order with PARALLEL execution
compileModulesInOrder ::
  Pkg.Name ->
  Parse.ProjectType ->
  FilePath ->
  Map.Map ModuleName.Raw I.Interface ->
  Map.Map ModuleName.Raw FilePath ->
  IO (Either Exit.BuildError ([Driver.CompileResult], Map.Map ModuleName.Raw I.Interface))
compileModulesInOrder pkg projectType _root initialInterfaces modulePaths = do
  Logger.debug COMPILE_DEBUG ("====== PARALLEL COMPILATION STARTING ======")
  Logger.debug COMPILE_DEBUG ("Total modules to compile: " ++ show (Map.size modulePaths))

  -- Create shared query engine for all module compilations
  engine <- Engine.initEngine

  -- Build dependency graph for parallel compilation
  -- Only include dependencies that are in modulePaths (i.e., modules we're compiling)
  moduleImports <- mapM (parseModuleImports projectType) (Map.toList modulePaths)
  let moduleNames = Map.keysSet modulePaths
      -- Filter imports to only include modules we're actually compiling
      depList = [(modName, filter (`Set.member` moduleNames) imports) | (modName, _, imports) <- moduleImports]
      graph = Graph.buildGraph depList

  Logger.debug COMPILE_DEBUG ("Dependency graph built with " ++ show (length depList) ++ " modules")

  -- Prepare module statuses (moduleName -> filepath)
  let moduleStatuses = modulePaths

  -- Compile in parallel using Build.Parallel with dependency graph
  -- We need to thread through interfaces as we compile, so we'll use a custom approach
  -- that leverages the parallel infrastructure while maintaining interface state
  result <- compileParallelWithInterfaces engine graph moduleStatuses initialInterfaces

  -- Log cache statistics after all compilations
  Driver.logCacheStats engine

  return result
  where
    -- Compile modules in parallel while threading interfaces through each dependency level
    compileParallelWithInterfaces ::
      Engine.QueryEngine ->
      Graph.DependencyGraph ->
      Map.Map ModuleName.Raw FilePath ->
      Map.Map ModuleName.Raw I.Interface ->
      IO (Either Exit.BuildError ([Driver.CompileResult], Map.Map ModuleName.Raw I.Interface))
    compileParallelWithInterfaces queryEngine graph statuses initialIfaces = do
      let plan = Parallel.groupByDependencyLevel graph
          levels = Parallel.planLevels plan

      Logger.debug COMPILE_DEBUG ("PARALLEL COMPILATION: " ++ show (length levels) ++ " dependency levels identified")
      Logger.debug COMPILE_DEBUG ("Level breakdown: " ++ show (map length levels) ++ " modules per level")

      -- Compile each level sequentially, but within each level compile in parallel
      compileLevels queryEngine levels initialIfaces [] statuses

    -- Compile levels one by one, accumulating results and interfaces
    compileLevels ::
      Engine.QueryEngine ->
      [[ModuleName.Raw]] ->
      Map.Map ModuleName.Raw I.Interface ->
      [Driver.CompileResult] ->
      Map.Map ModuleName.Raw FilePath ->
      IO (Either Exit.BuildError ([Driver.CompileResult], Map.Map ModuleName.Raw I.Interface))
    compileLevels _ [] ifaces compiled _ = return (Right (compiled, ifaces))
    compileLevels queryEngine (level : restLevels) ifaces compiled statuses = do
      -- Log parallel compilation level
      Logger.debug COMPILE_DEBUG ("Compiling level with " ++ show (length level) ++ " modules in parallel: " ++ show (map Name.toChars level))
      -- Compile all modules in this level in parallel
      levelResult <- compileLevelInParallel queryEngine level ifaces statuses
      case levelResult of
        Left err -> return (Left err)
        Right (levelCompiled, levelIfaces) -> do
          -- Merge interfaces and continue with next level
          let newIfaces = Map.union levelIfaces ifaces
              newCompiled = compiled ++ levelCompiled
          compileLevels queryEngine restLevels newIfaces newCompiled statuses

    -- Compile a single level (all modules in parallel)
    compileLevelInParallel ::
      Engine.QueryEngine ->
      [ModuleName.Raw] ->
      Map.Map ModuleName.Raw I.Interface ->
      Map.Map ModuleName.Raw FilePath ->
      IO (Either Exit.BuildError ([Driver.CompileResult], Map.Map ModuleName.Raw I.Interface))
    compileLevelInParallel queryEngine modules ifaces statuses = do
      -- Compile all modules in this level concurrently using Async
      results <- Async.mapConcurrently (compileOneModule queryEngine ifaces statuses) modules

      -- Check for errors
      let (errors, successes) = partitionEithers results
      case errors of
        (err : _) -> return (Left err)
        [] -> do
          let compiled = map fst successes
              newIfaces = Map.fromList [pair | (_, pair) <- successes]
          return (Right (compiled, newIfaces))

    -- Compile a single module
    compileOneModule ::
      Engine.QueryEngine ->
      Map.Map ModuleName.Raw I.Interface ->
      Map.Map ModuleName.Raw FilePath ->
      ModuleName.Raw ->
      IO (Either Exit.BuildError (Driver.CompileResult, (ModuleName.Raw, I.Interface)))
    compileOneModule queryEngine ifaces statuses modName = do
      case Map.lookup modName statuses of
        Nothing -> do
          -- This should not happen - module in dependency graph but not in paths
          let errMsg = "Internal error: Module " ++ Name.toChars modName ++ " not found in module paths"
          return (Left (Exit.BuildCannotCompile (Exit.CompileModuleNotFound errMsg)))
        Just path -> do
          Logger.debug COMPILE_DEBUG ("Compiling module: " ++ Name.toChars modName)
          compilationResult <- Driver.compileModuleWithEngine queryEngine pkg ifaces path projectType
          case compilationResult of
            Left err -> return (Left (Exit.BuildCannotCompile (queryErrorToCompileError path err)))
            Right compiledResult -> do
              let newIface = Driver.compileResultInterface compiledResult
              return (Right (compiledResult, (modName, newIface)))

    -- Helper to partition Either lists
    partitionEithers :: [Either a b] -> ([a], [b])
    partitionEithers = foldr (either left right) ([], [])
      where
        left a (l, r) = (a : l, r)
        right b (l, r) = (l, b : r)

-- Helper: Parse module to extract its imports
parseModuleImports :: Parse.ProjectType -> (ModuleName.Raw, FilePath) -> IO (ModuleName.Raw, FilePath, [ModuleName.Raw])
parseModuleImports projectType (modName, path) = do
  content <- BS.readFile path
  case Parse.fromByteString projectType content of
    Left _err -> return (modName, path, [])
    Right modul -> do
      let imports = [A.toValue (Src._importName imp) | imp <- Src._imports modul]
      return (modName, path, imports)

-- Helper: Convert QueryError to CompileError with proper categorization
queryErrorToCompileError :: FilePath -> Query.QueryError -> Exit.CompileError
queryErrorToCompileError path qErr =
  case qErr of
    Query.ParseError _ msg -> Exit.CompileParseError path msg
    Query.TypeError msg -> Exit.CompileTypeError path msg
    Query.FileNotFound fpath -> Exit.CompileModuleNotFound fpath
    Query.OtherError msg -> Exit.CompileCanonicalizeError path msg

-- Helper: Load all dependency artifacts (interfaces + GlobalGraph)
-- Uses parallel loading for optimal performance
loadDependencyArtifacts :: FilePath -> IO (Maybe (Map.Map ModuleName.Raw I.Interface, Opt.GlobalGraph))
loadDependencyArtifacts root = do
  -- Read project dependencies from elm.json/canopy.json
  deps <- readProjectDependencies root
  Logger.debug COMPILE_DEBUG ("Loading " ++ show (length deps) ++ " dependencies in parallel...")

  case deps of
    [] -> do
      Logger.debug COMPILE_DEBUG "No dependencies found"
      return (Just (Map.empty, Opt.empty))
    _ -> do
      -- Load all packages in parallel with async
      -- Packages that fail to load are silently skipped
      maybeArtifacts <- PackageCache.loadAllPackageArtifacts deps
      case maybeArtifacts of
        Nothing -> do
          Logger.debug COMPILE_DEBUG "No valid packages loaded"
          return (Just (Map.empty, Opt.empty))
        Just artifacts -> do
          let depInterfaces = PackageCache.artifactInterfaces artifacts
              convertedInterfaces = convertDependencyInterfaces depInterfaces
              globalGraph = PackageCache.artifactObjects artifacts
          Logger.debug COMPILE_DEBUG ("Successfully loaded " ++ show (Map.size convertedInterfaces) ++ " module interfaces")
          return (Just (convertedInterfaces, globalGraph))

-- Helper: Read project dependencies from elm.json or canopy.json
readProjectDependencies :: FilePath -> IO [(Pkg.Name, V.Version)]
readProjectDependencies root = do
  let canopyPath = root </> "canopy.json"
      elmPath = root </> "elm.json"

  -- Try canopy.json first, then elm.json
  canopyExists <- Dir.doesFileExist canopyPath
  elmExists <- Dir.doesFileExist elmPath

  let jsonPath = if canopyExists then canopyPath else if elmExists then elmPath else ""

  if null jsonPath
    then do
      Logger.debug COMPILE_DEBUG "No project file found"
      return []
    else do
      Logger.debug COMPILE_DEBUG ("Reading dependencies from: " ++ jsonPath)
      content <- LBS.readFile jsonPath
      case Json.decode content of
        Nothing -> do
          Logger.debug COMPILE_DEBUG "Failed to parse project file"
          return []
        Just (Json.Object obj) -> do
          let deps = extractDepsFromJson obj
          Logger.debug COMPILE_DEBUG ("Extracted " ++ show (length deps) ++ " dependencies")
          return deps
        _ -> return []

-- Helper: Extract dependencies from parsed JSON object
extractDepsFromJson :: Json.Object -> [(Pkg.Name, V.Version)]
extractDepsFromJson obj =
  case KeyMap.lookup "dependencies" obj of
    Nothing -> []
    Just (Json.Object depsObj) ->
      -- Handle both application format (dependencies.direct + dependencies.indirect)
      -- and package format (dependencies is a flat map)
      case (KeyMap.lookup "direct" depsObj, KeyMap.lookup "indirect" depsObj) of
        (Just (Json.Object directObj), Just (Json.Object indirectObj)) ->
          parseDepsMap directObj ++ parseDepsMap indirectObj
        _ -> parseDepsMap depsObj
    _ -> []

-- Helper: Parse dependencies map from JSON
parseDepsMap :: Json.Object -> [(Pkg.Name, V.Version)]
parseDepsMap depsMap =
  foldr extractDep [] (KeyMap.toList depsMap)
  where
    extractDep (pkgNameKey, versionValue) acc =
      case (parsePackageName pkgNameKey, parseVersion versionValue) of
        (Just pkgName, Just version) -> (pkgName, version) : acc
        _ -> acc

-- Helper: Parse package name from JSON key
parsePackageName :: Json.Key -> Maybe Pkg.Name
parsePackageName key =
  let keyText = Key.toText key
      parts = Text.splitOn "/" keyText
   in case parts of
        [authorText, projectText] ->
          let author = Utf8.fromChars (Text.unpack authorText)
              project = Utf8.fromChars (Text.unpack projectText)
           in Just (Pkg.Name author project)
        _ -> Nothing

-- Helper: Parse version from JSON value
parseVersion :: Json.Value -> Maybe V.Version
parseVersion (Json.String versionStr) =
  let parts = Text.splitOn "." versionStr
   in case parts of
        [majorStr, minorStr, patchStr] ->
          case (readMaybe (Text.unpack majorStr), readMaybe (Text.unpack minorStr), readMaybe (Text.unpack patchStr)) of
            (Just major, Just minor, Just patch) -> Just (V.Version major minor patch)
            _ -> Nothing
        _ -> Nothing
parseVersion _ = Nothing

readMaybe :: Read a => String -> Maybe a
readMaybe s = case reads s of
  [(val, "")] -> Just val
  _ -> Nothing

-- Helper: Convert DependencyInterface map to Interface map
convertDependencyInterfaces :: Map.Map ModuleName.Raw I.DependencyInterface -> Map.Map ModuleName.Raw I.Interface
convertDependencyInterfaces = Map.mapMaybe extractInterface
  where
    extractInterface :: I.DependencyInterface -> Maybe I.Interface
    extractInterface (I.Public iface) = Just iface
    extractInterface (I.Private pkg unions aliases) =
      -- Convert Private to Interface by wrapping unions and aliases
      Just (I.Interface pkg Map.empty (Map.map I.PrivateUnion unions) (Map.map I.PrivateAlias aliases) Map.empty)

-- Helper: Convert Driver result to Build.Module
driverResultToModule :: Driver.CompileResult -> Build.Module
driverResultToModule result =
  let modName = extractModuleName (Driver.compileResultModule result)
      iface = Driver.compileResultInterface result
      localGraph = Driver.compileResultLocalGraph result
   in Build.Fresh modName iface localGraph

-- Helper: Extract LocalGraph from CompileResult
extractLocalGraph :: Driver.CompileResult -> Opt.LocalGraph
extractLocalGraph = Driver.compileResultLocalGraph

-- Helper: Collect FFI info from all compiled modules
collectFFIInfo :: [Driver.CompileResult] -> Map.Map String JS.FFIInfo
collectFFIInfo compiledModules =
  Map.unions (map extractFFIInfo compiledModules)

-- Helper: Extract FFI info from single CompileResult
extractFFIInfo :: Driver.CompileResult -> Map.Map String JS.FFIInfo
extractFFIInfo result =
  Map.map convertFFIInfo (Driver.compileResultFFIInfo result)

-- Helper: Convert Driver.FFIInfo to JS.FFIInfo
convertFFIInfo :: Driver.FFIInfo -> JS.FFIInfo
convertFFIInfo driverInfo =
  JS.FFIInfo
    { JS.ffiFilePath = Driver.ffiFilePath driverInfo
    , JS.ffiContent = Driver.ffiContent driverInfo
    , JS.ffiAlias = Driver.ffiAlias driverInfo
    }

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
    moduleToRootIfMain (Build.Fresh modName iface localGraph@(Opt.LocalGraph maybeMain _ _)) =
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
