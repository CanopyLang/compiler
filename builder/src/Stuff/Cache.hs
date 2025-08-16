{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Cache management and storage for the Canopy compiler build system.
--
-- This module provides cache management functionality including package cache
-- creation, Zokka-specific cache handling, and package override management.
--
-- The cache system uses version isolation and multi-compiler support to prevent
-- conflicts between Canopy and Zokka compilers.
--
-- == Cache Architecture
--
-- @
-- ~/.canopy/VERSION/
-- ├── packages/              -- Main package cache
-- ├── repl/                  -- REPL session cache
-- ├── canopy/               -- Zokka configuration
-- └── canopy-cache-VERSION/  -- Zokka-specific cache
-- @
--
-- @since 0.19.1
module Stuff.Cache
  ( -- * Cache Types
    PackageCache (..)
  , ZokkaSpecificCache (..)
  , PackageOverridesCache (..)
  , PackageOverrideConfig (..)
  , ZokkaCustomRepositoryConfigFilePath (..)
    -- * Cache Lenses
  , packageCacheFilePath
  , zokkaSpecificCacheFilePath
  , packageOverridesCacheFilePath
    -- * Cache Creation
  , getPackageCache
  , getZokkaCache
  , getPackageOverridesCache
  , getReplCache
  , getCanopyHome
  , getOrCreateZokkaCustomRepositoryConfig
  , getOrCreateZokkaCacheDir
    -- * Cache Path Construction
  , registry
  , package
  , packageOverride
  , zokkaCacheToFilePath
    -- * Internal Utilities
  , getCacheDir
  , getZokkaDir
  , zokkaVersion
  ) where

import Canopy.Package (Name)
import qualified Canopy.Package as Pkg
import Canopy.Version (Version)
import qualified Canopy.Version as V
import Control.Lens (Lens', makeLenses, (^.))
import qualified Stuff.Paths as Paths
import qualified System.Directory as Dir
import qualified System.Environment as Env
import System.FilePath ((</>))
import Prelude (Bool (..), Eq, FilePath, IO, Maybe (..), Show, String, pure, return, (.), (<$>), (<>))

-- | Wrapper for package cache directory path.
--
-- @since 0.19.1
newtype PackageCache = PackageCache FilePath
  deriving (Eq, Show)

-- | Lens for accessing PackageCache file path.
--
-- @since 0.19.1
packageCacheFilePath :: Lens' PackageCache FilePath
packageCacheFilePath f (PackageCache fp) = PackageCache <$> f fp

-- | Wrapper for Zokka-specific cache directory path.
--
-- @since 0.19.1
newtype ZokkaSpecificCache = ZokkaSpecificCache FilePath
  deriving (Eq, Show)

-- | Lens for accessing ZokkaSpecificCache file path.
--
-- @since 0.19.1
zokkaSpecificCacheFilePath :: Lens' ZokkaSpecificCache FilePath
zokkaSpecificCacheFilePath f (ZokkaSpecificCache fp) = ZokkaSpecificCache <$> f fp

-- | Wrapper for package overrides cache directory path.
--
-- @since 0.19.1
newtype PackageOverridesCache = PackageOverridesCache FilePath
  deriving (Eq, Show)

-- | Lens for accessing PackageOverridesCache file path.
--
-- @since 0.19.1
packageOverridesCacheFilePath :: Lens' PackageOverridesCache FilePath
packageOverridesCacheFilePath f (PackageOverridesCache fp) = PackageOverridesCache <$> f fp

-- | Configuration for package dependency overrides.
--
-- @since 0.19.1
data PackageOverrideConfig = PackageOverrideConfig
  { _pocCache :: !PackageOverridesCache,
    _pocOriginalPkg :: !Name,
    _pocOriginalVersion :: !Version,
    _pocOverridingPkg :: !Name,
    _pocOverridingVersion :: !Version
  }
  deriving (Eq, Show)

-- | Generate lenses for PackageOverrideConfig fields.
--
-- @since 0.19.1
makeLenses ''PackageOverrideConfig

-- | Wrapper for Zokka custom repository configuration file path.
--
-- @since 0.19.1
newtype ZokkaCustomRepositoryConfigFilePath = ZokkaCustomRepositoryConfigFilePath {unZokkaCustomRepositoryConfigFilePath :: FilePath}
  deriving (Eq, Show)

-- | Get the global package cache directory.
--
-- @since 0.19.1
getPackageCache :: IO PackageCache
getPackageCache =
  PackageCache <$> getCacheDir "packages"

-- | Get the package overrides cache directory.
--
-- @since 0.19.1
getPackageOverridesCache :: IO PackageOverridesCache
getPackageOverridesCache = do
  zokkaCache <- getZokkaCache
  pure (PackageOverridesCache (zokkaCache ^. zokkaSpecificCacheFilePath))

-- | Extract file path from ZokkaSpecificCache.
--
-- @since 0.19.1
zokkaCacheToFilePath :: ZokkaSpecificCache -> FilePath
zokkaCacheToFilePath cache = cache ^. zokkaSpecificCacheFilePath

-- | Get the Zokka-specific cache directory.
--
-- @since 0.19.1
getZokkaCache :: IO ZokkaSpecificCache
getZokkaCache =
  ZokkaSpecificCache <$> getOrCreateZokkaCacheDir

-- | Get the path to the Zokka package registry file.
--
-- @since 0.19.1
registry :: ZokkaSpecificCache -> FilePath
registry cache =
  cache ^. zokkaSpecificCacheFilePath </> "canopy-registry.dat"

-- | Get the directory path for a specific package version.
--
-- @since 0.19.1
package :: PackageCache -> Name -> Version -> FilePath
package cache name version =
  cache ^. packageCacheFilePath </> Pkg.toFilePath name </> V.toChars version

-- | Get the directory path for a package dependency override.
--
-- @since 0.19.1
packageOverride :: PackageOverrideConfig -> FilePath
packageOverride config =
  dir </> Pkg.toFilePath (config ^. pocOriginalPkg) </> V.toChars (config ^. pocOriginalVersion) </> Pkg.toFilePath (config ^. pocOverridingPkg) </> V.toChars (config ^. pocOverridingVersion)
  where
    dir = config ^. pocCache . packageOverridesCacheFilePath

-- | Get the REPL cache directory path.
--
-- @since 0.19.1
getReplCache :: IO FilePath
getReplCache =
  getCacheDir "repl"

-- | Get a version-specific cache directory for a project.
--
-- @since 0.19.1
getCacheDir :: FilePath -> IO FilePath
getCacheDir projectName = do
  home <- getCanopyHome
  Dir.createDirectoryIfMissing True (home </> Paths.compilerVersion </> projectName)
  return (home </> Paths.compilerVersion </> projectName)

-- | Get the Canopy home directory path.
--
-- @since 0.19.1
getCanopyHome :: IO FilePath
getCanopyHome = do
  maybeCustomHome <- Env.lookupEnv "CANOPY_HOME"
  case maybeCustomHome of
    Just customHome -> return customHome
    Nothing -> Dir.getAppUserDataDirectory "canopy"

-- | Get or create the Zokka-specific cache directory.
--
-- @since 0.19.1
getOrCreateZokkaCacheDir :: IO FilePath
getOrCreateZokkaCacheDir = do
  cacheDir <- getCacheDir ("canopy-cache-" <> zokkaVersion)
  Dir.createDirectoryIfMissing True cacheDir
  pure cacheDir

-- | Get the Zokka configuration directory.
--
-- @since 0.19.1
getZokkaDir :: IO FilePath
getZokkaDir = getCacheDir "canopy"

-- | Get or create the Zokka custom repository configuration file path.
--
-- @since 0.19.1
getOrCreateZokkaCustomRepositoryConfig :: IO ZokkaCustomRepositoryConfigFilePath
getOrCreateZokkaCustomRepositoryConfig = do
  zokkaDir <- getZokkaDir
  Dir.createDirectoryIfMissing True zokkaDir
  pure (ZokkaCustomRepositoryConfigFilePath (zokkaDir </> "custom-package-repository-config.json"))

-- | The Zokka version string used in cache directory names.
--
-- @since 0.19.1
zokkaVersion :: String
zokkaVersion = "0.191.0"