{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Package bootstrap and environment setup for Canopy.
--
-- The @canopy setup@ command initializes the Canopy package environment
-- by downloading the package registry and ensuring standard library
-- packages (elm\/core, elm\/html, etc.) are available for compilation.
--
-- Implementation is split across focused sub-modules:
--
-- * "Setup.PackageLocator" -- Artifact location and cache copying
-- * "Setup.LocalCompilation" -- Local package compilation
--
-- @since 0.19.1
module Setup
  ( -- * Entry Point
    run,

    -- * Types
    Flags (..),
  )
where

import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Data.Map.Strict as Map
import qualified Deps.Registry as Registry
import qualified Http
import qualified Reporting
import qualified Reporting.Exit as Exit
import Reporting.Doc.ColorQQ (c)
import Setup.LocalCompilation (compileLocalPackages)
import Setup.PackageLocator (locatePackage)
import qualified Stuff
import qualified Terminal.Print as Print
import qualified Text.PrettyPrint.ANSI.Leijen as PP

-- | Configuration flags for the setup command.
data Flags = Flags
  { _setupVerbose :: !Bool
  }

-- | Standard library packages required for Canopy development.
--
-- Listed in dependency order so that packages with zero dependencies
-- are processed first.
standardPackages :: [(Pkg.Name, Version.Version)]
standardPackages =
  [ (Pkg.core, Version.Version 1 0 5),
    (mkPkg "elm" "json", Version.Version 1 1 3),
    (mkPkg "elm" "virtual-dom", Version.Version 1 0 3),
    (mkPkg "elm" "html", Version.Version 1 0 0),
    (mkPkg "elm" "browser", Version.Version 1 0 2),
    (mkPkg "elm" "url", Version.Version 1 0 0),
    (mkPkg "elm" "http", Version.Version 2 0 0),
    (mkPkg "elm" "time", Version.Version 1 0 0),
    (mkPkg "elm" "random", Version.Version 1 0 0)
  ]

-- | Construct a package name from author and project strings.
mkPkg :: String -> String -> Pkg.Name
mkPkg author project =
  Pkg.Name (Utf8.fromChars author) (Utf8.fromChars project)

-- | Entry point for @canopy setup@.
run :: () -> Flags -> IO ()
run () flags =
  Reporting.attempt Exit.setupToReport (setup flags)

-- | Execute the setup workflow.
setup :: Flags -> IO (Either Exit.Setup ())
setup flags = do
  Print.println [c|{bold|Setting up Canopy package environment...}|]
  Print.newline
  cache <- Stuff.getPackageCache
  verboseLog flags [c|Package cache: {cyan|#{cache}}|]
  registryResult <- fetchRegistry cache flags
  case registryResult of
    Left err -> pure (Left err)
    Right registry -> do
      reportRegistryStatus registry
      results <- mapM (locatePackage cache (_setupVerbose flags)) standardPackages
      let located = length (filter id results)
          missing = length standardPackages - located
      Print.newline
      Print.println [c|{bold|Checking local Canopy packages...}|]
      localResults <- compileLocalPackages (_setupVerbose flags)
      let localCompiled = length (filter id localResults)
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
      Print.println [c|  2. Otherwise, run '{green|canopy install canopy/core}' to fetch packages directly.|]
    else do
      Print.newline
      Print.println [c|  All standard library packages are available.|]

-- | Print a 'PP.Doc' message when verbose mode is enabled.
verboseLog :: Flags -> PP.Doc -> IO ()
verboseLog flags doc =
  if _setupVerbose flags
    then Print.println doc
    else pure ()
