# Plan 21: Transparent Concurrency

## Priority: LOW — Tier 4
## Effort: 6-8 weeks
## Depends on: Plan 01 (ESM), Plan 16 (effects, optional but helpful)

## Problem

Web Workers enable true parallelism in the browser, but they're painful to use:
- Manual serialization/deserialization of messages
- No shared state (structured cloning is expensive)
- Separate bundle management
- Callback-based communication

A pure functional language can make this invisible.

## Key Insight

Canopy functions are pure. Pure functions have no side effects, no shared mutable state, no ordering dependencies. The compiler can **prove** that parallel execution is safe. No developer annotation needed.

## Solution

### Automatic Parallelization

```canopy
-- Developer writes sequential-looking code:
processData : List Record -> Task Never (List Result)
processData records =
    records
        |> List.map transform      -- pure function
        |> Task.succeed

-- With the parallel combinator:
processDataParallel : List Record -> Task Never (List Result)
processDataParallel records =
    records
        |> List.chunks 1000
        |> Task.parallel (List.map processChunk)
        |> Task.map List.concat
```

`Task.parallel` is the opt-in signal. The compiler:
1. Verifies all functions in the parallel block are pure (no effects)
2. Generates Web Worker code for the parallel branches
3. Handles serialization automatically (knows the types)
4. Uses Transferable ArrayBuffers (safe because data is immutable)
5. Aggregates results on the main thread

### Generated Code

```javascript
// Main thread:
export async function processDataParallel(records) {
  const chunks = listChunks(1000, records);
  const workers = chunks.map(chunk => {
    const worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
    const buffer = serialize(chunk);  // compiler-generated serializer
    return new Promise(resolve => {
      worker.onmessage = e => { resolve(deserialize(e.data)); worker.terminate(); };
      worker.postMessage(buffer, [buffer]);  // transfer, not clone
    });
  });
  const results = await Promise.all(workers);
  return listConcat(results);
}

// worker.js (generated):
import { processChunk } from './App.js';
self.onmessage = (e) => {
  const input = deserialize(e.data);
  const result = processChunk(input);
  const buffer = serialize(result);
  self.postMessage(buffer, [buffer]);
};
```

### Efficient Serialization

The compiler generates binary serializers for every type used in parallel blocks:

```haskell
-- For type: { id : Int, name : String, score : Float }
-- Generate: write Int32, write String (length-prefixed UTF-8), write Float64
-- This is 10-100x faster than structured cloning of JS objects
```

Because Canopy knows the exact type, it can generate packed binary encoding instead of using the slow structured clone algorithm.

### Worker Pool

For repeated parallel operations, maintain a worker pool instead of creating/destroying workers:

```canopy
-- The runtime manages a pool of N workers (default: navigator.hardwareConcurrency)
-- Task.parallel reuses workers from the pool
-- Workers are pre-initialized with the compiled module code
```

## Implementation Phases

### Phase 1: Task.parallel primitive (Weeks 1-2)
- `Task.parallel : List (Task Never a) -> Task Never (List a)`
- Basic implementation: runs tasks sequentially (no actual parallelism yet)
- Type checking ensures tasks are pure (no effects)

### Phase 2: Binary serialization (Weeks 3-4)
- Generate binary encoder/decoder for types used in parallel blocks
- Use ArrayBuffer + DataView for packed encoding
- Benchmark against structured cloning

### Phase 3: Web Worker code generation (Weeks 5-6)
- Compiler emits worker entry point modules
- Worker modules contain only the functions needed for the parallel task
- Tree-shake aggressively — workers should be minimal
- Main thread code handles worker lifecycle

### Phase 4: Worker pool and optimization (Weeks 7-8)
- Worker pool management
- Transferable ArrayBuffer usage (zero-copy transfer)
- Automatic chunk sizing based on data size and available cores
- Fallback to main thread for small datasets (where worker overhead exceeds benefit)

## When NOT to Parallelize

The compiler should avoid parallelism when:
- Data set is small (< 1000 items) — worker overhead dominates
- The operation is I/O-bound, not CPU-bound
- The function accesses browser APIs (DOM, fetch) — these are main-thread-only

These checks are compile-time. The compiler warns if `Task.parallel` is used with effectful functions:

```
── CANNOT PARALLELIZE ──────────────── src/App.can

Task.parallel requires all functions to be pure, but `fetchUser`
uses the Http effect:

    15│  users <- Task.parallel (List.map fetchUser userIds)

Consider using Task.sequence instead, or restructure to separate
the pure computation from the effectful parts.
```

## Risks

- **Worker creation overhead**: Creating workers is ~50ms each. Mitigate with worker pooling.
- **Serialization cost**: For small data, serialization overhead exceeds parallelism benefit. Mitigate with automatic threshold detection.
- **Module duplication**: Workers need their own copy of the code. Mitigate with shared modules via SharedArrayBuffer or worker-specific tree-shaking.
