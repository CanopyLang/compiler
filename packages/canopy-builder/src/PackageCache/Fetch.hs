{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Package fetching with multi-source fallback for resilient dependency resolution.
--
-- This module implements a cascading fetch strategy for package archives:
--
-- 1. Local Canopy cache (@~\/.canopy\/packages\/{author}\/{project}\/{version}\/@)
-- 2. Elm cache fallback (@~\/.elm\/0.19.1\/packages\/{author}\/{project}\/{version}\/@)
-- 3. Canopy registry endpoint.json (provides download URL and hash)
-- 4. Direct GitHub ZIP download (deterministic URL from package name)
--
-- This design ensures that @canopy install@ degrades gracefully when the
-- primary registry is unavailable, following the same pattern as Go's
-- @GOPROXY=proxy.golang.org,direct@ fallback chain.
--
-- == Security
--
-- Archives downloaded via the registry path are verified against the
-- SHA-256 hash provided in @endpoint.json@. The comparison uses
-- 'Crypto.ConstantTime.secureCompareBS' to prevent timing side-channel
-- attacks. Archives from the GitHub fallback path are accepted without
-- hash verification (no registry-provided hash exists) but a warning
-- is logged.
--
-- == Architecture
--
-- All Canopy packages are hosted on GitHub (a requirement for @canopy publish@),
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

    -- * Hash Verification
    verifyArchiveHash,
    verifyGitHubArchive,

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
import qualified Crypto.ConstantTime as ConstantTime
import qualified Data.Aeson as Json
import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Digest.Pure.SHA as SHA
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
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
  | -- | Downloaded via the registry's endpoint.json with verified hash.
    FetchedRegistry !Text.Text !Text.Text
  | -- | Downloaded directly from GitHub with computed hash.
    --
    -- The first field is the download URL. The second field is the
    -- SHA-256 hex digest computed from the downloaded archive bytes,
    -- stored for lock file verification on subsequent fetches.
    FetchedGitHub !Text.Text !Text.Text
  deriving (Eq, Show)

-- | Errors that can occur during package fetching.
--
-- @since 0.19.2
data FetchError
  = -- | The registry endpoint.json was unreachable or returned invalid data.
    RegistryUnavailable !Text.Text
  | -- | GitHub returned an error or the ZIP was invalid.
    GitHubUnavailable !Text.Text
  | -- | The downloaded archive failed SHA-256 integrity verification.
    --
    -- Carries a description of the mismatch for diagnostics.
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

-- | The Canopy package registry base URL.
--
-- @since 0.19.2
registryBase :: String
registryBase = "https://package.canopy-lang.org"

-- | Build the GitHub ZIP download URL for a package version.
--
-- All Canopy packages live on GitHub, so the URL pattern is deterministic:
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
-- 4. Direct GitHub ZIP (with hash verification against lock file)
--
-- The optional 'Text.Text' parameter is the expected SHA-256 hex
-- digest from the lock file. When present and the GitHub fallback
-- is used, the downloaded archive is verified against this hash.
-- When absent, the hash is computed and returned for storage.
--
-- @since 0.19.2
fetchPackage :: Client.Manager -> Pkg.Name -> Version.Version -> Maybe Text.Text -> IO (Either FetchError FetchSource)
fetchPackage manager pkg ver expectedHash = do
  localResult <- checkLocalCache pkg ver
  maybe (tryElmCache manager pkg ver expectedHash) (pure . Right) localResult

-- | After local cache miss, try the Elm cache then network sources.
tryElmCache :: Client.Manager -> Pkg.Name -> Version.Version -> Maybe Text.Text -> IO (Either FetchError FetchSource)
tryElmCache manager pkg ver expectedHash = do
  elmResult <- checkElmCache pkg ver
  maybe (fetchFromNetwork manager pkg ver expectedHash) (pure . Right) elmResult

-- | Check the local Canopy package cache.
--
-- Looks for @~\/.canopy\/packages\/{author}\/{project}\/{version}\/@ and
-- returns 'CachedLocal' if the directory exists. Also checks the fallback
-- author mapping (e.g. @canopy@ -> @elm@) for backward compatibility.
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
    else
      maybe (pure Nothing) (checkLocalCacheDirect ver) (fallbackPkg pkg)

-- | Check the legacy Elm 0.19.1 package cache.
--
-- Looks for @~\/.elm\/0.19.1\/packages\/{author}\/{project}\/{version}\/@ and
-- returns 'CachedElm' if found. Also checks the fallback author mapping
-- for backward compatibility.
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
    else
      maybe (pure Nothing) (checkElmCacheDirect ver) (fallbackPkg pkg)

-- | Non-recursive local cache check (avoids infinite fallback loop).
checkLocalCacheDirect :: Version.Version -> Pkg.Name -> IO (Maybe FetchSource)
checkLocalCacheDirect ver pkg = do
  home <- Dir.getHomeDirectory
  let path = home </> ".canopy" </> "packages" </> Pkg.toFilePath pkg </> Version.toChars ver
  exists <- Dir.doesDirectoryExist path
  if exists
    then do
      Log.logEvent (PackageOperation "cache-hit-fallback" (Text.pack path))
      pure (Just (CachedLocal path))
    else pure Nothing

-- | Non-recursive Elm cache check (avoids infinite fallback loop).
checkElmCacheDirect :: Version.Version -> Pkg.Name -> IO (Maybe FetchSource)
checkElmCacheDirect ver pkg = do
  home <- Dir.getHomeDirectory
  let path = home </> ".elm" </> "0.19.1" </> "packages" </> Pkg.toFilePath pkg </> Version.toChars ver
  exists <- Dir.doesDirectoryExist path
  if exists
    then do
      Log.logEvent (PackageOperation "elm-cache-hit-fallback" (Text.pack path))
      pure (Just (CachedElm path))
    else pure Nothing

-- | Map a package to its fallback author equivalent.
--
-- When @canopy\/core@ is not found on disk, try @elm\/core@ and vice versa.
-- Returns 'Nothing' if no fallback mapping exists or if the package has
-- already been tried (to prevent infinite recursion).
--
-- @since 0.19.2
fallbackPkg :: Pkg.Name -> Maybe Pkg.Name
fallbackPkg (Pkg.Name author project)
  | author == Pkg.canopy = Just (Pkg.Name Pkg.elm project)
  | author == Pkg.canopyExplorations = Just (Pkg.Name Pkg.elmExplorations project)
  | author == Pkg.elm = Just (Pkg.Name Pkg.canopy project)
  | author == Pkg.elmExplorations = Just (Pkg.Name Pkg.canopyExplorations project)
  | otherwise = Nothing

-- | Attempt to fetch a package from network sources.
--
-- Tries the registry endpoint.json first, then falls back to
-- a direct GitHub ZIP download with optional hash verification.
--
-- @since 0.19.2
fetchFromNetwork :: Client.Manager -> Pkg.Name -> Version.Version -> Maybe Text.Text -> IO (Either FetchError FetchSource)
fetchFromNetwork manager pkg ver expectedHash = do
  Log.logEvent (PackageOperation "network-fetch" (Text.pack (Pkg.toChars pkg <> " " <> Version.toChars ver)))
  registryResult <- fetchViaEndpoint manager pkg ver
  either (\_ -> fetchFromGitHub manager pkg ver expectedHash) (pure . Right) registryResult

-- | Fetch a package via the registry's endpoint.json.
--
-- The registry serves endpoint files at:
-- @\/packages\/{author}\/{project}\/{version}\/endpoint.json@
--
-- The response contains the download URL and content hash. After
-- downloading the archive from the URL, the SHA-256 digest of the
-- downloaded bytes is computed and compared against the expected hash
-- using constant-time comparison to prevent timing attacks.
--
-- Returns 'IntegrityCheckFailed' if the hash does not match.
--
-- @since 0.19.2
fetchViaEndpoint :: Client.Manager -> Pkg.Name -> Version.Version -> IO (Either FetchError FetchSource)
fetchViaEndpoint manager pkg ver = do
  let endpointUrl = buildEndpointUrl pkg ver
  Log.logEvent (PackageOperation "endpoint-fetch" (Text.pack endpointUrl))
  endpointResult <- safeHttpGet manager endpointUrl
  either (pure . Left . RegistryUnavailable) (fetchAndVerify manager pkg ver) endpointResult

-- | Parse the endpoint response and download the archive with hash verification.
--
-- @since 0.19.2
fetchAndVerify :: Client.Manager -> Pkg.Name -> Version.Version -> ByteString -> IO (Either FetchError FetchSource)
fetchAndVerify manager pkg ver endpointBytes =
  maybe
    (pure (Left (RegistryUnavailable "Invalid endpoint.json response")))
    (downloadAndVerify manager pkg ver)
    (Json.decode (LBS.fromStrict endpointBytes))

-- | Download an archive from the endpoint URL and verify its SHA-256 hash.
--
-- @since 0.19.2
downloadAndVerify :: Client.Manager -> Pkg.Name -> Version.Version -> EndpointResponse -> IO (Either FetchError FetchSource)
downloadAndVerify manager pkg ver ep = do
  let archiveUrl = Text.unpack (_epUrl ep)
  Log.logEvent (PackageOperation "archive-download" (_epUrl ep))
  archiveResult <- safeHttpGet manager archiveUrl
  pure (either (Left . RegistryUnavailable) (verifyAndReturn pkg ver ep) archiveResult)

-- | Verify the downloaded archive bytes against the expected hash.
--
-- @since 0.19.2
verifyAndReturn :: Pkg.Name -> Version.Version -> EndpointResponse -> ByteString -> Either FetchError FetchSource
verifyAndReturn pkg ver ep archiveBytes =
  case verifyArchiveHash (_epHash ep) archiveBytes of
    True ->
      Right (FetchedRegistry (_epUrl ep) (_epHash ep))
    False ->
      Left (IntegrityCheckFailed (buildMismatchMessage pkg ver (_epHash ep) actualHashText))
  where
    actualHashText = computeSha256Hex archiveBytes

-- | Verify that archive bytes match an expected SHA-256 hash.
--
-- The expected hash should be a hex-encoded SHA-256 digest (64 characters).
-- Uses constant-time comparison to prevent timing side-channel attacks.
--
-- @since 0.19.2
verifyArchiveHash :: Text.Text -> ByteString -> Bool
verifyArchiveHash expectedHash archiveBytes =
  ConstantTime.secureCompareBS expectedHashBytes actualHashBytes
  where
    expectedHashBytes = TextEnc.encodeUtf8 expectedHash
    actualHashBytes = TextEnc.encodeUtf8 (computeSha256Hex archiveBytes)

-- | Compute the SHA-256 hex digest of a 'ByteString'.
--
-- @since 0.19.2
computeSha256Hex :: ByteString -> Text.Text
computeSha256Hex bytes =
  Text.pack (SHA.showDigest (SHA.sha256 (LBS.fromStrict bytes)))

-- | Build a human-readable integrity mismatch message.
--
-- @since 0.19.2
buildMismatchMessage :: Pkg.Name -> Version.Version -> Text.Text -> Text.Text -> Text.Text
buildMismatchMessage pkg ver expected actual =
  Text.concat
    [ "Hash mismatch for ",
      Text.pack (Pkg.toChars pkg),
      " ",
      Text.pack (Version.toChars ver),
      ": expected ",
      expected,
      " but got ",
      actual
    ]

-- | Build the endpoint.json URL for a package version.
buildEndpointUrl :: Pkg.Name -> Version.Version -> String
buildEndpointUrl pkg ver =
  registryBase
    <> "/packages/"
    <> Pkg.toChars pkg
    <> "/"
    <> Version.toChars ver
    <> "/endpoint.json"

-- | Endpoint.json response structure from the Canopy registry.
--
-- @since 0.19.2
data EndpointResponse = EndpointResponse
  { _epUrl :: !Text.Text,
    _epHash :: !Text.Text
  }

instance Json.FromJSON EndpointResponse where
  parseJSON = Json.withObject "EndpointResponse" $ \o ->
    EndpointResponse
      <$> o Json..: "url"
      <*> o Json..: "hash"

-- | Fetch a package directly from GitHub with optional hash verification.
--
-- Uses the deterministic URL pattern for Canopy packages on GitHub:
-- @https:\/\/github.com\/{author}\/{project}\/zipball\/{version}\/@
--
-- This is the last-resort fallback when both the local caches and
-- the registry are unavailable. When an expected hash is provided
-- (from the lock file), the downloaded archive is verified against
-- it using constant-time comparison. When no hash is available
-- (fresh install), the hash is computed and returned for lock file
-- storage, and a warning is logged.
--
-- @since 0.19.2
fetchFromGitHub :: Client.Manager -> Pkg.Name -> Version.Version -> Maybe Text.Text -> IO (Either FetchError FetchSource)
fetchFromGitHub manager pkg ver expectedHash = do
  let zipUrl = gitHubZipUrl pkg ver
  Log.logEvent (PackageOperation "github-fetch" (Text.pack zipUrl))
  result <- safeHttpGet manager zipUrl
  pure (either (Left . GitHubUnavailable) (verifyGitHubArchive pkg ver zipUrl expectedHash) result)

-- | Verify a GitHub-downloaded archive against an optional expected hash.
--
-- When a hash is expected (from the lock file), the archive is
-- verified using constant-time comparison and rejected on mismatch.
-- When no hash is expected, the archive is accepted and its computed
-- hash is returned for future verification.
--
-- @since 0.19.2
verifyGitHubArchive :: Pkg.Name -> Version.Version -> String -> Maybe Text.Text -> ByteString -> Either FetchError FetchSource
verifyGitHubArchive pkg ver url expectedHash archiveBytes =
  maybe acceptUnverified verifyExpected expectedHash
  where
    actualHash = computeSha256Hex archiveBytes
    urlText = Text.pack url
    acceptUnverified = Right (FetchedGitHub urlText actualHash)
    verifyExpected expected = verifyExpectedHash pkg ver urlText actualHash expected

-- | Verify archive hash against an expected value with constant-time comparison.
--
-- @since 0.19.2
verifyExpectedHash :: Pkg.Name -> Version.Version -> Text.Text -> Text.Text -> Text.Text -> Either FetchError FetchSource
verifyExpectedHash pkg ver url actualHash expected
  | ConstantTime.secureCompareBS (TextEnc.encodeUtf8 expected) (TextEnc.encodeUtf8 actualHash) =
      Right (FetchedGitHub url actualHash)
  | otherwise =
      Left (IntegrityCheckFailed (buildMismatchMessage pkg ver expected actualHash))

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
