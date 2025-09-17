{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import System.Process (readProcess)
import Control.Exception (catch, SomeException)

-- Compare specific test and show exact differences
compareSpecific :: String -> IO ()
compareSpecific testName = do
  putStrLn $ "=== COMPARING: " ++ testName ++ " ==="
  
  -- Run the test and capture the expected vs got output
  result <- catch 
    (readProcess "stack" ["test", "--ta=--pattern " ++ testName] "")
    (\e -> return $ "Error: " ++ show (e :: SomeException))
    
  let outputLines = lines result
      
  -- Find the expected and got sections
  let expectedStart = findLineWith "expected:" outputLines
      gotStart = findLineWith "but got:" outputLines
      
  case (expectedStart, gotStart) of
    (Just expIdx, Just gotIdx) -> do
      let expectedLine = outputLines !! expIdx
          gotLine = outputLines !! gotIdx
          
      putStrLn "=== EXPECTED ==="
      putStrLn expectedLine
      putStrLn "\n=== GOT ==="  
      putStrLn gotLine
      
      putStrLn "\n=== DETAILED COMPARISON ==="
      compareUserCode expectedLine gotLine
    _ -> putStrLn "Could not find expected/got comparison in test output"

findLineWith :: String -> [String] -> Maybe Int
findLineWith target lines = 
  let indexed = zip [0..] lines
  in fmap fst $ find (\(_, line) -> target `elem` words line) indexed
  where
    find _ [] = Nothing
    find p (x:xs) = if p x then Just x else find p xs

-- Extract and compare the user-generated code (after the platform code)
compareUserCode :: String -> String -> IO ()
compareUserCode expected got = do
  -- Find user code after the platform setup
  let expectedUserCode = extractUserCode expected
      gotUserCode = extractUserCode got
      
  putStrLn "Expected user code patterns:"
  analyzeUserPatterns expectedUserCode
  
  putStrLn "\nGot user code patterns:"  
  analyzeUserPatterns gotUserCode
  
  putStrLn "\nKey differences:"
  identifyDifferences expectedUserCode gotUserCode

extractUserCode :: String -> String
extractUserCode code = 
  -- Extract code after the platform setup, look for user-defined functions
  let parts = splitOn "var $author$project$Main$" code
  in if length parts > 1 then "$author$project$Main$" ++ parts !! 1 else code

splitOn :: Eq a => [a] -> [a] -> [[a]]
splitOn _ [] = [[]]
splitOn delim str = 
  let (before, remainder) = breakList (isPrefixOf delim) str
  in before : case remainder of
                [] -> []
                r -> splitOn delim (drop (length delim) r)

breakList :: ([a] -> Bool) -> [a] -> ([a], [a])
breakList _ [] = ([], [])
breakList p xs@(x:xs')
  | p xs = ([], xs)
  | otherwise = let (ys, zs) = breakList p xs' in (x:ys, zs)

isPrefixOf :: Eq a => [a] -> [a] -> Bool  
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (x:xs) (y:ys) = x == y && isPrefixOf xs ys

analyzeUserPatterns :: String -> IO ()
analyzeUserPatterns code = do
  putStrLn $ "  Function assignments: " ++ show (countOccurrences "= F" code)
  putStrLn $ "  Function calls in A3: " ++ show (countOccurrences "A3(" code)
  putStrLn $ "  Inline functions: " ++ show (countOccurrences "function (" code)

countOccurrences :: String -> String -> Int
countOccurrences needle haystack = length $ filter (isPrefixOf needle) $ tails haystack
  where
    tails [] = [[]]
    tails xs@(_:xs') = xs : tails xs'

identifyDifferences :: String -> String -> IO ()
identifyDifferences exp got = do
  putStrLn $ "  Expected contains 'F2(': " ++ show ("F2(" `elem` words exp)
  putStrLn $ "  Got contains 'F2(function': " ++ show ("F2(function" `elem` words got)
  putStrLn $ "  Expected has inline syntax: " ++ show ("g(x)" `elem` words exp)  
  putStrLn $ "  Got has explicit function: " ++ show ("function (x, y)" `elem` words got)

main :: IO ()
main = compareSpecific "basic-arithmetic"