{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified Data.List as List
import System.FilePath ((</>))
import Control.Monad (forM_)

-- Analyze multiple failing tests to identify patterns
analyzeFailingPatterns :: IO ()
analyzeFailingPatterns = do
  putStrLn "=== ANALYZING FAILING TEST PATTERNS ==="
  
  let testNames = 
        [ "basic-arithmetic"
        , "function-composition"  
        , "lambda-expressions"
        , "if-expression"
        , "let-binding"
        ]
  
  forM_ testNames $ \testName -> do
    putStrLn $ "\n=== ANALYZING: " ++ testName ++ " ==="
    analyzeTestFile testName

analyzeTestFile :: String -> IO ()
analyzeTestFile testName = do
  let expectedFile = "test/Golden/expected/elm-canopy" </> testName ++ ".js"
  
  putStrLn $ "Reading: " ++ expectedFile
  expected <- TextIO.readFile expectedFile
  
  -- Extract and analyze key patterns
  let jsLines = Text.lines expected
      
  putStrLn "=== FUNCTION DECLARATION PATTERNS ==="
  let functionDecls = filter (Text.isInfixOf "function") jsLines
  mapM_ (putStrLn . ("  " ++) . Text.unpack . Text.take 80) (take 3 functionDecls)
  
  putStrLn "\n=== FUNCTION CALL PATTERNS ==="  
  let functionCalls = filter (\line -> "(" `Text.isInfixOf` line && "function" `Text.isInfixOf` line) jsLines
  mapM_ (putStrLn . ("  " ++) . Text.unpack . Text.take 80) (take 3 functionCalls)
  
  putStrLn "\n=== VARIABLE ASSIGNMENT PATTERNS ==="
  let varAssignments = filter (Text.isInfixOf "var ") jsLines  
  mapM_ (putStrLn . ("  " ++) . Text.unpack . Text.take 80) (take 3 varAssignments)
  
  putStrLn "\n=== A3/F2/F3 CALL PATTERNS ==="
  let helperCalls = filter (\line -> any (`Text.isInfixOf` line) ["A3(", "F2(", "F3("]) jsLines
  mapM_ (putStrLn . ("  " ++) . Text.unpack . Text.take 80) (take 3 helperCalls)

main :: IO ()
main = analyzeFailingPatterns