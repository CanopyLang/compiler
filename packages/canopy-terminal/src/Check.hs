{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Type-check Canopy source files without generating output.
--
-- This module implements the @canopy check@ command, which provides the
-- fastest feedback loop for developers by running the full compilation
-- pipeline (parse, canonicalize, type-check) without emitting any
-- JavaScript or HTML output.
--
-- == Usage
--
-- @
-- canopy check                   -- check all exposed modules
-- canopy check src\/Main.can     -- check specific file
-- canopy check --report=json     -- structured JSON error output
-- @
--
-- == Architecture
--
-- The check command reuses the same compilation infrastructure as @make@
-- but discards all code-generation artifacts.  It follows the same
-- environment-setup / project-load / compile sequence as 'Make', omitting
-- the 'Make.Output.generateOutput' step entirely.
--
-- @since 0.19.1
module Check
  ( -- * Main Interface
    run,

    -- * Types
    Flags (..),
    ReportType (..),

    -- * Parsers
    reportType,
  )
where

import qualified BackgroundWriter as BW
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Compiler
import Data.NonEmptyList (List)
import qualified Data.NonEmptyList as NE
import Logging.Logger (setLogFlag)
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Stuff
import Terminal (Parser (..))

-- | Error reporting format for the check command.
--
-- Currently only JSON is supported as an alternative to the default
-- human-readable terminal output.
data ReportType
  = -- | Structured JSON error output for editor integration
    Json
  deriving (Eq, Show)

-- | Command-line flags for the check command.
--
-- The check command intentionally has fewer flags than @make@ because
-- it never generates output.  Debug\/optimize mode selection is irrelevant
-- here; we always compile in development mode for the fastest feedback.
data Flags = Flags
  { -- | Error reporting format; 'Nothing' uses terminal output
    _checkReport :: !(Maybe ReportType),
    -- | Enable verbose compiler logging
    _checkVerbose :: !Bool
  }
  deriving (Eq, Show)

-- | Type alias for the Task monad parameterised over check errors.
type CheckTask a = Task.Task Exit.Check a

-- | Main entry point for the check command.
--
-- Type-checks the given files (or all exposed modules when no paths are
-- supplied) and reports any errors.  Exits successfully when there are no
-- type errors, even though no output is written to disk.
--
-- @since 0.19.1
run :: [FilePath] -> Flags -> IO ()
run paths flags = do
  style <- resolveReportingStyle (_checkReport flags)
  maybeRoot <- locateProjectRoot (_checkVerbose flags)
  Reporting.attemptWithStyle style Exit.checkToReport $
    case maybeRoot of
      Just root -> executeCheck root paths style
      Nothing -> pure (Left Exit.CheckNoOutline)

-- | Convert the check-specific 'ReportType' to a shared 'Reporting.Style'.
resolveReportingStyle :: Maybe ReportType -> IO Reporting.Style
resolveReportingStyle maybeReport =
  case maybeReport of
    Nothing -> pure Reporting.terminal
    Just Json -> pure Reporting.json

-- | Find the project root directory, enabling verbose logging first.
--
-- Returns 'Nothing' when no @canopy.json@ (or @elm.json@) is found in the
-- current directory or any of its ancestors.
locateProjectRoot :: Bool -> IO (Maybe FilePath)
locateProjectRoot verbose = do
  setLogFlag verbose
  Stuff.findRoot

-- | Execute the full type-check pipeline from a known project root.
--
-- Opens a background-writer scope (a no-op in the current compiler),
-- acquires the root lock, then runs the check task.
executeCheck :: FilePath -> [FilePath] -> Reporting.Style -> IO (Either Exit.Check ())
executeCheck root paths style =
  BW.withScope $ \scope ->
    Stuff.withRootLock root . Task.run $
      coordinateCheck root paths style scope

-- | Coordinate the check task inside the 'CheckTask' monad.
--
-- Loads project details and delegates to the appropriate compilation
-- strategy based on whether explicit file paths were provided.
coordinateCheck ::
  FilePath ->
  [FilePath] ->
  Reporting.Style ->
  BW.Scope ->
  CheckTask ()
coordinateCheck root paths style scope = do
  details <- loadDetailsForCheck style scope root
  let srcDirs = extractSrcDirs details
  dispatchCheckStrategy root srcDirs details paths

-- | Load project details, mapping any loading failure to 'Exit.CheckBadDetails'.
loadDetailsForCheck ::
  Reporting.Style ->
  BW.Scope ->
  FilePath ->
  CheckTask Details.Details
loadDetailsForCheck style scope root = do
  result <- Task.io (Details.load style scope root)
  either (Task.throw . Exit.CheckBadDetails) pure result

-- | Choose between the exposed-module and path-based check strategies.
dispatchCheckStrategy ::
  FilePath ->
  [Compiler.SrcDir] ->
  Details.Details ->
  [FilePath] ->
  CheckTask ()
dispatchCheckStrategy root srcDirs details [] =
  checkExposedModules root srcDirs details
dispatchCheckStrategy root srcDirs details (p : ps) =
  checkFilePaths root srcDirs details (NE.List p ps)

-- | Check all exposed modules for a package project.
--
-- Raises 'Exit.CheckAppNeedsFileNames' for applications, which have no
-- canonical set of exposed modules to derive a target from.
checkExposedModules ::
  FilePath ->
  [Compiler.SrcDir] ->
  Details.Details ->
  CheckTask ()
checkExposedModules root srcDirs details = do
  exposed <- resolveExposedModules details
  let pkg = resolvePkgName details
  result <- Task.io (Compiler.compileFromExposed pkg False root srcDirs exposed)
  either (Task.throw . Exit.CheckCannotBuild) (const (pure ())) result

-- | Check a non-empty list of explicitly specified file paths.
checkFilePaths ::
  FilePath ->
  [Compiler.SrcDir] ->
  Details.Details ->
  List FilePath ->
  CheckTask ()
checkFilePaths root srcDirs details paths = do
  let pkg = resolvePkgName details
      isApp = detailsIsApp details
  result <- Task.io (Compiler.compileFromPaths pkg isApp root srcDirs (NE.toList paths))
  either (Task.throw . Exit.CheckCannotBuild) (const (pure ())) result

-- | Extract the exposed module list from project details.
--
-- Fails with 'Exit.CheckAppNeedsFileNames' for applications and with
-- 'Exit.CheckPkgNeedsExposing' for packages that expose nothing.
resolveExposedModules :: Details.Details -> CheckTask (List ModuleName.Raw)
resolveExposedModules (Details.Details _ validOutline _ _ _ _) =
  case validOutline of
    Details.ValidApp _ ->
      Task.throw Exit.CheckAppNeedsFileNames
    Details.ValidPkg _ [] _ ->
      Task.throw Exit.CheckPkgNeedsExposing
    Details.ValidPkg _ (m : ms) _ ->
      pure (NE.List m ms)

-- | Extract source directories from project details.
extractSrcDirs :: Details.Details -> [Compiler.SrcDir]
extractSrcDirs (Details.Details _ _ _ _ srcDirs _) =
  map Compiler.RelativeSrcDir srcDirs

-- | Extract the package name from project details.
--
-- Returns 'Details.dummyPkgName' for application projects, which have no
-- real package name but still need one for the compiler API.
resolvePkgName :: Details.Details -> Details.PkgName
resolvePkgName (Details.Details _ validOutline _ _ _ _) =
  case validOutline of
    Details.ValidPkg pkgName _ _ -> pkgName
    Details.ValidApp _ -> Details.dummyPkgName

-- | Determine whether project details describe an application.
detailsIsApp :: Details.Details -> Bool
detailsIsApp (Details.Details _ validOutline _ _ _ _) =
  case validOutline of
    Details.ValidApp _ -> True
    Details.ValidPkg _ _ _ -> False

-- | Parser for the @--report@ flag.
--
-- Accepts @"json"@ as the only valid value; any other input produces a
-- parse failure that the Terminal framework turns into a helpful error
-- message pointing users to the valid options.
reportType :: Parser ReportType
reportType =
  Parser
    { _singular = "report type",
      _plural = "report types",
      _parser = parseReportType,
      _suggest = \_ -> pure ["json"],
      _examples = \_ -> pure ["json"]
    }

-- | Parse a report type from the command-line string.
parseReportType :: String -> Maybe ReportType
parseReportType "json" = Just Json
parseReportType _ = Nothing
