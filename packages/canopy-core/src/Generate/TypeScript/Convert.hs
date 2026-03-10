{-# LANGUAGE OverloadedStrings #-}

-- | Convert Canopy canonical types to TypeScript types.
--
-- Maps the canonical type representation ('Can.Type') to the TypeScript
-- intermediate representation ('TsType'). Handles primitive types, records,
-- functions (uncurried), unions (discriminated), and recursive types.
--
-- @since 0.20.0
module Generate.TypeScript.Convert
  ( convertType,
    convertAnnotation,
    convertUnion,
    convertAlias,
    convertValue,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Utils.Type as Type
import qualified Canopy.Data.Name as Name
import Canopy.Data.Name (Name)
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Generate.TypeScript.Types (DtsDecl (..), TsType (..))

-- | Convert a canonical type to a TypeScript type.
--
-- The 'Set.Set Name' parameter tracks visited alias names to prevent
-- infinite recursion on recursive types.
--
-- @since 0.20.0
convertType :: Set.Set Name -> Can.Type -> TsType
convertType visited tpe =
  case tpe of
    Can.TLambda _ _ ->
      uncurryFunction visited tpe
    Can.TVar name ->
      TsTypeVar (toTsTypeVarName name)
    Can.TType home name args ->
      convertNamedType visited home name args
    Can.TRecord fields ext ->
      convertRecord visited fields ext
    Can.TUnit ->
      TsVoid
    Can.TTuple a b mc ->
      convertTuple visited a b mc
    Can.TAlias _ name _ (Can.Filled tpe') ->
      convertType (Set.insert name visited) tpe'
    Can.TAlias _ name args (Can.Holey tpe')
      | Set.member name visited -> TsNamed name []
      | otherwise ->
          convertType (Set.insert name visited) (Type.dealias args (Can.Holey tpe'))


-- | Convert a canonical annotation to a TypeScript type.
convertAnnotation :: Can.Annotation -> TsType
convertAnnotation (Can.Forall _ tpe) =
  convertType Set.empty tpe


-- | Convert an interface value export to a DtsDecl.
convertValue :: Name -> Can.Annotation -> DtsDecl
convertValue name (Can.Forall _ tpe) =
  DtsValue name (convertType Set.empty tpe)


-- | Convert a union type to a DtsDecl.
convertUnion :: Name -> Can.Union -> DtsDecl
convertUnion name (Can.Union vars _ alts _ _ _) =
  DtsUnionType name vars (TsUnion (map convertCtor alts))


-- | Convert a type alias to a DtsDecl.
convertAlias :: Name -> Can.Alias -> DtsDecl
convertAlias name (Can.Alias vars _ tpe _ _) =
  DtsTypeAlias name vars (convertType Set.empty tpe)


-- INTERNAL HELPERS


convertNamedType :: Set.Set Name -> ModuleName.Canonical -> Name -> [Can.Type] -> TsType
convertNamedType visited home name args
  | isBasicsType home name "Int" = TsNumber
  | isBasicsType home name "Float" = TsNumber
  | isBasicsType home name "Bool" = TsBoolean
  | isModuleType home ModuleName.string "String" name = TsString
  | isModuleType home ModuleName.char "Char" name = TsString
  | otherwise = convertNamedArgs visited home name args


convertNamedArgs :: Set.Set Name -> ModuleName.Canonical -> Name -> [Can.Type] -> TsType
convertNamedArgs visited home name [a]
  | home == ModuleName.list && name == Name.fromChars "List" =
      TsReadonlyArray (convertType visited a)
  | home == ModuleName.maybe && name == Name.fromChars "Maybe" =
      convertMaybe visited a
convertNamedArgs visited home name [e, a]
  | home == ModuleName.result && name == Name.fromChars "Result" =
      convertResult visited e a
convertNamedArgs visited _ name args =
  TsNamed name (map (convertType visited) args)


isBasicsType :: ModuleName.Canonical -> Name -> String -> Bool
isBasicsType home name expected =
  home == ModuleName.basics && name == Name.fromChars expected


isModuleType :: ModuleName.Canonical -> ModuleName.Canonical -> String -> Name -> Bool
isModuleType home expectedHome expectedName name =
  home == expectedHome && name == Name.fromChars expectedName


convertMaybe :: Set.Set Name -> Can.Type -> TsType
convertMaybe visited inner =
  TsUnion
    [ TsTaggedVariant (Name.fromChars "Just") [(Name.fromChars "a", convertType visited inner)],
      TsTaggedVariant (Name.fromChars "Nothing") []
    ]


convertResult :: Set.Set Name -> Can.Type -> Can.Type -> TsType
convertResult visited errTpe okTpe =
  TsUnion
    [ TsTaggedVariant (Name.fromChars "Ok") [(Name.fromChars "a", convertType visited okTpe)],
      TsTaggedVariant (Name.fromChars "Err") [(Name.fromChars "a", convertType visited errTpe)]
    ]


convertRecord :: Set.Set Name -> Map.Map Name Can.FieldType -> Maybe Name -> TsType
convertRecord visited fields ext =
  case ext of
    Nothing -> TsObject knownFields
    Just _ -> TsObjectWithIndex knownFields
  where
    knownFields = map convertField (Map.toAscList fields)
    convertField (name, Can.FieldType _ tpe) = (name, convertType visited tpe)


convertTuple :: Set.Set Name -> Can.Type -> Can.Type -> Maybe Can.Type -> TsType
convertTuple visited a b mc =
  TsObject fields
  where
    fields = case mc of
      Nothing ->
        [(Name.fromChars "a", convertType visited a), (Name.fromChars "b", convertType visited b)]
      Just c ->
        [ (Name.fromChars "a", convertType visited a),
          (Name.fromChars "b", convertType visited b),
          (Name.fromChars "c", convertType visited c)
        ]


uncurryFunction :: Set.Set Name -> Can.Type -> TsType
uncurryFunction visited tpe =
  TsFunction (map (convertType visited) params) (convertType visited ret)
  where
    (params, ret) = collectLambdas tpe


collectLambdas :: Can.Type -> ([Can.Type], Can.Type)
collectLambdas (Can.TLambda a b) =
  let (rest, ret) = collectLambdas b
   in (a : rest, ret)
collectLambdas tpe = ([], tpe)


convertCtor :: Can.Ctor -> TsType
convertCtor (Can.Ctor name _ _ args) =
  TsTaggedVariant name (zipWith mkField fieldNames (map (convertType Set.empty) args))
  where
    fieldNames = map (\c -> Name.fromChars [c]) (take (length args) ['a' ..])
    mkField n t = (n, t)


toTsTypeVarName :: Name -> Name
toTsTypeVarName name =
  Name.fromChars (map toUpper (Name.toChars name))
  where
    toUpper c
      | c >= 'a' && c <= 'z' = toEnum (fromEnum c - 32)
      | otherwise = c
