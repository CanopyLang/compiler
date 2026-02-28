# Plan 22: Compiler Plugin System

## Priority: LOW
## Effort: Large (5-10 days)
## Risk: High — architectural extension point

## Problem

The compiler has no extension mechanism. All transformations are hardcoded. Users cannot add custom optimizations, lints, or code generators without forking the compiler.

## Implementation Plan

### Step 1: Define plugin interface

**File**: `packages/canopy-core/src/Plugin/Interface.hs` (NEW)

```haskell
data PluginPhase
  = AfterParse        -- Transform Source AST
  | AfterCanonicalize  -- Transform Canonical AST
  | AfterTypeCheck     -- Transform typed AST
  | AfterOptimize      -- Transform optimized AST
  | CustomCodegen      -- Generate custom output

data Plugin = Plugin
  { _pluginName :: !Text
  , _pluginVersion :: !Version
  , _pluginPhase :: !PluginPhase
  , _pluginTransform :: PluginTransform
  }

data PluginTransform
  = SourceTransform (Src.Module -> Either PluginError Src.Module)
  | CanonicalTransform (Can.Module -> Either PluginError Can.Module)
  | OptimizedTransform (Opt.GlobalGraph -> Either PluginError Opt.GlobalGraph)
  | CodegenPlugin (Opt.GlobalGraph -> Either PluginError ByteString)
```

### Step 2: Plugin loading

**File**: `packages/canopy-core/src/Plugin/Loader.hs` (NEW)

Load plugins from canopy.json configuration:

```json
{
    "plugins": [
        { "name": "canopy-plugin-tailwind", "version": "1.0.0" }
    ]
}
```

Initially support only Haskell plugins compiled as shared libraries (`.so`/`.dylib`). Later consider a Canopy-native plugin format.

### Step 3: Plugin execution pipeline

**File**: `packages/canopy-core/src/Plugin/Pipeline.hs` (NEW)

Insert plugin hooks at each compiler phase:

```haskell
runPlugins :: PluginPhase -> [Plugin] -> a -> Either PluginError a
runPlugins phase plugins input =
  foldM applyPlugin input (filter (\p -> _pluginPhase p == phase) plugins)
```

### Step 4: Built-in plugins

Convert the existing lint rules (Plan 16 split) into the plugin format as proof-of-concept:

```haskell
unusedImportPlugin :: Plugin
unusedImportPlugin = Plugin
  { _pluginName = "unused-import"
  , _pluginPhase = AfterCanonicalize
  , _pluginTransform = CanonicalTransform checkUnusedImports
  }
```

### Step 5: Plugin API documentation

Document the plugin API with examples for each phase.

### Step 6: Tests

- Test plugin loading and registration
- Test plugin execution order
- Test error handling (plugin failure doesn't crash compiler)
- Test phase-specific transformations

## Dependencies
- Plan 16 (god module splits) — cleaner module boundaries make plugin hooks easier
