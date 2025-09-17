{-# LANGUAGE OverloadedStrings #-}

import qualified Language.JavaScript.Parser as JS
import qualified Language.JavaScript.Pretty.Printer as JSP
import qualified Language.JavaScript.Parser.AST as AST

-- Test what the correct array structure should be
main :: IO ()
main = do
  putStrLn "Testing array AST structure..."
  
  -- Parse a simple array to see its structure
  case JS.parse "var arr = [1, 2];" "" of
    Left err -> putStrLn ("Parse error: " ++ show err)
    Right (AST.JSAstProgram statements _) -> do
      putStrLn "Parsed AST structure:"
      mapM_ (putStrLn . show) statements
      
  putStrLn "\nTesting compact array:"  
  case JS.parse "var arr = [1,2];" "" of
    Left err -> putStrLn ("Parse error: " ++ show err)
    Right (AST.JSAstProgram statements _) -> do
      putStrLn "Compact AST structure:"
      mapM_ (putStrLn . show) statements