{-# LANGUAGE OverloadedStrings #-}

-- | Syntax error rendering for declarations.
--
-- This module handles rendering of parse errors for top-level declarations,
-- including type aliases, custom types, value definitions, ports, and the
-- declaration-level dispatching logic.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Declaration
  ( toDeclarationsReport,
    toDeclStartReport,
    toPortReport,
    toDeclTypeReport,
    toTypeAliasReport,
    toCustomTypeReport,
    toDeclDefReport,
  )
where

import qualified Data.Char as Char
import qualified Data.Name as Name
import Parse.Primitives (Col, Row)
import qualified Reporting.Annotation as A
import qualified Reporting.Doc as D
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
    Decl (..),
    DeclDef (..),
    DeclType (..),
    Port (..),
    TypeAlias (..),
  )
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report

-- | Render a declaration-level parse error.
toDeclarationsReport :: Code.Source -> Decl -> Report.Report
toDeclarationsReport source decl =
  case decl of
    DeclStart row col ->
      toDeclStartReport source row col
    DeclSpace space row col ->
      toSpaceReport source space row col
    Port port_ row col ->
      toPortReport source port_ row col
    DeclType declType row col ->
      toDeclTypeReport source declType row col
    DeclDef name declDef row col ->
      toDeclDefReport source name declDef row col
    DeclFreshLineAfterDocComment row col ->
      let region = toRegion row col
       in Report.Report "EXPECTING DECLARATION" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow "I just saw a doc comment, but then I got stuck here:",
                D.reflow $
                  "I was expecting to see the corresponding declaration next, starting on a fresh\
                  \ line with no indentation."
              )

-- | Render an error when the parser cannot identify a declaration start.
toDeclStartReport :: Code.Source -> Row -> Col -> Report.Report
toDeclStartReport source row col =
  case Code.whatIsNext source row col of
    Code.Close term bracket ->
      let region = toRegion row col
       in Report.Report ("STRAY " ++ map Char.toUpper term) region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow ("I was not expecting to see a " ++ term ++ " here:"),
                D.reflow $
                  "This " ++ bracket : " does not match up with an earlier open " ++ term ++ ". Try deleting it?"
              )
    Code.Keyword keyword ->
      toDeclStartKeywordReport source row col keyword
    Code.Upper c cs ->
      toDeclStartUpperReport source row col c cs
    Code.Other (Just char)
      | elem char ['(', '{', '[', '+', '-', '*', '/', '^', '&', '|', '"', '\'', '!', '@', '#', '$', '%'] ->
          toDeclStartSymbolReport source row col char
    _ ->
      toDeclStartWeirdReport source row col

toDeclStartKeywordReport :: Code.Source -> Row -> Col -> String -> Report.Report
toDeclStartKeywordReport source row col keyword =
  let region = toKeywordRegion row col keyword
   in Report.Report "RESERVED WORD" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( D.reflow ("I was not expecting to run into the `" ++ keyword ++ "` keyword here:"),
            toDeclStartKeywordHint keyword
          )

toDeclStartKeywordHint :: String -> D.Doc
toDeclStartKeywordHint keyword =
  case keyword of
    "import" ->
      D.reflow $
        "It is reserved for declaring imports at the top of your module. If you want\
        \ another import, try moving it up top with the other imports. If you want to\
        \ define a value or function, try changing the name to something else!"
    "case" ->
      D.stack
        [ D.reflow "It is reserved for writing `case` expressions. Try using a different name?",
          D.toSimpleNote $
            "If you are trying to write a `case` expression, it needs to be part of a\
            \ definition. So you could write something like this instead:",
          D.indent 4 $
            D.vcat
              [ D.indent 0 $ D.fillSep ["getWidth", "maybeWidth", "="],
                D.indent 2 $ D.fillSep [D.cyan "case", "maybeWidth", D.cyan "of"],
                D.indent 4 $ D.fillSep [D.blue "Just", "width", "->"],
                D.indent 6 $ D.fillSep ["width", "+", D.dullyellow "200"],
                "",
                D.indent 4 $ D.fillSep [D.blue "Nothing", "->"],
                D.indent 6 $ D.fillSep [D.dullyellow "400"]
              ],
          D.reflow "This defines a `getWidth` function that you can use elsewhere in your program."
        ]
    "if" ->
      D.stack
        [ D.reflow "It is reserved for writing `if` expressions. Try using a different name?",
          D.toSimpleNote $
            "If you are trying to write an `if` expression, it needs to be part of a\
            \ definition. So you could write something like this instead:",
          D.indent 4 $
            D.vcat
              [ "greet name =",
                D.fillSep
                  [ " ",
                    D.cyan "if",
                    "name",
                    "==",
                    D.dullyellow "\"Abraham Lincoln\"",
                    D.cyan "then",
                    D.dullyellow "\"Greetings Mr. President.\"",
                    D.cyan "else",
                    D.dullyellow "\"Hey!\""
                  ]
              ],
          D.reflow "This defines a `reviewPowerLevel` function that you can use elsewhere in your program."
        ]
    _ ->
      D.reflow "It is a reserved word. Try changing the name to something else?"

toDeclStartUpperReport :: Code.Source -> Row -> Col -> Char.Char -> String -> Report.Report
toDeclStartUpperReport source row col c cs =
  let region = toRegion row col
   in Report.Report "UNEXPECTED CAPITAL LETTER" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( D.reflow "Declarations always start with a lower-case letter, so I am getting stuck here:",
            D.stack
              [ D.fillSep
                  [ "Try",
                    "a",
                    "name",
                    "like",
                    D.green (D.fromChars (Char.toLower c : cs)),
                    "instead?"
                  ],
                D.toSimpleNote "Here are a couple valid declarations for reference:",
                D.indent 4 $
                  D.vcat
                    [ "greet : String -> String",
                      "greet name =",
                      "  " <> D.dullyellow "\"Hello \"" <> " ++ name ++ " <> D.dullyellow "\"!\"",
                      "",
                      D.cyan "type" <> " User = Anonymous | LoggedIn String"
                    ],
                D.reflow "Notice that they always start with a lower-case letter. Capitalization matters!"
              ]
          )

toDeclStartSymbolReport :: Code.Source -> Row -> Col -> Char.Char -> Report.Report
toDeclStartSymbolReport source row col char =
  let region = toRegion row col
   in Report.Report "UNEXPECTED SYMBOL" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( D.reflow ("I am getting stuck because this line starts with the " ++ [char] ++ " symbol:"),
            D.stack
              [ D.reflow "When a line has no spaces at the beginning, I expect it to be a declaration like one of these:",
                D.indent 4 $
                  D.vcat
                    [ "greet : String -> String",
                      "greet name =",
                      "  " <> D.dullyellow "\"Hello \"" <> " ++ name ++ " <> D.dullyellow "\"!\"",
                      "",
                      D.cyan "type" <> " User = Anonymous | LoggedIn String"
                    ],
                D.reflow "If this is not supposed to be a declaration, try adding some spaces before it?"
              ]
          )

toDeclStartWeirdReport :: Code.Source -> Row -> Col -> Report.Report
toDeclStartWeirdReport source row col =
  let region = toRegion row col
   in Report.Report "WEIRD DECLARATION" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( D.reflow "I am trying to parse a declaration, but I am getting stuck here:",
            D.stack
              [ D.reflow "When a line has no spaces at the beginning, I expect it to be a declaration like one of these:",
                D.indent 4 $
                  D.vcat
                    [ "greet : String -> String",
                      "greet name =",
                      "  " <> D.dullyellow "\"Hello \"" <> " ++ name ++ " <> D.dullyellow "\"!\"",
                      "",
                      D.cyan "type" <> " User = Anonymous | LoggedIn String"
                    ],
                D.reflow $
                  "Try to make your declaration look like one of those? Or if this is not\
                  \ supposed to be a declaration, try adding some spaces before it?"
              ]
          )

-- | Render a port declaration parse error.
toPortReport :: Code.Source -> Port -> Row -> Col -> Report.Report
toPortReport source port_ startRow startCol =
  case port_ of
    PortSpace space row col ->
      toSpaceReport source space row col
    PortName row col ->
      toPortNameReport source startRow startCol row col
    PortColon row col ->
      toPortColonReport source startRow startCol row col
    PortType tipe row col ->
      toTypeReport source TC_Port tipe row col
    PortIndentName row col ->
      toPortIndentNameReport source startRow startCol row col
    PortIndentColon row col ->
      toPortIndentColonReport source startRow startCol row col
    PortIndentType row col ->
      toPortIndentTypeReport source startRow startCol row col

toPortNameReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toPortNameReport source startRow startCol row col =
  case Code.whatIsNext source row col of
    Code.Keyword keyword ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toKeywordRegion row col keyword
       in Report.Report "RESERVED WORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow "I cannot handle ports with names like this:",
                D.reflow ("You are trying to make a port named `" ++ keyword ++ "` but that is a reserved word. Try using some other name?")
              )
    _ ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "PORT PROBLEM" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow "I just saw the start of a `port` declaration, but then I got stuck here:",
                D.stack
                  [ D.fillSep
                      [ "I", "was", "expecting", "to", "see", "a", "name", "like",
                        D.dullyellow "send", "or", D.dullyellow "receive", "next.",
                        "Something", "that", "starts", "with", "a", "lower-case", "letter."
                      ],
                    portNote
                  ]
              )

toPortColonReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toPortColonReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "PORT PROBLEM" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I just saw the start of a `port` declaration, but then I got stuck here:",
            D.stack
              [ D.reflow $
                  "I was expecting to see a colon next. And then a type that tells me\
                  \ what type of values are going to flow through.",
                portNote
              ]
          )

toPortIndentNameReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toPortIndentNameReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED PORT" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I just saw the start of a `port` declaration, but then I got stuck here:",
            D.stack
              [ D.fillSep
                  [ "I", "was", "expecting", "to", "see", "a", "name", "like",
                    D.dullyellow "send", "or", D.dullyellow "receive", "next.",
                    "Something", "that", "starts", "with", "a", "lower-case", "letter."
                  ],
                portNote
              ]
          )

toPortIndentColonReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toPortIndentColonReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED PORT" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I just saw the start of a `port` declaration, but then I got stuck here:",
            D.stack
              [ D.reflow $
                  "I was expecting to see a colon next. And then a type that tells me\
                  \ what type of values are going to flow through.",
                portNote
              ]
          )

toPortIndentTypeReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toPortIndentTypeReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED PORT" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I just saw the start of a `port` declaration, but then I got stuck here:",
            D.stack
              [ D.reflow $
                  "I was expecting to see a type next. Here are examples of outgoing and\
                  \ incoming ports for reference:",
                D.indent 4 $
                  D.vcat
                    [ D.fillSep [D.cyan "port", "send", ":", "String -> Cmd msg"],
                      D.fillSep [D.cyan "port", "receive", ":", "(String -> msg) -> Sub msg"]
                    ],
                D.reflow $
                  "The first line defines a `send` port so you can send strings out to JavaScript.\
                  \ Maybe you send them on a WebSocket or put them into IndexedDB. The second line\
                  \ defines a `receive` port so you can receive strings from JavaScript. Maybe you\
                  \ get receive messages when new WebSocket messages come in or when an entry in\
                  \ IndexedDB changes for some external reason."
              ]
          )

portNote :: D.Doc
portNote =
  D.stack
    [ D.toSimpleNote "Here are some example `port` declarations for reference:",
      D.indent 4 $
        D.vcat
          [ D.fillSep [D.cyan "port", "send", ":", "String -> Cmd msg"],
            D.fillSep [D.cyan "port", "receive", ":", "(String -> msg) -> Sub msg"]
          ],
      D.reflow $
        "The first line defines a `send` port so you can send strings out to JavaScript.\
        \ Maybe you send them on a WebSocket or put them into IndexedDB. The second line\
        \ defines a `receive` port so you can receive strings from JavaScript. Maybe you\
        \ get receive messages when new WebSocket messages come in or when the IndexedDB\
        \ is changed for some external reason."
    ]

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

toDTNameReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toDTNameReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "EXPECTING TYPE NAME" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I think I am parsing a type declaration, but I got stuck here:",
            D.stack
              [ D.fillSep
                  [ "I", "was", "expecting", "a", "name", "like",
                    D.dullyellow "Status", "or", D.dullyellow "Style", "next.",
                    "Just", "make", "sure", "it", "is", "a", "name", "that",
                    "starts", "with", "a", "capital", "letter!"
                  ],
                customTypeNote
              ]
          )

toDTIndentNameReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toDTIndentNameReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "EXPECTING TYPE NAME" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I think I am parsing a type declaration, but I got stuck here:",
            D.stack
              [ D.fillSep
                  [ "I", "was", "expecting", "a", "name", "like",
                    D.dullyellow "Status", "or", D.dullyellow "Style", "next.",
                    "Just", "make", "sure", "it", "is", "a", "name", "that",
                    "starts", "with", "a", "capital", "letter!"
                  ],
                customTypeNote
              ]
          )

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
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "EXPECTING TYPE ALIAS NAME" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I am partway through parsing a type alias, but I got stuck here:",
            D.stack
              [ D.fillSep
                  [ "I", "was", "expecting", "a", "name", "like",
                    D.dullyellow "Person", "or", D.dullyellow "Point", "next.",
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
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toKeywordRegion row col keyword
       in Report.Report "RESERVED WORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow "I ran into a reserved word unexpectedly while parsing this type alias:",
                D.stack
                  [ D.reflow $
                      "It looks like you are trying use `" ++ keyword
                        ++ "` as a type variable, but it is a reserved word. Try using a different name?",
                    typeAliasNote
                  ]
              )
    _ ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "PROBLEM IN TYPE ALIAS" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow "I am partway through parsing a type alias, but I got stuck here:",
                D.stack
                  [ D.reflow "I was expecting to see a type variable or an equals sign next.",
                    typeAliasNote
                  ]
              )

toAliasIndentEqualsReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toAliasIndentEqualsReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED TYPE ALIAS" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I am partway through parsing a type alias, but I got stuck here:",
            D.stack
              [ D.reflow "I was expecting to see a type variable or an equals sign next.",
                typeAliasNote
              ]
          )

toAliasIndentBodyReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toAliasIndentBodyReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED TYPE ALIAS" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I am partway through parsing a type alias, but I got stuck here:",
            D.stack
              [ D.fillSep
                  [ "I", "was", "expecting", "to", "see", "a", "type", "next.",
                    "Something", "as", "simple", "as",
                    D.dullyellow "Int", "or", D.dullyellow "Float", "would", "work!"
                  ],
                typeAliasNote
              ]
          )

typeAliasNote :: D.Doc
typeAliasNote =
  D.stack
    [ D.toSimpleNote "Here is an example of a valid `type alias` for reference:",
      D.vcat
        [ D.indent 4 $ D.fillSep [D.cyan "type", D.cyan "alias", "Person", "="],
          D.indent 6 $
            D.vcat
              [ "{ name : String",
                ", age : Int",
                ", height : Float",
                "}"
              ]
        ],
      D.reflow $
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
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "EXPECTING TYPE NAME" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I think I am parsing a type declaration, but I got stuck here:",
            D.stack
              [ D.fillSep
                  [ "I", "was", "expecting", "a", "name", "like",
                    D.dullyellow "Status", "or", D.dullyellow "Style", "next.",
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
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toKeywordRegion row col keyword
       in Report.Report "RESERVED WORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow "I ran into a reserved word unexpectedly while parsing this custom type:",
                D.stack
                  [ D.reflow $
                      "It looks like you are trying use `" ++ keyword
                        ++ "` as a type variable, but it is a reserved word. Try using a different name?",
                    customTypeNote
                  ]
              )
    _ ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "PROBLEM IN CUSTOM TYPE" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow "I am partway through parsing a custom type, but I got stuck here:",
                D.stack
                  [ D.reflow "I was expecting to see a type variable or an equals sign next.",
                    customTypeNote
                  ]
              )

toCTBarReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toCTBarReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "PROBLEM IN CUSTOM TYPE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I am partway through parsing a custom type, but I got stuck here:",
            D.stack
              [ D.reflow "I was expecting to see a vertical bar like | next.",
                customTypeNote
              ]
          )

toCTVariantReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toCTVariantReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "PROBLEM IN CUSTOM TYPE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I am partway through parsing a custom type, but I got stuck here:",
            D.stack
              [ D.fillSep
                  [ "I", "was", "expecting", "to", "see", "a", "variant", "name", "next.",
                    "Something", "like",
                    D.dullyellow "Success", "or", D.dullyellow "Sandwich" <> ".",
                    "Any", "name", "that", "starts", "with", "a", "capital", "letter", "really!"
                  ],
                customTypeNote
              ]
          )

toCTIndentEqualsReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toCTIndentEqualsReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED CUSTOM TYPE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I am partway through parsing a custom type, but I got stuck here:",
            D.stack
              [ D.reflow "I was expecting to see a type variable or an equals sign next.",
                customTypeNote
              ]
          )

toCTIndentBarReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toCTIndentBarReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED CUSTOM TYPE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I am partway through parsing a custom type, but I got stuck here:",
            D.stack
              [ D.reflow "I was expecting to see a vertical bar like | next.",
                customTypeNote
              ]
          )

toCTIndentAfterBarReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toCTIndentAfterBarReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED CUSTOM TYPE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I am partway through parsing a custom type, but I got stuck here:",
            D.stack
              [ D.reflow "I just saw a vertical bar, so I was expecting to see another variant defined next.",
                customTypeNote
              ]
          )

toCTIndentAfterEqualsReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toCTIndentAfterEqualsReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED CUSTOM TYPE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I am partway through parsing a custom type, but I got stuck here:",
            D.stack
              [ D.reflow "I just saw an equals sign, so I was expecting to see the first variant defined next.",
                customTypeNote
              ]
          )

customTypeNote :: D.Doc
customTypeNote =
  D.stack
    [ D.toSimpleNote "Here is an example of a valid `type` declaration for reference:",
      D.vcat
        [ D.indent 4 $ D.fillSep [D.cyan "type", "Status"],
          D.indent 6 $ D.fillSep ["=", "Failure"],
          D.indent 6 $ D.fillSep ["|", "Waiting"],
          D.indent 6 $ D.fillSep ["|", "Success", "String"]
        ],
      D.reflow $
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
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toKeywordRegion row col keyword
       in Report.Report "RESERVED WORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.fillSep
                  [ "The", "name",
                    "`" <> D.cyan (D.fromChars keyword) <> "`",
                    "is", "reserved", "in", "Canopy,", "so", "it", "cannot",
                    "be", "used", "as", "an", "argument", "here:"
                  ],
                D.stack
                  [ D.reflow "Try renaming it to something else.",
                    toDeclDefEqualsKeywordNote keyword
                  ]
              )
    Code.Operator "->" ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toWiderRegion row col 2
       in Report.Report "MISSING COLON?" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow "I was not expecting to see an arrow here:",
                D.stack
                  [ D.fillSep
                      [ "This", "usually", "means", "a", D.green ":", "is", "missing", "a", "bit",
                        "earlier", "in", "a", "type", "annotation.", "It", "could", "be", "something",
                        "else", "though,", "so", "here", "is", "a", "valid", "definition", "for", "reference:"
                      ],
                    D.indent 4 $
                      D.vcat
                        [ "greet : String -> String",
                          "greet name =",
                          "  " <> D.dullyellow "\"Hello \"" <> " ++ name ++ " <> D.dullyellow "\"!\""
                        ],
                    D.reflow ("Try to use that format with your `" ++ Name.toChars name ++ "` definition!")
                  ]
              )
    Code.Operator op ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toKeywordRegion row col op
       in Report.Report "UNEXPECTED SYMBOL" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow "I was not expecting to see this symbol here:",
                D.stack
                  [ D.reflow $
                      "I am not sure what is going wrong exactly, so here is a valid\
                      \ definition (with an optional type annotation) for reference:",
                    D.indent 4 $
                      D.vcat
                        [ "greet : String -> String",
                          "greet name =",
                          "  " <> D.dullyellow "\"Hello \"" <> " ++ name ++ " <> D.dullyellow "\"!\""
                        ],
                    D.reflow ("Try to use that format with your `" ++ Name.toChars name ++ "` definition!")
                  ]
              )
    _ ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "PROBLEM IN DEFINITION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow ("I got stuck while parsing the `" ++ Name.toChars name ++ "` definition:"),
                D.stack
                  [ D.reflow $
                      "I am not sure what is going wrong exactly, so here is a valid\
                      \ definition (with an optional type annotation) for reference:",
                    D.indent 4 $
                      D.vcat
                        [ "greet : String -> String",
                          "greet name =",
                          "  " <> D.dullyellow "\"Hello \"" <> " ++ name ++ " <> D.dullyellow "\"!\""
                        ],
                    D.reflow "Try to use that format!"
                  ]
              )

toDeclDefEqualsKeywordNote :: String -> D.Doc
toDeclDefEqualsKeywordNote keyword =
  case keyword of
    "as" ->
      D.toFancyNote
        [ "This", "keyword", "is", "reserved", "for", "pattern", "matches", "like",
          "((x,y)", D.cyan "as", "point)", "where", "you", "want", "to", "name", "a",
          "tuple", "and", "the", "values", "it", "contains."
        ]
    _ ->
      D.toSimpleNote ("The `" ++ keyword ++ "` keyword has a special meaning in Canopy, so it can only be used in certain situations.")

toDeclDefNameRepeatReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDeclDefNameRepeatReport source name startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "EXPECTING DEFINITION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow $
              "I just saw the type annotation for `" ++ Name.toChars name
                ++ "` so I was expecting to see its definition here:",
            D.stack
              [ D.reflow $
                  "Type annotations always appear directly above the relevant\
                  \ definition, without anything else in between. (Not even doc comments!)",
                declDefNote
              ]
          )

toDeclDefNameMatchReport :: Code.Source -> Name.Name -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDeclDefNameMatchReport source name defName startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "NAME MISMATCH" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow $
              "I just saw a type annotation for `" ++ Name.toChars name
                ++ "`, but it is followed by a definition for `" ++ Name.toChars defName ++ "`:",
            D.stack
              [ D.reflow "These names do not match! Is there a typo?",
                D.indent 4 $
                  D.fillSep [D.dullyellow (D.fromName defName), "->", D.green (D.fromName name)]
              ]
          )

toDeclDefIndentTypeReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDeclDefIndentTypeReport source name startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED DEFINITION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow ("I got stuck while parsing the `" ++ Name.toChars name ++ "` type annotation:"),
            D.stack
              [ D.reflow "I just saw a colon, so I am expecting to see a type next.",
                declDefNote
              ]
          )

toDeclDefIndentEqualsReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDeclDefIndentEqualsReport source name startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED DEFINITION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow ("I got stuck while parsing the `" ++ Name.toChars name ++ "` definition:"),
            D.stack
              [ D.reflow "I was expecting to see an argument or an equals sign next.",
                declDefNote
              ]
          )

toDeclDefIndentBodyReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDeclDefIndentBodyReport source name startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED DEFINITION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow ("I got stuck while parsing the `" ++ Name.toChars name ++ "` definition:"),
            D.stack
              [ D.reflow "I was expecting to see an expression next. What is it equal to?",
                declDefNote
              ]
          )
