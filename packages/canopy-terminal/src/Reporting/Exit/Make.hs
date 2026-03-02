{-# LANGUAGE OverloadedStrings #-}

-- | Build/make command error types and reporting.
--
-- @since 0.19.1
module Reporting.Exit.Make
  ( Make (..),
    makeToReport,
  )
where

import qualified Data.Text as Text
import qualified Exit as BuildExit
import qualified FFI.CapabilityEnforcement as CapEnforce
import Reporting.Diagnostic (Diagnostic)
import Reporting.Doc ((<+>))
import qualified Reporting.Doc as Doc
import Reporting.Exit.Help
  ( Report,
    appNeedsFileNamesError,
    badDetailsError,
    diagnosticReport,
    fixLine,
    noOutlineError,
    pkgNeedsExposingError,
    structuredError,
  )

-- | Build/Make errors.
data Make
  = MakeNoOutline
  | MakeBadDetails FilePath
  | MakeBuildError [Diagnostic]
  | MakeBadGenerate [Diagnostic]
  | MakeAppNeedsFileNames
  | MakePkgNeedsExposing
  | MakeNoMain
  | MakeMultipleFilesIntoHtml
  | MakeCannotBuild BuildExit.BuildError
  | MakeCannotOptimizeAndDebug
  | -- | Two builds produced different output at the given byte offset
    MakeReproducibilityFailure !Int
  | -- | FFI functions require capabilities not declared in canopy.json
    MakeCapabilityError ![CapEnforce.CapabilityError]
  deriving (Show)

-- | Convert a 'Make' error to a structured 'Report'.
makeToReport :: Make -> Report
makeToReport MakeNoOutline = noOutlineError "canopy make"
makeToReport (MakeBadDetails path) = badDetailsError path
makeToReport (MakeBuildError diags) = diagnosticReport "BUILD ERROR" diags
makeToReport (MakeBadGenerate diags) = diagnosticReport "CODE GENERATION ERROR" diags
makeToReport MakeAppNeedsFileNames = appNeedsFileNamesError "canopy make src/Main.can"
makeToReport MakePkgNeedsExposing = pkgNeedsExposingError
makeToReport MakeNoMain = noMainError
makeToReport MakeMultipleFilesIntoHtml = multipleFilesHtmlError
makeToReport (MakeCannotBuild buildErr) = BuildExit.toDoc buildErr
makeToReport MakeCannotOptimizeAndDebug = optimizeAndDebugError
makeToReport (MakeReproducibilityFailure offset) = reproducibilityFailureError offset
makeToReport (MakeCapabilityError capErrors) = capabilityError capErrors

noMainError :: Report
noMainError =
  structuredError
    "NO MAIN FUNCTION"
    (Doc.reflow "I cannot find a main value in your module. Every application needs a main value to serve as the entry point.")
    ( Doc.vcat
        [ Doc.reflow "Add a main value to your module, for example:",
          "",
          fixLine (Doc.green "main = Html.text \"Hello!\"")
        ]
    )

multipleFilesHtmlError :: Report
multipleFilesHtmlError =
  structuredError
    "TOO MANY FILES FOR HTML"
    (Doc.reflow "When generating HTML output, you can only compile one file at a time.")
    ( Doc.vcat
        [ Doc.reflow "Either pass a single source file:",
          "",
          fixLine (Doc.green "canopy make src/Main.can"),
          "",
          Doc.reflow "Or use JavaScript output for multiple files:",
          "",
          fixLine (Doc.green "canopy make src/Main.can src/Other.can --output=app.js")
        ]
    )

optimizeAndDebugError :: Report
optimizeAndDebugError =
  structuredError
    "CONFLICTING FLAGS"
    (Doc.reflow "You cannot use both --optimize and --debug at the same time. These flags are mutually exclusive.")
    ( Doc.vcat
        [ Doc.reflow "Use one or the other:",
          "",
          fixLine (Doc.green "canopy make --optimize    " <+> Doc.fromChars "for production builds"),
          fixLine (Doc.green "canopy make --debug       " <+> Doc.fromChars "for development builds")
        ]
    )

reproducibilityFailureError :: Int -> Report
reproducibilityFailureError offset =
  structuredError
    "REPRODUCIBILITY FAILURE"
    (Doc.reflow ("Two builds of the same source produced different output. First divergence at byte " ++ show offset ++ "."))
    ( Doc.vcat
        [ Doc.reflow "This indicates non-determinism in code generation.",
          "",
          Doc.reflow "Please report this as a bug at the project repository with:",
          fixLine (Doc.green "1. The project source code"),
          fixLine (Doc.green "2. The exact canopy version (canopy --version)"),
          fixLine (Doc.green "3. Your operating system and architecture")
        ]
    )

-- | Report missing capability declarations.
--
-- Produces a structured error listing each FFI function that requires
-- capabilities not declared in canopy.json, with a concrete fix showing
-- which capabilities to add.
capabilityError :: [CapEnforce.CapabilityError] -> Report
capabilityError capErrors =
  structuredError
    "MISSING CAPABILITIES"
    (Doc.reflow "Some FFI functions require capabilities that are not declared in canopy.json:")
    ( Doc.vcat
        (map formatCapError capErrors ++ [suggestion])
    )

-- | Format a single capability error for display.
formatCapError :: CapEnforce.CapabilityError -> Doc.Doc
formatCapError ce =
  Doc.indent 4 (Doc.fromChars line)
  where
    func = Text.unpack (CapEnforce._ceFunctionName ce)
    file = Text.unpack (CapEnforce._ceFilePath ce)
    cap = Text.unpack (CapEnforce._ceMissingCapability ce)
    line = func <> " (" <> file <> ") requires capability " <> show cap

-- | Suggestion text for adding missing capabilities to canopy.json.
suggestion :: Doc.Doc
suggestion =
  Doc.vcat
    [ "",
      Doc.reflow "Add the missing capabilities to canopy.json:",
      "",
      fixLine (Doc.green "\"capabilities\": [\"geolocation\", \"notifications\"]")
    ]
