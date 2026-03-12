# Plan 18: WebAssembly Backend

## Priority: LOW -- Tier 4
## Status: 0% complete
## Effort: 12-16 weeks
## Depends on: Stable compiler, Plan 01 (ESM for JS parts)

> **Note (revised 2026-03):** Elevated consideration from original Tier 4. Key developments:
>
> - **Wasm 3.0** became the W3C standard in September 2025
> - **WasmGC** shipped in all major browsers -- languages with GC (like Canopy) can now compile
>   to Wasm without shipping their own garbage collector
> - **Google Sheets** migrated its calculation engine to WasmGC and runs **2x faster** than JS
> - **Figma** saw **3x load time improvements** with their Wasm-compiled C++ graphics engine
> - For CPU-intensive tasks, Wasm delivers **5-15x performance improvements** over JavaScript
>
> A hybrid JS+Wasm strategy (JS for DOM, Wasm for compute-heavy modules like JSON parsing,
> data transformation, CRDT merging) would give Canopy a genuine "can't do this in React" story.
> WasmGC eliminates the GC-shipping problem that previously made this impractical for functional
> languages.

## What Already Exists

Nothing. This is a greenfield effort. No WASM code generator exists in the compiler.

**Related infrastructure that helps:**
- ESM code generation (Plan 01) provides the JS-side module format for hybrid mode
- Capability system (Plan 01) can enforce API restrictions for WASI target
- 72 stdlib packages provide the JS-side ecosystem that WASM modules interop with
- `canopy/web-worker` (4 files) demonstrates the worker model that hybrid WASM would extend

## What Remains

### Phase 1: WASM code generator for pure functions (Weeks 1-4)
- New module: `Generate/Wasm.hs`
- Emit WasmGC structs for ADTs and records
- Emit functions for pure Canopy functions
- Handle pattern matching via `ref.test`/`ref.cast`
- Handle tail calls via `return_call`
- Target: compile a pure Canopy module (no effects) to WASM

### Phase 2: WASM-JS bridge (Weeks 5-8)
- Model serialization between WASM and JS
- Message passing: JS events -> WASM update -> JS render
- Effect dispatch: WASM update returns effect descriptors, JS executes them
- Integration with reactive rendering pipeline

### Phase 3: WASI target (Weeks 9-12)
- Compile entire Canopy programs to WASM + WASI
- No DOM, no browser -- server-side execution
- HTTP server via WASI HTTP API
- File system access via WASI filesystem API
- Use case: CanopyKit SSR without Node.js

### Phase 4: Optimization (Weeks 13-16)
- Binaryen optimization passes on generated WASM
- Monomorphization for hot functions
- String interning and pooling
- Benchmark against JS output

## Architecture: Hybrid Compilation

NOT "compile everything to WASM." The DOM has no WASM access -- every DOM operation must cross a WASM->JS bridge. For a UI language, pure WASM would be *slower* for rendering.

Instead: **compute in WASM, render in JS.**

```
canopy build --target js        # Default: everything -> JS
canopy build --target hybrid    # Model/update -> WASM, view -> JS
canopy build --target wasi      # Everything -> WASM (server/CLI, no DOM)
```

### WasmGC Type Mapping

| Canopy Type | WasmGC Type |
|-------------|-------------|
| `Int` | `i31ref` (unboxed 31-bit int) |
| `Float` | `f64` |
| `Bool` | `i31ref` (0 or 1) |
| `String` | `(ref array (mut i8))` or JS string via externref |
| `List a` | Recursive struct: `(ref null $cons)` with head + tail |
| `Maybe a` | i31ref for Nothing, struct for Just |
| Custom type | Struct group with subtyping per constructor |
| Record | Struct with named fields |
| Closure | Struct with captured vars + funcref |
| `Task e a` | Not compiled to WASM (effect boundary) |

## Performance Targets

| Metric | JS Output | WASM Hybrid (target) |
|--------|-----------|---------------------|
| Model update (1K items) | ~2ms | < 1ms |
| Bundle parse time | ~50ms | < 10ms |
| Binary size (hello world) | ~19KB gzip | < 5KB gzip |
| Data transformation (10K records) | ~15ms | < 5ms |

## Risks

- **String handling**: WASM has no native string type. Passing strings between WASM and JS is expensive. For a UI language, most data is strings. Must benchmark whether bridge cost outweighs compute savings.
- **Garbage collection overhead**: WasmGC relies on the host GC. Functional languages allocate heavily. Host GC may not be optimized for this allocation pattern yet.
- **Complexity**: Maintaining two backends (JS + WASM) doubles code generation complexity. Must ensure both produce correct, equivalent results.
- **Debugging**: WASM debugging in browsers is improving but still inferior to JS debugging. Source maps for WASM are less mature.
