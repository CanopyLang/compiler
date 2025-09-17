{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

{-|
Module      : CompareTestOutput
Description : Compare expected vs actual JavaScript output for specific test case
Copyright   : (c) 2025 Canopy
License     : BSD-3-Clause
Maintainer  : info@canopy-lang.org

This module provides detailed comparison between expected and actual JavaScript
output to identify specific formatting differences in test cases.
-}

module CompareTestOutput
  ( compareTest
  , analyzeFormatDifferences
  , identifyPatterns
  ) where

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified Language.JavaScript.Parser as JS
import qualified Language.JavaScript.Pretty.Printer as JSP
import Control.Monad (when)
import System.FilePath ((</>))
import Data.Text (Text)

-- | Compare a specific test case and show the differences
compareTest :: String -> IO ()
compareTest testName = do
  let expectedFile = "test/Golden/expected/elm-canopy" </> testName ++ ".js"
      actualFile = "test/Golden/expected/elm-canopy" </> testName ++ ".ast"
  
  putStrLn ("Analyzing test: " ++ testName)
  
  -- Read expected output
  expected <- TextIO.readFile expectedFile
  
  -- For this analysis, we'll use the original JS to understand structure
  putStrLn "Expected JavaScript structure:"
  analyzeJSStructure expected
  
  putStrLn "\n=== FORMAT PATTERN ANALYSIS ==="
  analyzeFormatDifferences expected

-- | Analyze the structure of JavaScript output
analyzeJSStructure :: Text -> IO ()
analyzeJSStructure jsContent = do
  let fixedContent = Text.replace "return '\\';" "return '\\\\';" jsContent
  case JS.parse (Text.unpack fixedContent) "" of
    Left err -> putStrLn ("Parse error: " ++ show err)
    Right ast -> do
      let minified = JSP.renderToString ast
      putStrLn ("Minified length: " ++ show (length minified))
      putStrLn ("Sample minified: " ++ take 200 minified)

-- | Analyze format differences that are causing test failures
analyzeFormatDifferences :: Text -> IO ()
analyzeFormatDifferences content = do
  putStrLn "=== Function Declaration Patterns ==="
  let functionLines = filter (Text.isInfixOf "function") (Text.lines content)
  mapM_ (putStrLn . ("  " ++) . Text.unpack) (take 5 functionLines)
  
  putStrLn "\n=== String Literal Patterns ==="  
  let stringLines = filter (\line -> "'" `Text.isInfixOf` line || "\"" `Text.isInfixOf` line) (Text.lines content)
  mapM_ (putStrLn . ("  " ++) . Text.unpack) (take 5 stringLines)
  
  putStrLn "\n=== Call Expression Patterns ==="
  let callLines = filter (Text.isInfixOf "(") (Text.lines content)
  mapM_ (putStrLn . ("  " ++) . Text.unpack . Text.take 80) (take 5 callLines)

-- | Identify common patterns that need fixing
identifyPatterns :: Text -> IO [Text]
identifyPatterns content = do
  let patterns = []
  -- TODO: Add pattern detection logic
  pure patterns

-- | Main function for standalone execution
main :: IO ()
main = do
  putStrLn "JavaScript Output Comparison Tool"
  compareTest "simple-case"  -- Start with a simple test
  putStrLn "\n" 
  compareTest "generic-function"  -- A failing test