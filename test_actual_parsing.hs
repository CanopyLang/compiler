#!/usr/bin/env stack
{- stack
  script
  --resolver lts-22.30
  --package filepath
  --package directory
  --package text
  --package language-javascript
-}

{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import System.Directory (doesFileExist)
import Text.Regex.Posix

-- Simple test to extract JSDoc from actual JavaScript file
main :: IO ()
main = do
  let jsFile = "external/test-complex-types.js"

  exists <- doesFileExist jsFile
  if not exists
    then putStrLn $ "File not found: " ++ jsFile
    else do
      content <- readFile jsFile
      putStrLn "=== JavaScript file content ==="
      putStrLn content
      putStrLn ""

      putStrLn "=== Extracted function annotations ==="
      let functions = extractFunctions content
      mapM_ printFunction functions

extractFunctions :: String -> [(String, String)]
extractFunctions content =
  let -- Simple regex to find function definitions with JSDoc
      funcPattern = "\\*\\s*@canopy-type\\s+([^\\n]+)\\n[^}]*function\\s+(\\w+)"
      matches = content =~ funcPattern :: [[String]]
  in [(match !! 2, match !! 1) | match <- matches, length match >= 3]

printFunction :: (String, String) -> IO ()
printFunction (funcName, typeAnnotation) = do
  putStrLn $ "Function: " ++ funcName
  putStrLn $ "Type: " ++ typeAnnotation
  putStrLn ""