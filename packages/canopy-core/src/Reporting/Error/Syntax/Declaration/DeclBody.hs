{-# LANGUAGE OverloadedStrings #-}

-- | Reporting.Error.Syntax.Declaration.DeclBody - Type and definition error rendering
--
-- Contains rendering for type declaration errors (toDeclTypeReport,
-- toTypeAliasReport, toCustomTypeReport) and definition errors (toDeclDefReport).
--
-- This is a sub-module of "Reporting.Error.Syntax.Declaration" and is
-- re-exported from there. Users should import the parent module directly.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Declaration.DeclBody
  ( toDeclTypeReport,
    toTypeAliasReport,
    toCustomTypeReport,
    toDeclDefReport,
  )
where

import qualified Canopy.Data.Name as Name
import Parse.Primitives (Col, Row)
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import Reporting.Error.Syntax.Expression
  ( declDefNote,
    toExprReport,
  )
import Reporting.Error.Syntax.Helpers
  ( Context (..),
    toKeywordRegion,
    toRegion,
    toSpaceReport,
    toWiderRegion,
  )
import Reporting.Error.Syntax.Pattern
  ( PContext (..),
    toPatternReport,
  )
import Reporting.Error.Syntax.Type
  ( TContext (..),
    toTypeReport,
  )
import Reporting.Error.Syntax.Types
  ( CustomType (..),
    DeclDef (..),
    DeclType (..),
    TypeAlias (..),
  )
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report

-- | Render a type declaration parse error.
toDeclTypeReport :: Code.Source -> DeclType -> Row -> Col -> Report.Report
toDeclTypeReport source declType startRow startCol =
  case declType of
    DT_Space space row col ->
      toSpaceReport source space row col
    DT_Name row col ->
      toDTNameReport source startRow startCol row col
    DT_Alias typeAlias row col ->
      toTypeAliasReport source typeAlias row col
    DT_Union customType row col ->
      toCustomTypeReport source customType row col
    DT_IndentName row col ->
      toDTIndentNameReport source startRow startCol row col
    DT_MethodAlignment _ row col ->
      toDTMethodAlignmentReport source startRow startCol row col

toDTNameReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toDTNameReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "EXPECTING TYPE NAME" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I think I am parsing a type declaration, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep
                  [ "I", "was", "expecting", "a", "name", "like",
                    Doc.dullyellow "Status", "or", Doc.dullyellow "Style", "next.",
                    "Just", "make", "sure", "it", "is", "a", "name", "that",
                    "starts", "with", "a", "capital", "letter!"
                  ],
                customTypeNote
              ]
          )

toDTIndentNameReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toDTIndentNameReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "EXPECTING TYPE NAME" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I think I am parsing a type declaration, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep
                  [ "I", "was", "expecting", "a", "name", "like",
                    Doc.dullyellow "Status", "or", Doc.dullyellow "Style", "next.",
                    "Just", "make", "sure", "it", "is", "a", "name", "that",
                    "starts", "with", "a", "capital", "letter!"
                  ],
                customTypeNote
              ]
          )

toDTMethodAlignmentReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toDTMethodAlignmentReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED ABILITY" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I am partway through parsing an ability declaration, but I got stuck here:",
            Doc.stack
              [ Doc.reflow "I was expecting to see another method definition aligned with the others.",
                abilityNote
              ]
          )

abilityNote :: Doc.Doc
abilityNote =
  Doc.stack
    [ Doc.toSimpleNote "Here is an example of a valid `ability` declaration for reference:",
      Doc.vcat
        [ Doc.indent 4 $ Doc.fillSep [Doc.cyan "ability", "Show", "a", Doc.cyan "where"],
          Doc.indent 6 "show : a -> String"
        ],
      Doc.reflow $
        "All method definitions must be indented and aligned at the same column."
    ]

-- | Render a type alias parse error.
toTypeAliasReport :: Code.Source -> TypeAlias -> Row -> Col -> Report.Report
toTypeAliasReport source typeAlias startRow startCol =
  case typeAlias of
    AliasSpace space row col ->
      toSpaceReport source space row col
    AliasName row col ->
      toAliasNameReport source startRow startCol row col
    AliasEquals row col ->
      toAliasEqualsReport source startRow startCol row col
    AliasBody tipe row col ->
      toTypeReport source TC_TypeAlias tipe row col
    AliasIndentEquals row col ->
      toAliasIndentEqualsReport source startRow startCol row col
    AliasIndentBody row col ->
      toAliasIndentBodyReport source startRow startCol row col

toAliasNameReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toAliasNameReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "EXPECTING TYPE ALIAS NAME" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I am partway through parsing a type alias, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep
                  [ "I", "was", "expecting", "a", "name", "like",
                    Doc.dullyellow "Person", "or", Doc.dullyellow "Point", "next.",
                    "Just", "make", "sure", "it", "is", "a", "name", "that",
                    "starts", "with", "a", "capital", "letter!"
                  ],
                typeAliasNote
              ]
          )

toAliasEqualsReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toAliasEqualsReport source startRow startCol row col =
  case Code.whatIsNext source row col of
    Code.Keyword keyword ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toKeywordRegion row col keyword
       in Report.Report "RESERVED WORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow "I ran into a reserved word unexpectedly while parsing this type alias:",
                Doc.stack
                  [ Doc.reflow $
                      "It looks like you are trying use `" ++ keyword
                        ++ "` as a type variable, but it is a reserved word. Try using a different name?",
                    typeAliasNote
                  ]
              )
    _ ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "PROBLEM IN TYPE ALIAS" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow "I am partway through parsing a type alias, but I got stuck here:",
                Doc.stack
                  [ Doc.reflow "I was expecting to see a type variable or an equals sign next.",
                    typeAliasNote
                  ]
              )

toAliasIndentEqualsReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toAliasIndentEqualsReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED TYPE ALIAS" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I am partway through parsing a type alias, but I got stuck here:",
            Doc.stack
              [ Doc.reflow "I was expecting to see a type variable or an equals sign next.",
                typeAliasNote
              ]
          )

toAliasIndentBodyReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toAliasIndentBodyReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED TYPE ALIAS" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I am partway through parsing a type alias, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep
                  [ "I", "was", "expecting", "to", "see", "a", "type", "next.",
                    "Something", "as", "simple", "as",
                    Doc.dullyellow "Int", "or", Doc.dullyellow "Float", "would", "work!"
                  ],
                typeAliasNote
              ]
          )

typeAliasNote :: Doc.Doc
typeAliasNote =
  Doc.stack
    [ Doc.toSimpleNote "Here is an example of a valid `type alias` for reference:",
      Doc.vcat
        [ Doc.indent 4 $ Doc.fillSep [Doc.cyan "type", Doc.cyan "alias", "Person", "="],
          Doc.indent 6 $
            Doc.vcat
              [ "{ name : String",
                ", age : Int",
                ", height : Float",
                "}"
              ]
        ],
      Doc.reflow $
        "This would let us use `Person` as a shorthand for that record type. Using this\
        \ shorthand makes type annotations much easier to read, and makes changing code\
        \ easier if you decide later that there is more to a person than age and height!"
    ]

-- | Render a custom type declaration parse error.
toCustomTypeReport :: Code.Source -> CustomType -> Row -> Col -> Report.Report
toCustomTypeReport source customType startRow startCol =
  case customType of
    CT_Space space row col ->
      toSpaceReport source space row col
    CT_Name row col ->
      toCTNameReport source startRow startCol row col
    CT_Equals row col ->
      toCTEqualsReport source startRow startCol row col
    CT_Bar row col ->
      toCTBarReport source startRow startCol row col
    CT_Variant row col ->
      toCTVariantReport source startRow startCol row col
    CT_VariantArg tipe row col ->
      toTypeReport source TC_CustomType tipe row col
    CT_IndentEquals row col ->
      toCTIndentEqualsReport source startRow startCol row col
    CT_IndentBar row col ->
      toCTIndentBarReport source startRow startCol row col
    CT_IndentAfterBar row col ->
      toCTIndentAfterBarReport source startRow startCol row col
    CT_IndentAfterEquals row col ->
      toCTIndentAfterEqualsReport source startRow startCol row col

toCTNameReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toCTNameReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "EXPECTING TYPE NAME" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I think I am parsing a type declaration, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep
                  [ "I", "was", "expecting", "a", "name", "like",
                    Doc.dullyellow "Status", "or", Doc.dullyellow "Style", "next.",
                    "Just", "make", "sure", "it", "is", "a", "name", "that",
                    "starts", "with", "a", "capital", "letter!"
                  ],
                customTypeNote
              ]
          )

toCTEqualsReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toCTEqualsReport source startRow startCol row col =
  case Code.whatIsNext source row col of
    Code.Keyword keyword ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toKeywordRegion row col keyword
       in Report.Report "RESERVED WORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow "I ran into a reserved word unexpectedly while parsing this custom type:",
                Doc.stack
                  [ Doc.reflow $
                      "It looks like you are trying use `" ++ keyword
                        ++ "` as a type variable, but it is a reserved word. Try using a different name?",
                    customTypeNote
                  ]
              )
    _ ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "PROBLEM IN CUSTOM TYPE" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow "I am partway through parsing a custom type, but I got stuck here:",
                Doc.stack
                  [ Doc.reflow "I was expecting to see a type variable or an equals sign next.",
                    customTypeNote
                  ]
              )

toCTBarReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toCTBarReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "PROBLEM IN CUSTOM TYPE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I am partway through parsing a custom type, but I got stuck here:",
            Doc.stack
              [ Doc.reflow "I was expecting to see a vertical bar like | next.",
                customTypeNote
              ]
          )

toCTVariantReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toCTVariantReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "PROBLEM IN CUSTOM TYPE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I am partway through parsing a custom type, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep
                  [ "I", "was", "expecting", "to", "see", "a", "variant", "name", "next.",
                    "Something", "like",
                    Doc.dullyellow "Success", "or", Doc.dullyellow "Sandwich" <> ".",
                    "Any", "name", "that", "starts", "with", "a", "capital", "letter", "really!"
                  ],
                customTypeNote
              ]
          )

toCTIndentEqualsReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toCTIndentEqualsReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED CUSTOM TYPE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I am partway through parsing a custom type, but I got stuck here:",
            Doc.stack
              [ Doc.reflow "I was expecting to see a type variable or an equals sign next.",
                customTypeNote
              ]
          )

toCTIndentBarReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toCTIndentBarReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED CUSTOM TYPE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I am partway through parsing a custom type, but I got stuck here:",
            Doc.stack
              [ Doc.reflow "I was expecting to see a vertical bar like | next.",
                customTypeNote
              ]
          )

toCTIndentAfterBarReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toCTIndentAfterBarReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED CUSTOM TYPE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I am partway through parsing a custom type, but I got stuck here:",
            Doc.stack
              [ Doc.reflow "I just saw a vertical bar, so I was expecting to see another variant defined next.",
                customTypeNote
              ]
          )

toCTIndentAfterEqualsReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toCTIndentAfterEqualsReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED CUSTOM TYPE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I am partway through parsing a custom type, but I got stuck here:",
            Doc.stack
              [ Doc.reflow "I just saw an equals sign, so I was expecting to see the first variant defined next.",
                customTypeNote
              ]
          )

customTypeNote :: Doc.Doc
customTypeNote =
  Doc.stack
    [ Doc.toSimpleNote "Here is an example of a valid `type` declaration for reference:",
      Doc.vcat
        [ Doc.indent 4 $ Doc.fillSep [Doc.cyan "type", "Status"],
          Doc.indent 6 $ Doc.fillSep ["=", "Failure"],
          Doc.indent 6 $ Doc.fillSep ["|", "Waiting"],
          Doc.indent 6 $ Doc.fillSep ["|", "Success", "String"]
        ],
      Doc.reflow $
        "This defines a new `Status` type with three variants. This could be useful if\
        \ we are waiting for an HTTP request. Maybe we start with `Waiting` and then\
        \ switch to `Failure` or `Success \"message from server\"` depending on how\
        \ things go. Notice that the Success variant has some associated data, allowing\
        \ us to store a String if the request goes well!"
    ]

-- | Render a definition parse error.
toDeclDefReport :: Code.Source -> Name.Name -> DeclDef -> Row -> Col -> Report.Report
toDeclDefReport source name declDef startRow startCol =
  case declDef of
    DeclDefSpace space row col ->
      toSpaceReport source space row col
    DeclDefEquals row col ->
      toDeclDefEqualsReport source name startRow startCol row col
    DeclDefType tipe row col ->
      toTypeReport source (TC_Annotation name) tipe row col
    DeclDefArg pattern row col ->
      toPatternReport source PArg pattern row col
    DeclDefBody expr row col ->
      toExprReport source (InDef name startRow startCol) expr row col
    DeclDefNameRepeat row col ->
      toDeclDefNameRepeatReport source name startRow startCol row col
    DeclDefNameMatch defName row col ->
      toDeclDefNameMatchReport source name defName startRow startCol row col
    DeclDefIndentType row col ->
      toDeclDefIndentTypeReport source name startRow startCol row col
    DeclDefIndentEquals row col ->
      toDeclDefIndentEqualsReport source name startRow startCol row col
    DeclDefIndentBody row col ->
      toDeclDefIndentBodyReport source name startRow startCol row col

toDeclDefEqualsReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDeclDefEqualsReport source name startRow startCol row col =
  case Code.whatIsNext source row col of
    Code.Keyword keyword ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toKeywordRegion row col keyword
       in Report.Report "RESERVED WORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.fillSep
                  [ "The", "name",
                    "`" <> Doc.cyan (Doc.fromChars keyword) <> "`",
                    "is", "reserved", "in", "Canopy,", "so", "it", "cannot",
                    "be", "used", "as", "an", "argument", "here:"
                  ],
                Doc.stack
                  [ Doc.reflow "Try renaming it to something else.",
                    toDeclDefEqualsKeywordNote keyword
                  ]
              )
    Code.Operator "->" ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toWiderRegion row col 2
       in Report.Report "MISSING COLON?" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow "I was not expecting to see an arrow here:",
                Doc.stack
                  [ Doc.fillSep
                      [ "This", "usually", "means", "a", Doc.green ":", "is", "missing", "a", "bit",
                        "earlier", "in", "a", "type", "annotation.", "It", "could", "be", "something",
                        "else", "though,", "so", "here", "is", "a", "valid", "definition", "for", "reference:"
                      ],
                    Doc.indent 4 $
                      Doc.vcat
                        [ "greet : String -> String",
                          "greet name =",
                          "  " <> Doc.dullyellow "\"Hello \"" <> " ++ name ++ " <> Doc.dullyellow "\"!\""
                        ],
                    Doc.reflow ("Try to use that format with your `" ++ Name.toChars name ++ "` definition!")
                  ]
              )
    Code.Operator op ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toKeywordRegion row col op
       in Report.Report "UNEXPECTED SYMBOL" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow "I was not expecting to see this symbol here:",
                Doc.stack
                  [ Doc.reflow $
                      "I am not sure what is going wrong exactly, so here is a valid\
                      \ definition (with an optional type annotation) for reference:",
                    Doc.indent 4 $
                      Doc.vcat
                        [ "greet : String -> String",
                          "greet name =",
                          "  " <> Doc.dullyellow "\"Hello \"" <> " ++ name ++ " <> Doc.dullyellow "\"!\""
                        ],
                    Doc.reflow ("Try to use that format with your `" ++ Name.toChars name ++ "` definition!")
                  ]
              )
    _ ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "PROBLEM IN DEFINITION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow ("I got stuck while parsing the `" ++ Name.toChars name ++ "` definition:"),
                Doc.stack
                  [ Doc.reflow $
                      "I am not sure what is going wrong exactly, so here is a valid\
                      \ definition (with an optional type annotation) for reference:",
                    Doc.indent 4 $
                      Doc.vcat
                        [ "greet : String -> String",
                          "greet name =",
                          "  " <> Doc.dullyellow "\"Hello \"" <> " ++ name ++ " <> Doc.dullyellow "\"!\""
                        ],
                    Doc.reflow "Try to use that format!"
                  ]
              )

toDeclDefEqualsKeywordNote :: String -> Doc.Doc
toDeclDefEqualsKeywordNote keyword =
  case keyword of
    "as" ->
      Doc.toFancyNote
        [ "This", "keyword", "is", "reserved", "for", "pattern", "matches", "like",
          "((x,y)", Doc.cyan "as", "point)", "where", "you", "want", "to", "name", "a",
          "tuple", "and", "the", "values", "it", "contains."
        ]
    _ ->
      Doc.toSimpleNote ("The `" ++ keyword ++ "` keyword has a special meaning in Canopy, so it can only be used in certain situations.")

toDeclDefNameRepeatReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDeclDefNameRepeatReport source name startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "EXPECTING DEFINITION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I just saw the type annotation for `" ++ Name.toChars name
                ++ "` so I was expecting to see its definition here:",
            Doc.stack
              [ Doc.reflow $
                  "Type annotations always appear directly above the relevant\
                  \ definition, without anything else in between. (Not even doc comments!)",
                declDefNote
              ]
          )

toDeclDefNameMatchReport :: Code.Source -> Name.Name -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDeclDefNameMatchReport source name defName startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "NAME MISMATCH" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I just saw a type annotation for `" ++ Name.toChars name
                ++ "`, but it is followed by a definition for `" ++ Name.toChars defName ++ "`:",
            Doc.stack
              [ Doc.reflow "These names do not match! Is there a typo?",
                Doc.indent 4 $
                  Doc.fillSep [Doc.dullyellow (Doc.fromName defName), "->", Doc.green (Doc.fromName name)]
              ]
          )

toDeclDefIndentTypeReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDeclDefIndentTypeReport source name startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED DEFINITION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow ("I got stuck while parsing the `" ++ Name.toChars name ++ "` type annotation:"),
            Doc.stack
              [ Doc.reflow "I just saw a colon, so I am expecting to see a type next.",
                declDefNote
              ]
          )

toDeclDefIndentEqualsReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDeclDefIndentEqualsReport source name startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED DEFINITION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow ("I got stuck while parsing the `" ++ Name.toChars name ++ "` definition:"),
            Doc.stack
              [ Doc.reflow "I was expecting to see an argument or an equals sign next.",
                declDefNote
              ]
          )

toDeclDefIndentBodyReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDeclDefIndentBodyReport source name startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED DEFINITION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow ("I got stuck while parsing the `" ++ Name.toChars name ++ "` definition:"),
            Doc.stack
              [ Doc.reflow "I was expecting to see an expression next. What is it equal to?",
                declDefNote
              ]
          )
