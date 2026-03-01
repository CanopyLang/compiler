# Plan 03: Trusted Key Store Population

**Priority:** CRITICAL
**Effort:** Small (≤8 hours)
**Risk:** Low

## Problem

The trusted key store is empty (`trustedKeys = Map.empty` at `Crypto/TrustedKeys.hs:88`), making the entire Ed25519 signature verification pipeline dead code. Every package is classified as `UnsignedPackages` and silently accepted. `InvalidSignatures` only produces a warning, not an error.

## Files to Modify

### `packages/canopy-builder/src/Crypto/TrustedKeys.hs`

1. Either populate `trustedKeys` with the registry's actual Ed25519 public key, OR:
2. If no registry key exists yet, add a `--require-signatures` CLI flag and make the default behavior explicit

### `packages/canopy-terminal/src/Install/Execution.hs`

**Current code (lines 321–328):**
```haskell
verifySignatures lf =
  case LockFile.verifyPackageSignatures lf of
    LockFile.AllSigned -> pure ()
    LockFile.UnsignedPackages _ -> pure ()    -- SILENTLY IGNORES
    LockFile.InvalidSignatures invalids -> do
      Print.printErrLn ...                     -- ONLY WARNS
```

**Required changes:**
1. `UnsignedPackages` — print an informational message (not silent)
2. `InvalidSignatures` — make this a hard error that aborts installation
3. Add `--no-verify` CLI flag to explicitly opt out of signature checking

### CLI Integration

Add flags to the install command in `CLI/Commands/Package.hs`:
- `--require-signatures` — fail if any package is unsigned
- `--no-verify` — skip all signature verification (explicit opt-out)

## Alternative Approach (if no registry key exists)

If the Canopy package registry doesn't yet have a signing key:
1. Remove the dead crypto code entirely (TrustedKeys.hs, parts of Signature.hs)
2. Replace with a clear TODO that links to a tracking issue
3. Make `verifySignatures` a no-op with an explicit comment explaining why
4. This is better than pretending verification exists when it doesn't

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Verify that `UnsignedPackages` produces visible output (not silent)
4. Verify that `InvalidSignatures` aborts installation
