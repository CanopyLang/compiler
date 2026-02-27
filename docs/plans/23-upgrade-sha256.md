# Plan 23 — Upgrade SHA-1 to SHA-256 for Package Archives

**Priority:** Tier 4 (Security)
**Effort:** 1 day
**Risk:** Low (backward compatible — new hashes for new downloads)
**Files:** `packages/canopy-builder/src/Http.hs`, `packages/canopy-builder/src/Builder/Hash.hs`, `packages/canopy-builder/src/PackageCache.hs`

---

## Problem

Package archive integrity uses SHA-1 (`Data.Digest.Pure.SHA`). SHA-1 is collision-vulnerable (SHAttered attack, 2017) and deprecated for security use by NIST. While practical second-preimage attacks are not yet feasible, using SHA-1 for integrity checking is a known weakness that will draw scrutiny in any security audit.

## Implementation

### Step 1: Replace SHA-1 with SHA-256 in archive verification

In `Http.hs`, the archive download computes a hash incrementally:

```haskell
-- Before:
import qualified Data.Digest.Pure.SHA as SHA

hashArchive :: BSL.ByteString -> String
hashArchive = show . SHA.sha1

-- After:
import qualified Crypto.Hash.SHA256 as SHA256

hashArchive :: BS.ByteString -> HashValue
hashArchive = Hash.fromDigest . SHA256.hash
```

### Step 2: Update package cache format

If the package cache stores SHA-1 hashes, update to SHA-256. New packages get SHA-256 hashes. Old cached packages retain their existing hashes until re-downloaded.

### Step 3: Update custom-package-repository-config.json

Replace the `"hash": "generated"` placeholders with actual SHA-256 hashes of the package archives:

```bash
for pkg in core-packages/*/; do
  sha256sum "$pkg/..."
done
```

### Step 4: Update the dependency (if needed)

If the project currently uses `Data.Digest.Pure.SHA` for SHA-1, switch to `cryptohash-sha256` (already likely a transitive dependency) or `cryptonite` for SHA-256.

Check current dependency:

```bash
grep -r "sha\|SHA\|Digest\|Crypto" packages/canopy-builder/canopy-builder.cabal
```

## Validation

```bash
make build && make test
```

## Acceptance Criteria

- All new package archive hashes use SHA-256
- No new SHA-1 hash computations in the codebase
- `custom-package-repository-config.json` has real SHA-256 hashes, not `"generated"` placeholders
- `make build && make test` passes
