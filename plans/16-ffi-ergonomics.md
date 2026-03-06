# Plan 16: FFI Ergonomics — Eliminate Boilerplate with Compiler-Understood Annotations

## Priority: CRITICAL
## Effort: Large (5-10 days)
## Risk: Medium — touches parser, canonicalization, and codegen

## Problem

Canopy's FFI requires **triple declaration** for every function binding, making large API surfaces painful. The `AudioFFI.can` example has 1,266 lines for 225 functions — most of it pure boilerplate.

### Pain Point 1: Wrapper Function Boilerplate

Every FFI function requires an identical delegation line:

```canopy
-- 225 lines like this in AudioFFI.can:
createAudioContext = FFI.createAudioContext
getCurrentTime = FFI.getCurrentTime
getSampleRate = FFI.getSampleRate
-- ... 222 more
```

Zero value. Zero type safety. Pure mechanical noise.

### Pain Point 2: Type Signature Duplication

The type appears in BOTH the `.can` file and the `.js` JSDoc:

```canopy
-- In Math.can:
factorial : Int -> Int
factorial = FFI.factorial
```

```javascript
// In math.js:
/** @canopy-type Int -> Int */
function factorial(n) { ... }
```

Same type, written twice, manually kept in sync.

### Pain Point 3: JS Wrapper Functions for Methods/Properties/Constructors

Binding to `element.addEventListener(...)` requires a JS wrapper just to adapt calling convention:

```javascript
// external/dom.js — one wrapper per method
/** @canopy-type DOMElement -> String -> (Event -> ()) -> () */
function addEventListener(element, eventType, handler) {
    element.addEventListener(eventType, handler);  // Just forwarding!
}

/** @canopy-type AudioContext -> Float */
function getCurrentTime(ctx) {
    return ctx.currentTime;  // Just a property read!
}

/** @canopy-type () -> AudioContext */
function createAudioContext() {
    return new AudioContext();  // Just a constructor call!
}
```

The `AudioFFI` JS file has 40+ getter wrappers and 32+ constructor wrappers — all one-liners.

### Pain Point 4: Manual Opaque Type Declarations

Users must declare opaque types they never construct:

```canopy
-- 49 lines like this in AudioFFI.can:
type AudioContext = AudioContext
type OscillatorNode = OscillatorNode
type GainNode = GainNode
-- ... 46 more
```

### Evidence

**AudioFFI.can**: 1,266 lines → ~126 lines with these improvements (90% reduction)
**math-ffi external/math.js**: ~50% is wrapper code that `@get`/`@new` would eliminate

## Design

Inspired by **ReScript** (`@send`, `@get`, `@set`, `@new`) and **Gleam** (`@external`).

### Feature 1: Auto-Binding Generation (eliminates Pain Point 1)

When a module has `foreign import javascript "file.js" as FFI`, all functions declared in the JS file with `@canopy-type` annotations are **automatically available** in the Canopy module without explicit `functionName = FFI.functionName` wrapper lines.

The `.can` file only needs to list what it **exposes**:

```canopy
module Math exposing (factorial, gcd, sqrt, power)

foreign import javascript "external/math.js" as FFI

-- No wrapper lines needed. Functions are available directly from the JSDoc annotations.
-- Type signatures from @canopy-type are imported automatically.
-- Users can add explicit type annotations to override or restrict types:

factorial : Int -> Int  -- Optional: narrows the @canopy-type if needed
```

**Implementation**: During canonicalization, when processing a `foreign import`:
1. Parse the JS file (already done in `Canonicalize/Module/FFI.hs`)
2. For each `@canopy-type` annotated function, create a `Can.Def` binding automatically
3. If user provides explicit type annotation, use that (override). If not, use the JSDoc type.
4. Add to module exports if listed in `exposing`

### Feature 2: `@method`, `@get`, `@set`, `@new` Annotations (eliminates Pain Point 3)

New JSDoc annotations the compiler understands to eliminate JS wrapper functions:

```javascript
// external/dom.js — NO wrapper functions needed

/**
 * @canopy-type DOMElement -> String -> (Event -> ()) -> ()
 * @canopy-bind method addEventListener
 */

/**
 * @canopy-type AudioContext -> Float
 * @canopy-bind get currentTime
 */

/**
 * @canopy-type AudioContext -> Float -> ()
 * @canopy-bind set currentTime
 */

/**
 * @canopy-type () -> AudioContext
 * @canopy-bind new AudioContext
 */

/**
 * @canopy-type { sampleRate : Float } -> AudioContext
 * @canopy-bind new AudioContext
 */
```

The compiler generates the correct JS code directly:

| Annotation | Canopy call | Generated JS |
|---|---|---|
| `@canopy-bind method addEventListener` | `addEventListener el "click" handler` | `el.addEventListener("click", handler)` |
| `@canopy-bind get currentTime` | `getCurrentTime ctx` | `ctx.currentTime` |
| `@canopy-bind set currentTime` | `setCurrentTime ctx 1.5` | `ctx.currentTime = 1.5` |
| `@canopy-bind new AudioContext` | `createAudioContext ()` | `new AudioContext()` |

**No JS function body needed** — the annotation IS the implementation.

### Feature 3: Auto Opaque Type Inference (eliminates Pain Point 4)

When a `@canopy-type` annotation references a type name not defined in Canopy (e.g., `AudioContext`, `DOMElement`), the compiler automatically creates an opaque type for it.

Users no longer need to write:
```canopy
type AudioContext = AudioContext  -- GONE
```

The compiler infers: "AudioContext appears in FFI types but has no Canopy definition → create opaque type."

### Feature 4: `@canopy-name` for Renaming

Allow the JS function to have a different name than the Canopy binding:

```javascript
/**
 * @canopy-type OscillatorNode -> Float -> Float -> ()
 * @canopy-name setOscillatorFrequency
 * @name setFrequency
 */
function setFrequency(node, value, time) { ... }
```

Canopy sees `setOscillatorFrequency`. JS has `setFrequency`. No wrapper needed.

## Implementation Plan

### Step 1: Extend JSDoc Parsing for New Annotations

**File**: `packages/canopy-core/src/Foreign/FFI.hs`

Add extraction for new annotations:
- `@canopy-bind method <name>` / `@canopy-bind get <name>` / `@canopy-bind set <name>` / `@canopy-bind new <name>`
- `@canopy-name <canopyName>`

Add to `JSDocFunction`:
```haskell
data BindingMode
  = FunctionCall          -- default: call the JS function
  | MethodCall !Text      -- @canopy-bind method <name>
  | PropertyGet !Text     -- @canopy-bind get <name>
  | PropertySet !Text     -- @canopy-bind set <name>
  | ConstructorCall !Text -- @canopy-bind new <name>
  deriving (Eq, Show)
```

### Step 2: Extend FFI Types

**File**: `packages/canopy-core/src/FFI/Types.hs`

Add `BindingMode` to `FFIBinding`:
```haskell
data FFIBinding = FFIBinding
  { _bindingFuncName :: !FFIFuncName
  , _bindingTypeAnnotation :: !FFITypeAnnotation
  , _bindingCapabilities :: ![CapabilityName]
  , _bindingMode :: !BindingMode         -- NEW
  , _bindingCanopyName :: !(Maybe Text)  -- NEW: @canopy-name
  }
```

### Step 3: Auto-Binding Generation in Canonicalization

**File**: `packages/canopy-core/src/Canonicalize/Module/FFI.hs`

In `addFFIToEnvPure`, for each JSDoc function:
1. Create a `Can.Def` that represents the binding
2. Use `@canopy-name` if present, otherwise JS function name
3. Check if user provided an explicit type annotation (override) or use `@canopy-type`
4. Add to the module's value bindings

### Step 4: Code Generation for Binding Modes

**File**: `packages/canopy-core/src/Generate/JavaScript/FFI.hs`

For each binding mode, generate different JS:

```haskell
generateFFICall :: BindingMode -> [JS.Expr] -> JS.Expr
generateFFICall FunctionCall args =
  -- existing: functionName(arg1, arg2, ...)
generateFFICall (MethodCall methodName) (obj : args) =
  -- obj.methodName(arg1, arg2, ...)
  JS.MethodCall obj methodName args
generateFFICall (PropertyGet propName) [obj] =
  -- obj.propName
  JS.Access obj propName
generateFFICall (PropertySet propName) [obj, val] =
  -- obj.propName = val
  JS.Assign (JS.Access obj propName) val
generateFFICall (ConstructorCall className) args =
  -- new ClassName(arg1, arg2, ...)
  JS.New className args
```

### Step 5: Auto Opaque Type Inference

**File**: `packages/canopy-core/src/Canonicalize/Module/FFI.hs`

During FFI processing:
1. Collect all type names referenced in `@canopy-type` annotations
2. Check which ones have no definition in the current module or imports
3. For undefined names, create opaque type definitions automatically
4. Add to module's type environment

### Step 6: Update Static Analysis

**File**: `packages/canopy-core/src/FFI/StaticAnalysis.hs`

For `@canopy-bind` annotated functions:
- `method`: Verify first param type is consistent across methods on same type
- `get`/`set`: Verify get and set types are consistent for same property
- `new`: Verify return type matches the constructor name

### Step 7: Tests

- Auto-binding: FFI functions accessible without explicit wrappers
- `@canopy-bind method`: Correct JS method call codegen
- `@canopy-bind get`/`set`: Correct property access codegen
- `@canopy-bind new`: Correct constructor call codegen
- `@canopy-name`: Renaming works correctly
- Auto opaque types: Unknown types get opaque definitions
- Override: Explicit type annotations take precedence over `@canopy-type`
- Error messages: Clear errors when annotation is malformed

## Before/After: AudioFFI.can

**Before (1,266 lines):**
```canopy
module AudioFFI exposing (...)
foreign import javascript "external/audio.js" as FFI

type AudioContext = AudioContext
type OscillatorNode = OscillatorNode
type GainNode = GainNode
-- ... 46 more opaque types

createAudioContext : UserActivated -> Result CapabilityError (Initialized AudioContext)
createAudioContext = FFI.createAudioContext

getCurrentTime : Initialized AudioContext -> Float
getCurrentTime = FFI.getCurrentTime

getSampleRate : AudioContext -> Float
getSampleRate = FFI.getSampleRate
-- ... 222 more wrapper lines
```

**After (~80 lines):**
```canopy
module AudioFFI exposing (...)
foreign import javascript "external/audio.js" as FFI

-- Opaque types auto-inferred from @canopy-type annotations.
-- All 225 functions auto-bound from JSDoc annotations.
-- Only need explicit annotations for overrides:

createAudioContext : UserActivated -> Result CapabilityError (Initialized AudioContext)
-- Narrows the FFI type to require capability token
```

**JS file (external/audio.js) also shrinks:**
```javascript
// Before: wrapper function
/** @canopy-type AudioContext -> Float */
function getCurrentTime(ctx) { return ctx.currentTime; }

// After: annotation only, no function body
/** @canopy-type AudioContext -> Float
    @canopy-bind get currentTime */
```

## Dependencies
- None (self-contained FFI improvement)

## Risks
- Auto-binding generation changes module semantics (opt-in per module to reduce risk)
- `@canopy-bind` annotations add complexity to JSDoc parsing
- Auto opaque types could conflict with intentional type definitions

## Mitigation
- Feature 1 (auto-binding) can be behind a module-level opt-in: `foreign import javascript "file.js" as FFI auto`
- Each feature can be shipped independently — they don't depend on each other
- Extensive error messages when annotations conflict with user definitions
