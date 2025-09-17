#!/usr/bin/env python3

import difflib
import re

def find_first_difference():
    print("=== Finding Exact Differences in Normalized JavaScript ===\n")

    # Read the normalized files
    with open("/tmp/debug-canopy-user-basic-arithmetic.js", "r") as f:
        canopy_output = f.read()

    with open("/tmp/debug-elm-user-basic-arithmetic.js", "r") as f:
        elm_output = f.read()

    print(f"Canopy output length: {len(canopy_output)}")
    print(f"Elm output length: {len(elm_output)}")

    if canopy_output == elm_output:
        print("✅ Outputs are identical!")
        return

    print("❌ Outputs differ")

    # Find the first difference
    for i, (c_char, e_char) in enumerate(zip(canopy_output, elm_output)):
        if c_char != e_char:
            print(f"\nFirst difference at character {i}:")
            print(f"Context: ...{canopy_output[max(0, i-50):i+50]}...")
            print(f"         {'':>50}^")
            print(f"Canopy char: '{c_char}' (ASCII {ord(c_char)})")
            print(f"Elm char:    '{e_char}' (ASCII {ord(e_char)})")
            break

    # Show first few lines where they differ
    canopy_lines = canopy_output.splitlines()
    elm_lines = elm_output.splitlines()

    print(f"\nCanopy has {len(canopy_lines)} lines")
    print(f"Elm has {len(elm_lines)} lines")

    # Find first differing lines
    for line_num, (c_line, e_line) in enumerate(zip(canopy_lines, elm_lines)):
        if c_line != e_line:
            print(f"\nFirst differing line {line_num + 1}:")
            print(f"Canopy: {c_line[:100]}...")
            print(f"Elm:    {e_line[:100]}...")
            break

    # Look for kernel function differences
    print("\n=== Kernel Function Pattern Analysis ===")

    # Extract Utils patterns
    canopy_utils = extract_patterns(canopy_output, "_Utils_")
    elm_utils = extract_patterns(elm_output, "_Utils_")

    print("Canopy _Utils patterns:")
    for pattern in canopy_utils[:5]:
        print(f"  {pattern}")

    print("\nElm _Utils patterns:")
    for pattern in elm_utils[:5]:
        print(f"  {pattern}")

    # Check specific kernel functions
    key_patterns = ["_Utils_Tuple0", "_Utils_Tuple2", "_List_Nil", "_List_Cons"]
    for pattern in key_patterns:
        canopy_match = find_pattern_context(canopy_output, pattern)
        elm_match = find_pattern_context(elm_output, pattern)

        if canopy_match != elm_match:
            print(f"\n❌ {pattern} differs:")
            print(f"  Canopy: {canopy_match[:80]}")
            print(f"  Elm:    {elm_match[:80]}")
        else:
            print(f"✅ {pattern} matches")

def extract_patterns(text, pattern):
    matches = []
    lines = text.split(pattern)
    for i, line in enumerate(lines[1:], 1):  # Skip first empty match
        context = lines[i-1][-20:] + pattern + line[:60]
        matches.append(context)
    return matches[:10]  # First 10 matches

def find_pattern_context(text, pattern):
    index = text.find(pattern)
    if index == -1:
        return "NOT FOUND"
    return text[index:index+100]

if __name__ == "__main__":
    find_first_difference()