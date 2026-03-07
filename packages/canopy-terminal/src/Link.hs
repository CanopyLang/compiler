{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Local package development via symlinks.
--
-- The @canopy link@ command registers a local package directory in the
-- global cache (@~\/.canopy\/packages\/@) via a symbolic link, enabling
-- instant iteration during development without copying files.
--
-- @canopy unlink@ removes the symlink for the current (or specified) package.
--
-- @since 0.19.2
module Link
  ( -- * Entry Points
    runLink,
    runUnlink,

    -- * Types
    LinkFlags (..),
    UnlinkFlags (..),
  )
where

import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Exception (IOException)
import qualified Control.Exception as Exception
import Reporting.Doc.ColorQQ (c)
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified Terminal.Print as Print

-- | Flags for the @canopy link@ command.
data LinkFlags = LinkFlags

-- | Flags for the @canopy unlink@ command.
data UnlinkFlags = UnlinkFlags

-- | Run @canopy link@.
--
-- Reads @canopy.json@ from the target directory, extracts the package
-- name and version, then creates a symlink from the global cache to
-- the target directory.  If a real directory already exists at the
-- symlink target, it is removed first (after deleting any stale
-- @artifacts.dat@).
runLink :: Maybe FilePath -> LinkFlags -> IO ()
runLink maybePath LinkFlags = do
  targetDir <- resolveTarget maybePath
  eitherOutline <- Outline.read targetDir
  case eitherOutline of
    Left err -> do
      Print.println [c|{red|Error:} Could not read canopy.json: #{err}|]
    Right outline ->
      case outline of
        Outline.Pkg pkgOutline ->
          linkPackage targetDir pkgOutline
        Outline.App _ ->
          Print.println [c|{red|Error:} Cannot link an application. Only packages can be linked.|]
        Outline.Workspace _ ->
          Print.println [c|{red|Error:} Cannot link a workspace. Only packages can be linked.|]

-- | Run @canopy unlink@.
--
-- Reads @canopy.json@ from the current (or specified) directory and
-- removes the corresponding symlink from the global cache.
runUnlink :: Maybe FilePath -> UnlinkFlags -> IO ()
runUnlink maybePath UnlinkFlags = do
  targetDir <- resolveTarget maybePath
  eitherOutline <- Outline.read targetDir
  case eitherOutline of
    Left err ->
      Print.println [c|{red|Error:} Could not read canopy.json: #{err}|]
    Right outline ->
      case outline of
        Outline.Pkg pkgOutline ->
          unlinkPackage pkgOutline
        Outline.App _ ->
          Print.println [c|{red|Error:} Cannot unlink an application.|]
        Outline.Workspace _ ->
          Print.println [c|{red|Error:} Cannot unlink a workspace.|]

-- | Resolve the target directory from an optional path argument.
resolveTarget :: Maybe FilePath -> IO FilePath
resolveTarget maybePath =
  maybe Dir.getCurrentDirectory Dir.makeAbsolute maybePath

-- | Create a symlink for a package in the global cache.
linkPackage :: FilePath -> Outline.PkgOutline -> IO ()
linkPackage targetDir pkgOutline = do
  absTarget <- Dir.makeAbsolute targetDir
  let (author, project) = pkgStrings (Outline._pkgName pkgOutline)
      versionStr = Version.toChars (Outline._pkgVersion pkgOutline)
      label = author <> "/" <> project <> " " <> versionStr
  homeDir <- Dir.getHomeDirectory
  let linkDir = homeDir </> ".canopy" </> "packages" </> author </> project </> versionStr
  Dir.createDirectoryIfMissing True (homeDir </> ".canopy" </> "packages" </> author </> project)
  existingIsLink <- isSymlink linkDir
  existingIsDir <- Dir.doesDirectoryExist linkDir
  handleExisting existingIsLink existingIsDir linkDir
  Dir.createDirectoryLink absTarget linkDir
  removeStaleArtifacts linkDir
  Print.println [c|{green|Linked} #{label} -> #{absTarget}|]

-- | Check if a path is a symbolic link, returning False if it doesn't exist.
isSymlink :: FilePath -> IO Bool
isSymlink path =
  either (\(_ :: IOException) -> False) id
    <$> Exception.try (Dir.pathIsSymbolicLink path)

-- | Handle an existing entry at the link path.
handleExisting :: Bool -> Bool -> FilePath -> IO ()
handleExisting isLink isDir linkDir
  | isLink = Dir.removeDirectoryLink linkDir
  | isDir = Dir.removeDirectoryRecursive linkDir
  | otherwise = pure ()

-- | Remove stale artifacts so @canopy setup@ recompiles.
removeStaleArtifacts :: FilePath -> IO ()
removeStaleArtifacts linkDir = do
  let artifactsPath = linkDir </> "artifacts.dat"
  exists <- Dir.doesFileExist artifactsPath
  if exists
    then Dir.removeFile artifactsPath
    else pure ()

-- | Remove the symlink for a package from the global cache.
unlinkPackage :: Outline.PkgOutline -> IO ()
unlinkPackage pkgOutline = do
  let (author, project) = pkgStrings (Outline._pkgName pkgOutline)
      versionStr = Version.toChars (Outline._pkgVersion pkgOutline)
      label = author <> "/" <> project <> " " <> versionStr
  homeDir <- Dir.getHomeDirectory
  let linkDir = homeDir </> ".canopy" </> "packages" </> author </> project </> versionStr
  isLink <- isSymlink linkDir
  if isLink
    then do
      Dir.removeDirectoryLink linkDir
      Print.println [c|{green|Unlinked} #{label}|]
    else
      Print.println [c|{yellow|No symlink found for} #{label}|]

-- | Extract author and project strings from a package name.
pkgStrings :: Pkg.Name -> (String, String)
pkgStrings (Pkg.Name author project) =
  (Utf8.toChars author, Utf8.toChars project)
