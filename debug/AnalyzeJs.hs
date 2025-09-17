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
    Right ast -> putStrLn $ show ast
  
  putStrLn "\n=== CURRENT TERNARY AST ==="
  currentContent <- TextIO.readFile "current_ternary.js"
  case JS.parse (Text.unpack currentContent) "current" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> putStrLn $ show ast