#!/usr/bin/env bash
#
# Test script for parallel compilation determinism
#
# This script verifies that parallel compilation produces identical
# output across multiple runs, which is critical for:
#
# 1. Reproducible builds
# 2. Build caching
# 3. Debugging consistency
#
# Usage:
#   ./scripts/test-parallel-determinism.sh [num-iterations]
#
# Default iterations: 10

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ITERATIONS=${1:-10}
BUILD_CMD="cabal build canopy-builder"
OUTPUT_DIR="canopy-stuff"
HASH_FILE="/tmp/canopy-determinism-hashes.txt"

echo "=================================================="
echo "Canopy Parallel Compilation Determinism Test"
echo "=================================================="
echo ""
echo "Testing ${ITERATIONS} iterations for deterministic output"
echo ""

# Clean previous hashes
rm -f "${HASH_FILE}"

# Function to compute hash of build artifacts
compute_build_hash() {
    local iteration=$1
    echo -n "Iteration ${iteration}: "

    # Clean build artifacts
    rm -rf "${OUTPUT_DIR}" dist-newstyle/.tmp

    # Build with parallel compilation (default uses +RTS -N)
    ${BUILD_CMD} > /dev/null 2>&1

    # Compute hash of all .canopyo and .canopyi files
    # Sort by filename to ensure consistent ordering
    local hash=$(find "${OUTPUT_DIR}" -type f \( -name "*.canopyo" -o -name "*.canopyi" \) -print0 | \
                 sort -z | \
                 xargs -0 sha256sum | \
                 sha256sum | \
                 awk '{print $1}')

    echo "${hash}" >> "${HASH_FILE}"
    echo "${hash}"

    return 0
}

# Run multiple builds and collect hashes
echo "Running ${ITERATIONS} builds..."
echo ""

for i in $(seq 1 ${ITERATIONS}); do
    compute_build_hash $i
done

echo ""
echo "--------------------------------------------------"
echo "Analyzing results..."
echo "--------------------------------------------------"

# Count unique hashes
UNIQUE_HASHES=$(sort "${HASH_FILE}" | uniq | wc -l)

if [ "${UNIQUE_HASHES}" -eq 1 ]; then
    echo -e "${GREEN}✓ SUCCESS${NC}: All ${ITERATIONS} builds produced identical output!"
    echo -e "${GREEN}✓ Parallel compilation is deterministic${NC}"
    echo ""
    echo "Build hash: $(head -n 1 ${HASH_FILE})"
    exit 0
else
    echo -e "${RED}✗ FAILURE${NC}: Found ${UNIQUE_HASHES} different hashes across ${ITERATIONS} builds"
    echo -e "${RED}✗ Parallel compilation is NOT deterministic${NC}"
    echo ""
    echo "Unique hashes:"
    sort "${HASH_FILE}" | uniq -c
    exit 1
fi
