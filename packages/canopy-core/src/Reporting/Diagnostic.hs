{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Universal diagnostic type for all compiler error reporting.
--
-- 'Diagnostic' replaces the old 'Report' type with full structured
-- information: error codes, multi-span labels, typed suggestions,
-- severity levels, and phase tagging. Every compiler phase produces
-- 'Diagnostic' values that can be rendered to terminal, JSON, or LSP
-- without information loss.
--
-- @since 0.19.2
module Reporting.Diagnostic
  ( -- * Core types
    Diagnostic (..),
    LabeledSpan (..),
    SpanStyle (..),
    Severity (..),
    Confidence (..),
    Suggestion (..),
    Phase (..),

    -- * Error codes
    ErrorCode (..),
    errorCodeToText,
    errorCodeToInt,

    -- * Construction helpers
    makeDiagnostic,
    makeSimpleDiagnostic,
    addSuggestion,
    addSecondarySpan,
    addNote,

    -- * JSON encoding
    diagnosticToJson,
    labeledSpanToJson,
    suggestionToJson,
    encodeRegion,

    -- * Terminal rendering
    diagnosticToDoc,
  )
where

import qualified Data.Text as Text
import Data.Text (Text)
import Data.Word (Word16)
import Json.Encode ((==>))
import qualified Json.Encode as E
import qualified Reporting.Annotation as A
import qualified Reporting.Doc as D

-- | Severity level of a diagnostic.
--
-- Determines visual styling and whether compilation should halt.
data Severity
  = SError
  | SWarning
  | SInfo
  deriving (Eq, Ord, Show)

-- | Compiler phase that produced this diagnostic.
--
-- Used for filtering and grouping diagnostics by compilation stage.
data Phase
  = PhaseParse
  | PhaseImport
  | PhaseCanon
  | PhaseType
  | PhasePattern
  | PhaseMain
  | PhaseDocs
  | PhaseOptimize
  | PhaseGenerate
  | PhaseBuild
  deriving (Eq, Ord, Show)

-- | Stable error code for documentation and tooling.
--
-- Error codes are assigned per-phase in ranges:
--
-- @
-- E0100-E0199: Parse errors
-- E0200-E0299: Import errors
-- E0300-E0399: Name resolution errors
-- E0400-E0499: Type errors
-- E0500-E0599: Pattern errors
-- E0600-E0699: Main errors
-- E0700-E0799: Documentation errors
-- E0800-E0899: Optimization errors
-- E0900-E0999: Code generation errors
-- @
newtype ErrorCode = ErrorCode Word16
  deriving (Eq, Ord, Show)

-- | Render error code as @E0401@-style text.
errorCodeToText :: ErrorCode -> Text
errorCodeToText (ErrorCode n) =
  Text.pack ("E" <> padded)
  where
    raw = show n
    padded = replicate (4 - length raw) '0' <> raw

-- | Extract the numeric value from an error code.
errorCodeToInt :: ErrorCode -> Int
errorCodeToInt (ErrorCode n) = fromIntegral n

-- | How visually prominent a labeled span should be.
data SpanStyle
  = -- | The primary error location (red underline)
    SpanPrimary
  | -- | A related location (yellow underline)
    SpanSecondary
  | -- | An informational location (blue underline)
    SpanNote
  deriving (Eq, Ord, Show)

-- | A source region with a human-readable label and visual style.
--
-- Used for multi-span error rendering. Each span points to a
-- specific source location and explains its role in the diagnostic.
data LabeledSpan = LabeledSpan
  { _spanRegion :: !A.Region,
    _spanLabel :: !Text,
    _spanStyle :: !SpanStyle
  }
  deriving (Eq, Show)

-- | Confidence level for a suggestion.
--
-- Determines whether tooling should auto-apply a fix.
data Confidence
  = -- | Certain the fix is correct (IDE can auto-apply)
    Definite
  | -- | Very likely correct (show prominently)
    Likely
  | -- | Might be correct (show as option)
    Possible
  deriving (Eq, Ord, Show)

-- | A structured suggestion for fixing a diagnostic.
--
-- Contains enough information for IDEs to produce quick-fix code
-- actions, and for terminal rendering to show concrete fix text.
data Suggestion = Suggestion
  { _sugSpan :: !A.Region,
    _sugReplacement :: !Text,
    _sugMessage :: !Text,
    _sugConfidence :: !Confidence
  }
  deriving (Eq, Show)

-- | Universal diagnostic type for all compiler phases.
--
-- This is the single source of truth for error reporting. Every
-- compiler phase converts its internal error types into 'Diagnostic'
-- at the reporting boundary. The type carries enough information for
-- terminal rendering, JSON output, and LSP integration without any
-- information loss.
data Diagnostic = Diagnostic
  { _diagCode :: !ErrorCode,
    _diagSeverity :: !Severity,
    _diagTitle :: !Text,
    _diagSummary :: !Text,
    _diagPrimary :: !LabeledSpan,
    _diagSecondary :: ![LabeledSpan],
    _diagMessage :: !D.Doc,
    _diagSuggestions :: ![Suggestion],
    _diagNotes :: ![Text],
    _diagPhase :: !Phase
  }

instance Show Diagnostic where
  show diag =
    "Diagnostic {"
      <> " code=" <> show (_diagCode diag)
      <> ", severity=" <> show (_diagSeverity diag)
      <> ", title=" <> show (_diagTitle diag)
      <> ", phase=" <> show (_diagPhase diag)
      <> " }"

-- | Construct a diagnostic with all fields.
makeDiagnostic ::
  ErrorCode ->
  Severity ->
  Phase ->
  Text ->
  Text ->
  LabeledSpan ->
  D.Doc ->
  Diagnostic
makeDiagnostic code severity phase title summary primary message =
  Diagnostic
    { _diagCode = code,
      _diagSeverity = severity,
      _diagTitle = title,
      _diagSummary = summary,
      _diagPrimary = primary,
      _diagSecondary = [],
      _diagMessage = message,
      _diagSuggestions = [],
      _diagNotes = [],
      _diagPhase = phase
    }

-- | Construct a simple diagnostic with minimal fields.
makeSimpleDiagnostic ::
  ErrorCode ->
  Phase ->
  Text ->
  A.Region ->
  D.Doc ->
  Diagnostic
makeSimpleDiagnostic code phase title region message =
  Diagnostic
    { _diagCode = code,
      _diagSeverity = SError,
      _diagTitle = title,
      _diagSummary = title,
      _diagPrimary = LabeledSpan region "" SpanPrimary,
      _diagSecondary = [],
      _diagMessage = message,
      _diagSuggestions = [],
      _diagNotes = [],
      _diagPhase = phase
    }

-- | Add a suggestion to a diagnostic.
addSuggestion :: Suggestion -> Diagnostic -> Diagnostic
addSuggestion sug diag =
  diag {_diagSuggestions = _diagSuggestions diag <> [sug]}

-- | Add a secondary span to a diagnostic.
addSecondarySpan :: LabeledSpan -> Diagnostic -> Diagnostic
addSecondarySpan span_ diag =
  diag {_diagSecondary = _diagSecondary diag <> [span_]}

-- | Add a note to a diagnostic.
addNote :: Text -> Diagnostic -> Diagnostic
addNote note diag =
  diag {_diagNotes = _diagNotes diag <> [note]}

-- TERMINAL RENDERING

-- | Render a diagnostic to a Doc for terminal output.
--
-- The rendering follows this structure:
-- @
-- -- TITLE [E0401] ------------------------------------ path/to/file.can
--
-- Summary text explaining the error.
--
-- 6|   problematic code here
--      ^^^^^^^^^^^^^^^^^^^^^^
--      primary span label
--
-- 3|   related code here
--      ^^^^^^^^^^^^^^^^^^
--      secondary span label
--
-- Try: suggestion text
--
-- Note: additional context
--
-- Learn more: canopy explain E0401
-- @
diagnosticToDoc :: FilePath -> Diagnostic -> D.Doc
diagnosticToDoc relativePath diag =
  D.vcat
    [ toMessageBar (Text.unpack (_diagTitle diag)) (Text.unpack (errorCodeToText (_diagCode diag))) relativePath,
      "",
      _diagMessage diag,
      renderSuggestions (_diagSuggestions diag),
      renderNotes (_diagNotes diag),
      renderLearnMore (_diagCode diag),
      ""
    ]

-- | Render the colored message bar with error code.
toMessageBar :: String -> String -> FilePath -> D.Doc
toMessageBar title code filePath =
  let usedSpace = 4 + length title + 1 + length code + 2 + 1 + length filePath
      dashes = replicate (max 1 (80 - usedSpace)) '-'
   in D.dullcyan . D.fromChars $
        "-- " <> title <> " [" <> code <> "] " <> dashes <> " " <> filePath

-- | Render structured suggestions.
renderSuggestions :: [Suggestion] -> D.Doc
renderSuggestions [] = D.empty
renderSuggestions sugs =
  D.vcat ("" : fmap renderOneSuggestion sugs)

renderOneSuggestion :: Suggestion -> D.Doc
renderOneSuggestion sug =
  D.vcat
    [ D.fillSep
        ( D.green (D.underline "Try") <> ":" :
          fmap D.fromChars (words (Text.unpack (_sugMessage sug)))
        ),
      "",
      D.indent 4 (D.green (D.fromChars (Text.unpack (_sugReplacement sug))))
    ]

-- | Render notes.
renderNotes :: [Text] -> D.Doc
renderNotes [] = D.empty
renderNotes notes =
  D.vcat ("" : fmap renderOneNote notes)

renderOneNote :: Text -> D.Doc
renderOneNote note =
  D.fillSep (D.underline "Note" <> ":" : fmap D.fromChars (words (Text.unpack note)))

-- | Render the "Learn more" link.
renderLearnMore :: ErrorCode -> D.Doc
renderLearnMore code =
  D.vcat
    [ "",
      D.fromChars ("Learn more: canopy explain " <> Text.unpack (errorCodeToText code))
    ]

-- JSON ENCODING

-- | Encode a diagnostic as a fully structured JSON value.
--
-- The output contains all semantic information needed for IDE integration:
-- error code, severity, spans with labels, suggestions with confidence,
-- and phase information.
diagnosticToJson :: Diagnostic -> E.Value
diagnosticToJson diag =
  E.object
    [ "code" ==> E.chars (Text.unpack (errorCodeToText (_diagCode diag))),
      "severity" ==> encodeSeverity (_diagSeverity diag),
      "title" ==> E.chars (Text.unpack (_diagTitle diag)),
      "summary" ==> E.chars (Text.unpack (_diagSummary diag)),
      "primary" ==> labeledSpanToJson (_diagPrimary diag),
      "secondary" ==> E.list labeledSpanToJson (_diagSecondary diag),
      "suggestions" ==> E.list suggestionToJson (_diagSuggestions diag),
      "notes" ==> E.list (E.chars . Text.unpack) (_diagNotes diag),
      "phase" ==> encodePhase (_diagPhase diag),
      "message" ==> D.encode (_diagMessage diag)
    ]

-- | Encode a labeled span as JSON.
labeledSpanToJson :: LabeledSpan -> E.Value
labeledSpanToJson (LabeledSpan region label style) =
  E.object
    [ "region" ==> encodeRegion region,
      "label" ==> E.chars (Text.unpack label),
      "style" ==> encodeSpanStyle style
    ]

-- | Encode a suggestion as JSON.
suggestionToJson :: Suggestion -> E.Value
suggestionToJson (Suggestion region replacement message confidence) =
  E.object
    [ "region" ==> encodeRegion region,
      "replacement" ==> E.chars (Text.unpack replacement),
      "message" ==> E.chars (Text.unpack message),
      "confidence" ==> encodeConfidence confidence
    ]

-- | Encode a region as JSON.
encodeRegion :: A.Region -> E.Value
encodeRegion (A.Region (A.Position sr sc) (A.Position er ec)) =
  E.object
    [ "start"
        ==> E.object
          [ "line" ==> E.int (fromIntegral sr),
            "column" ==> E.int (fromIntegral sc)
          ],
      "end"
        ==> E.object
          [ "line" ==> E.int (fromIntegral er),
            "column" ==> E.int (fromIntegral ec)
          ]
    ]

encodeSeverity :: Severity -> E.Value
encodeSeverity = \case
  SError -> E.chars "error"
  SWarning -> E.chars "warning"
  SInfo -> E.chars "info"

encodePhase :: Phase -> E.Value
encodePhase = \case
  PhaseParse -> E.chars "parse"
  PhaseImport -> E.chars "import"
  PhaseCanon -> E.chars "canonicalize"
  PhaseType -> E.chars "type"
  PhasePattern -> E.chars "pattern"
  PhaseMain -> E.chars "main"
  PhaseDocs -> E.chars "docs"
  PhaseOptimize -> E.chars "optimize"
  PhaseGenerate -> E.chars "generate"
  PhaseBuild -> E.chars "build"

encodeSpanStyle :: SpanStyle -> E.Value
encodeSpanStyle = \case
  SpanPrimary -> E.chars "primary"
  SpanSecondary -> E.chars "secondary"
  SpanNote -> E.chars "note"

encodeConfidence :: Confidence -> E.Value
encodeConfidence = \case
  Definite -> E.chars "definite"
  Likely -> E.chars "likely"
  Possible -> E.chars "possible"
