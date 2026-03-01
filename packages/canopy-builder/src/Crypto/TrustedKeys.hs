{-# LANGUAGE OverloadedStrings #-}

-- | Trusted public key registry for package signature verification.
--
-- This module maintains the set of trusted Ed25519 public keys used
-- to verify package signatures. Keys are identified by a short key ID
-- (the first 16 hex chars of the public key), allowing key rotation
-- without breaking existing lock files.
--
-- == Current Status
--
-- The key store is intentionally empty because the Canopy package registry
-- does not yet sign packages. All packages will be classified as
-- 'UnsignedPackages' during verification, which produces an informational
-- message. If a package claims to be signed but the key is not in this
-- store, verification fails with 'InvalidSignatures' (a hard error).
--
-- Users can skip all verification with @canopy install --no-verify@.
--
-- == Key Management
--
-- When the Canopy registry begins signing packages, its Ed25519 public
-- key will be embedded here at compile time. Future versions may support
-- fetching trusted keys from the registry server or a well-known HTTPS
-- endpoint.
--
-- == Key Rotation
--
-- When a new signing key is introduced:
--
-- 1. Add the new key to 'trustedKeys'
-- 2. Keep the old key for verifying existing signatures
-- 3. New packages will be signed with the new key
-- 4. Old signatures remain valid until explicitly revoked
--
-- @since 0.19.2
module Crypto.TrustedKeys
  ( -- * Key Lookup
    lookupTrustedKey,

    -- * Key ID
    keyIdFromPublicKey,

    -- * Registry
    trustedKeyIds,
  )
where

import qualified Crypto.Signature as Sig
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import qualified Data.Text as Text

-- | Look up a trusted public key by its key ID.
--
-- Returns 'Nothing' for unknown key IDs, which should be treated
-- as an unverifiable signature (not necessarily invalid, but the
-- key is not in our trust store).
--
-- @since 0.19.2
lookupTrustedKey :: Text.Text -> Maybe Sig.PublicKey
lookupTrustedKey keyId = Map.lookup keyId trustedKeys

-- | Compute the key ID from a public key.
--
-- The key ID is the first 16 hex characters of the public key,
-- providing a short identifier for key lookup without exposing
-- the full key material in lock files.
--
-- @since 0.19.2
keyIdFromPublicKey :: Sig.PublicKey -> Text.Text
keyIdFromPublicKey pk = Text.take 16 (Sig.publicKeyToHex pk)

-- | List all trusted key IDs.
--
-- @since 0.19.2
trustedKeyIds :: [Text.Text]
trustedKeyIds = Map.keys trustedKeys

-- | The set of trusted signing keys.
--
-- This is the root of trust for package verification. Keys are
-- mapped by their key ID (first 16 hex chars of the public key).
--
-- The key store is currently empty because the Canopy registry has not
-- yet published a signing key. When the registry begins signing
-- packages, add each hex-encoded public key to 'registryKeyHexValues'
-- and this map will be populated automatically.
--
-- @since 0.19.2
trustedKeys :: Map Text.Text Sig.PublicKey
trustedKeys =
  Map.fromList (concatMap parseEntry registryKeyHexValues)
  where
    parseEntry hex =
      case Sig.parsePublicKeyHex hex of
        Right pk -> [(keyIdFromPublicKey pk, pk)]
        Left _ -> []

-- | Hex-encoded Ed25519 public keys for the Canopy package registry.
--
-- Each entry is a 64-character hex string representing a 32-byte Ed25519
-- public key. The first key in the list should be the current signing key.
-- Previous keys are retained to verify packages signed before key rotation.
--
-- To generate a new key pair (on an air-gapped machine):
--
-- @
-- bash scripts\/generate-signing-key.sh
-- @
--
-- Then paste the resulting 64-character hex string here.
--
-- @since 0.19.2
registryKeyHexValues :: [Text.Text]
registryKeyHexValues =
  [
    -- When the registry begins signing, add the public key hex here:
    -- "64_character_hex_encoded_ed25519_public_key_from_generate_script"
  ]
