{-# LANGUAGE OverloadedStrings #-}

-- | Optimize.Derive - Code generation for deriving clauses
--
-- Generates optimized expressions for @deriving (Encode, Decode)@.
-- Encode generates JSON encoder functions. Decode generates JSON decoder functions.
-- Ord is handled separately via ComparableBound (no generated function).
--
-- @since 0.20.0
module Optimize.Derive
  ( addDerivedDefs,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Utils.Type as TypeUtils
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.String as ES
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Control.Monad as Monad
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Optimize.Names as Names
import qualified Optimize.Port as Port

-- | Add derived definitions to the optimization graph.
--
-- For each type with deriving clauses, generates the corresponding
-- functions and adds them as 'Opt.Define' nodes.
addDerivedDefs ::
  ModuleName.Canonical ->
  Map.Map Name.Name Can.Union ->
  Map.Map Name.Name Can.Alias ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addDerivedDefs home unions aliases graph =
  Map.foldrWithKey (addAliasDeriving home) (Map.foldrWithKey (addUnionDeriving home) graph unions) aliases

-- UNION DERIVING

addUnionDeriving ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Union ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addUnionDeriving home name union@(Can.Union _ _ _ _ _ deriving_) graph =
  foldr (addUnionClause home name union) graph deriving_

addUnionClause ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Union ->
  Can.DerivingClause ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addUnionClause home name union clause graph =
  case clause of
    Can.DeriveOrd -> graph
    Can.DeriveEncode opts -> addEncodeUnion home name union opts graph
    Can.DeriveDecode opts -> addDecodeUnion home name union opts graph
    Can.DeriveEnum -> addEnumList home name union graph

-- ALIAS DERIVING

addAliasDeriving ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Alias ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addAliasDeriving home name alias@(Can.Alias _ _ _ _ deriving_) graph =
  foldr (addAliasClause home name alias) graph deriving_

addAliasClause ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Alias ->
  Can.DerivingClause ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addAliasClause home name alias@(Can.Alias typeParams _ _ _ _) clause graph =
  case clause of
    Can.DeriveOrd -> graph
    Can.DeriveEncode opts
      | null typeParams -> addEncodeAlias home name alias opts graph
      | otherwise -> graph
    Can.DeriveDecode opts
      | null typeParams -> addDecodeAlias home name alias opts graph
      | otherwise -> graph
    Can.DeriveEnum -> graph

-- EQUALITY HELPER

-- | Generate a kernel equality call: @_Utils_equal(a, b)@.
kernelEq :: Opt.Expr -> Opt.Expr -> Names.Tracker Opt.Expr
kernelEq a b =
  do
    eqFn <- Names.registerKernel Name.utils (Opt.VarRuntime Name.utils (Name.fromChars "equal"))
    pure (Opt.Call eqFn [a, b])

-- CONSTRUCTOR TAG MATCH

-- | Generate a condition that matches the @$@ field of a value against
-- a constructor name string. For Normal (non-enum) constructors, the
-- @$@ field holds the constructor name as a string in dev mode.
ctorTagMatch :: Name.Name -> Name.Name -> Names.Tracker Opt.Expr
ctorTagMatch dollar ctorName =
  let dollarField = Name.fromChars "$"
   in kernelEq (Opt.Access (Opt.VarLocal dollar) dollarField) (Opt.Str (Name.toCanopyString ctorName))

-- CONSTRUCTOR FIELD ACCESS

-- | Convert a 0-based index to the field name used by JS codegen.
--
-- Constructor argument 0 is field @a@, argument 1 is field @b@, etc.
-- This matches the @intToAscii@ function in @Generate.JavaScript.Name@.
ctorArgFieldName :: Int -> Name.Name
ctorArgFieldName i
  | i < 26 = Name.fromChars [toEnum (fromEnum 'a' + i)]
  | otherwise = Name.fromChars [toEnum (fromEnum 'A' + i - 26)]

-- JSON ENCODE UNION

addEncodeUnion ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Union ->
  Maybe Can.JsonOptions ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addEncodeUnion home name (Can.Union _ _ alts _ opts _) jsonOpts graph =
  let funcName = Name.fromChars ("encode" ++ Name.toChars name)
      (deps, fields, expr) = Names.run (toEncodeUnionExpr home alts opts jsonOpts)
      node = Opt.Define expr deps
   in addToGraph (Opt.Global home funcName) node fields graph

toEncodeUnionExpr ::
  ModuleName.Canonical ->
  [Can.Ctor] ->
  Can.CtorOpts ->
  Maybe Can.JsonOptions ->
  Names.Tracker Opt.Expr
toEncodeUnionExpr home alts opts jsonOpts =
  case opts of
    Can.Enum -> toEncodeEnumExpr home alts
    _ -> toEncodeTaggedExpr home alts jsonOpts

toEncodeEnumExpr :: ModuleName.Canonical -> [Can.Ctor] -> Names.Tracker Opt.Expr
toEncodeEnumExpr home alts =
  do
    let dollar = Name.fromChars "$"
    encodeString <- Names.registerGlobal elmJsonEncode "string"
    branches <- traverse (enumEncodeBranch home encodeString) alts
    let fallback = Opt.Call encodeString [Opt.Str (Name.toCanopyString (Name.fromChars ""))]
    pure (Opt.Function [dollar] (buildIfChain branches fallback))

enumEncodeBranch :: ModuleName.Canonical -> Opt.Expr -> Can.Ctor -> Names.Tracker (Opt.Expr, Opt.Expr)
enumEncodeBranch home encodeString (Can.Ctor ctorName index _ _) =
  do
    let dollar = Name.fromChars "$"
    cond <- kernelEq (Opt.VarLocal dollar) (Opt.VarEnum (Opt.Global home ctorName) index)
    let result = Opt.Call encodeString [Opt.Str (Name.toCanopyString ctorName)]
    pure (cond, result)

-- | Generate tagged-object encoding for union types with constructor args.
--
-- For each constructor, produces:
-- * 0 args: @{"tag": "CtorName"}@
-- * 1 arg:  @{"tag": "CtorName", "contents": encodedArg}@
-- * N args: @{"tag": "CtorName", "contents": [encodedArg0, ...]}@
toEncodeTaggedExpr ::
  ModuleName.Canonical ->
  [Can.Ctor] ->
  Maybe Can.JsonOptions ->
  Names.Tracker Opt.Expr
toEncodeTaggedExpr home alts jsonOpts =
  do
    let dollar = Name.fromChars "$"
    encodeObject <- Names.registerGlobal elmJsonEncode "object"
    encodeString <- Names.registerGlobal elmJsonEncode "string"
    branches <- traverse (taggedEncodeBranch home encodeObject encodeString jsonOpts) alts
    let fallback = Opt.Call encodeObject [Opt.List []]
    pure (Opt.Function [dollar] (buildIfChain branches fallback))

taggedEncodeBranch ::
  ModuleName.Canonical ->
  Opt.Expr ->
  Opt.Expr ->
  Maybe Can.JsonOptions ->
  Can.Ctor ->
  Names.Tracker (Opt.Expr, Opt.Expr)
taggedEncodeBranch _home encodeObject encodeString jsonOpts (Can.Ctor ctorName _index numArgs argTypes) =
  do
    let dollar = Name.fromChars "$"
    let tagStr = tagFieldName jsonOpts
    let ctorStr = Name.toCanopyString ctorName
    let tagPair = Opt.Tuple (Opt.Str tagStr) (Opt.Call encodeString [Opt.Str ctorStr]) Nothing
    cond <- ctorTagMatch dollar ctorName
    case numArgs of
      0 ->
        pure (cond, Opt.Call encodeObject [Opt.List [tagPair]])
      1 ->
        do
          encoder <- Port.toEncoder (head' argTypes)
          let argExpr = Opt.Access (Opt.VarLocal dollar) (ctorArgFieldName 0)
          let contentsPair = mkContentsPairWith jsonOpts (Opt.Call encoder [argExpr])
          pure (cond, Opt.Call encodeObject [Opt.List [tagPair, contentsPair]])
      _ ->
        do
          encodedArgs <- encodeCtorArgs dollar argTypes
          encodeList <- Names.registerGlobal elmJsonEncode "list"
          identity <- Names.registerGlobal ModuleName.basics Name.identity
          let contentsVal = Opt.Call encodeList [identity, Opt.List encodedArgs]
          let contentsPair = mkContentsPairWith jsonOpts contentsVal
          pure (cond, Opt.Call encodeObject [Opt.List [tagPair, contentsPair]])

-- | Encode each constructor argument by index using Port.toEncoder.
encodeCtorArgs :: Name.Name -> [Can.Type] -> Names.Tracker [Opt.Expr]
encodeCtorArgs dollar argTypes =
  traverse (encodeOneArg dollar) (zip [0 ..] argTypes)

-- | Encode a single constructor argument.
encodeOneArg :: Name.Name -> (Int, Can.Type) -> Names.Tracker Opt.Expr
encodeOneArg dollar (i, argType) =
  do
    encoder <- Port.toEncoder argType
    let argExpr = Opt.Access (Opt.VarLocal dollar) (ctorArgFieldName i)
    pure (Opt.Call encoder [argExpr])

-- | Build a @("contents", value)@ tuple using options for the field name.
mkContentsPairWith :: Maybe Can.JsonOptions -> Opt.Expr -> Opt.Expr
mkContentsPairWith jsonOpts val =
  Opt.Tuple (Opt.Str (contentsFieldName jsonOpts)) val Nothing

-- JSON DECODE UNION

addDecodeUnion ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Union ->
  Maybe Can.JsonOptions ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addDecodeUnion home name (Can.Union _ _ alts _ opts _) jsonOpts graph =
  let funcName = Name.fromChars (lowerFirst (Name.toChars name) ++ "Decoder")
      (deps, fields, expr) = Names.run (toDecodeUnionExpr home alts opts jsonOpts)
      node = Opt.Define expr deps
   in addToGraph (Opt.Global home funcName) node fields graph

toDecodeUnionExpr ::
  ModuleName.Canonical ->
  [Can.Ctor] ->
  Can.CtorOpts ->
  Maybe Can.JsonOptions ->
  Names.Tracker Opt.Expr
toDecodeUnionExpr home alts opts jsonOpts =
  case opts of
    Can.Enum -> toDecodeEnumExpr home alts
    _ -> toDecodeTaggedExpr home alts jsonOpts

toDecodeEnumExpr ::
  ModuleName.Canonical ->
  [Can.Ctor] ->
  Names.Tracker Opt.Expr
toDecodeEnumExpr home alts =
  do
    decodeString <- Names.registerGlobal elmJsonDecode "string"
    andThen <- Names.registerGlobal elmJsonDecode "andThen"
    succeed <- Names.registerGlobal elmJsonDecode "succeed"
    fail_ <- Names.registerGlobal elmJsonDecode "fail"
    let tagVar = Name.fromChars "tag"
    branches <- traverse (enumDecodeBranch home succeed) alts
    let fallback = Opt.Call fail_ [Opt.Str (Name.toCanopyString (Name.fromChars "Unknown variant"))]
    let body = buildIfChain branches fallback
    let decoder = Opt.Function [tagVar] body
    pure (Opt.Call andThen [decoder, decodeString])

enumDecodeBranch :: ModuleName.Canonical -> Opt.Expr -> Can.Ctor -> Names.Tracker (Opt.Expr, Opt.Expr)
enumDecodeBranch home succeed (Can.Ctor ctorName _ _ _) =
  do
    let tagVar = Name.fromChars "tag"
    cond <- kernelEq (Opt.VarLocal tagVar) (Opt.Str (Name.toCanopyString ctorName))
    pure (cond, Opt.Call succeed [Opt.VarGlobal (Opt.Global home ctorName)])

-- | Generate tagged-object decoding for union types with constructor args.
--
-- For each constructor, decodes:
-- * 0 args: @succeed CtorName@
-- * 1 arg:  @field "contents" (map CtorName decoder0)@
-- * N args: @field "contents" (index 0 dec0 |> andThen (\a -> ...))@
toDecodeTaggedExpr ::
  ModuleName.Canonical ->
  [Can.Ctor] ->
  Maybe Can.JsonOptions ->
  Names.Tracker Opt.Expr
toDecodeTaggedExpr home alts jsonOpts =
  do
    decodeField <- Names.registerGlobal elmJsonDecode "field"
    decodeString <- Names.registerGlobal elmJsonDecode "string"
    andThen <- Names.registerGlobal elmJsonDecode "andThen"
    fail_ <- Names.registerGlobal elmJsonDecode "fail"
    let tagVar = Name.fromChars "tag"
    let tagDecoder = Opt.Call decodeField [Opt.Str (tagFieldName jsonOpts), decodeString]
    branches <- traverse (taggedDecodeBranch home jsonOpts) alts
    let fallback = Opt.Call fail_ [Opt.Str (Name.toCanopyString (Name.fromChars "Unknown variant"))]
    let body = buildIfChain branches fallback
    let decoder = Opt.Function [tagVar] body
    pure (Opt.Call andThen [decoder, tagDecoder])

taggedDecodeBranch ::
  ModuleName.Canonical ->
  Maybe Can.JsonOptions ->
  Can.Ctor ->
  Names.Tracker (Opt.Expr, Opt.Expr)
taggedDecodeBranch home jsonOpts (Can.Ctor ctorName _ numArgs argTypes) =
  do
    let tagVar = Name.fromChars "tag"
    cond <- kernelEq (Opt.VarLocal tagVar) (Opt.Str (Name.toCanopyString ctorName))
    let ctorVal = Opt.VarGlobal (Opt.Global home ctorName)
    result <- decodeCtorBody ctorVal numArgs argTypes jsonOpts
    pure (cond, result)

-- | Build the decoder body for a single constructor.
decodeCtorBody :: Opt.Expr -> Int -> [Can.Type] -> Maybe Can.JsonOptions -> Names.Tracker Opt.Expr
decodeCtorBody ctorVal numArgs argTypes jsonOpts =
  case numArgs of
    0 -> do
      succeed <- Names.registerGlobal elmJsonDecode "succeed"
      pure (Opt.Call succeed [ctorVal])
    1 -> decodeSingleArg ctorVal (head' argTypes) jsonOpts
    _ -> decodeMultiArgs ctorVal argTypes jsonOpts

-- | Decode a single-argument constructor from @"contents"@.
decodeSingleArg :: Opt.Expr -> Can.Type -> Maybe Can.JsonOptions -> Names.Tracker Opt.Expr
decodeSingleArg ctorVal argType jsonOpts =
  do
    decodeField <- Names.registerGlobal elmJsonDecode "field"
    decodeMap <- Names.registerGlobal elmJsonDecode "map"
    decoder0 <- Port.toDecoder argType
    let mapped = Opt.Call decodeMap [ctorVal, decoder0]
    pure (Opt.Call decodeField [Opt.Str (contentsFieldName jsonOpts), mapped])

-- | Decode a multi-argument constructor from @"contents"@ array.
--
-- Generates: @field "contents" (index 0 dec0 |> andThen (\a -> index 1 dec1 |> andThen (\b -> succeed (Ctor a b))))@
decodeMultiArgs :: Opt.Expr -> [Can.Type] -> Maybe Can.JsonOptions -> Names.Tracker Opt.Expr
decodeMultiArgs ctorVal argTypes jsonOpts =
  do
    decodeField <- Names.registerGlobal elmJsonDecode "field"
    succeed <- Names.registerGlobal elmJsonDecode "succeed"
    let contentsStr = contentsFieldName jsonOpts
    let argNames = fmap (\i -> Name.fromVarIndex i) [0 .. length argTypes - 1]
    let ctorCall = Opt.Call ctorVal (fmap Opt.VarLocal argNames)
    let innermost = Opt.Call succeed [ctorCall]
    contentsDecoder <- buildAndThenChain argTypes argNames innermost (length argTypes - 1)
    pure (Opt.Call decodeField [Opt.Str contentsStr, contentsDecoder])

-- | Build a chain of @index i decoder |> andThen (\var -> ...)@ from inside out.
buildAndThenChain :: [Can.Type] -> [Name.Name] -> Opt.Expr -> Int -> Names.Tracker Opt.Expr
buildAndThenChain argTypes argNames innerExpr idx
  | idx < 0 = pure innerExpr
  | otherwise = do
      andThen <- Names.registerGlobal elmJsonDecode "andThen"
      decodeIndex <- Names.registerGlobal elmJsonDecode "index"
      decoder <- Port.toDecoder (argTypes !! idx)
      let varName = argNames !! idx
      let indexDecoder = Opt.Call decodeIndex [Opt.Int idx, decoder]
      let lambda = Opt.Function [varName] innerExpr
      let chained = Opt.Call andThen [lambda, indexDecoder]
      buildAndThenChain argTypes argNames chained (idx - 1)

-- JSON ENCODE ALIAS

addEncodeAlias ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Alias ->
  Maybe Can.JsonOptions ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addEncodeAlias home name (Can.Alias _ _ tipe _ _) jsonOpts graph =
  let funcName = Name.fromChars ("encode" ++ Name.toChars name)
      (deps, fields, expr) = Names.run (toEncoderWithOpts jsonOpts tipe)
      node = Opt.Define expr deps
   in addToGraph (Opt.Global home funcName) node fields graph

-- JSON DECODE ALIAS

addDecodeAlias ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Alias ->
  Maybe Can.JsonOptions ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addDecodeAlias home name (Can.Alias _ _ tipe _ _) jsonOpts graph =
  let funcName = Name.fromChars (lowerFirst (Name.toChars name) ++ "Decoder")
      (deps, fields, expr) = Names.run (toDecoderWithOpts jsonOpts tipe)
      node = Opt.Define expr deps
   in addToGraph (Opt.Global home funcName) node fields graph

-- ENCODER/DECODER WITH OPTIONS

-- | Like 'Port.toEncoder' but applies field naming from JsonOptions.
toEncoderWithOpts :: Maybe Can.JsonOptions -> Can.Type -> Names.Tracker Opt.Expr
toEncoderWithOpts Nothing tipe = Port.toEncoder tipe
toEncoderWithOpts (Just opts) tipe =
  case tipe of
    Can.TRecord fields Nothing ->
      encodeRecordWithOpts opts fields
    Can.TAlias _ _ args alias ->
      toEncoderWithOpts (Just opts) (TypeUtils.dealias args alias)
    _ -> Port.toEncoder tipe

-- | Encode a record with field naming options applied.
encodeRecordWithOpts :: Can.JsonOptions -> Map.Map Name.Name Can.FieldType -> Names.Tracker Opt.Expr
encodeRecordWithOpts opts fields =
  let encodeField (name, Can.FieldType _ fieldType) =
        do
          encoder <- Port.toEncoder fieldType
          let value = Opt.Call encoder [Opt.Access (Opt.VarLocal Name.dollar) name]
          let jsonName = applyFieldNaming (Just opts) name
          return (Opt.Tuple (Opt.Str jsonName) value Nothing)
   in do
        object <- Names.registerGlobal ModuleName.jsonEncode "object"
        keyValuePairs <- traverse encodeField (Map.toList fields)
        Names.registerFieldDict fields $
          Opt.Function [Name.dollar] (Opt.Call object [Opt.List keyValuePairs])

-- | Like 'Port.toDecoder' but applies field naming from JsonOptions.
toDecoderWithOpts :: Maybe Can.JsonOptions -> Can.Type -> Names.Tracker Opt.Expr
toDecoderWithOpts Nothing tipe = Port.toDecoder tipe
toDecoderWithOpts (Just opts) tipe =
  case tipe of
    Can.TRecord fields Nothing ->
      decodeRecordWithOpts opts fields
    Can.TAlias _ _ args alias ->
      toDecoderWithOpts (Just opts) (TypeUtils.dealias args alias)
    _ -> Port.toDecoder tipe

-- | Decode a record with field naming options applied.
decodeRecordWithOpts :: Can.JsonOptions -> Map.Map Name.Name Can.FieldType -> Names.Tracker Opt.Expr
decodeRecordWithOpts opts fields =
  let toFieldExpr name _ = Opt.VarLocal name
      record = Opt.Record (Map.mapWithKey toFieldExpr fields)
   in do
        succeed <- Names.registerGlobal elmJsonDecode "succeed"
        Names.registerFieldDict fields (Map.toList fields)
          >>= Monad.foldM (fieldAndThenWithOpts opts) (Opt.Call succeed [record])

-- | Like 'fieldAndThen' in Port but uses the naming strategy for field keys.
fieldAndThenWithOpts :: Can.JsonOptions -> Opt.Expr -> (Name.Name, Can.FieldType) -> Names.Tracker Opt.Expr
fieldAndThenWithOpts opts decoder (key, Can.FieldType _ tipe) =
  do
    andThen <- Names.registerGlobal elmJsonDecode "andThen"
    field <- Names.registerGlobal elmJsonDecode "field"
    typeDecoder <- Port.toDecoder tipe
    let jsonKey = applyFieldNaming (Just opts) key
    return (Opt.Call andThen [Opt.Function [key] decoder, Opt.Call field [Opt.Str jsonKey, typeDecoder]])

-- ENUM LIST

-- | Generate @allTypeName : List TypeName@ as a list of all constructors.
addEnumList ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Union ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addEnumList home name (Can.Union _ _ alts _ opts _) graph =
  let funcName = Name.fromChars ("all" ++ Name.toChars name)
      ctorExprs = fmap (enumCtorExpr home opts) alts
      expr = Opt.List ctorExprs
      deps = Set.fromList (fmap (enumCtorGlobal home) alts)
      node = Opt.Define expr deps
   in addToGraph (Opt.Global home funcName) node Map.empty graph

-- | Generate the expression for a single enum constructor.
enumCtorExpr :: ModuleName.Canonical -> Can.CtorOpts -> Can.Ctor -> Opt.Expr
enumCtorExpr home opts (Can.Ctor ctorName index _ _) =
  case opts of
    Can.Enum -> Opt.VarEnum (Opt.Global home ctorName) index
    _ -> Opt.VarGlobal (Opt.Global home ctorName)

-- | Get the global reference for a constructor (for dependency tracking).
enumCtorGlobal :: ModuleName.Canonical -> Can.Ctor -> Opt.Global
enumCtorGlobal home (Can.Ctor ctorName _ _ _) = Opt.Global home ctorName

-- JSON OPTIONS HELPERS

-- | Get the tag field name from options, defaulting to @"tag"@.
tagFieldName :: Maybe Can.JsonOptions -> ES.String
tagFieldName opts =
  maybe (Name.toCanopyString (Name.fromChars "tag")) (\o -> maybe (Name.toCanopyString (Name.fromChars "tag")) Name.toCanopyString (Can._jsonTagField o)) opts

-- | Get the contents field name from options, defaulting to @"contents"@.
contentsFieldName :: Maybe Can.JsonOptions -> ES.String
contentsFieldName opts =
  maybe (Name.toCanopyString (Name.fromChars "contents")) (\o -> maybe (Name.toCanopyString (Name.fromChars "contents")) Name.toCanopyString (Can._jsonContentsField o)) opts

-- | Apply a naming strategy to a field name.
applyNaming :: Can.NamingStrategy -> Name.Name -> ES.String
applyNaming Can.IdentityNaming name = Name.toCanopyString name
applyNaming Can.SnakeCase name = Name.toCanopyString (Name.fromChars (toSnakeCase (Name.toChars name)))
applyNaming Can.CamelCase name = Name.toCanopyString name
applyNaming Can.KebabCase name = Name.toCanopyString (Name.fromChars (toKebabCase (Name.toChars name)))

-- | Convert camelCase to snake_case.
toSnakeCase :: String -> String
toSnakeCase [] = []
toSnakeCase (c : cs)
  | c >= 'A' && c <= 'Z' = '_' : toEnum (fromEnum c + 32) : toSnakeCase cs
  | otherwise = c : toSnakeCase cs

-- | Convert camelCase to kebab-case.
toKebabCase :: String -> String
toKebabCase [] = []
toKebabCase (c : cs)
  | c >= 'A' && c <= 'Z' = '-' : toEnum (fromEnum c + 32) : toKebabCase cs
  | otherwise = c : toKebabCase cs

-- | Apply field naming from options to a field name.
applyFieldNaming :: Maybe Can.JsonOptions -> Name.Name -> ES.String
applyFieldNaming Nothing name = Name.toCanopyString name
applyFieldNaming (Just opts) name =
  maybe (Name.toCanopyString name) (\strategy -> applyNaming strategy name) (Can._jsonFieldNaming opts)

-- HELPERS

addToGraph :: Opt.Global -> Opt.Node -> Map.Map Name.Name Int -> Opt.LocalGraph -> Opt.LocalGraph
addToGraph global node fields (Opt.LocalGraph main nodes fieldCounts locs) =
  Opt.LocalGraph
    main
    (Map.insert global node nodes)
    (Map.unionWith (+) fields fieldCounts)
    locs

buildIfChain :: [(Opt.Expr, Opt.Expr)] -> Opt.Expr -> Opt.Expr
buildIfChain [] fallback = fallback
buildIfChain ((cond, result) : rest) fallback =
  Opt.If [(cond, result)] (buildIfChain rest fallback)

lowerFirst :: String -> String
lowerFirst [] = []
lowerFirst (c : cs) = toLower c : cs
  where
    toLower ch
      | ch >= 'A' && ch <= 'Z' = toEnum (fromEnum ch + 32)
      | otherwise = ch

-- | Safe head for non-empty lists from constructor argument types.
head' :: [a] -> a
head' (x : _) = x
head' [] = error "Optimize.Derive.head': empty list (constructor with args must have types)"

-- | Module name for @Json.Encode@ using the @elm@ package author.
--
-- Uses @elm/json@ instead of @canopy/json@ to match the actual compiled
-- package name, avoiding name mismatch in generated JavaScript.
--
-- @since 0.20.0
elmJsonEncode :: ModuleName.Canonical
elmJsonEncode = ModuleName.Canonical elmJsonPkg (Name.fromChars "Json.Encode")

-- | Module name for @Json.Decode@ using the @elm@ package author.
--
-- @since 0.20.0
elmJsonDecode :: ModuleName.Canonical
elmJsonDecode = ModuleName.Canonical elmJsonPkg (Name.fromChars "Json.Decode")

-- | Package name for @elm/json@, the actual installed package.
--
-- @since 0.20.0
elmJsonPkg :: Pkg.Name
elmJsonPkg = Pkg.Name Pkg.elm (Utf8.fromChars "json")
