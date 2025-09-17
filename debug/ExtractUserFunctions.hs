{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import System.Process (readProcess)
import Control.Exception (catch, SomeException)

-- Extract just the user-defined function parts
extractUserFunctions :: IO ()
extractUserFunctions = do
  putStrLn "=== EXTRACTING USER FUNCTION PATTERNS ==="
  
  -- Run the test and get the output
  result <- catch 
    (readProcess "stack" ["test", "--ta=--pattern basic-arithmetic"] "")
    (\e -> return $ "Error: " ++ show (e :: SomeException))
    
  let outputLines = lines result
  
  -- Find the expected and got lines
  let expectedLine = findLineContaining "expected:" outputLines
      gotLine = findLineContaining "but got:" outputLines
      
  case (expectedLine, gotLine) of
    (Just exp, Just got) -> do
      putStrLn "=== EXPECTED FUNCTIONS ==="
      let expectedFuncs = extractUserFunctionDeclarations exp
      mapM_ putStrLn expectedFuncs
      
      putStrLn "\n=== ACTUAL FUNCTIONS ==="
      let gotFuncs = extractUserFunctionDeclarations got
      mapM_ putStrLn gotFuncs
      
    _ -> putStrLn "Could not extract expected/got comparison"

findLineContaining :: String -> [String] -> Maybe String
findLineContaining target = find (elem target . words)
  where
    find _ [] = Nothing
    find p (x:xs) = if p x then Just x else find p xs

extractUserFunctionDeclarations :: String -> [String]
extractUserFunctionDeclarations line =
  -- Split on "var $author$project$Main$" to find function declarations
  let parts = splitOn "var $author$project$Main$" line
      userFunctions = drop 1 parts  -- Skip the first part (platform code)
  in map ("var $author$project$Main$" ++) userFunctions

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

main :: IO ()
main = extractUserFunctions