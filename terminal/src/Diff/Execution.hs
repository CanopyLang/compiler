{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

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
--
-- @since 0.19.1
runGlobal :: Env -> Name -> Version -> Version -> Task ()
runGlobal env name v1 v2 = do
  versions <- lookupPackageVersions env name
  oldDocs <- Documentation.getLocal env name versions (min v1 v2)
  newDocs <- Documentation.getLocal env name versions (max v1 v2)
  computeDiff oldDocs newDocs

-- | Look up available versions for package.
lookupPackageVersions :: Env -> Name -> Task Registry.KnownVersions
lookupPackageVersions env name =
  case Registry.getVersions' name (env ^. envRegistry) of
    Right versions -> pure versions
    Left suggestions -> Task.throw (Exit.DiffUnknownPackage name suggestions)

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
  computeDiff oldDocs newDocs

-- | Execute code vs latest comparison.
--
-- Compares local source code against the latest published version.
-- Generates documentation from source and loads latest from registry.
--
-- @since 0.19.1
runCodeVsLatest :: Env -> Task ()
runCodeVsLatest env = do
  (name, versions) <- loadOutlineInfo env
  oldDocs <- Documentation.getLatest env name versions
  newDocs <- Documentation.generate env
  computeDiff oldDocs newDocs

-- | Execute code vs specific version comparison.
--
-- Compares local source code against a specific published version.
-- Generates documentation from source and loads target version.
--
-- @since 0.19.1
runCodeVsSpecific :: Env -> Version -> Task ()
runCodeVsSpecific env version = do
  (name, versions) <- loadOutlineInfo env
  oldDocs <- Documentation.getLocal env name versions version
  newDocs <- Documentation.generate env
  computeDiff oldDocs newDocs

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

-- | Compute and output diff between documentation sets.
--
-- Performs API difference analysis and formats results for display.
-- Handles diff computation and output formatting in a single operation.
--
-- @since 0.19.1
computeDiff :: Documentation -> Documentation -> Task ()
computeDiff oldDocs newDocs =
  Task.io (Output.display oldDocs newDocs)
