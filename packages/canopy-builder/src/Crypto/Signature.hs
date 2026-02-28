{-# LANGUAGE OverloadedStrings #-}

-- | Cryptographic signature verification for package integrity.
--
-- This module provides Ed25519 signature verification for Canopy packages.
-- It wraps the @crypton@ library to provide a focused, type-safe API
-- for verifying that package archives were signed by a trusted key.
--
-- == Design
--
-- Ed25519 was chosen because:
--
-- * It is fast (both signing and verification)
-- * It produces compact signatures (64 bytes)
-- * It is deterministic (same input always produces same signature)
-- * It is widely supported and well-audited
--
-- == Usage
--
-- @
-- case parsePublicKeyHex "ab01...ff" of
--   Left err -> handleError err
--   Right pubKey ->
--     let msgBytes = encodeUtf8 "package content hash"
--         valid = verifyEd25519 pubKey msgBytes sig
--     in ...
-- @
--
-- @since 0.19.2
module Crypto.Signature
  ( -- * Types
    PublicKey (..),
    Signature (..),
    CryptoError (..),

    -- * Verification
    verifyEd25519,

    -- * Parsing
    parsePublicKeyHex,
    parseSignatureHex,

    -- * Formatting
    publicKeyToHex,
    signatureToHex,
  )
where

import qualified Crypto.Error as CE
import qualified Crypto.PubKey.Ed25519 as Ed25519
import qualified Data.ByteArray as BA
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Char (digitToInt, intToDigit, isHexDigit)
import qualified Data.Text as Text
import Data.Word (Word8)

-- | An Ed25519 public key for signature verification.
--
-- @since 0.19.2
newtype PublicKey = PublicKey Ed25519.PublicKey
  deriving (Eq, Show)

-- | An Ed25519 signature over a message.
--
-- @since 0.19.2
newtype Signature = Signature Ed25519.Signature
  deriving (Eq, Show)

-- | Errors that can occur during cryptographic operations.
--
-- @since 0.19.2
data CryptoError
  = -- | The hex string could not be decoded (odd length, non-hex chars).
    InvalidHex !Text.Text
  | -- | The decoded bytes have the wrong length for an Ed25519 key (expected 32).
    InvalidKeyLength !Int
  | -- | The decoded bytes have the wrong length for a signature (expected 64).
    InvalidSignatureLength !Int
  | -- | The crypton library rejected the key or signature bytes.
    CryptonError !Text.Text
  deriving (Eq, Show)

-- | Verify an Ed25519 signature over a message.
--
-- Returns 'True' if and only if the signature is valid for the given
-- public key and message bytes. Uses constant-time comparison internally
-- (provided by the crypton library).
--
-- @since 0.19.2
verifyEd25519 :: PublicKey -> ByteString -> Signature -> Bool
verifyEd25519 (PublicKey pk) msg (Signature sig) =
  Ed25519.verify pk msg sig

-- | Parse a hex-encoded Ed25519 public key (32 bytes = 64 hex chars).
--
-- @since 0.19.2
parsePublicKeyHex :: Text.Text -> Either CryptoError PublicKey
parsePublicKeyHex hex =
  decodeHexBytes hex >>= validateKeyBytes

-- | Validate raw bytes as an Ed25519 public key.
validateKeyBytes :: ByteString -> Either CryptoError PublicKey
validateKeyBytes bs
  | BS.length bs /= 32 = Left (InvalidKeyLength (BS.length bs))
  | otherwise = convertCryptonResult PublicKey (Ed25519.publicKey bs)

-- | Convert a crypton CryptoFailable result to our error type.
convertCryptonResult :: (a -> b) -> CE.CryptoFailable a -> Either CryptoError b
convertCryptonResult wrap (CE.CryptoPassed a) = Right (wrap a)
convertCryptonResult _ (CE.CryptoFailed err) = Left (CryptonError (Text.pack (show err)))

-- | Parse a hex-encoded Ed25519 signature (64 bytes = 128 hex chars).
--
-- @since 0.19.2
parseSignatureHex :: Text.Text -> Either CryptoError Signature
parseSignatureHex hex =
  decodeHexBytes hex >>= validateSigBytes

-- | Validate raw bytes as an Ed25519 signature.
validateSigBytes :: ByteString -> Either CryptoError Signature
validateSigBytes bs
  | BS.length bs /= 64 = Left (InvalidSignatureLength (BS.length bs))
  | otherwise = convertCryptonResult Signature (Ed25519.signature bs)

-- | Decode a hex string to raw bytes.
decodeHexBytes :: Text.Text -> Either CryptoError ByteString
decodeHexBytes hex
  | odd (Text.length hex) = Left (InvalidHex "odd length")
  | not (Text.all isHexDigit hex) = Left (InvalidHex "non-hex characters")
  | otherwise = Right (hexToBytes (Text.unpack hex))

-- | Convert pairs of hex characters to bytes.
hexToBytes :: String -> ByteString
hexToBytes = BS.pack . go
  where
    go [] = []
    go (h : l : rest) = hexPairToByte h l : go rest
    go [_] = []

-- | Convert a pair of hex digits to a byte.
hexPairToByte :: Char -> Char -> Word8
hexPairToByte h l =
  fromIntegral (digitToInt h * 16 + digitToInt l)

-- | Encode a public key as a hex string.
--
-- @since 0.19.2
publicKeyToHex :: PublicKey -> Text.Text
publicKeyToHex (PublicKey pk) =
  bytesToHex (BA.convert pk :: ByteString)

-- | Encode a signature as a hex string.
--
-- @since 0.19.2
signatureToHex :: Signature -> Text.Text
signatureToHex (Signature sig) =
  bytesToHex (BA.convert sig :: ByteString)

-- | Encode bytes as a lowercase hex string.
bytesToHex :: ByteString -> Text.Text
bytesToHex = Text.pack . concatMap byteToHex . BS.unpack

-- | Encode a single byte as two hex characters.
byteToHex :: Word8 -> String
byteToHex w = [intToDigit (fromIntegral (w `div` 16)), intToDigit (fromIntegral (w `mod` 16))]
