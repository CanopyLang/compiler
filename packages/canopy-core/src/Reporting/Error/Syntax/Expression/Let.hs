{-# LANGUAGE OverloadedStrings #-}

-- | Syntax error rendering for let expressions.
--
-- This module handles rendering of parse errors for let expressions,
-- including let definitions, let destructuring, and unfinished let bindings.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Expression.Let
  ( toLetReport,
    toUnfinishLetReport,
    toLetDefReport,
    toLetDestructReport,
  )
where

import qualified Canopy.Data.Name as Name
import Data.Word (Word16)
import Parse.Primitives (Col, Row)
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import Reporting.Error.Syntax.Expression.Function
  ( declDefNote,
    defNote,
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
  ( Def (..),
    Destruct (..),
    Expr (..),
    Let (..),
  )
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report

-- | Type alias for the recursive expression reporter.
type ExprReporter = Code.Source -> Context -> Expr -> Row -> Col -> Report.Report

-- | Render a let expression parse error.
--
-- Takes an expression reporter callback to handle recursive expression errors.
toLetReport :: ExprReporter -> Code.Source -> Context -> Let -> Row -> Col -> Report.Report
toLetReport exprReport source context let_ startRow startCol =
  case let_ of
    LetSpace space row col ->
      toSpaceReport source space row col
    LetIn row col ->
      toLetInReport source startRow startCol row col
    LetDefAlignment _ row col ->
      toLetDefAlignmentReport source startRow startCol row col
    LetDefName row col ->
      toLetDefNameReport source startRow startCol row col
    LetDef name def row col ->
      toLetDefReport exprReport source name def row col
    LetDestruct destruct row col ->
      toLetDestructReport exprReport source destruct row col
    LetBody expr row col ->
      exprReport source context expr row col
    LetIndentDef row col ->
      toUnfinishLetReport source row col startRow startCol $
        Doc.reflow $
          "I was expecting a value to be defined here."
    LetIndentIn row col ->
      toUnfinishLetReport source row col startRow startCol $
        Doc.fillSep $
          [ "I",
            "was",
            "expecting",
            "to",
            "see",
            "the",
            Doc.cyan "in",
            "keyword",
            "next.",
            "Or",
            "maybe",
            "more",
            "of",
            "that",
            "expression?"
          ]
    LetIndentBody row col ->
      toUnfinishLetReport source row col startRow startCol $
        Doc.reflow $
          "I was expecting an expression next. Tell me what should happen with the value you just defined!"

toLetInReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toLetInReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "LET PROBLEM" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I was partway through parsing a `let` expression, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep $
                  [ "Based",
                    "on",
                    "the",
                    "indentation,",
                    "I",
                    "was",
                    "expecting",
                    "to",
                    "see",
                    "the",
                    Doc.cyan "in",
                    "keyword",
                    "next.",
                    "Is",
                    "there",
                    "a",
                    "typo?"
                  ],
                Doc.toSimpleNote $
                  "This can also happen if you are trying to define another value within the `let` but\
                  \ it is not indented enough. Make sure each definition has exactly the same amount of\
                  \ spaces before it. They should line up exactly!"
              ]
          )

toLetDefAlignmentReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toLetDefAlignmentReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "LET PROBLEM" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I was partway through parsing a `let` expression, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep $
                  [ "Based",
                    "on",
                    "the",
                    "indentation,",
                    "I",
                    "was",
                    "expecting",
                    "to",
                    "see",
                    "the",
                    Doc.cyan "in",
                    "keyword",
                    "next.",
                    "Is",
                    "there",
                    "a",
                    "typo?"
                  ],
                Doc.toSimpleNote $
                  "This can also happen if you are trying to define another value within the `let` but\
                  \ it is not indented enough. Make sure each definition has exactly the same amount of\
                  \ spaces before it. They should line up exactly!"
              ]
          )

toLetDefNameReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toLetDefNameReport source startRow startCol row col =
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
                  "I was partway through parsing a `let` expression, but I got stuck here:",
                Doc.reflow $
                  "It looks like you are trying to use `" ++ keyword
                    ++ "` as a variable name, but\
                       \ it is a reserved word! Try using a different name instead."
              )
    _ ->
      toUnfinishLetReport source row col startRow startCol $
        Doc.reflow $
          "I was expecting the name of a definition next."

-- | Render an unfinished let expression error.
toUnfinishLetReport :: Code.Source -> Row -> Col -> Row -> Col -> Doc.Doc -> Report.Report
toUnfinishLetReport source row col startRow startCol message =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED LET" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I was partway through parsing a `let` expression, but I got stuck here:",
            Doc.stack
              [ message,
                Doc.toSimpleNote $
                  "Here is an example with a valid `let` expression for reference:",
                Doc.indent 4 $
                  Doc.vcat $
                    [ Doc.indent 0 $ Doc.fillSep ["viewPerson", "person", "="],
                      Doc.indent 2 $ Doc.fillSep [Doc.cyan "let"],
                      Doc.indent 4 $ Doc.fillSep ["fullName", "="],
                      Doc.indent 6 $ Doc.fillSep ["person.firstName", "++", Doc.dullyellow "\" \"", "++", "person.lastName"],
                      Doc.indent 2 $ Doc.fillSep [Doc.cyan "in"],
                      Doc.indent 2 $ Doc.fillSep ["div", "[]", "[", "text", "fullName", "]"]
                    ],
                Doc.reflow $
                  "Here we defined a `viewPerson` function that turns a person into some HTML. We use\
                  \ a `let` expression to define the `fullName` we want to show. Notice the indentation! The\
                  \ `fullName` is indented more than the `let` keyword, and the actual value of `fullName` is\
                  \ indented a bit more than that. That is important!"
              ]
          )

-- | Render a let definition parse error.
--
-- Takes an expression reporter callback to handle recursive expression errors.
toLetDefReport :: ExprReporter -> Code.Source -> Name.Name -> Def -> Row -> Col -> Report.Report
toLetDefReport exprReport source name def startRow startCol =
  case def of
    DefSpace space row col ->
      toSpaceReport source space row col
    DefType tipe row col ->
      toTypeReport source (TC_Annotation name) tipe row col
    DefNameRepeat row col ->
      toDefNameRepeatReport source name startRow startCol row col
    DefNameMatch defName row col ->
      toDefNameMatchReport source name defName startRow startCol row col
    DefArg pattern row col ->
      toPatternReport source PArg pattern row col
    DefEquals row col ->
      toDefEqualsReport source name startRow startCol row col
    DefBody expr row col ->
      exprReport source (InDef name startRow startCol) expr row col
    DefIndentEquals row col ->
      toDefIndentEqualsReport source name startRow startCol row col
    DefIndentType row col ->
      toDefIndentTypeReport source name startRow startCol row col
    DefIndentBody row col ->
      toDefIndentBodyReport source name startRow startCol row col
    DefAlignment indent row col ->
      toDefAlignmentReport source name indent startRow startCol row col

toDefNameRepeatReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDefNameRepeatReport source name startRow startCol row col =
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
                  \ definition, without anything else in between.",
                defNote
              ]
          )

toDefNameMatchReport :: Code.Source -> Name.Name -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDefNameMatchReport source name defName startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "NAME MISMATCH" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I just saw a type annotation for `" ++ Name.toChars name ++ "`, but it is followed by a definition for `" ++ Name.toChars defName ++ "`:",
            Doc.stack
              [ Doc.reflow $
                  "These names do not match! Is there a typo?",
                Doc.indent 4 $
                  Doc.fillSep $
                    [Doc.dullyellow (Doc.fromName defName), "->", Doc.green (Doc.fromName name)]
              ]
          )

toDefEqualsReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDefEqualsReport source name startRow startCol row col =
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
                  [ "The",
                    "name",
                    "`" <> Doc.cyan (Doc.fromChars keyword) <> "`",
                    "is",
                    "reserved",
                    "in",
                    "Canopy,",
                    "so",
                    "it",
                    "cannot",
                    "be",
                    "used",
                    "as",
                    "an",
                    "argument",
                    "here:"
                  ],
                toDefEqualsKeywordNote keyword
              )
    Code.Operator "->" ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toWiderRegion row col 2
       in Report.Report "MISSING COLON?" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I was not expecting to see an arrow here:",
                toMissingColonNote name
              )
    Code.Operator op ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toKeywordRegion row col op
       in Report.Report "UNEXPECTED SYMBOL" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I was not expecting to see this symbol here:",
                toUnexpectedSymbolNote name
              )
    _ ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "PROBLEM IN DEFINITION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I got stuck while parsing the `" ++ Name.toChars name ++ "` definition:",
                toProblemInDefNote
              )

toDefEqualsKeywordNote :: String -> Doc.Doc
toDefEqualsKeywordNote keyword =
  Doc.stack
    [ Doc.reflow $
        "Try renaming it to something else.",
      if keyword == "as"
        then
          Doc.toFancyNote
            [ "This",
              "keyword",
              "is",
              "reserved",
              "for",
              "pattern",
              "matches",
              "like",
              "((x,y)",
              Doc.cyan "as",
              "point)",
              "where",
              "you",
              "want",
              "to",
              "name",
              "a",
              "tuple",
              "and",
              "the",
              "values",
              "it",
              "contains."
            ]
        else
          Doc.toSimpleNote $
            "The `" ++ keyword ++ "` keyword has a special meaning in Canopy, so it can only be used in certain situations."
    ]

toMissingColonNote :: Name.Name -> Doc.Doc
toMissingColonNote name =
  Doc.stack
    [ Doc.fillSep
        [ "This",
          "usually",
          "means",
          "a",
          Doc.green ":",
          "is",
          "missing",
          "a",
          "bit",
          "earlier",
          "in",
          "a",
          "type",
          "annotation.",
          "It",
          "could",
          "be",
          "something",
          "else",
          "though,",
          "so",
          "here",
          "is",
          "a",
          "valid",
          "definition",
          "for",
          "reference:"
        ],
      Doc.indent 4 $
        Doc.vcat $
          [ "greet : String -> String",
            "greet name =",
            "  " <> Doc.dullyellow "\"Hello \"" <> " ++ name ++ " <> Doc.dullyellow "\"!\""
          ],
      Doc.reflow $
        "Try to use that format with your `" ++ Name.toChars name ++ "` definition!"
    ]

toUnexpectedSymbolNote :: Name.Name -> Doc.Doc
toUnexpectedSymbolNote name =
  Doc.stack
    [ Doc.reflow $
        "I am not sure what is going wrong exactly, so here is a valid\
        \ definition (with an optional type annotation) for reference:",
      Doc.indent 4 $
        Doc.vcat $
          [ "greet : String -> String",
            "greet name =",
            "  " <> Doc.dullyellow "\"Hello \"" <> " ++ name ++ " <> Doc.dullyellow "\"!\""
          ],
      Doc.reflow $
        "Try to use that format with your `" ++ Name.toChars name ++ "` definition!"
    ]

toProblemInDefNote :: Doc.Doc
toProblemInDefNote =
  Doc.stack
    [ Doc.reflow $
        "I am not sure what is going wrong exactly, so here is a valid\
        \ definition (with an optional type annotation) for reference:",
      Doc.indent 4 $
        Doc.vcat $
          [ "greet : String -> String",
            "greet name =",
            "  " <> Doc.dullyellow "\"Hello \"" <> " ++ name ++ " <> Doc.dullyellow "\"!\""
          ],
      Doc.reflow $
        "Try to use that format!"
    ]

toDefIndentEqualsReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDefIndentEqualsReport source name startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED DEFINITION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I got stuck while parsing the `" ++ Name.toChars name ++ "` definition:",
            Doc.stack
              [ Doc.reflow $
                  "I was expecting to see an argument or an equals sign next.",
                defNote
              ]
          )

toDefIndentTypeReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDefIndentTypeReport source name startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED DEFINITION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I got stuck while parsing the `" ++ Name.toChars name ++ "` type annotation:",
            Doc.stack
              [ Doc.reflow $
                  "I just saw a colon, so I am expecting to see a type next.",
                defNote
              ]
          )

toDefIndentBodyReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toDefIndentBodyReport source name startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED DEFINITION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I got stuck while parsing the `" ++ Name.toChars name ++ "` definition:",
            Doc.stack
              [ Doc.reflow $
                  "I was expecting to see an expression next. What is it equal to?",
                declDefNote
              ]
          )

toDefAlignmentReport :: Code.Source -> Name.Name -> Word16 -> Row -> Col -> Row -> Col -> Report.Report
toDefAlignmentReport source name indent startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
      indentInt = fromIntegral indent :: Int
      colInt = fromIntegral col :: Int
      offset = indentInt - colInt
   in Report.Report "PROBLEM IN DEFINITION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I got stuck while parsing the `" ++ Name.toChars name ++ "` definition:",
            Doc.reflow $
              "I just saw a type annotation indented " ++ show indentInt
                ++ " spaces, so I was\
                   \ expecting to see the corresponding definition next with the exact same amount\
                   \ of indentation. It looks like this line needs "
                ++ show offset
                ++ " more "
                ++ (if offset == 1 then "space" else "spaces")
                ++ "?"
          )

-- | Render a let destructuring parse error.
--
-- Takes an expression reporter callback to handle recursive expression errors.
toLetDestructReport :: ExprReporter -> Code.Source -> Destruct -> Row -> Col -> Report.Report
toLetDestructReport exprReport source destruct startRow startCol =
  case destruct of
    DestructSpace space row col ->
      toSpaceReport source space row col
    DestructPattern pattern row col ->
      toPatternReport source PLet pattern row col
    DestructEquals row col ->
      toDestructEqualsReport source startRow startCol row col
    DestructBody expr row col ->
      exprReport source (InDestruct startRow startCol) expr row col
    DestructIndentEquals row col ->
      toDestructIndentEqualsReport source startRow startCol row col
    DestructIndentBody row col ->
      toDestructIndentBodyReport source startRow startCol row col

toDestructEqualsReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toDestructEqualsReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "PROBLEM IN DEFINITION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I got stuck trying to parse this definition:",
            case Code.whatIsNext source row col of
              Code.Operator ":" ->
                Doc.stack
                  [ Doc.reflow $
                      "I was expecting to see an equals sign next, followed by an expression\
                      \ telling me what to compute.",
                    Doc.toSimpleNote $
                      "It looks like you may be trying to write a type annotation? It is not\
                      \ possible to add type annotations on destructuring definitions like this.\
                      \ You can assign a name to the overall structure, put a type annotation on\
                      \ that, and then destructure separately though."
                  ]
              _ ->
                Doc.reflow $
                  "I was expecting to see an equals sign next, followed by an expression\
                  \ telling me what to compute."
          )

toDestructIndentEqualsReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toDestructIndentEqualsReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED DEFINITION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I got stuck trying to parse this definition:",
            Doc.reflow $
              "I was expecting to see an equals sign next, followed by an expression\
              \ telling me what to compute."
          )

toDestructIndentBodyReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toDestructIndentBodyReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED DEFINITION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I got stuck while parsing this definition:",
            Doc.reflow $
              "I was expecting to see an expression next. What is it equal to?"
          )
