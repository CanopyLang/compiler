{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}

-- | Reporting.Error.Type - Type-error definitions and diagnostic rendering
--
-- This module is the single public interface for type errors in the Canopy
-- compiler.  It defines the 'Error', 'Expected', 'PExpected', 'Context',
-- 'PContext', and 'SubContext' types (used throughout the type solver and
-- constraint generator) and exposes 'toDiagnostic' as the main rendering
-- entry point.
--
-- The large rendering helpers are split into sub-modules:
--
--   * "Reporting.Error.Type.Hint"      - hint docs for type-variable problems
--   * "Reporting.Error.Type.Operators" - category types and operator errors
--
-- All types from sub-modules are re-exported so that downstream callers
-- ('Type.Constrain.Expression', 'Type.Solve', etc.) can continue importing
-- from this module unchanged.
module Reporting.Error.Type
  ( Error (..),
    -- * Expression expectations
    Expected (..),
    Context (..),
    SubContext (..),
    -- * Pattern expectations
    PExpected (..),
    PContext (..),
    -- * Category types (re-exported from Operators sub-module)
    Category (..),
    MaybeName (..),
    PCategory (..),
    -- * Helpers
    typeReplace,
    ptypeReplace,
    toDiagnostic,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Data.Map as Map
import qualified Data.Text as Text
import qualified Reporting.Annotation as Ann
import qualified Reporting.Diagnostic as Diag
import Reporting.Diagnostic (Diagnostic, LabeledSpan (..), SpanStyle (..))
import qualified Reporting.Doc as Doc
import qualified Reporting.ErrorCode as EC
import qualified Reporting.Render.Code as Code
import qualified Reporting.Render.Type as RT
import qualified Reporting.Render.Type.Localizer as Localizer
import qualified Reporting.Report as Report
import qualified Reporting.Suggest as Suggest
import qualified Type.Error as TypeErr
import Reporting.Error.Type.Hint (problemsToHint)
import Reporting.Error.Type.Operators
  ( Category (..),
    MaybeName (..),
    PCategory (..),
    RightDocs (..),
    addCategory,
    addPatternCategory,
    opLeftToDocs,
    opRightToDocs,
  )
import Prelude hiding (round)

-- ---------------------------------------------------------------------------
-- Error type
-- ---------------------------------------------------------------------------

-- | The top-level type error produced by the type solver.
data Error
  = BadExpr Ann.Region Category TypeErr.Type (Expected TypeErr.Type)
  | BadPattern Ann.Region PCategory TypeErr.Type (PExpected TypeErr.Type)
  | InfiniteType Ann.Region Name.Name TypeErr.Type
  deriving (Show)

-- ---------------------------------------------------------------------------
-- Expression expectations
-- ---------------------------------------------------------------------------

-- | How the solver arrived at the expected type for an expression.
data Expected tipe
  = NoExpectation tipe
  | FromContext Ann.Region Context tipe
  | FromAnnotation Name.Name Int SubContext tipe

deriving instance Show a => Show (Expected a)

-- | The syntactic context that constrains an expression's type.
data Context
  = ListEntry Index.ZeroBased
  | Negate
  | OpLeft Name.Name
  | OpRight Name.Name
  | IfCondition
  | IfBranch Index.ZeroBased
  | CaseBranch Index.ZeroBased
  | CallArity MaybeName Int
  | CallArg MaybeName Index.ZeroBased
  | RecordAccess Ann.Region (Maybe Name.Name) Ann.Region Name.Name
  | RecordUpdateKeys Name.Name (Map.Map Name.Name Can.FieldUpdate)
  | RecordUpdateValue Name.Name
  | Destructure
  deriving (Show)

-- | The sub-context within a type-annotated definition.
data SubContext
  = TypedIfBranch Index.ZeroBased
  | TypedCaseBranch Index.ZeroBased
  | TypedBody
  deriving (Show)

-- ---------------------------------------------------------------------------
-- Pattern expectations
-- ---------------------------------------------------------------------------

-- | How the solver arrived at the expected type for a pattern.
data PExpected tipe
  = PNoExpectation tipe
  | PFromContext Ann.Region PContext tipe
  deriving (Show)

-- | The syntactic context that constrains a pattern's type.
data PContext
  = PTypedArg Name.Name Index.ZeroBased
  | PCaseMatch Index.ZeroBased
  | PCtorArg Name.Name Index.ZeroBased
  | PListEntry Index.ZeroBased
  | PTail
  deriving (Show)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | Replace the type inside an 'Expected' wrapper.
typeReplace :: Expected a -> b -> Expected b
typeReplace expectation tipe =
  case expectation of
    NoExpectation _ ->
      NoExpectation tipe
    FromContext region context _ ->
      FromContext region context tipe
    FromAnnotation name arity context _ ->
      FromAnnotation name arity context tipe

-- | Replace the type inside a 'PExpected' wrapper.
ptypeReplace :: PExpected a -> b -> PExpected b
ptypeReplace expectation tipe =
  case expectation of
    PNoExpectation _ ->
      PNoExpectation tipe
    PFromContext region context _ ->
      PFromContext region context tipe

-- ---------------------------------------------------------------------------
-- toDiagnostic
-- ---------------------------------------------------------------------------

-- | Convert a type error to a structured 'Diagnostic'.
--
-- Wraps the error in the 'Diagnostic' type with structured metadata:
-- error code, severity, phase, summary text, and labeled source spans.
toDiagnostic :: Localizer.Localizer -> Code.Source -> Error -> Diagnostic
toDiagnostic localizer source err =
  case err of
    BadExpr region category tipe expected ->
      badExprDiagnostic localizer source region category tipe expected
    BadPattern region category tipe expected ->
      badPatternDiagnostic localizer source region category tipe expected
    InfiniteType region name tipe ->
      infiniteTypeDiagnostic localizer source region name tipe

-- | Produce a diagnostic for a 'BadExpr' type error.
badExprDiagnostic :: Localizer.Localizer -> Code.Source -> Ann.Region -> Category -> TypeErr.Type -> Expected TypeErr.Type -> Diagnostic
badExprDiagnostic localizer source region category tipe expected =
  Diag.makeDiagnostic
    (EC.typeError 0)
    Diag.SError
    Diag.PhaseType
    (Text.pack (categoryTitle category))
    (Text.pack (categorySummary category))
    (LabeledSpan region "type mismatch here" SpanPrimary)
    (Report._message (toExprReport source localizer region category tipe expected))

-- | Produce a diagnostic for a 'BadPattern' type error.
badPatternDiagnostic :: Localizer.Localizer -> Code.Source -> Ann.Region -> PCategory -> TypeErr.Type -> PExpected TypeErr.Type -> Diagnostic
badPatternDiagnostic localizer source region category tipe expected =
  Diag.makeDiagnostic
    (EC.typeError 1)
    Diag.SError
    Diag.PhaseType
    "TYPE MISMATCH IN PATTERN"
    (Text.pack (patternCategorySummary category))
    (LabeledSpan region "pattern type mismatch here" SpanPrimary)
    (Report._message (toPatternReport source localizer region category tipe expected))

-- | Produce a diagnostic for an 'InfiniteType' error.
infiniteTypeDiagnostic :: Localizer.Localizer -> Code.Source -> Ann.Region -> Name.Name -> TypeErr.Type -> Diagnostic
infiniteTypeDiagnostic localizer source region name tipe =
  Diag.makeDiagnostic
    (EC.typeError 2)
    Diag.SError
    Diag.PhaseType
    "INFINITE TYPE"
    (Text.pack ("Infinite type inferred for " <> Name.toChars name))
    (LabeledSpan region "infinite type here" SpanPrimary)
    (Report._message (toInfiniteReport source localizer region name tipe))

-- ---------------------------------------------------------------------------
-- Category helpers
-- ---------------------------------------------------------------------------

-- | Map a 'Category' to a display title for diagnostic output.
categoryTitle :: Category -> String
categoryTitle _ = "TYPE MISMATCH"

-- | Map a 'Category' to a one-line summary for diagnostic output.
categorySummary :: Category -> String
categorySummary category =
  case category of
    List -> "A list element has the wrong type."
    Number -> "A number has the wrong type."
    Float -> "A float has the wrong type."
    String -> "A string has the wrong type."
    Char -> "A character has the wrong type."
    If -> "An if expression branch has the wrong type."
    Case -> "A case expression branch has the wrong type."
    CallResult _ -> "A function call returns the wrong type."
    Lambda -> "An anonymous function has the wrong type."
    Accessor _ -> "A field accessor has the wrong type."
    Access _ -> "A field access has the wrong type."
    Record -> "A record has the wrong type."
    Tuple -> "A tuple has the wrong type."
    Unit -> "A unit value has the wrong type."
    Shader -> "A shader has the wrong type."
    Effects -> "An effects value has the wrong type."
    Local name -> "The value `" <> Name.toChars name <> "` has the wrong type."
    Foreign name -> "The value `" <> Name.toChars name <> "` has the wrong type."

-- | Map a 'PCategory' to a one-line summary for diagnostic output.
patternCategorySummary :: PCategory -> String
patternCategorySummary category =
  case category of
    PRecord -> "A record pattern has the wrong type."
    PUnit -> "A unit pattern has the wrong type."
    PTuple -> "A tuple pattern has the wrong type."
    PList -> "A list pattern has the wrong type."
    PCtor name -> "The `" <> Name.toChars name <> "` constructor pattern has the wrong type."
    PInt -> "An integer pattern has the wrong type."
    PStr -> "A string pattern has the wrong type."
    PChr -> "A character pattern has the wrong type."
    PBool -> "A boolean pattern has the wrong type."

-- ---------------------------------------------------------------------------
-- toPatternReport
-- ---------------------------------------------------------------------------

toPatternReport :: Code.Source -> Localizer.Localizer -> Ann.Region -> PCategory -> TypeErr.Type -> PExpected TypeErr.Type -> Report.Report
toPatternReport source localizer patternRegion category tipe expected =
  Report.Report "TYPE MISMATCH" patternRegion [] $
    case expected of
      PNoExpectation expectedType ->
        Code.toSnippet
          source
          patternRegion
          Nothing
          ( "This pattern is being used in an unexpected way:",
            patternTypeComparison
              localizer
              tipe
              expectedType
              (addPatternCategory "It is" category)
              "But it needs to match:"
              []
          )
      PFromContext region context expectedType ->
        Code.toSnippet source region (Just patternRegion) $
          patternContextDocs localizer tipe expectedType category context

patternContextDocs :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> PCategory -> PContext -> (Doc.Doc, Doc.Doc)
patternContextDocs localizer tipe expectedType category context =
  case context of
    PTypedArg name index ->
      ( Doc.reflow $
          "The " <> Doc.ordinal index <> " argument to `" <> Name.toChars name <> "` is weird.",
        patternTypeComparison
          localizer
          tipe
          expectedType
          (addPatternCategory "The argument is a pattern that matches" category)
          ( "But the type annotation on `" <> Name.toChars name
              <> "` says the "
              <> Doc.ordinal index
              <> " argument should be:"
          )
          []
      )
    PCaseMatch index ->
      patternCaseMatchDocs localizer tipe expectedType category index
    PCtorArg name index ->
      ( Doc.reflow $
          "The " <> Doc.ordinal index <> " argument to `" <> Name.toChars name <> "` is weird.",
        patternTypeComparison
          localizer
          tipe
          expectedType
          (addPatternCategory "It is trying to match" category)
          ( "But `" <> Name.toChars name <> "` needs its "
              <> Doc.ordinal index
              <> " argument to be:"
          )
          []
      )
    PListEntry index ->
      ( Doc.reflow $
          "The " <> Doc.ordinal index <> " pattern in this list does not match all the previous ones:",
        patternTypeComparison
          localizer
          tipe
          expectedType
          (addPatternCategory ("The " <> Doc.ordinal index <> " pattern is trying to match") category)
          "But all the previous patterns in the list are:"
          [ Doc.link
              "Hint"
              "Everything in a list must be the same type of value. This way, we never\
              \ run into unexpected values partway through a List.map, List.foldl, etc. Read"
              "custom-types"
              "to learn how to \8220mix\8221 types."
          ]
      )
    PTail ->
      ( Doc.reflow "The pattern after (::) is causing issues.",
        patternTypeComparison
          localizer
          tipe
          expectedType
          (addPatternCategory "The pattern after (::) is trying to match" category)
          "But it needs to match lists like this:"
          []
      )

patternCaseMatchDocs :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> PCategory -> Index.ZeroBased -> (Doc.Doc, Doc.Doc)
patternCaseMatchDocs localizer tipe expectedType category index =
  if index == Index.first
    then
      ( Doc.reflow "The 1st pattern in this `case` causing a mismatch:",
        patternTypeComparison
          localizer
          tipe
          expectedType
          (addPatternCategory "The first pattern is trying to match" category)
          "But the expression between `case` and `of` is:"
          [ Doc.reflow "These can never match! Is the pattern the problem? Or is it the expression?"
          ]
      )
    else
      ( Doc.reflow $
          "The " <> Doc.ordinal index <> " pattern in this `case` does not match the previous ones.",
        patternTypeComparison
          localizer
          tipe
          expectedType
          (addPatternCategory ("The " <> Doc.ordinal index <> " pattern is trying to match") category)
          "But all the previous patterns match:"
          [ Doc.link
              "Note"
              "A `case` expression can only handle one type of value, so you may want to use"
              "custom-types"
              "to handle \8220mixing\8221 types."
          ]
      )

patternTypeComparison :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> String -> String -> [Doc.Doc] -> Doc.Doc
patternTypeComparison localizer actual expected iAmSeeing insteadOf contextHints =
  let (actualDoc, expectedDoc, problems) =
        TypeErr.toComparison localizer actual expected
   in Doc.stack
        ( [ Doc.reflow iAmSeeing,
            Doc.indent 4 actualDoc,
            Doc.reflow insteadOf,
            Doc.indent 4 expectedDoc
          ]
            <> (problemsToHint problems <> contextHints)
        )

-- ---------------------------------------------------------------------------
-- toExprReport
-- ---------------------------------------------------------------------------

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
  let thing =
        case subContext of
          TypedIfBranch index -> Doc.ordinal index <> " branch of this `if` expression:"
          TypedCaseBranch index -> Doc.ordinal index <> " branch of this `case` expression:"
          TypedBody -> "body of the `" <> Name.toChars name <> "` definition:"
      itIs =
        case subContext of
          TypedIfBranch index -> "The " <> Doc.ordinal index <> " branch is"
          TypedCaseBranch index -> "The " <> Doc.ordinal index <> " branch is"
          TypedBody -> "The body is"
   in Report.Report "TYPE MISMATCH" exprRegion [] . Code.toSnippet source exprRegion Nothing $
        ( Doc.reflow ("Something is off with the " <> thing),
          typeComparison
            localizer
            tipe
            expectedType
            (addCategory itIs category)
            ("But the type annotation on `" <> Name.toChars name <> "` says it should be:")
            []
        )

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
  let mismatch (maybeHighlight, problem, thisIs, insteadOf, furtherDetails) =
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
   in contextDispatch mismatch badType custom source localizer exprRegion category tipe expectedType context

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
      let ith = Doc.ordinal index
       in mismatch
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
    Negate ->
      badType
        ( Just exprRegion,
          "I do not know how to negate this type of value:",
          "It is",
          [ Doc.fillSep
              ["But", "I", "only", "now", "how", "to", "negate", Doc.dullyellow "Int", "and", Doc.dullyellow "Float", "values."]
          ]
        )
    OpLeft op ->
      custom (Just exprRegion) $
        opLeftToDocs localizer category op tipe expectedType
    OpRight op ->
      case opRightToDocs localizer category op tipe expectedType of
        EmphBoth details -> custom Nothing details
        EmphRight details -> custom (Just exprRegion) details
    IfCondition ->
      badType
        ( Just exprRegion,
          "This `if` condition does not evaluate to a boolean value, True or False.",
          "It is",
          [Doc.fillSep ["But", "I", "need", "this", "`if`", "condition", "to", "be", "a", Doc.dullyellow "Bool", "value."]]
        )
    IfBranch index ->
      let ith = Doc.ordinal index
       in mismatch
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
    CaseBranch index ->
      let ith = Doc.ordinal index
       in mismatch
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
    CallArity maybeFuncName numGivenArgs ->
      callArityReport source exprRegion tipe maybeFuncName numGivenArgs
    CallArg maybeFuncName index ->
      callArgReport mismatch exprRegion maybeFuncName index
    RecordAccess recordRegion maybeName fieldRegion field ->
      recordAccessReport badType custom localizer tipe recordRegion maybeName fieldRegion field
    RecordUpdateKeys record expectedFields ->
      recordUpdateKeysReport mismatch badType custom localizer exprRegion tipe record expectedFields
    RecordUpdateValue field ->
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
    Destructure ->
      mismatch
        ( Nothing,
          "This definition is causing issues:",
          "You are defining",
          "But then trying to destructure it as:",
          []
        )

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
        let thisValue =
              case maybeFuncName of
                NoName -> "This value"
                FuncName name -> "The `" <> Name.toChars name <> "` value"
                CtorName name -> "The `" <> Name.toChars name <> "` value"
                OpName op -> "The (" <> Name.toChars op <> ") operator"
         in ( Doc.reflow $ thisValue <> " is not a function, but it was given " <> Doc.args numGivenArgs <> ".",
              Doc.reflow "Are there any missing commas? Or missing parentheses?"
            )
      n ->
        let thisFunction =
              case maybeFuncName of
                NoName -> "This function"
                FuncName name -> "The `" <> Name.toChars name <> "` function"
                CtorName name -> "The `" <> Name.toChars name <> "` constructor"
                OpName op -> "The (" <> Name.toChars op <> ") operator"
         in ( Doc.reflow $ thisFunction <> " expects " <> Doc.args n <> ", but it got " <> show numGivenArgs <> " instead.",
              Doc.reflow "Are there any missing commas? Or missing parentheses?"
            )

callArgReport ::
  ((Maybe Ann.Region, String, String, String, [Doc.Doc]) -> Report.Report) ->
  Ann.Region ->
  MaybeName ->
  Index.ZeroBased ->
  Report.Report
callArgReport mismatch exprRegion maybeFuncName index =
  let ith = Doc.ordinal index
      thisFunction =
        case maybeFuncName of
          NoName -> "this function"
          FuncName name -> "`" <> Name.toChars name <> "`"
          CtorName name -> "`" <> Name.toChars name <> "`"
          OpName op -> "(" <> Name.toChars op <> ")"
   in mismatch
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

recordAccessReport ::
  ((Maybe Ann.Region, String, String, [Doc.Doc]) -> Report.Report) ->
  (Maybe Ann.Region -> (Doc.Doc, Doc.Doc) -> Report.Report) ->
  Localizer.Localizer ->
  TypeErr.Type ->
  Ann.Region ->
  Maybe Name.Name ->
  Ann.Region ->
  Name.Name ->
  Report.Report
recordAccessReport badType custom localizer tipe recordRegion maybeName fieldRegion field =
  case TypeErr.iteratedDealias tipe of
    TypeErr.Record fields ext ->
      custom
        (Just fieldRegion)
        ( Doc.reflow $
            "This "
              <> maybe "" (\n -> "`" <> Name.toChars n <> "`") maybeName
              <> " record does not have a `"
              <> Name.toChars field
              <> "` field:",
          recordAccessBody localizer maybeName field fields ext
        )
    _ ->
      badType
        ( Just recordRegion,
          "This is not a record, so it has no fields to access!",
          "It is",
          [ Doc.fillSep
              ["But", "I", "need", "a", "record", "with", "a", Doc.dullyellow (Doc.fromName field), "field!"]
          ]
        )

recordAccessBody :: Localizer.Localizer -> Maybe Name.Name -> Name.Name -> Map.Map Name.Name TypeErr.Type -> TypeErr.Extension -> Doc.Doc
recordAccessBody localizer maybeName field fields ext =
  case Suggest.sort (Name.toChars field) (Name.toChars . fst) (Map.toList fields) of
    [] ->
      Doc.reflow "In fact, it is a record with NO fields!"
    f : fs ->
      Doc.stack
        [ Doc.reflow $
            "This is usually a typo. Here are the "
              <> maybe "" (\n -> "`" <> Name.toChars n <> "`") maybeName
              <> " fields that are most similar:",
          toNearbyRecord localizer f fs ext,
          Doc.fillSep
            ["So", "maybe", Doc.dullyellow (Doc.fromName field), "should", "be", Doc.green (Doc.fromName (fst f)) <> "?"]
        ]

recordUpdateKeysReport ::
  ((Maybe Ann.Region, String, String, String, [Doc.Doc]) -> Report.Report) ->
  ((Maybe Ann.Region, String, String, [Doc.Doc]) -> Report.Report) ->
  (Maybe Ann.Region -> (Doc.Doc, Doc.Doc) -> Report.Report) ->
  Localizer.Localizer ->
  Ann.Region ->
  TypeErr.Type ->
  Name.Name ->
  Map.Map Name.Name Can.FieldUpdate ->
  Report.Report
recordUpdateKeysReport mismatch badType custom localizer exprRegion tipe record expectedFields =
  case TypeErr.iteratedDealias tipe of
    TypeErr.Record actualFields ext ->
      case Map.lookupMin (Map.difference expectedFields actualFields) of
        Nothing ->
          mismatch
            ( Nothing,
              "Something is off with this record update:",
              "The `" <> Name.toChars record <> "` record is",
              "But this update needs it to be compatable with:",
              [ Doc.reflow
                  "Do you mind creating an <http://sscce.org/> that produces this error message and\
                  \ sharing it at <https://github.com/canopy/error-message-catalog/issues> so we\
                  \ can try to give better advice here?"
              ]
            )
        Just (field, Can.FieldUpdate fieldRegion _) ->
          recordUpdateMissingField custom localizer record field fieldRegion actualFields ext
    _ ->
      badType
        ( Just exprRegion,
          "This is not a record, so it has no fields to update!",
          "It is",
          [Doc.reflow "But I need a record!"]
        )

recordUpdateMissingField ::
  (Maybe Ann.Region -> (Doc.Doc, Doc.Doc) -> Report.Report) ->
  Localizer.Localizer ->
  Name.Name ->
  Name.Name ->
  Ann.Region ->
  Map.Map Name.Name TypeErr.Type ->
  TypeErr.Extension ->
  Report.Report
recordUpdateMissingField custom localizer record field fieldRegion actualFields ext =
  let rStr = "`" <> Name.toChars record <> "`"
      fStr = "`" <> Name.toChars field <> "`"
   in custom
        (Just fieldRegion)
        ( Doc.reflow $
            "The " <> rStr <> " record does not have a " <> fStr <> " field:",
          case Suggest.sort (Name.toChars field) (Name.toChars . fst) (Map.toList actualFields) of
            [] ->
              Doc.reflow $ "In fact, " <> rStr <> " is a record with NO fields!"
            f : fs ->
              Doc.stack
                [ Doc.reflow $
                    "This is usually a typo. Here are the " <> rStr <> " fields that are most similar:",
                  toNearbyRecord localizer f fs ext,
                  Doc.fillSep
                    ["So", "maybe", Doc.dullyellow (Doc.fromName field), "should", "be", Doc.green (Doc.fromName (fst f)) <> "?"]
                ]
        )

-- ---------------------------------------------------------------------------
-- Shared rendering helpers
-- ---------------------------------------------------------------------------

-- | Side-by-side type comparison with hints.
typeComparison :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> String -> String -> [Doc.Doc] -> Doc.Doc
typeComparison localizer actual expected iAmSeeing insteadOf contextHints =
  let (actualDoc, expectedDoc, problems) =
        TypeErr.toComparison localizer actual expected
   in Doc.stack
        ( [ Doc.reflow iAmSeeing,
            Doc.indent 4 actualDoc,
            Doc.reflow insteadOf,
            Doc.indent 4 expectedDoc
          ]
            <> (contextHints <> problemsToHint problems)
        )

-- | Show only the actual type with a custom heading.
loneType :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> Doc.Doc -> [Doc.Doc] -> Doc.Doc
loneType localizer actual expected iAmSeeing furtherDetails =
  let (actualDoc, _, problems) =
        TypeErr.toComparison localizer actual expected
   in Doc.stack
        ( [iAmSeeing, Doc.indent 4 actualDoc]
            <> (furtherDetails <> problemsToHint problems)
        )

-- | Count the number of arguments in a function type.
countArgs :: TypeErr.Type -> Int
countArgs tipe =
  case tipe of
    TypeErr.Lambda _ _ stuff -> 1 + length stuff
    _ -> 0

-- | Format the most similar record fields for a field-not-found error.
toNearbyRecord :: Localizer.Localizer -> (Name.Name, TypeErr.Type) -> [(Name.Name, TypeErr.Type)] -> TypeErr.Extension -> Doc.Doc
toNearbyRecord localizer f fs ext =
  Doc.indent 4 $
    if length fs <= 3
      then RT.vrecord (fmap (fieldToDocs localizer) (f : fs)) (extToDoc ext)
      else RT.vrecordSnippet (fieldToDocs localizer f) (fmap (fieldToDocs localizer) (take 3 fs))

fieldToDocs :: Localizer.Localizer -> (Name.Name, TypeErr.Type) -> (Doc.Doc, Doc.Doc)
fieldToDocs localizer (name, tipe) =
  ( Doc.fromName name,
    TypeErr.toDoc localizer RT.None tipe
  )

extToDoc :: TypeErr.Extension -> Maybe Doc.Doc
extToDoc ext =
  case ext of
    TypeErr.Closed -> Nothing
    TypeErr.FlexOpen x -> Just (Doc.fromName x)
    TypeErr.RigidOpen x -> Just (Doc.fromName x)

-- ---------------------------------------------------------------------------
-- toInfiniteReport
-- ---------------------------------------------------------------------------

toInfiniteReport :: Code.Source -> Localizer.Localizer -> Ann.Region -> Name.Name -> TypeErr.Type -> Report.Report
toInfiniteReport source localizer region name overallType =
  Report.Report "INFINITE TYPE" region [] $
    Code.toSnippet
      source
      region
      Nothing
      ( Doc.reflow $
          "I am inferring a weird self-referential type for " <> Name.toChars name <> ":",
        Doc.stack
          [ Doc.reflow
              "Here is my best effort at writing down the type. You will see \8734 for\
              \ parts of the type that repeat something already printed out infinitely.",
            Doc.indent 4 (Doc.dullyellow (TypeErr.toDoc localizer RT.None overallType)),
            Doc.reflowLink
              "Staring at this type is usually not so helpful, so I recommend reading the hints at"
              "infinite-type"
              "to get unstuck!"
          ]
      )
