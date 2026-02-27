{-# LANGUAGE OverloadedStrings #-}

-- | Reporting.Error.Type.Render - Shared rendering helpers for type errors
--
-- This module provides the low-level rendering primitives used by the
-- Pattern, Expression, and Record sub-modules to format type-error messages.
-- It includes side-by-side type comparison, lone-type display, record-field
-- formatting, argument counting, and the infinite-type report.
--
-- All functions in this module are self-contained: they depend only on
-- 'Type.Error', 'Reporting.Doc', 'Reporting.Render.Type', and similar
-- leaf modules, never on the parent 'Reporting.Error.Type' or its sibling
-- sub-modules (except 'Hint').
module Reporting.Error.Type.Render
  ( -- * Type comparison docs
    typeComparison,
    loneType,

    -- * Argument helpers
    countArgs,

    -- * Record field formatting
    toNearbyRecord,
    fieldToDocs,
    extToDoc,

    -- * Infinite type report
    toInfiniteReport,
  )
where

import qualified Canopy.Data.Name as Name
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import qualified Reporting.Render.Code as Code
import qualified Reporting.Render.Type as RT
import qualified Reporting.Render.Type.Localizer as Localizer
import qualified Reporting.Report as Report
import qualified Type.Error as TypeErr
import Reporting.Error.Type.Hint (problemsToHint)

-- ---------------------------------------------------------------------------
-- Type comparison docs
-- ---------------------------------------------------------------------------

-- | Side-by-side type comparison with hints.
--
-- Renders "I am seeing X / But I expected Y" with the two types indented
-- below the headings, followed by any context-specific hints and any
-- problem-derived hints.
typeComparison :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> String -> String -> [Doc.Doc] -> Doc.Doc
typeComparison localizer actual expected iAmSeeing insteadOf contextHints =
  Doc.stack
    ( [ Doc.reflow iAmSeeing,
        Doc.indent 4 actualDoc,
        Doc.reflow insteadOf,
        Doc.indent 4 expectedDoc
      ]
        <> (contextHints <> problemsToHint problems)
    )
  where
    (actualDoc, expectedDoc, problems) =
      TypeErr.toComparison localizer actual expected

-- | Show only the actual type with a custom heading.
--
-- Used when only one side of a mismatch is interesting (e.g. "I do not
-- know how to negate this type").
loneType :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> Doc.Doc -> [Doc.Doc] -> Doc.Doc
loneType localizer actual expected iAmSeeing furtherDetails =
  Doc.stack
    ( [iAmSeeing, Doc.indent 4 actualDoc]
        <> (furtherDetails <> problemsToHint problems)
    )
  where
    (actualDoc, _, problems) =
      TypeErr.toComparison localizer actual expected

-- ---------------------------------------------------------------------------
-- Argument helpers
-- ---------------------------------------------------------------------------

-- | Count the number of arguments in a function type.
--
-- Returns 0 for non-function types and 1 + length of the extra args
-- for 'TypeErr.Lambda' types.
countArgs :: TypeErr.Type -> Int
countArgs tipe =
  case tipe of
    TypeErr.Lambda _ _ stuff -> 1 + length stuff
    _ -> 0

-- ---------------------------------------------------------------------------
-- Record field formatting
-- ---------------------------------------------------------------------------

-- | Format the most similar record fields for a field-not-found error.
--
-- Shows up to 4 fields in a vertical record layout, or a snippet if there
-- are more than 4.
toNearbyRecord :: Localizer.Localizer -> (Name.Name, TypeErr.Type) -> [(Name.Name, TypeErr.Type)] -> TypeErr.Extension -> Doc.Doc
toNearbyRecord localizer f fs ext =
  Doc.indent 4 $
    if length fs <= 3
      then RT.vrecord (fmap (fieldToDocs localizer) (f : fs)) (extToDoc ext)
      else RT.vrecordSnippet (fieldToDocs localizer f) (fmap (fieldToDocs localizer) (take 3 fs))

-- | Convert a (name, type) pair to a (Doc, Doc) pair for record rendering.
fieldToDocs :: Localizer.Localizer -> (Name.Name, TypeErr.Type) -> (Doc.Doc, Doc.Doc)
fieldToDocs localizer (name, tipe) =
  ( Doc.fromName name,
    TypeErr.toDoc localizer RT.None tipe
  )

-- | Convert a record extension to an optional doc for the trailing @| ext@ part.
extToDoc :: TypeErr.Extension -> Maybe Doc.Doc
extToDoc ext =
  case ext of
    TypeErr.Closed -> Nothing
    TypeErr.FlexOpen x -> Just (Doc.fromName x)
    TypeErr.RigidOpen x -> Just (Doc.fromName x)

-- ---------------------------------------------------------------------------
-- Infinite type report
-- ---------------------------------------------------------------------------

-- | Build the report for an infinite / self-referential type.
--
-- Shown when the type solver detects that a type variable would need to
-- unify with a type that contains itself.
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
