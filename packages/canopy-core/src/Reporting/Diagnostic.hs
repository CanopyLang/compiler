{-# LANGUAGE OverloadedStrings #-}

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
import qualified Json.Encode as Encode
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc

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
  { _spanRegion :: !Ann.Region,
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
  { _sugSpan :: !Ann.Region,
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
    _diagMessage :: !Doc.Doc,
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
  Doc.Doc ->
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
  Ann.Region ->
  Doc.Doc ->
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
diagnosticToDoc :: FilePath -> Diagnostic -> Doc.Doc
diagnosticToDoc relativePath diag =
  Doc.vcat
    [ toMessageBar (Text.unpack (_diagTitle diag)) (Text.unpack (errorCodeToText (_diagCode diag))) relativePath,
      "",
      _diagMessage diag,
      renderSuggestions (_diagSuggestions diag),
      renderNotes (_diagNotes diag),
      renderLearnMore (_diagCode diag),
      ""
    ]

-- | Render the colored message bar with error code.
toMessageBar :: String -> String -> FilePath -> Doc.Doc
toMessageBar title code filePath =
  let usedSpace = 4 + length title + 1 + length code + 2 + 1 + length filePath
      dashes = replicate (max 1 (80 - usedSpace)) '-'
   in Doc.dullcyan . Doc.fromChars $
        "-- " <> title <> " [" <> code <> "] " <> dashes <> " " <> filePath

-- | Render structured suggestions.
renderSuggestions :: [Suggestion] -> Doc.Doc
renderSuggestions [] = Doc.empty
renderSuggestions sugs =
  Doc.vcat ("" : fmap renderOneSuggestion sugs)

renderOneSuggestion :: Suggestion -> Doc.Doc
renderOneSuggestion sug =
  Doc.vcat
    [ Doc.fillSep
        ( Doc.green (Doc.underline "Try") <> ":" :
          fmap Doc.fromChars (words (Text.unpack (_sugMessage sug)))
        ),
      "",
      Doc.indent 4 (Doc.green (Doc.fromChars (Text.unpack (_sugReplacement sug))))
    ]

-- | Render notes.
renderNotes :: [Text] -> Doc.Doc
renderNotes [] = Doc.empty
renderNotes notes =
  Doc.vcat ("" : fmap renderOneNote notes)

renderOneNote :: Text -> Doc.Doc
renderOneNote note =
  Doc.fillSep (Doc.underline "Note" <> ":" : fmap Doc.fromChars (words (Text.unpack note)))

-- | Render the "Learn more" link.
renderLearnMore :: ErrorCode -> Doc.Doc
renderLearnMore code =
  Doc.vcat
    [ "",
      Doc.fromChars ("Learn more: canopy explain " <> Text.unpack (errorCodeToText code))
    ]

-- JSON ENCODING

-- | Encode a diagnostic as a fully structured JSON value.
--
-- The output contains all semantic information needed for IDE integration:
-- error code, severity, spans with labels, suggestions with confidence,
-- and phase information.
diagnosticToJson :: Diagnostic -> Encode.Value
diagnosticToJson diag =
  Encode.object
    [ "code" ==> Encode.chars (Text.unpack (errorCodeToText (_diagCode diag))),
      "severity" ==> encodeSeverity (_diagSeverity diag),
      "title" ==> Encode.chars (Text.unpack (_diagTitle diag)),
      "summary" ==> Encode.chars (Text.unpack (_diagSummary diag)),
      "primary" ==> labeledSpanToJson (_diagPrimary diag),
      "secondary" ==> Encode.list labeledSpanToJson (_diagSecondary diag),
      "suggestions" ==> Encode.list suggestionToJson (_diagSuggestions diag),
      "notes" ==> Encode.list (Encode.chars . Text.unpack) (_diagNotes diag),
      "phase" ==> encodePhase (_diagPhase diag),
      "message" ==> Doc.encode (_diagMessage diag)
    ]

-- | Encode a labeled span as JSON.
labeledSpanToJson :: LabeledSpan -> Encode.Value
labeledSpanToJson (LabeledSpan region label style) =
  Encode.object
    [ "region" ==> encodeRegion region,
      "label" ==> Encode.chars (Text.unpack label),
      "style" ==> encodeSpanStyle style
    ]

-- | Encode a suggestion as JSON.
suggestionToJson :: Suggestion -> Encode.Value
suggestionToJson (Suggestion region replacement message confidence) =
  Encode.object
    [ "region" ==> encodeRegion region,
      "replacement" ==> Encode.chars (Text.unpack replacement),
      "message" ==> Encode.chars (Text.unpack message),
      "confidence" ==> encodeConfidence confidence
    ]

-- | Encode a region as JSON.
encodeRegion :: Ann.Region -> Encode.Value
encodeRegion (Ann.Region (Ann.Position sr sc) (Ann.Position er ec)) =
  Encode.object
    [ "start"
        ==> Encode.object
          [ "line" ==> Encode.int (fromIntegral sr),
            "column" ==> Encode.int (fromIntegral sc)
          ],
      "end"
        ==> Encode.object
          [ "line" ==> Encode.int (fromIntegral er),
            "column" ==> Encode.int (fromIntegral ec)
          ]
    ]

encodeSeverity :: Severity -> Encode.Value
encodeSeverity = \case
  SError -> Encode.chars "error"
  SWarning -> Encode.chars "warning"
  SInfo -> Encode.chars "info"

encodePhase :: Phase -> Encode.Value
encodePhase = \case
  PhaseParse -> Encode.chars "parse"
  PhaseImport -> Encode.chars "import"
  PhaseCanon -> Encode.chars "canonicalize"
  PhaseType -> Encode.chars "type"
  PhasePattern -> Encode.chars "pattern"
  PhaseMain -> Encode.chars "main"
  PhaseDocs -> Encode.chars "docs"
  PhaseOptimize -> Encode.chars "optimize"
  PhaseGenerate -> Encode.chars "generate"
  PhaseBuild -> Encode.chars "build"

encodeSpanStyle :: SpanStyle -> Encode.Value
encodeSpanStyle = \case
  SpanPrimary -> Encode.chars "primary"
  SpanSecondary -> Encode.chars "secondary"
  SpanNote -> Encode.chars "note"

encodeConfidence :: Confidence -> Encode.Value
encodeConfidence = \case
  Definite -> Encode.chars "definite"
  Likely -> Encode.chars "likely"
  Possible -> Encode.chars "possible"
