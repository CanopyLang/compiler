{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Structured error types and reporting for Terminal operations.
--
-- Every error displayed to the user flows through this module. Each error
-- follows a consistent three-part structure:
--
-- 1. A colored title bar (@Doc.dullred "-- ERROR TITLE"@)
-- 2. A reflowed explanation of what went wrong
-- 3. A concrete fix suggestion highlighted in green
--
-- This ensures all CLI error messages are visually consistent with the
-- compiler's own error output (inherited from Elm).
--
-- @since 0.19.1
module Reporting.Exit
  ( -- * Make Errors
    Make
      ( MakeNoOutline,
        MakeBadDetails,
        MakeBuildError,
        MakeBadGenerate,
        MakeAppNeedsFileNames,
        MakePkgNeedsExposing,
        MakeNoMain,
        MakeMultipleFilesIntoHtml,
        MakeCannotBuild,
        MakeCannotOptimizeAndDebug
      ),
    makeToReport,

    -- * Check Errors
    Check
      ( CheckNoOutline,
        CheckBadDetails,
        CheckCannotBuild,
        CheckAppNeedsFileNames,
        CheckPkgNeedsExposing
      ),
    checkToReport,

    -- * REPL Errors
    Repl
      ( ReplBadDetails,
        ReplBadGenerate,
        ReplCannotBuild
      ),
    replToReport,

    -- * Install Errors
    Install (..),
    installToReport,

    -- * Publish Errors
    Publish (..),
    publishToReport,
    newPackageOverview,

    -- * Diff Errors
    Diff (..),
    diffToReport,

    -- * Bump Errors
    Bump (..),
    bumpToReport,

    -- * Init Errors
    Init (..),
    initToReport,

    -- * Setup Errors
    Setup (..),
    setupToReport,

    -- * Other Error Types
    RegistryProblem (..),
    Solver (..),
    Reactor (..),
    reactorToReport,

    -- * Report Type
    Report,
    toStderr,
  )
where

import qualified Data.List as List
import qualified Exit as BuildExit
import Reporting.Doc ((<+>))
import qualified Reporting.Doc as Doc
import qualified System.IO as IO

-- ── Shared error formatting ──────────────────────────────────────────

-- | Build a structured error with title bar, explanation, and fix suggestion.
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

-- | Build a structured error without a fix suggestion.
structuredErrorNoFix :: String -> Doc.Doc -> Doc.Doc
structuredErrorNoFix title explanation =
  Doc.vcat
    [ errorBar title
    , ""
    , explanation
    , ""
    ]

-- | Render the colored error title bar.
errorBar :: String -> Doc.Doc
errorBar title =
  Doc.dullred ("--" <+> Doc.fromChars title <+> Doc.fromChars dashes)
  where
    dashes = replicate (max 1 (80 - 4 - length title)) '-'

-- | Render a fix suggestion line.
fixLine :: Doc.Doc -> Doc.Doc
fixLine = Doc.indent 4

-- ── Error Report Type ────────────────────────────────────────────────

-- | Error report type rendered as a styled Doc.
type Report = Doc.Doc

-- | Print a Report to stderr with ANSI color support.
toStderr :: Report -> IO ()
toStderr = Doc.toAnsi IO.stderr

-- ── Check errors ─────────────────────────────────────────────────────

-- | Type-check errors (check command).
data Check
  = CheckNoOutline
  | CheckBadDetails FilePath
  | CheckCannotBuild BuildExit.BuildError
  | CheckAppNeedsFileNames
  | CheckPkgNeedsExposing
  deriving (Show)

-- | Convert a 'Check' error to a structured 'Report'.
checkToReport :: Check -> Report
checkToReport CheckNoOutline = noOutlineError "canopy check"
checkToReport (CheckBadDetails path) = badDetailsError path
checkToReport (CheckCannotBuild buildErr) = BuildExit.toDoc buildErr
checkToReport CheckAppNeedsFileNames = appNeedsFileNamesError "canopy check src/Main.can"
checkToReport CheckPkgNeedsExposing = pkgNeedsExposingError

-- ── Make errors ──────────────────────────────────────────────────────

-- | Build/Make errors.
data Make
  = MakeNoOutline
  | MakeBadDetails FilePath
  | MakeBuildError String
  | MakeBadGenerate String
  | MakeAppNeedsFileNames
  | MakePkgNeedsExposing
  | MakeNoMain
  | MakeMultipleFilesIntoHtml
  | MakeCannotBuild BuildExit.BuildError
  | MakeCannotOptimizeAndDebug
  deriving (Show)

-- | Convert a 'Make' error to a structured 'Report'.
makeToReport :: Make -> Report
makeToReport MakeNoOutline = noOutlineError "canopy make"
makeToReport (MakeBadDetails path) = badDetailsError path
makeToReport (MakeBuildError msg) = buildError msg
makeToReport (MakeBadGenerate msg) = generateError msg
makeToReport MakeAppNeedsFileNames = appNeedsFileNamesError "canopy make src/Main.can"
makeToReport MakePkgNeedsExposing = pkgNeedsExposingError
makeToReport MakeNoMain = noMainError
makeToReport MakeMultipleFilesIntoHtml = multipleFilesHtmlError
makeToReport (MakeCannotBuild buildErr) = BuildExit.toDoc buildErr
makeToReport MakeCannotOptimizeAndDebug = optimizeAndDebugError

-- ── REPL errors ──────────────────────────────────────────────────────

-- | REPL errors.
data Repl
  = ReplBadDetails FilePath
  | ReplBadGenerate String
  | ReplCannotBuild BuildExit.BuildError
  deriving (Show)

-- | Convert a 'Repl' error to a structured 'Report'.
replToReport :: Repl -> Report
replToReport (ReplBadDetails path) = badDetailsError path
replToReport (ReplBadGenerate msg) = generateError msg
replToReport (ReplCannotBuild buildErr) = BuildExit.toDoc buildErr

-- ── Install errors ───────────────────────────────────────────────────

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

-- ── Publish errors ───────────────────────────────────────────────────

-- | Publish errors.
data Publish
  = PublishNoOutline
  | PublishBadOutline String
  | PublishMissingTag String
  | PublishCannotGetTag String
  | PublishCannotGetTagData String
  | PublishLocalChanges String
  | PublishCannotGetZip String
  | PublishCannotDecodeZip String
  | PublishCustomRepositoryConfigDataError String
  | PublishNoExposed
  | PublishNoSummary
  | PublishNoReadme
  | PublishShortReadme
  | PublishNoLicense
  | PublishBadDetails FilePath
  | PublishApplication
  | PublishBuildProblem BuildExit.BuildError
  | PublishNotInitialVersion String
  | PublishAlreadyPublished String
  | PublishInvalidBump String
  | PublishCannotGetDocs String
  | PublishBadBump String
  | PublishCannotRegister String
  | PublishMustHaveLatestRegistry
  | PublishNoGit
  | PublishWithNoRepositoryLocalName
  | PublishUsingRepositoryLocalNameThatDoesntExistInCustomRepositoryConfig String [String]
  | PublishToStandardCanopyRepositoryUsingCanopy
  deriving (Show)

-- | Convert a 'Publish' error to a structured 'Report'.
publishToReport :: Publish -> Report
publishToReport PublishNoOutline = noOutlineError "canopy publish"
publishToReport (PublishBadOutline msg) = badOutlineError msg
publishToReport (PublishMissingTag tag) = publishMissingTagError tag
publishToReport (PublishCannotGetTag msg) = publishCannotGetTagError msg
publishToReport (PublishCannotGetTagData msg) = publishCannotGetTagDataError msg
publishToReport (PublishLocalChanges msg) = publishLocalChangesError msg
publishToReport (PublishCannotGetZip msg) = publishCannotGetZipError msg
publishToReport (PublishCannotDecodeZip msg) = publishCannotDecodeZipError msg
publishToReport (PublishCustomRepositoryConfigDataError msg) = publishRepoConfigError msg
publishToReport PublishNoExposed = pkgNeedsExposingError
publishToReport PublishNoSummary = publishNoSummaryError
publishToReport PublishNoReadme = publishNoReadmeError
publishToReport PublishShortReadme = publishShortReadmeError
publishToReport PublishNoLicense = publishNoLicenseError
publishToReport (PublishBadDetails path) = badDetailsError path
publishToReport PublishApplication = publishApplicationError
publishToReport (PublishBuildProblem buildErr) = BuildExit.toDoc buildErr
publishToReport (PublishNotInitialVersion msg) = publishNotInitialVersionError msg
publishToReport (PublishAlreadyPublished msg) = publishAlreadyPublishedError msg
publishToReport (PublishInvalidBump msg) = publishInvalidBumpError msg
publishToReport (PublishCannotGetDocs msg) = publishCannotGetDocsError msg
publishToReport (PublishBadBump msg) = publishBadBumpError msg
publishToReport (PublishCannotRegister msg) = publishCannotRegisterError msg
publishToReport PublishMustHaveLatestRegistry = mustHaveLatestRegistryError "publish"
publishToReport PublishNoGit = publishNoGitError
publishToReport PublishWithNoRepositoryLocalName = publishNoRepoNameError
publishToReport (PublishUsingRepositoryLocalNameThatDoesntExistInCustomRepositoryConfig name suggestions) =
  publishRepoNotFoundError name suggestions
publishToReport PublishToStandardCanopyRepositoryUsingCanopy = publishStandardRepoError

-- | Message shown for new package creation guidance.
newPackageOverview :: Doc.Doc
newPackageOverview =
  Doc.vcat
    [ Doc.green "This appears to be a new package!"
    , ""
    , Doc.reflow "All new Canopy packages start at version 1.0.0 and use semantic"
    , Doc.reflow "versioning to communicate changes to users."
    ]

-- ── Diff errors ──────────────────────────────────────────────────────

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

-- ── Bump errors ──────────────────────────────────────────────────────

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

-- ── Init errors ──────────────────────────────────────────────────────

-- | Init (project initialization) errors.
data Init
  = InitAlreadyExists
  | InitRegistryProblem String
  | InitSolverProblem String
  | InitNoSolution [String]
  | InitNoOfflineSolution [String]
  | InitCannotCreateDirectory FilePath
  | InitCannotWriteFile FilePath
  | InitBadDetails FilePath
  deriving (Show)

-- | Convert an 'Init' error to a structured 'Report'.
initToReport :: Init -> Report
initToReport InitAlreadyExists = initAlreadyExistsError
initToReport (InitRegistryProblem msg) = initRegistryProblemError msg
initToReport (InitSolverProblem msg) = initSolverProblemError msg
initToReport (InitNoSolution pkgs) = initNoSolutionError pkgs
initToReport (InitNoOfflineSolution pkgs) = initNoOfflineSolutionError pkgs
initToReport (InitCannotCreateDirectory path) = initCannotCreateDirError path
initToReport (InitCannotWriteFile path) = initCannotWriteFileError path
initToReport (InitBadDetails path) = badDetailsError path

-- ── Setup errors ─────────────────────────────────────────────────────

-- | Errors related to the package registry.
data RegistryProblem
  = RegistryConnectionError String
  | RegistryBadData String
  deriving (Show)

-- | Errors from the dependency solver.
data Solver
  = SolverNoSolution String
  | SolverConflict String
  deriving (Show)

-- | Setup (bootstrap) errors.
data Setup
  = SetupRegistryFailed String
  | SetupCacheFailed String
  deriving (Show)

-- | Convert a 'Setup' error to a structured 'Report'.
setupToReport :: Setup -> Report
setupToReport (SetupRegistryFailed msg) = setupRegistryFailedError msg
setupToReport (SetupCacheFailed msg) = setupCacheFailedError msg

-- ── Reactor errors ───────────────────────────────────────────────────

-- | Errors from the development server (reactor).
data Reactor
  = ReactorCompileError String
  | ReactorBuildError String
  | ReactorBadDetails FilePath
  | ReactorBadBuild BuildExit.BuildError
  | ReactorBadGenerate String
  deriving (Show)

-- | Convert a 'Reactor' error to a structured 'Report'.
reactorToReport :: Reactor -> Report
reactorToReport (ReactorCompileError msg) = reactorCompileError msg
reactorToReport (ReactorBuildError msg) = reactorBuildErrorMsg msg
reactorToReport (ReactorBadDetails path) = badDetailsError path
reactorToReport (ReactorBadBuild buildErr) = BuildExit.toDoc buildErr
reactorToReport (ReactorBadGenerate msg) = generateError msg

-- ═══════════════════════════════════════════════════════════════════════
-- ── Shared error message builders ──────────────────────────────────────
-- ═══════════════════════════════════════════════════════════════════════

-- | No canopy.json found.
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

-- | Cannot load project details from path.
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

-- | Bad outline (invalid canopy.json).
badOutlineError :: String -> Report
badOutlineError msg =
  structuredError "INVALID canopy.json"
    (Doc.reflow ("There is a problem with your canopy.json file: " ++ msg))
    (Doc.reflow "Check the JSON syntax and ensure all required fields are present.")

-- | Bad registry data.
badRegistryError :: String -> Report
badRegistryError msg =
  structuredError "REGISTRY ERROR"
    (Doc.reflow ("The package registry data is invalid: " ++ msg))
    (Doc.vcat
      [ Doc.reflow "Try refreshing the registry cache:"
      , ""
      , fixLine (Doc.green "canopy setup")
      ])

-- | Application needs file names.
appNeedsFileNamesError :: String -> Report
appNeedsFileNamesError example =
  structuredError "MISSING FILE ARGUMENT"
    (Doc.reflow "Application projects need explicit file names to compile.")
    (Doc.vcat
      [ Doc.reflow "Try specifying a source file:"
      , ""
      , fixLine (Doc.green (Doc.fromChars example))
      ])

-- | Package has no exposed modules.
pkgNeedsExposingError :: Report
pkgNeedsExposingError =
  structuredError "NO EXPOSED MODULES"
    (Doc.reflow "Your package does not expose any modules. Without exposed modules, there is nothing for users to import.")
    (Doc.vcat
      [ Doc.reflow "Add modules to the \"exposed-modules\" field in canopy.json:"
      , ""
      , fixLine (Doc.green "\"exposed-modules\": [ \"MyModule\" ]")
      ])

-- | No main function found.
noMainError :: Report
noMainError =
  structuredError "NO MAIN FUNCTION"
    (Doc.reflow "I cannot find a main value in your module. Every application needs a main value to serve as the entry point.")
    (Doc.vcat
      [ Doc.reflow "Add a main value to your module, for example:"
      , ""
      , fixLine (Doc.green "main = Html.text \"Hello!\"")
      ])

-- | Cannot generate HTML from multiple files.
multipleFilesHtmlError :: Report
multipleFilesHtmlError =
  structuredError "TOO MANY FILES FOR HTML"
    (Doc.reflow "When generating HTML output, you can only compile one file at a time.")
    (Doc.vcat
      [ Doc.reflow "Either pass a single source file:"
      , ""
      , fixLine (Doc.green "canopy make src/Main.can")
      , ""
      , Doc.reflow "Or use JavaScript output for multiple files:"
      , ""
      , fixLine (Doc.green "canopy make src/Main.can src/Other.can --output=app.js")
      ])

-- | Cannot use both --optimize and --debug.
optimizeAndDebugError :: Report
optimizeAndDebugError =
  structuredError "CONFLICTING FLAGS"
    (Doc.reflow "You cannot use both --optimize and --debug at the same time. These flags are mutually exclusive.")
    (Doc.vcat
      [ Doc.reflow "Use one or the other:"
      , ""
      , fixLine (Doc.green "canopy make --optimize    " <+> Doc.fromChars "for production builds")
      , fixLine (Doc.green "canopy make --debug       " <+> Doc.fromChars "for development builds")
      ])

-- | Build error with message.
buildError :: String -> Report
buildError msg =
  structuredErrorNoFix "BUILD ERROR"
    (Doc.reflow msg)

-- | Code generation error.
generateError :: String -> Report
generateError msg =
  structuredError "CODE GENERATION ERROR"
    (Doc.reflow ("Code generation failed: " ++ msg))
    (Doc.reflow "This is likely a compiler bug. Please report it at the project repository.")

-- | Only packages support this operation.
onlyPackagesError :: String -> Report
onlyPackagesError cmd =
  structuredError "NOT A PACKAGE"
    (Doc.reflow ("The " ++ cmd ++ " command only works with packages, but this project is an application."))
    (Doc.reflow "Check your canopy.json — applications have a \"source-directories\" field, while packages have an \"exposed-modules\" field.")

-- | Repository configuration error.
repoConfigError :: String -> Report
repoConfigError cmd =
  structuredError "REPOSITORY CONFIG ERROR"
    (Doc.reflow ("There is a problem with the custom repository configuration needed for " ++ cmd ++ "."))
    (Doc.reflow "Check the repositories section of your canopy.json file.")

-- | Must have the latest registry.
mustHaveLatestRegistryError :: String -> Report
mustHaveLatestRegistryError cmd =
  structuredError "OUTDATED REGISTRY"
    (Doc.reflow ("The " ++ cmd ++ " command requires the latest package registry, but the registry could not be updated."))
    (Doc.vcat
      [ Doc.reflow "Try refreshing the registry:"
      , ""
      , fixLine (Doc.green "canopy setup")
      , ""
      , Doc.reflow "If the problem persists, check your internet connection."
      ])

-- ── Install-specific errors ──────────────────────────────────────────

-- | Unknown package (online).
unknownPackageError :: String -> [String] -> Report
unknownPackageError pkg suggestions =
  structuredError "UNKNOWN PACKAGE"
    (Doc.reflow ("I cannot find a package named " ++ pkg ++ " in the package registry."))
    (suggestionsBlock suggestions)

-- | Unknown package (offline).
unknownPackageOfflineError :: String -> [String] -> Report
unknownPackageOfflineError pkg suggestions =
  structuredError "UNKNOWN PACKAGE"
    (Doc.vcat
      [ Doc.reflow ("I cannot find a package named " ++ pkg ++ " in the local registry cache.")
      , Doc.reflow "Note: You appear to be offline."
      ])
    (suggestionsBlock suggestions)

-- | Format package suggestions.
suggestionsBlock :: [String] -> Doc.Doc
suggestionsBlock [] =
  Doc.reflow "Check the package name for typos."
suggestionsBlock suggestions =
  Doc.vcat
    [ Doc.reflow "Did you mean one of these?"
    , ""
    , Doc.vcat (fmap (\s -> fixLine (Doc.green (Doc.fromChars s))) suggestions)
    ]

-- | No dependency solution found.
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

-- | No offline dependency solution.
noOfflineSolutionError :: String -> Report
noOfflineSolutionError pkg =
  structuredError "DEPENDENCY CONFLICT (OFFLINE)"
    (Doc.reflow ("I cannot find a set of cached package versions that satisfies all constraints for " ++ pkg ++ "."))
    (Doc.vcat
      [ Doc.reflow "Since you appear to be offline, try connecting to the internet and running:"
      , ""
      , fixLine (Doc.green "canopy install")
      ])

-- | Solver had trouble.
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

-- | No packages specified for install.
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

-- ── Publish-specific errors ──────────────────────────────────────────

-- | Missing Git tag for version.
publishMissingTagError :: String -> Report
publishMissingTagError tag =
  structuredError "MISSING GIT TAG"
    (Doc.reflow ("I cannot find the Git tag " ++ tag ++ " that should correspond to this version."))
    (Doc.vcat
      [ Doc.reflow "Create and push the tag:"
      , ""
      , fixLine (Doc.green (Doc.fromChars ("git tag " ++ tag)))
      , fixLine (Doc.green (Doc.fromChars ("git push origin " ++ tag)))
      ])

-- | Cannot get Git tag.
publishCannotGetTagError :: String -> Report
publishCannotGetTagError msg =
  structuredError "GIT TAG ERROR"
    (Doc.reflow ("I had trouble reading Git tag information: " ++ msg))
    (Doc.reflow "Make sure you are in a Git repository with the correct tags pushed.")

-- | Cannot get tag data.
publishCannotGetTagDataError :: String -> Report
publishCannotGetTagDataError msg =
  structuredErrorNoFix "GIT TAG DATA ERROR"
    (Doc.reflow ("I could not read the data for the Git tag: " ++ msg))

-- | Local changes detected.
publishLocalChangesError :: String -> Report
publishLocalChangesError msg =
  structuredError "UNCOMMITTED CHANGES"
    (Doc.reflow ("Your local code has changes that are not committed: " ++ msg))
    (Doc.vcat
      [ Doc.reflow "Commit or stash your changes before publishing:"
      , ""
      , fixLine (Doc.green "git add -A && git commit -m \"prepare for publish\"")
      ])

-- | Cannot download zip archive.
publishCannotGetZipError :: String -> Report
publishCannotGetZipError msg =
  structuredError "DOWNLOAD FAILED"
    (Doc.reflow ("I could not download the source code archive from GitHub: " ++ msg))
    (Doc.reflow "Check that the repository is public and the tag exists on GitHub.")

-- | Cannot decode zip archive.
publishCannotDecodeZipError :: String -> Report
publishCannotDecodeZipError msg =
  structuredError "INVALID ARCHIVE"
    (Doc.reflow ("The downloaded source archive could not be decoded: " ++ msg))
    (Doc.reflow "This may indicate a corrupted download. Try publishing again.")

-- | Repository config data error.
publishRepoConfigError :: String -> Report
publishRepoConfigError msg =
  structuredError "REPOSITORY CONFIG ERROR"
    (Doc.reflow ("There is a problem with the repository configuration: " ++ msg))
    (Doc.reflow "Check the repositories section of your canopy.json file.")

-- | Package has no summary.
publishNoSummaryError :: Report
publishNoSummaryError =
  structuredError "MISSING SUMMARY"
    (Doc.reflow "Your package does not have a summary. The summary field is required for published packages.")
    (Doc.vcat
      [ Doc.reflow "Add a \"summary\" field to your canopy.json:"
      , ""
      , fixLine (Doc.green "\"summary\": \"A helpful one-line description of your package\"")
      ])

-- | No README.md found.
publishNoReadmeError :: Report
publishNoReadmeError =
  structuredError "MISSING README"
    (Doc.reflow "I cannot find a README.md file in your project root. A README is required for published packages.")
    (Doc.vcat
      [ Doc.reflow "Create a README.md file that explains:"
      , ""
      , fixLine (Doc.fromChars "- What your package does")
      , fixLine (Doc.fromChars "- How to install and use it")
      , fixLine (Doc.fromChars "- A quick example")
      ])

-- | README.md is too short.
publishShortReadmeError :: Report
publishShortReadmeError =
  structuredError "README TOO SHORT"
    (Doc.reflow "Your README.md is too short. A good README helps users understand your package.")
    (Doc.reflow "Add more detail about what your package does and how to use it.")

-- | No LICENSE file found.
publishNoLicenseError :: Report
publishNoLicenseError =
  structuredError "MISSING LICENSE"
    (Doc.reflow "I cannot find a LICENSE file in your project root. A license is required for published packages.")
    (Doc.reflow "Add a LICENSE file. Common choices are BSD-3-Clause and MIT.")

-- | Cannot publish applications.
publishApplicationError :: Report
publishApplicationError =
  structuredError "CANNOT PUBLISH APPLICATION"
    (Doc.reflow "You are trying to publish an application, but only packages can be published.")
    (Doc.reflow "If you meant to create a package, change the \"type\" field in canopy.json from \"application\" to \"package\".")

-- | Not the initial version.
publishNotInitialVersionError :: String -> Report
publishNotInitialVersionError vsn =
  structuredError "WRONG INITIAL VERSION"
    (Doc.reflow ("The version in canopy.json is " ++ vsn ++ ", but new packages must start at version 1.0.0."))
    (Doc.vcat
      [ Doc.reflow "Set the version to 1.0.0 in canopy.json:"
      , ""
      , fixLine (Doc.green "\"version\": \"1.0.0\"")
      ])

-- | Version already published.
publishAlreadyPublishedError :: String -> Report
publishAlreadyPublishedError vsn =
  structuredError "ALREADY PUBLISHED"
    (Doc.reflow ("Version " ++ vsn ++ " has already been published. You cannot publish the same version twice."))
    (Doc.vcat
      [ Doc.reflow "To publish changes, bump the version:"
      , ""
      , fixLine (Doc.green "canopy bump")
      ])

-- | Invalid version bump.
publishInvalidBumpError :: String -> Report
publishInvalidBumpError msg =
  structuredError "INVALID VERSION BUMP"
    (Doc.reflow ("The version bump is not valid: " ++ msg))
    (Doc.vcat
      [ Doc.reflow "Use canopy bump to calculate the correct version:"
      , ""
      , fixLine (Doc.green "canopy bump")
      ])

-- | Cannot get documentation.
publishCannotGetDocsError :: String -> Report
publishCannotGetDocsError msg =
  structuredError "DOCUMENTATION ERROR"
    (Doc.reflow ("I could not generate documentation for your package: " ++ msg))
    (Doc.vcat
      [ Doc.reflow "Make sure your project builds cleanly:"
      , ""
      , fixLine (Doc.green "canopy make")
      ])

-- | Bad version bump.
publishBadBumpError :: String -> Report
publishBadBumpError msg =
  structuredError "BAD VERSION BUMP"
    (Doc.reflow ("The version bump does not follow semantic versioning rules: " ++ msg))
    (Doc.vcat
      [ Doc.reflow "Use canopy bump to calculate the correct version:"
      , ""
      , fixLine (Doc.green "canopy bump")
      ])

-- | Cannot register package.
publishCannotRegisterError :: String -> Report
publishCannotRegisterError msg =
  structuredError "REGISTRATION FAILED"
    (Doc.reflow ("I could not register your package with the repository: " ++ msg))
    (Doc.reflow "Check your internet connection and try again.")

-- | No Git repository found.
publishNoGitError :: Report
publishNoGitError =
  structuredError "NO GIT REPOSITORY"
    (Doc.reflow "I cannot find a Git repository in this directory. Publishing requires Git for version tracking.")
    (Doc.vcat
      [ Doc.reflow "Initialize a Git repository:"
      , ""
      , fixLine (Doc.green "git init")
      , fixLine (Doc.green "git add -A")
      , fixLine (Doc.green "git commit -m \"initial commit\"")
      ])

-- | No repository local name specified.
publishNoRepoNameError :: Report
publishNoRepoNameError =
  structuredError "MISSING REPOSITORY NAME"
    (Doc.reflow "You must specify which repository to publish to.")
    (Doc.vcat
      [ Doc.reflow "Specify the repository name:"
      , ""
      , fixLine (Doc.green "canopy publish <repository-name>")
      ])

-- | Repository local name not found.
publishRepoNotFoundError :: String -> [String] -> Report
publishRepoNotFoundError name suggestions =
  structuredError "REPOSITORY NOT FOUND"
    (Doc.reflow ("I cannot find a repository named \"" ++ name ++ "\" in your configuration."))
    (availableReposBlock suggestions)

-- | Format available repositories list.
availableReposBlock :: [String] -> Doc.Doc
availableReposBlock [] =
  Doc.reflow "No repositories are configured. Add a repositories section to canopy.json."
availableReposBlock repos =
  Doc.vcat
    [ Doc.reflow "Available repositories:"
    , ""
    , Doc.vcat (fmap (\r -> fixLine (Doc.green (Doc.fromChars r))) repos)
    ]

-- | Cannot publish to standard Canopy repository.
publishStandardRepoError :: Report
publishStandardRepoError =
  structuredErrorNoFix "CANNOT PUBLISH HERE"
    (Doc.reflow "Cannot publish to the standard Canopy repository from this tool.")

-- ── Diff-specific errors ─────────────────────────────────────────────

-- | Unknown version for diff.
diffUnknownVersionError :: String -> Report
diffUnknownVersionError vsn =
  structuredError "UNKNOWN VERSION"
    (Doc.reflow ("I cannot find version " ++ vsn ++ " of this package in the registry."))
    (Doc.vcat
      [ Doc.reflow "Check the available versions with:"
      , ""
      , fixLine (Doc.green "canopy diff")
      ])

-- | Documentation problem during diff.
diffDocsProblemError :: String -> Report
diffDocsProblemError msg =
  structuredError "DOCUMENTATION ERROR"
    (Doc.reflow ("I could not generate documentation for the diff: " ++ msg))
    (Doc.vcat
      [ Doc.reflow "Make sure your project builds cleanly:"
      , ""
      , fixLine (Doc.green "canopy make")
      ])

-- ── Bump-specific errors ─────────────────────────────────────────────

-- | Unexpected version during bump.
bumpUnexpectedVersionError :: String -> [String] -> Report
bumpUnexpectedVersionError current suggestions =
  structuredError "UNEXPECTED VERSION"
    (Doc.reflow ("The current version " ++ current ++ " is not valid for bumping."))
    (bumpSuggestionsBlock suggestions)

-- | Format bump version suggestions.
bumpSuggestionsBlock :: [String] -> Doc.Doc
bumpSuggestionsBlock [] =
  Doc.reflow "Check the version field in canopy.json."
bumpSuggestionsBlock versions =
  Doc.vcat
    [ Doc.reflow "Expected one of these versions:"
    , ""
    , Doc.vcat (fmap (\v -> fixLine (Doc.green (Doc.fromChars v))) versions)
    ]

-- | Cannot find docs for bump.
bumpCannotFindDocsError :: String -> Report
bumpCannotFindDocsError msg =
  structuredError "DOCUMENTATION ERROR"
    (Doc.reflow ("I could not generate documentation needed for the version bump: " ++ msg))
    (Doc.vcat
      [ Doc.reflow "Make sure your project builds cleanly:"
      , ""
      , fixLine (Doc.green "canopy make")
      ])

-- ── Init-specific errors ─────────────────────────────────────────────

-- | Project already exists.
initAlreadyExistsError :: Report
initAlreadyExistsError =
  structuredError "PROJECT ALREADY EXISTS"
    (Doc.reflow "There is already a canopy.json in this directory.")
    (Doc.reflow "Use a different directory, or delete the existing canopy.json to start over.")

-- | Registry problem during init.
initRegistryProblemError :: String -> Report
initRegistryProblemError msg =
  structuredError "REGISTRY ERROR"
    (Doc.reflow ("I could not access the package registry during project initialization: " ++ msg))
    (Doc.vcat
      [ Doc.reflow "Check your internet connection, or try:"
      , ""
      , fixLine (Doc.green "canopy setup")
      ])

-- | Solver problem during init.
initSolverProblemError :: String -> Report
initSolverProblemError msg =
  structuredError "SOLVER ERROR"
    (Doc.reflow ("The dependency solver encountered a problem: " ++ msg))
    (Doc.reflow "This may be a temporary registry issue. Try again in a moment.")

-- | No dependency solution during init.
initNoSolutionError :: [String] -> Report
initNoSolutionError pkgs =
  structuredError "NO DEPENDENCY SOLUTION"
    (Doc.vcat
      [ Doc.reflow "I could not find a set of package versions that work together."
      , Doc.reflow ("Packages involved: " ++ List.intercalate ", " pkgs)
      ])
    (Doc.reflow "This is unusual for a new project. Try running canopy setup first.")

-- | No offline dependency solution during init.
initNoOfflineSolutionError :: [String] -> Report
initNoOfflineSolutionError pkgs =
  structuredError "NO OFFLINE SOLUTION"
    (Doc.vcat
      [ Doc.reflow "I could not find cached package versions that work together."
      , Doc.reflow ("Packages involved: " ++ List.intercalate ", " pkgs)
      ])
    (Doc.vcat
      [ Doc.reflow "Connect to the internet and try again, or run:"
      , ""
      , fixLine (Doc.green "canopy setup")
      ])

-- | Cannot create directory during init.
initCannotCreateDirError :: FilePath -> Report
initCannotCreateDirError path =
  structuredError "CANNOT CREATE DIRECTORY"
    (Doc.reflow ("I could not create the directory: " ++ path))
    (Doc.reflow "Check that you have write permissions and sufficient disk space.")

-- | Cannot write file during init.
initCannotWriteFileError :: FilePath -> Report
initCannotWriteFileError path =
  structuredError "CANNOT WRITE FILE"
    (Doc.reflow ("I could not write the file: " ++ path))
    (Doc.reflow "Check that you have write permissions and sufficient disk space.")

-- ── Setup-specific errors ────────────────────────────────────────────

-- | Registry fetch/read failed during setup.
setupRegistryFailedError :: String -> Report
setupRegistryFailedError msg =
  structuredError "REGISTRY UNAVAILABLE"
    (Doc.reflow ("I could not fetch or read the package registry: " ++ msg))
    (Doc.reflow "Check your internet connection and try again.")

-- | Cache error during setup.
setupCacheFailedError :: String -> Report
setupCacheFailedError msg =
  structuredError "CACHE ERROR"
    (Doc.reflow ("The package cache encountered an error: " ++ msg))
    (Doc.reflow "Check disk space and permissions for ~/.canopy/")

-- ── Reactor-specific errors ──────────────────────────────────────────

-- | Reactor compile error.
reactorCompileError :: String -> Report
reactorCompileError msg =
  structuredErrorNoFix "COMPILE ERROR"
    (Doc.reflow msg)

-- | Reactor build error.
reactorBuildErrorMsg :: String -> Report
reactorBuildErrorMsg msg =
  structuredErrorNoFix "BUILD ERROR"
    (Doc.reflow msg)
