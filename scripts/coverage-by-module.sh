#!/usr/bin/env bash
# Generate per-module coverage report.
#
# Usage: ./scripts/coverage-by-module.sh
#
# Reads the HPC coverage report and categorizes each module by its
# coverage level: CRITICAL (<50%), WARNING (<80%), or OK (>=80%).
# Modules are sorted by coverage percentage ascending.

set -euo pipefail

echo "=== Per-Module Coverage Report ==="
echo ""

COVERAGE_OUTPUT=$(stack hpc report canopy:canopy-test 2>&1 || true)

OVERALL=$(echo "$COVERAGE_OUTPUT" | \
  grep "expressions used" | \
  grep -oP '\d+(?=%)' | head -1 || true)

if [ -z "$OVERALL" ]; then
  echo "ERROR: Could not extract coverage data from HPC report"
  echo "Make sure you have run 'make test-coverage' first."
  exit 1
fi

echo "Overall: ${OVERALL}%"
echo ""

# Parse module lines (format: "  NN% ModuleName")
echo "$COVERAGE_OUTPUT" | \
  grep -E "^\s+\d+%" | \
  sort -t'%' -k1 -n | \
  while IFS= read -r line; do
    pct=$(echo "$line" | grep -oP '\d+(?=%)' | head -1)
    module_name=$(echo "$line" | sed 's/^[[:space:]]*[0-9]*%[[:space:]]*//')
    if [ "$pct" -lt 50 ]; then
      printf "  CRITICAL: %3s%% - %s\n" "$pct" "$module_name"
    elif [ "$pct" -lt 80 ]; then
      printf "  WARNING:  %3s%% - %s\n" "$pct" "$module_name"
    else
      printf "  OK:       %3s%% - %s\n" "$pct" "$module_name"
    fi
  done

echo ""
echo "Legend: CRITICAL (<50%), WARNING (<80%), OK (>=80%)"
