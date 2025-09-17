{-# LANGUAGE OverloadedStrings #-}

import qualified Language.JavaScript.Pretty.Printer as JSP
import qualified Generate.JavaScript.Builder as Builder
import qualified Generate.JavaScript.Name as Name
import qualified Data.ByteString.Builder as B

-- Test simple cases to understand spacing
testSpacing :: IO ()
testSpacing = do
  putStrLn "=== Testing Current Spacing Issues ==="
  
  -- Test binary expression
  let binaryExpr = Builder.Infix Builder.OpAdd (Builder.Ref (Name.fromLocal "x")) (Builder.Ref (Name.fromLocal "y"))
  putStrLn $ "Binary expr result: " ++ (show $ B.toLazyByteString $ Builder.exprToBuilder binaryExpr)
  
  -- Test function call with arguments  
  let funcCall = Builder.Call (Builder.Ref (Name.fromLocal "f")) [Builder.Ref (Name.fromLocal "a"), Builder.Ref (Name.fromLocal "b")]
  putStrLn $ "Function call result: " ++ (show $ B.toLazyByteString $ Builder.exprToBuilder funcCall)
  
  -- Test array
  let arrayExpr = Builder.Array [Builder.Ref (Name.fromLocal "x"), Builder.Ref (Name.fromLocal "y"), Builder.Ref (Name.fromLocal "z")]
  putStrLn $ "Array result: " ++ (show $ B.toLazyByteString $ Builder.exprToBuilder arrayExpr)

main :: IO ()
main = testSpacing