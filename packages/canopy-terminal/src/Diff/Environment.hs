{-# LANGUAGE OverloadedStrings #-}

-- | Environment setup and configuration for diff operations.
--
-- This module handles the initialization and setup of the runtime environment
-- required for API difference analysis. It manages package cache, HTTP
-- connections, registry access, and project root detection following
-- CLAUDE.md error handling and modularity patterns.
--
-- == Key Functions
--
-- * 'setup' - Initialize complete diff environment
-- * 'validateRoot' - Verify project root accessibility
-- * 'initializeRegistry' - Set up package registry connections
-- * 'configureCache' - Configure local package caching
--
-- == Error Handling
--
-- All functions use the 'Task' monad for structured error handling:
--
-- * Registry connection failures
-- * Cache initialization problems
-- * Custom repository configuration issues
-- * Network connectivity problems
--
-- == Usage Examples
--
-- @
-- env <- Environment.setup
-- result <- Execution.runDiff env args
-- case result of
--   Right output -> displayOutput output
--   Left err -> reportError err
-- @
--
-- @since 0.19.1
module Diff.Environment
  ( -- * Environment Setup
    setup,

    -- * Validation
    validateRoot,

    -- * Component Initialization
    initializeRegistry,
    configureCache,
    setupNetworking,
  )
where

import Canopy.CustomRepositoryData (CustomRepositoriesData)
import qualified Data.Map.Strict as Map
import Deps.CustomRepositoryDataIO (loadCustomRepositoriesData)
import qualified Deps.Registry as Registry
import Diff.Types (Env (..), Task)
import qualified Http
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Stuff

-- | Initialize complete diff environment.
--
-- Sets up all required components for diff operations:
-- package cache, HTTP manager, registry connections, and root detection.
-- Validates all components and returns ready-to-use environment.
--
-- ==== Examples
--
-- >>> env <- Environment.setup
-- >>> putStrLn "Environment ready for diff operations"
--
-- ==== Error Conditions
--
-- Returns 'Left' for:
--   * Cache initialization failures
--   * Registry connection problems
--   * Network setup issues
--   * Custom repository configuration errors
--
-- @since 0.19.1
setup :: Task Env
setup = do
  maybeRoot <- detectProjectRoot
  cache <- configureCache
  manager <- setupNetworking
  registry <- initializeRegistry manager
  pure (createEnvironment maybeRoot cache manager registry)

-- | Create environment from validated components.
createEnvironment :: Maybe FilePath -> Stuff.PackageCache -> Http.Manager -> Registry.CanopyRegistries -> Env
createEnvironment maybeRoot cache manager registry =
  Env maybeRoot cache manager registry

-- | Detect project root directory.
--
-- Searches for project root using standard Canopy project markers.
-- Returns 'Nothing' if not in a Canopy project directory.
--
-- @since 0.19.1
detectProjectRoot :: Task (Maybe FilePath)
detectProjectRoot = Task.io Stuff.findRoot

-- | Validate project root accessibility.
--
-- Verifies that the detected root directory exists and is accessible
-- for diff operations. Used for validation before performing local diffs.
--
-- @since 0.19.1
validateRoot :: Maybe FilePath -> Task ()
validateRoot Nothing = Task.throw Exit.DiffNoOutline
validateRoot (Just _) = pure () -- Root existence validated by findRoot

-- | Configure local package cache.
--
-- Initializes the package cache for storing downloaded documentation
-- and dependency information. Creates cache directories if needed.
--
-- @since 0.19.1
configureCache :: Task Stuff.PackageCache
configureCache = Task.io Stuff.getPackageCache

-- | Setup HTTP networking for registry access.
--
-- Configures HTTP manager with appropriate timeouts and connection
-- settings for package registry communication.
--
-- @since 0.19.1
setupNetworking :: Task Http.Manager
setupNetworking = Task.io Http.getManager

-- | Initialize package registry connections.
--
-- Sets up connections to package registries with custom repository
-- configuration support. Handles registry data loading and validation.
--
-- @since 0.19.1
initializeRegistry :: Http.Manager -> Task Registry.CanopyRegistries
initializeRegistry manager = do
  canopyCache <- Task.io Stuff.getCanopyCache
  reposConf <- Task.io Stuff.getOrCreateCanopyCustomRepositoryConfig
  reposData <- loadRepositoryData reposConf
  createRegistry manager reposData canopyCache reposConf

-- | Load custom repository data.
loadRepositoryData :: Stuff.CanopyCustomRepositoryConfigFilePath -> Task CustomRepositoriesData
loadRepositoryData reposConf = do
  result <- Task.io (loadCustomRepositoriesData reposConf)
  either (const (Task.throw Exit.DiffCustomReposDataProblem)) pure result

-- | Create registry from validated components.
createRegistry :: Http.Manager -> CustomRepositoriesData -> Stuff.CanopySpecificCache -> Stuff.CanopyCustomRepositoryConfigFilePath -> Task Registry.CanopyRegistries
createRegistry manager reposData canopyCache reposConf = do
  result <- Task.io (Registry.latest manager reposData canopyCache reposConf)
  registry <- either (const (Task.throw Exit.DiffMustHaveLatestRegistry)) pure result
  pure (Registry.CanopyRegistries registry [] Map.empty)
