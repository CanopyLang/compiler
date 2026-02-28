# Plan 33: Dependency Audit Command

## Priority: MEDIUM
## Effort: Medium (1-2 days)
## Risk: Low — new command, no existing code changes

## Problem

There's no `canopy audit` command to check for known vulnerabilities in dependencies. Users must manually check each package version.

## Implementation Plan

### Step 1: Create audit command

**File**: `packages/canopy-terminal/src/Audit.hs` (NEW)

```haskell
module Audit (run, Flags(..)) where

data Flags = Flags
  { _auditJson :: !Bool     -- Output as JSON
  , _auditFix :: !Bool      -- Auto-fix where possible
  , _auditLevel :: !Level   -- Minimum severity to report
  }

data Level = Low | Medium | High | Critical

run :: () -> Flags -> IO ()
```

### Step 2: Create advisory database format

**File**: `packages/canopy-builder/src/Deps/Advisory.hs` (NEW)

```haskell
data Advisory = Advisory
  { _advisoryId :: !Text
  , _advisoryPackage :: !Pkg.Name
  , _advisoryVersionRange :: !Constraint
  , _advisorySeverity :: !Severity
  , _advisoryDescription :: !Text
  , _advisoryFixedIn :: !(Maybe Version)
  }
```

### Step 3: Fetch advisories from registry

Add an advisory endpoint to the registry protocol:
- `GET /advisories` — all known advisories
- Cache locally with TTL

### Step 4: Check project dependencies

Cross-reference project dependencies (from lock file) against advisories:

```
canopy audit

Found 2 vulnerabilities:

  HIGH  elm/http 2.0.0
        CVE-2026-1234: URL injection vulnerability
        Fixed in: 2.0.1
        Run: canopy install elm/http@2.0.1

  LOW   elm/json 1.1.3
        CVE-2026-5678: Excessive memory on deeply nested JSON
        Fixed in: 1.1.4
```

### Step 5: CI integration

- `canopy audit --level=high` — fail on high/critical only
- `canopy audit --json` — machine-readable for CI pipelines

### Step 6: Tests

- Test advisory matching against lock file
- Test severity filtering
- Test JSON output format
- Test --fix behavior

## Dependencies
- Plan 14 (newtypes) for Advisory types
