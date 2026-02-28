{-# LANGUAGE OverloadedStrings #-}

-- | Core diff execution and orchestration logic.
--
-- This module contains the primary execution logic for API difference
-- analysis operations. It coordinates documentation loading, diff
-- computation, and result processing following CLAUDE.md patterns
-- for clear control flow and error handling.
--
-- == Key Functions
--
-- * 'run' - Main execution entry point for all diff operations
-- * 'runGlobal' - Execute global package comparisons
-- * 'runLocal' - Execute local project comparisons
-- * 'runCodeVs' - Execute code vs published comparisons
--
-- == Execution Modes
--
-- The module supports four primary diff execution modes:
--
-- * Global inquiry - Compare two published versions
-- * Local inquiry - Compare local versions in project
-- * Code vs latest - Compare local code against latest published
-- * Code vs specific - Compare local code against specific version
--
-- == Design Pattern
--
-- Each execution function follows the same pattern:
--
-- 1. Load/generate required documentation
-- 2. Perform diff computation
-- 3. Format and output results
-- 4. Handle errors appropriately
--
-- @since 0.19.1
module Diff.Execution
  ( -- * Main Execution
    run,

    -- * Specific Execution Modes
    runGlobal,
    runLocal,
    runCodeVsLatest,
    runCodeVsSpecific,

    -- * Helper Operations
    loadOutlineInfo,
    computeDiff,
  )
where

import Canopy.Docs (Documentation)
import Canopy.Package (Name)
import qualified Canopy.Package as Pkg
import Canopy.Version (Version)
import Control.Lens ((^.))
import qualified Deps.Registry as Registry
import qualified Diff.Documentation as Documentation
import qualified Diff.Outline as Outline
import qualified Diff.Output as Output
import Diff.Types (Args (..), Env, Task, envRegistry)
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task

-- | Main execution entry point for diff operations.
--
-- Dispatches to appropriate execution mode based on command arguments.
-- Provides unified error handling and result processing for all modes.
--
-- ==== Examples
--
-- >>> result <- Execution.run env (CodeVsLatest)
-- >>> case result of
--       Right () -> putStrLn "Diff completed successfully"
--       Left err -> reportError err
--
-- ==== Error Conditions
--
-- Propagates errors from specific execution modes:
--   * Documentation loading failures
--   * Package resolution problems
--   * Diff computation errors
--   * Output formatting issues
--
-- @since 0.19.1
run :: Env -> Args -> Task ()
run env args =
  case args of
    GlobalInquiry name v1 v2 -> runGlobal env name v1 v2
    LocalInquiry v1 v2 -> runLocal env v1 v2
    CodeVsLatest -> runCodeVsLatest env
    CodeVsExactly version -> runCodeVsSpecific env version

-- | Execute global package comparison.
--
-- Compares two published versions of a package from the registry.
-- Loads documentation for both versions and computes differences.
-- Includes a suggested version bump based on the newer version.
--
-- @since 0.19.1
runGlobal :: Env -> Name -> Version -> Version -> Task ()
runGlobal env name v1 v2 = do
  versions <- lookupPackageVersions env name
  oldDocs <- Documentation.getLocal env name versions (min v1 v2)
  newDocs <- Documentation.getLocal env name versions (max v1 v2)
  computeDiff oldDocs newDocs (Just (max v1 v2))

-- | Look up available versions for package.
lookupPackageVersions :: Env -> Name -> Task Registry.KnownVersions
lookupPackageVersions env name =
  case Registry.getVersions' (env ^. envRegistry) name of
    Just versions -> pure versions
    Nothing -> Task.throw (Exit.DiffUnknownPackage (Pkg.toChars name) [])

-- | Execute local project comparison.
--
-- Compares two versions within a local project. Requires valid project
-- outline and registry presence of both versions.
--
-- @since 0.19.1
runLocal :: Env -> Version -> Version -> Task ()
runLocal env v1 v2 = do
  (name, versions) <- loadOutlineInfo env
  oldDocs <- Documentation.getLocal env name versions (min v1 v2)
  newDocs <- Documentation.getLocal env name versions (max v1 v2)
  computeDiff oldDocs newDocs (Just (max v1 v2))

-- | Execute code vs latest comparison.
--
-- Compares local source code against the latest published version.
-- Generates documentation from source and loads latest from registry.
-- Includes a suggested version bump based on the current package version.
--
-- @since 0.19.1
runCodeVsLatest :: Env -> Task ()
runCodeVsLatest env = do
  (name, versions, currentVersion) <- loadOutlineInfoWithVersion env
  oldDocs <- Documentation.getLatest env name versions
  newDocs <- Documentation.generate env
  computeDiff oldDocs newDocs (Just currentVersion)

-- | Execute code vs specific version comparison.
--
-- Compares local source code against a specific published version.
-- Generates documentation from source and loads target version.
-- Includes a suggested version bump based on the current package version.
--
-- @since 0.19.1
runCodeVsSpecific :: Env -> Version -> Task ()
runCodeVsSpecific env version = do
  (name, versions, currentVersion) <- loadOutlineInfoWithVersion env
  oldDocs <- Documentation.getLocal env name versions version
  newDocs <- Documentation.generate env
  computeDiff oldDocs newDocs (Just currentVersion)

-- | Load project outline information.
--
-- Extracts package name and version information from project outline.
-- Validates project structure and registry presence.
--
-- @since 0.19.1
loadOutlineInfo :: Env -> Task (Name, Registry.KnownVersions)
loadOutlineInfo env = do
  outline <- Outline.load env
  packageName <- Outline.extractPackageName outline
  versions <- lookupPackageVersions env packageName
  pure (packageName, versions)

-- | Load project outline information including the current package version.
--
-- Like 'loadOutlineInfo', but also extracts the current version from
-- the package outline. Used by code-vs-published comparisons to
-- suggest a concrete next version number.
--
-- @since 0.19.2
loadOutlineInfoWithVersion :: Env -> Task (Name, Registry.KnownVersions, Version)
loadOutlineInfoWithVersion env = do
  outline <- Outline.load env
  packageName <- Outline.extractPackageName outline
  currentVersion <- Outline.extractPackageVersion outline
  versions <- lookupPackageVersions env packageName
  pure (packageName, versions, currentVersion)

-- | Compute and output diff between documentation sets.
--
-- Performs API difference analysis and formats results for display.
-- When a current version is provided, includes a suggested version
-- bump in the output.
--
-- @since 0.19.1
computeDiff :: Documentation -> Documentation -> Maybe Version -> Task ()
computeDiff oldDocs newDocs maybeVersion =
  case maybeVersion of
    Nothing -> Task.io (Output.display oldDocs newDocs)
    Just version -> Task.io (Output.displayWithVersion oldDocs newDocs version)
