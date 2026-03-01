# Plan 06: Trusted Key Store Bootstrap

- **Priority**: MEDIUM
- **Effort**: Medium (1-2d)
- **Risk**: Medium

## Problem

The trusted key store (`Crypto.TrustedKeys`) is intentionally empty. This means:

1. Every package is classified as `UnsignedPackages` during signature
   verification, which produces only an informational message.

2. If a malicious actor creates a package with a fake signature, verification
   cannot detect it because there are no trusted keys to verify against. The
   signature is simply ignored as "unsigned."

3. When the Canopy registry eventually starts signing packages, there is no
   mechanism to distribute the public key to existing installations.

The crypto infrastructure is fully built out:
- `Crypto.Signature` has Ed25519 verification
- `Crypto.TrustedKeys` has the lookup interface
- `Builder.LockFile.Verify` has signature verification logic
- `Crypto.ConstantTime` has timing-safe comparison

What is missing is the actual bootstrap: embedding a registry key and defining
the upgrade path.

### Current Code

**File**: `/home/quinten/fh/canopy/packages/canopy-builder/src/Crypto/TrustedKeys.hs`

At lines 98-99, the key store is empty:

```haskell
trustedKeys :: Map Text.Text Sig.PublicKey
trustedKeys = Map.empty
```

**File**: `/home/quinten/fh/canopy/packages/canopy-builder/src/Builder/LockFile/Verify.hs`

At lines 110-114, `verifyPackageSignatures` partitions into unsigned/signed:

```haskell
verifyPackageSignatures :: LockFile -> SignatureResult
verifyPackageSignatures lf =
  let packages = Map.toList (_lockPackages lf)
      (unsigned, signed) = partitionSignatures packages
   in classifySignatures unsigned signed
```

At lines 127-128, if there are ANY unsigned packages, all signed packages are
ignored:

```haskell
classifySignatures :: [Pkg.Name] -> [(Pkg.Name, PackageSignature)] -> SignatureResult
classifySignatures unsigned@(_ : _) _ = UnsignedPackages unsigned
```

This means even if some packages ARE signed and have invalid signatures, the
error is masked by the presence of unsigned packages. This is a logic bug that
should be fixed as part of the bootstrap.

**File**: `/home/quinten/fh/canopy/packages/canopy-builder/src/Crypto/Signature.hs`

The Ed25519 infrastructure is complete:

```haskell
verifyEd25519 :: PublicKey -> ByteString -> Signature -> Bool
verifyEd25519 (PublicKey pk) msg (Signature sig) = Ed25519.verify pk msg sig

parsePublicKeyHex :: Text.Text -> Either CryptoError PublicKey
parseSignatureHex :: Text.Text -> Either CryptoError Signature
publicKeyToHex :: PublicKey -> Text.Text
```

All the pieces work. The missing piece is a real key.

## Design: Minimum Viable Key Bootstrap

### Phase 1: Embed a Development/Staging Key

Generate a Canopy registry Ed25519 key pair. Embed the public key in
`TrustedKeys.hs`. This allows testing the full signature verification pipeline
end-to-end before the registry starts signing.

### Phase 2: Fix Signature Verification Logic

Fix `classifySignatures` to check invalid signatures even when unsigned
packages exist.

### Phase 3: Add Key Fetching (Future)

Add a mechanism to fetch trusted keys from a well-known HTTPS endpoint
(e.g., `https://package.canopy-lang.org/.well-known/canopy-keys.json`).
This allows key rotation without requiring a compiler update.

## Files to Modify

### 1. `Crypto/TrustedKeys.hs` (lines 98-99) -- Embed the registry key

**Current**:
```haskell
trustedKeys :: Map Text.Text Sig.PublicKey
trustedKeys = Map.empty
```

**Proposed**:
```haskell
trustedKeys :: Map Text.Text Sig.PublicKey
trustedKeys =
  Map.fromList (concatMap toEntry registryKeys)
  where
    toEntry hex =
      case Sig.parsePublicKeyHex hex of
        Right pk -> [(keyIdFromPublicKey pk, pk)]
        Left _ -> []

-- | The Canopy registry's Ed25519 public keys.
--
-- The first key is the current signing key. Additional keys are
-- retained for verifying packages signed with previous keys.
--
-- To generate a new key pair (offline, air-gapped machine):
--
-- @
-- openssl genpkey -algorithm ed25519 -outform DER | tail -c 32 | xxd -p -c 32
-- @
--
-- @since 0.19.2
registryKeys :: [Text.Text]
registryKeys =
  [ -- Canopy registry signing key v1 (2026-03-01)
    -- TODO: Replace with actual registry public key when generated
    "PLACEHOLDER_KEY_HEX_64_CHARS_REPLACE_BEFORE_RELEASE_0000000000"
  ]
```

The placeholder ensures the code compiles and the structure is correct.
Before the first signed release, the actual key must be generated and
substituted.

### 2. `Builder/LockFile/Verify.hs` (lines 126-132) -- Fix classification logic

**Current** (masks invalid signatures when unsigned packages exist):
```haskell
classifySignatures :: [Pkg.Name] -> [(Pkg.Name, PackageSignature)] -> SignatureResult
classifySignatures unsigned@(_ : _) _ = UnsignedPackages unsigned
classifySignatures [] signed =
  let invalids = filter (not . verifyOneSignature) signed
   in if null invalids
        then AllSigned
        else InvalidSignatures [(n, _sigKeyId s) | (n, s) <- invalids]
```

**Proposed** (always check signed packages for invalid signatures):
```haskell
classifySignatures :: [Pkg.Name] -> [(Pkg.Name, PackageSignature)] -> SignatureResult
classifySignatures unsigned signed =
  let invalids = filter (not . verifyOneSignature) signed
   in if not (null invalids)
        then InvalidSignatures [(n, _sigKeyId s) | (n, s) <- invalids]
        else if null unsigned
          then AllSigned
          else UnsignedPackages unsigned
```

This change ensures that invalid signatures are always a hard error, even in
mixed-signing environments. Unsigned packages are only reported when ALL signed
packages verify successfully.

### 3. Add a key generation script (new file)

**File**: `/home/quinten/fh/canopy/scripts/generate-signing-key.sh`

```bash
#!/usr/bin/env bash
# Generate an Ed25519 key pair for the Canopy package registry.
#
# Run this on an air-gapped machine. Store the private key securely.
# The public key should be embedded in Crypto/TrustedKeys.hs.

set -euo pipefail

PRIVATE_KEY_FILE="canopy-registry.key"
PUBLIC_KEY_FILE="canopy-registry.pub"

openssl genpkey -algorithm ed25519 -outform DER -out "$PRIVATE_KEY_FILE"
openssl pkey -in "$PRIVATE_KEY_FILE" -inform DER -pubout -outform DER -out "$PUBLIC_KEY_FILE"

# Extract raw 32-byte public key (skip DER header)
PUBLIC_KEY_HEX=$(tail -c 32 "$PUBLIC_KEY_FILE" | xxd -p -c 32)

echo "Public key (hex): $PUBLIC_KEY_HEX"
echo "Key ID (first 16 chars): ${PUBLIC_KEY_HEX:0:16}"
echo ""
echo "Add to Crypto/TrustedKeys.hs:"
echo "  \"$PUBLIC_KEY_HEX\""
echo ""
echo "Private key saved to: $PRIVATE_KEY_FILE"
echo "PUBLIC KEY FILE (for reference): $PUBLIC_KEY_FILE"
echo ""
echo "IMPORTANT: Store $PRIVATE_KEY_FILE in a secure, air-gapped location."
```

### 4. Add `SignatureResult` improvement -- new variant for mixed state

**Optional enhancement**: Add a `MixedSignatures` variant that reports both
unsigned and invalid packages in one result:

```haskell
data SignatureResult
  = AllSigned
  | UnsignedPackages ![Pkg.Name]
  | InvalidSignatures ![(Pkg.Name, KeyId)]
  | MixedState ![Pkg.Name] ![(Pkg.Name, KeyId)]
  deriving (Show)
```

This is optional for the initial bootstrap but would improve diagnostics.

## Verification

### Unit Tests

**Existing tests in** `test/Unit/Builder/LockFileTest.hs` should already
cover the verification logic. Add:

1. **Test invalid signature is caught even with unsigned packages**:
   Create a lock file with one unsigned package and one package with a
   fake signature. Verify that `InvalidSignatures` is returned (not
   `UnsignedPackages`).

2. **Test empty key store returns UnsignedPackages**:
   With the placeholder key (which will fail to parse), verify that all
   packages are classified as unsigned.

3. **Test valid key lookup**:
   Generate a test Ed25519 key pair, add the public key to a test-only
   key store, sign a message, and verify the signature passes.

### Integration Test

Once the registry key is generated:

1. Sign a test package archive with the private key.
2. Create a lock file with the signature.
3. Run `canopy install --verify` and confirm the signature is accepted.
4. Tamper with the signature and confirm verification fails.

### Commands

```bash
# Build
stack build

# Run all tests
stack test

# Run verification-specific tests
stack test --ta="--pattern Verify"
stack test --ta="--pattern Signature"
stack test --ta="--pattern LockFile"

# Generate a test key pair
bash scripts/generate-signing-key.sh
```
