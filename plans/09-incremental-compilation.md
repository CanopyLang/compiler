# Plan 09: Incremental Compilation + Error Recovery

## Priority: HIGH — Tier 2
## Effort: 4-6 weeks (reduced — query engine is 80% built)
## Depends on: Plan 01 (ESM output)

## Problem

The current compiler re-runs the full pipeline for every change. For a 100-module project, changing one function recompiles everything. Developers expect Vite-speed feedback (< 100ms).

Additionally, the compiler currently stops at the first error in a module. For IDE usage (LSP), **error recovery and partial compilation** are critical — the LSP must provide completions, hover information, and diagnostics even when the file contains errors. Without this, every typo kills the entire IDE experience until the error is fixed.

> **Note (revised):** The canopy-query engine (Salsa-inspired cache with dependency tracking
> and content hashing) is already 80% built. This plan integrates it rather than building from
> scratch. Additionally, error recovery has been added as a requirement for LSP quality.

### Error Recovery Requirements

1. **Parser error recovery**: When a parse error is encountered, skip to the next top-level declaration and continue parsing. Return partial AST + errors.
2. **Type checker error recovery**: When a type error is found in one binding, continue checking other bindings in the module. Return partial type information + errors.
3. **Cross-module partial compilation**: If module A has errors but module B (which doesn't depend on A) is clean, module B should still compile fully. The LSP should show full diagnostics for B.
4. **Stale data on error**: When a module has errors, the LSP should use the last-known-good type information for completions and hover, rather than showing nothing.

## Solution: Salsa-Style Query Architecture

Rewrite the compilation driver to use demand-driven, memoized queries with automatic invalidation. This is the architecture that powers rust-analyzer's sub-50ms response times.

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

When `App.Main.can` changes:
1. `parseModule("App.Main")` is invalidated
2. `canonicalizeModule` is re-run — but if the interface (exported types/functions) didn't change, downstream modules are NOT invalidated
3. This is **early cutoff**: the change stops propagating when results are unchanged

### Query Framework

```haskell
-- Core query types
class Query q where
    type Input q
    type Output q
    execute :: Input q -> CompilerM (Output q)

-- Example queries
data ParseModule = ParseModule
instance Query ParseModule where
    type Input ParseModule = ModuleName
    type Output ParseModule = AST.Source.Module
    execute name = do
        source <- readSourceFile name
        Parse.parse source

data ModuleInterface = ModuleInterface
instance Query ModuleInterface where
    type Input ModuleInterface = ModuleName
    type Output ModuleInterface = Interface  -- exported types/values
    execute name = do
        canonical <- query (CanonicalizeModule name)
        extractInterface canonical
```

### Dependency Tracking

Each query execution automatically records which other queries it called. This builds a dependency graph:

```
generateModule("App.Main")
  └─ optimizeModule("App.Main")
       └─ typeCheckModule("App.Main")
            ├─ canonicalizeModule("App.Main")
            │    └─ parseModule("App.Main")
            │         └─ readFile("src/App/Main.can")   ← filesystem input
            └─ moduleInterface("Canopy.Core.List")      ← imported module
                 └─ canonicalizeModule("Canopy.Core.List")
                      └─ ... (already cached, stdlib doesn't change)
```

### Invalidation Algorithm

Using the **try-mark-green** approach from Rust:

1. File change detected → mark `readFile("src/App/Main.can")` as RED
2. Walk dependents:
   - `parseModule("App.Main")` → parent is RED → re-execute → compare result with cache
   - If parse result changed → mark RED, continue propagation
   - If parse result same (e.g., only whitespace changed) → mark GREEN, **stop propagation**
3. Continue until all reachable queries are GREEN or RED
4. Only RED queries produce new outputs

### Durability Levels

Queries have durability annotations:

```haskell
data Durability = Volatile | Normal | Durable

-- Filesystem inputs: volatile (change frequently)
-- User module compilation: normal
-- Stdlib compilation: durable (never changes within a session)
```

When user code changes, durable queries (stdlib) are never re-checked. This skips the entire stdlib subgraph.

### Persistence

The query cache persists to disk between compiler invocations:

```
.canopy-cache/
  queries.db          -- SQLite database of query inputs/outputs/fingerprints
  artifacts/
    App.Main.iface    -- serialized module interface
    App.Main.opt      -- serialized optimized AST
    App.Main.js       -- generated JavaScript (final output)
```

On startup, the compiler loads the cache and only re-executes invalidated queries.

## Implementation Phases

### Phase 1: Query framework (Weeks 1-2)
- Define the `Query` typeclass and memoization infrastructure
- Implement dependency tracking (which query called which)
- Implement the try-mark-green invalidation algorithm
- No persistence yet — in-memory only

### Phase 2: Wrap existing passes as queries (Weeks 3-4)
- `parseModule`, `canonicalizeModule`, `typeCheckModule`, `optimizeModule`, `generateModule`
- Extract module interface as a separate query (enables early cutoff)
- Wire up dependency tracking across passes

### Phase 3: File watching integration (Week 5)
- Integrate with filesystem watcher (inotify/FSEvents)
- On file change, invalidate the corresponding `readFile` query
- Re-execute only affected query chain
- Report results to LSP/Vite plugin

### Phase 4: Disk persistence (Weeks 6-7)
- Serialize query results to disk (SQLite or custom binary format)
- Fingerprint-based comparison (hash of query output)
- Warm startup: load cache, verify fingerprints, skip unchanged queries

### Phase 5: LSP integration (Week 8)
- The LSP server uses the same query engine
- Type information available without full compilation
- Hover, go-to-definition, completions served from cached query results
- Error diagnostics update incrementally as the user types

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
- **Migration complexity**: Restructuring the compiler driver is high-risk. Solution: keep the old driver as a fallback, run both in CI and compare results.
