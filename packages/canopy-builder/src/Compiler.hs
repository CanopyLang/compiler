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
import qualified Build.Artifacts as Build
import Build.Artifacts
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Control.Monad (filterM)
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified Data.NonEmptyList as NE
import qualified Data.Utf8 as Utf8
import qualified Debug.Logger as Logger
import Debug.Logger (DebugCategory (..))
import qualified Driver
import qualified Exit
import qualified PackageCache
import qualified Parse.Module as Parse
import System.FilePath ((</>))
import qualified System.Directory as Dir

-- | Compile from file paths using NEW compiler.
--
-- This is the NEW replacement for Build.fromPaths.
compileFromPaths ::
  Pkg.Name ->
  FilePath ->
  [FilePath] ->
  IO (Either Exit.BuildError Build.Artifacts)
compileFromPaths pkg root paths = do
  Logger.debug COMPILE_DEBUG "Compiler: compileFromPaths (NEW pure compiler)"
  Logger.debug COMPILE_DEBUG ("Package: " ++ show pkg)
  Logger.debug COMPILE_DEBUG ("Paths: " ++ show paths)

  -- Load dependency artifacts (interfaces + GlobalGraph)
  maybeArtifacts <- loadDependencyArtifacts
  let (depInterfaces, depGlobalGraph) = case maybeArtifacts of
        Just (ifaces, globalGraph) -> (ifaces, globalGraph)
        Nothing -> (Map.empty, Opt.empty)

  -- Log dependency loading
  Logger.debug COMPILE_DEBUG ("Loaded dependency interfaces: " ++ show (Map.size depInterfaces))
  Logger.debug COMPILE_DEBUG ("Loaded dependency GlobalGraph with " ++ show (countGlobals depGlobalGraph) ++ " globals")

  -- Compile all modules using Driver with dependency interfaces
  results <- mapM (compileModuleWithInterfaces pkg root depInterfaces) paths

  -- Check for errors
  case sequence results of
    Left err -> return (Left err)
    Right compiledModules -> do
      -- Build artifacts with merged GlobalGraph
      let modules = map driverResultToModule compiledModules
          localGraphs = map extractLocalGraph compiledModules
          mergedGlobalGraph = mergeGraphs depGlobalGraph localGraphs
      Logger.debug COMPILE_DEBUG ("Merged GlobalGraph has " ++ show (countGlobals mergedGlobalGraph) ++ " globals")
      let artifacts = Build.Artifacts
            { Build._artifactsName = pkg
            , Build._artifactsDeps = Map.empty  -- TODO: Load from cache
            , Build._artifactsRoots = detectRoots modules
            , Build._artifactsModules = modules
            , Build._artifactsFFIInfo = Map.empty  -- TODO: Extract FFI info
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
  FilePath ->
  [SrcDir] ->
  NE.List ModuleName.Raw ->
  IO (Either Exit.BuildError Build.Artifacts)
compileFromExposed pkg root srcDirs exposedModules = do
  Logger.debug COMPILE_DEBUG "Compiler: compileFromExposed (NEW pure compiler)"
  Logger.debug COMPILE_DEBUG ("Package: " ++ show pkg)
  Logger.debug COMPILE_DEBUG ("Exposed: " ++ show (NE.toList exposedModules))

  -- Discover module paths
  paths <- discoverModulePaths root srcDirs (NE.toList exposedModules)

  compileFromPaths pkg root paths

-- Helper: Compile a single module with provided interfaces
compileModuleWithInterfaces ::
  Pkg.Name ->
  FilePath ->
  Map.Map ModuleName.Raw I.Interface ->
  FilePath ->
  IO (Either Exit.BuildError Driver.CompileResult)
compileModuleWithInterfaces pkg _root ifaces path = do
  result <- Driver.compileModule pkg ifaces path (Parse.Package pkg)
  case result of
    Left err -> return (Left (Exit.BuildCannotCompile (Exit.CompileParseError path (show err))))
    Right compiled -> return (Right compiled)

-- Helper: Load all dependency artifacts (interfaces + GlobalGraph)
loadDependencyArtifacts :: IO (Maybe (Map.Map ModuleName.Raw I.Interface, Opt.GlobalGraph))
loadDependencyArtifacts = do
  -- Load common packages that are typically used
  let elm = Utf8.fromChars "elm"
      commonDeps =
        [ (Pkg.Name elm (Utf8.fromChars "core"), V.Version 1 0 5)
        , (Pkg.Name elm (Utf8.fromChars "html"), V.Version 1 0 0)
        , (Pkg.Name elm (Utf8.fromChars "json"), V.Version 1 1 3)
        , (Pkg.Name elm (Utf8.fromChars "virtual-dom"), V.Version 1 0 3)
        ]

  maybeArtifacts <- PackageCache.loadAllPackageArtifacts commonDeps
  case maybeArtifacts of
    Nothing -> return Nothing
    Just artifacts ->
      -- Convert DependencyInterfaces to Interfaces
      let depInterfaces = PackageCache.artifactInterfaces artifacts
          convertedInterfaces = convertDependencyInterfaces depInterfaces
          globalGraph = PackageCache.artifactObjects artifacts
      in return (Just (convertedInterfaces, globalGraph))

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
  let relativePath = moduleNameToPath moduleName
  let searchPaths = map (\dir -> root </> srcDirToString dir </> relativePath) srcDirs
  existing <- filterM Dir.doesFileExist searchPaths
  return existing

moduleNameToPath :: ModuleName.Raw -> FilePath
moduleNameToPath moduleName =
  let nameStr = Name.toChars moduleName
      parts = splitOn '.' nameStr
   in foldr1 (</>) (map (++ ".can") parts)

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
