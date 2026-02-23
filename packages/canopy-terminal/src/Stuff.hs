{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Pure utility functions for Terminal.
--
-- Provides filesystem utilities, cache paths, and locking mechanisms
-- without STM/MVar dependencies.
--
-- @since 0.19.1
module Stuff
  ( -- * Project Root
    findRoot,

    -- * Cache Paths
    getReplCache,
    getCanopyCache,
    getPackageCache,
    prepublishDir,
    PackageCache,
    CanopySpecificCache,
    CanopyCustomRepositoryConfigFilePath,

    -- * Repository Config
    getOrCreateCanopyCustomRepositoryConfig,

    -- * Locking
    withRootLock,
  )
where

import qualified System.Directory as Dir
import System.FilePath ((</>))

-- | Filesystem path to the shared package artifact cache (@~\/.canopy\/packages\/@).
type PackageCache = FilePath

-- | Filesystem path to the Canopy-specific cache directory (@~\/.canopy\/@).
type CanopySpecificCache = FilePath

-- | Filesystem path to the custom repository configuration file.
type CanopyCustomRepositoryConfigFilePath = FilePath

-- | Find project root by looking for canopy.json.
findRoot :: IO (Maybe FilePath)
findRoot = do
  cwd <- Dir.getCurrentDirectory
  findRootFrom cwd

-- | Find project root starting from a directory.
findRootFrom :: FilePath -> IO (Maybe FilePath)
findRootFrom dir = do
  let canopyJson = dir </> "canopy.json"
      elmJson = dir </> "elm.json"
  canopyExists <- Dir.doesFileExist canopyJson
  elmExists <- Dir.doesFileExist elmJson
  if canopyExists || elmExists
    then pure (Just dir)
    else do
      let parent = takeDirectory dir
      if parent == dir
        then pure Nothing -- Reached filesystem root
        else findRootFrom parent
  where
    takeDirectory = fst . splitFileName
    splitFileName path =
      let reversed = reverse path
          (name, rest) = break (== '/') reversed
       in (reverse (drop 1 rest), reverse name)

-- | Get REPL cache directory.
getReplCache :: IO FilePath
getReplCache = do
  home <- Dir.getHomeDirectory
  let cache = home </> ".canopy" </> "repl"
  Dir.createDirectoryIfMissing True cache
  pure cache

-- | Get Canopy cache directory (for packages).
getCanopyCache :: IO FilePath
getCanopyCache = do
  home <- Dir.getHomeDirectory
  let cache = home </> ".canopy" </> "packages"
  Dir.createDirectoryIfMissing True cache
  pure cache

-- | Get package cache directory.
getPackageCache :: IO FilePath
getPackageCache = getCanopyCache

-- | Get or create the Canopy custom repository configuration file path.
getOrCreateCanopyCustomRepositoryConfig :: IO CanopyCustomRepositoryConfigFilePath
getOrCreateCanopyCustomRepositoryConfig = do
  home <- Dir.getHomeDirectory
  let configPath = home </> ".canopy" </> "repositories.json"
  Dir.createDirectoryIfMissing True (home </> ".canopy")
  pure configPath

-- | Get the pre-publish staging directory within a project root.
prepublishDir :: FilePath -> FilePath
prepublishDir root = root </> ".canopy" </> "prepublish"

-- | Run action with root lock (simplified, no actual locking).
--
-- In the OLD system, this used MVar for locking. Since we're using
-- the NEW pure compiler, we don't need actual locking anymore.
withRootLock :: FilePath -> IO a -> IO a
withRootLock _root action = action
