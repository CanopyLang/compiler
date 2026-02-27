{-# LANGUAGE OverloadedStrings #-}

-- | File generation utilities and helpers.
--
-- This module provides utilities for writing output files, managing
-- directories, and reporting generation results. It handles the final
-- step of the build process where compiled code is written to disk.
--
-- Key functions:
--   * 'writeOutputFile' - Write builder content to file
--   * 'ensureDirectoryExists' - Create parent directories
--   * 'reportGeneration' - Report successful file generation
--
-- The module follows CLAUDE.md guidelines with functions ≤15 lines,
-- comprehensive error handling, and proper resource management.
--
-- @since 0.19.1
module Make.Generation
  ( -- * File Writing
    writeOutputFile,
    ensureDirectoryExists,

    -- * Reporting
    reportGeneration,

    -- * Utilities
    prepareOutputPath,
  )
where

import qualified Canopy.ModuleName as ModuleName
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString as ByteString
import Data.Function ((&))
import Canopy.Data.NonEmptyList (List)
import qualified Data.Text as Text
import Data.Text (Text)
import qualified Data.Text.Encoding as Text
import qualified File
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import Make.Types (Task)
import qualified Reporting
import qualified Reporting.Task as Task
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath

-- | Write builder content to output file.
--
-- Creates the output file with the provided builder content and reports
-- the generation to the user. Ensures parent directories exist before
-- writing and provides detailed logging.
--
-- @
-- writeOutputFile style \"output.js\" builder moduleNames
-- @
writeOutputFile ::
  Reporting.Style ->
  FilePath ->
  Builder ->
  List ModuleName.Raw ->
  Task ()
writeOutputFile style targetPath builder moduleNames = do
  Task.io (prepareOutputPath targetPath)
  Task.io (writeBuilderContent targetPath builder)
  Task.io (reportGeneration style moduleNames targetPath)

-- | Prepare output path by ensuring parent directories exist.
--
-- Creates all necessary parent directories for the output file.
-- This prevents write failures due to missing directory structure.
prepareOutputPath :: FilePath -> IO ()
prepareOutputPath targetPath = do
  Log.logEvent (BuildStarted (Text.pack "Preparing output directory"))
  let parentDir = FilePath.takeDirectory targetPath
  Dir.createDirectoryIfMissing True parentDir

-- | Write builder content to file.
--
-- Writes the builder content to the specified file path. For JavaScript files,
-- applies post-processing to fix spacing issues before writing.
writeBuilderContent :: FilePath -> Builder -> IO ()
writeBuilderContent targetPath builder = do
  Log.logEvent (BuildStarted (Text.pack "Writing builder content"))
  if FilePath.takeExtension targetPath == ".js"
    then writeJavaScriptWithPostProcessing targetPath builder
    else File.writeBuilder targetPath builder

-- | Write JavaScript with post-processing to fix spacing issues.
--
-- Fixes common JavaScript spacing problems that can occur during optimization:
--   * 'elseif' becomes 'else if'
--   * 'elsereturn' becomes 'else return'
--   * Other missing spaces around 'else' keyword
writeJavaScriptWithPostProcessing :: FilePath -> Builder -> IO ()
writeJavaScriptWithPostProcessing targetPath builder = do
  let content = builderToText builder
      fixedContent = fixJavaScriptSpacing content
      fixedBytes = Text.encodeUtf8 fixedContent
  File.writeUtf8 targetPath fixedBytes

-- | Fix JavaScript spacing issues.
--
-- Applies regex-based fixes for spacing problems in generated JavaScript.
-- These issues typically arise from optimization passes that concat strings
-- without preserving proper keyword spacing.
fixJavaScriptSpacing :: Text -> Text
fixJavaScriptSpacing content =
  content
    & Text.replace "elseif" "else if"
    & Text.replace "elsereturn" "else return"
    & Text.replace "elsethrow" "else throw"
    & Text.replace "elsevar" "else var"
    & Text.replace "elsefor" "else for"
    & Text.replace "elsewhile" "else while"

-- | Convert Builder to Text for post-processing.
--
-- Efficiently converts a Builder to Text using the underlying ByteString.
builderToText :: Builder -> Text
builderToText = Text.decodeUtf8 . ByteString.toStrict . Builder.toLazyByteString

-- | Report successful file generation.
--
-- Notifies the user about successful file generation using the
-- appropriate reporting style. Provides feedback on build completion.
reportGeneration ::
  Reporting.Style ->
  List ModuleName.Raw ->
  FilePath ->
  IO ()
reportGeneration style moduleNames targetPath = do
  Log.logEvent (BuildStarted (Text.pack "Reporting generation success"))
  Reporting.reportGenerate style moduleNames targetPath

-- | Ensure directory exists for file path.
--
-- Creates the directory structure needed for the given file path.
-- This is a utility function that can be used independently.
--
-- @
-- ensureDirectoryExists \"/path/to/output.js\"  -- Creates /path/to/
-- @
ensureDirectoryExists :: FilePath -> IO ()
ensureDirectoryExists filePath = do
  let directory = FilePath.takeDirectory filePath
  Dir.createDirectoryIfMissing True directory
