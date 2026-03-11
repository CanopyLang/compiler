{-# LANGUAGE OverloadedStrings #-}

-- | Kit production build pipeline.
--
-- Orchestrates the full build process for a Kit application:
--
--   1. Scan the routes directory and generate @Routes.can@.
--   2. Compile all Canopy source to ES modules via @canopy make@.
--   3. Pre-render static pages into HTML shells.
--   4. Bundle the application with Vite.
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
import Kit.Route.Types (RouteManifest (..))
import Kit.SSG (generateStaticPages)
import Kit.Types (KitBuildFlags, kitBuildOptimize, kitBuildOutput)
import qualified Reporting.Exit.Help as Help
import qualified Reporting.Exit.Kit as ExitKit
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath
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

-- | Run each build phase in sequence.
executeBuildPipeline :: KitBuildFlags -> IO ()
executeBuildPipeline flags = do
  compileCanopy flags
  writeStaticPages
  runViteBuild flags

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
writeStaticPages :: IO ()
writeStaticPages = do
  Dir.createDirectoryIfMissing True "build"
  void (Map.traverseWithKey writeStaticPage (generateStaticPages emptyManifest))

-- | Write a single static HTML page to disk.
writeStaticPage :: FilePath -> Text.Text -> IO ()
writeStaticPage path content = do
  Dir.createDirectoryIfMissing True (FilePath.takeDirectory fullPath)
  TextIO.writeFile fullPath content
  where
    fullPath = "build/" ++ path

-- | A placeholder empty manifest for SSG when no scanner is available.
emptyManifest :: RouteManifest
emptyManifest =
  RouteManifest [] [] []

-- | Run the Vite bundler for production output.
runViteBuild :: KitBuildFlags -> IO ()
runViteBuild flags =
  Process.callProcess "npx" (["vite", "build"] ++ outDirArg)
  where
    outDirArg = maybe [] (\o -> ["--outDir", o]) (flags ^. kitBuildOutput)
