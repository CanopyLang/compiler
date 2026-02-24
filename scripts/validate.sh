#!/bin/bash
# Canopy Validation Script
# Full validation suite with clear PASS/FAIL output
# Exit Code: 0 = PASS, 1 = FAIL

set -e

echo "╔══════════════════════════════════════════╗"
echo "║     CANOPY VALIDATION SUITE              ║"
echo "╚══════════════════════════════════════════╝"
echo ""

FAIL=0
START_TIME=$(date +%s)

# Step 1: Build
echo "▶ [1/3] Building compiler..."
if make build > /tmp/canopy-build.log 2>&1; then
    echo "  ✓ BUILD: PASS"
else
    echo "  ✗ BUILD: FAIL"
    cat /tmp/canopy-build.log | tail -20
    FAIL=1
fi

# Step 2: Test
echo "▶ [2/3] Running tests..."
if make test > /tmp/canopy-test.log 2>&1; then
    # Extract test summary
    TESTS_PASSED=$(grep -o "[0-9]* tests passed" /tmp/canopy-test.log | tail -1 || echo "")
    echo "  ✓ TEST: PASS ($TESTS_PASSED)"
else
    echo "  ✗ TEST: FAIL"
    cat /tmp/canopy-test.log | tail -30
    FAIL=1
fi

# Step 3: Lint (warnings only, don't fail on lint)
echo "▶ [3/3] Checking lint..."
if make lint > /tmp/canopy-lint.log 2>&1; then
    echo "  ✓ LINT: PASS"
else
    LINT_WARNINGS=$(grep -c "warning:" /tmp/canopy-lint.log 2>/dev/null || echo "0")
    echo "  ⚠ LINT: $LINT_WARNINGS warnings (non-blocking)"
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "══════════════════════════════════════════"
echo "Duration: ${DURATION}s"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "╔══════════════════════════════════════════╗"
    echo "║  ✓ VALIDATION COMPLETE: ALL CHECKS PASS ║"
    echo "╚══════════════════════════════════════════╝"
    exit 0
else
    echo "╔══════════════════════════════════════════╗"
    echo "║  ✗ VALIDATION FAILED: SEE ERRORS ABOVE  ║"
    echo "╚══════════════════════════════════════════╝"
    exit 1
fi
