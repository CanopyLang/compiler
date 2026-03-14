{-# LANGUAGE OverloadedStrings #-}

-- | Kit development server.
--
-- Reads the project configuration, scans the routes directory, generates
-- the @Routes@ and @Loaders@ modules, and starts a Vite dev server.
-- A filesystem watcher monitors the routes directory and regenerates
-- both modules whenever routes are added, removed, or renamed.
--
-- @since 0.19.2
module Kit.Dev
  ( dev
  ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (newEmptyMVar, takeMVar)
import Control.Lens ((^.))
import qualified Control.Monad as Monad
import qualified Data.Text.IO as TextIO
import qualified Kit.DataLoader as DataLoader
import qualified Kit.Route.Generate as Generate
import Kit.Route.Types (RouteManifest (..))
import qualified Kit.Route.Scanner as Scanner
import Kit.Types (KitDevFlags, kitDevOpen, kitDevPort)
import qualified Reporting.Exit.Help as Help
import qualified Reporting.Exit.Kit as ExitKit
import qualified System.Directory as Dir
import qualified System.FSNotify as FSNotify
import qualified System.IO as IO
import qualified System.Process as Process

-- | Start the Kit development server.
--
-- Validates that the project is a Kit project, scans routes, generates
-- the @Routes.can@ and @Loaders.can@ modules, starts a file watcher,
-- and launches Vite.
--
-- @since 0.19.2
dev :: KitDevFlags -> IO ()
dev flags = do
  hasOutline <- Dir.doesFileExist "canopy.json"
  if hasOutline
    then startDevServer flags
    else Help.toStderr (ExitKit.kitToReport ExitKit.KitNoOutline)

-- | Start the development server after validation.
startDevServer :: KitDevFlags -> IO ()
startDevServer flags = do
  hasRoutes <- Dir.doesDirectoryExist "src/routes"
  if hasRoutes
    then runDevPipeline flags
    else Help.toStderr (ExitKit.kitToReport ExitKit.KitNotKitProject)

-- | Run the route generation, file watcher, and Vite dev server.
runDevPipeline :: KitDevFlags -> IO ()
runDevPipeline flags = do
  generateAllModules
  Monad.void (forkIO (watchRoutes "src/routes"))
  openBrowserIfRequested flags
  runViteDev flags

-- | Generate Routes.can and Loaders.can from the routes directory.
generateAllModules :: IO ()
generateAllModules = do
  scanResult <- Scanner.scanRoutes "src/routes"
  case scanResult of
    Left err -> IO.hPutStrLn IO.stderr ("Route scan error: " <> show err)
    Right manifest -> writeGeneratedModules manifest

-- | Write generated Routes.can and Loaders.can modules.
writeGeneratedModules :: RouteManifest -> IO ()
writeGeneratedModules manifest = do
  TextIO.writeFile "src/Routes.can" (Generate.generateRoutesModule manifest)
  loaders <- DataLoader.detectLoadersDev (_rmRoutes manifest)
  TextIO.writeFile "src/Loaders.can" (DataLoader.generateLoaderModule loaders)

-- | Watch the routes directory for changes and regenerate modules.
--
-- Monitors @src\/routes\/@ for file additions, removals, and renames.
-- On any change to @page.can@, @layout.can@, or @error.can@ files,
-- regenerates Routes.can and Loaders.can to trigger Vite HMR.
--
-- @since 0.20.1
watchRoutes :: FilePath -> IO ()
watchRoutes routesDir =
  FSNotify.withManager (startWatcher routesDir)

-- | Start the filesystem watcher within a manager.
startWatcher :: FilePath -> FSNotify.WatchManager -> IO ()
startWatcher routesDir manager = do
  Monad.void (FSNotify.watchTree manager routesDir isRouteFile handleRouteChange)
  blockForever

-- | Block the current thread indefinitely.
--
-- Uses an empty MVar to block without consuming stdin,
-- which is more robust when stdin is not connected.
blockForever :: IO ()
blockForever = newEmptyMVar >>= takeMVar

-- | Check if a filesystem event is for a route-relevant file.
isRouteFile :: FSNotify.Event -> Bool
isRouteFile event =
  isRelevantFile (FSNotify.eventPath event)

-- | Check if a file path is a route-relevant file.
isRelevantFile :: FilePath -> Bool
isRelevantFile path =
  any (`elem` suffixes) [takeFileName path]
  where
    suffixes = ["page.can", "layout.can", "error.can"]
    takeFileName = reverse . takeWhile (/= '/') . reverse

-- | Handle a route file change by regenerating modules and triggering HMR.
handleRouteChange :: FSNotify.Event -> IO ()
handleRouteChange _event = do
  IO.hPutStrLn IO.stderr "[kit] Routes changed, regenerating..."
  generateAllModules
  touchHmrSentinel

-- | Touch the HMR sentinel file so Vite detects a change.
--
-- The Canopy Vite plugin watches @.canopy-hmr-trigger@ alongside
-- @.can@ files. Touching this file after route regeneration ensures
-- Vite triggers a full reload even though the changed files are
-- generated @.can@ modules that Vite may not watch directly.
touchHmrSentinel :: IO ()
touchHmrSentinel =
  writeFile ".canopy-hmr-trigger" ""

-- | Open a browser to the dev server URL if the @--open@ flag is set.
openBrowserIfRequested :: KitDevFlags -> IO ()
openBrowserIfRequested flags =
  if flags ^. kitDevOpen
    then openBrowser (resolvePort (flags ^. kitDevPort))
    else pure ()

-- | Resolve the port number, defaulting to 5173 if unspecified.
resolvePort :: Maybe Int -> Int
resolvePort = maybe 5173 id

-- | Open the default browser to the given port.
openBrowser :: Int -> IO ()
openBrowser port =
  Process.callProcess "xdg-open" ["http://localhost:" ++ show port]

-- | Start the Vite development server with the configured port.
runViteDev :: KitDevFlags -> IO ()
runViteDev flags =
  Process.callProcess "npx" ("vite" : portArgs)
  where
    portArgs = maybe [] (\p -> ["--port", show p]) (flags ^. kitDevPort)
