{-# LANGUAGE OverloadedStrings #-}

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
--   * "Reporting.Error.Type.Types"      - core type definitions
--   * "Reporting.Error.Type.Hint"       - hint docs for type-variable problems
--   * "Reporting.Error.Type.Operators"  - category types and operator errors
--   * "Reporting.Error.Type.Render"     - shared rendering primitives
--   * "Reporting.Error.Type.Pattern"    - pattern error reports
--   * "Reporting.Error.Type.Expression" - expression error reports
--   * "Reporting.Error.Type.Record"     - record-specific error reports
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

import qualified Canopy.Data.Name as Name
import qualified Data.Text as Text
import qualified Reporting.Annotation as Ann
import qualified Reporting.Diagnostic as Diag
import Reporting.Diagnostic (Diagnostic, LabeledSpan (..), SpanStyle (..))
import qualified Reporting.ErrorCode as EC
import qualified Reporting.Render.Code as Code
import qualified Reporting.Render.Type.Localizer as Localizer
import qualified Reporting.Report as Report
import qualified Type.Error as TypeErr
import Reporting.Error.Type.Expression (toExprReport)
import Reporting.Error.Type.Operators
  ( Category (..),
    MaybeName (..),
    PCategory (..),
  )
import Reporting.Error.Type.Pattern (toPatternReport)
import Reporting.Error.Type.Render (toInfiniteReport)
import Reporting.Error.Type.Types
  ( Context (..),
    Error (..),
    Expected (..),
    PContext (..),
    PExpected (..),
    SubContext (..),
    ptypeReplace,
    typeReplace,
  )
import Prelude hiding (round)

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
