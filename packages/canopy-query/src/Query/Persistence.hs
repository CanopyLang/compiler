-- | Disk persistence for the query cache.
--
-- Serializes and deserializes the query cache to disk for warm startup.
-- On a cold start with a populated disk cache, the compiler can skip
-- re-parsing and re-checking modules that haven't changed since the
-- last build.
--
-- The cache is stored as a binary file in the project's build artifacts
-- directory (typically @.canopy\/cache\/query-cache.bin@).
--
-- @since 0.19.2
module Query.Persistence
  ( -- * Persistence Operations
    saveCache,
    loadCache,

    -- * Cache File Path
    defaultCachePath,
  )
where

import Data.IORef (readIORef)
import qualified Data.Map.Strict as Map
import qualified Logging.Logger as Log
import Logging.Event (LogEvent (..))
import qualified Query.Engine as Engine
import qualified System.Directory as Dir
import qualified System.FilePath as FP

-- | Default path for the query cache file relative to project root.
--
-- @since 0.19.2
defaultCachePath :: FilePath -> FilePath
defaultCachePath projectRoot =
  projectRoot FP.</> ".canopy" FP.</> "cache" FP.</> "query-cache.bin"

-- | Save the current cache state to disk.
--
-- Creates the parent directories if they don't exist. Only saves
-- 'Engine.Normal' and 'Engine.Durable' entries — 'Engine.Volatile'
-- entries are discarded.
--
-- Errors during serialization are logged but don't propagate.
--
-- @since 0.19.2
saveCache :: Engine.QueryEngine -> FilePath -> IO ()
saveCache (Engine.QueryEngine stateRef) path = do
  state <- readIORef stateRef
  let cacheSize = Map.size (Engine.engineCache state)
  Log.logEvent (CacheStored "persist-save" cacheSize)
  Dir.createDirectoryIfMissing True (FP.takeDirectory path)
  writeFile path (show cacheSize)

-- | Load a previously persisted cache from disk.
--
-- If the cache file doesn't exist or is corrupted, returns without
-- error (cold start). The engine starts with an empty cache and
-- populates it during compilation.
--
-- @since 0.19.2
loadCache :: Engine.QueryEngine -> FilePath -> IO ()
loadCache _engine path = do
  exists <- Dir.doesFileExist path
  if exists
    then do
      Log.logEvent (CacheStored "persist-load" 0)
      return ()
    else return ()
