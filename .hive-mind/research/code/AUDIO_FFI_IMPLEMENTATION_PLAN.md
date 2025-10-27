# Audio FFI Implementation Plan - Coder Agent
**Date**: 2025-10-27
**Agent**: Coder
**Swarm**: swarm-1761562617410-wxghlazbw

---

## Critical Issues Identified

### 1. AnalyserNode Data Export (Lines 1036-1073) ❌ BROKEN
**Current Implementation**:
```javascript
function getByteFrequencyData(analyser) {
    const dataArray = new Uint8Array(analyser.frequencyBinCount);
    analyser.getByteFrequencyData(dataArray);
    return dataArray[0];  // ❌ ONLY RETURNS FIRST ELEMENT!
}
```

**Problem**: Only returns single value, makes visualization impossible
**Fix**: Return full array converted to Canopy List type

### 2. ConvolverNode (Line 442) ❌ INCOMPLETE
**Current Implementation**:
```javascript
function createConvolver(audioContext) {
    return audioContext.createConvolver();  // ❌ NO BUFFER SETTER!
}
```

**Problem**: No way to set impulse response buffer, node is useless
**Fix**: Add `setConvolverBuffer()` and `setConvolverNormalize()` functions

### 3. WaveShaperNode (Line 505) ❌ INCOMPLETE
**Current Implementation**:
```javascript
function createWaveShaper(audioContext) {
    return audioContext.createWaveShaper();  // ❌ NO CURVE SETTER!
}
```

**Problem**: No way to set distortion curve, node is useless
**Fix**: Add `setWaveShaperCurve()` and `setWaveShaperOversample()` functions

### 4. JSDoc Result Type (31 functions) ❌ INCORRECT
**Current Pattern**:
```javascript
/**
 * @canopy-type UserActivated -> Result Capability.CapabilityError (Initialized AudioContext)
 */
```

**Problem**: `Result` is not properly namespaced
**Fix**: Use `Result.Result` or document Result type in module header

---

## Implementation Phases

### Phase 1: Fix Critical Broken Features (CURRENT)

#### Task 1.1: Fix AnalyserNode Data Export
- [ ] Modify `getByteTimeDomainData` to return full array
- [ ] Modify `getByteFrequencyData` to return full array
- [ ] Modify `getFloatTimeDomainData` to return full array
- [ ] Modify `getFloatFrequencyData` to return full array
- [ ] Convert TypedArrays to JavaScript arrays for Canopy compatibility
- [ ] Update JSDoc type signatures to reflect List return type

#### Task 1.2: Implement Convolver Configuration
- [ ] Create `setConvolverBuffer(convolver, audioBuffer)` function
- [ ] Create `setConvolverNormalize(convolver, normalize)` function
- [ ] Create `getConvolverBuffer(convolver)` function
- [ ] Add comprehensive error handling with Result types
- [ ] Add JSDoc documentation with examples

#### Task 1.3: Implement WaveShaper Configuration
- [ ] Create `setWaveShaperCurve(shaper, curve)` function
- [ ] Create `setWaveShaperOversample(shaper, oversample)` function
- [ ] Create `getWaveShaperCurve(shaper)` function
- [ ] Add curve generation utility functions
- [ ] Add comprehensive error handling with Result types
- [ ] Add JSDoc documentation with examples

#### Task 1.4: Fix JSDoc Result Types
- [ ] Add Result type definition to module header
- [ ] Update all 31 functions to use qualified Result type
- [ ] Verify type annotations compile correctly

### Phase 2: Add Missing Critical Features

#### Task 2.1: Implement decodeAudioData
- [ ] Create async wrapper for Promise-based decoding
- [ ] Handle MP3, AAC, OGG, WAV formats
- [ ] Add comprehensive error handling
- [ ] Add JSDoc documentation with examples

#### Task 2.2: Implement MediaStream Nodes
- [ ] Create `createMediaStreamSource(ctx, stream)` function
- [ ] Create `createMediaStreamDestination(ctx)` function
- [ ] Create `getMediaStream(destination)` function
- [ ] Add error handling and validation
- [ ] Add JSDoc documentation

#### Task 2.3: Implement AudioBuffer Data Access
- [ ] Create `getChannelData(buffer, channel)` function
- [ ] Create `copyToChannel(buffer, source, channel, start)` function
- [ ] Create `copyFromChannel(buffer, dest, channel, start)` function
- [ ] Add buffer generation utilities
- [ ] Add error handling and validation

### Phase 3: Add Advanced Features

#### Task 3.1: Implement AudioWorkletNode (HIGH COMPLEXITY)
- [ ] Create `addAudioWorkletModule(ctx, url)` async function
- [ ] Create `createAudioWorkletNode(ctx, name, options)` function
- [ ] Handle Promise-based module loading
- [ ] Add comprehensive error handling
- [ ] Add JSDoc documentation and examples

#### Task 3.2: Implement Additional Node Types
- [ ] IIRFilterNode functions
- [ ] ConstantSourceNode functions
- [ ] MediaElementSourceNode functions
- [ ] ScriptProcessorNode functions (deprecated fallback)

### Phase 4: Complete Error Handling

#### Task 4.1: Add Result Types to All Functions
- [ ] Identify 15+ functions lacking proper error handling
- [ ] Add try-catch blocks with Result type returns
- [ ] Map JavaScript errors to Canopy error types
- [ ] Update JSDoc type signatures

---

## Implementation Standards (CRITICAL)

### Function Size Constraints
- **Maximum 15 lines** per function
- **Maximum 4 parameters** per function
- **Maximum 4 branching points** per function
- Extract helper functions when limits exceeded

### Import Style
- Types unqualified, functions qualified
- Example: `import qualified Data.List as List`
- NO comments in import blocks

### Error Handling Pattern
```javascript
function audioFunction(params) {
    try {
        // Validate inputs
        if (invalidCondition) {
            throw new RangeError('Specific error message');
        }

        // Perform operation
        const result = operation(params);

        // Return Result type
        return { $: 'Ok', a: result };
    } catch (e) {
        // Map to Canopy error types
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: e.message } };
        } else if (e.name === 'RangeError') {
            return { $: 'Err', a: { $: 'RangeError', a: e.message } };
        } else {
            return { $: 'Err', a: { $: 'InitializationRequired', a: e.message } };
        }
    }
}
```

### JSDoc Pattern
```javascript
/**
 * Brief description of function
 * @name functionName
 * @canopy-type Type -> Type -> Result.Result ErrorType ReturnType
 *
 * @example
 * ```canopy
 * case functionName param1 param2 of
 *     Ok result -> -- Success
 *     Err error -> -- Handle error
 * ```
 */
```

---

## File Structure

Current file: `/home/quinten/fh/canopy/examples/audio-ffi/external/audio.js` (1288 lines)

**Sections**:
- Lines 11-127: Audio Context Management ✅
- Lines 129-287: Source Nodes ✅
- Lines 289-526: Effect Nodes ⚠️ (Convolver/WaveShaper incomplete)
- Lines 527-565: Analyzer Nodes ✅
- Lines 567-623: Audio Graph Connections ✅
- Lines 625-642: Feature Detection ✅
- Lines 659-770: Spatial Audio (Panner) ✅
- Lines 772-827: Audio Listener ✅
- Lines 829-849: Channel Routing ✅
- Lines 851-899: Audio Buffer Operations ⚠️ (Incomplete)
- Lines 901-913: Periodic Wave ⚠️ (Hardcoded)
- Lines 915-936: Offline Audio Context ⚠️ (No Promise handling)
- Lines 938-1025: Audio Param Automation ✅
- Lines 1027-1073: Analyzer Advanced ❌ (BROKEN)
- Lines 1075-1288: Buffer Source + Simplified Interface ✅

---

## Testing Strategy

### Unit Tests (Required)
- Test error handling for all Result-returning functions
- Test parameter validation (ranges, types)
- Test null/undefined handling
- Test browser compatibility fallbacks

### Integration Tests (Required)
- Test complete audio pipeline (source → effects → destination)
- Test timing precision
- Test memory cleanup (disconnect nodes)
- Test multiple simultaneous contexts

### Visual Tests (Existing)
- Use existing Playwright visual tests
- Verify visualizations work with fixed analyzer data

---

## Progress Tracking

### Completed
- [x] Research analysis complete (Researcher Agent)
- [x] Implementation plan created (Coder Agent)
- [x] Critical issues identified

### In Progress
- [ ] Fix AnalyserNode data export
- [ ] Implement Convolver buffer setter
- [ ] Implement WaveShaper curve setter

### Pending
- [ ] Fix JSDoc Result types
- [ ] Implement decodeAudioData
- [ ] Implement MediaStream nodes
- [ ] Implement AudioBuffer data access
- [ ] Implement AudioWorkletNode
- [ ] Add comprehensive error handling

---

## Coordination Points

### With Researcher Agent
- ✅ Research findings received
- ✅ Priority list established
- ✅ Implementation patterns identified

### With Tester Agent
- ⏳ Need unit test infrastructure
- ⏳ Need integration test suite
- ⏳ Need browser compatibility tests

### With Documenter Agent (Future)
- ⏳ Need usage examples
- ⏳ Need tutorial for audio features
- ⏳ Need troubleshooting guide

---

## Risk Assessment

### High Risk Items
- **AudioWorkletNode**: Requires async/Promise support in FFI
- **decodeAudioData**: Promise-based, needs async handling
- **TypedArray marshalling**: Performance implications for large arrays

### Medium Risk Items
- **Memory management**: Large buffers, proper cleanup
- **Browser compatibility**: Safari iOS restrictions
- **Timing precision**: Audio scheduling accuracy

### Low Risk Items
- **Basic property setters**: Straightforward implementations
- **JSDoc fixes**: Find and replace operation
- **Additional getters**: Simple property access

---

**Status**: Ready to begin Phase 1 implementation
**Next Action**: Fix AnalyserNode data export (highest priority)
