{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

{-|
Module      : AstSummary
Description : Create compact summaries of JavaScript ASTs for easier debugging
Copyright   : (c) 2025 Canopy
License     : BSD-3-Clause
Maintainer  : info@canopy-lang.org

This module provides utilities to create compact, human-readable summaries
of JavaScript ASTs for debugging purposes.
-}

module AstSummary
  ( summarizeAst
  , createCompactSummary
  , processAllAstFiles
  ) where

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified Language.JavaScript.Parser as JS
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath
import Control.Monad (forM_)
import Data.Text (Text)

-- | Create a compact summary of JavaScript AST
summarizeAst :: JS.JSAST -> Text
summarizeAst ast = 
  "JavaScript AST Summary:\n" <>
  "- Total nodes: " <> Text.pack (show (countNodes ast)) <> "\n" <>
  "- Functions: " <> Text.pack (show (countFunctions ast)) <> "\n" <>
  "- Variables: " <> Text.pack (show (countVariables ast)) <> "\n" <>
  "- Statements: " <> Text.pack (show (countStatements ast)) <> "\n" <>
  "\nTop-level structure:\n" <> summarizeTopLevel ast

-- | Count total nodes in AST (approximate)
countNodes :: JS.JSAST -> Int
countNodes ast = length (show ast)

-- | Count function declarations/expressions
countFunctions :: JS.JSAST -> Int
countFunctions ast = 
  length (filter (\line -> "JSFunction" `Text.isInfixOf` line) (Text.lines (Text.pack (show ast))))

-- | Count variable declarations
countVariables :: JS.JSAST -> Int
countVariables ast =
  length (filter (\line -> "JSVar" `Text.isInfixOf` line) (Text.lines (Text.pack (show ast))))

-- | Count statements
countStatements :: JS.JSAST -> Int
countStatements ast =
  length (filter (\line -> "Statement" `Text.isInfixOf` line || "JSStatement" `Text.isInfixOf` line) (Text.lines (Text.pack (show ast))))

-- | Create summary of top-level structure
summarizeTopLevel :: JS.JSAST -> Text
summarizeTopLevel ast =
  let astLines = Text.lines (Text.pack (show ast))
      topLines = take 20 (filter (not . Text.null) astLines)
      simplified = map simplifyLine topLines
  in Text.unlines simplified
  where
    simplifyLine line
      | "JSFunction" `Text.isInfixOf` line = "  - Function declaration"
      | "JSVar" `Text.isInfixOf` line = "  - Variable declaration"
      | "JSExpression" `Text.isInfixOf` line = "  - Expression"
      | "JSStatement" `Text.isInfixOf` line = "  - Statement"
      | otherwise = "  - " <> Text.take 50 (Text.strip line)

-- | Create compact summary and save to file
createCompactSummary :: FilePath -> IO ()
createCompactSummary jsFile = do
  content <- TextIO.readFile jsFile
  case JS.parse (Text.unpack content) "" of
    Left err -> putStrLn ("Error parsing " ++ jsFile ++ ": " ++ show err)
    Right ast -> do
      let summary = summarizeAst ast
          summaryFile = FilePath.replaceExtension jsFile ".summary"
      TextIO.writeFile summaryFile summary
      putStrLn ("Generated summary: " ++ summaryFile)

-- | Process all AST files and create summaries
processAllAstFiles :: IO ()
processAllAstFiles = do
  jsFiles <- findJsFiles "test/Golden/expected/elm-canopy"
  putStrLn ("Creating summaries for " ++ show (length jsFiles) ++ " files...")
  forM_ jsFiles createCompactSummary
  putStrLn "Summary generation complete!"

-- | Find all JavaScript files in directory
findJsFiles :: FilePath -> IO [FilePath]
findJsFiles dir = do
  contents <- Dir.listDirectory dir
  filterM isJsFile (map (dir FilePath.</>) contents)
  where
    isJsFile :: FilePath -> IO Bool
    isJsFile path = do
      isFile <- Dir.doesFileExist path
      pure (isFile && FilePath.takeExtension path == ".js")

    filterM :: Monad m => (a -> m Bool) -> [a] -> m [a]
    filterM _ [] = pure []
    filterM p (x:xs) = do
      result <- p x
      rest <- filterM p xs
      pure (if result then x : rest else rest)

-- | Main function for standalone execution
main :: IO ()
main = do
  putStrLn "JavaScript AST Summary Generator"
  processAllAstFiles