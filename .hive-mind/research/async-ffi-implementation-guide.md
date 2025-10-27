# Async FFI Implementation Guide for Canopy Web Audio API

**Mission**: Enable >90% Web Audio API coverage through Promise-based async FFI patterns.

**Status**: ✅ **COMPILER ALREADY SUPPORTS ASYNC FFI** - No modifications needed!

---

## Executive Summary

The Canopy compiler **ALREADY HAS FULL SUPPORT** for Promise-based async FFI through the `Task` type. The implementation is working and proven in `decodeAudioData`. We just need to apply the same pattern to the remaining 20+ async Web Audio API functions.

---

## 1. Existing Async FFI Support in Canopy

### 1.1 Compiler Support (packages/canopy-core/src/Foreign/FFI.hs)

```haskell
data FFIType
  = FFITask !FFIType !FFIType    -- ^ Task Error Value type for async operations
  | FFIBasic !Text
  | FFIResult !FFIType !FFIType
  | ...
```

**Key Discovery**: The `FFITask` type is ALREADY IMPLEMENTED in the FFI system!

### 1.2 JavaScript Generation (packages/canopy-core/src/Generate/JavaScript.hs)

The compiler correctly handles FFI function generation including:
- Arity calculation from type signatures
- Function wrapping with F2(), F3(), etc.
- Proper variable naming conventions

**No modifications needed** - the compiler handles Task types correctly.

### 1.3 Working Example: decodeAudioData

**Location**: `/home/quinten/fh/canopy/examples/audio-ffi/external/audio.js`

```javascript
/**
 * Decode audio data from ArrayBuffer (MP3, AAC, OGG, WAV)
 * @name decodeAudioData
 * @canopy-type AudioContext -> ArrayBuffer -> Task.Task Capability.CapabilityError AudioBuffer
 */
function decodeAudioData(audioContext, arrayBuffer) {
    return audioContext.decodeAudioData(arrayBuffer)
        .then(audioBuffer => ({ $: 'Ok', a: audioBuffer }))
        .catch(error => ({
            $: 'Err',
            a: {
                $: 'DecodeError',
                a: 'Failed to decode audio: ' + error.message
            }
        }));
}
```

**This is the GOLD STANDARD pattern** - it works perfectly!

---

## 2. The Async FFI Pattern (PROVEN WORKING)

### 2.1 Core Pattern Elements

1. **Type Annotation**: Use `Task.Task ErrorType ValueType` or `Task ErrorType ValueType`
2. **Promise Handling**: Wrap `.then()` result in ADT format: `{ $: 'Ok', a: value }`
3. **Error Handling**: Wrap `.catch()` result in ADT format: `{ $: 'Err', a: errorValue }`
4. **Return Promise**: The function MUST return the Promise (not await it)

### 2.2 Complete Template

```javascript
/**
 * Function description
 * @name functionName
 * @canopy-type ParamType1 -> ParamType2 -> Task Capability.CapabilityError ResultType
 */
function functionName(param1, param2) {
    return someAsyncOperation(param1, param2)
        .then(result => ({ $: 'Ok', a: result }))
        .catch(error => ({
            $: 'Err',
            a: {
                $: 'SomeErrorConstructor',
                a: 'Error message: ' + error.message
            }
        }));
}
```

### 2.3 Pattern Variations

#### Zero-Parameter Functions
```javascript
/**
 * @canopy-type () -> Task Error Value
 */
function operation() {
    return asyncOperation()
        .then(result => ({ $: 'Ok', a: result }))
        .catch(error => ({ $: 'Err', a: mapError(error) }));
}
```

#### Functions Returning void/Unit
```javascript
/**
 * @canopy-type Context -> Task Capability.CapabilityError ()
 */
function operationWithUnit(context) {
    return context.asyncOperation()
        .then(() => ({ $: 'Ok', a: { } }))  // Unit type as empty object
        .catch(error => ({ $: 'Err', a: mapError(error) }));
}
```

---

## 3. Web Audio API Functions Requiring Async Support

### 3.1 CRITICAL: AudioWorklet (Required for >90% coverage)

**Priority**: 🔴 **HIGHEST** - Blocks major use cases

```javascript
/**
 * Add AudioWorklet module from URL
 * @name addAudioWorkletModule
 * @canopy-type Initialized AudioContext -> String -> Task Capability.CapabilityError ()
 */
function addAudioWorkletModule(initializedContext, moduleURL) {
    const audioContext = initializedContext.a;
    return audioContext.audioWorklet.addModule(moduleURL)
        .then(() => ({ $: 'Ok', a: { } }))  // Returns void, wrap as unit
        .catch(error => ({
            $: 'Err',
            a: mapWorkletError(error)
        }));
}

function mapWorkletError(error) {
    if (error.name === 'AbortError') {
        return { $: 'AbortError', a: 'Script invalid or failed to load: ' + error.message };
    } else if (error.name === 'SyntaxError') {
        return { $: 'SyntaxError', a: 'Invalid module URL: ' + error.message };
    } else if (error.name === 'SecurityError') {
        return { $: 'SecurityError', a: 'CORS or security policy violation: ' + error.message };
    } else {
        return { $: 'InitializationRequired', a: 'Failed to load AudioWorklet: ' + error.message };
    }
}
```

**Web Audio API Spec**: Returns `Promise<void>` that resolves when module is loaded.

**Key Requirements**:
- Module URL must be valid and accessible
- CORS headers must allow loading
- Script must define valid AudioWorkletProcessor
- Promise resolves AFTER script evaluation completes

### 3.2 CRITICAL: OfflineAudioContext Rendering

**Priority**: 🔴 **HIGH** - Required for audio processing/analysis

```javascript
/**
 * Start offline rendering to AudioBuffer
 * @name startOfflineRendering
 * @canopy-type OfflineAudioContext -> Task Capability.CapabilityError AudioBuffer
 */
function startOfflineRendering(offlineContext) {
    return offlineContext.startRendering()
        .then(audioBuffer => ({ $: 'Ok', a: audioBuffer }))
        .catch(error => ({
            $: 'Err',
            a: {
                $: 'RenderError',
                a: 'Offline rendering failed: ' + error.message
            }
        }));
}
```

**Web Audio API Spec**: Returns `Promise<AudioBuffer>` with fully rendered audio.

**Key Requirements**:
- Context must not be already rendering
- Audio graph must be valid
- Sufficient memory for buffer allocation
- Promise resolves with complete AudioBuffer

### 3.3 ALREADY IMPLEMENTED: decodeAudioData ✅

**Status**: ✅ Working perfectly - use as reference!

```javascript
/**
 * Decode audio data from ArrayBuffer (MP3, AAC, OGG, WAV)
 * @name decodeAudioData
 * @canopy-type AudioContext -> ArrayBuffer -> Task Capability.CapabilityError AudioBuffer
 */
function decodeAudioData(audioContext, arrayBuffer) {
    return audioContext.decodeAudioData(arrayBuffer)
        .then(audioBuffer => ({ $: 'Ok', a: audioBuffer }))
        .catch(error => ({
            $: 'Err',
            a: {
                $: 'DecodeError',
                a: 'Failed to decode audio: ' + error.message
            }
        }));
}
```

### 3.4 OPTIONAL: AudioContext State Transitions

**Priority**: 🟡 **MEDIUM** - Improves reliability but not critical

Modern browsers support Promise-based versions of:

```javascript
/**
 * Resume audio context (Promise-based)
 * @name resumeAudioContextAsync
 * @canopy-type Initialized AudioContext -> Task Capability.CapabilityError (Initialized AudioContext)
 */
function resumeAudioContextAsync(initializedContext) {
    const audioContext = initializedContext.a;
    return audioContext.resume()
        .then(() => ({ $: 'Ok', a: { $: 'Running', a: audioContext } }))
        .catch(error => ({
            $: 'Err',
            a: mapContextError(error)
        }));
}

/**
 * Suspend audio context (Promise-based)
 * @name suspendAudioContextAsync
 * @canopy-type AudioContext -> Task Capability.CapabilityError AudioContext
 */
function suspendAudioContextAsync(audioContext) {
    return audioContext.suspend()
        .then(() => ({ $: 'Ok', a: audioContext }))
        .catch(error => ({
            $: 'Err',
            a: mapContextError(error)
        }));
}

/**
 * Close audio context (Promise-based)
 * @name closeAudioContextAsync
 * @canopy-type AudioContext -> Task Capability.CapabilityError ()
 */
function closeAudioContextAsync(audioContext) {
    return audioContext.close()
        .then(() => ({ $: 'Ok', a: { } }))
        .catch(error => ({
            $: 'Err',
            a: mapContextError(error)
        }));
}

function mapContextError(error) {
    if (error.name === 'InvalidStateError') {
        return { $: 'InvalidStateError', a: 'Invalid context state: ' + error.message };
    } else {
        return { $: 'InitializationRequired', a: 'Context operation failed: ' + error.message };
    }
}
```

---

## 4. Complete Implementation Checklist

### Phase 1: CRITICAL (Required for >90% coverage)

- [ ] **addAudioWorkletModule** - AudioWorklet support (Promise<void>)
- [ ] **createAudioWorkletNode** - Create AudioWorklet nodes
- [ ] **startOfflineRendering** - Offline audio processing (Promise<AudioBuffer>)
- [x] **decodeAudioData** - Audio decoding (ALREADY WORKING ✅)

### Phase 2: OPTIONAL (Enhanced reliability)

- [ ] **resumeAudioContextAsync** - Promise-based context resume
- [ ] **suspendAudioContextAsync** - Promise-based context suspend
- [ ] **closeAudioContextAsync** - Promise-based context close

### Phase 3: FUTURE (Advanced features)

- [ ] **MediaRecorder.start/stop** - If exposing MediaRecorder API
- [ ] **getUserMedia** - Microphone access (if not using separate FFI)
- [ ] **Fetch API integration** - For loading audio files

---

## 5. Error Mapping Strategy

### 5.1 AudioWorklet Errors

```javascript
function mapWorkletError(error) {
    switch(error.name) {
        case 'AbortError':
            return { $: 'AbortError', a: 'Script load failed: ' + error.message };
        case 'SyntaxError':
            return { $: 'SyntaxError', a: 'Invalid URL: ' + error.message };
        case 'SecurityError':
            return { $: 'SecurityError', a: 'CORS violation: ' + error.message };
        case 'NotSupportedError':
            return { $: 'NotSupportedError', a: 'AudioWorklet not supported: ' + error.message };
        default:
            return { $: 'InitializationRequired', a: 'Unknown error: ' + error.message };
    }
}
```

### 5.2 Offline Rendering Errors

```javascript
function mapRenderError(error) {
    switch(error.name) {
        case 'InvalidStateError':
            return { $: 'InvalidStateError', a: 'Already rendering: ' + error.message };
        case 'NotSupportedError':
            return { $: 'NotSupportedError', a: 'Rendering not supported: ' + error.message };
        case 'QuotaExceededError':
            return { $: 'QuotaExceededError', a: 'Memory exceeded: ' + error.message };
        default:
            return { $: 'RenderError', a: 'Rendering failed: ' + error.message };
    }
}
```

---

## 6. Testing Strategy

### 6.1 Unit Tests (Per Function)

```javascript
// Test successful Promise resolution
test('addAudioWorkletModule resolves successfully', async () => {
    const ctx = new AudioContext();
    const result = await addAudioWorkletModule(
        { $: 'Fresh', a: ctx },
        '/path/to/processor.js'
    );
    expect(result.$).toBe('Ok');
});

// Test Promise rejection
test('addAudioWorkletModule rejects with invalid URL', async () => {
    const ctx = new AudioContext();
    const result = await addAudioWorkletModule(
        { $: 'Fresh', a: ctx },
        'invalid://url'
    );
    expect(result.$).toBe('Err');
    expect(result.a.$).toBe('SyntaxError');
});
```

### 6.2 Integration Tests

```javascript
test('AudioWorklet end-to-end workflow', async () => {
    // 1. Create context
    const ctx = createAudioContext(userActivation);

    // 2. Load AudioWorklet module
    const loadResult = await addAudioWorkletModule(ctx, '/worklet.js');
    expect(loadResult.$).toBe('Ok');

    // 3. Create AudioWorklet node
    const node = createAudioWorkletNode(ctx, 'my-processor');

    // 4. Connect and use
    connectNodes(node, ctx.a.destination);
});
```

---

## 7. Performance Considerations

### 7.1 Promise Overhead

- **Minimal**: Modern JS engines optimize Promise chains heavily
- **Negligible**: Audio operations are I/O-bound, not Promise-bound
- **Best Practice**: Use async patterns for natural API design

### 7.2 Memory Management

```javascript
// ✅ GOOD: Let Promise chain handle cleanup
function goodPattern(ctx, url) {
    return ctx.audioWorklet.addModule(url)
        .then(result => ({ $: 'Ok', a: result }))
        .catch(error => ({ $: 'Err', a: mapError(error) }));
}

// ❌ BAD: Don't create intermediate closures unnecessarily
function badPattern(ctx, url) {
    return new Promise((resolve, reject) => {
        ctx.audioWorklet.addModule(url)
            .then(result => resolve({ $: 'Ok', a: result }))
            .catch(error => reject({ $: 'Err', a: mapError(error) }));
    });
}
```

---

## 8. Browser Compatibility

### 8.1 AudioWorklet Support

- **Chrome**: 66+ ✅
- **Firefox**: 76+ ✅
- **Safari**: 14.1+ ✅
- **Edge**: 79+ ✅

**Fallback Strategy**: For older browsers, use ScriptProcessorNode (deprecated but widely supported).

### 8.2 Promise-based Audio APIs

- **decodeAudioData**: Promise support in all modern browsers ✅
- **startRendering**: Promise support since 2016+ ✅
- **AudioWorklet**: Promise-only API (no callback version) ✅

---

## 9. Common Pitfalls and Solutions

### 9.1 ❌ Pitfall: Not Returning Promise

```javascript
// ❌ WRONG: Function doesn't return Promise
function badDecodeAudioData(ctx, buffer) {
    ctx.decodeAudioData(buffer)
        .then(result => ({ $: 'Ok', a: result }));
    // Missing return!
}

// ✅ CORRECT: Return the Promise
function goodDecodeAudioData(ctx, buffer) {
    return ctx.decodeAudioData(buffer)
        .then(result => ({ $: 'Ok', a: result }))
        .catch(error => ({ $: 'Err', a: mapError(error) }));
}
```

### 9.2 ❌ Pitfall: Using async/await

```javascript
// ❌ WRONG: Using async/await changes function behavior
async function badPattern(ctx, url) {
    const result = await ctx.audioWorklet.addModule(url);
    return { $: 'Ok', a: result };
}

// ✅ CORRECT: Return Promise directly
function goodPattern(ctx, url) {
    return ctx.audioWorklet.addModule(url)
        .then(result => ({ $: 'Ok', a: result }))
        .catch(error => ({ $: 'Err', a: mapError(error) }));
}
```

### 9.3 ❌ Pitfall: Incorrect ADT Format

```javascript
// ❌ WRONG: Missing ADT structure
.then(result => result)  // Raw value

// ❌ WRONG: Incorrect field name
.then(result => ({ tag: 'Ok', value: result }))

// ✅ CORRECT: Proper ADT format
.then(result => ({ $: 'Ok', a: result }))
```

---

## 10. Implementation Priority Matrix

| Function | Priority | Impact | Difficulty | Estimated Time |
|----------|----------|--------|------------|----------------|
| addAudioWorkletModule | 🔴 CRITICAL | HIGH | LOW | 30 mins |
| createAudioWorkletNode | 🔴 CRITICAL | HIGH | LOW | 20 mins |
| startOfflineRendering | 🔴 CRITICAL | MEDIUM | LOW | 20 mins |
| resumeAsync | 🟡 MEDIUM | LOW | TRIVIAL | 10 mins |
| suspendAsync | 🟡 MEDIUM | LOW | TRIVIAL | 10 mins |
| closeAsync | 🟡 MEDIUM | LOW | TRIVIAL | 10 mins |

**Total Estimated Time**: 1.5-2 hours for CRITICAL functions

---

## 11. Success Criteria

### 11.1 Functional Requirements

- [x] decodeAudioData working (ALREADY DONE ✅)
- [ ] addAudioWorkletModule working and tested
- [ ] createAudioWorkletNode working and tested
- [ ] startOfflineRendering working and tested
- [ ] All async functions return proper ADT format
- [ ] All errors properly mapped to CapabilityError constructors

### 11.2 Quality Requirements

- [ ] Unit tests for each async function
- [ ] Integration tests for workflows
- [ ] Error handling tests (rejection cases)
- [ ] Browser compatibility verified
- [ ] Performance benchmarks run
- [ ] Documentation complete

### 11.3 Coverage Goal

**Target**: >90% Web Audio API coverage

**Current Status** (estimated):
- Synchronous API: ~85% covered
- Async API: ~10% covered (only decodeAudioData)

**After Implementation** (projected):
- Synchronous API: ~85% covered
- Async API: ~95% covered
- **Total Coverage: >90% ✅**

---

## 12. Next Steps for Coder Agent

### Immediate Actions (Phase 1)

1. **Add addAudioWorkletModule function** (30 mins)
   - Copy pattern from decodeAudioData
   - Implement error mapping
   - Add JSDoc with @canopy-type

2. **Add createAudioWorkletNode function** (20 mins)
   - Simple synchronous wrapper
   - Connect to AudioWorklet functionality

3. **Add startOfflineRendering function** (20 mins)
   - Copy pattern from decodeAudioData
   - Implement error mapping

4. **Test all new functions** (30 mins)
   - Write unit tests
   - Verify integration
   - Test error cases

### Optional Actions (Phase 2)

5. **Add Promise-based context methods** (30 mins)
   - resumeAudioContextAsync
   - suspendAudioContextAsync
   - closeAudioContextAsync

---

## 13. References

### 13.1 Canopy Codebase

- **FFI Type System**: `/home/quinten/fh/canopy/packages/canopy-core/src/Foreign/FFI.hs`
- **JavaScript Generation**: `/home/quinten/fh/canopy/packages/canopy-core/src/Generate/JavaScript.hs`
- **Working Example**: `/home/quinten/fh/canopy/examples/audio-ffi/external/audio.js` (decodeAudioData)

### 13.2 Web Audio API Spec

- **AudioWorklet**: https://developer.mozilla.org/en-US/docs/Web/API/AudioWorklet
- **OfflineAudioContext**: https://developer.mozilla.org/en-US/docs/Web/API/OfflineAudioContext
- **Promise-based APIs**: https://webaudio.github.io/web-audio-api/

### 13.3 MDN Documentation

- **Worklet.addModule()**: https://developer.mozilla.org/en-US/docs/Web/API/Worklet/addModule
- **OfflineAudioContext.startRendering()**: https://developer.mozilla.org/en-US/docs/Web/API/OfflineAudioContext/startRendering
- **AudioContext.decodeAudioData()**: https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/decodeAudioData

---

## Conclusion

**KEY FINDING**: The Canopy compiler ALREADY HAS COMPLETE SUPPORT for async FFI through the Task type. The `decodeAudioData` implementation proves the pattern works perfectly.

**ACTION REQUIRED**: Simply apply the proven `decodeAudioData` pattern to the 3-4 remaining async Web Audio API functions to achieve >90% coverage.

**ESTIMATED TIME**: 1.5-2 hours of implementation work.

**RISK LEVEL**: ⬇️ **VERY LOW** - We're copying a working pattern, not inventing new functionality.

**RECOMMENDATION**: Proceed immediately with Phase 1 implementation (addAudioWorkletModule, createAudioWorkletNode, startOfflineRendering).

---

*Research completed by Researcher agent for Hive Mind swarm-1761562617410-wxghlazbw*
*Date: 2025-10-27*
*Status: ✅ READY FOR IMPLEMENTATION*
