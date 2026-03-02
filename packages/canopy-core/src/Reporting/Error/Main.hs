{-# LANGUAGE OverloadedStrings #-}

module Reporting.Error.Main
  ( Error (..),
    toDiagnostic,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Name as Name
import qualified Data.Text as Text
import Data.Text (Text)
import qualified Reporting.Annotation as Ann
import Reporting.Diagnostic (Diagnostic, LabeledSpan (..), SpanStyle (..))
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Doc as Doc
import qualified Reporting.Error.Canonicalize as CanonicalizeError
import qualified Reporting.ErrorCode as EC
import qualified Reporting.Render.Code as Code
import qualified Reporting.Render.Type as RT
import qualified Reporting.Render.Type.Localizer as Localizer

-- ERROR

data Error
  = BadType Ann.Region Can.Type
  | BadCycle Ann.Region Name.Name [Name.Name]
  | BadFlags Ann.Region Can.Type CanonicalizeError.InvalidPayload
  | InternalLookupFailure Name.Name Text
  deriving (Show)

-- TO DIAGNOSTIC

-- | Convert a main error to a structured 'Diagnostic'.
--
-- @
-- BadType                -> E0600
-- BadCycle               -> E0601
-- BadFlags               -> E0602
-- InternalLookupFailure  -> E0603
-- @
toDiagnostic :: Localizer.Localizer -> Code.Source -> Error -> Diagnostic
toDiagnostic localizer source err =
  case err of
    BadType region tipe ->
      badTypeDiagnostic localizer source region tipe
    BadCycle region name names ->
      badCycleDiagnostic source region name names
    BadFlags region _badType invalidPayload ->
      badFlagsDiagnostic source region invalidPayload
    InternalLookupFailure name context ->
      internalLookupDiagnostic name context

badTypeDiagnostic :: Localizer.Localizer -> Code.Source -> Ann.Region -> Can.Type -> Diagnostic
badTypeDiagnostic localizer source region tipe =
  Diag.makeDiagnostic
    (EC.mainError 0)
    Diag.SError
    Diag.PhaseMain
    "BAD MAIN TYPE"
    "The main value has an unsupported type"
    (LabeledSpan region "unsupported main type" SpanPrimary)
    ( Code.toSnippet
        source
        region
        Nothing
        ( "I cannot handle this type of `main` value:",
          Doc.stack
            [ "The type of `main` value I am seeing is:",
              Doc.indent 4 . Doc.dullyellow $ RT.canToDoc localizer RT.None tipe,
              Doc.reflow
                "I only know how to handle Html, Svg, and Programs\
                \ though. Modify `main` to be one of those types of values!"
            ]
        )
    )

badCycleDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> [Name.Name] -> Diagnostic
badCycleDiagnostic source region name names =
  Diag.makeDiagnostic
    (EC.mainError 1)
    Diag.SError
    Diag.PhaseMain
    "BAD MAIN"
    "The main value is defined recursively"
    (LabeledSpan region "recursive main definition" SpanPrimary)
    ( Code.toSnippet
        source
        region
        Nothing
        ( "A `main` definition cannot be defined in terms of itself.",
          Doc.stack
            [ Doc.reflow
                "It should be a boring value with no recursion. But\
                \ instead it is involved in this cycle of definitions:",
              Doc.cycle 4 name names
            ]
        )
    )

badFlagsDiagnostic :: Code.Source -> Ann.Region -> CanonicalizeError.InvalidPayload -> Diagnostic
badFlagsDiagnostic source region invalidPayload =
  Diag.makeDiagnostic
    (EC.mainError 2)
    Diag.SError
    Diag.PhaseMain
    "BAD FLAGS"
    (payloadSummary invalidPayload)
    (LabeledSpan region "invalid flags type" SpanPrimary)
    ( Code.toSnippet
        source
        region
        Nothing
        (payloadDetails invalidPayload)
    )

payloadSummary :: CanonicalizeError.InvalidPayload -> Text
payloadSummary = \case
  CanonicalizeError.ExtendedRecord -> "Flags cannot use extended records"
  CanonicalizeError.Function -> "Flags cannot use functions"
  CanonicalizeError.TypeVariable _ -> "Flags cannot use unspecified types"
  CanonicalizeError.UnsupportedType name -> Text.pack ("Flags cannot use `" <> Name.toChars name <> "` values")

payloadDetails :: CanonicalizeError.InvalidPayload -> (Doc.Doc, Doc.Doc)
payloadDetails = \case
  CanonicalizeError.ExtendedRecord ->
    ( "Your `main` program wants an extended record from JavaScript.",
      Doc.reflow "But the exact shape of the record must be known at compile time. No type variables!"
    )
  CanonicalizeError.Function ->
    ( "Your `main` program wants a function from JavaScript.",
      Doc.reflow
        "But if I allowed functions from JS, it would be possible to sneak\
        \ side-effects and runtime exceptions into Canopy!"
    )
  CanonicalizeError.TypeVariable name ->
    ( Doc.fromChars ("Your `main` program wants an unspecified type from JavaScript."),
      Doc.reflow
        ( "But type variables like `"
            <> ( Name.toChars name
                   <> "` cannot be given as flags.\
                      \ I need to know exactly what type of data I am getting, so I can guarantee that\
                      \ unexpected data cannot sneak in and crash the Canopy program."
               )
        )
    )
  CanonicalizeError.UnsupportedType name ->
    ( Doc.fromChars ("Your `main` program wants a `" <> (Name.toChars name <> "` value from JavaScript.")),
      Doc.stack
        [ Doc.reflow "I cannot handle that. The types that CAN be in flags include:",
          Doc.indent 4 . Doc.reflow $
            "Ints, Floats, Bools, Strings, Maybes, Lists, Arrays,\
            \ tuples, records, and JSON values.",
          Doc.reflow
            "Since JSON values can flow through, you can use JSON encoders and decoders\
            \ to allow other types through as well."
        ]
    )

-- | Diagnostic for internal lookup failures during optimization.
--
-- These indicate compiler bugs where a definition or annotation was expected
-- to be present in a lookup table but was not found.
--
-- @since 0.19.2
internalLookupDiagnostic :: Name.Name -> Text -> Diagnostic
internalLookupDiagnostic name context =
  Diag.makeDiagnostic
    (EC.mainError 3)
    Diag.SError
    Diag.PhaseMain
    "INTERNAL ERROR"
    (Text.pack ("Internal lookup failure for `" <> Name.toChars name <> "`"))
    (LabeledSpan
      (Ann.Region (Ann.Position 1 1) (Ann.Position 1 1))
      (Text.pack ("missing `" <> Name.toChars name <> "`"))
      SpanPrimary)
    ( Doc.stack
        [ Doc.reflow
            ("I encountered an internal error while optimizing `" <> Name.toChars name <> "`."),
          Doc.reflow (Text.unpack context),
          Doc.reflow "This is a compiler bug. Please report it at https://github.com/canopy-lang/canopy/issues"
        ]
    )
