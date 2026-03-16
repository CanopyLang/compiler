{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Elm-to-Canopy package conversion orchestrator.
--
-- Converts a pure Elm package into Canopy format by:
--
-- 1. Copying the source tree to an output directory (or working in-place)
-- 2. Renaming all @.elm@ files to @.can@
-- 3. Converting @elm.json@ to @canopy.json@ with dependency remapping
-- 4. Detecting unsupported features (ports, kernel JS) that block conversion
--
-- Community Elm packages are syntactically identical to Canopy — only
-- metadata and file extensions differ. This module coordinates the
-- mechanical transformation.
--
-- == Usage
--
-- @
-- let opts = ConvertOptions "path/to/elm-pkg" (Just "/tmp/output") False
-- result <- convertPackage opts
-- print (result ^. convertFilesRenamed)
-- @
--
-- @since 0.19.2
module Convert
  ( -- * Entry Point
    convertPackage,

    -- * Re-exports
    module Convert.Types,
  )
where

import Control.Exception (IOException)
import qualified Control.Exception as Exception
import Control.Lens ((^.))
import qualified Convert.ProjectFile as ProjectFile
import qualified Convert.Source as Source
import Convert.Types
import Data.Maybe (fromMaybe)
import qualified Data.Text as Text
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified System.FilePath as FP

-- | Convert an Elm package to Canopy format.
--
-- Validates the source directory, checks for unsupported features,
-- then performs file renaming and project file conversion.
-- IO exceptions are caught and returned as 'FileError' values.
--
-- @since 0.19.2
convertPackage :: ConvertOptions -> IO ConvertResult
convertPackage opts = do
  let srcDir = opts ^. convertSourceDir
  validated <- validateSourceDir srcDir
  either (pure . errorResult) (const (tryConvert (runConversion opts))) validated

-- | Validate that the source directory exists and contains an @elm.json@.
validateSourceDir :: FilePath -> IO (Either ConvertError ())
validateSourceDir srcDir = do
  dirExists <- Dir.doesDirectoryExist srcDir
  if not dirExists
    then pure (Left (SourceDirNotFound srcDir))
    else checkElmJson srcDir

-- | Check that @elm.json@ exists in the source directory.
checkElmJson :: FilePath -> IO (Either ConvertError ())
checkElmJson srcDir = do
  let elmJson = srcDir </> "elm.json"
  jsonExists <- Dir.doesFileExist elmJson
  pure (if jsonExists then Right () else Left (NoElmJson srcDir))

-- | Run the full conversion pipeline after validation.
runConversion :: ConvertOptions -> IO ConvertResult
runConversion opts = do
  let srcDir = opts ^. convertSourceDir
  unsupported <- ProjectFile.hasPortsOrKernel srcDir
  maybe (performConversion opts) (pure . unsupportedResult srcDir) unsupported

-- | Perform the actual file conversion.
performConversion :: ConvertOptions -> IO ConvertResult
performConversion opts
  | opts ^. convertDryRun = dryRunConversion opts
  | otherwise = liveConversion opts

-- | Execute a dry-run conversion that reports what would change.
--
-- Also checks for unsupported features and includes warnings.
dryRunConversion :: ConvertOptions -> IO ConvertResult
dryRunConversion opts = do
  let srcDir = opts ^. convertSourceDir
  elmFiles <- Source.discoverElmFiles (srcDir </> "src")
  unsupported <- ProjectFile.hasPortsOrKernel srcDir
  let errors = maybe [] (\msg -> [UnsupportedFeature srcDir msg]) unsupported
  pure (ConvertResult (length elmFiles) True errors)

-- | Execute a live conversion that writes files.
liveConversion :: ConvertOptions -> IO ConvertResult
liveConversion opts = do
  let srcDir = opts ^. convertSourceDir
      outDir = fromMaybe srcDir (opts ^. convertOutputDir)
  copySourceIfNeeded srcDir outDir
  renamed <- renameFiles srcDir outDir
  projResult <- ProjectFile.convertElmJsonToFile srcDir outDir
  let projConverted = maybe False (const True) projResult
      projErrors = maybe [NoElmJson srcDir] (const []) projResult
  pure (ConvertResult renamed projConverted projErrors)

-- | Wrap a conversion action to catch IO exceptions as 'FileError'.
tryConvert :: IO ConvertResult -> IO ConvertResult
tryConvert action =
  either handleIOError id <$> Exception.try action
  where
    handleIOError :: IOException -> ConvertResult
    handleIOError e = errorResult (FileError "" (Text.pack (show e)))

-- | Copy the source tree to the output directory if different from source.
copySourceIfNeeded :: FilePath -> FilePath -> IO ()
copySourceIfNeeded srcDir outDir
  | srcDir == outDir = pure ()
  | otherwise = do
      Dir.createDirectoryIfMissing True outDir
      copyDirectoryRecursive srcDir outDir

-- | Rename all @.elm@ files to @.can@ in the appropriate directory.
renameFiles :: FilePath -> FilePath -> IO Int
renameFiles srcDir outDir
  | srcDir == outDir = renameInPlace srcDir
  | otherwise = copyAndRename srcDir outDir

-- | Rename @.elm@ files in-place within the source directory.
renameInPlace :: FilePath -> IO Int
renameInPlace srcDir = do
  elmFiles <- Source.discoverElmFiles (srcDir </> "src")
  mapM_ Source.renameElmToCan elmFiles
  pure (length elmFiles)

-- | Copy and rename @.elm@ files to the output directory as @.can@.
copyAndRename :: FilePath -> FilePath -> IO Int
copyAndRename srcDir outDir = do
  let srcSrcDir = srcDir </> "src"
      outSrcDir = outDir </> "src"
  elmFiles <- Source.discoverElmFiles srcSrcDir
  mapM_ (Source.copyAndRenameElmToCan srcSrcDir outSrcDir) elmFiles
  pure (length elmFiles)

-- | Recursively copy a directory, preserving structure.
copyDirectoryRecursive :: FilePath -> FilePath -> IO ()
copyDirectoryRecursive src dst = do
  Dir.createDirectoryIfMissing True dst
  entries <- Dir.listDirectory src
  mapM_ (copyEntry src dst) entries

-- | Copy a single directory entry, recursing into subdirectories.
-- Skips @.elm@ files and @elm.json@ since they are handled separately.
copyEntry :: FilePath -> FilePath -> FilePath -> IO ()
copyEntry srcParent dstParent entry
  | shouldSkip entry = pure ()
  | otherwise = do
      let srcPath = srcParent </> entry
          dstPath = dstParent </> entry
      isDir <- Dir.doesDirectoryExist srcPath
      if isDir
        then copyDirectoryRecursive srcPath dstPath
        else Dir.copyFile srcPath dstPath

-- | Check if a file should be skipped during copy (handled by conversion).
shouldSkip :: FilePath -> Bool
shouldSkip entry =
  FP.takeExtension entry == ".elm" || entry == "elm.json" || entry == "elm-stuff"

-- | Create a result for a single error.
errorResult :: ConvertError -> ConvertResult
errorResult err = ConvertResult 0 False [err]

-- | Create a result for an unsupported feature detection.
unsupportedResult :: FilePath -> Text.Text -> ConvertResult
unsupportedResult path msg =
  ConvertResult 0 False [UnsupportedFeature path msg]
