{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Text as Text
import qualified Language.JavaScript.Parser as JS
import qualified Language.JavaScript.Pretty.Printer as JSP

-- Test array formatting
testArrayFormatting :: IO ()
testArrayFormatting = do
  putStrLn "Testing array formatting..."
  
  -- Test simple array
  let testCode1 = "var arr = [1, 2];"
  case JS.parse testCode1 "" of
    Left err -> putStrLn ("Parse error: " ++ show err)
    Right ast -> do
      let rendered = JSP.renderToString ast
      putStrLn ("Original:  " ++ testCode1)  
      putStrLn ("Rendered:  " ++ rendered)
      
  -- Test without spaces
  let testCode2 = "var arr = [1,2];"
  case JS.parse testCode2 "" of
    Left err -> putStrLn ("Parse error: " ++ show err)
    Right ast -> do
      let rendered = JSP.renderToString ast
      putStrLn ("Original:  " ++ testCode2)  
      putStrLn ("Rendered:  " ++ rendered)

main :: IO ()
main = testArrayFormatting