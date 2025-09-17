#!/usr/bin/env python3

import subprocess
import re

def extract_test_outputs():
    """Extract both expected and actual outputs from test failure"""
    print("=== Running test to extract outputs ===")

    try:
        result = subprocess.run(['timeout', '60', 'stack', 'test', '--ta=--pattern basic-arithmetic'],
                              capture_output=True, text=True, cwd='/home/quinten/fh/canopy')

        output = result.stderr + result.stdout

        # Extract expected output
        expected_match = re.search(r'expected: "(.*?)"', output, re.DOTALL)
        actual_match = re.search(r'but got: "(.*?)"', output, re.DOTALL)

        if expected_match and actual_match:
            expected = expected_match.group(1)
            actual = actual_match.group(1)

            print(f"Expected output length: {len(expected)}")
            print(f"Actual output length: {len(actual)}")

            # Write both to files
            with open('/tmp/debug_expected.js', 'w') as f:
                f.write(expected)
            with open('/tmp/debug_actual.js', 'w') as f:
                f.write(actual)

            # Check if they're both minified
            expected_lines = expected.count('\n')
            actual_lines = actual.count('\n')

            print(f"Expected line count: {expected_lines}")
            print(f"Actual line count: {actual_lines}")

            # Compare first 100 characters
            print(f"\nFirst 100 chars of expected: {expected[:100]}")
            print(f"First 100 chars of actual: {actual[:100]}")

            # Look for specific differences
            if len(expected) != len(actual):
                print(f"\nLength difference: expected={len(expected)}, actual={len(actual)}")

            # Find first difference
            min_len = min(len(expected), len(actual))
            for i in range(min_len):
                if expected[i] != actual[i]:
                    print(f"\nFirst difference at position {i}:")
                    print(f"Expected: '{expected[i:i+20]}'")
                    print(f"Actual:   '{actual[i:i+20]}'")
                    break
        else:
            print("Could not extract expected/actual from test output")
            print("Test output sample:")
            print(output[:1000])

    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    extract_test_outputs()