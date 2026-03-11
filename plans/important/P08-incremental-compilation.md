# Plan 09: Incremental Compilation + Error Recovery

## Priority: HIGH — Tier 2
## Effort: 5-7 weeks (revised — query engine is ~40% built, not 80%)
## Depends on: Plan 01 (ESM output)

> **Status Update (2026-03-10 deep audit):** The canopy-query engine exists but is
> **~40% built**, not 80%. Confirmed via code inspection.
>
> **What exists (verified):**
> - `Query/Engine.hs` (235 lines) — IORef-based state, `runQuery`/`invalidateQuery`/`clearCache`,
>   cache hit/miss tracking, `LogEvent` debug logging
> - `Query/Simple.hs` (139 lines) — GADT `Query` type with `ParseModuleQuery`, `ContentHash`
>   via SHA-256, `executeQuery` delegation, global parse cache via `unsafePerformIO`
> - `Parse/Cache.hs` (73 lines) — content-hash based parse result caching with validation
> - `Driver.hs` (463 lines) — query-aware driver with per-phase timing, parallel compilation
>   via worker pool, timeout protection (5 min/module)
> - Unit tests: `test/Unit/Query/EngineTest.hs` (244 lines) covering init, caching, invalidation
>
> **What does NOT exist (verified — aspirational comments in code are misleading):**
> - **No dependency tracking** — `EngineState` has no `engineDeps` field. `runQuery` does NOT
>   record which queries each execution calls. No dependency graph exists.
> - **Only parse is cached** — `compileModuleCore` always re-runs canonicalize, type-check,
>   optimize, and generate even when parse is cached. No downstream phase caching.
> - **No try-mark-green invalidation** — no RED/GREEN marking, no early cutoff when
>   intermediate results don't change.
> - **No durability levels** — stdlib re-checked every time despite never changing.
> - **No disk persistence** — in-memory only, lost on restart.
> - **LSP doesn't use query engine** — `language-server/` has its own tree-sitter TypeScript
>   type checker, completely separate from the Haskell query engine.
> - **No error recovery** — parser stops at first error, no partial AST generation.

## Problem

The current compiler re-runs the full pipeline for every change. For a 100-module project, changing one function recompiles everything. Developers expect Vite-speed feedback (< 100ms).

Additionally, the compiler currently stops at the first error in a module. For IDE usage (LSP), **error recovery and partial compilation** are critical — the LSP must provide completions, hover information, and diagnostics even when the file contains errors.

### Error Recovery Requirements

1. **Parser error recovery**: When a parse error is encountered, skip to the next top-level declaration and continue parsing. Return partial AST + errors.
2. **Type checker error recovery**: When a type error is found in one binding, continue checking other bindings in the module. Return partial type information + errors.
3. **Cross-module partial compilation**: If module A has errors but module B (which doesn't depend on A) is clean, module B should still compile fully.
4. **Stale data on error**: When a module has errors, the LSP should use the last-known-good type information for completions and hover.

## Solution: Salsa-Style Query Architecture

Extend the existing query engine to a demand-driven, memoized query system with automatic invalidation.

### Core Concept

Every compilation step becomes a **query** that takes inputs and produces outputs. Results are cached. When inputs change, only affected queries re-execute.

```
parseModule("App.Main") → AST.Source
    ↓ (depends on)
canonicalizeModule("App.Main") → AST.Canonical
    ↓ (depends on parseModule + imported interfaces)
typeCheckModule("App.Main") → Typed annotations
    ↓ (depends on canonicalizeModule)
optimizeModule("App.Main") → AST.Optimized
    ↓ (depends on typeCheckModule)
generateModule("App.Main") → JavaScript
```

### Dependency Tracking (NOT YET BUILT)

Each query execution must automatically record which other queries it called. This builds a dependency graph. The existing `EngineState` needs:

```haskell
data EngineState = EngineState
  { engineCache :: !(Map Query CacheEntry),
    engineRunning :: !(Set Query),
    engineDeps :: !(Map Query (Set Query)),  -- NEW: dependency graph
    engineHits :: !Int,
    engineMisses :: !Int
  }
```

### Invalidation Algorithm (NOT YET BUILT)

Using the **try-mark-green** approach:

1. File change detected → mark `readFile("src/App/Main.can")` as RED
2. Walk dependents:
   - `parseModule("App.Main")` → parent is RED → re-execute → compare result with cache
   - If parse result changed → mark RED, continue propagation
   - If parse result same (e.g., only whitespace changed) → mark GREEN, **stop propagation**
3. Continue until all reachable queries are GREEN or RED
4. Only RED queries produce new outputs

### Durability Levels (NOT YET BUILT)

```haskell
data Durability = Volatile | Normal | Durable

-- Filesystem inputs: volatile (change frequently)
-- User module compilation: normal
-- Stdlib compilation: durable (never changes within a session)
```

## Implementation Phases

### Phase 1: Dependency tracking in query engine (Weeks 1-2)
- Extend `EngineState` with dependency graph
- Modify `runQuery` to record which queries each execution calls
- Implement try-mark-green invalidation
- Wrap canonicalize, typecheck, optimize, generate as cached queries (currently only parse is cached)
- Test: changing a module only recompiles that module and its dependents

### Phase 2: Multi-phase caching (Weeks 3-4)
- Cache canonicalization results with interface extraction
- Cache type checking results
- Cache optimization results
- **Early cutoff**: if a module's interface didn't change, don't recompile downstream modules
- Extract module interface as a separate query

### Phase 3: Error recovery (Week 5)
- Parser error recovery: skip to next top-level declaration on error
- Type checker error recovery: continue checking other bindings on error
- Return partial results + errors from each phase
- Last-known-good fallback for LSP

### Phase 4: File watching + LSP integration (Weeks 6-7)
- Integrate with filesystem watcher (inotify/FSEvents)
- On file change, invalidate the corresponding `readFile` query
- Re-execute only affected query chain
- Expose query engine to LSP (currently the TypeScript LSP is completely separate)
- Disk persistence (SQLite or binary format) for warm startup

## Performance Targets

| Scenario | Current | Target |
|----------|---------|--------|
| Full build (100 modules) | ~5s | ~5s (no change) |
| Single file change | ~5s (full rebuild) | < 100ms |
| Whitespace-only change | ~5s | < 10ms (early cutoff) |
| Cold start (cached) | ~5s | < 500ms |
| LSP hover response | ~2s | < 50ms |

## Risks

- **Haskell's lazy evaluation** complicates caching — thunks can't be serialized. Solution: force evaluation before caching.
- **Cache invalidation correctness**: If the cache incorrectly marks a query as GREEN, we get stale results. Solution: comprehensive testing with property-based tests verifying that cached results match fresh computation.
- **LSP integration complexity**: The TypeScript LSP has its own type checker. Integrating the Haskell query engine requires either: (a) the LSP calls the Haskell compiler as a server, or (b) the Haskell compiler provides an LSP server directly. Option (a) is more practical short-term.
- **Migration complexity**: Restructuring the compiler driver is high-risk. Solution: keep the old driver as a fallback, run both in CI and compare results.
