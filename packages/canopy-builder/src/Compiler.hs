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

import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import qualified Build.Artifacts as Build
import Build.Artifacts
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import qualified Data.Aeson as Json
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import Control.Monad (filterM, foldM)
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
  Logger.debug COMPILE_DEBUG ("Loaded dependency GlobalGraph with " ++ show (countGlobals depGlobalGraph) ++ " globals")

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
      Logger.debug COMPILE_DEBUG ("Merged GlobalGraph has " ++ show (countGlobals mergedGlobalGraph) ++ " globals")
      let artifacts = Build.Artifacts
            { Build._artifactsName = pkg
            , Build._artifactsDeps = Map.empty
            , Build._artifactsRoots = detectRoots modules
            , Build._artifactsModules = modules
            , Build._artifactsFFIInfo = Map.empty
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
        Left err -> error ("Failed to parse: " ++ path ++ "\nError: " ++ show err)
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
    Nothing -> error ("Module not found: " ++ Name.toChars modName)
    Just path -> do
      content <- BS.readFile path
      case Parse.fromByteString projectType content of
        Left err -> error ("Failed to parse: " ++ path ++ "\nError: " ++ show err)
        Right m -> return m

findModulePath :: FilePath -> [SrcDir] -> ModuleName.Raw -> IO (Maybe FilePath)
findModulePath root srcDirs modName = do
  paths <- findModuleInDirs root srcDirs modName
  return (case paths of
            [] -> Nothing
            (p:_) -> Just p)

-- Helper: Compile modules in dependency order
compileModulesInOrder ::
  Pkg.Name ->
  Parse.ProjectType ->
  FilePath ->
  Map.Map ModuleName.Raw I.Interface ->
  Map.Map ModuleName.Raw FilePath ->
  IO (Either Exit.BuildError ([Driver.CompileResult], Map.Map ModuleName.Raw I.Interface))
compileModulesInOrder pkg projectType _root initialInterfaces modulePaths = do
  -- Build dependency graph and sort topologically
  moduleImports <- mapM (parseModuleImports projectType) (Map.toList modulePaths)
  let depGraph = Map.fromList [(modName, imports) | (modName, _, imports) <- moduleImports]
      sortedModules = topologicalSort depGraph (Map.keys modulePaths)
  -- Compile in topological order
  foldM compileNext (Right ([], initialInterfaces)) sortedModules
  where
    compileNext (Left err) _ = return (Left err)
    compileNext (Right (compiled, ifaces)) modName = do
      case Map.lookup modName modulePaths of
        Nothing -> return (Right (compiled, ifaces))
        Just path -> do
          Logger.debug COMPILE_DEBUG ("Compiling module: " ++ Name.toChars modName)
          result <- Driver.compileModule pkg ifaces path projectType
          case result of
            Left err -> return (Left (Exit.BuildCannotCompile (Exit.CompileParseError path (show err))))
            Right compiledResult -> do
              let newIface = Driver.compileResultInterface compiledResult
                  newIfaces = Map.insert modName newIface ifaces
              return (Right (compiled ++ [compiledResult], newIfaces))

-- Helper: Parse module to extract its imports
parseModuleImports :: Parse.ProjectType -> (ModuleName.Raw, FilePath) -> IO (ModuleName.Raw, FilePath, [ModuleName.Raw])
parseModuleImports projectType (modName, path) = do
  content <- BS.readFile path
  case Parse.fromByteString projectType content of
    Left _err -> return (modName, path, [])
    Right modul -> do
      let imports = [A.toValue (Src._importName imp) | imp <- Src._imports modul]
      return (modName, path, imports)

-- Helper: Topological sort of modules based on dependencies
topologicalSort :: Map.Map ModuleName.Raw [ModuleName.Raw] -> [ModuleName.Raw] -> [ModuleName.Raw]
topologicalSort depGraph modules =
  let (_visited, sorted) = go Set.empty [] modules
   in reverse sorted
  where
    go visited sorted [] = (visited, sorted)
    go visited sorted (m : ms)
      | Set.member m visited = go visited sorted ms
      | otherwise =
          let deps = Map.findWithDefault [] m depGraph
              visited' = Set.insert m visited
              (visited'', sorted') = foldl (\(v, s) dep -> visitModule v s dep) (visited', sorted) deps
           in go visited'' (m : sorted') ms

    visitModule visited sorted modName
      | Set.member modName visited = (visited, sorted)
      | otherwise =
          let deps = Map.findWithDefault [] modName depGraph
              visited' = Set.insert modName visited
              (visited'', sorted') = foldl (\(v, s) dep -> visitModule v s dep) (visited', sorted) deps
           in (visited'', modName : sorted')

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

-- Helper: Merge dependency GlobalGraph with compiled LocalGraphs
mergeGraphs :: Opt.GlobalGraph -> [Opt.LocalGraph] -> Opt.GlobalGraph
mergeGraphs depGlobalGraph localGraphs =
  foldr Opt.addLocalGraph depGlobalGraph localGraphs

-- Helper: Count globals in a GlobalGraph
countGlobals :: Opt.GlobalGraph -> Int
countGlobals (Opt.GlobalGraph nodes _) = Map.size nodes

-- Helper: Extract module name from canonical module
extractModuleName :: a -> ModuleName.Raw
extractModuleName _ = Name.fromChars "Main"  -- TODO: Extract actual name

-- Helper: Detect root modules
detectRoots :: [Build.Module] -> NE.List Build.Root
detectRoots modules =
  case modules of
    [] -> NE.List (Build.Inside (Name.fromChars "Main")) []
    (Build.Fresh modName iface localGraph : _) ->
      NE.List (Build.Outside modName iface localGraph) []

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
