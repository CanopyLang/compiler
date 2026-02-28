# Plan 48: Package Diff Command Enhancement

## Priority: LOW
## Effort: Small (4-8 hours)
## Risk: Low — extends existing diff infrastructure

## Problem

`canopy diff` exists but could be more useful:
- Show semver classification (major/minor/patch) of changes
- Show added/removed/changed types and functions
- Suggest version bump based on changes

## Implementation Plan

### Step 1: Audit existing diff

Review the current diff implementation to understand what it shows.

### Step 2: Classify changes by semver impact

```haskell
data ChangeType
  = Addition          -- New export → minor bump
  | Removal           -- Removed export → major bump
  | TypeChange        -- Changed type signature → major bump
  | ImplementationOnly -- Internal change → patch bump

suggestVersion :: [ChangeType] -> VersionBump
suggestVersion changes
  | any isMajor changes = Major
  | any isMinor changes = Minor
  | otherwise = Patch
```

### Step 3: Human-readable diff output

```
canopy diff 1.0.0 1.1.0

Added:
  + List.filterMap : (a -> Maybe b) -> List a -> List b
  + List.partition : (a -> Bool) -> List a -> (List a, List a)

Changed:
  ~ List.sort : List comparable -> List comparable
    was: List a -> List a

Removed:
  - List.sort1 : List comparable -> List comparable

Suggested version: 2.0.0 (MAJOR — removed exports)
```

### Step 4: Tests

- Test classification of additions, removals, type changes
- Test version suggestion logic
- Golden test for diff output format

## Dependencies
- None
