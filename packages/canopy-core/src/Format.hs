{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Format - AST-based pretty-printer for Canopy source files.
--
-- This module converts a parsed 'AST.Source.Module' back into normalized
-- Canopy source text with consistent style:
--
-- * Configurable indentation (default: 4 spaces)
-- * Alphabetically sorted imports
-- * Consistent spacing around operators and in type signatures
-- * Normalized exposing lists (one item per line for long lists)
-- * Blank lines between top-level declarations
--
-- The formatter is idempotent: formatting an already-formatted file
-- produces the same output.
--
-- Internally, all rendering functions produce 'P.Doc' values from the
-- @ansi-wl-pprint@ pretty-printer library.  Only the three public entry
-- points ('formatModule', 'formatFile', 'formatBytes') convert the final
-- 'P.Doc' into 'Text'.
--
-- == Usage
--
-- @
-- import qualified Format
--
-- formatted <- Format.formatFile Format.defaultFormatConfig "src/Main.can"
-- case formatted of
--   Left err  -> putStrLn ("Parse error: " ++ show err)
--   Right txt -> writeFile "src/Main.can" txt
-- @
--
-- @since 0.19.1
module Format
  ( -- * Configuration
    FormatConfig (..),
    defaultFormatConfig,

    -- * Main entry points
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
import qualified Canopy.Float as EF
import qualified Canopy.String as ES
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import qualified Data.List as List
import Data.Name (Name)
import qualified Data.Name as Name
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Syntax as E
import qualified Text.PrettyPrint.ANSI.Leijen as P

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

-- | Formatting configuration controlling indentation and line width.
--
-- @since 0.19.1
data FormatConfig = FormatConfig
  { -- | Number of spaces per indentation level (default: 4).
    _fmtIndent :: !Int,
    -- | Target maximum line width (default: 80).
    _fmtLineWidth :: !Int
  }
  deriving (Eq, Show)

-- | Default format configuration: 4-space indent, 80-column width.
--
-- @since 0.19.1
defaultFormatConfig :: FormatConfig
defaultFormatConfig =
  FormatConfig
    { _fmtIndent = 4,
      _fmtLineWidth = 80
    }

-- ---------------------------------------------------------------------------
-- Doc rendering helper
-- ---------------------------------------------------------------------------

-- | Render a Doc to plain Text at the configured line width.
renderToText :: FormatConfig -> P.Doc -> Text
renderToText config doc =
  Text.pack (P.displayS (P.renderPretty 1.0 (_fmtLineWidth config) (P.plain doc)) "")

-- ---------------------------------------------------------------------------
-- Internal Doc helpers
-- ---------------------------------------------------------------------------

-- | Produce a newline followed by indentation at the given level.
nlIndent :: FormatConfig -> Int -> P.Doc
nlIndent config levels =
  P.line <> P.text (replicate (levels * _fmtIndent config) ' ')

-- | Render a Name to a Doc.
nameDoc :: Name -> P.Doc
nameDoc name = P.text (Name.toChars name)

-- | Render a located Name to a Doc.
locNameDoc :: A.Located Name -> P.Doc
locNameDoc locName = nameDoc (A.toValue locName)

-- | Wrap a Doc in parentheses.
parens :: P.Doc -> P.Doc
parens d = P.text "(" <> d <> P.text ")"

-- | Separate Docs with commas and spaces.
commaSepDocs :: [P.Doc] -> P.Doc
commaSepDocs = P.hcat . P.punctuate (P.text ", ")

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- | Format a parsed 'Src.Module' to normalized source text.
--
-- This is the pure core of the formatter. It accepts a 'FormatConfig' and
-- an already-parsed module and emits canonical Canopy source text.
--
-- @since 0.19.1
formatModule :: FormatConfig -> Src.Module -> Text
formatModule config modul =
  renderToText config (renderModule config modul)

-- | Render a full module to a Doc, separating sections with blank lines.
renderModule :: FormatConfig -> Src.Module -> P.Doc
renderModule config modul =
  P.vcat (P.punctuate (P.line <> P.line) (List.filter notEmpty sections))
  where
    sections =
      [ renderHeader modul
      , renderImports modul
      , renderDeclarations config modul
      ]
    notEmpty doc = not (null (P.displayS (P.renderPretty 1.0 80 (P.plain doc)) ""))

-- | Read, parse, and format a @.can@ source file.
--
-- Returns 'Left' when parsing fails (the file is syntactically invalid),
-- or 'Right' with the formatted source text on success.
--
-- @since 0.19.1
formatFile :: FormatConfig -> FilePath -> IO (Either E.Error Text)
formatFile config path = do
  bytes <- BS.readFile path
  pure (formatBytes config bytes)

-- | Parse and format a source 'BS.ByteString'.
--
-- Convenience wrapper used by the CLI stdin mode and check mode,
-- where bytes are already available in memory.
--
-- @since 0.19.1
formatBytes :: FormatConfig -> BS.ByteString -> Either E.Error Text
formatBytes config bytes =
  fmap (formatModule config) (Parse.fromByteString Parse.Application bytes)

-- ---------------------------------------------------------------------------
-- Header rendering
-- ---------------------------------------------------------------------------

-- | Render the module declaration header.
--
-- Handles all four module kinds: plain, port, ffi, and effect modules.
-- When no explicit header exists the module is anonymous; we emit nothing
-- so that files without a module declaration remain unmodified in that
-- respect.
renderHeader :: Src.Module -> P.Doc
renderHeader (Src.Module maybeName exports _ _ _ _ _ _ _ effects) =
  maybe P.empty (renderNamedHeader effects exports) maybeName

-- | Render a named module header line.
renderNamedHeader :: Src.Effects -> A.Located Src.Exposing -> A.Located Name -> P.Doc
renderNamedHeader effects exports locName =
  effectsKeyword effects
    P.<+> locNameDoc locName
    P.<+> P.text "exposing"
    P.<+> formatExposing (A.toValue exports)

-- | Determine the module keyword from the effects declaration.
effectsKeyword :: Src.Effects -> P.Doc
effectsKeyword Src.NoEffects    = P.text "module"
effectsKeyword (Src.Ports _)    = P.text "port module"
effectsKeyword (Src.FFI _)      = P.text "ffi module"
effectsKeyword (Src.Manager _ _) = P.text "effect module"

-- ---------------------------------------------------------------------------
-- Import rendering
-- ---------------------------------------------------------------------------

-- | Render all import declarations, sorted alphabetically by module name.
renderImports :: Src.Module -> P.Doc
renderImports (Src.Module _ _ _ imports _ _ _ _ _ _) =
  renderSortedImports (List.sortBy compareImports imports)

-- | Render a sorted list of imports with newlines between them.
renderSortedImports :: [Src.Import] -> P.Doc
renderSortedImports [] = P.empty
renderSortedImports sorted =
  P.vcat (P.punctuate P.line (map formatImport sorted))

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
formatImport :: Src.Import -> P.Doc
formatImport (Src.Import locName maybeAlias exposing) =
  P.hsep (List.filter notEmpty parts)
  where
    parts =
      [ P.text "import"
      , locNameDoc locName
      , maybe P.empty renderAlias maybeAlias
      , exposingClause exposing
      ]
    notEmpty doc = not (null (P.displayS (P.renderPretty 1.0 80 (P.plain doc)) ""))

-- | Render an alias clause for an import.
renderAlias :: Name -> P.Doc
renderAlias a = P.text "as" P.<+> nameDoc a

-- | Render the exposing clause for an import (empty when nothing is exposed).
exposingClause :: Src.Exposing -> P.Doc
exposingClause Src.Open = P.text "exposing (..)"
exposingClause (Src.Explicit []) = P.empty
exposingClause (Src.Explicit exposed) =
  P.text "exposing (" <> commaSepDocs (map formatExposed exposed) <> P.text ")"

-- | Format an individual exposed item.
formatExposed :: Src.Exposed -> P.Doc
formatExposed (Src.Lower locName) = locNameDoc locName
formatExposed (Src.Upper locName privacy) =
  locNameDoc locName <> formatPrivacy privacy
formatExposed (Src.Operator _ name) = parens (nameDoc name)

-- | Format the privacy annotation for an exposed type.
formatPrivacy :: Src.Privacy -> P.Doc
formatPrivacy Src.Private = P.empty
formatPrivacy (Src.Public _) = P.text "(..)"

-- | Format an exposing clause in module declaration position.
--
-- @since 0.19.1
formatExposing :: Src.Exposing -> P.Doc
formatExposing Src.Open = P.text "(..)"
formatExposing (Src.Explicit []) = P.text "()"
formatExposing (Src.Explicit exposed) =
  P.text "(" <> commaSepDocs (map formatExposed exposed) <> P.text ")"

-- ---------------------------------------------------------------------------
-- Declaration rendering
-- ---------------------------------------------------------------------------

-- | Render all top-level declarations with blank lines between them.
renderDeclarations :: FormatConfig -> Src.Module -> P.Doc
renderDeclarations config (Src.Module _ _ _ _ _ values unions aliases binops effects) =
  stackNonEmpty allDecls
  where
    allDecls =
      map (formatUnion config . A.toValue) unions
        ++ map (formatAlias config . A.toValue) aliases
        ++ map (formatInfix . A.toValue) binops
        ++ map (formatValue config . A.toValue) values
        ++ formatEffects effects

-- | Stack a list of Docs with blank lines, filtering out empty ones.
stackNonEmpty :: [P.Doc] -> P.Doc
stackNonEmpty docs =
  P.vcat (P.punctuate (P.line <> P.line) (List.filter notEmpty docs))
  where
    notEmpty doc = not (null (P.displayS (P.renderPretty 1.0 80 (P.plain doc)) ""))

-- | Format a union type definition.
formatUnion :: FormatConfig -> Src.Union -> P.Doc
formatUnion config (Src.Union locName params variants) =
  P.text "type" P.<+> locNameDoc locName
    <> formatTypeParams params
    <> nlIndent config 1 <> P.text "= "
    <> joinWith (nlIndent config 1 <> P.text "| ") (map formatVariant variants)

-- | Join a list of Docs with a separator Doc.
joinWith :: P.Doc -> [P.Doc] -> P.Doc
joinWith _ [] = P.empty
joinWith sep (d : ds) = foldl (\acc x -> acc <> sep <> x) d ds

-- | Format constructor type parameters for a union type.
formatTypeParams :: [A.Located Name] -> P.Doc
formatTypeParams [] = P.empty
formatTypeParams ps =
  P.text " " <> P.hsep (map locNameDoc ps)

-- | Format a single variant of a union type.
formatVariant :: (A.Located Name, [Src.Type]) -> P.Doc
formatVariant (locName, types) =
  locNameDoc locName <> foldMap (\t -> P.text " " <> formatTypeArg t) types

-- | Format a type alias definition.
formatAlias :: FormatConfig -> Src.Alias -> P.Doc
formatAlias config (Src.Alias locName params body) =
  P.text "type alias" P.<+> locNameDoc locName
    <> formatTypeParams params
    <> P.text " =" <> nlIndent config 1 <> formatType body

-- | Format an infix operator declaration.
formatInfix :: Src.Infix -> P.Doc
formatInfix (Src.Infix opName assoc (Binop.Precedence prec) funcName) =
  P.text "infix" P.<+> formatAssoc assoc P.<+> P.text (show prec)
    P.<+> parens (nameDoc opName) P.<+> P.text "=" P.<+> nameDoc funcName

-- | Format associativity keyword.
formatAssoc :: Binop.Associativity -> P.Doc
formatAssoc Binop.Left  = P.text "left"
formatAssoc Binop.Right = P.text "right"
formatAssoc Binop.Non   = P.text "non"

-- | Format a value / function definition.
formatValue :: FormatConfig -> Src.Value -> P.Doc
formatValue config (Src.Value locName params body maybeType) =
  typeAnnotation <> definition
  where
    nameD = locNameDoc locName
    typeAnnotation = maybe P.empty (renderTypeAnnotation nameD) maybeType
    paramText = foldMap (\p -> P.text " " <> formatPattern p) params
    definition = nameD <> paramText <> P.text " =" <> nlIndent config 1 <> formatExpr config body

-- | Render a type annotation line for a value definition.
renderTypeAnnotation :: P.Doc -> Src.Type -> P.Doc
renderTypeAnnotation nameD t =
  nameD P.<+> P.text ":" P.<+> formatType t <> P.line

-- | Format the effects portion of a module (ports and FFI declarations).
formatEffects :: Src.Effects -> [P.Doc]
formatEffects Src.NoEffects     = []
formatEffects (Src.Manager _ _) = []
formatEffects (Src.Ports ports) = map formatPort ports
formatEffects (Src.FFI _)       = []

-- | Format a port declaration.
formatPort :: Src.Port -> P.Doc
formatPort (Src.Port locName portType) =
  P.text "port" P.<+> locNameDoc locName P.<+> P.text ":" P.<+> formatType portType

-- ---------------------------------------------------------------------------
-- Type rendering
-- ---------------------------------------------------------------------------

-- | Format a type annotation.
--
-- @since 0.19.1
formatType :: Src.Type -> P.Doc
formatType (A.At _ typ) = formatType_ typ

-- | Format a type without location wrapper.
formatType_ :: Src.Type_ -> P.Doc
formatType_ (Src.TLambda a b) =
  formatType a P.<+> P.text "->" P.<+> formatType b
formatType_ (Src.TVar name) = nameDoc name
formatType_ (Src.TType _ name []) = nameDoc name
formatType_ (Src.TType _ name args) =
  nameDoc name P.<+> P.hsep (map formatTypeArg args)
formatType_ (Src.TTypeQual _ mod_ name []) =
  nameDoc mod_ <> P.text "." <> nameDoc name
formatType_ (Src.TTypeQual _ mod_ name args) =
  nameDoc mod_ <> P.text "." <> nameDoc name
    P.<+> P.hsep (map formatTypeArg args)
formatType_ (Src.TRecord fields maybeExt) =
  formatRecordType fields maybeExt
formatType_ Src.TUnit = P.text "()"
formatType_ (Src.TTuple a b rest) =
  P.text "( " <> commaSepDocs (map formatType (a : b : rest)) <> P.text " )"

-- | Format a type argument, adding parentheses around complex types.
formatTypeArg :: Src.Type -> P.Doc
formatTypeArg t@(A.At _ typ) = formatTypeArgInner t typ

-- | Determine whether a type argument needs parenthesising.
formatTypeArgInner :: Src.Type -> Src.Type_ -> P.Doc
formatTypeArgInner t (Src.TLambda _ _)         = parens (formatType t)
formatTypeArgInner t (Src.TType _ _ (_:_))     = parens (formatType t)
formatTypeArgInner t (Src.TTypeQual _ _ _ (_:_)) = parens (formatType t)
formatTypeArgInner t _                         = formatType t

-- | Format a record type literal.
formatRecordType :: [(A.Located Name, Src.Type)] -> Maybe (A.Located Name) -> P.Doc
formatRecordType fields maybeExt =
  P.text "{ " <> extPrefix <> commaSepDocs (map formatFieldType fields) <> P.text " }"
  where
    extPrefix = maybe P.empty (\n -> locNameDoc n <> P.text " | ") maybeExt

-- | Format a single record field type.
formatFieldType :: (A.Located Name, Src.Type) -> P.Doc
formatFieldType (locName, fieldType) =
  locNameDoc locName P.<+> P.text ":" P.<+> formatType fieldType

-- ---------------------------------------------------------------------------
-- Pattern rendering
-- ---------------------------------------------------------------------------

-- | Format a pattern.
formatPattern :: Src.Pattern -> P.Doc
formatPattern (A.At _ pat) = formatPattern_ pat

-- | Format a pattern without the location wrapper.
formatPattern_ :: Src.Pattern_ -> P.Doc
formatPattern_ Src.PAnything = P.text "_"
formatPattern_ (Src.PVar name) = nameDoc name
formatPattern_ (Src.PRecord fields) =
  P.text "{ " <> commaSepDocs (map locNameDoc fields) <> P.text " }"
formatPattern_ (Src.PAlias inner locName) =
  formatPattern inner P.<+> P.text "as" P.<+> locNameDoc locName
formatPattern_ Src.PUnit = P.text "()"
formatPattern_ (Src.PTuple a b rest) =
  P.text "( " <> commaSepDocs (map formatPattern (a : b : rest)) <> P.text " )"
formatPattern_ (Src.PCtor _ name []) = nameDoc name
formatPattern_ (Src.PCtor _ name args) =
  nameDoc name P.<+> P.hsep (map formatPatternArg args)
formatPattern_ (Src.PCtorQual _ mod_ name []) =
  nameDoc mod_ <> P.text "." <> nameDoc name
formatPattern_ (Src.PCtorQual _ mod_ name args) =
  nameDoc mod_ <> P.text "." <> nameDoc name
    P.<+> P.hsep (map formatPatternArg args)
formatPattern_ (Src.PList items) =
  P.text "[ " <> commaSepDocs (map formatPattern items) <> P.text " ]"
formatPattern_ (Src.PCons hd tl) =
  formatPattern hd P.<+> P.text "::" P.<+> formatPattern tl
formatPattern_ (Src.PChr s) =
  P.text "'" <> P.text (ES.toChars s) <> P.text "'"
formatPattern_ (Src.PStr s) =
  P.text "\"" <> P.text (ES.toChars s) <> P.text "\""
formatPattern_ (Src.PInt n) = P.text (show n)

-- | Format a constructor pattern argument (add parens around complex patterns).
formatPatternArg :: Src.Pattern -> P.Doc
formatPatternArg p@(A.At _ pat) = formatPatternArgInner p pat

-- | Determine whether a pattern argument needs parenthesising.
formatPatternArgInner :: Src.Pattern -> Src.Pattern_ -> P.Doc
formatPatternArgInner p (Src.PCtor _ _ (_:_))     = parens (formatPattern p)
formatPatternArgInner p (Src.PCtorQual _ _ _ (_:_)) = parens (formatPattern p)
formatPatternArgInner p (Src.PCons _ _)           = parens (formatPattern p)
formatPatternArgInner p (Src.PAlias _ _)          = parens (formatPattern p)
formatPatternArgInner p _                         = formatPattern p

-- ---------------------------------------------------------------------------
-- Expression rendering
-- ---------------------------------------------------------------------------

-- | Format an expression.
formatExpr :: FormatConfig -> Src.Expr -> P.Doc
formatExpr config (A.At _ expr) = formatExpr_ config expr

-- | Format an expression without the location wrapper.
formatExpr_ :: FormatConfig -> Src.Expr_ -> P.Doc
formatExpr_ _      (Src.Chr s) = P.text "'" <> P.text (ES.toChars s) <> P.text "'"
formatExpr_ _      (Src.Str s) = P.text "\"" <> P.text (ES.toChars s) <> P.text "\""
formatExpr_ _      (Src.Int n) = P.text (show n)
formatExpr_ _      (Src.Float f) = floatDoc f
formatExpr_ _      (Src.Var _ name) = nameDoc name
formatExpr_ _      (Src.VarQual _ mod_ name) = nameDoc mod_ <> P.text "." <> nameDoc name
formatExpr_ config (Src.List items) = formatListExpr config items
formatExpr_ _      (Src.Op name) = parens (nameDoc name)
formatExpr_ config (Src.Negate e) = P.text "-" <> formatExprArg config e
formatExpr_ config (Src.Binops pairs final) = formatBinops config pairs final
formatExpr_ config (Src.Lambda pats body) = formatLambda config pats body
formatExpr_ config (Src.Call func args) = formatCall config func args
formatExpr_ config (Src.If branches elseBranch) = formatIf config branches elseBranch
formatExpr_ config (Src.Let defs body) = formatLet config defs body
formatExpr_ config (Src.Case subj branches) = formatCase config subj branches
formatExpr_ _      (Src.Accessor name) = P.text "." <> nameDoc name
formatExpr_ config (Src.Access rec_ locName) =
  formatExprArg config rec_ <> P.text "." <> locNameDoc locName
formatExpr_ config (Src.Update locName updates) = formatUpdate config locName updates
formatExpr_ config (Src.Record fields) = formatRecord config fields
formatExpr_ _      Src.Unit = P.text "()"
formatExpr_ config (Src.Tuple a b rest) =
  P.text "( " <> commaSepDocs (map (formatExpr config) (a : b : rest)) <> P.text " )"
formatExpr_ _      (Src.Shader _ _) = P.text "[glsl| ... |]"

-- | Render a float literal to a Doc via its builder representation.
floatDoc :: EF.Float -> P.Doc
floatDoc f =
  P.text (Text.unpack (TE.decodeUtf8 (BL.toStrict (BB.toLazyByteString (EF.toBuilder f)))))

-- | Format a list expression.
formatListExpr :: FormatConfig -> [Src.Expr] -> P.Doc
formatListExpr config items =
  P.text "[ " <> commaSepDocs (map (formatExpr config) items) <> P.text " ]"

-- | Format a lambda expression.
formatLambda :: FormatConfig -> [Src.Pattern] -> Src.Expr -> P.Doc
formatLambda config pats body =
  P.text "\\" <> P.hsep (map formatPattern pats) P.<+> P.text "->" P.<+> formatExpr config body

-- | Format a function call expression.
formatCall :: FormatConfig -> Src.Expr -> [Src.Expr] -> P.Doc
formatCall config func args =
  formatExprArg config func <> foldMap (\a -> P.text " " <> formatExprArg config a) args

-- | Wrap an expression in parentheses when it needs them as an argument.
formatExprArg :: FormatConfig -> Src.Expr -> P.Doc
formatExprArg config e@(A.At _ expr) = formatExprArgInner config e expr

-- | Determine whether an expression argument needs parenthesising.
formatExprArgInner :: FormatConfig -> Src.Expr -> Src.Expr_ -> P.Doc
formatExprArgInner config e (Src.Binops _ _)  = parens (formatExpr config e)
formatExprArgInner config e (Src.Lambda _ _)  = parens (formatExpr config e)
formatExprArgInner config e (Src.If _ _)      = parens (formatExpr config e)
formatExprArgInner config e (Src.Let _ _)     = parens (formatExpr config e)
formatExprArgInner config e (Src.Case _ _)    = parens (formatExpr config e)
formatExprArgInner config e (Src.Call _ (_:_)) = parens (formatExpr config e)
formatExprArgInner config e _                 = formatExpr config e

-- | Format a binary operator chain.
formatBinops :: FormatConfig -> [(Src.Expr, A.Located Name)] -> Src.Expr -> P.Doc
formatBinops config [] final = formatExpr config final
formatBinops config ((lhs, locOp) : rest) final =
  formatExpr config lhs P.<+> locNameDoc locOp
    P.<+> formatBinops config rest final

-- | Format an if-then-else expression.
formatIf :: FormatConfig -> [(Src.Expr, Src.Expr)] -> Src.Expr -> P.Doc
formatIf config [] elseExpr =
  P.text "else" <> nlIndent config 1 <> formatExpr config elseExpr
formatIf config ((cond, thenExpr) : rest) elseExpr =
  P.text "if" P.<+> formatExpr config cond P.<+> P.text "then"
    <> nlIndent config 1 <> formatExpr config thenExpr
    <> P.line <> nlIndent config 0 <> formatIf config rest elseExpr

-- | Format a let-in expression.
formatLet :: FormatConfig -> [A.Located Src.Def] -> Src.Expr -> P.Doc
formatLet config defs body =
  P.text "let" <> nlIndent config 1
    <> joinWith (nlIndent config 1) (map (formatDef config . A.toValue) defs)
    <> P.line <> P.text "  in" <> P.line <> P.text "  " <> formatExpr config body

-- | Format a local definition inside a let expression.
formatDef :: FormatConfig -> Src.Def -> P.Doc
formatDef config (Src.Define locName params body maybeType) =
  typeAnn <> locNameDoc locName <> paramText
    <> P.text " =" <> nlIndent config 2 <> formatExpr config body
  where
    typeAnn = maybe P.empty (renderDefTypeAnn config locName) maybeType
    paramText = foldMap (\p -> P.text " " <> formatPattern p) params
formatDef config (Src.Destruct pat body) =
  formatPattern pat <> P.text " =" <> nlIndent config 2 <> formatExpr config body

-- | Render the type annotation line for a local definition.
renderDefTypeAnn :: FormatConfig -> A.Located Name -> Src.Type -> P.Doc
renderDefTypeAnn config locName t =
  locNameDoc locName P.<+> P.text ":" P.<+> formatType t <> nlIndent config 1

-- | Format a case expression.
formatCase :: FormatConfig -> Src.Expr -> [(Src.Pattern, Src.Expr)] -> P.Doc
formatCase config subj branches =
  P.text "case" P.<+> formatExpr config subj P.<+> P.text "of"
    <> nlIndent config 1
    <> joinWith (nlIndent config 1) (map (formatBranch config) branches)

-- | Format a single case branch.
formatBranch :: FormatConfig -> (Src.Pattern, Src.Expr) -> P.Doc
formatBranch config (pat, body) =
  formatPattern pat P.<+> P.text "->"
    <> nlIndent config 2 <> formatExpr config body

-- | Format a record update expression.
formatUpdate :: FormatConfig -> A.Located Name -> [(A.Located Name, Src.Expr)] -> P.Doc
formatUpdate config locName updates =
  P.text "{ " <> locNameDoc locName <> P.text " | "
    <> commaSepDocs (map (formatFieldUpdate config) updates) <> P.text " }"

-- | Format a single field update.
formatFieldUpdate :: FormatConfig -> (A.Located Name, Src.Expr) -> P.Doc
formatFieldUpdate config (locName, expr) =
  locNameDoc locName P.<+> P.text "=" P.<+> formatExpr config expr

-- | Format a record literal expression.
formatRecord :: FormatConfig -> [(A.Located Name, Src.Expr)] -> P.Doc
formatRecord _ [] = P.text "{}"
formatRecord config fields =
  P.text "{ " <> commaSepDocs (map (formatField config) fields) <> P.text " }"

-- | Format a single record field assignment.
formatField :: FormatConfig -> (A.Located Name, Src.Expr) -> P.Doc
formatField config (locName, expr) =
  locNameDoc locName P.<+> P.text "=" P.<+> formatExpr config expr
