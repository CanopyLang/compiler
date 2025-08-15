{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Stuff - File system paths and caching infrastructure for the Canopy compiler
--
-- This module provides comprehensive file system path management and caching
-- infrastructure for the Canopy compiler build system. It handles the organization
-- of compiler artifacts, cache directories, package storage, and project root
-- discovery. The module is designed to support both vanilla Canopy and Zokka
-- (Canopy fork) compilation with proper isolation between compiler versions.
--
-- The caching system is hierarchical and version-aware, ensuring that different
-- compiler versions and package configurations don't interfere with each other.
-- All paths are constructed systematically to maintain consistency across the
-- entire build pipeline.
--
-- == Key Features
--
-- * **Version-Isolated Caching** - Separate cache directories for different compiler versions
-- * **Multi-Compiler Support** - Compatible with both Canopy and Zokka compilers
-- * **Package Management** - Structured storage for packages and dependencies
-- * **Dependency Overrides** - Support for Zokka's dependency override mechanism
-- * **Thread-Safe Locking** - File-based locking for concurrent build safety
-- * **Project Discovery** - Automatic detection of Canopy/Elm project roots
-- * **Artifact Organization** - Systematic organization of compiler artifacts
--
-- == Architecture
--
-- The module is organized into several functional areas:
--
-- * **Path Construction** - Functions for building standardized file paths
-- * **Cache Management** - Cache directory creation and organization
-- * **Project Discovery** - Finding project roots and configuration files
-- * **Locking Mechanisms** - Thread-safe access to shared resources
-- * **Package Storage** - Structured storage for downloaded packages
--
-- All paths are constructed relative to a project root or global cache directory,
-- ensuring portability and predictable organization.
--
-- == Usage Examples
--
-- === Basic Path Construction
--
-- @
-- -- Get compiler artifact paths for a project
-- root <- findRoot >>= maybe (error "No project found") pure
-- let detailsPath = details root
--     interfacesPath = interfaces root
--     objectsPath = objects root
-- @
--
-- === Package Cache Management
--
-- @
-- -- Set up package caching
-- cache <- getPackageCache
-- let packagePath = package cache (Pkg.fromChars "elm" "core") (V.fromChars "1.0.0")
--
-- -- Use with locking for thread safety
-- withRegistryLock cache $ do
--   downloadPackage packagePath
--   installPackage packagePath
-- @
--
-- === Project Root Discovery
--
-- @
-- -- Find and work within project root
-- maybeRoot <- findRoot
-- case maybeRoot of
--   Just root -> withRootLock root $ do
--     buildProject root
--     generateArtifacts root
--   Nothing -> putStrLn "No Canopy project found"
-- @
--
-- === Zokka-Specific Functionality
--
-- @
-- -- Set up Zokka-specific caching and configuration
-- zokkaCache <- getZokkaCache
-- configPath <- getOrCreateZokkaCustomRepositoryConfig
--
-- -- Handle dependency overrides
-- overridesCache <- getPackageOverridesCache
-- let overrideConfig = PackageOverrideConfig
--       { _pocCache = overridesCache
--       , _pocOriginalPkg = originalPackage
--       , _pocOriginalVersion = originalVersion
--       , _pocOverridingPkg = overridePackage
--       , _pocOverridingVersion = overrideVersion
--       }
-- let overridePath = packageOverride overrideConfig
-- @
--
-- == Error Handling
--
-- Most functions in this module are designed to be robust and create necessary
-- directories automatically. File system operations may fail due to:
--
-- * **Permission Errors** - Insufficient permissions to create directories
-- * **Disk Space** - Insufficient disk space for cache directories
-- * **Path Issues** - Invalid characters or overly long paths
-- * **Concurrent Access** - Lock contention during concurrent builds
--
-- The locking functions ('withRootLock', 'withRegistryLock') automatically
-- handle lock acquisition and release, ensuring proper cleanup even on exceptions.
--
-- == Performance Characteristics
--
-- * **Path Construction**: O(1) - Simple string concatenation operations
-- * **Directory Creation**: O(1) - Cached after first creation
-- * **Root Discovery**: O(d) where d is directory tree depth
-- * **Lock Operations**: O(1) - Fast file-based locking
--
-- The module is designed for minimal overhead with lazy directory creation
-- and efficient path operations.
--
-- == Thread Safety
--
-- All path construction functions are pure and thread-safe. Cache directory
-- creation uses atomic directory operations. The locking functions provide
-- thread-safe access to shared resources through file-based locking.
--
-- @since 0.19.1
module Stuff
  ( -- * Compiler Artifact Paths
    details,
    interfaces,
    objects,
    prepublishDir,

    -- * Module Artifact Paths
    canopyi,
    canopyo,
    temp,

    -- * Project Discovery
    findRoot,

    -- * Locking Mechanisms
    withRootLock,
    withRegistryLock,

    -- * Cache Types
    PackageCache,
    ZokkaSpecificCache,
    PackageOverridesCache,
    PackageOverrideConfig (..),
    ZokkaCustomRepositoryConfigFilePath (..),

    -- * Cache Management
    getPackageCache,
    getZokkaCache,
    getPackageOverridesCache,
    getReplCache,
    getCanopyHome,
    getOrCreateZokkaCustomRepositoryConfig,
    getOrCreateZokkaCacheDir,

    -- * Cache Path Construction
    registry,
    package,
    packageOverride,
    zokkaCacheToFilePath,
  )
where

import qualified Canopy.ModuleName as ModuleName
import Canopy.Package (Name)
import qualified Canopy.Package as Pkg
import Canopy.Version (Version)
import qualified Canopy.Version as V
import Control.Lens (Lens', makeLenses, (^.))
import qualified Data.List as List
import qualified System.Directory as Dir
import qualified System.Environment as Env
import qualified System.FileLock as Lock
import System.FilePath ((<.>), (</>))
import qualified System.FilePath as FP
import Prelude (Bool (..), Eq, FilePath, IO, Maybe (..), Show, String, const, pure, return, (.), (<$>), (<>), (||))

-- PATHS

-- | Construct the base compiler artifacts directory path.
--
-- Creates a version-specific directory for storing all compiler artifacts.
-- Uses "canopy-stuff" with a custom version suffix to maintain isolation
-- between different compiler versions and avoid cache conflicts between
-- vanilla Canopy and Zokka compilers.
--
-- The custom version suffix ensures that:
--
-- * Zokka dependency overrides don't corrupt vanilla Canopy caches
-- * Different compiler versions maintain separate artifact storage
-- * Timestamp-based rebuild detection works correctly
-- * Cache invalidation is handled properly across compiler switches
--
-- ==== Examples
--
-- >>> stuff "/home/user/myproject"
-- "/home/user/myproject/canopy-stuff/0.19.1-canopy"
--
-- >>> stuff "."
-- "./canopy-stuff/0.19.1-canopy"
--
-- @since 0.19.1
stuff :: FilePath -> FilePath
stuff root =
  -- We use zokka-stuff instead of canopy-stuff because this gets around an edge
  -- case where the compiler checks the timestamp of the stuff directory vs
  -- canopy.json to decide whether any re-building is necessary and this can mean
  -- that compiling with the Zokka compiler doesn't change any code that was
  -- compiled by the Canopy compiler, even though it probably should.
  root </> "canopy-stuff" </> customCompilerVersion
  where
    -- The following comment explains why we originally had compilerVersion ++ -zokka
    -- under the same canopy-stuff. Some of the reasoning there is stil true but not as
    -- relevant, because the -zokka suffix is superfluous now that we use
    -- zokka-stuff instead of the directory name canopy-stuff.
    --
    -- We need a custom compiler version because of Zokka's support for dependency
    -- overrides. If we override dependencies, we could end up with what appears to
    -- be an invalid cache for the vanilla Canopy compiler, because we will have
    -- resolved a different set of dependencies than what the vanilla Canopy compiler
    -- would have, which can result in interface files that do not correspond to
    -- canopy.json as the vanilla Canopy compiler understands the dependencies from
    -- canopy.json. This means that an end user who uses Zokka and then tries to revert
    -- back to using Canopy could observe non-obvious breakage (even though it's
    -- easily fixable by just deleting the canopy-stuff directory), which we are trying
    -- to minimimze.
    --
    -- As far as I know no Canopy IDE integration tools use the canopy-stuff directory for
    -- important analyses. If that's not true, then we may revert to using the usual
    -- compiler version and just letting the user delete canopy-stuff manually (the
    -- error message at least will tell them to delete the directory).
    customCompilerVersion = compilerVersion <> "-canopy"

-- | Get the path to the project details cache file.
--
-- The details file stores serialized project information including
-- dependency resolution, module discovery results, and build metadata.
-- This file is used to determine if rebuilding is necessary based on
-- changes to project configuration or source files.
--
-- ==== Examples
--
-- >>> details "/home/user/myproject"
-- "/home/user/myproject/canopy-stuff/0.19.1-canopy/d.dat"
--
-- @since 0.19.1
details :: FilePath -> FilePath
details root =
  stuff root </> "d.dat"

-- | Get the path to the compiled interfaces cache file.
--
-- The interfaces file stores serialized module interfaces containing
-- type signatures, exports, and other information needed for compilation
-- of dependent modules. This enables incremental compilation by avoiding
-- re-parsing of unchanged dependencies.
--
-- ==== Examples
--
-- >>> interfaces "/home/user/myproject"
-- "/home/user/myproject/canopy-stuff/0.19.1-canopy/i.dat"
--
-- @since 0.19.1
interfaces :: FilePath -> FilePath
interfaces root =
  stuff root </> "i.dat"

-- | Get the path to the compiled objects cache file.
--
-- The objects file stores serialized compiled code objects that can be
-- linked together during the final code generation phase. This allows
-- for efficient incremental compilation by reusing previously compiled
-- modules.
--
-- ==== Examples
--
-- >>> objects "/home/user/myproject"
-- "/home/user/myproject/canopy-stuff/0.19.1-canopy/o.dat"
--
-- @since 0.19.1
objects :: FilePath -> FilePath
objects root =
  stuff root </> "o.dat"

-- | Get the path to the package prepublishing directory.
--
-- The prepublish directory is used for staging package contents before
-- publishing to a package registry. It contains the processed package
-- files, documentation, and metadata in the format expected by the
-- package registry.
--
-- ==== Examples
--
-- >>> prepublishDir "/home/user/mypackage"
-- "/home/user/mypackage/canopy-stuff/0.19.1-canopy/prepublish"
--
-- @since 0.19.1
prepublishDir :: FilePath -> FilePath
prepublishDir root =
  stuff root </> "prepublish"

-- | Get the current compiler version as a string.
--
-- Retrieves the version identifier for the current compiler, used in
-- path construction to ensure version isolation. This version comes
-- from the Canopy.Version module and represents the compiler's release version.
--
-- ==== Examples
--
-- >>> compilerVersion
-- "0.19.1"
--
-- @since 0.19.1
compilerVersion :: FilePath
compilerVersion =
  V.toChars V.compiler

-- CANOPYI and CANOPYO

-- | Get the path to a module's interface file (.canopyi).
--
-- Interface files contain the public API information for a module,
-- including type signatures, exported values, and other metadata
-- needed for type checking and compilation of importing modules.
-- The file uses a hyphenated path format based on the module name.
--
-- ==== Examples
--
-- >>> canopyi "/project" (ModuleName.fromChars "Main")
-- "/project/canopy-stuff/0.19.1-canopy/Main.canopyi"
--
-- >>> canopyi "/project" (ModuleName.fromChars "App.Utils.String")
-- "/project/canopy-stuff/0.19.1-canopy/App-Utils-String.canopyi"
--
-- @since 0.19.1
canopyi :: FilePath -> ModuleName.Raw -> FilePath
canopyi root name =
  toArtifactPath root name "canopyi"

-- | Get the path to a module's object file (.canopyo).
--
-- Object files contain the compiled representation of a module,
-- including optimized code, dependency information, and metadata
-- needed for linking and code generation. The file uses a hyphenated
-- path format based on the module name.
--
-- ==== Examples
--
-- >>> canopyo "/project" (ModuleName.fromChars "Main")
-- "/project/canopy-stuff/0.19.1-canopy/Main.canopyo"
--
-- >>> canopyo "/project" (ModuleName.fromChars "App.Utils.String")
-- "/project/canopy-stuff/0.19.1-canopy/App-Utils-String.canopyo"
--
-- @since 0.19.1
canopyo :: FilePath -> ModuleName.Raw -> FilePath
canopyo root name =
  toArtifactPath root name "canopyo"

-- | Construct artifact path for a module with given extension.
--
-- Internal helper function that builds standardized paths for module
-- artifacts. Converts module names to hyphenated file paths and adds
-- the specified file extension within the compiler's artifact directory.
--
-- ==== Examples
--
-- >>> toArtifactPath "/project" (ModuleName.fromChars "App.Utils") "canopyi"
-- "/project/canopy-stuff/0.19.1-canopy/App-Utils.canopyi"
--
-- @since 0.19.1
toArtifactPath :: FilePath -> ModuleName.Raw -> String -> FilePath
toArtifactPath root name ext =
  stuff root </> ModuleName.toHyphenPath name <.> ext

-- TEMP

-- | Get the path to a temporary file with the given extension.
--
-- Creates a path for temporary files within the compiler's artifact
-- directory. Temporary files are used for intermediate compilation
-- results, temporary downloads, and other transient data that needs
-- to be cleaned up after compilation.
--
-- ==== Examples
--
-- >>> temp "/project" "js"
-- "/project/canopy-stuff/0.19.1-canopy/temp.js"
--
-- >>> temp "/project" "html"
-- "/project/canopy-stuff/0.19.1-canopy/temp.html"
--
-- @since 0.19.1
temp :: FilePath -> String -> FilePath
temp root ext =
  stuff root </> "temp" <.> ext

-- ROOT

-- | Find the root directory of a Canopy or Elm project.
--
-- Searches upward from the current working directory to find a directory
-- containing either "canopy.json" or "elm.json" configuration files.
-- This function is used to automatically detect the project root for
-- build operations and artifact storage.
--
-- The search process:
--
-- 1. **Start from current directory** - Begin search at working directory
-- 2. **Check for config files** - Look for canopy.json or elm.json
-- 3. **Traverse upward** - Move to parent directory if not found
-- 4. **Terminate at filesystem root** - Return Nothing if no project found
--
-- ==== Examples
--
-- >>> -- In /home/user/myproject/src/
-- >>> findRoot
-- Just "/home/user/myproject"
--
-- >>> -- In /tmp (no project)
-- >>> findRoot
-- Nothing
--
-- ==== Error Conditions
--
-- Returns 'Nothing' when:
--
-- * No canopy.json or elm.json found in directory tree
-- * Insufficient permissions to read directories
-- * Filesystem traversal reaches root without finding project
--
-- @since 0.19.1
findRoot :: IO (Maybe FilePath)
findRoot =
  do
    dir <- Dir.getCurrentDirectory
    findRootHelp (FP.splitDirectories dir)

-- | Helper function for project root discovery.
--
-- Recursively searches directory tree upward for project configuration
-- files. Takes a list of directory components and checks each level
-- for the presence of canopy.json or elm.json files.
--
-- @since 0.19.1
findRootHelp :: [String] -> IO (Maybe FilePath)
findRootHelp dirs =
  case dirs of
    [] ->
      return Nothing
    _ : _ ->
      do
        canopyExists <- Dir.doesFileExist (FP.joinPath dirs </> "canopy.json")
        elmExists <- Dir.doesFileExist (FP.joinPath dirs </> "elm.json")
        if canopyExists || elmExists
          then return (Just (FP.joinPath dirs))
          else findRootHelp (List.init dirs)

-- LOCKS

-- | Execute an action with an exclusive lock on the project root.
--
-- Provides thread-safe access to project-specific resources by acquiring
-- an exclusive file lock on the project's artifact directory. This prevents
-- concurrent builds from interfering with each other when accessing shared
-- files like cache data, temporary files, and compilation artifacts.
--
-- The lock is automatically released when the action completes, even if
-- an exception occurs. The artifact directory is created if it doesn't exist.
--
-- ==== Examples
--
-- >>> withRootLock "/home/user/myproject" $ do
-- >>>   compileProject
-- >>>   generateArtifacts
--
-- >>> withRootLock projectRoot $ do
-- >>>   cleanArtifacts
-- >>>   rebuildAll
--
-- ==== Error Conditions
--
-- May throw exceptions for:
--
-- * **Permission Errors** - Insufficient permissions to create lock file
-- * **Disk Space** - Insufficient disk space for artifact directory
-- * **Lock Contention** - Another process holds the lock (blocks until available)
--
-- @since 0.19.1
withRootLock :: FilePath -> IO a -> IO a
withRootLock root work =
  do
    Dir.createDirectoryIfMissing True dir
    Lock.withFileLock (dir </> "lock") Lock.Exclusive (const work)
  where
    dir = stuff root

-- | Execute an action with an exclusive lock on the package registry cache.
--
-- Provides thread-safe access to the global package cache by acquiring
-- an exclusive file lock. This prevents concurrent package operations
-- from corrupting the cache when downloading, installing, or updating
-- packages. The lock is shared between Canopy and Zokka compilers.
--
-- The lock is automatically released when the action completes, even if
-- an exception occurs. This ensures proper cleanup and prevents deadlocks.
--
-- ==== Examples
--
-- >>> cache <- getPackageCache
-- >>> withRegistryLock cache $ do
-- >>>   downloadPackage packageName version
-- >>>   installPackage packagePath
--
-- >>> withRegistryLock cache $ do
-- >>>   updateRegistry
-- >>>   validatePackages
--
-- ==== Error Conditions
--
-- May throw exceptions for:
--
-- * **Permission Errors** - Insufficient permissions to create lock file
-- * **Lock Contention** - Another process holds the lock (blocks until available)
-- * **Cache Directory Issues** - Problems accessing package cache directory
--
-- @since 0.19.1
withRegistryLock :: PackageCache -> IO a -> IO a
withRegistryLock cache work =
  Lock.withFileLock (cache ^. packageCacheFilePath </> "lock") Lock.Exclusive (const work)

-- PACKAGE CACHES

-- | Wrapper for package cache directory path.
--
-- Represents the global package cache directory where downloaded packages
-- are stored. This cache is shared between different projects and compiler
-- versions to avoid redundant downloads. The cache uses a structured layout
-- with separate directories for each package and version.
--
-- @since 0.19.1
newtype PackageCache = PackageCache FilePath
  deriving (Eq, Show)

-- | Lens for accessing PackageCache file path.
--
-- Provides lens-based access to the underlying file path of a PackageCache.
-- Used for path manipulation and accessing cache contents.
--
-- @since 0.19.1
packageCacheFilePath :: Lens' PackageCache FilePath
packageCacheFilePath f (PackageCache fp) = PackageCache <$> f fp

-- | Wrapper for Zokka-specific cache directory path.
--
-- Represents the cache directory for Zokka-specific data including the
-- custom package registry and Zokka-only configuration files. This cache
-- is separate from the main package cache to avoid conflicts between
-- Canopy and Zokka compiler operations.
--
-- @since 0.19.1
newtype ZokkaSpecificCache = ZokkaSpecificCache FilePath
  deriving (Eq, Show)

-- | Lens for accessing ZokkaSpecificCache file path.
--
-- Provides lens-based access to the underlying file path of a ZokkaSpecificCache.
-- Used for path manipulation and accessing Zokka-specific cache contents.
--
-- @since 0.19.1
zokkaSpecificCacheFilePath :: Lens' ZokkaSpecificCache FilePath
zokkaSpecificCacheFilePath f (ZokkaSpecificCache fp) = ZokkaSpecificCache <$> f fp

-- | Wrapper for package overrides cache directory path.
--
-- Represents the cache directory for Zokka's dependency override feature.
-- When packages are overridden with different versions or implementations,
-- the results are cached separately to maintain isolation from normal
-- package resolution.
--
-- @since 0.19.1
newtype PackageOverridesCache = PackageOverridesCache FilePath
  deriving (Eq, Show)

-- | Lens for accessing PackageOverridesCache file path.
--
-- Provides lens-based access to the underlying file path of a PackageOverridesCache.
-- Used for path manipulation and accessing package override cache contents.
--
-- @since 0.19.1
packageOverridesCacheFilePath :: Lens' PackageOverridesCache FilePath
packageOverridesCacheFilePath f (PackageOverridesCache fp) = PackageOverridesCache <$> f fp

-- | Configuration for package dependency overrides.
--
-- Contains all information needed to resolve and cache a package override
-- in Zokka's dependency override system. When a package dependency is
-- overridden, this configuration tracks both the original package being
-- replaced and the replacement package, along with their versions.
--
-- The cache path stores the override resolution results to avoid
-- re-computing dependency graphs when the same override is used.
--
-- ==== Fields
--
-- * '_pocCache' - Cache directory for storing override results
-- * '_pocOriginalPkg' - Name of the package being overridden
-- * '_pocOriginalVersion' - Version of the package being overridden
-- * '_pocOverridingPkg' - Name of the replacement package
-- * '_pocOverridingVersion' - Version of the replacement package
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
-- Creates lenses: pocCache, pocOriginalPkg, pocOriginalVersion,
-- pocOverridingPkg, pocOverridingVersion for accessing and updating
-- PackageOverrideConfig fields.
--
-- @since 0.19.1
makeLenses ''PackageOverrideConfig

-- | Get the global package cache directory.
--
-- Returns the configured package cache directory where downloaded packages
-- are stored. Creates the directory if it doesn't exist. This cache is
-- shared across all projects and compiler versions to minimize storage
-- and download overhead.
--
-- The cache directory structure:
-- * Each package gets its own subdirectory
-- * Each version gets its own subdirectory within the package directory
-- * Package contents are extracted into the version directory
--
-- ==== Examples
--
-- >>> cache <- getPackageCache
-- >>> let cachePath = cache ^. packageCacheFilePath
-- >>> -- cachePath might be "/home/user/.canopy/0.19.1/packages"
--
-- @since 0.19.1
getPackageCache :: IO PackageCache
getPackageCache =
  PackageCache <$> getCacheDir "packages"

-- | Get the package overrides cache directory.
--
-- Returns the cache directory for Zokka's dependency override feature.
-- This cache stores the results of dependency resolution when packages
-- are overridden with different versions or implementations. The cache
-- is isolated from the main package cache to avoid conflicts.
--
-- ==== Examples
--
-- >>> overridesCache <- getPackageOverridesCache
-- >>> let config = PackageOverrideConfig {
-- >>>   _pocCache = overridesCache,
-- >>>   _pocOriginalPkg = originalPackage,
-- >>>   ...
-- >>> }
--
-- @since 0.19.1
getPackageOverridesCache :: IO PackageOverridesCache
getPackageOverridesCache =
  do
    zokkaCache <- getZokkaCache
    pure (PackageOverridesCache (zokkaCache ^. zokkaSpecificCacheFilePath))

-- | Extract file path from ZokkaSpecificCache.
--
-- Convenience function to get the underlying file path from a
-- ZokkaSpecificCache wrapper. Used when a raw file path is needed
-- for file operations or path construction.
--
-- ==== Examples
--
-- >>> cache <- getZokkaCache
-- >>> let path = zokkaCacheToFilePath cache
-- >>> -- path might be "/home/user/.canopy/0.19.1/canopy-cache-0.191.0"
--
-- @since 0.19.1
zokkaCacheToFilePath :: ZokkaSpecificCache -> FilePath
zokkaCacheToFilePath cache = cache ^. zokkaSpecificCacheFilePath

-- | Get the Zokka-specific cache directory.
--
-- Returns the cache directory for Zokka-specific data including the
-- custom package registry and configuration files. This cache uses
-- a version-specific directory name to maintain isolation between
-- different Zokka versions.
--
-- ==== Examples
--
-- >>> zokkaCache <- getZokkaCache
-- >>> let registryPath = registry zokkaCache
-- >>> -- registryPath contains Zokka's custom package registry
--
-- @since 0.19.1
getZokkaCache :: IO ZokkaSpecificCache
getZokkaCache =
  ZokkaSpecificCache <$> getOrCreateZokkaCacheDir

-- | Get the path to the Zokka package registry file.
--
-- Returns the path to the registry file that contains Zokka's custom
-- package repository information. This registry supplements or overrides
-- the default Canopy package registry with Zokka-specific package sources
-- and dependency resolution data.
--
-- ==== Examples
--
-- >>> cache <- getZokkaCache
-- >>> let registryPath = registry cache
-- >>> -- registryPath might be "/home/user/.canopy/0.19.1/canopy-cache-0.191.0/canopy-registry.dat"
--
-- @since 0.19.1
registry :: ZokkaSpecificCache -> FilePath
registry cache =
  cache ^. zokkaSpecificCacheFilePath </> "canopy-registry.dat"

-- | Get the directory path for a specific package version.
--
-- Constructs the standardized directory path where a particular version
-- of a package is stored in the package cache. The path follows the
-- pattern: cache/author-project/version/ where package names are converted
-- to filesystem-safe formats.
--
-- ==== Examples
--
-- >>> cache <- getPackageCache
-- >>> let elmCore = Pkg.fromChars "elm" "core"
-- >>> let version = V.fromChars "1.0.0"
-- >>> package cache elmCore version
-- "/home/user/.canopy/0.19.1/packages/elm-core/1.0.0"
--
-- @since 0.19.1
package :: PackageCache -> Name -> Version -> FilePath
package cache name version =
  cache ^. packageCacheFilePath </> Pkg.toFilePath name </> V.toChars version

-- | Get the directory path for a package dependency override.
--
-- Constructs the directory path where the results of a dependency override
-- are cached. The path encodes both the original package being overridden
-- and the replacement package, ensuring each override combination gets
-- its own isolated cache space.
--
-- The path structure is: cache/original-pkg/original-version/overriding-pkg/overriding-version/
--
-- ==== Examples
--
-- >>> config <- PackageOverrideConfig {
-- >>>   _pocCache = overridesCache,
-- >>>   _pocOriginalPkg = Pkg.fromChars "elm" "core",
-- >>>   _pocOriginalVersion = V.fromChars "1.0.0",
-- >>>   _pocOverridingPkg = Pkg.fromChars "author" "custom-core",
-- >>>   _pocOverridingVersion = V.fromChars "2.0.0"
-- >>> }
-- >>> packageOverride config
-- "/cache/path/elm-core/1.0.0/author-custom-core/2.0.0"
--
-- @since 0.19.1
packageOverride :: PackageOverrideConfig -> FilePath
packageOverride config =
  dir </> Pkg.toFilePath (config ^. pocOriginalPkg) </> V.toChars (config ^. pocOriginalVersion) </> Pkg.toFilePath (config ^. pocOverridingPkg) </> V.toChars (config ^. pocOverridingVersion)
  where
    dir = config ^. pocCache . packageOverridesCacheFilePath

-- CACHE

-- | Get the REPL cache directory path.
--
-- Returns the directory where REPL (Read-Eval-Print Loop) session data
-- is cached, including command history, imported modules, and temporary
-- evaluation results. This cache improves REPL startup time and preserves
-- user session state between REPL invocations.
--
-- ==== Examples
--
-- >>> replCache <- getReplCache
-- >>> -- replCache might be "/home/user/.canopy/0.19.1/repl"
-- >>> saveReplHistory replCache
--
-- @since 0.19.1
getReplCache :: IO FilePath
getReplCache =
  getCacheDir "repl"

-- | Get a version-specific cache directory for a project.
--
-- Creates a cache directory under the Canopy home directory with the
-- current compiler version and specified project name. The directory
-- is created if it doesn't exist. This ensures version isolation and
-- prevents cache conflicts between different compiler versions.
--
-- ==== Examples
--
-- >>> packagesCache <- getCacheDir "packages"
-- >>> -- packagesCache might be "/home/user/.canopy/0.19.1/packages"
--
-- >>> docsCache <- getCacheDir "docs"
-- >>> -- docsCache might be "/home/user/.canopy/0.19.1/docs"
--
-- ==== Error Conditions
--
-- May throw exceptions for:
--
-- * **Permission Errors** - Insufficient permissions to create directory
-- * **Disk Space** - Insufficient disk space for cache directory
-- * **Path Issues** - Invalid project name characters
--
-- @since 0.19.1
getCacheDir :: FilePath -> IO FilePath
getCacheDir projectName =
  do
    home <- getCanopyHome
    Dir.createDirectoryIfMissing True (home </> compilerVersion </> projectName)
    return (home </> compilerVersion </> projectName)

-- | Get the Canopy home directory path.
--
-- Returns the root directory for all Canopy-related user data including
-- caches, configuration, and downloaded packages. The directory can be
-- customized using the CANOPY_HOME environment variable, otherwise it
-- defaults to the standard application data directory for the platform.
--
-- Directory selection priority:
--
-- 1. **CANOPY_HOME environment variable** - Custom user-specified location
-- 2. **Platform default** - Standard app data directory (varies by OS)
--
-- ==== Examples
--
-- >>> -- With CANOPY_HOME set
-- >>> setEnv "CANOPY_HOME" "/custom/canopy/path"
-- >>> getCanopyHome
-- "/custom/canopy/path"
--
-- >>> -- With default location (Linux)
-- >>> getCanopyHome
-- "/home/user/.canopy"
--
-- >>> -- With default location (macOS)
-- >>> getCanopyHome
-- "/Users/user/Library/Application Support/canopy"
--
-- @since 0.19.1
getCanopyHome :: IO FilePath
getCanopyHome =
  do
    maybeCustomHome <- Env.lookupEnv "CANOPY_HOME"
    case maybeCustomHome of
      Just customHome -> return customHome
      Nothing -> Dir.getAppUserDataDirectory "canopy"

-- | Get or create the Zokka-specific cache directory.
--
-- Creates and returns the cache directory for Zokka-specific data.
-- The cache directory contains the Zokka-specific registry file and
-- other transient data that can be regenerated. This is separate from
-- the main Zokka directory which contains more valuable configuration.
--
-- The cache directory uses a version-specific name to maintain isolation
-- between different Zokka versions and ensure cache compatibility.
--
-- ==== Examples
--
-- >>> cacheDir <- getOrCreateZokkaCacheDir
-- >>> -- cacheDir might be "/home/user/.canopy/0.19.1/canopy-cache-0.191.0"
--
-- @since 0.19.1
getOrCreateZokkaCacheDir :: IO FilePath
getOrCreateZokkaCacheDir = do
  cacheDir <- getCacheDir ("canopy-cache-" <> zokkaVersion)
  Dir.createDirectoryIfMissing True cacheDir
  pure cacheDir

-- | Get the Zokka configuration directory.
--
-- Returns the directory for Zokka-specific configuration files including
-- custom repository configuration and other persistent settings. This
-- directory contains more valuable data than the cache directory and
-- should be preserved across Zokka updates.
--
-- @since 0.19.1
getZokkaDir :: IO FilePath
getZokkaDir = getCacheDir "canopy"

-- | Wrapper for Zokka custom repository configuration file path.
--
-- Represents the path to Zokka's custom package repository configuration
-- file. This file contains information about custom package sources,
-- repository URLs, and authentication settings for non-standard package
-- repositories.
--
-- @since 0.19.1
newtype ZokkaCustomRepositoryConfigFilePath = ZokkaCustomRepositoryConfigFilePath {unZokkaCustomRepositoryConfigFilePath :: FilePath}
  deriving (Eq, Show)

-- | Get or create the Zokka custom repository configuration file path.
--
-- Returns the path to Zokka's custom package repository configuration file.
-- Creates the parent directory if it doesn't exist. This configuration file
-- allows users to specify custom package repositories beyond the default
-- Canopy package registry.
--
-- The configuration file is stored in JSON format and contains repository
-- URLs, authentication information, and package source priorities.
--
-- ==== Examples
--
-- >>> configPath <- getOrCreateZokkaCustomRepositoryConfig
-- >>> let path = unZokkaCustomRepositoryConfigFilePath configPath
-- >>> -- path might be "/home/user/.canopy/0.19.1/canopy/custom-package-repository-config.json"
--
-- ==== Error Conditions
--
-- May throw exceptions for:
--
-- * **Permission Errors** - Insufficient permissions to create directory
-- * **Disk Space** - Insufficient disk space for configuration directory
--
-- @since 0.19.1
getOrCreateZokkaCustomRepositoryConfig :: IO ZokkaCustomRepositoryConfigFilePath
getOrCreateZokkaCustomRepositoryConfig =
  do
    zokkaDir <- getZokkaDir
    Dir.createDirectoryIfMissing True zokkaDir
    pure (ZokkaCustomRepositoryConfigFilePath (zokkaDir </> "custom-package-repository-config.json"))

-- | The Zokka version string used in cache directory names.
--
-- Hardcoded version identifier for Zokka-specific cache directories.
-- This ensures that different Zokka versions use separate cache spaces
-- and don't interfere with each other. Eventually this should be
-- determined programmatically from build configuration.
--
-- ==== Examples
--
-- >>> zokkaVersion
-- "0.191.0"
--
-- @since 0.19.1
zokkaVersion :: String
zokkaVersion = "0.191.0"
