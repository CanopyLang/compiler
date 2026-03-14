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
-- The build cache uses a versioned binary format ("BCCH" magic header)
-- for fast serialization. On first load after upgrading from JSON,
-- the module falls back to JSON parsing and re-saves as binary.
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
import Data.Aeson (FromJSON (..), ToJSON (..), (.:), (.=))
import qualified Data.Aeson as Aeson
import qualified Data.Binary as Binary
import qualified Data.ByteString.Lazy as BSL
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Data.Set as Set
import Data.Time.Clock (UTCTime)
import qualified Data.Time.Clock as Time
import qualified Data.Time.Clock.POSIX as POSIX
import Data.Word (Word16)
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

-- BINARY INSTANCES

-- | Binary encoding for 'UTCTime' via POSIX seconds.
--
-- Converts to/from 'POSIXTime' (a 'NominalDiffTime') for compact
-- binary representation. Uses 'Double' serialization (8 bytes)
-- instead of ISO 8601 text strings.
--
-- @since 0.19.2
putUTCTime :: UTCTime -> Binary.Put
putUTCTime t = Binary.put (realToFrac (POSIX.utcTimeToPOSIXSeconds t) :: Double)

-- | Decode a 'UTCTime' from its binary POSIX seconds representation.
--
-- @since 0.19.2
getUTCTime :: Binary.Get UTCTime
getUTCTime = POSIX.posixSecondsToUTCTime . realToFrac <$> (Binary.get :: Binary.Get Double)

-- | Binary encoding for 'CacheEntry'.
--
-- Serializes all fields directly using their respective Binary instances,
-- avoiding the JSON overhead of hex-encoding hashes and text timestamps.
--
-- @since 0.19.2
instance Binary.Binary CacheEntry where
  put entry = do
    Binary.put (cacheSourceHash entry)
    Binary.put (cacheDepsHash entry)
    Binary.put (cacheArtifactPath entry)
    putUTCTime (cacheTimestamp entry)
    Binary.put (cacheInterfaceHash entry)
  get =
    CacheEntry
      <$> Binary.get
      <*> Binary.get
      <*> Binary.get
      <*> getUTCTime
      <*> Binary.get

-- | Build cache for incremental compilation.
data BuildCache = BuildCache
  { cacheEntries :: !(Map ModuleName.Raw CacheEntry),
    cacheVersion :: !String,
    cacheCreated :: !UTCTime
  }
  deriving (Show, Eq, Generic)

-- | Binary encoding for 'BuildCache'.
--
-- Serializes the map entries directly using the Binary instance for
-- 'ModuleName.Raw' (which uses 'Utf8.putUnder256') and 'CacheEntry'.
--
-- @since 0.19.2
instance Binary.Binary BuildCache where
  put cache = do
    Binary.put (cacheEntries cache)
    Binary.put (cacheVersion cache)
    putUTCTime (cacheCreated cache)
  get =
    BuildCache
      <$> Binary.get
      <*> Binary.get
      <*> getUTCTime

-- JSON INSTANCES (kept for legacy migration)

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
  parseJSON = Aeson.withObject "CacheEntry" parseEntry
    where
      parseEntry obj = do
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
          }

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
  parseJSON = Aeson.withObject "BuildCache" parseBuildCache
    where
      parseBuildCache obj = do
        entriesList <- obj .: "entries"
        version <- obj .: "version"
        created <- obj .: "created"
        entries <- mapM deserializeEntry entriesList
        return BuildCache
          { cacheEntries = Map.fromList entries,
            cacheVersion = version,
            cacheCreated = created
          }
      deserializeEntry = Aeson.withObject "Entry" (\entryObj -> do
        moduleStr <- entryObj .: "module"
        entry <- entryObj .: "entry"
        let moduleName = Name.fromChars moduleStr
        return (moduleName, entry))

-- VERSIONED BINARY FORMAT

-- | Magic bytes identifying a build cache file: "BCCH" in ASCII.
--
-- Used to distinguish the binary format from legacy JSON caches.
-- When the magic header is absent, the loader falls back to JSON
-- parsing for seamless migration.
--
-- @since 0.19.2
buildCacheMagic :: BSL.ByteString
buildCacheMagic = BSL.pack [0x42, 0x43, 0x43, 0x48]

-- | Current binary schema version for the build cache.
--
-- Bump this when the Binary encoding of 'BuildCache' or 'CacheEntry'
-- changes to force cache invalidation on upgrade.
--
-- @since 0.19.2
buildCacheSchemaVersion :: Word16
buildCacheSchemaVersion = 1

-- | Minimum header size: 4 (magic) + 2 (schema version).
--
-- @since 0.19.2
buildCacheHeaderSize :: Int
buildCacheHeaderSize = 6

-- | Encode a 'BuildCache' to the versioned binary format.
--
-- Layout: @"BCCH" (4 bytes) ++ schema version (2 bytes) ++ payload@.
--
-- @since 0.19.2
encodeBuildCache :: BuildCache -> BSL.ByteString
encodeBuildCache cache =
  buildCacheMagic
    <> Binary.encode buildCacheSchemaVersion
    <> Binary.encode cache

-- | Decode a 'BuildCache' from the versioned binary format.
--
-- Validates the magic header and schema version before decoding
-- the payload. Returns 'Left' with a diagnostic message on any
-- format mismatch or decode failure.
--
-- @since 0.19.2
decodeBuildCache :: BSL.ByteString -> Either String BuildCache
decodeBuildCache bytes
  | BSL.length bytes < fromIntegral buildCacheHeaderSize =
      Left "file too short for binary cache format"
  | BSL.take 4 bytes /= buildCacheMagic =
      Left "not a binary cache (missing BCCH magic header)"
  | otherwise =
      decodeSchemaAndPayload (BSL.drop 4 bytes)

-- | Decode the schema version and payload after the magic header.
--
-- @since 0.19.2
decodeSchemaAndPayload :: BSL.ByteString -> Either String BuildCache
decodeSchemaAndPayload bytes =
  case Binary.decodeOrFail bytes of
    Left (_, _, msg) -> Left ("schema version decode: " ++ msg)
    Right (rest, _, ver)
      | ver /= buildCacheSchemaVersion ->
          Left (schemaMismatchMsg ver)
      | otherwise ->
          decodePayload rest
  where
    schemaMismatchMsg :: Word16 -> String
    schemaMismatchMsg ver =
      "cache schema v" ++ show ver
        ++ " but compiler expects v"
        ++ show buildCacheSchemaVersion

-- | Decode the cache payload after schema version validation.
--
-- @since 0.19.2
decodePayload :: BSL.ByteString -> Either String BuildCache
decodePayload rest =
  case Binary.decodeOrFail rest of
    Left (_, _, msg) -> Left ("payload decode: " ++ msg)
    Right (_, _, cache) -> Right cache

-- | Try loading a legacy JSON cache for migration.
--
-- On first load after upgrading, the binary decode fails (no magic
-- header), so this fallback parses the JSON format. The next
-- 'saveCache' call writes the binary format, completing migration.
--
-- @since 0.19.2
tryLegacyJsonLoad :: BSL.ByteString -> Maybe BuildCache
tryLegacyJsonLoad contents =
  case Aeson.eitherDecode contents of
    Right cache -> Just cache
    Left _ -> Nothing

-- CACHE OPERATIONS

-- | Create empty cache.
emptyCache :: IO BuildCache
emptyCache = do
  now <- Time.getCurrentTime
  return
    BuildCache
      { cacheEntries = Map.empty,
        cacheVersion = "0.19.1",
        cacheCreated = now
      }

-- | Load cache from disk using versioned binary format.
--
-- Tries the binary format first; falls back to legacy JSON for
-- seamless migration from older Canopy versions.
--
-- @since 0.19.2
loadCache :: FilePath -> IO (Maybe BuildCache)
loadCache path = do
  Log.logEvent (CacheMiss PhaseCache (Text.pack ("loading from: " ++ path)))
  exists <- Dir.doesFileExist path
  if exists
    then loadCacheFromFile path
    else do
      Log.logEvent (CacheMiss PhaseCache (Text.pack "no cache file found"))
      return Nothing

-- | Read and decode a cache file, trying binary then JSON.
--
-- @since 0.19.2
loadCacheFromFile :: FilePath -> IO (Maybe BuildCache)
loadCacheFromFile path = do
  contents <- BSL.readFile path
  case decodeBuildCache contents of
    Right cache -> do
      logCacheLoaded cache
      return (Just cache)
    Left _binaryErr ->
      loadLegacyFallback path contents

-- | Attempt legacy JSON fallback and log the result.
--
-- @since 0.19.2
loadLegacyFallback :: FilePath -> BSL.ByteString -> IO (Maybe BuildCache)
loadLegacyFallback path contents =
  case tryLegacyJsonLoad contents of
    Just cache -> do
      Log.logEvent (CacheHit PhaseCache (Text.pack "migrated from JSON format"))
      logCacheLoaded cache
      saveCacheBinary path cache
      return (Just cache)
    Nothing -> do
      Log.logEvent (BuildFailed (Text.pack "cache decode failed (binary and JSON)"))
      return Nothing

-- | Log that a cache was successfully loaded.
--
-- @since 0.19.2
logCacheLoaded :: BuildCache -> IO ()
logCacheLoaded cache =
  Log.logEvent (CacheHit PhaseCache (Text.pack (show (Map.size (cacheEntries cache)) ++ " entries loaded")))

-- | Save cache to disk using versioned binary format.
--
-- @since 0.19.2
saveCache :: FilePath -> BuildCache -> IO ()
saveCache path cache = do
  Log.logEvent (CacheStored (Text.pack path) (Map.size (cacheEntries cache)))
  saveCacheBinary path cache
  Log.logEvent (InterfaceSaved path)

-- | Write the binary-encoded cache to disk.
--
-- @since 0.19.2
saveCacheBinary :: FilePath -> BuildCache -> IO ()
saveCacheBinary path cache =
  BSL.writeFile path (encodeBuildCache cache)

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
  now <- Time.getCurrentTime
  let entries = cacheEntries cache
      totalEntries = Map.size entries
      recentCutoff = Time.addUTCTime (-3600) now
      validEntries = Map.size (Map.filter (\e -> cacheTimestamp e > recentCutoff) entries)
      expiredEntries = totalEntries - validEntries
  return (totalEntries, validEntries, expiredEntries)
