# Plan 01: Cryptographic Package Signing & Verification

## Priority: CRITICAL
## Effort: Large (3-5 days)
## Risk: High — current signing infrastructure is a skeleton with no actual crypto

## Problem

`Builder.LockFile` defines `PackageSignature` with `_sigKeyId` and `_sigValue` fields, and `verifyPackageSignatures` checks only whether signatures are *present* — it never verifies cryptographic validity. This is security theater.

### Current Code (packages/canopy-builder/src/Builder/LockFile.hs)

```haskell
-- Lines 437-455: Only checks presence, not validity
verifyPackageSignatures :: LockFile -> SignatureResult
verifyPackageSignatures lf =
  let packages = Map.toList (_lockPackages lf)
      (unsigned, signed) = partitionSignatures packages
   in classifySignatures unsigned signed

classifySignatures :: [Pkg.Name] -> [(Pkg.Name, PackageSignature)] -> SignatureResult
classifySignatures [] _ = AllSigned  -- <-- NEVER checks actual signatures!
classifySignatures unsigned _ = UnsignedPackages unsigned
```

## Implementation Plan

### Step 1: Add ed25519 dependency

**File**: `packages/canopy-builder/canopy-builder.cabal`

Add `ed25519` or `crypton` to build-depends. The `crypton` package is preferred as it's more actively maintained and provides Ed25519 via `Crypto.PubKey.Ed25519`.

### Step 2: Create Crypto.Signature module

**File**: `packages/canopy-builder/src/Crypto/Signature.hs` (NEW)

- Define `PublicKey`, `Signature` newtypes wrapping raw bytes
- `verifyEd25519 :: PublicKey -> ByteString -> Signature -> Bool`
- `parsePublicKeyHex :: Text -> Either CryptoError PublicKey`
- `parseSignatureHex :: Text -> Either CryptoError Signature`
- Use constant-time comparison for all crypto operations

### Step 3: Create trusted key registry

**File**: `packages/canopy-builder/src/Crypto/TrustedKeys.hs` (NEW)

- Embed the registry's public key as a compile-time constant
- Support key rotation via key ID lookup
- `lookupTrustedKey :: Text -> Maybe PublicKey`
- Initially ship with one hardcoded key; later support fetching from registry

### Step 4: Implement real signature verification

**File**: `packages/canopy-builder/src/Builder/LockFile.hs`

Replace `classifySignatures` to actually verify:

```haskell
classifySignatures :: [Pkg.Name] -> [(Pkg.Name, PackageSignature)] -> SignatureResult
classifySignatures [] signed =
  let invalids = filter (not . verifySignature) signed
  in if null invalids then AllSigned
     else InvalidSignatures [(n, _sigKeyId s) | (n, s) <- invalids]
classifySignatures unsigned _ = UnsignedPackages unsigned

verifySignature :: (Pkg.Name, PackageSignature) -> Bool
verifySignature (pkg, sig) =
  case Crypto.lookupTrustedKey (_sigKeyId sig) of
    Nothing -> False
    Just pubKey -> Crypto.verifyEd25519 pubKey (packageBytes pkg) (parseSignatureHex (_sigValue sig))
```

### Step 5: Add signing to lock file generation

**File**: `packages/canopy-builder/src/Builder/LockFile.hs`

When generating lock files, if a signing key is available (e.g., from environment variable `CANOPY_SIGNING_KEY`), sign each package entry.

### Step 6: Add CLI flag for signature enforcement

**File**: `packages/canopy-terminal/src/CLI/Commands.hs`

Add `--require-signatures` flag to `build` and `install` commands that makes unsigned packages a hard error.

### Step 7: Tests

**File**: `test/Unit/Crypto/SignatureTest.hs` (NEW)

- Test key parsing (valid/invalid hex)
- Test signature verification with known test vectors
- Test key rotation (multiple key IDs)
- Test rejection of invalid signatures
- Test `--require-signatures` behavior

## Dependencies
- None (new capability)

## Risks
- Must not break existing lock files without signatures
- Key distribution is a bootstrapping problem (hardcode initially)
