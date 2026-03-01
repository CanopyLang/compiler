# Plan 02: Package Download Hash Verification

**Priority:** CRITICAL
**Effort:** Small (≤8 hours)
**Risk:** Low

## Problem

Downloaded package archives are never verified against their registry-provided hash. The `EndpointResponse` type in `PackageCache/Fetch.hs` parses `_epHash` from the registry's `endpoint.json` but discards it immediately (line 257). The `IntegrityCheckFailed` error constructor exists (line 98) but is never constructed. A MITM attacker or compromised CDN could substitute packages with arbitrary content.

## Files to Modify

### `packages/canopy-builder/src/PackageCache/Fetch.hs`

**Current code (lines 247–258):**
```haskell
parseEndpointResponse bs =
  maybe
    (Left (RegistryUnavailable "Invalid endpoint.json response"))
    (\ep -> Right (FetchedRegistry (_epUrl ep)))  -- _epHash DISCARDED
    (Json.decode (LBS.fromStrict bs))
```

**Required changes:**

1. Change `FetchedRegistry` to carry the hash: update the `FetchResult` type to include the expected hash
2. After downloading the archive from `_epUrl`, compute `SHA256.hash archiveBytes`
3. Compare computed hash against `_epHash` using `Crypto.ConstantTime.secureCompareBS`
4. If mismatch, return `Left (IntegrityCheckFailed pkg ver expectedHash actualHash)`
5. If match, proceed with archive extraction

**Specific implementation:**

In `fetchViaEndpoint` (around lines 247–258):
```haskell
-- After fetching archive bytes from the endpoint URL:
let actualHash = SHA256.hash archiveBytes
    expectedHash = Text.encodeUtf8 (_epHash endpointResponse)
unless (ConstantTime.secureCompareBS actualHash expectedHash)
  (Left (IntegrityCheckFailed ...))
```

### `packages/canopy-builder/src/Builder/LockFile/Generate.hs`

Store verified hashes in lock file entries so subsequent builds can verify cached packages without re-downloading.

### Dependencies

Add `crypton` or `cryptonite` to `canopy-builder` build-depends if not already present (check if `Crypto.Signature` already brings it in).

## What NOT to Change

- GitHub fallback path (`fetchFromGitHub`) — accept without hash verification but log a warning, since GitHub ZIPs don't have a registry-provided hash
- Lock file verification in `LockFile/Verify.hs` — already works correctly for post-fetch verification

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Add unit test: construct a `FetchResult` with wrong hash, verify `IntegrityCheckFailed` is returned
4. Add unit test: construct a `FetchResult` with correct hash, verify success
