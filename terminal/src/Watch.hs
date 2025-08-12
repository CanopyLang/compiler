{-# OPTIONS_GHC -Wall #-}

-- | File system watcher for monitoring source file changes.
--
-- This module provides functionality to watch files and directories
-- for changes and trigger actions when modifications occur.
--
-- @since 0.19.1
module Watch
  ( -- * File Watching
    files,
    file,
  )
where

import qualified Control.Concurrent as Concurrent
import Control.Monad (void)
import qualified Control.Monad as Monad
import qualified Data.Foldable as Foldable
import System.FSNotify (Event)
import qualified System.FSNotify as FSNotify
import qualified System.FilePath as FilePath

-- | Watch multiple file paths for changes.
--
-- Monitors the parent directories of all specified files and triggers
-- the provided handler when any monitored file changes.
--
-- ==== Examples
--
-- >>> files print ["src/Main.elm", "src/Utils.elm"]
-- -- Watches both files and prints events to stdout
--
-- >>> files (\event -> putStrLn ("Changed: " ++ show event)) paths
-- -- Custom event handler
--
-- ==== Notes
--
-- * Watches parent directories to catch file creation/deletion
-- * Handler is called for all events in watched directories
-- * Runs indefinitely until interrupted
--
-- @since 0.19.1
files ::
  -- | Event handler called on file changes
  (Event -> IO ()) ->
  -- | List of file paths to monitor
  [FilePath] ->
  IO ()
files handleEvent =
  Foldable.traverse_ (file handleEvent)

-- | Watch a single file for changes.
--
-- Monitors the parent directory of the specified file and triggers
-- the handler when any file in that directory changes.
--
-- ==== Examples
--
-- >>> file print "src/Main.elm"
-- -- Watches Main.elm and prints events
--
-- >>> file (\e -> putStrLn "Config changed!") "config.json"
-- -- Custom notification on config changes
--
-- ==== Implementation Notes
--
-- * Uses FSNotify for cross-platform file watching
-- * Watches entire parent directory for efficiency
-- * Keeps thread alive with periodic sleep
--
-- @since 0.19.1
file ::
  -- | Event handler called on changes
  (Event -> IO ()) ->
  -- | File path to monitor
  FilePath ->
  IO ()
file handleEvent path =
  FSNotify.withManager startWatching
  where
    startWatching mgr =
      setupWatcher mgr >> keepAlive
    setupWatcher mgr =
      void (FSNotify.watchTree mgr watchDir acceptAll handleEvent)
    watchDir = FilePath.takeDirectory path
    acceptAll = const True
    keepAlive = Monad.forever (Concurrent.threadDelay delayMicroseconds)
    delayMicroseconds = 1000000 -- 1 second
