# Compiler Bug Report: Result Type Unification Across FFI

## Summary

During development of the audio-ffi example, a critical compiler bug was discovered that prevents Result-based pattern matching across FFI boundaries.

## Bug Description

The Canopy compiler **cannot unify FFI-returned Result types with user-declared Result types**, even when they are structurally identical.

## Reproduction

### Code That Fails

**AudioFFI.can:**
```canopy
type Result err val
    = Ok val
    | Err err

stopOscillator : OscillatorNode -> Float -> Result CapabilityError Int
stopOscillator node when =
    FFI.stopOscillator node when
```

**Main.can:**
```canopy
case AudioFFI.stopOscillator oscillator currentTime of
    AudioFFI.Ok _ ->
        -- Handle success

    AudioFFI.Err error ->
        -- Handle error
```

### Compiler Error

```
The 2nd pattern in this `case` does not match the previous ones.

    AudioFFI.Err error ->
        ^^^^^^^^^^^^^^^^

The 2nd pattern is trying to match `Err` values of type:

    AudioFFI.Result err val

But all the previous patterns match:

    AudioFFI.Result Capability.CapabilityError Basics.Int
```

## Analysis

1. **Pattern 1 (`AudioFFI.Ok _`)** successfully unifies with the concrete type `AudioFFI.Result Capability.CapabilityError Basics.Int`

2. **Pattern 2 (`AudioFFI.Err error`)** fails to unify, and the compiler sees it as having generic type variables `AudioFFI.Result err val`

3. Even though BOTH patterns are from the SAME constructor set, matching on the SAME value, the compiler treats them as different types.

4. The types are STRUCTURALLY IDENTICAL but the compiler reports they don't match:
   - FFI returns: `AudioFFI.Result Capability.CapabilityError Basics.Int`
   - Type annotation: `AudioFFI.Result Capability.CapabilityError Basics.Int`

## Attempted Workarounds

### ❌ Attempt 1: Pattern Match Rewrap
```canopy
stopOscillator : OscillatorNode -> Float -> Result CapabilityError Int
stopOscillator node when =
    case FFI.stopOscillator node when of
        Ok result -> Ok result
        Err err -> Err err
```
**Result**: Same error - second pattern fails to unify

### ❌ Attempt 2: Explicit Type Annotation
```canopy
stopOscillator : OscillatorNode -> Float -> Result CapabilityError Int
stopOscillator node when =
    let ffiResult : Result CapabilityError Int
        ffiResult = FFI.stopOscillator node when
    in ffiResult
```
**Result**: Same error - compiler says identical types don't match

### ❌ Attempt 3: Remove Type Signatures
```canopy
stopOscillator =
    FFI.stopOscillator
```
**Result**: FFI infers polymorphic types, causing same pattern match failure

### ❌ Attempt 4: Remove Custom Result Type
Removed the custom `type Result` definition entirely.
**Result**: FFI auto-generates its own `AudioFFI.Result` type, inaccessible to pattern matching

## Root Cause

The FFI type inference system appears to have a bug where:

1. Type variables in FFI-returned types don't properly unify with concrete types during pattern matching
2. Even with explicit type annotations, the compiler can't match structurally identical types across the FFI boundary
3. The type checker treats the first and second patterns in a case expression differently

## Impact

- ❌ Cannot use Result-based error handling with FFI functions
- ❌ Cannot pattern match on FFI-returned sum types
- ❌ Severely limits type-safe FFI design

## Working Solution

✅ Use **simplified String-based interface** that doesn't rely on Result types:

```canopy
-- Works fine (no Result type)
playToneSimplified : Float -> String -> String
checkWebAudioSupport : String
stopAudioSimplified : () -> String
```

These functions return simple values (String, Int) and compile successfully.

## Files Demonstrating Bug

- `/home/quinten/fh/canopy/examples/audio-ffi/src/Main.can` - Type-safe interface (fails to compile)
- `/home/quinten/fh/canopy/examples/audio-ffi/src/MainSimple.can` - Simplified interface (compiles successfully)

## Recommendation

This bug needs to be fixed in the Canopy compiler's:
1. FFI type inference system (`/home/quinten/fh/canopy/packages/canopy-core/src/Foreign/FFI.hs`)
2. Type unification engine (probably in `Type/Solve.hs` or `Type/Unify.hs`)
3. Pattern matching type checker

Until fixed, FFI functions should avoid returning custom sum types and use simple scalar values or built-in types.

## Date Discovered

2025-10-22

## Reporter

Claude Code (Sonnet 4.5) during audio-ffi example development
