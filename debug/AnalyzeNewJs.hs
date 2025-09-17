{-# LANGUAGE OverloadedStrings #-}

import qualified Language.JavaScript.Parser as JS
import qualified Data.Text.IO as TextIO
import qualified Data.Text as Text
import Data.Text (Text)

main :: IO ()
main = do
  putStrLn "=== CORRECT TERNARY AST ==="
  correctContent <- TextIO.readFile "correct_ternary.js"
  case JS.parse (Text.unpack correctContent) "correct" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> do
      putStrLn $ show ast
      putStrLn "\n=== EXTRACTED TERNARY ==="
      putStrLn $ extractTernary ast
  
  putStrLn "\n=== NEW CURRENT TERNARY AST ==="
  currentContent <- TextIO.readFile "new_current_ternary.js"
  case JS.parse (Text.unpack currentContent) "current" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> do
      putStrLn $ show ast
      putStrLn "\n=== EXTRACTED TERNARY ==="
      putStrLn $ extractTernary ast

extractTernary ast = case ast of
  (JS.JSAstProgram [JS.JSVariable _ (JS.JSLOne (JS.JSVarInitExpression _ (JS.JSVarInit _ (JS.JSFunctionExpression _ _ _ _ _ (JS.JSBlock _ [JS.JSReturn _ (Just ternary)] _))))) _]) -> "TERNARY: " ++ show ternary
  _ -> "Could not extract ternary"