#!/bin/bash

# Test script for Canopy
# Usage: ./scripts/test.sh [options]

set -e

# Default values
VERBOSE=false
COVERAGE=false
PATTERN=""
TIMEOUT=300
QUICK=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -c|--coverage)
      COVERAGE=true
      shift
      ;;
    -p|--pattern)
      PATTERN="$2"
      shift 2
      ;;
    -t|--timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    -q|--quick)
      QUICK=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  -v, --verbose     Verbose output"
      echo "  -c, --coverage    Generate coverage report"
      echo "  -p, --pattern     Run tests matching pattern"
      echo "  -t, --timeout     Timeout in seconds (default: 300)"
      echo "  -q, --quick       Quick mode (fewer property test cases)"
      echo "  -h, --help        Show this help"
      exit 0
      ;;
    *)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

# Build test arguments
TEST_ARGS=""

if [ "$VERBOSE" = true ]; then
  TEST_ARGS="$TEST_ARGS --verbose"
fi

if [ -n "$PATTERN" ]; then
  TEST_ARGS="$TEST_ARGS --pattern=$PATTERN"
fi

TEST_ARGS="$TEST_ARGS --timeout=${TIMEOUT}"

if [ "$QUICK" = true ]; then
  TEST_ARGS="$TEST_ARGS --quickcheck-tests=50"
fi

# Run tests
echo "Running Canopy tests..."
echo "Arguments: $TEST_ARGS"
echo ""

if [ "$COVERAGE" = true ]; then
  echo "Running with coverage..."
  stack test --coverage --test-arguments "$TEST_ARGS"
  echo ""
  echo "Coverage report generated in .stack-work/install/*/doc/*/hpc_index.html"
else
  stack test --test-arguments "$TEST_ARGS"
fi

echo ""
echo "Tests completed successfully!"