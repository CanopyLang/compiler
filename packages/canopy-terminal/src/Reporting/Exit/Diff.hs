{-# LANGUAGE OverloadedStrings #-}

-- | Diff command error types and reporting.
--
-- @since 0.19.1
module Reporting.Exit.Diff
  ( Diff (..),
    diffToReport,
  )
where

import qualified Exit as BuildExit
import qualified Reporting.Doc as Doc
import Reporting.Exit.Help
  ( Report,
    badDetailsError,
    badOutlineError,
    fixLine,
    mustHaveLatestRegistryError,
    noOutlineError,
    onlyPackagesError,
    pkgNeedsExposingError,
    repoConfigError,
    structuredError,
    unknownPackageError,
  )

-- | Diff errors.
data Diff
  = DiffNoOutline
  | DiffBadOutline String
  | DiffApplication
  | DiffCustomReposDataProblem
  | DiffMustHaveLatestRegistry
  | DiffUnknownPackage String [String]
  | DiffUnknownVersion String
  | DiffDocsProblem String
  | DiffBadDetails FilePath
  | DiffBadBuild BuildExit.BuildError
  | DiffNoExposed
  deriving (Show)

-- | Convert a 'Diff' error to a structured 'Report'.
diffToReport :: Diff -> Report
diffToReport DiffNoOutline = noOutlineError "canopy diff"
diffToReport (DiffBadOutline msg) = badOutlineError msg
diffToReport DiffApplication = onlyPackagesError "diff"
diffToReport DiffCustomReposDataProblem = repoConfigError "diff"
diffToReport DiffMustHaveLatestRegistry = mustHaveLatestRegistryError "diff"
diffToReport (DiffUnknownPackage pkg suggestions) = unknownPackageError pkg suggestions
diffToReport (DiffUnknownVersion msg) = diffUnknownVersionError msg
diffToReport (DiffDocsProblem msg) = diffDocsProblemError msg
diffToReport (DiffBadDetails path) = badDetailsError path
diffToReport (DiffBadBuild buildErr) = BuildExit.toDoc buildErr
diffToReport DiffNoExposed = pkgNeedsExposingError

diffUnknownVersionError :: String -> Report
diffUnknownVersionError vsn =
  structuredError
    "UNKNOWN VERSION"
    (Doc.reflow ("I cannot find version " ++ vsn ++ " of this package in the registry."))
    ( Doc.vcat
        [ Doc.reflow "Check the available versions with:",
          "",
          fixLine (Doc.green "canopy diff")
        ]
    )

diffDocsProblemError :: String -> Report
diffDocsProblemError msg =
  structuredError
    "DOCUMENTATION ERROR"
    (Doc.reflow ("I could not generate documentation for the diff: " ++ msg))
    ( Doc.vcat
        [ Doc.reflow "Make sure your project builds cleanly:",
          "",
          fixLine (Doc.green "canopy make")
        ]
    )
