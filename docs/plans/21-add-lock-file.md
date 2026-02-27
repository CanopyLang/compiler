# Plan 21 — Add Lock File Support

**Priority:** Tier 4 (Ecosystem)
**Effort:** 3 days
**Risk:** Medium (new feature, requires careful design)
**Files:** ~6 new/modified files

---

## Problem

`canopy.json` records direct dependency versions but not a transitive dependency tree snapshot. Builds can drift across machines or over time if the registry resolves differently. Enterprise adoption requires deterministic builds.

## Design

### File Format: `canopy.lock`

JSON format, machine-generated, human-readable:

```json
{
  "lockfile-version": 1,
  "generated": "2026-02-27T12:00:00Z",
  "root": {
    "canopy.json-hash": "sha256:abc123..."
  },
  "packages": {
    "elm/core": {
      "version": "1.0.5",
      "hash": "sha256:def456...",
      "dependencies": {
        "elm/json": "1.1.3"
      }
    },
    "elm/html": {
      "version": "1.0.0",
      "hash": "sha256:789abc...",
      "dependencies": {
        "elm/core": "1.0.5",
        "elm/json": "1.1.3",
        "elm/virtual-dom": "1.0.3"
      }
    }
  }
}
```

### Behavior

1. **`canopy install`**: Resolves dependencies, writes `canopy.lock`
2. **`canopy make`**: If `canopy.lock` exists and `canopy.json` hash matches, use locked versions. If `canopy.json` changed, warn and suggest `canopy install`.
3. **`canopy install --update`**: Re-resolves all dependencies, updates `canopy.lock`
4. **No lock file**: Falls back to current behavior (resolve on the fly)

### Integrity

Each package entry includes a SHA-256 hash of the package archive. On install, the downloaded archive is verified against this hash. Mismatch = error, not silent corruption.

## Implementation

### Step 1: Define lock file types

```haskell
-- packages/canopy-builder/src/Builder/LockFile.hs (new)
module Builder.LockFile
  ( LockFile(..)
  , LockedPackage(..)
  , readLockFile
  , writeLockFile
  , isLockFileCurrent
  ) where

data LockFile = LockFile
  { _lockVersion :: !Int
  , _lockGenerated :: !Text
  , _lockRootHash :: !HashValue  -- SHA-256 of canopy.json content
  , _lockPackages :: !(Map Pkg.Name LockedPackage)
  } deriving (Show)

data LockedPackage = LockedPackage
  { _lpVersion :: !V.Version
  , _lpHash :: !HashValue          -- SHA-256 of package archive
  , _lpDependencies :: !(Map Pkg.Name V.Version)
  } deriving (Show)
```

### Step 2: Generate lock file after dependency resolution

In the solver output path (after `Deps.Solver` succeeds), collect the full transitive closure with versions and hashes, then write `canopy.lock`:

```haskell
generateLockFile :: FilePath -> Map Pkg.Name V.Version -> IO ()
generateLockFile root resolvedDeps = do
  canopyJsonHash <- Hash.hashFile (root </> "canopy.json")
  packages <- traverse fetchPackageHash (Map.toList resolvedDeps)
  let lockFile = LockFile
        { _lockVersion = 1
        , _lockGenerated = currentTimeText
        , _lockRootHash = canopyJsonHash
        , _lockPackages = Map.fromList packages
        }
  writeLockFile (root </> "canopy.lock") lockFile
```

### Step 3: Read lock file during build

In `Compiler.hs`, before dependency resolution:

```haskell
-- If canopy.lock exists and is current, use locked versions
case readLockFile (root </> "canopy.lock") of
  Just lockFile | isLockFileCurrent lockFile canopyJsonHash ->
    useLocked lockFile
  _ ->
    resolveFromScratch  -- current behavior
```

### Step 4: Verify package integrity on download

In `Http.hs`, after downloading a package archive, verify against the locked hash:

```haskell
downloadAndVerify :: Pkg.Name -> LockedPackage -> IO (Either Error Archive)
downloadAndVerify pkg locked = do
  archive <- downloadArchive pkg (locked ^. lpVersion)
  let actualHash = Hash.hashBytes (archiveContent archive)
  if actualHash == locked ^. lpHash
    then pure (Right archive)
    else pure (Left (IntegrityMismatch pkg (locked ^. lpHash) actualHash))
```

### Step 5: Add to .gitignore guidance

Document that `canopy.lock` should be committed for applications and not committed for packages (same as npm/cargo convention).

### Step 6: Update CLI help

Add lock file info to `canopy install --help` and `canopy make --help`.

## Validation

```bash
make build && make test

# Manual test:
cd test-project
canopy install            # Should create canopy.lock
cat canopy.lock           # Should contain all transitive deps with hashes
canopy make src/Main.can  # Should use locked versions
# Modify canopy.json:
canopy make src/Main.can  # Should warn about stale lock file
canopy install            # Should update canopy.lock
```

## Acceptance Criteria

- `canopy install` creates `canopy.lock` with all transitive dependencies and SHA-256 hashes
- `canopy make` uses locked versions when lock file is current
- `canopy make` warns when `canopy.json` has changed but lock file hasn't
- Package integrity is verified against locked hashes on download
- `make build && make test` passes
