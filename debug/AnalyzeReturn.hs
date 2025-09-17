{-# LANGUAGE OverloadedStrings #-}

import qualified Language.JavaScript.Parser as JS
import qualified Data.Text.IO as TextIO
import qualified Data.Text as Text
import Data.Text (Text)

main :: IO ()
main = do
  putStrLn "=== CORRECT RETURN AST ==="
  correctContent <- TextIO.readFile "return_test.js"
  case JS.parse (Text.unpack correctContent) "correct" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> do
      putStrLn $ show ast
      putStrLn "\n=== EXTRACTED RETURN ==="
      putStrLn $ extractReturn ast
  
  putStrLn "\n=== WRONG RETURN AST ==="
  wrongContent <- TextIO.readFile "return_test_wrong.js"
  case JS.parse (Text.unpack wrongContent) "wrong" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> do
      putStrLn $ show ast
      putStrLn "\n=== EXTRACTED RETURN ==="
      putStrLn $ extractReturn ast

extractReturn ast = case ast of
  (JS.JSAstExpression (JS.JSFunctionExpression _ _ _ _ _ (JS.JSBlock _ [returnStmt] _)) _) -> "RETURN: " ++ show returnStmt
  _ -> "Could not extract return: " ++ show ast