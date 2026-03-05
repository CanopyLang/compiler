{-# LANGUAGE OverloadedStrings #-}

-- | Optimize.Derive - Code generation for deriving clauses
--
-- Generates optimized expressions for @deriving (Show, Json.Encode, Json.Decode)@.
-- Show generates string conversion functions. Json uses Port.hs infrastructure.
-- Ord is handled separately via ComparableBound (no generated function).
--
-- @since 0.20.0
module Optimize.Derive
  ( addDerivedDefs,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.String as ES
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.Map.Strict as Map
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
    Can.DeriveShow -> addShowUnion home name union graph
    Can.DeriveJsonEncode opts -> addJsonEncodeUnion home name union opts graph
    Can.DeriveJsonDecode opts -> addJsonDecodeUnion home name union opts graph

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
    Can.DeriveShow -> addShowAlias home name alias graph
    Can.DeriveJsonEncode opts
      | null typeParams -> addJsonEncodeAlias home name alias opts graph
      | otherwise -> graph
    Can.DeriveJsonDecode opts
      | null typeParams -> addJsonDecodeAlias home name alias opts graph
      | otherwise -> graph

-- EQUALITY HELPER

-- | Generate a kernel equality call: @_Utils_equal(a, b)@.
kernelEq :: Opt.Expr -> Opt.Expr -> Names.Tracker Opt.Expr
kernelEq a b =
  do
    eqFn <- Names.registerKernel Name.utils (Opt.VarKernel Name.utils (Name.fromChars "equal"))
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

-- STRING APPEND HELPER

-- | Append two strings using @Basics.append@ (which wraps @_Utils_ap@).
strAppend :: Opt.Expr -> Opt.Expr -> Names.Tracker Opt.Expr
strAppend a b =
  do
    append_ <- Names.registerGlobal ModuleName.basics (Name.fromChars "append")
    pure (Opt.Call append_ [a, b])

-- SHOW UNION

addShowUnion ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Union ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addShowUnion home name (Can.Union _ _ alts _ opts _) graph =
  let funcName = Name.fromChars ("show" ++ Name.toChars name)
      (deps, fields, expr) = Names.run (toShowUnionExpr home alts opts)
      node = Opt.Define expr deps
   in addToGraph (Opt.Global home funcName) node fields graph

toShowUnionExpr ::
  ModuleName.Canonical ->
  [Can.Ctor] ->
  Can.CtorOpts ->
  Names.Tracker Opt.Expr
toShowUnionExpr home alts opts =
  case opts of
    Can.Enum -> toShowEnumExpr home alts
    _ -> toShowCtorExpr home alts

toShowEnumExpr ::
  ModuleName.Canonical ->
  [Can.Ctor] ->
  Names.Tracker Opt.Expr
toShowEnumExpr home alts =
  do
    let dollar = Name.fromChars "$"
    branches <- traverse (enumShowBranch home) alts
    let fallback = Opt.Str (Name.toCanopyString (Name.fromChars ""))
    pure (Opt.Function [dollar] (buildIfChain branches fallback))

enumShowBranch :: ModuleName.Canonical -> Can.Ctor -> Names.Tracker (Opt.Expr, Opt.Expr)
enumShowBranch home (Can.Ctor ctorName index _ _) =
  do
    let dollar = Name.fromChars "$"
    cond <- kernelEq (Opt.VarLocal dollar) (Opt.VarEnum (Opt.Global home ctorName) index)
    pure (cond, Opt.Str (Name.toCanopyString ctorName))

-- | Generate a Show function for union types with constructor arguments.
--
-- Builds an if-chain that matches on the @$@ field of the value,
-- then for each constructor concatenates the name with @Debug.toString@
-- of each argument field.
toShowCtorExpr ::
  ModuleName.Canonical ->
  [Can.Ctor] ->
  Names.Tracker Opt.Expr
toShowCtorExpr home alts =
  do
    let dollar = Name.fromChars "$"
    branches <- traverse (ctorShowBranch home) alts
    debugToString <- Names.registerGlobal ModuleName.debug "toString"
    let fallback = Opt.Call debugToString [Opt.VarLocal dollar]
    pure (Opt.Function [dollar] (buildIfChain branches fallback))

ctorShowBranch :: ModuleName.Canonical -> Can.Ctor -> Names.Tracker (Opt.Expr, Opt.Expr)
ctorShowBranch _home (Can.Ctor ctorName _index numArgs _) =
  do
    let dollar = Name.fromChars "$"
    cond <- ctorTagMatch dollar ctorName
    let nameStr = Opt.Str (Name.toCanopyString ctorName)
    case numArgs of
      0 -> pure (cond, nameStr)
      _ -> do
        result <- ctorShowArgs dollar nameStr numArgs
        pure (cond, result)

-- | Build string concatenation of ctor name with Debug.toString of each arg.
ctorShowArgs :: Name.Name -> Opt.Expr -> Int -> Names.Tracker Opt.Expr
ctorShowArgs dollar nameStr numArgs =
  do
    debugToString <- Names.registerGlobal ModuleName.debug "toString"
    let spaceStr = Name.toCanopyString (Name.fromChars " ")
    let argExprs = fmap (mkArgStr debugToString dollar) [0 .. numArgs - 1]
    foldl (\accM argExpr -> do acc <- accM; appendWithSpace acc spaceStr argExpr) (pure nameStr) argExprs
  where
    mkArgStr dbg d i = Opt.Call dbg [Opt.Access (Opt.VarLocal d) (ctorArgFieldName i)]

-- | Append a space and an argument string to an accumulator.
appendWithSpace :: Opt.Expr -> ES.String -> Opt.Expr -> Names.Tracker Opt.Expr
appendWithSpace acc spaceStr argExpr =
  do
    withSpace <- strAppend acc (Opt.Str spaceStr)
    strAppend withSpace argExpr

-- SHOW ALIAS

addShowAlias ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Alias ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addShowAlias home name (Can.Alias _ _ tipe _ _) graph =
  let funcName = Name.fromChars ("show" ++ Name.toChars name)
      (deps, fields, expr) = Names.run (toShowTypeExpr tipe)
      node = Opt.Define expr deps
   in addToGraph (Opt.Global home funcName) node fields graph

toShowTypeExpr :: Can.Type -> Names.Tracker Opt.Expr
toShowTypeExpr _tipe =
  let dollar = Name.fromChars "$"
   in do
        debugToString <- Names.registerGlobal ModuleName.debug "toString"
        pure (Opt.Function [dollar] (Opt.Call debugToString [Opt.VarLocal dollar]))

-- JSON ENCODE UNION

addJsonEncodeUnion ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Union ->
  Maybe Can.JsonOptions ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addJsonEncodeUnion home name (Can.Union _ _ alts _ opts _) _opts graph =
  let funcName = Name.fromChars ("encode" ++ Name.toChars name)
      (deps, fields, expr) = Names.run (toEncodeUnionExpr home alts opts)
      node = Opt.Define expr deps
   in addToGraph (Opt.Global home funcName) node fields graph

toEncodeUnionExpr ::
  ModuleName.Canonical ->
  [Can.Ctor] ->
  Can.CtorOpts ->
  Names.Tracker Opt.Expr
toEncodeUnionExpr home alts opts =
  case opts of
    Can.Enum -> toEncodeEnumExpr home alts
    _ -> toEncodeTaggedExpr home alts

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
  Names.Tracker Opt.Expr
toEncodeTaggedExpr home alts =
  do
    let dollar = Name.fromChars "$"
    encodeObject <- Names.registerGlobal elmJsonEncode "object"
    encodeString <- Names.registerGlobal elmJsonEncode "string"
    branches <- traverse (taggedEncodeBranch home encodeObject encodeString) alts
    let fallback = Opt.Call encodeObject [Opt.List []]
    pure (Opt.Function [dollar] (buildIfChain branches fallback))

taggedEncodeBranch ::
  ModuleName.Canonical ->
  Opt.Expr ->
  Opt.Expr ->
  Can.Ctor ->
  Names.Tracker (Opt.Expr, Opt.Expr)
taggedEncodeBranch _home encodeObject encodeString (Can.Ctor ctorName _index numArgs argTypes) =
  do
    let dollar = Name.fromChars "$"
    let tagStr = Name.toCanopyString (Name.fromChars "tag")
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
          let contentsPair = mkContentsPair (Opt.Call encoder [argExpr])
          pure (cond, Opt.Call encodeObject [Opt.List [tagPair, contentsPair]])
      _ ->
        do
          encodedArgs <- encodeCtorArgs dollar argTypes
          encodeList <- Names.registerGlobal elmJsonEncode "list"
          identity <- Names.registerGlobal ModuleName.basics Name.identity
          let contentsVal = Opt.Call encodeList [identity, Opt.List encodedArgs]
          let contentsPair = mkContentsPair contentsVal
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

-- | Build a @("contents", value)@ tuple.
mkContentsPair :: Opt.Expr -> Opt.Expr
mkContentsPair val =
  Opt.Tuple (Opt.Str (Name.toCanopyString (Name.fromChars "contents"))) val Nothing

-- JSON DECODE UNION

addJsonDecodeUnion ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Union ->
  Maybe Can.JsonOptions ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addJsonDecodeUnion home name (Can.Union _ _ alts _ opts _) _opts graph =
  let funcName = Name.fromChars (lowerFirst (Name.toChars name) ++ "Decoder")
      (deps, fields, expr) = Names.run (toDecodeUnionExpr home alts opts)
      node = Opt.Define expr deps
   in addToGraph (Opt.Global home funcName) node fields graph

toDecodeUnionExpr ::
  ModuleName.Canonical ->
  [Can.Ctor] ->
  Can.CtorOpts ->
  Names.Tracker Opt.Expr
toDecodeUnionExpr home alts opts =
  case opts of
    Can.Enum -> toDecodeEnumExpr home alts
    _ -> toDecodeTaggedExpr home alts

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
  Names.Tracker Opt.Expr
toDecodeTaggedExpr home alts =
  do
    decodeField <- Names.registerGlobal elmJsonDecode "field"
    decodeString <- Names.registerGlobal elmJsonDecode "string"
    andThen <- Names.registerGlobal elmJsonDecode "andThen"
    fail_ <- Names.registerGlobal elmJsonDecode "fail"
    let tagVar = Name.fromChars "tag"
    let tagDecoder = Opt.Call decodeField [Opt.Str (Name.toCanopyString (Name.fromChars "tag")), decodeString]
    branches <- traverse (taggedDecodeBranch home) alts
    let fallback = Opt.Call fail_ [Opt.Str (Name.toCanopyString (Name.fromChars "Unknown variant"))]
    let body = buildIfChain branches fallback
    let decoder = Opt.Function [tagVar] body
    pure (Opt.Call andThen [decoder, tagDecoder])

taggedDecodeBranch ::
  ModuleName.Canonical ->
  Can.Ctor ->
  Names.Tracker (Opt.Expr, Opt.Expr)
taggedDecodeBranch home (Can.Ctor ctorName _ numArgs argTypes) =
  do
    let tagVar = Name.fromChars "tag"
    cond <- kernelEq (Opt.VarLocal tagVar) (Opt.Str (Name.toCanopyString ctorName))
    let ctorVal = Opt.VarGlobal (Opt.Global home ctorName)
    result <- decodeCtorBody ctorVal numArgs argTypes
    pure (cond, result)

-- | Build the decoder body for a single constructor.
decodeCtorBody :: Opt.Expr -> Int -> [Can.Type] -> Names.Tracker Opt.Expr
decodeCtorBody ctorVal numArgs argTypes =
  case numArgs of
    0 -> do
      succeed <- Names.registerGlobal elmJsonDecode "succeed"
      pure (Opt.Call succeed [ctorVal])
    1 -> decodeSingleArg ctorVal (head' argTypes)
    _ -> decodeMultiArgs ctorVal argTypes

-- | Decode a single-argument constructor from @"contents"@.
decodeSingleArg :: Opt.Expr -> Can.Type -> Names.Tracker Opt.Expr
decodeSingleArg ctorVal argType =
  do
    decodeField <- Names.registerGlobal elmJsonDecode "field"
    decodeMap <- Names.registerGlobal elmJsonDecode "map"
    decoder0 <- Port.toDecoder argType
    let contentsStr = Name.toCanopyString (Name.fromChars "contents")
    let mapped = Opt.Call decodeMap [ctorVal, decoder0]
    pure (Opt.Call decodeField [Opt.Str contentsStr, mapped])

-- | Decode a multi-argument constructor from @"contents"@ array.
--
-- Generates: @field "contents" (index 0 dec0 |> andThen (\a -> index 1 dec1 |> andThen (\b -> succeed (Ctor a b))))@
decodeMultiArgs :: Opt.Expr -> [Can.Type] -> Names.Tracker Opt.Expr
decodeMultiArgs ctorVal argTypes =
  do
    decodeField <- Names.registerGlobal elmJsonDecode "field"
    succeed <- Names.registerGlobal elmJsonDecode "succeed"
    let contentsStr = Name.toCanopyString (Name.fromChars "contents")
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

addJsonEncodeAlias ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Alias ->
  Maybe Can.JsonOptions ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addJsonEncodeAlias home name (Can.Alias _ _ tipe _ _) _opts graph =
  let funcName = Name.fromChars ("encode" ++ Name.toChars name)
      (deps, fields, expr) = Names.run (Port.toEncoder tipe)
      node = Opt.Define expr deps
   in addToGraph (Opt.Global home funcName) node fields graph

-- JSON DECODE ALIAS

addJsonDecodeAlias ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Alias ->
  Maybe Can.JsonOptions ->
  Opt.LocalGraph ->
  Opt.LocalGraph
addJsonDecodeAlias home name (Can.Alias _ _ tipe _ _) _opts graph =
  let funcName = Name.fromChars (lowerFirst (Name.toChars name) ++ "Decoder")
      (deps, fields, expr) = Names.run (Port.toDecoder tipe)
      node = Opt.Define expr deps
   in addToGraph (Opt.Global home funcName) node fields graph

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
