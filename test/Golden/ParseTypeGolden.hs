module Golden.ParseTypeGolden (tests) where

import qualified AST.Source as Src
import qualified Data.ByteString.Char8 as C8
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Parse.Primitives as P
import qualified Parse.Type as Ty
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Syntax as E
import Test.Tasty
import Test.Tasty.Golden

tests :: TestTree
tests =
  testGroup
    "Golden.ParseType"
    [ goldenType "NestedRecordFunc" "{ r | a : { s | b : List (Maybe Int) } } -> Result x y" "test/Golden/expected/Type_NestedRecordFunc.golden"
    ]

goldenType :: String -> String -> FilePath -> TestTree
goldenType name src path =
  goldenVsString name path $ do
    let bs = C8.pack src
    case P.fromByteString Ty.expression E.TIndentStart bs of
      Left err -> pure (BL8.pack ("Parse error: " <> (show err <> "\n")))
      Right (tipe, _) -> pure (BL8.pack (typeSummary tipe <> "\n"))

typeSummary :: Src.Type -> String
typeSummary (A.At _ t) = go t
  where
    go v = case v of
      Src.TLambda _ _ -> "TLambda"
      Src.TRecord fs ext -> "TRecord/fields=" <> (show (length fs) <> maybe "" (const "/ext") ext)
      Src.TTuple _ _ rest -> "TTuple/len=" <> show (2 + length rest)
      Src.TType _ _ args -> "TType/args=" <> show (length args)
      other -> take 16 (show other)
