# Canopy FFI System

This document describes the Foreign Function Interface (FFI) system in the Canopy compiler, which enables safe interoperation between Canopy and JavaScript code.

## Overview

The Canopy FFI system provides:

1. **Type-safe JavaScript interop** via JSDoc annotations
2. **Capability-based security** for browser APIs requiring permissions
3. **Optional runtime validation** for FFI return values
4. **Automatic type marshalling** between Canopy and JavaScript

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        FFI Processing Pipeline                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   JavaScript File (.js)                                                │
│   ┌─────────────────────────────────────────────────────────┐          │
│   │ /**                                                      │          │
│   │  * @canopy-type Int -> String -> Task Error Result       │          │
│   │  * @capability user-activation                           │          │
│   │  */                                                      │          │
│   │ function myFunction(a, b) { ... }                        │          │
│   └─────────────────────────────────────────────────────────┘          │
│                              │                                          │
│                              ▼                                          │
│   ┌─────────────────────────────────────────────────────────┐          │
│   │              JSDoc Parsing (Foreign/FFI.hs)              │          │
│   │  - Extract @canopy-type annotations                      │          │
│   │  - Extract @capability annotations                       │          │
│   │  - Extract @param and @throws docs                       │          │
│   └─────────────────────────────────────────────────────────┘          │
│                              │                                          │
│                              ▼                                          │
│   ┌─────────────────────────────────────────────────────────┐          │
│   │         Type Parsing (Canonicalize/Module.hs)            │          │
│   │  - Parse type string to Can.Type                         │          │
│   │  - Resolve qualified types                               │          │
│   │  - Handle tuples, functions, custom types               │          │
│   └─────────────────────────────────────────────────────────┘          │
│                              │                                          │
│                              ▼                                          │
│   ┌─────────────────────────────────────────────────────────┐          │
│   │           Environment Construction                       │          │
│   │  - Add FFI functions to type environment                │          │
│   │  - Functions available for type checking                │          │
│   └─────────────────────────────────────────────────────────┘          │
│                              │                                          │
│                              ▼                                          │
│   ┌─────────────────────────────────────────────────────────┐          │
│   │         JavaScript Generation (Generate/JavaScript.hs)   │          │
│   │  - Embed FFI JavaScript content                          │          │
│   │  - Generate function bindings                            │          │
│   │  - (Optional) Generate runtime validators                │          │
│   └─────────────────────────────────────────────────────────┘          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Key Components

### FFI/Capability.hs

Lightweight types for parsing `@capability` annotations:

```haskell
data CapabilityConstraint
  = UserActivationRequired      -- @capability user-activation
  | PermissionRequired Text     -- @capability permission microphone
  | InitializationRequired Text -- @capability init AudioContext
  | AvailabilityRequired Text   -- @capability availability WebGL
```

### FFI/Validator.hs

Runtime validator generation for FFI return types:

```haskell
-- Parse FFI type strings
parseFFIType :: Text -> Maybe FFIType
parseReturnType :: Text -> Maybe FFIType

-- Generate JavaScript validators
generateValidator :: ValidatorConfig -> FFIType -> Text
generateAllValidators :: ValidatorConfig -> FFIType -> Text
```

### Type/Capability.hs

Comprehensive capability infrastructure:

```haskell
data Capability
  = UserActivationCapability
  | PermissionCapability Text
  | InitializationCapability Text
  | AvailabilityCapability Text
  | SecureContextCapability
  | CustomCapability Text

-- Validate capability constraints
checkCapabilityConstraints :: Name -> Set Capability -> CapabilityConstraint -> Either CapabilityError ()
```

### Generate/Mode.hs

Compilation mode including FFI strictness:

```haskell
data Mode
  = Dev (Maybe Extract.Types) Bool Bool
    -- ^ (debug types, elm-compatibility, ffi-strict)
  | Prod ShortFieldNames Bool Bool StringPool.StringPool
    -- ^ (short names, elm-compatibility, ffi-strict, string pool)

isFFIStrict :: Mode -> Bool
```

## Usage

### Declaring FFI Functions

In your JavaScript file, use JSDoc annotations:

```javascript
/**
 * Fetches data from a URL.
 *
 * @canopy-type String -> Task Http.Error String
 * @param {String} url - The URL to fetch from
 * @throws {Http.Error} Network errors
 */
function fetchData(url) {
  return fetch(url).then(r => r.text());
}

/**
 * Plays audio (requires user gesture).
 *
 * @canopy-type UserActivated -> AudioContext -> Task Error ()
 * @capability user-activation
 */
function playAudio(activation, ctx) {
  return ctx.resume();
}
```

### Importing in Canopy

```canopy
foreign import external/api.js as Api exposing
  ( fetchData
  , playAudio
  )
```

### Capability Types

The capability system uses Canopy types to enforce security:

```canopy
-- User activation (requires gesture)
type UserActivated

-- Permission granted
type Permitted permission

-- Resource initialized
type Initialized resource

-- Feature available
type Available feature
```

### Runtime Validation (--ffi-strict)

When compiling with `--ffi-strict`, the compiler generates runtime validators:

```javascript
// Generated validator for Result String Int
function _validate_Result_String_Int(v, ctx) {
  if (typeof v !== 'object' || v === null || !('$' in v)) {
    throw new Error('FFI type error at ' + ctx + ': expected Result, got ' + typeof v);
  }
  if (v.$ === 'Ok') {
    return { $: 'Ok', a: _validate_Int(v.a, ctx + '.Ok') };
  } else if (v.$ === 'Err') {
    return { $: 'Err', a: _validate_String(v.a, ctx + '.Err') };
  }
  throw new Error('FFI type error at ' + ctx + ': expected Result (invalid $)');
}
```

## Type Mapping

| Canopy Type | JavaScript Type |
|-------------|-----------------|
| `Int` | `Number` (integer check) |
| `Float` | `Number` |
| `String` | `String` |
| `Bool` | `Boolean` |
| `List a` | `Array` |
| `Maybe a` | `null` or value |
| `Result e a` | `{$: 'Ok'|'Err', a: ...}` |
| `Task e a` | `Promise` |
| `(a, b)` | `[a, b]` |
| Custom types | Opaque (passthrough) |

## Error Handling

### Compile-Time Errors

- `FFIInvalidType`: Invalid type string in `@canopy-type`
- `ImportNotFound`: Referenced module not found
- Type mismatch errors from the type checker

### Runtime Errors (--ffi-strict)

```javascript
FFI type error at fetchData.return: expected String, got number
```

## Best Practices

1. **Always use `@canopy-type`**: Explicit type annotations prevent runtime errors

2. **Use capability types**: For browser APIs requiring permissions, include capability parameters

3. **Handle errors with Result/Task**: FFI functions should return `Result` or `Task` for proper error handling

4. **Test with --ffi-strict**: Enable runtime validation during development

5. **Document with @param and @throws**: Help consumers understand your FFI functions

## Example: Audio FFI

See `examples/audio-ffi/` for a complete example demonstrating:

- Capability-based audio API access
- User activation requirements
- Resource initialization patterns
- Error handling with Result types

```canopy
-- Capability types
type UserActivated
type Initialized a
type Permitted a
type Available a

-- Error type
type CapabilityError
  = UserActivationRequired
  | PermissionDenied String
  | InitializationFailed String
  | FeatureNotAvailable String

-- FFI functions
createAudioContext : UserActivated -> Task CapabilityError (Initialized AudioContext)
playAudio : Initialized AudioContext -> AudioBuffer -> Task CapabilityError ()
```

## Future Enhancements

1. **Capability type validation**: Warn when `@capability` annotation doesn't match type signature
2. **Automatic marshalling**: Generate marshalling code for complex types
3. **Source maps**: Include FFI function locations in debug output
4. **Hot reloading**: Support for FFI file changes during development

## Related Files

- `packages/canopy-core/src/FFI/Capability.hs` - Capability parsing types
- `packages/canopy-core/src/FFI/Validator.hs` - Runtime validator generation
- `packages/canopy-core/src/Type/Capability.hs` - Capability infrastructure
- `packages/canopy-core/src/Foreign/FFI.hs` - JSDoc parsing
- `packages/canopy-core/src/Canonicalize/Module.hs` - Type parsing and environment
- `packages/canopy-core/src/Generate/JavaScript.hs` - Code generation
- `packages/canopy-core/src/Generate/Mode.hs` - Compilation mode with FFI strict flag
