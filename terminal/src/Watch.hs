module Watch (files) where

import Control.Concurrent (threadDelay)
import Control.Monad (forever, void)
import System.FSNotify
import System.FilePath

files :: [FilePath] -> (Event -> IO ()) -> IO ()
files paths handleEvent =
  void $ traverse (flip file handleEvent) paths

file :: FilePath -> (Event -> IO ()) -> IO ()
file path handleEvent = do
  withManager $ \mgr -> do
    -- start watching
    void (watchTree mgr (takeDirectory path) (const True) handleEvent)
    -- Keep the program running
    forever $ threadDelay 1000000
