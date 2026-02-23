{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
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

import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Control.Exception (IOException)
import qualified Control.Exception as Exception
import qualified Data.Map.Strict as Map
import qualified Data.Utf8 as Utf8
import qualified Deps.Registry as Registry
import qualified Http
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Stuff
import qualified System.Directory as Dir
import System.FilePath ((</>))

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
  putStrLn "Setting up Canopy package environment...\n"

  -- Step 1: Create package cache
  cache <- Stuff.getPackageCache
  verboseLog flags ("Package cache: " <> cache)

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

      -- Step 4: Report summary
      putStrLn ""
      reportSummary located missing
      pure (Right ())

-- | Fetch the package registry from the network, falling back to cache.
fetchRegistry :: FilePath -> Flags -> IO (Either Exit.Setup Registry.Registry)
fetchRegistry cache flags = do
  verboseLog flags "Fetching package registry..."
  manager <- Http.getManager
  result <- Registry.latest manager Map.empty cache cache
  case result of
    Right registry -> do
      putStrLn "  Registry: cached"
      pure (Right registry)
    Left err -> do
      putStrLn ("  Registry: fetch failed (" <> err <> ")")
      cached <- Registry.read cache
      case cached of
        Just registry -> do
          putStrLn "  Registry: using cached version"
          pure (Right registry)
        Nothing ->
          pure (Left (Exit.SetupRegistryFailed err))

-- | Report how many packages the registry knows about.
reportRegistryStatus :: Registry.Registry -> IO ()
reportRegistryStatus (Registry.Registry count _) =
  putStrLn ("  Registry: " <> show count <> " packages indexed")

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
      putStrLn ("  " <> label <> ": ready")
      pure True
    else do
      -- Check Elm cache
      elmExists <- Dir.doesFileExist elmArtifacts
      if elmExists
        then copyFromElmCache flags label canopyDir canopyArtifacts elmDir
        else do
          putStrLn ("  " <> label <> ": not found")
          verboseLog flags ("    Checked: " <> canopyArtifacts)
          verboseLog flags ("    Checked: " <> elmArtifacts)
          pure False

-- | Copy package artifacts from the Elm cache to the Canopy cache.
copyFromElmCache :: Flags -> String -> FilePath -> FilePath -> FilePath -> IO Bool
copyFromElmCache flags label canopyDir canopyArtifacts elmDir = do
  verboseLog flags ("    Copying from Elm cache: " <> elmDir)
  Dir.createDirectoryIfMissing True canopyDir
  let elmArtifacts = elmDir </> "artifacts.dat"
  copyResult <- safeCopyFile elmArtifacts canopyArtifacts
  case copyResult of
    Right () -> do
      -- Also copy source files if present
      copyPackageSource flags elmDir canopyDir
      putStrLn ("  " <> label <> ": copied from Elm cache")
      pure True
    Left err -> do
      putStrLn ("  " <> label <> ": copy failed (" <> err <> ")")
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
      verboseLog flags ("    Copying source: " <> srcSrcDir)
      copyDirectoryRecursive srcSrcDir (destDir </> "src")
    else pure ()

-- | Copy a file only if the source exists.
copyIfExists :: Flags -> FilePath -> FilePath -> IO ()
copyIfExists flags src dest = do
  exists <- Dir.doesFileExist src
  if exists
    then do
      verboseLog flags ("    Copying: " <> src)
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

-- | Report the final setup summary.
reportSummary :: Int -> Int -> IO ()
reportSummary located missing = do
  putStrLn "Setup complete."
  putStrLn ("  " <> show located <> " packages ready")
  if missing > 0
    then do
      putStrLn ("  " <> show missing <> " packages not found")
      putStrLn ""
      putStrLn "To install missing packages, either:"
      putStrLn "  1. Install Elm (https://elm-lang.org) and run 'elm make' on any project"
      putStrLn "     Canopy will use Elm's cached artifacts automatically."
      putStrLn "  2. Run 'canopy install elm/core' to add packages to your project."
    else
      putStrLn "\n  All standard library packages are available."

-- | Extract author and project strings from a package name.
pkgStrings :: Pkg.Name -> (String, String)
pkgStrings (Pkg.Name author project) =
  (Utf8.toChars author, Utf8.toChars project)

-- | Print a message when verbose mode is enabled.
verboseLog :: Flags -> String -> IO ()
verboseLog flags msg =
  if _setupVerbose flags
    then putStrLn msg
    else pure ()

-- | Try an IO action, catching IOExceptions.
tryIO :: IO a -> IO (Either IOException a)
tryIO = Exception.try
