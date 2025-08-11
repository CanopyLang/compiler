module Golden.ParseExprGolden (tests) where

import qualified Parse.Expression as Expr
import qualified Parse.Primitives as P
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Syntax as E
import qualified AST.Source as Src
import qualified Data.ByteString.Char8 as C8
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.List as List
import Test.Tasty
import Test.Tasty.Golden

tests :: TestTree
tests =
  testGroup
    "Golden.ParseExpr"
    [ goldenExpr "LambdaTupleMap" "List.map (\\(x,y) -> x) [ (1,2), (3,4) ]" "test/Golden/expected/Expr_LambdaTupleMap.golden",
      goldenExpr "RecordUpdate" "{ r | a = 1, b = 2 }" "test/Golden/expected/Expr_RecordUpdate.golden"
    ]

goldenExpr :: String -> String -> FilePath -> TestTree
goldenExpr name src path =
  goldenVsString name path $ do
    let bs = C8.pack src
    case P.fromByteString Expr.expression (\r c -> E.Start r c) bs of
      Left err -> pure (BL8.pack ("Parse error: " ++ show err ++ "\n"))
      Right (expr, _) -> pure (BL8.pack (exprSummary expr ++ "\n"))

exprSummary :: Src.Expr -> String
exprSummary (A.At _ e) = go e
  where
    go v = case v of
      Src.Lambda ps _ -> "Lambda/args=" ++ show (length ps)
      Src.List xs -> "List/len=" ++ show (length xs)
      Src.Update _ fs -> "Update/fields=" ++ show (length fs)
      Src.Record fs -> "Record/fields=" ++ show (length fs)
      Src.Tuple _ _ rest -> "Tuple/len=" ++ show (2 + length rest)
      Src.Binops ops _ -> "Binops/ops=" ++ show (length ops)
      Src.Call _ args -> "Call/args=" ++ show (length args)
      other -> take 16 (show other)
