#!/bin/bash

# CLAUDE.md Function Compliance Analyzer
# Analyzes Haskell functions for size, parameter, and branching violations

analyze_file() {
    local file="$1"
    echo "=== ANALYZING: $file ==="
    
    # Extract function definitions and analyze them
    grep -n "^[a-zA-Z][a-zA-Z0-9_']*\s*::" "$file" | while IFS=: read -r line_num signature; do
        func_name=$(echo "$signature" | sed 's/\s*::.*$//' | xargs)
        echo "Function: $func_name (line $line_num)"
        
        # Count parameters by counting -> in type signature
        param_count=$(echo "$signature" | grep -o " -> " | wc -l)
        echo "  Parameters: $param_count"
        
        # Find function body and count lines
        awk -v start="$line_num" -v fname="$func_name" '
        NR >= start && /^[a-zA-Z][a-zA-Z0-9_'\'']*\s*/ && $0 !~ /^[[:space:]]/ && $0 !~ fname {exit}
        NR >= start && /^[a-zA-Z][a-zA-Z0-9_'\'']*\s*/ && $0 ~ fname {in_func=1; next}
        in_func && /^[a-zA-Z][a-zA-Z0-9_'\'']*\s*/ && $0 !~ /^[[:space:]]/ {exit}
        in_func && NF > 0 && $0 !~ /^[[:space:]]*--/ {lines++}
        END {print "  Lines: " (lines ? lines : 0)}
        ' "$file"
        
        # Count branching points
        awk -v start="$line_num" -v fname="$func_name" '
        NR >= start && /^[a-zA-Z][a-zA-Z0-9_'\'']*\s*/ && $0 !~ /^[[:space:]]/ && $0 !~ fname {exit}
        NR >= start && /^[a-zA-Z][a-zA-Z0-9_'\'']*\s*/ && $0 ~ fname {in_func=1; next}
        in_func && /^[a-zA-Z][a-zA-Z0-9_'\'']*\s*/ && $0 !~ /^[[:space:]]/ {exit}
        in_func {
            branches += gsub(/\bif\b/, "&")
            branches += gsub(/\bthen\b/, "&") 
            branches += gsub(/\belse\b/, "&")
            branches += gsub(/\bcase\b/, "&")
            branches += gsub(/\|\s*[^|]/, "&")  # Guards
            branches += gsub(/&&/, "&")
            branches += gsub(/\|\|/, "&")
        }
        END {print "  Branches: " (branches ? branches : 0)}
        ' "$file"
        
        echo ""
    done
}

echo "CLAUDE.md Function Compliance Analysis"
echo "======================================"

for file in \
    "/home/quinten/fh/canopy/builder/src/Build.hs" \
    "/home/quinten/fh/canopy/builder/src/Build/Orchestration.hs" \
    "/home/quinten/fh/canopy/builder/src/Build/Module/Compile.hs" \
    "/home/quinten/fh/canopy/builder/src/Build/Artifacts/Management.hs" \
    "/home/quinten/fh/canopy/builder/src/Build/Paths/Resolution.hs" \
    "/home/quinten/fh/canopy/builder/src/Build/Validation.hs"
do
    if [ -f "$file" ]; then
        analyze_file "$file"
    else
        echo "File not found: $file"
    fi
done
