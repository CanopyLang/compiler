{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

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
    jobsParser,
  )
where

import qualified BackgroundWriter as BW
import qualified Builder.LockFile as LockFile
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Compiler
import Control.Lens ((^.))
import Canopy.Data.NonEmptyList (List)
import qualified Canopy.Data.NonEmptyList as NE
import qualified Data.Text as Text
import qualified Data.Time.Clock as Time
import qualified Logging.Config as Config
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import Make.Builder (buildFromExposed, buildFromPaths, createSplitBuilder, shouldSplitOutput)
import Make.Environment (createBuildContext, getDesiredMode, getReportingStyle, setupEnvironment)
import Make.KernelCheck (detectKernelPackages, emitKernelWarning)
import Make.Output (generateOutput, generateSplitJavaScript)
import Make.Parser (docsFile, jobsParser, output, reportType)
import Make.Types
  ( BuildContext,
    Flags (..),
    Output (..),
    ReportType (..),
    Task,
    bcDetails,
    allowKernel,
    debug,
    docs,
    ffiUnsafe,
    ffiDebug,
    noSplit,
    optimize,
    report,
    verbose,
    verifyReproducible,
    watch,
  )
import qualified Make.Types as Types
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Stuff
import qualified System.FilePath as FilePath
import qualified System.IO as IO
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

-- | Enable verbose logging if the @--verbose@ flag is set.
--
-- Activates DEBUG-level structured logging for all compiler phases,
-- bridging the CLI flag to the environment-variable-based logging system.
enableVerboseLogging :: Flags -> IO ()
enableVerboseLogging flags =
  if flags ^. verbose
    then Config.enableVerbose
    else pure ()

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
  Task.io (Log.logEvent (BuildStarted (Text.pack "Loading project details")))
  Task.io (checkLockFileStaleness root)
  Task.io (warnOnVersionMismatch root)
  checkKernelCodeUsage root flags
  details <- loadProjectDetailsFromRoot style scope root
  mode <- getDesiredMode (flags ^. debug) (flags ^. optimize)
  let ctx = createBuildContext style root details mode (flags ^. ffiUnsafe) (flags ^. ffiDebug)
  startTime <- Task.io Time.getCurrentTime
  executeBuildStrategy ctx paths (flags ^. docs) (flags ^. Types.output) (flags ^. noSplit) (flags ^. verifyReproducible)
  endTime <- Task.io Time.getCurrentTime
  Task.io (reportBuildTiming startTime endTime)

-- | Load project details from root directory.
--
-- Reads project configuration and validates the build environment.
-- Returns loaded details or throws an appropriate error.
loadProjectDetailsFromRoot :: Reporting.Style -> BW.Scope -> FilePath -> Task Details.Details
loadProjectDetailsFromRoot style scope root = do
  result <- Task.io (Details.load style scope root)
  either (Task.throw . Exit.MakeBadDetails) pure result

-- | Execute appropriate build strategy based on input paths.
--
-- Chooses between exposed module builds (packages) and path-based
-- builds (applications) depending on whether paths are provided.
-- When lazy imports are detected and @--no-split@ is not active,
-- routes to the code splitting pipeline.
executeBuildStrategy ::
  BuildContext ->
  [FilePath] ->
  Maybe FilePath ->
  Maybe Output ->
  Bool ->
  Bool ->
  Task ()
executeBuildStrategy ctx [] _maybeDocs maybeOutput forceSingleFile doVerify = do
  Task.io (Log.logEvent (BuildStarted (Text.pack "Building exposed modules (no paths provided)")))
  Task.io (progress "Compiling project...")
  exposed <- getExposedModules (ctx ^. bcDetails)
  let srcDirs = getSrcDirsFromDetails (ctx ^. bcDetails)
  artifacts <- buildFromExposed ctx srcDirs exposed
  emitOutput ctx artifacts maybeOutput forceSingleFile doVerify
executeBuildStrategy ctx (p : ps) _maybeDocs maybeOutput forceSingleFile doVerify = do
  Task.io (Log.logEvent (BuildStarted (Text.pack ("Building from paths: " <> show (p : ps)))))
  Task.io (progress ("Compiling " <> p <> concatPaths ps <> "..."))
  artifacts <- buildFromPaths ctx (NE.List p ps)
  emitOutput ctx artifacts maybeOutput forceSingleFile doVerify

-- | Emit output, choosing between single-file and code-split pipelines.
--
-- When all three conditions are met, routes to the split pipeline:
--
--   1. Lazy import boundaries exist in the compiled artifacts
--   2. The @--no-split@ flag is not active
--   3. The output target is a JS file (not HTML or /dev/null)
--
-- Otherwise falls back to the standard single-file output path.
emitOutput ::
  BuildContext ->
  Compiler.Artifacts ->
  Maybe Output ->
  Bool ->
  Bool ->
  Task ()
emitOutput ctx artifacts maybeOutput forceSingleFile doVerify
  | not forceSingleFile && shouldSplitOutput artifacts && isSplittableTarget maybeOutput = do
      Task.io (Log.logEvent (BuildStarted (Text.pack "Code splitting: lazy imports detected")))
      splitOutput <- createSplitBuilder ctx artifacts
      generateSplitJavaScript ctx splitOutput (splitTargetDir maybeOutput)
  | otherwise =
      generateOutput ctx artifacts maybeOutput doVerify

-- | Check whether the output target supports code splitting.
--
-- Only JS file targets can be split. HTML and /dev/null cannot.
isSplittableTarget :: Maybe Output -> Bool
isSplittableTarget (Just (JS _)) = True
isSplittableTarget Nothing = True
isSplittableTarget _ = False

-- | Derive the output directory for split chunks from the target.
--
-- For explicit JS targets, uses the parent directory. For auto-detected
-- targets, uses the current directory.
splitTargetDir :: Maybe Output -> FilePath
splitTargetDir (Just (JS target)) = FilePath.takeDirectory target
splitTargetDir _ = "."

-- | Check whether the lock file is stale with respect to @canopy.json@.
--
-- Emits a warning log event when the lock file exists but its stored hash
-- does not match the current @canopy.json@ content.  This warns users that
-- their build may not be reproducible without re-running @canopy install@.
--
-- @since 0.19.1
checkLockFileStaleness :: FilePath -> IO ()
checkLockFileStaleness root = do
  maybeLock <- LockFile.readLockFile root
  case maybeLock of
    Nothing -> pure ()
    Just lf -> do
      current <- LockFile.isLockFileCurrent lf root
      if current
        then Log.logEvent (PackageOperation "lock-ok" "canopy.lock is current")
        else Log.logEvent (PackageOperation "lock-stale" "canopy.lock is stale — run 'canopy install' to update")

-- | Warn the user if the project's Canopy version requirement does
-- not match the running compiler.
--
-- Reads the outline and checks 'Details.checkCompilerVersion'. If
-- there is a mismatch, logs a warning event. This is a non-blocking
-- check: the build continues regardless, because version constraints
-- are advisory for now.
--
-- @since 0.19.2
warnOnVersionMismatch :: FilePath -> IO ()
warnOnVersionMismatch root = do
  eitherOutline <- Outline.read root
  either (const (pure ())) checkOutlineVersion eitherOutline
  where
    checkOutlineVersion outline =
      case Details.checkCompilerVersion outline of
        Details.VersionOk -> pure ()
        Details.VersionMismatch required actual ->
          Log.logEvent
            ( PackageOperation
                "version-mismatch"
                ( Text.pack
                    ( "Project requires Canopy "
                        ++ required
                        ++ " but you have "
                        ++ actual
                        ++ " installed"
                    )
                )
            )

-- | Check for third-party packages using legacy kernel code.
--
-- In development mode, emits a prominent warning to stderr. In production
-- mode (@--optimize@), raises a hard error unless @--allow-kernel@ is set.
-- This ensures users are aware of the security implications of kernel code
-- before deploying to production.
--
-- @since 0.19.2
checkKernelCodeUsage :: FilePath -> Flags -> Task ()
checkKernelCodeUsage root flags = do
  kernelPkgs <- Task.io (detectKernelPackages root)
  case kernelPkgs of
    [] -> pure ()
    pkgs
      | flags ^. optimize && not (flags ^. allowKernel) ->
          Task.throw (Exit.MakeKernelCodeInProd pkgs)
      | otherwise ->
          Task.io (emitKernelWarning pkgs)

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

-- | Extract source directories from project details.
--
-- Converts FilePath list to Compiler.SrcDir list for compilation.
getSrcDirsFromDetails :: Details.Details -> [Compiler.SrcDir]
getSrcDirsFromDetails (Details.Details _ _ _ _ srcDirs _) =
  map Compiler.RelativeSrcDir srcDirs

-- | Write a progress message unconditionally to stderr.
--
-- These messages are always shown regardless of verbose/logging settings,
-- so the user can see that the compiler is working.
progress :: String -> IO ()
progress msg = IO.hPutStrLn IO.stderr msg

-- | Report build timing to stderr.
--
-- Shows the elapsed time after compilation completes.
reportBuildTiming :: Time.UTCTime -> Time.UTCTime -> IO ()
reportBuildTiming start end =
  progress ("Success! (" <> formatSeconds elapsed <> ")")
  where
    elapsed = Time.diffUTCTime end start

-- | Format a time difference as seconds with one decimal place.
formatSeconds :: Time.NominalDiffTime -> String
formatSeconds dt =
  show (fromIntegral tenths / 10.0 :: Double) <> "s"
  where
    tenths :: Int
    tenths = round (dt * 10)

-- | Format additional paths for progress message.
concatPaths :: [FilePath] -> String
concatPaths [] = ""
concatPaths ps = " (+" <> show (length ps) <> " more)"
