{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Pure error types for Terminal operations.
--
-- Clean, minimal exit codes and error types for the NEW terminal.
-- Wraps canopy-builder's Exit module and adds Terminal-specific errors.
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

import qualified Exit as BuildExit
import qualified Reporting.Doc as Doc
import System.IO (hPutStrLn, stderr)

-- | Type-check errors (check command).
--
-- Raised when the @canopy check@ command encounters errors during
-- project loading or compilation.
--
-- @since 0.19.1
data Check
  = -- | No @canopy.json@ found in the current directory tree.
    CheckNoOutline
  | -- | Project details could not be loaded from the given path.
    CheckBadDetails FilePath
  | -- | Compilation failed with the given build error.
    CheckCannotBuild BuildExit.BuildError
  | -- | Application projects require explicit file names.
    CheckAppNeedsFileNames
  | -- | Package project has no exposed modules to check.
    CheckPkgNeedsExposing
  deriving (Show, Eq)

-- | Convert a 'Check' error to a human-readable 'Report'.
--
-- @since 0.19.1
checkToReport :: Check -> Report
checkToReport err =
  case err of
    CheckNoOutline ->
      Doc.fromChars "ERROR: No canopy.json found. Run 'canopy init' to create a project."
    CheckBadDetails path ->
      Doc.fromChars ("ERROR: Cannot load project details from " ++ path)
    CheckCannotBuild buildErr ->
      BuildExit.toDoc buildErr
    CheckAppNeedsFileNames ->
      Doc.fromChars "ERROR: Application projects need file names. Try: canopy check src/Main.can"
    CheckPkgNeedsExposing ->
      Doc.fromChars "ERROR: Package has no exposed modules. Check your canopy.json."

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
  deriving (Show, Eq)

-- | REPL errors.
data Repl
  = ReplBadDetails FilePath
  | ReplBadGenerate String
  | ReplCannotBuild BuildExit.BuildError
  deriving (Show, Eq)

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
  deriving (Show, Eq)

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
  deriving (Show, Eq)

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
  deriving (Show, Eq)

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
  deriving (Show, Eq)

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
  deriving (Show, Eq)

-- | Registry problem errors (stub).
data RegistryProblem
  = RegistryConnectionError String
  | RegistryBadData String
  deriving (Show, Eq)

-- | Solver errors (stub).
data Solver
  = SolverNoSolution String
  | SolverConflict String
  deriving (Show, Eq)

-- | Reactor errors (stub for development server).
data Reactor
  = ReactorCompileError String
  | ReactorBuildError String
  | ReactorBadDetails FilePath
  | ReactorBadBuild BuildExit.BuildError
  | ReactorBadGenerate String
  deriving (Show, Eq)

-- | Error report type (Doc for formatting).
type Report = Doc.Doc

-- | Convert Make error to Report.
makeToReport :: Make -> Report
makeToReport err = case err of
  MakeNoOutline ->
    Doc.fromChars "ERROR: No canopy.json found. Run 'canopy init' to create a project."
  MakeBadDetails path ->
    Doc.fromChars ("ERROR: Cannot load project details from " ++ path)
  MakeBuildError msg ->
    Doc.fromChars ("BUILD ERROR: " ++ msg)
  MakeBadGenerate msg ->
    Doc.fromChars ("GENERATE ERROR: " ++ msg)
  MakeAppNeedsFileNames ->
    Doc.fromChars "ERROR: Application projects need file names. Try: canopy make src/Main.can"
  MakePkgNeedsExposing ->
    Doc.fromChars "ERROR: Package has no exposed modules. Check your canopy.json."
  MakeNoMain ->
    Doc.fromChars "ERROR: No main function found in module."
  MakeMultipleFilesIntoHtml ->
    Doc.fromChars "ERROR: Cannot generate HTML from multiple files."
  MakeCannotBuild buildErr ->
    BuildExit.toDoc buildErr
  MakeCannotOptimizeAndDebug ->
    Doc.fromChars "ERROR: Cannot use both optimize and debug flags together."

-- | Convert REPL error to Report.
replToReport :: Repl -> Report
replToReport err = case err of
  ReplBadDetails path ->
    Doc.fromChars ("ERROR: Cannot load project details from " ++ path)
  ReplBadGenerate msg ->
    Doc.fromChars ("GENERATE ERROR: " ++ msg)
  ReplCannotBuild buildErr ->
    BuildExit.toDoc buildErr

-- | Print Report to stderr.
toStderr :: Report -> IO ()
toStderr report = hPutStrLn stderr (show report)

-- | Show new package overview (stub).
newPackageOverview :: String
newPackageOverview = "New package created successfully!"

-- | Convert Reactor error to Report.
reactorToReport :: Reactor -> Report
reactorToReport err = case err of
  ReactorCompileError msg ->
    Doc.fromChars ("REACTOR COMPILE ERROR: " ++ msg)
  ReactorBuildError msg ->
    Doc.fromChars ("REACTOR BUILD ERROR: " ++ msg)
  ReactorBadDetails path ->
    Doc.fromChars ("ERROR: Cannot load project details from " ++ path)
  ReactorBadBuild buildErr ->
    Doc.fromChars (BuildExit.toString buildErr)
  ReactorBadGenerate msg ->
    Doc.fromChars ("GENERATE ERROR: " ++ msg)

-- | Convert Init error to Report.
initToReport :: Init -> Report
initToReport err = case err of
  InitAlreadyExists ->
    Doc.fromChars "ERROR: Project already exists in this directory"
  InitRegistryProblem msg ->
    Doc.fromChars ("REGISTRY ERROR: " ++ msg)
  InitSolverProblem msg ->
    Doc.fromChars ("SOLVER ERROR: " ++ msg)
  InitNoSolution pkgs ->
    Doc.fromChars ("ERROR: No dependency solution found for packages: " ++ show pkgs)
  InitNoOfflineSolution pkgs ->
    Doc.fromChars ("ERROR: No offline solution found for packages: " ++ show pkgs)
  InitCannotCreateDirectory path ->
    Doc.fromChars ("ERROR: Cannot create directory: " ++ path)
  InitCannotWriteFile path ->
    Doc.fromChars ("ERROR: Cannot write file: " ++ path)
  InitBadDetails path ->
    Doc.fromChars ("ERROR: Cannot load project details from " ++ path)

-- | Convert Publish error to Report.
publishToReport :: Publish -> Report
publishToReport err = case err of
  PublishNoOutline ->
    Doc.fromChars "ERROR: No canopy.json found"
  PublishBadOutline msg ->
    Doc.fromChars ("ERROR: Bad outline: " ++ msg)
  PublishMissingTag msg ->
    Doc.fromChars ("ERROR: Missing tag: " ++ msg)
  PublishCannotGetTag msg ->
    Doc.fromChars ("ERROR: Cannot get tag: " ++ msg)
  PublishCannotGetTagData msg ->
    Doc.fromChars ("ERROR: Cannot get tag data: " ++ msg)
  PublishLocalChanges msg ->
    Doc.fromChars ("ERROR: Local changes detected: " ++ msg)
  PublishCannotGetZip msg ->
    Doc.fromChars ("ERROR: Cannot get zip: " ++ msg)
  PublishCannotDecodeZip msg ->
    Doc.fromChars ("ERROR: Cannot decode zip: " ++ msg)
  PublishCustomRepositoryConfigDataError msg ->
    Doc.fromChars ("ERROR: Custom repository config error: " ++ msg)
  PublishNoExposed ->
    Doc.fromChars "ERROR: No exposed modules in package"
  PublishNoSummary ->
    Doc.fromChars "ERROR: Package has no summary"
  PublishNoReadme ->
    Doc.fromChars "ERROR: No README.md file found"
  PublishShortReadme ->
    Doc.fromChars "ERROR: README.md is too short"
  PublishNoLicense ->
    Doc.fromChars "ERROR: No LICENSE file found"
  PublishBadDetails path ->
    Doc.fromChars ("ERROR: Cannot load project details from " ++ path)
  PublishApplication ->
    Doc.fromChars "ERROR: Cannot publish applications, only packages"
  PublishBuildProblem buildErr ->
    Doc.fromChars (BuildExit.toString buildErr)
  PublishNotInitialVersion msg ->
    Doc.fromChars ("ERROR: Not initial version: " ++ msg)
  PublishAlreadyPublished msg ->
    Doc.fromChars ("ERROR: Already published: " ++ msg)
  PublishInvalidBump msg ->
    Doc.fromChars ("ERROR: Invalid version bump: " ++ msg)
  PublishCannotGetDocs msg ->
    Doc.fromChars ("ERROR: Cannot get documentation: " ++ msg)
  PublishBadBump msg ->
    Doc.fromChars ("ERROR: Bad version bump: " ++ msg)
  PublishCannotRegister msg ->
    Doc.fromChars ("ERROR: Cannot register package: " ++ msg)
  PublishMustHaveLatestRegistry ->
    Doc.fromChars "ERROR: Must have latest registry"
  PublishNoGit ->
    Doc.fromChars "ERROR: No git repository found"
  PublishWithNoRepositoryLocalName ->
    Doc.fromChars "ERROR: Must specify repository local name for publishing"
  PublishUsingRepositoryLocalNameThatDoesntExistInCustomRepositoryConfig name suggestions ->
    Doc.fromChars ("ERROR: Repository '" ++ name ++ "' not found. Available: " ++ show suggestions)
  PublishToStandardCanopyRepositoryUsingCanopy ->
    Doc.fromChars "ERROR: Use 'elm publish' to publish to standard Canopy repository"

-- | Convert Diff error to Report.
diffToReport :: Diff -> Report
diffToReport err = case err of
  DiffNoOutline ->
    Doc.fromChars "ERROR: No canopy.json found"
  DiffBadOutline msg ->
    Doc.fromChars ("ERROR: Bad outline: " ++ msg)
  DiffApplication ->
    Doc.fromChars "ERROR: Cannot diff applications, only packages"
  DiffCustomReposDataProblem ->
    Doc.fromChars "ERROR: Custom repository data problem"
  DiffMustHaveLatestRegistry ->
    Doc.fromChars "ERROR: Must have latest registry"
  DiffUnknownPackage pkg suggestions ->
    Doc.fromChars ("ERROR: Unknown package '" ++ pkg ++ "'. Suggestions: " ++ show suggestions)
  DiffUnknownVersion msg ->
    Doc.fromChars ("ERROR: Unknown version: " ++ msg)
  DiffDocsProblem msg ->
    Doc.fromChars ("ERROR: Documentation problem: " ++ msg)
  DiffBadDetails path ->
    Doc.fromChars ("ERROR: Cannot load project details from " ++ path)
  DiffBadBuild buildErr ->
    Doc.fromChars (BuildExit.toString buildErr)
  DiffNoExposed ->
    Doc.fromChars "ERROR: No exposed modules in package"

-- | Convert Bump error to Report.
bumpToReport :: Bump -> Report
bumpToReport err = case err of
  BumpNoOutline ->
    Doc.fromChars "ERROR: No canopy.json found"
  BumpBadOutline msg ->
    Doc.fromChars ("ERROR: Bad outline: " ++ msg)
  BumpApplication ->
    Doc.fromChars "ERROR: Cannot bump applications, only packages"
  BumpUnexpectedVersion current suggestions ->
    Doc.fromChars ("ERROR: Unexpected version '" ++ current ++ "'. Expected: " ++ show suggestions)
  BumpCustomRepositoryDataProblem ->
    Doc.fromChars "ERROR: Custom repository data problem"
  BumpMustHaveLatestRegistry ->
    Doc.fromChars "ERROR: Must have latest registry"
  BumpCannotFindDocs msg ->
    Doc.fromChars ("ERROR: Cannot find documentation: " ++ msg)
  BumpBadDetails path ->
    Doc.fromChars ("ERROR: Cannot load project details from " ++ path)
  BumpBuildProblem buildErr ->
    Doc.fromChars (BuildExit.toString buildErr)
  BumpBadBuild buildErr ->
    Doc.fromChars (BuildExit.toString buildErr)
  BumpNoExposed ->
    Doc.fromChars "ERROR: No exposed modules in package"

-- | Convert Install error to Report.
installToReport :: Install -> Report
installToReport err = case err of
  InstallNoOutline ->
    Doc.fromChars "ERROR: No canopy.json found"
  InstallBadOutline msg ->
    Doc.fromChars ("ERROR: Bad outline: " ++ msg)
  InstallBadRegistry msg ->
    Doc.fromChars ("ERROR: Bad registry: " ++ msg)
  InstallBadDetails path ->
    Doc.fromChars ("ERROR: Cannot load project details from " ++ path)
  InstallUnknownPackageOnline pkg suggestions ->
    Doc.fromChars ("ERROR: Unknown package '" ++ pkg ++ "'. Suggestions: " ++ show suggestions)
  InstallUnknownPackageOffline pkg suggestions ->
    Doc.fromChars ("ERROR: Unknown package '" ++ pkg ++ "' (offline). Suggestions: " ++ show suggestions)
  InstallNoOnlinePkgSolution pkg ->
    Doc.fromChars ("ERROR: No dependency solution found for package: " ++ pkg)
  InstallNoOfflinePkgSolution pkg ->
    Doc.fromChars ("ERROR: No offline dependency solution for package: " ++ pkg)
  InstallNoOnlineAppSolution pkg ->
    Doc.fromChars ("ERROR: No dependency solution found for app package: " ++ pkg)
  InstallNoOfflineAppSolution pkg ->
    Doc.fromChars ("ERROR: No offline dependency solution for app package: " ++ pkg)
  InstallHadSolverTrouble msg ->
    Doc.fromChars ("ERROR: Solver trouble: " ++ msg)
  InstallNoArgs canopyHome ->
    Doc.fromChars ("ERROR: No packages specified to install. Canopy home: " ++ canopyHome)
