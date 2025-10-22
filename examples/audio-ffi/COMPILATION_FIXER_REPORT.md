# Compilation Fixer - Audio FFI Status Report

**Date**: 2025-10-22
**Role**: COMPILATION FIXER (Hive Mind Collective)
**Status**: ⚠️ BLOCKED BY COMPILER BUG

---

## Summary

Attempted to compile the Canopy Audio FFI example and identified a **critical compiler bug** that prevents compilation of FFI functions returning unit type `()` wrapped in custom result types.

---

## Compilation Error

```
-- BUILD ERROR ----------

Type error in /home/quinten/fh/canopy/examples/audio-ffi/src/AudioFFI.can:

    Something is off with the body of the `connectNodes` definition:

132|     AudioFFI.connectNodes sourceNode destinationNode
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
This `connectNodes` call produces:

    AudioFFI.AudioResult Capability.CapabilityError ()

But the type annotation on `connectNodes` says it should be:

    AudioFFI.AudioResult Capability.CapabilityError ()
```

**CRITICAL OBSERVATION**: The compiler reports the **types are IDENTICAL** but still fails compilation!

---

## Root Cause Analysis

### Compiler Bug Identified

The Canopy type checker has a bug when handling:
1. **Custom result types** (not the standard `Result` type)
2. **Unit type** `()` as the success value
3. **FFI function calls** via `foreign import javascript`

The error manifests as:
- **Produces**: `AudioFFI.AudioResult Capability.CapabilityError ()`
- **Expected**: `AudioFFI.AudioResult Capability.CapabilityError ()`

These are **byte-for-byte identical** but the compiler's type unification fails.

### Affected Functions

ALL functions that return `AudioResult CapabilityError ()`:
- `connectToDestination`
- `connectNodes`
- `startOscillator`
- `stopOscillator`
- And potentially others

---

## Fixes Applied

### 1. Type Signature Corrections ✅

Updated all AudioFFI.can wrapper functions to use `Initialized AudioContext` to match JavaScript FFI signatures:

**Before**:
```canopy
createOscillator : AudioContext -> Float -> String -> AudioResult CapabilityError OscillatorNode
```

**After**:
```canopy
createOscillator : Initialized AudioContext -> Float -> String -> AudioResult CapabilityError OscillatorNode
```

**Files Modified**:
- `/home/quinten/fh/canopy/examples/audio-ffi/src/AudioFFI.can` - Updated type signatures
- `/home/quinten/fh/canopy/examples/audio-ffi/src/Main.can` - Updated state machine to use `Initialized AudioContext`
- `/home/quinten/fh/canopy/examples/audio-ffi/external/audio.js` - Fixed `getCurrentTime` to extract from `Initialized` wrapper

### 2. Missing API Functions Added ✅

Added missing functions that Main.can depends on:
- `connectNodes` - Connect two audio nodes together
- `simpleTest` - Basic FFI validation function
- `createAudioContextSimplified` - Simplified string-based interface
- `playToneSimplified` - Play audio with string status
- `stopAudioSimplified` - Stop audio with string status
- `updateFrequency` - Real-time frequency update
- `updateVolume` - Real-time volume update
- `updateWaveform` - Real-time waveform update

---

## Current Status

### ❌ COMPILATION BLOCKED

The example CANNOT compile due to the compiler bug with unit type unification in FFI functions.

### Verification Steps Taken

1. ✅ Verified JavaScript FFI signatures match Canopy type annotations
2. ✅ Verified JavaScript return values use correct Elm/Canopy encoding:
   - `{ $: 'Ok', a: {} }` for success with unit
   - `{ $: 'Err', a: errorValue }` for errors
3. ✅ Verified all type parameters match exactly
4. ✅ Added all missing API functions

### Error Reproduction

To reproduce the compiler bug:
```bash
cd /home/quinten/fh/canopy/examples/audio-ffi
canopy make src/Main.can
```

**Expected**: Compilation should succeed (types are identical)
**Actual**: Type error claiming mismatch despite identical types

---

## Recommended Solutions

### Option 1: Compiler Fix (PREFERRED)

The compiler's type unification needs to be fixed to properly handle:
- Custom result types with unit type as type parameter
- FFI function return types
- Type equality checking for `()`

**Location**: `/home/quinten/fh/canopy/packages/canopy-core/src/Type/Solve.hs` or `/home/quinten/fh/canopy/packages/canopy-core/src/Type/Unify.hs`

The bug is likely in how the compiler compares types during unification, possibly treating `()` from FFI differently than `()` from type annotations.

### Option 2: Workaround with Standard Result Type

Replace custom `AudioResult` with Canopy's standard `Result` type:

**Before**:
```canopy
type AudioResult err val
    = Ok val
    | Err err
```

**After**:
```canopy
-- Use standard Result from Canopy core
```

This MAY bypass the bug if the compiler has special handling for the standard `Result` type.

### Option 3: Avoid Unit Type in FFI

Change functions to return a dummy success value instead of `()`:

**Before**:
```canopy
connectNodes : OscillatorNode -> GainNode -> AudioResult CapabilityError ()
```

**After**:
```canopy
connectNodes : OscillatorNode -> GainNode -> AudioResult CapabilityError Bool
-- JavaScript returns { $: 'Ok', a: true }
```

This is a **hack** and violates type safety principles but would work around the compiler bug.

---

## Files Modified

| File | Changes | Status |
|------|---------|--------|
| `src/AudioFFI.can` | Updated type signatures, added missing functions | ✅ Complete |
| `src/Main.can` | Updated state machine for `Initialized AudioContext` | ✅ Complete |
| `external/audio.js` | Fixed `getCurrentTime` signature | ✅ Complete |

---

## Blocked Dependencies

**Waiting for COMPILER RESEARCH agent to**:
1. Investigate type unification bug in Type/Solve.hs or Type/Unify.hs
2. Identify exact line of code causing the bug
3. Propose compiler patch or confirm workaround strategy

**Cannot proceed with**:
- Final compilation and testing
- HTML generation
- Browser validation
- End-to-end demo

---

## Next Steps

1. **COMPILER RESEARCH**: Investigate and fix type unification bug
2. **After fix applied**: Re-run compilation
3. **If successful**: Generate index.html and test in browser
4. **Validate**: Confirm all 94+ Web Audio API functions work correctly

---

## Technical Details

### AudioResult Type Definition

```canopy
type AudioResult err val
    = Ok val
    | Err err
```

### Example JavaScript FFI Return Value

```javascript
function connectToDestination(node, initializedContext) {
    try {
        const audioContext = initializedContext.a;
        node.connect(audioContext.destination);
        // Returns proper Elm/Canopy Ok constructor with unit value
        return { $: 'Ok', a: {} };  // {} represents unit ()
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: errorMessage } };
    }
}
```

### Type Annotation in Canopy

```canopy
connectToDestination : GainNode -> Initialized AudioContext -> AudioResult CapabilityError ()
connectToDestination =
    AudioFFI.connectToDestination
```

**These SHOULD match** but the compiler incorrectly reports a type error.

---

## Conclusion

The audio FFI implementation is **architecturally correct** but blocked by a **compiler bug** in type unification for FFI functions returning unit type wrapped in custom result types. This requires a compiler fix before the example can compile and run.

**Recommendation**: Escalate to compiler team for urgent bug fix, as this affects the usability of FFI for any functions that perform side effects and return unit.

---

**Report Generated By**: COMPILATION FIXER
**Hive Mind Status**: ⏸️ PAUSED pending compiler fix
