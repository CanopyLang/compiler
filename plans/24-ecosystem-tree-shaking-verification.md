# Plan 24: Tree-Shaking Verification & Improvement

## Priority: MEDIUM
## Effort: Medium (1-2 days)
## Risk: Low — verification and optimization of existing feature

## Problem

Tree-shaking works via `GlobalGraph` dependency tracking in `AST/Optimized/Graph.hs`, but there's no verification that it actually eliminates dead code effectively. No metrics, no tests proving dead code is removed, and potential missed opportunities.

## Implementation Plan

### Step 1: Add tree-shaking metrics

**File**: `packages/canopy-core/src/Optimize/TreeShake.hs` (NEW or extend existing)

After tree-shaking, report:
```haskell
data TreeShakeReport = TreeShakeReport
  { _tsrTotalDefs :: !Int
  , _tsrReachableDefs :: !Int
  , _tsrEliminatedDefs :: !Int
  , _tsrEliminatedBytes :: !Int  -- Estimated
  }
```

### Step 2: Add --tree-shake-report flag

**File**: `packages/canopy-terminal/src/Make.hs`

Add `--tree-shake-report` flag that prints tree-shaking statistics:

```
Tree-shaking report:
  Total definitions:     234
  Reachable definitions: 156
  Eliminated:            78 (33%)
  Estimated savings:     12.4 KB
```

### Step 3: Verify with golden tests

Create test modules with known dead code and verify the output JS doesn't contain it:

```elm
module TreeShakeTest exposing (used)

used = "hello"

notUsed = "this should be eliminated"
deadHelper x = x + 1  -- also eliminated
```

### Step 4: Test cross-module tree-shaking

Verify that unused exports from imported modules are also eliminated.

### Step 5: Identify missed opportunities

Analyze common patterns that survive tree-shaking but shouldn't:
- Unused type class instances
- Unused record field accessors
- Unused pattern match helpers

### Step 6: Tests

- Golden test: dead code absent from output
- Golden test: used code present in output
- Cross-module elimination test
- Metrics accuracy test

## Dependencies
- None
