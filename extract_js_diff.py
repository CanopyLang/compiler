#!/usr/bin/env python3
"""
Extract JavaScript differences from test failure output
"""

import subprocess
import re
import sys
import os

def extract_js_from_test():
    """Extract JavaScript content from test failure."""
    print("Running test to extract JS content...")
    
    try:
        # Run the test and capture the full output
        cmd = ["stack", "test", "--ta=--pattern", "basic-arithmetic"]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        
        full_output = result.stderr + result.stdout
        lines = full_output.split('\n')
        
        expected_js = None
        actual_js = None
        
        # Look for the expected line
        for i, line in enumerate(lines):
            if 'expected:' in line and '(function(scope)' in line:
                # Extract the quoted JavaScript content
                start = line.find('"(function(scope)')
                if start != -1:
                    js_start = start + 1  # Skip the opening quote
                    
                    # Find the closing quote - look for the end of the line
                    # Since this is truncated, we need to look at the line ending
                    if line.endswith('"'):
                        expected_js = line[js_start:-1]  # Remove closing quote
                    else:
                        # The line might be truncated in the display
                        expected_js = line[js_start:]
                    break
        
        # Look for the actual output (this might be in a different format)
        for i, line in enumerate(lines):
            if ('but got:' in line or 'actual:' in line) and '(function(scope)' in line:
                start = line.find('"(function(scope)')
                if start != -1:
                    js_start = start + 1  # Skip the opening quote
                    
                    if line.endswith('"'):
                        actual_js = line[js_start:-1]  # Remove closing quote
                    else:
                        actual_js = line[js_start:]
                    break
        
        # If we couldn't find both, let's try a different approach
        if not expected_js or not actual_js:
            print("Trying alternative extraction method...")
            
            # Look for the test failure structure
            expected_start = full_output.find('expected: "(function(scope)')
            if expected_start != -1:
                expected_start += len('expected: "')
                
                # Find the end of the expected (look for next line or quote)
                expected_end = full_output.find('\n', expected_start)
                if expected_end == -1:
                    expected_end = len(full_output)
                
                expected_js = full_output[expected_start:expected_end].rstrip('"')
                
            # Look for actual/but got
            actual_markers = ['but got: "', 'actual: "']
            for marker in actual_markers:
                actual_start = full_output.find(marker)
                if actual_start != -1:
                    actual_start += len(marker)
                    actual_end = full_output.find('\n', actual_start)
                    if actual_end == -1:
                        actual_end = len(full_output)
                    
                    actual_js = full_output[actual_start:actual_end].rstrip('"')
                    break
        
        return expected_js, actual_js, full_output
        
    except Exception as e:
        print(f"Error: {e}")
        return None, None, None

def analyze_differences(expected, actual):
    """Analyze the differences between expected and actual JS."""
    if not expected:
        print("No expected JavaScript found")
        return
    if not actual:
        print("No actual JavaScript found")
        return
        
    print(f"Expected length: {len(expected)}")
    print(f"Actual length: {len(actual)}")
    print(f"Difference: {abs(len(expected) - len(actual))} bytes")
    
    # Save to files
    with open('/tmp/expected.js', 'w') as f:
        f.write(expected)
    print("Saved expected JS to /tmp/expected.js")
    
    with open('/tmp/actual.js', 'w') as f:
        f.write(actual)
    print("Saved actual JS to /tmp/actual.js")
    
    # Quick pattern analysis
    print("\n=== PATTERN ANALYSIS ===")
    
    # Check for double braces
    exp_braces = expected.count('{{')
    act_braces = actual.count('{{')
    print(f"Double braces {{ {{ - Expected: {exp_braces}, Actual: {act_braces}")
    
    # Check for _UNUSED
    exp_unused = expected.count('_UNUSED')
    act_unused = actual.count('_UNUSED')
    print(f"_UNUSED - Expected: {exp_unused}, Actual: {act_unused}")
    
    # Check for function patterns
    exp_funcs = expected.count('function(')
    act_funcs = actual.count('function(')
    print(f"function( - Expected: {exp_funcs}, Actual: {act_funcs}")
    
    # Check for specific patterns
    exp_closure = expected.count('}{};}')
    act_closure = actual.count('}{};}')
    print(f"Closure pattern }}{{}}; - Expected: {exp_closure}, Actual: {act_closure}")
    
    # Look for first difference
    min_len = min(len(expected), len(actual))
    first_diff = -1
    for i in range(min_len):
        if expected[i] != actual[i]:
            first_diff = i
            break
    
    if first_diff != -1:
        print(f"\nFirst difference at position {first_diff}:")
        start = max(0, first_diff - 50)
        end = min(len(expected), first_diff + 50)
        print(f"Expected: ...{expected[start:end]}...")
        
        start = max(0, first_diff - 50)
        end = min(len(actual), first_diff + 50)
        print(f"Actual:   ...{actual[start:end]}...")
    else:
        if len(expected) != len(actual):
            print(f"Contents are identical but lengths differ")
        else:
            print("Contents are identical")

def main():
    expected, actual, full_output = extract_js_from_test()
    
    if expected or actual:
        analyze_differences(expected, actual)
    else:
        print("Could not extract JavaScript content")
        print("First 2000 chars of output:")
        if full_output:
            print(full_output[:2000])

if __name__ == "__main__":
    main()