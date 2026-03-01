{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Types for the lock file system.
--
-- This module contains all data types used by the lock file subsystem:
-- domain-specific newtypes ('ContentHash', 'Timestamp', 'KeyId',
-- 'SignatureValue') and the main record types ('LockFile',
-- 'LockedPackage', 'PackageSignature') with their JSON serialization
-- and lens generation.
--
-- Separating these types here avoids circular imports between
-- "Builder.LockFile.Generate" and "Builder.LockFile.Verify".
--
-- @since 0.19.2
module Builder.LockFile.Types
  ( -- * Content Hashes
    ContentHash,
    mkContentHash,
    unsafeContentHash,
    unContentHash,

    -- * Timestamps
    Timestamp,
    mkTimestamp,
    unTimestamp,

    -- * Key Identifiers
    KeyId,
    mkKeyId,
    unKeyId,

    -- * Signature Values
    SignatureValue,
    mkSignatureValue,
    unSignatureValue,

    -- * Constants
    notCachedHash,

    -- * Lock File
    LockFile (..),
    lockVersion,
    lockGenerated,
    lockRootHash,
    lockPackages,

    -- * Locked Package
    LockedPackage (..),
    lpVersion,
    lpHash,
    lpDependencies,
    lpSignature,
    lpSource,

    -- * Package Signature
    PackageSignature (..),
    sigKeyId,
    sigValue,
  )
where

import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Lens (makeLenses)
import Data.Aeson ((.=))
import qualified Data.Aeson as Json
import Data.Map.Strict (Map)
import qualified Data.Text as Text
import qualified PackageCache.Fetch as Fetch

-- DOMAIN NEWTYPES

-- | SHA-256 content hash with a @\"sha256:\"@ prefix.
--
-- Used for package integrity verification. The prefix is enforced
-- by the smart constructor 'mkContentHash', guaranteeing that every
-- 'ContentHash' value is well-formed.
--
-- @since 0.19.2
newtype ContentHash = ContentHash Text.Text
  deriving (Eq, Ord, Show)

-- | Construct a 'ContentHash', validating the @\"sha256:\"@ prefix.
mkContentHash :: Text.Text -> Either String ContentHash
mkContentHash t
  | "sha256:" `Text.isPrefixOf` t = Right (ContentHash t)
  | otherwise = Left "Content hash must start with \"sha256:\""

-- | Construct a 'ContentHash' without validation.
unsafeContentHash :: Text.Text -> ContentHash
unsafeContentHash = ContentHash

-- | Extract the raw text from a 'ContentHash'.
unContentHash :: ContentHash -> Text.Text
unContentHash (ContentHash t) = t

instance Json.ToJSON ContentHash where
  toJSON = Json.toJSON . unContentHash

instance Json.FromJSON ContentHash where
  parseJSON v = ContentHash <$> Json.parseJSON v

-- | The sentinel hash used for packages that are not yet cached.
notCachedHash :: ContentHash
notCachedHash = ContentHash "sha256:not-cached"

-- | ISO 8601 timestamp string.
newtype Timestamp = Timestamp Text.Text
  deriving (Eq, Ord, Show)

-- | Construct a 'Timestamp' from ISO 8601 text.
mkTimestamp :: Text.Text -> Timestamp
mkTimestamp = Timestamp

-- | Extract the raw text from a 'Timestamp'.
unTimestamp :: Timestamp -> Text.Text
unTimestamp (Timestamp t) = t

instance Json.ToJSON Timestamp where
  toJSON = Json.toJSON . unTimestamp

instance Json.FromJSON Timestamp where
  parseJSON v = Timestamp <$> Json.parseJSON v

-- | Cryptographic key identifier.
newtype KeyId = KeyId Text.Text
  deriving (Eq, Ord, Show)

-- | Construct a 'KeyId'.
mkKeyId :: Text.Text -> KeyId
mkKeyId = KeyId

-- | Extract the raw text from a 'KeyId'.
unKeyId :: KeyId -> Text.Text
unKeyId (KeyId t) = t

instance Json.ToJSON KeyId where
  toJSON = Json.toJSON . unKeyId

instance Json.FromJSON KeyId where
  parseJSON v = KeyId <$> Json.parseJSON v

-- | Hex-encoded Ed25519 cryptographic signature.
newtype SignatureValue = SignatureValue Text.Text
  deriving (Eq, Ord, Show)

-- | Construct a 'SignatureValue'.
mkSignatureValue :: Text.Text -> SignatureValue
mkSignatureValue = SignatureValue

-- | Extract the raw text from a 'SignatureValue'.
unSignatureValue :: SignatureValue -> Text.Text
unSignatureValue (SignatureValue t) = t

instance Json.ToJSON SignatureValue where
  toJSON = Json.toJSON . unSignatureValue

instance Json.FromJSON SignatureValue where
  parseJSON v = SignatureValue <$> Json.parseJSON v

-- RECORD TYPES

-- | Lock file capturing the full dependency closure.
--
-- Contains the lock file format version, generation timestamp,
-- a hash of the source @canopy.json@ for staleness detection,
-- and the complete set of resolved packages with integrity hashes.
--
-- @since 0.19.1
data LockFile = LockFile
  { _lockVersion :: !Int,
    _lockGenerated :: !Timestamp,
    _lockRootHash :: !ContentHash,
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
    _lpHash :: !ContentHash,
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
  { _sigKeyId :: !KeyId,
    _sigValue :: !SignatureValue
  }
  deriving (Eq, Show)

makeLenses ''LockFile
makeLenses ''LockedPackage
makeLenses ''PackageSignature

-- JSON SERIALIZATION

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
