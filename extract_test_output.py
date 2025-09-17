#!/usr/bin/env python3
"""
Extract test output from golden test failures
"""

import subprocess
import re
import sys

def run_golden_test():
    """Run the golden test and capture output."""
    print("Running golden test to capture output...")
    
    try:
        # Run the test that we know fails
        cmd = ["stack", "test", "--ta=--pattern", "Golden"]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        
        stderr = result.stderr
        stdout = result.stdout
        
        print("=== STDERR OUTPUT ===")
        print(stderr[:2000])  # First 2000 chars
        
        print("\n=== STDOUT OUTPUT ===")
        print(stdout[:2000])  # First 2000 chars
        
        # Look for the actual test failure content
        if "expected:" in stderr:
            print("\n=== FOUND EXPECTED CONTENT ===")
            lines = stderr.split('\n')
            for i, line in enumerate(lines):
                if 'expected:' in line:
                    print(f"Line {i}: {line}")
                    # Print next few lines too
                    for j in range(1, 6):
                        if i + j < len(lines):
                            print(f"Line {i+j}: {lines[i+j]}")
                    break
        
        return stderr
        
    except Exception as e:
        print(f"Error: {e}")
        return None

def extract_js_from_failure(text):
    """Extract JavaScript content from test failure."""
    # Look for the pattern where JS content is shown
    lines = text.split('\n')
    
    expected_js = None
    actual_js = None
    
    for i, line in enumerate(lines):
        if 'expected:' in line and '"(function(scope)' in line:
            # This line contains the expected JS
            start = line.find('"(function(scope)')
            if start != -1:
                js_content = line[start+1:]  # Remove opening quote
                
                # Look for the end quote, handling escaped quotes
                end_pos = find_closing_quote(js_content)
                if end_pos != -1:
                    expected_js = js_content[:end_pos]
                
        elif ('but got:' in line or 'actual:' in line) and '"(function(scope)' in line:
            # This line contains the actual JS
            start = line.find('"(function(scope)')
            if start != -1:
                js_content = line[start+1:]  # Remove opening quote
                
                # Look for the end quote
                end_pos = find_closing_quote(js_content)
                if end_pos != -1:
                    actual_js = js_content[:end_pos]
    
    return expected_js, actual_js

def find_closing_quote(text):
    """Find the closing quote, handling escaped quotes."""
    i = 0
    while i < len(text):
        if text[i] == '"' and (i == 0 or text[i-1] != '\\'):
            return i
        i += 1
    return -1

def main():
    stderr_output = run_golden_test()
    
    if stderr_output:
        expected_js, actual_js = extract_js_from_failure(stderr_output)
        
        if expected_js and actual_js:
            print(f"\n=== EXTRACTED CONTENT ===")
            print(f"Expected JS length: {len(expected_js)}")
            print(f"Actual JS length: {len(actual_js)}")
            print(f"Difference: {abs(len(expected_js) - len(actual_js))} bytes")
            
            # Save to files for detailed analysis
            with open('/tmp/expected.js', 'w') as f:
                f.write(expected_js)
            with open('/tmp/actual.js', 'w') as f:
                f.write(actual_js)
            
            print("Saved to /tmp/expected.js and /tmp/actual.js")
            
            # Quick analysis
            analyze_differences(expected_js, actual_js)
        else:
            print("Could not extract JS content from test failure")

def analyze_differences(expected, actual):
    """Quick analysis of differences."""
    print(f"\n=== QUICK ANALYSIS ===")
    
    # Check for double braces pattern
    expected_braces = expected.count('{{')
    actual_braces = actual.count('{{')
    print(f"Double braces - Expected: {expected_braces}, Actual: {actual_braces}")
    
    # Check for _UNUSED pattern
    expected_unused = expected.count('_UNUSED')
    actual_unused = actual.count('_UNUSED')
    print(f"_UNUSED - Expected: {expected_unused}, Actual: {actual_unused}")
    
    # Check for function patterns
    expected_functions = expected.count('function(')
    actual_functions = actual.count('function(')
    print(f"Functions - Expected: {expected_functions}, Actual: {actual_functions}")
    
    # Look for specific differences in the first 1000 chars
    print(f"\n=== FIRST 1000 CHARS COMPARISON ===")
    exp_start = expected[:1000]
    act_start = actual[:1000]
    
    if exp_start != act_start:
        print("First 1000 chars differ!")
        # Find first difference
        for i in range(min(len(exp_start), len(act_start))):
            if exp_start[i] != act_start[i]:
                print(f"First difference at position {i}:")
                print(f"Expected: '{exp_start[i:i+50]}'")
                print(f"Actual:   '{act_start[i:i+50]}'")
                break
    else:
        print("First 1000 chars are identical")

if __name__ == "__main__":
    main()