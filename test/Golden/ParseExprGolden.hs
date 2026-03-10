module Golden.ParseExprGolden (tests) where

import qualified AST.Source as Src
import qualified Data.ByteString.Char8 as C8
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.List as List
import qualified Parse.Expression as Expr
import qualified Parse.Primitives as Parse
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Syntax as SyntaxError
import Test.Tasty
import Test.Tasty.Golden

tests :: TestTree
tests =
  testGroup
    "Golden.ParseExpr"
    [ goldenExpr "LambdaTupleMap" "List.map (\\(x,y) -> x) [ (1,2), (3,4) ]" "test/Golden/expected/Expr_LambdaTupleMap.golden",
      goldenExpr "RecordUpdate" "{ r | a = 1, b = 2 }" "test/Golden/expected/Expr_RecordUpdate.golden",
      goldenExpr "NestedRecordUpdate" "{ r | user { name = 1 }, count = 2 }" "test/Golden/expected/Expr_NestedRecordUpdate.golden",
      goldenExpr "InterpSimple" "`Hello ${name}!`" "test/Golden/expected/Expr_InterpSimple.golden",
      goldenExpr "InterpMulti" "`${a} and ${b}`" "test/Golden/expected/Expr_InterpMulti.golden",
      goldenExpr "InterpPlain" "`just text`" "test/Golden/expected/Expr_InterpPlain.golden",
      goldenExpr "InterpEmpty" "``" "test/Golden/expected/Expr_InterpEmpty.golden"
    ]

goldenExpr :: String -> String -> FilePath -> TestTree
goldenExpr name src path =
  goldenVsString name path $ do
    let bs = C8.pack src
    case Parse.fromByteString Expr.expression SyntaxError.Start bs of
      Left err -> pure (BL8.pack ("Parse error: " <> (show err <> "\n")))
      Right (expr, _) -> pure (BL8.pack (exprSummary expr <> "\n"))

exprSummary :: Src.Expr -> String
exprSummary (Ann.At _ e) = go e
  where
    go v = case v of
      Src.Lambda ps _ -> "Lambda/args=" <> show (length ps)
      Src.List xs -> "List/len=" <> show (length xs)
      Src.Update _ fs -> "Update/fields=" <> show (length fs) <> fieldDetails fs
      Src.Record fs -> "Record/fields=" <> show (length fs)
      Src.Tuple _ _ rest -> "Tuple/len=" <> show (2 + length rest)
      Src.Binops ops _ -> "Binops/ops=" <> show (length ops)
      Src.Call _ args -> "Call/args=" <> show (length args)
      Src.Interpolation segs -> "Interpolation/segs=" <> show (length segs) <> segDetails segs
      other -> take 16 (show other)

fieldDetails :: [(Ann.Located a, Src.FieldUpdate)] -> String
fieldDetails fs = "[" <> List.intercalate "," (map fieldSummary fs) <> "]"

fieldSummary :: (Ann.Located a, Src.FieldUpdate) -> String
fieldSummary (_, Src.FieldValue _) = "flat"
fieldSummary (_, Src.FieldNested subs) = "nested(" <> show (length subs) <> ")"

segDetails :: [Src.InterpolationSegment] -> String
segDetails segs = "[" <> List.intercalate "," (map segSummary segs) <> "]"

segSummary :: Src.InterpolationSegment -> String
segSummary (Src.IStr _) = "str"
segSummary (Src.IExpr _) = "expr"
