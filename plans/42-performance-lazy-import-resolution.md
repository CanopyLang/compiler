# Plan 42: Lazy Import Resolution

## Priority: MEDIUM
## Effort: Medium (2-3 days)
## Risk: Medium — changes core module loading

## Problem

The compiler loads and resolves all imports eagerly, even for modules that might not be needed for the current compilation target. This wastes time and memory on large projects where only a subset of modules are being compiled.

### Key Files
- `packages/canopy-builder/src/Compiler.hs` — module loading
- `packages/canopy-core/src/AST/Canonical/Types.hs` — `_lazyImports` field exists but unclear usage

## Implementation Plan

### Step 1: Audit _lazyImports field

The `Module` type already has `_lazyImports :: !(Set ModuleName.Canonical)`. Understand its current usage and whether it's populated.

### Step 2: Implement demand-driven module loading

Instead of loading all transitively imported modules upfront, load them on demand:

```haskell
data ModuleLoader = ModuleLoader
  { _mlCache :: !(IORef (Map ModuleName LoadedModule))
  , _mlPaths :: ![FilePath]
  }

loadModule :: ModuleLoader -> ModuleName -> IO (Either LoadError Module)
loadModule loader name = do
  cache <- readIORef (_mlCache loader)
  case Map.lookup name cache of
    Just loaded -> pure (Right loaded)
    Nothing -> do
      loaded <- findAndLoad (_mlPaths loader) name
      modifyIORef' (_mlCache loader) (Map.insert name loaded)
      pure loaded
```

### Step 3: Track which imports are actually used

After type checking, record which imported names were actually referenced. Use this to populate `_lazyImports` for future builds.

### Step 4: Skip unused imports in optimization

If an import is in `_lazyImports` and none of its names are used in the current module, don't include it in the optimization/codegen phase.

### Step 5: Tests

- Test that lazy loading produces same results as eager loading
- Test that unused imports are correctly identified
- Benchmark: measure loading time improvement on a project with many imports

## Dependencies
- Plan 09 (incremental type checking) for cache integration
