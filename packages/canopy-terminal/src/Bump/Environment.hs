{-# LANGUAGE OverloadedStrings #-}

-- | Environment setup and initialization for version bumping operations.
--
-- This module handles the construction and validation of the bump environment.
-- It locates the project root, loads necessary caches and registries,
-- and validates that the project is suitable for version bumping.
--
-- The main entry point 'getEnv' performs all necessary setup steps and
-- returns a validated environment or fails with appropriate error messages.
--
-- ==== Workflow
--
-- 1. Find project root directory
-- 2. Load package cache and HTTP manager
-- 3. Load registry configuration
-- 4. Parse canopy.json outline
-- 5. Validate outline is for a package (not application)
--
-- @since 0.19.1
module Bump.Environment
  ( getEnv,
    findProjectRoot,
    loadEnvironmentData,
    validatePackageOutline,
    loadRegistry,
  )
where

import Bump.Types (Env (..))
import Canopy.Outline (Outline)
import qualified Canopy.Outline as Outline
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import Deps.CustomRepositoryDataIO (loadCustomRepositoriesData)
import qualified Deps.Registry as Registry
import qualified Http
import Reporting.Exit (Bump (BumpCustomRepositoryDataProblem))
import qualified Reporting.Exit as Exit
import Reporting.Task (Task)
import qualified Reporting.Task as Task
import qualified Stuff

-- | Constructs the environment needed for version bumping operations.
--
-- Locates the project root, loads package cache and registry information,
-- and validates that we're working with a package (not an application).
--
-- ==== Steps
--
-- 1. Find project root containing canopy.json
-- 2. Load all required environment data
-- 3. Validate we have a package outline
--
-- ==== Errors
--
-- Throws various 'Exit.Bump' errors for:
--   * Missing project root or canopy.json
--   * Registry access failures
--   * Application projects (bump only works on packages)
--
-- @since 0.19.1
getEnv :: Task Exit.Bump Env
getEnv =
  findProjectRoot >>= loadEnvironmentData >>= validatePackageOutline

-- | Locates the project root directory containing canopy.json.
--
-- Searches upward from current directory to find a valid Canopy project root.
-- The root must contain a valid canopy.json file.
--
-- ==== Errors
--
-- Throws 'Exit.BumpNoOutline' if no project root is found.
--
-- @since 0.19.1
findProjectRoot :: Task Exit.Bump FilePath
findProjectRoot = do
  maybeRoot <- Task.io Stuff.findRoot
  Maybe.maybe (Task.throw Exit.BumpNoOutline) pure maybeRoot

-- | Loads all necessary data for the bump environment.
--
-- Collects package cache, HTTP manager, registry configuration,
-- and project outline in preparation for environment construction.
--
-- ==== Parameters
--
-- * 'root': Project root directory path
--
-- ==== Returns
--
-- Tuple containing all loaded environment components ready for validation.
--
-- @since 0.19.1
loadEnvironmentData ::
  FilePath ->
  Task Exit.Bump (FilePath, Stuff.PackageCache, Http.Manager, Registry.CanopyRegistries, Outline)
loadEnvironmentData root = do
  cache <- Task.io Stuff.getPackageCache
  manager <- Task.io Http.getManager
  registry <- loadRegistry manager
  eitherOutline <- Task.io (Outline.read root)
  outline <- either (Task.throw . Exit.BumpBadOutline) pure eitherOutline
  pure (root, cache, manager, registry, outline)

-- | Loads registry configuration with custom repositories.
--
-- Sets up the complete registry configuration including any custom
-- repository definitions. Ensures we have the latest registry data.
--
-- ==== Parameters
--
-- * 'manager': HTTP manager for network operations
--
-- ==== Errors
--
-- Throws registry-related errors if configuration cannot be loaded.
--
-- @since 0.19.1
loadRegistry :: Http.Manager -> Task Exit.Bump Registry.CanopyRegistries
loadRegistry manager = do
  canopyCache <- Task.io Stuff.getCanopyCache
  reposConfig <- Task.io Stuff.getOrCreateCanopyCustomRepositoryConfig
  customReposResult <- Task.io (loadCustomRepositoriesData reposConfig)
  customRepos <- either (const (Task.throw BumpCustomRepositoryDataProblem)) pure customReposResult
  registryResult <- Task.io (Registry.latest manager customRepos canopyCache reposConfig)
  registry <- either (const (Task.throw Exit.BumpMustHaveLatestRegistry)) pure registryResult
  pure (Registry.CanopyRegistries registry [] Map.empty)

-- | Validates that the outline represents a package and constructs the environment.
--
-- Version bumping only works on packages, not applications. This function
-- ensures we have a package outline and constructs the final environment.
--
-- ==== Parameters
--
-- * Tuple containing all loaded environment data
--
-- ==== Errors
--
-- Throws 'Exit.BumpApplication' if the project is an application.
--
-- @since 0.19.1
validatePackageOutline ::
  (FilePath, Stuff.PackageCache, Http.Manager, Registry.CanopyRegistries, Outline) ->
  Task Exit.Bump Env
validatePackageOutline (root, cache, manager, registry, outline) =
  case outline of
    Outline.App _ -> Task.throw Exit.BumpApplication
    Outline.Workspace _ -> Task.throw Exit.BumpApplication
    Outline.Pkg pkgOutline -> pure (Env root cache manager registry pkgOutline)
