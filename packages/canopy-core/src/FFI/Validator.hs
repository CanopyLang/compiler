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
-- function _validate_Int(v, ctx) {
--   if (!Number.isInteger(v)) {
--     throw new Error('FFI type error at ' + ctx + ': expected Int, got ' + typeof v);
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
-- All validator code is generated through the 'Generate.JavaScript.Builder'
-- AST rather than text concatenation, ensuring correct JS syntax and
-- enabling future optimisations.
--
-- @since 0.19.1
module FFI.Validator
  ( -- * Validator generation
    generateValidator
  , generateValidatorName
  , generateAllValidators
  , generateAllValidatorsDeduped
  , generateOpaqueValidator
  , collectAllTypes
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

import qualified Data.ByteString.Builder as BB
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString as BS
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Text (Text)
import qualified Data.Text.Encoding as TextEnc
import FFI.Types (FFIType (..), OpaqueKind (..))
import qualified FFI.TypeParser as TypeParser
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Name as JsName

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


-- INTERNAL AST HELPERS


-- | Construct a 'JsName.Name' from a 'String'.
nm :: String -> JsName.Name
nm = JsName.fromBuilder . BB.stringUtf8

-- | Construct a 'JsName.Name' from a 'Text' value.
nameFromText :: Text -> JsName.Name
nameFromText = JsName.fromBuilder . BB.byteString . TextEnc.encodeUtf8

-- | Reference a JavaScript variable by name (String literal).
ref :: String -> JS.Expr
ref = JS.Ref . nm

-- | Reference a JavaScript variable by name (Text value).
refT :: Text -> JS.Expr
refT = JS.Ref . nameFromText

-- | JavaScript string expression from a 'Text' value.
strE :: Text -> JS.Expr
strE t = JS.String (BB.byteString (TextEnc.encodeUtf8 t))

-- | @Object.prototype.hasOwnProperty.call(v, fieldName)@
hasProp :: JS.Expr -> Text -> JS.Expr
hasProp obj fieldName =
  JS.Call
    (JS.Access
      (JS.Access
        (JS.Access (ref "Object") (nm "prototype"))
        (nm "hasOwnProperty"))
      (nm "call"))
    [obj, strE fieldName]

-- | Build the error or warning message expression for a type mismatch.
--
-- In debug mode appends @: @ + JSON.stringify(v) for extra context.
mismatchMsg :: ValidatorConfig -> Text -> Text -> JS.Expr
mismatchMsg config prefix expectedType =
  if _configDebugMode config
    then JS.Infix JS.OpAdd
           (JS.Infix JS.OpAdd base (strE ": "))
           (JS.Call
             (JS.Access (ref "JSON") (nm "stringify"))
             [ref "v"])
    else base
  where
    base =
      JS.Infix JS.OpAdd
        (JS.Infix JS.OpAdd
          (JS.Infix JS.OpAdd
            (strE (prefix <> " at "))
            (ref "ctx"))
          (strE (": expected " <> expectedType <> ", got ")))
        (JS.Prefix JS.PrefixTypeof (ref "v"))

-- | Generate a throw/warn statement for a type mismatch.
--
-- In strict mode emits @throw new Error(...)@; in non-strict mode emits
-- @console.warn(...)@.
throwMismatch :: ValidatorConfig -> Text -> JS.Stmt
throwMismatch config expectedType =
  if _configStrictMode config
    then JS.Throw (JS.New (ref "Error") [mismatchMsg config "FFI type error" expectedType])
    else JS.ExprStmt
           (JS.Call
             (JS.Access (ref "console") (nm "warn"))
             [mismatchMsg config "FFI type warning" expectedType])

-- | @if (!condition) { throw/warn ...; }@
guardType :: ValidatorConfig -> JS.Expr -> Text -> JS.Stmt
guardType config cond expectedType =
  JS.IfStmt
    (JS.Prefix JS.PrefixNot cond)
    (JS.Block [throwMismatch config expectedType])
    JS.EmptyStmt

-- | @if (condition) { throw/warn ...; }@
guardCond :: ValidatorConfig -> JS.Expr -> Text -> JS.Stmt
guardCond config cond expectedType =
  JS.IfStmt cond (JS.Block [throwMismatch config expectedType]) JS.EmptyStmt


-- VALIDATOR NAME GENERATION


-- | Generate a unique validator name for a type.
generateValidatorName :: FFIType -> Text
generateValidatorName ffiType = "_validate_" <> typeToSuffix ffiType
  where
    typeToSuffix :: FFIType -> Text
    typeToSuffix t = case t of
      FFIInt                -> "Int"
      FFIFloat              -> "Float"
      FFIString             -> "String"
      FFIBool               -> "Bool"
      FFIUnit               -> "Unit"
      FFIList inner         -> "List_" <> typeToSuffix inner
      FFIMaybe inner        -> "Maybe_" <> typeToSuffix inner
      FFIResult e v         -> "Result_" <> typeToSuffix e <> "_" <> typeToSuffix v
      FFITask e v           -> "Task_" <> typeToSuffix e <> "_" <> typeToSuffix v
      FFITuple types        -> "Tuple_" <> Text.intercalate "_" (map typeToSuffix types)
      FFITypeVar name       -> "Var_" <> sanitizeName name
      FFIOpaque name _      -> "Opaque_" <> sanitizeName name
      FFIFunctionType _ ret -> "Fn_" <> typeToSuffix ret
      FFIRecord fields      -> "Rec_" <> Text.intercalate "_" (map (sanitizeName . fst) fields)

    sanitizeName :: Text -> Text
    sanitizeName =
      Text.filter (\c ->
        (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))


-- VALIDATOR BODY GENERATION


-- | Generate the body statements of a validator function for a given 'FFIType'.
--
-- Each case produces a list of 'JS.Stmt' values that form the function body.
-- Helper cases delegate to 'generateOpaqueValidatorBody'.
generateValidatorBody :: ValidatorConfig -> FFIType -> [JS.Stmt]
generateValidatorBody config ffiType = case ffiType of
  FFIInt ->
    [ guardType config
        (JS.Call (JS.Access (ref "Number") (nm "isInteger")) [ref "v"])
        "Int"
    , JS.Return (ref "v")
    ]

  FFIFloat ->
    [ guardCond config
        (JS.Infix JS.OpNe (JS.Prefix JS.PrefixTypeof (ref "v")) (strE "number"))
        "Float"
    , guardType config
        (JS.Call (JS.Access (ref "Number") (nm "isFinite")) [ref "v"])
        "finite Float"
    , JS.Return (ref "v")
    ]

  FFIString ->
    [ guardCond config
        (JS.Infix JS.OpNe (JS.Prefix JS.PrefixTypeof (ref "v")) (strE "string"))
        "String"
    , JS.Return (ref "v")
    ]

  FFIBool ->
    [ guardCond config
        (JS.Infix JS.OpNe (JS.Prefix JS.PrefixTypeof (ref "v")) (strE "boolean"))
        "Bool"
    , JS.Return (ref "v")
    ]

  FFIUnit ->
    [ JS.Return (ref "v") ]

  FFIList inner ->
    [ guardType config
        (JS.Call (JS.Access (ref "Array") (nm "isArray")) [ref "v"])
        "List"
    , JS.Return
        (JS.Call
          (JS.Access (ref "v") (nm "map"))
          [ JS.Function Nothing [nm "el", nm "i"]
              [ JS.Return
                  (JS.Call (refT (generateValidatorName inner))
                    [ ref "el"
                    , JS.Infix JS.OpAdd
                        (JS.Infix JS.OpAdd
                          (JS.Infix JS.OpAdd (ref "ctx") (strE "["))
                          (ref "i"))
                        (strE "]")
                    ])
              ]
          ])
    ]

  FFIMaybe inner ->
    [ JS.IfStmt
        (JS.Infix JS.OpLooseEq (ref "v") JS.Null)
        (JS.Block [JS.Return (JS.Object [(nm "$", strE "Nothing")])])
        JS.EmptyStmt
    , JS.Return
        (JS.Object
          [ (nm "$", strE "Just")
          , (nm "a",
              JS.Call (refT (generateValidatorName inner)) [ref "v", ref "ctx"])
          ])
    ]

  FFIResult errType valType ->
    [ guardCond config invalidResultShape "Result"
    , JS.IfStmt
        (JS.Infix JS.OpEq (JS.Access (ref "v") (nm "$")) (strE "Ok"))
        (JS.Block [JS.Return (resultObject "Ok" valType ".Ok")])
        (JS.IfStmt
          (JS.Infix JS.OpEq (JS.Access (ref "v") (nm "$")) (strE "Err"))
          (JS.Block [JS.Return (resultObject "Err" errType ".Err")])
          JS.EmptyStmt)
    , throwMismatch config "Result (invalid $)"
    ]
    where
      invalidResultShape =
        JS.Infix JS.OpOr
          (JS.Infix JS.OpOr
            (JS.Infix JS.OpNe
              (JS.Prefix JS.PrefixTypeof (ref "v"))
              (strE "object"))
            (JS.Infix JS.OpEq (ref "v") JS.Null))
          (JS.Prefix JS.PrefixNot (hasProp (ref "v") "$"))
      resultObject tag fieldType ctxSuffix =
        JS.Object
          [ (nm "$", strE tag)
          , (nm "a",
              JS.Call (refT (generateValidatorName fieldType))
                [ JS.Access (ref "v") (nm "a")
                , JS.Infix JS.OpAdd (ref "ctx") (strE ctxSuffix)
                ])
          ]

  FFITask errType valType ->
    [ guardCond config invalidTaskShape "Task (expected Promise)"
    , JS.Return
        (JS.Call
          (JS.Access (ref "v") (nm "then"))
          [ JS.Function Nothing [nm "ok"]
              [ JS.Try
                  (JS.Block [JS.Return okResult])
                  (nm "e")
                  (JS.Block [JS.Return (JS.Object
                    [ (nm "$", strE "Err")
                    , (nm "a",
                        JS.Call (refT (generateValidatorName errType))
                          [ JS.Call (ref "String") [ref "e"]
                          , JS.Infix JS.OpAdd (ref "ctx") (strE ".validation")
                          ])
                    ])])
              ]
          , JS.Function Nothing [nm "err"]
              [ JS.Try
                  (JS.Block [JS.Return errResult])
                  (nm "e")
                  (JS.Block [JS.Return (JS.Object
                    [(nm "$", strE "Err"), (nm "a", JS.Call (ref "String") [ref "e"])])])
              ]
          ])
    ]
    where
      invalidTaskShape =
        JS.Infix JS.OpOr
          (JS.Infix JS.OpOr
            (JS.Infix JS.OpNe
              (JS.Prefix JS.PrefixTypeof (ref "v"))
              (strE "object"))
            (JS.Infix JS.OpLooseEq (ref "v") JS.Null))
          (JS.Infix JS.OpNe
            (JS.Prefix JS.PrefixTypeof (JS.Access (ref "v") (nm "then")))
            (strE "function"))
      okResult =
        JS.Object
          [ (nm "$", strE "Ok")
          , (nm "a",
              JS.Call (refT (generateValidatorName valType))
                [ref "ok", JS.Infix JS.OpAdd (ref "ctx") (strE ".then")])
          ]
      errResult =
        JS.Object
          [ (nm "$", strE "Err")
          , (nm "a",
              JS.Call (refT (generateValidatorName errType))
                [ref "err", JS.Infix JS.OpAdd (ref "ctx") (strE ".catch")])
          ]

  FFITuple types ->
    [ guardCond config invalidTupleShape ("Tuple" <> Text.pack (show n_))
    , JS.Return (JS.Array (zipWith elementCheck [0..] types))
    ]
    where
      n_ = length types
      invalidTupleShape =
        JS.Infix JS.OpOr
          (JS.Prefix JS.PrefixNot
            (JS.Call (JS.Access (ref "Array") (nm "isArray")) [ref "v"]))
          (JS.Infix JS.OpNe
            (JS.Access (ref "v") (nm "length"))
            (JS.Int n_))
      elementCheck idx elemType =
        JS.Call (refT (generateValidatorName elemType))
          [ JS.Index (ref "v") (JS.Int idx)
          , JS.Infix JS.OpAdd
              (JS.Infix JS.OpAdd
                (JS.Infix JS.OpAdd (ref "ctx") (strE "["))
                (JS.Int idx))
              (strE "]")
          ]

  FFITypeVar _ ->
    [ guardCond config
        (JS.Infix JS.OpEq
          (JS.Prefix JS.PrefixTypeof (ref "v"))
          (strE "undefined"))
        "non-undefined value"
    , JS.Return (ref "v")
    ]

  FFIOpaque typeName _ ->
    generateOpaqueValidatorBody config typeName Unverified

  FFIFunctionType _ _ ->
    [ guardCond config
        (JS.Infix JS.OpNe
          (JS.Prefix JS.PrefixTypeof (ref "v"))
          (strE "function"))
        "Function"
    , JS.Return (ref "v")
    ]

  FFIRecord fields ->
    [ guardCond config invalidRecordShape "Record" ]
    ++ concatMap validateField fields
    ++ [ JS.Return (ref "v") ]
    where
      invalidRecordShape =
        JS.Infix JS.OpOr
          (JS.Infix JS.OpOr
            (JS.Infix JS.OpNe
              (JS.Prefix JS.PrefixTypeof (ref "v"))
              (strE "object"))
            (JS.Infix JS.OpEq (ref "v") JS.Null))
          (JS.Call (JS.Access (ref "Array") (nm "isArray")) [ref "v"])
      validateField (fieldName, fieldType) =
        [ JS.IfStmt
            (JS.Prefix JS.PrefixNot (hasProp (ref "v") fieldName))
            (JS.Block [throwMismatch config ("Record (missing field " <> fieldName <> ")")])
            JS.EmptyStmt
        , JS.ExprStmt
            (JS.Call (refT (generateValidatorName fieldType))
              [ JS.Access (ref "v") (nameFromText fieldName)
              , JS.Infix JS.OpAdd (ref "ctx") (strE ("." <> fieldName))
              ])
        ]


-- OPAQUE VALIDATOR


-- | Generate the body statements of an opaque type validator.
--
-- * 'ClassBacked' — uses @instanceof@ to verify the JS class
-- * 'SymbolBranded' — checks for a unique symbol brand property
-- * 'Unverified' — only rejects null/undefined (legacy behavior)
--
-- @since 0.20.1
generateOpaqueValidatorBody :: ValidatorConfig -> Text -> OpaqueKind -> [JS.Stmt]
generateOpaqueValidatorBody config typeName opaqueKind =
  nullCheck : kindStmts ++ [JS.Return (ref "v")]
  where
    nullCheck =
      JS.IfStmt
        (JS.Infix JS.OpLooseEq (ref "v") JS.Null)
        (JS.Block [throwMismatch config typeName])
        JS.EmptyStmt
    kindStmts = case opaqueKind of
      ClassBacked className ->
        [ JS.IfStmt
            (JS.Prefix JS.PrefixNot
              (JS.Infix JS.OpInstanceOf (ref "v") (refT className)))
            (JS.Block
              [throwMismatch config
                (typeName <> " (expected instanceof " <> className <> ")")])
            JS.EmptyStmt
        ]
      SymbolBranded brandName ->
        [ JS.IfStmt
            (JS.Prefix JS.PrefixNot
              (JS.Index (ref "v") (strE ("__canopy_brand_" <> brandName))))
            (JS.Block
              [throwMismatch config
                (typeName <> " (missing brand " <> brandName <> ")")])
            JS.EmptyStmt
        ]
      Unverified ->
        if _configValidateOpaque config
          then [ JS.IfStmt
                   (JS.Prefix JS.PrefixNot
                     (JS.Infix JS.OpInstanceOf (ref "v") (refT typeName)))
                   (JS.Block [throwMismatch config typeName])
                   JS.EmptyStmt
               ]
          else []

-- | Generate a complete opaque validator function with a specific 'OpaqueKind'.
--
-- @since 0.20.1
generateOpaqueValidator :: ValidatorConfig -> Text -> OpaqueKind -> JS.Stmt
generateOpaqueValidator config typeName opaqueKind =
  JS.FunctionStmt
    (nameFromText ("_validate_Opaque_" <> sanitize typeName))
    [nm "v", nm "ctx"]
    (generateOpaqueValidatorBody config typeName opaqueKind)
  where
    sanitize =
      Text.filter (\c ->
        (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))


-- PUBLIC API


-- | Generate a JavaScript validator 'JS.Stmt' (function declaration) for a
-- given 'FFIType'.
generateValidator :: ValidatorConfig -> FFIType -> JS.Stmt
generateValidator config ffiType =
  JS.FunctionStmt
    (nameFromText (generateValidatorName ffiType))
    [nm "v", nm "ctx"]
    (generateValidatorBody config ffiType)

-- | Collect a type and all transitively nested types.
--
-- Used to enumerate all validators that need to be emitted for a given
-- return type.  The returned list may contain duplicates — callers that
-- want a de-duplicated set should use 'generateAllValidatorsDeduped'.
collectAllTypes :: FFIType -> [FFIType]
collectAllTypes t = t : concatMap collectAllTypes (childTypes t)
  where
    childTypes ty = case ty of
      FFIList inner        -> [inner]
      FFIMaybe inner       -> [inner]
      FFIResult e v        -> [e, v]
      FFITask e v          -> [e, v]
      FFITuple types       -> types
      FFIFunctionType as r -> as ++ [r]
      FFIRecord fields     -> map snd fields
      FFITypeVar _         -> []
      _                    -> []

-- | Generate all required validators for a type and its nested types.
--
-- Note: may contain duplicate validator functions for shared sub-types.
-- Use 'generateAllValidatorsDeduped' when emitting multiple validators.
generateAllValidators :: ValidatorConfig -> FFIType -> Builder
generateAllValidators config ffiType =
  foldMap (JS.stmtToBuilder . generateValidator config) (collectTypes ffiType)
  where
    collectTypes :: FFIType -> [FFIType]
    collectTypes t = t : concatMap collectTypes (childTypes t)

    childTypes :: FFIType -> [FFIType]
    childTypes ty = case ty of
      FFIList inner        -> [inner]
      FFIMaybe inner       -> [inner]
      FFIResult e v        -> [e, v]
      FFITask e v          -> [e, v]
      FFITuple types       -> types
      FFIFunctionType as r -> as ++ [r]
      FFIRecord fields     -> map snd fields
      FFITypeVar _         -> []
      _                    -> []

-- | Generate deduplicated validators for a collection of return types.
--
-- Expands each type into its full set of nested types, merges them all,
-- removes duplicates, and emits each validator exactly once.  This is
-- the preferred entry point when validators for multiple functions are
-- generated together, because it avoids repeating @_validate_String@
-- and similar base validators once per function.
generateAllValidatorsDeduped :: ValidatorConfig -> [FFIType] -> Builder
generateAllValidatorsDeduped config returnTypes =
  foldMap (JS.stmtToBuilder . generateValidator config) uniqueTypes
  where
    uniqueTypes =
      List.nubBy
        (\a b -> generateValidatorName a == generateValidatorName b)
        (concatMap collectAllTypes returnTypes)


-- TYPE PARSING


-- | Parse a type string into 'FFIType'.
--
-- Delegates to the unified parser in "FFI.TypeParser".
parseFFIType :: Text -> Maybe FFIType
parseFFIType = TypeParser.parseType

-- | Parse and extract just the return type from a function type string.
--
-- Delegates to the unified parser in "FFI.TypeParser".
parseReturnType :: Text -> Maybe FFIType
parseReturnType = TypeParser.parseReturnType
