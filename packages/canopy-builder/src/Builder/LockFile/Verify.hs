{-# LANGUAGE OverloadedStrings #-}

-- | Lock file integrity and signature verification.
--
-- Provides hash verification (ensuring cached packages match their
-- lock file hashes) and Ed25519 signature verification (ensuring
-- packages were signed by trusted keys).
--
-- @since 0.19.2
module Builder.LockFile.Verify
  ( -- * Hash Verification
    VerifyResult (..),
    verifyPackageHashes,

    -- * Signature Verification
    SignatureResult (..),
    verifyPackageSignatures,
  )
where

import Builder.LockFile.Generate (hashPackageConfig, packageCachePath, getPackageCacheDir)
import Builder.LockFile.Types
  ( ContentHash,
    KeyId,
    LockFile (..),
    LockedPackage (..),
    PackageSignature (..),
  )
import qualified Builder.LockFile.Types as LFT
import qualified Canopy.Package as Pkg
import qualified Crypto.ConstantTime as CT
import qualified Crypto.Signature as Sig
import qualified Crypto.TrustedKeys as TrustedKeys
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc

-- HASH VERIFICATION

-- | Result of verifying package hashes against the lock file.
data VerifyResult
  = -- | All cached packages match their lock file hashes
    AllVerified
  | -- | Packages with mismatched hashes: (name, expected, actual)
    HashMismatch ![(Pkg.Name, ContentHash, ContentHash)]
  | -- | Packages not yet cached (hash is 'notCachedHash')
    NotCached ![Pkg.Name]
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
verifyOne :: FilePath -> (Pkg.Name, LockedPackage) -> IO (Either (Pkg.Name, ContentHash, ContentHash) Pkg.Name)
verifyOne cacheDir (pkg, lp)
  | _lpHash lp == LFT.notCachedHash = pure (Right pkg)
  | otherwise = do
      let pkgDir = packageCachePath cacheDir pkg (_lpVersion lp)
      actualHash <- hashPackageConfig pkgDir
      pure
        ( if CT.secureCompare (LFT.unContentHash actualHash) (LFT.unContentHash (_lpHash lp))
            then Right pkg
            else Left (pkg, _lpHash lp, actualHash)
        )

-- | Classify verification results.
classifyResults :: [(Pkg.Name, ContentHash, ContentHash)] -> [Pkg.Name] -> VerifyResult
classifyResults [] [] = AllVerified
classifyResults mismatches@(_ : _) _ = HashMismatch mismatches
classifyResults [] uncached = NotCached uncached

-- SIGNATURE VERIFICATION

-- | Result of verifying package signatures.
--
-- @since 0.19.2
data SignatureResult
  = -- | All packages have valid signatures
    AllSigned
  | -- | Packages that have no signature in the lock file
    UnsignedPackages ![Pkg.Name]
  | -- | Packages with invalid or unverifiable signatures (name, key-id)
    InvalidSignatures ![(Pkg.Name, KeyId)]
  deriving (Show)

-- | Verify signatures for all packages in the lock file.
--
-- Performs actual Ed25519 cryptographic verification against the
-- trusted key registry. For each signed package:
--
-- 1. Looks up the signing key by key ID in 'TrustedKeys'
-- 2. Parses the hex-encoded signature
-- 3. Verifies the signature over the package hash
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

-- | Classify signature verification results with actual crypto verification.
--
-- Invalid signatures take priority over unsigned packages. Even in a
-- mixed-signing environment, a package with a bad signature is always
-- a hard error -- it indicates tampering rather than merely missing
-- infrastructure.
classifySignatures :: [Pkg.Name] -> [(Pkg.Name, PackageSignature)] -> SignatureResult
classifySignatures unsigned signed =
  let invalids = [(n, _sigKeyId s) | (n, s) <- signed, not (verifyOneSignature (n, s))]
   in case invalids of
        _ : _ -> InvalidSignatures invalids
        [] -> case unsigned of
          _ : _ -> UnsignedPackages unsigned
          [] -> AllSigned

-- | Verify a single package signature against the trusted key store.
verifyOneSignature :: (Pkg.Name, PackageSignature) -> Bool
verifyOneSignature (pkg, sig) =
  case TrustedKeys.lookupTrustedKey (LFT.unKeyId (_sigKeyId sig)) of
    Nothing -> False
    Just pubKey -> verifySigBytes pubKey pkg sig

-- | Verify the Ed25519 signature bytes for a package.
verifySigBytes :: Sig.PublicKey -> Pkg.Name -> PackageSignature -> Bool
verifySigBytes pubKey pkg sig =
  case Sig.parseSignatureHex (LFT.unSignatureValue (_sigValue sig)) of
    Left _ -> False
    Right parsedSig ->
      let msg = TextEnc.encodeUtf8 (Text.pack (Pkg.toChars pkg))
       in Sig.verifyEd25519 pubKey msg parsedSig
