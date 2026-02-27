{-# LANGUAGE OverloadedStrings #-}

-- | Syntax error rendering for type annotations and type declarations.
--
-- This module handles rendering of parse errors for type annotations,
-- record types, and tuple types. It covers errors encountered while
-- parsing type expressions in annotations, aliases, custom types, and ports.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Type
  ( TContext (..),
    toTypeReport,
    toTRecordReport,
    toTTupleReport,
    noteForRecordTypeError,
    noteForRecordTypeIndentError,
  )
where

import qualified Data.Char as Char
import qualified Data.Name as Name
import Parse.Primitives (Col, Row)
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import Reporting.Error.Syntax.Helpers
  ( toKeywordRegion,
    toRegion,
    toSpaceReport,
  )
import Reporting.Error.Syntax.Types
  ( TRecord (..),
    TTuple (..),
    Type (..),
  )
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report
import Prelude hiding (Char, String)

-- | Context describing where a type annotation appears.
data TContext
  = TC_Annotation Name.Name
  | TC_CustomType
  | TC_TypeAlias
  | TC_Port

-- | Render a type expression parse error.
toTypeReport :: Code.Source -> TContext -> Type -> Row -> Col -> Report.Report
toTypeReport source context tipe startRow startCol =
  case tipe of
    TRecord record row col ->
      toTRecordReport source context record row col
    TTuple tuple row col ->
      toTTupleReport source context tuple row col
    TStart row col ->
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
                      "I was expecting to see a type next, but I got stuck on this reserved word:",
                    Doc.reflow $
                      "It looks like you are trying to use `" ++ keyword
                        ++ "` as a type variable, but \
                           \ it is a reserved word. Try using a different name!"
                  )
        _ ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toRegion row col

              thing =
                case context of
                  TC_Annotation _ -> "type annotation"
                  TC_CustomType -> "custom type"
                  TC_TypeAlias -> "type alias"
                  TC_Port -> "port"

              something =
                case context of
                  TC_Annotation name -> "the `" ++ Name.toChars name ++ "` type annotation"
                  TC_CustomType -> "a custom type"
                  TC_TypeAlias -> "a type alias"
                  TC_Port -> "a port"
           in Report.Report ("PROBLEM IN " ++ map Char.toUpper thing) region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( Doc.reflow $
                      "I was partway through parsing " ++ something ++ ", but I got stuck here:",
                    Doc.fillSep $
                      [ "I",
                        "was",
                        "expecting",
                        "to",
                        "see",
                        "a",
                        "type",
                        "next.",
                        "Try",
                        "putting",
                        Doc.dullyellow "Int",
                        "or",
                        Doc.dullyellow "String",
                        "for",
                        "now?"
                      ]
                  )
    TSpace space row col ->
      toSpaceReport source space row col
    TIndentStart row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col

          thing =
            case context of
              TC_Annotation _ -> "type annotation"
              TC_CustomType -> "custom type"
              TC_TypeAlias -> "type alias"
              TC_Port -> "port"
       in Report.Report ("UNFINISHED " ++ map Char.toUpper thing) region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I was partway through parsing a " ++ thing ++ ", but I got stuck here:",
                Doc.stack
                  [ Doc.fillSep $
                      [ "I",
                        "was",
                        "expecting",
                        "to",
                        "see",
                        "a",
                        "type",
                        "next.",
                        "Try",
                        "putting",
                        Doc.dullyellow "Int",
                        "or",
                        Doc.dullyellow "String",
                        "for",
                        "now?"
                      ],
                    Doc.toSimpleNote $
                      "I can get confused by indentation. If you think there is already a type\
                      \ next, maybe it is not indented enough?"
                  ]
              )

-- | Render a record type parse error.
toTRecordReport :: Code.Source -> TContext -> TRecord -> Row -> Col -> Report.Report
toTRecordReport source context record startRow startCol =
  case record of
    TRecordOpen row col ->
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
                      "I just started parsing a record type, but I got stuck on this field name:",
                    Doc.reflow $
                      "It looks like you are trying to use `" ++ keyword
                        ++ "` as a field name, but \
                           \ that is a reserved word. Try using a different name!"
                  )
        _ ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toRegion row col
           in Report.Report "UNFINISHED RECORD TYPE" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( Doc.reflow $
                      "I just started parsing a record type, but I got stuck here:",
                    Doc.fillSep
                      [ "Record",
                        "types",
                        "look",
                        "like",
                        Doc.dullyellow "{ name : String, age : Int },",
                        "so",
                        "I",
                        "was",
                        "expecting",
                        "to",
                        "see",
                        "a",
                        "field",
                        "name",
                        "next."
                      ]
                  )
    TRecordEnd row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED RECORD TYPE" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I am partway through parsing a record type, but I got stuck here:",
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
    TRecordField row col ->
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
                      "I am partway through parsing a record type, but I got stuck on this field name:",
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
                      "I am partway through parsing a record type, but I got stuck here:",
                    Doc.stack
                      [ Doc.reflow $
                          "I am seeing two commas in a row. This is the second one!",
                        Doc.reflow $
                          "Just delete one of the commas and you should be all set!",
                        noteForRecordTypeError
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
                      "I am partway through parsing a record type, but I got stuck here:",
                    Doc.stack
                      [ Doc.reflow $
                          "Trailing commas are not allowed in record types. Try deleting the comma that\
                          \ appears before this closing curly brace.",
                        noteForRecordTypeError
                      ]
                  )
        _ ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toRegion row col
           in Report.Report "PROBLEM IN RECORD TYPE" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( Doc.reflow $
                      "I am partway through parsing a record type, but I got stuck here:",
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
                        noteForRecordTypeError
                      ]
                  )
    TRecordColon row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED RECORD TYPE" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I am partway through parsing a record type, but I got stuck here:",
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
                        "a",
                        "colon",
                        "next.",
                        "So",
                        "try",
                        "putting",
                        "an",
                        Doc.green ":",
                        "sign",
                        "here?"
                      ],
                    noteForRecordTypeError
                  ]
              )
    TRecordType tipe row col ->
      toTypeReport source context tipe row col
    TRecordSpace space row col ->
      toSpaceReport source space row col
    TRecordIndentOpen row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED RECORD TYPE" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I just saw the opening curly brace of a record type, but then I got stuck here:",
                Doc.stack
                  [ Doc.fillSep $
                      [ "I",
                        "am",
                        "expecting",
                        "a",
                        "record",
                        "like",
                        Doc.dullyellow "{ name : String, age : Int }",
                        "here.",
                        "Try",
                        "defining",
                        "some",
                        "fields",
                        "of",
                        "your",
                        "own?"
                      ],
                    noteForRecordTypeIndentError
                  ]
              )
    TRecordIndentEnd row col ->
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
                      "I was partway through parsing a record type, but I got stuck here:",
                    Doc.stack
                      [ Doc.reflow $
                          "I need this curly brace to be indented more. Try adding some spaces before it!",
                        noteForRecordTypeError
                      ]
                  )
        Nothing ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toRegion row col
           in Report.Report "UNFINISHED RECORD TYPE" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( Doc.reflow $
                      "I was partway through parsing a record type, but I got stuck here:",
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
                        noteForRecordTypeIndentError
                      ]
                  )
    TRecordIndentField row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED RECORD TYPE" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I am partway through parsing a record type, but I got stuck after that last comma:",
                Doc.stack
                  [ Doc.reflow $
                      "Trailing commas are not allowed in record types, so the fix may be to\
                      \ delete that last comma? Or maybe you were in the middle of defining\
                      \ an additional field?",
                    noteForRecordTypeIndentError
                  ]
              )
    TRecordIndentColon row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED RECORD TYPE" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I am partway through parsing a record type. I just saw a record\
                  \ field, so I was expecting to see a colon next:",
                Doc.stack
                  [ Doc.fillSep $
                      [ "Try",
                        "putting",
                        "an",
                        Doc.green ":",
                        "followed",
                        "by",
                        "a",
                        "type?"
                      ],
                    noteForRecordTypeIndentError
                  ]
              )
    TRecordIndentType row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED RECORD TYPE" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I am partway through parsing a record type, and I was expecting to run into a type next:",
                Doc.stack
                  [ Doc.fillSep $
                      [ "Try",
                        "putting",
                        "something",
                        "like",
                        Doc.dullyellow "Int",
                        "or",
                        Doc.dullyellow "String",
                        "for",
                        "now?"
                      ],
                    noteForRecordTypeIndentError
                  ]
              )

-- | Documentation note for record type formatting errors.
noteForRecordTypeError :: Doc.Doc
noteForRecordTypeError =
  Doc.stack $
    [ Doc.toSimpleNote
        "If you are trying to define a record type across multiple lines, I recommend using this format:",
      Doc.indent 4 $
        Doc.vcat $
          [ "{ name : String",
            ", age : Int",
            ", height : Float",
            "}"
          ],
      Doc.reflow $
        "Notice that each line starts with some indentation. Usually two or four spaces.\
        \ This is the stylistic convention in the Canopy ecosystem."
    ]

-- | Documentation note for record type indentation errors.
noteForRecordTypeIndentError :: Doc.Doc
noteForRecordTypeIndentError =
  Doc.stack $
    [ Doc.toSimpleNote
        "I may be confused by indentation. For example, if you are trying to define\
        \ a record type across multiple lines, I recommend using this format:",
      Doc.indent 4 $
        Doc.vcat $
          [ "{ name : String",
            ", age : Int",
            ", height : Float",
            "}"
          ],
      Doc.reflow $
        "Notice that each line starts with some indentation. Usually two or four spaces.\
        \ This is the stylistic convention in the Canopy ecosystem."
    ]

-- | Render a tuple type parse error.
toTTupleReport :: Code.Source -> TContext -> TTuple -> Row -> Col -> Report.Report
toTTupleReport source context tuple startRow startCol =
  case tuple of
    TTupleOpen row col ->
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
                      "I ran into a reserved word unexpectedly:",
                    Doc.reflow $
                      "It looks like you are trying to use `" ++ keyword
                        ++ "` as a variable name, but \
                           \ it is a reserved word. Try using a different name!"
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
                      "I just saw an open parenthesis, so I was expecting to see a type next.",
                    Doc.fillSep $
                      [ "Something",
                        "like",
                        Doc.dullyellow "(Maybe Int)",
                        "or",
                        Doc.dullyellow "(List Person)" <> ".",
                        "Anything",
                        "where",
                        "you",
                        "are",
                        "putting",
                        "parentheses",
                        "around",
                        "normal",
                        "types."
                      ]
                  )
    TTupleEnd row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED PARENTHESES" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I was expecting to see a closing parenthesis next, but I got stuck here:",
                Doc.stack
                  [ Doc.fillSep ["Try", "adding", "a", Doc.dullyellow ")", "to", "see", "if", "that", "helps?"],
                    Doc.toSimpleNote $
                      "I can get stuck when I run into keywords, operators, parentheses, or brackets\
                      \ unexpectedly. So there may be some earlier syntax trouble (like extra parenthesis\
                      \ or missing brackets) that is confusing me."
                  ]
              )
    TTupleType tipe row col ->
      toTypeReport source context tipe row col
    TTupleSpace space row col ->
      toSpaceReport source space row col
    TTupleIndentType1 row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED PARENTHESES" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I just saw an open parenthesis, so I was expecting to see a type next.",
                Doc.stack
                  [ Doc.fillSep $
                      [ "Something",
                        "like",
                        Doc.dullyellow "(Maybe Int)",
                        "or",
                        Doc.dullyellow "(List Person)" <> ".",
                        "Anything",
                        "where",
                        "you",
                        "are",
                        "putting",
                        "parentheses",
                        "around",
                        "normal",
                        "types."
                      ],
                    Doc.toSimpleNote $
                      "I can get confused by indentation in cases like this, so\
                      \ maybe you have a type but it is not indented enough?"
                  ]
              )
    TTupleIndentTypeN row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED TUPLE TYPE" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I think I am in the middle of parsing a tuple type. I just saw a comma, so I was expecting to see a type next.",
                Doc.stack
                  [ Doc.fillSep $
                      [ "A",
                        "tuple",
                        "type",
                        "looks",
                        "like",
                        Doc.dullyellow "(Float,Float)",
                        "or",
                        Doc.dullyellow "(String,Int)" <> ",",
                        "so",
                        "I",
                        "think",
                        "there",
                        "is",
                        "a",
                        "type",
                        "missing",
                        "here?"
                      ],
                    Doc.toSimpleNote $
                      "I can get confused by indentation in cases like this, so\
                      \ maybe you have an expression but it is not indented enough?"
                  ]
              )
    TTupleIndentEnd row col ->
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

