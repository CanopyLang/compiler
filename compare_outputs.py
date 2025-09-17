#!/usr/bin/env python3

import re
import sys

def analyze_js_output():
    print("=== JavaScript Output Comparison Analysis ===\n")

    # Read the expected (golden file) output
    with open("/home/quinten/fh/canopy/test/Golden/expected/elm-canopy/basic-arithmetic.js", "r") as f:
        expected = f.read()

    print(f"Expected output length: {len(expected)} characters")
    print(f"Expected output is minified: {is_minified(expected)}")
    print(f"Expected output lines: {len(expected.splitlines())}")
    print(f"Expected output first line: {expected.splitlines()[0][:100]}...")
    print()

    # The test output shows minified JavaScript as expected, but let's check if it matches the golden file
    test_expected = "(function(scope){'use strict';function F(arity,fun,wrapper){wrapper.a=arity;wrapper.f=fun;return wrapper;}"
    print(f"Test shows expected starting with: {test_expected}")
    print(f"Golden file starts with: {expected[:100]}")
    print(f"Match: {expected.startswith(test_expected)}")
    print()

    # The issue is clear: test shows minified, golden file has formatted
    if not expected.startswith(test_expected):
        print("❌ ISSUE FOUND: Golden file contains formatted output but test expects minified output")
        print("This suggests the test is not reading from the golden file correctly")
        print("or there's a caching issue")

    # Look for kernel function patterns in both
    print("\n=== Kernel Function Analysis ===")
    expected_utils = find_utils_patterns(expected)
    print("Expected _Utils patterns found:")
    for pattern in expected_utils[:5]:
        print(f"  {pattern}")

    print("\n=== Next Steps ===")
    print("1. The golden file has correct formatted Elm output")
    print("2. But the test framework is reading old minified output")
    print("3. Need to investigate test framework caching or file reading")

def is_minified(text):
    lines = text.splitlines()
    non_empty_lines = [line for line in lines if line.strip()]
    return len(non_empty_lines) < 10 and len(text) > 1000

def find_utils_patterns(text):
    patterns = []
    for line in text.splitlines():
        if "_Utils_" in line:
            patterns.append(line.strip()[:100])
    return patterns

if __name__ == "__main__":
    analyze_js_output()