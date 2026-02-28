{-# LANGUAGE OverloadedStrings #-}

-- | Http.Error - HTTP error types and exception handlers
--
-- This module defines the 'Error' type used throughout the HTTP subsystem
-- and the low-level exception-to-error conversion helpers.  It is kept
-- separate so that "Http.Archive" and "Http.Upload" can import it without
-- creating circular dependencies with the parent "Http" module.
--
-- Callers should import "Http" and use 'Http.Error' rather than this
-- module directly.
module Http.Error
  ( Error (..),
    handleHttpException,
    handleIOException,
  )
where

import Control.Exception (IOException)
import qualified Data.Text as Text
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import Network.HTTP.Client
  ( HttpException (HttpExceptionRequest, InvalidUrlException),
    HttpExceptionContent,
  )

-- | Comprehensive HTTP error types with contextual information.
--
-- Represents all possible HTTP operation failures with sufficient context
-- for debugging and error reporting.  Each constructor includes the original
-- URL and specific error details.
--
-- @since 0.19.1
data Error
  = -- | Invalid or malformed URL error.
    BadUrl String String
  | -- | HTTP protocol or network error.
    BadHttp String HttpExceptionContent
  | -- | IO-level error (file access, DNS, network).
    BadIO String IOException
  deriving (Show)

-- | Convert an 'HttpException' into a typed 'Error' wrapped by @onError@.
handleHttpException :: String -> (Error -> e) -> HttpException -> IO (Either e a)
handleHttpException url onError httpException = do
  Log.logEvent (PackageOperation "http-error" (Text.pack url <> " " <> Text.pack (show httpException)))
  case httpException of
    InvalidUrlException _ reason ->
      return (Left (onError (BadUrl url reason)))
    HttpExceptionRequest _ content ->
      return (Left (onError (BadHttp url content)))

-- | Convert an 'IOException' into a typed 'Error' wrapped by @onError@.
--
-- Replaces the old @handleSomeException@ to catch only IO-level failures
-- (file not found for file:// URLs, DNS resolution, network errors)
-- while allowing programming errors to propagate.
handleIOException :: String -> (Error -> e) -> IOException -> IO (Either e a)
handleIOException url onError ioException = do
  Log.logEvent (PackageOperation "io-error" (Text.pack url <> " " <> Text.pack (show ioException)))
  return (Left (onError (BadIO url ioException)))
