#!/bin/bash

file="builder/src/Build/Module/Check.hs"

echo "=== BRANCHING COMPLEXITY ANALYSIS ==="
echo

# Get function definitions
grep -n "^[^[:space:]].*::" "$file" | grep -v "module" | grep -v "import" | while IFS=: read -r line_num signature; do
    func_name=$(echo "$signature" | sed 's/ ::.*$//')
    
    # Get next function line
    next_line=$(grep -n "^[^[:space:]].*::" "$file" | grep -v "module" | grep -v "import" | awk -v current="$line_num" '$1 > current {print $1; exit}')
    
    if [ -z "$next_line" ]; then
        # Last function - count to end of file
        func_body=$(tail -n +$line_num "$file")
    else
        # Count lines between this function and next
        func_body=$(sed -n "${line_num},${next_line}p" "$file" | head -n -1)
    fi
    
    # Count different types of branches
    case_arms=$(echo "$func_body" | grep -E "^\s*[A-Z].*\s*->" | wc -l)
    if_statements=$(echo "$func_body" | grep -E "if\s+.*\s+then" | wc -l)
    guards=$(echo "$func_body" | grep -E "^\s*\|.*=" | wc -l)
    boolean_splits=$(echo "$func_body" | grep -E "&&\s|\|\|\s" | wc -l)
    
    total_branches=$((case_arms + if_statements + guards + boolean_splits))
    
    echo "Function: $func_name"
    echo "  Case arms: $case_arms"
    echo "  If statements: $if_statements" 
    echo "  Guards: $guards"
    echo "  Boolean splits: $boolean_splits"
    echo "  Total branches: $total_branches"
    
    if [ "$total_branches" -gt 4 ]; then
        echo "  STATUS: VIOLATION (>4 branches)"
    else
        echo "  STATUS: COMPLIANT"
    fi
    echo
done
