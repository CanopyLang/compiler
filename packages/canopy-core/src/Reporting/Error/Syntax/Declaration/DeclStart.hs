{-# LANGUAGE OverloadedStrings #-}

-- | Reporting.Error.Syntax.Declaration.DeclStart - Declaration start and port error rendering
--
-- Contains rendering for declaration-start errors (toDeclStartReport) and
-- port declaration errors (toPortReport).
--
-- This is a sub-module of "Reporting.Error.Syntax.Declaration" and is
-- re-exported from there. Users should import the parent module directly.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Declaration.DeclStart
  ( toDeclStartReport,
    toPortReport,
  )
where

import qualified Data.Char as Char
import Parse.Primitives (Col, Row)
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import Reporting.Error.Syntax.Helpers
  ( toKeywordRegion,
    toRegion,
    toSpaceReport,
  )
import Reporting.Error.Syntax.Type
  ( TContext (..),
    toTypeReport,
  )
import Reporting.Error.Syntax.Types
  ( Port (..),
  )
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report

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
              ( Doc.reflow ("I was not expecting to see a " ++ term ++ " here:"),
                Doc.reflow $
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
          ( Doc.reflow ("I was not expecting to run into the `" ++ keyword ++ "` keyword here:"),
            toDeclStartKeywordHint keyword
          )

toDeclStartKeywordHint :: String -> Doc.Doc
toDeclStartKeywordHint keyword =
  case keyword of
    "import" ->
      Doc.reflow $
        "It is reserved for declaring imports at the top of your module. If you want\
        \ another import, try moving it up top with the other imports. If you want to\
        \ define a value or function, try changing the name to something else!"
    "case" ->
      Doc.stack
        [ Doc.reflow "It is reserved for writing `case` expressions. Try using a different name?",
          Doc.toSimpleNote $
            "If you are trying to write a `case` expression, it needs to be part of a\
            \ definition. So you could write something like this instead:",
          Doc.indent 4 $
            Doc.vcat
              [ Doc.indent 0 $ Doc.fillSep ["getWidth", "maybeWidth", "="],
                Doc.indent 2 $ Doc.fillSep [Doc.cyan "case", "maybeWidth", Doc.cyan "of"],
                Doc.indent 4 $ Doc.fillSep [Doc.blue "Just", "width", "->"],
                Doc.indent 6 $ Doc.fillSep ["width", "+", Doc.dullyellow "200"],
                "",
                Doc.indent 4 $ Doc.fillSep [Doc.blue "Nothing", "->"],
                Doc.indent 6 $ Doc.fillSep [Doc.dullyellow "400"]
              ],
          Doc.reflow "This defines a `getWidth` function that you can use elsewhere in your program."
        ]
    "if" ->
      Doc.stack
        [ Doc.reflow "It is reserved for writing `if` expressions. Try using a different name?",
          Doc.toSimpleNote $
            "If you are trying to write an `if` expression, it needs to be part of a\
            \ definition. So you could write something like this instead:",
          Doc.indent 4 $
            Doc.vcat
              [ "greet name =",
                Doc.fillSep
                  [ " ",
                    Doc.cyan "if",
                    "name",
                    "==",
                    Doc.dullyellow "\"Abraham Lincoln\"",
                    Doc.cyan "then",
                    Doc.dullyellow "\"Greetings Mr. President.\"",
                    Doc.cyan "else",
                    Doc.dullyellow "\"Hey!\""
                  ]
              ],
          Doc.reflow "This defines a `reviewPowerLevel` function that you can use elsewhere in your program."
        ]
    _ ->
      Doc.reflow "It is a reserved word. Try changing the name to something else?"

toDeclStartUpperReport :: Code.Source -> Row -> Col -> Char.Char -> String -> Report.Report
toDeclStartUpperReport source row col c cs =
  let region = toRegion row col
   in Report.Report "UNEXPECTED CAPITAL LETTER" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "Declarations always start with a lower-case letter, so I am getting stuck here:",
            Doc.stack
              [ Doc.fillSep
                  [ "Try",
                    "a",
                    "name",
                    "like",
                    Doc.green (Doc.fromChars (Char.toLower c : cs)),
                    "instead?"
                  ],
                Doc.toSimpleNote "Here are a couple valid declarations for reference:",
                Doc.indent 4 $
                  Doc.vcat
                    [ "greet : String -> String",
                      "greet name =",
                      "  " <> Doc.dullyellow "\"Hello \"" <> " ++ name ++ " <> Doc.dullyellow "\"!\"",
                      "",
                      Doc.cyan "type" <> " User = Anonymous | LoggedIn String"
                    ],
                Doc.reflow "Notice that they always start with a lower-case letter. Capitalization matters!"
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
          ( Doc.reflow ("I am getting stuck because this line starts with the " ++ [char] ++ " symbol:"),
            Doc.stack
              [ Doc.reflow "When a line has no spaces at the beginning, I expect it to be a declaration like one of these:",
                Doc.indent 4 $
                  Doc.vcat
                    [ "greet : String -> String",
                      "greet name =",
                      "  " <> Doc.dullyellow "\"Hello \"" <> " ++ name ++ " <> Doc.dullyellow "\"!\"",
                      "",
                      Doc.cyan "type" <> " User = Anonymous | LoggedIn String"
                    ],
                Doc.reflow "If this is not supposed to be a declaration, try adding some spaces before it?"
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
          ( Doc.reflow "I am trying to parse a declaration, but I am getting stuck here:",
            Doc.stack
              [ Doc.reflow "When a line has no spaces at the beginning, I expect it to be a declaration like one of these:",
                Doc.indent 4 $
                  Doc.vcat
                    [ "greet : String -> String",
                      "greet name =",
                      "  " <> Doc.dullyellow "\"Hello \"" <> " ++ name ++ " <> Doc.dullyellow "\"!\"",
                      "",
                      Doc.cyan "type" <> " User = Anonymous | LoggedIn String"
                    ],
                Doc.reflow $
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
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toKeywordRegion row col keyword
       in Report.Report "RESERVED WORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow "I cannot handle ports with names like this:",
                Doc.reflow ("You are trying to make a port named `" ++ keyword ++ "` but that is a reserved word. Try using some other name?")
              )
    _ ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "PORT PROBLEM" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow "I just saw the start of a `port` declaration, but then I got stuck here:",
                Doc.stack
                  [ Doc.fillSep
                      [ "I", "was", "expecting", "to", "see", "a", "name", "like",
                        Doc.dullyellow "send", "or", Doc.dullyellow "receive", "next.",
                        "Something", "that", "starts", "with", "a", "lower-case", "letter."
                      ],
                    portNote
                  ]
              )

toPortColonReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toPortColonReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "PORT PROBLEM" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I just saw the start of a `port` declaration, but then I got stuck here:",
            Doc.stack
              [ Doc.reflow $
                  "I was expecting to see a colon next. And then a type that tells me\
                  \ what type of values are going to flow through.",
                portNote
              ]
          )

toPortIndentNameReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toPortIndentNameReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED PORT" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I just saw the start of a `port` declaration, but then I got stuck here:",
            Doc.stack
              [ Doc.fillSep
                  [ "I", "was", "expecting", "to", "see", "a", "name", "like",
                    Doc.dullyellow "send", "or", Doc.dullyellow "receive", "next.",
                    "Something", "that", "starts", "with", "a", "lower-case", "letter."
                  ],
                portNote
              ]
          )

toPortIndentColonReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toPortIndentColonReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED PORT" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I just saw the start of a `port` declaration, but then I got stuck here:",
            Doc.stack
              [ Doc.reflow $
                  "I was expecting to see a colon next. And then a type that tells me\
                  \ what type of values are going to flow through.",
                portNote
              ]
          )

toPortIndentTypeReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toPortIndentTypeReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED PORT" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I just saw the start of a `port` declaration, but then I got stuck here:",
            Doc.stack
              [ Doc.reflow $
                  "I was expecting to see a type next. Here are examples of outgoing and\
                  \ incoming ports for reference:",
                Doc.indent 4 $
                  Doc.vcat
                    [ Doc.fillSep [Doc.cyan "port", "send", ":", "String -> Cmd msg"],
                      Doc.fillSep [Doc.cyan "port", "receive", ":", "(String -> msg) -> Sub msg"]
                    ],
                Doc.reflow $
                  "The first line defines a `send` port so you can send strings out to JavaScript.\
                  \ Maybe you send them on a WebSocket or put them into IndexedDB. The second line\
                  \ defines a `receive` port so you can receive strings from JavaScript. Maybe you\
                  \ get receive messages when new WebSocket messages come in or when an entry in\
                  \ IndexedDB changes for some external reason."
              ]
          )

portNote :: Doc.Doc
portNote =
  Doc.stack
    [ Doc.toSimpleNote "Here are some example `port` declarations for reference:",
      Doc.indent 4 $
        Doc.vcat
          [ Doc.fillSep [Doc.cyan "port", "send", ":", "String -> Cmd msg"],
            Doc.fillSep [Doc.cyan "port", "receive", ":", "(String -> msg) -> Sub msg"]
          ],
      Doc.reflow $
        "The first line defines a `send` port so you can send strings out to JavaScript.\
        \ Maybe you send them on a WebSocket or put them into IndexedDB. The second line\
        \ defines a `receive` port so you can receive strings from JavaScript. Maybe you\
        \ get receive messages when new WebSocket messages come in or when the IndexedDB\
        \ is changed for some external reason."
    ]
