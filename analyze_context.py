#!/usr/bin/env python3

import sys

def analyze_context(canopy_path, elm_path, diff_pos, context_size=500):
    with open(canopy_path, 'r') as f:
        canopy_content = f.read()
    with open(elm_path, 'r') as f:
        elm_content = f.read()

    # Show larger context around the difference
    start = max(0, diff_pos - context_size)
    end = min(len(canopy_content), diff_pos + context_size)

    print("CANOPY CONTEXT:")
    print("=" * 50)
    canopy_part = canopy_content[start:end]
    # Mark the difference position
    rel_pos = diff_pos - start
    print(canopy_part[:rel_pos] + "<<<HERE>>>" + canopy_part[rel_pos:])

    print("\nELM CONTEXT:")
    print("=" * 50)
    elm_part = elm_content[start:min(len(elm_content), start + len(canopy_part) + 50)]
    print(elm_part[:rel_pos] + "<<<HERE>>>" + elm_part[rel_pos:])

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 analyze_context.py <canopy_file> <elm_file>")
        sys.exit(1)

    analyze_context(sys.argv[1], sys.argv[2], 63507)