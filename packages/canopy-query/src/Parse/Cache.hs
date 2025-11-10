{-# LANGUAGE BangPatterns #-}
{-# OPTIONS_GHC -Wall #-}

-- | Parse cache for the NEW query system.
--
-- This provides a simple cache that stores parsed modules keyed by
-- file path and content hash. When the same file with the same content
-- is parsed again, we can return the cached AST directly.
--
-- @since 0.19.1
module Parse.Cache
  ( ParseCache
  , emptyCache
  , lookupParse
  , insertParse
  , cacheLookupOrParse
  , cacheSize
  ) where

import qualified AST.Source as Src
import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import qualified Parse.Module as Parse
import qualified Reporting.Error.Syntax as Syntax

-- | Cache mapping file paths to (content hash, parsed AST).
--
-- We store both the content and the AST so we can verify the content
-- hasn't changed before returning the cached result.
type ParseCache = Map.Map FilePath (BS.ByteString, Src.Module)

-- | Create an empty parse cache.
emptyCache :: ParseCache
emptyCache = Map.empty

-- | Look up a cached parse result by file path.
lookupParse :: FilePath -> ParseCache -> Maybe (BS.ByteString, Src.Module)
lookupParse = Map.lookup

-- | Insert a parse result into the cache.
insertParse :: FilePath -> BS.ByteString -> Src.Module -> ParseCache -> ParseCache
insertParse !path !content !ast !cache =
  Map.insert path (content, ast) cache

-- | Get the size of the cache (number of cached modules).
cacheSize :: ParseCache -> Int
cacheSize = Map.size

-- | Look up a cached parse result or parse the file if not cached.
--
-- This is the main entry point for using the cache. It will:
-- 1. Check if the file is cached with matching content
-- 2. If yes, return the cached AST (CACHE HIT)
-- 3. If no, parse the file and cache the result (CACHE MISS)
--
-- The cache is updated and returned along with the result.
cacheLookupOrParse ::
  FilePath ->
  Parse.ProjectType ->
  BS.ByteString ->
  ParseCache ->
  (Either Syntax.Error Src.Module, ParseCache)
cacheLookupOrParse !path !projectType !content !cache =
  case lookupParse path cache of
    Just (cachedContent, cachedAst)
      | cachedContent == content ->
          (Right cachedAst, cache)
    _ ->
      case Parse.fromByteString projectType content of
        Left err -> (Left err, cache)
        Right ast ->
          let !newCache = insertParse path content ast cache
           in (Right ast, newCache)
