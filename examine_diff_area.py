#!/usr/bin/env python3

def examine_difference_area():
    print("=== Examining Difference Area Around Character 63507 ===\n")

    # Read the files
    with open("/tmp/debug-canopy-user-basic-arithmetic.js", "r") as f:
        canopy_output = f.read()

    with open("/tmp/debug-elm-user-basic-arithmetic.js", "r") as f:
        elm_output = f.read()

    diff_pos = 63507
    window = 100

    print("Canopy context around difference:")
    canopy_context = canopy_output[diff_pos-window:diff_pos+window]
    print(canopy_context)

    print("\n" + "="*80)
    print("Elm context around difference:")
    elm_context = elm_output[diff_pos-window:diff_pos+window]
    print(elm_context)

    print("\n" + "="*80)
    print("Character-by-character comparison around difference:")

    for i in range(max(0, diff_pos-20), min(len(canopy_output), len(elm_output), diff_pos+20)):
        c_char = canopy_output[i] if i < len(canopy_output) else "EOF"
        e_char = elm_output[i] if i < len(elm_output) else "EOF"

        marker = " *** DIFF ***" if c_char != e_char else ""
        print(f"{i:6d}: '{c_char}' vs '{e_char}'{marker}")

if __name__ == "__main__":
    examine_difference_area()