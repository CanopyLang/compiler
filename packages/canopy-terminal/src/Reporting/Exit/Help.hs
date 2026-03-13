{-# LANGUAGE OverloadedStrings #-}

-- | Shared error formatting helpers for CLI exit reports.
--
-- Provides the common error structure (colored title bar, explanation,
-- fix suggestion) used by all command-specific exit error modules.
--
-- @since 0.19.1
module Reporting.Exit.Help
  ( -- * Report Type
    Report,
    toStderr,
    toStdout,

    -- * Formatting Helpers
    structuredError,
    structuredErrorNoFix,
    errorBar,
    fixLine,
    diagnosticReport,

    -- * Common Error Builders
    noOutlineError,
    badDetailsError,
    badOutlineError,
    appNeedsFileNamesError,
    pkgNeedsExposingError,
    onlyPackagesError,
    repoConfigError,
    mustHaveLatestRegistryError,
    unknownPackageError,
  )
where

import Data.List (isPrefixOf)
import Reporting.Diagnostic (Diagnostic)
import qualified Reporting.Diagnostic as Diag
import Reporting.Doc ((<+>))
import qualified Reporting.Doc as Doc
import qualified System.IO as IO

-- | Error report type rendered as a styled Doc.
type Report = Doc.Doc

-- | Print a Report to stderr with ANSI color support.
toStderr :: Report -> IO ()
toStderr = Doc.toAnsi IO.stderr

-- | Print a Doc to stdout with ANSI color support.
toStdout :: Doc.Doc -> IO ()
toStdout = Doc.toAnsi IO.stdout

-- | Build a three-part structured error: title bar, explanation, fix.
structuredError :: String -> Doc.Doc -> Doc.Doc -> Doc.Doc
structuredError title explanation fix =
  Doc.vcat
    [ errorBar title,
      "",
      explanation,
      "",
      fix,
      ""
    ]

-- | Build a two-part structured error without a fix suggestion.
structuredErrorNoFix :: String -> Doc.Doc -> Doc.Doc
structuredErrorNoFix title explanation =
  Doc.vcat
    [ errorBar title,
      "",
      explanation,
      ""
    ]

-- | Render a colored title bar for error output.
errorBar :: String -> Doc.Doc
errorBar title =
  Doc.dullred ("--" <+> Doc.fromChars title <+> Doc.fromChars dashes)
  where
    dashes = replicate (max 1 (80 - 4 - length title)) '-'

-- | Indent a line for fix suggestions.
fixLine :: Doc.Doc -> Doc.Doc
fixLine = Doc.indent 4

-- | Render a list of diagnostics under a titled error bar.
diagnosticReport :: String -> [Diagnostic] -> Report
diagnosticReport title [] =
  structuredErrorNoFix title (Doc.reflow "An error occurred.")
diagnosticReport title diags =
  Doc.vcat
    [ errorBar title,
      "",
      Doc.vcat (fmap (Diag.diagnosticToDoc "<unknown>") diags),
      ""
    ]

-- | Error when no canopy.json is found.
noOutlineError :: String -> Report
noOutlineError cmd =
  structuredError
    "NO PROJECT FOUND"
    (Doc.reflow "I could not find a canopy.json file in this directory or any parent directory.")
    ( Doc.vcat
        [ Doc.reflow "To create a new project, run:",
          "",
          fixLine (Doc.green "canopy init"),
          "",
          Doc.reflow ("Then try " ++ cmd ++ " again.")
        ]
    )

-- | Error when project details cannot be loaded.
--
-- Distinguishes between parse errors (which carry a descriptive message
-- from 'Outline.read') and generic project failures (bare directory path).
badDetailsError :: String -> Report
badDetailsError msg
  | isParseError msg =
      structuredError
        "INVALID canopy.json"
        (Doc.reflow msg)
        (Doc.reflow "Check the JSON syntax and ensure all required fields are present.")
  | otherwise =
      structuredError
        "CORRUPT PROJECT"
        (Doc.reflow ("I cannot load project details from " ++ msg ++ ". The canopy-stuff/ directory may be corrupted."))
        ( Doc.vcat
            [ Doc.reflow "Try deleting canopy-stuff/ and rebuilding:",
              "",
              fixLine (Doc.green "rm -rf canopy-stuff/"),
              fixLine (Doc.green "canopy make")
            ]
        )
  where
    isParseError s = "Failed to parse" `isPrefixOf` s || "No canopy.json" `isPrefixOf` s

-- | Error when canopy.json has invalid content.
badOutlineError :: String -> Report
badOutlineError msg =
  structuredError
    "INVALID canopy.json"
    (Doc.reflow ("There is a problem with your canopy.json file: " ++ msg))
    (Doc.reflow "Check the JSON syntax and ensure all required fields are present.")

-- | Error when an application project needs explicit file names.
appNeedsFileNamesError :: String -> Report
appNeedsFileNamesError example =
  structuredError
    "MISSING FILE ARGUMENT"
    (Doc.reflow "Application projects need explicit file names to compile.")
    ( Doc.vcat
        [ Doc.reflow "Try specifying a source file:",
          "",
          fixLine (Doc.green (Doc.fromChars example))
        ]
    )

-- | Error when a package project has no exposed modules.
pkgNeedsExposingError :: Report
pkgNeedsExposingError =
  structuredError
    "NO EXPOSED MODULES"
    (Doc.reflow "Your package does not expose any modules. Without exposed modules, there is nothing for users to import.")
    ( Doc.vcat
        [ Doc.reflow "Add modules to the \"exposed-modules\" field in canopy.json:",
          "",
          fixLine (Doc.green "\"exposed-modules\": [ \"MyModule\" ]")
        ]
    )

-- | Error when a package-only command is run on an application.
onlyPackagesError :: String -> Report
onlyPackagesError cmd =
  structuredError
    "NOT A PACKAGE"
    (Doc.reflow ("The " ++ cmd ++ " command only works with packages, but this project is an application."))
    (Doc.reflow "Check your canopy.json -- applications have a \"source-directories\" field, while packages have an \"exposed-modules\" field.")

-- | Error when custom repository configuration is invalid.
repoConfigError :: String -> Report
repoConfigError cmd =
  structuredError
    "REPOSITORY CONFIG ERROR"
    (Doc.reflow ("There is a problem with the custom repository configuration needed for " ++ cmd ++ "."))
    (Doc.reflow "Check the repositories section of your canopy.json file.")

-- | Error when the registry must be up to date but is not.
mustHaveLatestRegistryError :: String -> Report
mustHaveLatestRegistryError cmd =
  structuredError
    "OUTDATED REGISTRY"
    (Doc.reflow ("The " ++ cmd ++ " command requires the latest package registry, but the registry could not be updated."))
    ( Doc.vcat
        [ Doc.reflow "Try refreshing the registry:",
          "",
          fixLine (Doc.green "canopy setup"),
          "",
          Doc.reflow "If the problem persists, check your internet connection."
        ]
    )

-- | Error when a package name is not found in the registry.
unknownPackageError :: String -> [String] -> Report
unknownPackageError pkg suggestions =
  structuredError
    "UNKNOWN PACKAGE"
    (Doc.reflow ("I cannot find a package named " ++ pkg ++ " in the package registry."))
    (suggestionsBlock suggestions)

-- | Render a suggestions block for "did you mean?" prompts.
suggestionsBlock :: [String] -> Doc.Doc
suggestionsBlock [] =
  Doc.reflow "Check the package name for typos."
suggestionsBlock suggestions =
  Doc.vcat
    [ Doc.reflow "Did you mean one of these?",
      "",
      Doc.vcat (fmap (\s -> fixLine (Doc.green (Doc.fromChars s))) suggestions)
    ]
