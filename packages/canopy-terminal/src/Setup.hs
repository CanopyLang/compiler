{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE QuasiQuotes #-}
{-# OPTIONS_GHC -Wall #-}

-- | Package bootstrap and environment setup for Canopy.
--
-- The @canopy setup@ command initializes the Canopy package environment
-- by downloading the package registry and ensuring standard library
-- packages (elm\/core, elm\/html, etc.) are available for compilation.
--
-- == Package Resolution Strategy
--
-- Canopy resolves package artifacts in this order:
--
-- 1. @~\/.canopy\/packages\/{author}\/{project}\/{version}\/artifacts.dat@
-- 2. @~\/.elm\/0.19.1\/packages\/{author}\/{project}\/{version}\/artifacts.dat@
--
-- The setup command checks both locations and copies artifacts from
-- the Elm cache when they are missing from the Canopy cache.
--
-- == Standard Library Packages
--
-- The following packages are required for most Canopy projects:
--
-- * @elm\/core@ 1.0.5 — Foundation types (List, Maybe, Result, String, etc.)
-- * @elm\/json@ 1.1.3 — JSON encoding and decoding
-- * @elm\/html@ 1.0.0 — HTML generation
-- * @elm\/virtual-dom@ 1.0.3 — Virtual DOM diffing (dependency of html)
-- * @elm\/browser@ 1.0.2 — Browser applications
-- * @elm\/url@ 1.0.0 — URL parsing
-- * @elm\/http@ 2.0.0 — HTTP requests
-- * @elm\/time@ 1.0.0 — Time and date handling
-- * @elm\/random@ 1.0.0 — Random number generation
--
-- @since 0.19.1
module Setup
  ( -- * Entry Point
    run,

    -- * Types
    Flags (..),
  )
where

import qualified Build.Artifacts as Build
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import qualified Compiler
import Control.Exception (IOException)
import qualified Control.Exception as Exception
import qualified Data.Map.Strict as Map
import qualified Data.NonEmptyList as NE
import qualified Data.Utf8 as Utf8
import qualified Deps.Registry as Registry
import qualified Http
import qualified PackageCache
import qualified Reporting
import qualified Reporting.Exit as Exit
import Reporting.Doc.ColorQQ (c)
import qualified Stuff
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified Terminal.Print as Print
import qualified Text.PrettyPrint.ANSI.Leijen as P

-- | Configuration flags for the setup command.
data Flags = Flags
  { _setupVerbose :: !Bool
  }

-- | Standard library packages required for Canopy development.
--
-- Listed in dependency order so that packages with zero dependencies
-- are processed first. Each entry is @(package, version)@.
standardPackages :: [(Pkg.Name, V.Version)]
standardPackages =
  [ (Pkg.core, V.Version 1 0 5)
  , (mkPkg "elm" "json", V.Version 1 1 3)
  , (mkPkg "elm" "virtual-dom", V.Version 1 0 3)
  , (mkPkg "elm" "html", V.Version 1 0 0)
  , (mkPkg "elm" "browser", V.Version 1 0 2)
  , (mkPkg "elm" "url", V.Version 1 0 0)
  , (mkPkg "elm" "http", V.Version 2 0 0)
  , (mkPkg "elm" "time", V.Version 1 0 0)
  , (mkPkg "elm" "random", V.Version 1 0 0)
  ]

-- | Construct a package name from author and project strings.
mkPkg :: String -> String -> Pkg.Name
mkPkg author project =
  Pkg.Name (Utf8.fromChars author) (Utf8.fromChars project)

-- | Entry point for @canopy setup@.
--
-- Orchestrates the full bootstrap sequence:
--
-- 1. Create the Canopy package cache directory
-- 2. Fetch and cache the package registry
-- 3. Locate or copy standard library artifacts
-- 4. Report results to the user
run :: () -> Flags -> IO ()
run () flags =
  Reporting.attempt Exit.setupToReport (setup flags)

-- | Execute the setup workflow.
setup :: Flags -> IO (Either Exit.Setup ())
setup flags = do
  Print.println [c|{bold|Setting up Canopy package environment...}|]
  Print.newline

  -- Step 1: Create package cache
  cache <- Stuff.getPackageCache
  verboseLog flags [c|Package cache: {cyan|#{cache}}|]

  -- Step 2: Fetch registry
  registryResult <- fetchRegistry cache flags
  case registryResult of
    Left err -> pure (Left err)
    Right registry -> do
      reportRegistryStatus registry

      -- Step 3: Locate standard packages
      results <- mapM (locatePackage cache flags) standardPackages
      let located = length (filter id results)
          missing = length standardPackages - located

      -- Step 4: Compile local Canopy packages
      Print.newline
      Print.println [c|{bold|Checking local Canopy packages...}|]
      localResults <- compileLocalPackages flags
      let localCompiled = length (filter id localResults)

      -- Step 5: Report summary
      Print.newline
      reportSummary located missing localCompiled
      pure (Right ())

-- | Fetch the package registry from the network, falling back to cache.
fetchRegistry :: FilePath -> Flags -> IO (Either Exit.Setup Registry.Registry)
fetchRegistry cache flags = do
  verboseLog flags [c|Fetching package registry...|]
  manager <- Http.getManager
  result <- Registry.latest manager Map.empty cache cache
  case result of
    Right registry -> do
      Print.println [c|  Registry: {green|cached}|]
      pure (Right registry)
    Left err -> do
      Print.println [c|  Registry: {red|fetch failed (#{err})}|]
      cached <- Registry.read cache
      case cached of
        Just registry -> do
          Print.println [c|  Registry: {yellow|using cached version}|]
          pure (Right registry)
        Nothing ->
          pure (Left (Exit.SetupRegistryFailed err))

-- | Report how many packages the registry knows about.
reportRegistryStatus :: Registry.Registry -> IO ()
reportRegistryStatus (Registry.Registry count _) =
  let countStr = show count
  in Print.println [c|  Registry: #{countStr} packages indexed|]

-- | Locate a package's artifacts, copying from Elm cache if necessary.
--
-- Returns True if artifacts are available after this call.
locatePackage :: FilePath -> Flags -> (Pkg.Name, V.Version) -> IO Bool
locatePackage _cache flags (pkg, version) = do
  homeDir <- Dir.getHomeDirectory
  let (author, project) = pkgStrings pkg
      versionStr = V.toChars version
      canopyDir = homeDir </> ".canopy" </> "packages" </> author </> project </> versionStr
      canopyArtifacts = canopyDir </> "artifacts.dat"
      elmDir = homeDir </> ".elm" </> "0.19.1" </> "packages" </> author </> project </> versionStr
      elmArtifacts = elmDir </> "artifacts.dat"
      label = author <> "/" <> project <> " " <> versionStr

  -- Check Canopy cache first
  canopyExists <- Dir.doesFileExist canopyArtifacts
  if canopyExists
    then do
      Print.println [c|  #{label}: {green|ready}|]
      pure True
    else do
      -- Check Elm cache
      elmExists <- Dir.doesFileExist elmArtifacts
      if elmExists
        then copyFromElmCache flags label canopyDir canopyArtifacts elmDir
        else do
          Print.println [c|  #{label}: {red|not found}|]
          verboseLog flags [c|    Checked: {cyan|#{canopyArtifacts}}|]
          verboseLog flags [c|    Checked: {cyan|#{elmArtifacts}}|]
          pure False

-- | Copy package artifacts from the Elm cache to the Canopy cache.
copyFromElmCache :: Flags -> String -> FilePath -> FilePath -> FilePath -> IO Bool
copyFromElmCache flags label canopyDir canopyArtifacts elmDir = do
  verboseLog flags [c|    Copying from Elm cache: {cyan|#{elmDir}}|]
  Dir.createDirectoryIfMissing True canopyDir
  let elmArtifacts = elmDir </> "artifacts.dat"
  copyResult <- safeCopyFile elmArtifacts canopyArtifacts
  case copyResult of
    Right () -> do
      -- Also copy source files if present
      copyPackageSource flags elmDir canopyDir
      Print.println [c|  #{label}: {yellow|copied from Elm cache}|]
      pure True
    Left err -> do
      Print.println [c|  #{label}: {red|copy failed (#{err})}|]
      pure False

-- | Copy package source files (src/, elm.json) from one directory to another.
copyPackageSource :: Flags -> FilePath -> FilePath -> IO ()
copyPackageSource flags srcDir destDir = do
  -- Copy elm.json / canopy.json if present
  copyIfExists flags (srcDir </> "elm.json") (destDir </> "elm.json")
  -- Copy src directory if present
  let srcSrcDir = srcDir </> "src"
  srcExists <- Dir.doesDirectoryExist srcSrcDir
  if srcExists
    then do
      verboseLog flags [c|    Copying source: {cyan|#{srcSrcDir}}|]
      copyDirectoryRecursive srcSrcDir (destDir </> "src")
    else pure ()

-- | Copy a file only if the source exists.
copyIfExists :: Flags -> FilePath -> FilePath -> IO ()
copyIfExists flags src dest = do
  exists <- Dir.doesFileExist src
  if exists
    then do
      verboseLog flags [c|    Copying: {cyan|#{src}}|]
      _ <- safeCopyFile src dest
      pure ()
    else pure ()

-- | Copy a file with error handling.
safeCopyFile :: FilePath -> FilePath -> IO (Either String ())
safeCopyFile src dest = do
  result <- tryIO (Dir.copyFile src dest)
  pure (either (Left . show) Right result)

-- | Copy a directory recursively.
copyDirectoryRecursive :: FilePath -> FilePath -> IO ()
copyDirectoryRecursive src dest = do
  Dir.createDirectoryIfMissing True dest
  contents <- Dir.listDirectory src
  mapM_ (copyEntry src dest) contents

-- | Copy a single directory entry (file or subdirectory).
copyEntry :: FilePath -> FilePath -> FilePath -> IO ()
copyEntry srcBase destBase name = do
  let srcPath = srcBase </> name
      destPath = destBase </> name
  isDir <- Dir.doesDirectoryExist srcPath
  if isDir
    then copyDirectoryRecursive srcPath destPath
    else do
      _ <- safeCopyFile srcPath destPath
      pure ()

-- | Compile all local Canopy packages that have source but no artifacts.
--
-- Scans @~/.canopy/packages/canopy/@ for packages with source directories
-- but missing artifacts.dat, compiles them, and writes the artifacts.
compileLocalPackages :: Flags -> IO [Bool]
compileLocalPackages flags = do
  homeDir <- Dir.getHomeDirectory
  let canopyPkgDir = homeDir </> ".canopy" </> "packages" </> "canopy"

  -- Check if canopy packages directory exists
  exists <- Dir.doesDirectoryExist canopyPkgDir
  if not exists
    then pure []
    else do
      -- List all packages in canopy/
      packages <- Dir.listDirectory canopyPkgDir
      results <- mapM (compileLocalPackage flags canopyPkgDir) packages
      pure (concat results)

-- | Compile a single local Canopy package if needed.
compileLocalPackage :: Flags -> FilePath -> String -> IO [Bool]
compileLocalPackage flags canopyPkgDir packageName = do
  let pkgDir = canopyPkgDir </> packageName

  -- List all versions
  versionDirs <- tryListDirectory pkgDir
  mapM (compilePackageVersion flags packageName pkgDir) versionDirs

-- | Try to list a directory, returning empty list on failure.
tryListDirectory :: FilePath -> IO [FilePath]
tryListDirectory dir = do
  isDir <- Dir.doesDirectoryExist dir
  if isDir
    then Dir.listDirectory dir
    else pure []

-- | Compile a specific version of a package if it has source but no artifacts.
compilePackageVersion :: Flags -> String -> FilePath -> String -> IO Bool
compilePackageVersion flags packageName pkgDir versionStr = do
  let versionDir = pkgDir </> versionStr
      artifactsPath = versionDir </> "artifacts.dat"
      canopyJsonPath = versionDir </> "canopy.json"
      srcDir = versionDir </> "src"
      label = "canopy/" <> packageName <> " " <> versionStr

  -- Check if artifacts already exist
  artifactsExist <- Dir.doesFileExist artifactsPath
  if artifactsExist
    then do
      Print.println [c|  #{label}: {green|ready}|]
      pure True
    else do
      -- Check if source exists
      canopyJsonExists <- Dir.doesFileExist canopyJsonPath
      srcExists <- Dir.doesDirectoryExist srcDir
      if canopyJsonExists && srcExists
        then do
          Print.println [c|  #{label}: {yellow|compiling from source...}|]
          result <- compilePackageFromSource flags "canopy" packageName versionStr versionDir
          case result of
            Right () -> do
              Print.println [c|  #{label}: {green|compiled}|]
              pure True
            Left err -> do
              Print.println [c|  #{label}: {red|compilation failed}|]
              verboseLog flags [c|    Error: #{err}|]
              pure False
        else do
          Print.println [c|  #{label}: {red|no source found}|]
          pure False

-- | Compile a package from source and write its artifacts.
compilePackageFromSource :: Flags -> String -> String -> String -> FilePath -> IO (Either String ())
compilePackageFromSource _flags author packageName versionStr pkgDir = do
  -- Read canopy.json to get exposed modules using proper Aeson parsing
  maybeOutline <- Outline.read pkgDir
  case maybeOutline of
    Nothing -> pure (Left "Failed to read or parse canopy.json")
    Just outline ->
      case outline of
        Outline.App _ -> pure (Left "Expected package outline, found application outline")
        Outline.Pkg pkgOutline ->
          case exposedToNonEmpty (Outline._pkgExposed pkgOutline) of
            Nothing -> pure (Left "No exposed modules found in canopy.json")
            Just exposedModules -> do
              -- Compile the package
              let pkg = mkPkg author packageName
                  srcDir = pkgDir </> "src"
              compileResult <- Compiler.compileFromExposed pkg False pkgDir [Compiler.AbsoluteSrcDir srcDir] exposedModules
              case compileResult of
                Left err -> pure (Left (show err))
                Right artifacts -> do
                  -- Convert Build.Artifacts to PackageInterfaces
                  let interfaces = buildArtifactsToInterfaces artifacts
                      globalGraph = Build._artifactsGlobalGraph artifacts
                  -- Write artifacts
                  PackageCache.writePackageArtifacts author packageName versionStr interfaces globalGraph
                  pure (Right ())

-- | Convert Build.Artifacts to PackageInterfaces (Map ModuleName.Raw I.DependencyInterface).
buildArtifactsToInterfaces :: Build.Artifacts -> PackageCache.PackageInterfaces
buildArtifactsToInterfaces artifacts =
  Map.fromList
    [ (name, I.Public iface)
    | Build.Fresh name iface _ <- Build._artifactsModules artifacts
    ]

-- | Convert Exposed to NonEmpty list of module names.
--
-- Flattens ExposedList or ExposedDict into a non-empty list.
exposedToNonEmpty :: Outline.Exposed -> Maybe (NE.List ModuleName.Raw)
exposedToNonEmpty exposed =
  case Outline.flattenExposed exposed of
    [] -> Nothing
    (x:xs) -> Just (NE.List x xs)

-- | Report the final setup summary.
reportSummary :: Int -> Int -> Int -> IO ()
reportSummary located missing localCompiled = do
  let locatedStr = show located
      missingStr = show missing
      localStr = show localCompiled
  Print.println [c|{green|Setup complete.}|]
  Print.println [c|  {green|#{locatedStr}} standard packages ready|]
  if localCompiled > 0
    then Print.println [c|  {green|#{localStr}} local packages compiled|]
    else pure ()
  if missing > 0
    then do
      Print.println [c|  #{missingStr} packages not found|]
      Print.newline
      Print.println [c|To install missing packages:|]
      Print.println [c|  1. If you previously used Elm, Canopy can import cached artifacts from ~/.elm/|]
      Print.println [c|  2. Otherwise, run '{green|canopy install elm/core}' to fetch packages directly.|]
    else do
      Print.newline
      Print.println [c|  All standard library packages are available.|]

-- | Extract author and project strings from a package name.
pkgStrings :: Pkg.Name -> (String, String)
pkgStrings (Pkg.Name author project) =
  (Utf8.toChars author, Utf8.toChars project)

-- | Print a 'P.Doc' message when verbose mode is enabled.
verboseLog :: Flags -> P.Doc -> IO ()
verboseLog flags doc =
  if _setupVerbose flags
    then Print.println doc
    else pure ()

-- | Try an IO action, catching IOExceptions.
tryIO :: IO a -> IO (Either IOException a)
tryIO = Exception.try
