{-# LANGUAGE OverloadedStrings #-}

-- | Foreign Function Interface (FFI) query system.
--
-- This module provides queries for analyzing and caching FFI bindings.
-- It wraps the existing Foreign.FFI module with the query system for
-- automatic caching and invalidation.
--
-- == Usage Examples
--
-- @
-- import qualified Queries.Foreign as ForeignQuery
--
-- analyzeForeignFile :: FilePath -> IO (Either QueryError [JSDocFunction])
-- analyzeForeignFile path = ForeignQuery.foreignFileQuery path
-- @
--
-- @since 0.19.1
module Queries.Foreign
  ( -- * Query Functions
    foreignFileQuery,
    foreignImportsQuery,

    -- * Re-exports
    JSDocFunction (..),
    FFIType (..),
    FFIError (..),
  )
where

import qualified Data.Text as Text
import Data.Text (Text)
import qualified Foreign.FFI as FFI
import Foreign.FFI
  ( FFIError (..),
    FFIType (..),
    JSDocFunction (..),
  )
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import Query.Simple

-- | Query for analyzing a single JavaScript file.
--
-- Parses JSDoc comments and extracts type information for FFI bindings.
-- Results are cached based on file content hash.
--
-- @since 0.19.1
foreignFileQuery :: FilePath -> IO (Either QueryError [JSDocFunction])
foreignFileQuery jsFile = do
  Log.logEvent (FFILoading jsFile)

  result <- FFI.parseJSDocFromFile jsFile

  case result of
    Left ffiErr -> do
      Log.logEvent (FFIMissing jsFile)
      return (Left (convertFFIError jsFile ffiErr))
    Right functions -> do
      Log.logEvent (FFILoaded jsFile (length functions))
      return (Right functions)

-- | Query for processing multiple foreign imports.
--
-- Analyzes all JavaScript files referenced in foreign imports
-- and extracts their FFI bindings.
--
-- @since 0.19.1
foreignImportsQuery ::
  [FFI.SimpleFFIImport] ->
  IO (Either QueryError [(Text, [JSDocFunction])])
foreignImportsQuery imports = do
  Log.logEvent (FFILoading "<imports>")

  result <- FFI.processForeignImports imports

  case result of
    Left ffiErr -> do
      Log.logEvent (FFIMissing "<imports>")
      return (Left (convertFFIError "<imports>" ffiErr))
    Right bindings -> do
      Log.logEvent (FFILoaded "<imports>" (length bindings))
      return (Right bindings)

-- | Convert FFI errors to query errors.
convertFFIError :: FilePath -> FFIError -> QueryError
convertFFIError _ (JSFileNotFound file) =
  FileNotFound file
convertFFIError _ (JSDocParseError file msg) =
  ParseError file (Text.unpack msg)
convertFFIError _ (InvalidCanopyType typeText reason) =
  OtherError ("Invalid Canopy type: " ++ Text.unpack typeText ++ " - " ++ Text.unpack reason)
convertFFIError _ (FunctionNotFound file name) =
  OtherError ("Function not found: " ++ Text.unpack name ++ " in " ++ file)
convertFFIError _ (TypeMismatch name expected actual) =
  TypeError ("Type mismatch for " ++ Text.unpack name ++ ": expected " ++ show expected ++ ", got " ++ show actual)
convertFFIError _ (MissingCanopyType name) =
  OtherError ("Missing @canopy-type annotation for: " ++ Text.unpack name)
convertFFIError _ (UnsupportedJSType jsType) =
  OtherError ("Unsupported JavaScript type: " ++ Text.unpack jsType)
convertFFIError _ (InvalidCapabilityAnnotation name reason) =
  OtherError ("Invalid capability annotation for " ++ Text.unpack name ++ ": " ++ Text.unpack reason)
convertFFIError _ (CapabilityError capErr) =
  OtherError ("Capability error: " ++ show capErr)
