{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Documentation analysis for determining appropriate version bumps.
--
-- This module handles the analysis of API changes by comparing documentation
-- between the current version and the new version being prepared. It generates
-- documentation for the current state and retrieves previous documentation
-- from the registry for comparison.
--
-- The analysis determines whether changes require major, minor, or patch
-- version increments according to semantic versioning principles.
--
-- ==== Process
--
-- 1. Retrieve documentation for previous version from registry
-- 2. Generate documentation for current package state
-- 3. Compare documentation to identify API changes
-- 4. Suggest appropriate version increment
--
-- @since 0.19.1
module Bump.Analysis
  ( suggestVersion,
    analyzeDocs,
    generateDocs,
    loadPackageDetails,
    buildDocumentation,
  )
where

import qualified BackgroundWriter as BW
import qualified Build
import Bump.Types (Env, envCache, envManager, envOutline, envRegistry, envRoot)
import qualified Canopy.Details as Details
import Canopy.Docs (Documentation)
import qualified Canopy.ModuleName as ModuleName
import Canopy.Outline (PkgOutline (..))
import qualified Canopy.Outline as Outline
import Canopy.Package (Name)
import Canopy.Version (Version)
import Control.Lens ((^.))
import qualified Data.NonEmptyList as NE
import qualified Deps.Diff as Diff
import qualified Reporting
import qualified Reporting.Exit as Exit
import Reporting.Task (Task)
import qualified Reporting.Task as Task

-- | Suggests appropriate version bump based on API changes.
--
-- Analyzes differences between old and new documentation to determine
-- the semantic version increment required (major, minor, or patch).
-- Returns the suggested new version and change information.
--
-- ==== Parameters
--
-- * 'env': Bump environment containing all necessary context
--
-- ==== Returns
--
-- Task that yields the new version and package changes for user confirmation.
--
-- @since 0.19.1
suggestVersion :: Env -> Task Exit.Bump (Version, Diff.PackageChanges)
suggestVersion env = do
  (oldDocs, newDocs) <- analyzeDocs env
  let changes = Diff.diff oldDocs newDocs
  let newVersion = Diff.bump changes (getPackageVersion (env ^. envOutline))
  pure (newVersion, changes)
  where
    getPackageVersion (PkgOutline _ _ _ version _ _ _ _) = version

-- | Analyzes documentation differences between versions.
--
-- Retrieves documentation for the current published version and generates
-- documentation for the new version, preparing them for comparison.
--
-- ==== Parameters
--
-- * 'env': Bump environment with registry and package information
--
-- ==== Returns
--
-- Tuple of (old documentation, new documentation) for comparison.
--
-- ==== Errors
--
-- Throws 'Exit.BumpCannotFindDocs' if previous documentation cannot be retrieved.
--
-- @since 0.19.1
analyzeDocs :: Env -> Task Exit.Bump (Documentation, Documentation)
analyzeDocs env = do
  let outline@(PkgOutline pkg _ _ vsn _ _ _ _) = env ^. envOutline
  oldDocsResult <- Task.io (getDocs env pkg vsn)
  oldDocs <- case oldDocsResult of
    Left docsProblem -> Task.throw (Exit.BumpCannotFindDocs pkg vsn docsProblem)
    Right docs -> pure docs
  newDocs <- generateDocs (env ^. envRoot) outline
  pure (oldDocs, newDocs)

-- | Retrieves documentation for a specific package version.
--
-- Fetches documentation from the registry for the specified package and version.
--
-- ==== Parameters
--
-- * 'env': Environment with cache, registry, and HTTP manager
-- * 'pkg': Package name
-- * 'vsn': Version to retrieve documentation for
--
-- ==== Returns
--
-- IO action that retrieves the documentation or fails with error.
--
-- @since 0.19.1
getDocs :: Env -> Name -> Version -> IO (Either Exit.DocsProblem Documentation)
getDocs env pkg vsn =
  Diff.getDocs (env ^. envCache) (env ^. envRegistry) (env ^. envManager) pkg vsn

-- | Generates documentation for the current package version.
--
-- Loads package details and builds documentation from exposed modules.
-- Requires at least one exposed module to generate documentation.
--
-- ==== Parameters
--
-- * 'root': Project root directory
-- * 'outline': Package outline with exposed modules
--
-- ==== Errors
--
-- Throws various errors for invalid package state or build failures.
--
-- @since 0.19.1
generateDocs :: FilePath -> PkgOutline -> Task Exit.Bump Documentation
generateDocs root outline =
  loadPackageDetails root >>= buildDocumentation root outline

-- | Loads package details required for documentation generation.
--
-- Reads and validates package details from the project directory.
-- This includes dependency information and module structure.
--
-- ==== Parameters
--
-- * 'root': Project root directory
--
-- ==== Errors
--
-- Throws 'Exit.BumpBadDetails' if package details cannot be loaded.
--
-- @since 0.19.1
loadPackageDetails :: FilePath -> Task Exit.Bump Details.Details
loadPackageDetails root =
  Task.eio Exit.BumpBadDetails (BW.withScope loadDetails)
  where
    loadDetails scope = Details.load Reporting.silent scope root

-- | Builds documentation from package outline and details.
--
-- Generates documentation for all exposed modules in the package.
-- Requires at least one exposed module to proceed.
--
-- ==== Parameters
--
-- * 'root': Project root directory
-- * 'outline': Package outline with exposed modules
-- * 'details': Loaded package details
--
-- ==== Errors
--
-- Throws 'Exit.BumpNoExposed' if no modules are exposed.
-- Throws 'Exit.BumpBadBuild' if documentation build fails.
--
-- @since 0.19.1
buildDocumentation :: FilePath -> PkgOutline -> Details.Details -> Task Exit.Bump Documentation
buildDocumentation root (PkgOutline _ _ _ _ exposed _ _ _) details =
  case Outline.flattenExposed exposed of
    [] -> Task.throw Exit.BumpNoExposed
    (e : es) -> do
      buildResult <- Task.io (buildFromExposed root details e es)
      case buildResult of
        Left buildProblem -> Task.throw (Exit.BumpBadBuild buildProblem)
        Right docs -> pure docs

-- | Builds documentation from exposed modules.
--
-- Uses the build system to generate documentation for the specified modules.
--
-- ==== Parameters
--
-- * 'root': Project root directory
-- * 'details': Package details
-- * 'firstModule': First exposed module
-- * 'otherModules': Additional exposed modules
--
-- ==== Returns
--
-- IO action that builds documentation or fails with error.
--
-- @since 0.19.1
buildFromExposed :: FilePath -> Details.Details -> ModuleName.Raw -> [ModuleName.Raw] -> IO (Either Exit.BuildProblem Documentation)
buildFromExposed root details e es =
  Build.fromExposed Reporting.silent root details Build.KeepDocs (NE.List e es)
