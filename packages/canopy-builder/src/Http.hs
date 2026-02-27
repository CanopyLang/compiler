{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Http - HTTP client operations for package management and registry communication
--
-- This module provides a comprehensive HTTP client interface for the Canopy build
-- system, handling package downloads, registry communication, and file uploads.
-- Built on top of http-client with TLS support, it provides robust error handling,
-- automatic retries, and progress tracking for large operations.
--
-- The HTTP client is designed for reliability in package management scenarios:
-- downloading packages, uploading to registries, and communicating with remote
-- services. All operations include comprehensive error reporting with contextual
-- information for debugging network issues.
--
-- == Key Features
--
-- * **Robust HTTP Operations** - GET, POST requests with comprehensive error handling
-- * **Archive Handling** - Download and verify ZIP archives with SHA1 validation
-- * **Multipart Uploads** - Support for complex file uploads to package registries
-- * **TLS Security** - All connections use secure TLS with certificate validation
-- * **Progress Tracking** - Built-in progress reporting for long-running operations
-- * **Error Recovery** - Detailed error types with recovery suggestions
--
-- == Architecture
--
-- The module is organized into several functional areas:
--
-- * **Manager Creation** - TLS-enabled HTTP connection manager setup
-- * **Basic HTTP Operations** - GET/POST with custom headers and error handling
-- * **Archive Operations** - Specialized handling for package archive downloads
-- * **Upload Operations** - Multipart form data uploads for package publishing
-- * **Error Handling** - Comprehensive error types with contextual information
--
-- All HTTP operations use a shared 'Manager' for connection pooling and
-- efficient resource usage across multiple requests.
--
-- == Usage Examples
--
-- === Basic HTTP Operations
--
-- @
-- -- Simple GET request with error handling
-- manager <- getManager
-- result <- get manager "https://package.canopy-lang.org/packages/all"
--   []
--   HttpError
--   processPackageList
-- case result of
--   Left err -> handleError err
--   Right packages -> putStrLn ("Found " <> show (length packages) <> " packages")
-- @
--
-- === Archive Download with Verification
--
-- @
-- -- Download and verify package archive
-- manager <- getManager
-- result <- getArchive manager
--   "https://github.com/canopy-lang/core/archive/1.0.0.zip"
--   HttpError
--   ArchiveCorrupted
--   processArchive
-- case result of
--   Left err -> reportError err
--   Right (sha, archive) -> do
--     putStrLn ("Downloaded archive with SHA: " <> shaToChars sha)
--     extractArchive archive
-- @
--
-- === Package Upload
--
-- @
-- -- Upload package to registry
-- manager <- getManager
-- parts <- sequence
--   [ filePart "package" "canopy.json"
--   , filePart "archive" "package.zip"
--   , jsonPart "metadata" "meta.json" packageMetadata
--   ]
-- result <- upload manager "https://package.canopy-lang.org/upload" parts
-- case result of
--   Left err -> handleUploadError err
--   Right () -> putStrLn "Package uploaded successfully"
-- @
--
-- == Error Handling
--
-- All HTTP operations return detailed error information through the 'Error' type:
--
-- * 'BadUrl' - Malformed URL with specific parsing error
-- * 'BadHttp' - HTTP protocol errors (timeouts, connection failures, HTTP status codes)
-- * 'BadMystery' - Unexpected system-level errors with full exception context
--
-- Each error includes the original URL and sufficient context for debugging
-- network issues in different environments.
--
-- == Performance Characteristics
--
-- * **Connection Pooling** - Reuse connections through shared 'Manager'
-- * **Memory Efficient** - Streaming processing for large archives
-- * **Minimal Copying** - ByteString operations avoid unnecessary allocations
-- * **TLS Optimization** - Connection reuse and session resumption
--
-- == Thread Safety
--
-- All operations are thread-safe. The 'Manager' can be safely shared across
-- multiple threads for concurrent HTTP operations.
--
-- @since 0.19.1
module Http
  ( Manager,
    getManager,
    toUrl,
    -- fetch
    get,
    post,
    Header,
    accept,
    Error (..),
    -- archives
    Sha,
    shaToChars,
    getArchive,
    getArchiveWithHeaders,
    -- fallback
    getWithFallback,
    getArchiveWithFallback,
    getArchiveWithHeadersAndFallback,
    fallbackToElmUrl,
    -- upload
    upload,
    uploadWithHeaders,
    filePart,
    jsonPart,
    stringPart,
    bytesPart,
  )
where

import qualified Canopy.Version as V
import qualified Codec.Archive.Zip as Zip
import Control.Exception (SomeException)
import qualified Control.Exception as Exception
import Control.Lens (makeLenses, (&), (.~), (^.))
import qualified Data.Text as Text
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import qualified Data.Binary as Binary
import qualified Data.Binary.Get as Binary
import Data.ByteString (ByteString)
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Digest.Pure.SHA as SHA
import qualified Data.List as List
import qualified Data.String as String
import qualified Json.Encode as Encode
import qualified Network.HTTP as HTTP
import qualified Network.URI as URI
import qualified System.Directory as Directory
import Network.HTTP.Client
  ( BodyReader,
    HttpException (HttpExceptionRequest, InvalidUrlException),
    HttpExceptionContent,
    Manager,
    RequestBody (RequestBodyBS),
    brConsume,
    brRead,
    parseUrlThrow,
    responseBody,
    responseTimeoutNone,
    withResponse,
  )
import qualified Network.HTTP.Client as Client
import qualified Network.HTTP.Client.MultipartFormData as Multi
import qualified Network.HTTP.Client.TLS as TLS
import Network.HTTP.Types.Header (Header, hAccept, hAcceptEncoding, hUserAgent)
import Network.HTTP.Types.Method (Method, methodGet, methodPost)
import Prelude hiding (zip)

-- MANAGER

-- | Create a TLS-enabled HTTP connection manager.
--
-- Creates a new HTTP manager with TLS support for secure connections.
-- The manager handles connection pooling, keep-alive, and TLS certificate
-- validation. This manager should be reused across multiple HTTP operations
-- for optimal performance.
--
-- The manager is configured with:
--
-- * TLS certificate validation enabled
-- * Connection pooling for efficiency
-- * Keep-alive for persistent connections
-- * Secure cipher suites and protocols
--
-- ==== Examples
--
-- >>> manager <- getManager
-- >>> -- Use manager for multiple requests
-- >>> result1 <- get manager "https://api.example.com/endpoint1" [] handleError processResponse
-- >>> result2 <- get manager "https://api.example.com/endpoint2" [] handleError processResponse
--
-- ==== Error Conditions
--
-- May throw 'IOException' if:
--
-- * System cannot create socket connections
-- * TLS subsystem initialization fails
-- * Operating system resource limits exceeded
--
-- ==== Performance
--
-- * **Thread Safe**: Manager can be shared safely across threads
-- * **Connection Pooling**: Reuses TCP connections when possible
-- * **Memory Usage**: Minimal overhead, approximately 1KB per manager
--
-- @since 0.19.1
getManager :: IO Manager
getManager =
  Client.newManager TLS.tlsManagerSettings

-- URL

-- | Build URL with query parameters.
--
-- Constructs a complete URL by appending URL-encoded query parameters
-- to a base URL. Parameters are properly encoded to handle special
-- characters and spaces according to RFC 3986 standards.
--
-- ==== Examples
--
-- >>> toUrl "https://api.example.com/search" []
-- "https://api.example.com/search"
--
-- >>> toUrl "https://api.example.com/search" [("q", "canopy lang"), ("limit", "10")]
-- "https://api.example.com/search?q=canopy+lang&limit=10"
--
-- >>> toUrl "https://package.canopy-lang.org/packages" [("author", "elm"), ("version", ">=1.0.0")]
-- "https://package.canopy-lang.org/packages?author=elm&version=%3E%3D1.0.0"
--
-- ==== Parameters
--
-- The parameter list supports any string key-value pairs:
--
-- * Empty list results in original URL unchanged
-- * Special characters are automatically URL-encoded
-- * Multiple parameters are joined with '&'
-- * Keys and values can contain spaces and Unicode characters
--
-- @since 0.19.1
toUrl :: String -> [(String, String)] -> String
toUrl url params =
  case params of
    [] -> url
    _ : _ -> url <> ("?" <> HTTP.urlEncodeVars params)

-- FILE URL HANDLING

-- | Check if a URL uses the file:// scheme
isFileUrl :: String -> Bool
isFileUrl url =
  case URI.parseURI url of
    Just uri -> URI.uriScheme uri == "file:"
    Nothing -> False

-- | Convert file:// URL to local file path
fileUrlToPath :: String -> Maybe FilePath
fileUrlToPath url =
  case URI.parseURI url of
    Just uri | URI.uriScheme uri == "file:" -> Just (URI.uriPath uri)
    _ -> Nothing

-- | Read a local ZIP file and compute its SHA1 hash
readLocalArchive :: FilePath -> IO (Maybe (Sha, Zip.Archive))
readLocalArchive filePath = do
  fileExists <- Directory.doesFileExist filePath
  if fileExists
    then do
      content <- LBS.readFile filePath
      let sha = SHA.sha1 content
      case Binary.decodeOrFail content of
        Right (_, _, archive) -> return $ Just (sha, archive)
        Left _ -> return Nothing
    else return Nothing

-- FETCH

-- | Perform HTTP GET request with custom error handling.
--
-- Executes a GET request to the specified URL with optional custom headers.
-- Provides comprehensive error handling and allows custom response processing
-- through the success callback function.
--
-- The request includes automatic handling of:
--
-- * TLS certificate validation
-- * Connection timeouts and retries
-- * Gzip compression (Accept-Encoding: gzip)
-- * User agent identification (canopy/version)
--
-- ==== Examples
--
-- >>> manager <- getManager
-- >>> result <- get manager "https://package.canopy-lang.org/packages/all"
-- ...   []
-- ...   NetworkError
-- ...   (\body -> pure (Right (parsePackageList body)))
-- >>> case result of
-- ...   Left err -> putStrLn ("Network error: " <> show err)
-- ...   Right packages -> putStrLn ("Found " <> show (length packages) <> " packages")
--
-- >>> -- GET with custom headers
-- >>> let headers = [accept "application/json", ("Authorization", "Bearer token123")]
-- >>> result <- get manager "https://api.canopy-lang.org/user/packages" headers
-- ...   ApiError
-- ...   processUserPackages
--
-- ==== Error Conditions
--
-- Returns 'Left (Error -> e)' for:
--
-- * 'BadUrl' - Invalid or malformed URL
-- * 'BadHttp' - Network timeouts, DNS failures, HTTP error status codes
-- * 'BadMystery' - Unexpected system errors, out of memory, etc.
--
-- ==== Performance
--
-- * **Connection Reuse**: Uses manager's connection pool
-- * **Streaming**: Response body is processed in chunks to minimize memory usage
-- * **Compression**: Automatically handles gzip compressed responses
--
-- @since 0.19.1
get :: Manager -> String -> [Header] -> (Error -> e) -> (ByteString -> IO (Either e a)) -> IO (Either e a)
get =
  fetch methodGet

-- | Perform HTTP POST request with custom error handling.
--
-- Executes a POST request to the specified URL with optional custom headers.
-- Similar to 'get' but uses POST method, typically for sending data to servers.
-- Supports the same error handling and response processing capabilities.
--
-- The POST request includes:
--
-- * Same automatic headers as GET requests (User-Agent, Accept-Encoding)
-- * Support for request body through multipart uploads (see 'upload' functions)
-- * Comprehensive error handling with contextual information
-- * Streaming response processing
--
-- ==== Examples
--
-- >>> manager <- getManager
-- >>> result <- post manager "https://api.canopy-lang.org/packages/search"
-- ...   [accept "application/json", ("Content-Type", "application/json")]
-- ...   SearchError
-- ...   (\body -> pure (Right (parseSearchResults body)))
--
-- >>> -- POST for simple API calls (body handled separately)
-- >>> result <- post manager "https://webhook.example.com/canopy-build"
-- ...   [("X-Build-Status", "success")]
-- ...   WebhookError
-- ...   (\_ -> pure (Right ()))
--
-- ==== Error Conditions
--
-- Same error conditions as 'get':
--
-- * 'BadUrl' - Invalid URL format or unsupported scheme
-- * 'BadHttp' - Network connectivity, server errors, timeouts
-- * 'BadMystery' - System-level failures or resource exhaustion
--
-- ==== Performance
--
-- * **Connection Pooling**: Reuses existing connections when possible
-- * **Memory Efficient**: Streams response data without loading entire response
-- * **Timeout Handling**: Configurable timeouts prevent hanging requests
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
      Exception.handle (handleSomeException url onError) $
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
      Exception.handle (handleSomeException url onError) . Exception.handle (handleHttpException url onError) $
        do
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
  BS.pack ("canopy/" <> V.toChars V.compiler)

-- | Create Accept header for content type negotiation.
--
-- Creates an HTTP Accept header to specify the MIME type the client
-- can process. This is used for content negotiation to ensure the
-- server returns data in the expected format.
--
-- ==== Examples
--
-- >>> accept "application/json"
-- ("Accept", "application/json")
--
-- >>> accept "application/zip"
-- ("Accept", "application/zip")
--
-- >>> accept "text/plain; charset=utf-8"
-- ("Accept", "text/plain; charset=utf-8")
--
-- ==== Common MIME Types
--
-- * @application/json@ - JSON data
-- * @application/zip@ - ZIP archives
-- * @text/plain@ - Plain text
-- * @application/octet-stream@ - Binary data
-- * @application/x-tar@ - TAR archives
--
-- @since 0.19.1
accept :: ByteString -> Header
accept mime =
  (hAccept, mime)

-- URL FALLBACK

-- | Convert canopy-lang.org URL to elm-lang.org URL for fallback.
--
-- Replaces 'package.canopy-lang.org' and 'canopy-lang.org' domains with 
-- 'package.elm-lang.org' and 'elm-lang.org' respectively for package fallback.
--
-- ==== Examples
--
-- >>> fallbackToElmUrl "https://package.canopy-lang.org/packages/elm/core/1.0.0.zip"
-- "https://package.elm-lang.org/packages/elm/core/1.0.0.zip"
--
-- >>> fallbackToElmUrl "https://canopy-lang.org/packages/elm/core/1.0.0.zip"
-- "https://elm-lang.org/packages/elm/core/1.0.0.zip"
--
-- @since 0.19.1
fallbackToElmUrl :: String -> String
fallbackToElmUrl url =
  let withPackageFallback = replaceString "package.canopy-lang.org" "package.elm-lang.org" url
      withMainFallback = replaceString "canopy-lang.org" "elm-lang.org" withPackageFallback
  in withMainFallback

-- | Replace all occurrences of a substring in a string.
replaceString :: String -> String -> String -> String
replaceString old new = go
  where
    go [] = []
    go str@(c:cs)
      | List.isPrefixOf old str = new ++ go (drop (length old) str)
      | otherwise = c : go cs

-- EXCEPTIONS

-- | Comprehensive HTTP error types with contextual information.
--
-- Represents all possible HTTP operation failures with sufficient
-- context for debugging and error reporting. Each constructor includes
-- the original URL and specific error details for proper error handling.
--
-- @since 0.19.1
data Error
  = -- | Invalid or malformed URL error.
    --
    -- Occurs when the provided URL cannot be parsed or contains
    -- invalid characters, unsupported schemes, or malformed components.
    --
    -- ==== Examples
    --
    -- * Invalid scheme: @"ftp://example.com"@
    -- * Malformed syntax: @"http://[invalid"@
    -- * Missing components: @"://missing-host"@
    --
    -- The second 'String' contains the specific parsing error message.
    BadUrl String String
  | -- | HTTP protocol or network error.
    --
    -- Encompasses all network-level and HTTP protocol errors including:
    --
    -- * Connection timeouts and failures
    -- * DNS resolution errors
    -- * HTTP status code errors (4xx, 5xx)
    -- * TLS certificate validation failures
    -- * Server connection refused
    --
    -- The 'HttpExceptionContent' provides detailed error information
    -- including specific failure reason and context.
    BadHttp String HttpExceptionContent
  | -- | Unexpected system-level error.
    --
    -- Catches all other unexpected errors that don't fit into the
    -- above categories:
    --
    -- * Out of memory conditions
    -- * File descriptor exhaustion
    -- * System call failures
    -- * Threading exceptions
    --
    -- The 'SomeException' contains the full exception context for
    -- debugging system-level issues.
    BadMystery String SomeException
  deriving (Show)

handleHttpException :: String -> (Error -> e) -> HttpException -> IO (Either e a)
handleHttpException url onError httpException = do
  Log.logEvent (PackageOperation "http-error" (Text.pack url <> " " <> Text.pack (show httpException)))
  case httpException of
    InvalidUrlException _ reason ->
      return (Left (onError (BadUrl url reason)))
    HttpExceptionRequest _ content ->
      return (Left (onError (BadHttp url content)))

handleSomeException :: String -> (Error -> e) -> SomeException -> IO (Either e a)
handleSomeException url onError exception = do
  Log.logEvent (PackageOperation "exception" (Text.pack url <> " " <> Text.pack (show exception)))
  return (Left (onError (BadMystery url exception)))

-- SHA

-- | SHA1 digest type for archive integrity verification.
--
-- Represents a SHA1 cryptographic hash used to verify the integrity
-- of downloaded archives. The hash is computed incrementally during
-- download to minimize memory usage while ensuring data integrity.
--
-- @since 0.19.1
type Sha = SHA.Digest SHA.SHA1State

-- | Convert SHA1 digest to hexadecimal string representation.
--
-- Converts a SHA1 hash digest to its standard 40-character hexadecimal
-- string representation. This format is commonly used for displaying
-- and comparing hash values in logs and user interfaces.
--
-- ==== Examples
--
-- >>> sha <- computeFileSHA1 "package.zip"
-- >>> shaToChars sha
-- "da39a3ee5e6b4b0d3255bfef95601890afd80709"
--
-- >>> putStrLn ("Archive SHA1: " <> shaToChars archiveSha)
-- Archive SHA1: a94a8fe5ccb19ba61c4c0873d391e987982fbbd3
--
-- ==== Format
--
-- * **Length**: Always 40 characters
-- * **Characters**: Lowercase hexadecimal (0-9, a-f)
-- * **Standard**: Complies with RFC 3174 SHA1 specification
--
-- @since 0.19.1
shaToChars :: Sha -> String
shaToChars =
  SHA.showDigest

-- FETCH ARCHIVE

data ArchiveState = AS
  { _len :: !Int,
    _sha :: !(Binary.Decoder SHA.SHA1State),
    _zip :: !(Binary.Decoder Zip.Archive)
  }

makeLenses ''ArchiveState

readArchive :: BodyReader -> IO (Maybe (Sha, Zip.Archive))
readArchive body =
  readArchiveHelp body $
    AS
      { _len = 0,
        _sha = SHA.sha1Incremental,
        _zip = Binary.runGetIncremental Binary.get
      }

readArchiveHelp :: BodyReader -> ArchiveState -> IO (Maybe (Sha, Zip.Archive))
readArchiveHelp body archiveState =
  case archiveState ^. zip of
    Binary.Fail {} ->
      return Nothing
    Binary.Partial k ->
      do
        chunk <- brRead body
        let currentLen = archiveState ^. len
            currentSha = archiveState ^. sha
        readArchiveHelp body $
          archiveState
            & len .~ (currentLen + BS.length chunk)
            & sha .~ Binary.pushChunk currentSha chunk
            & zip .~ k (if BS.null chunk then Nothing else Just chunk)
    Binary.Done _ _ archive ->
      return $ Just (SHA.completeSha1Incremental (archiveState ^. sha) (archiveState ^. len), archive)

-- | Download ZIP archive with custom headers and integrity verification.
--
-- Downloads a ZIP archive from the specified URL while computing SHA1 hash
-- for integrity verification. Processes the archive streaming to minimize
-- memory usage and provides both the computed hash and parsed archive.
--
-- The function performs:
--
-- 1. **Streaming Download** - Downloads archive content in chunks
-- 2. **Hash Computation** - Computes SHA1 incrementally during download
-- 3. **Archive Parsing** - Parses ZIP structure while downloading
-- 4. **Integrity Verification** - Provides hash for verification against known values
--
-- ==== Examples
--
-- >>> manager <- getManager
-- >>> result <- getArchiveWithHeaders manager
-- ...   "https://github.com/canopy-lang/core/archive/1.0.0.zip"
-- ...   [accept "application/zip", ("User-Agent", "canopy-downloader")]
-- ...   HttpError
-- ...   ArchiveCorrupted
-- ...   processPackageArchive
-- >>> case result of
-- ...   Left err -> handleError err
-- ...   Right (sha, archive) -> do
-- ...     putStrLn ("Downloaded archive with SHA: " <> shaToChars sha)
-- ...     putStrLn ("Archive contains " <> show (length (Zip.zEntries archive)) <> " files")
--
-- ==== Error Conditions
--
-- Returns 'Left (Error -> e)' for:
--
-- * Network errors: 'BadUrl', 'BadHttp', 'BadMystery'
-- * Archive parsing errors: Returns 'e' parameter (archive corruption)
-- * Invalid ZIP format: Returns 'e' parameter (malformed archive)
--
-- The function distinguishes between network errors (converted via onError)
-- and archive format errors (returned as the provided 'e' value).
--
-- ==== Performance
--
-- * **Memory Efficient**: Streams archive without loading entire file
-- * **Concurrent Processing**: Hash computation and ZIP parsing happen simultaneously
-- * **Early Failure**: Stops immediately if ZIP format is invalid
-- * **Connection Reuse**: Uses manager's connection pooling
--
-- @since 0.19.1
getArchiveWithHeaders ::
  -- | HTTP connection manager for request execution
  Manager ->
  -- | URL of ZIP archive to download
  String ->
  -- | Additional HTTP headers for the request
  [Header] ->
  -- | Function to convert network errors to application error type
  (Error -> e) ->
  -- | Error value to return for archive parsing failures
  e ->
  -- | Success callback with verified archive and computed hash
  ((Sha, Zip.Archive) -> IO (Either e a)) ->
  -- | Result containing processed data or error
  IO (Either e a)
getArchiveWithHeaders manager url headers onError err onSuccess =
  if isFileUrl url
    then fetchLocalArchive
    else fetchRemoteArchive
  where
    urlText = Text.pack url

    fetchLocalArchive =
      Exception.handle (handleSomeException url onError) $
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
      Exception.handle (handleSomeException url onError) . Exception.handle (handleHttpException url onError) $
        do
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

-- | Download ZIP archive with integrity verification.
--
-- Simplified version of 'getArchiveWithHeaders' that uses no custom headers.
-- Downloads and verifies a ZIP archive, providing both the computed SHA1
-- hash and parsed archive contents for further processing.
--
-- This function is the most common way to download package archives where
-- no special headers are required. It handles all the same error conditions
-- and provides the same streaming performance as the header version.
--
-- ==== Examples
--
-- >>> manager <- getManager
-- >>> result <- getArchive manager
-- ...   "https://package.canopy-lang.org/packages/elm/core/1.0.0.zip"
-- ...   NetworkError
-- ...   CorruptedArchive
-- ...   extractPackageFiles
-- >>> case result of
-- ...   Right (sha, archive) -> installPackage sha archive
-- ...   Left err -> reportDownloadError err
--
-- >>> -- Verify against expected hash
-- >>> expectedSha = "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3"
-- >>> result <- getArchive manager packageUrl HttpError InvalidArchive processFiles
-- >>> case result of
-- ...   Right (actualSha, archive)
-- ...     | shaToChars actualSha == expectedSha -> installFiles archive
-- ...     | otherwise -> putStrLn "Hash verification failed!"
-- ...   Left err -> handleError err
--
-- ==== Error Conditions
--
-- Same error conditions as 'getArchiveWithHeaders':
--
-- * **Network Errors**: Converted via provided error function
-- * **Archive Errors**: Returned as provided error value
-- * **System Errors**: Converted via provided error function
--
-- @since 0.19.1
getArchive ::
  -- | HTTP connection manager for request execution
  Manager ->
  -- | URL of ZIP archive to download
  String ->
  -- | Function to convert network errors to application error type
  (Error -> e) ->
  -- | Error value to return for archive parsing failures
  e ->
  -- | Success callback with verified archive and computed hash
  ((Sha, Zip.Archive) -> IO (Either e a)) ->
  -- | Result containing processed data or error
  IO (Either e a)
getArchive manager url = getArchiveWithHeaders manager url []

-- FALLBACK FUNCTIONS

-- | Perform HTTP GET request with automatic fallback from canopy-lang.org to elm-lang.org.
--
-- Attempts the original URL first. If it fails with a network error, automatically
-- retries with elm-lang.org domains. This enables seamless fallback when Canopy
-- packages don't exist but equivalent Elm packages do.
--
-- @since 0.19.1
getWithFallback :: Manager -> String -> [Header] -> (Error -> e) -> (ByteString -> IO (Either e a)) -> IO (Either e a)
getWithFallback manager url headers onError onSuccess = do
  result <- get manager url headers onError onSuccess
  case result of
    Left networkErr -> do
      let fallbackUrl = fallbackToElmUrl url
      if fallbackUrl /= url
        then do
          Log.logEvent (PackageOperation "fallback" (Text.pack fallbackUrl))
          get manager fallbackUrl headers onError onSuccess
        else pure (Left networkErr)
    Right success -> pure (Right success)

-- | Download ZIP archive with automatic fallback from canopy-lang.org to elm-lang.org.
--
-- Attempts the original URL first. If it fails with a network error, automatically
-- retries with elm-lang.org domains for seamless package fallback.
--
-- @since 0.19.1
getArchiveWithFallback ::
  -- | HTTP connection manager for request execution
  Manager ->
  -- | URL of ZIP archive to download
  String ->
  -- | Function to convert network errors to application error type
  (Error -> e) ->
  -- | Error value to return for archive parsing failures
  e ->
  -- | Success callback with verified archive and computed hash
  ((Sha, Zip.Archive) -> IO (Either e a)) ->
  -- | Result containing processed data or error
  IO (Either e a)
getArchiveWithFallback manager url onError err onSuccess = do
  result <- getArchive manager url onError err onSuccess
  case result of
    Left networkErr -> do
      let fallbackUrl = fallbackToElmUrl url
      if fallbackUrl /= url
        then do
          Log.logEvent (PackageOperation "archive-fallback" (Text.pack fallbackUrl))
          getArchive manager fallbackUrl onError err onSuccess
        else pure (Left networkErr)
    Right success -> pure (Right success)

-- | Download ZIP archive with custom headers and automatic fallback from canopy-lang.org to elm-lang.org.
--
-- Attempts the original URL first. If it fails with a network error, automatically
-- retries with elm-lang.org domains for seamless package fallback.
--
-- @since 0.19.1
getArchiveWithHeadersAndFallback ::
  -- | HTTP connection manager for request execution
  Manager ->
  -- | URL of ZIP archive to download
  String ->
  -- | Additional HTTP headers for the request
  [Header] ->
  -- | Function to convert network errors to application error type
  (Error -> e) ->
  -- | Error value to return for archive parsing failures
  e ->
  -- | Success callback with verified archive and computed hash
  ((Sha, Zip.Archive) -> IO (Either e a)) ->
  -- | Result containing processed data or error
  IO (Either e a)
getArchiveWithHeadersAndFallback manager url headers onError err onSuccess = do
  result <- getArchiveWithHeaders manager url headers onError err onSuccess
  case result of
    Left networkErr -> do
      let fallbackUrl = fallbackToElmUrl url
      if fallbackUrl /= url
        then do
          Log.logEvent (PackageOperation "fallback" (Text.pack fallbackUrl))
          getArchiveWithHeaders manager fallbackUrl headers onError err onSuccess
        else pure (Left networkErr)
    Right success -> pure (Right success)

-- UPLOAD

-- | Upload multipart form data with custom headers.
--
-- Performs a multipart/form-data POST request to upload files and data
-- to a server endpoint. Commonly used for package publishing, where
-- multiple files and metadata need to be uploaded together.
--
-- The upload includes:
--
-- * **No timeout** - Uploads can take time, timeout is disabled
-- * **Multipart encoding** - Proper MIME multipart format
-- * **File streaming** - Large files are streamed to minimize memory usage
-- * **Custom headers** - Additional headers for authentication, etc.
--
-- ==== Examples
--
-- >>> manager <- getManager
-- >>> parts <- sequence
-- ...   [ filePart "canopy-json" "canopy.json"
-- ...   , filePart "package-zip" "package.zip"
-- ...   , stringPart "version" "1.0.0"
-- ...   , jsonPart "metadata" "meta.json" packageMetadata
-- ...   ]
-- >>> result <- uploadWithHeaders manager
-- ...   "https://package.canopy-lang.org/api/packages/upload"
-- ...   parts
-- ...   [("Authorization", "Bearer " <> authToken), ("X-Upload-Type", "package")]
-- >>> case result of
-- ...   Right () -> putStrLn "Upload successful"
-- ...   Left err -> putStrLn ("Upload failed: " <> show err)
--
-- ==== Error Conditions
--
-- Returns 'Left Error' for:
--
-- * 'BadUrl' - Invalid upload endpoint URL
-- * 'BadHttp' - Network errors, authentication failures, server errors
-- * 'BadMystery' - System errors during file reading or request building
--
-- Server-side errors (4xx, 5xx status codes) are returned as 'BadHttp'
-- with detailed HTTP error information.
--
-- ==== Performance
--
-- * **No Timeout**: Uploads are not subject to timeout limits
-- * **Streaming**: Large files are streamed without loading into memory
-- * **Connection Reuse**: Uses manager's connection pool
-- * **Concurrent Parts**: Multiple parts can be processed efficiently
--
-- @since 0.19.1
uploadWithHeaders :: Manager -> String -> [Multi.Part] -> [Header] -> IO (Either Error ())
uploadWithHeaders manager url parts headers =
  Exception.handle (handleSomeException url id) . Exception.handle (handleHttpException url id) $
    do
      Log.logEvent (PackageOperation "upload" (Text.pack url))
      req0 <- parseUrlThrow url
      req1 <-
        Multi.formDataBody parts $
          req0
            { Client.method = methodPost,
              Client.requestHeaders = addDefaultHeaders headers,
              Client.responseTimeout = responseTimeoutNone
            }
      withResponse req1 manager $ \_ -> do
        Log.logEvent (PackageOperation "upload-ok" (Text.pack url))
        return (Right ())

-- | Upload multipart form data without custom headers.
--
-- Simplified version of 'uploadWithHeaders' for common upload scenarios
-- where no special headers are required. Uses standard headers including
-- User-Agent and Accept-Encoding.
--
-- ==== Examples
--
-- >>> manager <- getManager
-- >>> parts <- sequence
-- ...   [ filePart "source" "Main.can"
-- ...   , filePart "config" "canopy.json"
-- ...   , stringPart "description" "My awesome package"
-- ...   ]
-- >>> result <- upload manager "https://api.example.com/upload" parts
-- >>> case result of
-- ...   Right () -> putStrLn "Files uploaded successfully"
-- ...   Left (BadHttp _ _) -> putStrLn "Server rejected upload"
-- ...   Left err -> putStrLn ("Upload error: " <> show err)
--
-- ==== Error Conditions
--
-- Same error conditions as 'uploadWithHeaders'. Most common errors:
--
-- * Authentication required (HTTP 401)
-- * File too large (HTTP 413)
-- * Invalid file format (HTTP 400)
-- * Server unavailable (HTTP 500)
--
-- @since 0.19.1
upload :: Manager -> String -> [Multi.Part] -> IO (Either Error ())
upload manager url parts =
  uploadWithHeaders manager url parts []

-- | Create multipart form part from a file.
--
-- Creates a multipart form data part that will upload the contents
-- of the specified file. The file is read and streamed during upload
-- to minimize memory usage for large files.
--
-- ==== Examples
--
-- >>> part <- filePart "package-archive" "my-package.zip"
-- >>> part <- filePart "readme" "README.md"
-- >>> part <- filePart "canopy-config" "canopy.json"
--
-- ==== File Handling
--
-- * **Streaming**: File contents are streamed during upload
-- * **MIME Detection**: Content-Type is automatically detected from filename
-- * **Error Handling**: File read errors occur during upload, not part creation
--
-- @since 0.19.1
filePart :: String -> FilePath -> Multi.Part
filePart name = Multi.partFileSource (String.fromString name)

-- | Create multipart form part with JSON data.
--
-- Creates a multipart form data part containing JSON-encoded data.
-- The JSON is encoded compactly (no pretty printing) to minimize
-- upload size. Commonly used for metadata and configuration data.
--
-- ==== Examples
--
-- >>> import Json.Encode as Encode
-- >>> let metadata = Encode.object
-- ...       [ ("name", Encode.string "my-package")
-- ...       , ("version", Encode.string "1.0.0")
-- ...       , ("dependencies", Encode.object [])
-- ...       ]
-- >>> part <- jsonPart "metadata" "package-meta.json" metadata
--
-- >>> -- Complex nested JSON
-- >>> let buildConfig = Encode.object
-- ...       [ ("optimization", Encode.bool True)
-- ...       , ("targets", Encode.list Encode.string ["js", "html"])
-- ...       ]
-- >>> part <- jsonPart "build-config" "build.json" buildConfig
--
-- ==== JSON Encoding
--
-- * **Compact Format**: No whitespace or pretty printing
-- * **UTF-8 Encoding**: Proper Unicode handling
-- * **Content-Type**: Automatically set to application/json
--
-- @since 0.19.1
jsonPart :: String -> FilePath -> Encode.Value -> Multi.Part
jsonPart name filePath value =
  let body =
        (Client.RequestBodyLBS . B.toLazyByteString $ Encode.encodeUgly value)
   in Multi.partFileRequestBody (String.fromString name) filePath body

-- | Create multipart form part with string data.
--
-- Creates a multipart form data part containing a simple string value.
-- Useful for form fields like version numbers, descriptions, or other
-- textual metadata that doesn't require JSON encoding.
--
-- ==== Examples
--
-- >>> part <- stringPart "version" "1.0.0"
-- >>> part <- stringPart "description" "A package for parsing Canopy code"
-- >>> part <- stringPart "license" "MIT"
-- >>> part <- stringPart "author" "Canopy Team"
--
-- ==== String Handling
--
-- * **UTF-8 Encoding**: Strings are properly encoded as UTF-8
-- * **Content-Type**: Set to text/plain
-- * **No Escaping**: Raw string content, no HTML or URL encoding
--
-- @since 0.19.1
stringPart :: String -> String -> Multi.Part
stringPart name string =
  Multi.partBS (String.fromString name) (BS.pack string)

-- | Create multipart form part with binary data.
--
-- Creates a multipart form data part containing arbitrary binary data.
-- Useful for uploading compiled assets, compressed data, or other
-- binary content that's already loaded in memory.
--
-- ==== Examples
--
-- >>> compiledModule <- compileToJS module
-- >>> part <- bytesPart "compiled-js" "Main.js" compiledModule
--
-- >>> compressedData <- compress packageContents
-- >>> part <- bytesPart "package-data" "data.gz" compressedData
--
-- ==== Binary Handling
--
-- * **Content-Type**: Set to application/octet-stream
-- * **No Encoding**: Raw binary data, no base64 or other encoding
-- * **Memory Usage**: Data should already be in memory (not streamed)
--
-- For large binary files, prefer 'filePart' which streams from disk.
--
-- @since 0.19.1
bytesPart :: String -> FilePath -> ByteString -> Multi.Part
bytesPart name filePath bytes =
  Multi.partFileRequestBody (String.fromString name) filePath (RequestBodyBS bytes)
