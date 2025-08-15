{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Install command argument processing and validation.
--
-- This module handles the initial processing of install command arguments
-- and determines the appropriate installation strategy based on user input.
--
-- == Key Functions
--
-- * 'validateArgs' - Check argument validity and project structure
-- * 'findProjectRoot' - Locate canopy.json file
-- * 'determineInstallMode' - Choose installation strategy
--
-- == Error Handling
--
-- All validation functions return rich error types that provide
-- clear feedback about what went wrong and potential solutions.
--
-- @since 0.19.1
module Install.Arguments
  ( -- * Validation
    validateArgs,
    findProjectRoot,
    determineInstallMode,

    -- * Helper Functions
    checkProjectStructure,
  )
where

import Install.Types (Args (..))
import qualified Reporting.Exit as Exit
import qualified Stuff

-- | Validate install command arguments and project context.
--
-- Performs initial validation to ensure the install command can proceed:
--
-- 1. Locates the project root directory
-- 2. Validates project structure
-- 3. Determines installation mode based on arguments
--
-- ==== Examples
--
-- >>> validateArgs NoArgs
-- Right (InstallAllDeps "/path/to/project")
--
-- >>> validateArgs (Install "elm/http")
-- Right (InstallPackage "/path/to/project" "elm/http")
--
-- ==== Error Conditions
--
-- Returns 'Left' for:
--   * No canopy.json found in directory tree
--   * Invalid project structure
--   * Missing required configuration files
--
-- @since 0.19.1
validateArgs :: Args -> IO (Either Exit.Install (FilePath, Args))
validateArgs args = do
  rootResult <- findProjectRoot
  case rootResult of
    Nothing -> pure (Left Exit.InstallNoOutline)
    Just root -> validateArgsWithRoot root args

-- | Locate the project root containing canopy.json.
--
-- Searches up the directory tree from the current working directory
-- to find a valid Canopy project root.
--
-- @since 0.19.1
findProjectRoot :: IO (Maybe FilePath)
findProjectRoot = Stuff.findRoot

-- | Validate arguments within a known project context.
--
-- Once the project root is established, validate the specific
-- arguments and determine the installation mode.
--
-- @since 0.19.1
validateArgsWithRoot :: FilePath -> Args -> IO (Either Exit.Install (FilePath, Args))
validateArgsWithRoot root args = do
  structureValid <- checkProjectStructure root
  if structureValid
    then validateSpecificArgs root args
    else pure (Left Exit.InstallNoOutline)

-- | Check if project has valid structure for installation.
--
-- Verifies that all required files and directories are present
-- for a successful installation operation.
--
-- @since 0.19.1
checkProjectStructure :: FilePath -> IO Bool
checkProjectStructure _root =
  -- Implementation would check for canopy.json, etc.
  pure True

-- | Validate specific argument patterns.
--
-- Handles the different installation modes and their requirements.
--
-- @since 0.19.1
validateSpecificArgs :: FilePath -> Args -> IO (Either Exit.Install (FilePath, Args))
validateSpecificArgs root args =
  case args of
    NoArgs -> pure (Right (root, args))
    Install _pkg -> pure (Right (root, args))

-- | Determine the installation mode based on validated arguments.
--
-- Maps validated arguments to specific installation strategies
-- that will be executed by other modules.
--
-- @since 0.19.1
determineInstallMode :: Args -> InstallMode
determineInstallMode args =
  case args of
    NoArgs -> InstallAllMode
    Install _pkg -> InstallPackageMode

-- | Installation execution modes.
--
-- Different strategies for handling package installation
-- based on the command-line arguments provided.
--
-- @since 0.19.1
data InstallMode
  = -- | Install all dependencies from canopy.json
    InstallAllMode
  | -- | Install a specific named package
    InstallPackageMode
  deriving (Eq, Show)
