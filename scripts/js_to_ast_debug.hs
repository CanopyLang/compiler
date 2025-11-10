#!/usr/bin/env stack
{- stack script
   --resolver lts-22.28
   --package language-javascript
   --package text
   --package pretty-show
   --package bytestring
-}

{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy.Char8 as L8
import qualified Language.JavaScript.Parser as JS
import qualified Language.JavaScript.Pretty.Printer as JSPrint
import Text.Show.Pretty (ppShow)
import System.Environment (getArgs)
import System.Exit (exitFailure)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [jsString] -> do
      putStrLn "=== JavaScript Input ==="
      putStrLn jsString
      putStrLn ""

      case JS.parse jsString "debug" of
        Left err -> do
          putStrLn "=== Parse Error ==="
          print err
          exitFailure
        Right ast -> do
          putStrLn "=== Raw AST ==="
          putStrLn (ppShow ast)
          putStrLn ""

          putStrLn "=== Pretty-printed JavaScript ==="
          putStrLn (L8.unpack $ Builder.toLazyByteString $ JSPrint.renderJS ast)

    _ -> do
      putStrLn "Usage: js_to_ast_debug.hs \"<javascript-code>\""
      putStrLn ""
      putStrLn "Examples:"
      putStrLn "  js_to_ast_debug.hs \"var x = F2(function(a,b){return a+b;});\""
      putStrLn "  js_to_ast_debug.hs \"var x = function(a){return a;};\""
      putStrLn "  js_to_ast_debug.hs \"(function(){var x=1;})();\""
      putStrLn ""
      putStrLn "Debug patterns:"
      putStrLn "  js_to_ast_debug.hs \"var \\$elm\\$core\\$Array\\$compressNodes=F2(function(nodes,acc){compressNodes:while(true){return nodes;}});\""
      exitFailure