{-# LANGUAGE OverloadedStrings #-}

-- | Kit production build pipeline.
--
-- Orchestrates the full build process for a Kit application:
--
--   1. Scan the routes directory and generate @Routes.can@.
--   2. Detect data loaders from route modules.
--   3. Compile all Canopy source to ES modules via @canopy make@.
--   4. Pre-render static pages into HTML shells.
--   5. Bundle the application with Vite.
--
-- @since 0.19.2
module Kit.Build
  ( build
  ) where

import Control.Lens ((^.))
import Control.Monad (void)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Kit.DataLoader (DataLoader)
import qualified Kit.DataLoader as DataLoader
import Kit.Route.Types (RouteManifest (..), ScanError)
import qualified Kit.Route.Generate as Generate
import qualified Kit.Route.Scanner as Scanner
import Kit.SSG (generateStaticPages)
import qualified Kit.SSR as SSR
import Kit.Types (KitBuildFlags, kitBuildOptimize, kitBuildOutput)
import qualified Reporting.Exit.Help as Help
import qualified Reporting.Exit.Kit as ExitKit
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath
import qualified System.IO as IO
import qualified System.Process as Process

-- | Run the Kit production build pipeline.
--
-- Validates the project, generates routes, compiles Canopy source,
-- pre-renders static pages, and runs Vite build. Exits with a
-- structured error report on failure.
--
-- @since 0.19.2
build :: KitBuildFlags -> IO ()
build flags = do
  hasOutline <- Dir.doesFileExist "canopy.json"
  if hasOutline
    then runBuild flags
    else Help.toStderr (ExitKit.kitToReport ExitKit.KitNoOutline)

-- | Execute the build after outline validation.
runBuild :: KitBuildFlags -> IO ()
runBuild flags = do
  hasRoutes <- Dir.doesDirectoryExist "src/routes"
  if hasRoutes
    then executeBuildPipeline flags
    else Help.toStderr (ExitKit.kitToReport ExitKit.KitNotKitProject)

-- | Run each build phase in sequence with the route manifest.
executeBuildPipeline :: KitBuildFlags -> IO ()
executeBuildPipeline flags = do
  scanResult <- Scanner.scanRoutes "src/routes"
  case scanResult of
    Left err -> reportScanError err
    Right manifest -> buildWithManifest flags manifest

-- | Build with a validated route manifest.
buildWithManifest :: KitBuildFlags -> RouteManifest -> IO ()
buildWithManifest flags manifest = do
  writeRoutesModule manifest
  loaders <- DataLoader.detectLoaders (_rmRoutes manifest)
  writeLoaderModule loaders
  compileCanopy flags
  writeStaticPages manifest
  renderSsrPages outputDir manifest loaders
  runViteBuild flags
  where
    outputDir = maybe "build" id (flags ^. kitBuildOutput)

-- | Write the generated Routes.can module.
writeRoutesModule :: RouteManifest -> IO ()
writeRoutesModule manifest =
  TextIO.writeFile "src/Routes.can" (Generate.generateRoutesModule manifest)

-- | Write the generated Loaders.can module.
writeLoaderModule :: [DataLoader] -> IO ()
writeLoaderModule loaders =
  TextIO.writeFile "src/Loaders.can" (DataLoader.generateLoaderModule loaders)

-- | Report a route scanning error.
reportScanError :: ScanError -> IO ()
reportScanError err =
  IO.hPutStrLn IO.stderr ("Route scan error: " <> show err)

-- | Compile Canopy source to ES modules.
compileCanopy :: KitBuildFlags -> IO ()
compileCanopy flags =
  Process.callProcess "canopy" (buildMakeArgs flags)

-- | Build the argument list for @canopy make@.
buildMakeArgs :: KitBuildFlags -> [String]
buildMakeArgs flags =
  ["make", "--output-format=esm"] ++ optimizeArg ++ outputArg
  where
    optimizeArg = if flags ^. kitBuildOptimize then ["--optimize"] else []
    outputArg = maybe [] (\o -> ["--output=" ++ o]) (flags ^. kitBuildOutput)

-- | Generate and write HTML shells for all static pages.
writeStaticPages :: RouteManifest -> IO ()
writeStaticPages manifest = do
  Dir.createDirectoryIfMissing True "build"
  void (Map.traverseWithKey writeStaticPage (generateStaticPages manifest))

-- | Pre-render SSR pages for routes with static data loaders.
renderSsrPages :: FilePath -> RouteManifest -> [DataLoader] -> IO ()
renderSsrPages outputDir manifest loaders =
  SSR.renderStaticRoutes outputDir manifest loaders

-- | Write a single static HTML page to disk.
writeStaticPage :: FilePath -> Text.Text -> IO ()
writeStaticPage path content = do
  Dir.createDirectoryIfMissing True (FilePath.takeDirectory fullPath)
  TextIO.writeFile fullPath content
  where
    fullPath = "build/" ++ path

-- | Run the Vite bundler for production output.
runViteBuild :: KitBuildFlags -> IO ()
runViteBuild flags =
  Process.callProcess "npx" (["vite", "build"] ++ outDirArg)
  where
    outDirArg = maybe [] (\o -> ["--outDir", o]) (flags ^. kitBuildOutput)
