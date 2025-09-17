{-# LANGUAGE OverloadedStrings #-}

import qualified Language.JavaScript.Parser as JS
import qualified Data.Text.IO as TextIO
import qualified Data.Text as Text
import Data.Text (Text)

main :: IO ()
main = do
  putStrLn "=== RECORD OBJECT AST ==="
  content <- TextIO.readFile "simple_record.js"
  case JS.parse (Text.unpack content) "record" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> putStrLn $ show ast