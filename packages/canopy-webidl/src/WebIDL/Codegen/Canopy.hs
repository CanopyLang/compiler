{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

-- | Canopy Source Code Generator
--
-- Generates type-safe Canopy (.can) source files from transformed
-- WebIDL definitions. Produces idiomatic Canopy code following
-- project conventions.
--
-- @since 0.20.0
module WebIDL.Codegen.Canopy
  ( -- * Module rendering
    renderModule
  , renderFunction
  , renderRecord
  , renderUnion

    -- * Type rendering
  , renderType
  , renderTypeAnnotation
  ) where

import Data.Text (Text)
import qualified Data.Text as Text

import WebIDL.Config
import WebIDL.Transform


-- | Render a complete Canopy module
renderModule :: Config -> CanopyModule -> Text
renderModule config canopyMod = Text.unlines
  [ renderModuleHeader canopyMod
  , ""
  , renderImports (cmImports canopyMod)
  , ""
  , renderExports canopyMod
  , ""
  , renderRecords (cmRecords canopyMod)
  , renderUnions (cmUnions canopyMod)
  , renderFunctions config canopyMod
  ]


-- | Render module header
renderModuleHeader :: CanopyModule -> Text
renderModuleHeader canopyMod = Text.unlines
  [ "module " <> cmName canopyMod <> " exposing"
  , "    ( " <> renderExportList (cmExports canopyMod)
  , "    )"
  ]


-- | Render export list
renderExportList :: [Text] -> Text
renderExportList exports =
  Text.intercalate "\n    , " exports


-- | Render imports section
renderImports :: [Text] -> Text
renderImports [] = ""
renderImports imports = Text.unlines
  [ "{- External imports -}"
  , Text.unlines (map renderImport imports)
  ]
  where
    renderImport name = "import " <> name


-- | Render exports
renderExports :: CanopyModule -> Text
renderExports _ = ""


-- | Render all record definitions
renderRecords :: [CanopyRecord] -> Text
renderRecords [] = ""
renderRecords records = Text.unlines (map renderRecord records)


-- | Render a single record definition
renderRecord :: CanopyRecord -> Text
renderRecord record = Text.unlines
  [ renderDoc (crDoc record)
  , "type alias " <> crName record <> " ="
  , "    { " <> renderFields (crFields record)
  , "    }"
  , ""
  ]


-- | Render record fields
renderFields :: [CanopyField] -> Text
renderFields [] = ""
renderFields fields =
  Text.intercalate "\n    , " (map renderField fields)


-- | Render a single field
renderField :: CanopyField -> Text
renderField field =
  cfldName field <> " : " <> renderType (cfldType field)


-- | Render all union definitions
renderUnions :: [CanopyUnion] -> Text
renderUnions [] = ""
renderUnions unions = Text.unlines (map renderUnion unions)


-- | Render a single union definition
renderUnion :: CanopyUnion -> Text
renderUnion union = Text.unlines
  [ renderDoc (cuDoc union)
  , "type " <> cuName union
  , "    = " <> renderVariants (cuVariants union)
  , ""
  ]


-- | Render union variants
renderVariants :: [CanopyVariant] -> Text
renderVariants [] = ""
renderVariants variants =
  Text.intercalate "\n    | " (map renderVariant variants)


-- | Render a single variant
renderVariant :: CanopyVariant -> Text
renderVariant variant =
  case cvPayload variant of
    Nothing -> cvName variant
    Just ty -> cvName variant <> " " <> renderType ty


-- | Render all function definitions
renderFunctions :: Config -> CanopyModule -> Text
renderFunctions config canopyMod =
  Text.unlines (map (renderFunction config) (cmFunctions canopyMod))


-- | Render a single function definition
renderFunction :: Config -> CanopyFunction -> Text
renderFunction config func = Text.unlines
  [ renderDoc (cfDoc func)
  , renderTypeAnnotation func
  , renderFunctionBody config func
  , ""
  ]


-- | Render function type annotation
renderTypeAnnotation :: CanopyFunction -> Text
renderTypeAnnotation func =
  cfName func <> " : " <> renderFunctionType (cfParams func) (cfReturn func)


-- | Render function type signature
renderFunctionType :: [(Text, CanopyType)] -> CanopyType -> Text
renderFunctionType params returnTy =
  Text.intercalate " -> " (paramTypes ++ [renderType returnTy])
  where
    paramTypes = map (renderType . snd) params


-- | Render function body with FFI call
renderFunctionBody :: Config -> CanopyFunction -> Text
renderFunctionBody _config func =
  cfName func <> " " <> paramNames <> " ="
    <> "\n    " <> renderFFICall func
  where
    paramNames = Text.unwords (map fst (cfParams func))


-- | Render FFI call
renderFFICall :: CanopyFunction -> Text
renderFFICall func =
  case cfJsTarget func of
    Nothing ->
      "Native." <> cfJsName func <> renderArgs (cfParams func)
    Just target ->
      if cfIsStatic func
        then "Native." <> target <> "_" <> cfJsName func <> renderArgs (cfParams func)
        else "Native." <> target <> "_" <> cfJsName func <> renderArgs (cfParams func)


-- | Render function arguments
renderArgs :: [(Text, CanopyType)] -> Text
renderArgs [] = ""
renderArgs params = " " <> Text.unwords (map fst params)


-- | Render a Canopy type
renderType :: CanopyType -> Text
renderType = \case
  CTInt -> "Int"
  CTFloat -> "Float"
  CTBool -> "Bool"
  CTString -> "String"
  CTChar -> "Char"
  CTUnit -> "()"
  CTValue -> "Value"
  CTMaybe inner -> "Maybe " <> renderTypeParens inner
  CTList inner -> "List " <> renderTypeParens inner
  CTTask err ok -> "Task " <> renderTypeParens err <> " " <> renderTypeParens ok
  CTDict key val -> "Dict " <> renderTypeParens key <> " " <> renderTypeParens val
  CTTuple types -> "( " <> Text.intercalate ", " (map renderType types) <> " )"
  CTRecord name -> name
  CTUnion name -> name
  CTCustom name -> name
  CTFunction params ret ->
    "(" <> Text.intercalate " -> " (map renderType params ++ [renderType ret]) <> ")"


-- | Render type with parentheses if needed
renderTypeParens :: CanopyType -> Text
renderTypeParens ty =
  case ty of
    CTMaybe _ -> parens (renderType ty)
    CTList _ -> parens (renderType ty)
    CTTask _ _ -> parens (renderType ty)
    CTDict _ _ -> parens (renderType ty)
    CTFunction _ _ -> parens (renderType ty)
    _ -> renderType ty
  where
    parens t = "(" <> t <> ")"


-- | Render documentation comment
renderDoc :: Maybe Text -> Text
renderDoc Nothing = ""
renderDoc (Just doc) = "{-| " <> doc <> " -}"
