{-# LANGUAGE OverloadedStrings #-}

import System.Process (readProcess)
import Control.Exception (catch, SomeException)

main :: IO ()
main = do
  putStrLn "=== INVESTIGATING SPACING ISSUES ==="
  
  -- Run specific failing tests and capture output
  result1 <- catch 
    (readProcess "stack" ["test", "--ta=--pattern type-annotation"] "")
    (\e -> return $ "Error: " ++ show (e :: SomeException))
    
  result2 <- catch 
    (readProcess "stack" ["test", "--ta=--pattern generic-function"] "")
    (\e -> return $ "Error: " ++ show (e :: SomeException))
  
  putStrLn "\n=== TYPE-ANNOTATION TEST OUTPUT ==="
  putStrLn result1
  
  putStrLn "\n=== GENERIC-FUNCTION TEST OUTPUT ==="  
  putStrLn result2