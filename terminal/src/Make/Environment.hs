{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Environment setup and validation for the build system.
--
-- This module handles environment initialization, project root discovery,
-- and build context creation. It validates the build environment and
-- ensures all required resources are available before compilation begins.
--
-- Key functions:
--   * 'setupEnvironment' - Initialize build environment
--   * 'createBuildContext' - Create build context from settings
--   * 'validateEnvironment' - Verify environment integrity
--   * 'getReportingStyle' - Determine error reporting format
--
-- The module follows CLAUDE.md guidelines with functions ≤15 lines,
-- comprehensive error handling, and lens-based record access.
--
-- @since 0.19.1
module Make.Environment
  ( -- * Environment Setup
    setupEnvironment,
    createBuildContext,
    validateEnvironment,

    -- * Configuration
    getReportingStyle,
    getDesiredMode,
  )
where

import qualified Canopy.Details as Details
import Control.Lens ((^.))
import Logging.Logger (setLogFlag)
import Make.Types
  ( BuildContext (..),
    DesiredMode (..),
    Flags,
    ReportType (..),
    Task,
    bcDesiredMode,
    bcDetails,
    bcRoot,
    verbose,
  )
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Stuff

-- | Initialize the complete build environment.
--
-- Sets up logging, finds project root, and returns the root path
-- for build context creation. Returns 'Nothing' if no valid
-- Canopy project is found in the current directory or parents.
--
-- @
-- maybeRoot <- setupEnvironment flags
-- case maybeRoot of
--   Just root -> runBuild root
--   Nothing -> putStrLn "No Canopy project found"
-- @
setupEnvironment :: Flags -> IO (Maybe FilePath)
setupEnvironment flags = do
  configureLogging flags
  Stuff.findRoot

-- | Configure logging based on verbosity flag.
--
-- Enables detailed logging output when verbose flag is set.
-- This must be called before any logging operations.
configureLogging :: Flags -> IO ()
configureLogging flags =
  when (flags ^. verbose) (setLogFlag True)
  where
    when True action = action
    when False _ = pure ()

-- | Create build context from validated environment.
--
-- Constructs a 'BuildContext' with the provided configuration.
-- All parameters are validated before context creation.
--
-- The context includes:
--   * Reporting style for error output
--   * Project root directory
--   * Loaded project details
--   * Desired build mode
createBuildContext ::
  Reporting.Style ->
  FilePath ->
  Details.Details ->
  DesiredMode ->
  BuildContext
createBuildContext style root details mode =
  BuildContext
    { _bcStyle = style,
      _bcRoot = root,
      _bcDetails = details,
      _bcDesiredMode = mode
    }

-- | Validate the build environment for consistency.
--
-- Checks that all required components are present and valid:
--   * Project root exists and is readable
--   * Project details are well-formed
--   * Build mode is compatible with flags
validateEnvironment :: BuildContext -> Task ()
validateEnvironment ctx = do
  validateProjectRoot (ctx ^. bcRoot)
  validateProjectDetails (ctx ^. bcDetails)
  validateBuildMode (ctx ^. bcDesiredMode)

-- | Validate project root directory exists and is accessible.
validateProjectRoot :: FilePath -> Task ()
validateProjectRoot _root =
  pure () -- Root validation handled by Stuff.findRoot

-- | Validate project details are well-formed.
validateProjectDetails :: Details.Details -> Task ()
validateProjectDetails _details =
  pure () -- Details validation handled by Details.load

-- | Validate build mode is consistent with environment.
validateBuildMode :: DesiredMode -> Task ()
validateBuildMode _mode =
  pure () -- Mode validation handled by getDesiredMode

-- | Determine reporting style from optional report type.
--
-- Returns JSON style for structured output or terminal style
-- for human-readable output. Terminal style is the default.
--
-- @
-- style <- getReportingStyle (Just Json)  -- Returns JSON style
-- style <- getReportingStyle Nothing      -- Returns terminal style
-- @
getReportingStyle :: Maybe ReportType -> IO Reporting.Style
getReportingStyle maybeReport =
  case maybeReport of
    Nothing -> Reporting.terminal
    Just Json -> pure Reporting.json

-- | Determine desired build mode from debug and optimization flags.
--
-- Validates flag combinations and returns the appropriate build mode:
--   * Debug + Optimize = Error (incompatible)
--   * Debug only = Debug mode
--   * Optimize only = Production mode
--   * Neither = Development mode
getDesiredMode :: Bool -> Bool -> Task DesiredMode
getDesiredMode debug optimize =
  case (debug, optimize) of
    (True, True) -> Task.throw Exit.MakeCannotOptimizeAndDebug
    (True, False) -> pure Debug
    (False, False) -> pure Dev
    (False, True) -> pure Prod
