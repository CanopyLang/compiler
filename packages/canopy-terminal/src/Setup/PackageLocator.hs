{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Package artifact location and cache copying for setup.
--
-- Locates standard library package artifacts in the Canopy and Elm
-- caches, copying from Elm to Canopy when necessary.
--
-- @since 0.19.1
module Setup.PackageLocator
  ( -- * Package Location
    locatePackage,

    -- * File Copying
    copyDirectoryRecursive,
    safeCopyFile,
  )
where

import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Exception (IOException)
import qualified Control.Exception as Exception
import Reporting.Doc.ColorQQ (c)
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified Terminal.Print as Print
import qualified Text.PrettyPrint.ANSI.Leijen as PP

-- | Locate a package's artifacts, copying from Elm cache if necessary.
--
-- Returns True if artifacts are available after this call.
locatePackage :: FilePath -> Bool -> (Pkg.Name, Version.Version) -> IO Bool
locatePackage _cache verbose (pkg, version) = do
  homeDir <- Dir.getHomeDirectory
  let (author, project) = pkgStrings pkg
      versionStr = Version.toChars version
      canopyDir = homeDir </> ".canopy" </> "packages" </> author </> project </> versionStr
      canopyArtifacts = canopyDir </> "artifacts.dat"
      elmDir = homeDir </> ".elm" </> "0.19.1" </> "packages" </> author </> project </> versionStr
      elmArtifacts = elmDir </> "artifacts.dat"
      label = author <> "/" <> project <> " " <> versionStr
  canopyExists <- Dir.doesFileExist canopyArtifacts
  if canopyExists
    then do
      Print.println [c|  #{label}: {green|ready}|]
      pure True
    else do
      elmExists <- Dir.doesFileExist elmArtifacts
      if elmExists
        then copyFromElmCache verbose label canopyDir canopyArtifacts elmDir
        else do
          Print.println [c|  #{label}: {red|not found}|]
          verboseLog verbose [c|    Checked: {cyan|#{canopyArtifacts}}|]
          verboseLog verbose [c|    Checked: {cyan|#{elmArtifacts}}|]
          pure False

-- | Copy package artifacts from the Elm cache to the Canopy cache.
copyFromElmCache :: Bool -> String -> FilePath -> FilePath -> FilePath -> IO Bool
copyFromElmCache verbose label canopyDir canopyArtifacts elmDir = do
  verboseLog verbose [c|    Copying from Elm cache: {cyan|#{elmDir}}|]
  Dir.createDirectoryIfMissing True canopyDir
  let elmArtifacts = elmDir </> "artifacts.dat"
  copyResult <- safeCopyFile elmArtifacts canopyArtifacts
  case copyResult of
    Right () -> do
      copyPackageSource verbose elmDir canopyDir
      Print.println [c|  #{label}: {yellow|copied from Elm cache}|]
      pure True
    Left err -> do
      Print.println [c|  #{label}: {red|copy failed (#{err})}|]
      pure False

-- | Copy package source files (src/, elm.json) from one directory to another.
copyPackageSource :: Bool -> FilePath -> FilePath -> IO ()
copyPackageSource verbose srcDir destDir = do
  copyIfExists verbose (srcDir </> "elm.json") (destDir </> "elm.json")
  let srcSrcDir = srcDir </> "src"
  srcExists <- Dir.doesDirectoryExist srcSrcDir
  if srcExists
    then do
      verboseLog verbose [c|    Copying source: {cyan|#{srcSrcDir}}|]
      copyDirectoryRecursive srcSrcDir (destDir </> "src")
    else pure ()

-- | Copy a file only if the source exists.
copyIfExists :: Bool -> FilePath -> FilePath -> IO ()
copyIfExists verbose src dest = do
  exists <- Dir.doesFileExist src
  if exists
    then do
      verboseLog verbose [c|    Copying: {cyan|#{src}}|]
      _ <- safeCopyFile src dest
      pure ()
    else pure ()

-- | Copy a file with error handling.
safeCopyFile :: FilePath -> FilePath -> IO (Either String ())
safeCopyFile src dest = do
  result <- tryIO (Dir.copyFile src dest)
  pure (either (Left . show) Right result)

-- | Copy a directory recursively.
copyDirectoryRecursive :: FilePath -> FilePath -> IO ()
copyDirectoryRecursive src dest = do
  Dir.createDirectoryIfMissing True dest
  contents <- Dir.listDirectory src
  mapM_ (copyEntry src dest) contents

-- | Copy a single directory entry (file or subdirectory).
copyEntry :: FilePath -> FilePath -> FilePath -> IO ()
copyEntry srcBase destBase name = do
  let srcPath = srcBase </> name
      destPath = destBase </> name
  isDir <- Dir.doesDirectoryExist srcPath
  if isDir
    then copyDirectoryRecursive srcPath destPath
    else do
      _ <- safeCopyFile srcPath destPath
      pure ()

-- UTILITIES

-- | Extract author and project strings from a package name.
pkgStrings :: Pkg.Name -> (String, String)
pkgStrings (Pkg.Name author project) =
  (Utf8.toChars author, Utf8.toChars project)

-- | Print a 'PP.Doc' message when verbose mode is enabled.
verboseLog :: Bool -> PP.Doc -> IO ()
verboseLog verbose doc =
  if verbose
    then Print.println doc
    else pure ()

-- | Try an IO action, catching IOExceptions.
tryIO :: IO a -> IO (Either IOException a)
tryIO = Exception.try
