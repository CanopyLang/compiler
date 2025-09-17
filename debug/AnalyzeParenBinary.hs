{-# LANGUAGE OverloadedStrings #-}

import qualified Language.JavaScript.Parser as JS
import qualified Data.Text.IO as TextIO
import qualified Data.Text as Text
import Data.Text (Text)

main :: IO ()
main = do
  putStrLn "=== CORRECT PAREN BINARY AST ==="
  correctContent <- TextIO.readFile "correct_paren_binary.js"
  case JS.parse (Text.unpack correctContent) "correct" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> putStrLn $ show ast
  
  putStrLn "\n=== WRONG PAREN BINARY AST ==="
  wrongContent <- TextIO.readFile "wrong_paren_binary.js"
  case JS.parse (Text.unpack wrongContent) "wrong" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> putStrLn $ show ast