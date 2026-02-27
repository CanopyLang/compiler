{-# LANGUAGE OverloadedStrings #-}

-- | Reporting.Error.Canonicalize.Diagnostics.Core - Core diagnostic builders
--
-- Contains diagnostic builders for: annotation, ambiguous names, arity,
-- operators, name clashes, effects, exports, imports, not-found, and patterns.
--
-- This is a sub-module of "Reporting.Error.Canonicalize.Diagnostics" and is
-- re-exported from there. Users should import the parent module directly.
--
-- @since 0.19.1
module Reporting.Error.Canonicalize.Diagnostics.Core
  ( -- * Annotation
    annotationTooShortDiagnostic,
    -- * Ambiguous names
    ambiguousNameDiagnostic,
    -- * Arity
    badArityDiagnostic,
    -- * Operators
    binopDiagnostic,
    -- * Name clashes
    nameClashDiagnostic,
    duplicatePatternMessage,
    -- * Effects
    effectNotFoundDiagnostic,
    effectFunctionNotFoundDiagnostic,
    -- * Exports
    exportDuplicateDiagnostic,
    exportNotFoundDiagnostic,
    exportOpenAliasDiagnostic,
    -- * Imports
    importCtorByNameDiagnostic,
    importNotFoundDiagnostic,
    importOpenAliasDiagnostic,
    importExposingNotFoundDiagnostic,
    -- * Not found
    notFoundDiagnostic,
    addNameSuggestions,
    toNameSuggestion,
    notFoundBinopDiagnostic,
    addBinopSuggestions,
    -- * Patterns
    patternHasRecordCtorDiagnostic,
  )
where

import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.OneOrMore as OneOrMore
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Reporting.Annotation as Ann
import Reporting.Diagnostic (Diagnostic, LabeledSpan (..), SpanStyle (..), Suggestion (..), Confidence (..))
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Doc as Doc
import qualified Reporting.Error.Canonicalize.Helpers as Helpers
import qualified Reporting.ErrorCode as EC
import qualified Reporting.Render.Code as Code
import qualified Reporting.Suggest as Suggest

-- ---------------------------------------------------------------------------
-- Annotation
-- ---------------------------------------------------------------------------

-- | Build a diagnostic for a type annotation argument count mismatch.
annotationTooShortDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Index.ZeroBased -> Int -> Diagnostic
annotationTooShortDiagnostic source region name index leftovers =
  Diag.makeDiagnostic
    (EC.canonError 0)
    Diag.SError
    Diag.PhaseCanon
    "BAD TYPE ANNOTATION"
    (Text.pack ("Type annotation for `" <> Name.toChars name <> "` has too few arguments"))
    (LabeledSpan region "annotation argument count mismatch" SpanPrimary)
    (Code.toSnippet source region Nothing (annotationTooShortMessage name numTypeArgs numDefArgs, annotationTooShortHint leftovers))
  where
    numTypeArgs = Index.toMachine index
    numDefArgs = numTypeArgs + leftovers

-- | Format the primary message for an annotation-too-short error.
annotationTooShortMessage :: Name.Name -> Int -> Int -> Doc.Doc
annotationTooShortMessage name numTypeArgs numDefArgs =
  Doc.reflow ("The type annotation for `" <> Name.toChars name <> "` says it can accept " <> Doc.args numTypeArgs <> ", but the definition says it has " <> Doc.args numDefArgs <> ":")

-- | Format the hint for an annotation-too-short error.
annotationTooShortHint :: Int -> Doc.Doc
annotationTooShortHint leftovers =
  Doc.reflow ("Is the type annotation missing something? Should some argument" <> (if leftovers == 1 then "" else "s") <> " be deleted? Maybe some parentheses are missing?")

-- ---------------------------------------------------------------------------
-- Ambiguous names
-- ---------------------------------------------------------------------------

-- | Build a diagnostic for an ambiguous name (variable, type, variant, or operator).
ambiguousNameDiagnostic ::
  Code.Source ->
  Ann.Region ->
  Maybe Name.Name ->
  Name.Name ->
  ModuleName.Canonical ->
  OneOrMore.OneOrMore ModuleName.Canonical ->
  String ->
  Diag.ErrorCode ->
  Diagnostic
ambiguousNameDiagnostic source region maybePrefix name h hs thing code =
  Diag.makeDiagnostic
    code
    Diag.SError
    Diag.PhaseCanon
    "AMBIGUOUS NAME"
    (Text.pack ("Ambiguous " <> thing <> " `" <> Name.toChars name <> "`"))
    (LabeledSpan region (Text.pack ("ambiguous " <> thing)) SpanPrimary)
    (Helpers.extractReportMessage (Helpers.ambiguousName source region maybePrefix name h hs thing))

-- ---------------------------------------------------------------------------
-- Arity
-- ---------------------------------------------------------------------------

-- | Build a diagnostic for an arity mismatch (too few or too many arguments).
badArityDiagnostic :: Code.Source -> Ann.Region -> String -> Name.Name -> Int -> Int -> Diagnostic
badArityDiagnostic source region arityCtxThing name expected actual =
  Diag.makeDiagnostic
    (EC.canonError 5)
    Diag.SError
    Diag.PhaseCanon
    (if actual < expected then "TOO FEW ARGS" else "TOO MANY ARGS")
    (Text.pack (arityCtxThing <> " `" <> Name.toChars name <> "` given wrong number of arguments"))
    (LabeledSpan region "wrong number of arguments" SpanPrimary)
    (badArityMessage source region arityCtxThing name expected actual)

-- | Build the message Doc for a bad-arity error.
badArityMessage :: Code.Source -> Ann.Region -> String -> Name.Name -> Int -> Int -> Doc.Doc
badArityMessage source region arityCtxThing name expected actual =
  let base = Doc.reflow ("The `" <> Name.toChars name <> "` " <> arityCtxThing <> " needs " <> Doc.args expected <> ", but I see " <> show actual <> " instead:")
   in if actual < expected
        then Code.toSnippet source region Nothing (base, Doc.reflow "What is missing? Are some parentheses misplaced?")
        else Code.toSnippet source region Nothing (base, if actual - expected == 1 then "Which is the extra one? Maybe some parentheses are missing?" else "Which are the extra ones? Maybe some parentheses are missing?")

-- ---------------------------------------------------------------------------
-- Operators (infix)
-- ---------------------------------------------------------------------------

-- | Build a diagnostic for mixed infix operators without parentheses.
binopDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Name.Name -> Diagnostic
binopDiagnostic source region op1 op2 =
  Diag.makeDiagnostic
    (EC.canonError 6)
    Diag.SError
    Diag.PhaseCanon
    "INFIX PROBLEM"
    (Text.pack ("Cannot mix (" <> Name.toChars op1 <> ") and (" <> Name.toChars op2 <> ") without parentheses"))
    (LabeledSpan region "mixed operators" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("You cannot mix (" <> Name.toChars op1 <> ") and (" <> Name.toChars op2 <> ") without parentheses."), Doc.reflow "I do not know how to group these expressions. Add parentheses for me!"))

-- ---------------------------------------------------------------------------
-- Name clashes
-- ---------------------------------------------------------------------------

-- | Build a diagnostic for a name clash (duplicate declaration, type, ctor, etc.).
nameClashDiagnostic :: Code.Source -> Ann.Region -> Ann.Region -> Diag.ErrorCode -> String -> Diagnostic
nameClashDiagnostic source r1 r2 code message =
  Diag.makeDiagnostic
    code
    Diag.SError
    Diag.PhaseCanon
    "NAME CLASH"
    (Text.pack message)
    (LabeledSpan r2 "duplicate definition" SpanPrimary)
    (Helpers.extractReportMessage (Helpers.nameClash source r1 r2 message))

-- | Produce the clash message for a duplicate pattern variable.
--
-- Takes a string tag for context to avoid importing the DuplicatePatternContext type.
duplicatePatternMessage :: String -> Name.Name -> Maybe Name.Name -> String
duplicatePatternMessage context name mFuncName =
  case context of
    "lambda" -> "This anonymous function has multiple `" <> Name.toChars name <> "` arguments."
    "func" ->
      case mFuncName of
        Just funcName -> "The `" <> Name.toChars funcName <> "` function has multiple `" <> Name.toChars name <> "` arguments."
        Nothing -> "This function has multiple `" <> Name.toChars name <> "` arguments."
    "case" -> "This `case` pattern has multiple `" <> Name.toChars name <> "` variables."
    "let" -> "This `let` expression defines `" <> Name.toChars name <> "` more than once!"
    _ -> "This pattern contains multiple `" <> Name.toChars name <> "` variables."

-- ---------------------------------------------------------------------------
-- Effects
-- ---------------------------------------------------------------------------

-- | Build a diagnostic for a missing effect type declaration.
effectNotFoundDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
effectNotFoundDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 15)
    Diag.SError
    Diag.PhaseCanon
    "EFFECT PROBLEM"
    (Text.pack ("Effect type `" <> Name.toChars name <> "` not found in this file"))
    (LabeledSpan region "effect type not found" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("You have declared that `" <> (Name.toChars name <> "` is an effect type:")), Doc.reflow ("But I cannot find a custom type named `" <> (Name.toChars name <> "` in this file!"))))

-- | Build a diagnostic for a missing effect function declaration.
effectFunctionNotFoundDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
effectFunctionNotFoundDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 16)
    Diag.SError
    Diag.PhaseCanon
    "EFFECT PROBLEM"
    (Text.pack ("Effect function `" <> Name.toChars name <> "` not defined in this file"))
    (LabeledSpan region "effect function not found" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("This kind of effect module must define a `" <> (Name.toChars name <> "` function.")), Doc.reflow ("But I cannot find `" <> (Name.toChars name <> "` in this file!"))))

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

-- | Build a diagnostic for a duplicated export.
exportDuplicateDiagnostic :: Code.Source -> Name.Name -> Ann.Region -> Ann.Region -> Diagnostic
exportDuplicateDiagnostic source name r1 r2 =
  Diag.makeDiagnostic
    (EC.canonError 17)
    Diag.SError
    Diag.PhaseCanon
    "REDUNDANT EXPORT"
    (Text.pack msg)
    (LabeledSpan r2 "duplicate export" SpanPrimary)
    (Code.toPair source r1 r2 (Doc.reflow msg, "Remove one of them and you should be all set!") (Doc.reflow (msg <> " Once here:"), "And again right here:", "Remove one of them and you should be all set!"))
  where
    msg = "You are trying to expose `" <> Name.toChars name <> "` multiple times!"

-- | Build a diagnostic for an export that references an unknown name.
exportNotFoundDiagnostic :: Code.Source -> Ann.Region -> String -> Name.Name -> [Name.Name] -> Diagnostic
exportNotFoundDiagnostic source region kindStr rawName possibleNames =
  let suggestions = fmap Name.toChars . take 4 $ Suggest.sort (Name.toChars rawName) Name.toChars possibleNames
      (a, thing, name) = Helpers.toKindInfo kindStr rawName
   in Diag.makeDiagnostic
        (EC.canonError 18)
        Diag.SError
        Diag.PhaseCanon
        "UNKNOWN EXPORT"
        (Text.pack ("Cannot find definition for exported name `" <> Name.toChars rawName <> "`"))
        (LabeledSpan region "unknown export" SpanPrimary)
        (buildExportNotFoundMsg source region a thing name suggestions)

-- | Build the message Doc for an export-not-found error.
buildExportNotFoundMsg :: Code.Source -> Ann.Region -> Doc.Doc -> Doc.Doc -> Doc.Doc -> [String] -> Doc.Doc
buildExportNotFoundMsg source region a thing name suggestions =
  Code.toSnippet source region Nothing
    ( Doc.stack
        [ Doc.fillSep
            [ "You", "are", "trying", "to", "expose", a, thing, "named", name, "but", "I", "cannot", "find", "its", "definition."
            ],
          case fmap Doc.fromChars suggestions of
            [] ->
              Doc.reflow "I do not see any super similar names in this file. Is the definition missing?"
            [alt] ->
              Doc.fillSep ["Maybe", "you", "want", Doc.dullyellow alt, "instead?"]
            alts ->
              Doc.stack
                [ "These names seem close though:",
                  Doc.indent 4 . Doc.vcat $ fmap Doc.dullyellow alts
                ]
        ],
      mempty
    )

-- | Build a diagnostic for exposing (..) on a type alias in an export.
exportOpenAliasDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
exportOpenAliasDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 19)
    Diag.SError
    Diag.PhaseCanon
    "BAD EXPORT"
    (Text.pack ("Cannot use (..) with type alias `" <> Name.toChars name <> "`"))
    (LabeledSpan region "open alias in export" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("The (..) syntax is for exposing variants of a custom type. It cannot be used with a type alias like `" <> (Name.toChars name <> "` though.")), Doc.reflow "Remove the (..) and you should be fine!"))

-- ---------------------------------------------------------------------------
-- Imports
-- ---------------------------------------------------------------------------

-- | Build a diagnostic for importing a variant constructor by name directly.
importCtorByNameDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Name.Name -> Diagnostic
importCtorByNameDiagnostic source region ctor tipe =
  Diag.makeDiagnostic
    (EC.canonError 20)
    Diag.SError
    Diag.PhaseCanon
    "BAD IMPORT"
    (Text.pack ("Cannot import variant `" <> Name.toChars ctor <> "` by name; import via its type"))
    (LabeledSpan region "variant imported by name" SpanPrimary)
    (buildImportCtorByNameMsg source region ctor tipe)

-- | Build the message Doc for an import-ctor-by-name error.
buildImportCtorByNameMsg :: Code.Source -> Ann.Region -> Name.Name -> Name.Name -> Doc.Doc
buildImportCtorByNameMsg source region ctor tipe =
  Code.toSnippet source region Nothing
    ( Doc.reflow ("You are trying to import the `" <> Name.toChars ctor <> "` variant by name:"),
      Doc.fillSep
        [ "Try", "importing", Doc.green (Doc.fromName tipe <> "(..)"), "instead.",
          "The", "dots", "mean", "\x201cexpose", "the", Doc.fromName tipe, "type", "and", "all",
          "its", "variants", "so", "it", "gives", "you", "access", "to", Doc.fromName ctor <> "."
        ]
    )

-- | Build a diagnostic for an unknown module import.
importNotFoundDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
importNotFoundDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 21)
    Diag.SError
    Diag.PhaseCanon
    "UNKNOWN IMPORT"
    (Text.pack ("Cannot find module `" <> Name.toChars name <> "`"))
    (LabeledSpan region "module not found" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("I could not find a `" <> Name.toChars name <> "` module to import!"), mempty))

-- | Build a diagnostic for using (..) with a type alias in an import.
importOpenAliasDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
importOpenAliasDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 22)
    Diag.SError
    Diag.PhaseCanon
    "BAD IMPORT"
    (Text.pack ("Cannot use (..) with type alias `" <> Name.toChars name <> "` in import"))
    (LabeledSpan region "open alias in import" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("The `" <> Name.toChars name <> "` type alias cannot be followed by (..) like this:"), Doc.reflow "Remove the (..) and it should work."))

-- | Build a diagnostic for an exposing clause that references an unknown name.
importExposingNotFoundDiagnostic :: Code.Source -> Ann.Region -> ModuleName.Canonical -> Name.Name -> [Name.Name] -> Diagnostic
importExposingNotFoundDiagnostic source region home value possibleNames =
  Diag.makeDiagnostic
    (EC.canonError 23)
    Diag.SError
    Diag.PhaseCanon
    "BAD IMPORT"
    (Text.pack ("Module `" <> Name.toChars homeName <> "` does not expose `" <> Name.toChars value <> "`"))
    (LabeledSpan region "unexposed name" SpanPrimary)
    (buildImportExposingMsg source region home value possibleNames)
  where
    (ModuleName.Canonical _ homeName) = home

-- | Build the message Doc for an import-exposing-not-found error.
buildImportExposingMsg :: Code.Source -> Ann.Region -> ModuleName.Canonical -> Name.Name -> [Name.Name] -> Doc.Doc
buildImportExposingMsg source region (ModuleName.Canonical _ home) value possibleNames =
  let suggestions = fmap Name.toChars . take 4 $ Suggest.sort (Name.toChars home) Name.toChars possibleNames
   in Code.toSnippet source region Nothing
        ( Doc.reflow ("The `" <> Name.toChars home <> "` module does not expose `" <> Name.toChars value <> "`:"),
          case fmap Doc.fromChars suggestions of
            [] -> "I cannot find any super similar exposed names. Maybe it is private?"
            [alt] -> Doc.fillSep ["Maybe", "you", "want", Doc.dullyellow alt, "instead?"]
            alts -> Doc.stack ["These names seem close though:", Doc.indent 4 . Doc.vcat $ fmap Doc.dullyellow alts]
        )

-- ---------------------------------------------------------------------------
-- Not found
-- ---------------------------------------------------------------------------

-- | Build a diagnostic for a name that cannot be resolved.
notFoundDiagnostic ::
  Code.Source ->
  Ann.Region ->
  Maybe Name.Name ->
  Name.Name ->
  String ->
  Set.Set Name.Name ->
  Map.Map Name.Name (Set.Set Name.Name) ->
  Diag.ErrorCode ->
  Diagnostic
notFoundDiagnostic source region maybePrefix name thing locals quals code =
  addNameSuggestions region name locals quals
    ( Diag.makeDiagnostic
        code
        Diag.SError
        Diag.PhaseCanon
        "NAMING ERROR"
        (Text.pack ("Cannot find `" <> givenName <> "` " <> thing))
        (LabeledSpan region (Text.pack (thing <> " not found")) SpanPrimary)
        (Helpers.extractReportMessage (Helpers.notFound source region maybePrefix name thing locals quals))
    )
  where
    givenName = maybe Name.toChars Helpers.toQualString maybePrefix name

-- | Add structured name suggestions from possible names to a diagnostic.
addNameSuggestions :: Ann.Region -> Name.Name -> Set.Set Name.Name -> Map.Map Name.Name (Set.Set Name.Name) -> Diagnostic -> Diagnostic
addNameSuggestions region name locals quals diag =
  foldr Diag.addSuggestion diag (take 3 (fmap (toNameSuggestion region) sorted))
  where
    allNames = Set.toList locals <> concatMap Set.toList (Map.elems quals)
    sorted = Suggest.sort (Name.toChars name) Name.toChars allNames

-- | Convert a suggested name into a structured Suggestion.
toNameSuggestion :: Ann.Region -> Name.Name -> Suggestion
toNameSuggestion region suggested =
  Suggestion
    region
    (Text.pack (Name.toChars suggested))
    (Text.pack ("Did you mean `" <> Name.toChars suggested <> "`?"))
    Likely

-- | Build a diagnostic for an unknown binary operator.
notFoundBinopDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Set.Set Name.Name -> Diagnostic
notFoundBinopDiagnostic source region op locals =
  addBinopSuggestions region op locals
    ( Diag.makeDiagnostic
        (EC.canonError 27)
        Diag.SError
        Diag.PhaseCanon
        "UNKNOWN OPERATOR"
        (Text.pack ("Unknown operator (" <> Name.toChars op <> ")"))
        (LabeledSpan region "unknown operator" SpanPrimary)
        (buildNotFoundBinopMsg source region op locals)
    )

-- | Build the message Doc for a not-found-binop error.
buildNotFoundBinopMsg :: Code.Source -> Ann.Region -> Name.Name -> Set.Set Name.Name -> Doc.Doc
buildNotFoundBinopMsg source region op locals =
  let suggestions = fmap Name.toChars . take 2 $ Suggest.sort (Name.toChars op) Name.toChars (Set.toList locals)
      format altOp = Doc.green ("(" <> altOp <> ")")
   in Code.toSnippet source region Nothing
        ( Doc.reflow ("I do not recognize the (" <> Name.toChars op <> ") operator."),
          Doc.fillSep
            ( ["Is", "there", "an", "`import`", "and", "`exposing`", "entry", "for", "it?"]
                <> case fmap Doc.fromChars suggestions of
                  [] -> []
                  alts -> ["Maybe", "you", "want"] <> (Doc.commaSep "or" format alts <> ["instead?"])
            )
        )

-- | Add structured suggestions for operators.
addBinopSuggestions :: Ann.Region -> Name.Name -> Set.Set Name.Name -> Diagnostic -> Diagnostic
addBinopSuggestions region op locals diag =
  foldr Diag.addSuggestion diag (take 2 (fmap (toNameSuggestion region) sorted))
  where
    sorted = Suggest.sort (Name.toChars op) Name.toChars (Set.toList locals)

-- ---------------------------------------------------------------------------
-- Patterns
-- ---------------------------------------------------------------------------

-- | Build a diagnostic for using a record constructor in a pattern.
patternHasRecordCtorDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
patternHasRecordCtorDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 28)
    Diag.SError
    Diag.PhaseCanon
    "BAD PATTERN"
    (Text.pack ("Record constructor `" <> Name.toChars name <> "` cannot be used in a pattern"))
    (LabeledSpan region "record ctor in pattern" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("You can construct records by using `" <> Name.toChars name <> "` as a function, but it is not available in pattern matching like this:"), Doc.reflow "I recommend matching the record as a variable and unpacking it later."))
