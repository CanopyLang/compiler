# Baseline Performance Measurements

**Date**: 2025-10-20
**Commit**: e7235e9 (fix(builder): Fix infinite loop in topological sort)
**Compiler State**: No optimizations integrated
**Build**: stack build --fast

---

## Test Environment

- **Machine**: Linux 6.8.0-85-generic
- **Measurement Tool**: `/usr/bin/time -f "%e"`
- **Methodology**: 10 runs per project, cold compile (no caching)
- **Output**: /tmp/baseline-test.js (discarded between runs)

---

## Small Project Results

**Project**: `/home/quinten/fh/canopy/benchmark/projects/small/`
**Size**: 1 module, 11 lines of code
**File**: `src/Main.canopy`

### Raw Measurements (seconds)

```
Run 1:  0.21
Run 2:  0.21
Run 3:  0.23
Run 4:  0.22
Run 5:  0.22
Run 6:  0.22
Run 7:  0.22
Run 8:  0.22
Run 9:  0.21
Run 10: 0.22
```

### Statistical Analysis

| Metric | Value |
|--------|-------|
| **Mean** | 0.218s |
| **Standard Deviation** | 0.006s |
| **Minimum** | 0.210s |
| **Maximum** | 0.230s |
| **Variance** | 2.8% |
| **95% Confidence Interval** | 0.218s ± 0.004s |

### Assessment

- ✅ Measurements are reliable (low variance)
- ✅ Consistent performance across runs
- ⚠️ Project too small to benefit from multi-module optimizations
- ⚠️ Time dominated by compiler startup overhead
- ⚠️ Parse caching: No benefit (only 1 module, no re-parsing)
- ⚠️ Parallel compilation: No benefit (nothing to parallelize)

**Use Case**: This baseline is useful for:
- Regression testing (ensure performance doesn't degrade)
- Verifying compiler builds correctly
- Quick sanity checks

**Not Useful For**:
- Measuring parse cache improvements (need multi-module project)
- Measuring parallel compilation improvements (need multiple modules)
- Realistic performance validation

---

## Medium Project Results

**Project**: `/home/quinten/fh/canopy/benchmark/projects/medium/`
**Size**: 4 modules, ~260 lines of code
**Files**: Main.can, Types.can, Logic.can, Utils.can

### Status

❌ **BROKEN** - Cannot compile due to import resolution errors

```
Parse error in /home/quinten/fh/canopy/benchmark/projects/medium/src/Main.can:
    TypeError "ImportNotFound (Region (Position 1 1) (Position 1 1)) Types []"
```

### Required Action

- Debug module resolution system
- Fix import path handling
- Validate project structure
- Re-test compilation

---

## Large Project Results

**Project**: Large multi-module test project

### Status

❌ **DOES NOT EXIST**

### Required Action

- Create large test project (10-20 modules)
- Or find working Elm project to use as benchmark
- Ensure realistic import dependencies
- Target: 500+ lines, multiple module layers

---

## Conclusion

**Current Baseline**:
- Only small project measured: **0.218s ± 0.006s**
- Medium and large projects not available
- Cannot perform meaningful optimization testing

**Next Steps**:
1. Fix medium project or create working large project
2. Integrate Cache.hs and Parallel.hs optimizations
3. Re-measure with optimizations enabled
4. Compare baseline vs optimized

**Realistic Timeline**:
- Fix/create test projects: 1-2 days
- Integrate optimizations: 3-5 days
- Measure and validate: 1 day
- **Total**: 1-2 weeks for complete measurements
