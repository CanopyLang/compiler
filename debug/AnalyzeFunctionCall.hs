{-# LANGUAGE OverloadedStrings #-}

import qualified Language.JavaScript.Parser as JS
import qualified Data.Text.IO as TextIO
import qualified Data.Text as Text
import Data.Text (Text)

main :: IO ()
main = do
  putStrLn "=== FUNCTION CALL AST ==="
  content <- TextIO.readFile "correct_function_call.js"
  case JS.parse (Text.unpack content) "func" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> do
      putStrLn $ show ast
      putStrLn "\n=== CALL BREAKDOWN ==="
      putStrLn $ analyzeCall ast

analyzeCall ast = case ast of
  (JS.JSAstProgram [JS.JSExpressionStatement (JS.JSCallExpression func ann1 args ann2) _] _) -> 
    "FUNCTION: " ++ show func ++ "\nANN1: " ++ show ann1 ++ "\nARGS: " ++ show args ++ "\nANN2: " ++ show ann2
  _ -> "Could not extract call: " ++ show ast