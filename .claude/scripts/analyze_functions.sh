#!/bin/bash

# Function to count non-blank lines in a function
count_function_lines() {
    local file="$1"
    local start_line="$2"
    local end_line="$3"
    
    sed -n "${start_line},${end_line}p" "$file" | grep -v '^\s*$' | wc -l
}

# Analyze all Haskell files in Generate directory
find /home/quinten/fh/canopy/compiler/src/Generate -name "*.hs" | while read file; do
    echo "=== Analyzing $file ==="
    
    # Extract function definitions and their line ranges
    awk '
    /^[a-zA-Z_][a-zA-Z0-9_]*.*::.*$/ { 
        if (func_name) {
            print func_name ":" func_start "-" (NR-1) ":" file
        }
        func_name = $1; 
        func_start = NR + 1; 
        file = FILENAME 
    }
    /^[a-zA-Z_][a-zA-Z0-9_]*.*=/ && !/:/ { 
        if (func_name) {
            print func_name ":" func_start "-" (NR-1) ":" file
        }
        func_name = $1; 
        func_start = NR; 
        file = FILENAME 
    }
    END { 
        if (func_name) {
            print func_name ":" func_start "-" NR ":" file
        }
    }' "$file" | while IFS=':' read func_name range file_path; do
        if [[ $range =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start_line=${BASH_REMATCH[1]}
            end_line=${BASH_REMATCH[2]}
            line_count=$(count_function_lines "$file" "$start_line" "$end_line")
            
            if [ "$line_count" -gt 15 ]; then
                echo "VIOLATION: $func_name ($line_count lines) in $file at lines $start_line-$end_line"
            fi
        fi
    done
    echo
done