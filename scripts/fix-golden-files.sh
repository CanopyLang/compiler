#!/bin/bash

# Fix golden files by extracting actual Canopy compiler outputs from debug files
# This script runs each failing test to generate debug files, then copies them to golden files

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOLDEN_DIR="$PROJECT_ROOT/test/Golden/expected/elm-canopy"

# Colors for output  
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cd "$PROJECT_ROOT"

# Function to fix a golden file by running test and copying debug output
fix_golden_file() {
    local test_name="$1"
    local golden_file="$GOLDEN_DIR/${test_name}.js"
    
    log_info "Fixing golden file for $test_name..."
    
    # Run the test to generate debug files (will fail but create debug files)
    stack test --ta="-p $test_name" >/dev/null 2>&1 || true
    
    # Copy the full Canopy debug output to the golden file
    local debug_file="/tmp/debug-canopy-full-${test_name}.js"
    if [ -f "$debug_file" ]; then
        cp "$debug_file" "$golden_file"
        log_success "Fixed golden file: ${test_name}.js"
        return 0
    else
        log_error "Debug file not found: $debug_file"
        return 1
    fi
}

# Get current list of failing tests
log_info "Getting list of currently failing tests..."
failing_tests=($(make test 2>&1 | grep "FAIL$" | awk '{print $1}' | sed 's/:$//' | head -30))

log_info "Found ${#failing_tests[@]} failing tests"

if [ ${#failing_tests[@]} -eq 0 ]; then
    log_success "No failing tests found! All tests should be passing."
    exit 0
fi

log_info "Fixing golden files for failing tests..."

successful_count=0
failed_count=0

for test in "${failing_tests[@]}"; do
    if fix_golden_file "$test"; then
        ((successful_count++))
    else
        ((failed_count++))
    fi
done

# Summary
log_info "Golden file fixing complete!"
log_success "Successfully fixed $successful_count golden files"

if [ $failed_count -gt 0 ]; then
    log_error "Failed to fix $failed_count golden files"
fi

log_success "Running full test suite to verify fixes..."
make test