# Plan 34 — Add Compilation Benchmarks

**Priority:** Tier 6 (Strategic)
**Effort:** 2 days
**Risk:** None
**Files:** ~5 new files

---

## Problem

No compilation time benchmarks exist. No memory profiling infrastructure. No regression detection for build time or output size. Performance claims cannot be validated and regressions cannot be detected.

## Design

### Benchmark Categories

1. **Parse benchmark** — Parse N modules of varying sizes
2. **Type-check benchmark** — Type-check modules with varying type complexity
3. **Codegen benchmark** — Generate JavaScript from optimized ASTs of varying sizes
4. **End-to-end benchmark** — Full compilation pipeline on realistic projects
5. **Incremental benchmark** — Measure cache hit/miss performance

### Benchmark Projects

Create synthetic projects in `bench/`:

```
bench/
├── small/          -- 10 modules, simple types
├── medium/         -- 100 modules, moderate types
├── large/          -- 500 modules (generated), complex types
├── deep-deps/      -- 50-level deep dependency chain
├── wide-deps/      -- 200 modules at same level
└── type-heavy/     -- 20 modules with complex polymorphic types
```

## Implementation

### Step 1: Add criterion dependency

```yaml
# canopy.cabal
benchmark canopy-bench
  type:             exitcode-stdio-1.0
  hs-source-dirs:   bench
  main-is:          Main.hs
  build-depends:
    , canopy-core
    , canopy-builder
    , canopy-driver
    , criterion
    , base
  default-language: Haskell2010
```

### Step 2: Write benchmark harness

```haskell
-- bench/Main.hs
module Main where

import Criterion.Main
import qualified Bench.Parse as Parse
import qualified Bench.TypeCheck as TypeCheck
import qualified Bench.Codegen as Codegen
import qualified Bench.EndToEnd as EndToEnd

main :: IO ()
main = defaultMain
  [ Parse.benchmarks
  , TypeCheck.benchmarks
  , Codegen.benchmarks
  , EndToEnd.benchmarks
  ]
```

### Step 3: Write individual benchmarks

```haskell
-- bench/Bench/Parse.hs
module Bench.Parse (benchmarks) where

benchmarks :: Benchmark
benchmarks = bgroup "Parse"
  [ bench "small module (50 lines)" $ nf Parse.fromByteString smallModule
  , bench "medium module (500 lines)" $ nf Parse.fromByteString mediumModule
  , bench "large module (5000 lines)" $ nf Parse.fromByteString largeModule
  , bench "expression-heavy" $ nf Parse.fromByteString exprHeavyModule
  ]
```

### Step 4: Generate synthetic test projects

Write a generator script that creates Canopy projects of configurable size:

```bash
# scripts/generate-bench-project.sh
#!/bin/bash
# Usage: ./generate-bench-project.sh bench/large 500
# Generates 500 modules with imports, types, and functions
```

### Step 5: Add Makefile targets

```makefile
bench:
	@stack bench canopy:canopy-bench --benchmark-arguments '--output bench/report.html'

bench-quick:
	@stack bench canopy:canopy-bench --benchmark-arguments '--time-limit 1'

bench-compare:
	@stack bench canopy:canopy-bench --benchmark-arguments '--csv bench/current.csv'
	@diff bench/baseline.csv bench/current.csv
```

### Step 6: Add memory profiling support

```makefile
profile:
	@stack build --profile canopy
	@canopy make bench/medium/src/Main.can +RTS -p -h
	@hp2ps canopy.hp
	@echo "See canopy.ps for heap profile"
```

## Validation

```bash
make bench  # Should produce timing results
```

## Acceptance Criteria

- `make bench` runs parse, type-check, codegen, and end-to-end benchmarks
- Results are saved as HTML report and CSV
- Synthetic projects of 10, 100, and 500 modules exist
- `make profile` generates heap profile
- Baseline numbers are recorded for future regression detection
