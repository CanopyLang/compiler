#!/usr/bin/env python3

def analyze_full_output_differences():
    print("=== Exact Character-by-Character Output Analysis ===\n")

    # Run test to get latest output and extract expected vs actual
    import subprocess
    import re

    try:
        result = subprocess.run(['timeout', '300', 'make', 'test'],
                              capture_output=True, text=True, cwd='/home/quinten/fh/canopy')

        output = result.stderr + result.stdout

        # Extract expected and actual from test failure
        expected_match = re.search(r'expected: "(.*?)"', output, re.DOTALL)
        actual_match = re.search(r'but got: "(.*?)"', output, re.DOTALL)

        if not expected_match or not actual_match:
            print("❌ Could not extract expected/actual from test output")
            print("Looking for test failure patterns...")
            lines = output.split('\n')
            for i, line in enumerate(lines):
                if 'basic-arithmetic' in line and 'FAIL' in line:
                    print(f"Found failure at line {i}: {line}")
                    # Show more context
                    start = max(0, i-3)
                    end = min(len(lines), i+20)
                    for j in range(start, end):
                        marker = ">>> " if j == i else "    "
                        print(f"{marker}{j}: {lines[j][:200]}")
                    break
            return

        expected = expected_match.group(1)
        actual = actual_match.group(1)

        print(f"Expected length: {len(expected)}")
        print(f"Actual length: {len(actual)}")

        # Find ALL differences, not just the first
        differences = []
        min_len = min(len(expected), len(actual))

        for i in range(min_len):
            if expected[i] != actual[i]:
                differences.append(i)

        if not differences:
            if len(expected) != len(actual):
                print(f"✅ Content identical up to position {min_len}")
                print(f"❌ Length difference: expected={len(expected)}, actual={len(actual)}")
                if len(expected) > len(actual):
                    print(f"Expected has extra: '{expected[min_len:min_len+200]}'")
                else:
                    print(f"Actual has extra: '{actual[min_len:min_len+200]}'")
            else:
                print("✅ Outputs are completely identical!")
                return
        else:
            print(f"❌ Found {len(differences)} character differences")

            # Show first few differences in detail
            for i, diff_pos in enumerate(differences[:5]):
                print(f"\nDifference #{i+1} at position {diff_pos}:")

                # Show larger context
                context_start = max(0, diff_pos - 50)
                context_end = min(len(expected), diff_pos + 50)

                expected_context = expected[context_start:context_end]
                actual_context = actual[context_start:context_end]

                print(f"Expected: '{expected_context}'")
                print(f"Actual:   '{actual_context}'")
                print(f"          {' ' * (diff_pos - context_start)}^")

                print(f"Character: Expected='{expected[diff_pos]}' (ascii {ord(expected[diff_pos])}), Actual='{actual[diff_pos]}' (ascii {ord(actual[diff_pos])})")

            if len(differences) > 5:
                print(f"... and {len(differences) - 5} more differences")

        # Write both outputs to files for detailed comparison
        with open('/tmp/expected_output.js', 'w') as f:
            f.write(expected)
        with open('/tmp/actual_output.js', 'w') as f:
            f.write(actual)

        print(f"\n" + "="*60)
        print("FILES WRITTEN FOR COMPARISON:")
        print("Expected: /tmp/expected_output.js")
        print("Actual:   /tmp/actual_output.js")
        print("Use 'diff -u /tmp/expected_output.js /tmp/actual_output.js' for detailed comparison")

        # Find lines that are different
        expected_lines = expected.split('\n')
        actual_lines = actual.split('\n')

        print(f"\n" + "="*60)
        print("LINE-BY-LINE ANALYSIS:")
        print(f"Expected lines: {len(expected_lines)}")
        print(f"Actual lines: {len(actual_lines)}")

        # Compare line by line
        max_lines = max(len(expected_lines), len(actual_lines))
        different_lines = []

        for i in range(max_lines):
            exp_line = expected_lines[i] if i < len(expected_lines) else ""
            act_line = actual_lines[i] if i < len(actual_lines) else ""

            if exp_line != act_line:
                different_lines.append(i)

        print(f"Different lines: {len(different_lines)}")

        # Show first few different lines
        for i, line_num in enumerate(different_lines[:3]):
            print(f"\nLine {line_num + 1} differs:")
            exp_line = expected_lines[line_num] if line_num < len(expected_lines) else "[MISSING]"
            act_line = actual_lines[line_num] if line_num < len(actual_lines) else "[MISSING]"

            print(f"Expected: '{exp_line[:100]}{'...' if len(exp_line) > 100 else ''}'")
            print(f"Actual:   '{act_line[:100]}{'...' if len(act_line) > 100 else ''}'")

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    analyze_full_output_differences()