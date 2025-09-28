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
printLog str =
  if "BOOTSTRAP:" `isInfixOf` str || "CompileError:" `isInfixOf` str || "=== COMPILE ERROR" `isInfixOf` str || "nothing branch" `isInfixOf` str || "all keys in" `isInfixOf` str || "TVar updated for" `isInfixOf` str || "Elm.JsArray" `isInfixOf` str || "DEBUG:" `isInfixOf` str || "isKernel check" `isInfixOf` str
  then putStrLn ("CANOPY_DEBUG: " <> str)
  else pure () -- Reduce noise, only show bootstrap and error messages
  where
    isInfixOf needle haystack = needle `elem` (take (length needle) <$> tails haystack)
    tails [] = [[]]
    tails xs@(_:ys) = xs : tails ys
