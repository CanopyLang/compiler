# Plan 01: GitHub Fallback Hash Verification

- **Priority**: CRITICAL
- **Effort**: Small (4-6h)
- **Risk**: Low

## Problem

When a package is downloaded via the GitHub fallback path (the last-resort source
after the registry is unavailable), the archive is accepted without any hash
verification. This means a compromised GitHub account, DNS hijack, or
man-in-the-middle attack could serve a malicious archive that would be silently
accepted and installed.

The registry path already performs SHA-256 verification with constant-time
comparison. The GitHub path does not.

### Current Code

**File**: `/home/quinten/fh/canopy/packages/canopy-builder/src/PackageCache/Fetch.hs`

At lines 423-430, `fetchFromGitHub` downloads the ZIP but discards the bytes
entirely -- it never computes or checks a hash:

```haskell
fetchFromGitHub :: Client.Manager -> Pkg.Name -> Version.Version -> IO (Either FetchError FetchSource)
fetchFromGitHub manager pkg ver = do
  let zipUrl = gitHubZipUrl pkg ver
  Log.logEvent (PackageOperation "github-fetch" (Text.pack zipUrl))
  result <- safeHttpGet manager zipUrl
  pure (either (Left . GitHubUnavailable) (handleGitHubSuccess zipUrl) result)
  where
    handleGitHubSuccess url _bytes = Right (FetchedGitHub (Text.pack url))
```

Note `_bytes` is explicitly ignored.

Contrast with the registry path at lines 342-350, which computes SHA-256 and
uses constant-time comparison:

```haskell
verifyAndReturn :: Pkg.Name -> Version.Version -> EndpointResponse -> ByteString -> Either FetchError FetchSource
verifyAndReturn pkg ver ep archiveBytes =
  case verifyArchiveHash (_epHash ep) archiveBytes of
    True -> Right (FetchedRegistry (_epUrl ep) (_epHash ep))
    False -> Left (IntegrityCheckFailed (buildMismatchMessage pkg ver (_epHash ep) actualHashText))
  where
    actualHashText = computeSha256Hex archiveBytes
```

### How Lock Files Store Hashes

**File**: `/home/quinten/fh/canopy/packages/canopy-builder/src/Builder/LockFile/Types.hs`

The `LockedPackage` type (line 185) has an `_lpHash :: !ContentHash` field.
`ContentHash` (line 81) is a newtype wrapping `Text` with a `"sha256:"` prefix.

When lock files exist, the hash of previously-downloaded packages is available.
When no lock file exists (fresh install), there is no pre-existing hash to
verify against -- but we can still compute and store the hash for future
verification.

### The Two Scenarios

1. **Lock file exists with a hash for this package**: The GitHub fallback should
   compute SHA-256 of the downloaded bytes and compare against the lock file
   hash. Mismatch = hard error.

2. **No lock file / package not in lock file**: Accept the download, compute
   its hash, and emit a warning that the archive was accepted without
   verification. The hash will be stored in the lock file for future runs.

## Files to Modify

### 1. `PackageCache/Fetch.hs` (lines 423-430)

**Change**: Thread the lock file hash (if available) into `fetchFromGitHub` and
verify the downloaded bytes.

**Current signature**:
```haskell
fetchFromGitHub :: Client.Manager -> Pkg.Name -> Version.Version -> IO (Either FetchError FetchSource)
```

**Proposed signature**:
```haskell
fetchFromGitHub :: Client.Manager -> Pkg.Name -> Version.Version -> Maybe Text.Text -> IO (Either FetchError FetchSource)
```

The `Maybe Text.Text` parameter is the expected SHA-256 hash from the lock file
(without the `"sha256:"` prefix). When `Just`, verification is mandatory. When
`Nothing`, the hash is computed and returned in `FetchedGitHub` for storage.

**Proposed `FetchedGitHub` change** (line 101):

```haskell
-- Current:
FetchedGitHub !Text.Text
-- Proposed:
FetchedGitHub !Text.Text !Text.Text  -- URL and computed SHA-256 hash
```

**Proposed `fetchFromGitHub` body**:

```haskell
fetchFromGitHub manager pkg ver expectedHash = do
  let zipUrl = gitHubZipUrl pkg ver
  Log.logEvent (PackageOperation "github-fetch" (Text.pack zipUrl))
  result <- safeHttpGet manager zipUrl
  pure (either (Left . GitHubUnavailable) (verifyGitHubArchive pkg ver zipUrl expectedHash) result)
```

New helper:

```haskell
verifyGitHubArchive :: Pkg.Name -> Version.Version -> String -> Maybe Text.Text -> ByteString -> Either FetchError FetchSource
verifyGitHubArchive pkg ver url expectedHash archiveBytes =
  maybe
    (Right (FetchedGitHub (Text.pack url) actualHash))
    (verifyExpectedHash pkg ver (Text.pack url) actualHash)
    expectedHash
  where
    actualHash = computeSha256Hex archiveBytes

verifyExpectedHash :: Pkg.Name -> Version.Version -> Text.Text -> Text.Text -> Text.Text -> Either FetchError FetchSource
verifyExpectedHash pkg ver url actualHash expected
  | ConstantTime.secureCompareBS (TextEnc.encodeUtf8 expected) (TextEnc.encodeUtf8 actualHash) =
      Right (FetchedGitHub url actualHash)
  | otherwise =
      Left (IntegrityCheckFailed (buildMismatchMessage pkg ver expected actualHash))
```

### 2. `PackageCache/Fetch.hs` -- `fetchFromNetwork` (line 293)

**Change**: Thread the expected hash through to the GitHub fallback call.

```haskell
-- Current:
fetchFromNetwork :: Client.Manager -> Pkg.Name -> Version.Version -> IO (Either FetchError FetchSource)
-- Proposed:
fetchFromNetwork :: Client.Manager -> Pkg.Name -> Version.Version -> Maybe Text.Text -> IO (Either FetchError FetchSource)
```

### 3. `PackageCache/Fetch.hs` -- `fetchPackage` (line 199)

**Change**: Accept the expected hash and pass it through.

```haskell
-- Current:
fetchPackage :: Client.Manager -> Pkg.Name -> Version.Version -> IO (Either FetchError FetchSource)
-- Proposed:
fetchPackage :: Client.Manager -> Pkg.Name -> Version.Version -> Maybe Text.Text -> IO (Either FetchError FetchSource)
```

### 4. All callers of `fetchPackage`

Search for callers and thread the lock file hash from the `LockedPackage`
when available. The hash stored in `_lpHash` has the `"sha256:"` prefix, so
strip it before passing:

```haskell
extractRawHash :: ContentHash -> Maybe Text.Text
extractRawHash (ContentHash t) = Text.stripPrefix "sha256:" t
```

### 5. Update `FetchedGitHub` pattern matches

All pattern matches on `FetchedGitHub` need updating for the additional
hash field. Search the codebase:

```
grep -rn "FetchedGitHub" packages/ test/
```

## Verification

### Unit Tests

Add tests in the existing `test/Unit/VendorTest.hs` or a new
`test/Unit/PackageCache/FetchTest.hs`:

1. **Test hash match succeeds**: Given a `Just expectedHash` that matches the
   computed hash, verify `verifyGitHubArchive` returns `Right FetchedGitHub`.

2. **Test hash mismatch fails**: Given a `Just expectedHash` that does NOT
   match, verify `verifyGitHubArchive` returns `Left IntegrityCheckFailed`.

3. **Test no expected hash**: Given `Nothing`, verify
   `verifyGitHubArchive` returns `Right FetchedGitHub` with the computed hash.

4. **Test constant-time comparison is used**: Verify the code path calls
   `ConstantTime.secureCompareBS` (can be checked via code review since
   mocking crypto primitives is not meaningful).

### Commands

```bash
# Build
stack build

# Run all tests
stack test

# Run fetch-specific tests
stack test --ta="--pattern Fetch"
```
