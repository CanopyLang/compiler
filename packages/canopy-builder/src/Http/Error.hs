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
    handleSomeException,
  )
where

import Control.Exception (SomeException)
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
  | -- | Unexpected system-level error.
    BadMystery String SomeException
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

-- | Convert a 'SomeException' into a typed 'Error' wrapped by @onError@.
handleSomeException :: String -> (Error -> e) -> SomeException -> IO (Either e a)
handleSomeException url onError exception = do
  Log.logEvent (PackageOperation "exception" (Text.pack url <> " " <> Text.pack (show exception)))
  return (Left (onError (BadMystery url exception)))
