{-# LANGUAGE OverloadedStrings #-}

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
-- Internally, all rendering functions produce 'PP.Doc' values from the
-- @ansi-wl-pprint@ pretty-printer library.  Only the three public entry
-- points ('formatModule', 'formatFile', 'formatBytes') convert the final
-- 'PP.Doc' into 'Text'.
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
import Data.Word (Word32)
import Canopy.Data.Name (Name)
import qualified Canopy.Data.Name as Name
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Syntax as SyntaxError
import qualified Text.PrettyPrint.ANSI.Leijen as PP

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
renderToText :: FormatConfig -> PP.Doc -> Text
renderToText config doc =
  Text.pack (PP.displayS (PP.renderPretty 1.0 (_fmtLineWidth config) (PP.plain doc)) "")

-- ---------------------------------------------------------------------------
-- Internal Doc helpers
-- ---------------------------------------------------------------------------

-- | Produce a newline followed by indentation at the given level.
nlIndent :: FormatConfig -> Int -> PP.Doc
nlIndent config levels =
  PP.line <> PP.text (replicate (levels * _fmtIndent config) ' ')

-- | Render a Name to a Doc.
nameDoc :: Name -> PP.Doc
nameDoc name = PP.text (Name.toChars name)

-- | Render a located Name to a Doc.
locNameDoc :: Ann.Located Name -> PP.Doc
locNameDoc locName = nameDoc (Ann.toValue locName)

-- | Wrap a Doc in parentheses.
parens :: PP.Doc -> PP.Doc
parens d = PP.text "(" <> d <> PP.text ")"

-- | Separate Docs with commas and spaces.
commaSepDocs :: [PP.Doc] -> PP.Doc
commaSepDocs = PP.hcat . PP.punctuate (PP.text ", ")

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
--
-- Comments are interleaved with declarations by source position.
-- Comments that fall outside the declaration region (e.g., between
-- the header and imports) are rendered between the appropriate
-- sections.
renderModule :: FormatConfig -> Src.Module -> PP.Doc
renderModule config modul =
  PP.vcat (PP.punctuate (PP.line <> PP.line) (List.filter notEmpty sections))
  where
    allComments = Src._comments modul
    importEnd = importsEndRow modul
    sections =
      [ renderHeader modul
      , renderImportsWithComments modul allComments importEnd
      , renderDeclarations config modul
      , renderTrailingComments config modul
      ]
    notEmpty doc = not (null (PP.displayS (PP.renderPretty 1.0 80 (PP.plain doc)) ""))

-- | Read, parse, and format a @.can@ source file.
--
-- Returns 'Left' when parsing fails (the file is syntactically invalid),
-- or 'Right' with the formatted source text on success.
--
-- @since 0.19.1
formatFile :: FormatConfig -> FilePath -> IO (Either SyntaxError.Error Text)
formatFile config path = do
  bytes <- BS.readFile path
  pure (formatBytes config bytes)

-- | Parse and format a source 'BS.ByteString'.
--
-- Convenience wrapper used by the CLI stdin mode and check mode,
-- where bytes are already available in memory.
--
-- @since 0.19.1
formatBytes :: FormatConfig -> BS.ByteString -> Either SyntaxError.Error Text
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
renderHeader :: Src.Module -> PP.Doc
renderHeader (Src.Module maybeName exports _ _ _ _ _ _ _ effects _) =
  maybe PP.empty (renderNamedHeader effects exports) maybeName

-- | Render a named module header line.
renderNamedHeader :: Src.Effects -> Ann.Located Src.Exposing -> Ann.Located Name -> PP.Doc
renderNamedHeader effects exports locName =
  effectsKeyword effects
    PP.<+> locNameDoc locName
    PP.<+> PP.text "exposing"
    PP.<+> formatExposing (Ann.toValue exports)

-- | Determine the module keyword from the effects declaration.
effectsKeyword :: Src.Effects -> PP.Doc
effectsKeyword Src.NoEffects    = PP.text "module"
effectsKeyword (Src.Ports _)    = PP.text "port module"
effectsKeyword (Src.FFI _)      = PP.text "ffi module"
effectsKeyword (Src.Manager _ _) = PP.text "effect module"

-- ---------------------------------------------------------------------------
-- Import rendering
-- ---------------------------------------------------------------------------

-- | Render all import declarations, sorted alphabetically by module name.
renderImports :: Src.Module -> PP.Doc
renderImports (Src.Module _ _ _ imports _ _ _ _ _ _ _) =
  renderSortedImports (List.sortBy compareImports imports)

-- | Render imports preceded by any comments that fall between the
-- header and the first declaration.
renderImportsWithComments :: Src.Module -> [Src.RawComment] -> Word32 -> PP.Doc
renderImportsWithComments modul allComments impEnd =
  stackNonEmpty (preImportDocs ++ [renderImports modul] ++ postImportDocs)
  where
    preImportDocs = map (renderRawComment . snd) preImportComments
    postImportDocs = map (renderRawComment . snd) postImportComments
    (preImportComments, postImportComments) = List.partition isBeforeImports betweenComments
    betweenComments = [(Src._rcRow c, c) | c <- allComments, isBetweenHeaderAndDecls c modul]
    isBeforeImports (row, _) = row <= impEnd

-- | Determine whether a comment falls between the header and declarations.
isBetweenHeaderAndDecls :: Src.RawComment -> Src.Module -> Bool
isBetweenHeaderAndDecls rc modul =
  Src._rcRow rc > headerEndRow modul && Src._rcRow rc < declStartRow modul

-- | Get the ending row of the module header (0 if no header).
headerEndRow :: Src.Module -> Word32
headerEndRow (Src.Module Nothing _ _ _ _ _ _ _ _ _ _) = 0
headerEndRow (Src.Module (Just (Ann.At (Ann.Region _ (Ann.Position row _)) _)) _ _ _ _ _ _ _ _ _ _) = row

-- | Get the starting row of the first declaration.
declStartRow :: Src.Module -> Word32
declStartRow (Src.Module _ _ _ _ _ values unions aliases binops _ _) =
  minimum (maxBound : allRows)
  where
    allRows = map locRow values ++ map locRow unions ++ map locRow aliases ++ map locRow binops
    locRow (Ann.At (Ann.Region (Ann.Position row _) _) _) = row

-- | Get the ending row of the last import.
importsEndRow :: Src.Module -> Word32
importsEndRow (Src.Module _ _ _ [] _ _ _ _ _ _ _) = 0
importsEndRow (Src.Module _ _ _ imports _ _ _ _ _ _ _) =
  maximum (map importRow imports)
  where
    importRow (Src.Import (Ann.At (Ann.Region _ (Ann.Position row _)) _) _ _ _) = row

-- | Render comments that appear after all declarations.
renderTrailingComments :: FormatConfig -> Src.Module -> PP.Doc
renderTrailingComments _config (Src.Module _ _ _ _ _ values unions aliases binops _ comments) =
  stackNonEmpty (map renderRawComment trailingComments)
  where
    lastDeclRow = maximum (0 : allRows)
    allRows = map locRow values ++ map locRow unions ++ map locRow aliases ++ map locRow binops
    locRow (Ann.At (Ann.Region _ (Ann.Position row _)) _) = row
    trailingComments = filter (\c -> Src._rcRow c > lastDeclRow) comments

-- | Render a sorted list of imports with newlines between them.
renderSortedImports :: [Src.Import] -> PP.Doc
renderSortedImports [] = PP.empty
renderSortedImports sorted =
  PP.vcat (PP.punctuate PP.line (map formatImport sorted))

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
formatImport :: Src.Import -> PP.Doc
formatImport (Src.Import locName maybeAlias exposing isLazy) =
  PP.hsep (List.filter notEmpty parts)
  where
    parts =
      [ if isLazy then PP.text "lazy" else PP.empty
      , PP.text "import"
      , locNameDoc locName
      , maybe PP.empty renderAlias maybeAlias
      , exposingClause exposing
      ]
    notEmpty doc = not (null (PP.displayS (PP.renderPretty 1.0 80 (PP.plain doc)) ""))

-- | Render an alias clause for an import.
renderAlias :: Name -> PP.Doc
renderAlias a = PP.text "as" PP.<+> nameDoc a

-- | Render the exposing clause for an import (empty when nothing is exposed).
exposingClause :: Src.Exposing -> PP.Doc
exposingClause Src.Open = PP.text "exposing (..)"
exposingClause (Src.Explicit []) = PP.empty
exposingClause (Src.Explicit exposed) =
  PP.text "exposing (" <> commaSepDocs (map formatExposed exposed) <> PP.text ")"

-- | Format an individual exposed item.
formatExposed :: Src.Exposed -> PP.Doc
formatExposed (Src.Lower locName) = locNameDoc locName
formatExposed (Src.Upper locName privacy) =
  locNameDoc locName <> formatPrivacy privacy
formatExposed (Src.Operator _ name) = parens (nameDoc name)

-- | Format the privacy annotation for an exposed type.
formatPrivacy :: Src.Privacy -> PP.Doc
formatPrivacy Src.Private = PP.empty
formatPrivacy (Src.Public _) = PP.text "(..)"

-- | Format an exposing clause in module declaration position.
--
-- @since 0.19.1
formatExposing :: Src.Exposing -> PP.Doc
formatExposing Src.Open = PP.text "(..)"
formatExposing (Src.Explicit []) = PP.text "()"
formatExposing (Src.Explicit exposed) =
  PP.text "(" <> commaSepDocs (map formatExposed exposed) <> PP.text ")"

-- ---------------------------------------------------------------------------
-- Declaration rendering
-- ---------------------------------------------------------------------------

-- | Render all top-level declarations with interleaved comments.
--
-- Merges declarations and non-doc comments into a single list
-- sorted by source position, so comments appear at their original
-- locations relative to declarations.
renderDeclarations :: FormatConfig -> Src.Module -> PP.Doc
renderDeclarations config (Src.Module _ _ _ _ _ values unions aliases binops effects comments) =
  stackNonEmpty (map snd sortedItems)
  where
    declItems = declsWithRows config values unions aliases binops effects
    commentItems = commentsInRange declRange comments
    declRange = itemRange declItems
    sortedItems = List.sortBy (\(r1, _) (r2, _) -> compare r1 r2) (declItems ++ commentItems)

-- | Build (row, Doc) pairs for all declarations.
declsWithRows ::
  FormatConfig ->
  [Ann.Located Src.Value] ->
  [Ann.Located Src.Union] ->
  [Ann.Located Src.Alias] ->
  [Ann.Located Src.Infix] ->
  Src.Effects ->
  [(Word32, PP.Doc)]
declsWithRows config values unions aliases binops effects =
  map (locatedDoc (formatUnion config)) unions
    ++ map (locatedDoc (formatAlias config)) aliases
    ++ map (locatedDoc formatInfix) binops
    ++ map (locatedDoc (formatValue config)) values
    ++ effectDocs effects

-- | Extract starting row and render a located declaration.
locatedDoc :: (a -> PP.Doc) -> Ann.Located a -> (Word32, PP.Doc)
locatedDoc render (Ann.At (Ann.Region (Ann.Position row _) _) val) =
  (row, render val)

-- | Build (row, Doc) pairs for effect declarations (ports).
effectDocs :: Src.Effects -> [(Word32, PP.Doc)]
effectDocs Src.NoEffects = []
effectDocs (Src.Manager _ _) = []
effectDocs (Src.FFI _) = []
effectDocs (Src.Ports ports) = map portDoc ports

-- | Extract starting row and render a port declaration.
portDoc :: Src.Port -> (Word32, PP.Doc)
portDoc port@(Src.Port (Ann.At (Ann.Region (Ann.Position row _) _) _) _) =
  (row, formatPort port)

-- | Filter comments whose row falls within a given range.
--
-- Returns (row, Doc) pairs for each comment in range, suitable for
-- merging with declaration items and sorting by position.
commentsInRange :: (Word32, Word32) -> [Src.RawComment] -> [(Word32, PP.Doc)]
commentsInRange (lo, hi) =
  map renderPositionedComment . filter (inRange lo hi)

-- | Check whether a comment's row falls within [lo, hi].
inRange :: Word32 -> Word32 -> Src.RawComment -> Bool
inRange lo hi rc = Src._rcRow rc >= lo && Src._rcRow rc <= hi

-- | Convert a 'RawComment' to a positioned Doc.
renderPositionedComment :: Src.RawComment -> (Word32, PP.Doc)
renderPositionedComment rc =
  (Src._rcRow rc, renderRawComment rc)

-- | Render a raw comment to a Doc, restoring its delimiters.
renderRawComment :: Src.RawComment -> PP.Doc
renderRawComment (Src.RawComment Src.LineComment _ _ text) =
  PP.text "--" <> PP.text (bytesToString text)
renderRawComment (Src.RawComment Src.BlockComment _ _ text) =
  PP.text "{-" <> PP.text (bytesToString text) <> PP.text "-}"

-- | Decode a raw ByteString to a String for rendering.
bytesToString :: BS.ByteString -> String
bytesToString = Text.unpack . TE.decodeUtf8

-- | Compute the row range (min, max) of a list of positioned items.
--
-- Returns @(maxBound, 0)@ for empty lists so that no comments match.
itemRange :: [(Word32, a)] -> (Word32, Word32)
itemRange [] = (maxBound, 0)
itemRange items = (minimum rows, maximum rows)
  where
    rows = map fst items

-- | Stack a list of Docs with blank lines, filtering out empty ones.
stackNonEmpty :: [PP.Doc] -> PP.Doc
stackNonEmpty docs =
  PP.vcat (PP.punctuate (PP.line <> PP.line) (List.filter notEmpty docs))
  where
    notEmpty doc = not (null (PP.displayS (PP.renderPretty 1.0 80 (PP.plain doc)) ""))

-- | Format a union type definition.
formatUnion :: FormatConfig -> Src.Union -> PP.Doc
formatUnion config (Src.Union locName params variants) =
  PP.text "type" PP.<+> locNameDoc locName
    <> formatTypeParams params
    <> nlIndent config 1 <> PP.text "= "
    <> joinWith (nlIndent config 1 <> PP.text "| ") (map formatVariant variants)

-- | Join a list of Docs with a separator Doc.
joinWith :: PP.Doc -> [PP.Doc] -> PP.Doc
joinWith _ [] = PP.empty
joinWith sep (d : ds) = foldl (\acc x -> acc <> sep <> x) d ds

-- | Format constructor type parameters for a union type.
formatTypeParams :: [Ann.Located Name] -> PP.Doc
formatTypeParams [] = PP.empty
formatTypeParams ps =
  PP.text " " <> PP.hsep (map locNameDoc ps)

-- | Format a single variant of a union type.
formatVariant :: (Ann.Located Name, [Src.Type]) -> PP.Doc
formatVariant (locName, types) =
  locNameDoc locName <> foldMap (\t -> PP.text " " <> formatTypeArg t) types

-- | Format a type alias definition.
formatAlias :: FormatConfig -> Src.Alias -> PP.Doc
formatAlias config (Src.Alias locName params body) =
  PP.text "type alias" PP.<+> locNameDoc locName
    <> formatTypeParams params
    <> PP.text " =" <> nlIndent config 1 <> formatType body

-- | Format an infix operator declaration.
formatInfix :: Src.Infix -> PP.Doc
formatInfix (Src.Infix opName assoc (Binop.Precedence prec) funcName) =
  PP.text "infix" PP.<+> formatAssoc assoc PP.<+> PP.text (show prec)
    PP.<+> parens (nameDoc opName) PP.<+> PP.text "=" PP.<+> nameDoc funcName

-- | Format associativity keyword.
formatAssoc :: Binop.Associativity -> PP.Doc
formatAssoc Binop.Left  = PP.text "left"
formatAssoc Binop.Right = PP.text "right"
formatAssoc Binop.Non   = PP.text "non"

-- | Format a value / function definition.
formatValue :: FormatConfig -> Src.Value -> PP.Doc
formatValue config (Src.Value locName params body maybeType) =
  typeAnnotation <> definition
  where
    nameD = locNameDoc locName
    typeAnnotation = maybe PP.empty (renderTypeAnnotation nameD) maybeType
    paramText = foldMap (\p -> PP.text " " <> formatPattern p) params
    definition = nameD <> paramText <> PP.text " =" <> nlIndent config 1 <> formatExpr config body

-- | Render a type annotation line for a value definition.
renderTypeAnnotation :: PP.Doc -> Src.Type -> PP.Doc
renderTypeAnnotation nameD t =
  nameD PP.<+> PP.text ":" PP.<+> formatType t <> PP.line

-- | Format the effects portion of a module (ports and FFI declarations).
formatEffects :: Src.Effects -> [PP.Doc]
formatEffects Src.NoEffects     = []
formatEffects (Src.Manager _ _) = []
formatEffects (Src.Ports ports) = map formatPort ports
formatEffects (Src.FFI _)       = []

-- | Format a port declaration.
formatPort :: Src.Port -> PP.Doc
formatPort (Src.Port locName portType) =
  PP.text "port" PP.<+> locNameDoc locName PP.<+> PP.text ":" PP.<+> formatType portType

-- ---------------------------------------------------------------------------
-- Type rendering
-- ---------------------------------------------------------------------------

-- | Format a type annotation.
--
-- @since 0.19.1
formatType :: Src.Type -> PP.Doc
formatType (Ann.At _ typ) = formatType_ typ

-- | Format a type without location wrapper.
formatType_ :: Src.Type_ -> PP.Doc
formatType_ (Src.TLambda a b) =
  formatType a PP.<+> PP.text "->" PP.<+> formatType b
formatType_ (Src.TVar name) = nameDoc name
formatType_ (Src.TType _ name []) = nameDoc name
formatType_ (Src.TType _ name args) =
  nameDoc name PP.<+> PP.hsep (map formatTypeArg args)
formatType_ (Src.TTypeQual _ mod_ name []) =
  nameDoc mod_ <> PP.text "." <> nameDoc name
formatType_ (Src.TTypeQual _ mod_ name args) =
  nameDoc mod_ <> PP.text "." <> nameDoc name
    PP.<+> PP.hsep (map formatTypeArg args)
formatType_ (Src.TRecord fields maybeExt) =
  formatRecordType fields maybeExt
formatType_ Src.TUnit = PP.text "()"
formatType_ (Src.TTuple a b rest) =
  PP.text "( " <> commaSepDocs (map formatType (a : b : rest)) <> PP.text " )"

-- | Format a type argument, adding parentheses around complex types.
formatTypeArg :: Src.Type -> PP.Doc
formatTypeArg t@(Ann.At _ typ) = formatTypeArgInner t typ

-- | Determine whether a type argument needs parenthesising.
formatTypeArgInner :: Src.Type -> Src.Type_ -> PP.Doc
formatTypeArgInner t (Src.TLambda _ _)         = parens (formatType t)
formatTypeArgInner t (Src.TType _ _ (_:_))     = parens (formatType t)
formatTypeArgInner t (Src.TTypeQual _ _ _ (_:_)) = parens (formatType t)
formatTypeArgInner t _                         = formatType t

-- | Format a record type literal.
formatRecordType :: [(Ann.Located Name, Src.Type)] -> Maybe (Ann.Located Name) -> PP.Doc
formatRecordType fields maybeExt =
  PP.text "{ " <> extPrefix <> commaSepDocs (map formatFieldType fields) <> PP.text " }"
  where
    extPrefix = maybe PP.empty (\n -> locNameDoc n <> PP.text " | ") maybeExt

-- | Format a single record field type.
formatFieldType :: (Ann.Located Name, Src.Type) -> PP.Doc
formatFieldType (locName, fieldType) =
  locNameDoc locName PP.<+> PP.text ":" PP.<+> formatType fieldType

-- ---------------------------------------------------------------------------
-- Pattern rendering
-- ---------------------------------------------------------------------------

-- | Format a pattern.
formatPattern :: Src.Pattern -> PP.Doc
formatPattern (Ann.At _ pat) = formatPattern_ pat

-- | Format a pattern without the location wrapper.
formatPattern_ :: Src.Pattern_ -> PP.Doc
formatPattern_ Src.PAnything = PP.text "_"
formatPattern_ (Src.PVar name) = nameDoc name
formatPattern_ (Src.PRecord fields) =
  PP.text "{ " <> commaSepDocs (map locNameDoc fields) <> PP.text " }"
formatPattern_ (Src.PAlias inner locName) =
  formatPattern inner PP.<+> PP.text "as" PP.<+> locNameDoc locName
formatPattern_ Src.PUnit = PP.text "()"
formatPattern_ (Src.PTuple a b rest) =
  PP.text "( " <> commaSepDocs (map formatPattern (a : b : rest)) <> PP.text " )"
formatPattern_ (Src.PCtor _ name []) = nameDoc name
formatPattern_ (Src.PCtor _ name args) =
  nameDoc name PP.<+> PP.hsep (map formatPatternArg args)
formatPattern_ (Src.PCtorQual _ mod_ name []) =
  nameDoc mod_ <> PP.text "." <> nameDoc name
formatPattern_ (Src.PCtorQual _ mod_ name args) =
  nameDoc mod_ <> PP.text "." <> nameDoc name
    PP.<+> PP.hsep (map formatPatternArg args)
formatPattern_ (Src.PList items) =
  PP.text "[ " <> commaSepDocs (map formatPattern items) <> PP.text " ]"
formatPattern_ (Src.PCons hd tl) =
  formatPattern hd PP.<+> PP.text "::" PP.<+> formatPattern tl
formatPattern_ (Src.PChr s) =
  PP.text "'" <> PP.text (ES.toChars s) <> PP.text "'"
formatPattern_ (Src.PStr s) =
  PP.text "\"" <> PP.text (ES.toChars s) <> PP.text "\""
formatPattern_ (Src.PInt n) = PP.text (show n)

-- | Format a constructor pattern argument (add parens around complex patterns).
formatPatternArg :: Src.Pattern -> PP.Doc
formatPatternArg p@(Ann.At _ pat) = formatPatternArgInner p pat

-- | Determine whether a pattern argument needs parenthesising.
formatPatternArgInner :: Src.Pattern -> Src.Pattern_ -> PP.Doc
formatPatternArgInner p (Src.PCtor _ _ (_:_))     = parens (formatPattern p)
formatPatternArgInner p (Src.PCtorQual _ _ _ (_:_)) = parens (formatPattern p)
formatPatternArgInner p (Src.PCons _ _)           = parens (formatPattern p)
formatPatternArgInner p (Src.PAlias _ _)          = parens (formatPattern p)
formatPatternArgInner p _                         = formatPattern p

-- ---------------------------------------------------------------------------
-- Expression rendering
-- ---------------------------------------------------------------------------

-- | Format an expression.
formatExpr :: FormatConfig -> Src.Expr -> PP.Doc
formatExpr config (Ann.At _ expr) = formatExpr_ config expr

-- | Format an expression without the location wrapper.
formatExpr_ :: FormatConfig -> Src.Expr_ -> PP.Doc
formatExpr_ _      (Src.Chr s) = PP.text "'" <> PP.text (ES.toChars s) <> PP.text "'"
formatExpr_ _      (Src.Str s) = PP.text "\"" <> PP.text (ES.toChars s) <> PP.text "\""
formatExpr_ _      (Src.Int n) = PP.text (show n)
formatExpr_ _      (Src.Float f) = floatDoc f
formatExpr_ _      (Src.Var _ name) = nameDoc name
formatExpr_ _      (Src.VarQual _ mod_ name) = nameDoc mod_ <> PP.text "." <> nameDoc name
formatExpr_ config (Src.List items) = formatListExpr config items
formatExpr_ _      (Src.Op name) = parens (nameDoc name)
formatExpr_ config (Src.Negate e) = PP.text "-" <> formatExprArg config e
formatExpr_ config (Src.Binops pairs final) = formatBinops config pairs final
formatExpr_ config (Src.Lambda pats body) = formatLambda config pats body
formatExpr_ config (Src.Call func args) = formatCall config func args
formatExpr_ config (Src.If branches elseBranch) = formatIf config branches elseBranch
formatExpr_ config (Src.Let defs body) = formatLet config defs body
formatExpr_ config (Src.Case subj branches) = formatCase config subj branches
formatExpr_ _      (Src.Accessor name) = PP.text "." <> nameDoc name
formatExpr_ config (Src.Access rec_ locName) =
  formatExprArg config rec_ <> PP.text "." <> locNameDoc locName
formatExpr_ config (Src.Update locName updates) = formatUpdate config locName updates
formatExpr_ config (Src.Record fields) = formatRecord config fields
formatExpr_ _      Src.Unit = PP.text "()"
formatExpr_ config (Src.Tuple a b rest) =
  PP.text "( " <> commaSepDocs (map (formatExpr config) (a : b : rest)) <> PP.text " )"
formatExpr_ _      (Src.Shader _ _) = PP.text "[glsl| ... |]"
formatExpr_ config (Src.Interpolation segments) = formatInterpolation config segments

-- | Format a string interpolation expression.
formatInterpolation :: FormatConfig -> [Src.InterpolationSegment] -> PP.Doc
formatInterpolation config segments =
  PP.text "[i|" <> PP.hcat (map (formatSegment config) segments) <> PP.text "|]"

-- | Format an interpolation segment.
formatSegment :: FormatConfig -> Src.InterpolationSegment -> PP.Doc
formatSegment _config (Src.IStr s) = PP.text (ES.toChars s)
formatSegment config (Src.IExpr expr) =
  PP.text "#{" <> formatExpr config expr <> PP.text "}"

-- | Render a float literal to a Doc via its builder representation.
floatDoc :: EF.Float -> PP.Doc
floatDoc f =
  PP.text (Text.unpack (TE.decodeUtf8 (BL.toStrict (BB.toLazyByteString (EF.toBuilder f)))))

-- | Format a list expression.
formatListExpr :: FormatConfig -> [Src.Expr] -> PP.Doc
formatListExpr config items =
  PP.text "[ " <> commaSepDocs (map (formatExpr config) items) <> PP.text " ]"

-- | Format a lambda expression.
formatLambda :: FormatConfig -> [Src.Pattern] -> Src.Expr -> PP.Doc
formatLambda config pats body =
  PP.text "\\" <> PP.hsep (map formatPattern pats) PP.<+> PP.text "->" PP.<+> formatExpr config body

-- | Format a function call expression.
formatCall :: FormatConfig -> Src.Expr -> [Src.Expr] -> PP.Doc
formatCall config func args =
  formatExprArg config func <> foldMap (\a -> PP.text " " <> formatExprArg config a) args

-- | Wrap an expression in parentheses when it needs them as an argument.
formatExprArg :: FormatConfig -> Src.Expr -> PP.Doc
formatExprArg config e@(Ann.At _ expr) = formatExprArgInner config e expr

-- | Determine whether an expression argument needs parenthesising.
formatExprArgInner :: FormatConfig -> Src.Expr -> Src.Expr_ -> PP.Doc
formatExprArgInner config e (Src.Binops _ _)  = parens (formatExpr config e)
formatExprArgInner config e (Src.Lambda _ _)  = parens (formatExpr config e)
formatExprArgInner config e (Src.If _ _)      = parens (formatExpr config e)
formatExprArgInner config e (Src.Let _ _)     = parens (formatExpr config e)
formatExprArgInner config e (Src.Case _ _)    = parens (formatExpr config e)
formatExprArgInner config e (Src.Call _ (_:_)) = parens (formatExpr config e)
formatExprArgInner config e _                 = formatExpr config e

-- | Format a binary operator chain.
formatBinops :: FormatConfig -> [(Src.Expr, Ann.Located Name)] -> Src.Expr -> PP.Doc
formatBinops config [] final = formatExpr config final
formatBinops config ((lhs, locOp) : rest) final =
  formatExpr config lhs PP.<+> locNameDoc locOp
    PP.<+> formatBinops config rest final

-- | Format an if-then-else expression.
formatIf :: FormatConfig -> [(Src.Expr, Src.Expr)] -> Src.Expr -> PP.Doc
formatIf config [] elseExpr =
  PP.text "else" <> nlIndent config 1 <> formatExpr config elseExpr
formatIf config ((cond, thenExpr) : rest) elseExpr =
  PP.text "if" PP.<+> formatExpr config cond PP.<+> PP.text "then"
    <> nlIndent config 1 <> formatExpr config thenExpr
    <> PP.line <> nlIndent config 0 <> formatIf config rest elseExpr

-- | Format a let-in expression.
formatLet :: FormatConfig -> [Ann.Located Src.Def] -> Src.Expr -> PP.Doc
formatLet config defs body =
  PP.text "let" <> nlIndent config 1
    <> joinWith (nlIndent config 1) (map (formatDef config . Ann.toValue) defs)
    <> PP.line <> PP.text "  in" <> PP.line <> PP.text "  " <> formatExpr config body

-- | Format a local definition inside a let expression.
formatDef :: FormatConfig -> Src.Def -> PP.Doc
formatDef config (Src.Define locName params body maybeType) =
  typeAnn <> locNameDoc locName <> paramText
    <> PP.text " =" <> nlIndent config 2 <> formatExpr config body
  where
    typeAnn = maybe PP.empty (renderDefTypeAnn config locName) maybeType
    paramText = foldMap (\p -> PP.text " " <> formatPattern p) params
formatDef config (Src.Destruct pat body) =
  formatPattern pat <> PP.text " =" <> nlIndent config 2 <> formatExpr config body

-- | Render the type annotation line for a local definition.
renderDefTypeAnn :: FormatConfig -> Ann.Located Name -> Src.Type -> PP.Doc
renderDefTypeAnn config locName t =
  locNameDoc locName PP.<+> PP.text ":" PP.<+> formatType t <> nlIndent config 1

-- | Format a case expression.
formatCase :: FormatConfig -> Src.Expr -> [(Src.Pattern, Src.Expr)] -> PP.Doc
formatCase config subj branches =
  PP.text "case" PP.<+> formatExpr config subj PP.<+> PP.text "of"
    <> nlIndent config 1
    <> joinWith (nlIndent config 1) (map (formatBranch config) branches)

-- | Format a single case branch.
formatBranch :: FormatConfig -> (Src.Pattern, Src.Expr) -> PP.Doc
formatBranch config (pat, body) =
  formatPattern pat PP.<+> PP.text "->"
    <> nlIndent config 2 <> formatExpr config body

-- | Format a record update expression.
formatUpdate :: FormatConfig -> Ann.Located Name -> [(Ann.Located Name, Src.Expr)] -> PP.Doc
formatUpdate config locName updates =
  PP.text "{ " <> locNameDoc locName <> PP.text " | "
    <> commaSepDocs (map (formatFieldUpdate config) updates) <> PP.text " }"

-- | Format a single field update.
formatFieldUpdate :: FormatConfig -> (Ann.Located Name, Src.Expr) -> PP.Doc
formatFieldUpdate config (locName, expr) =
  locNameDoc locName PP.<+> PP.text "=" PP.<+> formatExpr config expr

-- | Format a record literal expression.
formatRecord :: FormatConfig -> [(Ann.Located Name, Src.Expr)] -> PP.Doc
formatRecord _ [] = PP.text "{}"
formatRecord config fields =
  PP.text "{ " <> commaSepDocs (map (formatField config) fields) <> PP.text " }"

-- | Format a single record field assignment.
formatField :: FormatConfig -> (Ann.Located Name, Src.Expr) -> PP.Doc
formatField config (locName, expr) =
  locNameDoc locName PP.<+> PP.text "=" PP.<+> formatExpr config expr
