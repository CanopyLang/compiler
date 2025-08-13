{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

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
import Deps.CustomRepositoryDataIO (loadCustomRepositoriesData)
import Deps.Registry (ZokkaRegistries)
import qualified Deps.Registry as Registry
import Http (Manager)
import qualified Http
import Publish.Types (Env (..), Git (..))
import Reporting.Exit (Publish)
import qualified Reporting.Exit as Exit
import Reporting.Task (Task)
import qualified Reporting.Task as Task
import Stuff (PackageCache, ZokkaSpecificCache, ZokkaCustomRepositoryConfigFilePath)
import qualified Stuff
import qualified System.Directory as Dir
import System.Process (CreateProcess)
import qualified System.Process as Process
import System.Exit (ExitCode)

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
findProjectRoot = Task.mio Exit.PublishNoOutline Stuff.findRoot

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
loadPublishingRegistries :: Manager -> Task Publish ZokkaRegistries
loadPublishingRegistries manager = do
  zokkaCache <- loadZokkaCache
  reposConfig <- loadRepositoryConfig
  customReposData <- loadCustomRepositoryData reposConfig
  loadLatestRegistries manager customReposData zokkaCache reposConfig

-- | Load Zokka cache.
--
-- @since 0.19.1
loadZokkaCache :: Task Publish ZokkaSpecificCache
loadZokkaCache = Task.io Stuff.getZokkaCache

-- | Load repository configuration.
--
-- @since 0.19.1
loadRepositoryConfig :: Task Publish ZokkaCustomRepositoryConfigFilePath
loadRepositoryConfig = Task.io Stuff.getOrCreateZokkaCustomRepositoryConfig

-- | Load custom repository data.
--
-- @since 0.19.1
loadCustomRepositoryData :: ZokkaCustomRepositoryConfigFilePath -> Task Publish CustomRepositoriesData
loadCustomRepositoryData = Task.eio Exit.PublishCustomRepositoryConfigDataError . loadCustomRepositoriesData

-- | Load latest registry information.
--
-- @since 0.19.1
loadLatestRegistries :: Manager -> CustomRepositoriesData -> ZokkaSpecificCache -> ZokkaCustomRepositoryConfigFilePath -> Task Publish ZokkaRegistries
loadLatestRegistries mgr customData cache config =
  Task.eio Exit.PublishMustHaveLatestRegistry (Registry.latest mgr customData cache config)

-- | Load and parse project outline.
--
-- @since 0.19.1
loadProjectOutline :: FilePath -> Task Publish Outline
loadProjectOutline root = Task.eio Exit.PublishBadOutline (Outline.read root)

-- | Initialize Git command wrapper.
--
-- Finds the Git executable and creates a wrapper function for running
-- Git commands with proper process handling.
--
-- @since 0.19.1
initGit :: Task Publish Git
initGit = do
  maybeGit <- findGitExecutable
  maybe (Task.throw Exit.PublishNoGit) (pure . Git . createGitRunner) maybeGit

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