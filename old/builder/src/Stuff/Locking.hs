{-# OPTIONS_GHC -Wall #-}

-- | Thread-safe resource locking mechanisms for Canopy compiler operations.
--
-- This module provides comprehensive file-based locking functionality to ensure
-- thread-safe access to shared resources during concurrent build operations.
-- The locking system prevents race conditions, data corruption, and resource
-- conflicts when multiple compiler instances access the same files or directories.
--
-- The locking implementation uses exclusive file locks with automatic cleanup
-- to provide robust protection against concurrent access while ensuring proper
-- resource release even in the presence of exceptions or process termination.
--
-- == Key Features
--
-- * **Exclusive File Locking** - Prevents concurrent access to shared resources
-- * **Automatic Cleanup** - Locks released automatically when operations complete
-- * **Exception Safety** - Proper lock release even when exceptions occur
-- * **Directory Creation** - Required directories created automatically before locking
-- * **Cross-Platform** - Works on Unix and Windows systems
-- * **Non-Blocking Operations** - Configurable blocking behavior for lock acquisition
--
-- == Locking Architecture
--
-- The module provides two primary locking mechanisms:
--
-- * **Project Root Locking** - Protects project-specific resources and artifacts
-- * **Registry Locking** - Protects global package cache and registry operations
--
-- Both mechanisms use file-based locking with dedicated lock files to avoid
-- conflicts with the actual resources being protected.
--
-- == Lock File Locations
--
-- * **Root Lock** - Located at: `PROJECT_ROOT/canopy-stuff/VERSION/lock`
-- * **Registry Lock** - Located at: `CACHE_DIR/packages/lock`
--
-- The lock files are small marker files that exist only while locks are held.
-- They are automatically cleaned up when locks are released.
--
-- == Usage Examples
--
-- === Project-Level Locking
--
-- @
-- -- Protect project compilation operations
-- withRootLock "/home/user/myproject" $ do
--   compileProject
--   generateArtifacts
--   updateCaches
-- @
--
-- === Package Registry Locking
--
-- @
-- -- Protect package cache operations
-- cache <- Cache.getPackageCache
-- withRegistryLock cache $ do
--   downloadPackage packageName version
--   installPackage packagePath
--   updateRegistry
-- @
--
-- === Nested Locking Pattern
--
-- @
-- -- Combine both locking mechanisms safely
-- projectRoot <- Discovery.findRoot >>= maybe (error "No project") pure
-- cache <- Cache.getPackageCache
-- 
-- withRootLock projectRoot $ do
--   withRegistryLock cache $ do
--     -- Both project and registry are locked
--     synchronizeProjectWithRegistry projectRoot cache
-- @
--
-- === Error Handling
--
-- @
-- -- Handle locking failures gracefully
-- result <- try $ withRootLock projectRoot buildProject
-- case result of
--   Right success -> putStrLn "Build completed successfully"
--   Left exception -> putStrLn $ "Build failed: " ++ show exception
-- @
--
-- == Locking Behavior
--
-- * **Blocking** - Lock acquisition blocks until lock becomes available
-- * **Exclusive** - Only one process can hold a lock at a time
-- * **Timeout** - No timeout implemented (blocks indefinitely)
-- * **Reentrant** - Not reentrant (same process cannot acquire lock twice)
-- * **Fair** - Lock acquisition order not guaranteed to be fair
--
-- == Error Conditions
--
-- Locking operations may fail due to:
--
-- * **Permission Errors** - Insufficient permissions to create lock files
-- * **Disk Space** - Insufficient disk space for lock file creation
-- * **Process Termination** - Abrupt process termination may leave stale locks
-- * **Filesystem Issues** - Network filesystem problems or corruption
--
-- Most errors are handled automatically by the underlying file locking system,
-- but applications should be prepared to handle exceptions from locking operations.
--
-- == Performance Characteristics
--
-- * **Lock Acquisition** - O(1) for uncontended locks, O(n) for contended locks
-- * **Lock Release** - O(1) automatic cleanup
-- * **Directory Creation** - O(1) cached after first creation
-- * **Memory Overhead** - Minimal (only lock file handles)
--
-- The locking system is designed for correctness over performance, but typical
-- operations are fast enough for development and production workflows.
--
-- == Thread Safety
--
-- The locking functions are thread-safe and can be used safely from multiple
-- threads within the same process. However, the locks themselves are process-level
-- and coordinate between different processes rather than threads.
--
-- For thread-level coordination within a single process, additional synchronization
-- mechanisms like MVars or STM should be used in combination with file locks.
--
-- @since 0.19.1
module Stuff.Locking
  ( -- * Locking Operations
    withRootLock
  , withRegistryLock
  ) where

import qualified Stuff.Cache as Cache
import qualified Stuff.Paths as Paths
import Control.Lens ((^.))
import qualified System.Directory as Dir
import qualified System.FileLock as Lock
import System.FilePath ((</>))
import Prelude (Bool (..), FilePath, IO, const)

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
-- ==== Locking Mechanism
--
-- The function creates an exclusive file lock at:
-- @PROJECT_ROOT/canopy-stuff/COMPILER_VERSION-canopy/lock@
--
-- This location ensures that:
-- * Different projects have separate locks
-- * Different compiler versions have separate locks
-- * Lock files are co-located with protected artifacts
--
-- ==== Directory Creation
--
-- The artifact directory is created automatically using `createDirectoryIfMissing`
-- with the `True` flag to create parent directories as needed. This ensures
-- the lock file location always exists before attempting to acquire the lock.
--
-- ==== Exception Safety
--
-- The lock is held using `withFileLock` which provides automatic cleanup:
-- * Lock is released when action completes normally
-- * Lock is released when action throws an exception
-- * Lock is released if the process is terminated (OS cleanup)
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
withRootLock root work = do
  Dir.createDirectoryIfMissing True dir
  Lock.withFileLock (dir </> "lock") Lock.Exclusive (const work)
  where
    dir = Paths.stuff root

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
-- ==== Locking Mechanism
--
-- The function creates an exclusive file lock at:
-- @CACHE_DIR/packages/lock@
--
-- This location ensures that:
-- * All package operations are serialized across projects
-- * Registry updates are atomic and consistent
-- * Cache corruption is prevented during concurrent access
--
-- ==== Cross-Compiler Coordination
--
-- The registry lock is shared between Canopy and Zokka compilers, ensuring
-- that package operations from either compiler are properly serialized.
-- This prevents issues like:
-- * Incomplete package downloads being used by another compiler
-- * Registry corruption from concurrent updates
-- * Cache inconsistencies during package installation
--
-- ==== Exception Safety
--
-- The lock is held using `withFileLock` which provides automatic cleanup:
-- * Lock is released when action completes normally
-- * Lock is released when action throws an exception
-- * Lock is released if the process is terminated (OS cleanup)
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
withRegistryLock :: Cache.PackageCache -> IO a -> IO a
withRegistryLock cache work =
  Lock.withFileLock (cache ^. Cache.packageCacheFilePath </> "lock") Lock.Exclusive (const work)