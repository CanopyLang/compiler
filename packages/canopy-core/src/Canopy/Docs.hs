{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE UnboxedTuples #-}

module Canopy.Docs
  ( Documentation,
    Module (..),
    Comment,
    fromModule,
    Union (..),
    Alias (..),
    Value (..),
    Binop (..),
    Binop.Associativity (..),
    Binop.Precedence (..),
    Error (..),
    decoder,
    encode,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified AST.Utils.Binop as Binop
import qualified Canopy.Compiler.Type as Type
import qualified Canopy.Compiler.Type.Extract as Extract
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Coerce as Coerce
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Map.Merge.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.NonEmptyList as NE
import qualified Canopy.Data.OneOrMore as OneOrMore
import Data.Word (Word8)
import Foreign.Ptr (Ptr, plusPtr)
import qualified Json.Decode as Decode
import Json.Encode ((==>))
import qualified Json.Encode as Encode
import qualified Json.String as Json
import Parse.Primitives (Col, Row, word1)
import qualified Parse.Primitives as Parse
import qualified Parse.Space as Space
import qualified Parse.Symbol as Symbol
import qualified Parse.Variable as Var
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Docs as DocsError
import qualified Reporting.Result as Result

-- DOCUMENTATION

type Documentation =
  Map.Map Name.Name Module

data Module = Module
  { _name :: Name.Name,
    _comment :: Comment,
    _unions :: Map.Map Name.Name Union,
    _aliases :: Map.Map Name.Name Alias,
    _values :: Map.Map Name.Name Value,
    _binops :: Map.Map Name.Name Binop
  }

type Comment = Json.String

data Alias = Alias Comment [Name.Name] Type.Type

data Union = Union Comment [Name.Name] [(Name.Name, [Type.Type])]

data Value = Value Comment Type.Type

data Binop = Binop Comment Type.Type Binop.Associativity Binop.Precedence

-- JSON

encode :: Documentation -> Encode.Value
encode docs =
  Encode.list encodeModule (Map.elems docs)

encodeModule :: Module -> Encode.Value
encodeModule (Module name comment unions aliases values binops) =
  Encode.object
    [ "name" ==> ModuleName.encode name,
      "comment" ==> Encode.string comment,
      "unions" ==> Encode.list encodeUnion (Map.toList unions),
      "aliases" ==> Encode.list encodeAlias (Map.toList aliases),
      "values" ==> Encode.list encodeValue (Map.toList values),
      "binops" ==> Encode.list encodeBinop (Map.toList binops)
    ]

data Error
  = BadAssociativity
  | BadModuleName
  | BadType

decoder :: Decode.Decoder Error Documentation
decoder =
  toDict <$> Decode.list moduleDecoder

toDict :: [Module] -> Documentation
toDict modules =
  Map.fromList (fmap toDictHelp modules)

toDictHelp :: Module -> (Name.Name, Module)
toDictHelp modul@(Module name _ _ _ _ _) =
  (name, modul)

moduleDecoder :: Decode.Decoder Error Module
moduleDecoder =
  Module
    <$> Decode.field "name" moduleNameDecoder
    <*> Decode.field "comment" Decode.string
    <*> Decode.field "unions" (dictDecoder union)
    <*> Decode.field "aliases" (dictDecoder alias)
    <*> Decode.field "values" (dictDecoder value)
    <*> Decode.field "binops" (dictDecoder binop)

dictDecoder :: Decode.Decoder Error a -> Decode.Decoder Error (Map.Map Name.Name a)
dictDecoder entryDecoder =
  Map.fromList <$> Decode.list (named entryDecoder)

named :: Decode.Decoder Error a -> Decode.Decoder Error (Name.Name, a)
named entryDecoder =
  (,)
    <$> Decode.field "name" nameDecoder
    <*> entryDecoder

nameDecoder :: Decode.Decoder e Name.Name
nameDecoder =
  fmap Coerce.coerce Decode.string

moduleNameDecoder :: Decode.Decoder Error ModuleName.Raw
moduleNameDecoder =
  Decode.mapError (const BadModuleName) ModuleName.decoder

typeDecoder :: Decode.Decoder Error Type.Type
typeDecoder =
  Decode.mapError (const BadType) Type.decoder

-- UNION JSON

encodeUnion :: (Name.Name, Union) -> Encode.Value
encodeUnion (name, Union comment args cases) =
  Encode.object
    [ "name" ==> Encode.name name,
      "comment" ==> Encode.string comment,
      "args" ==> Encode.list Encode.name args,
      "cases" ==> Encode.list encodeCase cases
    ]

union :: Decode.Decoder Error Union
union =
  Union
    <$> Decode.field "comment" Decode.string
    <*> Decode.field "args" (Decode.list nameDecoder)
    <*> Decode.field "cases" (Decode.list caseDecoder)

encodeCase :: (Name.Name, [Type.Type]) -> Encode.Value
encodeCase (tag, args) =
  Encode.list id [Encode.name tag, Encode.list Type.encode args]

caseDecoder :: Decode.Decoder Error (Name.Name, [Type.Type])
caseDecoder =
  Decode.pair nameDecoder (Decode.list typeDecoder)

-- ALIAS JSON

encodeAlias :: (Name.Name, Alias) -> Encode.Value
encodeAlias (name, Alias comment args tipe) =
  Encode.object
    [ "name" ==> Encode.name name,
      "comment" ==> Encode.string comment,
      "args" ==> Encode.list Encode.name args,
      "type" ==> Type.encode tipe
    ]

alias :: Decode.Decoder Error Alias
alias =
  Alias
    <$> Decode.field "comment" Decode.string
    <*> Decode.field "args" (Decode.list nameDecoder)
    <*> Decode.field "type" typeDecoder

-- VALUE JSON

encodeValue :: (Name.Name, Value) -> Encode.Value
encodeValue (name, Value comment tipe) =
  Encode.object
    [ "name" ==> Encode.name name,
      "comment" ==> Encode.string comment,
      "type" ==> Type.encode tipe
    ]

value :: Decode.Decoder Error Value
value =
  Value
    <$> Decode.field "comment" Decode.string
    <*> Decode.field "type" typeDecoder

-- BINOP JSON

encodeBinop :: (Name.Name, Binop) -> Encode.Value
encodeBinop (name, Binop comment tipe assoc prec) =
  Encode.object
    [ "name" ==> Encode.name name,
      "comment" ==> Encode.string comment,
      "type" ==> Type.encode tipe,
      "associativity" ==> encodeAssoc assoc,
      "precedence" ==> encodePrec prec
    ]

binop :: Decode.Decoder Error Binop
binop =
  Binop
    <$> Decode.field "comment" Decode.string
    <*> Decode.field "type" typeDecoder
    <*> Decode.field "associativity" assocDecoder
    <*> Decode.field "precedence" precDecoder

-- ASSOCIATIVITY JSON

encodeAssoc :: Binop.Associativity -> Encode.Value
encodeAssoc assoc =
  case assoc of
    Binop.Left -> Encode.chars "left"
    Binop.Non -> Encode.chars "non"
    Binop.Right -> Encode.chars "right"

assocDecoder :: Decode.Decoder Error Binop.Associativity
assocDecoder =
  let left = Json.fromChars "left"
      non = Json.fromChars "non"
      right = Json.fromChars "right"
   in do
        str <- Decode.string
        if
            | str == left -> return Binop.Left
            | str == non -> return Binop.Non
            | str == right -> return Binop.Right
            | otherwise -> Decode.failure BadAssociativity

-- PRECEDENCE JSON

encodePrec :: Binop.Precedence -> Encode.Value
encodePrec (Binop.Precedence n) =
  Encode.int n

precDecoder :: Decode.Decoder Error Binop.Precedence
precDecoder =
  Binop.Precedence <$> Decode.int

-- FROM MODULE

fromModule :: Can.Module -> IO (Either DocsError.Error Module)
fromModule modul@(Can.Module _ exports docs _ _ _ _ _ _ _) =
  case exports of
    Can.ExportEverything region ->
      pure (Left (DocsError.ImplicitExposing region))
    Can.Export exportDict ->
      fromModuleDocs modul exportDict docs

fromModuleDocs :: Can.Module -> Map.Map Name.Name (Ann.Located Can.Export) -> Src.Docs -> IO (Either DocsError.Error Module)
fromModuleDocs _ _ (Src.NoDocs region) =
  pure (Left (DocsError.NoDocs region))
fromModuleDocs modul exportDict (Src.YesDocs overview comments) =
  either (pure . Left) (validateAndBuild modul exportDict overview comments) (parseOverview overview)

validateAndBuild :: Can.Module -> Map.Map Name.Name (Ann.Located Can.Export) -> Src.Comment -> [(Name.Name, Src.Comment)] -> [Ann.Located Name.Name] -> IO (Either DocsError.Error Module)
validateAndBuild modul exportDict overview comments names =
  either (pure . Left) (const (checkDefsIO exportDict overview (Map.fromList comments) modul)) (checkNames exportDict names)

-- PARSE OVERVIEW

parseOverview :: Src.Comment -> Either DocsError.Error [Ann.Located Name.Name]
parseOverview (Src.Comment snippet) =
  case Parse.fromSnippet (chompOverview []) DocsError.BadEnd snippet of
    Left err ->
      Left (DocsError.SyntaxProblem err)
    Right names ->
      Right names

type Parser a =
  Parse.Parser DocsError.SyntaxProblem a

chompOverview :: [Ann.Located Name.Name] -> Parser [Ann.Located Name.Name]
chompOverview names =
  do
    isDocs <- chompUntilDocs
    if isDocs
      then do
        Space.chomp DocsError.Space
        chompDocs names >>= chompOverview
      else return names

chompDocs :: [Ann.Located Name.Name] -> Parser [Ann.Located Name.Name]
chompDocs names =
  do
    name <-
      Parse.addLocation $
        Parse.oneOf
          DocsError.Name
          [ Var.lower DocsError.Name,
            Var.upper DocsError.Name,
            chompOperator
          ]

    Space.chomp DocsError.Space

    Parse.oneOfWithFallback
      [ do
          pos <- Parse.getPosition
          Space.checkIndent pos DocsError.Comma
          word1 0x2C {-,-} DocsError.Comma
          Space.chomp DocsError.Space
          chompDocs (name : names)
      ]
      (name : names)

chompOperator :: Parser Name.Name
chompOperator =
  do
    word1 0x28 {-(-} DocsError.Op
    op <- Symbol.operator DocsError.Op DocsError.OpBad
    word1 0x29 {-)-} DocsError.Op
    return op

-- Consider requiring @docs to appear after newline in a future version.
--
chompUntilDocs :: Parser Bool
chompUntilDocs =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ _ ->
    let (# isDocs, newPos, newRow, newCol #) = untilDocs pos end row col
        !newState = Parse.State src newPos end indent newRow newCol
     in cok isDocs newState

untilDocs :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> (# Bool, Ptr Word8, Row, Col #)
untilDocs pos end row col =
  if pos >= end
    then (# False, pos, row, col #)
    else
      let !word = Parse.unsafeIndex pos
       in if word == 0x0A {-\n-}
            then untilDocs (plusPtr pos 1) end (row + 1) 1
            else
              let !pos5 = plusPtr pos 5
               in if pos5 <= end
                    && Parse.unsafeIndex (pos) == 0x40 {-@-}
                    && Parse.unsafeIndex (plusPtr pos 1) == 0x64 {-d-}
                    && Parse.unsafeIndex (plusPtr pos 2) == 0x6F {-o-}
                    && Parse.unsafeIndex (plusPtr pos 3) == 0x63 {-c-}
                    && Parse.unsafeIndex (plusPtr pos 4) == 0x73 {-s-}
                    && Var.getInnerWidth pos5 end == 0
                    then (# True, pos5, row, col + 5 #)
                    else
                      let !newPos = plusPtr pos (Parse.getCharWidth word)
                       in untilDocs newPos end row (col + 1)

-- CHECK NAMES

checkNames :: Map.Map Name.Name (Ann.Located Can.Export) -> [Ann.Located Name.Name] -> Either DocsError.Error ()
checkNames exports names =
  let docs = List.foldl' addName Map.empty names
      loneDoc = Map.traverseMissing onlyInDocs
      loneExport = Map.traverseMissing onlyInExports
      checkBoth = Map.zipWithAMatched (\n _ r -> isUnique n r)
   in case Result.run (Map.mergeA loneExport loneDoc checkBoth exports docs) of
        (_, Right _) -> Right ()
        (_, Left es) -> Left (DocsError.NameProblems (OneOrMore.destruct NE.List es))

type DocNameRegions =
  Map.Map Name.Name (OneOrMore.OneOrMore Ann.Region)

addName :: DocNameRegions -> Ann.Located Name.Name -> DocNameRegions
addName dict (Ann.At region name) =
  Map.insertWith OneOrMore.more name (OneOrMore.one region) dict

isUnique :: Name.Name -> OneOrMore.OneOrMore Ann.Region -> Result.Result i w DocsError.NameProblem Ann.Region
isUnique name regions =
  case regions of
    OneOrMore.One region ->
      Result.ok region
    OneOrMore.More left right ->
      let (r1, r2) = OneOrMore.getFirstTwo left right
       in Result.throw (DocsError.NameDuplicate name r1 r2)

onlyInDocs :: Name.Name -> OneOrMore.OneOrMore Ann.Region -> Result.Result i w DocsError.NameProblem a
onlyInDocs name regions =
  do
    region <- isUnique name regions
    Result.throw $ DocsError.NameOnlyInDocs name region

onlyInExports :: Name.Name -> Ann.Located Can.Export -> Result.Result i w DocsError.NameProblem a
onlyInExports name (Ann.At region _) =
  Result.throw $ DocsError.NameOnlyInExports name region

-- CHECK DEFS (DEPRECATED - use checkDefsIO)

-- | Thread-safe version of checkDefs that handles IO for comment processing
checkDefsIO :: Map.Map Name.Name (Ann.Located Can.Export) -> Src.Comment -> Map.Map Name.Name Src.Comment -> Can.Module -> IO (Either DocsError.Error Module)
checkDefsIO exportDict overview comments (Can.Module name _ _ decls unions aliases infixes effects _ _) = do
  let types = gatherTypes decls Map.empty
      info = Info comments types unions aliases infixes effects
  case Result.run (Map.traverseWithKey (checkExportIO info) exportDict) of
    (_, Left problems) -> pure $ Left $ DocsError.DefProblems (OneOrMore.destruct NE.List problems)
    (_, Right ioInserters) -> do
      inserters <- sequence ioInserters
      emptyMod <- emptyModule name overview
      pure $ Right $ foldr ($) emptyMod inserters

emptyModule :: ModuleName.Canonical -> Src.Comment -> IO Module
emptyModule (ModuleName.Canonical _ name) (Src.Comment overview) = do
  processedOverview <- Json.fromComment overview
  pure $ Module name processedOverview Map.empty Map.empty Map.empty Map.empty


data Info = Info
  { _iComments :: Map.Map Name.Name Src.Comment,
    _iValues :: Map.Map Name.Name (Either Ann.Region Can.Type),
    _iUnions :: Map.Map Name.Name Can.Union,
    _iAliases :: Map.Map Name.Name Can.Alias,
    _iBinops :: Map.Map Name.Name Can.Binop,
    _iEffects :: Can.Effects
  }


-- | Thread-safe version of checkExport that handles IO for comment processing
checkExportIO :: Info -> Name.Name -> Ann.Located Can.Export -> Result.Result i w DocsError.DefProblem (IO (Module -> Module))
checkExportIO info name (Ann.At region export) =
  case export of
    Can.ExportValue ->
      do
        tipe <- getType name info
        Result.ok $ do
          comment <- getCommentIO region name info
          pure $ \m -> m {_values = Map.insert name (Value comment tipe) (_values m)}
    Can.ExportBinop ->
      do
        (Can.Binop_ assoc prec realName) <- lookupOrThrow name "binop" (_iBinops info)
        tipe <- getType realName info
        Result.ok $ do
          comment <- getCommentIO region realName info
          pure $ \m -> m {_binops = Map.insert name (Binop comment tipe assoc prec) (_binops m)}
    Can.ExportAlias ->
      do
        (Can.Alias tvars _ tipe _ _) <- lookupOrThrow name "alias" (_iAliases info)
        Result.ok $ do
          comment <- getCommentIO region name info
          pure $ \m -> m {_aliases = Map.insert name (Alias comment tvars (Extract.fromType tipe)) (_aliases m)}
    Can.ExportUnionOpen ->
      do
        (Can.Union tvars _ ctors _ _ _) <- lookupOrThrow name "union" (_iUnions info)
        Result.ok $ do
          comment <- getCommentIO region name info
          pure $ \m -> m {_unions = Map.insert name (Union comment tvars (fmap dector ctors)) (_unions m)}
    Can.ExportUnionClosed ->
      do
        (Can.Union tvars _ _ _ _ _) <- lookupOrThrow name "union" (_iUnions info)
        Result.ok $ do
          comment <- getCommentIO region name info
          pure $ \m -> m {_unions = Map.insert name (Union comment tvars []) (_unions m)}
    Can.ExportPort ->
      do
        tipe <- getType name info
        Result.ok $ do
          comment <- getCommentIO region name info
          pure $ \m -> m {_values = Map.insert name (Value comment tipe) (_values m)}


-- | Thread-safe version of getComment that handles IO for comment processing.
-- Returns an empty comment if the name is not found, rather than crashing.
getCommentIO :: Ann.Region -> Name.Name -> Info -> IO Comment
getCommentIO _region name info =
  case Map.lookup name (_iComments info) of
    Nothing ->
      pure (Json.fromChars "")
    Just (Src.Comment snippet) ->
      Json.fromComment snippet

-- | Look up a value type from the info map, throwing a recoverable error
-- instead of crashing if the name is not found.
getType :: Name.Name -> Info -> Result.Result i w DocsError.DefProblem Type.Type
getType name info =
  case Map.lookup name (_iValues info) of
    Nothing ->
      Result.throw (DocsError.InternalLookupFailure name "Value type missing from module info. Every exported value must have a type entry.")
    Just (Left region) ->
      Result.throw (DocsError.NoAnnotation name region)
    Just (Right tipe) ->
      Result.ok (Extract.fromType tipe)

-- | Look up a value in a map, throwing a recoverable DefProblem error
-- instead of crashing if the key is not found.
lookupOrThrow :: Name.Name -> Text.Text -> Map.Map Name.Name v -> Result.Result i w DocsError.DefProblem v
lookupOrThrow name category dict =
  case Map.lookup name dict of
    Nothing ->
      Result.throw (DocsError.InternalLookupFailure name ("Expected " <> category <> " to be present in module info, but it was not found."))
    Just v ->
      Result.ok v

dector :: Can.Ctor -> (Name.Name, [Type.Type])
dector (Can.Ctor name _ _ args) =
  (name, fmap Extract.fromType args)

-- GATHER TYPES

type Types =
  Map.Map Name.Name (Either Ann.Region Can.Type)

gatherTypes :: Can.Decls -> Types -> Types
gatherTypes decls types =
  case decls of
    Can.Declare def subDecls ->
      gatherTypes subDecls (addDef types def)
    Can.DeclareRec def defs subDecls ->
      gatherTypes subDecls (List.foldl' addDef (addDef types def) defs)
    Can.SaveTheEnvironment ->
      types

addDef :: Types -> Can.Def -> Types
addDef types def =
  case def of
    Can.Def (Ann.At region name) _ _ ->
      Map.insert name (Left region) types
    Can.TypedDef (Ann.At _ name) _ typedArgs _ resultType ->
      let tipe = foldr (Can.TLambda . snd) resultType typedArgs
       in Map.insert name (Right tipe) types
