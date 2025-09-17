{-# LANGUAGE OverloadedStrings #-}

import qualified Language.JavaScript.Parser as JS
import qualified Data.Text.IO as TextIO
import qualified Data.Text as Text
import Data.Text (Text)

main :: IO ()
main = do
  putStrLn "=== STRING CONCATENATION AST ==="
  content <- TextIO.readFile "correct_string_concat.js"
  case JS.parse (Text.unpack content) "concat" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> do
      putStrLn $ show ast
      putStrLn "\n=== BINARY BREAKDOWN ==="
      putStrLn $ analyzeConcat ast

analyzeConcat ast = case ast of
  (JS.JSAstProgram [JS.JSExpressionStatement (JS.JSExpressionBinary left op right) _] _) -> 
    "LEFT: " ++ show left ++ "\nOP: " ++ show op ++ "\nRIGHT: " ++ show right
  _ -> "Could not extract binary: " ++ show ast