module Golden.ParseModuleGolden (tests) where

import qualified AST.Source as Src
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.List as List
import qualified Data.Maybe as Maybe
import qualified Canopy.Data.Name as Name
import qualified Parse.Module as ParseModule
import qualified Reporting.Annotation as Ann
import Test.Tasty
import Test.Tasty.Golden

tests :: TestTree
tests =
  testGroup
    "Golden.ParseModule"
    [ goldenModule "Utils" "test/Golden/sources/Utils.canopy" "test/Golden/expected/Utils.golden",
      goldenModule "Shapes" "test/Golden/sources/Shapes.canopy" "test/Golden/expected/Shapes.golden",
      goldenModule "Ops" "test/Golden/sources/Ops.can" "test/Golden/expected/Ops.golden"
    ]

goldenModule :: String -> FilePath -> FilePath -> TestTree
goldenModule name srcPath goldenPath =
  goldenVsString name goldenPath $ do
    src <- BS.readFile srcPath
    case ParseModule.fromByteString ParseModule.Application src of
      Left err -> pure (BL8.pack ("Parse error: " <> show err))
      Right modul -> pure (BL8.pack (summary modul))

summary :: Src.Module -> String
summary modul =
  List.intercalate
    "\n"
    [ "Module: " <> Name.toChars (Src.getName modul),
      "Exports: " <> exportsSummary modul,
      "Values: " <> comma (List.sort (fmap (Name.toChars . getValName) (Src._values modul))),
      "Aliases: " <> comma (List.sort (fmap aliasWithVars (Src._aliases modul))),
      "Unions: " <> comma (List.sort (fmap showUnion (Src._unions modul))),
      "Imports: " <> showListImport (Src._imports modul)
    ]
    <> "\n"

comma :: [String] -> String
comma = List.intercalate ","

getValName :: Ann.Located Src.Value -> Name.Name
getValName (Ann.At _ (Src.Value (Ann.At _ n) _ _ _ _)) = n

aliasWithVars :: Ann.Located Src.Alias -> String
aliasWithVars (Ann.At _ (Src.Alias (Ann.At _ n) tvars _ _)) =
  Name.toChars n <> ("(" <> (show (length tvars) <> ")"))

showUnion :: Ann.Located Src.Union -> String
showUnion (Ann.At _ (Src.Union (Ann.At _ n) _ ctors)) =
  Name.toChars n <> ("(" <> (comma (fmap (\(Ann.At _ cn, _) -> Name.toChars cn) ctors) <> ")"))

showListImport :: [Src.Import] -> String
showListImport is =
  let lists = [i | i@(Src.Import (Ann.At _ n) _ _ _) <- is, n == Name.list]
      pick =
        case filter hasAlias lists of
          (x : _) -> x
          [] -> case filter hasExplicit lists of
            (x : _) -> x
            [] -> case lists of
              (x : _) -> x
              [] -> error "no List import"
      hasAlias (Src.Import _ alias _ _) = Maybe.isJust alias
      hasExplicit (Src.Import _ _ exposing _) = case exposing of
        Src.Open -> False
        Src.Explicit _ -> True
   in case pick of
        Src.Import (Ann.At _ _) alias exposing _ ->
          let aliasStr = maybe "" (\a -> " as " <> Name.toChars a) alias
              expoStr = case exposing of
                Src.Open -> " exposing(..)"
                Src.Explicit _ -> " exposing(explicit)"
           in ("List" <> (aliasStr <> expoStr))

exportsSummary :: Src.Module -> String
exportsSummary m =
  case Src._exports m of
    Ann.At _ Src.Open -> "Open"
    Ann.At _ (Src.Explicit xs) ->
      let lowers = length [() | Src.Lower _ <- xs]
          uppOpen = length [() | Src.Upper _ (Src.Public _) <- xs]
          uppClosed = length [() | Src.Upper _ Src.Private <- xs]
          ops = length [() | Src.Operator _ _ <- xs]
       in ("Explicit lower=" <> (show lowers <> (" upperOpen=" <> (show uppOpen <> (" upperClosed=" <> (show uppClosed <> (" operators=" <> show ops)))))))
