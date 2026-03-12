# Plan 23: Transparent Concurrency

## Priority: LOW -- Tier 4
## Status: ~20% complete
## Effort: 5-6 weeks (revised down from 6-8 -- worker library already exists)
## Depends on: Plan 01 (ESM), Plan 16 (effects, optional but helpful)

## What Already Exists

### Web Worker Library (`canopy/web-worker` -- 4 files)
- Worker creation and lifecycle management
- Worker pool with configurable size (defaults to `navigator.hardwareConcurrency`)
- Message passing between main thread and workers
- Structured cloning for data transfer

### Related Infrastructure
- `canopy/streams` -- streaming data processing primitives
- Capability system can enforce purity requirements at compile time
- ESM code generation enables `import.meta.url`-based worker instantiation

## What Remains

### Phase 1: `Task.parallel` Primitive (Weeks 1-2)
- `Task.parallel : List (Task Never a) -> Task Never (List a)`
- Compiler verifies all functions in parallel blocks are pure (no effects)
- Initial implementation: runs tasks sequentially as correctness baseline
- Type checking ensures tasks have `Never` error type (pure computation only)

### Phase 2: Binary Serialization Codegen (Weeks 3-4)
- Compiler generates binary encoder/decoder for types used in parallel blocks
- Use `ArrayBuffer` + `DataView` for packed encoding (10-100x faster than structured cloning)
- Canopy knows exact types at compile time, enabling optimal binary layout
- Transferable ArrayBuffer usage (zero-copy transfer, safe because data is immutable)

### Phase 3: Worker Code Generation (Weeks 5-6)
- Compiler emits worker entry point modules automatically
- Worker modules contain only the functions needed (aggressive tree-shaking)
- Integration with existing `canopy/web-worker` pool management
- Automatic chunk sizing based on data size and available cores
- Fallback to main thread for small datasets (where worker overhead exceeds benefit)

## Key Insight

Canopy functions are pure. Pure functions have no side effects, no shared mutable state, no ordering dependencies. The compiler can **prove** that parallel execution is safe. No developer annotation needed beyond `Task.parallel`.

## API

```canopy
-- Developer writes:
processDataParallel : List Record -> Task Never (List Result)
processDataParallel records =
    records
        |> List.chunks 1000
        |> Task.parallel (List.map processChunk)
        |> Task.map List.concat
```

The compiler:
1. Verifies `processChunk` is pure (no effects)
2. Generates Web Worker code for the parallel branches
3. Handles serialization automatically (knows the types)
4. Uses Transferable ArrayBuffers (safe because data is immutable)
5. Aggregates results on the main thread

## When NOT to Parallelize

The compiler warns if `Task.parallel` is used with effectful functions:

```
-- CANNOT PARALLELIZE -------------------- src/App.can

Task.parallel requires all functions to be pure, but `fetchUser`
uses the Http effect:

    15|  users <- Task.parallel (List.map fetchUser userIds)

Consider using Task.sequence instead, or restructure to separate
the pure computation from the effectful parts.
```

Automatic avoidance when:
- Data set is small (< 1000 items) -- worker overhead dominates
- The operation is I/O-bound, not CPU-bound
- The function accesses browser APIs (DOM, fetch) -- main-thread-only

## Risks

- **Worker creation overhead**: Creating workers is ~50ms each. Existing `canopy/web-worker` pool mitigates this.
- **Serialization cost**: For small data, serialization overhead exceeds parallelism benefit. Automatic threshold detection needed.
- **Module duplication**: Workers need their own copy of the code. Mitigate with worker-specific tree-shaking.
