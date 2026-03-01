# Plan 18: Comprehensive Benchmark Suite

**Priority:** MEDIUM
**Effort:** Medium (1–3 days)
**Risk:** Low

## Problem

The benchmark suite covers parsing, JSON, hashing, source maps, optimization, and tree-shaking. But the most computationally expensive compiler phases are completely unmeasured:

| Missing Benchmark | Why It Matters |
|-------------------|---------------|
| Type checking | Most expensive phase — constraint generation and solving |
| Canonicalization | Name resolution, environment building |
| End-to-end compilation | No real-project benchmark |
| JavaScript generation | Only source map encoding is benchmarked, not actual JS output |
| Binary cache round-trip | `.elco` serialization/deserialization performance |
| Large modules | Parse benchmarks max at 200 lines; real modules are 500–1000+ lines |
| FFI processing | Loading, parsing, type conversion |
| Dependency solving | SAT-like constraint solving for packages |

## Files to Create

### `bench/Bench/TypeCheck.hs`

Benchmark constraint generation and solving:
- Small module (5 functions, simple types)
- Medium module (20 functions, records, unions)
- Large module (50+ functions, polymorphic, complex constraints)
- Pathological case: deeply nested let bindings with shared type variables

### `bench/Bench/Canonicalize.hs`

Benchmark name resolution:
- Module with 10 imports
- Module with 50 imports
- Module with qualified vs unqualified imports
- Module with complex pattern matching

### `bench/Bench/EndToEnd.hs`

Benchmark full pipeline from source text to JS output:
- Single module, 100 lines
- Single module, 500 lines
- Single module, 1000 lines
- Multi-module project (10 modules with dependencies)

### `bench/Bench/JsGeneration.hs`

Benchmark JavaScript code generation (not just source maps):
- Simple function definitions
- Complex pattern match compilation
- Record operations
- List/Array operations

### `bench/Bench/Cache.hs`

Benchmark `.elco` binary serialization:
- Serialize and deserialize a Module interface
- Serialize and deserialize an optimized graph
- Round-trip with FFI info

### Update `bench/Bench/Parse.hs`

Add larger module benchmarks:
- 500-line module
- 1000-line module
- 2000-line module
- Module heavy on type annotations

## Files to Modify

### `bench/Main.hs`

Register all new benchmark groups.

### `Makefile`

Ensure `make bench` runs all benchmarks including the new ones.

## Verification

1. `make build` — zero warnings
2. `make bench` — all benchmarks run successfully
3. Each benchmark produces meaningful results (not all zeros or trivially fast)
4. Benchmark results are repeatable (low variance between runs)
