{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Package artifact location for setup.
--
-- Checks whether standard library package artifacts exist in the
-- Canopy cache (@~\/.canopy\/packages\/@).
--
-- @since 0.19.1
module Setup.PackageLocator
  ( -- * Package Location
    locatePackage,
  )
where

import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Reporting.Doc.ColorQQ (c)
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified Terminal.Print as Print
import qualified Text.PrettyPrint.ANSI.Leijen as PP

-- | Check whether a package's artifacts exist in the Canopy cache.
--
-- Returns True if artifacts are available (either compiled or with
-- source ready for compilation by 'compileLocalPackages').
locatePackage :: FilePath -> Bool -> (Pkg.Name, Version.Version) -> IO Bool
locatePackage _cache verbose (pkg, version) = do
  homeDir <- Dir.getHomeDirectory
  let (author, project) = pkgStrings pkg
      versionStr = Version.toChars version
      canopyDir = homeDir </> ".canopy" </> "packages" </> author </> project </> versionStr
      canopyArtifacts = canopyDir </> "artifacts.dat"
      label = author <> "/" <> project <> " " <> versionStr
  canopyExists <- Dir.doesFileExist canopyArtifacts
  if canopyExists
    then do
      Print.println [c|  #{label}: {green|ready}|]
      pure True
    else do
      hasSource <- hasPackageSource canopyDir
      if hasSource
        then do
          Print.println [c|  #{label}: {yellow|source available (will compile)}|]
          pure True
        else do
          Print.println [c|  #{label}: {red|not found — run `canopy link` to install from source}|]
          verboseLog verbose [c|    Checked: {cyan|#{canopyDir}}|]
          pure False

-- | Check whether a package directory has source files ready for compilation.
hasPackageSource :: FilePath -> IO Bool
hasPackageSource dir = do
  dirExists <- Dir.doesDirectoryExist dir
  if not dirExists
    then pure False
    else do
      hasOutline <- hasPackageOutline dir
      hasSrc <- Dir.doesDirectoryExist (dir </> "src")
      pure (hasOutline && hasSrc)

-- | Check whether a package directory contains a valid outline file.
hasPackageOutline :: FilePath -> IO Bool
hasPackageOutline dir = do
  canopyExists <- Dir.doesFileExist (dir </> "canopy.json")
  if canopyExists
    then pure True
    else Dir.doesFileExist (dir </> "elm.json")

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
