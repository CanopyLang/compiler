# Async FFI Quick Reference - TL;DR

**Status**: ✅ **READY TO IMPLEMENT** - Compiler already supports async FFI!

---

## Key Discovery

**The Canopy compiler ALREADY HAS COMPLETE async FFI support through the Task type.**

No compiler modifications needed. Just copy the `decodeAudioData` pattern.

---

## The Working Pattern (Copy This!)

```javascript
/**
 * Function description
 * @name functionName
 * @canopy-type Param1 -> Param2 -> Task Capability.CapabilityError ResultType
 */
function functionName(param1, param2) {
    return nativeAsyncOperation(param1, param2)
        .then(result => ({ $: 'Ok', a: result }))
        .catch(error => ({
            $: 'Err',
            a: { $: 'ErrorConstructor', a: 'Error: ' + error.message }
        }));
}
```

**Reference Implementation**: `/home/quinten/fh/canopy/examples/audio-ffi/external/audio.js` lines 129-143

---

## What You Need to Implement (3 functions)

### 1. addAudioWorkletModule (30 min) 🔴 CRITICAL
```javascript
/**
 * @name addAudioWorkletModule
 * @canopy-type Initialized AudioContext -> String -> Task Capability.CapabilityError ()
 */
function addAudioWorkletModule(ctx, url) {
    return ctx.a.audioWorklet.addModule(url)
        .then(() => ({ $: 'Ok', a: { } }))
        .catch(error => ({ $: 'Err', a: mapWorkletError(error) }));
}
```

### 2. createAudioWorkletNode (20 min) 🔴 CRITICAL
```javascript
/**
 * @name createAudioWorkletNode
 * @canopy-type Initialized AudioContext -> String -> Result Capability.CapabilityError AudioWorkletNode
 */
function createAudioWorkletNode(ctx, processorName) {
    try {
        const node = new AudioWorkletNode(ctx.a, processorName);
        return { $: 'Ok', a: node };
    } catch (e) {
        return { $: 'Err', a: mapWorkletError(e) };
    }
}
```

### 3. startOfflineRendering (20 min) 🔴 CRITICAL
```javascript
/**
 * @name startOfflineRendering
 * @canopy-type OfflineAudioContext -> Task Capability.CapabilityError AudioBuffer
 */
function startOfflineRendering(offlineCtx) {
    return offlineCtx.startRendering()
        .then(buffer => ({ $: 'Ok', a: buffer }))
        .catch(error => ({ $: 'Err', a: mapRenderError(error) }));
}
```

---

## Error Mapping Helpers

```javascript
function mapWorkletError(error) {
    if (error.name === 'AbortError') {
        return { $: 'AbortError', a: 'Script load failed: ' + error.message };
    } else if (error.name === 'SyntaxError') {
        return { $: 'SyntaxError', a: 'Invalid URL: ' + error.message };
    } else if (error.name === 'SecurityError') {
        return { $: 'SecurityError', a: 'CORS violation: ' + error.message };
    } else {
        return { $: 'InitializationRequired', a: 'Unknown: ' + error.message };
    }
}

function mapRenderError(error) {
    if (error.name === 'InvalidStateError') {
        return { $: 'InvalidStateError', a: 'Already rendering: ' + error.message };
    } else if (error.name === 'QuotaExceededError') {
        return { $: 'QuotaExceededError', a: 'Memory exceeded: ' + error.message };
    } else {
        return { $: 'RenderError', a: 'Rendering failed: ' + error.message };
    }
}
```

---

## Checklist

- [ ] Copy `decodeAudioData` pattern from audio.js
- [ ] Implement `addAudioWorkletModule` (30 min)
- [ ] Implement `createAudioWorkletNode` (20 min)
- [ ] Implement `startOfflineRendering` (20 min)
- [ ] Add error mapping functions
- [ ] Test with real AudioWorklet processor file
- [ ] Verify ADT format (Ok/Err with $ and a fields)

**Total Time**: ~1.5 hours

**Result**: >90% Web Audio API coverage ✅

---

## Critical Rules

1. ✅ **ALWAYS return the Promise** (don't await it)
2. ✅ **Use `.then()` and `.catch()`** (not async/await)
3. ✅ **Wrap in ADT format**: `{ $: 'Ok', a: value }` and `{ $: 'Err', a: error }`
4. ✅ **Unit type as empty object**: `{ }` for void returns
5. ✅ **Map JavaScript errors** to Capability.CapabilityError constructors

---

## Full Documentation

- **Complete Guide**: `/home/quinten/fh/canopy/.hive-mind/research/async-ffi-implementation-guide.md`
- **Functions List**: `/home/quinten/fh/canopy/.hive-mind/research/async-ffi-functions-list.md`
- **Working Example**: `/home/quinten/fh/canopy/examples/audio-ffi/external/audio.js`

---

## Web Audio API Coverage After Implementation

- **Before**: ~85% (missing AudioWorklet, offline rendering)
- **After**: >90% (complete core API coverage) ✅

---

*Research by: Researcher agent*
*For: Coder agent*
*Date: 2025-10-27*
*Hive: swarm-1761562617410-wxghlazbw*
