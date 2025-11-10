#!/bin/bash

file="builder/src/Generate.hs"
echo "=== Branching Complexity Analysis for $file ==="
echo

# Count branching points in each function
echo "debug function (lines 116-124):"
debug_branches=$(sed -n '116,124p' "$file" | grep -E '\bif\b|\bcase\b|\bthen\b|\belse\b|\|' | wc -l)
echo "  Branching points: $debug_branches (limit: 4)"
if [ $debug_branches -gt 4 ]; then
    echo "  ❌ VIOLATION: Exceeds 4 branching limit"
else
    echo "  ✅ COMPLIANT: Within branching limit"
fi
echo

echo "dev function (lines 160-166):"
dev_branches=$(sed -n '160,166p' "$file" | grep -E '\bif\b|\bcase\b|\bthen\b|\belse\b|\|' | wc -l)
echo "  Branching points: $dev_branches (limit: 4)"
if [ $dev_branches -gt 4 ]; then
    echo "  ❌ VIOLATION: Exceeds 4 branching limit"
else
    echo "  ✅ COMPLIANT: Within branching limit"
fi
echo

echo "prod function (lines 207-214):"
prod_branches=$(sed -n '207,214p' "$file" | grep -E '\bif\b|\bcase\b|\bthen\b|\belse\b|\|' | wc -l)
echo "  Branching points: $prod_branches (limit: 4)"
if [ $prod_branches -gt 4 ]; then
    echo "  ❌ VIOLATION: Exceeds 4 branching limit"
else
    echo "  ✅ COMPLIANT: Within branching limit"
fi
echo

echo "repl function (lines 253-257):"
repl_branches=$(sed -n '253,257p' "$file" | grep -E '\bif\b|\bcase\b|\bthen\b|\belse\b|\|' | wc -l)
echo "  Branching points: $repl_branches (limit: 4)"
if [ $repl_branches -gt 4 ]; then
    echo "  ❌ VIOLATION: Exceeds 4 branching limit"
else
    echo "  ✅ COMPLIANT: Within branching limit"
fi
echo

echo "=== Summary ==="
total_branch_violations=0
if [ $debug_branches -gt 4 ]; then total_branch_violations=$((total_branch_violations + 1)); fi
if [ $dev_branches -gt 4 ]; then total_branch_violations=$((total_branch_violations + 1)); fi
if [ $prod_branches -gt 4 ]; then total_branch_violations=$((total_branch_violations + 1)); fi
if [ $repl_branches -gt 4 ]; then total_branch_violations=$((total_branch_violations + 1)); fi

echo "Branching violations found: $total_branch_violations"
if [ $total_branch_violations -eq 0 ]; then
    echo "✅ ALL FUNCTIONS HAVE COMPLIANT BRANCHING"
else
    echo "❌ BRANCHING VIOLATIONS DETECTED"
fi
