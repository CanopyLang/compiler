{-# LANGUAGE OverloadedStrings #-}

module Reporting.Error.Main
  ( Error (..),
    toDiagnostic,
  )
where

import qualified AST.Canonical as Can
import qualified Data.Name as Name
import qualified Data.Text as Text
import Data.Text (Text)
import qualified Reporting.Annotation as A
import Reporting.Diagnostic (Diagnostic, LabeledSpan (..), SpanStyle (..))
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Doc as D
import qualified Reporting.Error.Canonicalize as E
import qualified Reporting.ErrorCode as EC
import qualified Reporting.Render.Code as Code
import qualified Reporting.Render.Type as RT
import qualified Reporting.Render.Type.Localizer as L

-- ERROR

data Error
  = BadType A.Region Can.Type
  | BadCycle A.Region Name.Name [Name.Name]
  | BadFlags A.Region Can.Type E.InvalidPayload
  deriving (Show)

-- TO DIAGNOSTIC

-- | Convert a main error to a structured 'Diagnostic'.
--
-- @
-- BadType  -> E0600
-- BadCycle -> E0601
-- BadFlags -> E0602
-- @
toDiagnostic :: L.Localizer -> Code.Source -> Error -> Diagnostic
toDiagnostic localizer source err =
  case err of
    BadType region tipe ->
      badTypeDiagnostic localizer source region tipe
    BadCycle region name names ->
      badCycleDiagnostic source region name names
    BadFlags region _badType invalidPayload ->
      badFlagsDiagnostic source region invalidPayload

badTypeDiagnostic :: L.Localizer -> Code.Source -> A.Region -> Can.Type -> Diagnostic
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
          D.stack
            [ "The type of `main` value I am seeing is:",
              D.indent 4 . D.dullyellow $ RT.canToDoc localizer RT.None tipe,
              D.reflow
                "I only know how to handle Html, Svg, and Programs\
                \ though. Modify `main` to be one of those types of values!"
            ]
        )
    )

badCycleDiagnostic :: Code.Source -> A.Region -> Name.Name -> [Name.Name] -> Diagnostic
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
          D.stack
            [ D.reflow
                "It should be a boring value with no recursion. But\
                \ instead it is involved in this cycle of definitions:",
              D.cycle 4 name names
            ]
        )
    )

badFlagsDiagnostic :: Code.Source -> A.Region -> E.InvalidPayload -> Diagnostic
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

payloadSummary :: E.InvalidPayload -> Text
payloadSummary = \case
  E.ExtendedRecord -> "Flags cannot use extended records"
  E.Function -> "Flags cannot use functions"
  E.TypeVariable _ -> "Flags cannot use unspecified types"
  E.UnsupportedType name -> Text.pack ("Flags cannot use `" <> Name.toChars name <> "` values")

payloadDetails :: E.InvalidPayload -> (D.Doc, D.Doc)
payloadDetails = \case
  E.ExtendedRecord ->
    ( "Your `main` program wants an extended record from JavaScript.",
      D.reflow "But the exact shape of the record must be known at compile time. No type variables!"
    )
  E.Function ->
    ( "Your `main` program wants a function from JavaScript.",
      D.reflow
        "But if I allowed functions from JS, it would be possible to sneak\
        \ side-effects and runtime exceptions into Canopy!"
    )
  E.TypeVariable name ->
    ( D.fromChars ("Your `main` program wants an unspecified type from JavaScript."),
      D.reflow
        ( "But type variables like `"
            <> ( Name.toChars name
                   <> "` cannot be given as flags.\
                      \ I need to know exactly what type of data I am getting, so I can guarantee that\
                      \ unexpected data cannot sneak in and crash the Canopy program."
               )
        )
    )
  E.UnsupportedType name ->
    ( D.fromChars ("Your `main` program wants a `" <> (Name.toChars name <> "` value from JavaScript.")),
      D.stack
        [ D.reflow "I cannot handle that. The types that CAN be in flags include:",
          D.indent 4 . D.reflow $
            "Ints, Floats, Bools, Strings, Maybes, Lists, Arrays,\
            \ tuples, records, and JSON values.",
          D.reflow
            "Since JSON values can flow through, you can use JSON encoders and decoders\
            \ to allow other types through as well."
        ]
    )
