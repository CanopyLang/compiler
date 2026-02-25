# Canopy FFI v3.1 — Production Architecture

**Version**: 3.1 (Architectural Revision)
**Date**: 2026-02-25
**Status**: MASTER ARCHITECTURE
**Authors**: Compiler Engineering Team
**Classification**: COMPLETE MIGRATION — NO LEGACY ARTIFACTS
**Revision Note**: v3.1 incorporates decoupled architecture from audit findings

---

## Executive Summary

This document defines the **complete, production-ready FFI architecture** for Canopy. It supersedes all previous versions (v1.0 PDF, v2.0 MD) and represents a **full migration away from all legacy patterns**.

**Critical Architectural Decision (v3.1):**

> **FFI binding generation is DECOUPLED from the compiler**, following the existing `canopy-webidl` pattern. The compiler only parses `foreign import` syntax; all binding generation happens in separate tools.

**Core Guarantees:**
- Zero Elm kernel code
- Zero legacy FFI behavior
- Zero implicit runtime assumptions
- Zero undefined behavior at boundaries
- Deterministic compilation output
- Sound type boundaries
- Explicit memory model
- Environment-agnostic runtime
- **Separate binding generators (not built into compiler)**
- **TypeScript .d.ts as source of truth**

---

## Package Architecture (v3.1)

The FFI ecosystem follows the **binding generator pattern** used by Rust (bindgen), ReScript (genType), and our own `canopy-webidl`:

```
┌─────────────────────────────────────────────────────────────────┐
│                    FFI PACKAGE ECOSYSTEM                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  BINDING GENERATORS (Separate CLI Tools)                         │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐ │
│  │  canopy-ffi      │  │  canopy-webidl   │  │  canopy-ts     │ │
│  │  (JSDoc → .can)  │  │  (WebIDL → .can) │  │  (.d.ts → .can)│ │
│  │  EXTRACT FROM    │  │  EXISTING        │  │  NEW           │ │
│  │  canopy-core     │  │  (model!)        │  │                │ │
│  └────────┬─────────┘  └────────┬─────────┘  └───────┬────────┘ │
│           │                     │                    │          │
│           └──────────┬──────────┴────────────────────┘          │
│                      ▼                                          │
│           ┌──────────────────────┐                              │
│           │  Generated Output    │                              │
│           │  - .can files        │                              │
│           │  - validators.js     │                              │
│           │  - runtime shims.js  │                              │
│           └──────────┬───────────┘                              │
│                      │                                          │
│  COMPILER (Minimal FFI Support)                                 │
│  ┌───────────────────▼──────────────────────────────┐           │
│  │              canopy-core                          │           │
│  │  ┌─────────────────────────────────────────────┐ │           │
│  │  │ - Parse `foreign import` syntax ONLY        │ │           │
│  │  │ - Type-check generated .can files           │ │           │
│  │  │ - NO JSDoc parsing (removed)                │ │           │
│  │  │ - NO FFIType (use Can.Type directly)        │ │           │
│  │  │ - Include runtime in output                 │ │           │
│  │  └─────────────────────────────────────────────┘ │           │
│  └──────────────────────────────────────────────────┘           │
│                                                                  │
│  SHARED RUNTIME                                                  │
│  ┌──────────────────────────────────────────────────┐           │
│  │  canopy-ffi-runtime (JavaScript)                 │           │
│  │  - $canopy$ffi.Ok(), $canopy$ffi.Err(), etc.    │           │
│  │  - Type validators (strict mode)                │           │
│  │  - Capability tracking                          │           │
│  │  - Environment detection                        │           │
│  │  - WeakRef registry for opaque types           │           │
│  └──────────────────────────────────────────────────┘           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Package Responsibilities

| Package | Responsibility | Depends On |
|---------|----------------|------------|
| **canopy-core** | Parse `foreign import`, type-check .can files, include runtime | nothing FFI-specific |
| **canopy-ffi** | JSDoc → .can + validators (extract from Foreign/FFI.hs) | canopy-ffi-runtime |
| **canopy-ts** | TypeScript .d.ts → .can + validators | canopy-ffi-runtime |
| **canopy-webidl** | WebIDL → .can + validators (existing) | canopy-ffi-runtime |
| **canopy-ffi-runtime** | Shared JS runtime library | nothing |

### Why Decoupled Architecture

| Aspect | Monolithic (v3.0) | Decoupled (v3.1) |
|--------|-------------------|------------------|
| Compiler complexity | 891+ lines of FFI | ~50 lines (parse syntax) |
| Type safety | Trust JSDoc | Generated + validated |
| TypeScript support | Partial | First-class |
| Tooling | Built into compiler | Standalone CLIs |
| Testing | Compiler tests | Isolated tool tests |
| Release cycle | FFI = compiler release | Independent releases |
| Industry alignment | Proprietary | bindgen/genType pattern |

---

# PHASE 1 — CRITICAL VULNERABILITIES

## 1.1 Architectural Flaws in v1.0/v2.0

### FAIL: Type System Duplication

**v1.0 Problem**: Creates `TypeSchema` with `SchemaInt`, `SchemaFloat`, etc.
**v2.0 Problem**: Uses `FFIType` which duplicates `Can.Type`.

```haskell
-- CURRENT (BAD): Duplicate type system
data FFIType
  = FFIBasic !Text      -- "Int", "String" as stringly-typed
  | FFIResult !FFIType !FFIType
  | FFITask !FFIType !FFIType
  ...
```

**Impact**: Two parallel type systems that can diverge. Changes to core types don't propagate to FFI.

### FAIL: No Lowered FFI IR

Both versions operate directly on either `FFIType` (intermediate) or generate JS directly. There is no lowered IR that:
- Separates FFI semantics from JS generation
- Enables optimization passes
- Provides stable intermediate representation

### FAIL: Stringly-Typed Type Contracts

```haskell
-- CURRENT: Type names as strings
FFIBasic "Int"   -- What if we rename Int?
FFIBasic "Bool"  -- No compile-time verification
```

**Impact**: No compile-time guarantee that JSDoc types match compiler types.

### FAIL: Incomplete Numeric Model

**Missing protections:**
- No 53-bit overflow detection for Int
- No NaN rejection at boundary
- No negative zero handling
- No BigInt integration
- No explicit Float vs Int separation at runtime

```javascript
// SILENT CORRUPTION
function getCount() { return 9007199254740993; } // > MAX_SAFE_INTEGER
// Canopy sees: 9007199254740992 (corrupted)
```

### FAIL: No Higher-Order Function Model

**v1.0/v2.0 callbacks are shallow:**
- No call-time validation
- No wrapper idempotency (wrapping twice = double validation)
- No closure lifetime tracking
- No capability propagation through callbacks
- No re-entry protection
- No async re-validation

```canopy
-- What happens when JS calls this callback with wrong types?
foreign import javascript "dom.js" as DOM
onClick : (Event -> msg) -> Attribute msg  -- UNPROTECTED
```

### FAIL: Opaque Type Lifecycle Undefined

```haskell
-- CURRENT: Phantom types with no runtime backing
FFIOpaque !Text  -- Just a name, no registry, no lifecycle
```

**Missing:**
- Ownership semantics (JS-owned? Canopy-owned?)
- Identity tracking (same object = same identity?)
- Destruction model (when is it safe to GC?)
- Cross-runtime serialization policy
- WeakRef/WeakMap integration

### FAIL: Capability System Not Integrated

**Two separate modules exist:**

| Module | Lines | Used | Integrated with Type Checker |
|--------|-------|------|------------------------------|
| `FFI.Capability` | 56 | Yes | **NO** |
| `Type.Capability` | 254 | **NO** | **NO** |

**Critical issues:**
- Capabilities are runtime values, not type-level constraints
- Can be forged via partial application
- Not tracked through async boundaries
- `window.CapabilityTracker` referenced but **doesn't exist**

### FAIL: Browser-Only Runtime Assumptions

```haskell
-- CURRENT: Direct window/document usage (Type/Capability.hs)
generateCapabilityCheck UserActivationCapability =
  "if (!window.CapabilityTracker.hasUserActivation()) ..."
```

**Will crash in:**
- Node.js (`window` undefined)
- Deno (`window` may be undefined)
- Bun (`window` undefined)
- SSR environments
- Web Workers

### FAIL: Non-Deterministic Code Generation

```haskell
-- FOUND IN Generate/JavaScript.hs:861
case Map.toList subs of ...

-- FOUND IN Generate/JavaScript/Expression.hs:311
JS.Object (fmap toPair (Map.toList fields))

-- FOUND IN Generate/JavaScript/Functions.hs:22-23
foldMap generateF (Set.toList arities)
```

**Impact**: `Map.toList` and `Set.toList` iteration order depends on key ordering. Different GHC versions or platforms may produce different output order, breaking deterministic hashing.

### FAIL: Kernel Code Still Present

```haskell
-- Canopy/Kernel.hs still exists with Elm-derived patterns
data Chunk
  = JS B.ByteString
  | CanopyVar ModuleName.Canonical Name.Name  -- Renamed from ElmVar
  | JsVar Name.Name Name.Name
  ...
```

**Binary format still uses Elm kernel chunk encoding.**

---

## 1.2 Soundness Gaps

### Integer Precision Corruption

JavaScript uses IEEE 754 doubles. Safe integer range: `-(2^53-1)` to `2^53-1`.

**Current behavior**: Silent truncation/corruption for integers outside safe range.

**Required**: Explicit handling strategy (clamp, error, or BigInt).

### NaN Poisoning

```javascript
function divide(a, b) { return a / b; }
divide(0, 0)  // Returns NaN
```

**Current**: NaN flows through as a valid Float, corrupting downstream calculations.

**Required**: NaN detection and explicit error at boundary.

### Callback Re-entry Hazards

```javascript
function processItems(items, callback) {
  items.forEach(item => {
    callback(item);  // What if callback modifies items?
  });
}
```

**Current**: No re-entry protection. Callback can mutate state mid-iteration.

### Cyclic Structure Infinite Recursion

```javascript
const obj = { name: "test" };
obj.self = obj;  // Cyclic reference
return obj;
```

**Current**: Deep validation/marshalling will stack overflow.

**Required**: Cycle detection with bounded depth or explicit handling.

---

## 1.3 Memory Hazards

### Opaque Object Leaks

```javascript
// JS creates AudioContext
const ctx = new AudioContext();
// Passed to Canopy
return CanopyMarshal.Initialized(ctx);
// When is ctx eligible for GC?
```

**Current**: No tracking. Objects leak if Canopy holds references longer than expected.

### Callback Retention

```javascript
// Canopy passes callback to JS
element.addEventListener('click', canopyCallback);
// canopyCallback holds closure over Canopy state
// When element is removed, callback is NOT removed
// Memory leak: Canopy state retained indefinitely
```

**Required**: WeakRef-based callback tracking or explicit cleanup API.

---

## 1.4 Security Holes

### Capability Forgery

```canopy
-- Capabilities are just values
userActivated : UserActivated
userActivated = UserActivated ()  -- Can be constructed anywhere!

-- No type-level protection
createAudioContext userActivated  -- Works even if forged
```

**Required**: Capabilities must be:
- Non-constructible outside trusted code
- Tracked in type system (phantom type parameters)
- Impossible to strip via partial application

### Prototype Pollution

```javascript
// Attacker modifies Object prototype
Object.prototype.isAdmin = true;

// Canopy record marshalling
const record = { name: "user" };
record.isAdmin  // true (unexpected field!)
```

**Required**: Use `Object.create(null)` or explicit `hasOwnProperty` checks.

---

## 1.5 Performance Traps

### Monomorphization Explosion

```haskell
-- v1.0 generates validators per function
generateFunctionValidator :: JSDocFunction -> Text
```

For 225 FFI functions with average 3 parameters each, this generates 675+ validator functions. With nested types, explosion is worse.

**Required**: Schema-based validation with shared validators.

### Double Wrapping

```javascript
// If callback is wrapped on every call
function withCallback(cb) {
  return wrappedFFI(wrapCallback(cb));  // Wrap
}

// Called in loop
for (let i = 0; i < 1000; i++) {
  withCallback(myCallback);  // 1000 wrapper allocations
}
```

**Required**: Idempotent wrapping via WeakMap memoization.

---

## 1.6 Determinism Violations

### Non-Deterministic Iteration

**Found instances:**

| File | Line | Pattern |
|------|------|---------|
| `Generate/JavaScript.hs` | 536 | `Map.keys graph` |
| `Generate/JavaScript.hs` | 861 | `Map.toList subs` |
| `Generate/JavaScript/StringPool.hs` | 55 | `Map.keys poolEntries` |
| `Generate/JavaScript/Expression.hs` | 210 | `Set.toList fields` |
| `Generate/JavaScript/Expression.hs` | 311 | `Map.toList fields` |
| `Generate/JavaScript/CodeSplit/Analyze.hs` | 462 | `Set.toList users` |
| `Generate/JavaScript/CodeSplit/Generate.hs` | 215 | `Set.toList globals` |
| `Generate/JavaScript/CodeSplit/Generate.hs` | 515 | `Map.toList subs` |

**Impact**: Two identical compilations may produce different JS output, breaking CI caching and reproducible builds.

**Required**: Sort before iteration or use ordered containers.

---

# PHASE 2 — CODEBASE-SPECIFIC FEEDBACK

## 2.1 Files to Delete

| File | Reason |
|------|--------|
| `packages/canopy-core/src/Type/Capability.hs` | Unused (254 lines dead code) |
| `packages/canopy-core/src/FFI/Capability.hs` | Replace with integrated capability system |

## 2.2 Files to Create

| File | Purpose |
|------|---------|
| `packages/canopy-core/src/FFI/IR.hs` | Lowered FFI IR types |
| `packages/canopy-core/src/FFI/Lower.hs` | Lower Can.Type to FFI IR |
| `packages/canopy-core/src/FFI/Validate.hs` | Compile-time FFI validation |
| `packages/canopy-core/src/FFI/Memory.hs` | Opaque registry, weak refs |
| `packages/canopy-core/src/FFI/Numeric.hs` | Safe integer/float handling |
| `packages/canopy-core/src/FFI/Capability.hs` | Integrated capability system |
| `packages/canopy-core/src/FFI/Runtime.hs` | Environment-agnostic runtime |
| `packages/canopy-core/js/canopy-ffi-runtime.js` | JS runtime library |

## 2.3 Files to Modify

| File | Changes Required |
|------|------------------|
| `Foreign/FFI.hs` | Remove `FFIType`, use FFI IR |
| `Generate/JavaScript.hs` | Sort `Map.toList` calls |
| `Generate/JavaScript/Expression.hs` | Sort `Map.toList`, `Set.toList` |
| `Generate/JavaScript/CodeSplit/*.hs` | Sort all iteration |
| `Canonicalize/Module.hs` | Integrate capability checking |
| `Type/Constrain.hs` | Add capability constraints |
| `Type/Solve.hs` | Solve capability constraints |

## 2.4 Unsafe Example Code to Fix

**`examples/audio-ffi/external/audio.js`:**

```javascript
// UNSAFE: Manual Canopy structure construction
return { $: 'Ok', a: { $: 'Fresh', a: ctx } };

// UNSAFE: Direct window access
const ctx = new (window.AudioContext || window.webkitAudioContext)();

// UNSAFE: No input validation
function createOscillator(context) {
  // context could be anything!
  return context.createOscillator();
}
```

## 2.5 Runtime Assumptions to Remove

| Assumption | Location | Fix |
|------------|----------|-----|
| `window.CapabilityTracker` | `Type/Capability.hs:217-254` | Feature-detected runtime |
| `window.AudioContext` | `audio.js` examples | Feature detection |
| `document.addEventListener` | `capability-tracker.js` (v1.0) | Environment check |
| `navigator.permissions` | `capability-tracker.js` (v1.0) | Graceful degradation |

---

# PHASE 3 — v3.0 MASTER FFI ARCHITECTURE

## 3.1 FFI Lowered IR (Exact Haskell Types)

```haskell
{-# LANGUAGE StrictData #-}
{-# OPTIONS_GHC -Wall #-}

-- | FFI/IR.hs — Lowered FFI Intermediate Representation
--
-- This IR is independent of source AST and target JS.
-- It represents the semantic contract between Canopy and JavaScript.
module FFI.IR
  ( -- * Core Types
    FFIModule(..)
  , FFIBinding(..)
  , FFISignature(..)
  , FFIParam(..)

    -- * Type Representation
  , FFITypeRep(..)
  , PrimitiveType(..)
  , ContainerType(..)
  , OpaqueTypeId(..)

    -- * Capabilities
  , CapabilitySet
  , Capability(..)

    -- * Numeric Constraints
  , NumericConstraint(..)
  , IntegerBounds(..)

    -- * Callback Specification
  , CallbackSpec(..)
  , CallbackSemantics(..)
  ) where

import Data.Map.Strict (Map)
import Data.Set (Set)
import Data.Text (Text)
import Data.Word (Word64)
import qualified Canopy.ModuleName as ModuleName

-- | Complete FFI module after lowering
data FFIModule = FFIModule
  { ffiModuleName :: ModuleName.Canonical
    -- ^ Canonical module name
  , ffiModuleSource :: FilePath
    -- ^ JavaScript source file
  , ffiModuleBindings :: [FFIBinding]
    -- ^ All FFI bindings
  , ffiModuleOpaqueTypes :: Map OpaqueTypeId OpaqueTypeSpec
    -- ^ Opaque type registry
  , ffiModuleHash :: Word64
    -- ^ Content hash for caching
  } deriving (Eq, Show)

-- | Single FFI binding
data FFIBinding = FFIBinding
  { ffiBindingName :: Text
    -- ^ Canopy function name
  , ffiBindingJSName :: Text
    -- ^ JavaScript function name
  , ffiBindingSignature :: FFISignature
    -- ^ Type signature
  , ffiBindingCapabilities :: CapabilitySet
    -- ^ Required capabilities
  , ffiBindingPure :: Bool
    -- ^ Is function pure (no side effects)?
  , ffiBindingAsync :: Bool
    -- ^ Is function async (returns Task)?
  } deriving (Eq, Show)

-- | Function signature
data FFISignature = FFISignature
  { sigParams :: [FFIParam]
    -- ^ Input parameters
  , sigReturn :: FFITypeRep
    -- ^ Return type
  , sigCallbacks :: [CallbackSpec]
    -- ^ Callback specifications (if any)
  } deriving (Eq, Show)

-- | Function parameter
data FFIParam = FFIParam
  { paramName :: Text
    -- ^ Parameter name (for error messages)
  , paramType :: FFITypeRep
    -- ^ Parameter type
  , paramOptional :: Bool
    -- ^ Is parameter optional?
  } deriving (Eq, Show)

-- | Type representation (NOT stringly-typed)
data FFITypeRep
  = FFIPrimitive PrimitiveType
    -- ^ Primitive types with constraints
  | FFIContainer ContainerType FFITypeRep
    -- ^ Container types (List, Maybe, etc.)
  | FFIResult FFITypeRep FFITypeRep
    -- ^ Result err ok
  | FFITask FFITypeRep FFITypeRep
    -- ^ Task err ok (async)
  | FFIRecord (Map Text FFITypeRep)
    -- ^ Record type { field: Type }
  | FFITuple [FFITypeRep]
    -- ^ Tuple type (a, b, c)
  | FFIFunction FFISignature
    -- ^ Higher-order function
  | FFIOpaque OpaqueTypeId
    -- ^ Opaque JS type
  | FFIUnit
    -- ^ Unit type ()
  deriving (Eq, Show)

-- | Primitive types with explicit constraints
data PrimitiveType
  = PrimInt IntegerBounds
    -- ^ Integer with bounds
  | PrimFloat
    -- ^ IEEE 754 double
  | PrimBool
    -- ^ Boolean
  | PrimString
    -- ^ UTF-16 string
  | PrimChar
    -- ^ Single UTF-16 code unit
  deriving (Eq, Show)

-- | Integer bounds for safe handling
data IntegerBounds
  = SafeInteger
    -- ^ -(2^53-1) to (2^53-1), validated at boundary
  | UncheckedInteger
    -- ^ No validation (legacy mode)
  | BigIntRequired
    -- ^ Must use BigInt
  deriving (Eq, Show)

-- | Container types
data ContainerType
  = ContainerList
  | ContainerMaybe
  | ContainerArray    -- ^ JS Array (not Canopy List)
  | ContainerTypedArray TypedArrayKind
  deriving (Eq, Show)

-- | TypedArray variants
data TypedArrayKind
  = Int8Array | Uint8Array | Uint8ClampedArray
  | Int16Array | Uint16Array
  | Int32Array | Uint32Array
  | Float32Array | Float64Array
  | BigInt64Array | BigUint64Array
  deriving (Eq, Show)

-- | Opaque type identifier
newtype OpaqueTypeId = OpaqueTypeId
  { unOpaqueTypeId :: Text
  } deriving (Eq, Ord, Show)

-- | Opaque type specification
data OpaqueTypeSpec = OpaqueTypeSpec
  { opaqueConstructor :: Maybe Text
    -- ^ JS constructor name (for instanceof check)
  , opaqueOwnership :: Ownership
    -- ^ Who owns the object?
  , opaqueDisposable :: Bool
    -- ^ Does it need explicit cleanup?
  } deriving (Eq, Show)

-- | Object ownership model
data Ownership
  = JSOwned
    -- ^ JavaScript owns, Canopy borrows
  | CanopyOwned
    -- ^ Canopy owns, must explicitly release to JS
  | SharedOwnership
    -- ^ Reference counted or immutable
  deriving (Eq, Show)

-- | Capability set (non-forgeable)
type CapabilitySet = Set Capability

-- | Capability types
data Capability
  = CapUserActivation
    -- ^ Requires user gesture
  | CapPermission Text
    -- ^ Requires browser permission
  | CapInitialized OpaqueTypeId
    -- ^ Requires initialized resource
  | CapAvailable Text
    -- ^ Requires feature availability
  | CapSecureContext
    -- ^ Requires HTTPS
  deriving (Eq, Ord, Show)

-- | Callback specification
data CallbackSpec = CallbackSpec
  { cbParamIndex :: Int
    -- ^ Which parameter is the callback
  , cbSignature :: FFISignature
    -- ^ Expected callback signature
  , cbSemantics :: CallbackSemantics
    -- ^ Callback behavior constraints
  } deriving (Eq, Show)

-- | Callback behavioral constraints
data CallbackSemantics
  = SyncCallback
    -- ^ Called synchronously, no re-entry
  | AsyncCallback
    -- ^ Called asynchronously (event handler)
  | OneShot
    -- ^ Called exactly once
  | Streaming
    -- ^ Called multiple times (observable)
  deriving (Eq, Show)

-- | Numeric constraint checking
data NumericConstraint
  = NoConstraint
  | RejectNaN
  | RejectInfinity
  | ClampToSafeRange
  | RequireBigInt
  deriving (Eq, Show)
```

## 3.2 Memory Model

### Object Ownership Rules

```
┌─────────────────────────────────────────────────────────────┐
│                    OWNERSHIP MODEL                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  JS-Owned (Default for opaque types)                        │
│  ┌─────────┐         ┌─────────────┐                        │
│  │   JS    │ ──────► │  Canopy     │                        │
│  │ (owns)  │         │ (borrows)   │                        │
│  └─────────┘         └─────────────┘                        │
│  - JS creates object                                        │
│  - Canopy receives opaque handle                            │
│  - JS controls lifecycle                                    │
│  - Canopy must not retain past JS intent                    │
│                                                             │
│  Canopy-Owned (For Canopy-allocated data)                   │
│  ┌─────────────┐         ┌─────────┐                        │
│  │   Canopy    │ ──────► │   JS    │                        │
│  │  (owns)     │         │(borrows)│                        │
│  └─────────────┘         └─────────┘                        │
│  - Canopy creates data structure                            │
│  - JS receives marshalled copy or view                      │
│  - Canopy controls when data can be released                │
│                                                             │
│  Shared (For immutable or ref-counted)                      │
│  ┌─────────┐    ◄────►    ┌─────────┐                       │
│  │   JS    │              │ Canopy  │                       │
│  └─────────┘              └─────────┘                       │
│  - Either side can hold references                          │
│  - GC collects when no references remain                    │
│  - Used for immutable data (strings, frozen objects)        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Opaque Registry Design

```haskell
-- | FFI/Memory.hs — Opaque type registry and weak reference management

module FFI.Memory
  ( OpaqueRegistry
  , registerOpaque
  , lookupOpaque
  , releaseOpaque
  , generateRegistryCode
  ) where

-- Compile-time registry for opaque type metadata
data OpaqueRegistry = OpaqueRegistry
  { registryTypes :: Map OpaqueTypeId OpaqueTypeSpec
  , registryValidators :: Map OpaqueTypeId Text
    -- ^ Generated instanceof/duck-type validators
  }

-- Runtime JavaScript registry
generateRegistryCode :: OpaqueRegistry -> Builder
generateRegistryCode registry = [r|
const $canopy$opaque = {
  // WeakMap for identity tracking
  _identityMap: new WeakMap(),
  _nextId: 0,

  // Register an opaque object, return stable ID
  register(obj, typeId) {
    if (this._identityMap.has(obj)) {
      return this._identityMap.get(obj);
    }
    const id = { _$opaque: typeId, _$id: this._nextId++ };
    this._identityMap.set(obj, id);
    return id;
  },

  // Get object from ID (returns undefined if GC'd)
  get(id) {
    // Reverse lookup via FinalizationRegistry
    return this._reverseMap.get(id._$id);
  },

  // Weak reverse map with cleanup
  _reverseMap: new Map(),
  _finalization: new FinalizationRegistry(id => {
    $canopy$opaque._reverseMap.delete(id);
  }),

  // Store with weak reference
  store(obj, id) {
    this._reverseMap.set(id._$id, obj);
    this._finalization.register(obj, id._$id);
  }
};
|]
```

### WeakRef Strategy

```javascript
// Runtime weak reference handling
const $canopy$weak = {
  // Store callbacks with weak references to prevent leaks
  callbacks: new WeakMap(),

  wrapCallback(canopyFn, signature) {
    // Check if already wrapped (idempotent)
    if (this.callbacks.has(canopyFn)) {
      return this.callbacks.get(canopyFn);
    }

    const wrapped = (...args) => {
      // Validate inputs according to signature
      const validatedArgs = signature.params.map((param, i) =>
        $canopy$ffi.validate(args[i], param.type, `callback.arg${i}`)
      );

      // Call Canopy function
      const result = canopyFn(...validatedArgs);

      // Validate output
      return $canopy$ffi.validate(result, signature.return, 'callback.result');
    };

    this.callbacks.set(canopyFn, wrapped);
    return wrapped;
  }
};
```

### Callback Retention Model

```
┌─────────────────────────────────────────────────────────────┐
│                  CALLBACK LIFECYCLE                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Canopy creates callback closure                         │
│     ┌──────────────┐                                        │
│     │ Canopy State │◄──┐                                    │
│     └──────────────┘   │                                    │
│                        │ closes over                        │
│     ┌──────────────┐   │                                    │
│     │   Callback   │───┘                                    │
│     └──────────────┘                                        │
│                                                             │
│  2. Callback passed to JS (wrapped)                         │
│     ┌──────────────┐     ┌──────────────┐                   │
│     │   Callback   │────►│   Wrapper    │                   │
│     └──────────────┘     └──────────────┘                   │
│                                │                            │
│                                ▼                            │
│     ┌──────────────┐     ┌──────────────┐                   │
│     │  WeakMap     │◄────│  JS Handler  │                   │
│     └──────────────┘     └──────────────┘                   │
│                                                             │
│  3. When JS no longer references handler:                   │
│     - WeakMap entry becomes eligible for GC                 │
│     - Wrapper is collected                                  │
│     - Canopy callback can be collected                      │
│     - Canopy state can be collected (if no other refs)      │
│                                                             │
│  INVARIANT: Canopy state lifetime ≥ callback lifetime       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Finalization Guarantees

**We do NOT guarantee finalization timing.** JavaScript's GC is non-deterministic.

**What we guarantee:**
1. No memory leaks from FFI wrapper allocations
2. Opaque object identity is stable while object exists
3. Callbacks do not retain Canopy state longer than necessary
4. Explicit `dispose()` API for resources requiring deterministic cleanup

```canopy
-- For resources requiring explicit cleanup
type alias Disposable a =
    { value : a
    , dispose : Task Never ()
    }

-- Usage
createAudioContext : UserActivated -> Task CapabilityError (Disposable (Initialized AudioContext))
```

## 3.3 Capability Model

### Type System Integration

```haskell
-- | FFI/Capability.hs — Integrated capability constraints

module FFI.Capability
  ( -- * Capability Representation
    Capability(..)
  , CapabilityVar

    -- * Constraint Integration
  , CapabilityConstraint(..)
  , addCapabilityConstraint
  , solveCapabilityConstraints

    -- * Type-Level Tracking
  , CapabilityPhantom
  , withCapability
  ) where

import qualified Type.Type as Type
import qualified Type.Constraint as Constraint

-- | Capability constraint in type system
data CapabilityConstraint
  = HasCapability Capability Type.Type
    -- ^ Type must have capability
  | PropagatesCapability Capability Type.Type Type.Type
    -- ^ Capability flows from first type to second
  deriving (Eq, Show)

-- | Add capability constraint during type inference
addCapabilityConstraint :: Capability -> Type.Type -> Constraint.Constraint
addCapabilityConstraint cap ty =
  Constraint.CCapability (HasCapability cap ty)

-- | Solve capability constraints
-- Returns Left if capability requirement cannot be satisfied
solveCapabilityConstraints
  :: [CapabilityConstraint]
  -> Either CapabilityError ()
solveCapabilityConstraints constraints =
  -- Check that all capabilities are either:
  -- 1. Provided by an FFI function that acquires them
  -- 2. Propagated from a parameter
  -- 3. Part of the function's declared requirements
  traverse_ checkConstraint constraints
```

### Non-Forgeability Proof Sketch

**Claim**: Capabilities cannot be forged by user code.

**Mechanism**:
1. Capability types are **opaque** — constructors not exported
2. Only FFI functions can **create** capability values
3. FFI functions that create capabilities require **runtime proof** (user gesture, permission grant, etc.)
4. Type system tracks capability **flow** — cannot appear from nowhere

```canopy
-- Module: Platform.Capability (INTERNAL)
-- Constructors NOT exported

type UserActivated = UserActivated ()
type Initialized a = Initialized a
type Permitted p = Permitted p

-- ONLY way to get UserActivated:
-- Through an event handler that the runtime knows was triggered by user

-- User code CANNOT write:
-- fakeActivation = UserActivated ()  -- ERROR: constructor not in scope
```

**Async Propagation**:
```canopy
-- Capability MUST flow through Task chain
createAudioContext : UserActivated -> Task CapabilityError (Initialized AudioContext)

-- INVALID: Cannot extract and reuse
badExample : Task CapabilityError (Initialized AudioContext)
badExample =
    -- ERROR: UserActivated required but not available
    createAudioContext ???

-- VALID: Capability flows from onClick handler
goodExample : Attribute Msg
goodExample =
    onClick (\userActivation ->
        -- userActivation : UserActivated (provided by runtime)
        createAudioContext userActivation
    )
```

### Async Propagation Rules

```
┌─────────────────────────────────────────────────────────────┐
│              CAPABILITY ASYNC PROPAGATION                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Rule 1: Task preserves capabilities                        │
│  ─────────────────────────────────────                      │
│  If: f : Cap -> Task e (Cap' a)                             │
│  Then: Cap flows into Task, Cap' available in continuation  │
│                                                             │
│  Rule 2: andThen propagates                                 │
│  ────────────────────────────                               │
│  task |> Task.andThen (\result -> nextTask)                 │
│  Capabilities from task available in nextTask               │
│                                                             │
│  Rule 3: UserActivation expires                             │
│  ────────────────────────────────                           │
│  UserActivated is CONSUMED by first use                     │
│  Cannot be reused across multiple operations                │
│                                                             │
│  Rule 4: Initialization persists                            │
│  ───────────────────────────────                            │
│  Initialized a remains valid for lifetime of a              │
│  Can be used multiple times                                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 3.4 Runtime Layout

### JS Artifact Structure

```
canopy-output/
├── Main.js                    # Application entry point
├── $canopy$ffi.js             # FFI runtime (always included)
├── $canopy$ffi.validators.js  # Type validators (strict mode only)
├── AudioFFI.ffi.js            # Per-module FFI bindings
└── source-maps/
    └── Main.js.map            # Source maps for debugging
```

### FFI Runtime Structure

```javascript
// $canopy$ffi.js — Environment-agnostic FFI runtime
(function(global) {
  'use strict';

  // Environment detection
  const ENV = {
    isBrowser: typeof window !== 'undefined',
    isNode: typeof process !== 'undefined' && process.versions?.node,
    isDeno: typeof Deno !== 'undefined',
    isBun: typeof Bun !== 'undefined',
    isWorker: typeof WorkerGlobalScope !== 'undefined'
  };

  // Feature detection (NOT assumption)
  const FEATURES = {
    WeakRef: typeof WeakRef !== 'undefined',
    FinalizationRegistry: typeof FinalizationRegistry !== 'undefined',
    BigInt: typeof BigInt !== 'undefined',
    userActivation: ENV.isBrowser && 'userActivation' in navigator
  };

  // Core FFI object
  const $canopy$ffi = {
    // Marshalling helpers
    Ok: (value) => ({ $: 'Ok', a: value }),
    Err: (error) => ({ $: 'Err', a: error }),
    Just: (value) => ({ $: 'Just', a: value }),
    Nothing: { $: 'Nothing' },

    // List conversion
    toList: (arr) => {
      let list = { $: 'Nil' };
      for (let i = arr.length - 1; i >= 0; i--) {
        list = { $: 'Cons', a: arr[i], b: list };
      }
      return list;
    },

    fromList: (list) => {
      const arr = [];
      while (list.$ === 'Cons') {
        arr.push(list.a);
        list = list.b;
      }
      return arr;
    },

    // Safe integer handling
    safeInt: (n, path) => {
      if (!Number.isInteger(n)) {
        throw new FFITypeError(`${path}: expected Int, got ${typeof n}`);
      }
      if (n > Number.MAX_SAFE_INTEGER || n < Number.MIN_SAFE_INTEGER) {
        throw new FFIRangeError(`${path}: integer ${n} outside safe range`);
      }
      return n;
    },

    // NaN rejection
    safeFloat: (n, path) => {
      if (typeof n !== 'number') {
        throw new FFITypeError(`${path}: expected Float, got ${typeof n}`);
      }
      if (Number.isNaN(n)) {
        throw new FFITypeError(`${path}: NaN is not a valid Float`);
      }
      return n;
    },

    // Validation (schema-based)
    validate: (value, schema, path) => {
      // Delegated to validators module in strict mode
      // No-op in legacy mode
      return value;
    }
  };

  // Error types
  class FFIError extends Error {
    constructor(message) {
      super(message);
      this.name = 'FFIError';
    }
  }

  class FFITypeError extends FFIError {
    constructor(message) {
      super(message);
      this.name = 'FFITypeError';
    }
  }

  class FFIRangeError extends FFIError {
    constructor(message) {
      super(message);
      this.name = 'FFIRangeError';
    }
  }

  class FFICapabilityError extends FFIError {
    constructor(message) {
      super(message);
      this.name = 'FFICapabilityError';
    }
  }

  // Capability tracking (environment-agnostic)
  const $canopy$cap = {
    _userActivated: false,
    _permissions: new Map(),
    _initialized: new Map(),
    _available: new Map(),

    // User activation (browser-specific, graceful elsewhere)
    hasUserActivation() {
      if (FEATURES.userActivation) {
        return navigator.userActivation.isActive;
      }
      // Non-browser: assume available (server-side has no user)
      return !ENV.isBrowser || this._userActivated;
    },

    requireUserActivation() {
      if (!this.hasUserActivation()) {
        throw new FFICapabilityError('User activation required');
      }
    },

    // Permission checking (browser-specific)
    async hasPermission(name) {
      if (!ENV.isBrowser || !navigator.permissions) {
        return true; // Non-browser: assume granted
      }
      try {
        const result = await navigator.permissions.query({ name });
        return result.state === 'granted';
      } catch (e) {
        return false;
      }
    },

    // Feature availability
    isAvailable(feature) {
      if (this._available.has(feature)) {
        return this._available.get(feature);
      }
      const available = this._checkAvailability(feature);
      this._available.set(feature, available);
      return available;
    },

    _checkAvailability(feature) {
      switch (feature) {
        case 'AudioContext':
          return typeof AudioContext !== 'undefined' ||
                 typeof webkitAudioContext !== 'undefined';
        case 'WebGL':
          return ENV.isBrowser && !!global.WebGLRenderingContext;
        case 'WebGL2':
          return ENV.isBrowser && !!global.WebGL2RenderingContext;
        case 'ServiceWorker':
          return ENV.isBrowser && 'serviceWorker' in navigator;
        case 'Clipboard':
          return ENV.isBrowser && 'clipboard' in navigator;
        default:
          // Unknown feature: check global
          return feature in global;
      }
    },

    // Initialization tracking
    markInitialized(resource, instance) {
      this._initialized.set(resource, instance);
    },

    isInitialized(resource) {
      return this._initialized.has(resource);
    },

    getInitialized(resource) {
      if (!this.isInitialized(resource)) {
        throw new FFICapabilityError(`Resource not initialized: ${resource}`);
      }
      return this._initialized.get(resource);
    }
  };

  // Export
  global.$canopy$ffi = $canopy$ffi;
  global.$canopy$cap = $canopy$cap;
  global.FFIError = FFIError;
  global.FFITypeError = FFITypeError;
  global.FFIRangeError = FFIRangeError;
  global.FFICapabilityError = FFICapabilityError;

})(typeof globalThis !== 'undefined' ? globalThis :
   typeof window !== 'undefined' ? window :
   typeof global !== 'undefined' ? global :
   typeof self !== 'undefined' ? self : {});
```

### Validator Structure

```javascript
// $canopy$ffi.validators.js — Generated type validators (strict mode)
(function(global) {
  'use strict';

  const V = {
    // Primitive validators
    int: (v, p) => {
      if (!Number.isInteger(v)) throw new FFITypeError(`${p}: expected Int`);
      if (v > 9007199254740991 || v < -9007199254740991) {
        throw new FFIRangeError(`${p}: integer outside safe range`);
      }
      return v;
    },

    float: (v, p) => {
      if (typeof v !== 'number') throw new FFITypeError(`${p}: expected Float`);
      if (Number.isNaN(v)) throw new FFITypeError(`${p}: NaN not allowed`);
      return v;
    },

    bool: (v, p) => {
      if (typeof v !== 'boolean') throw new FFITypeError(`${p}: expected Bool`);
      return v;
    },

    string: (v, p) => {
      if (typeof v !== 'string') throw new FFITypeError(`${p}: expected String`);
      return v;
    },

    // Container validators
    list: (inner) => (v, p) => {
      if (!Array.isArray(v)) throw new FFITypeError(`${p}: expected List`);
      return $canopy$ffi.toList(v.map((e, i) => inner(e, `${p}[${i}]`)));
    },

    maybe: (inner) => (v, p) => {
      if (v === null || v === undefined) return $canopy$ffi.Nothing;
      return $canopy$ffi.Just(inner(v, p));
    },

    result: (errV, okV) => (v, p) => {
      if (!v || typeof v.$ !== 'string') {
        throw new FFITypeError(`${p}: expected Result`);
      }
      if (v.$ === 'Ok') return $canopy$ffi.Ok(okV(v.a, `${p}.Ok`));
      if (v.$ === 'Err') return $canopy$ffi.Err(errV(v.a, `${p}.Err`));
      throw new FFITypeError(`${p}: invalid Result variant: ${v.$}`);
    },

    // Record validator (with prototype pollution protection)
    record: (fields) => (v, p) => {
      if (typeof v !== 'object' || v === null) {
        throw new FFITypeError(`${p}: expected Record`);
      }
      const result = Object.create(null); // No prototype
      for (const [name, validator] of Object.entries(fields)) {
        if (!Object.prototype.hasOwnProperty.call(v, name)) {
          throw new FFITypeError(`${p}: missing field '${name}'`);
        }
        result[name] = validator(v[name], `${p}.${name}`);
      }
      return result;
    },

    // Opaque type validator
    opaque: (typeId, constructor) => (v, p) => {
      if (constructor && !(v instanceof constructor)) {
        throw new FFITypeError(`${p}: expected ${typeId}`);
      }
      return v;
    },

    // Function/callback validator
    fn: (params, ret) => (v, p) => {
      if (typeof v !== 'function') {
        throw new FFITypeError(`${p}: expected Function`);
      }
      // Return wrapped function that validates on call
      return $canopy$weak.wrapCallback(v, { params, ret });
    }
  };

  global.$canopy$validators = V;

})(typeof globalThis !== 'undefined' ? globalThis :
   typeof window !== 'undefined' ? window :
   typeof global !== 'undefined' ? global :
   typeof self !== 'undefined' ? self : {});
```

### Stable Naming System

```haskell
-- | Generate deterministic, stable names for FFI artifacts
module FFI.Naming
  ( generateValidatorName
  , generateWrapperName
  , generateSchemaHash
  ) where

import Crypto.Hash (SHA256, hash)
import qualified Data.ByteString as BS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text

-- | Generate stable validator name from type signature
-- Uses content hash to ensure same type = same name
generateValidatorName :: FFITypeRep -> Text
generateValidatorName typeRep =
  "_$v$" <> Text.pack (take 8 (show (generateSchemaHash typeRep)))

-- | Generate stable wrapper name
generateWrapperName :: Text -> Text
generateWrapperName funcName =
  funcName <> "_$safe"

-- | Hash type schema for deduplication
generateSchemaHash :: FFITypeRep -> Word64
generateSchemaHash typeRep =
  let bytes = Text.encodeUtf8 (serializeTypeRep typeRep)
      digest = hash bytes :: Digest SHA256
  in fromIntegral (BS.foldl' (\acc b -> acc * 256 + fromIntegral b) 0 (BS.take 8 (convert digest)))

-- | Serialize type rep deterministically
-- CRITICAL: Must produce same output regardless of Map iteration order
serializeTypeRep :: FFITypeRep -> Text
serializeTypeRep = \case
  FFIPrimitive prim -> serializePrimitive prim
  FFIContainer cont inner ->
    "C:" <> serializeContainer cont <> "(" <> serializeTypeRep inner <> ")"
  FFIResult err ok ->
    "R(" <> serializeTypeRep err <> "," <> serializeTypeRep ok <> ")"
  FFITask err ok ->
    "T(" <> serializeTypeRep err <> "," <> serializeTypeRep ok <> ")"
  FFIRecord fields ->
    -- SORT fields by name for determinism
    let sortedFields = List.sortOn fst (Map.toList fields)
        serialized = map (\(n, t) -> n <> ":" <> serializeTypeRep t) sortedFields
    in "{" <> Text.intercalate "," serialized <> "}"
  FFITuple types ->
    "(" <> Text.intercalate "," (map serializeTypeRep types) <> ")"
  FFIFunction sig ->
    "F:" <> serializeSignature sig
  FFIOpaque (OpaqueTypeId name) ->
    "O:" <> name
  FFIUnit ->
    "()"
```

## 3.5 Strict vs Zero-Cost Mode

### Mode Definitions

| Mode | Validation | Wrappers | Overhead | Use Case |
|------|------------|----------|----------|----------|
| **Legacy** | None | None | Zero | Existing code, trusted FFI |
| **Strict** | Full | Generated | ~1-5% | Development, untrusted FFI |
| **Debug** | Full + Logging | Generated | ~10-20% | Debugging FFI issues |

### Compilation Differences

```haskell
-- | FFI compilation modes
data FFIMode
  = FFILegacy    -- ^ No validation, zero overhead
  | FFIStrict    -- ^ Full runtime validation
  | FFIDebug     -- ^ Validation + detailed logging
  deriving (Eq, Show)

-- | Generate FFI binding based on mode
generateBinding :: FFIMode -> FFIBinding -> Builder
generateBinding mode binding = case mode of
  FFILegacy -> generateLegacyBinding binding
  FFIStrict -> generateStrictBinding binding
  FFIDebug  -> generateDebugBinding binding

-- Legacy: Direct call, no validation
generateLegacyBinding :: FFIBinding -> Builder
generateLegacyBinding binding = [r|
function ${name}(${params}) {
  return ${jsName}(${params});
}
|]

-- Strict: Validation wrappers
generateStrictBinding :: FFIBinding -> Builder
generateStrictBinding binding = [r|
function ${name}(${params}) {
  ${inputValidation}
  const _result = ${jsName}(${validatedParams});
  return ${outputValidation};
}
|]

-- Debug: Validation + logging
generateDebugBinding :: FFIBinding -> Builder
generateDebugBinding binding = [r|
function ${name}(${params}) {
  console.log('[FFI] ${name} called with:', ${params});
  ${inputValidation}
  const _start = performance.now();
  const _result = ${jsName}(${validatedParams});
  const _end = performance.now();
  console.log('[FFI] ${name} returned in', _end - _start, 'ms:', _result);
  return ${outputValidation};
}
|]
```

### Zero Overhead Proof

**Claim**: Legacy mode produces identical output to pre-FFI-improvement code.

**Proof**:
1. Legacy mode generates direct function calls with no wrapper
2. No validation code included in output
3. No runtime library overhead (validators not loaded)
4. Byte-for-byte identical to current implementation

**Verification**:
```bash
# Build with legacy mode
canopy make --ffi=legacy

# Build with current (pre-improvement) compiler
canopy-old make

# Compare output
diff <(sha256sum output/Main.js) <(sha256sum output-old/Main.js)
# Expected: identical hashes
```

## 3.6 Determinism Guarantees

### Mechanism for Stable Output

```haskell
-- | Deterministic code generation utilities
module FFI.Determinism
  ( sortedMapToList
  , sortedSetToList
  , deterministicHash
  ) where

import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

-- | Convert Map to list with deterministic ordering
-- Uses Ord instance of key type
sortedMapToList :: Ord k => Map.Map k v -> [(k, v)]
sortedMapToList = List.sortOn fst . Map.toList

-- | Convert Set to list with deterministic ordering
sortedSetToList :: Ord a => Set.Set a -> [a]
sortedSetToList = List.sort . Set.toList

-- | Generate deterministic content hash
-- Includes all inputs that affect output
deterministicHash :: FFIModule -> Word64
deterministicHash ffiModule =
  hashWith SHA256 $ mconcat
    [ encodeUtf8 (moduleNameToText (ffiModuleName ffiModule))
    , encodeUtf8 (Text.pack (ffiModuleSource ffiModule))
    , mconcat (map hashBinding (List.sortOn ffiBindingName (ffiModuleBindings ffiModule)))
    ]
```

### Files to Modify for Determinism

| File | Line | Change |
|------|------|--------|
| `Generate/JavaScript.hs` | 536 | `List.sort (Map.keys graph)` |
| `Generate/JavaScript.hs` | 861 | `sortedMapToList subs` |
| `Generate/JavaScript/StringPool.hs` | 55 | `List.sort (Map.keys poolEntries)` |
| `Generate/JavaScript/Expression.hs` | 210 | `List.sort (Set.toList fields)` |
| `Generate/JavaScript/Expression.hs` | 311 | `sortedMapToList fields` |
| `Generate/JavaScript/CodeSplit/Analyze.hs` | 462 | `List.sort (Set.toList users)` |
| `Generate/JavaScript/CodeSplit/Generate.hs` | 215 | `List.sort (Set.toList globals)` |
| `Generate/JavaScript/CodeSplit/Generate.hs` | 515 | `sortedMapToList subs` |

### Verification Harness

```bash
#!/bin/bash
# determinism-test.sh — Verify compilation determinism

set -e

PROJECT=$1
ITERATIONS=${2:-10}

echo "Testing determinism for $PROJECT ($ITERATIONS iterations)"

# First compilation
canopy make --output=.test-det/baseline
BASELINE_HASH=$(sha256sum .test-det/baseline/Main.js | cut -d' ' -f1)

# Subsequent compilations
for i in $(seq 2 $ITERATIONS); do
  rm -rf .test-det/iter$i
  canopy make --output=.test-det/iter$i
  ITER_HASH=$(sha256sum .test-det/iter$i/Main.js | cut -d' ' -f1)

  if [ "$BASELINE_HASH" != "$ITER_HASH" ]; then
    echo "FAIL: Iteration $i produced different output"
    diff .test-det/baseline/Main.js .test-det/iter$i/Main.js
    exit 1
  fi
done

echo "PASS: All $ITERATIONS iterations produced identical output"
echo "Hash: $BASELINE_HASH"
```

---

# PHASE 4 — VERIFICATION STRATEGY

## 4.1 Property Tests

```haskell
-- | FFI property tests
module Test.FFI.Properties where

import Test.QuickCheck

-- Integer safety
prop_integerBoundaryPreserved :: Int -> Property
prop_integerBoundaryPreserved n =
  n >= minSafeInt && n <= maxSafeInt ==>
    marshalInt (unmarshalInt n) === n
  where
    minSafeInt = -9007199254740991
    maxSafeInt = 9007199254740991

prop_integerOverflowDetected :: Property
prop_integerOverflowDetected =
  forAll (arbitrary `suchThat` (\n -> abs n > 9007199254740991)) $ \n ->
    isLeft (tryMarshalInt n)

-- NaN rejection
prop_nanRejected :: Property
prop_nanRejected =
  expectFailure (marshalFloat (0/0))  -- NaN should fail

-- Float preservation
prop_floatPreserved :: Double -> Property
prop_floatPreserved f =
  not (isNaN f) ==>
    marshalFloat (unmarshalFloat f) === f

-- List roundtrip
prop_listRoundtrip :: [Int] -> Property
prop_listRoundtrip xs =
  all (\x -> abs x <= 9007199254740991) xs ==>
    fromCanopyList (toCanopyList xs) === xs

-- Record field ordering
prop_recordFieldsOrdered :: [(String, Int)] -> Property
prop_recordFieldsOrdered fields =
  let sorted = List.sortOn fst fields
      record = makeRecord fields
  in recordFields record === sorted
```

## 4.2 Integer Overflow Tests

```haskell
-- | Integer boundary tests
spec_integerBoundaries :: Spec
spec_integerBoundaries = describe "Integer boundaries" $ do

  it "accepts MAX_SAFE_INTEGER" $
    marshalInt 9007199254740991 `shouldBe` Right 9007199254740991

  it "accepts MIN_SAFE_INTEGER" $
    marshalInt (-9007199254740991) `shouldBe` Right (-9007199254740991)

  it "rejects MAX_SAFE_INTEGER + 1" $
    marshalInt 9007199254740992 `shouldSatisfy` isLeft

  it "rejects MIN_SAFE_INTEGER - 1" $
    marshalInt (-9007199254740992) `shouldSatisfy` isLeft

  it "handles zero correctly" $
    marshalInt 0 `shouldBe` Right 0

  it "handles negative zero" $
    marshalFloat (-0.0) `shouldBe` Right (-0.0)
```

## 4.3 NaN Tests

```haskell
spec_nanHandling :: Spec
spec_nanHandling = describe "NaN handling" $ do

  it "rejects NaN in strict mode" $
    validateFloat NaN `shouldSatisfy` isLeft

  it "rejects NaN from division" $
    validateFloat (0.0 / 0.0) `shouldSatisfy` isLeft

  it "accepts Infinity" $
    validateFloat (1.0 / 0.0) `shouldBe` Right Infinity

  it "accepts negative Infinity" $
    validateFloat (-1.0 / 0.0) `shouldBe` Right (-Infinity)
```

## 4.4 Callback Re-entry Tests

```haskell
spec_callbackReentry :: Spec
spec_callbackReentry = describe "Callback re-entry" $ do

  it "prevents concurrent modification" $ do
    ref <- newIORef []
    let callback = \x -> do
          modifyIORef ref (x:)
          threadDelay 1000
          readIORef ref

    -- Simulate re-entry
    result <- runWithReentryProtection callback [1, 2, 3]
    result `shouldSatisfy` isLeft

  it "allows sequential calls" $ do
    ref <- newIORef []
    let callback x = modifyIORef ref (x:) >> readIORef ref

    result1 <- callback 1
    result2 <- callback 2
    result2 `shouldBe` [2, 1]
```

## 4.5 Capability Leakage Tests

```haskell
spec_capabilityLeakage :: Spec
spec_capabilityLeakage = describe "Capability leakage prevention" $ do

  it "cannot construct UserActivated directly" $
    -- This should be a compile error, not runtime
    shouldNotCompile "UserActivated ()"

  it "cannot extract capability from wrapper" $
    shouldNotCompile "case initialized of Initialized x -> UserActivated ()"

  it "capabilities don't survive serialization" $ do
    let cap = mockUserActivated  -- test helper
    encode cap `shouldBe` Nothing  -- Not serializable

  it "partial application doesn't strip capability" $
    shouldNotCompile $ unlines
      [ "stripCap : (UserActivated -> a) -> a"
      , "stripCap f = f ???"
      ]
```

## 4.6 Async Propagation Tests

```haskell
spec_asyncPropagation :: Spec
spec_asyncPropagation = describe "Async capability propagation" $ do

  it "capability flows through Task.andThen" $
    shouldCompile $ unlines
      [ "example : UserActivated -> Task Error Result"
      , "example cap ="
      , "    createContext cap"
      , "    |> Task.andThen useContext"
      ]

  it "capability required in continuation" $
    shouldNotCompile $ unlines
      [ "badExample : Task Error Result"
      , "badExample ="
      , "    Task.succeed ()"
      , "    |> Task.andThen (\\_ -> createContext ???)"
      ]
```

## 4.7 Determinism Test Harness

```haskell
spec_determinism :: Spec
spec_determinism = describe "Compilation determinism" $ do

  it "produces identical output across 100 compilations" $ do
    results <- replicateM 100 (compileProject "examples/audio-ffi")
    let hashes = map hashOutput results
    all (== head hashes) hashes `shouldBe` True

  it "produces identical output across GHC versions" $ pending
    -- Requires CI matrix

  it "produces identical output on different platforms" $ pending
    -- Requires CI matrix
```

## 4.8 Fuzzing Strategy

```haskell
-- | FFI fuzzing with type-aware generation
module Test.FFI.Fuzz where

import Hedgehog

-- Generate arbitrary FFI inputs
genFFIInput :: FFITypeRep -> Gen Value
genFFIInput = \case
  FFIPrimitive (PrimInt _) -> genSafeInt
  FFIPrimitive PrimFloat -> genSafeFloat
  FFIPrimitive PrimBool -> Gen.bool
  FFIPrimitive PrimString -> genUnicodeString
  FFIContainer ContainerList inner -> Gen.list (Range.linear 0 100) (genFFIInput inner)
  FFIContainer ContainerMaybe inner -> Gen.maybe (genFFIInput inner)
  FFIRecord fields -> genRecord fields
  FFIOpaque _ -> genOpaqueHandle
  _ -> Gen.discard

-- Generate edge cases
genEdgeCaseInt :: Gen Int
genEdgeCaseInt = Gen.element
  [ 0
  , 1
  , -1
  , maxSafeInt
  , minSafeInt
  , maxSafeInt + 1  -- Should fail validation
  , minSafeInt - 1  -- Should fail validation
  ]

-- Fuzz test: validation never crashes
prop_validationNeverCrashes :: Property
prop_validationNeverCrashes = property $ do
  typeRep <- forAll genFFITypeRep
  input <- forAll (genFFIInput typeRep)

  -- Should either succeed or return error, never crash
  let result = validate input typeRep
  assert (isRight result || isLeft result)

-- Fuzz test: roundtrip preserves value
prop_roundtripPreservesValue :: Property
prop_roundtripPreservesValue = property $ do
  typeRep <- forAll genFFITypeRep
  input <- forAll (genValidFFIInput typeRep)

  let marshalled = marshal input typeRep
      unmarshalled = unmarshal marshalled typeRep

  input === unmarshalled
```

## 4.9 Memory Leak Detection

```javascript
// memory-leak-test.js — Detect FFI memory leaks
const v8 = require('v8');
const vm = require('vm');

async function testCallbackRetention() {
  const initialHeap = v8.getHeapStatistics().used_heap_size;

  // Create many callbacks
  for (let i = 0; i < 10000; i++) {
    const largeData = new Array(1000).fill(i);
    registerCallback(() => largeData.reduce((a, b) => a + b));
  }

  // Force GC
  global.gc();
  await new Promise(r => setTimeout(r, 1000));
  global.gc();

  const finalHeap = v8.getHeapStatistics().used_heap_size;
  const growth = finalHeap - initialHeap;

  // Should not retain more than ~1MB
  if (growth > 1024 * 1024) {
    throw new Error(`Memory leak detected: ${growth} bytes retained`);
  }

  console.log('PASS: No callback memory leak');
}

async function testOpaqueRetention() {
  const initialHeap = v8.getHeapStatistics().used_heap_size;

  // Create and release opaque objects
  for (let i = 0; i < 1000; i++) {
    const ctx = await createAudioContext();
    await disposeAudioContext(ctx);
  }

  global.gc();
  await new Promise(r => setTimeout(r, 1000));
  global.gc();

  const finalHeap = v8.getHeapStatistics().used_heap_size;
  const growth = finalHeap - initialHeap;

  if (growth > 512 * 1024) {
    throw new Error(`Opaque object leak: ${growth} bytes retained`);
  }

  console.log('PASS: No opaque object memory leak');
}
```

## 4.10 Opaque Lifecycle Tests

```haskell
spec_opaqueLifecycle :: Spec
spec_opaqueLifecycle = describe "Opaque type lifecycle" $ do

  it "maintains identity across FFI boundary" $ do
    ctx <- createContext
    ctx' <- passThrough ctx
    identityOf ctx `shouldBe` identityOf ctx'

  it "allows explicit disposal" $ do
    ctx <- createContext
    dispose ctx
    useContext ctx `shouldThrow` anyException

  it "survives GC while referenced" $ do
    ctx <- createContext
    performGC
    useContext ctx `shouldReturn` ()  -- Should work

  it "is collected when unreferenced" $ do
    weak <- mkWeak <$> createContext
    performGC
    deRefWeak weak `shouldReturn` Nothing
```

---

# APPENDIX A — Migration Checklist

## Kernel Code Removal

- [ ] Remove `Canopy/Kernel.hs` Elm-derived patterns
- [ ] Replace kernel chunk format with new IR
- [ ] Update all kernel references in codebase
- [ ] Verify no "Elm" strings in output

## Type System Migration

- [ ] Delete `FFIType` data type
- [ ] Implement `FFI.IR` module
- [ ] Implement `FFI.Lower` module
- [ ] Update `Foreign/FFI.hs` to use IR
- [ ] Update `Canonicalize/Module.hs`

## Memory Model Implementation

- [ ] Implement opaque registry
- [ ] Add WeakRef callback tracking
- [ ] Add FinalizationRegistry cleanup
- [ ] Test memory leak scenarios

## Capability System Integration

- [ ] Delete `Type/Capability.hs`
- [ ] Rewrite `FFI/Capability.hs`
- [ ] Add capability constraints to `Type/Constraint.hs`
- [ ] Add capability solving to `Type/Solve.hs`
- [ ] Update error messages

## Runtime Implementation

- [ ] Write `canopy-ffi-runtime.js`
- [ ] Write `canopy-ffi-validators.js`
- [ ] Test in Node.js
- [ ] Test in Deno
- [ ] Test in Bun
- [ ] Test in browser
- [ ] Test in Web Worker

## Determinism Fixes

- [ ] Fix all `Map.toList` calls
- [ ] Fix all `Set.toList` calls
- [ ] Add determinism test harness
- [ ] Verify across GHC versions

## Documentation

- [ ] Update FFI guide
- [ ] Write migration guide
- [ ] Document all breaking changes
- [ ] Add examples for new patterns

---

# APPENDIX B — Breaking Changes

| Area | Old Behavior | New Behavior | Migration |
|------|--------------|--------------|-----------|
| Integer overflow | Silent corruption | Error in strict mode | Use `--ffi=legacy` for old behavior |
| NaN values | Passed through | Rejected in strict mode | Handle NaN explicitly |
| Capability types | Runtime values | Type-level phantoms | Update type signatures |
| Manual marshalling | Required | Generated helpers available | Use `CanopyMarshal.*` |
| Browser globals | Assumed available | Feature detected | No change needed |

---

# APPENDIX C — Performance Benchmarks

Expected overhead measurements (to be validated):

| Operation | Legacy Mode | Strict Mode | Debug Mode |
|-----------|-------------|-------------|------------|
| Primitive validation | 0 ns | <10 ns | ~100 ns |
| List (100 items) | 0 ns | ~1 μs | ~10 μs |
| Record (10 fields) | 0 ns | ~500 ns | ~5 μs |
| Callback wrap | 0 ns | ~100 ns | ~1 μs |
| Opaque lookup | 0 ns | ~50 ns | ~500 ns |

---

**END OF DOCUMENT**

This document represents the complete, production-ready FFI architecture for Canopy v3.0. All implementations must conform to this specification. No legacy artifacts are permitted in the final system.
