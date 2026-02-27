{-# LANGUAGE OverloadedStrings #-}

-- | Syntax error rendering for tuple and list expressions.
--
-- This module handles rendering of parse errors for tuple expressions
-- (parenthesized expressions and tuples) and list expressions.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Expression.Sequence
  ( toTupleReport,
    toListReport,
  )
where

import Parse.Primitives (Col, Row)
import Parse.Symbol (BadOperator (..))
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import Reporting.Error.Syntax.Helpers
  ( Context (..),
    Node (..),
    toRegion,
    toSpaceReport,
  )
import Reporting.Error.Syntax.Types
  ( Expr (..),
    List (..),
    Tuple (..),
  )
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report
import Prelude hiding (Char, String)

-- | Type alias for the recursive expression reporter.
type ExprReporter = Code.Source -> Context -> Expr -> Row -> Col -> Report.Report

-- | Render a tuple expression parse error.
--
-- Takes an expression reporter callback to handle recursive expression errors.
toTupleReport :: ExprReporter -> Code.Source -> Context -> Tuple -> Row -> Col -> Report.Report
toTupleReport exprReport source context tuple startRow startCol =
  case tuple of
    TupleExpr expr row col ->
      exprReport source (InNode NParens startRow startCol context) expr row col
    TupleSpace space row col ->
      toSpaceReport source space row col
    TupleEnd row col ->
      toTupleEndReport source startRow startCol row col
    TupleOperatorClose row col ->
      toTupleOperatorCloseReport source startRow startCol row col
    TupleOperatorReserved operator row col ->
      toTupleOperatorReservedReport source operator startRow startCol row col
    TupleIndentExpr1 row col ->
      toTupleIndentExpr1Report source startRow startCol row col
    TupleIndentExprN row col ->
      toTupleIndentExprNReport source startRow startCol row col
    TupleIndentEnd row col ->
      toTupleIndentEndReport source startRow startCol row col

toTupleEndReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toTupleEndReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED PARENTHESES" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I was expecting to see a closing parentheses next, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep ["Try", "adding", "a", Doc.dullyellow ")", "to", "see", "if", "that", "helps?"],
                Doc.toSimpleNote $
                  "I can get stuck when I run into keywords, operators, parentheses, or brackets\
                  \ unexpectedly. So there may be some earlier syntax trouble (like extra parenthesis\
                  \ or missing brackets) that is confusing me."
              ]
          )

toTupleOperatorCloseReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toTupleOperatorCloseReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED OPERATOR FUNCTION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I was expecting a closing parenthesis here:",
            Doc.stack
              [ Doc.fillSep ["Try", "adding", "a", Doc.dullyellow ")", "to", "see", "if", "that", "helps!"],
                Doc.toSimpleNote $
                  "I think I am parsing an operator function right now, so I am expecting to see\
                  \ something like (+) or (&&) where an operator is surrounded by parentheses with\
                  \ no extra spaces."
              ]
          )

toTupleOperatorReservedReport :: Code.Source -> BadOperator -> Row -> Col -> Row -> Col -> Report.Report
toTupleOperatorReservedReport source operator startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNEXPECTED SYMBOL" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I ran into an unexpected symbol here:",
            Doc.fillSep $
              case operator of
                BadDot -> ["Maybe", "you", "wanted", "a", "record", "accessor", "like", Doc.dullyellow ".x", "or", Doc.dullyellow ".name", "instead?"]
                BadPipe -> ["Try", Doc.dullyellow "(||)", "instead?", "To", "turn", "boolean", "OR", "into", "a", "function?"]
                BadArrow -> ["Maybe", "you", "wanted", Doc.dullyellow "(>)", "or", Doc.dullyellow "(>=)", "instead?"]
                BadEquals -> ["Try", Doc.dullyellow "(==)", "instead?", "To", "make", "a", "function", "that", "checks", "equality?"]
                BadHasType -> ["Try", Doc.dullyellow "(::)", "instead?", "To", "add", "values", "to", "the", "front", "of", "lists?"]
          )

toTupleIndentExpr1Report :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toTupleIndentExpr1Report source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED PARENTHESES" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I just saw an open parenthesis, so I was expecting to see an expression next.",
            Doc.stack
              [ Doc.fillSep $
                  [ "Something",
                    "like",
                    Doc.dullyellow "(4 + 5)",
                    "or",
                    Doc.dullyellow "(String.reverse \"desserts\")" <> ".",
                    "Anything",
                    "where",
                    "you",
                    "are",
                    "putting",
                    "parentheses",
                    "around",
                    "normal",
                    "expressions."
                  ],
                Doc.toSimpleNote $
                  "I can get confused by indentation in cases like this, so\
                  \ maybe you have an expression but it is not indented enough?"
              ]
          )

toTupleIndentExprNReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toTupleIndentExprNReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED TUPLE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I think I am in the middle of parsing a tuple. I just saw a comma, so I was expecting to see an expression next.",
            Doc.stack
              [ Doc.fillSep $
                  [ "A",
                    "tuple",
                    "looks",
                    "like",
                    Doc.dullyellow "(3,4)",
                    "or",
                    Doc.dullyellow "(\"Tom\",42)" <> ",",
                    "so",
                    "I",
                    "think",
                    "there",
                    "is",
                    "an",
                    "expression",
                    "missing",
                    "here?"
                  ],
                Doc.toSimpleNote $
                  "I can get confused by indentation in cases like this, so\
                  \ maybe you have an expression but it is not indented enough?"
              ]
          )

toTupleIndentEndReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toTupleIndentEndReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED PARENTHESES" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I was expecting to see a closing parenthesis next:",
            Doc.stack
              [ Doc.fillSep ["Try", "adding", "a", Doc.dullyellow ")", "to", "see", "if", "that", "helps!"],
                Doc.toSimpleNote $
                  "I can get confused by indentation in cases like this, so\
                  \ maybe you have a closing parenthesis but it is not indented enough?"
              ]
          )

-- | Render a list expression parse error.
--
-- Takes an expression reporter callback to handle recursive expression errors.
toListReport :: ExprReporter -> Code.Source -> Context -> List -> Row -> Col -> Report.Report
toListReport exprReport source context list startRow startCol =
  case list of
    ListSpace space row col ->
      toSpaceReport source space row col
    ListOpen row col ->
      toListOpenReport source startRow startCol row col
    ListExpr expr row col ->
      toListExprReport exprReport source context expr startRow startCol row col
    ListEnd row col ->
      toListEndReport source startRow startCol row col
    ListIndentOpen row col ->
      toListIndentOpenReport source startRow startCol row col
    ListIndentEnd row col ->
      toListIndentEndReport source startRow startCol row col
    ListIndentExpr row col ->
      toListIndentExprReport source startRow startCol row col

toListOpenReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toListOpenReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED LIST" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I am partway through parsing a list, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep
                  [ "I",
                    "was",
                    "expecting",
                    "to",
                    "see",
                    "a",
                    "closing",
                    "square",
                    "bracket",
                    "before",
                    "this,",
                    "so",
                    "try",
                    "adding",
                    "a",
                    Doc.dullyellow "]",
                    "and",
                    "see",
                    "if",
                    "that",
                    "helps?"
                  ],
                Doc.toSimpleNote $
                  "When I get stuck like this, it usually means that there is a missing parenthesis\
                  \ or bracket somewhere earlier. It could also be a stray keyword or operator."
              ]
          )

toListExprReport :: ExprReporter -> Code.Source -> Context -> Expr -> Row -> Col -> Row -> Col -> Report.Report
toListExprReport exprReport source context expr startRow startCol row col =
  case expr of
    Start r c ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position r c)
          region = toRegion r c
       in Report.Report "UNFINISHED LIST" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I was expecting to see another list entry after that last comma:",
                Doc.stack
                  [ Doc.reflow $
                      "Trailing commas are not allowed in lists, so the fix may be to delete the comma?",
                    Doc.toSimpleNote
                      "I recommend using the following format for lists that span multiple lines:",
                    Doc.indent 4 $
                      Doc.vcat $
                        [ "[ " <> Doc.dullyellow "\"Alice\"",
                          ", " <> Doc.dullyellow "\"Bob\"",
                          ", " <> Doc.dullyellow "\"Chuck\"",
                          "]"
                        ],
                    Doc.reflow $
                      "Notice that each line starts with some indentation. Usually two or four spaces.\
                      \ This is the stylistic convention in the Canopy ecosystem."
                  ]
              )
    _ ->
      exprReport source (InNode NList startRow startCol context) expr row col

toListEndReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toListEndReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED LIST" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I am partway through parsing a list, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep
                  [ "I",
                    "was",
                    "expecting",
                    "to",
                    "see",
                    "a",
                    "closing",
                    "square",
                    "bracket",
                    "before",
                    "this,",
                    "so",
                    "try",
                    "adding",
                    "a",
                    Doc.dullyellow "]",
                    "and",
                    "see",
                    "if",
                    "that",
                    "helps?"
                  ],
                Doc.toSimpleNote $
                  "When I get stuck like this, it usually means that there is a missing parenthesis\
                  \ or bracket somewhere earlier. It could also be a stray keyword or operator."
              ]
          )

toListIndentOpenReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toListIndentOpenReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED LIST" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I cannot find the end of this list:",
            Doc.stack
              [ Doc.fillSep $
                  [ "You",
                    "could",
                    "change",
                    "it",
                    "to",
                    "something",
                    "like",
                    Doc.dullyellow "[3,4,5]",
                    "or",
                    "even",
                    "just",
                    Doc.dullyellow "[]" <> ".",
                    "Anything",
                    "where",
                    "there",
                    "is",
                    "an",
                    "open",
                    "and",
                    "close",
                    "square",
                    "brace,",
                    "and",
                    "where",
                    "the",
                    "elements",
                    "of",
                    "the",
                    "list",
                    "are",
                    "separated",
                    "by",
                    "commas."
                  ],
                Doc.toSimpleNote
                  "I may be confused by indentation. For example, if you are trying to define\
                  \ a list across multiple lines, I recommend using this format:",
                Doc.indent 4 $
                  Doc.vcat $
                    [ "[ " <> Doc.dullyellow "\"Alice\"",
                      ", " <> Doc.dullyellow "\"Bob\"",
                      ", " <> Doc.dullyellow "\"Chuck\"",
                      "]"
                    ],
                Doc.reflow $
                  "Notice that each line starts with some indentation. Usually two or four spaces.\
                  \ This is the stylistic convention in the Canopy ecosystem."
              ]
          )

toListIndentEndReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toListIndentEndReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED LIST" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I cannot find the end of this list:",
            Doc.stack
              [ Doc.fillSep $
                  [ "You",
                    "can",
                    "just",
                    "add",
                    "a",
                    "closing",
                    Doc.dullyellow "]",
                    "right",
                    "here,",
                    "and",
                    "I",
                    "will",
                    "be",
                    "all",
                    "set!"
                  ],
                Doc.toSimpleNote
                  "I may be confused by indentation. For example, if you are trying to define\
                  \ a list across multiple lines, I recommend using this format:",
                Doc.indent 4 $
                  Doc.vcat $
                    [ "[ " <> Doc.dullyellow "\"Alice\"",
                      ", " <> Doc.dullyellow "\"Bob\"",
                      ", " <> Doc.dullyellow "\"Chuck\"",
                      "]"
                    ],
                Doc.reflow $
                  "Notice that each line starts with some indentation. Usually two or four spaces.\
                  \ This is the stylistic convention in the Canopy ecosystem."
              ]
          )

toListIndentExprReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toListIndentExprReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED LIST" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I was expecting to see another list entry after this comma:",
            Doc.stack
              [ Doc.reflow $
                  "Trailing commas are not allowed in lists, so the fix may be to delete the comma?",
                Doc.toSimpleNote
                  "I recommend using the following format for lists that span multiple lines:",
                Doc.indent 4 $
                  Doc.vcat $
                    [ "[ " <> Doc.dullyellow "\"Alice\"",
                      ", " <> Doc.dullyellow "\"Bob\"",
                      ", " <> Doc.dullyellow "\"Chuck\"",
                      "]"
                    ],
                Doc.reflow $
                  "Notice that each line starts with some indentation. Usually two or four spaces.\
                  \ This is the stylistic convention in the Canopy ecosystem."
              ]
          )
