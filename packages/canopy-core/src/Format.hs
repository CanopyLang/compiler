{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Format - AST-based pretty-printer for Canopy source files.
--
-- This module converts a parsed 'AST.Source.Module' back into normalized
-- Canopy source text with consistent style:
--
-- * Two-space indentation throughout
-- * Alphabetically sorted imports
-- * Consistent spacing around operators and in type signatures
-- * Normalized exposing lists (one item per line for long lists)
-- * Blank lines between top-level declarations
--
-- The formatter is idempotent: formatting an already-formatted file
-- produces the same output.
--
-- == Usage
--
-- @
-- import qualified Format
--
-- formatted <- Format.formatFile "src/Main.can"
-- case formatted of
--   Left err  -> putStrLn ("Parse error: " ++ show err)
--   Right txt -> writeFile "src/Main.can" txt
-- @
--
-- @since 0.19.1
module Format
  ( -- * Main entry points
    formatModule,
    formatFile,
    formatBytes,

    -- * Exposed for testing
    formatImport,
    formatExposing,
    formatType,
  )
where

import qualified AST.Source as Src
import qualified AST.Utils.Binop as Binop
import qualified Canopy.String as ES
import qualified Data.ByteString as BS
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Builder as BB
import Data.Name (Name)
import qualified Data.Name as Name
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Syntax as E
import Data.Text (Text)
import qualified Canopy.Float as EF

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- | Format a parsed 'Src.Module' to normalized source text.
--
-- This is the pure core of the formatter. It accepts an already-parsed
-- module and emits canonical Canopy source text.
--
-- @since 0.19.1
formatModule :: Src.Module -> Text
formatModule modul =
  Text.intercalate "\n\n" (List.filter (not . Text.null) sections)
  where
    sections =
      [ renderHeader modul
      , renderImports modul
      , renderDeclarations modul
      ]

-- | Read, parse, and format a @.can@ source file.
--
-- Returns 'Left' when parsing fails (the file is syntactically invalid),
-- or 'Right' with the formatted source text on success.
--
-- @since 0.19.1
formatFile :: FilePath -> IO (Either E.Error Text)
formatFile path = do
  bytes <- BS.readFile path
  pure (formatBytes bytes)

-- | Parse and format a source 'BS.ByteString'.
--
-- Convenience wrapper used by the CLI stdin mode and check mode,
-- where bytes are already available in memory.
--
-- @since 0.19.1
formatBytes :: BS.ByteString -> Either E.Error Text
formatBytes bytes =
  fmap formatModule (Parse.fromByteString Parse.Application bytes)

-- ---------------------------------------------------------------------------
-- Header rendering
-- ---------------------------------------------------------------------------

-- | Render the module declaration header.
--
-- Handles all four module kinds: plain, port, ffi, and effect modules.
-- When no explicit header exists the module is anonymous; we emit nothing
-- so that files without a module declaration remain unmodified in that
-- respect.
renderHeader :: Src.Module -> Text
renderHeader (Src.Module maybeName exports _ _ _ _ _ _ _ effects) =
  maybe Text.empty renderNamedHeader maybeName
  where
    renderNamedHeader locName =
      keyword <> " " <> Text.pack (Name.toChars (A.toValue locName))
        <> " exposing " <> formatExposing (A.toValue exports)
    keyword = effectsKeyword effects

-- | Determine the module keyword from the effects declaration.
effectsKeyword :: Src.Effects -> Text
effectsKeyword effects =
  case effects of
    Src.NoEffects -> "module"
    Src.Ports _   -> "port module"
    Src.FFI _     -> "ffi module"
    Src.Manager _ _ -> "effect module"

-- ---------------------------------------------------------------------------
-- Import rendering
-- ---------------------------------------------------------------------------

-- | Render all import declarations, sorted alphabetically by module name.
renderImports :: Src.Module -> Text
renderImports (Src.Module _ _ _ imports _ _ _ _ _ _) =
  case List.sortBy compareImports imports of
    [] -> Text.empty
    sorted -> Text.unlines (map formatImport sorted)

-- | Compare imports by their module name for alphabetical sorting.
compareImports :: Src.Import -> Src.Import -> Ordering
compareImports a b =
  compare
    (Name.toChars (Src.getImportName a))
    (Name.toChars (Src.getImportName b))

-- | Format a single import declaration.
--
-- Produces text in one of these forms:
--
-- @
-- import Foo
-- import Foo as F
-- import Foo exposing (..)
-- import Foo as F exposing (bar, Baz)
-- @
--
-- @since 0.19.1
formatImport :: Src.Import -> Text
formatImport (Src.Import locName maybeAlias exposing) =
  Text.concat (List.intersperse " " parts)
  where
    parts = List.filter (not . Text.null)
      [ "import"
      , Text.pack (Name.toChars (A.toValue locName))
      , maybe Text.empty (\a -> "as " <> Text.pack (Name.toChars a)) maybeAlias
      , exposingClause exposing
      ]

-- | Render the exposing clause for an import (empty when nothing is exposed).
exposingClause :: Src.Exposing -> Text
exposingClause Src.Open = "exposing (..)"
exposingClause (Src.Explicit []) = Text.empty
exposingClause (Src.Explicit exposed) =
  "exposing (" <> Text.intercalate ", " (map formatExposed exposed) <> ")"

-- | Format an individual exposed item.
formatExposed :: Src.Exposed -> Text
formatExposed exposed =
  case exposed of
    Src.Lower locName -> Text.pack (Name.toChars (A.toValue locName))
    Src.Upper locName privacy ->
      Text.pack (Name.toChars (A.toValue locName)) <> formatPrivacy privacy
    Src.Operator _ name -> "(" <> Text.pack (Name.toChars name) <> ")"

-- | Format the privacy annotation for an exposed type.
formatPrivacy :: Src.Privacy -> Text
formatPrivacy Src.Private = Text.empty
formatPrivacy (Src.Public _) = "(..)"

-- | Format an exposing clause in module declaration position.
--
-- @since 0.19.1
formatExposing :: Src.Exposing -> Text
formatExposing Src.Open = "(..)"
formatExposing (Src.Explicit []) = "()"
formatExposing (Src.Explicit exposed) =
  "(" <> Text.intercalate ", " (map formatExposed exposed) <> ")"

-- ---------------------------------------------------------------------------
-- Declaration rendering
-- ---------------------------------------------------------------------------

-- | Render all top-level declarations with blank lines between them.
renderDeclarations :: Src.Module -> Text
renderDeclarations (Src.Module _ _ _ _ _ values unions aliases binops effects) =
  Text.intercalate "\n\n" (List.filter (not . Text.null) allDecls)
  where
    allDecls =
      map formatUnion (map A.toValue unions)
        ++ map formatAlias (map A.toValue aliases)
        ++ map formatInfix (map A.toValue binops)
        ++ map formatValue (map A.toValue values)
        ++ formatEffects effects

-- | Format a union type definition.
formatUnion :: Src.Union -> Text
formatUnion (Src.Union locName params variants) =
  "type " <> Text.pack (Name.toChars (A.toValue locName))
    <> formatTypeParams params
    <> "\n    = " <> Text.intercalate "\n    | " (map formatVariant variants)

-- | Format constructor type parameters for a union type.
formatTypeParams :: [A.Located Name] -> Text
formatTypeParams [] = Text.empty
formatTypeParams ps =
  " " <> Text.unwords (map (Text.pack . Name.toChars . A.toValue) ps)

-- | Format a single variant of a union type.
formatVariant :: (A.Located Name, [Src.Type]) -> Text
formatVariant (locName, types) =
  Text.pack (Name.toChars (A.toValue locName))
    <> foldMap (\t -> " " <> formatTypeArg t) types

-- | Format a type alias definition.
formatAlias :: Src.Alias -> Text
formatAlias (Src.Alias locName params body) =
  "type alias " <> Text.pack (Name.toChars (A.toValue locName))
    <> formatTypeParams params
    <> " =\n    " <> formatType body

-- | Format an infix operator declaration.
formatInfix :: Src.Infix -> Text
formatInfix (Src.Infix opName assoc (Binop.Precedence prec) funcName) =
  "infix " <> formatAssoc assoc <> " " <> Text.pack (show prec)
    <> " (" <> Text.pack (Name.toChars opName) <> ") = "
    <> Text.pack (Name.toChars funcName)

-- | Format associativity keyword.
formatAssoc :: Binop.Associativity -> Text
formatAssoc Binop.Left  = "left"
formatAssoc Binop.Right = "right"
formatAssoc Binop.Non   = "non"

-- | Format a value / function definition.
formatValue :: Src.Value -> Text
formatValue (Src.Value locName params body maybeType) =
  typeAnnotation <> definition
  where
    nameText = Text.pack (Name.toChars (A.toValue locName))
    typeAnnotation = maybe Text.empty (\t -> nameText <> " : " <> formatType t <> "\n") maybeType
    paramText = foldMap (\p -> " " <> formatPattern p) params
    definition = nameText <> paramText <> " =\n    " <> formatExpr body

-- | Format the effects portion of a module (ports and FFI declarations).
formatEffects :: Src.Effects -> [Text]
formatEffects effects =
  case effects of
    Src.NoEffects -> []
    Src.Manager _ _ -> []
    Src.Ports ports -> map formatPort ports
    Src.FFI _foreignImports -> []

-- | Format a port declaration.
formatPort :: Src.Port -> Text
formatPort (Src.Port locName portType) =
  "port " <> Text.pack (Name.toChars (A.toValue locName))
    <> " : " <> formatType portType

-- ---------------------------------------------------------------------------
-- Type rendering
-- ---------------------------------------------------------------------------

-- | Format a type annotation.
--
-- @since 0.19.1
formatType :: Src.Type -> Text
formatType (A.At _ typ) = formatType_ typ

-- | Format a type without location wrapper.
formatType_ :: Src.Type_ -> Text
formatType_ typ =
  case typ of
    Src.TLambda a b -> formatType a <> " -> " <> formatType b
    Src.TVar name -> Text.pack (Name.toChars name)
    Src.TType _ name [] -> Text.pack (Name.toChars name)
    Src.TType _ name args ->
      Text.pack (Name.toChars name) <> " " <> Text.unwords (map formatTypeArg args)
    Src.TTypeQual _ mod_ name [] ->
      Text.pack (Name.toChars mod_) <> "." <> Text.pack (Name.toChars name)
    Src.TTypeQual _ mod_ name args ->
      Text.pack (Name.toChars mod_) <> "." <> Text.pack (Name.toChars name)
        <> " " <> Text.unwords (map formatTypeArg args)
    Src.TRecord fields maybeExt ->
      formatRecordType fields maybeExt
    Src.TUnit -> "()"
    Src.TTuple a b rest ->
      "( " <> Text.intercalate ", " (map formatType (a : b : rest)) <> " )"

-- | Format a type argument, adding parentheses around complex types.
formatTypeArg :: Src.Type -> Text
formatTypeArg t@(A.At _ typ) =
  case typ of
    Src.TLambda _ _ -> "(" <> formatType t <> ")"
    Src.TType _ _ (_:_) -> "(" <> formatType t <> ")"
    Src.TTypeQual _ _ _ (_:_) -> "(" <> formatType t <> ")"
    _ -> formatType t

-- | Format a record type literal.
formatRecordType :: [(A.Located Name, Src.Type)] -> Maybe (A.Located Name) -> Text
formatRecordType fields maybeExt =
  "{ " <> extPrefix <> Text.intercalate ", " (map formatFieldType fields) <> " }"
  where
    extPrefix = maybe Text.empty
      (\n -> Text.pack (Name.toChars (A.toValue n)) <> " | ")
      maybeExt

-- | Format a single record field type.
formatFieldType :: (A.Located Name, Src.Type) -> Text
formatFieldType (locName, fieldType) =
  Text.pack (Name.toChars (A.toValue locName)) <> " : " <> formatType fieldType

-- ---------------------------------------------------------------------------
-- Pattern rendering
-- ---------------------------------------------------------------------------

-- | Format a pattern.
formatPattern :: Src.Pattern -> Text
formatPattern (A.At _ pat) = formatPattern_ pat

-- | Format a pattern without the location wrapper.
formatPattern_ :: Src.Pattern_ -> Text
formatPattern_ pat =
  case pat of
    Src.PAnything -> "_"
    Src.PVar name -> Text.pack (Name.toChars name)
    Src.PRecord fields ->
      "{ " <> Text.intercalate ", " (map (Text.pack . Name.toChars . A.toValue) fields) <> " }"
    Src.PAlias inner locName ->
      formatPattern inner <> " as " <> Text.pack (Name.toChars (A.toValue locName))
    Src.PUnit -> "()"
    Src.PTuple a b rest ->
      "( " <> Text.intercalate ", " (map formatPattern (a : b : rest)) <> " )"
    Src.PCtor _ name [] -> Text.pack (Name.toChars name)
    Src.PCtor _ name args ->
      Text.pack (Name.toChars name) <> " " <> Text.unwords (map formatPatternArg args)
    Src.PCtorQual _ mod_ name [] ->
      Text.pack (Name.toChars mod_) <> "." <> Text.pack (Name.toChars name)
    Src.PCtorQual _ mod_ name args ->
      Text.pack (Name.toChars mod_) <> "." <> Text.pack (Name.toChars name)
        <> " " <> Text.unwords (map formatPatternArg args)
    Src.PList items ->
      "[ " <> Text.intercalate ", " (map formatPattern items) <> " ]"
    Src.PCons hd tl -> formatPattern hd <> " :: " <> formatPattern tl
    Src.PChr s -> "'" <> Text.pack (ES.toChars s) <> "'"
    Src.PStr s -> "\"" <> Text.pack (ES.toChars s) <> "\""
    Src.PInt n -> Text.pack (show n)

-- | Format a constructor pattern argument (add parens around complex patterns).
formatPatternArg :: Src.Pattern -> Text
formatPatternArg p@(A.At _ pat) =
  case pat of
    Src.PCtor _ _ (_:_) -> "(" <> formatPattern p <> ")"
    Src.PCtorQual _ _ _ (_:_) -> "(" <> formatPattern p <> ")"
    Src.PCons _ _ -> "(" <> formatPattern p <> ")"
    Src.PAlias _ _ -> "(" <> formatPattern p <> ")"
    _ -> formatPattern p

-- ---------------------------------------------------------------------------
-- Expression rendering
-- ---------------------------------------------------------------------------

-- | Format an expression.
formatExpr :: Src.Expr -> Text
formatExpr (A.At _ expr) = formatExpr_ expr

-- | Format an expression without the location wrapper.
formatExpr_ :: Src.Expr_ -> Text
formatExpr_ expr =
  case expr of
    Src.Chr s -> "'" <> Text.pack (ES.toChars s) <> "'"
    Src.Str s -> "\"" <> Text.pack (ES.toChars s) <> "\""
    Src.Int n -> Text.pack (show n)
    Src.Float f -> Text.decodeUtf8 (BL.toStrict (BB.toLazyByteString (EF.toBuilder f)))
    Src.Var _ name -> Text.pack (Name.toChars name)
    Src.VarQual _ mod_ name ->
      Text.pack (Name.toChars mod_) <> "." <> Text.pack (Name.toChars name)
    Src.List items ->
      "[ " <> Text.intercalate ", " (map formatExpr items) <> " ]"
    Src.Op name -> "(" <> Text.pack (Name.toChars name) <> ")"
    Src.Negate e -> "-" <> formatExprArg e
    Src.Binops pairs final -> formatBinops pairs final
    Src.Lambda pats body ->
      "\\" <> Text.unwords (map formatPattern pats) <> " -> " <> formatExpr body
    Src.Call func args ->
      formatExprArg func <> foldMap (\a -> " " <> formatExprArg a) args
    Src.If branches elseBranch -> formatIf branches elseBranch
    Src.Let defs body -> formatLet defs body
    Src.Case subj branches -> formatCase subj branches
    Src.Accessor name -> "." <> Text.pack (Name.toChars name)
    Src.Access rec_ locName ->
      formatExprArg rec_ <> "." <> Text.pack (Name.toChars (A.toValue locName))
    Src.Update locName updates -> formatUpdate locName updates
    Src.Record fields -> formatRecord fields
    Src.Unit -> "()"
    Src.Tuple a b rest ->
      "( " <> Text.intercalate ", " (map formatExpr (a : b : rest)) <> " )"
    Src.Shader _ _ -> "[glsl| ... |]"

-- | Wrap an expression in parentheses when it needs them as an argument.
formatExprArg :: Src.Expr -> Text
formatExprArg e@(A.At _ expr) =
  case expr of
    Src.Binops _ _ -> "(" <> formatExpr e <> ")"
    Src.Lambda _ _ -> "(" <> formatExpr e <> ")"
    Src.If _ _ -> "(" <> formatExpr e <> ")"
    Src.Let _ _ -> "(" <> formatExpr e <> ")"
    Src.Case _ _ -> "(" <> formatExpr e <> ")"
    Src.Call _ (_:_) -> "(" <> formatExpr e <> ")"
    _ -> formatExpr e

-- | Format a binary operator chain.
formatBinops :: [(Src.Expr, A.Located Name)] -> Src.Expr -> Text
formatBinops [] final = formatExpr final
formatBinops ((lhs, locOp) : rest) final =
  formatExpr lhs <> " " <> Text.pack (Name.toChars (A.toValue locOp))
    <> " " <> formatBinops rest final

-- | Format an if-then-else expression.
formatIf :: [(Src.Expr, Src.Expr)] -> Src.Expr -> Text
formatIf [] elseExpr = "else\n    " <> formatExpr elseExpr
formatIf ((cond, thenExpr) : rest) elseExpr =
  "if " <> formatExpr cond <> " then\n    "
    <> formatExpr thenExpr <> "\n\n  " <> formatIf rest elseExpr

-- | Format a let-in expression.
formatLet :: [A.Located Src.Def] -> Src.Expr -> Text
formatLet defs body =
  "let\n    " <> Text.intercalate "\n    " (map (formatDef . A.toValue) defs)
    <> "\n  in\n  " <> formatExpr body

-- | Format a local definition inside a let expression.
formatDef :: Src.Def -> Text
formatDef def =
  case def of
    Src.Define locName params body maybeType ->
      typeAnn <> Text.pack (Name.toChars (A.toValue locName))
        <> paramText <> " =\n        " <> formatExpr body
      where
        typeAnn = maybe Text.empty (\t -> Text.pack (Name.toChars (A.toValue locName))
          <> " : " <> formatType t <> "\n    ") maybeType
        paramText = foldMap (\p -> " " <> formatPattern p) params
    Src.Destruct pat body ->
      formatPattern pat <> " =\n        " <> formatExpr body

-- | Format a case expression.
formatCase :: Src.Expr -> [(Src.Pattern, Src.Expr)] -> Text
formatCase subj branches =
  "case " <> formatExpr subj <> " of\n    "
    <> Text.intercalate "\n    " (map formatBranch branches)

-- | Format a single case branch.
formatBranch :: (Src.Pattern, Src.Expr) -> Text
formatBranch (pat, body) =
  formatPattern pat <> " ->\n        " <> formatExpr body

-- | Format a record update expression.
formatUpdate :: A.Located Name -> [(A.Located Name, Src.Expr)] -> Text
formatUpdate locName updates =
  "{ " <> Text.pack (Name.toChars (A.toValue locName)) <> " | "
    <> Text.intercalate ", " (map formatFieldUpdate updates) <> " }"

-- | Format a single field update.
formatFieldUpdate :: (A.Located Name, Src.Expr) -> Text
formatFieldUpdate (locName, expr) =
  Text.pack (Name.toChars (A.toValue locName)) <> " = " <> formatExpr expr

-- | Format a record literal expression.
formatRecord :: [(A.Located Name, Src.Expr)] -> Text
formatRecord [] = "{}"
formatRecord fields =
  "{ " <> Text.intercalate ", " (map formatField fields) <> " }"

-- | Format a single record field assignment.
formatField :: (A.Located Name, Src.Expr) -> Text
formatField (locName, expr) =
  Text.pack (Name.toChars (A.toValue locName)) <> " = " <> formatExpr expr
