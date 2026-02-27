{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | File content cache to eliminate redundant I/O operations
--
-- This module provides a simple in-memory cache for file contents
-- to avoid re-reading the same file multiple times during compilation.
-- This complements the Parse.Cache by providing the raw file content.
module File.Cache
  ( FileCache,
    emptyCache,
    cachedReadUtf8,
    cacheSize,
  )
where

import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import qualified File

-- | Cache mapping file paths to their contents
--
-- We store the ByteString content for files that have been read
-- during the current compilation session.
type FileCache = Map.Map FilePath BS.ByteString

-- | Create an empty file cache
emptyCache :: FileCache
emptyCache = Map.empty

-- | Read a file with caching
--
-- If the file has been read before in this session, return the cached content.
-- Otherwise, read the file, cache it, and return the content.
--
-- This function is designed to work with MVar for thread-safe access:
--
-- @
-- cache <- takeMVar cacheMVar
-- (content, newCache) <- cachedReadUtf8 path cache
-- putMVar cacheMVar newCache
-- @
cachedReadUtf8 :: FilePath -> FileCache -> IO (BS.ByteString, FileCache)
cachedReadUtf8 !path !cache =
  case Map.lookup path cache of
    Just content ->
      -- Cache hit - return cached content without I/O
      return (content, cache)
    Nothing ->
      -- Cache miss - read file and update cache
      do
        !content <- File.readUtf8 path
        let !newCache = Map.insert path content cache
        return (content, newCache)

-- | Get the number of cached files
cacheSize :: FileCache -> Int
cacheSize = Map.size
