{-# LANGUAGE OverloadedStrings #-}

-- | Reporting.Error.Type.Pattern - Pattern type-error rendering
--
-- This module builds 'Report.Report' values for 'BadPattern' type errors.
-- It handles all pattern contexts: typed arguments, case branches, constructor
-- arguments, list entries, and cons-tail patterns.
--
-- The main entry point is 'toPatternReport', called from the parent module's
-- 'toDiagnostic' function.
module Reporting.Error.Type.Pattern
  ( toPatternReport,
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
import Reporting.Error.Type.Hint (problemsToHint)
import Reporting.Error.Type.Operators (PCategory, addPatternCategory)
import Reporting.Error.Type.Types (PContext (..), PExpected (..))

-- ---------------------------------------------------------------------------
-- toPatternReport
-- ---------------------------------------------------------------------------

-- | Build a report for a pattern type mismatch.
--
-- Dispatches on the 'PExpected' wrapper to decide between a bare
-- "unexpected usage" message and a context-aware comparison.
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

-- ---------------------------------------------------------------------------
-- Context dispatch
-- ---------------------------------------------------------------------------

-- | Build the (header, body) doc pair for a specific pattern context.
patternContextDocs :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> PCategory -> PContext -> (Doc.Doc, Doc.Doc)
patternContextDocs localizer tipe expectedType category context =
  case context of
    PTypedArg name index ->
      patternTypedArgDocs localizer tipe expectedType category name index
    PCaseMatch index ->
      patternCaseMatchDocs localizer tipe expectedType category index
    PCtorArg name index ->
      patternCtorArgDocs localizer tipe expectedType category name index
    PListEntry index ->
      patternListEntryDocs localizer tipe expectedType category index
    PTail ->
      patternTailDocs localizer tipe expectedType category

-- ---------------------------------------------------------------------------
-- Per-context doc builders
-- ---------------------------------------------------------------------------

-- | Docs for a typed-argument pattern mismatch.
patternTypedArgDocs :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> PCategory -> Name.Name -> Index.ZeroBased -> (Doc.Doc, Doc.Doc)
patternTypedArgDocs localizer tipe expectedType category name index =
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

-- | Docs for a case-branch pattern mismatch.
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

-- | Docs for a constructor-argument pattern mismatch.
patternCtorArgDocs :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> PCategory -> Name.Name -> Index.ZeroBased -> (Doc.Doc, Doc.Doc)
patternCtorArgDocs localizer tipe expectedType category name index =
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

-- | Docs for a list-entry pattern mismatch.
patternListEntryDocs :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> PCategory -> Index.ZeroBased -> (Doc.Doc, Doc.Doc)
patternListEntryDocs localizer tipe expectedType category index =
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

-- | Docs for a cons-tail pattern mismatch.
patternTailDocs :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> PCategory -> (Doc.Doc, Doc.Doc)
patternTailDocs localizer tipe expectedType category =
  ( Doc.reflow "The pattern after (::) is causing issues.",
    patternTypeComparison
      localizer
      tipe
      expectedType
      (addPatternCategory "The pattern after (::) is trying to match" category)
      "But it needs to match lists like this:"
      []
  )

-- ---------------------------------------------------------------------------
-- Pattern type comparison
-- ---------------------------------------------------------------------------

-- | Side-by-side type comparison for pattern errors.
--
-- Similar to the expression-level 'typeComparison' in "Reporting.Error.Type.Render"
-- but appends hints in a different order: problem hints come before context hints.
patternTypeComparison :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> String -> String -> [Doc.Doc] -> Doc.Doc
patternTypeComparison localizer actual expected iAmSeeing insteadOf contextHints =
  Doc.stack
    ( [ Doc.reflow iAmSeeing,
        Doc.indent 4 actualDoc,
        Doc.reflow insteadOf,
        Doc.indent 4 expectedDoc
      ]
        <> (problemsToHint problems <> contextHints)
    )
  where
    (actualDoc, expectedDoc, problems) =
      TypeErr.toComparison localizer actual expected
