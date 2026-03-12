{-# LANGUAGE OverloadedStrings #-}

-- | Kit preview server.
--
-- Serves the production build output locally for testing before
-- deployment. For static targets, serves the @build/@ directory.
-- For Node targets, starts the generated @server.js@.
--
-- @since 0.20.1
module Kit.Preview
  ( preview
  ) where

import Control.Lens ((^.))
import Kit.Types (KitPreviewFlags, kitPreviewOpen, kitPreviewPort)
import qualified Reporting.Exit.Help as Help
import qualified Reporting.Exit.Kit as ExitKit
import qualified System.Directory as Dir
import qualified System.Process as Process

-- | Start the preview server for the production build.
--
-- Checks for either a @build/server.js@ (Node target) or
-- @build/index.html@ (static target) and serves accordingly.
--
-- @since 0.20.1
preview :: KitPreviewFlags -> IO ()
preview flags = do
  hasServer <- Dir.doesFileExist "build/server.js"
  if hasServer
    then previewNode flags
    else previewStatic flags

-- | Preview a Node.js SSR build by running the server.
previewNode :: KitPreviewFlags -> IO ()
previewNode flags = do
  openIfRequested flags
  Process.callProcess "node" (["build/server.js"] ++ portEnv)
  where
    portEnv = maybe [] (\p -> ["--port", show p]) (flags ^. kitPreviewPort)

-- | Preview a static build using npx serve.
previewStatic :: KitPreviewFlags -> IO ()
previewStatic flags = do
  hasBuild <- Dir.doesDirectoryExist "build"
  if hasBuild
    then do
      openIfRequested flags
      Process.callProcess "npx" (["serve", "build"] ++ portArgs)
    else Help.toStderr (ExitKit.kitToReport ExitKit.KitNoBuild)
  where
    portArgs = maybe [] (\p -> ["-l", show p]) (flags ^. kitPreviewPort)

-- | Open browser if the flag is set.
openIfRequested :: KitPreviewFlags -> IO ()
openIfRequested flags =
  if flags ^. kitPreviewOpen
    then openBrowser (maybe 3000 id (flags ^. kitPreviewPort))
    else pure ()

-- | Open the default browser to the given port.
openBrowser :: Int -> IO ()
openBrowser port =
  Process.callProcess "xdg-open" ["http://localhost:" ++ show port]
