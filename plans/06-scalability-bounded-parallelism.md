# Plan 06: Bounded Parallel Compilation in Compiler.hs

## Priority: HIGH
## Effort: Medium (1-2 days)
## Risk: Medium — core compilation path change

## Problem

`Compiler.hs` (in canopy-builder) uses `Async.mapConcurrently` which spawns unbounded threads — one per module in a compilation level. On large projects (100+ modules), this can exhaust file descriptors, memory, and CPU.

Note: `Worker/Pool.hs` in canopy-driver IS actively used by `Driver.hs` (with `Pool.createPool`, `Pool.compileModules`, `Pool.shutdownPool`, `Pool.compileModulesWithProgress`). However, `Compiler.hs` in canopy-builder does NOT use it — it has its own unbounded `Async.mapConcurrently` path.

### Current Code

**Unbounded** (packages/canopy-builder/src/Compiler.hs, line 372):
```haskell
results <- Async.mapConcurrently (compileOneModule queryEngine cacheRef hitRef missRef ifaces statuses modImportMap) modules
```

**Bounded** (packages/canopy-driver/src/Driver.hs, lines 314-348):
```haskell
pool <- Pool.createPool config compileTaskFn
results <- Pool.compileModules pool tasks
Pool.shutdownPool pool
```

The canopy-driver path uses proper bounded parallelism. The canopy-builder path does not.

## Implementation Plan

### Step 1: Replace Async.mapConcurrently in Compiler.hs

**File**: `packages/canopy-builder/src/Compiler.hs`

Replace the unbounded `Async.mapConcurrently` at line 372 with a bounded semaphore approach:

```haskell
compileLevelInParallel queryEngine cacheRef hitRef missRef modules ifaces statuses modImportMap = do
  numCaps <- getNumCapabilities
  sem <- QSem.newQSem numCaps
  results <- Async.mapConcurrently (withSemaphore sem . compileOneModule queryEngine cacheRef hitRef missRef ifaces statuses modImportMap) modules
  ...

withSemaphore :: QSem -> IO a -> IO a
withSemaphore sem = Exception.bracket_ (QSem.waitQSem sem) (QSem.signalQSem sem)
```

Alternatively, reuse the Pool abstraction from canopy-driver if the dependency direction allows it.

### Step 2: Add -j flag for explicit thread count

**File**: `packages/canopy-terminal/src/CLI/Commands.hs`

Add `-j<N>` / `--jobs=<N>` flag to `make` and `build`:
- Default: number of CPU capabilities
- `-j1`: sequential compilation (useful for debugging)
- `-j0`: auto-detect (same as default)

### Step 3: Thread the job count

Pass the `-j` value from CLI through to both the canopy-builder `Compiler.compileLevelInParallel` and the canopy-driver `Pool.createPool` config.

### Step 4: Add progress reporting

Wire the pool's existing progress tracking (already in canopy-driver) to the terminal output for both paths:

```
Compiling [15/42] Module.Name...
```

### Step 5: Tests

- Test that -j1 produces sequential compilation
- Test that -j flag limits actual concurrency
- Test progress reporting output
- Benchmark: compare unbounded vs bounded on a multi-module project

## Dependencies
- None
