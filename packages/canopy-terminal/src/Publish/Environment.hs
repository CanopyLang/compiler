{-# LANGUAGE OverloadedStrings #-}

-- | Environment initialization for Canopy package publishing.
--
-- This module handles setting up the publishing environment,
-- including loading project configuration, registries, and
-- initializing HTTP managers.
--
-- @since 0.19.1
module Publish.Environment
  ( -- * Environment Setup
    getEnv,
    initGit,
  )
where

import Canopy.CustomRepositoryData (CustomRepositoriesData)
import Canopy.Outline (Outline)
import qualified Canopy.Outline as Outline
import qualified Data.Map.Strict as Map
import Deps.CustomRepositoryDataIO (loadCustomRepositoriesData)
import Deps.Registry (CanopyRegistries)
import qualified Deps.Registry as Registry
import Http (Manager)
import qualified Http
import Publish.Types (Env (..), Git (..))
import Reporting.Exit (Publish)
import qualified Reporting.Exit as Exit
import Reporting.Task (Task)
import qualified Reporting.Task as Task
import Stuff (PackageCache, CanopyCustomRepositoryConfigFilePath, CanopySpecificCache)
import qualified Stuff
import qualified System.Directory as Dir
import System.Exit (ExitCode)
import System.Process (CreateProcess)
import qualified System.Process as Process

-- | Initialize the publishing environment.
--
-- Loads all necessary components including project root, caches, HTTP manager,
-- registries, and project outline. Validates that the project is in a valid
-- state for publishing.
--
-- @since 0.19.1
getEnv :: Task Publish Env
getEnv = do
  root <- findProjectRoot
  cache <- loadPackageCache
  manager <- initHttpManager
  registries <- loadPublishingRegistries manager
  outline <- loadProjectOutline root
  pure (Env root cache manager registries outline)

-- | Find the project root directory.
--
-- @since 0.19.1
findProjectRoot :: Task Publish FilePath
findProjectRoot = do
  maybeRoot <- Task.io Stuff.findRoot
  case maybeRoot of
    Just root -> pure root
    Nothing -> Task.throw Exit.PublishNoOutline

-- | Load the package cache.
--
-- @since 0.19.1
loadPackageCache :: Task Publish PackageCache
loadPackageCache = Task.io Stuff.getPackageCache

-- | Initialize HTTP manager for network requests.
--
-- @since 0.19.1
initHttpManager :: Task Publish Manager
initHttpManager = Task.io Http.getManager

-- | Load publishing registries configuration.
--
-- @since 0.19.1
loadPublishingRegistries :: Manager -> Task Publish CanopyRegistries
loadPublishingRegistries manager = do
  canopyCache <- loadCanopyCache
  reposConfig <- loadRepositoryConfig
  customReposData <- loadCustomRepositoryData reposConfig
  loadLatestRegistries manager customReposData canopyCache reposConfig

-- | Load Canopy cache.
--
-- @since 0.19.1
loadCanopyCache :: Task Publish CanopySpecificCache
loadCanopyCache = Task.io Stuff.getCanopyCache

-- | Load repository configuration.
--
-- @since 0.19.1
loadRepositoryConfig :: Task Publish CanopyCustomRepositoryConfigFilePath
loadRepositoryConfig = Task.io Stuff.getOrCreateCanopyCustomRepositoryConfig

-- | Load custom repository data.
--
-- @since 0.19.1
loadCustomRepositoryData :: CanopyCustomRepositoryConfigFilePath -> Task Publish CustomRepositoriesData
loadCustomRepositoryData config = do
  result <- Task.io (loadCustomRepositoriesData config)
  either (Task.throw . Exit.PublishCustomRepositoryConfigDataError . show) pure result

-- | Load latest registry information.
--
-- @since 0.19.1
loadLatestRegistries :: Manager -> CustomRepositoriesData -> CanopySpecificCache -> CanopyCustomRepositoryConfigFilePath -> Task Publish CanopyRegistries
loadLatestRegistries mgr customData cache config = do
  result <- Task.io (Registry.latest mgr customData cache config)
  registry <- either (const (Task.throw Exit.PublishMustHaveLatestRegistry)) pure result
  pure (Registry.CanopyRegistries registry [] Map.empty)

-- | Load and parse project outline.
--
-- @since 0.19.1
loadProjectOutline :: FilePath -> Task Publish Outline
loadProjectOutline root = do
  result <- Task.io (Outline.read root)
  maybe (Task.throw Exit.PublishNoOutline) pure result

-- | Initialize Git command wrapper.
--
-- Finds the Git executable and creates a wrapper function for running
-- Git commands with proper process handling.
--
-- @since 0.19.1
initGit :: Task Publish Git
initGit = do
  maybeGit <- findGitExecutable
  maybe (Task.throw Exit.PublishNoGit) pure (fmap createGitWrapper maybeGit)
  where
    createGitWrapper gitPath = Git (createGitRunner gitPath)

-- | Find Git executable in PATH.
--
-- @since 0.19.1
findGitExecutable :: Task Publish (Maybe FilePath)
findGitExecutable = Task.io (Dir.findExecutable "git")

-- | Create Git command runner.
--
-- @since 0.19.1
createGitRunner :: FilePath -> [String] -> IO ExitCode
createGitRunner gitPath args =
  let processConfig = createProcessConfig gitPath args
   in Process.withCreateProcess processConfig waitForProcess
  where
    waitForProcess _ _ _ handle = Process.waitForProcess handle

-- | Create process configuration for Git commands.
--
-- @since 0.19.1
createProcessConfig :: FilePath -> [String] -> CreateProcess
createProcessConfig gitPath args =
  (Process.proc gitPath args)
    { Process.std_in = Process.CreatePipe,
      Process.std_out = Process.CreatePipe,
      Process.std_err = Process.CreatePipe
    }
