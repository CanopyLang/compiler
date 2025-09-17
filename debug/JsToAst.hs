{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

{-|
Module      : JsToAst
Description : Utility to convert JavaScript files to language-javascript AST representation
Copyright   : (c) 2025 Canopy
License     : BSD-3-Clause
Maintainer  : info@canopy-lang.org

This module provides utilities to parse JavaScript files and convert them to
language-javascript AST representations for debugging purposes.
-}

module JsToAst
  ( parseJsFile
  , parseJsText
  , prettyPrintAst
  , processAllGoldenFiles
  ) where

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified Data.ByteString.Lazy.Char8 as BS
import qualified Language.JavaScript.Parser as JS
import qualified Language.JavaScript.Pretty.Printer as JSPrint
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath
import System.IO (Handle, IOMode(..), withFile)
import Control.Monad (forM_, when)
import Data.Text (Text)

-- | Parse a JavaScript file and return its AST representation
parseJsFile :: FilePath -> IO (Either String JS.JSAST)
parseJsFile filePath = do
  content <- TextIO.readFile filePath
  pure (parseJsText content)

-- | Parse JavaScript text and return its AST representation
parseJsText :: Text -> Either String JS.JSAST
parseJsText content =
  let fixedContent = fixInvalidEscapes content
  in case JS.parse (Text.unpack fixedContent) "" of
    Left err -> Left (show err)
    Right ast -> Right ast

-- | Fix invalid escape sequences in JavaScript content
fixInvalidEscapes :: Text -> Text
fixInvalidEscapes content =
  -- Fix the invalid escape sequence return '\'; to return '\\';
  Text.replace "return '\\';" "return '\\\\';" content

-- | Pretty print the AST in a readable format
prettyPrintAst :: JS.JSAST -> Text
prettyPrintAst ast = Text.pack (show ast)

-- | Process all golden test JavaScript files and generate their AST representations
processAllGoldenFiles :: IO ()
processAllGoldenFiles = do
  goldenDir <- findGoldenDirectory
  case goldenDir of
    Nothing -> putStrLn "Golden test directory not found"
    Just dir -> do
      jsFiles <- findJsFiles dir
      putStrLn ("Found " ++ show (length jsFiles) ++ " JavaScript files")
      forM_ jsFiles processGoldenFile
  where
    processGoldenFile :: FilePath -> IO ()
    processGoldenFile jsFile = do
      putStrLn ("Processing: " ++ jsFile)
      result <- parseJsFile jsFile
      case result of
        Left err -> putStrLn ("Error parsing " ++ jsFile ++ ": " ++ err)
        Right ast -> do
          let astFile = replaceExtension jsFile ".ast"
          writeAstFile astFile ast
          putStrLn ("Generated AST: " ++ astFile)

    writeAstFile :: FilePath -> JS.JSAST -> IO ()
    writeAstFile filePath ast =
      TextIO.writeFile filePath (prettyPrintAst ast)

    replaceExtension :: FilePath -> String -> FilePath
    replaceExtension path newExt =
      FilePath.dropExtension path ++ newExt

-- | Find the golden test directory
findGoldenDirectory :: IO (Maybe FilePath)
findGoldenDirectory = do
  let possibleDirs = 
        [ "test/Golden"
        , "test/golden" 
        , "Golden"
        , "golden"
        ]
  findFirstExisting possibleDirs
  where
    findFirstExisting :: [FilePath] -> IO (Maybe FilePath)
    findFirstExisting [] = pure Nothing
    findFirstExisting (dir:dirs) = do
      exists <- Dir.doesDirectoryExist dir
      if exists
        then pure (Just dir)
        else findFirstExisting dirs

-- | Find all JavaScript files in a directory recursively
findJsFiles :: FilePath -> IO [FilePath]
findJsFiles dir = do
  contents <- Dir.listDirectory dir
  files <- filterM isJsFile (map (dir FilePath.</>) contents)
  subdirs <- filterM Dir.doesDirectoryExist (map (dir FilePath.</>) contents)
  subFiles <- concat <$> mapM findJsFiles subdirs
  pure (files ++ subFiles)
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
  putStrLn "JavaScript to AST Converter"
  putStrLn "Processing all golden test files..."
  processAllGoldenFiles
  putStrLn "Done!"