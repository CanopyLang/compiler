# Complete Audio FFI Implementation Analysis
## Hive Mind Research Report - Agent Analysis

**Date**: 2025-10-22
**Agent Role**: Researcher
**Task**: Comprehensive analysis of audio-ffi implementation gaps and missing features

---

## Executive Summary

The current audio FFI implementation (`examples/audio-ffi/external/audio.js`) is **39KB and contains 1289 lines** of JavaScript. It provides a solid foundation but has significant gaps in:
1. **Missing Web Audio API nodes** (11+ node types not implemented)
2. **Incomplete JSDoc type annotations** (Result type issues)
3. **Missing advanced features** (AudioWorklet, Media Streams, Recording)
4. **Incomplete error handling** for some operations
5. **No comprehensive test coverage** for all functions

---

## 1. Current Implementation Inventory

### ✅ IMPLEMENTED Features (Lines 1-1289)

#### Audio Context Management (Lines 11-127)
- ✅ `createAudioContext` - Full error handling with Result type
- ✅ `getCurrentTime` - Basic getter
- ✅ `resumeAudioContext` - With InvalidStateError handling
- ✅ `suspendAudioContext` - With error handling
- ✅ `closeAudioContext` - With error handling
- ✅ `getSampleRate` - Basic getter
- ✅ `getContextState` - Basic getter

#### Source Nodes (Lines 129-287)
- ✅ `createOscillator` - Full validation and error handling
- ✅ `startOscillator` - With timing validation
- ✅ `stopOscillator` - With timing validation
- ✅ `setOscillatorFrequency` - Basic setter
- ✅ `setOscillatorDetune` - Basic setter
- ✅ `createBufferSource` - Basic creation
- ✅ `startBufferSource` - With error handling
- ✅ `stopBufferSource` - With error handling

#### Effect Nodes (Lines 289-526)
- ✅ `createGainNode` - Full error handling
- ✅ `setGain` - With error handling
- ✅ `rampGainLinear` - With error handling
- ✅ `rampGainExponential` - With zero-value validation
- ✅ `createBiquadFilter` - Basic creation
- ✅ `setFilterFrequency` - Basic setter
- ✅ `setFilterQ` - Basic setter
- ✅ `setFilterGain` - Basic setter
- ✅ `createDelay` - Basic creation
- ✅ `setDelayTime` - Basic setter
- ✅ `createConvolver` - Basic creation
- ✅ `createDynamicsCompressor` - Basic creation
- ✅ `setCompressorThreshold/Knee/Ratio/Attack/Release` - Basic setters
- ✅ `createWaveShaper` - Basic creation
- ✅ `createStereoPanner` - Basic creation
- ✅ `setPan` - Basic setter

#### Analyzer Nodes (Lines 527-565)
- ✅ `createAnalyser` - Basic creation
- ✅ `setAnalyserFFTSize` - Basic setter
- ✅ `setAnalyserSmoothing` - Basic setter
- ✅ `getFrequencyBinCount` - Basic getter

#### Audio Graph Connections (Lines 567-623)
- ✅ `connectNodes` - Full error handling
- ✅ `connectToDestination` - Full error handling
- ✅ `disconnectNode` - Basic operation

#### Feature Detection (Lines 625-642)
- ✅ `checkWebAudioSupport` - Basic detection

#### Spatial Audio - PannerNode (Lines 659-770)
- ✅ `createPanner` - Basic creation
- ✅ `setPannerPosition` - With fallback for older browsers
- ✅ `setPannerOrientation` - With fallback
- ✅ `setPanningModel` - Basic setter
- ✅ `setDistanceModel` - Basic setter
- ✅ `setRefDistance/MaxDistance/RolloffFactor` - Basic setters
- ✅ `setConeInnerAngle/OuterAngle/OuterGain` - Basic setters

#### Audio Listener (Lines 772-827)
- ✅ `getAudioListener` - Basic getter
- ✅ `setListenerPosition` - With fallback
- ✅ `setListenerForward` - With fallback
- ✅ `setListenerUp` - With fallback

#### Channel Routing (Lines 829-849)
- ✅ `createChannelSplitter` - Basic creation
- ✅ `createChannelMerger` - Basic creation

#### Audio Buffer Operations (Lines 851-899)
- ✅ `createAudioBuffer` - Basic creation
- ✅ `getBufferLength/Duration/SampleRate/Channels` - Basic getters

#### Periodic Wave (Lines 901-913)
- ✅ `createPeriodicWave` - Basic creation with hardcoded values

#### Offline Audio Context (Lines 915-936)
- ✅ `createOfflineAudioContext` - Basic creation
- ✅ `startOfflineRendering` - Basic operation

#### Audio Param Automation (Lines 938-1025)
- ✅ `getGainParam/FrequencyParam/DetuneParam` - Basic getters
- ✅ `setParamValueAtTime` - Basic setter
- ✅ `linearRampToValue` - Basic ramp
- ✅ `exponentialRampToValue` - Basic ramp
- ✅ `setTargetAtTime` - Basic target
- ✅ `cancelScheduledValues` - Basic cancel
- ✅ `cancelAndHoldAtTime` - With fallback

#### Analyzer Advanced (Lines 1027-1073)
- ✅ `getByteTimeDomainData` - Returns only first element
- ✅ `getByteFrequencyData` - Returns only first element
- ✅ `getFloatTimeDomainData` - Returns only first element
- ✅ `getFloatFrequencyData` - Returns only first element

#### Buffer Source Advanced (Lines 1075-1131)
- ✅ `setBufferSourceBuffer` - Basic setter
- ✅ `setBufferSourceLoop/LoopStart/LoopEnd` - Basic setters
- ✅ `setBufferSourcePlaybackRate/Detune` - Basic setters

#### Simplified Interface (Lines 1133-1289)
- ✅ Complete simplified string-based interface with global state management

---

## 2. ❌ MISSING Web Audio API Features

### 2.1 Missing Audio Node Types

#### **MediaElementAudioSourceNode** (HIGH PRIORITY)
```javascript
// NOT IMPLEMENTED - Needed for <audio>/<video> element integration
function createMediaElementSource(audioContext, mediaElement) {
    return audioContext.createMediaElementSource(mediaElement);
}
```

**Use Cases**: Playing HTML5 audio/video through Web Audio effects chain
**Web Audio API**: `AudioContext.createMediaElementSource()`
**Priority**: HIGH - Essential for real-world audio applications

---

#### **MediaStreamAudioSourceNode** (HIGH PRIORITY)
```javascript
// NOT IMPLEMENTED - Needed for microphone/getUserMedia integration
function createMediaStreamSource(audioContext, mediaStream) {
    return audioContext.createMediaStreamSource(mediaStream);
}
```

**Use Cases**: Processing microphone input, WebRTC audio
**Web Audio API**: `AudioContext.createMediaStreamSource()`
**Priority**: HIGH - Critical for recording/VoIP applications

---

#### **MediaStreamAudioDestinationNode** (HIGH PRIORITY)
```javascript
// NOT IMPLEMENTED - Needed for capturing audio output to MediaStream
function createMediaStreamDestination(audioContext) {
    return audioContext.createMediaStreamDestination();
}

function getMediaStream(destinationNode) {
    return destinationNode.stream;
}
```

**Use Cases**: Recording Web Audio output, WebRTC transmission
**Web Audio API**: `AudioContext.createMediaStreamDestination()`
**Priority**: HIGH - Required for audio recording

---

#### **ScriptProcessorNode** (MEDIUM PRIORITY - DEPRECATED)
```javascript
// NOT IMPLEMENTED - Legacy audio processing
// NOTE: Deprecated in favor of AudioWorkletNode
function createScriptProcessor(audioContext, bufferSize, inputChannels, outputChannels) {
    return audioContext.createScriptProcessor(bufferSize, inputChannels, outputChannels);
}
```

**Status**: DEPRECATED - Replaced by AudioWorklet
**Priority**: MEDIUM - Still needed for browser compatibility
**Note**: Should warn users about deprecation

---

#### **AudioWorkletNode** (HIGHEST PRIORITY)
```javascript
// NOT IMPLEMENTED - Modern custom audio processing
async function addAudioWorkletModule(audioContext, moduleURL) {
    return await audioContext.audioWorklet.addModule(moduleURL);
}

function createAudioWorkletNode(audioContext, name, options) {
    return new AudioWorkletNode(audioContext, name, options);
}
```

**Use Cases**: Custom audio DSP, advanced synthesis, real-time effects
**Web Audio API**: `AudioWorkletNode`, `audioWorklet.addModule()`
**Priority**: HIGHEST - Modern standard for custom audio processing
**Complexity**: HIGH - Requires Promise handling in FFI

---

#### **ConstantSourceNode** (MEDIUM PRIORITY)
```javascript
// NOT IMPLEMENTED - Constant audio signal source
function createConstantSource(audioContext) {
    return audioContext.createConstantSource();
}

function setConstantSourceOffset(source, value, when) {
    source.offset.setValueAtTime(value, when);
}

function startConstantSource(source, when) {
    source.start(when);
}

function stopConstantSource(source, when) {
    source.stop(when);
}
```

**Use Cases**: DC offset, constant modulation signals
**Web Audio API**: `AudioContext.createConstantSource()`
**Priority**: MEDIUM - Useful for advanced synthesis

---

#### **IIRFilterNode** (MEDIUM PRIORITY)
```javascript
// NOT IMPLEMENTED - Infinite Impulse Response filters
function createIIRFilter(audioContext, feedforward, feedback) {
    return audioContext.createIIRFilter(feedforward, feedback);
}

function getIIRFrequencyResponse(filter, frequencyArray) {
    const magResponse = new Float32Array(frequencyArray.length);
    const phaseResponse = new Float32Array(frequencyArray.length);
    filter.getFrequencyResponse(frequencyArray, magResponse, phaseResponse);
    return { magnitude: magResponse, phase: phaseResponse };
}
```

**Use Cases**: Custom digital filters, emulation of analog filters
**Web Audio API**: `AudioContext.createIIRFilter()`
**Priority**: MEDIUM - Advanced filtering capabilities

---

### 2.2 Missing AudioBuffer Features

#### **AudioBuffer Data Access** (HIGH PRIORITY)
```javascript
// NOT IMPLEMENTED - Getting/setting audio buffer data
function getChannelData(audioBuffer, channelNumber) {
    return audioBuffer.getChannelData(channelNumber);
}

function copyToChannel(audioBuffer, source, channelNumber, startInChannel) {
    audioBuffer.copyToChannel(source, channelNumber, startInChannel || 0);
}

function copyFromChannel(audioBuffer, destination, channelNumber, startInChannel) {
    audioBuffer.copyFromChannel(destination, channelNumber, startInChannel || 0);
}
```

**Use Cases**: Manual audio buffer manipulation, waveform generation
**Priority**: HIGH - Essential for procedural audio

---

#### **AudioBuffer Utilities** (MEDIUM PRIORITY)
```javascript
// NOT IMPLEMENTED - Buffer utilities
function createSilentBuffer(audioContext, duration, channels, sampleRate) {
    const length = duration * sampleRate;
    return audioContext.createBuffer(channels, length, sampleRate);
}

function cloneAudioBuffer(audioContext, sourceBuffer) {
    const clone = audioContext.createBuffer(
        sourceBuffer.numberOfChannels,
        sourceBuffer.length,
        sourceBuffer.sampleRate
    );
    for (let i = 0; i < sourceBuffer.numberOfChannels; i++) {
        clone.copyToChannel(sourceBuffer.getChannelData(i), i);
    }
    return clone;
}
```

**Priority**: MEDIUM - Useful utilities

---

### 2.3 Missing Audio Decoding

#### **decodeAudioData** (HIGHEST PRIORITY)
```javascript
// NOT IMPLEMENTED - Decode compressed audio (MP3, AAC, etc.)
function decodeAudioData(audioContext, arrayBuffer) {
    return audioContext.decodeAudioData(arrayBuffer)
        .then(audioBuffer => ({ $: 'Ok', a: audioBuffer }))
        .catch(error => ({
            $: 'Err',
            a: { $: 'DecodeError', a: 'Failed to decode audio: ' + error.message }
        }));
}
```

**Use Cases**: Loading MP3/AAC/OGG files, audio streaming
**Web Audio API**: `AudioContext.decodeAudioData()`
**Priority**: HIGHEST - Essential for loading audio files
**Note**: Returns Promise, needs async FFI support

---

### 2.4 Missing Oscillator Features

#### **Custom Waveform Support** (HIGH PRIORITY)
```javascript
// PARTIAL IMPLEMENTATION - createPeriodicWave exists but limited
function setPeriodicWave(oscillator, periodicWave) {
    oscillator.setPeriodicWave(periodicWave);
}

function createPeriodicWaveAdvanced(audioContext, real, imag, constraints) {
    const realArray = new Float32Array(real);
    const imagArray = new Float32Array(imag);
    const options = constraints || { disableNormalization: false };
    return audioContext.createPeriodicWave(realArray, imagArray, options);
}
```

**Status**: Partially implemented (basic version exists)
**Priority**: HIGH - Needed for custom synthesis

---

### 2.5 Missing Convolver Features

#### **Convolver Configuration** (HIGH PRIORITY)
```javascript
// NOT IMPLEMENTED - Convolver buffer and normalization
function setConvolverBuffer(convolver, audioBuffer) {
    convolver.buffer = audioBuffer;
}

function setConvolverNormalize(convolver, normalize) {
    convolver.normalize = normalize;
}

function getConvolverBuffer(convolver) {
    return convolver.buffer;
}
```

**Use Cases**: Reverb effects, impulse response processing
**Priority**: HIGH - Convolver node is useless without buffer setting

---

### 2.6 Missing WaveShaper Features

#### **WaveShaper Curve** (HIGH PRIORITY)
```javascript
// NOT IMPLEMENTED - WaveShaper curve configuration
function setWaveShaperCurve(shaper, curve) {
    const curveArray = new Float32Array(curve);
    shaper.curve = curveArray;
}

function setWaveShaperOversample(shaper, oversampleType) {
    shaper.oversample = oversampleType; // 'none', '2x', '4x'
}

function getWaveShaperCurve(shaper) {
    return shaper.curve;
}
```

**Use Cases**: Distortion effects, saturation
**Priority**: HIGH - WaveShaper node is useless without curve

---

### 2.7 Missing Analyzer Data Export

#### **Full Array Data** (HIGH PRIORITY)
```javascript
// CURRENT ISSUE: Only returns first element
// NEEDED: Return full array

function getByteTimeDomainDataArray(analyser) {
    const dataArray = new Uint8Array(analyser.frequencyBinCount);
    analyser.getByteTimeDomainData(dataArray);
    return Array.from(dataArray); // Convert to Canopy list
}

function getByteFrequencyDataArray(analyser) {
    const dataArray = new Uint8Array(analyser.frequencyBinCount);
    analyser.getByteFrequencyData(dataArray);
    return Array.from(dataArray);
}

function getFloatTimeDomainDataArray(analyser) {
    const dataArray = new Float32Array(analyser.frequencyBinCount);
    analyser.getFloatTimeDomainData(dataArray);
    return Array.from(dataArray);
}

function getFloatFrequencyDataArray(analyser) {
    const dataArray = new Float32Array(analyser.frequencyBinCount);
    analyser.getFloatFrequencyData(dataArray);
    return Array.from(dataArray);
}
```

**Current Status**: Only returns single value `dataArray[0]`
**Priority**: HIGH - Visualization requires full arrays

---

### 2.8 Missing Audio Rendering

#### **Offline Rendering Completion** (HIGH PRIORITY)
```javascript
// PARTIAL IMPLEMENTATION - startOfflineRendering exists but no Promise handling
function startOfflineRenderingAsync(offlineContext) {
    return offlineContext.startRendering()
        .then(renderedBuffer => ({ $: 'Ok', a: renderedBuffer }))
        .catch(error => ({
            $: 'Err',
            a: { $: 'RenderError', a: 'Rendering failed: ' + error.message }
        }));
}

function suspendOfflineContext(offlineContext, suspendTime) {
    return offlineContext.suspend(suspendTime)
        .then(() => ({ $: 'Ok', a: 1 }))
        .catch(error => ({
            $: 'Err',
            a: { $: 'InvalidStateError', a: error.message }
        }));
}

function resumeOfflineContext(offlineContext) {
    return offlineContext.resume()
        .then(() => ({ $: 'Ok', a: 1 }))
        .catch(error => ({
            $: 'Err',
            a: { $: 'InvalidStateError', a: error.message }
        }));
}
```

**Current Status**: Basic `startOfflineRendering` exists but returns void
**Priority**: HIGH - Offline rendering needs Promise-based completion

---

### 2.9 Missing Base AudioNode Properties

#### **AudioNode Configuration** (MEDIUM PRIORITY)
```javascript
// NOT IMPLEMENTED - Common AudioNode properties
function getNodeChannelCount(node) {
    return node.channelCount;
}

function setNodeChannelCount(node, count) {
    node.channelCount = count;
}

function getNodeChannelCountMode(node) {
    return node.channelCountMode; // "max", "clamped-max", "explicit"
}

function setNodeChannelCountMode(node, mode) {
    node.channelCountMode = mode;
}

function getNodeChannelInterpretation(node) {
    return node.channelInterpretation; // "speakers", "discrete"
}

function setNodeChannelInterpretation(node, interpretation) {
    node.channelInterpretation = interpretation;
}

function getNumberOfInputs(node) {
    return node.numberOfInputs;
}

function getNumberOfOutputs(node) {
    return node.numberOfOutputs;
}
```

**Priority**: MEDIUM - Advanced audio routing configuration

---

### 2.10 Missing Advanced Connection Methods

#### **Selective Connection** (MEDIUM PRIORITY)
```javascript
// NOT IMPLEMENTED - Connect specific channels
function connectNodesWithChannels(source, destination, outputChannel, inputChannel) {
    return source.connect(destination, outputChannel, inputChannel);
}

function disconnectNodeFromDestination(source, destination) {
    source.disconnect(destination);
}

function disconnectNodeOutput(source, output) {
    source.disconnect(output);
}

function disconnectNodeFromDestinationOutput(source, destination, output, input) {
    source.disconnect(destination, output, input);
}
```

**Priority**: MEDIUM - Advanced audio graph routing

---

### 2.11 Missing AudioContext Properties

#### **Context Configuration** (MEDIUM PRIORITY)
```javascript
// NOT IMPLEMENTED - Additional context properties
function getContextBaseLatency(audioContext) {
    return audioContext.baseLatency;
}

function getContextOutputLatency(audioContext) {
    return audioContext.outputLatency;
}

function getContextDestination(audioContext) {
    return audioContext.destination;
}

function getContextDestinationMaxChannels(audioContext) {
    return audioContext.destination.maxChannelCount;
}
```

**Priority**: MEDIUM - Latency monitoring for pro audio

---

## 3. JSDoc Type Signature Issues

### 3.1 Result Type References

**ISSUE**: JSDoc comments reference `Result` without proper namespace

**Current Pattern (Lines 18, 54, 77, 95, etc.)**:
```javascript
/**
 * @canopy-type UserActivated -> Result Capability.CapabilityError (Initialized AudioContext)
 */
```

**Problem**: `Result` is not namespaced properly in JSDoc. The Canopy compiler expects fully qualified type names.

**Recommended Fix Options**:

1. **Use fully qualified Result type**:
```javascript
/**
 * @canopy-type UserActivated -> Result.Result Capability.CapabilityError (Initialized AudioContext)
 */
```

2. **Document Result in module header**:
```javascript
/**
 * @typedef {import('Result').Result} Result
 */
```

3. **Use Canopy standard library convention**:
```javascript
/**
 * @canopy-type UserActivated -> Basics.Result Capability.CapabilityError (Initialized AudioContext)
 */
```

**Affected Functions**: 31 functions use Result type (lines 18, 54, 77, 95, 136, 171, 196, 246, 269, 296, 322, 343, 362, 574, 596, etc.)

---

### 3.2 Missing Type Annotations

**ISSUE**: Some functions lack proper error handling Result types

**Functions with basic returns that should have Result types**:
```javascript
// Lines 239-241 - Should validate context state
function createBufferSource(audioContext) {
    return audioContext.createBufferSource();
}
// SHOULD BE:
function createBufferSource(audioContext) {
    try {
        return { $: 'Ok', a: audioContext.createBufferSource() };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidStateError', a: e.message } };
    }
}
```

**Functions lacking error handling** (Lines 384-526):
- `createBiquadFilter`
- `setFilterFrequency/Q/Gain`
- `createDelay`
- `setDelayTime`
- `createConvolver`
- `createDynamicsCompressor`
- `setCompressor*` (all 5 functions)
- `createWaveShaper`
- `createStereoPanner`
- `setPan`

---

### 3.3 Unit Type Inconsistency

**ISSUE**: Functions return `Basics.Int` for unit type

**Current Pattern**:
```javascript
/**
 * @canopy-type OscillatorNode -> Float -> Result Capability.CapabilityError Basics.Int
 */
function startOscillator(oscillator, when) {
    // ...
    return { $: 'Ok', a: 1 };
}
```

**Recommendation**: Use proper `()` unit type or define `Unit` type
```javascript
/**
 * @canopy-type OscillatorNode -> Float -> Result Capability.CapabilityError ()
 */
```

---

## 4. Web Audio API Best Practices Analysis

### 4.1 AudioBufferSourceNode Usage

**Current Implementation**: Basic (Lines 236-287)

**Missing Best Practices**:
1. **One-shot restriction not documented** - BufferSource can only be started once
2. **No helper for repeated playback** - Should create new node each time
3. **No buffer validation** - Should check if buffer is set before start

**Recommended Addition**:
```javascript
function createAndStartBufferSource(audioContext, buffer, destination, when, loop) {
    try {
        const source = audioContext.createBufferSource();
        source.buffer = buffer;
        source.loop = loop || false;
        source.connect(destination);
        source.start(when || 0);
        return { $: 'Ok', a: source };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidStateError', a: e.message } };
    }
}
```

---

### 4.2 BiquadFilterNode Best Practices

**Current Implementation**: Basic creation (Lines 382-417)

**Missing**:
1. **No frequency response calculation** - `getFrequencyResponse()`
2. **No filter type validation** - Should validate type strings
3. **No Q factor limits** - Should warn about instability

**Recommended Addition**:
```javascript
function getFilterFrequencyResponse(filter, frequencyHz) {
    const magResponse = new Float32Array(1);
    const phaseResponse = new Float32Array(1);
    const freqArray = new Float32Array([frequencyHz]);
    filter.getFrequencyResponse(freqArray, magResponse, phaseResponse);
    return { magnitude: magResponse[0], phase: phaseResponse[0] };
}
```

---

### 4.3 DelayNode Best Practices

**Current Implementation**: Basic (Lines 419-435)

**Missing**:
1. **No maxDelayTime explanation** - Important parameter for buffer allocation
2. **No validation** - delayTime must be ≤ maxDelayTime
3. **No feedback loop warning** - Common source of bugs

**Recommended Addition**:
```javascript
function setDelayTimeWithValidation(delayNode, delayTime, when, maxDelayTime) {
    try {
        if (delayTime > maxDelayTime) {
            throw new RangeError(`Delay time ${delayTime} exceeds max ${maxDelayTime}`);
        }
        if (delayTime < 0) {
            throw new RangeError('Delay time cannot be negative');
        }
        delayNode.delayTime.setValueAtTime(delayTime, when);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'RangeError', a: e.message } };
    }
}
```

---

### 4.4 ConvolverNode Best Practices

**Current Implementation**: INCOMPLETE (Line 442)

**Critical Missing Features**:
1. **No buffer setting** - Convolver is useless without impulse response
2. **No normalize property** - Important for consistent volume
3. **No buffer loading utilities**

**Must Add**:
```javascript
function setConvolverBuffer(convolver, audioBuffer) {
    try {
        convolver.buffer = audioBuffer;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidStateError', a: e.message } };
    }
}

function createConvolverWithBuffer(audioContext, audioBuffer, normalize) {
    try {
        const convolver = audioContext.createConvolver();
        convolver.buffer = audioBuffer;
        convolver.normalize = normalize !== undefined ? normalize : true;
        return { $: 'Ok', a: convolver };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidStateError', a: e.message } };
    }
}
```

---

### 4.5 DynamicsCompressorNode Best Practices

**Current Implementation**: Basic (Lines 447-498)

**Missing**:
1. **No reduction metering** - `reduction` property for VU meter
2. **No presets** - Common compressor settings (mastering, vocal, drum bus)
3. **No parameter range documentation**

**Recommended Addition**:
```javascript
function getCompressorReduction(compressor) {
    return compressor.reduction; // Current gain reduction in dB
}

function applyCompressorPreset(compressor, preset, when) {
    // "gentle", "medium", "heavy", "limiter"
    const presets = {
        gentle: { threshold: -24, knee: 30, ratio: 4, attack: 0.003, release: 0.25 },
        medium: { threshold: -18, knee: 12, ratio: 8, attack: 0.003, release: 0.15 },
        heavy: { threshold: -12, knee: 6, ratio: 12, attack: 0.001, release: 0.1 },
        limiter: { threshold: -3, knee: 0, ratio: 20, attack: 0.001, release: 0.05 }
    };
    const p = presets[preset];
    if (p) {
        compressor.threshold.setValueAtTime(p.threshold, when);
        compressor.knee.setValueAtTime(p.knee, when);
        compressor.ratio.setValueAtTime(p.ratio, when);
        compressor.attack.setValueAtTime(p.attack, when);
        compressor.release.setValueAtTime(p.release, when);
    }
}
```

---

### 4.6 WaveShaperNode Best Practices

**Current Implementation**: INCOMPLETE (Line 505)

**Critical Missing**:
1. **No curve setting** - WaveShaper is useless without transfer curve
2. **No oversample setting** - Important for reducing aliasing
3. **No curve generation utilities**

**Must Add**:
```javascript
function setWaveShaperCurve(shaper, curve) {
    try {
        shaper.curve = new Float32Array(curve);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidStateError', a: e.message } };
    }
}

function makeDistortionCurve(amount, nSamples) {
    const k = amount || 50;
    const n = nSamples || 44100;
    const curve = new Float32Array(n);
    const deg = Math.PI / 180;
    for (let i = 0; i < n; i++) {
        const x = (i * 2 / n) - 1;
        curve[i] = (3 + k) * x * 20 * deg / (Math.PI + k * Math.abs(x));
    }
    return curve;
}
```

---

### 4.7 StereoPannerNode Best Practices

**Current Implementation**: Basic (Lines 511-525)

**Notes**:
- ✅ Correct implementation
- ⚠️ Should mention fallback to PannerNode for older browsers
- ⚠️ Range validation missing (-1 to +1)

---

### 4.8 AnalyserNode Best Practices

**Current Implementation**: INCOMPLETE (Lines 532-565 and 1027-1073)

**Issues**:
1. **Only returns first array element** - Visualization needs full arrays
2. **No min/max decibels configuration** - Important for scaling
3. **No preset FFT sizes** - Should suggest powers of 2

**Must Fix**:
```javascript
function setAnalyserMinMaxDecibels(analyser, minDecibels, maxDecibels) {
    try {
        if (minDecibels >= maxDecibels) {
            throw new Error('minDecibels must be less than maxDecibels');
        }
        analyser.minDecibels = minDecibels;
        analyser.maxDecibels = maxDecibels;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'RangeError', a: e.message } };
    }
}
```

---

### 4.9 PannerNode Best Practices

**Current Implementation**: Good (Lines 659-770)

**Strengths**:
- ✅ Handles both new and legacy APIs with fallbacks
- ✅ Comprehensive parameter coverage
- ✅ All spatial properties included

**Suggestions**:
- Add validation for panning model strings ("equalpower", "HRTF")
- Add validation for distance model strings ("linear", "inverse", "exponential")

---

### 4.10 AudioListener Best Practices

**Current Implementation**: Good (Lines 772-827)

**Strengths**:
- ✅ Handles modern and legacy APIs
- ✅ Proper 3D positioning

**Missing**:
- Helper function to set listener from camera matrix
- Quaternion rotation support

---

### 4.11 ChannelSplitter/Merger Best Practices

**Current Implementation**: Basic (Lines 829-849)

**Missing**:
- No validation for channel count (must be ≤ 32)
- No usage examples in comments
- No multi-channel routing utilities

---

### 4.12 AudioBuffer Best Practices

**Current Implementation**: INCOMPLETE (Lines 851-899)

**Critical Missing**:
1. **No data access** - `getChannelData()` essential for buffer manipulation
2. **No buffer copying** - `copyToChannel()`, `copyFromChannel()`
3. **No buffer generation utilities** - sine wave, noise, etc.

---

### 4.13 PeriodicWave Best Practices

**Current Implementation**: HARDCODED (Lines 901-913)

**Issues**:
- Only creates one fixed waveform
- No support for custom harmonics
- No array input support

**Must Fix**:
```javascript
function createPeriodicWaveFromArrays(audioContext, realArray, imagArray, disableNormalization) {
    try {
        const real = new Float32Array(realArray);
        const imag = new Float32Array(imagArray);
        const constraints = { disableNormalization: disableNormalization || false };
        return { $: 'Ok', a: audioContext.createPeriodicWave(real, imag, constraints) };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidStateError', a: e.message } };
    }
}
```

---

### 4.14 OfflineAudioContext Best Practices

**Current Implementation**: INCOMPLETE (Lines 915-936)

**Critical Missing**:
1. **No Promise handling** - `startRendering()` returns Promise
2. **No suspend/resume** - Important for progress tracking
3. **No length validation**

---

### 4.15 AudioParam Automation Best Practices

**Current Implementation**: Good (Lines 938-1025)

**Strengths**:
- ✅ Most automation methods covered
- ✅ Fallback for `cancelAndHoldAtTime`

**Missing**:
- `setValueCurveAtTime()` - Important for complex automation
- Parameter range/default value getters

---

## 5. Missing Testing Infrastructure

### 5.1 Unit Test Gaps

**No tests found for**:
- All error handling branches
- All Result return paths
- Edge cases (negative frequencies, out-of-range parameters)
- Browser compatibility fallbacks

### 5.2 Integration Test Gaps

**No tests for**:
- Complete audio pipeline (source → effects → destination)
- Audio timing precision
- Memory leaks (node cleanup)
- Multiple context scenarios

### 5.3 Recommended Test Structure

```javascript
// test/audio-ffi-unit.test.js
describe('AudioFFI Error Handling', () => {
    test('createOscillator with invalid frequency returns RangeError', () => {
        const result = createOscillator(ctx, -100, 'sine');
        expect(result.$).toBe('Err');
        expect(result.a.$).toBe('RangeError');
    });

    test('startOscillator with negative time returns RangeError', () => {
        const result = startOscillator(osc, -1);
        expect(result.$).toBe('Err');
    });
});
```

---

## 6. Documentation Gaps

### 6.1 Missing Function Examples

**Current**: Most functions lack usage examples in JSDoc
**Needed**: Code examples for each major node type

Example:
```javascript
/**
 * Create gain node for volume control
 * @name createGainNode
 * @canopy-type Initialized AudioContext -> Float -> Result Capability.CapabilityError GainNode
 *
 * @example
 * ```canopy
 * case createGainNode ctx 0.5 of
 *     Ok gainNode -> -- Use gain node
 *     Err error -> -- Handle error
 * ```
 */
```

### 6.2 Missing Architecture Documentation

**Needed**:
- Audio graph connection patterns
- Common effect chains
- Performance considerations
- Browser compatibility matrix

---

## 7. Performance Considerations

### 7.1 Memory Management Issues

**Current**: No automatic node cleanup
**Issue**: Disconnected nodes may not be garbage collected

**Recommendation**:
```javascript
function cleanupNode(node) {
    try {
        node.disconnect();
        // Clear references
        if (node.buffer) node.buffer = null;
        if (node.curve) node.curve = null;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidStateError', a: e.message } };
    }
}
```

### 7.2 Audio Graph Optimization

**Missing**:
- Node reuse strategies
- Effect chain templates
- Batch connection operations

---

## 8. Security Considerations

### 8.1 Current Security Measures

✅ **Good**:
- User activation validation for context creation
- Parameter range validation (frequency, gain, etc.)
- Error handling prevents crashes

### 8.2 Missing Security Features

❌ **Needed**:
- Maximum node count limits (prevent DoS)
- Audio buffer size limits (prevent memory exhaustion)
- Rate limiting for node creation

**Recommendation**:
```javascript
const MAX_NODES = 1000;
let nodeCount = 0;

function createNodeWithLimit(nodeType, createFn) {
    if (nodeCount >= MAX_NODES) {
        return {
            $: 'Err',
            a: { $: 'QuotaExceededError', a: 'Maximum node count exceeded' }
        };
    }
    nodeCount++;
    return createFn();
}
```

---

## 9. Browser Compatibility

### 9.1 Current Compatibility Handling

✅ **Good**:
- Webkit prefix fallback for AudioContext
- Legacy API fallbacks for PannerNode/AudioListener
- `cancelAndHoldAtTime` fallback

### 9.2 Missing Compatibility

❌ **Needed**:
- Safari AudioWorklet detection
- iOS AudioContext restrictions
- Firefox-specific quirks

---

## 10. Priority Implementation Roadmap

### Phase 1: Critical Missing Features (Week 1-2)
1. ✅ **decodeAudioData** - Essential for loading audio files
2. ✅ **Full analyzer data arrays** - Fix current implementation
3. ✅ **Convolver buffer setting** - Make convolver usable
4. ✅ **WaveShaper curve setting** - Make waveshaper usable
5. ✅ **MediaStreamSource/Destination** - Recording and mic input

### Phase 2: Audio Buffer Operations (Week 3)
6. ✅ **getChannelData/copyToChannel** - Buffer manipulation
7. ✅ **Buffer utilities** - Clone, generate waveforms
8. ✅ **Custom PeriodicWave** - Fix hardcoded implementation

### Phase 3: Advanced Features (Week 4)
9. ✅ **AudioWorkletNode** - Modern audio processing
10. ✅ **IIRFilterNode** - Advanced filtering
11. ✅ **ConstantSourceNode** - Modulation sources
12. ✅ **MediaElementSource** - HTML5 audio integration

### Phase 4: Completion (Week 5)
13. ✅ **AudioNode channel configuration** - Advanced routing
14. ✅ **Context latency properties** - Pro audio monitoring
15. ✅ **Complete error handling** - All functions return Result
16. ✅ **Comprehensive tests** - Unit, integration, browser compat

---

## 11. Recommended File Structure

```
examples/audio-ffi/
├── external/
│   ├── audio-core.js           # Context, basic nodes (current audio.js split)
│   ├── audio-effects.js        # All effect nodes
│   ├── audio-analysis.js       # Analyzer, PeriodicWave
│   ├── audio-spatial.js        # Panner, Listener
│   ├── audio-buffer.js         # Buffer operations
│   ├── audio-advanced.js       # AudioWorklet, MediaStream, IIR
│   └── audio-utils.js          # Utilities, presets, helpers
├── src/
│   ├── AudioFFI/
│   │   ├── Core.can           # Basic types and context
│   │   ├── Sources.can        # Oscillator, BufferSource
│   │   ├── Effects.can        # Gain, Filter, Delay, etc.
│   │   ├── Analysis.can       # Analyzer node
│   │   ├── Spatial.can        # Panner, Listener
│   │   ├── Buffer.can         # Buffer operations
│   │   └── Advanced.can       # AudioWorklet, MediaStream
│   └── Main.can
└── test/
    ├── unit/                  # Unit tests
    ├── integration/           # Integration tests
    └── browser-compat/        # Browser compatibility tests
```

---

## 12. Conclusion

### Current State Assessment

**Strengths**:
- Solid foundation with 133+ functions implemented
- Good error handling patterns with Result types
- Comprehensive spatial audio support
- Well-structured simplified interface

**Critical Gaps**:
- **11+ missing node types** (AudioWorklet, MediaStream, IIR, etc.)
- **Incomplete implementations** (Convolver, WaveShaper, AnalyserNode)
- **No audio decoding** (can't load MP3/AAC files)
- **Limited buffer operations** (can't manipulate audio data)
- **JSDoc type issues** (Result type not properly namespaced)

### Implementation Effort Estimate

- **Phase 1 (Critical)**: 40-60 hours
- **Phase 2 (Buffer Ops)**: 20-30 hours
- **Phase 3 (Advanced)**: 40-50 hours
- **Phase 4 (Polish)**: 30-40 hours
- **Total**: 130-180 hours (4-5 weeks full-time)

### Risk Assessment

**High Risk**:
- AudioWorklet requires async/await support in FFI
- Promise-based functions (decodeAudioData, offline rendering)
- Browser compatibility testing across platforms

**Medium Risk**:
- Array/TypedArray marshalling performance
- Memory management for large buffers
- Safari iOS AudioContext restrictions

**Low Risk**:
- Basic node implementations
- JSDoc fixes
- Additional setters/getters

---

## 13. Next Steps for Implementation Team

1. **Review this analysis** with team leads
2. **Prioritize features** based on project needs
3. **Assign ownership** for each phase
4. **Set up testing infrastructure** before implementing
5. **Document decisions** in architecture docs
6. **Create tracking issues** for each missing feature
7. **Establish PR review process** for audio FFI changes

---

**End of Comprehensive Analysis Report**

*Generated by Hive Mind Research Agent*
*Repository: /home/quinten/fh/canopy*
*Analysis Date: 2025-10-22*
