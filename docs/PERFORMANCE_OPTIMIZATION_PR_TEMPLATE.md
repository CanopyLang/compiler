# Performance Optimization - [Brief Description]

**Phase**: [1/2/3/4]
**Optimization**: [Name of optimization]
**Expected Impact**: [X%] improvement
**Actual Impact**: [To be filled after benchmarking]

---

## Summary

[Brief 2-3 sentence summary of what this optimization does and why it's needed]

## Problem

[Detailed description of the performance bottleneck]

**Evidence**:
- Profiling data showing bottleneck
- Baseline benchmark results
- Specific code locations

**Example**:
```
COST CENTRE              %time    %alloc
[Function name]          35.2%    28.4%
```

## Solution

[Detailed description of the optimization implemented]

**Approach**:
1. [Step 1]
2. [Step 2]
3. [Step 3]

**Files Modified**:
- `path/to/file1.hs` - [What changed]
- `path/to/file2.hs` - [What changed]

**Code Changes**:

```haskell
-- BEFORE
[Old code snippet]

-- AFTER
[New code snippet]
```

## Measurements

### Before Optimization

**Baseline Performance**:
- Small project: [X]ms
- Medium project: [X]ms
- Large project: [X]s

**Profiling**:
```
COST CENTRE              %time    %alloc
[Hot path]               XX.X%    XX.X%
```

**Benchmark Command**:
```bash
cd /home/quinten/fh/canopy/benchmark
./run-benchmarks.sh > baseline.txt
cat baseline.txt
```

### After Optimization

**Optimized Performance**:
- Small project: [X]ms ([±X]% change)
- Medium project: [X]ms ([±X]% change)
- Large project: [X]s ([±X]% change)

**Improvement**:
- Overall: [X]% faster
- Expected: [Y]% faster
- Status: [✅ Met expectations / ⚠️ Below expectations / 🎉 Exceeded expectations]

**Profiling**:
```
COST CENTRE              %time    %alloc
[Hot path]               XX.X%    XX.X%
```

**Benchmark Command**:
```bash
./run-benchmarks.sh > optimized.txt
diff baseline.txt optimized.txt
```

### Variance Analysis

**Before**:
- Large project variance: [X]% (min: [X]s, max: [X]s)

**After**:
- Large project variance: [X]% (min: [X]s, max: [X]s)
- Improvement: [X]% reduction in variance

## Testing

### Test Results

- [x] All unit tests pass
  ```bash
  stack test
  # Output: All tests passed
  ```

- [x] All integration tests pass
  ```bash
  make test-integration
  # Output: All tests passed
  ```

- [x] Golden tests pass (output identical)
  ```bash
  make test-golden
  # Output: All golden tests passed
  ```

- [x] Property tests pass
  ```bash
  stack test --ta="--pattern Property"
  # Output: All properties verified
  ```

### Output Verification

**Method**: Byte-for-byte comparison

```bash
# Baseline
canopy make src/Main.elm --output=build/baseline.js

# Optimized
canopy make src/Main.elm --output=build/optimized.js

# Compare
diff build/baseline.js build/optimized.js
# Expected: No differences (or documented intentional changes)
```

**Result**: [✅ Identical / ⚠️ Differences explained below]

**Differences** (if any):
- [Explain any differences and why they're acceptable]

### Coverage

**Before**: [X]%
**After**: [X]%
**Status**: [✅ Maintained / ⚠️ Decreased - explanation needed]

## Profiling Evidence

### Time Profile

**Before**:
```
COST CENTRE              MODULE              %time    %alloc
[Full profiling output or relevant sections]
```

**After**:
```
COST CENTRE              MODULE              %time    %alloc
[Full profiling output or relevant sections]
```

**Analysis**:
- [Hot path] time reduced from [X]% to [Y]%
- [Function] allocations reduced from [X]% to [Y]%
- [Observation about changes]

### Heap Profile

**Before**:
[Screenshot or description of heap profile]
- Peak heap: [X]MB
- Allocation pattern: [Description]

**After**:
[Screenshot or description of heap profile]
- Peak heap: [X]MB ([±X]% change)
- Allocation pattern: [Description]

**Analysis**:
- [Observations about memory usage]

### GC Statistics

**Before**:
```
GC statistics:
  Total time: [X]s
  GC time: [X]s ([Y]%)
  Collections: [N]
```

**After**:
```
GC statistics:
  Total time: [X]s
  GC time: [X]s ([Y]%)
  Collections: [N]
```

**Improvement**:
- GC time reduced by [X]%
- Collections reduced by [X]

## Risk Assessment

**Risk Level**: [Low / Medium / High]

**Potential Issues**:
1. [Issue 1]: [Mitigation]
2. [Issue 2]: [Mitigation]

**Rollback Plan**:
- Feature flag: `--no-[optimization-name]` to disable
- Git revert: This commit can be cleanly reverted
- Benchmark verification: Track performance over time

**Testing Done**:
- [x] Stress testing with large projects
- [x] Edge case testing
- [x] Concurrent execution testing (if applicable)
- [x] Memory leak checking
- [x] Thread safety verification (if applicable)

## Technical Details

### Design Decisions

**Decision 1**: [What was decided]
- **Rationale**: [Why]
- **Alternatives Considered**: [What else was considered and why rejected]
- **Trade-offs**: [What trade-offs were made]

**Decision 2**: [What was decided]
- **Rationale**: [Why]
- **Alternatives Considered**: [What else was considered and why rejected]
- **Trade-offs**: [What trade-offs were made]

### Implementation Notes

**Key Techniques**:
1. [Technique 1] - [Brief description]
2. [Technique 2] - [Brief description]

**Code Patterns**:
- [Pattern used and why]

**Data Structures**:
- [Data structure changes and reasoning]

### Corner Cases

**Handled**:
1. [Corner case 1]: [How handled]
2. [Corner case 2]: [How handled]

**Known Limitations**:
1. [Limitation 1]: [Impact and mitigation]
2. [Limitation 2]: [Impact and mitigation]

## Documentation

**Documentation Updated**:
- [x] [PERFORMANCE.md](../PERFORMANCE.md) - Updated with results
- [x] [OPTIMIZATION_ROADMAP.md](optimizations/OPTIMIZATION_ROADMAP.md) - Marked phase complete
- [x] [CHANGELOG.md](../CHANGELOG.md) - Added entry
- [x] Optimization write-up created: [docs/optimizations/XX-name.md](optimizations/XX-name.md)
- [x] Code comments added where needed
- [x] Inline documentation updated

**Write-up Location**: [docs/optimizations/XX-name.md](optimizations/XX-name.md)

## Checklist

### Pre-Implementation

- [x] Baseline benchmarks established
- [x] Profiling data collected
- [x] Bottleneck identified and verified
- [x] Hypothesis formed
- [x] Expected impact estimated

### Implementation

- [x] Code changes made
- [x] Code follows style guide ([CLAUDE.md](../CLAUDE.md))
- [x] Functions ≤15 lines
- [x] Complexity ≤4 branches
- [x] Lenses used for record operations
- [x] Qualified imports
- [x] Haddock documentation added

### Verification

- [x] All tests pass
- [x] Golden tests verified
- [x] Benchmarks run and analyzed
- [x] Profiling confirms improvement
- [x] No performance regressions
- [x] Memory usage analyzed
- [x] Output correctness verified

### Documentation

- [x] Optimization write-up created
- [x] Code comments added
- [x] PERFORMANCE.md updated
- [x] CHANGELOG.md updated
- [x] OPTIMIZATION_ROADMAP.md updated

### Review

- [x] Self-review completed
- [x] Edge cases considered
- [x] Security implications reviewed
- [x] Performance impact measured
- [ ] Team review requested
- [ ] Approved by [reviewer name]

## Related

**Issues**: [Link to related issues]
**Documentation**: [Link to optimization plan/roadmap]
**Related PRs**: [Link to related PRs]

## Screenshots/Graphs

[If applicable, add benchmark graphs, profiling screenshots, etc.]

**Benchmark Comparison**:
[Graph showing before/after performance]

**Heap Profile**:
[Heap profile screenshots or graphs]

## Notes for Reviewers

[Any specific areas that need attention or questions for reviewers]

**Focus Areas**:
1. [Area 1] - [Why it needs attention]
2. [Area 2] - [Why it needs attention]

**Questions**:
1. [Question for reviewers]
2. [Question for reviewers]

---

**Submitted by**: [Your name]
**Date**: [YYYY-MM-DD]
**Phase**: [Phase number and name]
**Expected Merge**: [Timeline]
