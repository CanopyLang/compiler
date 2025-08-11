module Golden.ParseAliasGolden (tests) where

import qualified AST.Source as Src
import qualified Parse.Module as M
import qualified Reporting.Annotation as A
import qualified Data.ByteString as BS
import qualified Data.List as List
import qualified Data.Name as Name
import Test.Tasty
import Test.Tasty.Golden
import qualified Data.ByteString.Lazy.Char8 as BL8

tests :: TestTree
tests =
  testGroup
    "Golden.ParseAlias"
    [ goldenAlias "Alias" "test/Golden/sources/Alias.can" "test/Golden/expected/Alias.golden" ]

goldenAlias :: String -> FilePath -> FilePath -> TestTree
goldenAlias name srcPath goldenPath =
  goldenVsString name goldenPath $ do
    src <- BS.readFile srcPath
    case M.fromByteString M.Application src of
      Left err -> pure (BL8.pack ("Parse error: " ++ show err ++ "\n"))
      Right modul -> pure (BL8.pack (aliasSummary modul ++ "\n"))

aliasSummary :: Src.Module -> String
aliasSummary modul =
  let items = map summarize (Src._aliases modul)
   in List.intercalate "\n" (List.sort items)

summarize :: A.Located Src.Alias -> String
summarize (A.At _ (Src.Alias (A.At _ n) tvars tipe)) =
  let header = Name.toChars n ++ "/vars=" ++ show (length tvars)
   in header ++ " " ++ body tipe

body :: Src.Type -> String
body (A.At _ t) =
  case t of
    Src.TRecord fields ext ->
      "fields=[" ++ List.intercalate "," (map field fields) ++ "]" ++ maybe "" (const " ext") ext
    Src.TTuple _ _ rest -> "tuple=len" ++ show (2 + length rest)
    Src.TType _ name args -> "type=" ++ Name.toChars name ++ argsS args
    Src.TTypeQual _ _ name args -> "type=" ++ Name.toChars name ++ argsS args
    Src.TLambda _ _ -> "lambda"
    Src.TVar v -> "var=" ++ Name.toChars v

argsS :: [Src.Type] -> String
argsS args = if null args then "" else "<" ++ show (length args) ++ ">"

field :: (A.Located Name.Name, Src.Type) -> String
field (A.At _ n, t) = Name.toChars n ++ ":" ++ fieldType t

fieldType :: Src.Type -> String
fieldType (A.At _ t) =
  case t of
    Src.TVar v -> Name.toChars v
    Src.TType _ name _ -> Name.toChars name
    Src.TTypeQual _ _ name _ -> Name.toChars name
    Src.TTuple _ _ rest -> "Tuple" ++ show (2 + length rest)
    Src.TRecord _ _ -> "Record"
    Src.TLambda _ _ -> "Func"
