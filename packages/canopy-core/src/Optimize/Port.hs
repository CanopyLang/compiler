{-# LANGUAGE OverloadedStrings #-}

module Optimize.Port
  ( toEncoder,
    toFlagsDecoder,
    toDecoder,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Utils.Type as Type
import qualified Canopy.ModuleName as ModuleName
import Control.Monad (foldM)
import qualified Canopy.Data.Index as Index
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Optimize.Names as Names
import qualified Reporting.InternalError as InternalError
import Prelude hiding (maybe, null)

-- ENCODE

toEncoder :: Can.Type -> Names.Tracker Opt.Expr
toEncoder tipe =
  case tipe of
    Can.TAlias _ _ args alias ->
      toEncoder (Type.dealias args alias)
    Can.TLambda _ _ ->
      InternalError.report
        "Optimize.Port.toEncoder"
        "function type reached port encoder"
        "Functions cannot be serialized through ports. The type checker must reject function types in port signatures before optimization reaches this code."
    Can.TVar _ ->
      InternalError.report
        "Optimize.Port.toEncoder"
        "type variable reached port encoder"
        "Unconstrained type variables cannot be serialized through ports. The type checker must fully resolve port types before optimization reaches this code."
    Can.TUnit ->
      Opt.Function [Name.dollar] <$> encode "null"
    Can.TTuple a b c ->
      encodeTuple a b c
    Can.TType _ name args ->
      case args of
        []
          | name == Name.float -> encode "float"
          | name == Name.int -> encode "int"
          | name == Name.bool -> encode "bool"
          | name == Name.string -> encode "string"
          | name == Name.value -> Names.registerGlobal ModuleName.basics Name.identity
        [arg]
          | name == Name.maybe -> encodeMaybe arg
          | name == Name.list -> encodeList arg
          | name == Name.array -> encodeArray arg
        _ ->
          InternalError.report
            "Optimize.Port.toEncoder"
            "unsupported custom type reached port encoder"
            "The port encoder only handles built-in types (Int, Float, Bool, String, Maybe, List, Array) and records. Custom type aliases or unexpected type applications should have been rejected by the type checker."
    Can.TRecord _ (Just _) ->
      InternalError.report
        "Optimize.Port.toEncoder"
        "extensible record type reached port encoder"
        "Extensible records (records with a row variable) cannot be serialized through ports. The type checker must reject extensible record types in port signatures."
    Can.TRecord fields Nothing ->
      let encodeField (name, Can.FieldType _ fieldType) =
            do
              encoder <- toEncoder fieldType
              let value = Opt.Call encoder [Opt.Access (Opt.VarLocal Name.dollar) name]
              return $ Opt.Tuple (Opt.Str (Name.toCanopyString name)) value Nothing
       in do
            object <- encode "object"
            keyValuePairs <- traverse encodeField (Map.toList fields)
            Names.registerFieldDict fields $
              Opt.Function [Name.dollar] (Opt.Call object [Opt.List keyValuePairs])

-- ENCODE HELPERS

encodeMaybe :: Can.Type -> Names.Tracker Opt.Expr
encodeMaybe tipe =
  do
    null <- encode "null"
    encoder <- toEncoder tipe
    destruct <- Names.registerGlobal ModuleName.maybe "destruct"
    return . Opt.Function [Name.dollar] $ Opt.Call destruct [null, encoder, Opt.VarLocal Name.dollar]

encodeList :: Can.Type -> Names.Tracker Opt.Expr
encodeList tipe =
  do
    list <- encode "list"
    encoder <- toEncoder tipe
    return $ Opt.Call list [encoder]

encodeArray :: Can.Type -> Names.Tracker Opt.Expr
encodeArray tipe =
  do
    array <- encode "array"
    encoder <- toEncoder tipe
    return $ Opt.Call array [encoder]

encodeTuple :: Can.Type -> Can.Type -> Maybe Can.Type -> Names.Tracker Opt.Expr
encodeTuple a b maybeC =
  let encodeArg arg tipe =
        do
          encoder <- toEncoder tipe
          return $ Opt.Call encoder [Opt.VarLocal arg]

      let_ arg index = Opt.Destruct (Opt.Destructor arg (Opt.Index index (Opt.Root Name.dollar)))
   in do
        list <- encode "list"
        identity <- Names.registerGlobal ModuleName.basics Name.identity
        arg1 <- encodeArg "a" a
        arg2 <- encodeArg "b" b

        case maybeC of
          Nothing ->
            ((return . Opt.Function [Name.dollar]) . let_ "a" Index.first) . let_ "b" Index.second $ Opt.Call list [identity, Opt.List [arg1, arg2]]
          Just c ->
            do
              arg3 <- encodeArg "c" c
              (((return . Opt.Function [Name.dollar]) . let_ "a" Index.first) . let_ "b" Index.second) . let_ "c" Index.third $ Opt.Call list [identity, Opt.List [arg1, arg2, arg3]]

-- FLAGS DECODER

toFlagsDecoder :: Can.Type -> Names.Tracker Opt.Expr
toFlagsDecoder tipe =
  case tipe of
    Can.TUnit ->
      do
        succeed <- decode "succeed"
        return $ Opt.Call succeed [Opt.Unit]
    _ ->
      toDecoder tipe

-- DECODE

toDecoder :: Can.Type -> Names.Tracker Opt.Expr
toDecoder tipe =
  case tipe of
    Can.TLambda _ _ ->
      InternalError.report
        "Optimize.Port.toDecoder"
        "function type reached port decoder"
        "Functions cannot be received through input ports. The type checker must reject function types in port signatures before optimization reaches this code."
    Can.TVar _ ->
      InternalError.report
        "Optimize.Port.toDecoder"
        "type variable reached port decoder"
        "Unconstrained type variables cannot be received through input ports. The type checker must fully resolve port types before optimization reaches this code."
    Can.TAlias _ _ args alias ->
      toDecoder (Type.dealias args alias)
    Can.TUnit ->
      decodeTuple0
    Can.TTuple a b c ->
      decodeTuple a b c
    Can.TType _ name args ->
      case args of
        []
          | name == Name.float -> decode "float"
          | name == Name.int -> decode "int"
          | name == Name.bool -> decode "bool"
          | name == Name.string -> decode "string"
          | name == Name.value -> decode "value"
        [arg]
          | name == Name.maybe -> decodeMaybe arg
          | name == Name.list -> decodeList arg
          | name == Name.array -> decodeArray arg
        _ ->
          InternalError.report
            "Optimize.Port.toDecoder"
            "unsupported type reached port decoder"
            "The port decoder only handles built-in types (Int, Float, Bool, String, Value, Maybe, List, Array) and records. Unexpected type applications should have been rejected by the type checker."
    Can.TRecord _ (Just _) ->
      InternalError.report
        "Optimize.Port.toDecoder"
        "extensible record type reached port decoder"
        "Extensible records (records with a row variable) cannot be received through input ports. The type checker must reject extensible record types in port signatures."
    Can.TRecord fields Nothing ->
      decodeRecord fields

-- DECODE MAYBE

decodeMaybe :: Can.Type -> Names.Tracker Opt.Expr
decodeMaybe tipe =
  do
    nothing <- Names.registerGlobal ModuleName.maybe "Nothing"
    just <- Names.registerGlobal ModuleName.maybe "Just"

    oneOf <- decode "oneOf"
    null <- decode "null"
    map_ <- decode "map"

    subDecoder <- toDecoder tipe

    return $
      Opt.Call
        oneOf
        [ Opt.List
            [ Opt.Call null [nothing],
              Opt.Call map_ [just, subDecoder]
            ]
        ]

-- DECODE LIST

decodeList :: Can.Type -> Names.Tracker Opt.Expr
decodeList tipe =
  do
    list <- decode "list"
    decoder <- toDecoder tipe
    return $ Opt.Call list [decoder]

-- DECODE ARRAY

decodeArray :: Can.Type -> Names.Tracker Opt.Expr
decodeArray tipe =
  do
    array <- decode "array"
    decoder <- toDecoder tipe
    return $ Opt.Call array [decoder]

-- DECODE TUPLES

decodeTuple0 :: Names.Tracker Opt.Expr
decodeTuple0 =
  do
    null <- decode "null"
    return (Opt.Call null [Opt.Unit])

decodeTuple :: Can.Type -> Can.Type -> Maybe Can.Type -> Names.Tracker Opt.Expr
decodeTuple a b maybeC =
  do
    succeed <- decode "succeed"
    case maybeC of
      Nothing ->
        let tuple = Opt.Tuple (toLocal 0) (toLocal 1) Nothing
         in (indexAndThen 1 b (Opt.Call succeed [tuple]) >>= indexAndThen 0 a)
      Just c ->
        let tuple = Opt.Tuple (toLocal 0) (toLocal 1) (Just (toLocal 2))
         in ((indexAndThen 2 c (Opt.Call succeed [tuple]) >>= indexAndThen 1 b) >>= indexAndThen 0 a)

toLocal :: Int -> Opt.Expr
toLocal index =
  Opt.VarLocal (Name.fromVarIndex index)

indexAndThen :: Int -> Can.Type -> Opt.Expr -> Names.Tracker Opt.Expr
indexAndThen i tipe decoder =
  do
    andThen <- decode "andThen"
    index <- decode "index"
    typeDecoder <- toDecoder tipe
    return $
      Opt.Call
        andThen
        [ Opt.Function [Name.fromVarIndex i] decoder,
          Opt.Call index [Opt.Int i, typeDecoder]
        ]

-- DECODE RECORDS

decodeRecord :: Map.Map Name.Name Can.FieldType -> Names.Tracker Opt.Expr
decodeRecord fields =
  let toFieldExpr name _ =
        Opt.VarLocal name

      record =
        Opt.Record (Map.mapWithKey toFieldExpr fields)
   in do
        succeed <- decode "succeed"
        Names.registerFieldDict fields (Map.toList fields) >>= foldM fieldAndThen (Opt.Call succeed [record])

fieldAndThen :: Opt.Expr -> (Name.Name, Can.FieldType) -> Names.Tracker Opt.Expr
fieldAndThen decoder (key, Can.FieldType _ tipe) =
  do
    andThen <- decode "andThen"
    field <- decode "field"
    typeDecoder <- toDecoder tipe
    return $
      Opt.Call
        andThen
        [ Opt.Function [key] decoder,
          Opt.Call field [Opt.Str (Name.toCanopyString key), typeDecoder]
        ]

-- GLOBALS HELPERS

encode :: Name.Name -> Names.Tracker Opt.Expr
encode = Names.registerGlobal ModuleName.jsonEncode

decode :: Name.Name -> Names.Tracker Opt.Expr
decode = Names.registerGlobal ModuleName.jsonDecode
