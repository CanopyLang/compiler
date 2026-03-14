
-- | File system watcher with event debouncing.
--
-- This module provides functionality to watch files and directories
-- for changes and trigger actions when modifications occur. Events
-- are debounced to prevent redundant handler invocations when a
-- single save produces multiple file system events (content write,
-- metadata update, timestamp change).
--
-- == Debouncing Strategy
--
-- Each incoming event resets a timer. The handler fires only after
-- the debounce window expires with no new events. This coalesces
-- rapid-fire events (common with editors) into a single handler call.
--
-- @since 0.19.1
module Watch
  ( -- * File Watching
    files,
    file,
  )
where

import qualified Control.Concurrent as Concurrent
import qualified Control.Exception as Exception
import qualified Control.Monad as Monad
import Data.IORef (IORef)
import qualified Data.IORef as IORef
import qualified Data.Foldable as Foldable
import qualified Data.Time.Clock as Time
import qualified System.Directory as Directory
import System.FSNotify (Event)
import qualified System.FSNotify as FSNotify
import qualified System.FilePath as FilePath
import qualified System.IO.Error as IOError

-- | Watch multiple file paths for changes with debouncing.
--
-- Monitors the parent directories of all specified files and triggers
-- the provided handler when any monitored file changes. Events are
-- debounced to coalesce rapid-fire file system notifications.
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

-- | Watch a single file for changes with debouncing.
--
-- Monitors the parent directory of the specified file and triggers
-- the handler after a 200ms debounce window expires with no new events.
-- This prevents redundant handler calls when editors produce multiple
-- file system events for a single save operation.
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

  dirExists <- Directory.doesDirectoryExist watchDir
  if not dirExists
    then IOError.ioError (IOError.mkIOError IOError.doesNotExistErrorType "Watch.file" Nothing (Just watchDir))
    else
      FSNotify.withManager (startWatching watchDir)
  where
    startWatching dir mgr = do
      lastEventRef <- IORef.newIORef Nothing
      setupWatcher dir mgr lastEventRef
      runDebounceLoop lastEventRef

    setupWatcher dir mgr lastEventRef =
      Monad.void (FSNotify.watchTree mgr dir acceptAll (recordEvent lastEventRef))

    acceptAll = const True

    -- | Record the event and its timestamp for debouncing.
    recordEvent :: IORef (Maybe (Event, Time.UTCTime)) -> Event -> IO ()
    recordEvent ref event = do
      now <- Time.getCurrentTime
      IORef.writeIORef ref (Just (event, now))

    -- | Poll loop that fires the handler after the debounce window expires.
    runDebounceLoop :: IORef (Maybe (Event, Time.UTCTime)) -> IO ()
    runDebounceLoop lastEventRef =
      Exception.handle handleThreadKilled (Monad.forever pollOnce)
      where
        pollOnce = do
          Concurrent.threadDelay pollIntervalMicros
          maybeEvent <- IORef.readIORef lastEventRef
          case maybeEvent of
            Nothing -> return ()
            Just (event, eventTime) -> do
              now <- Time.getCurrentTime
              let elapsed = Time.diffUTCTime now eventTime
              Monad.when (elapsed >= debounceSeconds) $ do
                IORef.writeIORef lastEventRef Nothing
                handleEvent event

    handleThreadKilled Exception.ThreadKilled = return ()
    handleThreadKilled ex = Exception.throwIO ex

-- | Debounce window: 200ms.
--
-- Events within this window are coalesced. The handler fires only
-- after no new events arrive for this duration.
debounceSeconds :: Time.NominalDiffTime
debounceSeconds = 0.2

-- | Poll interval: 50ms.
--
-- How frequently we check whether the debounce window has expired.
-- Shorter intervals give more responsive debouncing at slightly
-- higher CPU cost (negligible for a poll-based watcher).
pollIntervalMicros :: Int
pollIntervalMicros = 50000
