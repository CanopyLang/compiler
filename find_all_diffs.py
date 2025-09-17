#!/usr/bin/env python3
def find_all_differences(file1, file2, max_diffs=10):
    with open(file1, 'rb') as f1, open(file2, 'rb') as f2:
        content1 = f1.read()
        content2 = f2.read()
        
        print(f"File1 length: {len(content1)}")
        print(f"File2 length: {len(content2)}")
        
        pos = 0
        diffs_found = 0
        diff_positions = []
        
        min_len = min(len(content1), len(content2))
        
        # Find all character differences
        for pos in range(min_len):
            if content1[pos] != content2[pos]:
                diff_positions.append(pos)
                diffs_found += 1
                if diffs_found >= max_diffs:
                    break
        
        # Handle length differences
        if len(content1) != len(content2):
            diff_positions.append(min_len)
            
        print(f"\nFound {len(diff_positions)} difference positions:")
        
        # Show context around each difference
        for i, pos in enumerate(diff_positions[:5]):  # Show first 5 diffs
            if pos < min_len:
                start = max(0, pos - 30)
                end = min(min_len, pos + 30)
                
                context1 = content1[start:end]
                context2 = content2[start:end]
                
                print(f"\nDifference {i+1} at position {pos}:")
                print(f"File1: {repr(context1)}")
                print(f"File2: {repr(context2)}")
            else:
                print(f"\nLength difference at position {pos}")
                
        if len(diff_positions) > 5:
            print(f"\n... and {len(diff_positions) - 5} more differences")
            
        return diff_positions

find_all_differences('debug-canopy-user-basic-arithmetic.js', 'debug-elm-user-basic-arithmetic.js')
