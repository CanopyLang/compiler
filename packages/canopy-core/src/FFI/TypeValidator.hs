{-# LANGUAGE OverloadedStrings #-}

-- | FFI type validator for TypeScript declaration files.
--
-- Validates that FFI type annotations in Canopy code are compatible
-- with the TypeScript types declared in companion @.d.ts@ files.
-- This catches type mismatches at compile time rather than runtime.
--
-- == Type Mapping
--
-- @
-- TypeScript         ↔ FFI Type
-- string             ↔ FFIString
-- number             ↔ FFIInt | FFIFloat
-- boolean            ↔ FFIBool
-- void / undefined   ↔ FFIUnit
-- ReadonlyArray\<T\> ↔ FFIList T
-- T | null           ↔ FFIMaybe T
-- Promise\<T\>       ↔ FFITask _ T
-- { field: T; ... }  ↔ FFIRecord [(field, T)]
-- (p: A) => B        ↔ FFIFunctionType [A] B
-- @
--
-- @since 0.20.0
module FFI.TypeValidator
  ( -- * Validation
    validateFFIAgainstTs,
    TypeMismatch (..),
  )
where

import qualified Canopy.Data.Name as Name
import Data.Text (Text)
import qualified Data.Text as Text
import FFI.Types (FFIType (..))
import Generate.TypeScript.Types (TsType (..))

-- | A type mismatch between a TypeScript declaration and an FFI annotation.
--
-- @since 0.20.0
data TypeMismatch = TypeMismatch
  { _tmPath :: !Text,
    _tmExpected :: !Text,
    _tmActual :: !Text
  }
  deriving (Eq, Show)

-- | Validate an FFI type against a TypeScript type.
--
-- Returns an empty list if the types are compatible, or a list of
-- mismatches describing where they diverge.
--
-- @since 0.20.0
validateFFIAgainstTs :: TsType -> FFIType -> [TypeMismatch]
validateFFIAgainstTs tsType ffiType =
  validateAt "root" tsType ffiType

-- | Validate at a specific path for error reporting.
validateAt :: Text -> TsType -> FFIType -> [TypeMismatch]
validateAt path ts ffi =
  case (ts, ffi) of
    (TsString, FFIString) -> []
    (TsNumber, FFIInt) -> []
    (TsNumber, FFIFloat) -> []
    (TsBoolean, FFIBool) -> []
    (TsVoid, FFIUnit) -> []
    (TsUnknown, _) -> []
    (TsReadonlyArray elemTs, FFIList elemFfi) ->
      validateAt (path <> ".element") elemTs elemFfi
    (TsFunction paramTs retTs, FFIFunctionType paramFfi retFfi) ->
      validateParams path paramTs paramFfi ++ validateAt (path <> ".return") retTs retFfi
    (TsObject fieldsTs, FFIRecord fieldsFfi) ->
      validateFields path fieldsTs fieldsFfi
    (TsTypeVar _, FFITypeVar _) -> []
    (TsTypeVar _, _) -> []
    (_, FFITypeVar _) -> []
    (TsNamed name [innerTs], FFITask _ innerFfi)
      | Name.toChars name == "Promise" ->
          validateAt (path <> ".promise") innerTs innerFfi
    (TsUnion members, FFIMaybe innerFfi) ->
      validateMaybe path members innerFfi
    (_, FFIOpaque _ _) -> []
    _ ->
      [TypeMismatch path (describeTsType ts) (describeFFIType ffi)]

-- | Validate function parameters pairwise.
validateParams :: Text -> [TsType] -> [FFIType] -> [TypeMismatch]
validateParams path tsParams ffiParams
  | length tsParams /= length ffiParams =
      [TypeMismatch path (describeCount "TS" tsParams) (describeCount "FFI" ffiParams)]
  | otherwise =
      concatMap validateParam (zip3 [0 :: Int ..] tsParams ffiParams)
  where
    validateParam (i, ts, ffi) =
      validateAt (path <> ".param" <> Text.pack (show i)) ts ffi
    describeCount label ps =
      label <> " has " <> Text.pack (show (length ps)) <> " params"

-- | Validate record fields.
validateFields :: Text -> [(Name.Name, TsType)] -> [(Text, FFIType)] -> [TypeMismatch]
validateFields path tsFields ffiFields =
  concatMap checkField ffiFields
  where
    tsFieldMap = [(Name.toChars n, t) | (n, t) <- tsFields]
    checkField (ffiName, ffiType) =
      case lookup (Text.unpack ffiName) tsFieldMap of
        Just tsType -> validateAt (path <> "." <> ffiName) tsType ffiType
        Nothing -> [TypeMismatch (path <> "." <> ffiName) "field exists in .d.ts" "field missing"]

-- | Validate Maybe type against a union containing null.
validateMaybe :: Text -> [TsType] -> FFIType -> [TypeMismatch]
validateMaybe path members innerFfi =
  case filter (not . isNullType) members of
    [nonNull] -> validateAt (path <> ".maybe") nonNull innerFfi
    _ -> []
  where
    isNullType TsVoid = True
    isNullType (TsNamed n []) | Name.toChars n == "null" = True
    isNullType _ = False

-- | Describe a TsType for error messages.
describeTsType :: TsType -> Text
describeTsType TsString = "string"
describeTsType TsNumber = "number"
describeTsType TsBoolean = "boolean"
describeTsType TsVoid = "void"
describeTsType TsUnknown = "unknown"
describeTsType (TsReadonlyArray _) = "ReadonlyArray<...>"
describeTsType (TsFunction _ _) = "(...) => ..."
describeTsType (TsObject _) = "{ ... }"
describeTsType (TsUnion _) = "... | ..."
describeTsType (TsTypeVar n) = Text.pack (Name.toChars n)
describeTsType (TsNamed n _) = Text.pack (Name.toChars n)
describeTsType (TsTaggedVariant n _) = Text.pack (Name.toChars n)
describeTsType (TsBranded n _) = Text.pack (Name.toChars n)
describeTsType (TsObjectWithIndex _) = "{ [key]: ... }"

-- | Describe an FFIType for error messages.
describeFFIType :: FFIType -> Text
describeFFIType FFIInt = "Int"
describeFFIType FFIFloat = "Float"
describeFFIType FFIString = "String"
describeFFIType FFIBool = "Bool"
describeFFIType FFIUnit = "()"
describeFFIType (FFIList _) = "List ..."
describeFFIType (FFIMaybe _) = "Maybe ..."
describeFFIType (FFIResult _ _) = "Result ..."
describeFFIType (FFITask _ _) = "Task ..."
describeFFIType (FFITuple _) = "( ... )"
describeFFIType (FFITypeVar v) = v
describeFFIType (FFIOpaque name _) = name
describeFFIType (FFIFunctionType _ _) = "... -> ..."
describeFFIType (FFIRecord _) = "{ ... }"
