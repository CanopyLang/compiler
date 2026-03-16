{-# LANGUAGE OverloadedStrings #-}

-- | Source file discovery and renaming for Elm-to-Canopy conversion.
--
-- Handles the mechanical task of finding all @.elm@ files in a package
-- source tree and renaming them to @.can@. No content transformation
-- is needed since Canopy syntax is identical to Elm syntax for community
-- packages (which don't use ports or kernel code).
--
-- @since 0.19.2
module Convert.Source
  ( -- * Discovery
    discoverElmFiles,

    -- * Renaming
    renameElmToCan,
    copyAndRenameElmToCan,
  )
where

import qualified Data.List as List
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified System.FilePath as FP

-- | Recursively discover all @.elm@ files under the given directory.
--
-- Returns absolute paths sorted alphabetically. Skips hidden directories
-- (those starting with @.@) and @elm-stuff@.
--
-- @since 0.19.2
discoverElmFiles :: FilePath -> IO [FilePath]
discoverElmFiles root = do
  exists <- Dir.doesDirectoryExist root
  if exists
    then List.sort <$> walkDirectory root
    else pure []

-- | Walk a directory tree collecting @.elm@ file paths.
walkDirectory :: FilePath -> IO [FilePath]
walkDirectory dir = do
  entries <- Dir.listDirectory dir
  results <- mapM (processEntry dir) entries
  pure (concat results)

-- | Process a single directory entry, recursing into non-hidden subdirectories.
processEntry :: FilePath -> FilePath -> IO [FilePath]
processEntry parent entry
  | isHiddenOrElmStuff entry = pure []
  | otherwise = do
      let full = parent </> entry
      isDir <- Dir.doesDirectoryExist full
      if isDir
        then walkDirectory full
        else pure (elmFileAction full)

-- | Return the path in a singleton list if it ends in @.elm@, otherwise empty.
elmFileAction :: FilePath -> [FilePath]
elmFileAction path
  | FP.takeExtension path == ".elm" = [path]
  | otherwise = []

-- | Check if a directory entry should be skipped during traversal.
isHiddenOrElmStuff :: FilePath -> Bool
isHiddenOrElmStuff name =
  List.isPrefixOf "." name || name == "elm-stuff"

-- | Rename a @.elm@ file to @.can@ in place.
--
-- The original @.elm@ file is removed after the @.can@ file is written.
--
-- @since 0.19.2
renameElmToCan :: FilePath -> IO FilePath
renameElmToCan path = do
  Dir.renameFile path newPath
  pure newPath
  where
    newPath = FP.replaceExtension path ".can"

-- | Copy a @.elm@ file to a new location with @.can@ extension.
--
-- Used when converting to an output directory rather than in-place.
-- The source file is left unchanged.
--
-- @since 0.19.2
copyAndRenameElmToCan :: FilePath -> FilePath -> FilePath -> IO FilePath
copyAndRenameElmToCan sourceRoot outputRoot elmPath = do
  Dir.createDirectoryIfMissing True (FP.takeDirectory destPath)
  Dir.copyFile elmPath destPath
  pure destPath
  where
    relative = FP.makeRelative sourceRoot elmPath
    destPath = outputRoot </> FP.replaceExtension relative ".can"
