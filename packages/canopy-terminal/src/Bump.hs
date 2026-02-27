{-# LANGUAGE OverloadedStrings #-}

-- | Module for version bumping functionality in the Canopy package manager.
--
-- This module provides commands to automatically suggest and apply version
-- bumps based on API changes. It follows semantic versioning principles
-- and integrates with the package registry to ensure proper version management.
--
-- The main entry point is 'run', which analyzes the current package's API
-- changes and suggests appropriate version increments.
--
-- ==== Architecture
--
-- The bump system is organized into several specialized modules:
--   * 'Bump.Types' - Core data types and lenses
--   * 'Bump.Environment' - Environment setup and validation
--   * 'Bump.Validation' - Version validation logic
--   * 'Bump.Analysis' - Documentation analysis and comparison
--   * 'Bump.Operations' - User interaction and file operations
--
-- ==== Workflow
--
-- 1. Initialize environment and validate project structure
-- 2. Check if package is new or exists in registry
-- 3. For new packages: validate initial version is 1.0.0
-- 4. For existing packages: analyze API changes and suggest version
-- 5. Prompt user for confirmation and apply changes
--
-- @since 0.19.1
module Bump
  ( run,
  )
where

import qualified Bump.Analysis as Analysis
import qualified Bump.Environment as Environment
import qualified Bump.Operations as Operations
import Bump.Types (Env, envOutline, envRegistry)
import qualified Bump.Validation as Validation
import Canopy.Package (Name)
import Control.Lens ((^.))
import qualified Data.Maybe as Maybe
import qualified Deps.Registry as Registry
import qualified Reporting
import Reporting.Exit (Bump)
import qualified Reporting.Exit as Exit
import Reporting.Task (Task)
import qualified Reporting.Task as Task

-- | Main entry point for the bump command.
--
-- Analyzes the current package's API changes and suggests appropriate
-- version increments based on semantic versioning principles.
--
-- The function orchestrates the entire bump workflow:
-- 1. Sets up environment
-- 2. Determines if package is new or existing
-- 3. Handles version validation and suggestions accordingly
--
-- @since 0.19.1
run :: () -> () -> IO ()
run () () =
  Reporting.attempt Exit.bumpToReport (Task.run bumpWorkflow)
  where
    bumpWorkflow = Environment.getEnv >>= bump

-- | Performs the version bump operation based on package registry status.
--
-- For existing packages, analyzes API changes and suggests version increments.
-- For new packages, validates the initial version is set to 1.0.0.
--
-- ==== Parameters
--
-- * 'env': Validated bump environment with all necessary context
--
-- ==== Errors
--
-- Throws 'Exit.BumpUnexpectedVersion' if the current version is not suitable for bumping.
--
-- @since 0.19.1
bump :: Env -> Task Bump ()
bump env =
  Maybe.maybe handleNewPackage (handleExistingPackage env) (getPackageVersions env)
  where
    getPackageVersions environment =
      Registry.getVersions' (environment ^. envRegistry) (getPackageName environment)

    handleNewPackage = Task.io (checkNewPackage env)

-- | Handles version bumping for packages that exist in the registry.
--
-- Validates that the current version is suitable for bumping, then
-- analyzes API changes and prompts for version update.
--
-- ==== Parameters
--
-- * 'env': Bump environment
-- * 'knownVersions': List of versions already published in registry
--
-- ==== Errors
--
-- Delegates to validation and analysis modules for specific error handling.
--
-- @since 0.19.1
handleExistingPackage :: Env -> Registry.KnownVersions -> Task Bump ()
handleExistingPackage env knownVersions = do
  Validation.handleExistingPackage env knownVersions
  (newVersion, changes) <- Analysis.suggestVersion env
  Task.io (Operations.promptVersionUpdate env newVersion changes)

-- | Validates version for new packages that haven't been published.
--
-- Delegates to the validation module to handle new package version checking.
--
-- ==== Parameters
--
-- * 'env': Bump environment with package information
--
-- ==== Output
--
-- Prints guidance and validates initial version through validation module.
--
-- @since 0.19.1
checkNewPackage :: Env -> IO ()
checkNewPackage env =
  Validation.checkNewPackage (Validation.getPackageVersion (env ^. envOutline))

-- | Extracts package name from environment.
--
-- Utility function to get the package name for registry operations.
--
-- ==== Parameters
--
-- * 'env': Bump environment
--
-- ==== Returns
--
-- Package name for registry lookups.
--
-- @since 0.19.1
getPackageName :: Env -> Name
getPackageName env = Validation.getPackageName (env ^. envOutline)
