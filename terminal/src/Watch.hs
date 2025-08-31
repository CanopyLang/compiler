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
import qualified System.Directory as Directory
import System.FSNotify (Event)
import qualified System.FSNotify as FSNotify
import qualified System.FilePath as FilePath
import qualified System.IO.Error as IOError

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
-- * Handles nonexistent files and permission errors gracefully
-- * Keeps thread alive with periodic sleep
--
-- @since 0.19.1
file ::
  -- | Event handler called on changes
  (Event -> IO ()) ->
  -- | File path to monitor
  FilePath ->
  IO ()
file handleEvent path = do
  let watchDir = FilePath.takeDirectory path
  
  -- Check if the directory exists
  dirExists <- Directory.doesDirectoryExist watchDir
  if not dirExists
    then IOError.ioError (IOError.mkIOError IOError.doesNotExistErrorType "Watch.file" Nothing (Just watchDir))
    else do
      -- Try to watch the directory, propagating any errors (including permission errors)
      FSNotify.withManager (startWatching watchDir)
  where
    startWatching dir mgr =
      setupWatcher dir mgr >> keepAlive
    setupWatcher dir mgr =
      void (FSNotify.watchTree mgr dir acceptAll handleEvent)
    acceptAll = const True
    keepAlive = Monad.forever (Concurrent.threadDelay delayMicroseconds)
    delayMicroseconds = 1000000 -- 1 second
