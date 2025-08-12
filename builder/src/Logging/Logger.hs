module Logging.Logger
  ( printLog,
    setLogFlag,
  )
where

import Control.Monad (when)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import GHC.IO (unsafePerformIO)

shouldLogFlag :: IORef Bool
{-# NOINLINE shouldLogFlag #-}
shouldLogFlag = unsafePerformIO (newIORef False)

setLogFlag :: Bool -> IO ()
setLogFlag = writeIORef shouldLogFlag

printLog :: String -> IO ()
printLog str =
  do
    shouldLog <- readIORef shouldLogFlag
    when shouldLog (print str)
