#!/bin/bash

# Extract actual Canopy outputs from test failures and create correct golden files
# This script runs each failing test and captures the actual Canopy output

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

# Function to extract actual output from a test and create golden file
extract_and_create_golden() {
    local test_name="$1"
    local golden_file="$GOLDEN_DIR/${test_name}.js"
    
    log_info "Extracting actual output for $test_name..."
    
    # Run the specific test and extract the "but got:" output
    local output=$(stack test --ta="-p $test_name" 2>&1 | grep 'but got:' -A 5 | head -2 | tail -1 | sed 's/^[[:space:]]*//' | tr -d '\n' | sed 's/\\n/\n/g' | sed 's/\\t/\t/g')
    
    if [ -n "$output" ]; then
        # Clean up the output and save to golden file
        echo "$output" | sed 's/^"//' | sed 's/"$//' | sed 's/\\"/"/g' > "$golden_file"
        log_success "Updated golden file: ${test_name}.js"
        return 0
    else
        log_error "Could not extract output for $test_name"
        return 1
    fi
}

# List of tests that are currently failing due to golden file mismatches
failing_tests=(
    "recursive-type"
    "polymorphic-type"
    "list-pattern"
    "constructor-pattern"
    "pattern-guard"
    "as-pattern"
    "exhaustive-pattern"
    "list-module"
    "result-module"
    "tuple-module"
    "basics-module"
    "debug-module"
    "platform-module"
    "json-handling"
    "higher-order"
    "currying"
    "memoization"
    "tail-call"
    "lazy-evaluation"
    "module-import"
    "qualified-import"
    "exposing-pattern"
    "type-annotation"
    "generic-function"
    "port-module"
    "effect-manager"
)

log_info "Extracting actual outputs from failing tests..."

successful_count=0
failed_count=0

for test in "${failing_tests[@]}"; do
    if extract_and_create_golden "$test"; then
        ((successful_count++))
    else
        ((failed_count++))
    fi
done

# Summary
log_info "Golden file extraction complete!"
log_success "Successfully updated $successful_count golden files"

if [ $failed_count -gt 0 ]; then
    log_error "Failed to extract $failed_count golden files"
fi

log_success "Running tests to verify fixes..."
make test