#!/bin/bash

# Function to count lines in a function (excluding blank lines and comments)
count_function_lines() {
    local start_line=$1
    local end_line=$2
    local file=$3
    
    # Extract function lines and count non-blank, non-comment lines
    sed -n "${start_line},${end_line}p" "$file" | \
    grep -v '^[[:space:]]*--' | \
    grep -v '^[[:space:]]*$' | \
    wc -l
}

# Analyze builder/src/Generate.hs
file="builder/src/Generate.hs"
echo "=== Function Analysis for $file ==="
echo

# debug function (lines 116-124)
debug_lines=$(count_function_lines 116 124 "$file")
echo "debug function:"
echo "  Lines: $debug_lines (limit: 15)"
echo "  Parameters: 3 (limit: 4)"
if [ $debug_lines -gt 15 ]; then
    echo "  ❌ VIOLATION: Exceeds 15 line limit"
else
    echo "  ✅ COMPLIANT: Within 15 line limit"
fi
echo

# dev function (lines 160-166)
dev_lines=$(count_function_lines 160 166 "$file")
echo "dev function:"
echo "  Lines: $dev_lines (limit: 15)"
echo "  Parameters: 3 (limit: 4)"
if [ $dev_lines -gt 15 ]; then
    echo "  ❌ VIOLATION: Exceeds 15 line limit"
else
    echo "  ✅ COMPLIANT: Within 15 line limit"
fi
echo

# prod function (lines 207-214)
prod_lines=$(count_function_lines 207 214 "$file")
echo "prod function:"
echo "  Lines: $prod_lines (limit: 15)"
echo "  Parameters: 3 (limit: 4)"
if [ $prod_lines -gt 15 ]; then
    echo "  ❌ VIOLATION: Exceeds 15 line limit"
else
    echo "  ✅ COMPLIANT: Within 15 line limit"
fi
echo

# repl function (lines 253-257)
repl_lines=$(count_function_lines 253 257 "$file")
echo "repl function:"
echo "  Lines: $repl_lines (limit: 15)"
echo "  Parameters: 5 (limit: 4)"
if [ $repl_lines -gt 15 ]; then
    echo "  ❌ VIOLATION: Exceeds 15 line limit"
else
    echo "  ✅ COMPLIANT: Within 15 line limit"
fi
if [ 5 -gt 4 ]; then
    echo "  ❌ VIOLATION: Exceeds 4 parameter limit"
else
    echo "  ✅ COMPLIANT: Within 4 parameter limit"
fi
echo

echo "=== Summary ==="
echo "Functions analyzed: 4"
violations=0
if [ $debug_lines -gt 15 ]; then violations=$((violations + 1)); fi
if [ $dev_lines -gt 15 ]; then violations=$((violations + 1)); fi
if [ $prod_lines -gt 15 ]; then violations=$((violations + 1)); fi
if [ $repl_lines -gt 15 ]; then violations=$((violations + 1)); fi
if [ 5 -gt 4 ]; then violations=$((violations + 1)); fi

echo "Violations found: $violations"
if [ $violations -eq 0 ]; then
    echo "✅ ALL FUNCTIONS COMPLIANT"
else
    echo "❌ VIOLATIONS DETECTED - REFACTORING REQUIRED"
fi
