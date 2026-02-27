{-# LANGUAGE OverloadedStrings #-}

-- | Reporting.Exit.Install - Error types and reports for the install command
--
-- This module provides the 'Install' error type and its rendering function.
-- It is a sub-module of "Reporting.Exit" and is re-exported from there.
-- Users should import "Reporting.Exit" rather than this module directly.
--
-- @since 0.19.1
module Reporting.Exit.Install
  ( Install (..),
    installToReport,
  )
where

import Reporting.Doc ((<+>))
import qualified Reporting.Doc as Doc

-- | Report type rendered as a styled Doc.
type Report = Doc.Doc

-- | Install errors.
data Install
  = InstallNoOutline
  | InstallBadOutline String
  | InstallBadRegistry String
  | InstallBadDetails FilePath
  | InstallUnknownPackageOnline String [String]
  | InstallUnknownPackageOffline String [String]
  | InstallNoOnlinePkgSolution String
  | InstallNoOfflinePkgSolution String
  | InstallNoOnlineAppSolution String
  | InstallNoOfflineAppSolution String
  | InstallHadSolverTrouble String
  | InstallNoArgs FilePath
  deriving (Show)

-- | Convert an 'Install' error to a structured 'Report'.
installToReport :: Install -> Report
installToReport InstallNoOutline = noOutlineError "canopy install"
installToReport (InstallBadOutline msg) = badOutlineError msg
installToReport (InstallBadRegistry msg) = badRegistryError msg
installToReport (InstallBadDetails path) = badDetailsError path
installToReport (InstallUnknownPackageOnline pkg suggestions) = unknownPackageError pkg suggestions
installToReport (InstallUnknownPackageOffline pkg suggestions) = unknownPackageOfflineError pkg suggestions
installToReport (InstallNoOnlinePkgSolution pkg) = noSolutionError pkg
installToReport (InstallNoOfflinePkgSolution pkg) = noOfflineSolutionError pkg
installToReport (InstallNoOnlineAppSolution pkg) = noSolutionError pkg
installToReport (InstallNoOfflineAppSolution pkg) = noOfflineSolutionError pkg
installToReport (InstallHadSolverTrouble msg) = solverTroubleError msg
installToReport (InstallNoArgs home) = installNoArgsError home

-- SHARED HELPERS (duplicated from parent for independence)

structuredError :: String -> Doc.Doc -> Doc.Doc -> Doc.Doc
structuredError title explanation fix =
  Doc.vcat
    [ errorBar title
    , ""
    , explanation
    , ""
    , fix
    , ""
    ]

errorBar :: String -> Doc.Doc
errorBar title =
  Doc.dullred ("--" <+> Doc.fromChars title <+> Doc.fromChars dashes)
  where
    dashes = replicate (max 1 (80 - 4 - length title)) '-'

fixLine :: Doc.Doc -> Doc.Doc
fixLine = Doc.indent 4

noOutlineError :: String -> Report
noOutlineError cmd =
  structuredError "NO PROJECT FOUND"
    (Doc.reflow "I could not find a canopy.json file in this directory or any parent directory.")
    (Doc.vcat
      [ Doc.reflow "To create a new project, run:"
      , ""
      , fixLine (Doc.green "canopy init")
      , ""
      , Doc.reflow ("Then try " ++ cmd ++ " again.")
      ])

badDetailsError :: FilePath -> Report
badDetailsError path =
  structuredError "CORRUPT PROJECT"
    (Doc.reflow ("I cannot load project details from " ++ path ++ ". The canopy-stuff/ directory may be corrupted."))
    (Doc.vcat
      [ Doc.reflow "Try deleting canopy-stuff/ and rebuilding:"
      , ""
      , fixLine (Doc.green "rm -rf canopy-stuff/")
      , fixLine (Doc.green "canopy make")
      ])

badOutlineError :: String -> Report
badOutlineError msg =
  structuredError "INVALID canopy.json"
    (Doc.reflow ("There is a problem with your canopy.json file: " ++ msg))
    (Doc.reflow "Check the JSON syntax and ensure all required fields are present.")

badRegistryError :: String -> Report
badRegistryError msg =
  structuredError "REGISTRY ERROR"
    (Doc.reflow ("The package registry data is invalid: " ++ msg))
    (Doc.vcat
      [ Doc.reflow "Try refreshing the registry cache:"
      , ""
      , fixLine (Doc.green "canopy setup")
      ])

unknownPackageError :: String -> [String] -> Report
unknownPackageError pkg suggestions =
  structuredError "UNKNOWN PACKAGE"
    (Doc.reflow ("I cannot find a package named " ++ pkg ++ " in the package registry."))
    (suggestionsBlock suggestions)

unknownPackageOfflineError :: String -> [String] -> Report
unknownPackageOfflineError pkg suggestions =
  structuredError "UNKNOWN PACKAGE"
    (Doc.vcat
      [ Doc.reflow ("I cannot find a package named " ++ pkg ++ " in the local registry cache.")
      , Doc.reflow "Note: You appear to be offline."
      ])
    (suggestionsBlock suggestions)

suggestionsBlock :: [String] -> Doc.Doc
suggestionsBlock [] =
  Doc.reflow "Check the package name for typos."
suggestionsBlock suggestions =
  Doc.vcat
    [ Doc.reflow "Did you mean one of these?"
    , ""
    , Doc.vcat (fmap (\s -> fixLine (Doc.green (Doc.fromChars s))) suggestions)
    ]

noSolutionError :: String -> Report
noSolutionError pkg =
  structuredError "DEPENDENCY CONFLICT"
    (Doc.reflow ("I cannot find a set of package versions that satisfies all constraints for " ++ pkg ++ "."))
    (Doc.vcat
      [ Doc.reflow "Try these steps:"
      , ""
      , fixLine (Doc.fromChars "1. Run " <> Doc.green "canopy diff" <> Doc.fromChars " to check version compatibility")
      , fixLine (Doc.fromChars "2. Remove canopy-stuff/ and try again")
      , fixLine (Doc.fromChars "3. Check for conflicting version constraints in canopy.json")
      ])

noOfflineSolutionError :: String -> Report
noOfflineSolutionError pkg =
  structuredError "DEPENDENCY CONFLICT (OFFLINE)"
    (Doc.reflow ("I cannot find a set of cached package versions that satisfies all constraints for " ++ pkg ++ "."))
    (Doc.vcat
      [ Doc.reflow "Since you appear to be offline, try connecting to the internet and running:"
      , ""
      , fixLine (Doc.green "canopy install")
      ])

solverTroubleError :: String -> Report
solverTroubleError msg =
  structuredError "SOLVER FAILURE"
    (Doc.reflow ("The dependency solver encountered a problem: " ++ msg))
    (Doc.vcat
      [ Doc.reflow "Try removing cached data and reinstalling:"
      , ""
      , fixLine (Doc.green "rm -rf canopy-stuff/")
      , fixLine (Doc.green "canopy install")
      ])

installNoArgsError :: FilePath -> Report
installNoArgsError home =
  structuredError "NO PACKAGE SPECIFIED"
    (Doc.reflow "You did not specify which package to install.")
    (Doc.vcat
      [ Doc.reflow "To install a package, specify it by name:"
      , ""
      , fixLine (Doc.green "canopy install author/package")
      , ""
      , Doc.reflow ("Canopy home: " ++ home)
      ])
