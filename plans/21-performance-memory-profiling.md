# Plan 21: Memory Profiling Infrastructure

## Priority: MEDIUM
## Effort: Small (4-8 hours)
## Risk: Low — diagnostic tooling only

## Problem

No systematic memory profiling is set up. Thunk leaks and excessive allocation can degrade compilation performance on large projects, but there's no way to detect them before users report issues.

## Implementation Plan

### Step 1: Add profiling build target

**File**: `Makefile`

```makefile
profile-build:
	stack build --profile --ghc-options="-fprof-auto -rtsopts"

profile-run:
	stack exec -- canopy make src/Main.can +RTS -p -hT -l

profile-heap:
	stack exec -- canopy make src/Main.can +RTS -hc -p
	hp2ps -c canopy.hp
```

### Step 2: Add memory regression tests

**File**: `bench/MemoryBench.hs` (NEW)

Use the `weigh` library to measure allocations:

```haskell
main :: IO ()
main = mainWith $ do
  setColumns [Case, Allocated, GCs, Max]
  func "parse 1000 lines" Parse.parse thousandLineModule
  func "typecheck 50 modules" TypeCheck.checkAll fiftyModules
  func "optimize module" Optimize.optimize testModule
```

### Step 3: Strictness audit

Audit key data structures for missing strictness annotations:

- `CompileEnv` fields
- `CacheEntry` fields
- Type inference `State` monad contents
- Builder task queues

Add `{-# UNPACK #-}` and bang patterns where beneficial.

### Step 4: Identify thunk leaks

Run with `-hT` (type-based heap profile) on a large test project. Look for:
- Growing `[]` (list) allocations — indicates lazy accumulation
- Growing `(,)` (tuple) allocations — indicates unevaluated pairs
- Growing `IORef` contents — indicates leaked state

### Step 5: CI memory checks

Add a CI step that compiles a reference project and checks peak memory stays below a threshold.

## Dependencies
- Plan 19 (benchmarks) provides test corpus
