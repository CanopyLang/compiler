{-# LANGUAGE OverloadedStrings #-}

-- | Syntax error rendering for anonymous function expressions.
--
-- This module handles rendering of parse errors for anonymous functions
-- (lambda expressions) and provides shared documentation notes used
-- across expression error reporting.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Expression.Function
  ( toFuncReport,
    defNote,
    declDefNote,
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
import Reporting.Error.Syntax.Pattern
  ( PContext (..),
    toPatternReport,
  )
import Reporting.Error.Syntax.Types
  ( Expr (..),
    Func (..),
  )
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report
import Prelude hiding (Char, String)

-- | Type alias for the recursive expression reporter.
type ExprReporter = Code.Source -> Context -> Expr -> Row -> Col -> Report.Report

-- | Render an anonymous function parse error.
--
-- Takes an expression reporter callback to handle recursive expression errors.
toFuncReport :: ExprReporter -> Code.Source -> Context -> Func -> Row -> Col -> Report.Report
toFuncReport exprReport source context func startRow startCol =
  case func of
    FuncSpace space row col ->
      toSpaceReport source space row col
    FuncArg pattern row col ->
      toPatternReport source PArg pattern row col
    FuncBody expr row col ->
      exprReport source (InNode NFunc startRow startCol context) expr row col
    FuncArrow row col ->
      toFuncArrowReport source startRow startCol row col
    FuncIndentArg row col ->
      toFuncIndentArgReport source startRow startCol row col
    FuncIndentArrow row col ->
      toFuncIndentArrowReport source startRow startCol row col
    FuncIndentBody row col ->
      toFuncIndentBodyReport source startRow startCol row col

toFuncArrowReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toFuncArrowReport source startRow startCol row col =
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
                  "I was parsing an anonymous function, but I got stuck here:",
                Doc.reflow $
                  "It looks like you are trying to use `" ++ keyword
                    ++ "` as an argument, but\
                       \ it is a reserved word in this language. Try using a different argument name!"
              )
    _ ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED ANONYMOUS FUNCTION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I just saw the beginning of an anonymous function, so I was expecting to see an arrow next:",
                Doc.fillSep $
                  [ "The",
                    "syntax",
                    "for",
                    "anonymous",
                    "functions",
                    "is",
                    Doc.dullyellow "(\\x -> x + 1)",
                    "so",
                    "I",
                    "am",
                    "missing",
                    "the",
                    "arrow",
                    "and",
                    "the",
                    "body",
                    "of",
                    "the",
                    "function."
                  ]
              )

toFuncIndentArgReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toFuncIndentArgReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "MISSING ARGUMENT" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I just saw the beginning of an anonymous function, so I was expecting to see an argument next:",
            Doc.stack
              [ Doc.fillSep
                  [ "Something",
                    "like",
                    Doc.dullyellow "x",
                    "or",
                    Doc.dullyellow "name" <> ".",
                    "Anything",
                    "that",
                    "starts",
                    "with",
                    "a",
                    "lower",
                    "case",
                    "letter!"
                  ],
                Doc.toSimpleNote $
                  "The syntax for anonymous functions is (\\x -> x + 1) where the backslash\
                  \ is meant to look a bit like a lambda if you squint. This visual pun seemed\
                  \ like a better idea at the time!"
              ]
          )

toFuncIndentArrowReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toFuncIndentArrowReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED ANONYMOUS FUNCTION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I just saw the beginning of an anonymous function, so I was expecting to see an arrow next:",
            Doc.stack
              [ Doc.fillSep $
                  [ "The",
                    "syntax",
                    "for",
                    "anonymous",
                    "functions",
                    "is",
                    Doc.dullyellow "(\\x -> x + 1)",
                    "so",
                    "I",
                    "am",
                    "missing",
                    "the",
                    "arrow",
                    "and",
                    "the",
                    "body",
                    "of",
                    "the",
                    "function."
                  ],
                Doc.toSimpleNote $
                  "It is possible that I am confused about indetation! I generally recommend\
                  \ switching to named functions if the definition cannot fit inline nicely, so\
                  \ either (1) try to fit the whole anonymous function on one line or (2) break\
                  \ the whole thing out into a named function. Things tend to be clearer that way!"
              ]
          )

toFuncIndentBodyReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toFuncIndentBodyReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED ANONYMOUS FUNCTION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I was expecting to see the body of your anonymous function next:",
            Doc.stack
              [ Doc.fillSep $
                  [ "The",
                    "syntax",
                    "for",
                    "anonymous",
                    "functions",
                    "is",
                    Doc.dullyellow "(\\x -> x + 1)",
                    "so",
                    "I",
                    "am",
                    "missing",
                    "all",
                    "the",
                    "stuff",
                    "after",
                    "the",
                    "arrow!"
                  ],
                Doc.toSimpleNote $
                  "It is possible that I am confused about indetation! I generally recommend\
                  \ switching to named functions if the definition cannot fit inline nicely, so\
                  \ either (1) try to fit the whole anonymous function on one line or (2) break\
                  \ the whole thing out into a named function. Things tend to be clearer that way!"
              ]
          )

-- | Documentation note for definition format.
defNote :: Doc.Doc
defNote =
  Doc.stack
    [ Doc.reflow $
        "Here is a valid definition (with a type annotation) for reference:",
      Doc.indent 4 $
        Doc.vcat $
          [ "greet : String -> String",
            "greet name =",
            "  " <> Doc.dullyellow "\"Hello \"" <> " ++ name ++ " <> Doc.dullyellow "\"!\""
          ],
      Doc.reflow $
        "The top line (called a \"type annotation\") is optional. You can leave it off\
        \ if you want. As you get more comfortable with Canopy and as your project grows,\
        \ it becomes more and more valuable to add them though! They work great as\
        \ compiler-verified documentation, and they often improve error messages!"
    ]

-- | Documentation note for declaration definition format.
declDefNote :: Doc.Doc
declDefNote =
  Doc.stack
    [ Doc.reflow $
        "Here is a valid definition (with a type annotation) for reference:",
      Doc.indent 4 $
        Doc.vcat $
          [ "greet : String -> String",
            "greet name =",
            "  " <> Doc.dullyellow "\"Hello \"" <> " ++ name ++ " <> Doc.dullyellow "\"!\""
          ],
      Doc.reflow $
        "The top line (called a \"type annotation\") is optional. You can leave it off\
        \ if you want. As you get more comfortable with Canopy and as your project grows,\
        \ it becomes more and more valuable to add them though! They work great as\
        \ compiler-verified documentation, and they often improve error messages!"
    ]
