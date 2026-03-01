{-# LANGUAGE StrictData #-}

-- | Query engine with caching and dependency tracking.
--
-- This module implements the core query execution engine following
-- modern compiler architectures (Rust Salsa, Swift 6.0). It uses:
--
-- * Single IORef for mutable state (NO MVars/TVars)
-- * Pure data structures (Map, Set) for cache
-- * Content-hash based invalidation
-- * Comprehensive debug logging
--
-- @since 0.19.1
module Query.Engine
  ( -- * Engine Types
    QueryEngine (..),
    EngineState (..),
    CacheEntry (..),

    -- * Engine Creation
    initEngine,

    -- * Query Execution
    runQuery,
    invalidateQuery,
    clearCache,

    -- * Cache Management
    getCacheSize,
    getCacheHits,
    getCacheMisses,

    -- * Phase Tracking
    trackPhaseExecution,
  )
where

import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time.Clock (UTCTime, getCurrentTime)
import Logging.Event (LogEvent (..), Phase (..))
import qualified Logging.Logger as Log
import Query.Simple

-- | Cache entry with result and metadata.
data CacheEntry = CacheEntry
  { cacheEntryResult :: !QueryResult,
    cacheEntryHash :: !ContentHash,
    cacheEntryTime :: !UTCTime,
    cacheEntryHits :: !Int
  }
  deriving (Show)

-- | Engine state with pure data structures.
data EngineState = EngineState
  { engineCache :: !(Map Query CacheEntry),
    engineRunning :: !(Set Query),
    engineHits :: !Int,
    engineMisses :: !Int
  }
  deriving (Show)

-- | Query engine with single IORef.
newtype QueryEngine = QueryEngine
  { engineState :: IORef EngineState
  }

-- | Create empty engine state.
emptyState :: EngineState
emptyState =
  EngineState
    { engineCache = Map.empty,
      engineRunning = Set.empty,
      engineHits = 0,
      engineMisses = 0
    }

-- | Initialize a new query engine.
initEngine :: IO QueryEngine
initEngine = do
  Log.logEvent (BuildStarted "query-engine-init")
  stateRef <- newIORef emptyState
  return (QueryEngine stateRef)

-- | Run a query with caching.
runQuery :: QueryEngine -> Query -> IO (Either QueryError QueryResult)
runQuery (QueryEngine stateRef) query = do
  state <- readIORef stateRef
  case checkCache state query of
    Just entry -> do
      Log.logEvent (CacheHit PhaseCache (showQuery query))
      modifyIORef' stateRef incrementHits
      modifyIORef' stateRef (updateCacheHitCount query)
      return (Right (cacheEntryResult entry))
    Nothing -> do
      Log.logEvent (CacheMiss PhaseCache (showQuery query))
      modifyIORef' stateRef incrementMisses
      executeAndCache stateRef query

-- | Check cache for query result.
checkCache :: EngineState -> Query -> Maybe CacheEntry
checkCache state query =
  Map.lookup query (engineCache state)

-- | Increment cache hits.
incrementHits :: EngineState -> EngineState
incrementHits state =
  state {engineHits = engineHits state + 1}

-- | Increment cache misses.
incrementMisses :: EngineState -> EngineState
incrementMisses state =
  state {engineMisses = engineMisses state + 1}

-- | Update cache hit count for entry.
updateCacheHitCount :: Query -> EngineState -> EngineState
updateCacheHitCount query state =
  case Map.lookup query (engineCache state) of
    Just entry ->
      let updated = entry {cacheEntryHits = cacheEntryHits entry + 1}
          newCache = Map.insert query updated (engineCache state)
       in state {engineCache = newCache}
    Nothing -> state

-- | Execute query and cache result.
executeAndCache ::
  IORef EngineState ->
  Query ->
  IO (Either QueryError QueryResult)
executeAndCache stateRef query = do
  modifyIORef' stateRef (markRunning query)

  result <- executeQuery query

  modifyIORef' stateRef (unmarkRunning query)

  case result of
    Left err ->
      return (Left err)
    Right queryResult -> do
      currentTime <- getCurrentTime
      let hash = getQueryHash query
      modifyIORef' stateRef (cacheResult query queryResult hash currentTime)
      return (Right queryResult)

-- | Mark query as running.
markRunning :: Query -> EngineState -> EngineState
markRunning query state =
  state {engineRunning = Set.insert query (engineRunning state)}

-- | Unmark query as running.
unmarkRunning :: Query -> EngineState -> EngineState
unmarkRunning query state =
  state {engineRunning = Set.delete query (engineRunning state)}

-- | Cache query result.
cacheResult ::
  Query ->
  QueryResult ->
  ContentHash ->
  UTCTime ->
  EngineState ->
  EngineState
cacheResult query result hash time state =
  let entry =
        CacheEntry
          { cacheEntryResult = result,
            cacheEntryHash = hash,
            cacheEntryTime = time,
            cacheEntryHits = 0
          }
      newCache = Map.insert query entry (engineCache state)
   in state {engineCache = newCache}

-- | Get hash from query.
getQueryHash :: Query -> ContentHash
getQueryHash (ParseModuleQuery _ hash _) = hash

-- | Invalidate a query in the cache.
invalidateQuery :: QueryEngine -> Query -> IO ()
invalidateQuery (QueryEngine stateRef) query = do
  Log.logEvent (CacheMiss PhaseCache (showQuery query))
  modifyIORef' stateRef removeFromCache
  where
    removeFromCache state =
      state {engineCache = Map.delete query (engineCache state)}

-- | Clear entire cache.
clearCache :: QueryEngine -> IO ()
clearCache (QueryEngine stateRef) = do
  Log.logEvent (CacheMiss PhaseCache "clear-all")
  modifyIORef' stateRef (\s -> s {engineCache = Map.empty})

-- | Get cache size.
getCacheSize :: QueryEngine -> IO Int
getCacheSize (QueryEngine stateRef) = do
  state <- readIORef stateRef
  return (Map.size (engineCache state))

-- | Get cache hit count.
getCacheHits :: QueryEngine -> IO Int
getCacheHits (QueryEngine stateRef) = do
  state <- readIORef stateRef
  return (engineHits state)

-- | Get cache miss count.
getCacheMisses :: QueryEngine -> IO Int
getCacheMisses (QueryEngine stateRef) = do
  state <- readIORef stateRef
  return (engineMisses state)

-- | Track execution of a compilation phase through the query engine.
--
-- Records an uncached phase execution (canonicalization, type checking, etc.)
-- in the engine's statistics. This ensures cache hit rate calculations
-- accurately reflect all compilation work, not just parse queries.
--
-- @since 0.19.1
trackPhaseExecution :: QueryEngine -> String -> IO ()
trackPhaseExecution (QueryEngine stateRef) phaseName = do
  Log.logEvent (CompilePhaseEnter PhaseBuild (showText phaseName))
  modifyIORef' stateRef incrementMisses

-- | Convert a Query to Text for logging.
showQuery :: Query -> Text
showQuery = Text.pack . show

-- | Convert a String to Text.
showText :: String -> Text
showText = Text.pack
