{-# LANGUAGE OverloadedStrings #-}

-- | Documentation rendering for the @canopy docs@ command.
--
-- Provides multiple output formats for generated documentation:
--
--   * JSON -- machine-readable structured output for editor tooling
--   * Markdown -- human-readable documentation suitable for viewing or
--     converting to HTML
--
-- The rendering layer operates on 'Canopy.Docs.Documentation', which is a
-- map from module name to 'Canopy.Docs.Module'. Each module contains its
-- exported values, type aliases, custom types, and binary operators together
-- with their type signatures and doc-comments.
--
-- @since 0.19.2
module Docs.Render
  ( -- * Output Format
    OutputFormat (..),

    -- * Rendering
    renderJson,
    renderMarkdown,
    renderModuleMarkdown,

    -- * Type Display
    typeToText,
  )
where

import qualified Canopy.Compiler.Type as Type
import qualified Canopy.Data.Name as Name
import qualified Canopy.Docs as Docs
import qualified Data.ByteString.Builder as BB
import qualified Data.Map.Strict as Map
import qualified Json.Encode as Encode
import qualified Json.String as Json
import qualified Reporting.Doc as Doc
import qualified Reporting.Render.Type as RT
import qualified Reporting.Render.Type.Localizer as Localizer

-- | Supported documentation output formats.
data OutputFormat
  = -- | Structured JSON output for editor integration and tooling
    JsonFormat
  | -- | Human-readable Markdown output
    MarkdownFormat
  deriving (Eq, Show)

-- JSON RENDERING

-- | Render full documentation as a JSON 'BB.Builder'.
--
-- The JSON structure is an array of module objects, each containing:
--
-- @
-- { "name": "ModuleName",
--   "comment": "Module doc comment",
--   "values": [...],
--   "aliases": [...],
--   "unions": [...],
--   "binops": [...]
-- }
-- @
--
-- This delegates to the existing 'Docs.encode' for the core structure,
-- which is the same format used by @canopy make --docs@.
--
-- @since 0.19.2
renderJson :: Docs.Documentation -> BB.Builder
renderJson docs =
  Encode.encode (Docs.encode docs)

-- MARKDOWN RENDERING

-- | Render full documentation as a Markdown string.
--
-- Produces a concatenation of per-module Markdown sections separated by
-- horizontal rules. Each module section includes its doc comment, values,
-- type aliases, custom types, and binary operators.
--
-- @since 0.19.2
renderMarkdown :: Docs.Documentation -> String
renderMarkdown docs =
  unlines (concatMap renderOneModule (Map.elems docs))

-- | Render a single module as Markdown lines.
--
-- Produces a level-1 heading with the module name, followed by the module
-- comment (if non-empty), and sections for values, aliases, unions, and
-- binary operators.
--
-- @since 0.19.2
renderModuleMarkdown :: Docs.Module -> String
renderModuleMarkdown modul =
  unlines (renderOneModule modul)

-- | Internal: render a single module to a list of Markdown lines.
renderOneModule :: Docs.Module -> [String]
renderOneModule (Docs.Module name comment unions aliases values binops abilities) =
  concat
    [ [moduleHeading name],
      renderComment comment,
      renderValuesSection values,
      renderAliasesSection aliases,
      renderUnionsSection unions,
      renderBinopsSection binops,
      renderAbilitiesSection abilities,
      ["", "---", ""]
    ]

-- | Render a module-level heading.
moduleHeading :: Name.Name -> String
moduleHeading name =
  "# " ++ Name.toChars name

-- | Render a doc comment as Markdown lines, or empty if blank.
renderComment :: Docs.Comment -> [String]
renderComment comment =
  let text = Json.toChars comment
   in if null text
        then []
        else ["", text]

-- VALUES

-- | Render the values section, or empty if there are no values.
renderValuesSection :: Map.Map Name.Name Docs.Value -> [String]
renderValuesSection values
  | Map.null values = []
  | otherwise =
      ["", "## Values", ""]
        ++ concatMap renderValueEntry (Map.toAscList values)

-- | Render a single value entry with name, type signature, and comment.
renderValueEntry :: (Name.Name, Docs.Value) -> [String]
renderValueEntry (name, Docs.Value comment tipe) =
  concat
    [ ["### " ++ Name.toChars name, ""],
      ["```", Name.toChars name ++ " : " ++ typeToText tipe, "```"],
      renderComment comment,
      [""]
    ]

-- ALIASES

-- | Render the type aliases section, or empty if there are no aliases.
renderAliasesSection :: Map.Map Name.Name Docs.Alias -> [String]
renderAliasesSection aliases
  | Map.null aliases = []
  | otherwise =
      ["", "## Type Aliases", ""]
        ++ concatMap renderAliasEntry (Map.toAscList aliases)

-- | Render a single type alias entry.
renderAliasEntry :: (Name.Name, Docs.Alias) -> [String]
renderAliasEntry (name, Docs.Alias comment tvars tipe) =
  concat
    [ ["### " ++ Name.toChars name, ""],
      ["```", "type alias " ++ Name.toChars name ++ renderTVars tvars ++ " = " ++ typeToText tipe, "```"],
      renderComment comment,
      [""]
    ]

-- UNIONS

-- | Render the custom types (unions) section.
renderUnionsSection :: Map.Map Name.Name Docs.Union -> [String]
renderUnionsSection unions
  | Map.null unions = []
  | otherwise =
      ["", "## Types", ""]
        ++ concatMap renderUnionEntry (Map.toAscList unions)

-- | Render a single custom type entry.
renderUnionEntry :: (Name.Name, Docs.Union) -> [String]
renderUnionEntry (name, Docs.Union comment tvars ctors) =
  concat
    [ ["### " ++ Name.toChars name, ""],
      renderUnionDefinition name tvars ctors,
      renderComment comment,
      [""]
    ]

-- | Render a union type definition in Canopy syntax.
renderUnionDefinition :: Name.Name -> [Name.Name] -> [(Name.Name, [Type.Type])] -> [String]
renderUnionDefinition name tvars ctors =
  ["```"]
    ++ renderUnionHeader name tvars ctors
    ++ ["```"]

-- | Render the header line(s) of a union type.
renderUnionHeader :: Name.Name -> [Name.Name] -> [(Name.Name, [Type.Type])] -> [String]
renderUnionHeader name tvars [] =
  ["type " ++ Name.toChars name ++ renderTVars tvars]
renderUnionHeader name tvars (first : rest) =
  ("type " ++ Name.toChars name ++ renderTVars tvars)
    : renderFirstCtor first
    : map renderRestCtor rest

-- | Render the first constructor with @=@.
renderFirstCtor :: (Name.Name, [Type.Type]) -> String
renderFirstCtor (ctorName, args) =
  "    = " ++ Name.toChars ctorName ++ renderCtorArgs args

-- | Render subsequent constructors with @|@.
renderRestCtor :: (Name.Name, [Type.Type]) -> String
renderRestCtor (ctorName, args) =
  "    | " ++ Name.toChars ctorName ++ renderCtorArgs args

-- | Render constructor arguments as a space-separated list.
renderCtorArgs :: [Type.Type] -> String
renderCtorArgs [] = ""
renderCtorArgs args = " " ++ unwords (map typeToText args)

-- BINOPS

-- | Render the binary operators section.
renderBinopsSection :: Map.Map Name.Name Docs.Binop -> [String]
renderBinopsSection binops
  | Map.null binops = []
  | otherwise =
      ["", "## Operators", ""]
        ++ concatMap renderBinopEntry (Map.toAscList binops)

-- | Render a single binary operator entry.
renderBinopEntry :: (Name.Name, Docs.Binop) -> [String]
renderBinopEntry (name, Docs.Binop comment tipe _assoc _prec) =
  concat
    [ ["### (" ++ Name.toChars name ++ ")", ""],
      ["```", "(" ++ Name.toChars name ++ ") : " ++ typeToText tipe, "```"],
      renderComment comment,
      [""]
    ]

-- ABILITIES

-- | Render the abilities section, or empty if there are no abilities.
renderAbilitiesSection :: Map.Map Name.Name Docs.Ability -> [String]
renderAbilitiesSection abilities
  | Map.null abilities = []
  | otherwise =
      ["", "## Abilities", ""]
        ++ concatMap renderAbilityEntry (Map.toAscList abilities)

-- | Render a single ability entry with its methods.
renderAbilityEntry :: (Name.Name, Docs.Ability) -> [String]
renderAbilityEntry (name, Docs.Ability comment tvars methods) =
  concat
    [ ["### " ++ Name.toChars name, ""],
      renderAbilityDefinition name tvars methods,
      renderComment comment,
      [""]
    ]

-- | Render an ability definition in Canopy syntax.
renderAbilityDefinition :: Name.Name -> [Name.Name] -> [(Name.Name, Type.Type)] -> [String]
renderAbilityDefinition name tvars methods =
  ["```"]
    ++ ["ability " ++ Name.toChars name ++ renderTVars tvars]
    ++ map renderMethodSig methods
    ++ ["```"]

-- | Render a single method signature.
renderMethodSig :: (Name.Name, Type.Type) -> String
renderMethodSig (methodName, tipe) =
  "    " ++ Name.toChars methodName ++ " : " ++ typeToText tipe

-- HELPERS

-- | Render type variables as a space-separated string prefixed with a space.
renderTVars :: [Name.Name] -> String
renderTVars [] = ""
renderTVars tvars = " " ++ unwords (map Name.toChars tvars)

-- | Convert a 'Type.Type' to its textual representation.
--
-- Uses the existing pretty-printer with an empty localizer, producing
-- the canonical form of the type signature as it would appear in source
-- code.
--
-- @since 0.19.2
typeToText :: Type.Type -> String
typeToText tipe =
  Doc.toLine (Type.toDoc Localizer.empty RT.None tipe)
