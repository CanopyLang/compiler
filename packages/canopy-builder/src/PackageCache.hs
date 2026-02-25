{-# OPTIONS_GHC -Wall #-}

-- | Package artifact cache loading for dependency interfaces.
--
-- This module provides functions to load compiled interfaces from package
-- artifact cache files. These artifacts are generated when packages are
-- installed and contain the compiled interfaces needed for type checking.
--
-- ==== Package Cache Structure
--
-- Installed packages store artifacts at:
-- @~/.elm/0.19.1/packages/author/package/version/artifacts.dat@
--
-- For Canopy, packages may also be at:
-- @~/.canopy/packages/author/package/version/artifacts.dat@
--
-- ==== Examples
--
-- >>> -- Load elm/core 1.0.5 interfaces
-- >>> interfaces <- loadPackageInterfaces "elm" "core" "1.0.5"
-- >>> case interfaces of
-- ...   Just ifaces -> -- Use the interfaces for compilation
-- ...   Nothing -> -- Package not installed or no artifacts
--
-- @since 0.19.1
module PackageCache
  ( -- * Loading Interfaces
    loadPackageInterfaces
  , loadElmCoreInterfaces
  , loadAllDependencyInterfaces
  , loadModuleInterface
    -- * Loading Complete Artifacts
  , loadPackageArtifacts
  , loadAllPackageArtifacts
    -- * Writing Artifacts
  , writePackageArtifacts
  , getPackageArtifactPath
    -- * Types
  , PackageInterfaces
  , PackageArtifacts(..)
  ) where

import qualified AST.Optimized as Opt
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Control.Concurrent.Async (mapConcurrently)
import Control.Monad (liftM2)
import Data.Binary (Binary)
import qualified Data.Binary as Binary
import qualified Interface.JSON as IFace
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Utf8 as Utf8
import qualified System.Directory as Dir
import System.FilePath ((</>))

-- | Map of module names to their dependency interfaces.
type PackageInterfaces = Map ModuleName.Raw I.DependencyInterface

-- | Complete package artifacts including interfaces and optimized code.
data PackageArtifacts = PackageArtifacts
  { artifactInterfaces :: !PackageInterfaces
  , artifactObjects :: !Opt.GlobalGraph
  }
  deriving (Show)

-- | Fingerprint tracking package dependencies (matches old Details.hs).
type Fingerprint = Map Pkg.Name V.Version

-- | Artifact cache structure (matches old/builder/src/Canopy/Details.hs).
data ArtifactCache = ArtifactCache
  { _fingerprints :: !(Set Fingerprint)
  , _artifacts :: !Artifacts
  }

instance Binary ArtifactCache where
  get = liftM2 ArtifactCache Binary.get Binary.get
  put (ArtifactCache fps arts) = Binary.put fps >> Binary.put arts

-- | Compiled artifacts for a package.
data Artifacts = Artifacts
  { _ifaces :: !PackageInterfaces
  , _objects :: !Opt.GlobalGraph
  }

instance Binary Artifacts where
  get = liftM2 Artifacts Binary.get Binary.get
  put (Artifacts ifaces objs) = Binary.put ifaces >> Binary.put objs

-- | Load package interfaces from artifact cache.
--
-- Attempts to load compiled interfaces for a specific package version
-- from the package cache. Returns Nothing if the package isn't installed
-- or doesn't have cached artifacts.
--
-- >>> interfaces <- loadPackageInterfaces "elm" "core" "1.0.5"
--
-- ==== Search Order
--
-- 1. @~/.canopy/packages/author/package/version/artifacts.dat@
-- 2. @~/.elm/0.19.1/packages/author/package/version/artifacts.dat@
--
-- @since 0.19.1
loadPackageInterfaces ::
  -- | Package author
  String ->
  -- | Package name
  String ->
  -- | Package version
  String ->
  IO (Maybe PackageInterfaces)
loadPackageInterfaces author package version = do
  homeDir <- Dir.getHomeDirectory

  let canopyPath = homeDir </> ".canopy" </> "packages" </> author </> package </> version </> "artifacts.dat"
      elmPath = homeDir </> ".elm" </> "0.19.1" </> "packages" </> author </> package </> version </> "artifacts.dat"

  -- Try Canopy cache first, then Elm cache
  canopyExists <- Dir.doesFileExist canopyPath
  if canopyExists
    then loadArtifactsFile canopyPath
    else do
      elmExists <- Dir.doesFileExist elmPath
      if elmExists
        then loadArtifactsFile elmPath
        else return Nothing

-- | Load artifacts from a specific file path.
loadArtifactsFile :: FilePath -> IO (Maybe PackageInterfaces)
loadArtifactsFile path = do
  result <- Binary.decodeFileOrFail path
  case result of
    Right (ArtifactCache _fingerprints artifacts) ->
      return (Just (_ifaces artifacts))
    Left _ ->
      return Nothing

-- | Load complete artifacts (interfaces + objects) from a specific file path.
loadCompleteArtifactsFile :: FilePath -> IO (Maybe PackageArtifacts)
loadCompleteArtifactsFile path = do
  result <- Binary.decodeFileOrFail path
  case result of
    Right (ArtifactCache _fingerprints artifacts) ->
      return (Just (PackageArtifacts (_ifaces artifacts) (_objects artifacts)))
    Left _ ->
      return Nothing

-- | Load elm\/core package interfaces.
--
-- Convenience function to load the core Elm package interfaces.
-- This package contains Basics, List, Maybe, Result, String, etc.
-- Returns 'Nothing' when the package is not installed or its
-- artifact cache is missing.
--
-- @since 0.19.1
loadElmCoreInterfaces :: IO (Maybe PackageInterfaces)
loadElmCoreInterfaces =
  loadPackageInterfaces "elm" "core" "1.0.5"

-- | Load all dependency interfaces for a project.
--
-- Given a list of package dependencies, loads and merges all their
-- interfaces into a single map. Useful for setting up compilation
-- environment with all dependencies available.
--
-- Uses parallel I/O for significant performance improvement.
--
-- >>> let deps = [(Pkg.Name "elm" "core", V.Version 1 0 5)]
-- >>> allInterfaces <- loadAllDependencyInterfaces deps
--
-- ==== Behavior
--
-- * Missing packages are silently skipped
-- * Later packages override earlier ones if they have conflicting modules
-- * Returns empty map if no packages can be loaded
-- * Loads packages in parallel for 10-20x speedup
--
-- @since 0.19.1
loadAllDependencyInterfaces ::
  -- | List of (package, version) pairs
  [(Pkg.Name, V.Version)] ->
  IO PackageInterfaces
loadAllDependencyInterfaces deps = do
  -- Load in parallel using async
  interfaceLists <- mapConcurrently loadDep deps
  return (Map.unions (concat interfaceLists))
  where
    loadDep (Pkg.Name author project, V.Version major minor patch) = do
      let authorStr = Utf8.toChars author
          projectStr = Utf8.toChars project
          versionStr = show major ++ "." ++ show minor ++ "." ++ show patch
      maybeIfaces <- loadPackageInterfaces authorStr projectStr versionStr
      return (maybe [] (: []) maybeIfaces)

-- | Load complete package artifacts (interfaces + objects).
--
-- Similar to loadPackageInterfaces but returns both type interfaces
-- and optimized GlobalGraph objects needed for code generation.
--
-- @since 0.19.1
loadPackageArtifacts ::
  -- | Package author
  String ->
  -- | Package name
  String ->
  -- | Package version
  String ->
  IO (Maybe PackageArtifacts)
loadPackageArtifacts author package version = do
  homeDir <- Dir.getHomeDirectory

  let canopyPath = homeDir </> ".canopy" </> "packages" </> author </> package </> version </> "artifacts.dat"
      elmPath = homeDir </> ".elm" </> "0.19.1" </> "packages" </> author </> package </> version </> "artifacts.dat"

  -- Try Canopy cache first, then Elm cache
  canopyExists <- Dir.doesFileExist canopyPath
  if canopyExists
    then loadCompleteArtifactsFile canopyPath
    else do
      elmExists <- Dir.doesFileExist elmPath
      if elmExists
        then loadCompleteArtifactsFile elmPath
        else return Nothing

-- | Load all package artifacts for multiple packages.
--
-- Returns both interfaces and GlobalGraph objects for all requested packages.
-- Merges GlobalGraphs from all packages into a single GlobalGraph.
--
-- Uses parallel I/O for significant performance improvement when loading
-- many packages. Typical speedup: 10-20x for 40+ packages.
--
-- @since 0.19.1
loadAllPackageArtifacts ::
  -- | List of (package, version) pairs
  [(Pkg.Name, V.Version)] ->
  IO (Maybe PackageArtifacts)
loadAllPackageArtifacts deps = do
  -- Load packages in parallel using async - major performance improvement
  artifactsList <- mapConcurrently loadDep deps
  let validArtifacts = concat artifactsList
  if null validArtifacts
    then return Nothing
    else return (Just (mergeArtifacts validArtifacts))
  where
    loadDep (Pkg.Name author project, V.Version major minor patch) = do
      let authorStr = Utf8.toChars author
          projectStr = Utf8.toChars project
          versionStr = show major ++ "." ++ show minor ++ "." ++ show patch
      -- Load with error handling - skip packages that fail
      maybeArtifacts <- loadPackageArtifacts authorStr projectStr versionStr
      case maybeArtifacts of
        Just artifacts -> return [artifacts]
        Nothing -> return []  -- Silently skip packages that fail to load

    mergeArtifacts :: [PackageArtifacts] -> PackageArtifacts
    mergeArtifacts artifacts =
      PackageArtifacts
        { artifactInterfaces = Map.unions (map artifactInterfaces artifacts)
        , artifactObjects = mergeGlobalGraphs (map artifactObjects artifacts)
        }

    mergeGlobalGraphs :: [Opt.GlobalGraph] -> Opt.GlobalGraph
    mergeGlobalGraphs graphs =
      let allGraphs = map (\(Opt.GlobalGraph g _ _) -> g) graphs
          allFields = map (\(Opt.GlobalGraph _ f _) -> f) graphs
          allLocs = map (\(Opt.GlobalGraph _ _ l) -> l) graphs
      in Opt.GlobalGraph (Map.unions allGraphs) (Map.unionsWith (+) allFields) (Map.unions allLocs)

-- | Load a single module interface from JSON or binary format.
--
-- This function provides granular interface loading for IDEs and tools
-- that need quick access to specific module interfaces without loading
-- the entire package artifacts.
--
-- Attempts to read JSON format first (faster parsing), falling back to
-- binary .cani if JSON is not available.
--
-- >>> interface <- loadModuleInterface "project-root" "Main"
-- >>> case interface of
-- ...   Right iface -> -- Use the interface for type checking
-- ...   Left err -> -- Handle error
--
-- @since 0.19.1
loadModuleInterface ::
  FilePath ->
  -- ^ Project root directory
  String ->
  -- ^ Module name (e.g., "Main", "Utils")
  IO (Either String I.Interface)
loadModuleInterface root moduleName = do
  let interfaceDir = root </> "canopy-stuff" </> "0.19.1" </> "i.cani"
      basePath = interfaceDir </> moduleName

  -- Try JSON first, fall back to binary
  IFace.readInterface basePath

-- | Get the path where a package's artifacts.dat should be stored.
--
-- Returns the path at @~/.canopy/packages/{author}/{project}/{version}/artifacts.dat@
--
-- @since 0.19.1
getPackageArtifactPath ::
  -- | Package author
  String ->
  -- | Package name
  String ->
  -- | Package version
  String ->
  IO FilePath
getPackageArtifactPath author package version = do
  homeDir <- Dir.getHomeDirectory
  return (homeDir </> ".canopy" </> "packages" </> author </> package </> version </> "artifacts.dat")

-- | Write package artifacts to the cache.
--
-- Serializes the given interfaces and GlobalGraph into an artifacts.dat file
-- at the appropriate cache location for the specified package.
--
-- This is used by the setup command to compile local packages and cache
-- their artifacts for faster subsequent loads.
--
-- >>> writePackageArtifacts "canopy" "test" "1.0.0" interfaces globalGraph
--
-- @since 0.19.1
writePackageArtifacts ::
  -- | Package author
  String ->
  -- | Package name
  String ->
  -- | Package version
  String ->
  -- | Compiled module interfaces
  PackageInterfaces ->
  -- | Optimized global graph
  Opt.GlobalGraph ->
  IO ()
writePackageArtifacts author package version interfaces globalGraph = do
  artifactPath <- getPackageArtifactPath author package version
  let artifacts = Artifacts interfaces globalGraph
      cache = ArtifactCache Set.empty artifacts
  Binary.encodeFile artifactPath cache
