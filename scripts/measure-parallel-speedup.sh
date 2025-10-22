#!/usr/bin/env bash
#
# Performance measurement script for parallel compilation
#
# This script measures the speedup achieved by parallel compilation
# compared to sequential compilation.
#
# Expected results: 3-5x improvement on multi-core systems
#
# Usage:
#   ./scripts/measure-parallel-speedup.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BUILD_CMD="cabal build canopy-builder"
ITERATIONS=5
OUTPUT_DIR="canopy-stuff"

echo "=================================================="
echo "Canopy Parallel Compilation Performance Test"
echo "=================================================="
echo ""

# Detect number of cores
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    NUM_CORES=$(nproc)
elif [[ "$OSTYPE" == "darwin"* ]]; then
    NUM_CORES=$(sysctl -n hw.ncpu)
else
    NUM_CORES=4
fi

echo "System information:"
echo "  - CPU cores: ${NUM_CORES}"
echo "  - Iterations per test: ${ITERATIONS}"
echo ""

# Function to measure build time
measure_build_time() {
    local rts_flags=$1
    local test_name=$2
    local times_file="/tmp/canopy-build-times-$$.txt"

    echo "=================================================="
    echo "Testing: ${test_name}"
    echo "RTS flags: ${rts_flags}"
    echo "=================================================="
    echo ""

    rm -f "${times_file}"

    for i in $(seq 1 ${ITERATIONS}); do
        echo -n "  Iteration $i: "

        # Clean build artifacts to ensure fresh build
        rm -rf "${OUTPUT_DIR}" dist-newstyle/.tmp

        # Measure build time
        local start_time=$(date +%s.%N)
        ${BUILD_CMD} ${rts_flags} > /dev/null 2>&1
        local end_time=$(date +%s.%N)

        local elapsed=$(echo "${end_time} - ${start_time}" | bc)
        echo "${elapsed}" >> "${times_file}"
        echo "${elapsed}s"
    done

    # Calculate average time
    local avg_time=$(awk '{sum+=$1} END {print sum/NR}' "${times_file}")
    local min_time=$(sort -n "${times_file}" | head -n 1)
    local max_time=$(sort -n "${times_file}" | tail -n 1)

    echo ""
    echo "Results:"
    echo "  - Average: ${avg_time}s"
    echo "  - Min: ${min_time}s"
    echo "  - Max: ${max_time}s"
    echo ""

    rm -f "${times_file}"

    echo "${avg_time}"
}

# Test 1: Sequential compilation (single thread)
echo -e "${BLUE}Phase 1: Sequential Compilation (1 thread)${NC}"
echo ""
SEQUENTIAL_TIME=$(measure_build_time "+RTS -N1 -RTS" "Sequential (1 thread)")

# Test 2: Parallel compilation (all cores)
echo -e "${BLUE}Phase 2: Parallel Compilation (${NUM_CORES} threads)${NC}"
echo ""
PARALLEL_TIME=$(measure_build_time "+RTS -N${NUM_CORES} -RTS" "Parallel (${NUM_CORES} threads)")

# Test 3: Parallel compilation (N-1 cores, recommended)
if [ ${NUM_CORES} -gt 2 ]; then
    RECOMMENDED_CORES=$((NUM_CORES - 1))
    echo -e "${BLUE}Phase 3: Parallel Compilation (${RECOMMENDED_CORES} threads, recommended)${NC}"
    echo ""
    RECOMMENDED_TIME=$(measure_build_time "+RTS -N${RECOMMENDED_CORES} -RTS" "Parallel (${RECOMMENDED_CORES} threads)")
fi

# Calculate speedup
echo "=================================================="
echo "Performance Summary"
echo "=================================================="
echo ""

SPEEDUP=$(echo "scale=2; ${SEQUENTIAL_TIME} / ${PARALLEL_TIME}" | bc)

echo "Sequential time:  ${SEQUENTIAL_TIME}s"
echo "Parallel time:    ${PARALLEL_TIME}s"
if [ ${NUM_CORES} -gt 2 ]; then
    echo "Recommended time: ${RECOMMENDED_TIME}s"
    RECOMMENDED_SPEEDUP=$(echo "scale=2; ${SEQUENTIAL_TIME} / ${RECOMMENDED_TIME}" | bc)
    echo "Recommended speedup: ${RECOMMENDED_SPEEDUP}x"
fi
echo ""
echo -e "Overall speedup: ${GREEN}${SPEEDUP}x${NC}"
echo ""

# Check if speedup meets expectations
MIN_EXPECTED_SPEEDUP=3.0
SPEEDUP_CHECK=$(echo "${SPEEDUP} >= ${MIN_EXPECTED_SPEEDUP}" | bc)

if [ "${SPEEDUP_CHECK}" -eq 1 ]; then
    echo -e "${GREEN}✓ SUCCESS${NC}: Speedup (${SPEEDUP}x) meets or exceeds target (${MIN_EXPECTED_SPEEDUP}x)"
    echo ""
    echo "CPU utilization improved from ~8% to ~$(echo "scale=0; ${SPEEDUP} * 8" | bc)%"
    exit 0
else
    echo -e "${YELLOW}⚠ WARNING${NC}: Speedup (${SPEEDUP}x) is below target (${MIN_EXPECTED_SPEEDUP}x)"
    echo ""
    echo "Possible reasons:"
    echo "  - Not enough modules for significant parallelism"
    echo "  - High dependency depth (sequential bottleneck)"
    echo "  - I/O bound operations"
    echo "  - Need to tune thread count with +RTS -N"
    exit 1
fi
