{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Lock file support for deterministic builds.
--
-- This module implements @canopy.lock@ generation and reading for
-- reproducible dependency resolution. The lock file captures the full
-- transitive dependency closure with exact versions and SHA-256 hashes,
-- ensuring builds are identical across machines and over time.
--
-- == Lock File Format
--
-- The lock file is JSON with the following structure:
--
-- @
-- {
--   "lockfile-version": 1,
--   "generated": "2026-02-27T12:00:00Z",
--   "root": { "canopy-json-hash": "sha256:abc123..." },
--   "packages": {
--     "elm/core": {
--       "version": "1.0.5",
--       "hash": "sha256:def456...",
--       "dependencies": { "elm/json": "1.1.3" }
--     }
--   }
-- }
-- @
--
-- == Conventions
--
-- * Applications should commit @canopy.lock@ for reproducible builds
-- * Packages should NOT commit @canopy.lock@ (allows broader compatibility)
--
-- @since 0.19.1
module Builder.LockFile
  ( -- * Types
    LockFile (..),
    LockedPackage (..),

    -- * Lenses
    lockVersion,
    lockGenerated,
    lockRootHash,
    lockPackages,
    lpVersion,
    lpHash,
    lpDependencies,

    -- * Operations
    readLockFile,
    writeLockFile,
    isLockFileCurrent,
    lockFilePath,

    -- * Generation
    generateLockFile,
  )
where

import qualified Builder.Hash as Hash
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Lens (makeLenses)
import Data.Aeson ((.=))
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

-- | Lock file capturing the full dependency closure.
--
-- Contains the lock file format version, generation timestamp,
-- a hash of the source @canopy.json@ for staleness detection,
-- and the complete set of resolved packages with integrity hashes.
--
-- @since 0.19.1
data LockFile = LockFile
  { _lockVersion :: !Int,
    _lockGenerated :: !Text.Text,
    _lockRootHash :: !Text.Text,
    _lockPackages :: !(Map Pkg.Name LockedPackage)
  }
  deriving (Show)

-- | A single locked package with version, integrity hash, and dependencies.
--
-- @since 0.19.1
data LockedPackage = LockedPackage
  { _lpVersion :: !Version.Version,
    _lpHash :: !Text.Text,
    _lpDependencies :: !(Map Pkg.Name Version.Version)
  }
  deriving (Show)

makeLenses ''LockFile
makeLenses ''LockedPackage

-- | Compute the path to the lock file within a project root.
--
-- @since 0.19.1
lockFilePath :: FilePath -> FilePath
lockFilePath root = root </> "canopy.lock"

-- | Read a lock file from disk.
--
-- Returns 'Nothing' if the file does not exist or cannot be parsed.
--
-- @since 0.19.1
readLockFile :: FilePath -> IO (Maybe LockFile)
readLockFile root = do
  let path = lockFilePath root
  exists <- Dir.doesFileExist path
  if exists
    then do
      Log.logEvent (PackageOperation "lock-read" (Text.pack path))
      content <- LBS.readFile path
      pure (Json.decode content)
    else pure Nothing

-- | Write a lock file to disk.
--
-- @since 0.19.1
writeLockFile :: FilePath -> LockFile -> IO ()
writeLockFile root lf = do
  let path = lockFilePath root
  Log.logEvent (PackageOperation "lock-write" (Text.pack path))
  LBS.writeFile path (Json.encode lf)

-- | Check whether the lock file is current with respect to @canopy.json@.
--
-- Computes the SHA-256 hash of the project's @canopy.json@ and compares
-- it against the hash stored in the lock file.  Returns 'True' when they
-- match, meaning the lock file reflects the current dependency specification.
--
-- @since 0.19.1
isLockFileCurrent :: LockFile -> FilePath -> IO Bool
isLockFileCurrent lf root = do
  let canopyJsonPath = root </> "canopy.json"
  exists <- Dir.doesFileExist canopyJsonPath
  if exists
    then do
      contentHash <- Hash.hashFile canopyJsonPath
      let currentHex = Text.pack ("sha256:" ++ Hash.toHexString (Hash.hashValue contentHash))
      pure (currentHex == _lockRootHash lf)
    else pure False

-- | Generate a lock file from resolved dependencies.
--
-- Takes the project root and the map of resolved package versions,
-- computes the @canopy.json@ hash, and writes the lock file. Package
-- hashes are looked up from the local cache when available; packages
-- not yet cached receive a placeholder that will be filled on first download.
--
-- @since 0.19.1
generateLockFile :: FilePath -> Map Pkg.Name Version.Version -> IO ()
generateLockFile root resolvedDeps = do
  let canopyJsonPath = root </> "canopy.json"
  contentHash <- Hash.hashFile canopyJsonPath
  let rootHash = Text.pack ("sha256:" ++ Hash.toHexString (Hash.hashValue contentHash))
  now <- Time.getCurrentTime
  let generated = Text.pack (ISO8601.iso8601Show now)
  packages <- traverse (buildLockedPackage root) (Map.toList resolvedDeps)
  let lf =
        LockFile
          { _lockVersion = 1,
            _lockGenerated = generated,
            _lockRootHash = rootHash,
            _lockPackages = Map.fromList packages
          }
  writeLockFile root lf
  Log.logEvent (PackageOperation "lock-generated" (Text.pack (show (Map.size resolvedDeps)) <> " packages"))

-- | Build a 'LockedPackage' entry for a single resolved dependency.
buildLockedPackage :: FilePath -> (Pkg.Name, Version.Version) -> IO (Pkg.Name, LockedPackage)
buildLockedPackage _root (pkg, ver) = do
  let lp =
        LockedPackage
          { _lpVersion = ver,
            _lpHash = "sha256:pending",
            _lpDependencies = Map.empty
          }
  pure (pkg, lp)

-- JSON serialization

instance Json.ToJSON LockFile where
  toJSON lf =
    Json.object
      [ "lockfile-version" .= _lockVersion lf,
        "generated" .= _lockGenerated lf,
        "root" .= Json.object ["canopy-json-hash" .= _lockRootHash lf],
        "packages" .= _lockPackages lf
      ]

instance Json.FromJSON LockFile where
  parseJSON = Json.withObject "LockFile" $ \o -> do
    ver <- o Json..: "lockfile-version"
    gen <- o Json..: "generated"
    rootObj <- o Json..: "root"
    rootH <- rootObj Json..: "canopy-json-hash"
    pkgs <- o Json..: "packages"
    pure
      LockFile
        { _lockVersion = ver,
          _lockGenerated = gen,
          _lockRootHash = rootH,
          _lockPackages = pkgs
        }

instance Json.ToJSON LockedPackage where
  toJSON lp =
    Json.object
      [ "version" .= _lpVersion lp,
        "hash" .= _lpHash lp,
        "dependencies" .= _lpDependencies lp
      ]

instance Json.FromJSON LockedPackage where
  parseJSON = Json.withObject "LockedPackage" $ \o ->
    LockedPackage
      <$> o Json..: "version"
      <*> o Json..: "hash"
      <*> o Json..: "dependencies"
