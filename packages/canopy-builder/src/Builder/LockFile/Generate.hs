{-# LANGUAGE OverloadedStrings #-}

-- | Lock file generation from resolved dependencies.
--
-- Given a resolved dependency map, generates a @canopy.lock@ file
-- capturing the full transitive closure with exact versions and
-- SHA-256 integrity hashes.
--
-- @since 0.19.1
module Builder.LockFile.Generate
  ( -- * Generation
    generateLockFile,

    -- * Internals (exported for testing)
    packageCachePath,
    hashPackageConfig,
    hashFileToContentHash,
    getPackageCacheDir,
  )
where

import qualified Builder.Hash as Hash
import Builder.LockFile.Types
  ( ContentHash,
    LockFile (..),
    LockedPackage (..),
  )
import qualified Builder.LockFile.Types as LFT
import qualified Canopy.Constraint as Constraint
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Exception (IOException)
import qualified Control.Exception as Exception
import qualified Data.Aeson as Json
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Time as Time
import qualified Data.Time.Format.ISO8601 as ISO8601
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import qualified System.Directory as Dir
import System.FilePath ((</>))

-- | Generate a lock file from resolved dependencies.
--
-- Takes the project root and the map of resolved package versions,
-- computes the @canopy.json@ hash, and writes the lock file. Package
-- hashes are computed from the cached package config files. Dependencies
-- are read from each package's own outline and cross-referenced with
-- the resolved versions map.
--
-- @since 0.19.1
generateLockFile :: FilePath -> Map Pkg.Name Version.Version -> IO ()
generateLockFile root resolvedDeps = do
  let canopyJsonPath = root </> "canopy.json"
  rootHash <- hashFileToContentHash canopyJsonPath
  now <- Time.getCurrentTime
  let generated = LFT.mkTimestamp (Text.pack (ISO8601.iso8601Show now))
  cacheDir <- getPackageCacheDir
  packages <- traverse (buildLockedPackage cacheDir resolvedDeps) (Map.toList resolvedDeps)
  let lf =
        LockFile
          { _lockVersion = 1,
            _lockGenerated = generated,
            _lockRootHash = rootHash,
            _lockPackages = Map.fromList packages
          }
  let path = root </> "canopy.lock"
  Log.logEvent (PackageOperation "lock-write" (Text.pack path))
  LBS.writeFile path (Json.encode lf)
  Log.logEvent (PackageOperation "lock-generated" (Text.pack (show (Map.size resolvedDeps)) <> " packages"))

-- | Resolve the global package cache directory.
getPackageCacheDir :: IO FilePath
getPackageCacheDir = do
  home <- Dir.getHomeDirectory
  pure (home </> ".canopy" </> "packages")

-- | Build a 'LockedPackage' entry for a single resolved dependency.
--
-- Looks up the package in the cache directory, hashes its config file
-- for integrity verification, and reads its declared dependencies.
--
-- If the package is not yet cached, uses @\"sha256:not-cached\"@ as
-- a placeholder that will be filled on next download.
buildLockedPackage :: FilePath -> Map Pkg.Name Version.Version -> (Pkg.Name, Version.Version) -> IO (Pkg.Name, LockedPackage)
buildLockedPackage cacheDir resolvedDeps (pkg, ver) = do
  let pkgDir = packageCachePath cacheDir pkg ver
  pkgHash <- hashPackageConfig pkgDir
  pkgDeps <- readPackageDeps pkgDir resolvedDeps
  let lp =
        LockedPackage
          { _lpVersion = ver,
            _lpHash = pkgHash,
            _lpDependencies = pkgDeps,
            _lpSignature = Nothing,
            _lpSource = Nothing
          }
  pure (pkg, lp)

-- | Compute the cache path for a specific package version.
--
-- Layout: @{cacheDir}\/{author}\/{project}\/{version}\/@
packageCachePath :: FilePath -> Pkg.Name -> Version.Version -> FilePath
packageCachePath cacheDir pkg ver =
  cacheDir </> Pkg.toFilePath pkg </> Version.toChars ver

-- | Hash the package's config file for integrity verification.
--
-- Tries @canopy.json@ first, then falls back to @elm.json@.
-- Returns 'LFT.notCachedHash' if neither exists.
hashPackageConfig :: FilePath -> IO ContentHash
hashPackageConfig pkgDir = do
  let canopyJson = pkgDir </> "canopy.json"
      elmJson = pkgDir </> "elm.json"
  canopyExists <- Dir.doesFileExist canopyJson
  if canopyExists
    then hashFileToContentHash canopyJson
    else do
      elmExists <- Dir.doesFileExist elmJson
      if elmExists
        then hashFileToContentHash elmJson
        else pure LFT.notCachedHash

-- | Hash a file and wrap as a 'ContentHash' with @\"sha256:\"@ prefix.
hashFileToContentHash :: FilePath -> IO ContentHash
hashFileToContentHash path = do
  contentHash <- Hash.hashFile path
  pure (LFT.unsafeContentHash (Text.pack ("sha256:" ++ Hash.toHexString (Hash.hashValue contentHash))))

-- | Read a package's declared dependencies and resolve to exact versions.
readPackageDeps :: FilePath -> Map Pkg.Name Version.Version -> IO (Map Pkg.Name Version.Version)
readPackageDeps pkgDir resolvedDeps = do
  result <- safeReadOutline pkgDir
  pure (extractDepsFromOutline result resolvedDeps)

-- | Safely read a package outline, catching IO exceptions.
safeReadOutline :: FilePath -> IO (Either String Outline.Outline)
safeReadOutline pkgDir =
  Outline.read pkgDir `Exception.catch` handleIOError
  where
    handleIOError :: IOException -> IO (Either String Outline.Outline)
    handleIOError err = pure (Left ("failed to read outline: " ++ show err))

-- | Extract resolved dependency versions from a package outline.
extractDepsFromOutline :: Either String Outline.Outline -> Map Pkg.Name Version.Version -> Map Pkg.Name Version.Version
extractDepsFromOutline (Left _) _ = Map.empty
extractDepsFromOutline (Right outline) resolvedDeps =
  Map.intersection resolvedDeps declaredDeps
  where
    declaredDeps = outlineDeps outline

-- | Extract the dependency map from an outline.
outlineDeps :: Outline.Outline -> Map Pkg.Name Constraint.Constraint
outlineDeps (Outline.App appOutline) = Outline._appDeps appOutline
outlineDeps (Outline.Pkg pkgOutline) = Outline._pkgDeps pkgOutline
outlineDeps (Outline.Workspace _) = Map.empty
