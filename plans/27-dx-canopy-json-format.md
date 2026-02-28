# Plan 27: canopy.json Format Improvements

## Priority: MEDIUM
## Effort: Medium (1-2 days)
## Risk: Medium — must maintain backward compatibility with elm.json

## Problem

canopy.json is inherited from elm.json and has some friction points:
- No `"scripts"` field for custom build hooks
- No `"repository"` field for package metadata
- Direct/indirect dependency split confuses new users

Note: `AppOutline` already has `_appCanopy :: !Version.Version` for the Canopy/Elm version constraint. But there's no mechanism to CHECK this version against the running compiler, and no scripts/repository fields.

### Current AppOutline (packages/canopy-core/src/Canopy/Outline.hs, line 85):
```haskell
data AppOutline = AppOutline
  { _appCanopy :: !Version.Version
  , _appSrcDirs :: ![SrcDir]
  , _appDeps :: !(Map Pkg.Name Constraint.Constraint)
  , _appTestDeps :: !(Map Pkg.Name Constraint.Constraint)
  , _appDepsDirect :: !(Map Pkg.Name Version.Version)
  , _appDepsIndirect :: !(Map Pkg.Name Version.Version)
  , _appTestDepsDirect :: !(Map Pkg.Name Version.Version)
  }
```

## Implementation Plan

### Step 1: Add optional new fields

**File**: `packages/canopy-core/src/Canopy/Outline.hs`

Add optional fields that don't break elm.json compatibility:

```haskell
data AppOutline = AppOutline
  { ...existing fields...
  , _appScripts :: !(Maybe (Map Text Text))  -- Custom scripts
  , _appRepository :: !(Maybe Text)          -- Repository URL
  }
```

### Step 2: Support canopy.json alongside elm.json

When reading project config, check for `canopy.json` first, fall back to `elm.json`. When writing (e.g., `canopy install`), always write `canopy.json`.

### Step 3: Migration command

Add `canopy migrate` command that converts `elm.json` to `canopy.json`:
- Copies all fields
- Optionally merges direct/indirect deps into a flat list

### Step 4: Compiler version checking

Use the existing `_appCanopy` field to check at build time:

```
-- COMPILER VERSION MISMATCH

This project requires Canopy 0.19.2 but you have 0.19.1 installed.

To update: canopy upgrade
```

### Step 5: Scripts support

```json
{
    "scripts": {
        "prebuild": "node scripts/generate-types.js",
        "postbuild": "cp dist/main.js ../server/public/",
        "test": "canopy-test --reporter=json"
    }
}
```

### Step 6: Tests

- Test backward compatibility: elm.json still parses correctly
- Test new fields parse and serialize
- Test migration command
- Test compiler version checking
- Test scripts execution

## Dependencies
- None
