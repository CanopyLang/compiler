{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Embedded HTTP server for browser test execution.
--
-- Provides a minimal file-serving HTTP server that serves compiled
-- application files during browser test runs. Uses the Snap framework
-- (already a dependency for the development server).
--
-- == Lifecycle
--
-- @
-- port   <- findAvailablePort
-- server <- startTestServer appDir port
-- -- ... run tests ...
-- stopTestServer server
-- @
--
-- The server binds to @127.0.0.1@ only (localhost) and suppresses
-- all access\/error logging for clean test output.
--
-- @since 0.19.1
module Test.Server
  ( -- * Types
    TestServer,
    ServerPort (..),
    ServerError (..),

    -- * Lifecycle
    startTestServer,
    stopTestServer,

    -- * Port Discovery
    findAvailablePort,

    -- * Lenses
    serverPort,
    serverDir,
  )
where

import Control.Concurrent (ThreadId)
import Control.Lens (makeLenses, (^.))
import Data.Word (Word16)
import qualified Control.Concurrent as Concurrent
import qualified Control.Exception as Exception
import qualified Network.Socket as Socket
import qualified Snap.Http.Server as Server
import qualified Snap.Http.Server.Config as Config
import qualified Snap.Util.FileServe as FileServe

-- | Strongly-typed server port (valid range: 1024-65535).
newtype ServerPort = ServerPort {unServerPort :: Word16}
  deriving (Eq, Show)

-- | Errors that can occur during server operations.
data ServerError
  = -- | No available port found in the search range
    PortRangeExhausted
  | -- | Server thread died unexpectedly
    ServerCrashed
  deriving (Eq, Show)

-- | Handle to a running test server.
--
-- Created by 'startTestServer', cleaned up by 'stopTestServer'.
data TestServer = TestServer
  { _serverThread :: !ThreadId,
    _serverPort :: !ServerPort,
    _serverDir :: !FilePath
  }

makeLenses ''TestServer

-- | Find an available TCP port in range 8000-9000.
--
-- Tries each port by binding a socket and immediately closing it.
-- Returns the first port that succeeds.
--
-- @since 0.19.1
findAvailablePort :: IO (Either ServerError ServerPort)
findAvailablePort = tryPorts [8000 .. 9000]
  where
    tryPorts [] = pure (Left PortRangeExhausted)
    tryPorts (p : ps) = do
      available <- isPortAvailable p
      if available
        then pure (Right (ServerPort (fromIntegral p)))
        else tryPorts ps

-- | Check whether a port is available by attempting to bind it.
isPortAvailable :: Int -> IO Bool
isPortAvailable port =
  Exception.bracket openAndBind Socket.close (const (pure True))
    `Exception.catch` handleBindError
  where
    openAndBind = do
      sock <- Socket.socket Socket.AF_INET Socket.Stream Socket.defaultProtocol
      Socket.setSocketOption sock Socket.ReuseAddr 1
      Socket.bind sock (Socket.SockAddrInet (fromIntegral port) 0)
      pure sock

    handleBindError :: Exception.IOException -> IO Bool
    handleBindError _ = pure False

-- | Start an HTTP server serving files from the given directory.
--
-- Spawns a Snap server on a background thread. Waits 100ms after
-- spawning to allow the server to initialize before returning.
--
-- @since 0.19.1
startTestServer :: FilePath -> ServerPort -> IO TestServer
startTestServer appDir port = do
  threadId <- Concurrent.forkIO (runServer appDir port)
  Concurrent.threadDelay 100000
  pure
    TestServer
      { _serverThread = threadId,
        _serverPort = port,
        _serverDir = appDir
      }

-- | Run the Snap file server (called on the background thread).
runServer :: FilePath -> ServerPort -> IO ()
runServer appDir (ServerPort port) =
  Server.httpServe config (FileServe.serveDirectory appDir)
  where
    config =
      Config.setPort (fromIntegral port)
        . Config.setAccessLog Config.ConfigNoLog
        . Config.setErrorLog Config.ConfigNoLog
        . Config.setVerbose False
        . Config.setBind "127.0.0.1"
        $ Config.defaultConfig

-- | Stop the test server by killing its background thread.
--
-- @since 0.19.1
stopTestServer :: TestServer -> IO ()
stopTestServer server =
  Concurrent.killThread (server ^. serverThread)
