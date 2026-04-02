{-# LANGUAGE OverloadedStrings #-}

-- | Incremental build cache and versioned ELCO binary serialization.
--
-- Manages the @canopy-stuff\/build-cache.json@ index and per-module
-- @.elco@ artifact files.  The ELCO format uses a magic header,
-- schema version, and compiler version to detect stale caches early.
--
-- == ELCO Header Layout (12 bytes)
--
-- @
-- bytes  0-3:  magic \"ELCO\" (4 bytes)
-- bytes  4-5:  schema version (Word16, big-endian)
-- bytes  6-7:  compiler major (Word16, big-endian)
-- bytes  8-9:  compiler minor (Word16, big-endian)
-- bytes 10-11: compiler patch (Word16, big-endian)
-- bytes 12+:   payload (Binary-encoded)
-- @
--
-- @since 0.19.1
module Compiler.Cache
  ( -- * Build Cache
    loadBuildCache,
    saveBuildCache,
    cachePath,
    cacheArtifactPath,

    -- * Cache Queries
    tryCacheHit,
    loadCachedArtifact,
    saveToCacheAsync,
    computeDepsHash,
    computeFFIHash,

    -- * Versioned Binary
    encodeVersioned,
    decodeVersioned,

    -- * Statistics
    logIncrementalStats,

    -- * Constants
    elcoMagic,
    elcoSchemaVersion,
    elcoHeaderSize,
  )
where

import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import qualified Builder.Hash as Hash
import qualified Builder.Incremental as Incremental
import qualified Canopy.Data.Name as Name
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import Canopy.Version (Version (..))
import qualified Canopy.Version as Version
import Compiler.Types (ModuleResult (..))
import Control.Exception (IOException)
import qualified Control.Exception as Exception
import qualified Data.Binary as Binary
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.IORef (IORef)
import qualified Data.IORef as IORef
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Word (Word16)
import qualified Data.Text as Text
import qualified Data.Time.Clock as Time
import qualified Foreign.FFI as FFI
import qualified Generate.JavaScript as JS
import Logging.Event (LogEvent (..), Phase (..))
import qualified Logging.Logger as Log
import qualified Parse.Module as Parse
import qualified System.Directory as Dir
import System.FilePath ((</>))

-- BUILD CACHE INDEX

-- | Load build cache from disk, returning empty cache on failure.
loadBuildCache :: FilePath -> IO Incremental.BuildCache
loadBuildCache root = do
  maybeCache <- Incremental.loadCache (cachePath root)
  maybe Incremental.emptyCache return maybeCache

-- | Save build cache to disk.
saveBuildCache :: FilePath -> Incremental.BuildCache -> IO ()
saveBuildCache root cache = do
  let cacheDir = root </> "canopy-stuff"
  Dir.createDirectoryIfMissing True cacheDir
  Incremental.saveCache (cachePath root) cache

-- | Path to the build cache index file.
cachePath :: FilePath -> FilePath
cachePath root = root </> "canopy-stuff" </> "build-cache.json"

-- | Path to a cached module artifact (Binary-encoded Interface + LocalGraph).
cacheArtifactPath :: FilePath -> ModuleName.Raw -> FilePath
cacheArtifactPath root modName =
  root </> "canopy-stuff" </> "cache" </> Name.toChars modName ++ ".elco"

-- CACHE QUERIES

-- | Try to load a module from the incremental cache.
--
-- Checks source hash, dependency hash, and FFI file hash.  If all three
-- match, loads the cached Interface and LocalGraph from the binary artifact
-- file.  The FFI hash is computed by parsing the source module to discover
-- which @external\/*.js@ files it references, then hashing their content.
tryCacheHit ::
  IORef Incremental.BuildCache ->
  FilePath ->
  Parse.ProjectType ->
  ModuleName.Raw ->
  FilePath ->
  [ModuleName.Raw] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  IO (Maybe ModuleResult)
tryCacheHit cacheRef root projType modName path modImports ifaces = do
  cache <- IORef.readIORef cacheRef
  sourceHash <- Hash.hashFile path
  let depsHash = computeDepsHash modImports ifaces
  ffiPaths <- extractFFIPaths projType path
  ffiHash <- computeFFIHash root ffiPaths
  if Incremental.needsRecompile cache modName sourceHash depsHash ffiHash
    then return Nothing
    else loadCachedArtifact root modName

-- | Load cached module artifact from disk.
loadCachedArtifact :: FilePath -> ModuleName.Raw -> IO (Maybe ModuleResult)
loadCachedArtifact root modName = do
  let artifactFile = cacheArtifactPath root modName
  exists <- Dir.doesFileExist artifactFile
  if not exists
    then return Nothing
    else do
      result <- Exception.try (decodeCachedModule artifactFile)
      handleDecodeResult modName result

-- | Decode a cached module from a binary file.
--
-- Decodes the full triple of (Interface, LocalGraph, FFIInfo) that was
-- saved by 'saveToCacheAsync'. Checks the magic header and schema
-- version before decoding. Falls back to unversioned legacy formats
-- when the magic header is absent.
decodeCachedModule :: FilePath -> IO (Interface.Interface, Opt.LocalGraph, Map.Map String JS.FFIInfo)
decodeCachedModule artifactFile = do
  bytes <- LBS.readFile artifactFile
  case decodeVersioned bytes of
    Right triple -> return triple
    Left _msg -> decodeLegacyBytes bytes

-- | Attempt legacy (unversioned) decoding from already-read bytes.
decodeLegacyBytes :: LBS.ByteString -> IO (Interface.Interface, Opt.LocalGraph, Map.Map String JS.FFIInfo)
decodeLegacyBytes bytes =
  case Binary.decodeOrFail bytes of
    Right (_, _, triple) -> return triple
    Left _ ->
      case Binary.decodeOrFail bytes of
        Right (_, _, (iface, localGraph)) -> return (iface, localGraph, Map.empty)
        Left (_, _, msg) -> fail ("decode error: " ++ msg)

-- | Handle the result of attempting to decode a cached module.
handleDecodeResult ::
  ModuleName.Raw ->
  Either IOException (Interface.Interface, Opt.LocalGraph, Map.Map String JS.FFIInfo) ->
  IO (Maybe ModuleResult)
handleDecodeResult modName result =
  case result of
    Right (iface, localGraph, ffiInfo) ->
      return (Just (ModuleResult modName iface localGraph ffiInfo Set.empty))
    Left _ex -> do
      Log.logEvent (CacheMiss PhaseCache (Text.pack ("decode failed: " ++ Name.toChars modName)))
      return Nothing

-- | Save module artifacts to cache (asynchronous, best-effort).
saveToCacheAsync ::
  IORef Incremental.BuildCache ->
  FilePath ->
  ModuleName.Raw ->
  FilePath ->
  [ModuleName.Raw] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  ModuleResult ->
  IO ()
saveToCacheAsync cacheRef root modName path modImports ifaces mr = do
  sourceHash <- Hash.hashFile path
  let depsHash = computeDepsHash modImports ifaces
      artifactFile = cacheArtifactPath root modName
      ffiPaths = Map.keys (mrFFIInfo mr)

  Dir.createDirectoryIfMissing True (root </> "canopy-stuff" </> "cache")
  LBS.writeFile artifactFile (encodeVersioned (mrInterface mr, mrLocalGraph mr, mrFFIInfo mr))

  ffiHash <- computeFFIHash root ffiPaths
  now <- Time.getCurrentTime
  let ifaceHash = Hash.hashBytes (LBS.toStrict (Binary.encode (mrInterface mr)))
      entry =
        Incremental.CacheEntry
          { Incremental.cacheSourceHash = sourceHash,
            Incremental.cacheDepsHash = depsHash,
            Incremental.cacheArtifactPath = artifactFile,
            Incremental.cacheTimestamp = now,
            Incremental.cacheInterfaceHash = Just ifaceHash,
            Incremental.cacheFFIHash = ffiHash
          }
  IORef.atomicModifyIORef' cacheRef (\c -> (Incremental.insertCache c modName entry, ()))

-- | Compute a combined hash of a module's actual dependency interfaces.
computeDepsHash :: [ModuleName.Raw] -> Map.Map ModuleName.Raw Interface.Interface -> Hash.ContentHash
computeDepsHash modImports ifaces =
  Hash.hashDependencies ifaceHashes
  where
    relevantIfaces = Map.restrictKeys ifaces (Set.fromList modImports)
    ifaceHashes = Map.map hashInterface relevantIfaces
    hashInterface iface = Hash.hashBytes (LBS.toStrict (Binary.encode iface))

-- | Compute a combined hash of FFI JavaScript files.
--
-- Reads each file path (relative to the project root) from disk and
-- combines their content hashes.  Missing files contribute an empty hash
-- so that a deleted FFI file still invalidates the cache.  Returns
-- 'Hash.emptyHash' when the path list is empty (module has no FFI imports).
--
-- @since 0.19.3
computeFFIHash :: FilePath -> [FilePath] -> IO Hash.ContentHash
computeFFIHash root paths = do
  hashes <- traverse (hashOneFFI root) (List.sort paths)
  pure (combineFFIHashes hashes)

-- | Hash a single FFI file, returning 'Hash.emptyHash' if it does not exist.
hashOneFFI :: FilePath -> FilePath -> IO Hash.ContentHash
hashOneFFI root relPath = do
  let absPath = root </> relPath
  exists <- Dir.doesFileExist absPath
  if exists
    then do
      bytes <- BS.readFile absPath
      pure (Hash.hashBytes bytes)
    else pure Hash.emptyHash

-- | Combine a list of hashes into a single hash by hashing their hex representations.
combineFFIHashes :: [Hash.ContentHash] -> Hash.ContentHash
combineFFIHashes [] = Hash.emptyHash
combineFFIHashes hashes =
  Hash.hashString combined
  where
    combined = concatMap (Hash.toHexString . Hash.hashValue) hashes

-- | Parse a source file and extract the FFI file paths it references.
--
-- Parses the @.can@ source using the given project type to obtain the
-- 'Src.Module', then extracts the 'FilePath' from each
-- @foreign import javascript@ declaration.  Returns an empty list when
-- the source cannot be parsed (parse errors surface as compilation errors
-- later in the pipeline, not here).
--
-- @since 0.19.3
extractFFIPaths :: Parse.ProjectType -> FilePath -> IO [FilePath]
extractFFIPaths projType path = do
  bytes <- BS.readFile path
  pure (either (const []) extractFromModule (Parse.fromByteString projType bytes))

-- | Extract FFI file paths from a parsed source module.
extractFromModule :: Src.Module -> [FilePath]
extractFromModule modul =
  [path | fi <- Src._foreignImports modul, path <- ffiTargetPath (Src._foreignTarget fi)]

-- | Extract the file path from an FFI target, if applicable.
ffiTargetPath :: FFI.FFITarget -> [FilePath]
ffiTargetPath (FFI.JavaScriptFFI p) = [p]
ffiTargetPath (FFI.WebAssemblyFFI p) = [p]

-- VERSIONED BINARY CACHE

-- | Magic bytes identifying a versioned .elco file: "ELCO" in ASCII.
--
-- @since 0.19.1
elcoMagic :: LBS.ByteString
elcoMagic = LBS.pack [0x45, 0x4C, 0x43, 0x4F]

-- | Current schema version.
--
-- Bump this when the Binary encoding of cached types changes
-- (e.g. FFIInfo serialization format) to force cache invalidation.
--
-- Version history:
--   1 — initial binary format
--   2 — added FFIInfo to artifact payload
--   3 — 'CacheEntry' gained 'cacheFFIHash' field; old @.elco@ files are stale
--
-- @since 0.19.1
elcoSchemaVersion :: Word16
elcoSchemaVersion = 3

-- | Minimum header size: 4 (magic) + 2 (schema) + 6 (compiler version).
--
-- @since 0.19.2
elcoHeaderSize :: Int
elcoHeaderSize = 12

-- | Encode a value with the versioned .elco header.
--
-- @since 0.19.1
encodeVersioned :: (Binary.Binary a) => a -> LBS.ByteString
encodeVersioned payload =
  elcoMagic
    <> Binary.encode elcoSchemaVersion
    <> Binary.encode (_major Version.compiler)
    <> Binary.encode (_minor Version.compiler)
    <> Binary.encode (_patch Version.compiler)
    <> Binary.encode payload

-- | Decode a versioned .elco file. Returns Left on magic/version mismatch.
--
-- @since 0.19.1
decodeVersioned ::
  (Binary.Binary a) => LBS.ByteString -> Either String a
decodeVersioned bytes
  | LBS.length bytes < fromIntegral elcoHeaderSize =
      Left "file too short for versioned format"
  | LBS.take 4 bytes /= elcoMagic =
      Left "missing ELCO magic header"
  | otherwise =
      case Binary.decodeOrFail (LBS.drop 4 bytes) of
        Left (_, _, msg) -> Left ("version decode: " ++ msg)
        Right (rest1, _, ver)
          | ver /= elcoSchemaVersion ->
              Left (schemaMismatchMessage ver)
          | otherwise ->
              decodePayloadAfterVersion rest1
  where
    schemaMismatchMessage :: Word16 -> String
    schemaMismatchMessage ver =
      "schema version mismatch: cache is v"
        ++ show ver
        ++ " but compiler expects v"
        ++ show elcoSchemaVersion
        ++ ". Run `canopy make` to rebuild."

    decodePayloadAfterVersion :: (Binary.Binary a) => LBS.ByteString -> Either String a
    decodePayloadAfterVersion rest =
      case verifyCompilerVersion rest of
        Left msg -> Left msg
        Right payloadBytes ->
          case Binary.decodeOrFail payloadBytes of
            Left (_, _, msg) -> Left ("payload decode: " ++ msg)
            Right (_, _, payload) -> Right payload

    verifyCompilerVersion :: LBS.ByteString -> Either String LBS.ByteString
    verifyCompilerVersion bs
      | LBS.length bs < 6 = Left "truncated compiler version in cache header"
      | otherwise =
          decodeWord16 bs >>= \(rest1, major) ->
            decodeWord16 rest1 >>= \(rest2, minor) ->
              decodeWord16 rest2 >>= \(payloadBytes, patch) ->
                let actual = Version major minor patch
                 in if actual == Version.compiler
                      then Right payloadBytes
                      else Left (versionMismatchMessage actual)

    decodeWord16 :: LBS.ByteString -> Either String (LBS.ByteString, Word16)
    decodeWord16 input =
      case Binary.decodeOrFail input of
        Left (_, _, msg) -> Left ("version decode: " ++ msg)
        Right (rest, _, w) -> Right (rest, w)

    versionMismatchMessage :: Version -> String
    versionMismatchMessage actual =
      "compiler version mismatch: cache compiled with v"
        ++ Version.toChars actual
        ++ " but current compiler is v"
        ++ Version.toChars Version.compiler
        ++ ". Run `canopy make` to rebuild."

-- | Log incremental compilation statistics.
logIncrementalStats :: IORef Int -> IORef Int -> IO ()
logIncrementalStats hitRef missRef = do
  hits <- IORef.readIORef hitRef
  misses <- IORef.readIORef missRef
  Log.logEvent (BuildIncremental hits misses)
