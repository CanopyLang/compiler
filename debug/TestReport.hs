{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

{-|
Module      : TestReport
Description : Generate a comprehensive report of golden test file processing
Copyright   : (c) 2025 Canopy
License     : BSD-3-Clause
Maintainer  : info@canopy-lang.org

This module generates reports on the success/failure status of processing
JavaScript golden test files.
-}

module TestReport
  ( generateReport
  , checkFileStatus
  , createStatusReport
  ) where

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified Language.JavaScript.Parser as JS
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath
import Control.Monad (filterM, forM_)
import Data.Text (Text)

-- | Status of a JavaScript file
data FileStatus = Success | ParseError String | NotFound
  deriving (Eq, Show)

-- | Check the parsing status of a JavaScript file
checkFileStatus :: FilePath -> IO FileStatus  
checkFileStatus jsFile = do
  exists <- Dir.doesFileExist jsFile
  if not exists
    then pure NotFound
    else do
      content <- TextIO.readFile jsFile
      let fixedContent = Text.replace "return '\\';" "return '\\\\';" content
      case JS.parse (Text.unpack fixedContent) "" of
        Left err -> pure (ParseError (show err))
        Right _ -> pure Success

-- | Generate comprehensive status report
generateReport :: IO ()
generateReport = do
  putStrLn "=== Golden Test File Processing Report ==="
  jsFiles <- findJsFiles "test/Golden/expected/elm-canopy"
  putStrLn ("Total JavaScript files found: " ++ show (length jsFiles))
  
  statuses <- mapM (\file -> do
    status <- checkFileStatus file
    pure (file, status)) jsFiles
    
  let successful = filter (\(_, status) -> status == Success) statuses
      failed = filter (\(_, status) -> case status of 
                         ParseError _ -> True
                         _ -> False) statuses
      notFound = filter (\(_, status) -> status == NotFound) statuses
  
  putStrLn ("\nSuccessful parses: " ++ show (length successful))
  putStrLn ("Failed parses: " ++ show (length failed))  
  putStrLn ("Files not found: " ++ show (length notFound))
  
  let report = createStatusReport statuses
      reportFile = "debug/golden-test-report.txt"
  TextIO.writeFile reportFile report
  TextIO.putStrLn report
  putStrLn ("Report saved to: " ++ reportFile)

-- | Create detailed status report
createStatusReport :: [(FilePath, FileStatus)] -> Text
createStatusReport statuses = 
  let successful = [(f, s) | (f, s) <- statuses, s == Success]
      failed = [(f, s) | (f, s) <- statuses, case s of ParseError _ -> True; _ -> False]
      notFound = [(f, s) | (f, s) <- statuses, s == NotFound]
  in Text.unlines $
    [ "=== Golden Test Processing Report ==="
    , "Generated: " <> Text.pack (show (length statuses)) <> " files analyzed"
    , ""
    , "=== SUCCESSFUL FILES (" <> Text.pack (show (length successful)) <> ") ==="
    ] ++
    map (\(file, _) -> "✓ " <> Text.pack (FilePath.takeBaseName file)) successful ++
    [ ""
    , "=== FAILED FILES (" <> Text.pack (show (length failed)) <> ") ==="
    ] ++
    map (\(file, status) -> case status of
           ParseError err -> "✗ " <> Text.pack (FilePath.takeBaseName file) <> " - " <> Text.take 100 (Text.pack err)
           _ -> "✗ " <> Text.pack (FilePath.takeBaseName file)) failed ++
    (if not (null notFound) then
      [ ""
      , "=== NOT FOUND FILES (" <> Text.pack (show (length notFound)) <> ") ==="
      ] ++ map (\(file, _) -> "? " <> Text.pack file) notFound
     else []) ++
    [ ""
    , "=== SUMMARY ==="
    , "Total files: " <> Text.pack (show (length statuses))
    , "Successful: " <> Text.pack (show (length successful)) <> " (" <> Text.pack (show (percentage (length successful) (length statuses))) <> "%)"
    , "Failed: " <> Text.pack (show (length failed)) <> " (" <> Text.pack (show (percentage (length failed) (length statuses))) <> "%)"
    , "Not found: " <> Text.pack (show (length notFound))
    , ""
    , "=== RECOMMENDATIONS ==="
    , if length failed > length successful
        then "⚠️  Most files are failing to parse. Check for lexical issues in generated JS."
        else if length failed > 0  
        then "⚠️  Some files failing to parse. May need JS generation fixes."
        else "✅ All files parsing successfully!"
    ]
  where
    percentage :: Int -> Int -> Int
    percentage n total = if total == 0 then 0 else (n * 100) `div` total

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

-- | Main function for standalone execution
main :: IO ()
main = generateReport