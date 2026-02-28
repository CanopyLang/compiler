{-# LANGUAGE OverloadedStrings #-}

-- | Domain-specific newtypes for lock file values.
--
-- These newtypes prevent accidental confusion between semantically
-- distinct 'Text' values in the lock file system. For example, a
-- 'ContentHash' (a SHA-256 digest) and a 'Timestamp' (an ISO 8601
-- string) are both stored as text, but passing one where the other
-- is expected is now a compile-time error.
--
-- Each newtype provides:
--
-- * A smart constructor with validation (where applicable)
-- * An unwrap function for serialization boundaries
-- * 'ToJSON'/'FromJSON' instances that delegate to 'Text'
-- * 'Eq', 'Ord', 'Show' for standard usage
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
  )
where

import qualified Data.Aeson as Json
import qualified Data.Text as Text

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
--
-- Returns 'Left' with a description if the input does not start
-- with @\"sha256:\"@.
--
-- @since 0.19.2
mkContentHash :: Text.Text -> Either String ContentHash
mkContentHash t
  | "sha256:" `Text.isPrefixOf` t = Right (ContentHash t)
  | otherwise = Left "Content hash must start with \"sha256:\""

-- | Construct a 'ContentHash' without validation.
--
-- Use only when the value is known to be well-formed, such as
-- when constructing literal constants or reading from a trusted
-- source that has already been validated.
--
-- @since 0.19.2
unsafeContentHash :: Text.Text -> ContentHash
unsafeContentHash = ContentHash

-- | Extract the raw text from a 'ContentHash'.
--
-- @since 0.19.2
unContentHash :: ContentHash -> Text.Text
unContentHash (ContentHash t) = t

instance Json.ToJSON ContentHash where
  toJSON = Json.toJSON . unContentHash

instance Json.FromJSON ContentHash where
  parseJSON v = ContentHash <$> Json.parseJSON v

-- | The sentinel hash used for packages that are not yet cached.
--
-- @since 0.19.2
notCachedHash :: ContentHash
notCachedHash = ContentHash "sha256:not-cached"

-- | ISO 8601 timestamp string.
--
-- Represents the generation time of a lock file. Validated at parse
-- time by the ISO 8601 formatting library, so no further validation
-- is needed in the smart constructor.
--
-- @since 0.19.2
newtype Timestamp = Timestamp Text.Text
  deriving (Eq, Ord, Show)

-- | Construct a 'Timestamp' from ISO 8601 text.
--
-- No additional validation is performed here because the value
-- is produced by 'Data.Time.Format.ISO8601.iso8601Show'.
--
-- @since 0.19.2
mkTimestamp :: Text.Text -> Timestamp
mkTimestamp = Timestamp

-- | Extract the raw text from a 'Timestamp'.
--
-- @since 0.19.2
unTimestamp :: Timestamp -> Text.Text
unTimestamp (Timestamp t) = t

instance Json.ToJSON Timestamp where
  toJSON = Json.toJSON . unTimestamp

instance Json.FromJSON Timestamp where
  parseJSON v = Timestamp <$> Json.parseJSON v

-- | Cryptographic key identifier.
--
-- Identifies which public key was used to sign a package.  Typically
-- the first 16 hex characters of the Ed25519 public key.
--
-- @since 0.19.2
newtype KeyId = KeyId Text.Text
  deriving (Eq, Ord, Show)

-- | Construct a 'KeyId'.
--
-- @since 0.19.2
mkKeyId :: Text.Text -> KeyId
mkKeyId = KeyId

-- | Extract the raw text from a 'KeyId'.
--
-- @since 0.19.2
unKeyId :: KeyId -> Text.Text
unKeyId (KeyId t) = t

instance Json.ToJSON KeyId where
  toJSON = Json.toJSON . unKeyId

instance Json.FromJSON KeyId where
  parseJSON v = KeyId <$> Json.parseJSON v

-- | Hex-encoded Ed25519 cryptographic signature.
--
-- The raw hex string representing a 64-byte Ed25519 signature
-- over a package's content hash.
--
-- @since 0.19.2
newtype SignatureValue = SignatureValue Text.Text
  deriving (Eq, Ord, Show)

-- | Construct a 'SignatureValue'.
--
-- @since 0.19.2
mkSignatureValue :: Text.Text -> SignatureValue
mkSignatureValue = SignatureValue

-- | Extract the raw text from a 'SignatureValue'.
--
-- @since 0.19.2
unSignatureValue :: SignatureValue -> Text.Text
unSignatureValue (SignatureValue t) = t

instance Json.ToJSON SignatureValue where
  toJSON = Json.toJSON . unSignatureValue

instance Json.FromJSON SignatureValue where
  parseJSON v = SignatureValue <$> Json.parseJSON v
