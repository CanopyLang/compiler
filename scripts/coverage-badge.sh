#!/usr/bin/env bash
# Generate a coverage badge URL for documentation.
#
# Usage: ./scripts/coverage-badge.sh
#
# Outputs a shields.io markdown badge with color coding:
# - brightgreen: 90%+
# - green: 80-89%
# - yellow: 70-79%
# - orange: 60-69%
# - red: <60%

set -euo pipefail

COVERAGE_OUTPUT=$(stack hpc report canopy:canopy-test 2>&1 || true)

COVERAGE=$(echo "$COVERAGE_OUTPUT" | \
  grep "expressions used" | \
  grep -oP '\d+(?=%)' | head -1 || true)

if [ -z "$COVERAGE" ]; then
  echo "ERROR: Could not extract coverage percentage from HPC report"
  echo "Make sure you have run 'make test-coverage' first."
  exit 1
fi

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
