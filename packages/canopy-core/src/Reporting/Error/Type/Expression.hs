{-# LANGUAGE OverloadedStrings #-}

-- | Reporting.Error.Type.Expression - Expression type-error rendering
--
-- This module builds 'Report.Report' values for 'BadExpr' type errors.
-- The main entry point is 'toExprReport', called from the parent module's
-- 'toDiagnostic' function.  It dispatches through 'fromAnnotationReport'
-- (for annotated definitions), 'fromContextReport' (for contextual
-- mismatches), and 'contextDispatch' which fans out to operator, call,
-- record, and branch-specific handlers.
module Reporting.Error.Type.Expression
  ( toExprReport,
  )
where

import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import qualified Reporting.Render.Code as Code
import qualified Reporting.Render.Type.Localizer as Localizer
import qualified Reporting.Report as Report
import qualified Type.Error as TypeErr
import Reporting.Error.Type.Operators
  ( Category,
    MaybeName (..),
    RightDocs (..),
    addCategory,
    opLeftToDocs,
    opRightToDocs,
  )
import Reporting.Error.Type.Render
  ( countArgs,
    loneType,
    typeComparison,
  )
import Reporting.Error.Type.Record
  ( recordAccessReport,
    recordUpdateKeysReport,
  )
import Reporting.Error.Type.Types
  ( Context (..),
    Expected (..),
    SubContext (..),
  )

-- ---------------------------------------------------------------------------
-- toExprReport
-- ---------------------------------------------------------------------------

-- | Build a report for an expression type mismatch.
--
-- Dispatches on the 'Expected' wrapper to decide between a bare
-- "unexpected usage" message, an annotation-based comparison, or a
-- context-aware comparison.
toExprReport :: Code.Source -> Localizer.Localizer -> Ann.Region -> Category -> TypeErr.Type -> Expected TypeErr.Type -> Report.Report
toExprReport source localizer exprRegion category tipe expected =
  case expected of
    NoExpectation expectedType ->
      Report.Report "TYPE MISMATCH" exprRegion [] $
        Code.toSnippet
          source
          exprRegion
          Nothing
          ( "This expression is being used in an unexpected way:",
            typeComparison
              localizer
              tipe
              expectedType
              (addCategory "It is" category)
              "But you are trying to use it as:"
              []
          )
    FromAnnotation name _arity subContext expectedType ->
      fromAnnotationReport source localizer exprRegion category tipe name subContext expectedType
    FromContext region context expectedType ->
      fromContextReport source localizer exprRegion category tipe region context expectedType

-- ---------------------------------------------------------------------------
-- Annotation reports
-- ---------------------------------------------------------------------------

-- | Build a report when an expression does not match its type annotation.
fromAnnotationReport ::
  Code.Source ->
  Localizer.Localizer ->
  Ann.Region ->
  Category ->
  TypeErr.Type ->
  Name.Name ->
  SubContext ->
  TypeErr.Type ->
  Report.Report
fromAnnotationReport source localizer exprRegion category tipe name subContext expectedType =
  Report.Report "TYPE MISMATCH" exprRegion [] . Code.toSnippet source exprRegion Nothing $
    ( Doc.reflow ("Something is off with the " <> thing),
      typeComparison
        localizer
        tipe
        expectedType
        (addCategory itIs category)
        ("But the type annotation on `" <> Name.toChars name <> "` says it should be:")
        []
    )
  where
    thing =
      case subContext of
        TypedIfBranch index -> Doc.ordinal index <> " branch of this `if` expression:"
        TypedCaseBranch index -> Doc.ordinal index <> " branch of this `case` expression:"
        TypedBody -> "body of the `" <> Name.toChars name <> "` definition:"
    itIs =
      case subContext of
        TypedIfBranch index -> "The " <> Doc.ordinal index <> " branch is"
        TypedCaseBranch index -> "The " <> Doc.ordinal index <> " branch is"
        TypedBody -> "The body is"

-- ---------------------------------------------------------------------------
-- Context reports
-- ---------------------------------------------------------------------------

-- | Build a report when a context (list entry, if branch, call arg, etc.)
-- constrains an expression's type.
fromContextReport ::
  Code.Source ->
  Localizer.Localizer ->
  Ann.Region ->
  Category ->
  TypeErr.Type ->
  Ann.Region ->
  Context ->
  TypeErr.Type ->
  Report.Report
fromContextReport source localizer exprRegion category tipe region context expectedType =
  contextDispatch mismatch badType custom source localizer exprRegion category tipe expectedType context
  where
    mismatch (maybeHighlight, problem, thisIs, insteadOf, furtherDetails) =
      Report.Report "TYPE MISMATCH" exprRegion [] $
        Code.toSnippet
          source
          region
          maybeHighlight
          ( Doc.reflow problem,
            typeComparison localizer tipe expectedType (addCategory thisIs category) insteadOf furtherDetails
          )

    badType (maybeHighlight, problem, thisIs, furtherDetails) =
      Report.Report "TYPE MISMATCH" exprRegion [] $
        Code.toSnippet
          source
          region
          maybeHighlight
          ( Doc.reflow problem,
            loneType localizer tipe expectedType (Doc.reflow (addCategory thisIs category)) furtherDetails
          )

    custom maybeHighlight docPair =
      Report.Report "TYPE MISMATCH" exprRegion [] $
        Code.toSnippet source region maybeHighlight docPair

-- ---------------------------------------------------------------------------
-- Context dispatch
-- ---------------------------------------------------------------------------

-- | Fan out to the appropriate handler for each 'Context' variant.
--
-- The @mismatch@, @badType@, and @custom@ callbacks wrap the resulting doc
-- pair into a full 'Report.Report' with the correct snippet framing.
contextDispatch ::
  ((Maybe Ann.Region, String, String, String, [Doc.Doc]) -> Report.Report) ->
  ((Maybe Ann.Region, String, String, [Doc.Doc]) -> Report.Report) ->
  (Maybe Ann.Region -> (Doc.Doc, Doc.Doc) -> Report.Report) ->
  Code.Source ->
  Localizer.Localizer ->
  Ann.Region ->
  Category ->
  TypeErr.Type ->
  TypeErr.Type ->
  Context ->
  Report.Report
contextDispatch mismatch badType custom source localizer exprRegion category tipe expectedType context =
  case context of
    ListEntry index ->
      listEntryReport mismatch exprRegion index
    Negate ->
      negateReport badType exprRegion
    OpLeft op ->
      custom (Just exprRegion) $
        opLeftToDocs localizer category op tipe expectedType
    OpRight op ->
      case opRightToDocs localizer category op tipe expectedType of
        EmphBoth details -> custom Nothing details
        EmphRight details -> custom (Just exprRegion) details
    IfCondition ->
      ifConditionReport badType exprRegion
    IfBranch index ->
      ifBranchReport mismatch exprRegion index
    CaseBranch index ->
      caseBranchReport mismatch exprRegion index
    CallArity maybeFuncName numGivenArgs ->
      callArityReport source exprRegion tipe maybeFuncName numGivenArgs
    CallArg maybeFuncName index ->
      callArgReport mismatch exprRegion maybeFuncName index
    RecordAccess recordRegion maybeName fieldRegion field ->
      recordAccessReport badType custom localizer tipe recordRegion maybeName fieldRegion field
    RecordUpdateKeys record expectedFields ->
      recordUpdateKeysReport mismatch badType custom localizer exprRegion tipe record expectedFields
    RecordUpdateValue field ->
      recordUpdateValueReport mismatch exprRegion field
    Destructure ->
      destructureReport mismatch
    Interpolation index ->
      interpolationReport badType exprRegion index

-- ---------------------------------------------------------------------------
-- Per-context helpers
-- ---------------------------------------------------------------------------

-- | Report for a list entry that does not match the previous entries.
listEntryReport ::
  ((Maybe Ann.Region, String, String, String, [Doc.Doc]) -> Report.Report) ->
  Ann.Region ->
  Index.ZeroBased ->
  Report.Report
listEntryReport mismatch exprRegion index =
  mismatch
    ( Just exprRegion,
      "The " <> ith <> " element of this list does not match all the previous elements:",
      "The " <> ith <> " element is",
      "But all the previous elements in the list are:",
      [ Doc.link
          "Hint"
          "Everything in a list must be the same type of value. This way, we never\
          \ run into unexpected values partway through a List.map, List.foldl, etc. Read"
          "custom-types"
          "to learn how to \8220mix\8221 types."
      ]
    )
  where
    ith = Doc.ordinal index

-- | Report for negating a non-numeric value.
negateReport ::
  ((Maybe Ann.Region, String, String, [Doc.Doc]) -> Report.Report) ->
  Ann.Region ->
  Report.Report
negateReport badType exprRegion =
  badType
    ( Just exprRegion,
      "I do not know how to negate this type of value:",
      "It is",
      [ Doc.fillSep
          ["But", "I", "only", "now", "how", "to", "negate", Doc.dullyellow "Int", "and", Doc.dullyellow "Float", "values."]
      ]
    )

-- | Report for a non-boolean if-condition.
ifConditionReport ::
  ((Maybe Ann.Region, String, String, [Doc.Doc]) -> Report.Report) ->
  Ann.Region ->
  Report.Report
ifConditionReport badType exprRegion =
  badType
    ( Just exprRegion,
      "This `if` condition does not evaluate to a boolean value, True or False.",
      "It is",
      [Doc.fillSep ["But", "I", "need", "this", "`if`", "condition", "to", "be", "a", Doc.dullyellow "Bool", "value."]]
    )

-- | Report for an if-branch that does not match the previous branches.
ifBranchReport ::
  ((Maybe Ann.Region, String, String, String, [Doc.Doc]) -> Report.Report) ->
  Ann.Region ->
  Index.ZeroBased ->
  Report.Report
ifBranchReport mismatch exprRegion index =
  mismatch
    ( Just exprRegion,
      "The " <> ith <> " branch of this `if` does not match all the previous branches:",
      "The " <> ith <> " branch is",
      "But all the previous branches result in:",
      [ Doc.link
          "Hint"
          "All branches in an `if` must produce the same type of values. This way, no\
          \ matter which branch we take, the result is always a consistent shape. Read"
          "custom-types"
          "to learn how to \8220mix\8221 types."
      ]
    )
  where
    ith = Doc.ordinal index

-- | Report for a case-branch that does not match the previous branches.
caseBranchReport ::
  ((Maybe Ann.Region, String, String, String, [Doc.Doc]) -> Report.Report) ->
  Ann.Region ->
  Index.ZeroBased ->
  Report.Report
caseBranchReport mismatch exprRegion index =
  mismatch
    ( Just exprRegion,
      "The " <> ith <> " branch of this `case` does not match all the previous branches:",
      "The " <> ith <> " branch is",
      "But all the previous branches result in:",
      [ Doc.link
          "Hint"
          "All branches in a `case` must produce the same type of values. This way, no\
          \ matter which branch we take, the result is always a consistent shape. Read"
          "custom-types"
          "to learn how to \8220mix\8221 types."
      ]
    )
  where
    ith = Doc.ordinal index

-- | Report for calling a value with too many arguments.
callArityReport ::
  Code.Source ->
  Ann.Region ->
  TypeErr.Type ->
  MaybeName ->
  Int ->
  Report.Report
callArityReport source exprRegion tipe maybeFuncName numGivenArgs =
  Report.Report "TOO MANY ARGS" exprRegion [] . Code.toSnippet source exprRegion (Just exprRegion) $
    case countArgs tipe of
      0 ->
        ( Doc.reflow $ thisValue <> " is not a function, but it was given " <> Doc.args numGivenArgs <> ".",
          Doc.reflow "Are there any missing commas? Or missing parentheses?"
        )
        where
          thisValue =
            case maybeFuncName of
              NoName -> "This value"
              FuncName name -> "The `" <> Name.toChars name <> "` value"
              CtorName name -> "The `" <> Name.toChars name <> "` value"
              OpName op -> "The (" <> Name.toChars op <> ") operator"
      n ->
        ( Doc.reflow $ thisFunction <> " expects " <> Doc.args n <> ", but it got " <> show numGivenArgs <> " instead.",
          Doc.reflow "Are there any missing commas? Or missing parentheses?"
        )
        where
          thisFunction =
            case maybeFuncName of
              NoName -> "This function"
              FuncName name -> "The `" <> Name.toChars name <> "` function"
              CtorName name -> "The `" <> Name.toChars name <> "` constructor"
              OpName op -> "The (" <> Name.toChars op <> ") operator"

-- | Report for a call argument with the wrong type.
callArgReport ::
  ((Maybe Ann.Region, String, String, String, [Doc.Doc]) -> Report.Report) ->
  Ann.Region ->
  MaybeName ->
  Index.ZeroBased ->
  Report.Report
callArgReport mismatch exprRegion maybeFuncName index =
  mismatch
    ( Just exprRegion,
      "The " <> ith <> " argument to " <> thisFunction <> " is not what I expect:",
      "This argument is",
      "But " <> thisFunction <> " needs the " <> ith <> " argument to be:",
      if Index.toHuman index == 1
        then []
        else
          [ Doc.toSimpleHint
              "I always figure out the argument types from left to right. If an argument\
              \ is acceptable, I assume it is \8220correct\8221 and move on. So the problem may\
              \ actually be in one of the previous arguments!"
          ]
    )
  where
    ith = Doc.ordinal index
    thisFunction =
      case maybeFuncName of
        NoName -> "this function"
        FuncName name -> "`" <> Name.toChars name <> "`"
        CtorName name -> "`" <> Name.toChars name <> "`"
        OpName op -> "(" <> Name.toChars op <> ")"

-- | Report for a record-update value with the wrong field type.
recordUpdateValueReport ::
  ((Maybe Ann.Region, String, String, String, [Doc.Doc]) -> Report.Report) ->
  Ann.Region ->
  Name.Name ->
  Report.Report
recordUpdateValueReport mismatch exprRegion field =
  mismatch
    ( Just exprRegion,
      "I cannot update the `" <> Name.toChars field <> "` field like this:",
      "You are trying to update `" <> Name.toChars field <> "` to be",
      "But it should be:",
      [ Doc.toSimpleNote
          "The record update syntax does not allow you to change the type of fields.\
          \ You can achieve that with record constructors or the record literal syntax."
      ]
    )

-- | Report for a destructuring pattern that does not match the value type.
destructureReport ::
  ((Maybe Ann.Region, String, String, String, [Doc.Doc]) -> Report.Report) ->
  Report.Report
destructureReport mismatch =
  mismatch
    ( Nothing,
      "This definition is causing issues:",
      "You are defining",
      "But then trying to destructure it as:",
      []
    )

-- | Report for a template literal expression that is not a String.
interpolationReport ::
  ((Maybe Ann.Region, String, String, [Doc.Doc]) -> Report.Report) ->
  Ann.Region ->
  Index.ZeroBased ->
  Report.Report
interpolationReport badType exprRegion index =
  badType
    ( Just exprRegion,
      "The " <> ith <> " expression in this template literal is not a String:",
      "It is",
      [ Doc.fillSep
          [ "Every",
            "expression",
            "inside",
            Doc.dullyellow "${...}",
            "must",
            "be",
            "a",
            Doc.green "String" <> "."
          ],
        Doc.toSimpleHint
          "To convert other types to strings, use String.fromInt, String.fromFloat,\
          \ or write a custom function that returns a String."
      ]
    )
  where
    ith = Doc.ordinal index
