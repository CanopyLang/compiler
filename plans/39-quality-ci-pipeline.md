# Plan 39: CI Pipeline Hardening

## Priority: HIGH
## Effort: Medium (1-2 days)
## Risk: Low — CI configuration only

## Problem

The CI pipeline has several gaps:
- Coverage enforcement is non-blocking (`continue-on-error: true`)
- No benchmark regression detection
- No package DAG validation
- No lint check
- No format check
- No security audit step
- No artifact size tracking

## Implementation Plan

### Step 1: Add mandatory checks

**File**: `.github/workflows/test.yml`

```yaml
jobs:
  build:
    steps:
      - name: Build
        run: make build

      - name: Test
        run: make test

      - name: Lint (hlint)
        run: make lint

      - name: Format check
        run: make format-check

      - name: Package DAG validation
        run: bash scripts/check-package-dag.sh

      - name: Coverage check
        run: |
          make test-coverage
          # Fail if below threshold

      - name: Artifact size check
        run: |
          SIZE=$(stat -c%s $(stack path --local-install-root)/bin/canopy)
          echo "Binary size: $SIZE bytes"
          if [ "$SIZE" -gt 50000000 ]; then
            echo "Binary exceeds 50MB threshold"
            exit 1
          fi
```

### Step 2: Add benchmark CI

**File**: `.github/workflows/bench.yml` (NEW)

```yaml
on:
  pull_request:
    branches: [master]

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - name: Run benchmarks
        run: make bench
      - name: Compare with baseline
        run: scripts/compare-bench.sh
```

### Step 3: Add security scan

```yaml
      - name: Security audit
        run: |
          # Check for unsafe patterns
          ! grep -r "unsafePerformIO" packages/ --include="*.hs" | grep -v NOINLINE
          # Check for hardcoded secrets
          ! grep -rE "(password|secret|token)\s*=" packages/ --include="*.hs"
```

### Step 4: Add release build validation

**File**: `.github/workflows/release.yml` (NEW or update)

For release builds:
- Build all platforms (Linux, macOS, Windows)
- Run full test suite on each platform
- Generate and upload binaries
- Generate documentation

### Step 5: Branch protection rules

Document recommended GitHub branch protection:
- Require all CI checks to pass
- Require at least 1 review
- Require up-to-date branch
- No force pushes to master

## Dependencies
- Plan 17 (coverage enforcement)
- Plan 19 (benchmarks)
- Plan 30 (package DAG enforcement)
