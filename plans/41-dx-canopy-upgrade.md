# Plan 41: Self-Update Command (`canopy upgrade`)

## Priority: LOW
## Effort: Medium (1-2 days)
## Risk: Medium — modifying own binary

## Problem

Users have no easy way to update the Canopy compiler. They must manually download and install new versions.

## Implementation Plan

### Step 1: Version check

**File**: `packages/canopy-terminal/src/Upgrade.hs` (NEW)

```haskell
module Upgrade (run, Flags(..)) where

data Flags = Flags
  { _upgradeCheck :: !Bool    -- Just check, don't upgrade
  , _upgradeForce :: !Bool    -- Upgrade even if current
  , _upgradeVersion :: !(Maybe Version)  -- Specific version
  }

run :: () -> Flags -> IO ()
run () flags = do
  current <- getCurrentVersion
  latest <- fetchLatestVersion
  case compare current latest of
    EQ -> reportUpToDate current
    LT -> performUpgrade current latest flags
    GT -> reportNewerThanLatest current latest
```

### Step 2: Fetch latest version info

```haskell
fetchLatestVersion :: IO (Either UpgradeError Version)
-- Check GitHub releases API or canopy-lang.org/releases
```

### Step 3: Download and replace binary

```haskell
performUpgrade :: Version -> Version -> Flags -> IO ()
performUpgrade current target flags = do
  binaryUrl <- platformBinaryUrl target
  tempPath <- downloadBinary binaryUrl
  verifyChecksum tempPath target
  replaceBinary tempPath
  reportSuccess current target
```

### Step 4: Platform detection

Detect OS and architecture for the correct binary:
- linux-x86_64
- darwin-x86_64
- darwin-aarch64
- windows-x86_64

### Step 5: Checksum verification

Verify downloaded binary against published SHA-256 checksum.

### Step 6: Tests

- Test version comparison logic
- Test platform detection
- Test checksum verification
- Test --check mode (no actual upgrade)

## Dependencies
- None
