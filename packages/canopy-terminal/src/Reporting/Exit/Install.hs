{-# LANGUAGE OverloadedStrings #-}

-- | Install command error types and reporting.
--
-- @since 0.19.1
module Reporting.Exit.Install
  ( Install (..),
    installToReport,
  )
where

import qualified Reporting.Doc as Doc
import Reporting.Exit.Help
  ( Report,
    badDetailsError,
    badOutlineError,
    fixLine,
    noOutlineError,
    structuredError,
    unknownPackageError,
  )

-- | Install errors.
data Install
  = InstallNoOutline
  | InstallBadOutline !String
  | InstallBadRegistry !String
  | InstallBadDetails !FilePath
  | InstallBadFetch
  | InstallUnknownPackageOnline !String ![String]
  | InstallUnknownPackageOffline !String ![String]
  | InstallNoOnlinePkgSolution !String
  | InstallNoOfflinePkgSolution !String
  | InstallNoOnlineAppSolution !String
  | InstallNoOfflineAppSolution !String
  | InstallHadSolverTrouble !String
  | InstallNoArgs !FilePath
  | InstallBadSignature ![String]
  deriving (Show)

-- | Convert an 'Install' error to a structured 'Report'.
installToReport :: Install -> Report
installToReport InstallNoOutline = noOutlineError "canopy install"
installToReport (InstallBadOutline msg) = badOutlineError msg
installToReport (InstallBadRegistry msg) = badRegistryError msg
installToReport (InstallBadDetails path) = badDetailsError path
installToReport InstallBadFetch = badFetchError
installToReport (InstallUnknownPackageOnline pkg suggestions) = unknownPackageError pkg suggestions
installToReport (InstallUnknownPackageOffline pkg suggestions) = unknownPackageOfflineError pkg suggestions
installToReport (InstallNoOnlinePkgSolution pkg) = noSolutionError pkg
installToReport (InstallNoOfflinePkgSolution pkg) = noOfflineSolutionError pkg
installToReport (InstallNoOnlineAppSolution pkg) = noSolutionError pkg
installToReport (InstallNoOfflineAppSolution pkg) = noOfflineSolutionError pkg
installToReport (InstallHadSolverTrouble msg) = solverTroubleError msg
installToReport (InstallNoArgs home) = installNoArgsError home
installToReport (InstallBadSignature pkgs) = badSignatureError pkgs

badRegistryError :: String -> Report
badRegistryError msg =
  structuredError
    "REGISTRY ERROR"
    (Doc.reflow ("The package registry data is invalid: " ++ msg))
    ( Doc.vcat
        [ Doc.reflow "Try refreshing the registry cache:",
          "",
          fixLine (Doc.green "canopy setup")
        ]
    )

badFetchError :: Report
badFetchError =
  structuredError
    "PACKAGE FETCH FAILED"
    (Doc.reflow "I could not download one or more packages from the registry or GitHub.")
    ( Doc.vcat
        [ Doc.reflow "Possible causes:",
          "",
          fixLine (Doc.fromChars "1. No internet connection"),
          fixLine (Doc.fromChars "2. The package registry is temporarily down"),
          fixLine (Doc.fromChars "3. GitHub rate limiting"),
          "",
          Doc.reflow "Try again later, or check your network connection."
        ]
    )

unknownPackageOfflineError :: String -> [String] -> Report
unknownPackageOfflineError pkg suggestions =
  structuredError
    "UNKNOWN PACKAGE"
    ( Doc.vcat
        [ Doc.reflow ("I cannot find a package named " ++ pkg ++ " in the local registry cache."),
          Doc.reflow "Note: You appear to be offline."
        ]
    )
    (suggestionsBlock suggestions)

suggestionsBlock :: [String] -> Doc.Doc
suggestionsBlock [] =
  Doc.reflow "Check the package name for typos."
suggestionsBlock suggestions =
  Doc.vcat
    [ Doc.reflow "Did you mean one of these?",
      "",
      Doc.vcat (fmap (\s -> fixLine (Doc.green (Doc.fromChars s))) suggestions)
    ]

noSolutionError :: String -> Report
noSolutionError pkg =
  structuredError
    "DEPENDENCY CONFLICT"
    (Doc.reflow ("I cannot find a set of package versions that satisfies all constraints for " ++ pkg ++ "."))
    ( Doc.vcat
        [ Doc.reflow "Try these steps:",
          "",
          fixLine (Doc.fromChars "1. Run " <> Doc.green "canopy diff" <> Doc.fromChars " to check version compatibility"),
          fixLine (Doc.fromChars "2. Remove canopy-stuff/ and try again"),
          fixLine (Doc.fromChars "3. Check for conflicting version constraints in canopy.json")
        ]
    )

noOfflineSolutionError :: String -> Report
noOfflineSolutionError pkg =
  structuredError
    "DEPENDENCY CONFLICT (OFFLINE)"
    (Doc.reflow ("I cannot find a set of cached package versions that satisfies all constraints for " ++ pkg ++ "."))
    ( Doc.vcat
        [ Doc.reflow "Since you appear to be offline, try connecting to the internet and running:",
          "",
          fixLine (Doc.green "canopy install")
        ]
    )

solverTroubleError :: String -> Report
solverTroubleError msg =
  structuredError
    "SOLVER FAILURE"
    (Doc.reflow ("The dependency solver encountered a problem: " ++ msg))
    ( Doc.vcat
        [ Doc.reflow "Try removing cached data and reinstalling:",
          "",
          fixLine (Doc.green "rm -rf canopy-stuff/"),
          fixLine (Doc.green "canopy install")
        ]
    )

installNoArgsError :: FilePath -> Report
installNoArgsError home =
  structuredError
    "NO PACKAGE SPECIFIED"
    (Doc.reflow "You did not specify which package to install.")
    ( Doc.vcat
        [ Doc.reflow "To install a package, specify it by name:",
          "",
          fixLine (Doc.green "canopy install author/package"),
          "",
          Doc.reflow ("Canopy home: " ++ home)
        ]
    )

badSignatureError :: [String] -> Report
badSignatureError pkgs =
  structuredError
    "INVALID PACKAGE SIGNATURES"
    ( Doc.vcat
        [ Doc.reflow "The following packages have signatures that could not be verified against any trusted key:",
          "",
          Doc.vcat (fmap (\p -> fixLine (Doc.dullred (Doc.fromChars p))) pkgs)
        ]
    )
    ( Doc.vcat
        [ Doc.reflow "This may indicate that the packages have been tampered with.",
          "",
          Doc.reflow "If you trust these packages, you can skip verification with:",
          "",
          fixLine (Doc.green "canopy install --no-verify")
        ]
    )
