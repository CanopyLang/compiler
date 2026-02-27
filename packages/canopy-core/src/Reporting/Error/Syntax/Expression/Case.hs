{-# LANGUAGE OverloadedStrings #-}

-- | Syntax error rendering for case expressions.
--
-- This module handles rendering of parse errors for case expressions,
-- including pattern matching branches, case-of keyword errors, and
-- indentation issues.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Expression.Case
  ( toCaseReport,
    toUnfinishCaseReport,
  )
where

import Parse.Primitives (Col, Row)
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import Reporting.Error.Syntax.Helpers
  ( Context (..),
    Node (..),
    noteForCaseError,
    noteForCaseIndentError,
    toKeywordRegion,
    toRegion,
    toSpaceReport,
  )
import Reporting.Error.Syntax.Pattern
  ( PContext (..),
    toPatternReport,
  )
import Reporting.Error.Syntax.Types
  ( Case (..),
    Expr (..),
  )
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report
import Prelude hiding (Char, String)

-- | Type alias for the recursive expression reporter.
type ExprReporter = Code.Source -> Context -> Expr -> Row -> Col -> Report.Report

-- | Render a case expression parse error.
--
-- Takes an expression reporter callback to handle recursive expression errors.
toCaseReport :: ExprReporter -> Code.Source -> Context -> Case -> Row -> Col -> Report.Report
toCaseReport exprReport source context case_ startRow startCol =
  case case_ of
    CaseSpace space row col ->
      toSpaceReport source space row col
    CaseOf row col ->
      toUnfinishCaseReport source row col startRow startCol $
        Doc.fillSep ["I", "was", "expecting", "to", "see", "the", Doc.dullyellow "of", "keyword", "next."]
    CasePattern pattern row col ->
      toPatternReport source PCase pattern row col
    CaseArrow row col ->
      toCaseArrowReport source startRow startCol row col
    CaseExpr expr row col ->
      exprReport source (InNode NCase startRow startCol context) expr row col
    CaseBranch expr row col ->
      exprReport source (InNode NBranch startRow startCol context) expr row col
    CaseIndentOf row col ->
      toUnfinishCaseReport source row col startRow startCol $
        Doc.fillSep ["I", "was", "expecting", "to", "see", "the", Doc.dullyellow "of", "keyword", "next."]
    CaseIndentExpr row col ->
      toUnfinishCaseReport source row col startRow startCol $
        Doc.reflow "I was expecting to see a expression next."
    CaseIndentPattern row col ->
      toUnfinishCaseReport source row col startRow startCol $
        Doc.reflow "I was expecting to see a pattern next."
    CaseIndentArrow row col ->
      toUnfinishCaseReport source row col startRow startCol $
        Doc.fillSep
          [ "I",
            "just",
            "saw",
            "a",
            "pattern,",
            "so",
            "I",
            "was",
            "expecting",
            "to",
            "see",
            "a",
            Doc.dullyellow "->",
            "next."
          ]
    CaseIndentBranch row col ->
      toUnfinishCaseReport source row col startRow startCol $
        Doc.reflow $
          "I was expecting to see an expression next. What should I do when\
          \ I run into this particular pattern?"
    CasePatternAlignment indent row col ->
      toUnfinishCaseReport source row col startRow startCol $
        Doc.reflow $
          "I suspect this is a pattern that is not indented far enough? (" ++ show indent ++ " spaces)"

toCaseArrowReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toCaseArrowReport source startRow startCol row col =
  case Code.whatIsNext source row col of
    Code.Keyword keyword ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toKeywordRegion row col keyword
       in Report.Report "RESERVED WORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I am partway through parsing a `case` expression, but I got stuck here:",
                Doc.reflow $
                  "It looks like you are trying to use `" ++ keyword
                    ++ "` in one of your\
                       \ patterns, but it is a reserved word. Try using a different name?"
              )
    Code.Operator ":" ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNEXPECTED OPERATOR" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I am partway through parsing a `case` expression, but I got stuck here:",
                Doc.fillSep $
                  [ "I",
                    "am",
                    "seeing",
                    Doc.dullyellow ":",
                    "but",
                    "maybe",
                    "you",
                    "want",
                    Doc.green "::",
                    "instead?",
                    "For",
                    "pattern",
                    "matching",
                    "on",
                    "lists?"
                  ]
              )
    Code.Operator "=" ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNEXPECTED OPERATOR" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I am partway through parsing a `case` expression, but I got stuck here:",
                Doc.fillSep $
                  [ "I",
                    "am",
                    "seeing",
                    Doc.dullyellow "=",
                    "but",
                    "maybe",
                    "you",
                    "want",
                    Doc.green "->",
                    "instead?"
                  ]
              )
    _ ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "MISSING ARROW" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I am partway through parsing a `case` expression, but I got stuck here:",
                Doc.stack
                  [ Doc.reflow "I was expecting to see an arrow next.",
                    noteForCaseIndentError
                  ]
              )

-- | Render an unfinished case expression error.
toUnfinishCaseReport :: Code.Source -> Row -> Col -> Row -> Col -> Doc.Doc -> Report.Report
toUnfinishCaseReport source row col startRow startCol message =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED CASE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I was partway through parsing a `case` expression, but I got stuck here:",
            Doc.stack
              [ message,
                noteForCaseError
              ]
          )
