#!/bin/bash
# Canopy Smoke Test Script
# Quick validation that completes in under 60 seconds
# Exit Code: 0 = PASS, 1 = FAIL

set -e

echo "╔══════════════════════════════════════════╗"
echo "║     CANOPY SMOKE TEST                    ║"
echo "╚══════════════════════════════════════════╝"
echo ""

START_TIME=$(date +%s)

# Quick build check (incremental, fast mode)
echo "▶ [1/2] Quick build check..."
if stack build --fast --no-run-tests 2>&1 | tail -3; then
    echo "  ✓ Build OK"
else
    echo "  ✗ Build FAILED"
    exit 1
fi

# Run unit tests only (fast)
echo "▶ [2/2] Running unit tests..."
if stack test --fast 2>&1 | tail -10; then
    echo "  ✓ Tests OK"
else
    echo "  ✗ Tests FAILED"
    exit 1
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "══════════════════════════════════════════"
echo "Duration: ${DURATION}s"
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  ✓ SMOKE TEST PASS                       ║"
echo "╚══════════════════════════════════════════╝"

exit 0
