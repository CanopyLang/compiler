# FFI System Improvement Plan

**Version**: 3.1
**Date**: 2026-02-25
**Status**: REVISED — DECOUPLED ARCHITECTURE
**Based On**: FFI_V3_ARCHITECTURE_AUDIT.md + Industry Best Practices
**See Also**: FFI_V3_ARCHITECTURE.md (master specification)

---

## Critical Issues Identified in v1.0

The initial improvement plan had several architectural flaws that must be corrected:

| Issue | v1.0 Approach | v2.0 Correction |
|-------|---------------|-----------------|
| **Type Duplication** | Create new schema types (`SchemaInt`, etc.) | Reuse existing `Can.Type` / `Type.Type` |
| **Import Syntax** | New syntax `with validation = strict` | Automatic via compiler flags |
| **Code Generation** | `Text.unlines` (hard to read) | Quasi-quotes `[r\|...\|]` |
| **Capability Modules** | Two disconnected modules | Merge into one, integrate with type checker |

---

## User-Facing Summary

### What's Changing

1. **Runtime Type Validation** - FFI calls will be validated at runtime. Wrong types from JavaScript produce clear errors, not silent corruption.

2. **Automatic Marshalling** - No more manually constructing `{ $: 'Ok', a: value }` in JavaScript. Generated helpers handle this.

3. **Better Error Messages** - When FFI fails, you see exactly which function, expected type, and actual value.

4. **Compiler Flag for Strict Mode** - Enable strict FFI validation via:
   ```bash
   canopy make --ffi-strict
   ```
   No changes to import syntax required.

5. **Working Capability System** - Capability types (`UserActivated`, `Initialized`) will be enforced properly.

### Migration Guide

**Existing FFI code continues to work.** To enable new safety features:

```bash
# Check your FFI for issues
canopy ffi validate

# Build with runtime validation
canopy make --ffi-strict

# Or in canopy.json:
{
    "ffi": {
        "validation": "strict"
    }
}
```

---

## Architectural Decisions

### 1. No Duplicate Type System

**Problem**: `FFIType` in `Foreign/FFI.hs` duplicates types already in `Can.Type` and `Type.Type`:

```haskell
-- CURRENT (BAD): Duplicate types
data FFIType
  = FFIBasic !Text      -- "Int", "String" as text
  | FFIResult !FFIType !FFIType
  | FFITask !FFIType !FFIType
  ...

-- EXISTING (GOOD): Canonical types
-- Can.Type in AST/Canonical.hs
-- Type.Type in Type/Type.hs (with int, float, string, etc.)
```

**Solution**: Convert from JSDoc directly to `Can.Type`. The `ffiTypeToCanType` function already exists (commented out in `Canonicalize/Module.hs`):

```haskell
-- Expand and use this instead of FFIType
ffiTypeToCanType :: JSDocTypeAnnotation -> Either FFIError Can.Type
ffiTypeToCanType annotation = case annotation of
  "Int" -> Right (Can.TType ModuleName.basics (Name.fromChars "Int") [])
  "Float" -> Right (Can.TType ModuleName.basics (Name.fromChars "Float") [])
  "String" -> Right (Can.TType ModuleName.string (Name.fromChars "String") [])
  "Bool" -> Right (Can.TType ModuleName.basics (Name.fromChars "Bool") [])
  -- ... handle all cases
```

**Validation**:
- Remove `FFIType` data type
- All FFI functions work with `Can.Type`
- No stringly-typed intermediate representation

### 2. No New Import Syntax

**Problem**: v1.0 proposed syntax changes:
```canopy
-- BAD: Puts validation policy in source code
foreign import javascript "external/audio.js" as Audio
    with validation = strict
```

**Solution**: Validation is a build concern, not a source concern. Use compiler flags:

```bash
# Command line
canopy make --ffi-strict

# Or in canopy.json
{
    "ffi": {
        "validation": "strict",
        "generate-helpers": true
    }
}
```

**Validation**:
- Import syntax unchanged
- `canopy.json` gains FFI config section
- `--ffi-strict` flag added to compiler

### 3. Quasi-Quotes for Code Generation

**Problem**: Current code generation is hard to read:

```haskell
-- CURRENT (BAD): Can't see what code is generated
generateRuntimeWrapper :: JSDocFunction -> Text
generateRuntimeWrapper jsFunc =
  Text.unlines
    [ "// Auto-generated wrapper for " <> funcName
    , "function " <> wrapperName <> "(" <> paramList <> ") {"
    , "  try {"
    , "    var result = " <> funcName <> "(" <> paramList <> ");"
    ...
```

**Solution**: Use quasi-quotes like the rest of the codebase (`Generate/JavaScript/Functions.hs`):

```haskell
{-# LANGUAGE QuasiQuotes #-}
import Text.RawString.QQ (r)

-- GOOD: See exactly what we generate
generateRuntimeWrapper :: Text -> Text -> Text
generateRuntimeWrapper funcName wrapperName = [r|
// Auto-generated wrapper for ${funcName}
function ${wrapperName}(args) {
  try {
    var result = ${funcName}.apply(null, args);
    return { $: 'Ok', a: result };
  } catch (e) {
    return { $: 'Err', a: e.message };
  }
}
|]
```

For dynamic content, use a template system with clear interpolation markers.

**Validation**:
- All code generation uses `[r|...|]` or similar
- Generated code is visually inspectable in source
- Template tests verify output

### 4. Unified Capability System

**Problem**: TWO separate capability modules exist:

| Module | Lines | Used By | Status |
|--------|-------|---------|--------|
| `FFI.Capability` | 56 | `Foreign/FFI.hs` | Active but minimal |
| `Type.Capability` | 254 | NOTHING | Dead code |

`Type.Capability` references `window.CapabilityTracker` which doesn't exist.

**Solution**:

1. **Delete** `Type.Capability` (unused dead code)
2. **Expand** `FFI.Capability` with necessary features
3. **Integrate** with type checker for compile-time capability checking
4. **Generate** runtime checks that actually work

```haskell
-- FFI.Capability (expanded)
module FFI.Capability
  ( Capability(..)
  , CapabilityConstraint(..)
  , checkCapabilities      -- Compile-time
  , generateRuntimeCheck   -- Runtime JS
  ) where

-- Generate actual working JavaScript
generateRuntimeCheck :: Capability -> Builder
generateRuntimeCheck UserActivationCapability = [r|
(function() {
  // Check if we're in a user gesture context
  if (typeof navigator !== 'undefined' &&
      navigator.userActivation &&
      !navigator.userActivation.isActive) {
    throw new Error('User activation required');
  }
})();
|]
```

**Validation**:
- `Type.Capability` deleted
- `FFI.Capability` is the single source of truth
- Runtime checks use browser APIs that actually exist
- Capability violations produce clear compile-time or runtime errors

---

## Implementation Plan (v3.1 — Decoupled Architecture)

**Architectural Decision**: FFI binding generation is **decoupled from the compiler**, following the existing `canopy-webidl` pattern. This is industry best practice (see: Rust bindgen, ReScript genType, wasm-bindgen).

### Phase 1: Create canopy-ffi Package (Week 1-2)

**Goal**: Extract JSDoc parsing and binding generation from `canopy-core` into a standalone package.

#### 1.1 Create Package Structure

```
packages/canopy-ffi/
├── canopy-ffi.cabal
├── src/
│   ├── JSDoc/
│   │   ├── Parser.hs          # Extracted from Foreign/FFI.hs
│   │   ├── Types.hs           # JSDocFunction, JSDocTypeAnnotation
│   │   └── Transform.hs       # JSDoc → Canopy types
│   ├── Codegen/
│   │   ├── Canopy.hs          # Generate .can source files
│   │   └── JavaScript.hs      # Generate validators + runtime shims
│   └── Config.hs              # CLI configuration
├── app/
│   └── Main.hs                # CLI: canopy-ffi generate
└── test/
    └── ...
```

**Validation Criteria**:
- [ ] Package compiles with `stack build canopy-ffi`
- [ ] ZERO dependency on `canopy-core`
- [ ] `canopy-ffi generate audio.js --output=src/` produces valid .can file
- [ ] Generated JavaScript validators work in isolation

#### 1.2 Extract from canopy-core

**Move these files/functions:**

| From | To |
|------|-----|
| `Foreign/FFI.hs` (891 lines) | `canopy-ffi/src/JSDoc/Parser.hs` |
| `FFI/Capability.hs` (56 lines) | `canopy-ffi/src/Capability.hs` |
| `Foreign/TestGeneratorNew.hs` | `canopy-ffi/src/TestGenerator.hs` |

**Delete from canopy-core:**
- `packages/canopy-core/src/Type/Capability.hs` (254 lines, completely unused)
- `packages/canopy-core/src/Foreign/FFI.hs` (after extraction)
- `packages/canopy-core/src/Foreign/TestGeneratorNew.hs` (after extraction)

**Validation Criteria**:
- [ ] `Type.Capability.hs` deleted
- [ ] `Foreign/FFI.hs` removed from canopy-core
- [ ] `make build` succeeds (canopy-core compiles without FFI code)

### Phase 2: Create canopy-ts Package (Week 3-4)

**Goal**: TypeScript .d.ts → Canopy bindings generator.

#### 2.1 TypeScript Parser

```
packages/canopy-ts/
├── canopy-ts.cabal
├── src/
│   ├── TypeScript/
│   │   ├── Parser.hs          # Parse .d.ts files
│   │   ├── Types.hs           # TypeScript AST types
│   │   └── Transform.hs       # TS types → Canopy types
│   ├── Codegen/
│   │   ├── Canopy.hs          # Generate .can source files
│   │   └── JavaScript.hs      # Generate validators
│   └── Bidirectional.hs       # Canopy → .d.ts (for exporting)
├── app/
│   └── Main.hs                # CLI: canopy-ts generate
└── test/
    └── ...
```

**Validation Criteria**:
- [ ] `canopy-ts generate audio.d.ts --output=src/` produces valid .can file
- [ ] Supports TypeScript generics, union types, interfaces
- [ ] Bidirectional: can also generate .d.ts from Canopy modules

#### 2.2 TypeScript Type Mapping

| TypeScript | Canopy |
|------------|--------|
| `number` | `Float` |
| `number` (integer annotation) | `Int` |
| `string` | `String` |
| `boolean` | `Bool` |
| `T \| null` | `Maybe T` |
| `{ ok: T } \| { err: E }` | `Result E T` |
| `Promise<T>` | `Task X T` |
| `Array<T>` | `List T` |
| `[T, U]` | `(T, U)` |
| Interface | Record type |
| Opaque class | Opaque type |

### Phase 3: Create canopy-ffi-runtime (Week 5-6)

**Goal**: Shared JavaScript runtime library used by all binding generators.

#### 3.1 Runtime Library

```
packages/canopy-ffi-runtime/
├── js/
│   ├── runtime.js             # Core marshalling
│   ├── validators.js          # Type validators
│   ├── capability.js          # Capability tracking
│   └── environment.js         # Environment detection
├── package.json               # npm package
└── README.md
```

**Runtime API:**

```javascript
// packages/canopy-ffi-runtime/js/runtime.js
const $canopy$ffi = {
  // Marshalling helpers
  Ok: (v) => ({ $: 'Ok', a: v }),
  Err: (e) => ({ $: 'Err', a: String(e) }),
  Just: (v) => ({ $: 'Just', a: v }),
  Nothing: { $: 'Nothing' },

  // List conversion
  toList: (arr) => arr.reduceRight((acc, x) => ({ $: '::', a: x, b: acc }), { $: '[]' }),
  fromList: (list) => { /* reverse iteration */ },

  // Validation (strict mode only)
  validateInt: (v, path) => {
    if (!Number.isInteger(v)) throw new TypeError(`${path}: expected Int, got ${typeof v}`);
    if (v < -9007199254740991 || v > 9007199254740991) throw new RangeError(`${path}: integer overflow`);
    return v;
  },
  validateFloat: (v, path) => {
    if (typeof v !== 'number') throw new TypeError(`${path}: expected Float, got ${typeof v}`);
    if (Number.isNaN(v)) throw new TypeError(`${path}: NaN not allowed`);
    return v;
  },
  // ... more validators
};

// Environment detection (NOT browser assumption)
const $canopy$env = {
  isBrowser: typeof window !== 'undefined' && typeof document !== 'undefined',
  isNode: typeof process !== 'undefined' && process.versions?.node,
  isDeno: typeof Deno !== 'undefined',
  isBun: typeof Bun !== 'undefined',
  hasUserActivation: () => {
    if (typeof navigator !== 'undefined' && navigator.userActivation) {
      return navigator.userActivation.isActive;
    }
    return true; // Non-browser: assume capability available
  }
};
```

**Validation Criteria**:
- [ ] Runtime works in Browser, Node.js, Deno, Bun
- [ ] No `window`/`document` assumptions
- [ ] Validators catch type mismatches with clear errors
- [ ] Tests cover all marshalling helpers

### Phase 4: Simplify canopy-core (Week 7-8)

**Goal**: Remove all FFI-specific code from the compiler. Compiler only parses `foreign import` syntax.

#### 4.1 Minimal Foreign Import

**Keep in canopy-core:**

```haskell
-- AST/Source.hs
data ForeignImport = ForeignImport
  { _fiPath :: !FilePath      -- "external/audio.js"
  , _fiAlias :: !Name.Name    -- Audio
  , _fiRegion :: !A.Region
  }
  -- NO type information! Types come from generated .can files

-- Parse/Module.hs
parseForeignImport :: Parser ForeignImport
-- Parses: foreign import javascript "path" as Alias
```

**Remove from canopy-core:**

| File | Lines | Action |
|------|-------|--------|
| `Foreign/FFI.hs` | 891 | MOVE to canopy-ffi |
| `Foreign/TestGeneratorNew.hs` | ~300 | MOVE to canopy-ffi |
| `FFI/Capability.hs` | 56 | MOVE to canopy-ffi |
| `Type/Capability.hs` | 254 | DELETE (unused) |

**Validation Criteria**:
- [ ] `canopy-core` has ~50 lines of FFI code (just parsing)
- [ ] `make build` succeeds
- [ ] All existing tests pass
- [ ] No JSDoc parsing in compiler

#### 4.2 Include Runtime in Output

**In Generate/JavaScript.hs:**

```haskell
-- Include canopy-ffi-runtime in output when FFI is used
includeFFIRuntime :: Builder
includeFFIRuntime =
  -- Embed runtime.js content (or reference via import)
  Builder.fromText runtimeSource
```

### Phase 5: Compiler Flags & Tooling (Week 9-10)

#### 5.1 Add Compiler Flags

**Files:**
- `packages/canopy-terminal/src/Make.hs`
- `packages/canopy-builder/src/Canopy/Outline.hs`

**Changes:**
```bash
# Enable strict FFI validation
canopy make --ffi-strict

# Or in canopy.json
{
  "ffi": {
    "validation": "strict"    # "strict" | "permissive" | "disabled"
  }
}
```

#### 5.2 FFI CLI Commands

```bash
# Validate FFI bindings
canopy ffi validate

# Generate from JSDoc
canopy-ffi generate audio.js --module=AudioFFI --output=src/

# Generate from TypeScript
canopy-ts generate audio.d.ts --module=AudioFFI --output=src/

# Generate from WebIDL (existing)
canopy-webidl-gen fetch --api=AudioContext --output=src/
```

### Phase 6: Documentation & Examples (Week 11-12)

#### 6.1 Update audio-ffi Example

**New workflow:**

```bash
# 1. Write TypeScript definitions (source of truth)
cat > external/audio.d.ts << 'EOF'
export interface AudioContext {
  readonly state: 'suspended' | 'running' | 'closed';
  resume(): Promise<void>;
  close(): Promise<void>;
}
export function createAudioContext(): AudioContext | null;
EOF

# 2. Generate Canopy bindings
canopy-ts generate external/audio.d.ts --module=Audio --output=src/

# 3. Generated files:
# - src/Audio.can (type-safe FFI declarations)
# - src/Audio.validators.js (runtime validation)

# 4. Compile with strict validation
canopy make --ffi-strict
```

#### 6.2 Comprehensive Documentation

**Create: `docs/FFI_GUIDE.md`**

Contents:
1. Quick start with TypeScript bindings
2. Quick start with JSDoc bindings
3. Type mapping reference
4. Capability system guide
5. Runtime validation options
6. Troubleshooting common errors
7. Migration from manual FFI

---

## Validation Matrix (v3.1)

| Package | Unit Tests | Property Tests | Integration Tests | Golden Tests |
|---------|------------|----------------|-------------------|--------------|
| canopy-ffi | JSDoc parsing, transforms | Type mapping invariants | CLI end-to-end | Generated .can output |
| canopy-ts | .d.ts parsing, transforms | Type mapping invariants | CLI end-to-end | Generated .can output |
| canopy-ffi-runtime | Marshalling helpers | Validator coverage | Browser/Node/Deno/Bun | - |
| canopy-core (FFI) | Parse foreign import | - | Compile with FFI | - |

---

## Risk Assessment (v3.1)

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Breaking existing FFI | Medium | High | Deprecation path; old workflow still works |
| Performance overhead | Low | Medium | Validation only in strict mode, can be disabled |
| TypeScript parser complexity | Medium | Medium | Use existing TS parser (tree-sitter or ts-morph) |
| Package coordination | Medium | Low | Shared runtime library, clear interfaces |
| Migration effort | Low | Low | Gradual adoption; binding generators are optional |

---

## Success Criteria (v3.1)

1. **Decoupled architecture**: FFI binding generation in separate packages
2. **Zero canopy-core dependency**: canopy-ffi and canopy-ts have no dependency on canopy-core
3. **canopy-webidl pattern**: New packages follow existing canopy-webidl structure
4. **TypeScript first-class**: .d.ts files as source of truth for bindings
5. **Minimal compiler FFI**: canopy-core only parses `foreign import` syntax (~50 lines)
6. **Type.Capability deleted**: Dead code removed
7. **Runtime works everywhere**: Browser, Node.js, Deno, Bun
8. **All tests pass**: Including audio-ffi example with `--ffi-strict`
9. **Documentation complete**: FFI guide covers TypeScript workflow

---

## Appendix: Files to Create/Modify/Delete

### New Packages

```
packages/canopy-ffi/               # NEW: JSDoc binding generator
├── canopy-ffi.cabal
├── src/JSDoc/Parser.hs
├── src/JSDoc/Types.hs
├── src/JSDoc/Transform.hs
├── src/Codegen/Canopy.hs
├── src/Codegen/JavaScript.hs
└── app/Main.hs

packages/canopy-ts/                # NEW: TypeScript binding generator
├── canopy-ts.cabal
├── src/TypeScript/Parser.hs
├── src/TypeScript/Types.hs
├── src/TypeScript/Transform.hs
├── src/Codegen/Canopy.hs
├── src/Codegen/JavaScript.hs
└── app/Main.hs

packages/canopy-ffi-runtime/       # NEW: Shared JS runtime
├── package.json
├── js/runtime.js
├── js/validators.js
├── js/capability.js
└── js/environment.js
```

### Delete from canopy-core

| File | Lines | Reason |
|------|-------|--------|
| `Type/Capability.hs` | 254 | Completely unused (dead code) |
| `Foreign/FFI.hs` | 891 | Move to canopy-ffi package |
| `Foreign/TestGeneratorNew.hs` | ~300 | Move to canopy-ffi package |
| `FFI/Capability.hs` | 56 | Move to canopy-ffi package |

### Keep in canopy-core (minimal)

| File | Changes |
|------|---------|
| `AST/Source.hs` | Keep `ForeignImport` type (simplified) |
| `Parse/Module.hs` | Keep `parseForeignImport` parser |
| `Generate/JavaScript.hs` | Include runtime when FFI used |

### Config Changes

- `canopy.json` schema: add `ffi` section
- CLI parser: add `--ffi-strict` flag
- Build system: coordinate multi-package build
