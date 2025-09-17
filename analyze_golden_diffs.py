#!/usr/bin/env python3
"""
Golden Test Difference Analyzer for Canopy Compiler

This script analyzes differences between expected and actual golden test outputs
to identify patterns that need to be fixed in the JavaScript generation.
"""

import os
import re
import sys
import json
import difflib
from collections import defaultdict, Counter
from pathlib import Path
import subprocess
import tempfile

class GoldenAnalyzer:
    def __init__(self, test_dir="test/Golden"):
        self.test_dir = Path(test_dir)
        self.expected_dir = self.test_dir / "expected" / "elm-canopy"
        self.patterns = defaultdict(list)
        self.differences = []
        
    def run_tests_and_capture_output(self):
        """Run tests and capture the actual output for comparison."""
        print("Running tests to capture actual outputs...")
        
        # Get list of all test files
        test_files = list(self.expected_dir.glob("*.js"))
        test_names = [f.stem for f in test_files]
        
        results = {}
        
        for test_name in test_names[:5]:  # Start with first 5 tests to avoid timeout
            print(f"Running test: {test_name}")
            try:
                # Run the specific test and capture output
                cmd = ["stack", "test", "--ta=--pattern", test_name]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
                
                # Extract the actual output from test failure message
                if "expected:" in result.stderr and "but got:" in result.stderr:
                    output_text = result.stderr
                    # Parse the expected vs actual from test output
                    expected_match = re.search(r'expected: "([^"]*)"', output_text, re.DOTALL)
                    actual_match = re.search(r'but got: "([^"]*)"', output_text, re.DOTALL)
                    
                    if expected_match and actual_match:
                        results[test_name] = {
                            'expected': expected_match.group(1),
                            'actual': actual_match.group(1)
                        }
                    elif "expected:" in output_text:
                        # Sometimes the format is different
                        lines = output_text.split('\n')
                        expected_line = None
                        actual_line = None
                        
                        for i, line in enumerate(lines):
                            if line.strip().startswith('expected:'):
                                expected_line = i
                            elif expected_line and not actual_line and line.strip() and not line.startswith('  '):
                                actual_line = i
                                break
                        
                        if expected_line and actual_line:
                            expected_content = lines[expected_line].replace('expected: "', '').replace('"', '')
                            actual_content = lines[actual_line].replace('actual: "', '').replace('"', '')
                            results[test_name] = {
                                'expected': expected_content,
                                'actual': actual_content
                            }
                
            except subprocess.TimeoutExpired:
                print(f"  Timeout for {test_name}")
                continue
            except Exception as e:
                print(f"  Error running {test_name}: {e}")
                continue
                
        return results
    
    def extract_test_output_from_stderr(self, stderr_text):
        """Extract expected and actual output from test failure stderr."""
        # Pattern to match the test output format
        lines = stderr_text.split('\n')
        
        expected_content = None
        actual_content = None
        
        for i, line in enumerate(lines):
            if 'expected:' in line and '"' in line:
                # Find the start and end of the expected content
                start_quote = line.find('"')
                if start_quote != -1:
                    # This is a complex multiline string, we need to parse it carefully
                    content = line[start_quote+1:]
                    
                    # Look for the closing quote or continue to next lines
                    if content.endswith('"'):
                        expected_content = content[:-1]
                    else:
                        # Multi-line content, keep reading
                        j = i + 1
                        while j < len(lines):
                            if lines[j].strip().endswith('"') and not lines[j].strip().startswith('but got:'):
                                content += lines[j][:-1]
                                break
                            else:
                                content += lines[j]
                            j += 1
                        expected_content = content
                        
            elif 'but got:' in line or 'actual:' in line:
                # Similar logic for actual content
                start_quote = line.find('"')
                if start_quote != -1:
                    content = line[start_quote+1:]
                    if content.endswith('"'):
                        actual_content = content[:-1]
                    else:
                        j = i + 1
                        while j < len(lines) and j < len(lines):
                            if lines[j].strip().endswith('"'):
                                content += lines[j][:-1]
                                break
                            else:
                                content += lines[j]
                            j += 1
                        actual_content = content
        
        return expected_content, actual_content
    
    def simple_test_capture(self):
        """Simplified approach to capture test output."""
        print("Capturing basic-arithmetic test output...")
        
        try:
            cmd = ["stack", "test", "--ta=--pattern", "basic-arithmetic"]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            
            stderr = result.stderr
            
            # Look for the expected and actual content in the failure message
            expected_start = stderr.find('expected: "')
            if expected_start != -1:
                expected_start += len('expected: "')
                
                # Find the end of expected (look for the next non-escaped quote)
                expected_end = expected_start
                while expected_end < len(stderr):
                    if stderr[expected_end] == '"' and (expected_end == 0 or stderr[expected_end-1] != '\\'):
                        break
                    expected_end += 1
                
                expected_content = stderr[expected_start:expected_end]
                
                # Now look for "but got:" or similar
                actual_marker = stderr.find('but got:', expected_end)
                if actual_marker == -1:
                    actual_marker = stderr.find('actual:', expected_end)
                
                if actual_marker != -1:
                    actual_start = stderr.find('"', actual_marker)
                    if actual_start != -1:
                        actual_start += 1
                        actual_end = actual_start
                        
                        while actual_end < len(stderr):
                            if stderr[actual_end] == '"' and (actual_end == 0 or stderr[actual_end-1] != '\\'):
                                break
                            actual_end += 1
                        
                        actual_content = stderr[actual_start:actual_end]
                        
                        return expected_content, actual_content
            
            print("Could not extract expected/actual from test output")
            print("First 1000 chars of stderr:")
            print(stderr[:1000])
            
        except Exception as e:
            print(f"Error running test: {e}")
            
        return None, None
    
    def find_pattern_differences(self, expected, actual, test_name):
        """Find and categorize differences between expected and actual output."""
        if not expected or not actual:
            return
            
        # Normalize strings for comparison
        expected_clean = expected.replace('\\n', '\n').replace('\\"', '"')
        actual_clean = actual.replace('\\n', '\n').replace('\\"', '"')
        
        print(f"\nAnalyzing differences for {test_name}:")
        print(f"Expected length: {len(expected_clean)}")
        print(f"Actual length: {len(actual_clean)}")
        
        # Character-by-character diff
        differ = difflib.unified_diff(
            expected_clean.splitlines(keepends=True),
            actual_clean.splitlines(keepends=True),
            fromfile='expected',
            tofile='actual',
            lineterm=''
        )
        
        diff_lines = list(differ)
        if diff_lines:
            print("First 20 diff lines:")
            for line in diff_lines[:20]:
                print(repr(line))
        
        # Look for specific patterns
        self.identify_js_patterns(expected_clean, actual_clean, test_name)
    
    def identify_js_patterns(self, expected, actual, test_name):
        """Identify specific JavaScript generation patterns that differ."""
        patterns = []
        
        # Check for function wrapper differences
        if "{{" in expected and "{{" not in actual:
            patterns.append("missing_function_wrappers")
        elif "{{" not in expected and "{{" in actual:
            patterns.append("extra_function_wrappers")
            
        # Check for variable assignment patterns
        expected_vars = re.findall(r'var \$([^=]+)=', expected)
        actual_vars = re.findall(r'var \$([^=]+)=', actual)
        
        if len(expected_vars) != len(actual_vars):
            patterns.append(f"variable_count_diff_{len(expected_vars)}_vs_{len(actual_vars)}")
        
        # Check for specific code blocks that might be different
        if "return" in expected and "return" in actual:
            expected_returns = expected.count("return")
            actual_returns = actual.count("return")
            if expected_returns != actual_returns:
                patterns.append(f"return_count_diff_{expected_returns}_vs_{actual_returns}")
        
        # Check for function call patterns
        if "function(" in expected and "function(" in actual:
            expected_funcs = expected.count("function(")
            actual_funcs = actual.count("function(")
            if expected_funcs != actual_funcs:
                patterns.append(f"function_count_diff_{expected_funcs}_vs_{actual_funcs}")
        
        # Store patterns
        for pattern in patterns:
            self.patterns[pattern].append(test_name)
        
        # Store raw diff info
        self.differences.append({
            'test': test_name,
            'expected_len': len(expected),
            'actual_len': len(actual),
            'patterns': patterns,
            'size_diff': abs(len(expected) - len(actual))
        })
        
        print(f"Identified patterns: {patterns}")
    
    def analyze_differences(self):
        """Main analysis function."""
        print("=== Golden Test Difference Analysis ===\n")
        
        # Try to capture actual test output
        expected, actual = self.simple_test_capture()
        
        if expected and actual:
            self.find_pattern_differences(expected, actual, "basic-arithmetic")
        else:
            print("Could not capture test output for detailed analysis")
            return
        
        # Report findings
        print("\n=== ANALYSIS RESULTS ===")
        print("\nIdentified Patterns:")
        for pattern, tests in self.patterns.items():
            print(f"  {pattern}: {tests}")
        
        print("\nDifference Summary:")
        for diff in self.differences:
            print(f"  {diff['test']}: {diff['size_diff']} byte difference")
            print(f"    Expected: {diff['expected_len']} bytes")
            print(f"    Actual: {diff['actual_len']} bytes")
            print(f"    Patterns: {diff['patterns']}")

def main():
    analyzer = GoldenAnalyzer()
    analyzer.analyze_differences()

if __name__ == "__main__":
    main()