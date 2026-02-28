{-# LANGUAGE OverloadedStrings #-}

-- | Reporting.Error.Type.Record - Record-specific type-error reports
--
-- This module handles type errors that arise from record field access
-- (@.field@), record update syntax (@{ r | field = ... }@), and missing
-- fields.  The functions here receive callback parameters from
-- "Reporting.Error.Type.Expression" so they can produce 'Report.Report'
-- values without depending on the expression-level context types directly.
module Reporting.Error.Type.Record
  ( recordAccessReport,
    recordAccessBody,
    recordUpdateKeysReport,
    recordUpdateMissingField,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Name as Name
import qualified Data.Map.Strict as Map
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import qualified Reporting.Render.Type.Localizer as Localizer
import qualified Reporting.Report as Report
import qualified Reporting.Suggest as Suggest
import qualified Type.Error as TypeErr
import Reporting.Error.Type.Render (toNearbyRecord)

-- ---------------------------------------------------------------------------
-- Record access
-- ---------------------------------------------------------------------------

-- | Build a report for a @.field@ access on a value that either lacks the
-- field or is not a record at all.
--
-- The @badType@ and @custom@ parameters are callback functions created by
-- the expression-level report builder to wrap the result in the appropriate
-- snippet format.
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

-- | Build the body doc for a record-access error when the record exists
-- but lacks the requested field.
--
-- Suggests the most similar field names using edit-distance sorting.
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

-- ---------------------------------------------------------------------------
-- Record update
-- ---------------------------------------------------------------------------

-- | Build a report for a record-update expression where the update fields
-- do not match the actual record type.
--
-- The @mismatch@, @badType@, and @custom@ parameters are callback functions
-- created by the expression-level report builder.
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

-- | Build a report for a record-update expression where a specific field
-- is missing from the record type.
--
-- Suggests the most similar field names using edit-distance sorting.
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
  custom
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
  where
    rStr = "`" <> Name.toChars record <> "`"
    fStr = "`" <> Name.toChars field <> "`"
