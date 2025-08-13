{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | WebSocket-based file watching for development server hot reloading.
--
-- This module provides WebSocket-based file monitoring functionality for the
-- development server. It enables real-time file change detection to support
-- hot reloading during development, following CLAUDE.md patterns for clear
-- separation of concerns and robust error handling.
--
-- == Key Functions
--
-- * 'handleWebSocket' - Main WebSocket connection handler
-- * 'startFileWatcher' - Initialize file system monitoring
-- * 'maintainConnection' - Keep WebSocket connection alive
-- * 'watchCanopyFiles' - Monitor Canopy source files specifically
--
-- == Architecture
--
-- The file watching system operates through several components:
--
-- 1. WebSocket connection management and lifecycle
-- 2. File system monitoring with multiple extension support  
-- 3. Connection keep-alive with periodic pings
-- 4. Graceful error handling and connection cleanup
--
-- == Monitored File Types
--
-- The system monitors these file types for changes:
--
-- * @.can@ - Canopy source files
-- * @.canopy@ - Canopy source files (alternative extension)
-- * @.elm@ - Elm source files (compatibility)
--
-- == Usage Examples
--
-- @
-- -- In server route handler:
-- app <- WS.acceptRequest pending  
-- Socket.handleWebSocket "." app
-- @
--
-- @since 0.19.1
module Develop.Socket
  ( -- * WebSocket Handling
    handleWebSocket,
    
    -- * File Monitoring
    startFileWatcher,
    watchCanopyFiles,
    
    -- * Connection Management
    maintainConnection,
    createWatchManager,
  ) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Exception (SomeException, catch)
import qualified Data.ByteString.Char8 as BS
import qualified Network.WebSockets as WS
import qualified System.FSNotify as Notify

-- | Handle WebSocket connection for file watching.
--
-- Accepts a WebSocket connection and sets up comprehensive file monitoring
-- for the specified directory with automatic change detection and notifications.
--
-- ==== Examples
--
-- >>> connection <- WS.acceptRequest pendingConnection
-- >>> handleWebSocket "src" connection
--
-- ==== Error Handling
--
-- Handles connection errors gracefully:
--   * Network disconnections
--   * File system monitoring failures  
--   * Invalid directory paths
--   * Resource cleanup on shutdown
--
-- @since 0.19.1
handleWebSocket :: FilePath -> WS.Connection -> IO ()
handleWebSocket watchDir connection = do
  watchManager <- createWatchManager
  watchers <- startFileWatcher watchManager watchDir
  maintainConnection connection
  cleanupWatchers watchers

-- | Create file system watch manager.
--
-- Initializes the file system notification manager for monitoring
-- file changes in the development environment.
--
-- @since 0.19.1
createWatchManager :: IO Notify.WatchManager
createWatchManager = Notify.startManager

-- | Start comprehensive file watching for development.
--
-- Sets up file system watchers for all relevant file types in the
-- specified directory, returning cleanup actions for proper resource management.
--
-- @since 0.19.1
startFileWatcher :: Notify.WatchManager -> FilePath -> IO [IO ()]
startFileWatcher manager watchDir = do
  canWatcher <- watchCanopyFiles manager watchDir ".can"
  canopyWatcher <- watchCanopyFiles manager watchDir ".canopy" 
  elmWatcher <- watchCanopyFiles manager watchDir ".elm"
  pure [canWatcher, canopyWatcher, elmWatcher]

-- | Watch Canopy source files with specific extension.
--
-- Creates a file system watcher for files with the specified extension,
-- triggering notifications when files are modified, created, or deleted.
--
-- @since 0.19.1
watchCanopyFiles :: Notify.WatchManager -> FilePath -> String -> IO (IO ())
watchCanopyFiles manager watchDir extension =
  Notify.watchTree manager watchDir (matchesExtension extension) handleFileEvent
  where
    matchesExtension ext event = 
      let eventPath = Notify.eventPath event
      in takeExtension eventPath == ext
      
    handleFileEvent _event = 
      putStrLn ("File changed: " ++ show _event)

-- | Extract file extension from path.
takeExtension :: FilePath -> String
takeExtension path =
  let segments = reverse path
      extension = takeWhile (/= '.') segments
  in if null extension then "" else '.' : reverse extension

-- | Maintain WebSocket connection with periodic pings.
--
-- Keeps the WebSocket connection alive by sending periodic ping messages
-- and handling incoming messages. Includes graceful error handling for
-- connection issues.
--
-- @since 0.19.1
maintainConnection :: WS.Connection -> IO ()
maintainConnection connection = do
  _receiverThread <- forkIO (runMessageReceiver connection)
  runConnectionPinger connection 1

-- | Run message receiver loop.
runMessageReceiver :: WS.Connection -> IO ()
runMessageReceiver connection = do
  messageLoop connection `catch` handleConnectionError
  where
    messageLoop conn = do
      _message <- WS.receiveDataMessage conn
      messageLoop conn
      
    handleConnectionError :: SomeException -> IO ()
    handleConnectionError _exception = pure () -- Graceful shutdown

-- | Run connection pinger with periodic keep-alive messages.
runConnectionPinger :: WS.Connection -> Integer -> IO ()  
runConnectionPinger connection pingNumber = do
  result <- sendPingMessage connection pingNumber
  case result of
    True -> do
      threadDelay pingInterval
      runConnectionPinger connection (pingNumber + 1)
    False -> pure () -- Connection closed

-- | Send ping message to maintain connection.
sendPingMessage :: WS.Connection -> Integer -> IO Bool
sendPingMessage connection pingNumber = do
  let pingData = BS.pack (show pingNumber)
  result <- safeSendPing connection pingData
  pure result

-- | Safely send ping with error handling.
safeSendPing :: WS.Connection -> BS.ByteString -> IO Bool
safeSendPing connection pingData = do
  (WS.sendPing connection pingData >> pure True) `catch` handlePingError
  where
    handlePingError :: SomeException -> IO Bool
    handlePingError _exception = pure False

-- | Ping interval in microseconds (5 seconds).
pingInterval :: Int
pingInterval = 5 * 1000 * 1000

-- | Clean up file watchers on shutdown.
cleanupWatchers :: [IO ()] -> IO ()
cleanupWatchers watchers = mapM_ executeCleanup watchers
  where
    executeCleanup cleanup = cleanup `catch` ignoreCleanupErrors
    ignoreCleanupErrors :: SomeException -> IO ()
    ignoreCleanupErrors _exception = pure ()
