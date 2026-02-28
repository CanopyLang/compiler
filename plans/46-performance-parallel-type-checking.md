# Plan 46: Parallel Type Checking

## Priority: LOW
## Effort: Large (5-10 days)
## Risk: High — type inference has mutable state

## Problem

Type checking is currently sequential. For large projects with many independent modules, this is a bottleneck. Modules that don't depend on each other could be type-checked in parallel.

## Implementation Plan

### Step 1: Analyze type checker state

Audit `Type/Solve.hs` and `Type/Unify.hs` for mutable state:
- Unification variables (IORef-based)
- Type variable supply
- Error accumulation

### Step 2: Isolate per-module type checking state

Ensure each module's type checking creates its own unification variable pool and error accumulator, with no shared mutable state.

### Step 3: Build module dependency graph

From the canonical AST, extract which modules depend on which for type information:
- A module's type checking depends on the interfaces of its imports
- Once all imports are type-checked, the module can proceed

### Step 4: Parallel type checking with dependency ordering

```haskell
typeCheckModulesParallel :: Pool -> [CanonicalModule] -> IO [Either TypeError TypedModule]
typeCheckModulesParallel pool modules = do
  let graph = buildDependencyGraph modules
      levels = topologicalLevels graph
  -- Type check each level in parallel
  foldM (typeCheckLevel pool) Map.empty levels
```

### Step 5: Interface sharing between parallel workers

After a module is type-checked, its interface is made available to downstream modules via a concurrent map:

```haskell
type InterfaceStore = TVar (Map ModuleName Interface)
```

### Step 6: Tests

- Test parallel type checking produces same results as sequential
- Test with circular dependency detection
- Benchmark: measure speedup on multi-module projects

## Dependencies
- Plan 06 (bounded parallelism) for the worker pool
- Plan 09 (incremental type checking) for cache integration
