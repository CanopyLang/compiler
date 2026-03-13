{-# LANGUAGE OverloadedStrings #-}

-- | Code generation query with caching.
--
-- Wraps 'Generate.JavaScript.generate' in the query system with
-- content-hash based caching. When the optimization output has not
-- changed since the last generation, the cached JavaScript is returned
-- directly, skipping the expensive code generation phase.
--
-- @since 0.19.1
module Queries.Generate
  ( generateJavaScriptQuery,
    generateCachedJavaScript,
    buildCompleteGlobalGraph,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Binary as Binary
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import qualified Generate.JavaScript as JS
import qualified Generate.Mode as Mode
import Logging.Event (GenStats (..), LogEvent (..), Phase (..))
import qualified Logging.Logger as Log
import qualified Query.Engine as Engine
import Query.Simple

-- | Generate JavaScript code from optimized AST (uncached).
--
-- This query wraps Generate.JavaScript.generate with debug logging.
-- Takes mode, global graph, mains, and FFI info, returns JavaScript Builder.
generateJavaScriptQuery ::
  Mode.Mode ->
  Opt.GlobalGraph ->
  Map ModuleName.Canonical Opt.Main ->
  Map String JS.FFIInfo ->
  IO (Either QueryError Builder)
generateJavaScriptQuery mode globalGraph mains ffiInfos = do
  let modNameText = Text.pack ("js:" ++ show (Map.size mains) ++ " mains")
  Log.logEvent (GenerateStarted modNameText)

  let (jsBuilder, _sourceMap, _coverageMap) = JS.generate mode globalGraph mains ffiInfos

  Log.logEvent (GenerateCompleted modNameText (GenStats 0 0))

  return (Right jsBuilder)

-- | Generate JavaScript with query engine caching.
--
-- Computes a content hash of the optimization inputs (GlobalGraph,
-- mains, mode). If a cached result exists with the same hash, returns
-- the cached JavaScript directly. Otherwise generates fresh JavaScript
-- and stores it in the cache.
--
-- @since 0.19.2
generateCachedJavaScript ::
  Engine.QueryEngine ->
  Mode.Mode ->
  Opt.GlobalGraph ->
  Map ModuleName.Canonical Opt.Main ->
  Map String JS.FFIInfo ->
  IO (Either QueryError Builder)
generateCachedJavaScript engine mode globalGraph mains ffiInfos = do
  let inputHash = computeGenerateHash mode globalGraph mains
      query = GenerateQuery "js-output" inputHash
  cached <- Engine.lookupQuery engine query
  case cached of
    Just (GeneratedJS cachedBytes) -> do
      Log.logEvent (CacheHit PhaseGenerate (Text.pack "js-output"))
      return (Right (BB.byteString cachedBytes))
    _ -> do
      result <- generateJavaScriptQuery mode globalGraph mains ffiInfos
      cacheGenerateResult engine query result
      return result

-- | Cache the generation result if successful.
cacheGenerateResult ::
  Engine.QueryEngine ->
  Query ->
  Either QueryError Builder ->
  IO ()
cacheGenerateResult _ _ (Left _) = return ()
cacheGenerateResult engine query (Right jsBuilder) = do
  let jsBytes = LBS.toStrict (BB.toLazyByteString jsBuilder)
      resultHash = computeContentHash jsBytes
  Engine.storeQuery engine query (GeneratedJS jsBytes) resultHash Nothing

-- | Compute content hash for generation inputs.
--
-- Combines the mode, global graph hash, and main modules hash
-- into a single content hash for the cache key.
computeGenerateHash ::
  Mode.Mode ->
  Opt.GlobalGraph ->
  Map ModuleName.Canonical Opt.Main ->
  ContentHash
computeGenerateHash mode globalGraph mains =
  combineHashes [modeHash, graphHash, mainsHash]
  where
    modeHash = computeContentHash (TE.encodeUtf8 (Text.pack (show mode)))
    graphHash = computeContentHash (LBS.toStrict (Binary.encode globalGraph))
    mainsHash = computeContentHash (TE.encodeUtf8 (Text.pack (show (Map.keys mains))))

-- | Build complete GlobalGraph including ALL dependencies.
--
-- Takes all LocalGraphs from compiled modules, merges them into
-- a single GlobalGraph containing ALL code needed for generation.
--
-- @since 0.19.1
buildCompleteGlobalGraph :: [Opt.LocalGraph] -> Opt.GlobalGraph
buildCompleteGlobalGraph localGraphs =
  foldr Opt.addLocalGraph Opt.empty localGraphs
