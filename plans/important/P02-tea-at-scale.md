# P02: TEA at Scale

## Priority: HIGH -- Phase 1 (Finish Line)
## Effort: 3-4 days
## Depends on: P05 (CanopyKit) for router integration

## Status Overview

Code splitting is **100% complete** in the compiler. The entire 5-module pipeline (1,547 lines) is built, tested, and production-ready. What remains is a small library module (~50 lines of Canopy code) and integration with CanopyKit's file-based router.

| Component | Status |
|-----------|--------|
| Code splitting types (ChunkId, ChunkKind, Chunk, ChunkGraph) | DONE |
| Lazy import parsing and validation | DONE |
| Chunk analysis (DFS, shared extraction, code motion) | DONE |
| Incremental analysis with content-hash invalidation | DONE |
| Per-chunk JS generation with `__canopy_register()` wrapping | DONE |
| Content-addressable manifest with SHA-256 | DONE |
| HTML prefetch hints | DONE |
| Runtime loader (`__canopy_register`, `__canopy_load`, `__canopy_prefetch`) | DONE |
| Unit + property + integration tests | DONE |
| Platform.Delegate library module | NOT BUILT |
| CanopyKit router integration (auto lazy-import per route) | NOT BUILT |
| Documentation (performance tuning, advanced patterns) | NOT BUILT |

## What's Done (with file references)

### Code Splitting Pipeline (1,547 lines, fully tested)

- **`Generate/JavaScript/CodeSplit/Types.hs`** (218 lines) -- ChunkId, ChunkKind (Entry/Lazy/Shared), Chunk, ChunkGraph, SplitConfig, SplitOutput, ChunkGraphCache with lens support
- **`Generate/JavaScript/CodeSplit/Analyze.hs`** (524 lines) -- Graph analysis with DFS reachability, incremental caching via `analyzeWithCache`, content-hash graph invalidation, code motion optimization (globals pushed deep in DAG), invariant enforcement (disjoint sets, acyclic DAG)
- **`Generate/JavaScript/CodeSplit/Generate.hs`** (572 lines) -- Per-chunk JS generation with `__canopy_register()` wrapping for lazy chunks, traversal state machine, kernel/cycle/manager/port/enum support
- **`Generate/JavaScript/CodeSplit/Manifest.hs`** (155 lines) -- JSON manifest with SHA-256 content hashes, cache-busting filenames, dual output (embedded + disk)
- **`Generate/JavaScript/CodeSplit/Runtime.hs`** (78 lines) -- ~40 lines of JS runtime: `__canopy_register()`, `__canopy_load()`, `__canopy_prefetch()`, promise-based async loading

### Lazy Import Support

- `lazy import` syntax parsed in the module parser
- Lazy imports validated during canonicalization
- Lazy import boundaries used as chunk split points in analysis

## What Remains

### Task 1: Platform.Delegate library module (1 day)

A ~50 line Canopy module providing standard delegation helpers for the common "parent delegates to child" pattern:

```canopy
module Platform.Delegate exposing (delegate)

delegate :
    { toModel : childModel -> parentModel -> parentModel
    , toMsg : childMsg -> parentMsg
    }
    -> ( childModel, Cmd childMsg )
    -> parentModel
    -> ( parentModel, Cmd parentMsg )
delegate config ( childModel, childCmd ) parentModel =
    ( config.toModel childModel parentModel
    , Cmd.map config.toMsg childCmd
    )
```

This eliminates the boilerplate of wrapping child messages at every nesting level. It is a library-level solution, not a compiler change. Goes in canopy/core or a new canopy/platform-helpers package.

### Task 2: CanopyKit router integration with code splitting (1-2 days)

Each CanopyKit route module should automatically be declared as a `lazy import` boundary so that route-level code splitting happens without developer configuration. The CanopyKit router uses the code split manifest to load route chunks on navigation.

This is primarily a CanopyKit concern. The compiler-side code splitting infrastructure is complete and ready.

### Task 3: Documentation (1 day)

- "Scaling TEA" guide with patterns for large applications
- Code splitting performance tuning guide (minimum shared reference thresholds, chunk size targets)
- Advanced patterns: prefetching on hover, preloading adjacent routes

## What This Plan Does NOT Include

**Stores/Signals are deferred.** The original plan considered a `Store` type with mutable state behind a Cmd facade. This introduces hidden mutability -- a philosophical departure from Elm/Canopy. If real user demand emerges after CanopyKit ships, Stores can be revisited.

## Dependencies

- P05 (CanopyKit) for the router integration piece. The delegation helpers and documentation can proceed independently.

## Definition of Done

- [x] Code splitting infrastructure exists in compiler (1,547 lines, 5 modules)
- [x] Lazy import parsing and validation
- [x] Chunk analysis with DFS, shared extraction, code motion
- [x] Runtime loader with promise-based async loading
- [x] Content-addressable manifest with SHA-256
- [x] HTML prefetch hints generation
- [x] Unit + property + integration tests passing
- [ ] `Platform.Delegate` module exists and is documented
- [ ] CanopyKit routes are code-split (verified with bundle analysis)
- [ ] "Scaling TEA" documentation written
- [ ] No new runtime concepts introduced (no Stores, no Signals)
