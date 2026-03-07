{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Local Canopy package compilation during setup.
--
-- Scans @~\/.canopy\/packages\/canopy\/@ for packages with source
-- directories but missing @artifacts.dat@, compiles them, and writes
-- the resulting artifacts.
--
-- @since 0.19.1
module Setup.LocalCompilation
  ( -- * Compilation
    compileLocalPackages,
  )
where

import qualified Build.Artifacts as Build
import qualified Canopy.Data.NonEmptyList as NE
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Compiler
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified PackageCache
import Reporting.Doc.ColorQQ (c)
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified Terminal.Print as Print
import qualified Text.PrettyPrint.ANSI.Leijen as PP

-- | Compile all local Canopy packages that have source but no artifacts.
--
-- Scans @~/.canopy/packages/canopy/@ for packages with source directories
-- but missing artifacts.dat, compiles them, and writes the artifacts.
-- Packages are compiled in dependency order (topological sort) so that
-- each package's artifacts include its dependencies' FFI info.
--
-- @since 0.19.1
compileLocalPackages :: Bool -> IO [Bool]
compileLocalPackages verbose = do
  homeDir <- Dir.getHomeDirectory
  let canopyPkgDir = homeDir </> ".canopy" </> "packages" </> "canopy"
  exists <- Dir.doesDirectoryExist canopyPkgDir
  if not exists
    then pure []
    else do
      entries <- discoverPackageEntries canopyPkgDir
      sorted <- sortByDependencyOrder canopyPkgDir entries
      mapM (compileEntry verbose canopyPkgDir) sorted

-- | A discovered package entry ready for compilation.
data PackageEntry = PackageEntry
  { _entryName :: !String
  , _entryVersion :: !String
  } deriving (Eq, Ord, Show)

-- | Discover all (packageName, versionStr) entries under the canopy dir.
--
-- @since 0.19.2
discoverPackageEntries :: FilePath -> IO [PackageEntry]
discoverPackageEntries canopyPkgDir = do
  packages <- tryListDirectory canopyPkgDir
  fmap concat (mapM (discoverVersions canopyPkgDir) packages)

-- | Find all version directories for a given package.
discoverVersions :: FilePath -> String -> IO [PackageEntry]
discoverVersions canopyPkgDir packageName = do
  let pkgDir = canopyPkgDir </> packageName
  versions <- tryListDirectory pkgDir
  pure (map (PackageEntry packageName) versions)

-- | Sort package entries by dependency order using topological sort.
--
-- Reads each package's outline to discover dependencies, then sorts
-- so that dependencies compile before dependents. This ensures each
-- package's @artifacts.dat@ includes its dependencies' FFI info.
--
-- @since 0.19.2
sortByDependencyOrder :: FilePath -> [PackageEntry] -> IO [PackageEntry]
sortByDependencyOrder canopyPkgDir entries = do
  depPairs <- mapM (readEntryDeps canopyPkgDir) entries
  let depMap = Map.fromList depPairs
      known = Set.fromList (map _entryName entries)
  pure (topoSort known depMap entries)

-- | Read the local-package dependencies of one entry.
--
-- Only returns deps that are also @canopy/*@ packages (ignoring
-- external deps like @elm/*@).
--
-- @since 0.19.2
readEntryDeps :: FilePath -> PackageEntry -> IO (String, [String])
readEntryDeps canopyPkgDir (PackageEntry name ver) = do
  let versionDir = canopyPkgDir </> name </> ver
  eitherOutline <- Outline.read versionDir
  pure (name, either (const []) extractLocalDeps eitherOutline)

-- | Extract @canopy/*@ dependency names from an outline.
--
-- Only uses regular dependencies (not test dependencies) to avoid
-- circular dependency cycles (e.g. core → test → html → json → core).
extractLocalDeps :: Outline.Outline -> [String]
extractLocalDeps (Outline.Pkg o) =
  [ Utf8.toChars project
  | Pkg.Name author project <- Map.keys (Outline._pkgDeps o)
  , Utf8.toChars author == "canopy"
  ]
extractLocalDeps _ = []

-- | Topological sort of package entries by dependency order.
--
-- Iteratively emits entries whose dependencies have all been emitted,
-- breaking cycles by falling through to alphabetical order.
--
-- @since 0.19.2
topoSort :: Set.Set String -> Map.Map String [String] -> [PackageEntry] -> [PackageEntry]
topoSort known depMap = go Set.empty . List.sortOn _entryName
  where
    go _emitted [] = []
    go emitted remaining =
      case List.partition (isReady emitted) remaining of
        ([], _) -> remaining
        (ready, rest) ->
          let newEmitted = Set.union emitted (Set.fromList (map _entryName ready))
           in ready ++ go newEmitted rest
    isReady emitted (PackageEntry name _) =
      all (\d -> Set.member d emitted || not (Set.member d known)) deps
      where
        deps = maybe [] id (Map.lookup name depMap)

-- | Compile a single package entry.
compileEntry :: Bool -> FilePath -> PackageEntry -> IO Bool
compileEntry verbose canopyPkgDir (PackageEntry packageName versionStr) =
  compilePackageVersion verbose packageName (canopyPkgDir </> packageName) versionStr

-- | Try to list a directory, returning empty list on failure.
tryListDirectory :: FilePath -> IO [FilePath]
tryListDirectory dir = do
  isDir <- Dir.doesDirectoryExist dir
  if isDir
    then Dir.listDirectory dir
    else pure []

-- | Compile a specific version of a package if it has source but no artifacts.
compilePackageVersion :: Bool -> String -> FilePath -> String -> IO Bool
compilePackageVersion verbose packageName pkgDir versionStr = do
  let versionDir = pkgDir </> versionStr
      artifactsPath = versionDir </> "artifacts.dat"
      srcDir = versionDir </> "src"
      label = "canopy/" <> packageName <> " " <> versionStr
  artifactsExist <- Dir.doesFileExist artifactsPath
  if artifactsExist
    then do
      Print.println [c|  #{label}: {green|ready}|]
      pure True
    else do
      hasOutline <- hasPackageOutline versionDir
      srcExists <- Dir.doesDirectoryExist srcDir
      if hasOutline && srcExists
        then compileAndReport verbose label packageName versionStr versionDir
        else do
          Print.println [c|  #{label}: {red|no source found}|]
          pure False

-- | Check whether a package directory contains a valid outline file.
--
-- Accepts either @canopy.json@ or @elm.json@ to support both native
-- Canopy packages and packages copied from the Elm cache.
hasPackageOutline :: FilePath -> IO Bool
hasPackageOutline dir = do
  canopyExists <- Dir.doesFileExist (dir </> "canopy.json")
  if canopyExists
    then pure True
    else Dir.doesFileExist (dir </> "elm.json")

-- | Attempt compilation and report the result.
compileAndReport :: Bool -> String -> String -> String -> FilePath -> IO Bool
compileAndReport verbose label packageName versionStr versionDir = do
  Print.println [c|  #{label}: {yellow|compiling from source...}|]
  result <- compilePackageFromSource "canopy" packageName versionStr versionDir
  case result of
    Right () -> do
      Print.println [c|  #{label}: {green|compiled}|]
      pure True
    Left err -> do
      Print.println [c|  #{label}: {red|compilation failed}|]
      verboseLog verbose [c|    Error: #{err}|]
      pure False

-- | Compile a package from source and write its artifacts.
compilePackageFromSource :: String -> String -> String -> FilePath -> IO (Either String ())
compilePackageFromSource author packageName versionStr pkgDir = do
  cleanBuildCache pkgDir
  eitherOutline <- Outline.read pkgDir
  case eitherOutline of
    Left err -> pure (Left err)
    Right outline ->
      compileFromOutline author packageName versionStr pkgDir outline

-- | Remove @canopy-stuff\/@ to avoid stale lock files from previous runs.
cleanBuildCache :: FilePath -> IO ()
cleanBuildCache pkgDir = do
  let cacheDir = pkgDir </> "canopy-stuff"
  exists <- Dir.doesDirectoryExist cacheDir
  if exists
    then Dir.removeDirectoryRecursive cacheDir
    else pure ()

-- | Compile from a parsed package outline.
compileFromOutline :: String -> String -> String -> FilePath -> Outline.Outline -> IO (Either String ())
compileFromOutline _ _ _ _ (Outline.App _) = pure (Left "Expected package outline, found application outline")
compileFromOutline _ _ _ _ (Outline.Workspace _) = pure (Left "Expected package outline, found workspace outline")
compileFromOutline author packageName versionStr pkgDir (Outline.Pkg pkgOutline) =
  case exposedToNonEmpty (Outline._pkgExposed pkgOutline) of
    Nothing -> pure (Left "No exposed modules found in canopy.json")
    Just exposedModules -> do
      let pkg = mkPkg author packageName
          srcDir = pkgDir </> "src"
      compileResult <- Dir.withCurrentDirectory pkgDir
        (Compiler.compileFromExposed pkg False (Compiler.ProjectRoot pkgDir) [Compiler.AbsoluteSrcDir srcDir] exposedModules)
      case compileResult of
        Left err -> pure (Left (show err))
        Right artifacts -> do
          let interfaces = buildArtifactsToInterfaces artifacts
              globalGraph = Build._artifactsGlobalGraph artifacts
              ffiInfo = Build._artifactsFFIInfo artifacts
          PackageCache.writePackageArtifacts author packageName versionStr interfaces globalGraph ffiInfo
          pure (Right ())

-- | Convert Build.Artifacts to PackageInterfaces.
buildArtifactsToInterfaces :: Build.Artifacts -> PackageCache.PackageInterfaces
buildArtifactsToInterfaces artifacts =
  Map.fromList
    [ (name, Interface.Public iface)
    | Build.Fresh name iface _ <- Build._artifactsModules artifacts
    ]

-- | Convert Exposed to NonEmpty list of module names.
exposedToNonEmpty :: Outline.Exposed -> Maybe (NE.List ModuleName.Raw)
exposedToNonEmpty exposed =
  case Outline.flattenExposed exposed of
    [] -> Nothing
    (x:xs) -> Just (NE.List x xs)

-- | Construct a package name from author and project strings.
mkPkg :: String -> String -> Pkg.Name
mkPkg author project =
  Pkg.Name (Utf8.fromChars author) (Utf8.fromChars project)

-- | Print a 'PP.Doc' message when verbose mode is enabled.
verboseLog :: Bool -> PP.Doc -> IO ()
verboseLog verbose doc =
  if verbose
    then Print.println doc
    else pure ()
