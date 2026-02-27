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
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
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
              ( Doc.reflow $
                  "I was expecting to see a record accessor here:",
                Doc.fillSep
                  [ "Something",
                    "like",
                    Doc.dullyellow ".name",
                    "or",
                    Doc.dullyellow ".price",
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
              ( Doc.reflow $
                  "I am trying to parse a record accessor here:",
                Doc.stack
                  [ Doc.fillSep
                      [ "Something",
                        "like",
                        Doc.dullyellow ".name",
                        "or",
                        Doc.dullyellow ".price",
                        "that",
                        "accesses",
                        "a",
                        "value",
                        "from",
                        "a",
                        "record."
                      ],
                    Doc.toSimpleNote $
                      "Record field names must start with a lower case letter!"
                  ]
              )
    OperatorRight op row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
          isMath = elem op ["-", "+", "*", "/", "^"]
       in Report.Report "MISSING EXPRESSION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I just saw a " ++ Name.toChars op ++ " "
                    ++ (if isMath then "sign" else "operator")
                    ++ ", so I am getting stuck here:",
                if isMath
                  then
                    Doc.fillSep
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
                        Doc.dullyellow "42",
                        "or",
                        Doc.dullyellow "1000",
                        "that",
                        "makes",
                        "sense",
                        "with",
                        "a",
                        Doc.fromName op,
                        "sign."
                      ]
                  else
                    if op == "&&" || op == "||"
                      then
                        Doc.fillSep
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
                            Doc.dullyellow "True",
                            "or",
                            Doc.dullyellow "False",
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
                            Doc.reflow $
                              "I was expecting to see a function next."
                          else
                            if op == "<|"
                              then
                                Doc.reflow $
                                  "I was expecting to see an argument next."
                              else
                                Doc.reflow $
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

          surroundings = Ann.Region (Ann.Position contextRow contextCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "MISSING EXPRESSION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I am partway through parsing " ++ aThing ++ ", but I got stuck here:",
                Doc.stack
                  [ Doc.fillSep $
                      [ "I",
                        "was",
                        "expecting",
                        "to",
                        "see",
                        "an",
                        "expression",
                        "like",
                        Doc.dullyellow "42",
                        "or",
                        Doc.dullyellow "\"hello\"" <> ".",
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
                    Doc.toSimpleNote $
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
              ( Doc.reflow "I cannot find the end of this shader:",
                Doc.reflow "Add a |] somewhere after this to end the shader."
              )
    ShaderProblem problem row col ->
      let region = toRegion row col
       in Report.Report "SHADER PROBLEM" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow $
                  "I ran into a problem while parsing this GLSL block.",
                Doc.stack
                  [ Doc.reflow $
                      "I use a 3rd party GLSL parser for now, and I did my best to extract their error message:",
                    Doc.indent 4 $
                      Doc.vcat $
                        map Doc.fromChars (filter (/= "") (lines problem))
                  ]
              )
    IndentOperatorRight op row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "MISSING EXPRESSION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I was expecting to see an expression after this " ++ Name.toChars op ++ " operator:",
                Doc.stack
                  [ Doc.fillSep $
                      [ "You",
                        "can",
                        "just",
                        "put",
                        "anything",
                        "for",
                        "now,",
                        "like",
                        Doc.dullyellow "42",
                        "or",
                        Doc.dullyellow "\"hello\"" <> ".",
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
                    Doc.toSimpleNote $
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
    LetDefAlignment _ row col ->
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
    LetDefName row col ->
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
    LetDef name def row col ->
      toLetDefReport source name def row col
    LetDestruct destruct row col ->
      toLetDestructReport source destruct row col
    LetBody expr row col ->
      toExprReport source context expr row col
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
toLetDefReport :: Code.Source -> Name.Name -> Def -> Row -> Col -> Report.Report
toLetDefReport source name def startRow startCol =
  case def of
    DefSpace space row col ->
      toSpaceReport source space row col
    DefType tipe row col ->
      toTypeReport source (TC_Annotation name) tipe row col
    DefNameRepeat row col ->
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
    DefNameMatch defName row col ->
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
    DefArg pattern row col ->
      toPatternReport source PArg pattern row col
    DefEquals row col ->
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
                    Doc.stack
                      [ Doc.reflow $
                          "Try renaming it to something else.",
                        case keyword of
                          "as" ->
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
                          _ ->
                            Doc.toSimpleNote $
                              "The `" ++ keyword ++ "` keyword has a special meaning in Canopy, so it can only be used in certain situations."
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
                  ( Doc.reflow $
                      "I was not expecting to see an arrow here:",
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
                  )
    DefBody expr row col ->
      toExprReport source (InDef name startRow startCol) expr row col
    DefIndentEquals row col ->
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
    DefIndentType row col ->
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
    DefIndentBody row col ->
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
    DefAlignment indent row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
          offset = indent - col
       in Report.Report "PROBLEM IN DEFINITION" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I got stuck while parsing the `" ++ Name.toChars name ++ "` definition:",
                Doc.reflow $
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
    DestructBody expr row col ->
      toExprReport source (InDestruct startRow startCol) expr row col
    DestructIndentEquals row col ->
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
    DestructIndentBody row col ->
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

-- | Render a case expression parse error.
toCaseReport :: Code.Source -> Context -> Case -> Row -> Col -> Report.Report
toCaseReport source context case_ startRow startCol =
  case case_ of
    CaseSpace space row col ->
      toSpaceReport source space row col
    CaseOf row col ->
      toUnfinishCaseReport source row col startRow startCol $
        Doc.fillSep ["I", "was", "expecting", "to", "see", "the", Doc.dullyellow "of", "keyword", "next."]
    CasePattern pattern row col ->
      toPatternReport source PCase pattern row col
    CaseArrow row col ->
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
                      "I am partway through parsing a `case` expression, but I got stuck here:",
                    Doc.reflow $
                      "It looks like you are trying to use `" ++ keyword
                        ++ "` in one of your\
                           \ patterns, but it is a reserved word. Try using a different name?"
                  )
        Code.Operator ":" ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toRegion row col
           in Report.Report "UNEXPECTED OPERATOR" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( Doc.reflow $
                      "I am partway through parsing a `case` expression, but I got stuck here:",
                    Doc.fillSep $
                      [ "I",
                        "am",
                        "seeing",
                        Doc.dullyellow ":",
                        "but",
                        "maybe",
                        "you",
                        "want",
                        Doc.green "::",
                        "instead?",
                        "For",
                        "pattern",
                        "matching",
                        "on",
                        "lists?"
                      ]
                  )
        Code.Operator "=" ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toRegion row col
           in Report.Report "UNEXPECTED OPERATOR" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( Doc.reflow $
                      "I am partway through parsing a `case` expression, but I got stuck here:",
                    Doc.fillSep $
                      [ "I",
                        "am",
                        "seeing",
                        Doc.dullyellow "=",
                        "but",
                        "maybe",
                        "you",
                        "want",
                        Doc.green "->",
                        "instead?"
                      ]
                  )
        _ ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toRegion row col
           in Report.Report "MISSING ARROW" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( Doc.reflow $
                      "I am partway through parsing a `case` expression, but I got stuck here:",
                    Doc.stack
                      [ Doc.reflow "I was expecting to see an arrow next.",
                        noteForCaseIndentError
                      ]
                  )
    CaseExpr expr row col ->
      toExprReport source (InNode NCase startRow startCol context) expr row col
    CaseBranch expr row col ->
      toExprReport source (InNode NBranch startRow startCol context) expr row col
    CaseIndentOf row col ->
      toUnfinishCaseReport source row col startRow startCol $
        Doc.fillSep ["I", "was", "expecting", "to", "see", "the", Doc.dullyellow "of", "keyword", "next."]
    CaseIndentExpr row col ->
      toUnfinishCaseReport source row col startRow startCol $
        Doc.reflow "I was expecting to see a expression next."
    CaseIndentPattern row col ->
      toUnfinishCaseReport source row col startRow startCol $
        Doc.reflow "I was expecting to see a pattern next."
    CaseIndentArrow row col ->
      toUnfinishCaseReport source row col startRow startCol $
        Doc.fillSep
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
            Doc.dullyellow "->",
            "next."
          ]
    CaseIndentBranch row col ->
      toUnfinishCaseReport source row col startRow startCol $
        Doc.reflow $
          "I was expecting to see an expression next. What should I do when\
          \ I run into this particular pattern?"
    CasePatternAlignment indent row col ->
      toUnfinishCaseReport source row col startRow startCol $
        Doc.reflow $
          "I suspect this is a pattern that is not indented far enough? (" ++ show indent ++ " spaces)"

-- | Render an unfinished case expression error.
toUnfinishCaseReport :: Code.Source -> Row -> Col -> Row -> Col -> Doc.Doc -> Report.Report
toUnfinishCaseReport source row col startRow startCol message =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED CASE" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I was partway through parsing a `case` expression, but I got stuck here:",
            Doc.stack
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
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED IF" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I was expecting to see more of this `if` expression, but I got stuck here:",
                Doc.fillSep $
                  [ "I",
                    "was",
                    "expecting",
                    "to",
                    "see",
                    "the",
                    Doc.cyan "then",
                    "keyword",
                    "next."
                  ]
              )
    IfElse row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED IF" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I was expecting to see more of this `if` expression, but I got stuck here:",
                Doc.fillSep $
                  [ "I",
                    "was",
                    "expecting",
                    "to",
                    "see",
                    "the",
                    Doc.cyan "else",
                    "keyword",
                    "next."
                  ]
              )
    IfElseBranchStart row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED IF" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I just saw the start of an `else` branch, but then I got stuck here:",
                Doc.reflow $
                  "I was expecting to see an expression next. Maybe it is not filled in yet?"
              )
    IfCondition expr row col ->
      toExprReport source (InNode NCond startRow startCol context) expr row col
    IfThenBranch expr row col ->
      toExprReport source (InNode NThen startRow startCol context) expr row col
    IfElseBranch expr row col ->
      toExprReport source (InNode NElse startRow startCol context) expr row col
    IfIndentCondition row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED IF" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I was expecting to see more of this `if` expression, but I got stuck here:",
                Doc.stack
                  [ Doc.fillSep $
                      [ "I",
                        "was",
                        "expecting",
                        "to",
                        "see",
                        "an",
                        "expression",
                        "like",
                        Doc.dullyellow "x < 0",
                        "that",
                        "evaluates",
                        "to",
                        "True",
                        "or",
                        "False."
                      ],
                    Doc.toSimpleNote $
                      "I can be confused by indentation. Maybe something is not indented enough?"
                  ]
              )
    IfIndentThen row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED IF" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I was expecting to see more of this `if` expression, but I got stuck here:",
                Doc.stack
                  [ Doc.fillSep $
                      [ "I",
                        "was",
                        "expecting",
                        "to",
                        "see",
                        "the",
                        Doc.cyan "then",
                        "keyword",
                        "next."
                      ],
                    Doc.toSimpleNote $
                      "I can be confused by indentation. Maybe something is not indented enough?"
                  ]
              )
    IfIndentThenBranch row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED IF" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I got stuck after the start of this `then` branch:",
                Doc.stack
                  [ Doc.reflow $
                      "I was expecting to see an expression next. Maybe it is not filled in yet?",
                    Doc.toSimpleNote $
                      "I can be confused by indentation, so if the `then` branch is already\
                      \ present, it may not be indented enough for me to recognize it."
                  ]
              )
    IfIndentElseBranch row col ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "UNFINISHED IF" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow $
                  "I got stuck after the start of this `else` branch:",
                Doc.stack
                  [ Doc.reflow $
                      "I was expecting to see an expression next. Maybe it is not filled in yet?",
                    Doc.toSimpleNote $
                      "I can be confused by indentation, so if the `else` branch is already\
                      \ present, it may not be indented enough for me to recognize it."
                  ]
              )
    IfIndentElse row col ->
      case Code.nextLineStartsWithKeyword "else" source row of
        Just (elseRow, elseCol) ->
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position elseRow elseCol)
              region = toWiderRegion elseRow elseCol 4
           in Report.Report "WEIRD ELSE BRANCH" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( Doc.reflow $
                      "I was partway through an `if` expression when I got stuck here:",
                    Doc.fillSep $
                      [ "I",
                        "think",
                        "this",
                        Doc.cyan "else",
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
          let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
              region = toRegion row col
           in Report.Report "UNFINISHED IF" region [] $
                Code.toSnippet
                  source
                  surroundings
                  (Just region)
                  ( Doc.reflow $
                      "I was expecting to see an `else` branch after this:",
                    Doc.stack
                      [ Doc.fillSep
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
                            Doc.cyan "else",
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
    RecordEnd row col ->
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
    RecordField row col ->
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
    RecordEquals row col ->
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
    RecordExpr expr row col ->
      toExprReport source (InNode NRecord startRow startCol context) expr row col
    RecordSpace space row col ->
      toSpaceReport source space row col
    RecordIndentOpen row col ->
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
    RecordIndentEnd row col ->
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
    RecordIndentField row col ->
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
    RecordIndentEquals row col ->
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
    RecordIndentExpr row col ->
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

-- | Render a tuple expression parse error.
toTupleReport :: Code.Source -> Context -> Tuple -> Row -> Col -> Report.Report
toTupleReport source context tuple startRow startCol =
  case tuple of
    TupleExpr expr row col ->
      toExprReport source (InNode NParens startRow startCol context) expr row col
    TupleSpace space row col ->
      toSpaceReport source space row col
    TupleEnd row col ->
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
    TupleOperatorClose row col ->
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
    TupleOperatorReserved operator row col ->
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
    TupleIndentExpr1 row col ->
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
    TupleIndentExprN row col ->
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
    TupleIndentEnd row col ->
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
toListReport :: Code.Source -> Context -> List -> Row -> Col -> Report.Report
toListReport source context list startRow startCol =
  case list of
    ListSpace space row col ->
      toSpaceReport source space row col
    ListOpen row col ->
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
    ListExpr expr row col ->
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
          toExprReport source (InNode NList startRow startCol context) expr row col
    ListEnd row col ->
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
    ListIndentOpen row col ->
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
    ListIndentEnd row col ->
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
    ListIndentExpr row col ->
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
    FuncIndentArg row col ->
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
    FuncIndentArrow row col ->
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
    FuncIndentBody row col ->
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
