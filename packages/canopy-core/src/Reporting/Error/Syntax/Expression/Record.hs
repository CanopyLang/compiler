{-# LANGUAGE OverloadedStrings #-}

-- | Syntax error rendering for record expressions.
--
-- This module handles rendering of parse errors for record expressions,
-- including field name errors, missing equals signs, and indentation issues.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Expression.Record
  ( toRecordReport,
  )
where

import Parse.Primitives (Col, Row)
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import Reporting.Error.Syntax.Helpers
  ( Context (..),
    Node (..),
    toKeywordRegion,
    toRegion,
    toSpaceReport,
  )
import Reporting.Error.Syntax.Types
  ( Expr (..),
    Record (..),
  )
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report
import Prelude hiding (Char, String)

-- | Type alias for the recursive expression reporter.
type ExprReporter = Code.Source -> Context -> Expr -> Row -> Col -> Report.Report

-- | Render a record expression parse error.
--
-- Takes an expression reporter callback to handle recursive expression errors.
toRecordReport :: ExprReporter -> Code.Source -> Context -> Record -> Row -> Col -> Report.Report
toRecordReport exprReport source context record startRow startCol =
  case record of
    RecordOpen row col ->
      toRecordOpenReport source startRow startCol row col
    RecordEnd row col ->
      toRecordEndReport source startRow startCol row col
    RecordField row col ->
      toRecordFieldReport source startRow startCol row col
    RecordEquals row col ->
      toRecordEqualsReport source startRow startCol row col
    RecordExpr expr row col ->
      exprReport source (InNode NRecord startRow startCol context) expr row col
    RecordSpace space row col ->
      toSpaceReport source space row col
    RecordIndentOpen row col ->
      toRecordIndentOpenReport source startRow startCol row col
    RecordIndentEnd row col ->
      toRecordIndentEndReport source startRow startCol row col
    RecordIndentField row col ->
      toRecordIndentFieldReport source startRow startCol row col
    RecordIndentEquals row col ->
      toRecordIndentEqualsReport source startRow startCol row col
    RecordIndentExpr row col ->
      toRecordIndentExprReport source startRow startCol row col

toRecordOpenReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toRecordOpenReport source startRow startCol row col =
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
                  "I just started parsing a record, but I got stuck on this field name:",
                Doc.reflow $
                  "It looks like you are trying to use `" ++ keyword
                    ++ "` as a field name, but \
                       \ that is a reserved word. Try using a different name!"
              )
    _ ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "PROBLEM IN RECORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I just started parsing a record, but I got stuck here:",
                Doc.stack
                  [ Doc.fillSep
                      [ "I",
                        "was",
                        "expecting",
                        "to",
                        "see",
                        "a",
                        "record",
                        "field",
                        "defined",
                        "next,",
                        "so",
                        "I",
                        "am",
                        "looking",
                        "for",
                        "a",
                        "name",
                        "like",
                        Doc.dullyellow "userName",
                        "or",
                        Doc.dullyellow "plantHeight" <> "."
                      ],
                    Doc.toSimpleNote $
                      "Field names must start with a lower-case letter. After that, you can use\
                      \ any sequence of letters, numbers, and underscores.",
                    noteForRecordError
                  ]
              )

toRecordEndReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toRecordEndReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "PROBLEM IN RECORD" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I am partway through parsing a record, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep
                  [ "I",
                    "was",
                    "expecting",
                    "to",
                    "see",
                    "a",
                    "closing",
                    "curly",
                    "brace",
                    "before",
                    "this,",
                    "so",
                    "try",
                    "adding",
                    "a",
                    Doc.dullyellow "}",
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

toRecordFieldReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toRecordFieldReport source startRow startCol row col =
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
                  "I am partway through parsing a record, but I got stuck on this field name:",
                Doc.reflow $
                  "It looks like you are trying to use `" ++ keyword
                    ++ "` as a field name, but \
                       \ that is a reserved word. Try using a different name!"
              )
    Code.Other (Just ',') ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "EXTRA COMMA" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I am partway through parsing a record, but I got stuck here:",
                Doc.stack
                  [ Doc.reflow $
                      "I am seeing two commas in a row. This is the second one!",
                    Doc.reflow $
                      "Just delete one of the commas and you should be all set!",
                    noteForRecordError
                  ]
              )
    Code.Close _ '}' ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "EXTRA COMMA" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I am partway through parsing a record, but I got stuck here:",
                Doc.stack
                  [ Doc.reflow $
                      "Trailing commas are not allowed in records. Try deleting the comma that appears\
                      \ before this closing curly brace.",
                    noteForRecordError
                  ]
              )
    _ ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "PROBLEM IN RECORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I am partway through parsing a record, but I got stuck here:",
                Doc.stack
                  [ Doc.fillSep
                      [ "I",
                        "was",
                        "expecting",
                        "to",
                        "see",
                        "another",
                        "record",
                        "field",
                        "defined",
                        "next,",
                        "so",
                        "I",
                        "am",
                        "looking",
                        "for",
                        "a",
                        "name",
                        "like",
                        Doc.dullyellow "userName",
                        "or",
                        Doc.dullyellow "plantHeight" <> "."
                      ],
                    Doc.toSimpleNote $
                      "Field names must start with a lower-case letter. After that, you can use\
                      \ any sequence of letters, numbers, and underscores.",
                    noteForRecordError
                  ]
              )

toRecordEqualsReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toRecordEqualsReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "PROBLEM IN RECORD" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I am partway through parsing a record, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep $
                  [ "I",
                    "just",
                    "saw",
                    "a",
                    "field",
                    "name,",
                    "so",
                    "I",
                    "was",
                    "expecting",
                    "to",
                    "see",
                    "an",
                    "equals",
                    "sign",
                    "next.",
                    "So",
                    "try",
                    "putting",
                    "an",
                    Doc.green "=",
                    "sign",
                    "here?"
                  ],
                noteForRecordError
              ]
          )

toRecordIndentOpenReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toRecordIndentOpenReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED RECORD" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I just saw the opening curly brace of a record, but then I got stuck here:",
            Doc.stack
              [ Doc.fillSep $
                  [ "I",
                    "am",
                    "expecting",
                    "a",
                    "record",
                    "like",
                    Doc.dullyellow "{ x = 3, y = 4 }",
                    "here.",
                    "Try",
                    "defining",
                    "some",
                    "fields",
                    "of",
                    "your",
                    "own?"
                  ],
                noteForRecordIndentError
              ]
          )

toRecordIndentEndReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toRecordIndentEndReport source startRow startCol row col =
  case Code.nextLineStartsWithCloseCurly source row of
    Just (curlyRow, curlyCol) ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position curlyRow curlyCol)
          region = toRegion curlyRow curlyCol
       in Report.Report "NEED MORE INDENTATION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I was partway through parsing a record, but I got stuck here:",
                Doc.stack
                  [ Doc.reflow $
                      "I need this curly brace to be indented more. Try adding some spaces before it!",
                    noteForRecordError
                  ]
              )
    Nothing ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED RECORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I was partway through parsing a record, but I got stuck here:",
                Doc.stack
                  [ Doc.fillSep $
                      [ "I",
                        "was",
                        "expecting",
                        "to",
                        "see",
                        "a",
                        "closing",
                        "curly",
                        "brace",
                        "next.",
                        "Try",
                        "putting",
                        "a",
                        Doc.green "}",
                        "next",
                        "and",
                        "see",
                        "if",
                        "that",
                        "helps?"
                      ],
                    noteForRecordIndentError
                  ]
              )

toRecordIndentFieldReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toRecordIndentFieldReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED RECORD" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I am partway through parsing a record, but I got stuck after that last comma:",
            Doc.stack
              [ Doc.reflow $
                  "Trailing commas are not allowed in records, so the fix may be to\
                  \ delete that last comma? Or maybe you were in the middle of defining\
                  \ an additional field?",
                noteForRecordError
              ]
          )

toRecordIndentEqualsReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toRecordIndentEqualsReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED RECORD" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I am partway through parsing a record. I just saw a record\
              \ field, so I was expecting to see an equals sign next:",
            Doc.stack
              [ Doc.fillSep $
                  [ "Try",
                    "putting",
                    "an",
                    Doc.green "=",
                    "followed",
                    "by",
                    "an",
                    "expression?"
                  ],
                noteForRecordIndentError
              ]
          )

toRecordIndentExprReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toRecordIndentExprReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED RECORD" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I am partway through parsing a record, and I was expecting to run into an expression next:",
            Doc.stack
              [ Doc.fillSep $
                  [ "Try",
                    "putting",
                    "something",
                    "like",
                    Doc.dullyellow "42",
                    "or",
                    Doc.dullyellow "\"hello\"",
                    "for",
                    "now?"
                  ],
                noteForRecordIndentError
              ]
          )

-- | Documentation note for record expression formatting errors.
noteForRecordError :: Doc.Doc
noteForRecordError =
  Doc.stack $
    [ Doc.toSimpleNote
        "If you are trying to define a record across multiple lines, I recommend using this format:",
      Doc.indent 4 $
        Doc.vcat $
          [ "{ name = " <> Doc.dullyellow "\"Alice\"",
            ", age = " <> Doc.dullyellow "42",
            ", height = " <> Doc.dullyellow "1.75",
            "}"
          ],
      Doc.reflow $
        "Notice that each line starts with some indentation. Usually two or four spaces.\
        \ This is the stylistic convention in the Canopy ecosystem."
    ]

-- | Documentation note for record expression indentation errors.
noteForRecordIndentError :: Doc.Doc
noteForRecordIndentError =
  Doc.stack
    [ Doc.toSimpleNote
        "I may be confused by indentation. For example, if you are trying to define\
        \ a record across multiple lines, I recommend using this format:",
      Doc.indent 4 $
        Doc.vcat $
          [ "{ name = " <> Doc.dullyellow "\"Alice\"",
            ", age = " <> Doc.dullyellow "42",
            ", height = " <> Doc.dullyellow "1.75",
            "}"
          ],
      Doc.reflow $
        "Notice that each line starts with some indentation. Usually two or four spaces.\
        \ This is the stylistic convention in the Canopy ecosystem!"
    ]
