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

import qualified Canopy.Data.Name as Name
import Parse.Primitives (Col, Row)
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import qualified Reporting.Error.Syntax.Expression.Case as ExprCase
import qualified Reporting.Error.Syntax.Expression.Function as ExprFunction
import qualified Reporting.Error.Syntax.Expression.If as ExprIf
import qualified Reporting.Error.Syntax.Expression.Let as ExprLet
import qualified Reporting.Error.Syntax.Expression.Record as ExprRecord
import qualified Reporting.Error.Syntax.Expression.Sequence as ExprSequence
import Reporting.Error.Syntax.Helpers
  ( Context (..),
    Node (..),
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
import qualified Prelude
import Prelude hiding (Char, String)

-- | Exported re-export of declDefNote from sub-module.
declDefNote :: Doc.Doc
declDefNote = ExprFunction.declDefNote

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
      toDotReport source row col
    Access row col ->
      toAccessReport source row col
    OperatorRight op row col ->
      toOperatorRightReport source op startRow startCol row col
    OperatorReserved operator row col ->
      toOperatorReport source context operator row col
    Start row col ->
      toStartReport source context startRow startCol row col
    Char char row col ->
      toCharReport source char row col
    String string row col ->
      toStringReport source string row col
    Number number row col ->
      toNumberReport source number row col
    Space space row col ->
      toSpaceReport source space row col
    EndlessShader row col ->
      toEndlessShaderReport source row col
    ShaderProblem problem row col ->
      toShaderProblemReport source problem row col
    IndentOperatorRight op row col ->
      toIndentOperatorRightReport source op startRow startCol row col
    EndlessInterpolation row col ->
      toEndlessInterpolationReport source row col
    InterpolationExpr innerExpr row col ->
      toExprReport source context innerExpr row col
    InterpolationClose row col ->
      toInterpolationCloseReport source row col
    TooDeepFieldAccess limit row col ->
      toTooDeepFieldAccessReport source limit row col

-- | Render a let expression parse error.
toLetReport :: Code.Source -> Context -> Let -> Row -> Col -> Report.Report
toLetReport source context let_ startRow startCol =
  ExprLet.toLetReport toExprReport source context let_ startRow startCol

-- | Render an unfinished let expression error.
toUnfinishLetReport :: Code.Source -> Row -> Col -> Row -> Col -> Doc.Doc -> Report.Report
toUnfinishLetReport = ExprLet.toUnfinishLetReport

-- | Render a let definition parse error.
toLetDefReport :: Code.Source -> Name.Name -> Def -> Row -> Col -> Report.Report
toLetDefReport source name def startRow startCol =
  ExprLet.toLetDefReport toExprReport source name def startRow startCol

-- | Render a let destructuring parse error.
toLetDestructReport :: Code.Source -> Destruct -> Row -> Col -> Report.Report
toLetDestructReport source destruct startRow startCol =
  ExprLet.toLetDestructReport toExprReport source destruct startRow startCol

-- | Render a case expression parse error.
toCaseReport :: Code.Source -> Context -> Case -> Row -> Col -> Report.Report
toCaseReport source context case_ startRow startCol =
  ExprCase.toCaseReport toExprReport source context case_ startRow startCol

-- | Render an unfinished case expression error.
toUnfinishCaseReport :: Code.Source -> Row -> Col -> Row -> Col -> Doc.Doc -> Report.Report
toUnfinishCaseReport = ExprCase.toUnfinishCaseReport

-- | Render an if expression parse error.
toIfReport :: Code.Source -> Context -> If -> Row -> Col -> Report.Report
toIfReport source context if_ startRow startCol =
  ExprIf.toIfReport toExprReport source context if_ startRow startCol

-- | Render a record expression parse error.
toRecordReport :: Code.Source -> Context -> Record -> Row -> Col -> Report.Report
toRecordReport source context record startRow startCol =
  ExprRecord.toRecordReport toExprReport source context record startRow startCol

-- | Render a tuple expression parse error.
toTupleReport :: Code.Source -> Context -> Tuple -> Row -> Col -> Report.Report
toTupleReport source context tuple startRow startCol =
  ExprSequence.toTupleReport toExprReport source context tuple startRow startCol

-- | Render a list expression parse error.
toListReport :: Code.Source -> Context -> List -> Row -> Col -> Report.Report
toListReport source context list startRow startCol =
  ExprSequence.toListReport toExprReport source context list startRow startCol

-- | Render an anonymous function parse error.
toFuncReport :: Code.Source -> Context -> Func -> Row -> Col -> Report.Report
toFuncReport source context func startRow startCol =
  ExprFunction.toFuncReport toExprReport source context func startRow startCol

toDotReport :: Code.Source -> Row -> Col -> Report.Report
toDotReport source row col =
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

toAccessReport :: Code.Source -> Row -> Col -> Report.Report
toAccessReport source row col =
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

toOperatorRightReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toOperatorRightReport source op startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
      isMath = op `elem` ["-", "+", "*", "/", "^"]
   in Report.Report "MISSING EXPRESSION" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow $
              "I just saw a " ++ Name.toChars op ++ " "
                ++ (if isMath then "sign" else "operator")
                ++ ", so I am getting stuck here:",
            toOperatorRightNote op isMath
          )

toOperatorRightNote :: Name.Name -> Bool -> Doc.Doc
toOperatorRightNote op isMath
  | isMath =
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
  | op == "&&" || op == "||" =
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
  | op == "|>" = Doc.reflow "I was expecting to see a function next."
  | op == "<|" = Doc.reflow "I was expecting to see an argument next."
  | otherwise = Doc.reflow "I was expecting to see an expression next."

toStartReport :: Code.Source -> Context -> Row -> Col -> Row -> Col -> Report.Report
toStartReport source context startRow startCol row col =
  let (contextRow, contextCol, aThing) = toContextDescription context startRow startCol
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

toContextDescription :: Context -> Row -> Col -> (Row, Col, Prelude.String)
toContextDescription context _startRow _startCol =
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

toEndlessShaderReport :: Code.Source -> Row -> Col -> Report.Report
toEndlessShaderReport source row col =
  let region = toWiderRegion row col 6
   in Report.Report "ENDLESS SHADER" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "I cannot find the end of this shader:",
            Doc.reflow "Add a |] somewhere after this to end the shader."
          )

toShaderProblemReport :: Code.Source -> Prelude.String -> Row -> Col -> Report.Report
toShaderProblemReport source problem row col =
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

toEndlessInterpolationReport :: Code.Source -> Row -> Col -> Report.Report
toEndlessInterpolationReport source row col =
  let region = toWiderRegion row col 1
   in Report.Report "ENDLESS TEMPLATE LITERAL" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "I cannot find the end of this template literal:",
            Doc.stack
              [ Doc.reflow "Add a closing backtick somewhere after this.",
                Doc.toSimpleNote
                  "Template literals start and end with backticks. For example:"
              , Doc.indent 4 $
                  Doc.dullyellow (Doc.fromChars "`Hello ${name}!`")
              ]
          )

toInterpolationCloseReport :: Code.Source -> Row -> Col -> Report.Report
toInterpolationCloseReport source row col =
  let region = toRegion row col
   in Report.Report "MISSING CLOSING BRACE" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow
              "I was expecting a } to close this interpolation expression:",
            Doc.stack
              [ Doc.reflow "Every ${ must have a matching }.",
                Doc.toSimpleNote
                  "Template literal expressions look like this:"
              , Doc.indent 4 $
                  Doc.dullyellow (Doc.fromChars "`Hello ${name}!`")
              ]
          )

toIndentOperatorRightReport :: Code.Source -> Name.Name -> Row -> Col -> Row -> Col -> Report.Report
toIndentOperatorRightReport source op startRow startCol row col =
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

-- | Render an error for field access chains exceeding the depth limit.
toTooDeepFieldAccessReport :: Code.Source -> Int -> Row -> Col -> Report.Report
toTooDeepFieldAccessReport source limit row col =
  let region = toRegion row col
   in Report.Report "TOO DEEP FIELD ACCESS" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow $
              "This field access chain exceeds the maximum depth of "
                ++ show limit
                ++ ":",
            Doc.stack
              [ Doc.reflow
                  "Field access chains like record.a.b.c... are limited to prevent \
                  \stack overflows on deeply nested expressions.",
                Doc.toSimpleNote
                  "Consider refactoring by introducing intermediate variables \
                  \to break up the chain."
              ]
          )
