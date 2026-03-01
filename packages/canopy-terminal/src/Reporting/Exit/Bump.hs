{-# LANGUAGE OverloadedStrings #-}

-- | Bump command error types and reporting.
--
-- @since 0.19.1
module Reporting.Exit.Bump
  ( Bump (..),
    bumpToReport,
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
  )

-- | Bump errors.
data Bump
  = BumpNoOutline
  | BumpBadOutline String
  | BumpApplication
  | BumpUnexpectedVersion String [String]
  | BumpCustomRepositoryDataProblem
  | BumpMustHaveLatestRegistry
  | BumpCannotFindDocs String
  | BumpBadDetails FilePath
  | BumpBuildProblem BuildExit.BuildError
  | BumpBadBuild BuildExit.BuildError
  | BumpNoExposed
  deriving (Show)

-- | Convert a 'Bump' error to a structured 'Report'.
bumpToReport :: Bump -> Report
bumpToReport BumpNoOutline = noOutlineError "canopy bump"
bumpToReport (BumpBadOutline msg) = badOutlineError msg
bumpToReport BumpApplication = onlyPackagesError "bump"
bumpToReport (BumpUnexpectedVersion current suggestions) = bumpUnexpectedVersionError current suggestions
bumpToReport BumpCustomRepositoryDataProblem = repoConfigError "bump"
bumpToReport BumpMustHaveLatestRegistry = mustHaveLatestRegistryError "bump"
bumpToReport (BumpCannotFindDocs msg) = bumpCannotFindDocsError msg
bumpToReport (BumpBadDetails path) = badDetailsError path
bumpToReport (BumpBuildProblem buildErr) = BuildExit.toDoc buildErr
bumpToReport (BumpBadBuild buildErr) = BuildExit.toDoc buildErr
bumpToReport BumpNoExposed = pkgNeedsExposingError

bumpUnexpectedVersionError :: String -> [String] -> Report
bumpUnexpectedVersionError current suggestions =
  structuredError
    "UNEXPECTED VERSION"
    (Doc.reflow ("The current version " ++ current ++ " is not valid for bumping."))
    (bumpSuggestionsBlock suggestions)

bumpSuggestionsBlock :: [String] -> Doc.Doc
bumpSuggestionsBlock [] =
  Doc.reflow "Check the version field in canopy.json."
bumpSuggestionsBlock versions =
  Doc.vcat
    [ Doc.reflow "Expected one of these versions:",
      "",
      Doc.vcat (fmap (\v -> fixLine (Doc.green (Doc.fromChars v))) versions)
    ]

bumpCannotFindDocsError :: String -> Report
bumpCannotFindDocsError msg =
  structuredError
    "DOCUMENTATION ERROR"
    (Doc.reflow ("I could not generate documentation needed for the version bump: " ++ msg))
    ( Doc.vcat
        [ Doc.reflow "Make sure your project builds cleanly:",
          "",
          fixLine (Doc.green "canopy make")
        ]
    )
