# Plan 01: ESM Output

## Priority: CRITICAL — Tier 0
## Status: NOT STARTED — highest priority unstarted work
## Effort: 2-3 weeks
## Blocks: Plans 04, 05, 06, 07, 09 (almost everything)

> **Status Update (2026-03-07 audit):** No ESM generation code exists. The JS generator
> (`Generate/JavaScript.hs`) only produces IIFE output. No `Generate/JavaScript/ESM.hs` file
> exists.
>
> However, several things are ready for ESM:
> - The MCP server (`canopy-mcp`) already has an `esm` option in its `format` enum
> - Code splitting infrastructure (`Generate/JavaScript/CodeSplit/`) produces separate chunks
>   that would benefit from ESM imports
> - All packages use FFI external JS files that could become ESM imports
>
> **This is the single most critical unstarted task in the entire roadmap.**

## Problem

Canopy emits JavaScript as a single IIFE:

```javascript
(function(scope){'use strict';
  // ... everything ...
  if (typeof global !== 'undefined') { global.Canopy = scope['Canopy']; }
}(typeof window !== 'undefined' ? window : this));
```

This is the 2015 approach. It causes:

1. **No tree shaking** — bundlers can't statically analyze IIFE contents. All code is considered live.
2. **No per-module code splitting** — the IIFE is monolithic. Bundlers can't split it.
3. **No HMR** — Vite's HMR works on ESM module boundaries. An IIFE is one opaque blob.
4. **No import maps** — can't use native browser ESM for zero-bundler dev.
5. **Property-based exports defeat DCE** — all functions stored as properties on namespace objects; if the object is alive, everything is alive.

Community workaround (elm-esm) uses fragile regex to convert output. We should do this properly.

## Solution

Emit native ES modules. Each Canopy module compiles to one ESM file with named exports.

### Output Shape

```javascript
// Canopy.Core.List.js
import * as $Basics from './Canopy.Core.Basics.js';
import * as $Maybe from './Canopy.Core.Maybe.js';

// Internal (not exported — bundlers can eliminate)
const _map_helper = (f, xs) => { ... };

// Exported
export const map = /*#__PURE__*/ F2((f, list) => { ... });
export const filter = /*#__PURE__*/ F2((pred, list) => { ... });
export const foldl = /*#__PURE__*/ F3((fn, acc, list) => { ... });
```

### Key Design Decisions

**One file per module**: `Canopy.Core.List` → `Canopy.Core.List.js`. Gives bundlers maximum granularity.

**Named exports only**: Each exposed function/type is a named export. Enables precise tree shaking. No default exports.

**`/*#__PURE__*/` annotations**: Every top-level binding gets this. Since Canopy functions are pure, bundlers can safely eliminate unused bindings. This is a massive advantage over hand-written JS.

**`sideEffects: false`**: Generated package.json declares no side effects. Bundlers can prune entire unused modules.

**Import structure**: Internal imports use relative paths. External package imports use bare specifiers resolvable via import maps or bundler config.

**Runtime**: The small runtime (F2, F3, A2, A3 for currying) ships as a separate module imported by those that need it.

## Implementation

### Phase 1: New code generation backend

**Files to modify:**
- `compiler/packages/canopy-core/src/Generate/JavaScript.hs` — top-level orchestrator
- `compiler/packages/canopy-core/src/Generate/JavaScript/Expression.hs` — expression codegen
- New: `compiler/packages/canopy-core/src/Generate/JavaScript/ESM.hs` — ESM-specific output

**Changes:**
1. Replace the IIFE wrapper with ESM import/export statements
2. Generate one output file per module instead of concatenating everything
3. Emit `import` statements for inter-module dependencies
4. Emit `export` for each exposed definition
5. Annotate all top-level bindings with `/*#__PURE__*/`
6. Extract runtime helpers (F2, F3, A2, A3, etc.) into `canopy-runtime.js`

### Phase 2: Entry point generation

Generate an entry module that re-exports the app's `main`:

```javascript
// main.js (generated entry point)
import { main } from './App.Main.js';
import * as $Platform from './Canopy.Core.Platform.js';

$Platform.worker(main);  // or $Platform.element, $Platform.document, etc.
```

### Phase 3: Import map generation

For development mode, generate an import map alongside the output:

```json
{
  "imports": {
    "canopy/core/": "./output/Canopy.Core.",
    "canopy/html/": "./output/Canopy.Html."
  }
}
```

This enables zero-bundler development — browsers load ESM directly.

### Phase 4: Backward compatibility

Add a `--output-format` flag:
- `--output-format=esm` (new default)
- `--output-format=iife` (legacy, for existing users)

The IIFE mode wraps the ESM output in a compatibility shim.

## Testing

- All 3,707 existing tests must continue passing with ESM output
- New tests: verify ESM syntax validity, import/export correctness
- Integration test: build a multi-module app, verify bundler tree shaking works
- Benchmark: compare bundle sizes IIFE vs ESM (after tree shaking)
- Test with Vite, esbuild, Rollup to verify compatibility

## Migration

Existing projects using the IIFE output can either:
1. Use `--output-format=iife` (no changes needed)
2. Switch to ESM (recommended; may require updating HTML script tags)

## Dependencies

None — this is foundational work.

## Risks

- Kernel JS modules currently embedded inline. Must be extracted to separate importable modules.
- FFI content currently injected into the IIFE. Must become separate ESM files or part of the module that declares the foreign import.
- Circular module dependencies must be handled (ESM supports them but with initialization order constraints).
