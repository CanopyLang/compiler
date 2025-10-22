# Quick Performance Measurement Guide

**TL;DR**: Run these commands to measure compiler performance

---

## Pre-Flight Check (30 seconds)

```bash
cd /home/quinten/fh/canopy

# Verify build works
stack build --fast

# Verify canopy works
stack exec -- canopy --version

# Check test projects exist
ls benchmark/test-projects/{small,medium,large}/Main.elm

# Make scripts executable
chmod +x benchmark/*.sh scripts/*.sh
```

---

## Baseline Measurement (2 hours)

```bash
# 1. Checkout baseline version
git checkout master  # or your baseline branch

# 2. Clean build
stack clean --full
stack build --fast

# 3. Run baseline measurement
./benchmark/baseline-performance.sh > baselines/master-$(date +%Y%m%d).txt

# 4. Check results
cat baselines/master-*/baseline-times.csv
```

**Expected Output**:
```
Test Case,Average Time (seconds)
small,0.050
medium,0.100
large,0.400
```

---

## Optimization Measurement (2 hours)

```bash
# 1. Checkout optimization branch
git checkout architecture-multi-package-migration

# 2. Clean build
stack clean --full
stack build --fast

# 3. Run optimized measurement
./benchmark/baseline-performance.sh > baselines/optimized-$(date +%Y%m%d).txt

# 4. Check results
cat baselines/optimized-*/baseline-times.csv
```

---

## Comparison (5 minutes)

```bash
# Compare results
./scripts/bench-compare.sh \
  baselines/master-YYYYMMDD.txt \
  baselines/optimized-YYYYMMDD.txt \
  --format=markdown \
  --output=RESULTS.md

# View results
cat RESULTS.md
```

**Expected Output**:
```
Benchmark       Baseline    Current     Diff        Change %
-----------------------------------------------------------------
Small           50ms        45ms        -5ms        10%
Medium          100ms       70ms        -30ms       30%
Large           400ms       200ms       -200ms      50%
```

---

## Detailed Profiling (1 hour)

```bash
# Time profile
./benchmark/profile.sh time large

# View top hotspots
head -50 profiling-results/large-time.prof

# Heap profile
./benchmark/profile.sh heap large

# Visualize heap
hp2ps -c profiling-results/large-heap.hp
```

---

## Phase Breakdown (30 minutes)

```bash
# Detailed phase timing
./scripts/measure-compile-time.sh benchmark/test-projects/large \
  --iterations=10 \
  --format=table

# Save as JSON for analysis
./scripts/measure-compile-time.sh benchmark/test-projects/large \
  --iterations=10 \
  --format=json \
  --output=phase-breakdown.json
```

**Expected Output**:
```
Phase            Min (ms)   Max (ms)   Avg (ms)   StdDev
----------       --------   --------   --------   ------
Parse            60         80         70         5.2
Canonicalize     80         100        90         6.1
Type Check       120        150        135        8.3
Optimize         80         100        90         5.7
Generate         60         80         70         4.9
TOTAL            400        510        455        15.6
```

---

## Memory Analysis (20 minutes)

```bash
# Track memory usage
./scripts/track-memory.sh benchmark/test-projects/large \
  --iterations=5 \
  --output=memory-stats.json

# View results
cat memory-stats.json
```

---

## Comprehensive Report (15 minutes)

```bash
# Generate full performance report
./scripts/generate-performance-report.sh \
  --format=markdown \
  --output=PERFORMANCE_REPORT.md

# View report
cat PERFORMANCE_REPORT.md
```

---

## Success/Fail Criteria

### ✅ SUCCESS if:
- Large project: <10s (from 35.25s baseline)
- Improvement ≥ 40% (target: 70-80%)
- No memory regression (peak <+10%)
- GC time <15%
- p-value <0.05 (statistically significant)

### ⚠️ WARNING if:
- 20-40% improvement (some benefit)
- Memory +10% to +25%
- GC time 15-25%

### ❌ FAIL if:
- <20% improvement
- Memory +25% or more
- GC time >25%
- Any performance regression

---

## Troubleshooting

### High Variance
```bash
# Increase sample size
for i in {1..20}; do
  /usr/bin/time -f "%e" stack exec -- canopy make ... 2>> times.txt
done
```

### Build Issues
```bash
# Full clean rebuild
stack clean --full
rm -rf ~/.stack/snapshots
stack setup
stack build
```

### Profiling Issues
```bash
# Build with profiling explicitly
stack clean
stack build --profile --ghc-options="-fprof-auto -rtsopts"
```

---

## File Locations

**Scripts**:
- `/home/quinten/fh/canopy/benchmark/baseline-performance.sh`
- `/home/quinten/fh/canopy/scripts/measure-compile-time.sh`
- `/home/quinten/fh/canopy/scripts/bench-compare.sh`

**Test Projects**:
- `/home/quinten/fh/canopy/benchmark/test-projects/small/`
- `/home/quinten/fh/canopy/benchmark/test-projects/medium/`
- `/home/quinten/fh/canopy/benchmark/test-projects/large/`

**Results**:
- `/home/quinten/fh/canopy/baselines/` (measurements)
- `/home/quinten/fh/canopy/benchmark/profiling-results/` (profiles)

---

## Full Documentation

For complete details, see:
- `FINAL_PERFORMANCE_REPORT.md` - Comprehensive guide (12 sections)
- `PERFORMANCE_MEASUREMENT_SUMMARY.md` - Executive summary
- `benchmark/PROFILING_GUIDE.md` - Profiling details

---

**Total Time Investment**: ~5 hours for complete before/after measurement with statistical validation
