{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Build system for Canopy projects.
--
-- This module provides the main build functionality for Canopy projects,
-- including compilation, optimization, and code generation. It supports
-- multiple output formats (JavaScript, HTML) and various build modes.
--
-- The module has been refactored into specialized sub-modules following
-- CLAUDE.md guidelines for maintainability and single responsibility:
--
--   * 'Make.Types' - Core types and data structures
--   * 'Make.Environment' - Environment setup and validation
--   * 'Make.Parser' - Command line argument parsers
--   * 'Make.Builder' - Code generation and building
--   * 'Make.Output' - Output generation and target handling
--   * 'Make.Generation' - File generation utilities
--
-- Key features:
--   * Incremental compilation
--   * Multiple output formats (JS, HTML, /dev/null)
--   * Development and production modes
--   * File watching for continuous builds
--   * Comprehensive error reporting
--
-- @since 0.19.1
module Make
  ( -- * Types
    Flags (..),
    Output (..),
    ReportType (..),

    -- * Main Interface
    run,

    -- * Parsers
    reportType,
    output,
    docsFile,
  )
where

import qualified BackgroundWriter as BW
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import Control.Lens ((^.))
import Data.NonEmptyList (List)
import qualified Data.NonEmptyList as NE
import Logging.Logger (printLog, setLogFlag)
import Make.Builder (buildFromExposed, buildFromPaths)
import Make.Environment (createBuildContext, getDesiredMode, getReportingStyle, setupEnvironment)
import Make.Output (generateOutput)
import Make.Parser (docsFile, output, reportType)
import Make.Types
  ( BuildContext,
    Flags (..),
    Output,
    ReportType (..),
    Task,
    bcDetails,
    debug,
    docs,
    optimize,
    report,
    verbose,
    watch,
  )
import qualified Make.Types as Types
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Stuff
import qualified Watch

-- | Main entry point for the Make system.
--
-- Handles file watching if enabled, otherwise runs a single build.
-- This is the top-level orchestration function that delegates to
-- specialized modules based on the configuration.
--
-- @
-- run [\"src/Main.elm\"] (Flags False True False Nothing Nothing Nothing False)
-- @
run :: [FilePath] -> Flags -> IO ()
run paths flags =
  if flags ^. watch
    then watchAndBuild paths flags
    else runSingleBuild paths flags

-- | Run build with file watching enabled.
--
-- Sets up file watching to trigger rebuilds when source files change.
-- Provides continuous feedback during development.
watchAndBuild :: [FilePath] -> Flags -> IO ()
watchAndBuild paths flags =
  Watch.files (const (runSingleBuild paths flags)) paths

-- | Run a single build without file watching.
--
-- Performs complete build setup, validation, and execution.
-- Reports errors using the configured reporting style.
runSingleBuild :: [FilePath] -> Flags -> IO ()
runSingleBuild paths flags = do
  enableVerboseLogging flags
  style <- getReportingStyle (flags ^. report)
  maybeRoot <- setupEnvironment flags
  Reporting.attemptWithStyle style Exit.makeToReport $
    case maybeRoot of
      Just root -> executeBuildWithRoot root paths flags style
      Nothing -> pure (Left Exit.MakeNoOutline)

-- | Enable verbose logging if requested.
--
-- Configures the logger based on the verbose flag from command line.
-- Must be called before any logging operations.
enableVerboseLogging :: Flags -> IO ()
enableVerboseLogging flags =
  setLogFlag (flags ^. verbose)

-- | Execute the complete build process with root path.
--
-- Coordinates between environment setup, project loading, and build
-- execution. This is the main build orchestration function.
executeBuildWithRoot :: FilePath -> [FilePath] -> Flags -> Reporting.Style -> IO (Either Exit.Make ())
executeBuildWithRoot root paths flags style =
  BW.withScope $ \scope ->
    Stuff.withRootLock root . Task.run $
      coordinateBuildWithRoot root paths flags style scope

-- | Coordinate the build process with proper resource management.
--
-- Loads project details, creates build context, and delegates to
-- appropriate build strategy based on input paths.
coordinateBuildWithRoot :: FilePath -> [FilePath] -> Flags -> Reporting.Style -> BW.Scope -> Task ()
coordinateBuildWithRoot root paths flags style scope = do
  Task.io (printLog "Loading project details")
  details <- loadProjectDetailsFromRoot style scope root
  mode <- getDesiredMode (flags ^. debug) (flags ^. optimize)
  let ctx = createBuildContext style root details mode
  executeBuildStrategy ctx paths (flags ^. docs) (flags ^. Types.output)

-- | Load project details from root directory.
--
-- Reads project configuration and validates the build environment.
-- Returns loaded details or throws an appropriate error.
loadProjectDetailsFromRoot :: Reporting.Style -> BW.Scope -> FilePath -> Task Details.Details
loadProjectDetailsFromRoot style scope root =
  Task.eio Exit.MakeBadDetails $
    Details.load style scope root

-- | Execute appropriate build strategy based on input paths.
--
-- Chooses between exposed module builds (packages) and path-based
-- builds (applications) depending on whether paths are provided.
executeBuildStrategy ::
  BuildContext ->
  [FilePath] ->
  Maybe FilePath ->
  Maybe Output ->
  Task ()
executeBuildStrategy ctx [] maybeDocs _maybeOutput = do
  Task.io (printLog "Building exposed modules (no paths provided)")
  exposed <- getExposedModules (ctx ^. bcDetails)
  buildFromExposed ctx exposed maybeDocs
executeBuildStrategy ctx (p : ps) _maybeDocs maybeOutput = do
  Task.io (printLog ("Building from paths: " <> show (p : ps)))
  artifacts <- buildFromPaths ctx (NE.List p ps)
  generateOutput ctx artifacts maybeOutput

-- | Extract exposed modules from project details.
--
-- Validates that the project has exposed modules and returns them
-- as a non-empty list. Throws appropriate errors for invalid projects.
getExposedModules :: Details.Details -> Task (List ModuleName.Raw)
getExposedModules (Details.Details _ validOutline _ _ _ _) =
  case validOutline of
    Details.ValidApp _ ->
      Task.throw Exit.MakeAppNeedsFileNames
    Details.ValidPkg _ exposed _ ->
      case exposed of
        [] -> Task.throw Exit.MakePkgNeedsExposing
        m : ms -> pure (NE.List m ms)
