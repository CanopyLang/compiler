{-# LANGUAGE TemplateHaskell #-}

import Data.FileEmbed (embedStringFile)

testRuntime :: String
testRuntime = $(embedStringFile "compiler/resources/elm_runtime.js")

main :: IO ()
main = do
  putStrLn $ "Runtime size: " ++ show (length testRuntime)
  putStrLn $ "First 100 chars: " ++ take 100 testRuntime