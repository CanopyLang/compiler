{-# LANGUAGE OverloadedStrings #-}

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
        MakeCannotOptimizeAndDebug,
        MakeReproducibilityFailure
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

    -- * New (project scaffolding) Errors
    New (..),
    newToReport,

    -- * Docs Errors
    Docs
      ( DocsNoOutline,
        DocsBadDetails,
        DocsCannotBuild,
        DocsAppNeedsFileNames,
        DocsPkgNeedsExposing,
        DocsCannotWrite
      ),
    docsToReport,

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
import Reporting.Exit.Install
  ( Install (..),
    installToReport,
  )
import Reporting.Exit.Publish
  ( Publish (..),
    newPackageOverview,
    publishToReport,
  )
import qualified System.IO as IO

-- SHARED ERROR FORMATTING

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

structuredErrorNoFix :: String -> Doc.Doc -> Doc.Doc
structuredErrorNoFix title explanation =
  Doc.vcat
    [ errorBar title
    , ""
    , explanation
    , ""
    ]

errorBar :: String -> Doc.Doc
errorBar title =
  Doc.dullred ("--" <+> Doc.fromChars title <+> Doc.fromChars dashes)
  where
    dashes = replicate (max 1 (80 - 4 - length title)) '-'

fixLine :: Doc.Doc -> Doc.Doc
fixLine = Doc.indent 4

-- ERROR REPORT TYPE

-- | Error report type rendered as a styled Doc.
type Report = Doc.Doc

-- | Print a Report to stderr with ANSI color support.
toStderr :: Report -> IO ()
toStderr = Doc.toAnsi IO.stderr

-- CHECK ERRORS

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

-- DOCS ERRORS

-- | Documentation generation errors.
data Docs
  = DocsNoOutline
  | DocsBadDetails FilePath
  | DocsCannotBuild BuildExit.BuildError
  | DocsAppNeedsFileNames
  | DocsPkgNeedsExposing
  | DocsCannotWrite FilePath String
  deriving (Show)

-- | Convert a 'Docs' error to a structured 'Report'.
docsToReport :: Docs -> Report
docsToReport DocsNoOutline = noOutlineError "canopy docs"
docsToReport (DocsBadDetails path) = badDetailsError path
docsToReport (DocsCannotBuild buildErr) = BuildExit.toDoc buildErr
docsToReport DocsAppNeedsFileNames = appNeedsFileNamesError "canopy docs src/Main.can"
docsToReport DocsPkgNeedsExposing = pkgNeedsExposingError
docsToReport (DocsCannotWrite path msg) = docsCannotWriteError path msg

-- MAKE ERRORS

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
  | -- | Two builds produced different output at the given byte offset
    MakeReproducibilityFailure !Int
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
makeToReport (MakeReproducibilityFailure offset) = reproducibilityFailureError offset

-- REPL ERRORS

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

-- DIFF ERRORS

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

-- BUMP ERRORS

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

-- INIT ERRORS

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

-- NEW (PROJECT SCAFFOLDING) ERRORS

-- | Errors from the @canopy new@ project scaffolding command.
data New
  = -- | Project directory already exists
    NewDirectoryExists !FilePath
  | -- | Project name is empty
    NewEmptyName
  | -- | Project name contains invalid characters
    NewInvalidName !String !String
  | -- | Cannot create project directory
    NewCannotCreateDirectory !FilePath !String
  | -- | Cannot write a project file
    NewCannotWriteFile !FilePath !String
  | -- | Git initialization failed
    NewGitInitFailed !String
  deriving (Show)

-- | Convert a 'New' error to a structured 'Report'.
newToReport :: New -> Report
newToReport (NewDirectoryExists path) = newDirectoryExistsError path
newToReport NewEmptyName = newEmptyNameError
newToReport (NewInvalidName name reason) = newInvalidNameError name reason
newToReport (NewCannotCreateDirectory path msg) = newCannotCreateDirError path msg
newToReport (NewCannotWriteFile path msg) = newCannotWriteFileError path msg
newToReport (NewGitInitFailed msg) = newGitInitFailedError msg

-- SETUP ERRORS

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

-- REACTOR ERRORS

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

-- SHARED ERROR MESSAGE BUILDERS

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

appNeedsFileNamesError :: String -> Report
appNeedsFileNamesError example =
  structuredError "MISSING FILE ARGUMENT"
    (Doc.reflow "Application projects need explicit file names to compile.")
    (Doc.vcat
      [ Doc.reflow "Try specifying a source file:"
      , ""
      , fixLine (Doc.green (Doc.fromChars example))
      ])

pkgNeedsExposingError :: Report
pkgNeedsExposingError =
  structuredError "NO EXPOSED MODULES"
    (Doc.reflow "Your package does not expose any modules. Without exposed modules, there is nothing for users to import.")
    (Doc.vcat
      [ Doc.reflow "Add modules to the \"exposed-modules\" field in canopy.json:"
      , ""
      , fixLine (Doc.green "\"exposed-modules\": [ \"MyModule\" ]")
      ])

noMainError :: Report
noMainError =
  structuredError "NO MAIN FUNCTION"
    (Doc.reflow "I cannot find a main value in your module. Every application needs a main value to serve as the entry point.")
    (Doc.vcat
      [ Doc.reflow "Add a main value to your module, for example:"
      , ""
      , fixLine (Doc.green "main = Html.text \"Hello!\"")
      ])

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

buildError :: String -> Report
buildError msg =
  structuredErrorNoFix "BUILD ERROR"
    (Doc.reflow msg)

generateError :: String -> Report
generateError msg =
  structuredError "CODE GENERATION ERROR"
    (Doc.reflow ("Code generation failed: " ++ msg))
    (Doc.reflow "This is likely a compiler bug. Please report it at the project repository.")

-- | Error for when two builds of the same source produce different output.
reproducibilityFailureError :: Int -> Report
reproducibilityFailureError offset =
  structuredError "REPRODUCIBILITY FAILURE"
    (Doc.reflow ("Two builds of the same source produced different output. First divergence at byte " ++ show offset ++ "."))
    (Doc.vcat
      [ Doc.reflow "This indicates non-determinism in code generation."
      , ""
      , Doc.reflow "Please report this as a bug at the project repository with:"
      , fixLine (Doc.green "1. The project source code")
      , fixLine (Doc.green "2. The exact canopy version (canopy --version)")
      , fixLine (Doc.green "3. Your operating system and architecture")
      ])

onlyPackagesError :: String -> Report
onlyPackagesError cmd =
  structuredError "NOT A PACKAGE"
    (Doc.reflow ("The " ++ cmd ++ " command only works with packages, but this project is an application."))
    (Doc.reflow "Check your canopy.json — applications have a \"source-directories\" field, while packages have an \"exposed-modules\" field.")

repoConfigError :: String -> Report
repoConfigError cmd =
  structuredError "REPOSITORY CONFIG ERROR"
    (Doc.reflow ("There is a problem with the custom repository configuration needed for " ++ cmd ++ "."))
    (Doc.reflow "Check the repositories section of your canopy.json file.")

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

unknownPackageError :: String -> [String] -> Report
unknownPackageError pkg suggestions =
  structuredError "UNKNOWN PACKAGE"
    (Doc.reflow ("I cannot find a package named " ++ pkg ++ " in the package registry."))
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

diffUnknownVersionError :: String -> Report
diffUnknownVersionError vsn =
  structuredError "UNKNOWN VERSION"
    (Doc.reflow ("I cannot find version " ++ vsn ++ " of this package in the registry."))
    (Doc.vcat
      [ Doc.reflow "Check the available versions with:"
      , ""
      , fixLine (Doc.green "canopy diff")
      ])

diffDocsProblemError :: String -> Report
diffDocsProblemError msg =
  structuredError "DOCUMENTATION ERROR"
    (Doc.reflow ("I could not generate documentation for the diff: " ++ msg))
    (Doc.vcat
      [ Doc.reflow "Make sure your project builds cleanly:"
      , ""
      , fixLine (Doc.green "canopy make")
      ])

bumpUnexpectedVersionError :: String -> [String] -> Report
bumpUnexpectedVersionError current suggestions =
  structuredError "UNEXPECTED VERSION"
    (Doc.reflow ("The current version " ++ current ++ " is not valid for bumping."))
    (bumpSuggestionsBlock suggestions)

bumpSuggestionsBlock :: [String] -> Doc.Doc
bumpSuggestionsBlock [] =
  Doc.reflow "Check the version field in canopy.json."
bumpSuggestionsBlock versions =
  Doc.vcat
    [ Doc.reflow "Expected one of these versions:"
    , ""
    , Doc.vcat (fmap (\v -> fixLine (Doc.green (Doc.fromChars v))) versions)
    ]

bumpCannotFindDocsError :: String -> Report
bumpCannotFindDocsError msg =
  structuredError "DOCUMENTATION ERROR"
    (Doc.reflow ("I could not generate documentation needed for the version bump: " ++ msg))
    (Doc.vcat
      [ Doc.reflow "Make sure your project builds cleanly:"
      , ""
      , fixLine (Doc.green "canopy make")
      ])

initAlreadyExistsError :: Report
initAlreadyExistsError =
  structuredError "PROJECT ALREADY EXISTS"
    (Doc.reflow "There is already a canopy.json in this directory.")
    (Doc.reflow "Use a different directory, or delete the existing canopy.json to start over.")

initRegistryProblemError :: String -> Report
initRegistryProblemError msg =
  structuredError "REGISTRY ERROR"
    (Doc.reflow ("I could not access the package registry during project initialization: " ++ msg))
    (Doc.vcat
      [ Doc.reflow "Check your internet connection, or try:"
      , ""
      , fixLine (Doc.green "canopy setup")
      ])

initSolverProblemError :: String -> Report
initSolverProblemError msg =
  structuredError "SOLVER ERROR"
    (Doc.reflow ("The dependency solver encountered a problem: " ++ msg))
    (Doc.reflow "This may be a temporary registry issue. Try again in a moment.")

initNoSolutionError :: [String] -> Report
initNoSolutionError pkgs =
  structuredError "NO DEPENDENCY SOLUTION"
    (Doc.vcat
      [ Doc.reflow "I could not find a set of package versions that work together."
      , Doc.reflow ("Packages involved: " ++ List.intercalate ", " pkgs)
      ])
    (Doc.reflow "This is unusual for a new project. Try running canopy setup first.")

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

initCannotCreateDirError :: FilePath -> Report
initCannotCreateDirError path =
  structuredError "CANNOT CREATE DIRECTORY"
    (Doc.reflow ("I could not create the directory: " ++ path))
    (Doc.reflow "Check that you have write permissions and sufficient disk space.")

initCannotWriteFileError :: FilePath -> Report
initCannotWriteFileError path =
  structuredError "CANNOT WRITE FILE"
    (Doc.reflow ("I could not write the file: " ++ path))
    (Doc.reflow "Check that you have write permissions and sufficient disk space.")

setupRegistryFailedError :: String -> Report
setupRegistryFailedError msg =
  structuredError "REGISTRY UNAVAILABLE"
    (Doc.reflow ("I could not fetch or read the package registry: " ++ msg))
    (Doc.reflow "Check your internet connection and try again.")

setupCacheFailedError :: String -> Report
setupCacheFailedError msg =
  structuredError "CACHE ERROR"
    (Doc.reflow ("The package cache encountered an error: " ++ msg))
    (Doc.reflow "Check disk space and permissions for ~/.canopy/")

reactorCompileError :: String -> Report
reactorCompileError msg =
  structuredErrorNoFix "COMPILE ERROR"
    (Doc.reflow msg)

reactorBuildErrorMsg :: String -> Report
reactorBuildErrorMsg msg =
  structuredErrorNoFix "BUILD ERROR"
    (Doc.reflow msg)

-- NEW ERROR MESSAGE BUILDERS

newDirectoryExistsError :: FilePath -> Report
newDirectoryExistsError path =
  structuredError "DIRECTORY ALREADY EXISTS"
    (Doc.reflow ("A directory named " ++ path ++ " already exists."))
    (Doc.vcat
      [ Doc.reflow "Choose a different project name, or remove the existing directory:"
      , ""
      , fixLine (Doc.green (Doc.fromChars ("rm -rf " ++ path)))
      ])

newEmptyNameError :: Report
newEmptyNameError =
  structuredError "MISSING PROJECT NAME"
    (Doc.reflow "You need to provide a project name for canopy new.")
    (Doc.vcat
      [ Doc.reflow "For example:"
      , ""
      , fixLine (Doc.green "canopy new my-project")
      ])

newInvalidNameError :: String -> String -> Report
newInvalidNameError name reason =
  structuredError "INVALID PROJECT NAME"
    (Doc.vcat
      [ Doc.reflow ("The project name " ++ show name ++ " is not valid.")
      , Doc.reflow reason
      ])
    (Doc.vcat
      [ Doc.reflow "Project names must:"
      , ""
      , fixLine (Doc.fromChars "Start with a lowercase letter")
      , fixLine (Doc.fromChars "Contain only lowercase letters, digits, and hyphens")
      , fixLine (Doc.fromChars "Not end with a hyphen")
      , ""
      , Doc.reflow "For example:"
      , ""
      , fixLine (Doc.green "canopy new my-project")
      ])

newCannotCreateDirError :: FilePath -> String -> Report
newCannotCreateDirError path msg =
  structuredError "CANNOT CREATE DIRECTORY"
    (Doc.reflow ("I could not create the directory " ++ path ++ ": " ++ msg))
    (Doc.reflow "Check that you have write permissions and sufficient disk space.")

newCannotWriteFileError :: FilePath -> String -> Report
newCannotWriteFileError path msg =
  structuredError "CANNOT WRITE FILE"
    (Doc.reflow ("I could not write the file " ++ path ++ ": " ++ msg))
    (Doc.reflow "Check that you have write permissions and sufficient disk space.")

newGitInitFailedError :: String -> Report
newGitInitFailedError msg =
  structuredError "GIT INIT FAILED"
    (Doc.reflow ("I could not initialize a git repository: " ++ msg))
    (Doc.vcat
      [ Doc.reflow "Make sure git is installed, or use the --no-git flag:"
      , ""
      , fixLine (Doc.green "canopy new my-project --no-git")
      ])

-- DOCS ERROR MESSAGE BUILDERS

docsCannotWriteError :: FilePath -> String -> Report
docsCannotWriteError path msg =
  structuredError "CANNOT WRITE DOCS"
    (Doc.reflow ("I could not write documentation to " ++ path ++ ": " ++ msg))
    (Doc.reflow "Check that you have write permissions and sufficient disk space.")
