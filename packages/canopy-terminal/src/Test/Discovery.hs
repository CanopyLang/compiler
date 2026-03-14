-- | Test file discovery for the @canopy test@ command.
--
-- Recursively scans @tests\/@ and @test\/@ directories (or explicit paths)
-- for @.can@ files that should be compiled as test modules.
--
-- @since 0.19.1
module Test.Discovery
  ( discoverTestFiles,
  )
where

import qualified Control.Monad as Monad
import qualified Data.List as List
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified System.FilePath as FilePath

-- | Discover test files from paths or the default @tests\/@ directory.
--
-- When no paths are given, scans both @tests\/@ and @test\/@ for @.can@ files.
-- When explicit paths are given, files are returned as-is and directories
-- are recursively scanned.
discoverTestFiles :: [FilePath] -> IO [FilePath]
discoverTestFiles [] = do
  testsDir <- findCanopyFilesIn "tests"
  testDir <- findCanopyFilesIn "test"
  pure (testsDir ++ testDir)
discoverTestFiles paths = do
  expanded <- mapM expandPath paths
  pure (concat expanded)

-- | Expand a path: files are returned as-is, directories are scanned.
expandPath :: FilePath -> IO [FilePath]
expandPath path = do
  isDir <- Dir.doesDirectoryExist path
  isFile <- Dir.doesFileExist path
  if isDir
    then findCanopyFilesIn path
    else if isFile then pure [path] else pure []

-- | Recursively find all @.can@ files under a directory.
--
-- Skips hidden directories (those starting with @.@).
findCanopyFilesIn :: FilePath -> IO [FilePath]
findCanopyFilesIn dir = do
  exists <- Dir.doesDirectoryExist dir
  if not exists
    then pure []
    else do
      entries <- Dir.listDirectory dir
      let paths = map (dir </>) entries
      files <- Monad.filterM Dir.doesFileExist paths
      let canFiles = filter ((".can" ==) . FilePath.takeExtension) files
      dirs <- Monad.filterM Dir.doesDirectoryExist paths
      let visibleDirs = filter (not . ("." `List.isPrefixOf`) . FilePath.takeFileName) dirs
      nested <- mapM findCanopyFilesIn visibleDirs
      pure (canFiles ++ concat nested)
