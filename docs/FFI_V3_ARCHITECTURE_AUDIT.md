# FFI v3.0 Architecture Audit: Coupling Analysis & Best Practices

**Version**: 3.1 (Architectural Revision)
**Date**: 2026-02-25
**Status**: CRITICAL ARCHITECTURAL FEEDBACK
**Question**: Should FFI be built into the compiler or decoupled?

---

## Executive Summary

**Your instinct is correct.** The current FFI architecture has a fundamental design flaw:

> **FFI binding generation is tightly coupled to the compiler when it should be a separate tool.**

This audit examines industry best practices and recommends a **decoupled architecture** that provides:
- True compile-time type safety
- Bidirectional type verification
- Better tooling ecosystem integration
- Cleaner separation of concerns

---

## Part 1: Current Architecture Analysis

### What We Have

```
┌─────────────────────────────────────────────────────────────┐
│                    CURRENT ARCHITECTURE                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────────┐                                   │
│  │    canopy-core       │                                   │
│  │    (Compiler)        │                                   │
│  ├──────────────────────┤                                   │
│  │ - AST/Source.hs      │◄── FFI declarations parsed here   │
│  │ - Foreign/FFI.hs     │◄── JSDoc parsing (891 lines!)     │
│  │ - FFI/Capability.hs  │◄── Capability types               │
│  │ - Canonicalize/*.hs  │◄── FFI type conversion            │
│  │ - Generate/*.hs      │◄── FFI wrapper generation         │
│  └──────────────────────┘                                   │
│           │                                                 │
│           ▼                                                 │
│  ┌──────────────────────┐                                   │
│  │   canopy-webidl      │◄── SEPARATE (good!)               │
│  │   (Binding Gen)      │                                   │
│  └──────────────────────┘                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Problems with Current Approach

| Issue | Impact |
|-------|--------|
| **JSDoc parsing in compiler** | 891 lines of code that shouldn't be in the compiler |
| **FFIType intermediate representation** | Duplicates Can.Type, adds maintenance burden |
| **Tight coupling** | Changes to FFI require compiler changes |
| **No TypeScript support** | JSDoc is inferior to .d.ts for type definitions |
| **Runtime validation in compiler** | Validation logic embedded in code generation |
| **Single point of failure** | FFI bugs affect entire compiler |

### What You Already Have Right

**canopy-webidl is correctly architected!**

```
canopy-webidl (GOOD):
├── Parses WebIDL specifications
├── Generates Canopy .can source files
├── Generates JavaScript runtime
├── ZERO dependency on canopy-core
└── Standalone CLI tool
```

This is the model to follow for ALL FFI binding generation.

---

## Part 2: Industry Best Practices Research

### Approach 1: Separate Binding Generator (RECOMMENDED)

**Used by:** Rust (bindgen, wasm-bindgen), ReScript (genType), OCaml (js_of_ocaml-ppx), Dart (ffigen)

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Source     │────►│  Binding    │────►│  Compiler   │
│  (.d.ts,    │     │  Generator  │     │  (type      │
│   .h, IDL)  │     │  (separate) │     │   checks)   │
└─────────────┘     └─────────────┘     └─────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │ Generated   │
                    │ Source      │
                    │ (.can, .rs) │
                    └─────────────┘
```

**Key insight from [Rust bindgen](https://github.com/rust-lang/rust-bindgen):**
> "Writing matching type signatures by hand can be quite mechanical, tedious, and error-prone. When those signatures are simple enough, tools like bindgen can instead automatically generate them."

**Key insight from [ReScript genType](https://github.com/rescript-association/genType):**
> "genType lets you export ReScript values and types to use in TypeScript, and import TypeScript values and types into ReScript."

### Approach 2: Compiler Built-in FFI (COMMON BUT LIMITED)

**Used by:** Elm (ports), Haskell (FFI extension), PureScript (foreign import)

```
┌─────────────┐     ┌─────────────────────────────┐
│  Canopy     │────►│        Compiler              │
│  Source     │     │  ┌─────────────────────┐    │
│  + foreign  │     │  │ Parse foreign decl  │    │
│    imports  │     │  │ Trust type is right │    │
│             │     │  │ Generate JS call    │    │
└─────────────┘     │  └─────────────────────┘    │
                    └─────────────────────────────┘
```

**Key insight from [PureScript documentation](https://github.com/purescript/documentation/blob/master/guides/FFI.md):**
> "Choosing to work with JavaScript via the FFI will 'void the warranty' of the typechecker to a certain extent. Once you step outside the safe confines of the PureScript type system, nothing is guaranteed."

**Key insight from [Elm criticism](https://cscalfani.medium.com/the-biggest-problem-with-elm-4faecaa58b77):**
> "Every other mainstream language has an FFI because... mature languages understand that sometimes the current language doesn't cut it, and you need an escape hatch."

### Approach 3: Bidirectional Type Generation (BEST)

**Used by:** Cheerp (C++ ↔ TypeScript), wasm-bindgen (Rust ↔ JS)

```
┌─────────────┐     ┌─────────────────────────────────────┐
│ TypeScript  │────►│        Bidirectional Generator       │
│ .d.ts       │     │  ┌───────────────────────────────┐  │
│             │     │  │ 1. Parse .d.ts                │  │
│             │     │  │ 2. Generate Canopy types      │  │
│             │     │  │ 3. Generate runtime validators│  │
│             │     │  │ 4. Generate JS shims          │  │
└─────────────┘     │  └───────────────────────────────┘  │
                    └─────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
            ┌───────────┐   ┌───────────┐   ┌───────────┐
            │ .can      │   │ validators│   │ JS shims  │
            │ (types)   │   │ .js       │   │ .js       │
            └───────────┘   └───────────┘   └───────────┘
```

**Key insight from [Cheerp](https://labs.leaningtech.com/blog/cheerp-typescript):**
> "The Cheerp compiler can generate TypeScript declaration files (.d.ts)... ts2cpp converts TypeScript declaration files into C++ headers."

**This is bidirectional:** TypeScript ↔ Target Language

---

## Part 3: Recommended Architecture

### The Canopy FFI Ecosystem

```
┌─────────────────────────────────────────────────────────────────┐
│                    RECOMMENDED ARCHITECTURE                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  BINDING GENERATORS (Separate Tools)                             │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐ │
│  │  canopy-ffi      │  │  canopy-webidl   │  │ canopy-ts-gen │ │
│  │  (JSDoc → .can)  │  │  (WebIDL → .can) │  │ (.d.ts → .can)│ │
│  └────────┬─────────┘  └────────┬─────────┘  └───────┬────────┘ │
│           │                     │                    │          │
│           └──────────┬──────────┴────────────────────┘          │
│                      ▼                                          │
│           ┌──────────────────────┐                              │
│           │  Generated .can      │                              │
│           │  + .js runtime       │                              │
│           └──────────┬───────────┘                              │
│                      │                                          │
│  COMPILER (Minimal FFI Support)                                 │
│  ┌───────────────────▼──────────────────────────────┐           │
│  │              canopy-core                          │           │
│  │  ┌─────────────────────────────────────────────┐ │           │
│  │  │ - Parse `foreign import` syntax             │ │           │
│  │  │ - Type-check generated .can files           │ │           │
│  │  │ - NO JSDoc parsing                          │ │           │
│  │  │ - NO FFIType (use Can.Type directly)        │ │           │
│  │  │ - Include runtime in output                 │ │           │
│  │  └─────────────────────────────────────────────┘ │           │
│  └──────────────────────────────────────────────────┘           │
│                                                                  │
│  RUNTIME LIBRARY (Shipped with generated JS)                    │
│  ┌──────────────────────────────────────────────────┐           │
│  │  canopy-ffi-runtime.js                           │           │
│  │  - Marshalling helpers                           │           │
│  │  - Type validators                               │           │
│  │  - Capability tracking                           │           │
│  │  - Environment detection                         │           │
│  └──────────────────────────────────────────────────┘           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Package Structure

```
canopy/
├── packages/
│   ├── canopy-core/           # Compiler (SIMPLIFIED)
│   │   └── src/
│   │       ├── Parse/Module.hs       # Parse foreign import syntax
│   │       ├── AST/Source.hs         # ForeignImport AST node
│   │       └── Generate/JavaScript/  # Include runtime, nothing more
│   │
│   ├── canopy-ffi/            # NEW: JSDoc/JS binding generator
│   │   ├── src/
│   │   │   ├── JSDoc/Parser.hs       # JSDoc parsing (move from FFI.hs)
│   │   │   ├── JSDoc/Transform.hs    # Transform to Canopy types
│   │   │   ├── Codegen/Canopy.hs     # Generate .can files
│   │   │   └── Codegen/JavaScript.hs # Generate validators
│   │   └── app/Main.hs               # CLI: canopy-ffi
│   │
│   ├── canopy-ts/             # NEW: TypeScript binding generator
│   │   ├── src/
│   │   │   ├── TypeScript/Parser.hs  # Parse .d.ts files
│   │   │   ├── TypeScript/Transform.hs
│   │   │   ├── Codegen/Canopy.hs
│   │   │   └── Codegen/JavaScript.hs
│   │   └── app/Main.hs               # CLI: canopy-ts
│   │
│   ├── canopy-webidl/         # EXISTING: WebIDL binding generator
│   │   └── ...                       # Already well-structured!
│   │
│   └── canopy-ffi-runtime/    # NEW: Shared runtime library
│       └── js/
│           ├── runtime.js            # Core marshalling
│           ├── validators.js         # Type validators
│           └── capability.js         # Capability tracking
```

### Why This Is Better

| Aspect | Current | Proposed |
|--------|---------|----------|
| **Compiler complexity** | 891+ lines of FFI code | ~50 lines (parse syntax only) |
| **Type safety** | Trust JSDoc matches JS | Generated + validated |
| **TypeScript support** | None | First-class |
| **Tooling** | None | CLI tools, IDE integration |
| **Testing** | Compiler tests | Isolated tool tests |
| **Maintenance** | FFI changes = compiler release | FFI tools release independently |
| **Ecosystem** | Proprietary JSDoc | Standard TypeScript |

---

## Part 4: Compile-Time Type Safety Analysis

### Current Approach: Trust-Based

```
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│  audio.js    │      │  Compiler    │      │  Runtime     │
│  + JSDoc     │─────►│  trusts      │─────►│  hope it     │
│  comments    │      │  JSDoc       │      │  works       │
└──────────────┘      └──────────────┘      └──────────────┘

PROBLEM: JSDoc might not match actual JavaScript implementation!

Example:
/**
 * @canopy-type Int -> Int
 */
function add(x) {
  return x + "oops";  // BUG: Returns String, not Int!
}

Compiler has NO WAY to catch this.
```

### Proposed Approach: Verified + Validated

```
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│  audio.d.ts  │      │  canopy-ts   │      │  Compiler    │
│  (TypeScript │─────►│  generates   │─────►│  type-checks │
│   types)     │      │  .can + .js  │      │  .can files  │
└──────────────┘      └──────────────┘      └──────────────┘
                             │
                             ▼
                      ┌──────────────┐      ┌──────────────┐
                      │  validators  │─────►│  Runtime     │
                      │  .js         │      │  VALIDATES   │
                      └──────────────┘      └──────────────┘

COMPILE-TIME: TypeScript → Canopy type conversion is mechanical & correct
RUNTIME: Validators catch JavaScript implementation bugs
```

### Best Practice: TypeScript as Source of Truth

**Why TypeScript over JSDoc:**

| JSDoc | TypeScript |
|-------|------------|
| Comments (can be ignored) | Actual code (enforced) |
| Inconsistent tooling | Industry standard tooling |
| No IDE enforcement | Full IDE support |
| Manual type annotations | Type inference |
| No structural types | Full structural typing |
| Limited generics | Full generic support |

**Industry trend:** [JSDoc with TypeScript](https://www.typescriptlang.org/docs/handbook/jsdoc-supported-types.html) is increasingly popular, but .d.ts files are the gold standard for type definitions.

---

## Part 5: Migration Plan

### Phase 1: Create canopy-ffi Package (Week 1-2)

**Extract from canopy-core:**

```haskell
-- Move these from canopy-core/src/Foreign/FFI.hs
-- to canopy-ffi/src/JSDoc/Parser.hs

module JSDoc.Parser
  ( parseJSDocFromFile
  , extractJSDocFromAST
  , parseCanopyTypeAnnotation
  ) where

-- This is 500+ lines that shouldn't be in the compiler
```

**New package structure:**

```
canopy-ffi/
├── canopy-ffi.cabal
├── src/
│   ├── JSDoc/
│   │   ├── Parser.hs          # From Foreign/FFI.hs
│   │   ├── Types.hs           # JSDocFunction, etc.
│   │   └── Transform.hs       # JSDoc → CanopyModule
│   ├── Codegen/
│   │   ├── Canopy.hs          # Generate .can files
│   │   └── JavaScript.hs      # Generate validators
│   └── Config.hs              # Configuration
└── app/
    └── Main.hs                # CLI entry point
```

### Phase 2: Create canopy-ts Package (Week 3-4)

**TypeScript definition parser:**

```haskell
module TypeScript.Parser
  ( parseDefinitionFile
  , Definition(..)
  , TypeDef(..)
  ) where

-- Parse .d.ts files using existing TypeScript parser
-- or tree-sitter-typescript
```

**Bidirectional generation:**

```haskell
module TypeScript.Bidirectional
  ( -- .d.ts → Canopy
    generateCanopyFromTS
    -- Canopy → .d.ts (for exposing Canopy to TS)
  , generateTSFromCanopy
  ) where
```

### Phase 3: Simplify canopy-core (Week 5-6)

**Remove from canopy-core:**

```haskell
-- DELETE these files:
-- packages/canopy-core/src/Foreign/FFI.hs (891 lines)
-- packages/canopy-core/src/Foreign/TestGeneratorNew.hs
-- packages/canopy-core/src/FFI/Capability.hs (56 lines)
-- packages/canopy-core/src/Type/Capability.hs (254 lines, already unused)

-- KEEP only:
-- Parse `foreign import javascript "path" as Alias` syntax
-- Include runtime in generated output
```

**Simplified foreign import handling:**

```haskell
-- AST/Source.hs
data ForeignImport = ForeignImport
  { fiPath :: FilePath      -- "external/audio.js"
  , fiAlias :: Name.Name    -- Audio
  , fiRegion :: A.Region
  }
  -- NO type information here!
  -- Types come from the generated .can file
```

### Phase 4: Unified Runtime (Week 7-8)

**Create canopy-ffi-runtime:**

```javascript
// packages/canopy-ffi-runtime/js/runtime.js

// Environment-agnostic (works in Node, Deno, Bun, Browser)
const $canopy$ffi = {
  // Marshalling
  Ok: (v) => ({ $: 'Ok', a: v }),
  Err: (e) => ({ $: 'Err', a: e }),
  Just: (v) => ({ $: 'Just', a: v }),
  Nothing: { $: 'Nothing' },

  // Validation (only in strict mode)
  validate: (value, schema, path) => { ... },

  // Lists
  toList: (arr) => { ... },
  fromList: (list) => { ... },
};

// Feature detection, NOT assumption
const $canopy$env = {
  isBrowser: typeof window !== 'undefined',
  isNode: typeof process !== 'undefined',
  hasUserActivation: () => {
    if (typeof navigator !== 'undefined' && navigator.userActivation) {
      return navigator.userActivation.isActive;
    }
    return true; // Non-browser: assume available
  }
};
```

---

## Part 6: Workflow Comparison

### Current Workflow (BAD)

```bash
# Developer writes:
# 1. audio.js with JSDoc comments
# 2. AudioFFI.can with foreign imports

canopy make
# Compiler:
# - Reads AudioFFI.can
# - Parses audio.js JSDoc
# - Hopes they match
# - Generates output
```

### Proposed Workflow (GOOD)

```bash
# Developer writes:
# 1. audio.ts or audio.d.ts (TypeScript definitions)
# 2. audio.js (implementation)

# Step 1: Generate bindings (explicit, auditable)
canopy-ts generate audio.d.ts --module=AudioFFI --output=src/

# This creates:
# - src/AudioFFI.can (type-safe bindings)
# - src/AudioFFI.validators.js (runtime checks)

# Step 2: Compile (normal compilation)
canopy make
# Compiler:
# - Reads AudioFFI.can (generated, trusted)
# - Type-checks normally
# - Includes validators in output

# Step 3: Runtime (validates actual JS)
# Validators catch implementation bugs at runtime
```

### Benefits of Proposed Workflow

1. **Auditable**: Generated .can files can be reviewed
2. **Cacheable**: Regenerate only when .d.ts changes
3. **Testable**: Test binding generator independently
4. **Debuggable**: Clear separation of concerns
5. **Ecosystem**: Use TypeScript tooling

---

## Part 7: Comparison with Other Languages

| Language | FFI Approach | Binding Generator | Compile-Time Safe | Runtime Safe |
|----------|--------------|-------------------|-------------------|--------------|
| **Rust** | unsafe FFI | bindgen (separate) | No (unsafe) | No |
| **Rust/WASM** | wasm-bindgen | wasm-bindgen (separate) | Yes | Yes |
| **PureScript** | foreign import | Manual | No (trust) | No |
| **ReScript** | @bs.* attributes | genType (separate) | Yes | Partial |
| **OCaml/JS** | js_of_ocaml | js_of_ocaml-ppx (separate) | Partial | No |
| **Elm** | ports | None | Partial | No |
| **Canopy (current)** | foreign import | Built-in (bad) | No (trust) | No |
| **Canopy (proposed)** | foreign import | canopy-ts (separate) | **Yes** | **Yes** |

### Key Insight

> The most type-safe FFI systems (wasm-bindgen, genType) use **separate binding generators** that produce **verifiable output**.

---

## Part 8: Revised v3.0 Plan Summary

### What Changes from v3.0 Document

| v3.0 Original | v3.1 Revision |
|---------------|---------------|
| FFI built into compiler | FFI as separate tools |
| JSDoc parsing in compiler | JSDoc parsing in canopy-ffi |
| FFIType intermediate | Direct to Can.Type |
| Runtime in compiler | Shared canopy-ffi-runtime |
| Single monolith | Multiple focused packages |

### New Package Responsibilities

| Package | Responsibility |
|---------|----------------|
| **canopy-core** | Parse `foreign import` syntax, include runtime |
| **canopy-ffi** | JSDoc → .can + validators |
| **canopy-ts** | TypeScript .d.ts → .can + validators |
| **canopy-webidl** | WebIDL → .can + validators (existing) |
| **canopy-ffi-runtime** | Shared JS runtime library |

### Timeline Adjustment

| Week | Original v3.0 | Revised v3.1 |
|------|---------------|--------------|
| 1-2 | Foundation (FFIType, flags) | Extract canopy-ffi package |
| 3-4 | Code generation | Create canopy-ts package |
| 5-6 | Runtime validation | Simplify canopy-core |
| 7-8 | Capability system | Unified runtime + capabilities |
| 9-10 | Tooling | CLI polish + IDE integration |
| 11-12 | Documentation | Documentation + examples |

---

## Conclusion

**Yes, the FFI should be decoupled from the compiler.**

The current architecture has FFI logic embedded in the compiler, which is:
- Harder to maintain
- Harder to test
- Harder to extend
- Less type-safe
- Missing TypeScript support

The proposed architecture follows industry best practices:
- **Separate binding generators** (like bindgen, genType, wasm-bindgen)
- **TypeScript as source of truth** (not JSDoc comments)
- **Generated + validated** (compile-time AND runtime safety)
- **Minimal compiler changes** (compiler just compiles)

**You already have the right pattern with canopy-webidl.** Apply it to all FFI binding generation.

---

## Sources

- [PureScript FFI Documentation](https://github.com/purescript/documentation/blob/master/guides/FFI.md)
- [ReScript genType](https://github.com/rescript-association/genType)
- [Rust bindgen](https://github.com/rust-lang/rust-bindgen)
- [wasm-bindgen Guide](https://rustwasm.github.io/docs/wasm-bindgen/)
- [Cheerp TypeScript Integration](https://labs.leaningtech.com/blog/cheerp-typescript)
- [Elm Ports Criticism](https://cscalfani.medium.com/the-biggest-problem-with-elm-4faecaa58b77)
- [js_of_ocaml](https://ocsigen.org/js_of_ocaml/latest/manual/overview)
- [ts-rs: TypeScript bindings from Rust](https://github.com/Aleph-Alpha/ts-rs)
- [TypeScript JSDoc Reference](https://www.typescriptlang.org/docs/handbook/jsdoc-supported-types.html)
- [GHC JavaScript FFI](https://downloads.haskell.org/ghc/latest/docs/users_guide/javascript.html)
