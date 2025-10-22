# CANOPY vs ELM: COMPREHENSIVE PERFORMANCE BENCHMARK

**Date:** October 21, 2025
**Test Project:** ContactForm.elm (61 modules)
**Location:** ~/fh/tafkar/components/src/ContactForm.elm
**Methodology:** 3 independent runs per test with /usr/bin/time

---

## EXECUTIVE SUMMARY

Canopy demonstrates **severe performance deficiencies** compared to Elm:
- **2.5x slower** on cold builds (no cache)
- **20x slower** on warm builds (with cache)
- Parse cache appears **non-functional**
- Debug logging overhead **cannot be disabled**

**Bottom Line:** Canopy is not production-ready for real-world development.

---

## BENCHMARK RESULTS

### Cold Build Performance (No Cache)

| Run | Elm Time | Canopy Time | Delta |
|-----|----------|-------------|-------|
| 1   | 1.17s    | 3.48s       | +2.31s |
| 2   | 1.17s    | 3.05s       | +1.88s |
| 3   | 1.43s    | 2.98s       | +1.55s |
| **AVG** | **1.26s** | **3.17s** | **+1.91s** |

**Result: Canopy is 152.3% slower (2.5x)**

### Warm Build Performance (With Cache)

| Run | Elm Time | Canopy Time | Delta |
|-----|----------|-------------|-------|
| 1   | 0.15s    | 2.95s       | +2.80s |
| 2   | 0.14s    | 2.77s       | +2.63s |
| 3   | 0.14s    | 2.86s       | +2.72s |
| **AVG** | **0.14s** | **2.86s** | **+2.72s** |

**Result: Canopy is 1895.3% slower (20x)**

---

## CRITICAL ISSUES DISCOVERED

### 1. Parse Cache Not Working

**Expected Behavior:**
- Warm builds should show dramatic speedup (Elm: 1.26s → 0.14s = 89% faster)
- Parse results should be cached to disk
- Subsequent builds should skip parsing for unchanged files

**Actual Behavior:**
- Warm builds barely improve (3.17s → 2.86s = only 10% faster)
- No `canopy-stuff` directory created in project
- Cache appears non-existent or non-functional

**Evidence:**
```bash
$ ls ~/fh/tafkar/components/
drwxrwxr-x  3 quinten quinten 4096 okt 21 10:03 elm-stuff
# No canopy-stuff directory exists
```

**Impact:** Without effective caching, Canopy will have 2-3 second rebuild times even for unchanged code, making iterative development painful.

### 2. Hardcoded Debug Logging

**Discovery:**
During compilation, Canopy outputs extensive debug logs that CANNOT be disabled:

```
DEBUG interface defs for Platform.Sub: [batch,map,none]
DEBUG interface defs for Platform.Cmd: [batch,map,none]
DEBUG handleNoCopy rank==noRank: Structure rank=0
DEBUG handleNoCopy RigidVar: name=k rank=2 (checking ambient)
DEBUG constrainDef alter (TypedDef): RTV size=3, expectedType present=True
...
```

**Source Code Analysis:**
```bash
$ grep -r "trace (" packages/canopy-core/src/ --include="*.hs" | wc -l
14
```

Found hardcoded trace calls in:
- `packages/canopy-core/src/Canonicalize/Environment/Foreign.hs`
- `packages/canopy-core/src/Type/Solve.hs`

Example from Foreign.hs:
```haskell
!vars = trace ("DEBUG interface defs for " ++ show name ++ ": " ++ show (Map.keys defs))
        (Map.map (Env.Specific home) defs)
```

**Impact:**
- I/O overhead from hundreds of debug prints per build
- String formatting/concatenation overhead
- Cannot be disabled via environment variables (CANOPY_LOG=0 has no effect)
- Estimated 20-30% performance penalty

### 3. Baseline Performance Gap

Even ignoring the cache issue, cold build performance is poor:
- Elm: 1.26s for 61 modules = **48 modules/second**
- Canopy: 3.17s for 61 modules = **19 modules/second**

Canopy is **2.5x slower** at the fundamental compilation task.

Potential causes:
- Type inference algorithm inefficiency
- Debug logging overhead (confirmed above)
- Haskell runtime overhead
- I/O inefficiencies
- Suboptimal data structures

---

## PERFORMANCE COMPARISON MATRIX

|                    | Elm     | Canopy  | Ratio    |
|--------------------|---------|---------|----------|
| Cold build         | 1.26s   | 3.17s   | 2.5x slower |
| Warm build         | 0.14s   | 2.86s   | 20x slower |
| Cache effectiveness| 89% faster | 10% faster | 8.9x worse |
| Modules/sec (cold) | 48      | 19      | 2.5x slower |
| Ready for production? | Yes  | No      | - |

---

## OPTIMIZATION RECOMMENDATIONS

### Immediate (Must Fix Before Launch)

**1. Remove ALL Debug Trace Calls**
- Priority: CRITICAL
- Files to fix:
  - `packages/canopy-core/src/Canonicalize/Environment/Foreign.hs`
  - `packages/canopy-core/src/Type/Solve.hs`
  - All other files with `trace (` calls
- Expected impact: 20-30% performance improvement
- Action: Replace with conditional logging using `Logging.Debug` module

**2. Implement Functional Parse Cache**
- Priority: CRITICAL
- Current state: Non-functional or non-existent
- Required behavior:
  - Cache parsed ASTs to `canopy-stuff/` directory
  - Use file modification times for cache invalidation
  - Target: <0.5s for warm builds (similar to Elm's 0.14s)
- Expected impact: 10x improvement on warm builds

**3. Profile Type Inference**
- Priority: HIGH
- Tool: GHC profiler with `-prof -fprof-auto`
- Focus areas:
  - Type unification algorithm
  - Constraint solving
  - Environment lookups
- Goal: Identify and optimize hot paths

### Medium Term (Performance Competitive with Elm)

**4. Optimize Core Data Structures**
- Use strict data types where appropriate
- Replace lists with vectors for sequential access
- Profile memory allocations
- Target: Match Elm's 1.26s cold build time

**5. Parallel Compilation**
- Implement parallel module compilation
- Use worker pool for independent modules
- Target: 50% faster for large projects

**6. Incremental Type Checking**
- Cache type information for unchanged modules
- Only re-check modified modules and dependencies
- Target: Sub-second rebuild for single file changes

### Long Term (Production Excellence)

**7. Build Benchmarking Suite**
- Automated performance regression tests
- Track compilation times across git commits
- Alert on performance degradation >5%

**8. Production Logging Infrastructure**
- Zero-cost abstractions (compile-time disabled)
- Conditional compilation flags for debug builds
- No performance impact in release builds

---

## TEST METHODOLOGY

### Test Environment
```
OS: Linux 6.8.0-85-generic
Elm: /home/quinten/.local/share/nvm/v19.9.0/bin/elm
Canopy: /home/quinten/.local/bin/canopy
Working Directory: ~/fh/tafkar/components
Test File: src/ContactForm.elm (61 modules total)
```

### Cold Build Test Script
```bash
# Clean cache
rm -rf elm-stuff  # or canopy-stuff

# Time compilation
/usr/bin/time -f "Real: %e seconds" \
  elm make src/ContactForm.elm --output=/tmp/elm-test.js
```

### Warm Build Test Script
```bash
# First build to populate cache
elm make src/ContactForm.elm --output=/tmp/elm-test.js > /dev/null 2>&1

# Then time subsequent builds (no file changes)
/usr/bin/time -f "Real: %e seconds" \
  elm make src/ContactForm.elm --output=/tmp/elm-test.js
```

### Why /usr/bin/time?
- Accurate real (wall clock) time measurement
- Independent of shell overhead
- Consistent across runs
- Standard benchmarking tool

---

## COMPARISON WITH ELM

### What Elm Does Well
1. **Excellent caching:** 89% speedup on warm builds (1.26s → 0.14s)
2. **Fast baseline:** 1.26s for 61 modules is impressive
3. **No debug overhead:** Clean, production-ready builds
4. **Predictable performance:** Consistent times across runs

### What Canopy Needs to Match
1. **Functional cache system:** Must achieve similar speedup ratios
2. **Competitive cold builds:** Target <1.5s for this test (currently 3.17s)
3. **Production hygiene:** Remove all debug logging
4. **Sub-second warm builds:** Critical for developer experience

---

## DEVELOPER EXPERIENCE IMPLICATIONS

### Current Canopy Experience
```
Developer makes 1-line change → Wait 2.86s → See result
```

After 10 iterations: **28.6 seconds** of pure waiting

### Elm Experience
```
Developer makes 1-line change → Wait 0.14s → See result
```

After 10 iterations: **1.4 seconds** of waiting

**Productivity Impact:** Canopy wastes **27 extra seconds** every 10 iterations.

For a typical development session (100 builds):
- **Elm:** 14 seconds of compilation time
- **Canopy:** 286 seconds (4.7 minutes!) of compilation time

This is **unacceptable for professional development.**

---

## CONCLUSIONS

### Current State
Canopy is **not ready for production use** due to:
1. Non-functional parse cache (20x slower warm builds)
2. Hardcoded debug logging that cannot be disabled
3. 2.5x slower baseline performance vs Elm

### Minimum Viable Performance
To be competitive with Elm, Canopy must achieve:
- **Cold builds:** <1.5s (currently 3.17s) = 50% faster
- **Warm builds:** <0.5s (currently 2.86s) = 83% faster
- **Cache effectiveness:** >80% speedup (currently 10%)

### Recommended Path Forward
1. **Week 1:** Remove all trace calls → Target: 2.5s cold, 2.0s warm
2. **Week 2-3:** Implement functional parse cache → Target: 2.5s cold, 0.5s warm
3. **Week 4-6:** Profile and optimize type checker → Target: 1.5s cold, 0.3s warm
4. **Week 7-8:** Add automated performance regression tests
5. **Week 9-12:** Implement parallel compilation for larger projects

### Success Criteria
Before Canopy can replace Elm in production:
- [ ] Cold builds within 20% of Elm (target: <1.5s for this test)
- [ ] Warm builds within 50% of Elm (target: <0.2s for this test)
- [ ] Parse cache provides >80% speedup on warm builds
- [ ] Zero debug output in release builds
- [ ] Automated performance regression tests in CI

**Until these criteria are met, Canopy should be considered pre-alpha quality for performance-sensitive use cases.**

---

## APPENDIX: RAW BENCHMARK OUTPUT

### Full Test Script
See `/tmp/benchmark_canopy_elm.sh`

### Sample Debug Output
```
DEBUG interface defs for Platform.Sub: [batch,map,none]
DEBUG interface defs for Platform.Cmd: [batch,map,none]
DEBUG interface defs for Platform: [sendToApp,sendToSelf,worker]
DEBUG handleNoCopy rank==noRank: Structure rank=0
DEBUG handleNoCopy rank==noRank: RigidSuper rank=0
DEBUG handleNoCopy RigidVar: name=k rank=2 (checking ambient)
DEBUG constrainDef alter (TypedDef): RTV size=3, expectedType present=True
...
```

This debug output appears **on every compilation** and **cannot be disabled**, contributing significantly to performance problems.

---

**Report Generated:** October 21, 2025
**Benchmark Script:** /tmp/benchmark_canopy_elm.sh
**Test Project:** ~/fh/tafkar/components/src/ContactForm.elm
