# Plan 12: Test Coverage Enforcement with HPC

**Priority**: CRITICAL
**Effort**: Medium (2 days)
**Risk**: Low
**Audit Finding**: CLAUDE.md claims 80% minimum coverage but it's never measured or enforced; estimated actual coverage is 60-70%

---

## Problem

The codebase has 3,350 tests across 157 test modules, but:
1. No coverage measurement exists
2. No coverage threshold is enforced in CI
3. The 80% target in CLAUDE.md is aspirational, not verified
4. You can't manage what you don't measure

---

## Solution

Add HPC (Haskell Program Coverage) to the build system and enforce minimum coverage thresholds.

---

## Implementation

### Step 1: Add Coverage Target to Makefile

**File: `Makefile`**

```makefile
# Coverage with report generation
test-coverage:
	stack test --coverage --fast canopy:canopy-test
	stack hpc report canopy:canopy-test --destdir=coverage-report
	@echo "Coverage report: coverage-report/hpc_index.html"

# Coverage with threshold enforcement
test-coverage-check: test-coverage
	@./scripts/check-coverage.sh 80
```

### Step 2: Create Coverage Threshold Script

**File: `scripts/check-coverage.sh`**

```bash
#!/usr/bin/env bash
# Check that HPC coverage meets the minimum threshold.
# Usage: ./scripts/check-coverage.sh <minimum-percentage>

set -euo pipefail

THRESHOLD="${1:-80}"

# Extract coverage percentage from HPC report
COVERAGE=$(stack hpc report canopy:canopy-test 2>&1 | \
  grep "expressions used" | \
  grep -oP '\d+(?=%)' | head -1)

if [ -z "$COVERAGE" ]; then
  echo "ERROR: Could not extract coverage percentage from HPC report"
  exit 1
fi

echo "Coverage: ${COVERAGE}%  (threshold: ${THRESHOLD}%)"

if [ "$COVERAGE" -lt "$THRESHOLD" ]; then
  echo "FAIL: Coverage ${COVERAGE}% is below minimum ${THRESHOLD}%"
  echo ""
  echo "Modules below threshold:"
  stack hpc report canopy:canopy-test 2>&1 | \
    grep -E "^\s+\d+%" | \
    awk -v thresh="$THRESHOLD" '{
      pct = $1+0;
      if (pct < thresh) print "  " $0
    }'
  exit 1
else
  echo "PASS: Coverage ${COVERAGE}% meets minimum ${THRESHOLD}%"
fi
```

### Step 3: Per-Module Coverage Tracking

**File: `scripts/coverage-by-module.sh`**

```bash
#!/usr/bin/env bash
# Generate per-module coverage report.
# Identifies modules with zero or low coverage.

set -euo pipefail

echo "=== Per-Module Coverage Report ==="
echo ""

stack hpc report canopy:canopy-test 2>&1 | \
  grep -E "^[A-Z]" | \
  sort -t'%' -k1 -n | \
  while IFS= read -r line; do
    pct=$(echo "$line" | grep -oP '\d+(?=%)' | head -1)
    module=$(echo "$line" | awk '{print $NF}')
    if [ "$pct" -lt 50 ]; then
      echo "  CRITICAL: ${pct}% - ${module}"
    elif [ "$pct" -lt 80 ]; then
      echo "  WARNING:  ${pct}% - ${module}"
    else
      echo "  OK:       ${pct}% - ${module}"
    fi
  done
```

### Step 4: Add Coverage Badge Generation

**File: `scripts/coverage-badge.sh`**

```bash
#!/usr/bin/env bash
# Generate coverage badge for README.
set -euo pipefail

COVERAGE=$(stack hpc report canopy:canopy-test 2>&1 | \
  grep "expressions used" | \
  grep -oP '\d+(?=%)' | head -1)

if [ "$COVERAGE" -ge 90 ]; then
  COLOR="brightgreen"
elif [ "$COVERAGE" -ge 80 ]; then
  COLOR="green"
elif [ "$COVERAGE" -ge 70 ]; then
  COLOR="yellow"
elif [ "$COVERAGE" -ge 60 ]; then
  COLOR="orange"
else
  COLOR="red"
fi

echo "![Coverage](https://img.shields.io/badge/coverage-${COVERAGE}%25-${COLOR})"
```

### Step 5: Identify and Fill Coverage Gaps

After running initial coverage measurement, identify the lowest-covered modules and create targeted tests.

Expected low-coverage modules (based on test file distribution):
- `Type/Solve/Pool.hs` — complex solver internals
- `Generate/JavaScript/Expression/Case.hs` — decision tree generation
- `Optimize/DecisionTree.hs` — pattern match optimization
- `Canonicalize/Environment/*` — environment construction
- `Reporting/Error/*` — error formatting paths

For each under-covered module, add tests in the corresponding test directory:

```haskell
-- Example: test/Unit/Type/SolvePoolTest.hs
module Unit.Type.SolvePoolTest (tests) where

import qualified Type.Solve.Pool as Pool
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests = testGroup "Type.Solve.Pool"
  [ testCase "pool creation" $ ...
  , testCase "pool merge" $ ...
  , testCase "pool register" $ ...
  ]
```

### Step 6: CI Integration

Add coverage check to the existing CI/Makefile validation:

```makefile
# Full validation pipeline (used by CI)
validate: build test-coverage-check lint
	@echo "All validations passed"
```

---

## Validation

```bash
# Generate coverage report
make test-coverage

# Check threshold
make test-coverage-check

# Per-module breakdown
./scripts/coverage-by-module.sh
```

---

## Success Criteria

- [ ] `make test-coverage` generates HPC coverage report
- [ ] `make test-coverage-check` enforces 80% minimum threshold
- [ ] Per-module coverage report identifies low-coverage modules
- [ ] Coverage badge generated for documentation
- [ ] CI pipeline includes coverage check
- [ ] Overall coverage is >= 80%
- [ ] No module has 0% coverage
- [ ] `scripts/check-coverage.sh` is executable and works
