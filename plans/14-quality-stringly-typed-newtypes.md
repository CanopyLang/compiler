# Plan 14: Replace Stringly-Typed Values with Newtypes

## Priority: MEDIUM
## Effort: Medium (1-2 days)
## Risk: Low — type-safe refactoring with compiler assistance

## Problem

`Builder/LockFile.hs` (packages/canopy-builder/src/Builder/LockFile.hs) uses raw `Text` for 5 semantically distinct values:
- `_lockGenerated :: !Text.Text` — ISO 8601 timestamp
- `_lockRootHash :: !Text.Text` — SHA-256 content hash with "sha256:" prefix
- `_lpHash :: !Text.Text` — SHA-256 package hash with "sha256:" prefix
- `_sigKeyId :: !Text.Text` — cryptographic key identifier
- `_sigValue :: !Text.Text` — hex-encoded signature value

Note: The non-Text fields already use strong types (`_lpVersion :: !Version.Version`, `_lockPackages :: !(Map Pkg.Name LockedPackage)`, etc.). The issue is limited to these 5 fields where Text values with different semantics could be swapped at the type level — e.g., passing a timestamp where a hash is expected compiles fine. This matters most in the verification pipeline where hash comparisons are security-critical.

## Implementation Plan

### Step 1: Define domain newtypes

**File**: `packages/canopy-builder/src/Builder/LockFile/Types.hs` (NEW)

```haskell
-- | SHA-256 hash with "sha256:" prefix.
newtype ContentHash = ContentHash { unContentHash :: Text }
  deriving (Eq, Ord, Show)

-- | ISO 8601 timestamp string.
newtype Timestamp = Timestamp { unTimestamp :: Text }
  deriving (Eq, Ord, Show)

-- | Cryptographic key identifier.
newtype KeyId = KeyId { unKeyId :: Text }
  deriving (Eq, Ord, Show)

-- | Hex-encoded cryptographic signature.
newtype SignatureValue = SignatureValue { unSignatureValue :: Text }
  deriving (Eq, Ord, Show)

-- Smart constructors with validation
mkContentHash :: Text -> Either String ContentHash
mkContentHash t
  | "sha256:" `Text.isPrefixOf` t = Right (ContentHash t)
  | otherwise = Left "Content hash must start with sha256:"

mkTimestamp :: Text -> Timestamp
mkTimestamp = Timestamp  -- Validated at parse time by ISO8601
```

### Step 2: Update LockFile types

**File**: `packages/canopy-builder/src/Builder/LockFile.hs`

```haskell
data LockFile = LockFile
  { _lockVersion :: !Int
  , _lockGenerated :: !Timestamp      -- was: Text
  , _lockRootHash :: !ContentHash     -- was: Text
  , _lockPackages :: !(Map Pkg.Name LockedPackage)
  }

data LockedPackage = LockedPackage
  { _lpVersion :: !Version.Version
  , _lpHash :: !ContentHash           -- was: Text
  , _lpDependencies :: !(Map Pkg.Name Version.Version)
  , _lpSignature :: !(Maybe PackageSignature)
  }

data PackageSignature = PackageSignature
  { _sigKeyId :: !KeyId               -- was: Text
  , _sigValue :: !SignatureValue       -- was: Text
  }
```

### Step 3: Update JSON instances

Update `ToJSON`/`FromJSON` instances to unwrap/wrap newtypes at the serialization boundary.

### Step 4: Update all usage sites

- `isLockFileCurrent`: Compare `ContentHash` values
- `generateLockFile`: Construct `Timestamp` and `ContentHash`
- `hashPackageConfig`: Return `ContentHash`
- `verifyPackageHashes`: Compare `ContentHash` values
- All callers in `Install/Execution.hs`

### Step 5: Update tests

**File**: `test/Unit/Builder/LockFileTest.hs`

Update test data to use new constructors:
```haskell
sampleLockFile = LockFile
  { _lockVersion = 1
  , _lockGenerated = Timestamp "2026-02-27T12:00:00Z"
  , _lockRootHash = ContentHash "sha256:abc123"
  , _lockPackages = samplePackages
  }
```

## Dependencies
- None (but Plan 01 and Plan 02 will also benefit from these types)
