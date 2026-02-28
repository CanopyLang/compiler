{-# LANGUAGE OverloadedStrings #-}

-- | Trusted public key registry for package signature verification.
--
-- This module maintains the set of trusted Ed25519 public keys used
-- to verify package signatures. Keys are identified by a short key ID
-- (the first 16 hex chars of the public key), allowing key rotation
-- without breaking existing lock files.
--
-- == Key Management
--
-- Currently, the Canopy registry signing key is embedded at compile time.
-- Future versions may support fetching trusted keys from the registry
-- server or a well-known HTTPS endpoint.
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
-- The initial key set is empty because the Canopy registry has not
-- yet published a signing key. When the registry begins signing
-- packages, its public key will be added here.
--
-- To add a key:
--
-- @
-- trustedKeys = Map.fromList
--   [ ("ab01cd23ef456789", key)
--   ]
--   where
--     Right key = Sig.parsePublicKeyHex "ab01cd23ef456789..."
-- @
trustedKeys :: Map Text.Text Sig.PublicKey
trustedKeys = Map.empty
