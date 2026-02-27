{-# LANGUAGE OverloadedStrings #-}

-- | Package registry for Terminal.
--
-- Handles downloading, caching, and querying package metadata from the
-- Canopy (and fallback Elm) package registry. The registry maps package
-- names to their known versions and is stored as a binary cache on disk
-- to avoid redundant network requests.
--
-- == Design
--
-- The 'Registry' type maps each 'Pkg.Name' to all known 'V.Version' values.
-- On disk, it is persisted using 'Data.Binary' serialization so reads are
-- fast and do not require JSON parsing. Network fetches use the JSON
-- endpoint at 'registryUrl' and fall back to returning the cached (or empty)
-- registry when unavailable so the compiler degrades gracefully.
--
-- == Cache Layout
--
-- @
-- \<canopyCache\>/registry.dat   -- Binary-serialized Registry
-- @
--
-- @since 0.19.1
module Deps.Registry
  ( -- * Registry Type
    Registry (..),
    CanopyRegistries (..),
    KnownVersions (..),
    RegistryKey (RepositoryUrlKey, PackageUrlKey),

    -- * Operations
    read,
    mergeRegistries,
    latest,
    createAuthHeader,
    getVersions',
  )
where

import qualified Canopy.CustomRepositoryData as CustomRepo
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import qualified Control.Exception as Exception
import Control.Exception (SomeException)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKM
import qualified Data.Binary as Binary
import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Text as Text
import qualified Data.Utf8 as Utf8
import qualified Http
import qualified Stuff
import qualified System.Directory as Dir
import System.FilePath ((</>))
import Prelude hiding (read)

-- | Package registry with total package count and per-package version map.
--
-- The 'Int' field records the total number of packages at last fetch,
-- used as a cheap staleness signal. The map stores every known version
-- for every known package.
data Registry = Registry !Int !(Map Pkg.Name (Map V.Version ()))
  deriving (Show, Eq)

-- | Registry key types for authentication and package lookup.
data RegistryKey
  = RepositoryUrlKey String
  | PackageUrlKey Pkg.Name
  deriving (Show, Eq, Ord)

-- | Multiple registries combined, with the main registry accessible first.
data CanopyRegistries = CanopyRegistries
  { _registriesMain :: !Registry
  , _registriesCustom :: ![Registry]
  , _registries :: !(Map RegistryKey Registry)
  }
  deriving (Show, Eq)

-- | Known package versions with latest version and all older versions.
--
-- The first field is the highest (latest) version; the list contains
-- all older versions.
data KnownVersions = KnownVersions !V.Version ![V.Version]
  deriving (Show, Eq)

-- BINARY INSTANCES

instance Binary.Binary Registry where
  put (Registry count pkgs) = do
    Binary.put count
    Binary.put (Map.size pkgs)
    mapM_ putPkgEntry (Map.toAscList pkgs)
    where
      putPkgEntry (name, versions) = do
        Binary.put name
        Binary.put (Map.size versions)
        mapM_ Binary.put (Map.keys versions)
  get = do
    count <- Binary.get
    pkgCount <- Binary.get :: Binary.Get Int
    entries <- mapM (const getPkgEntry) [1 .. pkgCount]
    pure (Registry count (Map.fromList entries))
    where
      getPkgEntry = do
        name <- Binary.get
        vCount <- Binary.get :: Binary.Get Int
        versions <- mapM (const Binary.get) [1 .. vCount]
        pure (name, Map.fromList [(v, ()) | v <- versions])

-- CONSTANTS

-- | Default registry URL (Elm package registry, which Canopy is compatible with).
registryUrl :: String
registryUrl = "https://package.elm-lang.org/all-packages"

-- | Absolute path of the binary cache file within the canopy cache directory.
registryCacheFile :: FilePath -> FilePath
registryCacheFile cache = cache </> "registry.dat"

-- EXPORTED OPERATIONS

-- | Create an HTTP Authorization header from a bearer token.
createAuthHeader :: String -> (String, String)
createAuthHeader token = ("Authorization", "Bearer " <> token)

-- | Read a 'Registry' from the binary cache file.
--
-- Returns 'Nothing' when the file does not exist or cannot be decoded,
-- allowing callers to fall back to a network fetch.
read :: FilePath -> IO (Maybe Registry)
read cache = do
  let path = registryCacheFile cache
  exists <- Dir.doesFileExist path
  if exists
    then parseRegistryFile path
    else pure Nothing

-- | Merge multiple registries (identity — the main registry is already merged).
mergeRegistries :: Registry -> Registry
mergeRegistries = id

-- | Fetch the latest registry, using the disk cache when available.
--
-- Attempts in order:
--
-- 1. Fetch from 'registryUrl' via HTTP GET and parse the JSON response.
-- 2. On success, write the result to the binary cache and return it.
-- 3. On any network or parse failure, return the cached registry when one
--    exists, otherwise return an empty registry so the compiler degrades
--    gracefully.
latest
  :: Http.Manager
  -> CustomRepo.CustomRepositoriesData
  -> Stuff.CanopySpecificCache
  -> Stuff.CanopyCustomRepositoryConfigFilePath
  -> IO (Either String Registry)
latest manager _customRepos cache _reposConfig = do
  cached <- read cache
  networkResult <- fetchFromNetwork manager
  case networkResult of
    Right fresh -> do
      writeCache cache fresh
      pure (Right fresh)
    Left _networkErr ->
      pure (Right (maybe emptyRegistry id cached))

-- | Get versions for a package from the combined registries.
--
-- Searches the main registry then custom registries in order.
-- Returns 'Nothing' when the package is not present in any registry.
getVersions' :: CanopyRegistries -> Pkg.Name -> Maybe KnownVersions
getVersions' (CanopyRegistries mainReg customRegs _) pkg =
  firstJust (lookupInRegistry pkg) (mainReg : customRegs)

-- INTERNAL HELPERS

-- | An empty registry used as a last-resort graceful fallback.
emptyRegistry :: Registry
emptyRegistry = Registry 0 Map.empty

-- | Attempt to parse the binary cache file, returning Nothing on any error.
parseRegistryFile :: FilePath -> IO (Maybe Registry)
parseRegistryFile path =
  Exception.handle ignoreException $ do
    bytes <- LBS.readFile path
    pure (either (const Nothing) Just (decodeFully bytes))

-- | Decode a lazy ByteString, returning Left on partial decode or failure.
decodeFully :: LBS.ByteString -> Either String Registry
decodeFully bytes =
  case Binary.decodeOrFail bytes of
    Right (_, _, reg) -> Right reg
    Left (_, _, msg) -> Left msg

-- | Suppress any IO exception and return Nothing.
ignoreException :: SomeException -> IO (Maybe a)
ignoreException _ = pure Nothing

-- | Perform an HTTP GET to the registry endpoint and parse the response.
fetchFromNetwork :: Http.Manager -> IO (Either String Registry)
fetchFromNetwork manager =
  Http.get manager registryUrl [] httpErrorToString parseRegistryResponse

-- | Convert an HTTP error to a descriptive String for error reporting.
httpErrorToString :: Http.Error -> String
httpErrorToString (Http.BadUrl url reason) =
  "Bad URL " <> url <> ": " <> reason
httpErrorToString (Http.BadHttp url _) =
  "HTTP error for " <> url
httpErrorToString (Http.BadMystery url _) =
  "Unexpected error for " <> url

-- | Parse the strict ByteString JSON response into a 'Registry'.
--
-- The expected format is an Aeson Object mapping @"author/project"@ keys
-- to arrays of version strings:
--
-- @
-- { "elm/core": ["1.0.0", "1.0.1"], "elm/html": ["1.0.0"] }
-- @
parseRegistryResponse :: ByteString -> IO (Either String Registry)
parseRegistryResponse bytes =
  pure (parseRegistryJson (LBS.fromStrict bytes))

-- | Parse the lazy ByteString JSON registry object into a 'Registry'.
parseRegistryJson :: LBS.ByteString -> Either String Registry
parseRegistryJson bytes =
  case Aeson.eitherDecode bytes of
    Left err -> Left ("Registry JSON parse error: " <> err)
    Right obj -> Right (buildRegistry obj)

-- | Build a 'Registry' from the decoded JSON object.
buildRegistry :: Aeson.Object -> Registry
buildRegistry obj =
  let entries = mapMaybe parseEntry (AesonKM.toList obj)
   in Registry (length entries) (Map.fromList entries)

-- | Parse a single registry entry (key = "author/project", value = versions array).
parseEntry :: (AesonKey.Key, Aeson.Value) -> Maybe (Pkg.Name, Map V.Version ())
parseEntry (key, val) = do
  name <- parsePkgName (AesonKey.toText key)
  versions <- parseVersionMap val
  pure (name, versions)

-- | Parse a @"author/project"@ Text value into a 'Pkg.Name'.
parsePkgName :: Text.Text -> Maybe Pkg.Name
parsePkgName txt =
  case Text.splitOn "/" txt of
    [author, project] ->
      Just (Pkg.Name (Utf8.fromChars (Text.unpack author)) (Utf8.fromChars (Text.unpack project)))
    _ -> Nothing

-- | Parse an array of version strings from a JSON value into a version map.
parseVersionMap :: Aeson.Value -> Maybe (Map V.Version ())
parseVersionMap val =
  case Aeson.fromJSON val of
    Aeson.Success (strs :: [Text.Text]) ->
      Just (Map.fromList [(v, ()) | Just v <- map parseVersionText strs])
    _ -> Nothing

-- | Parse a single version string using the 'Aeson.FromJSON' instance for 'V.Version'.
parseVersionText :: Text.Text -> Maybe V.Version
parseVersionText txt =
  case Aeson.fromJSON (Aeson.String txt) of
    Aeson.Success v -> Just v
    _ -> Nothing

-- | Write the registry to the binary cache file (best-effort, silently ignores errors).
writeCache :: FilePath -> Registry -> IO ()
writeCache cache registry =
  Exception.handle ignoreWriteException $ do
    Dir.createDirectoryIfMissing True cache
    LBS.writeFile (registryCacheFile cache) (Binary.encode registry)

-- | Suppress write exceptions (best-effort caching).
ignoreWriteException :: SomeException -> IO ()
ignoreWriteException _ = pure ()

-- | Return the first 'Just' result from applying a function over a list.
firstJust :: (a -> Maybe b) -> [a] -> Maybe b
firstJust _ [] = Nothing
firstJust f (x : xs) =
  case f x of
    Just result -> Just result
    Nothing -> firstJust f xs

-- | Look up 'KnownVersions' for a package within a single 'Registry'.
lookupInRegistry :: Pkg.Name -> Registry -> Maybe KnownVersions
lookupInRegistry pkg (Registry _ pkgs) =
  toKnownVersions =<< Map.lookup pkg pkgs

-- | Convert a non-empty version map to 'KnownVersions'.
--
-- Returns 'Nothing' for an empty map since there is no meaningful latest version.
toKnownVersions :: Map V.Version () -> Maybe KnownVersions
toKnownVersions versions =
  case Map.keys versions of
    [] -> Nothing
    (v : vs) -> Just (KnownVersions v vs)
