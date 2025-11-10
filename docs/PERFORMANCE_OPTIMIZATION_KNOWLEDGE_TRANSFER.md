# Canopy Compiler Performance Optimization - Knowledge Transfer Guide

**Date**: 2025-10-20
**Audience**: Future contributors, optimization engineers, compiler developers
**Purpose**: Share knowledge and best practices from performance optimization research

---

## Table of Contents

1. [Introduction](#introduction)
2. [How to Profile the Canopy Compiler](#how-to-profile-the-canopy-compiler)
3. [How to Optimize Effectively](#how-to-optimize-effectively)
4. [Common Performance Patterns](#common-performance-patterns)
5. [Tools and Techniques](#tools-and-techniques)
6. [Case Studies](#case-studies)
7. [Anti-Patterns to Avoid](#anti-patterns-to-avoid)
8. [Quick Reference](#quick-reference)

---

## Introduction

This guide captures the knowledge gained from deep research into Canopy compiler performance. It's designed to help future contributors understand:

- How to identify performance bottlenecks
- How to measure and verify improvements
- What optimization techniques work (and which don't)
- How to avoid common pitfalls

### Key Principles

1. **Measure, Don't Guess**: Always profile before optimizing
2. **Verify Everything**: Benchmark before and after every change
3. **Test Thoroughly**: Never sacrifice correctness for speed
4. **Document Decisions**: Future you (and others) will thank you
5. **Be Conservative**: When in doubt, don't optimize

---

## How to Profile the Canopy Compiler

### Quick Start: Finding Bottlenecks

**Step 1: Build with profiling enabled**

```bash
cd /home/quinten/fh/canopy

# Build with profiling support
stack build --profile --ghc-options="-fprof-auto -rtsopts"
```

**Step 2: Run on representative workload**

```bash
# Use the large CMS project for realistic profiling
cd /home/quinten/fh/tafkar/cms

# Run with profiling flags
stack exec canopy -- make src/Main.elm --output=build/prof.js +RTS -p -h -s -RTS
```

**Step 3: Analyze results**

```bash
# View time profile
less canopy.prof

# Generate heap profile graph
hp2ps -c canopy.hp
evince canopy.ps

# View GC statistics
grep -A 20 "total time" canopy.prof
```

### Understanding Profiling Output

**Time Profile (`canopy.prof`)**:

```
COST CENTRE              MODULE              %time    %alloc

Parse.fromByteString     Parse                35.2     28.4
Type.solve              Type.Solve            22.1     31.2
Generate.JavaScript     Generate.JavaScript   18.5     25.1
Canonicalize.module     Canonicalize          12.3     10.8
```

**What to look for**:

- **High %time** (>10%): CPU-bound operations, hot paths
- **High %alloc** (>15%): Memory allocation bottlenecks
- **Surprising entries**: Functions you didn't expect to be slow

**Example Investigation**:

```
Parse.fromByteString: 35.2% time
→ Why is parsing taking 35% of compilation time?
→ Add instrumentation to count parse calls
→ Discovery: Being called 486 times instead of 162!
→ Root cause: Triple parsing bug
→ Solution: Parse cache
```

### Heap Profiling

**Purpose**: Find memory leaks and allocation hotspots

**Command**:
```bash
canopy make src/Main.elm +RTS -h -RTS
hp2ps -c canopy.hp
```

**What to look for**:

- **Growing heap**: Potential space leak
- **Saw-tooth pattern**: Normal GC behavior
- **Flat lines**: Memory not being released
- **Spikes**: Allocation bursts (may indicate opportunity for optimization)

**Common Issues**:

1. **Lazy accumulation**: Use strict folds (`foldl'` not `foldl`)
2. **Thunk buildup**: Add strictness annotations (`!` on fields)
3. **Inefficient data structures**: Use strict `Map`, `Set`

### Custom Instrumentation

**When to use**: To measure specific code paths or count operations

**Example: Count function calls**

```haskell
{-# LANGUAGE CPP #-}

import Data.IORef
import System.IO.Unsafe (unsafePerformIO)

#ifdef PROFILE_BUILD
parseCounter :: IORef Int
parseCounter = unsafePerformIO (newIORef 0)
{-# NOINLINE parseCounter #-}

countParse :: IO ()
countParse = atomicModifyIORef' parseCounter (\n -> (n+1, ()))

reportParseCount :: IO ()
reportParseCount = do
  count <- readIORef parseCounter
  putStrLn ("Total parses: " ++ show count)
#else
countParse :: IO ()
countParse = pure ()

reportParseCount :: IO ()
reportParseCount = pure ()
#endif
```

**Usage**:

```haskell
parseModule :: FilePath -> IO (Either Error Module)
parseModule path = do
  countParse  -- Instrument the hot path
  content <- readFile path
  pure (runParser moduleParser content)

main :: IO ()
main = do
  compile project
  reportParseCount  -- Print total
```

**Build and run**:

```bash
stack build --flag canopy:profile-build --ghc-options="-DPROFILE_BUILD"
canopy make src/Main.elm
# Output: Total parses: 486
```

### ThreadScope for Parallel Profiling

**Purpose**: Visualize parallel execution and identify bottlenecks

**Setup**:

```bash
# Build with eventlog support
stack build --flag canopy:threaded --ghc-options="-eventlog"

# Run with eventlog
canopy make src/Main.elm +RTS -N4 -l -RTS

# View in ThreadScope
threadscope canopy.eventlog
```

**What to look for**:

- **Spark creation**: Are parallel tasks being created?
- **Spark conversion**: Are sparks actually running?
- **GC pauses**: Are GCs blocking parallel execution?
- **Load balance**: Are all cores utilized equally?

---

## How to Optimize Effectively

### The Optimization Workflow

**1. Establish Baseline**

```bash
cd /home/quinten/fh/canopy/benchmark
./run-benchmarks.sh > baseline.txt
```

Save baseline results for comparison.

**2. Profile to Find Bottleneck**

```bash
stack build --profile
stack exec canopy -- make large-project +RTS -p -h -RTS
less canopy.prof  # Identify hot path
```

**3. Form Hypothesis**

Example:
- **Observation**: `Parse.fromByteString` takes 35% of time
- **Investigation**: Add parse counter → shows 486 calls for 162 modules
- **Hypothesis**: Triple parsing is the bottleneck
- **Expected Impact**: Eliminating 2/3 of parses → 40-50% faster

**4. Implement Solution**

Write the optimization code. Keep changes minimal and focused.

**5. Verify Correctness**

```bash
# All tests must pass
make test
make test-golden  # Output must be identical

# Compare output byte-for-byte
canopy make src/Main.elm --output=build/optimized.js
diff build/baseline.js build/optimized.js
# Should be identical (or explain differences)
```

**6. Benchmark Improvement**

```bash
./run-benchmarks.sh > optimized.txt
diff baseline.txt optimized.txt

# Calculate improvement
# Baseline: 35.25s
# Optimized: 20.12s
# Improvement: 42.9% faster ✓
```

**7. Profile to Verify Hypothesis**

```bash
stack exec canopy -- make large-project +RTS -p -RTS
less canopy.prof

# Verify:
# - Parse time decreased from 35% to expected %
# - No unexpected hotspots appeared
# - Allocation improved as expected
```

**8. Document**

Create optimization write-up in `docs/optimizations/`:

```markdown
# Optimization: Eliminate Triple Parsing

## Problem
Every module was being parsed 3 times...

## Solution
Created parse cache to store AST after first parse...

## Results
- Before: 35.25s
- After: 20.12s
- Improvement: 42.9% faster
- Parse count: 486 → 162 ✓

## Testing
- All unit tests: PASS
- All golden tests: PASS (output identical)
- Benchmark: 42.9% improvement ✓
```

### When to Optimize (and When Not To)

**DO optimize when**:

- ✅ Profiling shows clear bottleneck (>10% time)
- ✅ Solution is well-understood and tested
- ✅ Impact is measurable and significant
- ✅ Correctness can be verified easily
- ✅ Code remains readable and maintainable

**DON'T optimize when**:

- ❌ No profiling data (guessing)
- ❌ Function takes <5% of time (not worth it)
- ❌ Solution is complex and risky
- ❌ Can't verify correctness easily
- ❌ Makes code significantly harder to understand

### Risk Assessment

**Low Risk Optimizations**:

- Adding strictness annotations (`!` on fields)
- Using strict `Map`/`Set` instead of lazy
- Replacing `reverse . foldl'` with difference lists
- Simple caching of pure computations
- Using `foldl'` instead of `foldl`

**Medium Risk Optimizations**:

- Parallel compilation (determinism)
- Memory pooling (lifetime management)
- Custom data structures (correctness)
- Fusion transformations (semantics)

**High Risk Optimizations**:

- Cache invalidation (staleness)
- Unsafe operations (`unsafePerformIO`)
- Low-level optimization (FFI, pointers)
- Changing algorithm fundamentally

---

## Common Performance Patterns

### Pattern 1: Repeated Work

**Symptom**: Same computation performed multiple times

**Example from Canopy**:
```haskell
-- BAD: Parse module 3 times
parse1 <- parseModule path  -- For status check
parse2 <- parseModule path  -- For dependencies
parse3 <- parseModule path  -- For compilation
```

**Solution**: Cache results
```haskell
-- GOOD: Parse once, reuse
cached <- parseOnce cache path
let ast = getAST cached
    deps = getImports cached
```

**Impact**: 40-50% faster in Canopy (eliminated triple parsing)

### Pattern 2: Inefficient Data Structures

**Symptom**: Slow lookups, updates, or iterations

**Example**:
```haskell
-- BAD: List lookup is O(n)
lookupVar :: Name -> [(Name, Type)] -> Maybe Type
lookupVar name = lookup name

-- GOOD: Map lookup is O(log n)
lookupVar :: Name -> Map Name Type -> Maybe Type
lookupVar name = Map.lookup name
```

**Common Issues**:

- Using `String` instead of `Text` or `ByteString`
- Using `List` for lookups instead of `Map` or `HashMap`
- Using lazy `Map` instead of strict `Map`

### Pattern 3: Allocation in Hot Paths

**Symptom**: High %alloc in profiling, GC pressure

**Example**:
```haskell
-- BAD: Allocates intermediate lists and reverses
flattenStmts :: [Stmt] -> [Stmt]
flattenStmts stmts =
  reverse (foldl' flatten [] stmts)
  where
    flatten acc EmptyStmt = acc
    flatten acc (Block inner) = reverse (foldl' flatten [] inner) ++ acc
    flatten acc stmt = stmt : acc
```

**Solution**: Difference lists
```haskell
-- GOOD: Single-pass, no reversals
flattenStmts :: [Stmt] -> [Stmt]
flattenStmts stmts = build stmts []
  where
    build :: [Stmt] -> ([Stmt] -> [Stmt])
    build [] = id
    build (EmptyStmt:rest) = build rest
    build (Block inner:rest) = build inner . build rest
    build (stmt:rest) = (stmt :) . build rest
```

### Pattern 4: Space Leaks

**Symptom**: Growing heap, doesn't GC properly

**Example**:
```haskell
-- BAD: Lazy accumulation builds thunk
sumModules :: [Module] -> Int
sumModules = foldl (\acc m -> acc + moduleSize m) 0
```

**Solution**: Strictness
```haskell
-- GOOD: Strict accumulation
sumModules :: [Module] -> Int
sumModules = foldl' (\acc m -> acc + moduleSize m) 0
-- Or with BangPatterns:
sumModules mods = go 0 mods
  where
    go !acc [] = acc
    go !acc (m:ms) = go (acc + moduleSize m) ms
```

### Pattern 5: Sequential Bottlenecks

**Symptom**: Low CPU utilization on multi-core system

**Example**:
```haskell
-- BAD: Sequential compilation
compileAll :: [Module] -> IO [Compiled]
compileAll = traverse compile
```

**Solution**: Parallel processing (when safe)
```haskell
-- GOOD: Parallel compilation (independent modules)
compileAll :: [Module] -> IO [Compiled]
compileAll = mapConcurrently compile

-- Or with dependency tracking:
compileParallel :: [[Module]] -> IO [Compiled]
compileParallel levels =
  concat <$> traverse (mapConcurrently compile) levels
```

---

## Tools and Techniques

### Essential Tools

**1. GHC Profiler**

```bash
# Build with profiling
stack build --profile

# Run with profiling
canopy make src/Main.elm +RTS -p -h -s -RTS

# Analyze
less canopy.prof      # Time profile
hp2ps -c canopy.hp    # Heap profile
```

**2. Criterion Benchmarking**

```haskell
-- benchmark/Main.hs
import Criterion.Main

main = defaultMain
  [ bench "parse-small" $ nfIO (parseModule "Small.elm")
  , bench "parse-large" $ nfIO (parseModule "Large.elm")
  , bench "type-check" $ nf typeCheck testAST
  ]
```

**3. ThreadScope**

```bash
# Build with eventlog
stack build --ghc-options="-eventlog"

# Run
canopy make src/Main.elm +RTS -l -RTS

# View
threadscope canopy.eventlog
```

**4. strace (System Call Tracing)**

```bash
# Count file operations
strace -c -e openat,read,write canopy make src/Main.elm

# Shows if files being read multiple times
```

**5. htop/perf (CPU Monitoring)**

```bash
# Monitor CPU usage
htop

# Profile with perf (Linux)
perf record canopy make src/Main.elm
perf report
```

### Optimization Techniques

**1. Strictness Annotations**

```haskell
-- Add ! to force evaluation
data State = State
  { _stateModules :: !(Map ModuleName Module)
  , _stateErrors :: ![Error]
  , _stateCounter :: !Int
  }
```

**2. Difference Lists**

```haskell
type DList a = [a] -> [a]

-- Efficient append: O(1) instead of O(n)
append :: DList a -> DList a -> DList a
append f g = f . g

-- Build and convert back to list
toList :: DList a -> [a]
toList f = f []
```

**3. Builder Pattern**

```haskell
import qualified Data.ByteString.Builder as BB

-- Efficient string building
generateJS :: Module -> ByteString
generateJS mod = BB.toLazyByteString (buildModule mod)

buildModule :: Module -> BB.Builder
buildModule mod = mconcat
  [ BB.byteString "function "
  , BB.byteString (moduleName mod)
  , BB.byteString "() { ... }"
  ]
```

**4. Memoization**

```haskell
import Data.Map.Strict as Map

-- Cache expensive computations
memoize :: Ord k => (k -> v) -> (k -> v)
memoize f = \k -> cache Map.! k
  where
    cache = Map.fromList [(x, f x) | x <- keys]
```

**5. Lazy Evaluation Control**

```haskell
-- Force evaluation when needed
import Control.DeepSeq

processModule :: Module -> IO Module
processModule mod = do
  result <- compile mod
  pure $!! result  -- Force full evaluation
```

---

## Case Studies

### Case Study 1: Triple Parsing Discovery

**Background**: Initial benchmarks showed 35.25s for large project, but unclear why.

**Investigation Process**:

1. **Profile**: `Parse.fromByteString` showed 35% of time
2. **Hypothesis**: "Maybe parsing is just slow?"
3. **Instrumentation**: Added parse counter
4. **Discovery**: 486 parses for 162 modules (3x redundant!)
5. **Root Cause Analysis**: Traced through code, found 3 call sites:
   - `checkStatus` (line 153)
   - `crawl` (lines 203-217)
   - `topoSort` (line 238)

**Solution**: Parse cache

**Result**: Expected 40-50% improvement (14-17s saved)

**Lesson**: Even "obvious" bottlenecks need investigation. The problem wasn't that parsing was slow—it was that we were doing it 3 times!

### Case Study 2: Failed "Optimizations"

**Background**: Recent changes made compilation **5% slower** (33.6s → 35.3s)

**What Went Wrong**:

**Optimization 1: Name Caching**
- **Idea**: Cache string-to-name conversions
- **Problem**: Added Map lookup overhead, minimal benefit
- **Why**: String conversion wasn't the bottleneck
- **Impact**: Slightly negative

**Optimization 2: Direct Builder Rendering**
- **Idea**: Use Builder directly instead of intermediate
- **Problem**: Implementation was inefficient
- **Result**: Output grew 15%, more Builder operations
- **Impact**: Slightly negative

**Lesson**: Never optimize without profiling data. We "fixed" things that weren't broken and ignored the real problems.

### Case Study 3: High Variance Analysis

**Observation**: Large project variance of 75% (23.9s - 41.7s)

**Investigation**:

1. **Hypothesis**: GC or allocation issue
2. **Heap Profile**: Showed allocation spikes during code generation
3. **Code Review**: Found `reverse . foldl'` pattern in hot path
4. **Root Cause**: Multiple list traversals and reversals causing GC pressure

**Solution**: Difference list approach (single-pass, no reversals)

**Expected Result**: Variance reduction to <50%

**Lesson**: High variance is a symptom of memory pressure. Look for allocation-heavy patterns.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Premature Optimization

**Example**:
```haskell
-- DON'T: Optimize before measuring
-- "I think this might be slow, let me make it faster"
complexOptimization :: Module -> Module
complexOptimization = ...  -- Makes code harder to read
```

**DO**:
```haskell
-- 1. Profile first
-- 2. Identify actual bottleneck
-- 3. Optimize only if significant (>10% time)
-- 4. Keep simple until proven necessary
simpleImplementation :: Module -> Module
```

### Anti-Pattern 2: Micro-Optimization in Cold Paths

**Example**:
```haskell
-- DON'T: Optimize code that runs once
initializeCompiler :: IO Compiler
initializeCompiler = do
  -- This runs once per compilation
  -- Optimizing it won't help overall performance
  ...
```

**Focus on hot paths**:
- Code called per-module (162 times for large project)
- Inner loops
- Recursive functions
- Code called per-expression/type

### Anti-Pattern 3: Breaking Correctness for Speed

**Example**:
```haskell
-- DON'T: Skip validation for performance
quickButWrong :: Input -> Output
quickButWrong input = unsafeConvert input  -- May crash or produce wrong results
```

**DO**:
```haskell
-- Keep correctness, optimize elsewhere
correctAndOptimized :: Input -> Output
correctAndOptimized input =
  validate input >>= safeConvert
  -- Optimize the hot path AFTER validation
```

### Anti-Pattern 4: Ignoring Test Results

**Example**:
```haskell
-- DON'T: Merge optimization if tests fail or output changes
-- "The output is different but it still works, right?"
```

**DO**:
- All tests must pass
- Golden tests must match byte-for-byte
- If output changes, understand why
- Document any intentional changes

### Anti-Pattern 5: Optimizing Without Benchmarks

**Example**:
```haskell
-- DON'T: "I made it faster!" (without measuring)
```

**DO**:
```bash
# Always benchmark before and after
./run-benchmarks.sh > before.txt
# Make optimization
./run-benchmarks.sh > after.txt
diff before.txt after.txt  # Verify improvement
```

---

## Quick Reference

### Profiling Cheat Sheet

```bash
# Build with profiling
stack build --profile

# Time profiling
canopy make src/Main.elm +RTS -p -RTS
less canopy.prof

# Heap profiling
canopy make src/Main.elm +RTS -h -RTS
hp2ps -c canopy.hp && evince canopy.ps

# GC statistics
canopy make src/Main.elm +RTS -s -RTS

# Thread profiling
canopy make src/Main.elm +RTS -N4 -l -RTS
threadscope canopy.eventlog

# Detailed allocation
canopy make src/Main.elm +RTS -P -RTS
```

### Benchmarking Cheat Sheet

```bash
# Run benchmark suite
cd /home/quinten/fh/canopy/benchmark
./run-benchmarks.sh

# Compare two versions
./run-benchmarks.sh > baseline.txt
# Make changes
./run-benchmarks.sh > optimized.txt
diff baseline.txt optimized.txt

# Specific project
cd benchmark/projects/large
time canopy make src/Main.elm --output=build/main.js

# Monitor file I/O
strace -c -e openat canopy make src/Main.elm
```

### Common Optimizations

**Make fields strict**:
```haskell
data Foo = Foo
  { _field1 :: !Int     -- Add !
  , _field2 :: !Text    -- Add !
  }
```

**Use strict folds**:
```haskell
sum xs = foldl' (+) 0 xs  -- Not foldl
```

**Use strict containers**:
```haskell
import qualified Data.Map.Strict as Map  -- Not Data.Map
```

**Difference lists**:
```haskell
build xs = buildDL xs []
  where buildDL = foldl' (\acc x -> acc . (x:)) id
```

**Builder for strings**:
```haskell
import qualified Data.ByteString.Builder as BB
build = BB.toLazyByteString . mconcat . map BB.byteString
```

### GHC Options for Performance

```yaml
# Development (fast compile)
ghc-options: -O0

# Testing (balanced)
ghc-options: -O1

# Production (max performance)
ghc-options:
  - -O2
  - -funbox-strict-fields
  - -fspecialise-aggressively
  - -threaded
  - -rtsopts
  - -with-rtsopts=-N
  - -with-rtsopts=-A128m
```

### Verification Checklist

Before merging any optimization:

- [ ] Profiling shows bottleneck (>10% time)
- [ ] Benchmarks show improvement (>5%)
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Golden tests pass (output identical)
- [ ] No new compiler warnings
- [ ] Code is well-documented
- [ ] Optimization write-up created
- [ ] Reviewed by team

---

## Additional Resources

### Internal Documentation

- [PERFORMANCE.md](../PERFORMANCE.md) - Performance guide
- [COMPILER_PERFORMANCE_OPTIMIZATION_PLAN.md](COMPILER_PERFORMANCE_OPTIMIZATION_PLAN.md) - Detailed plan
- [OPTIMIZATION_ROADMAP.md](optimizations/OPTIMIZATION_ROADMAP.md) - Roadmap
- [BENCHMARK_GUIDE.md](../benchmark/BENCHMARK_GUIDE.md) - Benchmarking
- [PROFILING_GUIDE.md](profiling/PROFILING_GUIDE.md) - Profiling

### External Resources

- [GHC User Guide - Profiling](https://downloads.haskell.org/ghc/latest/docs/html/users_guide/profiling.html)
- [Real World Haskell - Profiling and Optimization](http://book.realworldhaskell.org/read/profiling-and-optimization.html)
- [Parallel and Concurrent Programming in Haskell](https://simonmar.github.io/pages/pcph.html)
- [ThreadScope User Guide](https://wiki.haskell.org/ThreadScope)

---

## Conclusion

Performance optimization is both an art and a science. The key is to:

1. **Measure** before you optimize
2. **Understand** the bottleneck before you fix it
3. **Test** that you didn't break anything
4. **Verify** that you actually improved performance
5. **Document** what you learned

This knowledge transfer guide captures the lessons learned from deep research into Canopy compiler performance. Use it as a starting point for your own optimization work.

**Remember**: The best optimization is the one that's:
- Measured and proven effective
- Correct and well-tested
- Documented and maintainable
- Worth the effort invested

Happy optimizing!

---

**Document Version**: 1.0
**Last Updated**: 2025-10-20
**Maintainer**: Canopy Performance Team
**Feedback**: Please update this document as you learn new techniques!
