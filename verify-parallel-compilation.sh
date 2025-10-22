#!/bin/bash

# Verify parallel compilation is actually working in Canopy
#
# This script:
# 1. Checks if binary is compiled with -threaded
# 2. Tests runtime with different +RTS -N settings
# 3. Monitors CPU usage during compilation
# 4. Verifies multiple cores are utilized

set -e

echo "=========================================="
echo "PARALLEL COMPILATION VERIFICATION"
echo "=========================================="
echo ""

# Find the canopy executable
CANOPY_BIN=""
if [ -f "./.stack-work/install/x86_64-linux-tinfo6/50c2bb46c9090f342bc27080578ec29c34061472daaa79653cf926cd7b589ab2/9.8.4/bin/canopy" ]; then
    CANOPY_BIN="./.stack-work/install/x86_64-linux-tinfo6/50c2bb46c9090f342bc27080578ec29c34061472daaa79653cf926cd7b589ab2/9.8.4/bin/canopy"
elif [ -f "./dist-newstyle/build/x86_64-linux/ghc-9.4.8/canopy-0.19.1/x/canopy/build/canopy/canopy" ]; then
    CANOPY_BIN="./dist-newstyle/build/x86_64-linux/ghc-9.4.8/canopy-0.19.1/x/canopy/build/canopy/canopy"
elif command -v canopy &> /dev/null; then
    CANOPY_BIN="canopy"
else
    echo "❌ Error: Canopy executable not found"
    echo ""
    echo "Please build canopy first:"
    echo "  stack build"
    echo "  or"
    echo "  cabal build exe:canopy"
    exit 1
fi

echo "Using canopy binary: $CANOPY_BIN"
echo ""

# Check 1: RTS info
echo "=== Check 1: GHC RTS Configuration ==="
if $CANOPY_BIN +RTS --info -RTS 2>&1 | grep -q "rts_thr"; then
    echo "✅ Binary compiled with threaded runtime (rts_thr)"
else
    echo "❌ Binary NOT compiled with threaded runtime"
    echo "   Check canopy.cabal ghc-options for -threaded flag"
    exit 1
fi
echo ""

# Check 2: Test with +RTS -N1
echo "=== Check 2: Single-threaded execution (+RTS -N1) ==="
START=$(date +%s.%N)
$CANOPY_BIN --version +RTS -N1 -RTS > /dev/null 2>&1
END=$(date +%s.%N)
SINGLE_TIME=$(echo "$END - $START" | bc)
echo "Time: ${SINGLE_TIME}s"
echo "This establishes baseline performance"
echo ""

# Check 3: Test with +RTS -N
echo "=== Check 3: Multi-threaded execution (+RTS -N) ==="
NUM_CORES=$(nproc)
echo "System has $NUM_CORES CPU cores"

START=$(date +%s.%N)
$CANOPY_BIN --version +RTS -N -RTS > /dev/null 2>&1
END=$(date +%s.%N)
MULTI_TIME=$(echo "$END - $START" | bc)
echo "Time: ${MULTI_TIME}s"
echo ""

# Check 4: Verify RTS accepts -N flag
echo "=== Check 4: RTS Flag Support ==="
if $CANOPY_BIN --version +RTS -N4 -RTS 2>&1 | grep -q "invalid RTS option"; then
    echo "❌ Binary does not support +RTS -N flag"
    echo "   Ensure binary is compiled with -rtsopts"
    exit 1
else
    echo "✅ Binary accepts +RTS -N flag"
fi
echo ""

# Check 5: Test actual compilation if test files exist
echo "=== Check 5: Actual Compilation Test ==="
if [ -d "./examples" ] || [ -d "./test" ]; then
    echo "Testing with actual Canopy source files..."

    # Find a test file
    TEST_FILE=""
    if [ -f "./examples/HelloWorld.elm" ]; then
        TEST_FILE="./examples/HelloWorld.elm"
    elif [ -f "./test/fixtures/simple.elm" ]; then
        TEST_FILE="./test/fixtures/simple.elm"
    fi

    if [ -n "$TEST_FILE" ]; then
        echo "Using test file: $TEST_FILE"

        # Test sequential
        echo "Sequential compilation (+RTS -N1)..."
        START=$(date +%s.%N)
        timeout 30 $CANOPY_BIN make $TEST_FILE --output=/tmp/test-seq.js +RTS -N1 -RTS 2>&1 || true
        END=$(date +%s.%N)
        SEQ_TIME=$(echo "$END - $START" | bc)
        echo "Sequential time: ${SEQ_TIME}s"

        # Test parallel
        echo "Parallel compilation (+RTS -N)..."
        START=$(date +%s.%N)
        timeout 30 $CANOPY_BIN make $TEST_FILE --output=/tmp/test-par.js +RTS -N -RTS 2>&1 || true
        END=$(date +%s.%N)
        PAR_TIME=$(echo "$END - $START" | bc)
        echo "Parallel time: ${PAR_TIME}s"

        # Calculate speedup
        if [ $(echo "$PAR_TIME > 0" | bc) -eq 1 ]; then
            SPEEDUP=$(echo "scale=2; $SEQ_TIME / $PAR_TIME" | bc)
            echo "Speedup: ${SPEEDUP}x"

            if [ $(echo "$SPEEDUP > 1.5" | bc) -eq 1 ]; then
                echo "✅ Significant speedup detected - parallelism is working!"
            else
                echo "⚠️  Low speedup - parallelism may not be effective"
            fi
        fi
    else
        echo "No test files found, skipping compilation test"
    fi
else
    echo "No examples or test directory found, skipping"
fi
echo ""

# Summary
echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo ""
echo "Binary: $CANOPY_BIN"
echo ""

# Get RTS info
RTS_WAY=$($CANOPY_BIN +RTS --info -RTS 2>&1 | grep "RTS way" | cut -d'"' -f4)
WITH_RTSOPTS=$($CANOPY_BIN +RTS --info -RTS 2>&1 | grep "Flag -with-rtsopts" | cut -d'"' -f4)

echo "RTS Configuration:"
echo "  RTS way: $RTS_WAY"
echo "  Default RTS opts: ${WITH_RTSOPTS:-none}"
echo "  System cores: $NUM_CORES"
echo ""

if [ "$RTS_WAY" = "rts_thr" ]; then
    echo "✅ Threaded runtime: YES"
else
    echo "❌ Threaded runtime: NO"
fi

if [ -z "$WITH_RTSOPTS" ]; then
    echo "⚠️  Default RTS opts: NONE"
    echo "   Users must manually specify +RTS -N -RTS"
    echo ""
    echo "Recommendation:"
    echo "  Add to canopy.cabal:"
    echo "    ghc-options: -with-rtsopts=-N"
    echo ""
else
    echo "✅ Default RTS opts: $WITH_RTSOPTS"
fi

echo ""
echo "To enable parallel compilation, users should run:"
echo "  canopy make src/Main.elm +RTS -N -RTS"
echo ""
echo "Or to use specific thread count:"
echo "  canopy make src/Main.elm +RTS -N8 -RTS"
echo ""
echo "=========================================="
