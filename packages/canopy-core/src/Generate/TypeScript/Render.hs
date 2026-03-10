{-# LANGUAGE OverloadedStrings #-}

-- | Render TypeScript types and declarations to @.d.ts@ text.
--
-- Converts 'TsType' and 'DtsDecl' values into 'Builder' output suitable
-- for writing to @.d.ts@ files. Follows TypeScript declaration file
-- conventions with @readonly@ fields and discriminated unions.
--
-- @since 0.20.0
module Generate.TypeScript.Render
  ( renderDecl,
    renderType,
    renderDecls,
  )
where

import qualified Canopy.Data.Name as Name
import Canopy.Data.Name (Name)
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.List as List
import Generate.TypeScript.Types (DtsDecl (..), TsType (..))

-- | Render a list of declarations to a complete @.d.ts@ file.
--
-- @since 0.20.0
renderDecls :: [DtsDecl] -> Builder
renderDecls decls =
  mconcat (List.intersperse newline (map renderDecl decls)) <> newline


-- | Render a single declaration.
renderDecl :: DtsDecl -> Builder
renderDecl (DtsValue name tpe) =
  "export const " <> nameB name <> ": " <> renderType tpe <> ";\n"
renderDecl (DtsTypeAlias name vars tpe) =
  "export type " <> nameB name <> renderTypeParams vars <> " = " <> renderType tpe <> ";\n"
renderDecl (DtsUnionType name vars tpe) =
  "export type " <> nameB name <> renderTypeParams vars <> " = " <> renderType tpe <> ";\n"
renderDecl (DtsBrandedType name vars) =
  "export type " <> nameB name <> renderTypeParams vars
    <> " = { readonly __brand: unique symbol };\n"


-- | Render a TypeScript type expression.
renderType :: TsType -> Builder
renderType TsString = "string"
renderType TsNumber = "number"
renderType TsBoolean = "boolean"
renderType TsVoid = "void"
renderType TsUnknown = "unknown"
renderType (TsTypeVar name) = nameB name
renderType (TsReadonlyArray inner) =
  "ReadonlyArray<" <> renderType inner <> ">"
renderType (TsFunction params ret) =
  renderFunctionType params ret
renderType (TsObject fields) =
  renderObjectType fields
renderType (TsObjectWithIndex fields) =
  renderObjectWithIndex fields
renderType (TsUnion variants) =
  renderUnionType variants
renderType (TsTaggedVariant tag fields) =
  renderTaggedVariant tag fields
renderType (TsBranded name vars) =
  nameB name <> renderTypeArgs (map TsTypeVar vars)
renderType (TsNamed name args) =
  nameB name <> renderTypeArgs args


-- INTERNAL HELPERS


renderFunctionType :: [TsType] -> TsType -> Builder
renderFunctionType params ret =
  "(" <> renderParams params <> ") => " <> renderType ret


renderParams :: [TsType] -> Builder
renderParams params =
  mconcat (List.intersperse ", " (zipWith renderParam [0 :: Int ..] params))


renderParam :: Int -> TsType -> Builder
renderParam idx tpe =
  "p" <> BB.intDec idx <> ": " <> renderType tpe


renderObjectType :: [(Name, TsType)] -> Builder
renderObjectType [] = "{}"
renderObjectType fields =
  "{ " <> mconcat (List.intersperse "; " (map renderField fields)) <> " }"


renderObjectWithIndex :: [(Name, TsType)] -> Builder
renderObjectWithIndex [] = "{ [key: string]: unknown }"
renderObjectWithIndex fields =
  "{ " <> mconcat (List.intersperse "; " (map renderField fields)) <> "; [key: string]: unknown }"


renderField :: (Name, TsType) -> Builder
renderField (name, tpe) =
  "readonly " <> nameB name <> ": " <> renderType tpe


renderUnionType :: [TsType] -> Builder
renderUnionType [] = "never"
renderUnionType variants =
  mconcat (List.intersperse " | " (map renderType variants))


renderTaggedVariant :: Name -> [(Name, TsType)] -> Builder
renderTaggedVariant tag fields =
  "{ " <> tagField <> fieldsPart <> " }"
  where
    tagField = "readonly $: '" <> nameB tag <> "'"
    fieldsPart
      | null fields = ""
      | otherwise = "; " <> mconcat (List.intersperse "; " (map renderField fields))


renderTypeParams :: [Name] -> Builder
renderTypeParams [] = ""
renderTypeParams vars =
  "<" <> mconcat (List.intersperse ", " (map (nameB . toUpperName) vars)) <> ">"


renderTypeArgs :: [TsType] -> Builder
renderTypeArgs [] = ""
renderTypeArgs args =
  "<" <> mconcat (List.intersperse ", " (map renderType args)) <> ">"


nameB :: Name -> Builder
nameB = BB.stringUtf8 . Name.toChars


toUpperName :: Name -> Name
toUpperName name =
  Name.fromChars (map toUpper (Name.toChars name))
  where
    toUpper c
      | c >= 'a' && c <= 'z' = toEnum (fromEnum c - 32)
      | otherwise = c


newline :: Builder
newline = "\n"
