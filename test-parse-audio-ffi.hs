-- Quick test to see if audio.js parsing works
import System.IO
import Data.List (isPrefixOf, isInfixOf)

main :: IO ()
main = do
  content <- readFile "examples/audio-ffi/external/audio.js"
  let functions = extractFunctionsWithTypes (lines content)
  putStrLn $ "Found " ++ show (length functions) ++ " functions:"
  mapM_ print (take 10 functions)

extractFunctionsWithTypes :: [String] -> [(String, String)]
extractFunctionsWithTypes [] = []
extractFunctionsWithTypes inputLines = extractFromJSDocBlocks inputLines

extractFromJSDocBlocks :: [String] -> [(String, String)]
extractFromJSDocBlocks [] = []
extractFromJSDocBlocks (line:rest)
  | isJSDocStart line =
      let (commentBlock, remaining) = takeJSDocBlock (line:rest)
          mbFunction = parseJSDocBlock commentBlock
      in case mbFunction of
           Just func -> func : extractFromJSDocBlocks remaining
           Nothing -> extractFromJSDocBlocks remaining
  | otherwise = extractFromJSDocBlocks rest

isJSDocStart :: String -> Bool
isJSDocStart line =
  let trimmed = dropWhile (`elem` (" \t" :: String)) line
  in "/**" `isPrefixOf` trimmed

takeJSDocBlock :: [String] -> ([String], [String])
takeJSDocBlock [] = ([], [])
takeJSDocBlock (line:rest) =
  if isJSDocEnd line
    then ([line], rest)
    else let (block, remaining) = takeJSDocBlock rest
         in (line:block, remaining)

isJSDocEnd :: String -> Bool
isJSDocEnd line = "*/" `isInfixOf` line

parseJSDocBlock :: [String] -> Maybe (String, String)
parseJSDocBlock commentLines = do
  functionName <- findNameAnnotation commentLines
  canopyType <- findCanopyTypeAnnotation commentLines
  pure (functionName, canopyType)

findNameAnnotation :: [String] -> Maybe String
findNameAnnotation [] = Nothing
findNameAnnotation (line:rest) =
  case parseNameAnnotation line of
    Just name -> Just name
    Nothing -> findNameAnnotation rest

findCanopyTypeAnnotation :: [String] -> Maybe String
findCanopyTypeAnnotation [] = Nothing
findCanopyTypeAnnotation (line:rest) =
  case parseCanopyTypeAnnotation line of
    Just typeStr -> Just typeStr
    Nothing -> findCanopyTypeAnnotation rest

parseNameAnnotation :: String -> Maybe String
parseNameAnnotation line =
  let trimmed = dropWhile (`elem` (" *" :: String)) line
  in if ("@name " :: String) `isPrefixOf` trimmed
     then Just (strip (drop (length ("@name " :: String)) trimmed))
     else Nothing

parseCanopyTypeAnnotation :: String -> Maybe String
parseCanopyTypeAnnotation line =
  let trimmed = dropWhile (`elem` (" *" :: String)) line
  in if ("@canopy-type " :: String) `isPrefixOf` trimmed
     then Just (drop (length ("@canopy-type " :: String)) trimmed)
     else Nothing

strip :: String -> String
strip = dropWhileEnd (`elem` (" \t\n\r" :: String)) . dropWhile (`elem` (" \t\n\r" :: String))
  where
    dropWhileEnd predicate xs = foldr (\x acc -> if predicate x && null acc then [] else x:acc) [] xs
