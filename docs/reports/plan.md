# Canopy Compiler — Code Splitting & Lazy Loading (Revised Plan)

## Why Not `canopy.json` Configuration?

Configuration-driven splitting is the wrong abstraction. It separates the intent (this module is lazy) from the code that expresses the dependency. Developers must maintain a separate config file, it drifts out of sync, and it makes the laziness invisible at the call site. Every modern language that has solved this well — ES modules (`import()`), ReScript (`Js.import`), TypeScript (dynamic `import()`) — puts the split point in the source code where the dependency lives.

Canopy has a unique advantage: **full control over the parser, AST, type system, and code generator**. Since all Canopy code is pure and side-effect-free, cross-module code motion is always safe. We should build first-class language-level lazy imports — the best approach for a greenfield compiler.

---

## Design: Language-Level `lazy import`

### Syntax

```elm
-- Eager (existing behavior, unchanged)
import Dashboard
import Settings exposing (Settings)

-- Lazy: entire module loaded on demand
lazy import Dashboard
lazy import Settings exposing (Settings)

-- Lazy with alias
lazy import Analytics.Dashboard as Dashboard
```

### Semantics

1. **Types are always eagerly resolved.** `lazy import` does NOT change type checking. All types, type aliases, and constructors from a lazy module are available at compile time exactly as before. The compiler still validates everything statically.

2. **Values are loaded on demand.** When code references a function or value from a lazy-imported module, the generated JavaScript loads the chunk containing that module (if not already loaded). Since all Canopy functions are pure, the timing of loading has no observable effect on program behavior.

3. **Loading is synchronous-first.** If the chunk is already loaded (e.g., via a `<script>` tag or a previous load), access is instant. If the chunk must be fetched over the network, the runtime returns a `Promise` and the Canopy runtime scheduler handles the async continuation — this is invisible to Canopy code because the effect system already manages async operations.

4. **Backward compatible.** Without any `lazy` keywords, behavior is identical to today's single-file output. No existing code breaks.

### Why This Is Best-in-Class

| Approach | Split point visible at call site | Type-safe | Zero config | Compiler-optimized |
|----------|--------------------------------|-----------|-------------|-------------------|
| canopy.json config | No | N/A | No | Yes |
| ES `import()` | Yes | No (returns `any`) | Yes | No |
| ReScript `Js.import` | Yes | Yes | Yes | Partial |
| **Canopy `lazy import`** | **Yes** | **Yes** | **Yes** | **Yes** |

Canopy's purity guarantee means the compiler can:
- Automatically extract shared chunks (Closure Compiler-style cross-module code motion)
- Merge tiny chunks based on size heuristics
- Move pure definitions between chunks freely
- Guarantee no behavioral difference between eager and lazy loading

---

## Architecture Overview

```
Source: `lazy import Foo`
    | parse (new keyword in import parser)
    v
Src.Import with _importLazy = True
    | canonicalize (type-check as normal, track lazy set)
    v
Can.Module with _lazyImports :: Set ModuleName.Canonical
    | optimize (propagate lazy info into GlobalGraph)
    v
Opt.GlobalGraph + lazy boundary set
    | analyze (partition globals into chunks)
    v
ChunkGraph (entry chunk, lazy chunks, shared chunks)
    | generate (per-chunk JS emission)
    v
Multiple Builders + Manifest
    | output
    v
dist/entry.js + dist/chunk-<hash>.js + dist/manifest.json
```

---

## Phase 1: Parser & AST — `lazy import` Syntax

### 1A. Extend `Src.Import` with lazy flag

**File**: `packages/canopy-core/src/AST/Source.hs`

```haskell
data Import = Import
  { _importName :: A.Located Name
  , _importAlias :: Maybe Name
  , _importExposing :: Exposing
  , _importLazy :: !Bool          -- NEW
  }
```

Update `getImportName`, `Show` instance, and any pattern matches on `Import`.

### 1B. Parse `lazy` keyword before `import`

**File**: `packages/canopy-core/src/Parse/Module.hs`

Modify `chompImport` to optionally consume a `lazy` keyword before `import`:

```haskell
chompImport :: Parser E.Module Src.Import
chompImport = do
  isLazy <- chompLazyKeyword
  Keyword.import_ E.ImportStart
  -- ... existing parsing ...
  pure (Src.Import name alias exposing isLazy)

chompLazyKeyword :: Parser E.Module Bool
chompLazyKeyword =
  oneOfWithFallback
    [ do Keyword.lazy_ E.ImportStart
         pure True
    ]
    False
```

Add `lazy_` to `Parse/Keyword.hs` (or equivalent keyword module). Since `lazy` is a new keyword, verify it doesn't conflict with any existing identifiers in the language.

### 1C. Add error reporting for invalid lazy imports

**File**: `packages/canopy-core/src/Reporting/Error/Syntax.hs`

Add error case for `lazy import` on kernel/default modules (which cannot be lazily loaded).

### 1D. Propagate through Binary serialization

**File**: `packages/canopy-core/src/AST/Source.hs`

If `Import` has a `Binary` instance, update it to include the `_importLazy` field.

**Files to modify**:
- `packages/canopy-core/src/AST/Source.hs` — type change
- `packages/canopy-core/src/Parse/Module.hs` — parser change
- `packages/canopy-core/src/Parse/Keyword.hs` (or wherever keywords live) — add `lazy`
- `packages/canopy-core/src/Reporting/Error/Syntax.hs` — error for invalid lazy usage

---

## Phase 2: Canonicalization — Track Lazy Boundaries

### 2A. Add lazy import tracking to Canonical module

**File**: `packages/canopy-core/src/AST/Canonical.hs`

```haskell
data Module = Module
  { ... existing fields ...
  , _lazyImports :: !(Set ModuleName.Canonical)  -- NEW
  }
```

### 2B. Collect lazy imports during canonicalization

**File**: `packages/canopy-core/src/Canonicalize/Module.hs`

During `canonicalize`, when processing imports:
- For each import with `_importLazy = True`, resolve it to `ModuleName.Canonical` and add to the lazy set
- Validate: kernel modules, `Basics`, `Platform`, and default imports cannot be lazy (emit error)
- All name resolution proceeds identically — lazy only affects code generation

### 2C. Propagate through Binary serialization

Update the `Binary` instance for `Can.Module` to include `_lazyImports`.

**Files to modify**:
- `packages/canopy-core/src/AST/Canonical.hs` — type change + Binary
- `packages/canopy-core/src/Canonicalize/Module.hs` — collect lazy set

---

## Phase 3: Core Types for Code Splitting

### 3A. Create types module

**New file**: `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Types.hs`

```haskell
module Generate.JavaScript.CodeSplit.Types where

-- | Unique identifier for a generated chunk.
newtype ChunkId = ChunkId Text

-- | Classification of a chunk.
data ChunkKind
  = EntryChunk      -- Contains runtime + initial code
  | LazyChunk       -- Loaded on demand
  | SharedChunk     -- Extracted common code between 2+ chunks

-- | A single chunk of code to be emitted.
data Chunk = Chunk
  { _chunkId :: !ChunkId
  , _chunkKind :: !ChunkKind
  , _chunkGlobals :: !(Set Opt.Global)
  , _chunkDeps :: !(Set ChunkId)
  , _chunkModule :: !(Maybe ModuleName.Canonical)  -- For lazy chunks: trigger module
  }

-- | Complete chunk graph after analysis.
data ChunkGraph = ChunkGraph
  { _cgEntry :: !Chunk
  , _cgLazy :: ![Chunk]
  , _cgShared :: ![Chunk]
  , _cgGlobalToChunk :: !(Map Opt.Global ChunkId)
  }

-- | Configuration derived from source-level lazy imports.
data SplitConfig = SplitConfig
  { _scLazyModules :: !(Set ModuleName.Canonical)
  , _scMinSharedRefs :: !Int  -- Default: 2
  }

-- | Final output of the code splitting pipeline.
data SplitOutput = SplitOutput
  { _soChunks :: ![ChunkOutput]
  , _soManifest :: !Builder
  }

-- | Output for a single chunk.
data ChunkOutput = ChunkOutput
  { _coChunkId :: !ChunkId
  , _coKind :: !ChunkKind
  , _coBuilder :: !Builder
  , _coHash :: !Text
  , _coFilename :: !FilePath
  , _coSourceMap :: !(Maybe SourceMap.SourceMap)
  }
```

Generate lenses for all record types.

**Files**:
- `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Types.hs` — **NEW**
- `packages/canopy-core/canopy-core.cabal` — add to exposed-modules

---

## Phase 4: Dependency Graph Analysis

### 4A. Create analysis module

**New file**: `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Analyze.hs`

**Algorithm** (5 steps):

**Step 1 — Reachability from mains**: Starting from each main entry point, compute the full set of reachable globals using the same depth-first traversal as existing `addGlobal`. Collect sets instead of building JS.

**Step 2 — Identify lazy boundaries**: For each module in the lazy set (from `SplitConfig`), find all globals whose `ModuleName` matches. These globals and their transitive dependencies that are NOT reachable from mains without crossing a lazy boundary form lazy chunks.

**Step 3 — Extract shared globals**: Globals reachable from 2+ chunks get extracted into shared chunks. Uses `_scMinSharedRefs` threshold.

**Step 4 — Cross-module code motion** (Closure Compiler-inspired): Since all Canopy code is pure, move definitions DOWN the chunk graph to the deepest chunk that needs them. A definition used only by lazy chunk A should live in chunk A, not shared. A definition used by lazy chunks A and B goes to their LCA in the loading tree (shared chunk).

**Step 5 — Build ChunkGraph**: Assign every reachable global to exactly one chunk. Compute inter-chunk dependency edges. Verify: union of all chunk globals equals full reachable set.

```haskell
analyze :: SplitConfig -> Opt.GlobalGraph -> Mains -> ChunkGraph

reachableFrom :: Graph -> Set Opt.Global -> Set Opt.Global

identifyLazyGlobals :: Set ModuleName.Canonical -> Graph -> Set Opt.Global
    -> Map ModuleName.Canonical (Set Opt.Global)

extractShared :: Int -> Map ChunkId (Set Opt.Global)
    -> (Set Opt.Global, Map ChunkId (Set Opt.Global))

codeMotion :: ChunkGraph -> Graph -> ChunkGraph

buildChunkGraph :: Chunk -> [Chunk] -> [Chunk] -> Map Opt.Global ChunkId -> ChunkGraph
```

**Edge cases**:
- **Circular dependencies between lazy modules**: Merge into single lazy chunk
- **Kernel globals**: Always stay in entry chunk (shared runtime)
- **FFI functions**: Go into the chunk that first references them
- **Constructors/Enums**: Go with their defining module's chunk
- **No lazy imports**: Returns single entry chunk (degenerate case, no splitting)

**Files**:
- `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Analyze.hs` — **NEW**
- `packages/canopy-core/canopy-core.cabal` — add module

---

## Phase 5: Chunk-Aware Code Generation

### 5A. Create chunk generation module

**New file**: `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Generate.hs`

Reuses existing `Generate.JavaScript` traversal machinery but operates per-chunk.

```haskell
generateChunks :: Mode.Mode -> Opt.GlobalGraph -> Mains
    -> Map String FFIInfo -> ChunkGraph -> SplitOutput

generateChunk :: Mode.Mode -> Graph -> ChunkGraph -> Chunk -> ChunkOutput
```

**Entry chunk structure** (same IIFE pattern, plus runtime):
```javascript
(function(scope){'use strict';
// Runtime (F2-F9, A2-A9)
// Chunk registry & loader runtime
var __canopy_chunks = {};
var __canopy_loaded = {};
function __canopy_register(id, factory) { __canopy_chunks[id] = factory; }
function __canopy_load(id) {
  if (__canopy_loaded[id]) return __canopy_loaded[id];
  if (__canopy_chunks[id]) {
    __canopy_loaded[id] = __canopy_chunks[id]();
    return __canopy_loaded[id];
  }
  return new Promise(function(resolve, reject) {
    var s = document.createElement('script');
    s.src = __canopy_manifest[id];
    s.onload = function() {
      __canopy_loaded[id] = __canopy_chunks[id]();
      resolve(__canopy_loaded[id]);
    };
    s.onerror = reject;
    document.head.appendChild(s);
  });
}
var __canopy_manifest = { /* chunk-id: filename pairs */ };
// Entry point code (all non-lazy globals)
// Main exports
}(typeof window !== 'undefined' ? window : this));
```

**Lazy chunk structure**:
```javascript
__canopy_register("lazy-Dashboard-a1b2c3d4", function() {
  // All globals assigned to this chunk
  var $author$project$Dashboard$view = ...;
  return { '$author$project$Dashboard$view': $author$project$Dashboard$view, ... };
});
```

### 5B. Add `generateForChunk` to Generate.JavaScript

**File**: `packages/canopy-core/src/Generate/JavaScript.hs`

New entry point that traverses only globals assigned to a specific chunk:

```haskell
generateForChunk :: Mode.Mode -> Graph -> Set Opt.Global
    -> Map Opt.Global A.Region -> (Builder, [SourceMap.Mapping])
```

This uses the same `addGlobal`/`continueAddGlobal` machinery but skips globals that belong to other chunks (they'll be accessed via `__canopy_load`).

### 5C. Chunk-aware cross-references in Expression.hs

**File**: `packages/canopy-core/src/Generate/JavaScript/Expression.hs`

When generating a `VarGlobal` reference, check if the target global is in a different chunk:
- **Same chunk**: emit direct reference (existing behavior)
- **Different chunk**: emit `__canopy_load("chunk-id").$global_name`

This requires threading a `ChunkContext` through expression generation:

```haskell
data ChunkContext
  = ChunkContext
      { _ccCurrentChunk :: !ChunkId
      , _ccGlobalToChunk :: !(Map Opt.Global ChunkId)
      }
  | NoSplitting  -- Default: no code splitting active
```

The `generate` function in Expression.hs gains an optional `ChunkContext` parameter. When `NoSplitting`, behavior is identical to today.

### 5D. Content hashing

SHA-256, truncated to 8 hex chars, for cache-busting filenames:
```
entry.js
chunk-Dashboard-a1b2c3d4.js
chunk-Settings-e5f6g7h8.js
shared-i9j0k1l2.js
```

**Files to modify**:
- `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Generate.hs` — **NEW**
- `packages/canopy-core/src/Generate/JavaScript.hs` — add `generateForChunk`
- `packages/canopy-core/src/Generate/JavaScript/Expression.hs` — chunk-aware references
- `packages/canopy-core/canopy-core.cabal` — add module

---

## Phase 6: Manifest & Runtime

### 6A. Manifest module

**New file**: `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Manifest.hs`

```haskell
generateManifest :: [ChunkOutput] -> Builder
generateRuntime :: [ChunkOutput] -> Builder
```

Manifest format:
```json
{
  "entry": "entry.js",
  "chunks": {
    "lazy-Dashboard-a1b2c3d4": "chunk-Dashboard-a1b2c3d4.js",
    "shared-0-i9j0k1l2": "shared-i9j0k1l2.js"
  }
}
```

### 6B. Runtime module

**New file**: `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Runtime.hs`

~40 lines of JavaScript providing:
- `__canopy_register(id, factory)` — register a chunk's factory function
- `__canopy_load(id)` — sync load (if registered) or async load (script tag)
- `__canopy_prefetch(id)` — preload a chunk without executing
- `__canopy_manifest` — embedded chunk-to-URL mapping

Emitted as raw string builder (using `raw-strings-qq` like `Functions.hs`).

**Files**:
- `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Manifest.hs` — **NEW**
- `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Runtime.hs` — **NEW**
- `packages/canopy-core/canopy-core.cabal` — add modules

---

## Phase 7: Output Pipeline Integration

### 7A. Wire code splitting into Make pipeline

**File**: `packages/canopy-terminal/src/Make.hs` (and related)

When lazy imports are detected in the compiled modules, the build pipeline switches from single-file output to split output automatically. No `--split` flag needed — the presence of `lazy import` in source code is the trigger.

Add an escape hatch `--no-split` flag to force single-file output even when lazy imports are present (useful for debugging).

```haskell
-- In Make pipeline, after compilation:
if Set.null allLazyImports
  then generateSingleFile ...    -- existing path
  else generateSplitFiles ...    -- new path
```

### 7B. Extend output to handle multiple files

**File**: `packages/canopy-terminal/src/Make/Output.hs`

```haskell
generateSplitOutput :: BuildContext -> SplitConfig
    -> Compiler.Artifacts -> FilePath -> Task ()
```

Writes:
1. `entry.js` — the entry chunk
2. `chunk-<name>-<hash>.js` — each lazy chunk
3. `shared-<hash>.js` — each shared chunk
4. `manifest.json` — the chunk manifest
5. `*.js.map` — source maps per chunk (dev mode)

### 7C. Add `--no-split` CLI flag

**File**: `packages/canopy-terminal/src/Make/Types.hs`

```haskell
data Flags = Flags
  { ... existing ...
  , _noSplit :: !Bool  -- --no-split to disable automatic splitting
  }
```

**Files to modify**:
- `packages/canopy-terminal/src/Make.hs` — routing logic
- `packages/canopy-terminal/src/Make/Output.hs` — split output
- `packages/canopy-terminal/src/Make/Types.hs` — flag
- `packages/canopy-terminal/src/Make/Environment.hs` — parse flag

---

## Phase 8: Comprehensive Test Suite

### 8A. Parser tests (~15 tests)

**New file**: `test/Unit/Parse/LazyImportTest.hs`

- `lazy import Foo` parses with `_importLazy = True`
- `import Foo` parses with `_importLazy = False`
- `lazy import Foo exposing (bar)` works
- `lazy import Foo as F` works
- `lazy import Foo as F exposing (bar, Baz)` works
- `lazy` as variable name still works in expressions (not a reserved word in expression context)
- Error: `lazy import Basics` rejected
- Error: `lazy foreign import` rejected
- Round-trip: parse then show preserves lazy flag

### 8B. Analysis tests (~30 tests)

**New file**: `test/Unit/Generate/CodeSplit/AnalyzeTest.hs`

- No lazy imports -> single entry chunk, no splitting
- Single lazy module -> entry + lazy chunk
- Multiple lazy modules -> entry + N lazy chunks
- Shared globals extracted when referenced by 2+ chunks
- Kernel globals always in entry chunk
- Circular lazy deps merged into single chunk
- `minSharedRefs` threshold respected
- Every reachable global assigned to exactly one chunk
- Inter-chunk deps computed correctly
- Code motion pushes definitions to deepest possible chunk
- Empty lazy module handled gracefully
- Lazy module with only type exports -> no chunk generated

### 8C. Generation tests (~25 tests)

**New file**: `test/Unit/Generate/CodeSplit/GenerateTest.hs`

- Entry chunk contains runtime code
- Entry chunk contains manifest
- Lazy chunks wrapped in `__canopy_register`
- Cross-chunk references use `__canopy_load`
- Content hashes are deterministic
- Dev mode generates source maps per chunk
- Prod mode applies string pool per chunk
- Same-chunk references remain direct (no unnecessary load)

### 8D. Manifest & runtime tests (~15 tests)

**New file**: `test/Unit/Generate/CodeSplit/ManifestTest.hs`

- Manifest JSON is valid
- All chunks present in manifest
- Hashes in filenames match content
- Runtime includes all required functions
- Runtime handles missing chunks gracefully

### 8E. Integration tests (~15 tests)

**New file**: `test/Integration/CodeSplitIntegrationTest.hs`

- Compile with lazy imports produces multiple JS files
- Entry chunk loads standalone
- Lazy chunks register correctly
- Manifest matches actual files on disk
- Production mode splits correctly
- No lazy imports produces single file (backward compat)
- Invalid lazy module name produces helpful error
- `--no-split` forces single file even with lazy imports

### 8F. Property tests (~10 tests)

**New file**: `test/Property/Generate/CodeSplitProperties.hs`

- Every reachable global appears in exactly one chunk
- Chunk dependency graph is acyclic
- Entry chunk has no incoming chunk dependencies
- Union of all chunk globals equals full reachable set
- Content hashes are deterministic (same input -> same hash)
- Code motion never increases total chunk count
- Shared extraction never duplicates globals

---

## Phase 9: Performance & Polish

### 9A. Chunk size reporting

In verbose/dev mode, report chunk sizes after compilation:
```
Code splitting:
  entry.js          42.3 KB
  chunk-Dashboard-a1b2.js  18.7 KB
  chunk-Settings-e5f6.js   12.1 KB
  shared-i9j0.js     8.4 KB
  Total: 81.5 KB (4 chunks)
```

### 9B. Prefetch hints in HTML

When generating HTML output, emit `<link rel="prefetch">` tags for lazy chunks:
```html
<link rel="prefetch" href="chunk-Dashboard-a1b2c3d4.js">
```

### 9C. Incremental analysis caching

Cache the `ChunkGraph` alongside existing build caches. Only re-analyze when the dependency graph or lazy import set changes.

---

## Files Summary

| File | Change |
|------|--------|
| `packages/canopy-core/src/AST/Source.hs` | Add `_importLazy` field to `Import` |
| `packages/canopy-core/src/AST/Canonical.hs` | Add `_lazyImports` to `Module` |
| `packages/canopy-core/src/Parse/Module.hs` | Parse `lazy` keyword before `import` |
| `packages/canopy-core/src/Parse/Keyword.hs` | Add `lazy_` keyword |
| `packages/canopy-core/src/Canonicalize/Module.hs` | Collect lazy import set |
| `packages/canopy-core/src/Reporting/Error/Syntax.hs` | Error for invalid lazy imports |
| `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Types.hs` | **NEW** Core types |
| `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Analyze.hs` | **NEW** Graph partitioning |
| `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Generate.hs` | **NEW** Per-chunk JS gen |
| `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Manifest.hs` | **NEW** Manifest JSON |
| `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Runtime.hs` | **NEW** Chunk loader JS |
| `packages/canopy-core/src/Generate/JavaScript.hs` | Add `generateForChunk` entry point |
| `packages/canopy-core/src/Generate/JavaScript/Expression.hs` | Chunk-aware cross-references |
| `packages/canopy-core/canopy-core.cabal` | Add 5 new modules |
| `packages/canopy-terminal/src/Make.hs` | Route to split pipeline |
| `packages/canopy-terminal/src/Make/Output.hs` | Split output handling |
| `packages/canopy-terminal/src/Make/Types.hs` | Add `--no-split` flag |
| `packages/canopy-terminal/src/Make/Environment.hs` | Parse flag |
| 6 new test files | ~110 tests total |

---

## Execution Order

| Phase | Description | Risk | Dependencies |
|-------|------------|------|-------------|
| 1 | Parser & AST (`lazy import`) | Low | None — purely additive |
| 2 | Canonicalization (lazy tracking) | Low | Phase 1 |
| 3 | Core types | Low | None — standalone |
| 4 | Graph analysis | High | Phases 2, 3 — core algorithm |
| 5 | Chunk-aware codegen | High | Phases 3, 4 — most invasive |
| 6 | Manifest & runtime | Low | Phase 3 — standalone |
| 7 | Output pipeline | Medium | Phases 4, 5, 6 |
| 8 | Tests | Low | Phases 1-7 |
| 9 | Performance & polish | Low | Phase 7 |

Phases 1+3 and 2+6 can run in parallel. Phase 4 is high-risk because the partitioning + code motion algorithm must handle all edge cases. Phase 5 is high-risk because threading chunk context into expression generation is the most invasive change to existing code.

---

## Verification Protocol

After each phase:
```bash
make build    # zero warnings
make test     # all existing tests pass
```

After Phase 8:
```bash
make test     # all tests including new code splitting tests

# Manual: compile a test app with lazy imports
echo 'lazy import Dashboard' > test-app/src/Main.can
canopy make src/Main.can --output=dist/
ls dist/          # entry.js, chunk-Dashboard-*.js, manifest.json
node dist/entry.js  # entry chunk runs standalone
```

---

## Key Design Decisions

1. **`lazy import` in source code, not config** — intent lives where the dependency is expressed
2. **Types always eager** — no change to type checking or inference; lazy is purely a codegen concern
3. **Automatic shared extraction** — compiler analyzes cross-chunk sharing; developer never manually configures shared chunks
4. **Cross-module code motion** — Canopy's purity guarantee enables Closure Compiler-style optimization that JavaScript bundlers cannot safely do
5. **Synchronous-first loading** — if already loaded, zero overhead; async only for network fetch
6. **No `--split` flag needed** — presence of `lazy import` triggers splitting automatically
7. **Backward compatible** — no lazy imports = identical output to today
8. **Source maps per chunk** — each chunk gets its own `.js.map` in dev mode
