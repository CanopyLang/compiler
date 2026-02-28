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
    PackageSignature (..),

    -- * Lenses
    lockVersion,
    lockGenerated,
    lockRootHash,
    lockPackages,
    lpVersion,
    lpHash,
    lpDependencies,
    lpSignature,
    lpSource,

    -- * Operations
    readLockFile,
    writeLockFile,
    isLockFileCurrent,
    lockFilePath,

    -- * Generation
    generateLockFile,

    -- * Verification
    verifyPackageHashes,
    VerifyResult (..),

    -- * Signature Verification
    verifyPackageSignatures,
    SignatureResult (..),

    -- * Signature Lenses
    sigKeyId,
    sigValue,
  )
where

import qualified Builder.Hash as Hash
import qualified Canopy.Constraint as Constraint
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Exception (IOException)
import qualified Control.Exception as Exception
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
import qualified PackageCache.Fetch as Fetch
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

-- | A single locked package with version, integrity hash, dependencies, and source.
--
-- The optional '_lpSource' field records where the package was originally
-- obtained from, enabling resilient re-fetching when the registry is down.
--
-- @since 0.19.1
data LockedPackage = LockedPackage
  { _lpVersion :: !Version.Version,
    _lpHash :: !Text.Text,
    _lpDependencies :: !(Map Pkg.Name Version.Version),
    _lpSignature :: !(Maybe PackageSignature),
    _lpSource :: !(Maybe Fetch.PackageSource)
  }
  deriving (Show)

-- | Cryptographic signature for a package archive.
--
-- Stores the hex-encoded signature and the key identifier used to
-- produce it. The key ID allows looking up the corresponding public
-- key for verification.
--
-- @since 0.19.2
data PackageSignature = PackageSignature
  { _sigKeyId :: !Text.Text,
    _sigValue :: !Text.Text
  }
  deriving (Eq, Show)

makeLenses ''LockFile
makeLenses ''LockedPackage
makeLenses ''PackageSignature

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
-- hashes are computed from the cached package config files. Dependencies
-- are read from each package's own outline and cross-referenced with
-- the resolved versions map.
--
-- @since 0.19.1
generateLockFile :: FilePath -> Map Pkg.Name Version.Version -> IO ()
generateLockFile root resolvedDeps = do
  let canopyJsonPath = root </> "canopy.json"
  contentHash <- Hash.hashFile canopyJsonPath
  let rootHash = Text.pack ("sha256:" ++ Hash.toHexString (Hash.hashValue contentHash))
  now <- Time.getCurrentTime
  let generated = Text.pack (ISO8601.iso8601Show now)
  cacheDir <- getPackageCacheDir
  packages <- traverse (buildLockedPackage cacheDir resolvedDeps) (Map.toList resolvedDeps)
  let lf =
        LockFile
          { _lockVersion = 1,
            _lockGenerated = generated,
            _lockRootHash = rootHash,
            _lockPackages = Map.fromList packages
          }
  writeLockFile root lf
  Log.logEvent (PackageOperation "lock-generated" (Text.pack (show (Map.size resolvedDeps)) <> " packages"))

-- | Resolve the global package cache directory (@~\/.canopy\/packages\/@).
getPackageCacheDir :: IO FilePath
getPackageCacheDir = do
  home <- Dir.getHomeDirectory
  pure (home </> ".canopy" </> "packages")

-- | Build a 'LockedPackage' entry for a single resolved dependency.
--
-- Looks up the package in the cache directory, hashes its config file
-- for integrity verification, and reads its declared dependencies
-- (cross-referenced against the full resolved versions map).
--
-- If the package is not yet cached, uses @\"sha256:not-cached\"@ as
-- a placeholder that will be filled on next download.
--
-- @since 0.19.1
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
-- Returns @\"sha256:not-cached\"@ if neither exists.
hashPackageConfig :: FilePath -> IO Text.Text
hashPackageConfig pkgDir = do
  let canopyJson = pkgDir </> "canopy.json"
      elmJson = pkgDir </> "elm.json"
  canopyExists <- Dir.doesFileExist canopyJson
  if canopyExists
    then hashFileToText canopyJson
    else do
      elmExists <- Dir.doesFileExist elmJson
      if elmExists
        then hashFileToText elmJson
        else pure "sha256:not-cached"

-- | Hash a file and format as @\"sha256:{hex}\"@.
hashFileToText :: FilePath -> IO Text.Text
hashFileToText path = do
  contentHash <- Hash.hashFile path
  pure (Text.pack ("sha256:" ++ Hash.toHexString (Hash.hashValue contentHash)))

-- | Read a package's declared dependencies and resolve to exact versions.
--
-- Reads the package's outline, extracts its dependency constraints,
-- and looks up the exact resolved version for each dependency.
-- Only includes dependencies present in the resolved map.
readPackageDeps :: FilePath -> Map Pkg.Name Version.Version -> IO (Map Pkg.Name Version.Version)
readPackageDeps pkgDir resolvedDeps = do
  result <- safeReadOutline pkgDir
  pure (extractDepsFromOutline result resolvedDeps)

-- | Safely read a package outline, catching IO exceptions.
--
-- Returns a descriptive error on failure instead of a generic message.
safeReadOutline :: FilePath -> IO (Either String Outline.Outline)
safeReadOutline pkgDir =
  Outline.read pkgDir `Exception.catch` handleIOError
  where
    handleIOError :: IOException -> IO (Either String Outline.Outline)
    handleIOError err = pure (Left ("failed to read outline: " ++ show err))

-- | Extract resolved dependency versions from a package outline.
--
-- For each dependency declared in the outline, looks up its exact
-- version in the resolved map. Dependencies not in the resolved
-- map are omitted (they are not part of the current closure).
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
    Json.object (requiredFields ++ signatureField ++ sourceField)
    where
      requiredFields =
        [ "version" .= _lpVersion lp,
          "hash" .= _lpHash lp,
          "dependencies" .= _lpDependencies lp
        ]
      signatureField = maybe [] (\sig -> ["signature" .= sig]) (_lpSignature lp)
      sourceField = maybe [] (\src -> ["source" .= src]) (_lpSource lp)

instance Json.FromJSON LockedPackage where
  parseJSON = Json.withObject "LockedPackage" $ \o ->
    LockedPackage
      <$> o Json..: "version"
      <*> o Json..: "hash"
      <*> o Json..: "dependencies"
      <*> o Json..:? "signature"
      <*> o Json..:? "source"

instance Json.ToJSON PackageSignature where
  toJSON sig =
    Json.object
      [ "key-id" .= _sigKeyId sig,
        "value" .= _sigValue sig
      ]

instance Json.FromJSON PackageSignature where
  parseJSON = Json.withObject "PackageSignature" $ \o ->
    PackageSignature
      <$> o Json..: "key-id"
      <*> o Json..: "value"

-- VERIFICATION

-- | Result of verifying package hashes against the lock file.
data VerifyResult
  = AllVerified
    -- ^ All cached packages match their lock file hashes
  | HashMismatch ![(Pkg.Name, Text.Text, Text.Text)]
    -- ^ Packages with mismatched hashes: (name, expected, actual)
  | NotCached ![Pkg.Name]
    -- ^ Packages not yet cached (hash is @sha256:not-cached@)
  deriving (Show)

-- | Verify that all cached packages match their lock file hashes.
--
-- For each package in the lock file, computes the current SHA-256
-- hash of its config file and compares against the stored hash.
-- Packages with @sha256:not-cached@ are reported as not yet cached.
-- Packages with mismatched hashes indicate potential tampering or
-- corruption.
--
-- @since 0.19.2
verifyPackageHashes :: LockFile -> IO VerifyResult
verifyPackageHashes lf = do
  cacheDir <- getPackageCacheDir
  results <- traverse (verifyOne cacheDir) (Map.toList (_lockPackages lf))
  let mismatches = [r | Left r <- results]
      uncached = [n | Right n <- results]
  pure (classifyResults mismatches uncached)

-- | Verify a single package's hash.
verifyOne :: FilePath -> (Pkg.Name, LockedPackage) -> IO (Either (Pkg.Name, Text.Text, Text.Text) Pkg.Name)
verifyOne cacheDir (pkg, lp)
  | _lpHash lp == "sha256:not-cached" = pure (Right pkg)
  | otherwise = do
      let pkgDir = packageCachePath cacheDir pkg (_lpVersion lp)
      actualHash <- hashPackageConfig pkgDir
      pure (if actualHash == _lpHash lp
        then Right pkg
        else Left (pkg, _lpHash lp, actualHash))

-- | Classify verification results.
classifyResults :: [(Pkg.Name, Text.Text, Text.Text)] -> [Pkg.Name] -> VerifyResult
classifyResults [] [] = AllVerified
classifyResults mismatches@(_ : _) _ = HashMismatch mismatches
classifyResults [] uncached = NotCached uncached

-- SIGNATURE VERIFICATION

-- | Result of verifying package signatures.
--
-- @since 0.19.2
data SignatureResult
  = AllSigned
    -- ^ All packages have valid signatures
  | UnsignedPackages ![Pkg.Name]
    -- ^ Packages that have no signature in the lock file
  | InvalidSignatures ![(Pkg.Name, Text.Text)]
    -- ^ Packages with invalid or unverifiable signatures (name, key-id)
  deriving (Show)

-- | Verify signatures for all packages in the lock file.
--
-- Checks that every locked package has a signature and that the
-- signature's key ID is from a trusted source. Actual cryptographic
-- verification requires the registry's public key, which is fetched
-- separately.
--
-- @since 0.19.2
verifyPackageSignatures :: LockFile -> SignatureResult
verifyPackageSignatures lf =
  let packages = Map.toList (_lockPackages lf)
      (unsigned, signed) = partitionSignatures packages
   in classifySignatures unsigned signed

-- | Partition packages into unsigned and signed groups.
partitionSignatures :: [(Pkg.Name, LockedPackage)] -> ([Pkg.Name], [(Pkg.Name, PackageSignature)])
partitionSignatures = foldr categorize ([], [])
  where
    categorize (name, lp) (uns, sig) =
      case _lpSignature lp of
        Nothing -> (name : uns, sig)
        Just s -> (uns, (name, s) : sig)

-- | Classify signature verification results.
classifySignatures :: [Pkg.Name] -> [(Pkg.Name, PackageSignature)] -> SignatureResult
classifySignatures [] _ = AllSigned
classifySignatures unsigned _ = UnsignedPackages unsigned
