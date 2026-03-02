#!/usr/bin/env bash
# Check that HPC coverage meets the minimum threshold.
#
# Usage: ./scripts/check-coverage.sh [minimum-percentage]
#
# Reads the HPC coverage report from the most recent stack test --coverage
# run and verifies that expression coverage meets or exceeds the threshold.
# Exits 0 on pass, 1 on failure or if coverage cannot be determined.

set -euo pipefail

THRESHOLD="${1:-80}"

# Extract coverage percentage from HPC report
COVERAGE_OUTPUT=$(stack hpc report canopy:canopy-test 2>&1 || true)

COVERAGE=$(echo "$COVERAGE_OUTPUT" | \
  grep "expressions used" | \
  grep -oP '\d+(?=%)' | head -1 || true)

if [ -z "$COVERAGE" ]; then
  echo "ERROR: Could not extract coverage percentage from HPC report"
  echo ""
  echo "Make sure you have run 'make test-coverage' first."
  echo ""
  echo "Raw output:"
  echo "$COVERAGE_OUTPUT"
  exit 1
fi

echo "Coverage: ${COVERAGE}%  (threshold: ${THRESHOLD}%)"

if [ "$COVERAGE" -lt "$THRESHOLD" ]; then
  echo "FAIL: Coverage ${COVERAGE}% is below minimum ${THRESHOLD}%"
  echo ""
  echo "Modules below threshold:"
  echo "$COVERAGE_OUTPUT" | \
    grep -E "^\s+\d+%" | \
    awk -v thresh="$THRESHOLD" '{
      pct = $1+0;
      if (pct < thresh) print "  " $0
    }' || true
  exit 1
else
  echo "PASS: Coverage ${COVERAGE}% meets minimum ${THRESHOLD}%"
fi
