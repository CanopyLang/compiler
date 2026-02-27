{-# LANGUAGE OverloadedStrings #-}

-- | Syntax error rendering for expressions.
--
-- This module handles rendering of parse errors for all expression types,
-- including let expressions, case expressions, if expressions, records,
-- tuples, lists, and anonymous functions.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Expression
  ( toExprReport,
    toLetReport,
    toUnfinishLetReport,
    toLetDefReport,
    toLetDestructReport,
    toCaseReport,
    toUnfinishCaseReport,
    toIfReport,
    toRecordReport,
    toTupleReport,
    toListReport,
    toFuncReport,
    declDefNote,
  )
where

import qualified Data.Name as Name
import Parse.Primitives (Col, Row)
import Parse.Symbol (BadOperator (..))
import qualified Reporting.Annotation as A
import qualified Reporting.Doc as D
import Reporting.Error.Syntax.Helpers
  ( Context (..),
    Node (..),
    noteForCaseError,
    noteForCaseIndentError,
    toKeywordRegion,
    toRegion,
    toSpaceReport,
    toWiderRegion,
  )
import Reporting.Error.Syntax.Literal
  ( toCharReport,
    toNumberReport,
    toOperatorReport,
    toStringReport,
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
  ( Case (..),
    Def (..),
    Destruct (..),
    Expr (..),
    Func (..),
    If (..),
    Let (..),
    List (..),
    Record (..),
    Tuple (..),
  )
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report
import Prelude hiding (Char, String)

-- | Render an expression parse error.
toExprReport :: Code.Source -> Context -> Expr -> Row -> Col -> Report.Report
toExprReport source context expr startRow startCol =
  case expr of
    Let let_ row col ->
      toLetReport source context let_ row col
    Case case_ row col ->
      toCaseReport source context case_ row col
    If if_ row col ->
      toIfReport source context if_ row col
    List list row col ->
      toListReport source context list row col
    Record record row col ->
      toRecordReport source context record row col
    Tuple tuple row col ->
      toTupleReport source context tuple row col
    Func func row col ->
      toFuncReport source context func row col
    Dot row col ->
      let region = toRegion row col
       in Report.Report "EXPECTING RECORD ACCESSOR" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow $
                  "I was expecting to see a record accessor here:",
                D.fillSep
                  [ "Something",
                    "like",
                    D.dullyellow ".name",
                    "or",
                    D.dullyellow ".price",
                    "that",
                    "accesses",
                    "a",
                    "value",
                    "from",
                    "a",
                    "record."
                  ]
              )
    Access row col ->
      let region = toRegion row col
       in Report.Report "EXPECTING RECORD ACCESSOR" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow $
                  "I am trying to parse a record accessor here:",
                D.stack
                  [ D.fillSep
                      [ "Something",
                        "like",
                        D.dullyellow ".name",
                        "or",
                        D.dullyellow ".price",
                        "that",
                        "accesses",
                        "a",
                        "value",
                        "from",
                        "a",
                        "record."
                      ],
                    D.toSimpleNote $
                      "Record field names must start with a lower case letter!"
                  ]
              )
    OperatorRight op row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
          isMath = elem op ["-", "+", "*", "/", "^"]
       in Report.Report "MISSING EXPRESSION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I just saw a " ++ Name.toChars op ++ " "
                    ++ (if isMath then "sign" else "operator")
                    ++ ", so I am getting stuck here:",
                if isMath
                  then
                    D.fillSep
                      [ "I",
                        "was",
                        "expecting",
                        "to",
                        "see",
                        "an",
                        "expression",
                        "next.",
                        "Something",
                        "like",
                        D.dullyellow "42",
                        "or",
                        D.dullyellow "1000",
                        "that",
                        "makes",
                        "sense",
                        "with",
                        "a",
                        D.fromName op,
                        "sign."
                      ]
                  else
                    if op == "&&" || op == "||"
                      then
                        D.fillSep
                          [ "I",
                            "was",
                            "expecting",
                            "to",
                            "see",
                            "an",
                            "expression",
                            "next.",
                            "Something",
                            "like",
                            D.dullyellow "True",
                            "or",
                            D.dullyellow "False",
                            "that",
                            "makes",
                            "sense",
                            "with",
                            "boolean",
                            "logic."
                          ]
                      else
                        if op == "|>"
                          then
                            D.reflow $
                              "I was expecting to see a function next."
                          else
                            if op == "<|"
                              then
                                D.reflow $
                                  "I was expecting to see an argument next."
                              else
                                D.reflow $
                                  "I was expecting to see an expression next."
              )
    OperatorReserved operator row col ->
      toOperatorReport source context operator row col
    Start row col ->
      let (contextRow, contextCol, aThing) =
            case context of
              InDestruct r c -> (r, c, "a definition")
              InDef name r c -> (r, c, "the `" ++ Name.toChars name ++ "` definition")
              InNode NRecord r c _ -> (r, c, "a record")
              InNode NParens r c _ -> (r, c, "some parentheses")
              InNode NList r c _ -> (r, c, "a list")
              InNode NFunc r c _ -> (r, c, "an anonymous function")
              InNode NCond r c _ -> (r, c, "an `if` expression")
              InNode NThen r c _ -> (r, c, "an `if` expression")
              InNode NElse r c _ -> (r, c, "an `if` expression")
              InNode NCase r c _ -> (r, c, "a `case` expression")
              InNode NBranch r c _ -> (r, c, "a `case` expression")

          surroundings = A.Region (A.Position contextRow contextCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "MISSING EXPRESSION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I am partway through parsing " ++ aThing ++ ", but I got stuck here:",
                D.stack
                  [ D.fillSep $
                      [ "I",
                        "was",
                        "expecting",
                        "to",
                        "see",
                        "an",
                        "expression",
                        "like",
                        D.dullyellow "42",
                        "or",
                        D.dullyellow "\"hello\"" <> ".",
                        "Once",
                        "there",
                        "is",
                        "something",
                        "there,",
                        "I",
                        "can",
                        "probably",
                        "give",
                        "a",
                        "more",
                        "specific",
                        "hint!"
                      ],
                    D.toSimpleNote $
                      "This can also happen if I run into reserved words like `let` or `as` unexpectedly.\
                      \ Or if I run into operators in unexpected spots. Point is, there are a\
                      \ couple ways I can get confused and give sort of weird advice!"
                  ]
              )
    Char char row col ->
      toCharReport source char row col
    String string row col ->
      toStringReport source string row col
    Number number row col ->
      toNumberReport source number row col
    Space space row col ->
      toSpaceReport source space row col
    EndlessShader row col ->
      let region = toWiderRegion row col 6
       in Report.Report "ENDLESS SHADER" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow "I cannot find the end of this shader:",
                D.reflow "Add a |] somewhere after this to end the shader."
              )
    ShaderProblem problem row col ->
      let region = toRegion row col
       in Report.Report "SHADER PROBLEM" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow $
                  "I ran into a problem while parsing this GLSL block.",
                D.stack
                  [ D.reflow $
                      "I use a 3rd party GLSL parser for now, and I did my best to extract their error message:",
                    D.indent 4 $
                      D.vcat $
                        map D.fromChars (filter (/= "") (lines problem))
                  ]
              )
    IndentOperatorRight op row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "MISSING EXPRESSION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I was expecting to see an expression after this " ++ Name.toChars op ++ " operator:",
                D.stack
                  [ D.fillSep $
                      [ "You",
                        "can",
                        "just",
                        "put",
                        "anything",
                        "for",
                        "now,",
                        "like",
                        D.dullyellow "42",
                        "or",
                        D.dullyellow "\"hello\"" <> ".",
                        "Once",
                        "there",
                        "is",
                        "something",
                        "there,",
                        "I",
                        "can",
                        "probably",
                        "give",
                        "a",
                        "more",
                        "specific",
                        "hint!"
                      ],
                    D.toSimpleNote $
                      "I may be getting confused by your indentation? The easiest way to make sure\
                      \ this is not an indentation problem is to put the expression on the right of\
                      \ the "
                        ++ Name.toChars op
                        ++ " operator on the same line."
                  ]
              )

-- | Render a let expression parse error.
toLetReport :: Code.Source -> Context -> Let -> Row -> Col -> Report.Report
toLetReport source context let_ startRow startCol =
  case let_ of
    LetSpace space row col ->
      toSpaceReport source space row col
    LetIn row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "LET PROBLEM" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I was partway through parsing a `let` expression, but I got stuck here:",
                D.stack
                  [ D.fillSep $
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
                        D.cyan "in",
                        "keyword",
                        "next.",
                        "Is",
                        "there",
                        "a",
                        "typo?"
                      ],
                    D.toSimpleNote $
                      "This can also happen if you are trying to define another value within the `let` but\
                      \ it is not indented enough. Make sure each definition has exactly the same amount of\
                      \ spaces before it. They should line up exactly!"
                  ]
              )
    LetDefAlignment _ row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "LET PROBLEM" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I was partway through parsing a `let` expression, but I got stuck here:",
                D.stack
                  [ D.fillSep $
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
                        D.cyan "in",
                        "keyword",
                        "next.",
                        "Is",
                        "there",
                        "a",
                        "typo?"
                      ],
                    D.toSimpleNote $
                      "This can also happen if you are trying to define another value within the `let` but\
                      \ it is not indented enough. Make sure each definition has exactly the same amount of\
                      \ spaces before it. They should line up exactly!"
                  ]
              )
    LetDefName row col ->
      case Code.whatIsNext source row col of
        Code.Keyword keyword ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
              region = toKeywordRegion row col keyword
           in Report.Report "RESERVED WORD" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I was partway through parsing a `let` expression, but I got stuck here:",
                    D.reflow $
                      "It looks like you are trying to use `" ++ keyword
                        ++ "` as a variable name, but\
                           \ it is a reserved word! Try using a different name instead."
                  )
        _ ->
          toUnfinishLetReport source row col startRow startCol $
            D.reflow $
              "I was expecting the name of a definition next."
    LetDef name def row col ->
      toLetDefReport source name def row col
    LetDestruct destruct row col ->
      toLetDestructReport source destruct row col
    LetBody expr row col ->
      toExprReport source context expr row col
    LetIndentDef row col ->
      toUnfinishLetReport source row col startRow startCol $
        D.reflow $
          "I was expecting a value to be defined here."
    LetIndentIn row col ->
      toUnfinishLetReport source row col startRow startCol $
        D.fillSep $
          [ "I",
            "was",
            "expecting",
            "to",
            "see",
            "the",
            D.cyan "in",
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
        D.reflow $
          "I was expecting an expression next. Tell me what should happen with the value you just defined!"

-- | Render an unfinished let expression error.
toUnfinishLetReport :: Code.Source -> Row -> Col -> Row -> Col -> D.Doc -> Report.Report
toUnfinishLetReport source row col startRow startCol message =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED LET" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow $
              "I was partway through parsing a `let` expression, but I got stuck here:",
            D.stack
              [ message,
                D.toSimpleNote $
                  "Here is an example with a valid `let` expression for reference:",
                D.indent 4 $
                  D.vcat $
                    [ D.indent 0 $ D.fillSep ["viewPerson", "person", "="],
                      D.indent 2 $ D.fillSep [D.cyan "let"],
                      D.indent 4 $ D.fillSep ["fullName", "="],
                      D.indent 6 $ D.fillSep ["person.firstName", "++", D.dullyellow "\" \"", "++", "person.lastName"],
                      D.indent 2 $ D.fillSep [D.cyan "in"],
                      D.indent 2 $ D.fillSep ["div", "[]", "[", "text", "fullName", "]"]
                    ],
                D.reflow $
                  "Here we defined a `viewPerson` function that turns a person into some HTML. We use\
                  \ a `let` expression to define the `fullName` we want to show. Notice the indentation! The\
                  \ `fullName` is indented more than the `let` keyword, and the actual value of `fullName` is\
                  \ indented a bit more than that. That is important!"
              ]
          )

-- | Render a let definition parse error.
toLetDefReport :: Code.Source -> Name.Name -> Def -> Row -> Col -> Report.Report
toLetDefReport source name def startRow startCol =
  case def of
    DefSpace space row col ->
      toSpaceReport source space row col
    DefType tipe row col ->
      toTypeReport source (TC_Annotation name) tipe row col
    DefNameRepeat row col ->
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
                      \ definition, without anything else in between.",
                    defNote
                  ]
              )
    DefNameMatch defName row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "NAME MISMATCH" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I just saw a type annotation for `" ++ Name.toChars name ++ "`, but it is followed by a definition for `" ++ Name.toChars defName ++ "`:",
                D.stack
                  [ D.reflow $
                      "These names do not match! Is there a typo?",
                    D.indent 4 $
                      D.fillSep $
                        [D.dullyellow (D.fromName defName), "->", D.green (D.fromName name)]
                  ]
              )
    DefArg pattern row col ->
      toPatternReport source PArg pattern row col
    DefEquals row col ->
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
                      [ "The",
                        "name",
                        "`" <> D.cyan (D.fromChars keyword) <> "`",
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
                    D.stack
                      [ D.reflow $
                          "Try renaming it to something else.",
                        case keyword of
                          "as" ->
                            D.toFancyNote
                              [ "This",
                                "keyword",
                                "is",
                                "reserved",
                                "for",
                                "pattern",
                                "matches",
                                "like",
                                "((x,y)",
                                D.cyan "as",
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
                          _ ->
                            D.toSimpleNote $
                              "The `" ++ keyword ++ "` keyword has a special meaning in Canopy, so it can only be used in certain situations."
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
                  ( D.reflow $
                      "I was not expecting to see an arrow here:",
                    D.stack
                      [ D.fillSep
                          [ "This",
                            "usually",
                            "means",
                            "a",
                            D.green ":",
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
                        D.indent 4 $
                          D.vcat $
                            [ "greet : String -> String",
                              "greet name =",
                              "  " <> D.dullyellow "\"Hello \"" <> " ++ name ++ " <> D.dullyellow "\"!\""
                            ],
                        D.reflow $
                          "Try to use that format with your `" ++ Name.toChars name ++ "` definition!"
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
                  ( D.reflow $
                      "I was not expecting to see this symbol here:",
                    D.stack
                      [ D.reflow $
                          "I am not sure what is going wrong exactly, so here is a valid\
                          \ definition (with an optional type annotation) for reference:",
                        D.indent 4 $
                          D.vcat $
                            [ "greet : String -> String",
                              "greet name =",
                              "  " <> D.dullyellow "\"Hello \"" <> " ++ name ++ " <> D.dullyellow "\"!\""
                            ],
                        D.reflow $
                          "Try to use that format with your `" ++ Name.toChars name ++ "` definition!"
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
                  ( D.reflow $
                      "I got stuck while parsing the `" ++ Name.toChars name ++ "` definition:",
                    D.stack
                      [ D.reflow $
                          "I am not sure what is going wrong exactly, so here is a valid\
                          \ definition (with an optional type annotation) for reference:",
                        D.indent 4 $
                          D.vcat $
                            [ "greet : String -> String",
                              "greet name =",
                              "  " <> D.dullyellow "\"Hello \"" <> " ++ name ++ " <> D.dullyellow "\"!\""
                            ],
                        D.reflow $
                          "Try to use that format!"
                      ]
                  )
    DefBody expr row col ->
      toExprReport source (InDef name startRow startCol) expr row col
    DefIndentEquals row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED DEFINITION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I got stuck while parsing the `" ++ Name.toChars name ++ "` definition:",
                D.stack
                  [ D.reflow $
                      "I was expecting to see an argument or an equals sign next.",
                    defNote
                  ]
              )
    DefIndentType row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED DEFINITION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I got stuck while parsing the `" ++ Name.toChars name ++ "` type annotation:",
                D.stack
                  [ D.reflow $
                      "I just saw a colon, so I am expecting to see a type next.",
                    defNote
                  ]
              )
    DefIndentBody row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED DEFINITION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I got stuck while parsing the `" ++ Name.toChars name ++ "` definition:",
                D.stack
                  [ D.reflow $
                      "I was expecting to see an expression next. What is it equal to?",
                    declDefNote
                  ]
              )
    DefAlignment indent row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
          offset = indent - col
       in Report.Report "PROBLEM IN DEFINITION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I got stuck while parsing the `" ++ Name.toChars name ++ "` definition:",
                D.reflow $
                  "I just saw a type annotation indented " ++ show indent
                    ++ " spaces, so I was\
                       \ expecting to see the corresponding definition next with the exact same amount\
                       \ of indentation. It looks like this line needs "
                    ++ show offset
                    ++ " more "
                    ++ (if offset == 1 then "space" else "spaces")
                    ++ "?"
              )

-- | Render a let destructuring parse error.
toLetDestructReport :: Code.Source -> Destruct -> Row -> Col -> Report.Report
toLetDestructReport source destruct startRow startCol =
  case destruct of
    DestructSpace space row col ->
      toSpaceReport source space row col
    DestructPattern pattern row col ->
      toPatternReport source PLet pattern row col
    DestructEquals row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "PROBLEM IN DEFINITION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I got stuck trying to parse this definition:",
                case Code.whatIsNext source row col of
                  Code.Operator ":" ->
                    D.stack
                      [ D.reflow $
                          "I was expecting to see an equals sign next, followed by an expression\
                          \ telling me what to compute.",
                        D.toSimpleNote $
                          "It looks like you may be trying to write a type annotation? It is not\
                          \ possible to add type annotations on destructuring definitions like this.\
                          \ You can assign a name to the overall structure, put a type annotation on\
                          \ that, and then destructure separately though."
                      ]
                  _ ->
                    D.reflow $
                      "I was expecting to see an equals sign next, followed by an expression\
                      \ telling me what to compute."
              )
    DestructBody expr row col ->
      toExprReport source (InDestruct startRow startCol) expr row col
    DestructIndentEquals row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED DEFINITION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I got stuck trying to parse this definition:",
                D.reflow $
                  "I was expecting to see an equals sign next, followed by an expression\
                  \ telling me what to compute."
              )
    DestructIndentBody row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED DEFINITION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I got stuck while parsing this definition:",
                D.reflow $
                  "I was expecting to see an expression next. What is it equal to?"
              )

-- | Render a case expression parse error.
toCaseReport :: Code.Source -> Context -> Case -> Row -> Col -> Report.Report
toCaseReport source context case_ startRow startCol =
  case case_ of
    CaseSpace space row col ->
      toSpaceReport source space row col
    CaseOf row col ->
      toUnfinishCaseReport source row col startRow startCol $
        D.fillSep ["I", "was", "expecting", "to", "see", "the", D.dullyellow "of", "keyword", "next."]
    CasePattern pattern row col ->
      toPatternReport source PCase pattern row col
    CaseArrow row col ->
      case Code.whatIsNext source row col of
        Code.Keyword keyword ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
              region = toKeywordRegion row col keyword
           in Report.Report "RESERVED WORD" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I am partway through parsing a `case` expression, but I got stuck here:",
                    D.reflow $
                      "It looks like you are trying to use `" ++ keyword
                        ++ "` in one of your\
                           \ patterns, but it is a reserved word. Try using a different name?"
                  )
        Code.Operator ":" ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
              region = toRegion row col
           in Report.Report "UNEXPECTED OPERATOR" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I am partway through parsing a `case` expression, but I got stuck here:",
                    D.fillSep $
                      [ "I",
                        "am",
                        "seeing",
                        D.dullyellow ":",
                        "but",
                        "maybe",
                        "you",
                        "want",
                        D.green "::",
                        "instead?",
                        "For",
                        "pattern",
                        "matching",
                        "on",
                        "lists?"
                      ]
                  )
        Code.Operator "=" ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
              region = toRegion row col
           in Report.Report "UNEXPECTED OPERATOR" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I am partway through parsing a `case` expression, but I got stuck here:",
                    D.fillSep $
                      [ "I",
                        "am",
                        "seeing",
                        D.dullyellow "=",
                        "but",
                        "maybe",
                        "you",
                        "want",
                        D.green "->",
                        "instead?"
                      ]
                  )
        _ ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
              region = toRegion row col
           in Report.Report "MISSING ARROW" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I am partway through parsing a `case` expression, but I got stuck here:",
                    D.stack
                      [ D.reflow "I was expecting to see an arrow next.",
                        noteForCaseIndentError
                      ]
                  )
    CaseExpr expr row col ->
      toExprReport source (InNode NCase startRow startCol context) expr row col
    CaseBranch expr row col ->
      toExprReport source (InNode NBranch startRow startCol context) expr row col
    CaseIndentOf row col ->
      toUnfinishCaseReport source row col startRow startCol $
        D.fillSep ["I", "was", "expecting", "to", "see", "the", D.dullyellow "of", "keyword", "next."]
    CaseIndentExpr row col ->
      toUnfinishCaseReport source row col startRow startCol $
        D.reflow "I was expecting to see a expression next."
    CaseIndentPattern row col ->
      toUnfinishCaseReport source row col startRow startCol $
        D.reflow "I was expecting to see a pattern next."
    CaseIndentArrow row col ->
      toUnfinishCaseReport source row col startRow startCol $
        D.fillSep
          [ "I",
            "just",
            "saw",
            "a",
            "pattern,",
            "so",
            "I",
            "was",
            "expecting",
            "to",
            "see",
            "a",
            D.dullyellow "->",
            "next."
          ]
    CaseIndentBranch row col ->
      toUnfinishCaseReport source row col startRow startCol $
        D.reflow $
          "I was expecting to see an expression next. What should I do when\
          \ I run into this particular pattern?"
    CasePatternAlignment indent row col ->
      toUnfinishCaseReport source row col startRow startCol $
        D.reflow $
          "I suspect this is a pattern that is not indented far enough? (" ++ show indent ++ " spaces)"

-- | Render an unfinished case expression error.
toUnfinishCaseReport :: Code.Source -> Row -> Col -> Row -> Col -> D.Doc -> Report.Report
toUnfinishCaseReport source row col startRow startCol message =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED CASE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow $
              "I was partway through parsing a `case` expression, but I got stuck here:",
            D.stack
              [ message,
                noteForCaseError
              ]
          )

-- | Render an if expression parse error.
toIfReport :: Code.Source -> Context -> If -> Row -> Col -> Report.Report
toIfReport source context if_ startRow startCol =
  case if_ of
    IfSpace space row col ->
      toSpaceReport source space row col
    IfThen row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED IF" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I was expecting to see more of this `if` expression, but I got stuck here:",
                D.fillSep $
                  [ "I",
                    "was",
                    "expecting",
                    "to",
                    "see",
                    "the",
                    D.cyan "then",
                    "keyword",
                    "next."
                  ]
              )
    IfElse row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED IF" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I was expecting to see more of this `if` expression, but I got stuck here:",
                D.fillSep $
                  [ "I",
                    "was",
                    "expecting",
                    "to",
                    "see",
                    "the",
                    D.cyan "else",
                    "keyword",
                    "next."
                  ]
              )
    IfElseBranchStart row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED IF" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I just saw the start of an `else` branch, but then I got stuck here:",
                D.reflow $
                  "I was expecting to see an expression next. Maybe it is not filled in yet?"
              )
    IfCondition expr row col ->
      toExprReport source (InNode NCond startRow startCol context) expr row col
    IfThenBranch expr row col ->
      toExprReport source (InNode NThen startRow startCol context) expr row col
    IfElseBranch expr row col ->
      toExprReport source (InNode NElse startRow startCol context) expr row col
    IfIndentCondition row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED IF" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I was expecting to see more of this `if` expression, but I got stuck here:",
                D.stack
                  [ D.fillSep $
                      [ "I",
                        "was",
                        "expecting",
                        "to",
                        "see",
                        "an",
                        "expression",
                        "like",
                        D.dullyellow "x < 0",
                        "that",
                        "evaluates",
                        "to",
                        "True",
                        "or",
                        "False."
                      ],
                    D.toSimpleNote $
                      "I can be confused by indentation. Maybe something is not indented enough?"
                  ]
              )
    IfIndentThen row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED IF" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I was expecting to see more of this `if` expression, but I got stuck here:",
                D.stack
                  [ D.fillSep $
                      [ "I",
                        "was",
                        "expecting",
                        "to",
                        "see",
                        "the",
                        D.cyan "then",
                        "keyword",
                        "next."
                      ],
                    D.toSimpleNote $
                      "I can be confused by indentation. Maybe something is not indented enough?"
                  ]
              )
    IfIndentThenBranch row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED IF" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I got stuck after the start of this `then` branch:",
                D.stack
                  [ D.reflow $
                      "I was expecting to see an expression next. Maybe it is not filled in yet?",
                    D.toSimpleNote $
                      "I can be confused by indentation, so if the `then` branch is already\
                      \ present, it may not be indented enough for me to recognize it."
                  ]
              )
    IfIndentElseBranch row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED IF" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I got stuck after the start of this `else` branch:",
                D.stack
                  [ D.reflow $
                      "I was expecting to see an expression next. Maybe it is not filled in yet?",
                    D.toSimpleNote $
                      "I can be confused by indentation, so if the `else` branch is already\
                      \ present, it may not be indented enough for me to recognize it."
                  ]
              )
    IfIndentElse row col ->
      case Code.nextLineStartsWithKeyword "else" source row of
        Just (elseRow, elseCol) ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position elseRow elseCol)
              region = toWiderRegion elseRow elseCol 4
           in Report.Report "WEIRD ELSE BRANCH" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I was partway through an `if` expression when I got stuck here:",
                    D.fillSep $
                      [ "I",
                        "think",
                        "this",
                        D.cyan "else",
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
          let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
              region = toRegion row col
           in Report.Report "UNFINISHED IF" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I was expecting to see an `else` branch after this:",
                    D.stack
                      [ D.fillSep
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
                            D.cyan "else",
                            "branch",
                            "to",
                            "handle",
                            "that",
                            "scenario!"
                          ]
                      ]
                  )

-- | Render a record expression parse error.
toRecordReport :: Code.Source -> Context -> Record -> Row -> Col -> Report.Report
toRecordReport source context record startRow startCol =
  case record of
    RecordOpen row col ->
      case Code.whatIsNext source row col of
        Code.Keyword keyword ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
              region = toKeywordRegion row col keyword
           in Report.Report "RESERVED WORD" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I just started parsing a record, but I got stuck on this field name:",
                    D.reflow $
                      "It looks like you are trying to use `" ++ keyword
                        ++ "` as a field name, but \
                           \ that is a reserved word. Try using a different name!"
                  )
        _ ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
              region = toRegion row col
           in Report.Report "PROBLEM IN RECORD" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I just started parsing a record, but I got stuck here:",
                    D.stack
                      [ D.fillSep
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
                            D.dullyellow "userName",
                            "or",
                            D.dullyellow "plantHeight" <> "."
                          ],
                        D.toSimpleNote $
                          "Field names must start with a lower-case letter. After that, you can use\
                          \ any sequence of letters, numbers, and underscores.",
                        noteForRecordError
                      ]
                  )
    RecordEnd row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "PROBLEM IN RECORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I am partway through parsing a record, but I got stuck here:",
                D.stack
                  [ D.fillSep
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
                        D.dullyellow "}",
                        "and",
                        "see",
                        "if",
                        "that",
                        "helps?"
                      ],
                    D.toSimpleNote $
                      "When I get stuck like this, it usually means that there is a missing parenthesis\
                      \ or bracket somewhere earlier. It could also be a stray keyword or operator."
                  ]
              )
    RecordField row col ->
      case Code.whatIsNext source row col of
        Code.Keyword keyword ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
              region = toKeywordRegion row col keyword
           in Report.Report "RESERVED WORD" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I am partway through parsing a record, but I got stuck on this field name:",
                    D.reflow $
                      "It looks like you are trying to use `" ++ keyword
                        ++ "` as a field name, but \
                           \ that is a reserved word. Try using a different name!"
                  )
        Code.Other (Just ',') ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
              region = toRegion row col
           in Report.Report "EXTRA COMMA" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I am partway through parsing a record, but I got stuck here:",
                    D.stack
                      [ D.reflow $
                          "I am seeing two commas in a row. This is the second one!",
                        D.reflow $
                          "Just delete one of the commas and you should be all set!",
                        noteForRecordError
                      ]
                  )
        Code.Close _ '}' ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
              region = toRegion row col
           in Report.Report "EXTRA COMMA" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I am partway through parsing a record, but I got stuck here:",
                    D.stack
                      [ D.reflow $
                          "Trailing commas are not allowed in records. Try deleting the comma that appears\
                          \ before this closing curly brace.",
                        noteForRecordError
                      ]
                  )
        _ ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
              region = toRegion row col
           in Report.Report "PROBLEM IN RECORD" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I am partway through parsing a record, but I got stuck here:",
                    D.stack
                      [ D.fillSep
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
                            D.dullyellow "userName",
                            "or",
                            D.dullyellow "plantHeight" <> "."
                          ],
                        D.toSimpleNote $
                          "Field names must start with a lower-case letter. After that, you can use\
                          \ any sequence of letters, numbers, and underscores.",
                        noteForRecordError
                      ]
                  )
    RecordEquals row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "PROBLEM IN RECORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I am partway through parsing a record, but I got stuck here:",
                D.stack
                  [ D.fillSep $
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
                        D.green "=",
                        "sign",
                        "here?"
                      ],
                    noteForRecordError
                  ]
              )
    RecordExpr expr row col ->
      toExprReport source (InNode NRecord startRow startCol context) expr row col
    RecordSpace space row col ->
      toSpaceReport source space row col
    RecordIndentOpen row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED RECORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I just saw the opening curly brace of a record, but then I got stuck here:",
                D.stack
                  [ D.fillSep $
                      [ "I",
                        "am",
                        "expecting",
                        "a",
                        "record",
                        "like",
                        D.dullyellow "{ x = 3, y = 4 }",
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
    RecordIndentEnd row col ->
      case Code.nextLineStartsWithCloseCurly source row of
        Just (curlyRow, curlyCol) ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position curlyRow curlyCol)
              region = toRegion curlyRow curlyCol
           in Report.Report "NEED MORE INDENTATION" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I was partway through parsing a record, but I got stuck here:",
                    D.stack
                      [ D.reflow $
                          "I need this curly brace to be indented more. Try adding some spaces before it!",
                        noteForRecordError
                      ]
                  )
        Nothing ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
              region = toRegion row col
           in Report.Report "UNFINISHED RECORD" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I was partway through parsing a record, but I got stuck here:",
                    D.stack
                      [ D.fillSep $
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
                            D.green "}",
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
    RecordIndentField row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED RECORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I am partway through parsing a record, but I got stuck after that last comma:",
                D.stack
                  [ D.reflow $
                      "Trailing commas are not allowed in records, so the fix may be to\
                      \ delete that last comma? Or maybe you were in the middle of defining\
                      \ an additional field?",
                    noteForRecordError
                  ]
              )
    RecordIndentEquals row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED RECORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I am partway through parsing a record. I just saw a record\
                  \ field, so I was expecting to see an equals sign next:",
                D.stack
                  [ D.fillSep $
                      [ "Try",
                        "putting",
                        "an",
                        D.green "=",
                        "followed",
                        "by",
                        "an",
                        "expression?"
                      ],
                    noteForRecordIndentError
                  ]
              )
    RecordIndentExpr row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED RECORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I am partway through parsing a record, and I was expecting to run into an expression next:",
                D.stack
                  [ D.fillSep $
                      [ "Try",
                        "putting",
                        "something",
                        "like",
                        D.dullyellow "42",
                        "or",
                        D.dullyellow "\"hello\"",
                        "for",
                        "now?"
                      ],
                    noteForRecordIndentError
                  ]
              )

-- | Render a tuple expression parse error.
toTupleReport :: Code.Source -> Context -> Tuple -> Row -> Col -> Report.Report
toTupleReport source context tuple startRow startCol =
  case tuple of
    TupleExpr expr row col ->
      toExprReport source (InNode NParens startRow startCol context) expr row col
    TupleSpace space row col ->
      toSpaceReport source space row col
    TupleEnd row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED PARENTHESES" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I was expecting to see a closing parentheses next, but I got stuck here:",
                D.stack
                  [ D.fillSep ["Try", "adding", "a", D.dullyellow ")", "to", "see", "if", "that", "helps?"],
                    D.toSimpleNote $
                      "I can get stuck when I run into keywords, operators, parentheses, or brackets\
                      \ unexpectedly. So there may be some earlier syntax trouble (like extra parenthesis\
                      \ or missing brackets) that is confusing me."
                  ]
              )
    TupleOperatorClose row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED OPERATOR FUNCTION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow "I was expecting a closing parenthesis here:",
                D.stack
                  [ D.fillSep ["Try", "adding", "a", D.dullyellow ")", "to", "see", "if", "that", "helps!"],
                    D.toSimpleNote $
                      "I think I am parsing an operator function right now, so I am expecting to see\
                      \ something like (+) or (&&) where an operator is surrounded by parentheses with\
                      \ no extra spaces."
                  ]
              )
    TupleOperatorReserved operator row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNEXPECTED SYMBOL" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I ran into an unexpected symbol here:",
                D.fillSep $
                  case operator of
                    BadDot -> ["Maybe", "you", "wanted", "a", "record", "accessor", "like", D.dullyellow ".x", "or", D.dullyellow ".name", "instead?"]
                    BadPipe -> ["Try", D.dullyellow "(||)", "instead?", "To", "turn", "boolean", "OR", "into", "a", "function?"]
                    BadArrow -> ["Maybe", "you", "wanted", D.dullyellow "(>)", "or", D.dullyellow "(>=)", "instead?"]
                    BadEquals -> ["Try", D.dullyellow "(==)", "instead?", "To", "make", "a", "function", "that", "checks", "equality?"]
                    BadHasType -> ["Try", D.dullyellow "(::)", "instead?", "To", "add", "values", "to", "the", "front", "of", "lists?"]
              )
    TupleIndentExpr1 row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED PARENTHESES" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I just saw an open parenthesis, so I was expecting to see an expression next.",
                D.stack
                  [ D.fillSep $
                      [ "Something",
                        "like",
                        D.dullyellow "(4 + 5)",
                        "or",
                        D.dullyellow "(String.reverse \"desserts\")" <> ".",
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
                    D.toSimpleNote $
                      "I can get confused by indentation in cases like this, so\
                      \ maybe you have an expression but it is not indented enough?"
                  ]
              )
    TupleIndentExprN row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED TUPLE" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I think I am in the middle of parsing a tuple. I just saw a comma, so I was expecting to see an expression next.",
                D.stack
                  [ D.fillSep $
                      [ "A",
                        "tuple",
                        "looks",
                        "like",
                        D.dullyellow "(3,4)",
                        "or",
                        D.dullyellow "(\"Tom\",42)" <> ",",
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
                    D.toSimpleNote $
                      "I can get confused by indentation in cases like this, so\
                      \ maybe you have an expression but it is not indented enough?"
                  ]
              )
    TupleIndentEnd row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED PARENTHESES" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I was expecting to see a closing parenthesis next:",
                D.stack
                  [ D.fillSep ["Try", "adding", "a", D.dullyellow ")", "to", "see", "if", "that", "helps!"],
                    D.toSimpleNote $
                      "I can get confused by indentation in cases like this, so\
                      \ maybe you have a closing parenthesis but it is not indented enough?"
                  ]
              )

-- | Render a list expression parse error.
toListReport :: Code.Source -> Context -> List -> Row -> Col -> Report.Report
toListReport source context list startRow startCol =
  case list of
    ListSpace space row col ->
      toSpaceReport source space row col
    ListOpen row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED LIST" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I am partway through parsing a list, but I got stuck here:",
                D.stack
                  [ D.fillSep
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
                        D.dullyellow "]",
                        "and",
                        "see",
                        "if",
                        "that",
                        "helps?"
                      ],
                    D.toSimpleNote $
                      "When I get stuck like this, it usually means that there is a missing parenthesis\
                      \ or bracket somewhere earlier. It could also be a stray keyword or operator."
                  ]
              )
    ListExpr expr row col ->
      case expr of
        Start r c ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position r c)
              region = toRegion r c
           in Report.Report "UNFINISHED LIST" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I was expecting to see another list entry after that last comma:",
                    D.stack
                      [ D.reflow $
                          "Trailing commas are not allowed in lists, so the fix may be to delete the comma?",
                        D.toSimpleNote
                          "I recommend using the following format for lists that span multiple lines:",
                        D.indent 4 $
                          D.vcat $
                            [ "[ " <> D.dullyellow "\"Alice\"",
                              ", " <> D.dullyellow "\"Bob\"",
                              ", " <> D.dullyellow "\"Chuck\"",
                              "]"
                            ],
                        D.reflow $
                          "Notice that each line starts with some indentation. Usually two or four spaces.\
                          \ This is the stylistic convention in the Canopy ecosystem."
                      ]
                  )
        _ ->
          toExprReport source (InNode NList startRow startCol context) expr row col
    ListEnd row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED LIST" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I am partway through parsing a list, but I got stuck here:",
                D.stack
                  [ D.fillSep
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
                        D.dullyellow "]",
                        "and",
                        "see",
                        "if",
                        "that",
                        "helps?"
                      ],
                    D.toSimpleNote $
                      "When I get stuck like this, it usually means that there is a missing parenthesis\
                      \ or bracket somewhere earlier. It could also be a stray keyword or operator."
                  ]
              )
    ListIndentOpen row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED LIST" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I cannot find the end of this list:",
                D.stack
                  [ D.fillSep $
                      [ "You",
                        "could",
                        "change",
                        "it",
                        "to",
                        "something",
                        "like",
                        D.dullyellow "[3,4,5]",
                        "or",
                        "even",
                        "just",
                        D.dullyellow "[]" <> ".",
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
                    D.toSimpleNote
                      "I may be confused by indentation. For example, if you are trying to define\
                      \ a list across multiple lines, I recommend using this format:",
                    D.indent 4 $
                      D.vcat $
                        [ "[ " <> D.dullyellow "\"Alice\"",
                          ", " <> D.dullyellow "\"Bob\"",
                          ", " <> D.dullyellow "\"Chuck\"",
                          "]"
                        ],
                    D.reflow $
                      "Notice that each line starts with some indentation. Usually two or four spaces.\
                      \ This is the stylistic convention in the Canopy ecosystem."
                  ]
              )
    ListIndentEnd row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED LIST" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I cannot find the end of this list:",
                D.stack
                  [ D.fillSep $
                      [ "You",
                        "can",
                        "just",
                        "add",
                        "a",
                        "closing",
                        D.dullyellow "]",
                        "right",
                        "here,",
                        "and",
                        "I",
                        "will",
                        "be",
                        "all",
                        "set!"
                      ],
                    D.toSimpleNote
                      "I may be confused by indentation. For example, if you are trying to define\
                      \ a list across multiple lines, I recommend using this format:",
                    D.indent 4 $
                      D.vcat $
                        [ "[ " <> D.dullyellow "\"Alice\"",
                          ", " <> D.dullyellow "\"Bob\"",
                          ", " <> D.dullyellow "\"Chuck\"",
                          "]"
                        ],
                    D.reflow $
                      "Notice that each line starts with some indentation. Usually two or four spaces.\
                      \ This is the stylistic convention in the Canopy ecosystem."
                  ]
              )
    ListIndentExpr row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED LIST" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I was expecting to see another list entry after this comma:",
                D.stack
                  [ D.reflow $
                      "Trailing commas are not allowed in lists, so the fix may be to delete the comma?",
                    D.toSimpleNote
                      "I recommend using the following format for lists that span multiple lines:",
                    D.indent 4 $
                      D.vcat $
                        [ "[ " <> D.dullyellow "\"Alice\"",
                          ", " <> D.dullyellow "\"Bob\"",
                          ", " <> D.dullyellow "\"Chuck\"",
                          "]"
                        ],
                    D.reflow $
                      "Notice that each line starts with some indentation. Usually two or four spaces.\
                      \ This is the stylistic convention in the Canopy ecosystem."
                  ]
              )

-- | Render an anonymous function parse error.
toFuncReport :: Code.Source -> Context -> Func -> Row -> Col -> Report.Report
toFuncReport source context func startRow startCol =
  case func of
    FuncSpace space row col ->
      toSpaceReport source space row col
    FuncArg pattern row col ->
      toPatternReport source PArg pattern row col
    FuncBody expr row col ->
      toExprReport source (InNode NFunc startRow startCol context) expr row col
    FuncArrow row col ->
      case Code.whatIsNext source row col of
        Code.Keyword keyword ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
              region = toKeywordRegion row col keyword
           in Report.Report "RESERVED WORD" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I was parsing an anonymous function, but I got stuck here:",
                    D.reflow $
                      "It looks like you are trying to use `" ++ keyword
                        ++ "` as an argument, but\
                           \ it is a reserved word in this language. Try using a different argument name!"
                  )
        _ ->
          let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
              region = toRegion row col
           in Report.Report "UNFINISHED ANONYMOUS FUNCTION" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( D.reflow $
                      "I just saw the beginning of an anonymous function, so I was expecting to see an arrow next:",
                    D.fillSep $
                      [ "The",
                        "syntax",
                        "for",
                        "anonymous",
                        "functions",
                        "is",
                        D.dullyellow "(\\x -> x + 1)",
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
    FuncIndentArg row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "MISSING ARGUMENT" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I just saw the beginning of an anonymous function, so I was expecting to see an argument next:",
                D.stack
                  [ D.fillSep
                      [ "Something",
                        "like",
                        D.dullyellow "x",
                        "or",
                        D.dullyellow "name" <> ".",
                        "Anything",
                        "that",
                        "starts",
                        "with",
                        "a",
                        "lower",
                        "case",
                        "letter!"
                      ],
                    D.toSimpleNote $
                      "The syntax for anonymous functions is (\\x -> x + 1) where the backslash\
                      \ is meant to look a bit like a lambda if you squint. This visual pun seemed\
                      \ like a better idea at the time!"
                  ]
              )
    FuncIndentArrow row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED ANONYMOUS FUNCTION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I just saw the beginning of an anonymous function, so I was expecting to see an arrow next:",
                D.stack
                  [ D.fillSep $
                      [ "The",
                        "syntax",
                        "for",
                        "anonymous",
                        "functions",
                        "is",
                        D.dullyellow "(\\x -> x + 1)",
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
                    D.toSimpleNote $
                      "It is possible that I am confused about indetation! I generally recommend\
                      \ switching to named functions if the definition cannot fit inline nicely, so\
                      \ either (1) try to fit the whole anonymous function on one line or (2) break\
                      \ the whole thing out into a named function. Things tend to be clearer that way!"
                  ]
              )
    FuncIndentBody row col ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED ANONYMOUS FUNCTION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow $
                  "I was expecting to see the body of your anonymous function next:",
                D.stack
                  [ D.fillSep $
                      [ "The",
                        "syntax",
                        "for",
                        "anonymous",
                        "functions",
                        "is",
                        D.dullyellow "(\\x -> x + 1)",
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
                    D.toSimpleNote $
                      "It is possible that I am confused about indetation! I generally recommend\
                      \ switching to named functions if the definition cannot fit inline nicely, so\
                      \ either (1) try to fit the whole anonymous function on one line or (2) break\
                      \ the whole thing out into a named function. Things tend to be clearer that way!"
                  ]
              )

-- | Documentation note for definition format.
defNote :: D.Doc
defNote =
  D.stack
    [ D.reflow $
        "Here is a valid definition (with a type annotation) for reference:",
      D.indent 4 $
        D.vcat $
          [ "greet : String -> String",
            "greet name =",
            "  " <> D.dullyellow "\"Hello \"" <> " ++ name ++ " <> D.dullyellow "\"!\""
          ],
      D.reflow $
        "The top line (called a \"type annotation\") is optional. You can leave it off\
        \ if you want. As you get more comfortable with Canopy and as your project grows,\
        \ it becomes more and more valuable to add them though! They work great as\
        \ compiler-verified documentation, and they often improve error messages!"
    ]

-- | Documentation note for declaration definition format.
declDefNote :: D.Doc
declDefNote =
  D.stack
    [ D.reflow $
        "Here is a valid definition (with a type annotation) for reference:",
      D.indent 4 $
        D.vcat $
          [ "greet : String -> String",
            "greet name =",
            "  " <> D.dullyellow "\"Hello \"" <> " ++ name ++ " <> D.dullyellow "\"!\""
          ],
      D.reflow $
        "The top line (called a \"type annotation\") is optional. You can leave it off\
        \ if you want. As you get more comfortable with Canopy and as your project grows,\
        \ it becomes more and more valuable to add them though! They work great as\
        \ compiler-verified documentation, and they often improve error messages!"
    ]

-- | Documentation note for record expression formatting errors.
noteForRecordError :: D.Doc
noteForRecordError =
  D.stack $
    [ D.toSimpleNote
        "If you are trying to define a record across multiple lines, I recommend using this format:",
      D.indent 4 $
        D.vcat $
          [ "{ name = " <> D.dullyellow "\"Alice\"",
            ", age = " <> D.dullyellow "42",
            ", height = " <> D.dullyellow "1.75",
            "}"
          ],
      D.reflow $
        "Notice that each line starts with some indentation. Usually two or four spaces.\
        \ This is the stylistic convention in the Canopy ecosystem."
    ]

-- | Documentation note for record expression indentation errors.
noteForRecordIndentError :: D.Doc
noteForRecordIndentError =
  D.stack
    [ D.toSimpleNote
        "I may be confused by indentation. For example, if you are trying to define\
        \ a record across multiple lines, I recommend using this format:",
      D.indent 4 $
        D.vcat $
          [ "{ name = " <> D.dullyellow "\"Alice\"",
            ", age = " <> D.dullyellow "42",
            ", height = " <> D.dullyellow "1.75",
            "}"
          ],
      D.reflow $
        "Notice that each line starts with some indentation. Usually two or four spaces.\
        \ This is the stylistic convention in the Canopy ecosystem!"
    ]
