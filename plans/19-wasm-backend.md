# Plan 19: WebAssembly Backend

## Priority: MEDIUM — Tier 4
## Effort: 12-16 weeks
## Depends on: Stable compiler, Plan 01 (ESM for JS parts)

## Problem

JavaScript is Canopy's only compilation target. WebAssembly (specifically WasmGC) is now shipped in all major browsers and offers:

- Smaller binary sizes than equivalent JS
- Faster parse/compile times
- Predictable performance (no JIT warmup)
- WASI target for server-side execution without Node.js

## Current WASM Landscape (2026)

| Feature | Status | Browser Support |
|---------|--------|----------------|
| WasmGC | Shipped (Wasm 3.0) | Chrome 119+, Firefox 120+, Safari 18.2+ |
| Tail calls | Shipped (Wasm 3.0) | All major browsers |
| i31ref | Part of WasmGC | All major browsers |
| Component Model | Phase 2/3 | Server-side only |
| Stack Switching | Phase 3 | Not yet |
| Shared-everything threads | Phase 1 | Not yet |

## Solution: Hybrid Compilation

NOT "compile everything to WASM." The DOM has no WASM access — every DOM operation must cross a WASM→JS bridge. For a UI language, pure WASM would be *slower* for rendering.

Instead: **compute in WASM, render in JS.**

### Architecture

```
canopy build --target js        # Default: everything → JS
canopy build --target hybrid    # Model/update → WASM, view → JS
canopy build --target wasi      # Everything → WASM (server/CLI, no DOM)
```

**Hybrid mode splits the app:**

```
┌─────────────────────────────────┐
│          Browser                │
│                                 │
│  ┌──────────┐  ┌────────────┐  │
│  │   WASM   │  │     JS     │  │
│  │          │  │            │  │
│  │  Model   │←→│   View     │  │
│  │  Update  │  │   DOM ops  │  │
│  │  Logic   │  │   Events   │  │
│  │          │  │            │  │
│  └──────────┘  └────────────┘  │
└─────────────────────────────────┘
```

The WASM module exports:
- `init() -> Model` (serialized)
- `update(msg, model) -> (Model, [Effect])` (pure computation)

The JS module handles:
- DOM rendering (via Plan 04's reactive compiler)
- Event listener attachment
- Effect execution (HTTP, timers, etc.)
- Calling WASM for model updates

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

### ADT Encoding

```canopy
type Expr
    = Lit Int
    | Add Expr Expr
    | Neg Expr
```

```wat
;; WasmGC encoding:
(type $Expr (sub (struct)))
(type $Lit (sub $Expr (struct (field i31ref))))
(type $Add (sub $Expr (struct (field (ref $Expr)) (field (ref $Expr)))))
(type $Neg (sub $Expr (struct (field (ref $Expr)))))
```

Pattern matching compiles to `ref.test` / `ref.cast`:

```wat
;; case expr of Lit n -> ...
(if (ref.test $Lit (local.get $expr))
  (then
    (local.set $n (struct.get $Lit 0 (ref.cast $Lit (local.get $expr))))
    ;; ... handle Lit case
  )
)
```

### Closure Encoding

```canopy
map : (a -> b) -> List a -> List b
-- Partial application: map f creates a closure
```

```wat
(type $Closure_1 (struct
  (field $func (ref $func_type))   ;; function pointer
  (field $captured_0 (ref any))     ;; first captured variable
))
```

## Implementation Phases

### Phase 1: WASM code generator for pure functions (Weeks 1-4)
- New module: `Generate/Wasm.hs`
- Emit WasmGC structs for ADTs and records
- Emit functions for pure Canopy functions
- Handle pattern matching via ref.test/ref.cast
- Handle tail calls via return_call
- Target: compile a pure Canopy module (no effects) to WASM

### Phase 2: WASM ↔ JS bridge (Weeks 5-8)
- Model serialization between WASM and JS
- Message passing: JS events → WASM update → JS render
- Effect dispatch: WASM update returns effect descriptors, JS executes them
- Integration with Plan 04's reactive rendering

### Phase 3: WASI target (Weeks 9-12)
- Compile entire Canopy programs to WASM + WASI
- No DOM, no browser — server-side execution
- HTTP server via WASI HTTP API
- File system access via WASI filesystem API
- Use case: CanopyKit SSR without Node.js

### Phase 4: Optimization (Weeks 13-16)
- Binaryen optimization passes on generated WASM
- Monomorphization for hot functions
- String interning and pooling
- Benchmark against JS output

## Performance Targets

| Metric | JS Output | WASM Hybrid (target) |
|--------|-----------|---------------------|
| Model update (1K items) | ~2ms | < 1ms |
| Bundle parse time | ~50ms | < 10ms |
| Binary size (hello world) | ~19KB gzip | < 5KB gzip |
| Data transformation (10K records) | ~15ms | < 5ms |

## Risks

- **String handling**: WASM has no native string type. Passing strings between WASM and JS is expensive. For a UI language, most data is strings. Must carefully benchmark whether the bridge cost outweighs compute savings.
- **Garbage collection overhead**: WasmGC relies on the host GC. Functional languages allocate heavily (immutable updates create new values). Host GC may not be optimized for this allocation pattern yet.
- **Complexity**: Maintaining two backends (JS + WASM) doubles code generation complexity. Must ensure both produce correct, equivalent results.
- **Debugging**: WASM debugging in browsers is improving but still inferior to JS debugging. Source maps for WASM are less mature.
