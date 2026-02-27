{-# LANGUAGE OverloadedStrings #-}

-- | Syntax error rendering for if expressions.
--
-- This module handles rendering of parse errors for if-then-else expressions,
-- including missing branches, wrong keywords, and indentation issues.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Expression.If
  ( toIfReport,
  )
where

import Parse.Primitives (Col, Row)
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import Reporting.Error.Syntax.Helpers
  ( Context (..),
    Node (..),
    toRegion,
    toSpaceReport,
    toWiderRegion,
  )
import Reporting.Error.Syntax.Types
  ( Expr (..),
    If (..),
  )
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report
import Prelude hiding (Char, String)

-- | Type alias for the recursive expression reporter.
type ExprReporter = Code.Source -> Context -> Expr -> Row -> Col -> Report.Report

-- | Render an if expression parse error.
--
-- Takes an expression reporter callback to handle recursive expression errors.
toIfReport :: ExprReporter -> Code.Source -> Context -> If -> Row -> Col -> Report.Report
toIfReport exprReport source context if_ startRow startCol =
  case if_ of
    IfSpace space row col ->
      toSpaceReport source space row col
    IfThen row col ->
      toIfThenReport source startRow startCol row col
    IfElse row col ->
      toIfElseReport source startRow startCol row col
    IfElseBranchStart row col ->
      toIfElseBranchStartReport source startRow startCol row col
    IfCondition expr row col ->
      exprReport source (InNode NCond startRow startCol context) expr row col
    IfThenBranch expr row col ->
      exprReport source (InNode NThen startRow startCol context) expr row col
    IfElseBranch expr row col ->
      exprReport source (InNode NElse startRow startCol context) expr row col
    IfIndentCondition row col ->
      toIfIndentConditionReport source startRow startCol row col
    IfIndentThen row col ->
      toIfIndentThenReport source startRow startCol row col
    IfIndentThenBranch row col ->
      toIfIndentThenBranchReport source startRow startCol row col
    IfIndentElseBranch row col ->
      toIfIndentElseBranchReport source startRow startCol row col
    IfIndentElse row col ->
      toIfIndentElseReport source startRow startCol row col

toIfThenReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toIfThenReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED IF" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I was expecting to see more of this `if` expression, but I got stuck here:",
            Doc.fillSep $
              [ "I",
                "was",
                "expecting",
                "to",
                "see",
                "the",
                Doc.cyan "then",
                "keyword",
                "next."
              ]
          )

toIfElseReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toIfElseReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED IF" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I was expecting to see more of this `if` expression, but I got stuck here:",
            Doc.fillSep $
              [ "I",
                "was",
                "expecting",
                "to",
                "see",
                "the",
                Doc.cyan "else",
                "keyword",
                "next."
              ]
          )

toIfElseBranchStartReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toIfElseBranchStartReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED IF" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I just saw the start of an `else` branch, but then I got stuck here:",
            Doc.reflow $
              "I was expecting to see an expression next. Maybe it is not filled in yet?"
          )

toIfIndentConditionReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toIfIndentConditionReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED IF" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I was expecting to see more of this `if` expression, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep $
                  [ "I",
                    "was",
                    "expecting",
                    "to",
                    "see",
                    "an",
                    "expression",
                    "like",
                    Doc.dullyellow "x < 0",
                    "that",
                    "evaluates",
                    "to",
                    "True",
                    "or",
                    "False."
                  ],
                Doc.toSimpleNote $
                  "I can be confused by indentation. Maybe something is not indented enough?"
              ]
          )

toIfIndentThenReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toIfIndentThenReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED IF" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I was expecting to see more of this `if` expression, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep $
                  [ "I",
                    "was",
                    "expecting",
                    "to",
                    "see",
                    "the",
                    Doc.cyan "then",
                    "keyword",
                    "next."
                  ],
                Doc.toSimpleNote $
                  "I can be confused by indentation. Maybe something is not indented enough?"
              ]
          )

toIfIndentThenBranchReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toIfIndentThenBranchReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED IF" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I got stuck after the start of this `then` branch:",
            Doc.stack
              [ Doc.reflow $
                  "I was expecting to see an expression next. Maybe it is not filled in yet?",
                Doc.toSimpleNote $
                  "I can be confused by indentation, so if the `then` branch is already\
                  \ present, it may not be indented enough for me to recognize it."
              ]
          )

toIfIndentElseBranchReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toIfIndentElseBranchReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED IF" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I got stuck after the start of this `else` branch:",
            Doc.stack
              [ Doc.reflow $
                  "I was expecting to see an expression next. Maybe it is not filled in yet?",
                Doc.toSimpleNote $
                  "I can be confused by indentation, so if the `else` branch is already\
                  \ present, it may not be indented enough for me to recognize it."
              ]
          )

toIfIndentElseReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toIfIndentElseReport source startRow startCol row col =
  case Code.nextLineStartsWithKeyword "else" source row of
    Just (elseRow, elseCol) ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position elseRow elseCol)
          region = toWiderRegion elseRow elseCol 4
       in Report.Report "WEIRD ELSE BRANCH" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I was partway through an `if` expression when I got stuck here:",
                Doc.fillSep $
                  [ "I",
                    "think",
                    "this",
                    Doc.cyan "else",
                    "keyword",
                    "needs",
                    "to",
                    "be",
                    "indented",
                    "more.",
                    "Try",
                    "adding",
                    "some",
                    "spaces",
                    "before",
                    "it."
                  ]
              )
    Nothing ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED IF" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I was expecting to see an `else` branch after this:",
                Doc.stack
                  [ Doc.fillSep
                      [ "I",
                        "know",
                        "what",
                        "to",
                        "do",
                        "when",
                        "the",
                        "condition",
                        "is",
                        "True,",
                        "but",
                        "what",
                        "happens",
                        "when",
                        "it",
                        "is",
                        "False?",
                        "Add",
                        "an",
                        Doc.cyan "else",
                        "branch",
                        "to",
                        "handle",
                        "that",
                        "scenario!"
                      ]
                  ]
              )
