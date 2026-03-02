module Golden.ParseAliasGolden (tests) where

import qualified AST.Source as Src
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.List as List
import qualified Canopy.Data.Name as Name
import qualified Parse.Module as ParseModule
import qualified Reporting.Annotation as Ann
import Test.Tasty
import Test.Tasty.Golden

tests :: TestTree
tests =
  testGroup
    "Golden.ParseAlias"
    [goldenAlias "Alias" "test/Golden/sources/Alias.can" "test/Golden/expected/Alias.golden"]

goldenAlias :: String -> FilePath -> FilePath -> TestTree
goldenAlias name srcPath goldenPath =
  goldenVsString name goldenPath $ do
    src <- BS.readFile srcPath
    case ParseModule.fromByteString ParseModule.Application src of
      Left err -> pure (BL8.pack ("Parse error: " <> (show err <> "\n")))
      Right modul -> pure (BL8.pack (aliasSummary modul <> "\n"))

aliasSummary :: Src.Module -> String
aliasSummary modul =
  let items = fmap summarize (Src._aliases modul)
   in List.intercalate "\n" (List.sort items)

summarize :: Ann.Located Src.Alias -> String
summarize (Ann.At _ (Src.Alias (Ann.At _ n) tvars _ tipe maybeBound)) =
  let header = (Name.toChars n <> ("/vars=" <> show (length tvars)))
      boundStr = maybe "" (\b -> " bound=" <> showBound b) maybeBound
   in (header <> (" " <> body tipe <> boundStr))

-- | Render a supertype bound as a short string for golden output.
showBound :: Src.SupertypeBound -> String
showBound Src.ComparableBound = "comparable"
showBound Src.AppendableBound = "appendable"
showBound Src.NumberBound = "number"
showBound Src.CompAppendBound = "compappend"

body :: Src.Type -> String
body (Ann.At _ t) =
  case t of
    Src.TRecord fields ext ->
      "fields=[" <> (List.intercalate "," (fmap field fields) <> ("]" <> maybe "" (const " ext") ext))
    Src.TTuple _ _ rest -> "tuple=len" <> show (2 + length rest)
    Src.TType _ name args -> "type=" <> (Name.toChars name <> argsS args)
    Src.TTypeQual _ _ name args -> "type=" <> (Name.toChars name <> argsS args)
    Src.TLambda _ _ -> "lambda"
    Src.TVar v -> "var=" <> Name.toChars v
    Src.TUnit -> "unit"

argsS :: [Src.Type] -> String
argsS args = if null args then "" else "<" <> (show (length args) <> ">")

field :: (Ann.Located Name.Name, Src.Type) -> String
field (Ann.At _ n, t) = Name.toChars n <> (":" <> fieldType t)

fieldType :: Src.Type -> String
fieldType (Ann.At _ t) =
  case t of
    Src.TVar v -> Name.toChars v
    Src.TType _ name _ -> Name.toChars name
    Src.TTypeQual _ _ name _ -> Name.toChars name
    Src.TTuple _ _ rest -> "Tuple" <> show (2 + length rest)
    Src.TRecord _ _ -> "Record"
    Src.TLambda _ _ -> "Func"
    Src.TUnit -> "Unit"
