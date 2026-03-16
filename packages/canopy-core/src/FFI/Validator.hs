{-# LANGUAGE OverloadedStrings #-}

-- | FFI Runtime Validation
--
-- This module generates JavaScript validators for FFI type boundaries.
-- These validators ensure type safety at runtime when calling JavaScript
-- functions from Canopy code.
--
-- = Usage
--
-- In strict FFI mode (@--ffi-strict@), the generated JavaScript includes
-- runtime type checks for FFI function return values:
--
-- @
-- function validateInt(v, name) {
--   if (!Number.isInteger(v)) {
--     throw new Error('FFI type error: ' + name + ' expected Int, got ' + typeof v);
--   }
--   return v;
-- }
-- @
--
-- = Validation Strategy
--
-- * Primitive types: Direct typeof/Number.isInteger checks
-- * List types: Array.isArray + recursive element validation
-- * Maybe types: null check + value validation
-- * Result types: Structure check ($: 'Ok' | 'Err') + field validation
-- * Task types: Promise check + result validation on resolution
-- * Opaque types: Optional instanceof check (configurable)
--
-- @since 0.19.1
module FFI.Validator
  ( -- * Validator generation
    generateValidator
  , generateValidatorName
  , generateAllValidators
  , generateOpaqueValidator
  , ValidatorConfig(..)
  , defaultConfig

    -- * FFI type representation (re-exported from FFI.Types)
  , FFIType(..)

    -- * Opaque kind (re-exported from FFI.Types)
  , OpaqueKind(..)

    -- * Type string parsing (delegated to FFI.TypeParser)
  , parseFFIType
  , parseReturnType
  ) where

import qualified Data.Text as Text
import Data.Text (Text)
import FFI.Types (FFIType (..), OpaqueKind (..))
import qualified FFI.TypeParser as TypeParser

-- | Configuration for validator generation
data ValidatorConfig = ValidatorConfig
  { _configStrictMode :: !Bool
    -- ^ Enable strict validation (throws on type mismatch)
  , _configValidateOpaque :: !Bool
    -- ^ Validate opaque types with instanceof checks
  , _configDebugMode :: !Bool
    -- ^ Include debug information in error messages
  } deriving (Eq, Show)

-- | Default validator configuration
defaultConfig :: ValidatorConfig
defaultConfig = ValidatorConfig
  { _configStrictMode = True
  , _configValidateOpaque = False
  , _configDebugMode = False
  }

-- FFIType is imported from FFI.Types (single source of truth)

-- | Generate a unique validator name for a type
generateValidatorName :: FFIType -> Text
generateValidatorName ffiType = "_validate_" <> typeToSuffix ffiType
  where
    typeToSuffix :: FFIType -> Text
    typeToSuffix t = case t of
      FFIInt -> "Int"
      FFIFloat -> "Float"
      FFIString -> "String"
      FFIBool -> "Bool"
      FFIUnit -> "Unit"
      FFIList inner -> "List_" <> typeToSuffix inner
      FFIMaybe inner -> "Maybe_" <> typeToSuffix inner
      FFIResult e v -> "Result_" <> typeToSuffix e <> "_" <> typeToSuffix v
      FFITask e v -> "Task_" <> typeToSuffix e <> "_" <> typeToSuffix v
      FFITuple types -> "Tuple_" <> Text.intercalate "_" (map typeToSuffix types)
      FFITypeVar name -> "Var_" <> sanitizeName name
      FFIOpaque name _ -> "Opaque_" <> sanitizeName name
      FFIFunctionType _ ret -> "Fn_" <> typeToSuffix ret
      FFIRecord fields -> "Rec_" <> Text.intercalate "_" (map (sanitizeName . fst) fields)

    sanitizeName :: Text -> Text
    sanitizeName = Text.filter (\c -> c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9')

-- | Generate JavaScript validator function for an FFI type
generateValidator :: ValidatorConfig -> FFIType -> Text
generateValidator config ffiType =
  let name = generateValidatorName ffiType
      body = generateValidatorBody config ffiType
  in Text.unlines
       [ "function " <> name <> "(v, ctx) {"
       , body
       , "}"
       ]

-- | Generate the body of a validator function
generateValidatorBody :: ValidatorConfig -> FFIType -> Text
generateValidatorBody config ffiType = case ffiType of
  FFIInt ->
    indent <> "if (!Number.isInteger(v)) {\n"
    <> indent <> "  " <> throwError config "Int" <> "\n"
    <> indent <> "}\n"
    <> indent <> "return v;"

  FFIFloat ->
    indent <> "if (typeof v !== 'number') {\n"
    <> indent <> "  " <> throwError config "Float" <> "\n"
    <> indent <> "}\n"
    <> indent <> "if (!Number.isFinite(v)) {\n"
    <> indent <> "  " <> throwError config "finite Float" <> "\n"
    <> indent <> "}\n"
    <> indent <> "return v;"

  FFIString ->
    indent <> "if (typeof v !== 'string') {\n"
    <> indent <> "  " <> throwError config "String" <> "\n"
    <> indent <> "}\n"
    <> indent <> "return v;"

  FFIBool ->
    indent <> "if (typeof v !== 'boolean') {\n"
    <> indent <> "  " <> throwError config "Bool" <> "\n"
    <> indent <> "}\n"
    <> indent <> "return v;"

  FFIUnit ->
    indent <> "return v;"

  FFIList inner ->
    let innerValidator = generateValidatorName inner
    in indent <> "if (!Array.isArray(v)) {\n"
       <> indent <> "  " <> throwError config "List" <> "\n"
       <> indent <> "}\n"
       <> indent <> "return v.map(function(el, i) { return " <> innerValidator <> "(el, ctx + '[' + i + ']'); });"

  FFIMaybe inner ->
    let innerValidator = generateValidatorName inner
    in indent <> "if (v == null) { return { $: 'Nothing' }; }\n"
       <> indent <> "return { $: 'Just', a: " <> innerValidator <> "(v, ctx) };"

  FFIResult errType valType ->
    let errValidator = generateValidatorName errType
        valValidator = generateValidatorName valType
    in indent <> "if (typeof v !== 'object' || v === null || !Object.prototype.hasOwnProperty.call(v, '$')) {\n"
       <> indent <> "  " <> throwError config "Result" <> "\n"
       <> indent <> "}\n"
       <> indent <> "if (v.$ === 'Ok') {\n"
       <> indent <> "  return { $: 'Ok', a: " <> valValidator <> "(v.a, ctx + '.Ok') };\n"
       <> indent <> "} else if (v.$ === 'Err') {\n"
       <> indent <> "  return { $: 'Err', a: " <> errValidator <> "(v.a, ctx + '.Err') };\n"
       <> indent <> "}\n"
       <> indent <> throwError config "Result (invalid $)"

  FFITask errType valType ->
    let errValidator = generateValidatorName errType
        valValidator = generateValidatorName valType
    in indent <> "if (typeof v !== 'object' || v === null || typeof v.then !== 'function') {\n"
       <> indent <> "  " <> throwError config "Task (expected Promise)" <> "\n"
       <> indent <> "}\n"
       <> indent <> "return v.then(\n"
       <> indent <> "  function(ok) {\n"
       <> indent <> "    try { return { $: 'Ok', a: " <> valValidator <> "(ok, ctx + '.then') }; }\n"
       <> indent <> "    catch (e) { return { $: 'Err', a: " <> errValidator <> "(String(e), ctx + '.validation') }; }\n"
       <> indent <> "  },\n"
       <> indent <> "  function(err) {\n"
       <> indent <> "    try { return { $: 'Err', a: " <> errValidator <> "(err, ctx + '.catch') }; }\n"
       <> indent <> "    catch (e) { return { $: 'Err', a: String(e) }; }\n"
       <> indent <> "  }\n"
       <> indent <> ");"

  FFITuple types ->
    let validators = map generateValidatorName types
        checks = zipWith (\idx vn -> vn <> "(v[" <> Text.pack (show (idx :: Int)) <> "], ctx + '[" <> Text.pack (show idx) <> "]')") [0..] validators
    in indent <> "if (!Array.isArray(v) || v.length !== " <> Text.pack (show (length types)) <> ") {\n"
       <> indent <> "  " <> throwError config ("Tuple" <> Text.pack (show (length types))) <> "\n"
       <> indent <> "}\n"
       <> indent <> "return [" <> Text.intercalate ", " checks <> "];"

  FFITypeVar _ ->
    indent <> "if (typeof v === 'undefined') {\n"
    <> indent <> "  " <> throwError config "non-undefined value" <> "\n"
    <> indent <> "}\n"
    <> indent <> "return v;"

  FFIOpaque typeName _ ->
    generateOpaqueValidatorBody config typeName Unverified

  FFIFunctionType _ _ ->
    indent <> "if (typeof v !== 'function') {\n"
    <> indent <> "  " <> throwError config "Function" <> "\n"
    <> indent <> "}\n"
    <> indent <> "return v;"

  FFIRecord fields ->
    indent <> "if (typeof v !== 'object' || v === null || Array.isArray(v)) {\n"
    <> indent <> "  " <> throwError config "Record" <> "\n"
    <> indent <> "}\n"
    <> Text.concat (map validateField fields)
    <> indent <> "return v;"

  where
    validateField (name, fieldType) =
      indent <> "if (!Object.prototype.hasOwnProperty.call(v, '" <> name <> "')) {\n"
      <> indent <> "  " <> throwError config ("Record (missing field " <> name <> ")") <> "\n"
      <> indent <> "}\n"
      <> indent <> generateValidatorName fieldType <> "(v." <> name <> ", ctx + '." <> name <> "');\n"
    indent = "  "

-- | Generate an opaque type validator body using the 'OpaqueKind' strategy.
--
-- * 'ClassBacked' — uses @instanceof@ to verify the JS class
-- * 'SymbolBranded' — checks for a unique symbol brand property
-- * 'Unverified' — only rejects null/undefined (legacy behavior)
--
-- @since 0.20.1
generateOpaqueValidatorBody :: ValidatorConfig -> Text -> OpaqueKind -> Text
generateOpaqueValidatorBody config typeName opaqueKind =
  indent <> "if (v == null) {\n"
    <> indent <> "  " <> throwError config typeName <> "\n"
    <> indent <> "}\n"
    <> kindCheck
    <> indent <> "return v;"
  where
    indent = "  "
    kindCheck = case opaqueKind of
      ClassBacked className ->
        indent <> "if (!(v instanceof " <> className <> ")) {\n"
          <> indent <> "  " <> throwError config (typeName <> " (expected instanceof " <> className <> ")") <> "\n"
          <> indent <> "}\n"
      SymbolBranded brandName ->
        indent <> "if (!v['__canopy_brand_" <> brandName <> "']) {\n"
          <> indent <> "  " <> throwError config (typeName <> " (missing brand " <> brandName <> ")") <> "\n"
          <> indent <> "}\n"
      Unverified ->
        if _configValidateOpaque config
          then indent <> "if (!(v instanceof " <> typeName <> ")) {\n"
                <> indent <> "  " <> throwError config typeName <> "\n"
                <> indent <> "}\n"
          else ""

-- | Generate a complete opaque validator function with a specific 'OpaqueKind'.
--
-- @since 0.20.1
generateOpaqueValidator :: ValidatorConfig -> Text -> OpaqueKind -> Text
generateOpaqueValidator config typeName opaqueKind =
  Text.unlines
    [ "function _validate_Opaque_" <> sanitize typeName <> "(v, ctx) {",
      generateOpaqueValidatorBody config typeName opaqueKind,
      "}"
    ]
  where
    sanitize = Text.filter (\c -> c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9')

-- | Generate error throwing statement
throwError :: ValidatorConfig -> Text -> Text
throwError config expectedType =
  if _configStrictMode config
    then if _configDebugMode config
           then "throw new Error('FFI type error at ' + ctx + ': expected " <> expectedType <> ", got ' + typeof v + ': ' + JSON.stringify(v));"
           else "throw new Error('FFI type error at ' + ctx + ': expected " <> expectedType <> ", got ' + typeof v);"
    else "console.warn('FFI type warning at ' + ctx + ': expected " <> expectedType <> ", got ' + typeof v);"

-- | Generate all required validators for a type and its nested types
generateAllValidators :: ValidatorConfig -> FFIType -> Text
generateAllValidators config ffiType =
  Text.unlines (map (generateValidator config) (collectTypes ffiType))
  where
    collectTypes :: FFIType -> [FFIType]
    collectTypes t = t : concatMap collectTypes (childTypes t)

    childTypes :: FFIType -> [FFIType]
    childTypes ty = case ty of
      FFIList inner -> [inner]
      FFIMaybe inner -> [inner]
      FFIResult e v -> [e, v]
      FFITask e v -> [e, v]
      FFITuple types -> types
      FFIFunctionType args ret -> args ++ [ret]
      FFIRecord fields -> map snd fields
      FFITypeVar _ -> []
      _ -> []

-- | Parse a type string into FFIType.
--
-- Delegates to the unified parser in "FFI.TypeParser".
parseFFIType :: Text -> Maybe FFIType
parseFFIType = TypeParser.parseType

-- | Parse and extract just the return type from a function type string.
--
-- Delegates to the unified parser in "FFI.TypeParser".
parseReturnType :: Text -> Maybe FFIType
parseReturnType = TypeParser.parseReturnType
