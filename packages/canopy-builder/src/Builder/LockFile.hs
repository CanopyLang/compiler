{-# LANGUAGE OverloadedStrings #-}

-- | Lock file support for deterministic builds.
--
-- This module is the public API for @canopy.lock@ management.
-- Implementation is split across focused sub-modules:
--
-- * "Builder.LockFile.Types" -- Data types, lenses, JSON serialization
-- * "Builder.LockFile.Generate" -- Lock file generation from resolved deps
-- * "Builder.LockFile.Verify" -- Hash and signature verification
--
-- == Lock File Format
--
-- @
-- {
--   "lockfile-version": 1,
--   "generated": "2026-02-27T12:00:00Z",
--   "root": { "canopy-json-hash": "sha256:abc123..." },
--   "packages": {
--     "canopy/core": {
--       "version": "1.0.5",
--       "hash": "sha256:def456...",
--       "dependencies": { "canopy/json": "1.1.3" }
--     }
--   }
-- }
-- @
--
-- @since 0.19.1
module Builder.LockFile
  ( -- * Types (re-exported from Types)
    LockFile (..),
    LockedPackage (..),
    PackageSignature (..),

    -- * Domain Newtypes (re-exported from Types)
    LFT.ContentHash,
    LFT.Timestamp,
    LFT.KeyId,
    LFT.SignatureValue,
    LFT.unContentHash,
    LFT.unTimestamp,
    LFT.unKeyId,
    LFT.unSignatureValue,
    LFT.notCachedHash,

    -- * Lenses (re-exported from Types)
    lockVersion,
    lockGenerated,
    lockRootHash,
    lockPackages,
    lpVersion,
    lpHash,
    lpDependencies,
    lpSignature,
    lpSource,
    sigKeyId,
    sigValue,

    -- * Operations
    readLockFile,
    writeLockFile,
    isLockFileCurrent,
    lockFilePath,

    -- * Generation (re-exported from Generate)
    generateLockFile,

    -- * Verification (re-exported from Verify)
    verifyPackageHashes,
    VerifyResult (..),
    verifyPackageSignatures,
    SignatureResult (..),
  )
where

import Builder.LockFile.Generate (generateLockFile)
import Builder.LockFile.Types
  ( LockFile (..),
    LockedPackage (..),
    PackageSignature (..),
    lockVersion,
    lockGenerated,
    lockRootHash,
    lockPackages,
    lpVersion,
    lpHash,
    lpDependencies,
    lpSignature,
    lpSource,
    sigKeyId,
    sigValue,
  )
import qualified Builder.LockFile.Types as LFT
import Builder.LockFile.Verify
  ( VerifyResult (..),
    SignatureResult (..),
    verifyPackageHashes,
    verifyPackageSignatures,
  )
import qualified Canopy.Limits as Limits
import qualified Crypto.ConstantTime as CT
import qualified Data.Aeson as Json
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified File.Atomic as Atomic
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import qualified System.Directory as Dir
import System.FilePath ((</>))
import Builder.LockFile.Generate (hashFileToContentHash)

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
      enforceLockFileLimit path
      content <- LBS.readFile path
      pure (Json.decode content)
    else pure Nothing

-- | Enforce the lock file size limit.
--
-- @since 0.19.2
enforceLockFileLimit :: FilePath -> IO ()
enforceLockFileLimit path = do
  size <- Dir.getFileSize path
  case Limits.checkFileSize path (fromIntegral size) Limits.maxLockFileBytes of
    Nothing -> pure ()
    Just (Limits.FileSizeError fp actual limit) ->
      ioError (userError (lockFileTooLargeMsg fp actual limit))

-- | Format a file-too-large error message for lock files.
lockFileTooLargeMsg :: FilePath -> Int -> Int -> String
lockFileTooLargeMsg path actual limit =
  "FILE TOO LARGE -- " ++ path ++ "\n\n"
    ++ "    This lock file is " ++ showMB actual
    ++ ", which exceeds the " ++ showMB limit ++ " limit.\n\n"
    ++ "    The lock file may be corrupted. Try deleting it and\n"
    ++ "    running 'canopy install' to regenerate it.\n"
  where
    showMB bytes = show (bytes `div` (1024 * 1024)) ++ " MB"

-- | Write a lock file to disk.
--
-- @since 0.19.1
writeLockFile :: FilePath -> LockFile -> IO ()
writeLockFile root lf = do
  let path = lockFilePath root
  Log.logEvent (PackageOperation "lock-write" (Text.pack path))
  Atomic.writeLazyBytesAtomic path (Json.encode lf)

-- | Check whether the lock file is current with respect to @canopy.json@.
--
-- @since 0.19.1
isLockFileCurrent :: LockFile -> FilePath -> IO Bool
isLockFileCurrent lf root = do
  let canopyJsonPath = root </> "canopy.json"
  exists <- Dir.doesFileExist canopyJsonPath
  if exists
    then do
      currentHash <- hashFileToContentHash canopyJsonPath
      pure (CT.secureCompare (LFT.unContentHash currentHash) (LFT.unContentHash (_lockRootHash lf)))
    else pure False
