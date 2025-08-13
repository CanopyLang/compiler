{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Socket-based file watching for development server.
--
-- This module provides socket-based file monitoring functionality
-- for the development server. It enables real-time file change
-- detection to support hot reloading during development.
--
-- @since 0.19.1
module Develop.Socket (watchFile) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Exception (SomeException, catch)
import qualified Data.ByteString.Char8 as BS
import qualified Network.WebSockets as WS
import qualified System.FSNotify as Notify
import qualified System.FSNotify.Devel as Notify

watchFile :: FilePath -> WS.PendingConnection -> IO ()
watchFile _watchedFile pendingConnection =
  do
    connection <- WS.acceptRequest pendingConnection

    Notify.withManager $ \mgmt ->
      do
        stop1 <- Notify.treeExtAny mgmt "." ".can" print
        stop2 <- Notify.treeExtAny mgmt "." ".canopy" print
        stop3 <- Notify.treeExtAny mgmt "." ".elm" print
        tend connection
        stop1
        stop2
        stop3

tend :: WS.Connection -> IO ()
tend connection =
  let pinger :: Integer -> IO a
      pinger n =
        do
          threadDelay (5 * 1000 * 1000)
          WS.sendPing connection (BS.pack (show n))
          pinger (n + 1)

      receiver :: IO ()
      receiver =
        do
          _ <- WS.receiveDataMessage connection
          receiver

      shutdown :: SomeException -> IO ()
      shutdown _ =
        return ()
   in do
        _pid <- forkIO (receiver `catch` shutdown)
        pinger 1 `catch` shutdown
