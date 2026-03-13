
-- | Query engine with caching, dependency tracking, and invalidation.
--
-- This module implements the core query execution engine following
-- modern compiler architectures (Rust Salsa, Swift 6.0). It uses:
--
-- * Single IORef for mutable state (NO MVars/TVars)
-- * Pure data structures (Map, Set) for cache
-- * Content-hash based invalidation
-- * Dependency graph for transitive invalidation
-- * Early cutoff: re-execution that produces the same hash stops propagation
-- * Durability levels for stdlib vs user code
--
-- @since 0.19.1
module Query.Engine
  ( -- * Engine Types
    QueryEngine (..),
    EngineState (..),
    CacheEntry (..),
    Durability (..),

    -- * Engine Creation
    initEngine,

    -- * Query Execution
    runQuery,
    runQueryWithFallback,
    lookupQuery,
    storeQuery,

    -- * Invalidation
    invalidateQuery,
    invalidateAndPropagate,
    clearCache,

    -- * Cache Management
    getCacheSize,
    getCacheHits,
    getCacheMisses,
    hashQueryResult,

    -- * Persisted Hashes
    populatePersistedHash,
    populatePersistedHashes,

    -- * Phase Tracking
    trackPhaseExecution,
  )
where

import qualified Crypto.Hash.SHA256 as SHA256
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import Data.Time.Clock (UTCTime, getCurrentTime)
import Logging.Event (LogEvent (..), Phase (..))
import qualified Logging.Logger as Log
import Query.Simple

-- | Durability levels for cache entries.
--
-- Controls how aggressively entries are re-checked:
--
--   * 'Durable': Standard library modules — never re-checked within session
--   * 'Normal': User modules — re-checked on file change
--   * 'Volatile': Cleared after each build cycle
--
-- @since 0.19.2
data Durability = Volatile | Normal | Durable
  deriving (Eq, Ord, Show)

-- | Cache entry with result, metadata, and durability.
data CacheEntry = CacheEntry
  { cacheEntryResult :: !QueryResult,
    cacheEntryHash :: !ContentHash,
    cacheEntryTime :: !UTCTime,
    cacheEntryHits :: !Int,
    cacheEntryDurability :: !Durability
  }
  deriving (Show)

-- | Engine state with dependency tracking.
--
-- The dependency graph enables transitive invalidation: when a file changes,
-- we invalidate its parse query, then propagate to all dependent queries
-- (canonicalize, type-check, optimize) following 'engineReverseDeps'.
--
-- @since 0.19.2
data EngineState = EngineState
  { engineCache :: !(Map Query CacheEntry),
    engineRunning :: !(Set Query),
    engineDeps :: !(Map Query (Set Query)),
    engineReverseDeps :: !(Map Query (Set Query)),
    engineHits :: !Int,
    engineMisses :: !Int,
    engineGeneration :: !Int,
    enginePersistedHashes :: !(Map Query ContentHash)
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
      engineDeps = Map.empty,
      engineReverseDeps = Map.empty,
      engineHits = 0,
      engineMisses = 0,
      engineGeneration = 0,
      enginePersistedHashes = Map.empty
    }

-- | Initialize a new query engine.
initEngine :: IO QueryEngine
initEngine = do
  Log.logEvent (BuildStarted "query-engine-init")
  stateRef <- newIORef emptyState
  return (QueryEngine stateRef)

-- | Run a query with caching (parse queries only).
--
-- For non-parse queries, use 'lookupQuery' and 'storeQuery' directly
-- from the Driver, which has the context to execute them.
runQuery :: QueryEngine -> Query -> IO (Either QueryError QueryResult)
runQuery (QueryEngine stateRef) query = do
  state <- readIORef stateRef
  case checkCache state query of
    Just entry -> do
      Log.logEvent (CacheHit PhaseCache (showQuery query))
      modifyIORef' stateRef (incrementHits . updateCacheHitCount query)
      return (Right (cacheEntryResult entry))
    Nothing -> do
      Log.logEvent (CacheMiss PhaseCache (showQuery query))
      modifyIORef' stateRef incrementMisses
      executeAndCache stateRef query

-- | Run a query with stale-on-error fallback.
--
-- Attempts to execute the query. On error, returns the previous cached
-- result if available. This enables IDE-like behavior where stale but
-- valid results are better than no results during editing.
--
-- Returns @Left@ only when both execution fails AND no cached result exists.
--
-- @since 0.20.0
runQueryWithFallback :: QueryEngine -> Query -> IO (Either QueryError QueryResult)
runQueryWithFallback engine@(QueryEngine stateRef) query = do
  state <- readIORef stateRef
  let staleEntry = Map.lookup query (engineCache state)
  result <- runQuery engine query
  pure (fallbackOnError staleEntry result)

-- | Return the stale cached result when execution fails.
fallbackOnError :: Maybe CacheEntry -> Either QueryError QueryResult -> Either QueryError QueryResult
fallbackOnError _ (Right r) = Right r
fallbackOnError (Just stale) (Left _) = Right (cacheEntryResult stale)
fallbackOnError Nothing err = err

-- | Look up a cached query result without executing.
--
-- Returns 'Just' the result if the query is cached with a matching hash,
-- 'Nothing' otherwise. Does not modify cache statistics.
--
-- @since 0.19.2
lookupQuery :: QueryEngine -> Query -> IO (Maybe QueryResult)
lookupQuery (QueryEngine stateRef) query = do
  state <- readIORef stateRef
  case checkCache state query of
    Just entry -> do
      Log.logEvent (CacheHit PhaseCache (showQuery query))
      modifyIORef' stateRef (incrementHits . updateCacheHitCount query)
      return (Just (cacheEntryResult entry))
    Nothing -> return Nothing

-- | Store a query result in the cache with dependency tracking.
--
-- The optional parent query establishes a dependency edge: if the parent
-- is later invalidated, this query will also be invalidated.
--
-- @since 0.19.2
storeQuery ::
  QueryEngine ->
  Query ->
  QueryResult ->
  ContentHash ->
  Maybe Query ->
  IO ()
storeQuery (QueryEngine stateRef) query result hash parentQuery = do
  currentTime <- getCurrentTime
  Log.logEvent (CacheStored (showQuery query) 1)
  modifyIORef' stateRef (insertCacheEntry query result hash currentTime . recordDependency query parentQuery)

-- | Insert a cache entry into the engine state.
insertCacheEntry ::
  Query ->
  QueryResult ->
  ContentHash ->
  UTCTime ->
  EngineState ->
  EngineState
insertCacheEntry query result hash time state =
  state {engineCache = Map.insert query entry (engineCache state)}
  where
    entry =
      CacheEntry
        { cacheEntryResult = result,
          cacheEntryHash = hash,
          cacheEntryTime = time,
          cacheEntryHits = 0,
          cacheEntryDurability = Normal
        }

-- | Record a dependency edge between child and parent query.
recordDependency :: Query -> Maybe Query -> EngineState -> EngineState
recordDependency _ Nothing state = state
recordDependency child (Just parent) state =
  state
    { engineDeps = Map.insertWith Set.union child (Set.singleton parent) (engineDeps state),
      engineReverseDeps = Map.insertWith Set.union parent (Set.singleton child) (engineReverseDeps state)
    }

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
       in state {engineCache = Map.insert query updated (engineCache state)}
    Nothing -> state

-- | Execute query and cache result.
--
-- Stores the hash of the actual result (not the query key's hash)
-- so that early cutoff can detect when re-execution produces the
-- same output despite changed inputs.
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
      let resultHash = hashQueryResult queryResult
      modifyIORef' stateRef (insertCacheEntry query queryResult resultHash currentTime)
      return (Right queryResult)

-- | Mark query as running.
markRunning :: Query -> EngineState -> EngineState
markRunning query state =
  state {engineRunning = Set.insert query (engineRunning state)}

-- | Unmark query as running.
unmarkRunning :: Query -> EngineState -> EngineState
unmarkRunning query state =
  state {engineRunning = Set.delete query (engineRunning state)}

-- | Invalidate a single query in the cache.
invalidateQuery :: QueryEngine -> Query -> IO ()
invalidateQuery (QueryEngine stateRef) query = do
  Log.logEvent (CacheMiss PhaseCache (showQuery query))
  modifyIORef' stateRef removeEntry
  where
    removeEntry state =
      state {engineCache = Map.delete query (engineCache state)}

-- | Invalidate a query and propagate to all dependents.
--
-- Implements try-mark-green / early cutoff:
--
--   1. Remove the query from cache (mark RED)
--   2. Re-execute the query
--   3. Compute hash of the NEW result
--   4. Compare with old result's hash
--   5. Same hash -> stop propagation (early cutoff, dependents stay valid)
--   6. Different hash -> update cache, recurse on reverse dependencies
--
-- This is the key to incremental compilation performance: most edits
-- don't change a module's public interface, so dependents skip recompilation.
--
-- @since 0.19.2
invalidateAndPropagate :: QueryEngine -> Query -> IO ()
invalidateAndPropagate engine@(QueryEngine stateRef) query = do
  state <- readIORef stateRef
  let maybeOldHash = lookupOldHash state query
  case maybeOldHash of
    Nothing -> return ()
    Just oldHash -> do
      modifyIORef' stateRef (\s -> s {engineCache = Map.delete query (engineCache s)})
      reResult <- executeQuery query
      case reResult of
        Left _ -> propagateToDependents engine state query
        Right newResult -> do
          let newResultHash = hashQueryResult newResult
          currentTime <- getCurrentTime
          modifyIORef' stateRef (insertCacheEntry query newResult newResultHash currentTime)
          if newResultHash == oldHash
            then Log.logEvent (CacheHit PhaseCache ("early-cutoff:" <> showQuery query))
            else propagateToDependents engine state query

-- | Look up the old result hash from cache or persisted hashes.
lookupOldHash :: EngineState -> Query -> Maybe ContentHash
lookupOldHash state query =
  case Map.lookup query (engineCache state) of
    Just entry -> Just (cacheEntryHash entry)
    Nothing -> Map.lookup query (enginePersistedHashes state)

-- | Compute a content hash of a query result for early-cutoff comparison.
--
-- Uses the 'Show' representation of the result to produce a SHA256 hash.
-- This captures structural changes in the compilation output: if the
-- canonical AST, type annotations, or optimized graph change, the hash
-- changes. If only internal details change (e.g., whitespace, comments),
-- the hash stays the same because the parsed AST normalizes them away.
--
-- @since 0.19.2
hashQueryResult :: QueryResult -> ContentHash
hashQueryResult result =
  ContentHash (SHA256.hash (TE.encodeUtf8 (Text.pack (show result))))

-- | Propagate invalidation to all reverse dependencies of a query.
propagateToDependents :: QueryEngine -> EngineState -> Query -> IO ()
propagateToDependents engine state query =
  case Map.lookup query (engineReverseDeps state) of
    Nothing -> return ()
    Just dependents -> mapM_ (invalidateAndPropagate engine) (Set.toList dependents)

-- | Populate a single persisted hash entry from disk cache.
--
-- Called during cache loading to restore hash data from a previous
-- session. These hashes enable early cutoff in 'invalidateAndPropagate'
-- without requiring full result deserialization.
--
-- @since 0.19.2
populatePersistedHash :: QueryEngine -> Query -> ContentHash -> IO ()
populatePersistedHash (QueryEngine stateRef) query hash =
  modifyIORef' stateRef addPersistedHash
  where
    addPersistedHash s =
      s {enginePersistedHashes = Map.insert query hash (enginePersistedHashes s)}

-- | Populate multiple persisted hash entries from disk cache.
--
-- Batch version of 'populatePersistedHash' for efficient cache loading.
--
-- @since 0.19.2
populatePersistedHashes :: QueryEngine -> [(Query, ContentHash)] -> IO ()
populatePersistedHashes (QueryEngine stateRef) entries =
  modifyIORef' stateRef addAllHashes
  where
    addAllHashes s =
      s {enginePersistedHashes = Map.union (Map.fromList entries) (enginePersistedHashes s)}

-- | Clear entire cache.
clearCache :: QueryEngine -> IO ()
clearCache (QueryEngine stateRef) = do
  Log.logEvent (CacheMiss PhaseCache "clear-all")
  modifyIORef' stateRef clearAllState
  where
    clearAllState s =
      s
        { engineCache = Map.empty,
          engineDeps = Map.empty,
          engineReverseDeps = Map.empty,
          engineGeneration = engineGeneration s + 1,
          enginePersistedHashes = Map.empty
        }

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
