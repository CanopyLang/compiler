{-# LANGUAGE OverloadedStrings #-}

import qualified Language.JavaScript.Parser as JS
import qualified Data.Text.IO as TextIO
import qualified Data.Text as Text
import Data.Text (Text)

main :: IO ()
main = do
  putStrLn "=== BOOLEAN TERNARY AST ==="
  content <- TextIO.readFile "simple_boolean.js"
  case JS.parse (Text.unpack content) "boolean" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> do
      putStrLn $ show ast
      putStrLn "\n=== TERNARY ANALYSIS ==="
      putStrLn $ analyzeBoolean ast

analyzeBoolean ast = case ast of
  (JS.JSAstProgram [JS.JSExpressionStatement (JS.JSExpressionTernary cond q then_expr c else_expr) _] _) -> 
    "CONDITION: " ++ show cond ++ "\nQUESTION: " ++ show q ++ "\nTHEN: " ++ show then_expr ++ "\nCOLON: " ++ show c ++ "\nELSE: " ++ show else_expr
  _ -> "Could not extract ternary: " ++ show ast