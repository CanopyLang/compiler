{-# LANGUAGE OverloadedStrings #-}

-- | Syntax error rendering for pattern matching.
--
-- This module handles rendering of parse errors for patterns, including
-- record patterns, tuple patterns, and list patterns.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Pattern
  ( PContext (..),
    toPatternReport,
    toPRecordReport,
    toUnfinishRecordPatternReport,
    toPTupleReport,
    toPListReport,
  )
where

import qualified Data.Char as Char
import qualified Canopy.Data.Name as Name
import Parse.Primitives (Col, Row)
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import Reporting.Error.Syntax.Helpers
  ( toKeywordRegion,
    toRegion,
    toSpaceReport,
    toWiderRegion,
  )
import Reporting.Error.Syntax.Literal
  ( toCharReport,
    toNumberReport,
    toStringReport,
  )
import Reporting.Error.Syntax.Types
  ( PList (..),
    PRecord (..),
    PTuple (..),
    Pattern (..),
  )
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report

-- | Context describing where a pattern appears.
data PContext
  = PCase
  | PArg
  | PLet

-- | Render a pattern parse error.
toPatternReport :: Code.Source -> PContext -> Pattern -> Row -> Col -> Report.Report
toPatternReport source context pattern startRow startCol =
  case pattern of
    PRecord record row col ->
      toPRecordReport source record row col
    PTuple tuple row col ->
      toPTupleReport source context tuple row col
    PList list row col ->
      toPListReport source context list row col
    PStart row col ->
      case Code.whatIsNext source row col of
        Code.Keyword keyword ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toKeywordRegion row col keyword
              inThisThing =
                case context of
                  PArg -> "as an argument"
                  PCase -> "in this pattern"
                  PLet -> "in this pattern"
           in Report.Report "RESERVED WORD" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( Doc.reflow $
                      "It looks like you are trying to use `" ++ keyword ++ "` " ++ inThisThing ++ ":",
                    Doc.reflow $
                      "This is a reserved word! Try using some other name?"
                  )
        Code.Operator "-" ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toRegion row col
           in Report.Report "UNEXPECTED SYMBOL" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( Doc.reflow $
                      "I ran into a minus sign unexpectedly in this pattern:",
                    Doc.reflow $
                      "It is not possible to pattern match on negative numbers at this\
                      \ time. Try using an `if` expression for that sort of thing for now."
                  )
        _ ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toRegion row col
           in Report.Report "PROBLEM IN PATTERN" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( Doc.reflow $
                      "I wanted to parse a pattern next, but I got stuck here:",
                    Doc.fillSep $
                      [ "I",
                        "am",
                        "not",
                        "sure",
                        "why",
                        "I",
                        "am",
                        "getting",
                        "stuck",
                        "exactly.",
                        "I",
                        "just",
                        "know",
                        "that",
                        "I",
                        "want",
                        "a",
                        "pattern",
                        "next.",
                        "Something",
                        "as",
                        "simple",
                        "as",
                        Doc.dullyellow "maybeHeight",
                        "or",
                        Doc.dullyellow "result",
                        "would",
                        "work!"
                      ]
                  )
    PChar char row col ->
      toCharReport source char row col
    PString string row col ->
      toStringReport source string row col
    PNumber number row col ->
      toNumberReport source number row col
    PFloat width row col ->
      let region = toWiderRegion row col width
       in Report.Report "UNEXPECTED PATTERN" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow $
                  "I cannot pattern match with floating point numbers:",
                Doc.fillSep $
                  [ "Equality",
                    "on",
                    "floats",
                    "can",
                    "be",
                    "unreliable,",
                    "so",
                    "you",
                    "usually",
                    "want",
                    "to",
                    "check",
                    "that",
                    "they",
                    "are",
                    "nearby",
                    "with",
                    "some",
                    "sort",
                    "of",
                    Doc.dullyellow "(abs (actual - expected) < 0.001)",
                    "check."
                  ]
              )
    PAlias row col ->
      let region = toRegion row col
       in Report.Report "UNFINISHED PATTERN" region [] $
            Code.toSnippet source region Nothing $
              ( Doc.reflow $
                  "I was expecting to see a variable name after the `as` keyword:",
                Doc.stack
                  [ Doc.fillSep $
                      [ "The",
                        "`as`",
                        "keyword",
                        "lets",
                        "you",
                        "write",
                        "patterns",
                        "like",
                        "((" <> Doc.dullyellow "x" <> "," <> Doc.dullyellow "y" <> ") " <> Doc.cyan "as" <> Doc.dullyellow " point" <> ")",
                        "so",
                        "you",
                        "can",
                        "refer",
                        "to",
                        "individual",
                        "parts",
                        "of",
                        "the",
                        "tuple",
                        "with",
                        Doc.dullyellow "x",
                        "and",
                        Doc.dullyellow "y",
                        "or",
                        "you",
                        "refer",
                        "to",
                        "the",
                        "whole",
                        "thing",
                        "with",
                        Doc.dullyellow "point" <> "."
                      ],
                    Doc.reflow $
                      "So I was expecting to see a variable name after the `as` keyword here. Sometimes\
                      \ people just want to use `as` as a variable name though. Try using a different name\
                      \ in that case!"
                  ]
              )
    PWildcardNotVar name width row col ->
      let region = toWiderRegion row col (fromIntegral width)
          examples =
            case dropWhile (== '_') (Name.toChars name) of
              [] -> [Doc.dullyellow "x", "or", Doc.dullyellow "age"]
              c : cs -> [Doc.dullyellow (Doc.fromChars (Char.toLower c : cs))]
       in Report.Report "UNEXPECTED NAME" region [] $
            Code.toSnippet source region Nothing $
              ( Doc.reflow $
                  "Variable names cannot start with underscores like this:",
                Doc.fillSep $
                  [ "You",
                    "can",
                    "either",
                    "have",
                    "an",
                    "underscore",
                    "like",
                    Doc.dullyellow "_",
                    "to",
                    "ignore",
                    "the",
                    "value,",
                    "or",
                    "you",
                    "can",
                    "have",
                    "a",
                    "name",
                    "like"
                  ]
                    ++ examples
                    ++ ["to", "use", "the", "matched", "value."]
              )
    PSpace space row col ->
      toSpaceReport source space row col
    PIndentStart row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED PATTERN" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I wanted to parse a pattern next, but I got stuck here:",
                Doc.stack
                  [ Doc.fillSep $
                      [ "I",
                        "am",
                        "not",
                        "sure",
                        "why",
                        "I",
                        "am",
                        "getting",
                        "stuck",
                        "exactly.",
                        "I",
                        "just",
                        "know",
                        "that",
                        "I",
                        "want",
                        "a",
                        "pattern",
                        "next.",
                        "Something",
                        "as",
                        "simple",
                        "as",
                        Doc.dullyellow "maybeHeight",
                        "or",
                        Doc.dullyellow "result",
                        "would",
                        "work!"
                      ],
                    Doc.toSimpleNote $
                      "I can get confused by indentation. If you think there is a pattern next, maybe\
                      \ it needs to be indented a bit more?"
                  ]
              )
    PIndentAlias row col ->
      let region = toRegion row col
       in Report.Report "UNFINISHED PATTERN" region [] $
            Code.toSnippet source region Nothing $
              ( Doc.reflow $
                  "I was expecting to see a variable name after the `as` keyword:",
                Doc.stack
                  [ Doc.fillSep $
                      [ "The",
                        "`as`",
                        "keyword",
                        "lets",
                        "you",
                        "write",
                        "patterns",
                        "like",
                        "((" <> Doc.dullyellow "x" <> "," <> Doc.dullyellow "y" <> ") " <> Doc.cyan "as" <> Doc.dullyellow " point" <> ")",
                        "so",
                        "you",
                        "can",
                        "refer",
                        "to",
                        "individual",
                        "parts",
                        "of",
                        "the",
                        "tuple",
                        "with",
                        Doc.dullyellow "x",
                        "and",
                        Doc.dullyellow "y",
                        "or",
                        "you",
                        "refer",
                        "to",
                        "the",
                        "whole",
                        "thing",
                        "with",
                        Doc.dullyellow "point."
                      ],
                    Doc.reflow $
                      "So I was expecting to see a variable name after the `as` keyword here. Sometimes\
                      \ people just want to use `as` as a variable name though. Try using a different name\
                      \ in that case!"
                  ]
              )

-- | Render a record pattern parse error.
toPRecordReport :: Code.Source -> PRecord -> Row -> Col -> Report.Report
toPRecordReport source record startRow startCol =
  case record of
    PRecordOpen row col ->
      toUnfinishRecordPatternReport source row col startRow startCol $
        Doc.reflow "I was expecting to see a field name next."
    PRecordEnd row col ->
      toUnfinishRecordPatternReport source row col startRow startCol $
        Doc.fillSep
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
            "adding",
            "a",
            Doc.dullyellow "}",
            "here?"
          ]
    PRecordField row col ->
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
                      "I was not expecting to see `" ++ keyword ++ "` as a record field name:",
                    Doc.reflow $
                      "This is a reserved word, not available for variable names. Try another name!"
                  )
        _ ->
          toUnfinishRecordPatternReport source row col startRow startCol $
            Doc.reflow "I was expecting to see a field name next."
    PRecordSpace space row col ->
      toSpaceReport source space row col
    PRecordIndentOpen row col ->
      toUnfinishRecordPatternReport source row col startRow startCol $
        Doc.reflow "I was expecting to see a field name next."
    PRecordIndentEnd row col ->
      toUnfinishRecordPatternReport source row col startRow startCol $
        Doc.fillSep
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
            "adding",
            "a",
            Doc.dullyellow "}",
            "here?"
          ]
    PRecordIndentField row col ->
      toUnfinishRecordPatternReport source row col startRow startCol $
        Doc.reflow "I was expecting to see a field name next."

-- | Render an unfinished record pattern error.
toUnfinishRecordPatternReport :: Code.Source -> Row -> Col -> Row -> Col -> Doc.Doc -> Report.Report
toUnfinishRecordPatternReport source row col startRow startCol message =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED RECORD PATTERN" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I was partway through parsing a record pattern, but I got stuck here:",
            Doc.stack
              [ message,
                Doc.toFancyHint $
                  [ "A",
                    "record",
                    "pattern",
                    "looks",
                    "like",
                    Doc.dullyellow "{x,y}",
                    "or",
                    Doc.dullyellow "{name,age}",
                    "where",
                    "you",
                    "list",
                    "the",
                    "field",
                    "names",
                    "you",
                    "want",
                    "to",
                    "access."
                  ]
              ]
          )

-- | Render a tuple pattern parse error.
toPTupleReport :: Code.Source -> PContext -> PTuple -> Row -> Col -> Report.Report
toPTupleReport source context tuple startRow startCol =
  case tuple of
    PTupleOpen row col ->
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
                      "It looks like you are trying to use `" ++ keyword ++ "` as a variable name:",
                    Doc.reflow $
                      "This is a reserved word! Try using some other name?"
                  )
        _ ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toRegion row col
           in Report.Report "UNFINISHED PARENTHESES" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( Doc.reflow $
                      "I just saw an open parenthesis, but I got stuck here:",
                    Doc.fillSep
                      [ "I",
                        "was",
                        "expecting",
                        "to",
                        "see",
                        "a",
                        "pattern",
                        "next.",
                        "Maybe",
                        "it",
                        "will",
                        "end",
                        "up",
                        "being",
                        "something",
                        "like",
                        Doc.dullyellow "(x,y)",
                        "or",
                        Doc.dullyellow "(name, _)" <> "?"
                      ]
                  )
    PTupleEnd row col ->
      case Code.whatIsNext source row col of
        Code.Keyword keyword ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toKeywordRegion row col keyword
           in Report.Report "RESERVED WORD" region [] $
                Code.toSnippet source surroundings (Just region) $
                  ( Doc.reflow $
                      "I ran into a reserved word in this pattern:",
                    Doc.reflow $
                      "The `" ++ keyword ++ "` keyword is reserved. Try using a different name instead!"
                  )
        Code.Operator op ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toKeywordRegion row col op
           in Report.Report "UNEXPECTED SYMBOL" region [] $
                Code.toSnippet source surroundings (Just region) $
                  ( Doc.reflow $
                      "I ran into the " ++ op ++ " symbol unexpectedly in this pattern:",
                    Doc.reflow $
                      "Only the :: symbol that works in patterns. It is useful if you\
                      \ are pattern matching on lists, trying to get the first element\
                      \ off the front. Did you want that instead?"
                  )
        Code.Close term bracket ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toRegion row col
           in Report.Report ("STRAY " ++ map Char.toUpper term) region [] $
                Code.toSnippet source surroundings (Just region) $
                  ( Doc.reflow $
                      "I ran into a an unexpected " ++ term ++ " in this pattern:",
                    Doc.reflow $
                      "This " ++ bracket : " does not match up with an earlier open " ++ term ++ ". Try deleting it?"
                  )
        _ ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toRegion row col
           in Report.Report "UNFINISHED PARENTHESES" region [] $
                Code.toSnippet source surroundings (Just region) $
                  ( Doc.reflow $
                      "I was partway through parsing a pattern, but I got stuck here:",
                    Doc.fillSep
                      [ "I",
                        "was",
                        "expecting",
                        "a",
                        "closing",
                        "parenthesis",
                        "next,",
                        "so",
                        "try",
                        "adding",
                        "a",
                        Doc.dullyellow ")",
                        "to",
                        "see",
                        "if",
                        "that",
                        "helps?"
                      ]
                  )
    PTupleExpr pattern row col ->
      toPatternReport source context pattern row col
    PTupleSpace space row col ->
      toSpaceReport source space row col
    PTupleIndentEnd row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED PARENTHESES" region [] $
            Code.toSnippet source surroundings (Just region) $
              ( Doc.reflow $
                  "I was expecting a closing parenthesis next:",
                Doc.stack
                  [ Doc.fillSep ["Try", "adding", "a", Doc.dullyellow ")", "to", "see", "if", "that", "helps?"],
                    Doc.toSimpleNote $
                      "I can get confused by indentation in cases like this, so\
                      \ maybe you have a closing parenthesis but it is not indented enough?"
                  ]
              )
    PTupleIndentExpr1 row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED PARENTHESES" region [] $
            Code.toSnippet source surroundings (Just region) $
              ( Doc.reflow $
                  "I just saw an open parenthesis, but then I got stuck here:",
                Doc.fillSep
                  [ "I",
                    "was",
                    "expecting",
                    "to",
                    "see",
                    "a",
                    "pattern",
                    "next.",
                    "Maybe",
                    "it",
                    "will",
                    "end",
                    "up",
                    "being",
                    "something",
                    "like",
                    Doc.dullyellow "(x,y)",
                    "or",
                    Doc.dullyellow "(name, _)" <> "?"
                  ]
              )
    PTupleIndentExprN row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED TUPLE PATTERN" region [] $
            Code.toSnippet source surroundings (Just region) $
              ( Doc.reflow $
                  "I am partway through parsing a tuple pattern, but I got stuck here:",
                Doc.stack
                  [ Doc.fillSep
                      [ "I",
                        "was",
                        "expecting",
                        "to",
                        "see",
                        "a",
                        "pattern",
                        "next.",
                        "I",
                        "am",
                        "expecting",
                        "the",
                        "final",
                        "result",
                        "to",
                        "be",
                        "something",
                        "like",
                        Doc.dullyellow "(x,y)",
                        "or",
                        Doc.dullyellow "(name, _)" <> "."
                      ],
                    Doc.toSimpleNote $
                      "I can get confused by indentation in cases like this, so the problem\
                      \ may be that the next part is not indented enough?"
                  ]
              )

-- | Render a list pattern parse error.
toPListReport :: Code.Source -> PContext -> PList -> Row -> Col -> Report.Report
toPListReport source context list startRow startCol =
  case list of
    PListOpen row col ->
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
                      "It looks like you are trying to use `" ++ keyword ++ "` to name an element of a list:",
                    Doc.reflow $
                      "This is a reserved word though! Try using some other name?"
                  )
        _ ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toRegion row col
           in Report.Report "UNFINISHED LIST PATTERN" region [] $
                Code.toSnippet source surroundings (Just region) $
                  ( Doc.reflow $
                      "I just saw an open square bracket, but then I got stuck here:",
                    Doc.fillSep ["Try", "adding", "a", Doc.dullyellow "]", "to", "see", "if", "that", "helps?"]
                  )
    PListEnd row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED LIST PATTERN" region [] $
            Code.toSnippet source surroundings (Just region) $
              ( Doc.reflow $
                  "I was expecting a closing square bracket to end this list pattern:",
                Doc.fillSep ["Try", "adding", "a", Doc.dullyellow "]", "to", "see", "if", "that", "helps?"]
              )
    PListExpr pattern row col ->
      toPatternReport source context pattern row col
    PListSpace space row col ->
      toSpaceReport source space row col
    PListIndentOpen row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED LIST PATTERN" region [] $
            Code.toSnippet source surroundings (Just region) $
              ( Doc.reflow $
                  "I just saw an open square bracket, but then I got stuck here:",
                Doc.stack
                  [ Doc.fillSep ["Try", "adding", "a", Doc.dullyellow "]", "to", "see", "if", "that", "helps?"],
                    Doc.toSimpleNote $
                      "I can get confused by indentation in cases like this, so\
                      \ maybe there is something next, but it is not indented enough?"
                  ]
              )
    PListIndentEnd row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED LIST PATTERN" region [] $
            Code.toSnippet source surroundings (Just region) $
              ( Doc.reflow $
                  "I was expecting a closing square bracket to end this list pattern:",
                Doc.stack
                  [ Doc.fillSep ["Try", "adding", "a", Doc.dullyellow "]", "to", "see", "if", "that", "helps?"],
                    Doc.toSimpleNote $
                      "I can get confused by indentation in cases like this, so\
                      \ maybe you have a closing square bracket but it is not indented enough?"
                  ]
              )
    PListIndentExpr row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED LIST PATTERN" region [] $
            Code.toSnippet source surroundings (Just region) $
              ( Doc.reflow $
                  "I am partway through parsing a list pattern, but I got stuck here:",
                Doc.stack
                  [ Doc.reflow $
                      "I was expecting to see another pattern next. Maybe a variable name.",
                    Doc.toSimpleNote $
                      "I can get confused by indentation in cases like this, so\
                      \ maybe there is more to this pattern but it is not indented enough?"
                  ]
              )
