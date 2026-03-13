{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Schema-driven form code generation from record type aliases.
--
-- Given a Canopy type alias like:
--
-- @
-- type alias LoginData =
--     { email : String
--     , password : String
--     , rememberMe : Bool
--     }
-- @
--
-- Generates a corresponding form definition:
--
-- @
-- loginDataForm : Form LoginData
-- loginDataForm =
--     Form.succeed LoginData
--         |> Form.append (Field.emailField { id = "email", label = "Email", ... })
--         |> Form.append (Field.passwordField { id = "password", label = "Password", ... })
--         |> Form.append (Field.checkboxField { id = "rememberMe", label = "Remember Me", ... })
-- @
--
-- == Field Type Mapping
--
-- The generator maps Canopy types to form field constructors:
--
-- * @String@ → @Field.textField@
-- * @Int@ → @Field.numberField@
-- * @Float@ → @Field.numberField@
-- * @Bool@ → @Field.checkboxField@
-- * @Maybe a@ → @Form.optional (fieldFor a)@
-- * Fields named @email@ → @Field.emailField@
-- * Fields named @password@ → @Field.passwordField@
-- * Fields named @url@ → @Field.urlField@
--
-- @since 0.20.1
module Generate.Form
  ( -- * Code Generation
    generateFormModule,
    generateFormDefinition,

    -- * Field Mapping
    FieldMapping (..),
    mapFieldType,
    fieldNameToLabel,
  )
where

import qualified AST.Canonical as Can
import Canopy.Data.Name (Name)
import qualified Canopy.Data.Name as Name
import qualified Data.ByteString.Builder as BB
import Data.ByteString.Builder (Builder)
import qualified Data.Char as Char
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE

-- | Mapping from a record field to a form field constructor.
--
-- @since 0.20.1
data FieldMapping = FieldMapping
  { _fmFieldId :: !Text,
    _fmLabel :: !Text,
    _fmConstructor :: !Text,
    _fmIsOptional :: !Bool
  }
  deriving (Eq, Show)

-- | Generate a complete Canopy module containing form definitions
-- for all type aliases in the given list.
--
-- @since 0.20.1
generateFormModule :: Text -> [(Name, Can.Alias)] -> Builder
generateFormModule moduleName aliases =
  moduleHeader moduleName
    <> BB.char7 '\n'
    <> imports
    <> BB.char7 '\n'
    <> mconcat (fmap generateFromAlias aliases)

-- | Generate a form definition for a single type alias.
--
-- Returns 'Nothing' if the alias is not a record type.
--
-- @since 0.20.1
generateFormDefinition :: Name -> Can.Alias -> Maybe Builder
generateFormDefinition name (Can.Alias _vars _variance tipe _ _) =
  generateFromType name tipe

-- INTERNAL

moduleHeader :: Text -> Builder
moduleHeader moduleName =
  BB.stringUtf8 "module "
    <> TE.encodeUtf8Builder moduleName
    <> BB.stringUtf8 " exposing (..)\n\n"

imports :: Builder
imports =
  BB.stringUtf8 "import Form exposing (Form)\n"
    <> BB.stringUtf8 "import Form.Field as Field\n"
    <> BB.stringUtf8 "import Form.Validate as Validate\n\n"

generateFromAlias :: (Name, Can.Alias) -> Builder
generateFromAlias (name, Can.Alias _vars _variance tipe _ _) =
  maybe mempty id (generateFromType name tipe)

generateFromType :: Name -> Can.Type -> Maybe Builder
generateFromType name (Can.TRecord fields _) =
  Just (generateRecordForm name fields)
generateFromType _ _ =
  Nothing

generateRecordForm :: Name -> Map.Map Name Can.FieldType -> Builder
generateRecordForm typeName fields =
  formAnnotation typeName
    <> formDefinition typeName
    <> succeedLine typeName
    <> fieldAppends sortedFields
    <> BB.char7 '\n'
  where
    sortedFields = Can.fieldsToList fields

formAnnotation :: Name -> Builder
formAnnotation typeName =
  formNameBuilder typeName
    <> BB.stringUtf8 " : Form "
    <> nameBuilder typeName
    <> BB.char7 '\n'

formDefinition :: Name -> Builder
formDefinition typeName =
  formNameBuilder typeName
    <> BB.stringUtf8 " =\n"

succeedLine :: Name -> Builder
succeedLine typeName =
  BB.stringUtf8 "    Form.succeed "
    <> nameBuilder typeName
    <> BB.char7 '\n'

fieldAppends :: [(Name, Can.Type)] -> Builder
fieldAppends =
  mconcat . fmap fieldAppend

fieldAppend :: (Name, Can.Type) -> Builder
fieldAppend (fieldName, fieldType) =
  BB.stringUtf8 "        |> Form.append ("
    <> fieldExpr mapping
    <> BB.stringUtf8 ")\n"
  where
    mapping = mapFieldType fieldName fieldType

fieldExpr :: FieldMapping -> Builder
fieldExpr mapping
  | _fmIsOptional mapping =
      BB.stringUtf8 "Form.optional ("
        <> innerFieldExpr mapping
        <> BB.char7 ')'
  | otherwise =
      innerFieldExpr mapping

innerFieldExpr :: FieldMapping -> Builder
innerFieldExpr mapping =
  TE.encodeUtf8Builder (_fmConstructor mapping)
    <> BB.stringUtf8 " { id = Form.FieldId \""
    <> TE.encodeUtf8Builder (_fmFieldId mapping)
    <> BB.stringUtf8 "\", label = \""
    <> TE.encodeUtf8Builder (_fmLabel mapping)
    <> BB.stringUtf8 "\", placeholder = \"\", validators = [] }"

-- | Map a record field name and type to a form field constructor.
--
-- Uses both the field name and type to determine the best field
-- constructor. Name-based heuristics take priority (e.g., a field
-- named @email@ always maps to @Field.emailField@).
--
-- @since 0.20.1
mapFieldType :: Name -> Can.Type -> FieldMapping
mapFieldType fieldName fieldType =
  FieldMapping
    { _fmFieldId = nameText,
      _fmLabel = fieldNameToLabel fieldName,
      _fmConstructor = constructor,
      _fmIsOptional = isOptional
    }
  where
    nameText = Text.pack (Name.toChars fieldName)
    (constructor, isOptional) = resolveConstructor nameText fieldType

resolveConstructor :: Text -> Can.Type -> (Text, Bool)
resolveConstructor nameText fieldType =
  case unwrapMaybe fieldType of
    Just innerType ->
      (fst (resolveConstructor nameText innerType), True)
    Nothing ->
      (resolveByNameOrType nameText fieldType, False)

resolveByNameOrType :: Text -> Can.Type -> Text
resolveByNameOrType nameText fieldType
  | isEmailName nameText = "Field.emailField"
  | isPasswordName nameText = "Field.passwordField"
  | isUrlName nameText = "Field.urlField"
  | otherwise = resolveByType fieldType

resolveByType :: Can.Type -> Text
resolveByType (Can.TType _ name _)
  | nameIs "String" name = "Field.textField"
  | nameIs "Int" name = "Field.numberField"
  | nameIs "Float" name = "Field.numberField"
  | nameIs "Bool" name = "Field.checkboxField"
  | otherwise = "Field.textField"
resolveByType _ = "Field.textField"

nameIs :: String -> Name -> Bool
nameIs s n = Name.toChars n == s

unwrapMaybe :: Can.Type -> Maybe Can.Type
unwrapMaybe (Can.TType _ name [inner])
  | nameIs "Maybe" name = Just inner
unwrapMaybe _ = Nothing

isEmailName :: Text -> Bool
isEmailName n = n == "email" || Text.isSuffixOf "Email" n

isPasswordName :: Text -> Bool
isPasswordName n = n == "password" || Text.isSuffixOf "Password" n

isUrlName :: Text -> Bool
isUrlName n = n == "url" || Text.isSuffixOf "Url" n

-- | Convert a camelCase field name to a human-readable label.
--
-- @
-- fieldNameToLabel \"firstName\" == \"First Name\"
-- fieldNameToLabel \"email\" == \"Email\"
-- fieldNameToLabel \"rememberMe\" == \"Remember Me\"
-- @
--
-- @since 0.20.1
fieldNameToLabel :: Name -> Text
fieldNameToLabel name =
  Text.pack (capitalize (insertSpaces (Name.toChars name)))

capitalize :: String -> String
capitalize [] = []
capitalize (c : cs) = Char.toUpper c : cs

insertSpaces :: String -> String
insertSpaces =
  List.concatMap insertSpace

insertSpace :: Char -> String
insertSpace c
  | Char.isUpper c = [' ', Char.toLower c]
  | otherwise = [c]

formNameBuilder :: Name -> Builder
formNameBuilder typeName =
  BB.stringUtf8 (lowerFirst (Name.toChars typeName))
    <> BB.stringUtf8 "Form"

nameBuilder :: Name -> Builder
nameBuilder =
  BB.stringUtf8 . Name.toChars

lowerFirst :: String -> String
lowerFirst [] = []
lowerFirst (c : cs) = Char.toLower c : cs
