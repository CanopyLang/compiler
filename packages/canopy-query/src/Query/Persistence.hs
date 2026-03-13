{-# LANGUAGE OverloadedStrings #-}

-- | Disk persistence for the query cache.
--
-- Serializes content hashes and the dependency graph to disk for warm
-- startup. On a cold start with a populated disk cache, the compiler
-- can determine which modules have changed since the last build without
-- re-parsing everything.
--
-- The cache stores a version-tagged binary file at
-- @.canopy\/cache\/query-cache.bin@. Entries marked 'Engine.Volatile'
-- are excluded from persistence.
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

import qualified Control.Exception as Exception
import qualified Data.ByteString as BS
import Data.IORef (IORef, modifyIORef', readIORef)
import qualified Data.Map.Strict as Map
import Data.Word (Word8, Word32)
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import qualified Parse.Module as Parse
import qualified Query.Engine as Engine
import Query.Simple (ContentHash (..), Query (..))
import qualified System.Directory as Dir
import qualified System.FilePath as FP

-- | Current cache format version.
--
-- Increment when the serialization format changes to avoid loading
-- incompatible caches. Old-version caches are silently discarded.
--
-- @since 0.19.2
cacheVersion :: Word32
cacheVersion = 1

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
-- Errors during serialization are logged but don't propagate,
-- ensuring a failed save never blocks compilation.
--
-- @since 0.19.2
saveCache :: Engine.QueryEngine -> FilePath -> IO ()
saveCache (Engine.QueryEngine stateRef) path = do
  state <- readIORef stateRef
  let durable = filterDurable (Engine.engineCache state)
      encoded = encodeEntries durable
  Dir.createDirectoryIfMissing True (FP.takeDirectory path)
  Exception.catch
    (BS.writeFile path encoded >> logSaved (Map.size durable))
    logSaveError
  where
    logSaved count = Log.logEvent (CacheStored "persist-save" count)
    logSaveError :: Exception.IOException -> IO ()
    logSaveError _ = Log.logEvent (CacheStored "persist-save-failed" 0)

-- | Filter cache entries to exclude 'Engine.Volatile' entries.
filterDurable ::
  Map.Map Query Engine.CacheEntry ->
  Map.Map Query Engine.CacheEntry
filterDurable =
  Map.filter (\e -> Engine.cacheEntryDurability e /= Engine.Volatile)

-- | Load a previously persisted cache from disk.
--
-- If the cache file doesn't exist, is corrupted, or has an incompatible
-- version, returns without error (cold start). The engine starts with an
-- empty cache and populates it during compilation.
--
-- On successful load, bumps the engine generation counter to signal
-- that cached state was restored from a previous session.
--
-- @since 0.19.2
loadCache :: Engine.QueryEngine -> FilePath -> IO ()
loadCache (Engine.QueryEngine stateRef) path = do
  exists <- Dir.doesFileExist path
  if exists
    then Exception.catch (loadAndPopulate stateRef path) logLoadError
    else Log.logEvent (CacheStored "persist-cold-start" 0)

-- | Attempt to load and populate cache from file.
--
-- Decodes all persisted entries and populates the engine's
-- 'Engine.enginePersistedHashes' map. These hashes enable early
-- cutoff in watch mode: when a file changes but the compilation
-- result hash is unchanged, downstream dependents skip recompilation.
loadAndPopulate :: IORef Engine.EngineState -> FilePath -> IO ()
loadAndPopulate stateRef path = do
  bytes <- BS.readFile path
  case decodeVersion bytes of
    Nothing ->
      Log.logEvent (CacheStored "persist-decode-failed" 0)
    Just version
      | version /= cacheVersion ->
          Log.logEvent (CacheStored "persist-version-mismatch" 0)
      | otherwise -> do
          let entryCount = decodeEntryCount bytes
              entries = decodeAllEntries (BS.drop 8 bytes) (fromIntegral entryCount)
              hashMap = Map.fromList entries
          Log.logEvent (CacheStored "persist-load" (Map.size hashMap))
          modifyIORef' stateRef (populateFromDisk hashMap)

-- | Populate engine state from decoded disk entries.
--
-- Sets persisted hashes and bumps generation counter to signal
-- that cached state was restored from a previous session.
populateFromDisk :: Map.Map Query ContentHash -> Engine.EngineState -> Engine.EngineState
populateFromDisk hashMap state =
  state
    { Engine.enginePersistedHashes = hashMap,
      Engine.engineGeneration = Engine.engineGeneration state + 1
    }

-- | Encode cache entries as a version-tagged binary blob.
--
-- Format: [version:4][entry_count:4][entries...]
-- Each entry: [tag:1][path_len:4][path:n][hash:32][durability:1]
encodeEntries :: Map.Map Query Engine.CacheEntry -> BS.ByteString
encodeEntries entries =
  BS.concat
    [ encodeWord32 cacheVersion,
      encodeWord32 (fromIntegral (Map.size entries)),
      BS.concat (fmap encodeEntry (Map.toAscList entries))
    ]

-- | Encode a single cache entry.
encodeEntry :: (Query, Engine.CacheEntry) -> BS.ByteString
encodeEntry (query, entry) =
  BS.concat
    [ BS.singleton (queryTag query),
      encodeString (queryPath query),
      encodeContentHash (Engine.cacheEntryHash entry),
      encodeDurability (Engine.cacheEntryDurability entry)
    ]

-- | Extract the phase tag from a query.
queryTag :: Query -> Word8
queryTag ParseModuleQuery {} = 0
queryTag CanonicalizeQuery {} = 1
queryTag TypeCheckQuery {} = 2
queryTag OptimizeQuery {} = 3
queryTag InterfaceQuery {} = 4
queryTag GenerateQuery {} = 5

-- | Extract the file path from a query.
queryPath :: Query -> FilePath
queryPath (ParseModuleQuery f _ _) = f
queryPath (CanonicalizeQuery f _) = f
queryPath (TypeCheckQuery f _) = f
queryPath (OptimizeQuery f _) = f
queryPath (InterfaceQuery f _) = f
queryPath (GenerateQuery f _) = f

-- | Decode the version from a cache blob.
decodeVersion :: BS.ByteString -> Maybe Word32
decodeVersion bs
  | BS.length bs < 4 = Nothing
  | otherwise = Just (decodeWord32 (BS.take 4 bs))

-- | Decode the entry count from a cache blob.
decodeEntryCount :: BS.ByteString -> Word32
decodeEntryCount bs
  | BS.length bs < 8 = 0
  | otherwise = decodeWord32 (BS.take 4 (BS.drop 4 bs))

-- | Decode all entries from the binary blob after the 8-byte header.
--
-- Each entry is: [tag:1][path_len:4][path:n][hash:32][durability:1]
decodeAllEntries :: BS.ByteString -> Int -> [(Query, ContentHash)]
decodeAllEntries = go []
  where
    go acc _ 0 = reverse acc
    go acc bs remaining
      | BS.null bs = reverse acc
      | otherwise =
          case decodeOneEntry bs of
            Nothing -> reverse acc
            Just (entry, rest) -> go (entry : acc) rest (remaining - 1)

-- | Decode a single entry, returning the entry and remaining bytes.
decodeOneEntry :: BS.ByteString -> Maybe ((Query, ContentHash), BS.ByteString)
decodeOneEntry bs
  | BS.length bs < 6 = Nothing
  | otherwise =
      let tag = BS.index bs 0
          pathLen = fromIntegral (decodeWord32 (BS.take 4 (BS.drop 1 bs)))
          afterPathLen = BS.drop 5 bs
       in decodeEntryPayload tag pathLen afterPathLen

-- | Decode entry payload after tag and path length.
decodeEntryPayload :: Word8 -> Int -> BS.ByteString -> Maybe ((Query, ContentHash), BS.ByteString)
decodeEntryPayload tag pathLen bs
  | BS.length bs < pathLen + 33 = Nothing
  | otherwise =
      let pathBytes = BS.take pathLen bs
          path = fmap (toEnum . fromIntegral) (BS.unpack pathBytes)
          hashBytes = BS.take 32 (BS.drop pathLen bs)
          contentHash = ContentHash hashBytes
          rest = BS.drop (pathLen + 33) bs
          query = tagToQuery tag path contentHash
       in Just ((query, contentHash), rest)

-- | Reconstruct a query from its persisted tag, path, and hash.
tagToQuery :: Word8 -> FilePath -> ContentHash -> Query
tagToQuery 0 path hash = ParseModuleQuery path hash Parse.Application
tagToQuery 1 path hash = CanonicalizeQuery path hash
tagToQuery 2 path hash = TypeCheckQuery path hash
tagToQuery 3 path hash = OptimizeQuery path hash
tagToQuery 4 path hash = InterfaceQuery path hash
tagToQuery 5 path hash = GenerateQuery path hash
tagToQuery _ path hash = ParseModuleQuery path hash Parse.Application

-- | Encode a Word32 as 4 big-endian bytes.
encodeWord32 :: Word32 -> BS.ByteString
encodeWord32 w =
  BS.pack
    [ fromIntegral (w `div` 16777216),
      fromIntegral ((w `div` 65536) `mod` 256),
      fromIntegral ((w `div` 256) `mod` 256),
      fromIntegral (w `mod` 256)
    ]

-- | Decode a Word32 from 4 big-endian bytes.
decodeWord32 :: BS.ByteString -> Word32
decodeWord32 bs
  | BS.length bs < 4 = 0
  | otherwise =
      fromIntegral (BS.index bs 0) * 16777216
        + fromIntegral (BS.index bs 1) * 65536
        + fromIntegral (BS.index bs 2) * 256
        + fromIntegral (BS.index bs 3)

-- | Encode a string as length-prefixed bytes.
encodeString :: String -> BS.ByteString
encodeString s =
  BS.concat [encodeWord32 (fromIntegral len), encoded]
  where
    encoded = BS.pack (fmap (fromIntegral . fromEnum) s)
    len = BS.length encoded

-- | Encode a content hash (always 32 bytes for SHA256).
encodeContentHash :: ContentHash -> BS.ByteString
encodeContentHash (ContentHash h) = h

-- | Encode durability as a single byte.
encodeDurability :: Engine.Durability -> BS.ByteString
encodeDurability Engine.Volatile = BS.singleton 0
encodeDurability Engine.Normal = BS.singleton 1
encodeDurability Engine.Durable = BS.singleton 2

-- | Log a load error without crashing.
logLoadError :: Exception.IOException -> IO ()
logLoadError _ = Log.logEvent (CacheStored "persist-load-failed" 0)
