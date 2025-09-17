#!/usr/bin/env python3

import re

def extract_user_functions(filepath):
    """Extract user functions from the end of the JS file."""
    with open(filepath, 'r') as f:
        content = f.read()

    # Find the start of user functions (after all the kernel functions)
    # Look for pattern like "var $author$project$..."
    user_pattern = r'(var \$[^$]+\$[^$]+\$.*?;.*?)(_Platform_export.*)'
    match = re.search(user_pattern, content, re.DOTALL)

    if match:
        user_functions = match.group(1) + match.group(2)
        return user_functions
    else:
        # Fallback: look for any $author$project pattern
        author_pattern = r'(var \$author\$project\$.*?)$'
        match = re.search(author_pattern, content, re.DOTALL)
        if match:
            return match.group(1)
        else:
            # Last fallback: get the last 2000 characters
            return content[-2000:]

def main():
    elm_user = extract_user_functions('/tmp/debug-elm-user-basic-arithmetic.js')
    canopy_user = extract_user_functions('/tmp/debug-canopy-user-basic-arithmetic.js')

    print("=== ELM USER FUNCTIONS ===")
    print(elm_user)
    print()
    print("=== CANOPY USER FUNCTIONS ===")
    print(canopy_user)
    print()

    # Character by character diff
    print("=== CHARACTER BY CHARACTER ANALYSIS ===")
    min_len = min(len(elm_user), len(canopy_user))
    max_len = max(len(elm_user), len(canopy_user))

    differences = []
    for i in range(max_len):
        elm_char = elm_user[i] if i < len(elm_user) else '<END>'
        canopy_char = canopy_user[i] if i < len(canopy_user) else '<END>'

        if elm_char != canopy_char:
            differences.append((i, elm_char, canopy_char))

    if differences:
        print(f"Found {len(differences)} character differences:")
        for pos, elm_char, canopy_char in differences[:20]:  # Show first 20
            context_start = max(0, pos - 20)
            context_end = min(len(elm_user), pos + 20)
            elm_context = elm_user[context_start:context_end].replace('\n', '\\n')
            canopy_context = canopy_user[context_start:context_end].replace('\n', '\\n') if pos < len(canopy_user) else '<END>'

            print(f"  Position {pos}: '{elm_char}' vs '{canopy_char}'")
            print(f"    Elm context:    ...{elm_context}...")
            print(f"    Canopy context: ...{canopy_context}...")
            print()
    else:
        print("No differences found in extracted user functions!")

if __name__ == "__main__":
    main()