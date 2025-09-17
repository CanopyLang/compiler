{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

{-|
Module      : DetailedAstAnalysis  
Description : Detailed analysis and debugging utilities for JavaScript ASTs
Copyright   : (c) 2025 Canopy
License     : BSD-3-Clause
Maintainer  : info@canopy-lang.org

This module provides detailed analysis of JavaScript ASTs generated from
Canopy compiler output for debugging and validation purposes.
-}

module DetailedAstAnalysis
  ( analyzeJsFile
  , compareAsts  
  , extractFunctionNames
  , extractVariableNames
  , createDebugReport
  ) where

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified Language.JavaScript.Parser as JS
import qualified Language.JavaScript.Parser.AST as AST
import qualified System.FilePath as FilePath
import Data.Text (Text)
import Control.Monad (when)

-- | Analyze a JavaScript file and create detailed report
analyzeJsFile :: FilePath -> IO ()
analyzeJsFile jsFile = do
  putStrLn ("Analyzing: " ++ jsFile)
  content <- TextIO.readFile jsFile
  case JS.parse (Text.unpack content) "" of
    Left err -> putStrLn ("Parse error: " ++ show err)
    Right ast -> do
      let report = createDebugReport jsFile ast
          reportFile = FilePath.replaceExtension jsFile ".analysis"
      TextIO.writeFile reportFile report
      TextIO.putStrLn report
      putStrLn ("Analysis saved to: " ++ reportFile)

-- | Create comprehensive debug report for an AST
createDebugReport :: FilePath -> JS.JSAST -> Text
createDebugReport fileName ast = Text.unlines
  [ "=== JavaScript AST Analysis Report ==="
  , "File: " <> Text.pack fileName
  , "Generated: " <> Text.pack (show (length (show ast))) <> " characters in AST"
  , ""
  , "=== Function Analysis ==="
  , analyzeFunctions ast
  , ""
  , "=== Variable Analysis ==="
  , analyzeVariables ast
  , ""
  , "=== Structure Analysis ==="
  , analyzeStructure ast
  , ""
  , "=== Code Pattern Analysis ==="
  , analyzePatterns ast
  ]

-- | Extract function names from AST
extractFunctionNames :: JS.JSAST -> [Text]
extractFunctionNames ast = 
  let astStr = Text.pack (show ast)
      lines' = Text.lines astStr
  in extractNamesFromLines "function" lines'

-- | Extract variable names from AST  
extractVariableNames :: JS.JSAST -> [Text]
extractVariableNames ast =
  let astStr = Text.pack (show ast)
      lines' = Text.lines astStr
  in extractNamesFromLines "var" lines'

-- | Helper to extract names from AST string representation
extractNamesFromLines :: Text -> [Text] -> [Text]
extractNamesFromLines pattern lines' =
  let matchingLines = filter (Text.isInfixOf pattern) lines'
      names = concatMap extractNameFromLine matchingLines
  in take 20 (filter (not . Text.null) names)  -- Limit to first 20
  where
    extractNameFromLine line =
      let words' = Text.words line
          candidates = filter (Text.all (\c -> c /= '(' && c /= ')' && c /= '{' && c /= '}')) words'
      in take 3 candidates

-- | Analyze functions in the AST
analyzeFunctions :: JS.JSAST -> Text  
analyzeFunctions ast = 
  let functionNames = extractFunctionNames ast
      funcCount = length functionNames
  in Text.unlines
    [ "Function count: " <> Text.pack (show funcCount)
    , "Function names (sample): " <> Text.intercalate ", " (take 10 functionNames)
    ]

-- | Analyze variables in the AST
analyzeVariables :: JS.JSAST -> Text
analyzeVariables ast =
  let varNames = extractVariableNames ast  
      varCount = length varNames
  in Text.unlines
    [ "Variable count: " <> Text.pack (show varCount)
    , "Variable names (sample): " <> Text.intercalate ", " (take 10 varNames)
    ]

-- | Analyze overall structure
analyzeStructure :: JS.JSAST -> Text
analyzeStructure ast =
  let astStr = Text.pack (show ast)
      totalLines = length (Text.lines astStr)
      hasClosures = "closure" `Text.isInfixOf` Text.toLower astStr
      hasModules = "module" `Text.isInfixOf` Text.toLower astStr  
      hasExports = "export" `Text.isInfixOf` Text.toLower astStr
  in Text.unlines
    [ "Total AST lines: " <> Text.pack (show totalLines)
    , "Contains closures: " <> Text.pack (show hasClosures)
    , "Contains modules: " <> Text.pack (show hasModules)
    , "Contains exports: " <> Text.pack (show hasExports)
    ]

-- | Analyze common patterns in generated JavaScript
analyzePatterns :: JS.JSAST -> Text
analyzePatterns ast = 
  let astStr = Text.pack (show ast)
      hasElmPatterns = detectElmPatterns astStr
      hasOptimizations = detectOptimizations astStr
  in Text.unlines
    [ "=== Elm/Canopy Patterns ==="
    , hasElmPatterns
    , ""
    , "=== Optimization Patterns ===" 
    , hasOptimizations
    ]

-- | Detect Elm/Canopy-specific patterns
detectElmPatterns :: Text -> Text
detectElmPatterns astStr = Text.unlines
  [ "Function currying: " <> Text.pack (show (countPattern "F2\\|F3\\|F4" astStr))
  , "Virtual DOM: " <> Text.pack (show (countPattern "VirtualDom\\|_VirtualDom" astStr))
  , "Message handling: " <> Text.pack (show (countPattern "Cmd\\|Sub\\|Task" astStr))
  , "Maybe/Result: " <> Text.pack (show (countPattern "Maybe\\|Result\\|Just\\|Nothing" astStr))
  ]

-- | Detect optimization patterns
detectOptimizations :: Text -> Text  
detectOptimizations astStr = Text.unlines
  [ "Inlined functions: " <> Text.pack (show (countPattern "inline" astStr))
  , "Dead code elimination: " <> Text.pack (show (countPattern "unused\\|dead" astStr))
  , "Tail call optimization: " <> Text.pack (show (countPattern "tailcall\\|_trampoline" astStr))
  ]

-- | Count occurrences of a pattern (simplified)
countPattern :: Text -> Text -> Int
countPattern pattern text = 
  length (Text.splitOn pattern text) - 1

-- | Compare two ASTs and highlight differences
compareAsts :: FilePath -> FilePath -> IO ()
compareAsts file1 file2 = do
  putStrLn ("Comparing " ++ file1 ++ " with " ++ file2)
  content1 <- TextIO.readFile file1
  content2 <- TextIO.readFile file2
  case (JS.parse (Text.unpack content1) "", JS.parse (Text.unpack content2) "") of
    (Right ast1, Right ast2) -> do
      let comparison = compareAstStructures ast1 ast2
          comparisonFile = file1 ++ ".vs." ++ FilePath.takeBaseName file2 ++ ".comparison"
      TextIO.writeFile comparisonFile comparison
      TextIO.putStrLn comparison
      putStrLn ("Comparison saved to: " ++ comparisonFile)
    (Left err, _) -> putStrLn ("Error parsing " ++ file1 ++ ": " ++ show err)
    (_, Left err) -> putStrLn ("Error parsing " ++ file2 ++ ": " ++ show err)

-- | Compare structures of two ASTs
compareAstStructures :: JS.JSAST -> JS.JSAST -> Text
compareAstStructures ast1 ast2 = 
  let size1 = length (show ast1)
      size2 = length (show ast2) 
      funcs1 = extractFunctionNames ast1
      funcs2 = extractFunctionNames ast2
      vars1 = extractVariableNames ast1
      vars2 = extractVariableNames ast2
  in Text.unlines
    [ "=== AST Comparison ==="
    , "Size difference: " <> Text.pack (show (size2 - size1)) <> " characters"
    , "Function count: " <> Text.pack (show (length funcs1)) <> " vs " <> Text.pack (show (length funcs2))
    , "Variable count: " <> Text.pack (show (length vars1)) <> " vs " <> Text.pack (show (length vars2))
    , ""
    , "Functions in first only: " <> Text.intercalate ", " (take 5 (filter (`notElem` funcs2) funcs1))
    , "Functions in second only: " <> Text.intercalate ", " (take 5 (filter (`notElem` funcs1) funcs2))
    ]

-- | Main function for standalone execution
main :: IO ()
main = do
  putStrLn "Detailed JavaScript AST Analysis"
  putStrLn "Analyzing simple-case.js as example..."
  analyzeJsFile "test/Golden/expected/elm-canopy/simple-case.js"