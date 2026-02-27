{-# LANGUAGE OverloadedStrings #-}

module Canopy.Compiler.Type
  ( Type (..),
    RT.Context (..),
    toDoc,
    DebugMetadata (..),
    Alias (..),
    Union (..),
    encode,
    decoder,
    encodeMetadata,
  )
where

import qualified AST.Source as Src
import qualified Canopy.Data.Name as Name
import qualified Json.Decode as Decode
import Json.Encode ((==>))
import qualified Json.Encode as Encode
import qualified Json.String as Json
import qualified Parse.Primitives as Parse
import qualified Parse.Type as Type
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import qualified Reporting.Render.Type as RT
import qualified Reporting.Render.Type.Localizer as Localizer

-- TYPES

data Type
  = Lambda Type Type
  | Var Name.Name
  | Type Name.Name [Type]
  | Record [(Name.Name, Type)] (Maybe Name.Name)
  | Unit
  | Tuple Type Type [Type]

data DebugMetadata = DebugMetadata
  { _message :: Type,
    _aliases :: [Alias],
    _unions :: [Union]
  }

data Alias = Alias Name.Name [Name.Name] Type

data Union = Union Name.Name [Name.Name] [(Name.Name, [Type])]

-- TO DOC

toDoc :: Localizer.Localizer -> RT.Context -> Type -> Doc.Doc
toDoc localizer context tipe =
  case tipe of
    Lambda _ _ ->
      let docs = fmap (toDoc localizer RT.Func) (collectLambdas tipe)
          (a, b, cs) = case docs of
            x : y : zs -> (x, y, zs)
            [x] -> (x, Doc.fromChars "()", [])
            [] -> (Doc.fromChars "()", Doc.fromChars "()", [])
       in RT.lambda context a b cs
    Var name ->
      Doc.fromName name
    Unit ->
      "()"
    Tuple a b cs ->
      RT.tuple
        (toDoc localizer RT.None a)
        (toDoc localizer RT.None b)
        (fmap (toDoc localizer RT.None) cs)
    Type name args ->
      RT.apply
        context
        (Doc.fromName name)
        (fmap (toDoc localizer RT.App) args)
    Record fields ext ->
      RT.record
        (fmap (entryToDoc localizer) fields)
        (fmap Doc.fromName ext)

entryToDoc :: Localizer.Localizer -> (Name.Name, Type) -> (Doc.Doc, Doc.Doc)
entryToDoc localizer (field, fieldType) =
  (Doc.fromName field, toDoc localizer RT.None fieldType)

collectLambdas :: Type -> [Type]
collectLambdas tipe =
  case tipe of
    Lambda arg body ->
      arg : collectLambdas body
    _ ->
      [tipe]

-- JSON for TYPE

encode :: Type -> Encode.Value
encode tipe =
  Encode.chars $ Doc.toLine (toDoc Localizer.empty RT.None tipe)

decoder :: Decode.Decoder () Type
decoder =
  let parser =
        Parse.specialize (\_ _ _ -> ()) (fromRawType . fst <$> Type.expression)
   in Decode.customString parser (\_ _ -> ())

fromRawType :: Src.Type -> Type
fromRawType (Ann.At _ astType) =
  case astType of
    Src.TLambda t1 t2 ->
      Lambda (fromRawType t1) (fromRawType t2)
    Src.TVar x ->
      Var x
    Src.TUnit ->
      Unit
    Src.TTuple a b cs ->
      Tuple
        (fromRawType a)
        (fromRawType b)
        (fmap fromRawType cs)
    Src.TType _ name args ->
      Type name (fmap fromRawType args)
    Src.TTypeQual _ _ name args ->
      Type name (fmap fromRawType args)
    Src.TRecord fields ext ->
      let fromField (Ann.At _ field, tipe) = (field, fromRawType tipe)
       in Record
            (fmap fromField fields)
            (fmap Ann.toValue ext)

-- JSON for PROGRAM

encodeMetadata :: DebugMetadata -> Encode.Value
encodeMetadata (DebugMetadata msg aliases unions) =
  Encode.object
    [ "message" ==> encode msg,
      "aliases" ==> Encode.object (fmap toTypeAliasField aliases),
      "unions" ==> Encode.object (fmap toCustomTypeField unions)
    ]

toTypeAliasField :: Alias -> (Json.String, Encode.Value)
toTypeAliasField (Alias name args tipe) =
  ( Json.fromName name,
    Encode.object
      [ "args" ==> Encode.list Encode.name args,
        "type" ==> encode tipe
      ]
  )

toCustomTypeField :: Union -> (Json.String, Encode.Value)
toCustomTypeField (Union name args constructors) =
  ( Json.fromName name,
    Encode.object
      [ "args" ==> Encode.list Encode.name args,
        "tags" ==> Encode.object (fmap toVariantObject constructors)
      ]
  )

toVariantObject :: (Name.Name, [Type]) -> (Json.String, Encode.Value)
toVariantObject (name, args) =
  (Json.fromName name, Encode.list encode args)
