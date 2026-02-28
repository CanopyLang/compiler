# Plan 30: Package DAG Enforcement

## Priority: MEDIUM
## Effort: Small (4-8 hours)
## Risk: Low — build system guardrail

## Problem

The package dependency graph is a DAG (not a linear chain). From the .cabal files:

```
canopy-core        (no canopy dependencies — foundation)
canopy-query       depends on: canopy-core
canopy-driver      depends on: canopy-core, canopy-query
canopy-builder     depends on: canopy-core, canopy-query, canopy-driver
canopy-terminal    depends on: canopy-core, canopy-query, canopy-driver, canopy-builder
```

This DAG is currently enforced only by Cabal's dependency resolver. There's no CI check preventing someone from adding a reverse dependency (e.g., canopy-core depending on canopy-builder). Such a cycle would only be caught at build time with a confusing error.

## Implementation Plan

### Step 1: Add dependency validation script

**File**: `scripts/check-package-dag.sh` (NEW)

```bash
#!/bin/bash
set -e
# Verify the package DAG has no reverse dependencies.
# canopy-core is the foundation — must not depend on ANY other canopy package.

FAIL=0

check_no_dep() {
  local pkg=$1; shift
  for forbidden in "$@"; do
    if grep -q "build-depends:.*$forbidden" "packages/$pkg/$pkg.cabal"; then
      echo "VIOLATION: $pkg depends on $forbidden"
      FAIL=1
    fi
  done
}

check_no_dep canopy-core canopy-query canopy-driver canopy-builder canopy-terminal
check_no_dep canopy-query canopy-driver canopy-builder canopy-terminal
check_no_dep canopy-driver canopy-builder canopy-terminal
check_no_dep canopy-builder canopy-terminal

[ $FAIL -eq 0 ] && echo "Package DAG: OK" || exit 1
```

### Step 2: Add CI check

**File**: `.github/workflows/test.yml`

Add a step that runs the DAG validation before building:

```yaml
- name: Check package DAG
  run: bash scripts/check-package-dag.sh
```

### Step 3: Document the architecture

**File**: `docs/PACKAGE_ARCHITECTURE.md` (NEW)

Document the package dependency graph with rationale for each layer.

### Step 4: Add cabal-level constraints

In each package's `.cabal` file, explicitly document forbidden dependencies in comments:

```cabal
-- ARCHITECTURAL CONSTRAINT: canopy-core must NOT depend on
-- canopy-query, canopy-driver, canopy-builder, or canopy-terminal
```

## Dependencies
- None
