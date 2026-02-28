{-# LANGUAGE DeriveGeneric #-}

-- | Incremental compilation support using content hashing.
--
-- This module implements incremental compilation by:
--
-- * Tracking content hashes of source files
-- * Detecting changes in dependencies
-- * Skipping unchanged modules
-- * Invalidating transitive dependencies
--
-- Follows the NEW query engine pattern with pure data structures.
--
-- @since 0.19.1
module Builder.Incremental
  ( -- * Cache Types
    BuildCache (..),
    CacheEntry (..),

    -- * Cache Operations
    emptyCache,
    loadCache,
    saveCache,
    lookupCache,
    insertCache,

    -- * Change Detection
    needsRecompile,
    invalidateModule,
    invalidateTransitive,

    -- * Interface-Aware Caching
    getInterfaceHash,
    interfaceUnchanged,

    -- * Cache Management
    pruneCache,
    getCacheStats,
  )
where

import qualified Builder.Hash as Hash
import qualified Canopy.ModuleName as ModuleName
import Data.Aeson (FromJSON (..), ToJSON (..), (.:), (.:?), (.=))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BSL
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Data.Set as Set
import Data.Time.Clock (UTCTime, addUTCTime, getCurrentTime)
import GHC.Generics (Generic)
import qualified Data.Text as Text
import Logging.Event (LogEvent (..), Phase (..))
import qualified Logging.Logger as Log
import qualified System.Directory as Dir

-- | Cache entry for a module.
--
-- The 'cacheInterfaceHash' field enables interface-aware cache invalidation:
-- when a module is recompiled but its exported interface (types, values,
-- unions, aliases, binops) is unchanged, downstream dependents skip
-- recompilation because their deps hash remains stable.
data CacheEntry = CacheEntry
  { cacheSourceHash :: !Hash.ContentHash,
    cacheDepsHash :: !Hash.ContentHash,
    cacheArtifactPath :: !FilePath,
    cacheTimestamp :: !UTCTime,
    cacheInterfaceHash :: !(Maybe Hash.ContentHash)
  }
  deriving (Show, Eq, Generic)

instance ToJSON CacheEntry where
  toJSON entry =
    Aeson.object
      [ "sourceHash" .= Hash.toHexString (Hash.hashValue (cacheSourceHash entry)),
        "depsHash" .= Hash.toHexString (Hash.hashValue (cacheDepsHash entry)),
        "artifactPath" .= cacheArtifactPath entry,
        "timestamp" .= cacheTimestamp entry,
        "interfaceHash" .= fmap (Hash.toHexString . Hash.hashValue) (cacheInterfaceHash entry)
      ]

instance FromJSON CacheEntry where
  parseJSON = Aeson.withObject "CacheEntry" (\obj -> do
    sourceHashStr <- obj .: "sourceHash"
    depsHashStr <- obj .: "depsHash"
    artifactPath <- obj .: "artifactPath"
    timestamp <- obj .: "timestamp"
    maybeIfaceHashStr <- obj Aeson..:? "interfaceHash"
    let srcHash = maybe (Hash.HashValue mempty) id (Hash.fromHexString sourceHashStr)
        depsHash = maybe (Hash.HashValue mempty) id (Hash.fromHexString depsHashStr)
        ifaceHash = maybeIfaceHashStr >>= Hash.fromHexString
    return CacheEntry
      { cacheSourceHash = Hash.ContentHash srcHash "loaded",
        cacheDepsHash = Hash.ContentHash depsHash "loaded",
        cacheArtifactPath = artifactPath,
        cacheTimestamp = timestamp,
        cacheInterfaceHash = fmap (\hv -> Hash.ContentHash hv "interface") ifaceHash
      })

-- | Build cache for incremental compilation.
data BuildCache = BuildCache
  { cacheEntries :: !(Map ModuleName.Raw CacheEntry),
    cacheVersion :: !String,
    cacheCreated :: !UTCTime
  }
  deriving (Show, Eq, Generic)

-- Custom serialization to handle ModuleName.Raw keys
instance ToJSON BuildCache where
  toJSON cache =
    Aeson.object
      [ "entries" .= map serializeEntry (Map.toList (cacheEntries cache)),
        "version" .= cacheVersion cache,
        "created" .= cacheCreated cache
      ]
    where
      serializeEntry (moduleName, entry) =
        Aeson.object
          [ "module" .= show moduleName,
            "entry" .= entry
          ]

instance FromJSON BuildCache where
  parseJSON = Aeson.withObject "BuildCache" (\obj -> do
    entriesList <- obj .: "entries"
    version <- obj .: "version"
    created <- obj .: "created"
    entries <- mapM deserializeEntry entriesList
    return BuildCache
      { cacheEntries = Map.fromList entries,
        cacheVersion = version,
        cacheCreated = created
      })
    where
      deserializeEntry = Aeson.withObject "Entry" (\entryObj -> do
        moduleStr <- entryObj .: "module"
        entry <- entryObj .: "entry"
        -- Parse module name from string using Name.fromChars
        let moduleName = Name.fromChars moduleStr
        return (moduleName, entry))

-- | Create empty cache.
emptyCache :: IO BuildCache
emptyCache = do
  now <- getCurrentTime
  return
    BuildCache
      { cacheEntries = Map.empty,
        cacheVersion = "0.19.1",
        cacheCreated = now
      }

-- | Load cache from disk using JSON deserialization.
loadCache :: FilePath -> IO (Maybe BuildCache)
loadCache path = do
  Log.logEvent (CacheMiss PhaseCache (Text.pack ("loading from: " ++ path)))
  exists <- Dir.doesFileExist path
  if exists
    then do
      contents <- BSL.readFile path
      case Aeson.eitherDecode contents of
        Left err -> do
          Log.logEvent (BuildFailed (Text.pack ("Cache decode error: " ++ err)))
          return Nothing
        Right cache -> do
          Log.logEvent (CacheHit PhaseCache (Text.pack (show (Map.size (cacheEntries cache)) ++ " entries loaded")))
          return (Just cache)
    else do
      Log.logEvent (CacheMiss PhaseCache (Text.pack "no cache file found"))
      return Nothing

-- | Save cache to disk using JSON serialization.
saveCache :: FilePath -> BuildCache -> IO ()
saveCache path cache = do
  Log.logEvent (CacheStored (Text.pack path) (Map.size (cacheEntries cache)))
  let json = Aeson.encode cache
  BSL.writeFile path json
  Log.logEvent (InterfaceSaved path)

-- | Lookup module in cache.
lookupCache :: BuildCache -> ModuleName.Raw -> Maybe CacheEntry
lookupCache cache moduleName =
  Map.lookup moduleName (cacheEntries cache)

-- | Insert module into cache.
insertCache :: BuildCache -> ModuleName.Raw -> CacheEntry -> BuildCache
insertCache cache moduleName entry =
  cache {cacheEntries = Map.insert moduleName entry (cacheEntries cache)}

-- | Check if module needs recompilation.
needsRecompile ::
  BuildCache ->
  ModuleName.Raw ->
  Hash.ContentHash -> -- ^ Current source hash
  Hash.ContentHash -> -- ^ Current deps hash
  Bool
needsRecompile cache moduleName sourceHash depsHash =
  case lookupCache cache moduleName of
    Nothing ->
      True -- Not in cache, must compile
    Just entry
      | Hash.hashChanged sourceHash (cacheSourceHash entry) ->
          True
      | Hash.hashChanged depsHash (cacheDepsHash entry) ->
          True
      | otherwise ->
          False

-- | Invalidate a module in cache.
invalidateModule :: BuildCache -> ModuleName.Raw -> BuildCache
invalidateModule cache moduleName =
  cache {cacheEntries = Map.delete moduleName (cacheEntries cache)}

-- | Invalidate module and all transitive dependents.
--
-- Uses a Set-based work queue for O(V + E) traversal instead of
-- the previous list-append approach which was O(V^2).
invalidateTransitive ::
  BuildCache ->
  ModuleName.Raw ->
  Map ModuleName.Raw [ModuleName.Raw] -> -- ^ Reverse dependency map
  BuildCache
invalidateTransitive cache moduleName reverseDeps =
  let toInvalidate = collectTransitive (Set.singleton moduleName) Set.empty
      newEntries = Set.foldl' (flip Map.delete) (cacheEntries cache) toInvalidate
   in cache {cacheEntries = newEntries}
  where
    collectTransitive pending visited
      | Set.null pending = visited
      | otherwise =
          let (current, rest) = Set.deleteFindMin pending
           in if Set.member current visited
                then collectTransitive rest visited
                else
                  let deps = Set.fromList (maybe [] id (Map.lookup current reverseDeps))
                   in collectTransitive (Set.union rest deps) (Set.insert current visited)

-- | Retrieve the cached interface hash for a module, if available.
--
-- Returns 'Nothing' when the module is not in the cache or when the
-- cache entry predates interface-hash tracking.
getInterfaceHash :: BuildCache -> ModuleName.Raw -> Maybe Hash.ContentHash
getInterfaceHash cache moduleName =
  lookupCache cache moduleName >>= cacheInterfaceHash

-- | Check whether a module's interface is unchanged between builds.
--
-- Compares the newly computed interface hash against the cached one.
-- When both exist and are equal, downstream dependents can skip
-- recompilation because the exported API has not changed.
interfaceUnchanged :: BuildCache -> ModuleName.Raw -> Hash.ContentHash -> Bool
interfaceUnchanged cache moduleName newIfaceHash =
  maybe False (Hash.hashesEqual newIfaceHash) (getInterfaceHash cache moduleName)

-- | Prune old entries from cache.
pruneCache :: BuildCache -> UTCTime -> BuildCache
pruneCache cache cutoff =
  let validEntries = Map.filter (isRecent cutoff) (cacheEntries cache)
   in cache {cacheEntries = validEntries}
  where
    isRecent cutoffTime entry = cacheTimestamp entry > cutoffTime

-- | Get cache statistics.
--
-- Returns (total entries, valid entries, expired entries).
-- Hit/miss tracking is handled externally via IORefs in the
-- compilation pipeline (see Compiler.compileModulesInOrder).
getCacheStats :: BuildCache -> IO (Int, Int, Int)
getCacheStats cache = do
  now <- getCurrentTime
  let entries = cacheEntries cache
      totalEntries = Map.size entries
      recentCutoff = addUTCTime (-3600) now
      validEntries = Map.size (Map.filter (\e -> cacheTimestamp e > recentCutoff) entries)
      expiredEntries = totalEntries - validEntries
  return (totalEntries, validEntries, expiredEntries)
