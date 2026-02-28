{-# LANGUAGE OverloadedStrings #-}

-- | Http.Upload - Multipart form-data upload helpers
--
-- This module provides the multipart upload operations and part-building
-- helpers extracted from "Http" to keep that module within the 1000-line
-- limit.
--
-- Callers should import "Http" rather than this module directly.
module Http.Upload
  ( -- * Upload operations
    uploadWithHeaders,
    upload,

    -- * Part builders
    filePart,
    jsonPart,
    stringPart,
    bytesPart,
  )
where

import qualified Canopy.Version as Version
import qualified Control.Exception as Exception
import Data.ByteString (ByteString)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Char8 as BS
import qualified Data.String as String
import qualified Json.Encode as Encode
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import qualified Data.Text as Text
import Network.HTTP.Client
  ( Manager,
    RequestBody (RequestBodyBS),
    responseTimeoutNone,
    withResponse,
    parseUrlThrow,
  )
import qualified Network.HTTP.Client as Client
import qualified Network.HTTP.Client.MultipartFormData as Multi
import Network.HTTP.Types.Header (Header, hAcceptEncoding, hUserAgent)
import Network.HTTP.Types.Method (methodPost)
import Http.Error (Error, handleHttpException, handleIOException)

-- | Create a TLS-aware user-agent header value.
--
-- This is a local copy to avoid circular imports.
{-# NOINLINE uploadUserAgent #-}
uploadUserAgent :: ByteString
uploadUserAgent =
  BS.pack ("canopy/" <> Version.toChars Version.compiler)

addUploadDefaultHeaders :: [Header] -> [Header]
addUploadDefaultHeaders headers =
  (hUserAgent, uploadUserAgent) : (hAcceptEncoding, "gzip") : headers

-- | Upload multipart form data with custom headers.
--
-- Performs a multipart/form-data POST request to upload files and data
-- to a server endpoint. Commonly used for package publishing, where
-- multiple files and metadata need to be uploaded together.
--
-- The upload is not subject to any response timeout so that large payloads
-- can complete without being cut short.
--
-- @since 0.19.1
uploadWithHeaders :: Manager -> String -> [Multi.Part] -> [Header] -> IO (Either Error ())
uploadWithHeaders manager url parts headers =
  Exception.handle (handleIOException url id) . Exception.handle (handleHttpException url id) $ do
    Log.logEvent (PackageOperation "upload" (Text.pack url))
    req0 <- parseUrlThrow url
    req1 <-
      Multi.formDataBody parts $
        req0
          { Client.method = methodPost,
            Client.requestHeaders = addUploadDefaultHeaders headers,
            Client.responseTimeout = responseTimeoutNone
          }
    withResponse req1 manager $ \_ -> do
      Log.logEvent (PackageOperation "upload-ok" (Text.pack url))
      return (Right ())

-- | Upload multipart form data without custom headers.
--
-- Simplified version of 'uploadWithHeaders' for common upload scenarios
-- where no special headers are required.
--
-- @since 0.19.1
upload :: Manager -> String -> [Multi.Part] -> IO (Either Error ())
upload manager url parts =
  uploadWithHeaders manager url parts []

-- | Create a multipart form part from a file on disk.
--
-- The file is streamed during upload, keeping memory usage low even for
-- large files.
--
-- @since 0.19.1
filePart :: String -> FilePath -> Multi.Part
filePart name = Multi.partFileSource (String.fromString name)

-- | Create a multipart form part containing JSON-encoded data.
--
-- The JSON is encoded compactly (no pretty printing) to minimise upload size.
--
-- @since 0.19.1
jsonPart :: String -> FilePath -> Encode.Value -> Multi.Part
jsonPart name filePath value =
  let body = Client.RequestBodyLBS . BB.toLazyByteString $ Encode.encodeUgly value
   in Multi.partFileRequestBody (String.fromString name) filePath body

-- | Create a multipart form part with a plain-string value.
--
-- Useful for short textual fields like version numbers and descriptions.
--
-- @since 0.19.1
stringPart :: String -> String -> Multi.Part
stringPart name string =
  Multi.partBS (String.fromString name) (BS.pack string)

-- | Create a multipart form part with arbitrary binary data already in memory.
--
-- For large binary files prefer 'filePart', which streams directly from disk.
--
-- @since 0.19.1
bytesPart :: String -> FilePath -> ByteString -> Multi.Part
bytesPart name filePath bytes =
  Multi.partFileRequestBody (String.fromString name) filePath (RequestBodyBS bytes)
