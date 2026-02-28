# Plan 17: Test Coverage Enforcement

## Priority: HIGH
## Effort: Small (2-4 hours)
## Risk: Low — CI configuration change

## Problem

`.github/workflows/test.yml` has coverage upload with `continue-on-error: true`, meaning coverage failures never block PRs. The 80% coverage target in CLAUDE.md is aspirational, not enforced.

### Current Code (.github/workflows/test.yml)

```yaml
- name: Upload coverage
  continue-on-error: true  # <-- NEVER fails the build
  run: ...
```

## Implementation Plan

### Step 1: Remove continue-on-error

**File**: `.github/workflows/test.yml`

```yaml
- name: Check coverage
  run: |
    stack test --coverage
    COVERAGE=$(stack hpc report --all 2>&1 | grep -oP '\d+%' | head -1 | tr -d '%')
    if [ "$COVERAGE" -lt 80 ]; then
      echo "Coverage $COVERAGE% is below 80% threshold"
      exit 1
    fi
```

### Step 2: Add per-package coverage thresholds

Different packages have different coverage needs:

```yaml
# Core compiler: 80% minimum
# Builder: 70% minimum (more IO-heavy)
# Terminal: 60% minimum (UI code)
```

### Step 3: Add coverage reporting to PR comments

Use a GitHub Action to post coverage summary as a PR comment with diff from main branch.

### Step 4: Add coverage badges to README

Generate and commit coverage badges for each package.

### Step 5: Identify current coverage gaps

Run `stack test --coverage` and generate a report listing modules below threshold. Prioritize writing tests for those modules.

## Dependencies
- None
