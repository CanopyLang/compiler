# Plan 19: Comprehensive Performance Benchmarking

## Priority: MEDIUM
## Effort: Medium (2-3 days)
## Risk: Low — additive, no existing code changes

## Problem

The project has a `bench/` directory with compilation benchmarks and fuzz testing runtime (from Plan 32/34 in prior session), but lacks systematic benchmarks for individual compiler phases: parsing, canonicalization, type inference, optimization, and code generation.

## Implementation Plan

### Step 1: Phase-level benchmarks

**File**: `bench/PhaseBench.hs` (NEW)

Benchmark each compiler phase independently:

```haskell
main :: IO ()
main = defaultMain
  [ bgroup "parse"
      [ bench "small-module" $ nf Parse.parse smallModule
      , bench "medium-module" $ nf Parse.parse mediumModule
      , bench "large-module" $ nf Parse.parse largeModule
      ]
  , bgroup "canonicalize"
      [ bench "simple-names" $ nf Canonicalize.canonicalize simpleAST
      , bench "qualified-names" $ nf Canonicalize.canonicalize qualifiedAST
      ]
  , bgroup "type-inference"
      [ bench "monomorphic" $ nf TypeCheck.check monoModule
      , bench "polymorphic" $ nf TypeCheck.check polyModule
      , bench "recursive" $ nf TypeCheck.check recursiveModule
      ]
  , bgroup "optimize"
      [ bench "dead-code" $ nf Optimize.optimize deadCodeModule
      , bench "inlining" $ nf Optimize.optimize inlineModule
      ]
  , bgroup "codegen"
      [ bench "simple-js" $ nf Generate.generate simpleOptModule
      , bench "complex-js" $ nf Generate.generate complexOptModule
      ]
  ]
```

### Step 2: Memory profiling benchmarks

Add weigh-based benchmarks for memory allocation:

```haskell
main :: IO ()
main = mainWith $ do
  func "parse small" Parse.parse smallSource
  func "parse large" Parse.parse largeSource
  func "typecheck" TypeCheck.check testModule
```

### Step 3: Regression detection

**File**: `.github/workflows/bench.yml` (NEW or update existing)

Run benchmarks on every PR and compare against main:

```yaml
- name: Run benchmarks
  run: stack bench --benchmark-arguments="--output bench-results.html --csv bench-results.csv"

- name: Compare with baseline
  run: |
    # Compare against stored baseline
    python3 scripts/compare-bench.py baseline.csv bench-results.csv --threshold 10
```

### Step 4: Test corpus

**File**: `bench/corpus/` (NEW directory)

Create representative test files of varying sizes:
- `small.can` — 50 lines, simple module
- `medium.can` — 500 lines, typical app module
- `large.can` — 5000 lines, stress test
- `deep-types.can` — deeply nested types
- `many-branches.can` — large case expressions
- `heavy-imports.can` — many qualified imports

### Step 5: CI integration

Store baseline benchmark results and fail CI if any phase regresses by more than 10%.

## Dependencies
- None
