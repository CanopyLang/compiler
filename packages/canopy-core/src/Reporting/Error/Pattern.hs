{-# LANGUAGE OverloadedStrings #-}

module Reporting.Error.Pattern
  ( PatternMatches.Error (..),
    toDiagnostic,
  )
where

import qualified Canopy.String as ES
import qualified Data.List as List
import Data.Text (Text)
import qualified Nitpick.PatternMatches as PatternMatches
import qualified Reporting.Annotation as Ann
import Reporting.Diagnostic (Diagnostic, LabeledSpan (..), SpanStyle (..))
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Doc as Doc
import qualified Reporting.ErrorCode as EC
import qualified Reporting.Render.Code as Code

-- TO DIAGNOSTIC

-- | Convert a pattern error to a structured 'Diagnostic'.
--
-- @
-- Redundant  -> E0501
-- Incomplete -> E0500
-- @
toDiagnostic :: Code.Source -> PatternMatches.Error -> Diagnostic
toDiagnostic source err =
  case err of
    PatternMatches.Redundant caseRegion patternRegion index ->
      redundantDiagnostic source caseRegion patternRegion index
    PatternMatches.Incomplete region context unhandled ->
      incompleteDiagnostic source region context unhandled

redundantDiagnostic :: Code.Source -> Ann.Region -> Ann.Region -> Int -> Diagnostic
redundantDiagnostic source caseRegion patternRegion index =
  Diag.addSecondarySpan
    (LabeledSpan caseRegion "in this case expression" SpanSecondary)
    ( Diag.makeDiagnostic
        (EC.patternError 1)
        Diag.SWarning
        Diag.PhasePattern
        "REDUNDANT PATTERN"
        "A pattern can never be matched"
        (LabeledSpan patternRegion "this pattern is redundant" SpanPrimary)
        ( Code.toSnippet
            source
            caseRegion
            (Just patternRegion)
            ( Doc.reflow
                ("The " <> Doc.intToOrdinal index <> " pattern is redundant:"),
              Doc.reflow
                "Any value with this shape will be handled by a previous\
                \ pattern, so it should be removed."
            )
        )
    )

incompleteDiagnostic :: Code.Source -> Ann.Region -> PatternMatches.Context -> [PatternMatches.Pattern] -> Diagnostic
incompleteDiagnostic source region context unhandled =
  Diag.makeDiagnostic
    (EC.patternError 0)
    Diag.SError
    Diag.PhasePattern
    (contextTitle context)
    (contextSummary context)
    (LabeledSpan region "incomplete patterns here" SpanPrimary)
    (contextMessage source region context unhandled)

contextTitle :: PatternMatches.Context -> Text
contextTitle PatternMatches.BadArg = "UNSAFE PATTERN"
contextTitle PatternMatches.BadDestruct = "UNSAFE PATTERN"
contextTitle PatternMatches.BadCase = "MISSING PATTERNS"

contextSummary :: PatternMatches.Context -> Text
contextSummary PatternMatches.BadArg = "This pattern does not cover all possibilities"
contextSummary PatternMatches.BadDestruct = "This pattern does not cover all possible values"
contextSummary PatternMatches.BadCase = "This case expression does not have branches for all possibilities"

contextMessage :: Code.Source -> Ann.Region -> PatternMatches.Context -> [PatternMatches.Pattern] -> Doc.Doc
contextMessage source region context unhandled =
  case context of
    PatternMatches.BadArg ->
      Code.toSnippet source region Nothing
        ( "This pattern does not cover all possibilities:",
          Doc.stack
            [ "Other possibilities include:",
              unhandledPatternsToDocBlock unhandled,
              Doc.reflow
                "I would have to crash if I saw one of those! So rather than\
                \ pattern matching in function arguments, put a `case` in\
                \ the function body to account for all possibilities."
            ]
        )
    PatternMatches.BadDestruct ->
      Code.toSnippet source region Nothing
        ( "This pattern does not cover all possible values:",
          Doc.stack
            [ "Other possibilities include:",
              unhandledPatternsToDocBlock unhandled,
              Doc.reflow
                "I would have to crash if I saw one of those! You can use\
                \ `let` to deconstruct values only if there is ONE possibility.\
                \ Switch to a `case` expression to account for all possibilities.",
              Doc.toSimpleHint
                "Are you calling a function that definitely returns values\
                \ with a very specific shape? Try making the return type of\
                \ that function more specific!"
            ]
        )
    PatternMatches.BadCase ->
      Code.toSnippet source region Nothing
        ( "This `case` does not have branches for all possibilities:",
          Doc.stack
            [ "Missing possibilities include:",
              unhandledPatternsToDocBlock unhandled,
              Doc.reflow
                "I would have to crash if I saw one of those. Add branches for them!",
              Doc.link
                "Hint"
                "If you want to write the code for each branch later, use `Debug.todo` as a placeholder. Read"
                "missing-patterns"
                "for more guidance on this workflow."
            ]
        )

-- PATTERN TO DOC

unhandledPatternsToDocBlock :: [PatternMatches.Pattern] -> Doc.Doc
unhandledPatternsToDocBlock unhandledPatterns =
  Doc.indent 4 $
    Doc.dullyellow $
      Doc.vcat $
        map (patternToDoc Unambiguous) unhandledPatterns

data Context
  = Arg
  | Head
  | Unambiguous
  deriving (Eq)

patternToDoc :: Context -> PatternMatches.Pattern -> Doc.Doc
patternToDoc context pattern =
  case delist pattern [] of
    NonList PatternMatches.Anything ->
      "_"
    NonList (PatternMatches.Literal literal) ->
      case literal of
        PatternMatches.Chr chr ->
          "'" <> Doc.fromChars (ES.toChars chr) <> "'"
        PatternMatches.Str str ->
          "\"" <> Doc.fromChars (ES.toChars str) <> "\""
        PatternMatches.Int int ->
          Doc.fromInt int
    NonList (PatternMatches.Ctor _ "#0" []) ->
      "()"
    NonList (PatternMatches.Ctor _ "#2" [a, b]) ->
      "( " <> patternToDoc Unambiguous a
        <> ", "
        <> patternToDoc Unambiguous b
        <> " )"
    NonList (PatternMatches.Ctor _ "#3" [a, b, c]) ->
      "( " <> patternToDoc Unambiguous a
        <> ", "
        <> patternToDoc Unambiguous b
        <> ", "
        <> patternToDoc Unambiguous c
        <> " )"
    NonList (PatternMatches.Ctor _ name args) ->
      let ctorDoc =
            Doc.hsep (Doc.fromName name : map (patternToDoc Arg) args)
       in if context == Arg && length args > 0
            then "(" <> ctorDoc <> ")"
            else ctorDoc
    FiniteList [] ->
      "[]"
    FiniteList entries ->
      let entryDocs = map (patternToDoc Unambiguous) entries
       in "[" <> Doc.hcat (List.intersperse "," entryDocs) <> "]"
    Conses conses finalPattern ->
      let consDoc =
            foldr
              (\hd tl -> patternToDoc Head hd <> " :: " <> tl)
              (patternToDoc Unambiguous finalPattern)
              conses
       in if context == Unambiguous
            then consDoc
            else "(" <> consDoc <> ")"

data Structure
  = FiniteList [PatternMatches.Pattern]
  | Conses [PatternMatches.Pattern] PatternMatches.Pattern
  | NonList PatternMatches.Pattern

delist :: PatternMatches.Pattern -> [PatternMatches.Pattern] -> Structure
delist pattern revEntries =
  case pattern of
    PatternMatches.Ctor _ "[]" [] ->
      FiniteList revEntries
    PatternMatches.Ctor _ "::" [hd, tl] ->
      delist tl (hd : revEntries)
    _ ->
      case revEntries of
        [] ->
          NonList pattern
        _ ->
          Conses (reverse revEntries) pattern
