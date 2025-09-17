{-# LANGUAGE OverloadedStrings #-}

import qualified Language.JavaScript.Parser as JS
import qualified Data.Text.IO as TextIO
import qualified Data.Text as Text
import Data.Text (Text)

main :: IO ()
main = do
  putStrLn "=== COMPLEX ARITHMETIC AST ==="
  content <- TextIO.readFile "correct_arithmetic.js"
  case JS.parse (Text.unpack content) "arithmetic" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> putStrLn $ show ast