{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Http - HTTP client operations for package management and registry communication
--
-- This module provides a comprehensive HTTP client interface for the Canopy build
-- system, handling package downloads, registry communication, and file uploads.
-- Built on top of http-client with TLS support, it provides robust error handling,
-- automatic retries, and progress tracking for large operations.
--
-- == Architecture
--
-- The module is split across three implementation sub-modules:
--
--   * "Http.Error"   - 'Error' type and exception-to-error conversion helpers
--   * "Http.Archive" - ZIP archive streaming download and parsing
--   * "Http.Upload"  - Multipart form-data upload helpers
--
-- All public types and functions are re-exported from this module so callers
-- only need to import @Http@.
--
-- == Usage Examples
--
-- === Basic HTTP GET
--
-- @
-- manager <- getManager
-- result <- get manager "https://package.canopy-lang.org/packages/all"
--   []
--   HttpError
--   processPackageList
-- @
--
-- === Archive Download with Verification
--
-- @
-- result <- getArchive manager
--   "https://github.com/canopy-lang/core/archive/1.0.0.zip"
--   HttpError
--   ArchiveCorrupted
--   processArchive
-- @
--
-- === Package Upload
--
-- @
-- parts <- sequence
--   [ filePart "package" "canopy.json"
--   , filePart "archive" "package.zip"
--   ]
-- result <- upload manager "https://package.canopy-lang.org/upload" parts
-- @
--
-- @since 0.19.1
module Http
  ( Manager,
    getManager,
    toUrl,
    -- * Fetch
    get,
    post,
    Header,
    accept,
    authorization,
    Error (..),
    -- * Archives
    Sha,
    shaToChars,
    getArchive,
    getArchiveWithHeaders,
    -- * Fallback Policy
    FallbackPolicy (..),
    getWithFallback,
    getArchiveWithFallback,
    getArchiveWithHeadersAndFallback,
    fallbackToElmUrl,
    -- * Upload
    upload,
    uploadWithHeaders,
    filePart,
    jsonPart,
    stringPart,
    bytesPart,
  )
where

import qualified Canopy.PathValidation as PathValidation
import qualified Canopy.Version as Version
import qualified Codec.Archive.Zip as Zip
import qualified Control.Exception as Exception
import qualified Data.Text as Text
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BS
import qualified Data.Digest.Pure.SHA as SHA
import qualified Data.List as List
import qualified Network.HTTP as HTTP
import qualified Network.URI as URI
import qualified System.Directory as Directory
import Network.HTTP.Client
  ( Manager,
    brConsume,
    parseUrlThrow,
    responseBody,
    withResponse,
  )
import qualified Network.HTTP.Client as Client
import qualified Network.HTTP.Client.TLS as TLS
import Network.HTTP.Types.Header (Header, hAccept, hAcceptEncoding, hUserAgent)
import Network.HTTP.Types.Method (Method, methodGet, methodPost)
import Http.Archive (readArchive, readLocalArchive)
import Http.Error (Error (..), handleHttpException, handleIOException)
import Http.Upload
  ( upload,
    uploadWithHeaders,
    filePart,
    jsonPart,
    stringPart,
    bytesPart,
  )
import qualified System.IO as IO
import Prelude hiding (zip)

-- MANAGER

-- | Create a TLS-enabled HTTP connection manager.
--
-- The manager handles connection pooling, keep-alive, and TLS certificate
-- validation and should be reused across multiple HTTP operations.
--
-- @since 0.19.1
getManager :: IO Manager
getManager =
  Client.newManager TLS.tlsManagerSettings

-- URL

-- | Build a URL with query parameters.
--
-- Appends URL-encoded query parameters to a base URL.  An empty parameter
-- list returns the base URL unchanged.
--
-- @since 0.19.1
toUrl :: String -> [(String, String)] -> String
toUrl url params =
  case params of
    [] -> url
    _ : _ -> url <> ("?" <> HTTP.urlEncodeVars params)

-- FILE URL HELPERS

isFileUrl :: String -> Bool
isFileUrl url =
  case URI.parseURI url of
    Just uri -> URI.uriScheme uri == "file:"
    Nothing -> False

-- | Extract a filesystem path from a @file:\/\/@ URL.
--
-- Validates the extracted path against directory traversal, absolute
-- path escapes, and null byte injection before returning it.
-- Returns 'Nothing' for non-file URLs or paths that fail validation.
--
-- @since 0.19.2
fileUrlToPath :: String -> Maybe FilePath
fileUrlToPath url =
  case URI.parseURI url of
    Just uri | URI.uriScheme uri == "file:" ->
      either (const Nothing) Just (PathValidation.validatePath (URI.uriPath uri))
    _ -> Nothing

-- FETCH

-- | Perform an HTTP GET request.
--
-- @since 0.19.1
get :: Manager -> String -> [Header] -> (Error -> e) -> (ByteString -> IO (Either e a)) -> IO (Either e a)
get =
  fetch methodGet

-- | Perform an HTTP POST request.
--
-- @since 0.19.1
post :: Manager -> String -> [Header] -> (Error -> e) -> (ByteString -> IO (Either e a)) -> IO (Either e a)
post =
  fetch methodPost

fetch :: Method -> Manager -> String -> [Header] -> (Error -> e) -> (ByteString -> IO (Either e a)) -> IO (Either e a)
fetch methodVerb manager url headers onError onSuccess =
  if isFileUrl url
    then fetchLocal
    else fetchRemote
  where
    urlText = Text.pack url
    verb = Text.pack (BS.unpack methodVerb)

    fetchLocal =
      Exception.handle (handleIOException url onError) $
        case fileUrlToPath url of
          Just filePath -> do
            fileExists <- Directory.doesFileExist filePath
            if fileExists
              then do
                Log.logEvent (PackageOperation "local-read" (Text.pack filePath))
                content <- BS.readFile filePath
                onSuccess content
              else do
                Log.logEvent (PackageOperation "local-not-found" (Text.pack filePath))
                return (Left (onError (BadUrl url "File not found")))
          Nothing -> do
            Log.logEvent (PackageOperation "invalid-file-url" urlText)
            return (Left (onError (BadUrl url "Invalid file:// URL format")))

    fetchRemote =
      Exception.handle (handleIOException url onError) . Exception.handle (handleHttpException url onError) $ do
        Log.logEvent (PackageOperation verb urlText)
        req0 <- parseUrlThrow url
        let req1 =
              req0
                { Client.method = methodVerb,
                  Client.requestHeaders = addDefaultHeaders headers
                }
        withResponse req1 manager $ \response -> do
          Log.logEvent (PackageOperation (verb <> "-response") urlText)
          chunks <- brConsume (responseBody response)
          onSuccess (BS.concat chunks)

addDefaultHeaders :: [Header] -> [Header]
addDefaultHeaders headers =
  (hUserAgent, userAgent) : (hAcceptEncoding, "gzip") : headers

{-# NOINLINE userAgent #-}
userAgent :: ByteString
userAgent =
  BS.pack ("canopy/" <> Version.toChars Version.compiler)

-- | Create an HTTP Accept header for the given MIME type.
--
-- @since 0.19.1
accept :: ByteString -> Header
accept mime =
  (hAccept, mime)

-- | Create an Authorization header with the given value.
--
-- Typically used with a @Bearer@ token for private registry access.
--
-- @since 0.19.2
authorization :: ByteString -> Header
authorization value =
  ("Authorization", value)

-- FALLBACK POLICY

-- | Policy controlling whether fallback from canopy-lang.org to
-- elm-lang.org is permitted.
--
-- When 'AllowFallback' is used, a user-visible warning is printed to
-- stderr before attempting the fallback URL. 'DenyFallback' causes the
-- original error to be returned without attempting any fallback.
--
-- @since 0.19.2
data FallbackPolicy
  = -- | Allow fallback with a user-visible warning.
    AllowFallback
  | -- | Deny fallback; return the primary error.
    DenyFallback
  deriving (Eq, Show)

-- FALLBACK

-- | Convert a @canopy-lang.org@ URL to its @elm-lang.org@ equivalent.
--
-- @since 0.19.1
fallbackToElmUrl :: String -> String
fallbackToElmUrl url =
  let withPackageFallback = replaceString "package.canopy-lang.org" "package.elm-lang.org" url
      withMainFallback = replaceString "canopy-lang.org" "elm-lang.org" withPackageFallback
  in withMainFallback

replaceString :: String -> String -> String -> String
replaceString old new = go
  where
    go [] = []
    go str@(c : cs)
      | List.isPrefixOf old str = new ++ go (drop (length old) str)
      | otherwise = c : go cs

-- SHA

-- | SHA-256 digest type for archive integrity verification.
--
-- @since 0.19.1
type Sha = SHA.Digest SHA.SHA256State

-- | Convert a SHA-256 digest to its hexadecimal string representation.
--
-- @since 0.19.1
shaToChars :: Sha -> String
shaToChars =
  SHA.showDigest

-- ARCHIVE OPERATIONS

-- | Download a ZIP archive with custom headers and stream-verify its integrity.
--
-- @since 0.19.1
getArchiveWithHeaders ::
  Manager ->
  String ->
  [Header] ->
  (Error -> e) ->
  e ->
  ((Sha, Zip.Archive) -> IO (Either e a)) ->
  IO (Either e a)
getArchiveWithHeaders manager url headers onError err onSuccess =
  if isFileUrl url
    then fetchLocalArchive
    else fetchRemoteArchive
  where
    urlText = Text.pack url

    fetchLocalArchive =
      Exception.handle (handleIOException url onError) $
        case fileUrlToPath url of
          Just filePath -> do
            Log.logEvent (ArchiveOperation "local-read" (Text.pack filePath))
            result <- readLocalArchive filePath
            case result of
              Nothing -> do
                Log.logEvent (ArchiveOperation "local-read-failed" (Text.pack filePath))
                return (Left err)
              Just shaAndArchive -> do
                Log.logEvent (ArchiveOperation "local-read-ok" (Text.pack filePath))
                onSuccess shaAndArchive
          Nothing -> do
            Log.logEvent (ArchiveOperation "invalid-file-url" urlText)
            return (Left (onError (BadUrl url "Invalid file:// URL format")))

    fetchRemoteArchive =
      Exception.handle (handleIOException url onError) . Exception.handle (handleHttpException url onError) $ do
        Log.logEvent (PackageOperation "http-get" urlText)
        req0 <- parseUrlThrow url
        let req1 =
              req0
                { Client.method = methodGet,
                  Client.requestHeaders = addDefaultHeaders headers
                }
        withResponse req1 manager $ \response -> do
          Log.logEvent (PackageOperation "http-response" urlText)
          result <- readArchive (responseBody response)
          case result of
            Nothing -> do
              Log.logEvent (ArchiveOperation "parse-failed" urlText)
              return (Left err)
            Just shaAndArchive -> do
              Log.logEvent (ArchiveOperation "parse-ok" urlText)
              onSuccess shaAndArchive

-- | Download a ZIP archive and stream-verify its integrity (no custom headers).
--
-- @since 0.19.1
getArchive ::
  Manager ->
  String ->
  (Error -> e) ->
  e ->
  ((Sha, Zip.Archive) -> IO (Either e a)) ->
  IO (Either e a)
getArchive manager url = getArchiveWithHeaders manager url []

-- FALLBACK OPERATIONS

-- | GET with automatic fallback from @canopy-lang.org@ to @elm-lang.org@.
--
-- When 'AllowFallback' is set and the primary request fails, a warning
-- is printed to stderr before attempting the fallback URL. With
-- 'DenyFallback', the primary error is returned immediately.
--
-- @since 0.19.2
getWithFallback :: FallbackPolicy -> Manager -> String -> [Header] -> (Error -> e) -> (ByteString -> IO (Either e a)) -> IO (Either e a)
getWithFallback policy manager url headers onError onSuccess = do
  result <- get manager url headers onError onSuccess
  either (tryFallbackGet policy manager url headers onError onSuccess) (pure . Right) result

-- | Attempt a GET fallback if the policy allows it.
tryFallbackGet :: FallbackPolicy -> Manager -> String -> [Header] -> (Error -> e) -> (ByteString -> IO (Either e a)) -> e -> IO (Either e a)
tryFallbackGet DenyFallback _ _ _ _ _ primaryErr =
  pure (Left primaryErr)
tryFallbackGet AllowFallback manager url headers onError onSuccess primaryErr =
  let fallbackUrl = fallbackToElmUrl url
   in if fallbackUrl /= url
        then warnAndFetchGet manager fallbackUrl headers onError onSuccess
        else pure (Left primaryErr)

-- | Warn the user and perform a fallback GET request.
warnAndFetchGet :: Manager -> String -> [Header] -> (Error -> e) -> (ByteString -> IO (Either e a)) -> IO (Either e a)
warnAndFetchGet manager fallbackUrl headers onError onSuccess = do
  emitFallbackWarning fallbackUrl
  Log.logEvent (PackageOperation "fallback" (Text.pack fallbackUrl))
  get manager fallbackUrl headers onError onSuccess

-- | Archive download with automatic fallback from @canopy-lang.org@ to @elm-lang.org@.
--
-- When 'AllowFallback' is set and the primary request fails, a warning
-- is printed to stderr before attempting the fallback URL.
--
-- @since 0.19.2
getArchiveWithFallback ::
  FallbackPolicy ->
  Manager ->
  String ->
  (Error -> e) ->
  e ->
  ((Sha, Zip.Archive) -> IO (Either e a)) ->
  IO (Either e a)
getArchiveWithFallback policy manager url onError err onSuccess = do
  result <- getArchive manager url onError err onSuccess
  either (tryFallbackArchive policy manager url onError err onSuccess) (pure . Right) result

-- | Attempt an archive fallback if the policy allows it.
tryFallbackArchive :: FallbackPolicy -> Manager -> String -> (Error -> e) -> e -> ((Sha, Zip.Archive) -> IO (Either e a)) -> e -> IO (Either e a)
tryFallbackArchive DenyFallback _ _ _ _ _ primaryErr =
  pure (Left primaryErr)
tryFallbackArchive AllowFallback manager url onError err onSuccess primaryErr =
  let fallbackUrl = fallbackToElmUrl url
   in if fallbackUrl /= url
        then warnAndFetchArchive manager fallbackUrl onError err onSuccess
        else pure (Left primaryErr)

-- | Warn the user and perform a fallback archive request.
warnAndFetchArchive :: Manager -> String -> (Error -> e) -> e -> ((Sha, Zip.Archive) -> IO (Either e a)) -> IO (Either e a)
warnAndFetchArchive manager fallbackUrl onError err onSuccess = do
  emitFallbackWarning fallbackUrl
  Log.logEvent (PackageOperation "archive-fallback" (Text.pack fallbackUrl))
  getArchive manager fallbackUrl onError err onSuccess

-- | Archive download with custom headers and automatic fallback.
--
-- When 'AllowFallback' is set and the primary request fails, a warning
-- is printed to stderr before attempting the fallback URL.
--
-- @since 0.19.2
getArchiveWithHeadersAndFallback ::
  FallbackPolicy ->
  Manager ->
  String ->
  [Header] ->
  (Error -> e) ->
  e ->
  ((Sha, Zip.Archive) -> IO (Either e a)) ->
  IO (Either e a)
getArchiveWithHeadersAndFallback policy manager url headers onError err onSuccess = do
  result <- getArchiveWithHeaders manager url headers onError err onSuccess
  either (tryFallbackHeadersArchive policy manager url headers onError err onSuccess) (pure . Right) result

-- | Attempt a headers+archive fallback if the policy allows it.
tryFallbackHeadersArchive :: FallbackPolicy -> Manager -> String -> [Header] -> (Error -> e) -> e -> ((Sha, Zip.Archive) -> IO (Either e a)) -> e -> IO (Either e a)
tryFallbackHeadersArchive DenyFallback _ _ _ _ _ _ primaryErr =
  pure (Left primaryErr)
tryFallbackHeadersArchive AllowFallback manager url headers onError err onSuccess primaryErr =
  let fallbackUrl = fallbackToElmUrl url
   in if fallbackUrl /= url
        then warnAndFetchHeadersArchive manager fallbackUrl headers onError err onSuccess
        else pure (Left primaryErr)

-- | Warn the user and perform a fallback headers+archive request.
warnAndFetchHeadersArchive :: Manager -> String -> [Header] -> (Error -> e) -> e -> ((Sha, Zip.Archive) -> IO (Either e a)) -> IO (Either e a)
warnAndFetchHeadersArchive manager fallbackUrl headers onError err onSuccess = do
  emitFallbackWarning fallbackUrl
  Log.logEvent (PackageOperation "fallback" (Text.pack fallbackUrl))
  getArchiveWithHeaders manager fallbackUrl headers onError err onSuccess

-- | Emit a user-visible fallback warning to stderr.
--
-- This ensures users are aware when a request is being served from
-- the Elm registry instead of the Canopy registry, which is a
-- supply-chain concern.
emitFallbackWarning :: String -> IO ()
emitFallbackWarning fallbackUrl =
  IO.hPutStrLn IO.stderr $
    "WARNING: canopy-lang.org unreachable, falling back to " <> fallbackUrl
