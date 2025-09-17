#!/usr/bin/env python3

import sys
import difflib

def read_file(path):
    with open(path, 'r') as f:
        return f.read()

def find_differences(canopy_path, elm_path):
    canopy_content = read_file(canopy_path)
    elm_content = read_file(elm_path)

    print(f"Canopy length: {len(canopy_content)}")
    print(f"Elm length: {len(elm_content)}")
    print(f"Difference: {len(elm_content) - len(canopy_content)}")
    print()

    # Find first difference character by character
    min_len = min(len(canopy_content), len(elm_content))
    first_diff = None

    for i in range(min_len):
        if canopy_content[i] != elm_content[i]:
            first_diff = i
            break

    if first_diff is not None:
        print(f"First difference at character {first_diff}")

        # Show context around first difference
        start = max(0, first_diff - 100)
        end = min(min_len, first_diff + 100)

        print("\nCanopy context:")
        print(repr(canopy_content[start:end]))
        print("\nElm context:")
        print(repr(elm_content[start:end]))
        print()

        # Show the different characters
        print(f"Canopy char at {first_diff}: {repr(canopy_content[first_diff] if first_diff < len(canopy_content) else 'EOF')}")
        print(f"Elm char at {first_diff}: {repr(elm_content[first_diff] if first_diff < len(elm_content) else 'EOF')}")
    else:
        print("Files are identical up to the shorter length")

    # Check if one file is longer
    if len(canopy_content) != len(elm_content):
        shorter = canopy_content if len(canopy_content) < len(elm_content) else elm_content
        longer = elm_content if len(canopy_content) < len(elm_content) else canopy_content
        which = "Elm" if len(elm_content) > len(canopy_content) else "Canopy"

        print(f"\n{which} is longer by {abs(len(elm_content) - len(canopy_content))} characters")
        print("Additional content:")
        print(repr(longer[len(shorter):len(shorter)+200]))

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 analyze_js_diff.py <canopy_file> <elm_file>")
        sys.exit(1)

    find_differences(sys.argv[1], sys.argv[2])