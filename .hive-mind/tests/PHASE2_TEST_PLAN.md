# Phase 2 Web Audio API Test Plan

**Agent:** Tester
**Swarm:** swarm-1761562617410-wxghlazbw
**Date:** 2025-10-27
**Status:** Waiting for Coder Implementation

## Executive Summary

Analysis of the Canopy codebase reveals that **Phase 2 Web Audio API features are partially implemented**. AudioWorklet processor examples exist (`gain-processor.js`, `bitcrusher-processor.js`), and some Phase 2 features like `MediaStreamDestination` and `PeriodicWave` have FFI bindings in `audio.js`. However, **critical AudioWorklet FFI bindings** (addModule, AudioWorkletNode creation) and other P0/P1 features are **not yet implemented**.

## Current Implementation Status

### ✅ IMPLEMENTED (Ready for Testing)

1. **MediaStreamDestination** (P2)
   - Location: `/home/quinten/fh/canopy/examples/audio-ffi/external/audio.js:285`
   - Function: `createMediaStreamDestination`
   - Type: `AudioContext -> Result.Result Capability.CapabilityError MediaStreamAudioDestinationNode`
   - Error handling: InvalidStateError, NotSupportedError, InvalidAccessError
   - **Status: READY FOR PLAYWRIGHT TESTS**

2. **PeriodicWave** (P2)
   - Location: `/home/quinten/fh/canopy/examples/audio-ffi/external/audio.js:1122`
   - Function: `createPeriodicWave`
   - Type: `AudioContext -> PeriodicWave`
   - Basic implementation with Float32Array(2) real/imag arrays
   - **Status: READY FOR PLAYWRIGHT TESTS**

3. **AudioWorklet Processors** (Examples)
   - `gain-processor.js` - Simple gain control with MessagePort
   - `bitcrusher-processor.js` - Advanced effect with bidirectional communication
   - **Status: EXAMPLES EXIST, NO FFI BINDINGS**

4. **Existing Test Infrastructure**
   - `comprehensive-integration-test.js` - 41 screenshots, 5 test phases
   - Playwright-based with visual verification
   - Covers BiquadFilter, Panner, basic audio nodes
   - **Status: EXCELLENT FOUNDATION FOR PHASE 2 TESTS**

### ❌ NOT IMPLEMENTED (Blocking Tests)

1. **AudioWorklet FFI Bindings** (P0 - CRITICAL)
   - ❌ `addModule()` - Load AudioWorklet processor modules
   - ❌ `AudioWorkletNode()` - Create custom audio processors
   - ❌ MessagePort communication setup
   - ❌ Parameter passing to processors
   - **BLOCKER: Cannot test without FFI bindings**

2. **IIRFilterNode** (P1)
   - ❌ `createIIRFilter()` - Not in audio.js
   - ❌ Feedforward/feedback coefficient arrays
   - ❌ `getFrequencyResponse()` method
   - **BLOCKER: No implementation found**

3. **ConstantSourceNode** (P1)
   - ❌ `createConstantSource()` - Not in audio.js
   - ❌ Offset AudioParam control
   - ❌ Start/stop lifecycle
   - **BLOCKER: No implementation found**

4. **AudioBuffer Advanced Methods** (P2)
   - ❌ `copyToChannel()` - Not in audio.js
   - ❌ `copyFromChannel()` - Not in audio.js
   - Basic buffer support exists but missing advanced methods
   - **BLOCKER: Partial implementation only**

## Test Strategy

### Phase 1: Test Currently Implemented Features

While waiting for Coder to implement missing features, create Playwright tests for:

#### Test Suite 1: MediaStreamDestination (P2)
**Priority:** Medium
**Estimated Tests:** 8-10

```javascript
// Test cases:
1. Create MediaStreamDestination with valid AudioContext
2. Verify MediaStream object creation
3. Connect audio source to destination
4. Test stream.getTracks() returns audio tracks
5. Test MediaRecorder integration
6. Error: Create with closed context
7. Error: Browser doesn't support MediaStream
8. Performance: Measure stream latency
```

**Playwright Implementation:**
- Use `mcp__playwright__*` tools
- Navigate to test HTML page
- Call FFI functions via browser console
- Capture screenshots for each test
- Validate Result types (Ok/Err)
- Check browser console for errors

#### Test Suite 2: PeriodicWave (P2)
**Priority:** Medium
**Estimated Tests:** 10-12

```javascript
// Test cases:
1. Create PeriodicWave with default arrays
2. Create custom waveform (sine, square, sawtooth)
3. Apply PeriodicWave to OscillatorNode
4. Test normalization option (true/false)
5. Test real/imag coefficient validation
6. Test harmonics (1st, 2nd, 3rd, 5th)
7. Compare with built-in waveforms
8. Error: Invalid coefficient arrays
9. Error: Mismatched array lengths
10. Performance: Waveform generation time
```

#### Test Suite 3: AudioBuffer Advanced (P2)
**Priority:** Low (waiting for copyToChannel/copyFromChannel)
**Estimated Tests:** 12-15

```javascript
// Test cases when implemented:
1. copyToChannel - mono buffer
2. copyToChannel - stereo buffer
3. copyFromChannel - read samples
4. Multi-channel manipulation (5.1 surround)
5. Large buffer performance (10s @ 48kHz)
6. Edge cases: empty buffers, null channels
7. Error: Invalid channel index
8. Error: Out of bounds offset
```

### Phase 2: Test After Coder Implementation

#### Test Suite 4: AudioWorklet (P0 - CRITICAL)
**Priority:** CRITICAL
**Estimated Tests:** 20-25
**BLOCKED BY:** Missing FFI bindings

```javascript
// Test cases (implement after Coder adds FFI):
1. addModule - Load gain-processor.js
2. addModule - Load bitcrusher-processor.js
3. Create AudioWorkletNode with valid processor
4. Test MessagePort send message (setGain)
5. Test MessagePort receive message (status)
6. Test parameter passing (bitDepth, sampleRate)
7. Test audio processing (verify output)
8. Test processor lifecycle (start/stop)
9. Test multiple processors simultaneously
10. Error: Invalid processor name
11. Error: Module load failure
12. Error: Message to non-existent processor
13. Performance: Processing latency
14. Performance: CPU usage with multiple processors
```

#### Test Suite 5: IIRFilterNode (P1)
**Priority:** High
**Estimated Tests:** 15-18
**BLOCKED BY:** Missing createIIRFilter()

```javascript
// Test cases (implement after Coder adds FFI):
1. Create IIRFilter with feedforward/feedback arrays
2. Test lowpass IIR filter (compare with BiquadFilter)
3. Test highpass IIR filter
4. Test bandpass IIR filter
5. getFrequencyResponse - magnitude/phase arrays
6. Test filter stability (poles inside unit circle)
7. Test cascade filters (multiple IIR stages)
8. Error: Unstable filter coefficients
9. Error: Invalid array lengths
10. Error: All-zero coefficients
11. Performance: Real-time filtering
```

#### Test Suite 6: ConstantSourceNode (P1)
**Priority:** High
**Estimated Tests:** 12-15
**BLOCKED BY:** Missing createConstantSource()

```javascript
// Test cases (implement after Coder adds FFI):
1. Create ConstantSourceNode
2. Set offset value (0.0 to 1.0)
3. Test modulation use case (control GainNode)
4. Test start() method
5. Test stop() method
6. Test offset AudioParam automation
7. Test as LFO (low-frequency oscillator)
8. Error: Start after stop
9. Error: Negative offset
10. Performance: Multiple constant sources
```

## Test Infrastructure

### Directory Structure

```
/home/quinten/fh/canopy/
├── .hive-mind/
│   └── tests/
│       ├── PHASE2_TEST_PLAN.md (this file)
│       ├── phase2-mediastream-tests.js (NEW)
│       ├── phase2-periodicwave-tests.js (NEW)
│       ├── phase2-audioworklet-tests.js (BLOCKED)
│       ├── phase2-iirfilter-tests.js (BLOCKED)
│       ├── phase2-constantsource-tests.js (BLOCKED)
│       └── phase2-audiobuffer-tests.js (BLOCKED)
├── examples/audio-ffi/
│   ├── external/
│   │   ├── audio.js (FFI bindings)
│   │   ├── gain-processor.js (AudioWorklet example)
│   │   └── bitcrusher-processor.js (AudioWorklet example)
│   ├── test-results/
│   │   └── phase2/ (NEW - test screenshots/reports)
│   └── comprehensive-integration-test.js (existing)
```

### Playwright Test Template

```javascript
/**
 * Phase 2 Feature Tests - [FEATURE_NAME]
 *
 * Uses mcp__playwright__* tools for browser automation
 *
 * Test Requirements:
 * - Use mcp__playwright__browser_snapshot for state capture
 * - Use mcp__playwright__browser_take_screenshot for visual proof
 * - Test error conditions with Result types
 * - Validate browser console for errors
 * - Measure performance metrics
 */

const CONFIG = {
  baseURL: 'file:///home/quinten/fh/canopy/examples/audio-ffi/test-phase2.html',
  screenshotDir: 'test-results/phase2/[feature]',
  timeout: 10000
};

async function testFeature() {
  // 1. Navigate and initialize
  await mcp__playwright__browser_navigate({ url: CONFIG.baseURL });
  await mcp__playwright__browser_snapshot({});

  // 2. Execute test cases
  // 3. Capture screenshots
  // 4. Validate results
  // 5. Store in hive/tests/phase2/
}
```

## Success Criteria

### Phase 1 (Current - Ready to Test)
- ✅ MediaStreamDestination: 8+ tests, 100% pass rate
- ✅ PeriodicWave: 10+ tests, 100% pass rate
- ✅ Screenshots captured for all test cases
- ✅ Results stored in `hive/tests/phase2/` namespace
- ✅ Test report with coverage metrics

### Phase 2 (Blocked - Waiting for Coder)
- ⏳ AudioWorklet: 20+ tests, 100% pass rate (CRITICAL)
- ⏳ IIRFilterNode: 15+ tests, 100% pass rate
- ⏳ ConstantSourceNode: 12+ tests, 100% pass rate
- ⏳ AudioBuffer advanced: 12+ tests, 100% pass rate
- ⏳ >90% coverage across all Phase 2 features
- ⏳ Performance benchmarks documented

## Recommendations for Coder

### Priority 1: AudioWorklet FFI Bindings (CRITICAL)

**Add to audio.js:**

```javascript
/**
 * Add AudioWorklet module
 * @name addAudioWorkletModule
 * @canopy-type AudioContext -> String -> Task Capability.CapabilityError ()
 */
function addAudioWorkletModule(audioContext, moduleURL) {
  return audioContext.audioWorklet.addModule(moduleURL)
    .then(() => ({ $: 'Ok', a: { $: 'Unit' } }))
    .catch(e => ({
      $: 'Err',
      a: { $: 'ModuleLoadError', a: e.message }
    }));
}

/**
 * Create AudioWorkletNode
 * @name createAudioWorkletNode
 * @canopy-type AudioContext -> String -> Result Capability.CapabilityError AudioWorkletNode
 */
function createAudioWorkletNode(audioContext, processorName) {
  try {
    const node = new AudioWorkletNode(audioContext, processorName);
    return { $: 'Ok', a: node };
  } catch (e) {
    return { $: 'Err', a: { $: 'ProcessorNotFound', a: e.message } };
  }
}
```

### Priority 2: IIRFilterNode

```javascript
/**
 * Create IIR filter
 * @name createIIRFilter
 * @canopy-type AudioContext -> List Float -> List Float -> Result Capability.CapabilityError IIRFilterNode
 */
function createIIRFilter(audioContext, feedforward, feedback) {
  try {
    const node = audioContext.createIIRFilter(feedforward, feedback);
    return { $: 'Ok', a: node };
  } catch (e) {
    return { $: 'Err', a: { $: 'InvalidCoefficients', a: e.message } };
  }
}
```

### Priority 3: ConstantSourceNode

```javascript
/**
 * Create constant source
 * @name createConstantSource
 * @canopy-type AudioContext -> Result Capability.CapabilityError ConstantSourceNode
 */
function createConstantSource(audioContext) {
  try {
    const node = audioContext.createConstantSource();
    return { $: 'Ok', a: node };
  } catch (e) {
    return { $: 'Err', a: { $: 'CreationFailed', a: e.message } };
  }
}
```

## Next Steps

1. **Tester (Current):**
   - ✅ Complete analysis (DONE)
   - ⏳ Create MediaStreamDestination Playwright tests
   - ⏳ Create PeriodicWave Playwright tests
   - ⏳ Store results in hive memory

2. **Coder (Blocked):**
   - ❌ Implement AudioWorklet FFI bindings (P0 CRITICAL)
   - ❌ Implement IIRFilterNode FFI (P1)
   - ❌ Implement ConstantSourceNode FFI (P1)
   - ❌ Implement AudioBuffer advanced methods (P2)

3. **Tester (After Coder):**
   - ⏳ Create AudioWorklet Playwright tests
   - ⏳ Create IIRFilterNode Playwright tests
   - ⏳ Create ConstantSourceNode Playwright tests
   - ⏳ Generate comprehensive coverage report
   - ⏳ Validate 100% pass rate

## Resources

- **FFI Implementation:** `/home/quinten/fh/canopy/examples/audio-ffi/external/audio.js` (1501 lines)
- **AudioWorklet Examples:** `gain-processor.js`, `bitcrusher-processor.js`
- **Existing Tests:** `comprehensive-integration-test.js` (754 lines, 41 screenshots)
- **Test HTML Pages:** `index.html`, `test-*.html` (5 files)
- **Hive Memory:** `hive/tests/phase2/` namespace

## Estimated Timeline

- **Phase 1 Testing (Ready Now):** 2-3 hours
  - MediaStreamDestination tests: 1 hour
  - PeriodicWave tests: 1 hour
  - Documentation & reporting: 1 hour

- **Phase 2 Testing (After Coder):** 5-7 hours
  - AudioWorklet tests: 2-3 hours (CRITICAL)
  - IIRFilterNode tests: 1-2 hours
  - ConstantSourceNode tests: 1 hour
  - AudioBuffer tests: 1 hour
  - Integration & reporting: 1 hour

**Total Estimated:** 7-10 hours (2-3 hours now, 5-7 hours after Coder)

---

**Status:** 🟡 PARTIAL IMPLEMENTATION
**Blocker:** AudioWorklet, IIRFilterNode, ConstantSourceNode FFI bindings
**Ready to Test:** MediaStreamDestination, PeriodicWave
**Next Action:** Await Coder implementation OR proceed with partial testing
