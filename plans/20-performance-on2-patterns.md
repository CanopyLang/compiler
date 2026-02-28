# Plan 20: Eliminate O(n²) Patterns

## Priority: HIGH
## Effort: Small (4-8 hours)
## Risk: Low — targeted data structure replacements

## Problem

Beyond the occurs check (Plan 07), several other O(n²) patterns exist in the codebase.

### Known Locations

1. **Reporting/Doc.hs** — `splitLast` (lines 142-148): O(n) recursive traversal on lists, then `commaSep` rebuilds the list
2. **Type/Occurs.hs** — `elem` on list (addressed in Plan 07)
3. **List append patterns** — left-associated `++` in hot loops

## Implementation Plan

### Step 1: Fix splitLast in Reporting/Doc.hs

**File**: `packages/canopy-core/src/Reporting/Doc.hs`

Current:
```haskell
splitLast :: [a] -> Maybe ([a], a)
splitLast [] = Nothing
splitLast [x] = Just ([], x)
splitLast (x:xs) = fmap (\(ys, y) -> (x:ys, y)) (splitLast xs)
```

Replace with:
```haskell
splitLast :: [a] -> Maybe ([a], a)
splitLast [] = Nothing
splitLast xs = Just (init xs, last xs)
-- Or better: use NonEmpty
splitLast xs = NE.nonEmpty xs <&> \ne -> (NE.init ne, NE.last ne)
```

### Step 2: Audit for left-associated (++)

Search for patterns like:
```haskell
foldl (\acc x -> acc ++ [x]) [] items  -- O(n²)
```

Replace with:
```haskell
-- Use difference lists or right fold
foldr (\x acc -> x : acc) [] items
-- Or Data.Sequence for repeated appends
```

### Step 3: Audit Map.fromList after sort

Look for patterns where we sort a list then build a Map from it (the sort is redundant since Map.fromList already handles ordering).

### Step 4: Run profiling

After fixes, run the benchmark suite (Plan 19) to verify improvements on large inputs.

### Step 5: Tests

- Existing tests should continue to pass
- Add property tests: old and new implementations produce same results

## Dependencies
- Plan 07 (occurs check) is a subset of this
