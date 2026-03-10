# Plan 08: TEA at Scale

## Priority: MEDIUM — Tier 2
## Effort: 1-2 weeks (reduced — code splitting infrastructure already exists)
## Depends on: Plan 03 (packages — DONE), Plan 05 (CanopyKit for route code splitting)

> **Status Update (2026-03-10 deep audit):** Code splitting infrastructure is **fully built**
> and substantial (1,547 lines across 5 modules):
>
> - `Generate/JavaScript/CodeSplit/Types.hs` (218 lines) — ChunkId, ChunkKind (Entry/Lazy/Shared),
>   Chunk, ChunkGraph, SplitConfig, SplitOutput, ChunkGraphCache with lens support
> - `Generate/JavaScript/CodeSplit/Analyze.hs` (524 lines) — graph analysis with DFS reachability,
>   incremental caching via `analyzeWithCache`, content-hash graph invalidation, code motion
>   optimization (globals pushed deep in DAG), invariant enforcement (disjoint sets, acyclic DAG)
> - `Generate/JavaScript/CodeSplit/Generate.hs` (572 lines) — per-chunk JS generation with
>   `__canopy_register()` wrapping for lazy chunks, traversal state machine, kernel/cycle/manager
>   /port/enum support
> - `Generate/JavaScript/CodeSplit/Manifest.hs` (155 lines) — JSON manifest with SHA-256 content
>   hashes, cache-busting filenames, dual output (embedded + disk)
> - `Generate/JavaScript/CodeSplit/Runtime.hs` (78 lines) — ~40 lines of JS runtime:
>   `__canopy_register()`, `__canopy_load()`, `__canopy_prefetch()`, promise-based async loading
>
> What remains: **delegation helper library** and **CanopyKit router integration** (Plan 05).

## Problem

Two genuine TEA pain points at scale:

1. **No route-level code splitting in CanopyKit**: Large apps ship all route code upfront, leading to slow initial loads.
2. **Message indirection**: In large apps with deeply nested components, message delegation through multiple layers creates noise.

Both are solvable without introducing mutable state.

## Solution 1: Route-Level Code Splitting

### What Already Exists

The compiler has a full code splitting pipeline in `Generate/JavaScript/CodeSplit/`:
- **ChunkId/ChunkKind/Chunk** types for identifying and classifying chunks
- **ChunkGraph** for tracking dependencies between chunks
- **SplitConfig** with `lazy import` module detection and minimum shared reference thresholds
- **Generate** module that produces per-chunk JavaScript output with content hashes
- **Manifest** generation for the runtime loader
- **Runtime** module for dynamic chunk loading

### What Remains

Integration with CanopyKit (Plan 05) file-based routing:
- Each route module declared as a `lazy import` boundary
- CanopyKit router uses the code split manifest to load route chunks on navigation
- This is primarily a CanopyKit concern, not a compiler concern

## Solution 2: Message Delegation Helpers

Provide standard library helpers for the common "parent delegates to child" pattern:

```canopy
module Platform.Delegate exposing (delegate)

{-| Transform a child's (model, Cmd msg) into a parent's (model, Cmd parentMsg).

    Eliminates the boilerplate of wrapping child messages at every level.
-}
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

Usage:

```canopy
update msg model =
    case msg of
        SettingsMsg subMsg ->
            Settings.update subMsg model.settings
                |> delegate
                    { toModel = \s m -> { m | settings = s }
                    , toMsg = SettingsMsg
                    }
                    model
```

This is a library-level solution, not a compiler change. Include it in canopy/core or a new canopy/platform-helpers package.

## What This Plan Does NOT Include

**Stores/Signals are deferred.** The original plan proposed a `Store` type with mutable state behind a Cmd facade. This introduces hidden mutability — a philosophical departure from Elm. If real user demand emerges after CanopyKit ships, Stores can be revisited.

## Timeline

### Week 1: Delegation Helpers + Documentation
- Implement `Platform.Delegate` module
- Write documentation with examples
- "Scaling TEA" guide with patterns for large applications

### Week 2: Integration Testing
- Build a multi-route sample app with CanopyKit
- Verify code splitting works via existing infrastructure
- Verify delegation helpers reduce boilerplate in the sample app

## Definition of Done

- [x] Code splitting infrastructure exists in compiler
- [ ] `Platform.Delegate` module exists and is documented
- [ ] CanopyKit routes are code-split (verified with bundle analysis)
- [ ] "Scaling TEA" documentation published
- [ ] No new runtime concepts introduced (no Stores, no Signals)
