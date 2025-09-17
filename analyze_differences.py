#!/usr/bin/env python3

import re

def find_patterns(elm_user, canopy_user):
    """Find and categorize all the differences between Elm and Canopy outputs."""

    print("=== PATTERN ANALYSIS ===\n")

    # 1. Tail call optimization patterns
    print("1. TAIL CALL OPTIMIZATION DIFFERENCES:")
    elm_tail_calls = re.findall(r'(\w+):while\(true\){[^}]*continue \w+;[^}]*}', elm_user)
    canopy_tail_calls = re.findall(r'\{\{.*?return \w+\([^}]*\);\}\}', canopy_user, re.DOTALL)
    print(f"  Elm while loops: {len(elm_tail_calls)}")
    print(f"  Canopy tail call wrappers: {len(canopy_tail_calls)}")

    if elm_tail_calls:
        print("  Elm example:", elm_tail_calls[0][:100] + "...")
    if canopy_tail_calls:
        print("  Canopy example:", canopy_tail_calls[0][:100] + "...")
    print()

    # 2. Record constructor field ordering
    print("2. RECORD CONSTRUCTOR FIELD ORDERING:")
    elm_records = re.findall(r'return\{(\$:[^}]*,[^}]*)\}', elm_user)
    canopy_records = re.findall(r'return\{([^}]*,\$:[^}]*)\}', canopy_user)

    print(f"  Elm $-first records: {len(elm_records)}")
    print(f"  Canopy $-last records: {len(canopy_records)}")

    if elm_records:
        print(f"  Elm example: {{{elm_records[0]}}}")
    if canopy_records:
        print(f"  Canopy example: {{{canopy_records[0]}}}")
    print()

    # 3. Spacing and formatting differences
    print("3. SPACING/FORMATTING DIFFERENCES:")
    # Count parentheses spacing
    elm_spaced_parens = len(re.findall(r'\(\s+', elm_user))
    canopy_spaced_parens = len(re.findall(r'\(\s+', canopy_user))

    elm_return_space = len(re.findall(r'return\s+', elm_user))
    canopy_return_space = len(re.findall(r'return\s+', canopy_user))

    print(f"  Elm spaced parentheses: {elm_spaced_parens}")
    print(f"  Canopy spaced parentheses: {canopy_spaced_parens}")
    print(f"  Elm 'return ' (with space): {elm_return_space}")
    print(f"  Canopy 'return' (without space): {canopy_return_space}")
    print()

    # 4. Specific function patterns
    print("4. FUNCTION IMPLEMENTATION DIFFERENCES:")

    # Find functions that are implemented differently
    function_diffs = []

    # Extract function names and their implementations
    elm_functions = extract_functions(elm_user)
    canopy_functions = extract_functions(canopy_user)

    common_funcs = set(elm_functions.keys()) & set(canopy_functions.keys())

    for func_name in sorted(common_funcs):
        elm_impl = elm_functions[func_name]
        canopy_impl = canopy_functions[func_name]

        if elm_impl != canopy_impl:
            function_diffs.append((func_name, elm_impl, canopy_impl))

    print(f"  Total functions with differences: {len(function_diffs)}")

    # Show a few examples
    for i, (name, elm_impl, canopy_impl) in enumerate(function_diffs[:5]):
        print(f"  Function {i+1}: {name}")
        print(f"    Elm:    {elm_impl[:150]}{'...' if len(elm_impl) > 150 else ''}")
        print(f"    Canopy: {canopy_impl[:150]}{'...' if len(canopy_impl) > 150 else ''}")
        print()

    return function_diffs

def extract_functions(js_code):
    """Extract function definitions from JavaScript code."""
    functions = {}

    # Pattern to match function definitions
    # var $module$function=F2(function(...){...});
    pattern = r'var (\$[^=]+)=([^;]+);'

    matches = re.findall(pattern, js_code)

    for name, impl in matches:
        functions[name] = impl

    return functions

def main():
    with open('/tmp/debug-elm-user-basic-arithmetic.js', 'r') as f:
        elm_user = f.read()

    with open('/tmp/debug-canopy-user-basic-arithmetic.js', 'r') as f:
        canopy_user = f.read()

    function_diffs = find_patterns(elm_user, canopy_user)

    print("=== DETAILED FUNCTION DIFFERENCES ===\n")

    # Focus on the most important ones
    important_functions = [
        ('$elm$core$Dict$foldr', 'foldr'),
        ('$elm$core$List$foldl', 'foldl'),
        ('$elm$core$List$rangeHelp', 'rangeHelp'),
        ('$elm$json$Json$Decode$errorToStringHelp', 'errorToStringHelp'),
        ('$elm$core$Array$compressNodes', 'compressNodes'),
        ('$elm$core$Array$treeFromBuilder', 'treeFromBuilder'),
        ('$elm$core$Array$initializeHelp', 'initializeHelp')
    ]

    for func_name, display_name in important_functions:
        for name, elm_impl, canopy_impl in function_diffs:
            if func_name in name:
                print(f"--- {display_name} ---")
                print("Elm implementation:")
                print(elm_impl)
                print("\nCanopy implementation:")
                print(canopy_impl)
                print("\n" + "="*80 + "\n")
                break

if __name__ == "__main__":
    main()