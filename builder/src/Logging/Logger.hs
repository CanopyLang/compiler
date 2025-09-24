module Logging.Logger
  ( printLog,
    setLogFlag,
  )
where

-- NOTE: Global logging state removed due to unsafePerformIO causing MVar deadlocks
-- Logging is now disabled by default to prevent threading issues during compilation

setLogFlag :: Bool -> IO ()
setLogFlag _flag = pure () -- No-op since global state was causing MVar deadlocks

printLog :: String -> IO ()
printLog _str = pure () -- No-op since global state was causing MVar deadlocks
-- For debugging, change to: putStrLn str
