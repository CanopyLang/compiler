#!/usr/bin/env runhaskell
{-# LANGUAGE OverloadedStrings #-}

import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.IO as T
import System.Environment (getArgs)
import Data.List (isPrefixOf)
import Text.Printf (printf)

-- Compare two JavaScript files and show differences
main :: IO ()
main = do
  putStrLn "=== JavaScript Test Output Comparison Tool ==="

  -- Read the expected (Elm) output
  expectedBS <- BL.readFile "/home/quinten/fh/canopy/test/Golden/expected/elm-canopy/basic-arithmetic.js"
  let expectedText = T.decodeUtf8 (BL.toStrict expectedBS)

  -- Generate actual (Canopy) output by running the test and capturing it
  putStrLn "Generating Canopy output..."
  canopyOutput <- generateCanopyOutput

  putStrLn $ "Expected output length: " ++ show (T.length expectedText) ++ " characters"
  putStrLn $ "Actual output length: " ++ show (T.length canopyOutput) ++ " characters"
  putStrLn ""

  -- Compare line by line for formatted output
  let expectedLines = T.lines expectedText
      actualLines = T.lines canopyOutput

  putStrLn "=== LINE-BY-LINE COMPARISON ==="
  putStrLn $ "Expected lines: " ++ show (length expectedLines)
  putStrLn $ "Actual lines: " ++ show (length actualLines)
  putStrLn ""

  -- Show first few lines of each
  putStrLn "=== FIRST 10 LINES EXPECTED ==="
  mapM_ (putStrLn . T.unpack) (take 10 expectedLines)
  putStrLn ""

  putStrLn "=== FIRST 10 LINES ACTUAL ==="
  mapM_ (putStrLn . T.unpack) (take 10 actualLines)
  putStrLn ""

  -- Find first difference
  let differences = findDifferences expectedLines actualLines
  putStrLn "=== FIRST 5 DIFFERENCES ==="
  mapM_ printDifference (take 5 differences)

  -- Check if one is minified vs formatted
  let expectedMinified = isMinified expectedText
      actualMinified = isMinified canopyOutput

  putStrLn ""
  putStrLn $ "Expected is minified: " ++ show expectedMinified
  putStrLn $ "Actual is minified: " ++ show actualMinified

  -- Look for key kernel function patterns
  putStrLn ""
  putStrLn "=== KERNEL FUNCTION ANALYSIS ==="
  analyzeKernelFunctions expectedText canopyOutput

-- Generate Canopy output using the same method as the test
generateCanopyOutput :: IO T.Text
generateCanopyOutput = do
  -- This is a simplified version - we'll extract from test output
  putStrLn "Run: stack test --ta=\"--pattern basic-arithmetic\" and check output..."
  return "placeholder - will extract from test run"

-- Check if text is minified (single line, no indentation)
isMinified :: T.Text -> Bool
isMinified text =
  let lines = T.lines text
      nonEmptyLines = filter (not . T.null . T.strip) lines
      totalLines = length nonEmptyLines
      -- If most content is on just a few lines, it's likely minified
  in totalLines < 10 && T.length text > 1000

-- Find line differences
findDifferences :: [T.Text] -> [T.Text] -> [(Int, T.Text, T.Text)]
findDifferences expected actual = go 1 expected actual
  where
    go _ [] [] = []
    go n (e:es) (a:as)
      | e == a = go (n+1) es as
      | otherwise = (n, e, a) : go (n+1) es as
    go n (e:es) [] = (n, e, "<MISSING>") : go (n+1) es []
    go n [] (a:as) = (n, "<EXTRA>", a) : go (n+1) [] as

printDifference :: (Int, T.Text, T.Text) -> IO ()
printDifference (lineNum, expected, actual) = do
  printf "Line %d:\n" lineNum
  printf "  Expected: %s\n" (T.unpack expected)
  printf "  Actual:   %s\n" (T.unpack actual)
  putStrLn ""

-- Analyze kernel function patterns
analyzeKernelFunctions :: T.Text -> T.Text -> IO ()
analyzeKernelFunctions expected actual = do
  let expectedUtils = extractUtilsPatterns expected
      actualUtils = extractUtilsPatterns actual

  putStrLn "Expected _Utils patterns:"
  mapM_ (putStrLn . ("  " ++)) expectedUtils

  putStrLn "\nActual _Utils patterns:"
  mapM_ (putStrLn . ("  " ++)) actualUtils

  putStrLn "\nPattern differences:"
  let commonPatterns = ["_Utils_Tuple0", "_Utils_Tuple2", "_List_Nil", "_List_Cons"]
  mapM_ (comparePattern expected actual) commonPatterns

extractUtilsPatterns :: T.Text -> [String]
extractUtilsPatterns text =
  let allLines = T.lines text
      utilsLines = filter (T.isInfixOf "_Utils_" ) allLines
  in map T.unpack (take 5 utilsLines)

comparePattern :: T.Text -> T.Text -> String -> IO ()
comparePattern expected actual pattern = do
  let expectedMatch = extractPattern expected pattern
      actualMatch = extractPattern actual pattern
  if expectedMatch /= actualMatch
    then do
      putStrLn $ "  " ++ pattern ++ ":"
      putStrLn $ "    Expected: " ++ expectedMatch
      putStrLn $ "    Actual:   " ++ actualMatch
    else putStrLn $ "  " ++ pattern ++ ": MATCH"

extractPattern :: T.Text -> String -> String
extractPattern text pattern =
  let textStr = T.unpack text
      patternIndex = case T.breakOn (T.pack pattern) text of
        (_, rest) | T.null rest -> "NOT FOUND"
        (_, rest) ->
          let line = T.unpack $ T.takeWhile (/= '\n') rest
              -- Take first 100 chars to see the pattern
          in take 100 line
  in patternIndex