{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Package fetching with multi-source fallback for resilient dependency resolution.
--
-- This module implements a cascading fetch strategy for package archives:
--
-- 1. Local Canopy cache (@~\/.canopy\/packages\/{author}\/{project}\/{version}\/@)
-- 2. Elm cache fallback (@~\/.elm\/0.19.1\/packages\/{author}\/{project}\/{version}\/@)
-- 3. Elm registry endpoint.json (provides download URL and hash)
-- 4. Direct GitHub ZIP download (deterministic URL from package name)
--
-- This design ensures that @canopy install@ degrades gracefully when the
-- primary registry is unavailable, following the same pattern as Go's
-- @GOPROXY=proxy.golang.org,direct@ fallback chain.
--
-- == Architecture
--
-- All Elm packages are hosted on GitHub (a requirement for @elm publish@),
-- so the GitHub URL pattern @github.com\/{author}\/{project}\/zipball\/{version}\/@
-- is deterministic and serves as a reliable last-resort source.
--
-- @since 0.19.2
module PackageCache.Fetch
  ( -- * Types
    FetchSource (..),
    FetchError (..),
    PackageSource (..),

    -- * Lenses
    psGitUrl,
    psArchiveUrl,

    -- * Fetching
    fetchPackage,
    fetchFromNetwork,

    -- * Cache Helpers
    checkLocalCache,
    checkElmCache,

    -- * Network Fetching
    fetchViaEndpoint,
    fetchFromGitHub,

    -- * Source Helpers
    gitRepoUrl,
    toPackageSource,

    -- * Constants
    registryBase,
    gitHubZipUrl,
  )
where

import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Exception (IOException)
import qualified Control.Exception as Exception
import Control.Lens (makeLenses)
import qualified Data.Aeson as Json
import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import qualified Network.HTTP.Client as Client
import qualified System.Directory as Dir
import System.FilePath ((</>))

-- | Where a package was obtained from during resolution.
--
-- Tracks provenance so the lock file can record source URLs
-- for resilient future fetches.
--
-- @since 0.19.2
data FetchSource
  = -- | Found in the local Canopy cache.
    CachedLocal !FilePath
  | -- | Found in the Elm 0.19.1 cache (backward compatibility).
    CachedElm !FilePath
  | -- | Downloaded via the registry's endpoint.json.
    FetchedRegistry !Text.Text
  | -- | Downloaded directly from GitHub.
    FetchedGitHub !Text.Text
  deriving (Eq, Show)

-- | Errors that can occur during package fetching.
--
-- @since 0.19.2
data FetchError
  = -- | The registry endpoint.json was unreachable or returned invalid data.
    RegistryUnavailable !Text.Text
  | -- | GitHub returned an error or the ZIP was invalid.
    GitHubUnavailable !Text.Text
  | -- | The downloaded archive failed integrity verification.
    IntegrityCheckFailed !Text.Text
  | -- | All fetch sources exhausted without success.
    AllSourcesFailed !Pkg.Name !Version.Version
  deriving (Eq, Show)

-- | Metadata recording where a package was originally fetched from.
--
-- Stored in the lock file so that future installs can re-fetch
-- from the same source (or fall back to alternatives) without
-- depending on the registry.
--
-- @since 0.19.2
data PackageSource = PackageSource
  { _psGitUrl :: !Text.Text,
    _psArchiveUrl :: !(Maybe Text.Text)
  }
  deriving (Eq, Show)

makeLenses ''PackageSource

instance Json.ToJSON PackageSource where
  toJSON ps =
    Json.object (requiredFields ++ archiveField)
    where
      requiredFields = ["git-url" Json..= _psGitUrl ps]
      archiveField = maybe [] (\u -> ["archive-url" Json..= u]) (_psArchiveUrl ps)

instance Json.FromJSON PackageSource where
  parseJSON = Json.withObject "PackageSource" $ \o ->
    PackageSource
      <$> o Json..: "git-url"
      <*> o Json..:? "archive-url"

-- | The Elm package registry base URL.
--
-- @since 0.19.2
registryBase :: String
registryBase = "https://package.elm-lang.org"

-- | Build the GitHub ZIP download URL for a package version.
--
-- All Elm packages live on GitHub, so the URL pattern is deterministic:
-- @https:\/\/github.com\/{author}\/{project}\/zipball\/{version}\/@
--
-- @since 0.19.2
gitHubZipUrl :: Pkg.Name -> Version.Version -> String
gitHubZipUrl (Pkg.Name author project) ver =
  "https://github.com/"
    <> Utf8.toChars author
    <> "/"
    <> Utf8.toChars project
    <> "/zipball/"
    <> Version.toChars ver
    <> "/"

-- | Build the git repository URL for a package.
--
-- @since 0.19.2
gitRepoUrl :: Pkg.Name -> String
gitRepoUrl (Pkg.Name author project) =
  "https://github.com/" <> Utf8.toChars author <> "/" <> Utf8.toChars project

-- | Build a 'PackageSource' from a package name and optional archive URL.
--
-- @since 0.19.2
toPackageSource :: Pkg.Name -> Maybe Text.Text -> PackageSource
toPackageSource pkg archiveUrl =
  PackageSource
    { _psGitUrl = Text.pack (gitRepoUrl pkg),
      _psArchiveUrl = archiveUrl
    }

-- | Fetch a package, trying each source in priority order.
--
-- Resolution order:
--
-- 1. Local Canopy cache (@~\/.canopy\/packages\/@)
-- 2. Elm cache (@~\/.elm\/0.19.1\/packages\/@)
-- 3. Registry endpoint.json
-- 4. Direct GitHub ZIP
--
-- Returns the 'FetchSource' indicating where the package was found.
--
-- @since 0.19.2
fetchPackage :: Client.Manager -> Pkg.Name -> Version.Version -> IO (Either FetchError FetchSource)
fetchPackage manager pkg ver = do
  localResult <- checkLocalCache pkg ver
  maybe (tryElmCache manager pkg ver) (pure . Right) localResult

-- | After local cache miss, try the Elm cache then network sources.
tryElmCache :: Client.Manager -> Pkg.Name -> Version.Version -> IO (Either FetchError FetchSource)
tryElmCache manager pkg ver = do
  elmResult <- checkElmCache pkg ver
  maybe (fetchFromNetwork manager pkg ver) (pure . Right) elmResult

-- | Check the local Canopy package cache.
--
-- Looks for @~\/.canopy\/packages\/{author}\/{project}\/{version}\/@ and
-- returns 'CachedLocal' if the directory exists.
--
-- @since 0.19.2
checkLocalCache :: Pkg.Name -> Version.Version -> IO (Maybe FetchSource)
checkLocalCache pkg ver = do
  home <- Dir.getHomeDirectory
  let path = home </> ".canopy" </> "packages" </> Pkg.toFilePath pkg </> Version.toChars ver
  exists <- Dir.doesDirectoryExist path
  if exists
    then do
      Log.logEvent (PackageOperation "cache-hit" (Text.pack path))
      pure (Just (CachedLocal path))
    else pure Nothing

-- | Check the legacy Elm 0.19.1 package cache.
--
-- Looks for @~\/.elm\/0.19.1\/packages\/{author}\/{project}\/{version}\/@ and
-- returns 'CachedElm' if found.
--
-- @since 0.19.2
checkElmCache :: Pkg.Name -> Version.Version -> IO (Maybe FetchSource)
checkElmCache pkg ver = do
  home <- Dir.getHomeDirectory
  let path = home </> ".elm" </> "0.19.1" </> "packages" </> Pkg.toFilePath pkg </> Version.toChars ver
  exists <- Dir.doesDirectoryExist path
  if exists
    then do
      Log.logEvent (PackageOperation "elm-cache-hit" (Text.pack path))
      pure (Just (CachedElm path))
    else pure Nothing

-- | Attempt to fetch a package from network sources.
--
-- Tries the registry endpoint.json first, then falls back to
-- a direct GitHub ZIP download.
--
-- @since 0.19.2
fetchFromNetwork :: Client.Manager -> Pkg.Name -> Version.Version -> IO (Either FetchError FetchSource)
fetchFromNetwork manager pkg ver = do
  Log.logEvent (PackageOperation "network-fetch" (Text.pack (Pkg.toChars pkg <> " " <> Version.toChars ver)))
  registryResult <- fetchViaEndpoint manager pkg ver
  either (\_ -> fetchFromGitHub manager pkg ver) (pure . Right) registryResult

-- | Fetch a package via the registry's endpoint.json.
--
-- The registry serves endpoint files at:
-- @\/packages\/{author}\/{project}\/{version}\/endpoint.json@
--
-- The response contains the download URL and content hash.
--
-- @since 0.19.2
fetchViaEndpoint :: Client.Manager -> Pkg.Name -> Version.Version -> IO (Either FetchError FetchSource)
fetchViaEndpoint manager pkg ver = do
  let endpointUrl = buildEndpointUrl pkg ver
  Log.logEvent (PackageOperation "endpoint-fetch" (Text.pack endpointUrl))
  result <- safeHttpGet manager endpointUrl
  pure (either (Left . RegistryUnavailable) parseEndpointResponse result)
  where
    parseEndpointResponse bs =
      maybe
        (Left (RegistryUnavailable "Invalid endpoint.json response"))
        (\ep -> Right (FetchedRegistry (_epUrl ep)))
        (Json.decode (LBS.fromStrict bs))

-- | Build the endpoint.json URL for a package version.
buildEndpointUrl :: Pkg.Name -> Version.Version -> String
buildEndpointUrl pkg ver =
  registryBase
    <> "/packages/"
    <> Pkg.toChars pkg
    <> "/"
    <> Version.toChars ver
    <> "/endpoint.json"

-- | Endpoint.json response structure from the Elm registry.
data EndpointResponse = EndpointResponse
  { _epUrl :: !Text.Text,
    _epHash :: !Text.Text
  }

instance Json.FromJSON EndpointResponse where
  parseJSON = Json.withObject "EndpointResponse" $ \o ->
    EndpointResponse
      <$> o Json..: "url"
      <*> o Json..: "hash"

-- | Fetch a package directly from GitHub.
--
-- Uses the deterministic URL pattern for Elm packages on GitHub:
-- @https:\/\/github.com\/{author}\/{project}\/zipball\/{version}\/@
--
-- This is the last-resort fallback when both the local caches
-- and the registry are unavailable.
--
-- @since 0.19.2
fetchFromGitHub :: Client.Manager -> Pkg.Name -> Version.Version -> IO (Either FetchError FetchSource)
fetchFromGitHub manager pkg ver = do
  let zipUrl = gitHubZipUrl pkg ver
  Log.logEvent (PackageOperation "github-fetch" (Text.pack zipUrl))
  result <- safeHttpGet manager zipUrl
  pure (either (Left . GitHubUnavailable) (\_ -> Right (FetchedGitHub (Text.pack zipUrl))) result)

-- | Perform a safe HTTP GET, catching exceptions and returning errors.
safeHttpGet :: Client.Manager -> String -> IO (Either Text.Text ByteString)
safeHttpGet manager url =
  Exception.handle handleIO . Exception.handle handleHttp $ do
    req <- Client.parseUrlThrow url
    response <- Client.httpLbs req manager
    pure (Right (LBS.toStrict (Client.responseBody response)))
  where
    handleHttp :: Client.HttpException -> IO (Either Text.Text ByteString)
    handleHttp ex = pure (Left (Text.pack ("HTTP error: " <> show ex)))

    handleIO :: IOException -> IO (Either Text.Text ByteString)
    handleIO ex = pure (Left (Text.pack ("IO error: " <> show ex)))
