{-# LANGUAGE OverloadedStrings #-}

import qualified Language.JavaScript.Parser as JS
import qualified Data.Text.IO as TextIO
import qualified Data.Text as Text
import Data.Text (Text)

main :: IO ()
main = do
  putStrLn "=== MORE EXPRESSIONS AST ==="
  content <- TextIO.readFile "more_exprs.js"
  case JS.parse (Text.unpack content) "more" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> putStrLn $ show ast