#!/usr/bin/env stack
{- stack script --resolver lts-21.7
    --package language-javascript
    --package bytestring
    --package text
-}

{-# LANGUAGE OverloadedStrings #-}

import qualified Language.JavaScript.Parser as JS
import qualified Language.JavaScript.Pretty.Printer as JSP
import qualified Data.ByteString.Char8 as BS

-- Test string with the expected formatting
testJS1 = "var output=$elm$core$String$fromInt(result1)+(' '+result2);"
testJS2 = "var $elm$virtual_dom$VirtualDom$text=_VirtualDom_text;"

main :: IO ()
main = do
  putStrLn "=== Parsing test JS 1 ==="
  putStrLn testJS1
  case JS.parse testJS1 "test" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> do
      putStrLn "AST:"
      print ast
      putStrLn "\nRe-rendered:"
      putStrLn $ JSP.renderToString ast

  putStrLn "\n=== Parsing test JS 2 ==="
  putStrLn testJS2
  case JS.parse testJS2 "test" of
    Left err -> putStrLn $ "Parse error: " ++ show err
    Right ast -> do
      putStrLn "AST:"
      print ast
      putStrLn "\nRe-rendered:"
      putStrLn $ JSP.renderToString ast