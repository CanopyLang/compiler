# Plan 07: Incremental Compilation + Error Recovery

## Priority: HIGH -- Tier 2
## Effort: 5-6 weeks remaining (revised 2026-03-11)
## Depends on: Plan 01 (ESM output)
## Completion: ~60-65%

---

## Status Summary (2026-03-11 deep audit)

The query engine and driver are substantially built. Multi-phase caching, dependency
graph structures, early cutoff logic, interface hashing, worker pool, and timing all
exist and are wired together. The major gaps are: persistence is stubbed, dependency
tracking is structural-only (never called automatically during query execution),
worker pools create isolated engines instead of sharing cache, and error recovery
does not exist.

### What EXISTS (verified via source inspection)

| Component | File | Lines | Status |
|-----------|------|-------|--------|
| Query engine | `canopy-query/src/Query/Engine.hs` | 383 | IORef-based state, `runQuery`/`lookupQuery`/`storeQuery`, cache hit/miss stats, `invalidateAndPropagate` with try-mark-green logic, `runQueryWithFallback` for stale-on-error, `Durability` type defined |
| Query types (GADT) | `canopy-query/src/Query/Simple.hs` | 220 | `ParseModuleQuery`, `CanonicalizeQuery`, `TypeCheckQuery`, `OptimizeQuery`, `InterfaceQuery` with `ContentHash` via SHA-256, global parse cache |
| Parse cache | `canopy-query/src/Parse/Cache.hs` | 72 | Content-hash based parse result caching, cache hit/miss with content validation |
| Interface hashing | `canopy-query/src/Query/Interface.hs` | 76 | `computeInterfaceHash` (values/unions/aliases/binops), `computeExportHash` (names only) for early cutoff |
| Persistence (STUB) | `canopy-query/src/Query/Persistence.hs` | 68 | `saveCache` writes only cache size as text, `loadCache` returns immediately without populating |
| Driver | `canopy-driver/src/Driver.hs` | 482 | Per-phase caching (`runCachedCanon`, `runCachedTypeCheck`, `runCachedOptimize`), input hash composition via `combineHashes`, timeout protection (5 min/module), per-phase timing, `compileFromSource` |
| Worker pool | `canopy-driver/src/Worker/Pool.hs` | 278 | Configurable thread count, channel-based task dispatch, progress tracking with callback, exception handling |
| Engine tests | `test/Unit/Query/EngineTest.hs` | 244 | Engine init, cache hit/miss, invalidation, stats |

**Total existing code: ~1,579 lines across 7 modules + 244 lines of tests.**

### What does NOT work (verified)

1. **Persistence is stubbed.** `saveCache` writes `show cacheSize` to a file. `loadCache` checks if the file exists and returns. No binary serialization, no cache population on load.

2. **Automatic dependency tracking never fires.** `recordDependency` exists and `engineDeps`/`engineReverseDeps` fields exist in `EngineState`, but `storeQuery` is the only caller, and it only records a parent when explicitly passed `Just parentQuery`. During actual query execution in `executeAndCache`, no parent is passed. The Driver passes `Nothing` for the parse-to-canon edge and `Just canonQuery` for type-check and optimize, so only partial dependency edges exist.

3. **Cross-module dependency tracking absent.** No module-level import graph. If module A imports module B, changing B does not invalidate A. The dependency graph only tracks intra-module phase dependencies.

4. **Worker pool creates isolated engines.** `createPool` calls `Engine.initEngine` internally (line 126), creating a fresh engine per pool. Workers do not share cached results with the caller's engine or with each other.

5. **Durability never enforced.** The `Durability` type exists with `Volatile | Normal | Durable` constructors. All `CacheEntry` values are hardcoded to `Normal` in `insertCacheEntry`. No code checks durability to skip re-validation of stdlib modules.

6. **Generate phase not cached.** Parse, canonicalize, type-check, and optimize are cached. JavaScript generation is always re-run.

7. **Error recovery absent.** Parser stops at first error. Type checker stops at first error in a module. No partial AST, no partial type information.

8. **File watching not integrated.** No filesystem watcher. No automatic invalidation on file change.

9. **LSP uses separate system.** The TypeScript language server has its own tree-sitter type checker, completely independent of the Haskell query engine.

---

## Problem

The current compiler re-runs the full pipeline for every change. For a 100-module project, changing one function recompiles everything. Developers expect Vite-speed feedback (< 100ms).

For IDE usage (LSP), error recovery and partial compilation are critical -- the LSP must provide completions, hover information, and diagnostics even when the file contains errors.

## Solution: Salsa-Style Query Architecture

Extend the existing query engine to a demand-driven, memoized query system with automatic invalidation and cross-module dependency tracking.

### Architecture (existing)

```
parseModule("App.Main") -> AST.Source        [CACHED]
    |
canonicalizeModule("App.Main") -> AST.Canonical  [CACHED]
    |
typeCheckModule("App.Main") -> Typed annotations  [CACHED]
    |
optimizeModule("App.Main") -> AST.Optimized       [CACHED]
    |
generateModule("App.Main") -> JavaScript           [NOT CACHED]
```

### Dependency Graph (partially built)

`EngineState` already has `engineDeps` and `engineReverseDeps` fields. `invalidateAndPropagate` already implements try-mark-green with early cutoff. The gap is that dependency edges are only recorded for type-check and optimize phases (via explicit `Just parentQuery` in the Driver), not automatically during query execution.

### Interface Hashing (built)

`Query.Interface.computeInterfaceHash` hashes exported values, unions, aliases, and binops. `computeExportHash` provides a lighter structural check. These enable early cutoff: if a module's interface hash is unchanged after re-canonicalization, downstream modules skip recompilation.

---

## Remaining Work

### Phase 1: Persistence -- binary serialization of cache entries (1 week)

**Current state:** `Persistence.hs` is 68 lines, fully stubbed.

**Work needed:**
- Implement binary serialization for `CacheEntry`, `QueryResult`, and `EngineState` using `Data.Serialize` or `Data.Binary`
- Handle `Src.Module`, `Can.Module`, `Opt.LocalGraph`, and `Interface.Interface` serialization (these are the `QueryResult` payloads)
- Force evaluation (via `NFData` or `deepseq`) before serializing to avoid thunks
- Implement `loadCache` to deserialize and populate `engineCache`
- Add version tag to cache format for forward compatibility
- Handle corrupt/incompatible cache gracefully (delete and cold-start)
- Wire `saveCache`/`loadCache` into `Driver.compileModule` entry/exit

**Risk:** AST types may not have `Serialize`/`Binary` instances. May need to derive or hand-write them for `AST.Source`, `AST.Canonical`, `AST.Optimized`, and `Canopy.Interface`.

### Phase 2: Shared worker cache (3 days)

**Current state:** `Worker.Pool.createPool` calls `Engine.initEngine` on line 126, creating a new engine per pool. Each worker compiles against an empty cache.

**Work needed:**
- Accept an external `QueryEngine` in `createPool` instead of creating one internally
- Pass the caller's engine to `compileTaskFn`
- Add `atomicModifyIORef'` to `Engine.hs` for thread-safe cache updates (currently uses non-atomic `modifyIORef'`)
- Update `Driver.compileModulesParallel` to create one engine and pass it to the pool

### Phase 3: Automatic dependency tracking (1-2 weeks)

**Current state:** `recordDependency` exists but is only called with explicit parent in 2 of 4 cache-store sites. No cross-module import graph.

**Work needed:**
- Add a "current query" stack to `EngineState` (push on `runQuery` entry, pop on exit)
- Automatically call `recordDependency` when a query reads another query's result
- Build a module-level import graph from `Src.Module` imports during the parse phase
- When a file changes, invalidate its parse query and propagate through the module import graph to all transitive dependents
- Wire `computeInterfaceHash` into the propagation to enable early cutoff at module boundaries

### Phase 4: File watching + invalidation (1 week)

**Work needed:**
- Integrate `fsnotify` (Haskell library) for filesystem watching
- On file change, compute new content hash and compare with cached hash
- If changed, call `invalidateAndPropagate` on the file's parse query
- Debounce rapid changes (editor save + format = 2 events)
- Wire into `canopy make --watch` and dev server

### Phase 5: Durability enforcement (3 days)

**Current state:** `Durability` type exists, all entries hardcoded to `Normal`.

**Work needed:**
- Mark stdlib queries as `Durable` when caching
- Skip re-validation of `Durable` entries within a session
- Mark user module queries as `Normal`
- Clear `Volatile` entries between build cycles

### Phase 6: Error recovery (2-3 weeks, can be phased)

**Current state:** No error recovery at any phase.

**Work needed (can be split into sub-phases):**

6a. Parser error recovery (1 week):
- On parse error, skip to the next top-level declaration and continue
- Return partial `Src.Module` with successfully parsed declarations + list of errors
- Requires modifying `Parse/Module.hs` and `Parse/Declaration.hs`

6b. Type checker error recovery (1 week):
- On type error in one binding, continue checking other bindings
- Return partial type annotations + list of errors
- Requires modifying `Type/Constrain/Module.hs` and `Type/Solve.hs`

6c. Stale-on-error fallback (3 days):
- `runQueryWithFallback` already exists in `Engine.hs`
- Wire it into the Driver so that when a phase fails, the last-known-good result is returned for downstream consumers (especially LSP)

### Phase 7: LSP integration (2-3 weeks, separate effort)

**Current state:** TypeScript LSP is independent. Would require either:
- (a) Haskell compiler exposes a persistent query server (LSP protocol or custom RPC)
- (b) The TypeScript LSP shells out to the Haskell compiler

This is a separate effort and should be its own plan. Not blocking incremental compilation.

---

## Performance Targets

| Scenario | Current | Target |
|----------|---------|--------|
| Full build (100 modules) | ~5s | ~5s (no change) |
| Single file change (body only) | ~5s (full rebuild) | < 100ms |
| Whitespace-only change | ~5s | < 10ms (early cutoff) |
| Cold start with disk cache | ~5s | < 500ms |
| Interface-only change | ~5s | < 500ms (dependents recompile) |

## Risks

- **Serialization of AST types**: May require significant boilerplate for `Binary`/`Serialize` instances across `AST.Source`, `AST.Canonical`, `AST.Optimized`, and `Canopy.Interface`.
- **Thread safety**: Upgrading from `modifyIORef'` to `atomicModifyIORef'` may surface latent race conditions in the cache.
- **Cache correctness**: If the dependency graph misses an edge, cached results go stale silently. Requires property tests comparing cached vs. fresh computation.
- **Error recovery complexity**: Elm's parser uses a continuation-passing style that makes recovery non-trivial. May need to restructure parser internals.
- **LSP integration**: Deferred to a separate plan. The TypeScript LSP divergence is a strategic question, not just an engineering task.

## Key Files

```
packages/canopy-query/src/Query/Engine.hs       -- Query engine (383 lines)
packages/canopy-query/src/Query/Simple.hs        -- Query GADT + types (220 lines)
packages/canopy-query/src/Query/Interface.hs     -- Interface hashing (76 lines)
packages/canopy-query/src/Query/Persistence.hs   -- Persistence STUB (68 lines)
packages/canopy-query/src/Parse/Cache.hs         -- Parse cache (72 lines)
packages/canopy-driver/src/Driver.hs             -- Compiler driver (482 lines)
packages/canopy-driver/src/Worker/Pool.hs        -- Worker pool (278 lines)
test/Unit/Query/EngineTest.hs                    -- Engine tests (244 lines)
```
