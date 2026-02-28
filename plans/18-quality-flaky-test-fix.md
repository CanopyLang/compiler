# Plan 18: ~~Fix Flaky Logging.Sink Test~~ → Test Suite Reliability Audit

## Priority: MEDIUM
## Effort: Small (2-4 hours)
## Risk: Low — test improvements only

## Problem

~~Original claim: One test in the Logging.Sink test suite is flaky.~~

**Correction**: After verification, `test/Unit/Logging/SinkTest.hs` (134 lines) contains 5 clean test groups with no flaky indicators — no `threadDelay`, no timing sensitivity, no `xfail` markers. The flaky test claim was unsubstantiated.

However, there IS a legitimate issue: the CI workflow at `.github/workflows/test.yml` has `continue-on-error: true` on lines 57 (coverage report) and 64 (codecov upload) AND line 87 (hlint). This means lint failures and coverage failures never block merges.

## Revised Implementation Plan

### Step 1: Remove continue-on-error from hlint

**File**: `.github/workflows/test.yml` (line 87)

HLint failures should block merges. Remove `continue-on-error: true` from the HLint step.

### Step 2: Run full test suite in CI stress mode

Add a nightly CI job that runs the test suite multiple times to catch intermittent failures:

```yaml
- name: Test suite stress run
  run: |
    for i in 1 2 3; do
      stack test 2>&1 || exit 1
    done
```

### Step 3: Add test timing tracking

Record test execution times in CI to catch tests that are getting slower:

```yaml
- name: Run tests with timing
  run: stack test --ta="--time"
```

### Step 4: Audit all tests for timing sensitivity

Search for `threadDelay`, `timeout`, and similar patterns in test code. Any timing-dependent tests should use proper synchronization instead.

## Dependencies
- None
