# Plan 45: Package Publishing (`canopy publish`)

## Priority: MEDIUM
## Effort: Medium (2-3 days)
## Risk: Medium — needs registry coordination

## Problem

There's no `canopy publish` command for publishing packages to a registry. Package authors have no workflow for releasing their packages.

## Implementation Plan

### Step 1: Create publish command

**File**: `packages/canopy-terminal/src/Publish.hs` (NEW)

```haskell
module Publish (run, Flags(..)) where

data Flags = Flags
  { _publishDryRun :: !Bool
  , _publishRegistry :: !(Maybe Text)
  , _publishTag :: !(Maybe Text)
  }

run :: () -> Flags -> IO ()
run () flags = do
  outline <- Outline.read "."
  validateForPublish outline
  pkg <- buildPackageArchive outline
  if _publishDryRun flags
    then reportDryRun pkg
    else uploadPackage flags pkg
```

### Step 2: Pre-publish validation

Before publishing, verify:
- canopy.json has required package fields (name, version, license, summary)
- All exposed modules compile without errors
- Documentation builds successfully
- Version hasn't already been published
- No uncommitted changes in git
- Git tag matches package version

### Step 3: Archive creation

Create a reproducible tarball of the package:
- Include only source files, canopy.json, LICENSE, README
- Exclude canopy-stuff/, node_modules/, .git/
- Compute SHA-256 hash of archive

### Step 4: Registry upload

Upload the archive to the configured registry with authentication.

### Step 5: Post-publish actions

- Create git tag for the version
- Update local cache with published version
- Print success message with package URL

### Step 6: Tests

- Test pre-publish validation
- Test archive creation (correct files included/excluded)
- Test dry-run mode
- Test version conflict detection

## Dependencies
- Plan 01 (package signing) for archive signing
- Plan 11 (private registry) for registry selection
