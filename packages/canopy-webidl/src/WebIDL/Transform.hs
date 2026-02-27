{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

-- | WebIDL Type Transformation
--
-- Transforms WebIDL AST into Canopy-compatible types and structures.
-- Handles type mapping, name conversion, and interface resolution.
--
-- @since 0.20.0
module WebIDL.Transform
  ( -- * Transformation types
    CanopyModule(..)
  , CanopyType(..)
  , CanopyFunction(..)
  , CanopyRecord(..)
  , CanopyField(..)
  , CanopyUnion(..)
  , CanopyVariant(..)

    -- * Transformation functions
  , transformDefinitions
  , transformInterface
  , transformType
  , transformOperation
  , transformAttribute

    -- * Name conversion
  , toModuleName
  , toTypeName
  , toFunctionName
  , toFieldName

    -- * Mixin resolution
  , resolveMixins
  , mergePartials
  ) where

import Data.Char (toLower, toUpper)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text

import WebIDL.AST
import WebIDL.Config


-- | A transformed Canopy module
data CanopyModule = CanopyModule
  { cmName :: !Text
    -- ^ Module name (e.g., "Dom.Element")
  , cmExports :: ![Text]
    -- ^ Exported names
  , cmImports :: ![Text]
    -- ^ Required imports
  , cmTypes :: ![CanopyType]
    -- ^ Type definitions
  , cmFunctions :: ![CanopyFunction]
    -- ^ Function definitions
  , cmRecords :: ![CanopyRecord]
    -- ^ Record type definitions
  , cmUnions :: ![CanopyUnion]
    -- ^ Union type definitions
  } deriving (Eq, Show)


-- | A Canopy type reference
data CanopyType
  = CTInt
  | CTFloat
  | CTBool
  | CTString
  | CTChar
  | CTUnit
  | CTValue
    -- ^ Opaque JavaScript value
  | CTMaybe !CanopyType
  | CTList !CanopyType
  | CTTask !CanopyType !CanopyType
    -- ^ Task error success
  | CTDict !CanopyType !CanopyType
  | CTTuple ![CanopyType]
  | CTRecord !Text
    -- ^ Named record type
  | CTUnion !Text
    -- ^ Named union type
  | CTCustom !Text
    -- ^ Custom/imported type
  | CTFunction ![CanopyType] !CanopyType
    -- ^ Function type
  deriving (Eq, Show)


-- | A Canopy function definition
data CanopyFunction = CanopyFunction
  { cfName :: !Text
    -- ^ Function name
  , cfDoc :: !(Maybe Text)
    -- ^ Documentation
  , cfParams :: ![(Text, CanopyType)]
    -- ^ Parameters (name, type)
  , cfReturn :: !CanopyType
    -- ^ Return type
  , cfIsStatic :: !Bool
    -- ^ Whether it's a static method
  , cfJsName :: !Text
    -- ^ Original JavaScript name
  , cfJsTarget :: !(Maybe Text)
    -- ^ Target interface for method calls
  } deriving (Eq, Show)


-- | A Canopy record type definition
data CanopyRecord = CanopyRecord
  { crName :: !Text
    -- ^ Record type name
  , crDoc :: !(Maybe Text)
    -- ^ Documentation
  , crFields :: ![CanopyField]
    -- ^ Record fields
  } deriving (Eq, Show)


-- | A record field
data CanopyField = CanopyField
  { cfldName :: !Text
    -- ^ Field name
  , cfldType :: !CanopyType
    -- ^ Field type
  , cfldRequired :: !Bool
    -- ^ Whether the field is required
  , cfldDefault :: !(Maybe Text)
    -- ^ Default value expression
  } deriving (Eq, Show)


-- | A Canopy union type definition
data CanopyUnion = CanopyUnion
  { cuName :: !Text
    -- ^ Union type name
  , cuDoc :: !(Maybe Text)
    -- ^ Documentation
  , cuVariants :: ![CanopyVariant]
    -- ^ Union variants
  } deriving (Eq, Show)


-- | A union variant
data CanopyVariant = CanopyVariant
  { cvName :: !Text
    -- ^ Variant constructor name
  , cvPayload :: !(Maybe CanopyType)
    -- ^ Optional payload type
  } deriving (Eq, Show)


-- | Transform all definitions into Canopy modules
transformDefinitions :: Config -> Definitions -> [CanopyModule]
transformDefinitions config defs =
  transformInterfaces config resolvedDefs
  where
    merged = mergePartials defs
    resolvedDefs = resolveMixins merged


-- | Merge partial interfaces/dictionaries with their main definitions
mergePartials :: Definitions -> Definitions
mergePartials defs = Map.elems mergedInterfaces ++ otherDefs
  where
    interfaces = extractInterfaces defs
    partials = extractPartialInterfaces defs
    dictionaries = extractDictionaries defs
    partialDicts = extractPartialDictionaries defs
    otherDefs = extractOther defs

    mergedInterfaces = Map.mapWithKey (mergeInterface partials) interfaces
      `Map.union` mergedDictionaries

    mergedDictionaries = Map.mapWithKey (mergeDictionary partialDicts) dictionaries


-- | Extract interfaces from definitions
extractInterfaces :: Definitions -> Map Text Definition
extractInterfaces = Map.fromList . foldr extract []
  where
    extract (DefInterface intf) acc = (intfName intf, DefInterface intf) : acc
    extract _ acc = acc


-- | Extract partial interfaces
extractPartialInterfaces :: Definitions -> Map Text [PartialInterface]
extractPartialInterfaces = foldr extract Map.empty
  where
    extract (DefPartialInterface partial) acc =
      Map.insertWith (++) (partialIntfName partial) [partial] acc
    extract _ acc = acc


-- | Extract dictionaries
extractDictionaries :: Definitions -> Map Text Definition
extractDictionaries = Map.fromList . foldr extract []
  where
    extract (DefDictionary dict) acc = (dictName dict, DefDictionary dict) : acc
    extract _ acc = acc


-- | Extract partial dictionaries
extractPartialDictionaries :: Definitions -> Map Text [Dictionary]
extractPartialDictionaries = foldr extract Map.empty
  where
    extract (DefPartialDictionary dict) acc =
      Map.insertWith (++) (dictName dict) [dict] acc
    extract _ acc = acc


-- | Extract other definitions
extractOther :: Definitions -> Definitions
extractOther = filter isOther
  where
    isOther DefInterface {} = False
    isOther DefPartialInterface {} = False
    isOther DefMixin {} = False
    isOther DefPartialMixin {} = False
    isOther DefDictionary {} = False
    isOther DefPartialDictionary {} = False
    isOther _ = True


-- | Merge partial interface into main interface
mergeInterface :: Map Text [PartialInterface] -> Text -> Definition -> Definition
mergeInterface partials name (DefInterface intf) =
  case Map.lookup name partials of
    Nothing -> DefInterface intf
    Just parts -> DefInterface intf
      { intfMembers = intfMembers intf ++ concatMap partialIntfMembers parts
      }
mergeInterface _ _ def = def


-- | Merge partial dictionary into main dictionary
mergeDictionary :: Map Text [Dictionary] -> Text -> Definition -> Definition
mergeDictionary partials name (DefDictionary dict) =
  case Map.lookup name partials of
    Nothing -> DefDictionary dict
    Just parts -> DefDictionary dict
      { dictMembers = dictMembers dict ++ concatMap dictMembers parts
      }
mergeDictionary _ _ def = def


-- | Resolve mixin includes into interfaces
resolveMixins :: Definitions -> Definitions
resolveMixins defs = map resolveDef defs
  where
    mixins = Map.fromList
      [ (mixinName m, m) | DefMixin m <- defs ]

    includes = Map.fromListWith (++)
      [ (target, [mixin]) | DefIncludes target mixin <- defs ]

    resolveDef (DefInterface intf) =
      DefInterface intf
        { intfMembers = intfMembers intf ++ mixinMembers' }
      where
        mixinNames = Map.findWithDefault [] (intfName intf) includes
        mixinMembers' = concatMap (getMixinMembers mixins) mixinNames

    resolveDef def = def

    getMixinMembers mixinMap name =
      maybe [] (map mixinToInterface . mixinMembers) (Map.lookup name mixinMap)

    mixinToInterface = \case
      MMConst c -> IMConst c
      MMOperation op -> IMOperation op
      MMAttribute attr -> IMAttribute attr
      MMStringifier maybeAttr -> IMStringifier maybeAttr


-- | Transform interfaces to Canopy modules
transformInterfaces :: Config -> Definitions -> [CanopyModule]
transformInterfaces config = mapMaybe (transformDef config)


-- | Transform a single definition
transformDef :: Config -> Definition -> Maybe CanopyModule
transformDef config = \case
  DefInterface intf -> Just (transformInterface config intf)
  DefDictionary dict -> Just (transformDictionary config dict)
  DefEnum enum -> Just (transformEnum config enum)
  _ -> Nothing


-- | Transform an interface to a Canopy module
transformInterface :: Config -> Interface -> CanopyModule
transformInterface config intf = CanopyModule
  { cmName = moduleName
  , cmExports = exports
  , cmImports = collectImports functions
  , cmTypes = []
  , cmFunctions = functions
  , cmRecords = []
  , cmUnions = []
  }
  where
    moduleName = toModuleName config (intfName intf)
    functions = transformMembers config (intfName intf) (intfMembers intf)
    exports = map cfName functions


-- | Transform interface members to functions
transformMembers :: Config -> Text -> [InterfaceMember] -> [CanopyFunction]
transformMembers config intfName = concatMap transformMember
  where
    transformMember = \case
      IMOperation op -> [transformOperation config intfName op]
      IMAttribute attr ->
        transformAttributeToFunctions config intfName attr
      IMConstructor ctor -> [transformConstructor config intfName ctor]
      IMStaticMember (IMOperation op) ->
        [transformStaticOperation config intfName op]
      IMStaticMember (IMAttribute attr) ->
        transformStaticAttributeToFunctions config intfName attr
      _ -> []


-- | Transform an operation to a function
transformOperation :: Config -> Text -> Operation -> CanopyFunction
transformOperation config intfName op = CanopyFunction
  { cfName = functionName
  , cfDoc = extractDoc (opExtended op)
  , cfParams = selfParam : transformedParams
  , cfReturn = transformType config (opReturnType op)
  , cfIsStatic = False
  , cfJsName = maybe functionName id (opName op)
  , cfJsTarget = Just intfName
  }
  where
    baseName = maybe "invoke" id (opName op)
    functionName = toFunctionName baseName
    selfParam = ("self", CTCustom intfName)
    transformedParams = map (transformArgument config) (opArguments op)


-- | Transform a static operation
transformStaticOperation :: Config -> Text -> Operation -> CanopyFunction
transformStaticOperation config intfName op = CanopyFunction
  { cfName = functionName
  , cfDoc = extractDoc (opExtended op)
  , cfParams = transformedParams
  , cfReturn = transformType config (opReturnType op)
  , cfIsStatic = True
  , cfJsName = maybe functionName id (opName op)
  , cfJsTarget = Just intfName
  }
  where
    baseName = maybe "invoke" id (opName op)
    functionName = toFunctionName baseName
    transformedParams = map (transformArgument config) (opArguments op)


-- | Transform an attribute to getter/setter functions
transformAttribute :: Config -> Text -> Attribute -> [CanopyFunction]
transformAttribute = transformAttributeToFunctions


-- | Transform attribute to getter (and optional setter)
transformAttributeToFunctions :: Config -> Text -> Attribute -> [CanopyFunction]
transformAttributeToFunctions config intfName attr =
  getter : if attrReadonly attr then [] else [setter]
  where
    transformedType = transformType config (attrType attr)
    baseName = attrName attr

    getter = CanopyFunction
      { cfName = toFunctionName baseName
      , cfDoc = extractDoc (attrExtended attr)
      , cfParams = [("self", CTCustom intfName)]
      , cfReturn = transformedType
      , cfIsStatic = False
      , cfJsName = baseName
      , cfJsTarget = Just intfName
      }

    setter = CanopyFunction
      { cfName = toFunctionName ("set" <> capitalizeFirst baseName)
      , cfDoc = Nothing
      , cfParams = [("self", CTCustom intfName), ("value", transformedType)]
      , cfReturn = CTUnit
      , cfIsStatic = False
      , cfJsName = baseName
      , cfJsTarget = Just intfName
      }


-- | Transform static attribute
transformStaticAttributeToFunctions :: Config -> Text -> Attribute -> [CanopyFunction]
transformStaticAttributeToFunctions config intfName attr =
  getter : if attrReadonly attr then [] else [setter]
  where
    transformedType = transformType config (attrType attr)
    baseName = attrName attr

    getter = CanopyFunction
      { cfName = toFunctionName baseName
      , cfDoc = extractDoc (attrExtended attr)
      , cfParams = []
      , cfReturn = transformedType
      , cfIsStatic = True
      , cfJsName = baseName
      , cfJsTarget = Just intfName
      }

    setter = CanopyFunction
      { cfName = toFunctionName ("set" <> capitalizeFirst baseName)
      , cfDoc = Nothing
      , cfParams = [("value", transformedType)]
      , cfReturn = CTUnit
      , cfIsStatic = True
      , cfJsName = baseName
      , cfJsTarget = Just intfName
      }


-- | Transform a constructor
transformConstructor :: Config -> Text -> Constructor -> CanopyFunction
transformConstructor config intfName ctor = CanopyFunction
  { cfName = toFunctionName ("new" <> intfName)
  , cfDoc = extractDoc (ctorExtended ctor)
  , cfParams = map (transformArgument config) (ctorArguments ctor)
  , cfReturn = CTCustom intfName
  , cfIsStatic = True
  , cfJsName = intfName
  , cfJsTarget = Nothing
  }


-- | Transform an argument
transformArgument :: Config -> Argument -> (Text, CanopyType)
transformArgument config arg = (name, ty)
  where
    name = toFieldName (argName arg)
    baseTy = transformType config (argType arg)
    ty = if argOptional arg then CTMaybe baseTy else baseTy


-- | Transform a dictionary to a module
transformDictionary :: Config -> Dictionary -> CanopyModule
transformDictionary config dict = CanopyModule
  { cmName = toModuleName config (dictName dict)
  , cmExports = [dictName dict]
  , cmImports = collectRecordImports record
  , cmTypes = []
  , cmFunctions = []
  , cmRecords = [record]
  , cmUnions = []
  }
  where
    record = CanopyRecord
      { crName = dictName dict
      , crDoc = Nothing
      , crFields = map (transformDictMember config) (dictMembers dict)
      }


-- | Transform a dictionary member
transformDictMember :: Config -> DictionaryMember -> CanopyField
transformDictMember config dm = CanopyField
  { cfldName = toFieldName (dmName dm)
  , cfldType = transformType config (dmType dm)
  , cfldRequired = dmRequired dm
  , cfldDefault = fmap renderDefault (dmDefault dm)
  }


-- | Transform an enum to a module
transformEnum :: Config -> IDLEnum -> CanopyModule
transformEnum config enum = CanopyModule
  { cmName = toModuleName config (enumName enum)
  , cmExports = [enumName enum]
  , cmImports = []
  , cmTypes = []
  , cmFunctions = []
  , cmRecords = []
  , cmUnions = [union]
  }
  where
    union = CanopyUnion
      { cuName = enumName enum
      , cuDoc = Nothing
      , cuVariants = map toVariant (enumValues enum)
      }

    toVariant val = CanopyVariant
      { cvName = toTypeName val
      , cvPayload = Nothing
      }


-- | Transform a WebIDL type to a Canopy type
transformType :: Config -> IDLType -> CanopyType
transformType config = \case
  TyPrimitive prim -> transformPrimitive config prim
  TyString _ -> CTString
  TyBuffer _ -> CTCustom "Bytes"
  TyIdentifier name -> lookupType config name
  TySequence inner -> CTList (transformType config inner)
  TyFrozenArray inner -> CTList (transformType config inner)
  TyObservableArray inner -> CTList (transformType config inner)
  TyRecord _ valTy -> CTDict CTString (transformType config valTy)
  TyPromise inner -> CTTask (CTCustom "Error") (transformType config inner)
  TyUnion types -> CTUnion (unionTypeName types)
  TyNullable inner -> CTMaybe (transformType config inner)
  TyAny -> CTValue
  TyVoid -> CTUnit
  TyUndefined -> CTUnit
  TyObject -> CTValue
  TySymbol -> CTValue


-- | Transform a primitive type
transformPrimitive :: Config -> PrimitiveType -> CanopyType
transformPrimitive _ = \case
  PrimBoolean -> CTBool
  PrimByte -> CTInt
  PrimOctet -> CTInt
  PrimShort -> CTInt
  PrimUnsignedShort -> CTInt
  PrimLong -> CTInt
  PrimUnsignedLong -> CTInt
  PrimLongLong -> CTInt
  PrimUnsignedLongLong -> CTInt
  PrimFloat -> CTFloat
  PrimUnrestrictedFloat -> CTFloat
  PrimDouble -> CTFloat
  PrimUnrestrictedDouble -> CTFloat
  PrimBigint -> CTInt


-- | Look up a type name in configuration
lookupType :: Config -> Text -> CanopyType
lookupType config name =
  case Map.lookup name (mapInterfaces (configTypeMapping config)) of
    Just mapped -> CTCustom mapped
    Nothing -> CTCustom name


-- | Generate a union type name
unionTypeName :: [IDLType] -> Text
unionTypeName types = Text.intercalate "Or" (map typeName types)
  where
    typeName = \case
      TyPrimitive PrimBoolean -> "Bool"
      TyPrimitive _ -> "Number"
      TyString _ -> "String"
      TyIdentifier n -> n
      _ -> "Value"


-- | Convert to module name
toModuleName :: Config -> Text -> Text
toModuleName config name =
  pkgModulePrefix (configPackage config) <> "." <> name


-- | Convert to type name (PascalCase)
toTypeName :: Text -> Text
toTypeName txt = Text.concat (map capitalizeFirst (Text.words cleaned))
  where
    cleaned = Text.filter (\c -> c /= '-' && c /= '_') txt


-- | Convert to function name (camelCase)
toFunctionName :: Text -> Text
toFunctionName txt
  | Text.null txt = txt
  | otherwise = uncapitalizeFirst (toTypeName txt)


-- | Convert to field name (camelCase)
toFieldName :: Text -> Text
toFieldName = toFunctionName


-- | Capitalize first character
capitalizeFirst :: Text -> Text
capitalizeFirst txt =
  case Text.uncons txt of
    Nothing -> txt
    Just (c, rest) -> Text.cons (toUpper c) rest


-- | Uncapitalize first character
uncapitalizeFirst :: Text -> Text
uncapitalizeFirst txt =
  case Text.uncons txt of
    Nothing -> txt
    Just (c, rest) -> Text.cons (toLower c) rest


-- | Extract documentation from extended attributes
extractDoc :: ExtendedAttributes -> Maybe Text
extractDoc attrs = listToMaybe
  [ desc | EAIdent "Description" desc <- attrs ]
  where
    listToMaybe [] = Nothing
    listToMaybe (x:_) = Just x


-- | Render a default value to Canopy code
renderDefault :: DefaultValue -> Text
renderDefault = \case
  DVNull -> "Nothing"
  DVBool True -> "True"
  DVBool False -> "False"
  DVInteger n -> Text.pack (show n)
  DVFloat f -> Text.pack (show f)
  DVString s -> "\"" <> s <> "\""
  DVEmptySequence -> "[]"
  DVEmptyDictionary -> "Dict.empty"
  DVIdentifier name -> name


-- | Collect imports needed for functions
collectImports :: [CanopyFunction] -> [Text]
collectImports funcs = Set.toList (Set.fromList imports)
  where
    imports = concatMap collectFuncImports funcs

    collectFuncImports func =
      concatMap collectTypeImports (cfReturn func : map snd (cfParams func))

    collectTypeImports = \case
      CTMaybe inner -> "Maybe" : collectTypeImports inner
      CTList inner -> "List" : collectTypeImports inner
      CTTask e s -> "Task" : collectTypeImports e ++ collectTypeImports s
      CTDict k v -> "Dict" : collectTypeImports k ++ collectTypeImports v
      CTCustom name -> [name]
      _ -> []


-- | Collect imports for a record
collectRecordImports :: CanopyRecord -> [Text]
collectRecordImports record =
  Set.toList (Set.fromList (concatMap (collectTypeImports . cfldType) (crFields record)))
  where
    collectTypeImports = \case
      CTMaybe inner -> "Maybe" : collectTypeImports inner
      CTList inner -> "List" : collectTypeImports inner
      CTTask e s -> "Task" : collectTypeImports e ++ collectTypeImports s
      CTDict k v -> "Dict" : collectTypeImports k ++ collectTypeImports v
      CTCustom name -> [name]
      _ -> []


-- | mapMaybe implementation
mapMaybe :: (a -> Maybe b) -> [a] -> [b]
mapMaybe f = foldr (\x acc -> maybe acc (: acc) (f x)) []
