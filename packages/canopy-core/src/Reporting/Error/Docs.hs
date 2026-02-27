{-# LANGUAGE OverloadedStrings #-}

module Reporting.Error.Docs
  ( Error (..),
    SyntaxProblem (..),
    NameProblem (..),
    DefProblem (..),
    toDiagnostics,
  )
where

import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.NonEmptyList as NE
import qualified Data.Text as Text
import Parse.Primitives (Col, Row)
import Parse.Symbol (BadOperator (..))
import qualified Reporting.Annotation as Ann
import Reporting.Diagnostic (Diagnostic, LabeledSpan (..), SpanStyle (..))
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Doc as Doc
import qualified Reporting.Error.Syntax as SyntaxError
import qualified Reporting.ErrorCode as EC
import qualified Reporting.Render.Code as Code

data Error
  = NoDocs Ann.Region
  | ImplicitExposing Ann.Region
  | SyntaxProblem SyntaxProblem
  | NameProblems (NE.List NameProblem)
  | DefProblems (NE.List DefProblem)
  deriving (Show)

data SyntaxProblem
  = Op Row Col
  | OpBad BadOperator Row Col
  | Name Row Col
  | Space SyntaxError.Space Row Col
  | Comma Row Col
  | BadEnd Row Col
  deriving (Show)

data NameProblem
  = NameDuplicate Name.Name Ann.Region Ann.Region
  | NameOnlyInDocs Name.Name Ann.Region
  | NameOnlyInExports Name.Name Ann.Region
  deriving (Show)

data DefProblem
  = NoComment Name.Name Ann.Region
  | NoAnnotation Name.Name Ann.Region
  deriving (Show)

-- TO DIAGNOSTICS

-- | Convert a docs error to structured 'Diagnostic' values.
--
-- @
-- NoDocs           -> E0700
-- ImplicitExposing -> E0701
-- SyntaxProblem    -> E0702
-- NameProblems     -> E0703
-- DefProblems      -> E0704
-- @
toDiagnostics :: Code.Source -> Error -> NE.List Diagnostic
toDiagnostics source err =
  case err of
    NoDocs region ->
      NE.singleton (noDocsDiagnostic source region)
    ImplicitExposing region ->
      NE.singleton (implicitExposingDiagnostic source region)
    SyntaxProblem problem ->
      NE.singleton (toSyntaxProblemDiagnostic source problem)
    NameProblems problems ->
      fmap (toNameProblemDiagnostic source) problems
    DefProblems problems ->
      fmap (toDefProblemDiagnostic source) problems

noDocsDiagnostic :: Code.Source -> Ann.Region -> Diagnostic
noDocsDiagnostic source region =
  Diag.makeDiagnostic
    (EC.docsError 0)
    Diag.SError
    Diag.PhaseDocs
    "NO DOCS"
    "Module documentation is missing"
    (LabeledSpan region "documentation required here" SpanPrimary)
    ( Code.toSnippet source region Nothing
        ( Doc.reflow
            "You must have a documentation comment between the module\
            \ declaration and the imports.",
          Doc.reflow
            "Learn more at <https://package.canopy-lang.org/help/documentation-format>"
        )
    )

implicitExposingDiagnostic :: Code.Source -> Ann.Region -> Diagnostic
implicitExposingDiagnostic source region =
  Diag.makeDiagnostic
    (EC.docsError 1)
    Diag.SError
    Diag.PhaseDocs
    "IMPLICIT EXPOSING"
    "Module uses implicit exposing"
    (LabeledSpan region "implicit exposing list" SpanPrimary)
    ( Code.toSnippet source region Nothing
        ( Doc.reflow "I need you to be explicit about what this module exposes:",
          Doc.reflow
            "A great API usually hides some implementation details, so it is rare that\
            \ everything in the file should be exposed. And requiring package authors\
            \ to be explicit about this is a way of adding another quality check before\
            \ code gets published. So as you write out the public API, ask yourself if\
            \ it will be easy to understand as people read the documentation!"
        )
    )

toSyntaxProblemDiagnostic :: Code.Source -> SyntaxProblem -> Diagnostic
toSyntaxProblemDiagnostic source problem =
  case problem of
    Op row col ->
      syntaxDiagnostic source row col "I am trying to parse an operator like (+) or (*) but something is going wrong."
    OpBad _ row col ->
      syntaxDiagnostic source row col
        "I am trying to parse an operator like (+) or (*) but it looks like you are using\
        \ a reserved symbol in this case."
    Name row col ->
      syntaxDiagnostic source row col "I was expecting to see the name of another exposed value from this module."
    Space _space row col ->
      syntaxDiagnostic source row col "I ran into a whitespace problem while parsing module documentation."
    Comma row col ->
      syntaxDiagnostic source row col "I was expecting to see a comma next."
    BadEnd row col ->
      syntaxDiagnostic source row col
        "I reached an unexpected point while parsing the @docs block. Check that\
        \ every entry is a valid exposed name separated by commas, and that the\
        \ block is properly terminated."

syntaxDiagnostic :: Code.Source -> Row -> Col -> String -> Diagnostic
syntaxDiagnostic source row col details =
  Diag.makeDiagnostic
    (EC.docsError 2)
    Diag.SError
    Diag.PhaseDocs
    "PROBLEM IN DOCS"
    "Documentation has a syntax problem"
    (LabeledSpan region "syntax error here" SpanPrimary)
    ( Code.toSnippet source region Nothing
        ( Doc.reflow "I was partway through parsing your module documentation, but I got stuck here:",
          Doc.stack
            [ Doc.reflow details,
              Doc.toSimpleHint
                "Read through <https://package.canopy-lang.org/help/documentation-format> for\
                \ tips on how to write module documentation!"
            ]
        )
    )
  where
    region = toRegion row col

toNameProblemDiagnostic :: Code.Source -> NameProblem -> Diagnostic
toNameProblemDiagnostic _source problem =
  case problem of
    NameDuplicate name _r1 r2 ->
      Diag.makeDiagnostic
        (EC.docsError 3)
        Diag.SError
        Diag.PhaseDocs
        "DUPLICATE DOCS"
        (Text.pack ("Duplicate documentation for `" <> Name.toChars name <> "`"))
        (LabeledSpan r2 (Text.pack ("duplicate `" <> Name.toChars name <> "`")) SpanPrimary)
        ( Doc.stack
            [ Doc.reflow
                ( "There can only be one `" <> Name.toChars name
                    <> "` in your module documentation, but it is listed twice:"
                ),
              "Remove one of them!"
            ]
        )
    NameOnlyInDocs name region ->
      Diag.makeDiagnostic
        (EC.docsError 3)
        Diag.SError
        Diag.PhaseDocs
        "DOCS MISTAKE"
        (Text.pack ("`" <> Name.toChars name <> "` is documented but not exported"))
        (LabeledSpan region (Text.pack ("`" <> Name.toChars name <> "` not in exposing list")) SpanPrimary)
        ( Doc.stack
            [ Doc.reflow
                ( "I do not see `" <> Name.toChars name
                    <> "` in the `exposing` list, but it is in your module documentation:"
                ),
              Doc.reflow
                ( "Does it need to be added to the `exposing` list as well? Or maybe you removed `"
                    <> Name.toChars name
                    <> "` and forgot to delete it here?"
                )
            ]
        )
    NameOnlyInExports name region ->
      Diag.makeDiagnostic
        (EC.docsError 3)
        Diag.SError
        Diag.PhaseDocs
        "DOCS MISTAKE"
        (Text.pack ("`" <> Name.toChars name <> "` is exported but not documented"))
        (LabeledSpan region (Text.pack ("`" <> Name.toChars name <> "` not documented")) SpanPrimary)
        ( Doc.stack
            [ Doc.reflow
                ( "I do not see `" <> Name.toChars name
                    <> "` in your module documentation, but it is in your `exposing` list:"
                ),
              Doc.reflow
                ("Add a line like `@docs " <> Name.toChars name <> "` to your module documentation!"),
              Doc.link "Note" "See" "docs" "for more guidance on writing high quality docs."
            ]
        )

toDefProblemDiagnostic :: Code.Source -> DefProblem -> Diagnostic
toDefProblemDiagnostic source problem =
  case problem of
    NoComment name region ->
      Diag.makeDiagnostic
        (EC.docsError 4)
        Diag.SError
        Diag.PhaseDocs
        "NO DOCS"
        (Text.pack ("The `" <> Name.toChars name <> "` definition has no documentation"))
        (LabeledSpan region (Text.pack ("`" <> Name.toChars name <> "` needs documentation")) SpanPrimary)
        ( Code.toSnippet source region Nothing
            ( Doc.reflow
                ("The `" <> Name.toChars name <> "` definition does not have a documentation comment."),
              Doc.stack
                [ Doc.reflow "Add documentation with nice examples of how to use it!",
                  Doc.link "Note" "Read" "docs" "for more advice on writing great docs. There are a couple important tricks!"
                ]
            )
        )
    NoAnnotation name region ->
      Diag.makeDiagnostic
        (EC.docsError 4)
        Diag.SError
        Diag.PhaseDocs
        "NO TYPE ANNOTATION"
        (Text.pack ("The `" <> Name.toChars name <> "` definition has no type annotation"))
        (LabeledSpan region (Text.pack ("`" <> Name.toChars name <> "` needs a type annotation")) SpanPrimary)
        ( Code.toSnippet source region Nothing
            ( Doc.reflow
                ("The `" <> Name.toChars name <> "` definition does not have a type annotation."),
              Doc.stack
                [ Doc.reflow
                    "I use the type variable names from your annotations when generating docs. So if\
                    \ you say `Html msg` in your type annotation, I can use `msg` in the docs and make\
                    \ them a bit clearer. So add an annotation and try to use nice type variables!",
                  Doc.link "Note" "Read" "docs" "for more advice on writing great docs. There are a couple important tricks!"
                ]
            )
        )

-- HELPERS

toRegion :: Row -> Col -> Ann.Region
toRegion row col =
  let pos = Ann.Position row col
   in Ann.Region pos pos
