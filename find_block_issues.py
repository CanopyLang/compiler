#!/usr/bin/env python3

import re

def find_block_issues(file_path):
    with open(file_path, 'r') as f:
        content = f.read()

    # Find all instances of {var
    block_var_pattern = r'\{var\s+\$'
    matches = re.finditer(block_var_pattern, content)

    print(f"Found {len(list(re.finditer(block_var_pattern, content)))} instances of '{{var' pattern")

    # Show context around each match
    for i, match in enumerate(re.finditer(block_var_pattern, content)):
        start = max(0, match.start() - 50)
        end = min(len(content), match.end() + 100)
        context = content[start:end]
        print(f"\nMatch {i+1} at position {match.start()}:")
        print(repr(context))

if __name__ == "__main__":
    find_block_issues("/tmp/debug-canopy-user-basic-arithmetic.js")