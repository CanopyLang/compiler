{-# LANGUAGE OverloadedStrings #-}

import qualified Language.JavaScript.Parser as JS
import qualified Data.Text.IO as TextIO
import qualified Data.Text as Text
import Data.Text (Text)

main :: IO ()
main = do
  putStrLn "=== CORRECT COMPLEX CONCAT AST ==="
  correctContent <- TextIO.readFile "correct_complex_concat.js"
  case JS.parse (Text.unpack correctContent) "correct" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> putStrLn $ show ast
  
  putStrLn "\n=== WRONG COMPLEX CONCAT AST ==="
  wrongContent <- TextIO.readFile "wrong_complex_concat.js"
  case JS.parse (Text.unpack wrongContent) "wrong" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> putStrLn $ show ast