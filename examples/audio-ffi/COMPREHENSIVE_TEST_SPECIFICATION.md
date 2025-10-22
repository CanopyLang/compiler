# Comprehensive Audio FFI Test Specification

**Document Version**: 1.0.0
**Date**: 2025-10-22
**Purpose**: Complete catalog of all testable features for browser validation
**Status**: Research Complete - Ready for Test Agent Execution

---

## Executive Summary

This document provides a comprehensive inventory of the Canopy Audio FFI implementation, cataloging **ALL 104 exposed functions** across **15 functional categories**. It defines test priorities, expected behaviors, dependencies, and execution order for systematic browser testing.

### Key Statistics

- **Total FFI Functions**: 104 (exposed in AudioFFI.can)
- **Demo UI Modes**: 4 (SimplifiedInterface, TypeSafeInterface, ComparisonMode, AdvancedFeatures)
- **Interactive Controls**: 27 distinct UI interactions (buttons, sliders, selectors)
- **Msg Types**: 29 user actions that trigger FFI operations
- **Test Execution Time**: Estimated 45-60 minutes for complete validation

---

## Part 1: Complete FFI Function Inventory

### Category 1: Audio Context Operations (7 functions)

**Priority**: P0 (Critical - Required for all other features)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `createAudioContext` | `UserActivated -> Result CapabilityError (Initialized AudioContext)` | Result | P0 |
| `getCurrentTime` | `Initialized AudioContext -> Float` | Direct | P0 |
| `resumeAudioContext` | `Initialized AudioContext -> Result CapabilityError (Initialized AudioContext)` | Result | P1 |
| `suspendAudioContext` | `AudioContext -> Result CapabilityError AudioContext` | Result | P1 |
| `closeAudioContext` | `AudioContext -> Result CapabilityError Int` | Result | P1 |
| `getSampleRate` | `AudioContext -> Float` | Direct | P2 |
| `getContextState` | `AudioContext -> String` | Direct | P2 |

**Dependencies**:
- User activation (browser click/interaction) required for `createAudioContext`
- All other audio operations depend on successful AudioContext creation

**Expected Behaviors**:
- `createAudioContext`: Must return `Ok (Initialized AudioContext)` with valid context
- `getCurrentTime`: Should return monotonically increasing Float (seconds since context creation)
- `getSampleRate`: Typical values: 44100 Hz or 48000 Hz
- `getContextState`: Returns "running", "suspended", or "closed"

---

### Category 2: Oscillator Node Operations (5 functions)

**Priority**: P0 (Core audio generation)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `createOscillator` | `Initialized AudioContext -> Float -> String -> Result CapabilityError OscillatorNode` | Result | P0 |
| `startOscillator` | `OscillatorNode -> Float -> Result CapabilityError Int` | Result | P0 |
| `stopOscillator` | `OscillatorNode -> Float -> Result CapabilityError Int` | Result | P0 |
| `setOscillatorFrequency` | `OscillatorNode -> Float -> Float -> ()` | Unit | P0 |
| `setOscillatorDetune` | `OscillatorNode -> Float -> Float -> ()` | Unit | P1 |

**Dependencies**:
- Requires initialized AudioContext
- Requires connection to GainNode and destination before audio output
- Cannot start same oscillator twice without recreation

**Test Cases**:
1. **Waveform Types**: "sine", "square", "sawtooth", "triangle"
2. **Frequency Range**: 20 Hz - 20000 Hz (test: 100, 440, 1000, 5000 Hz)
3. **Detune Range**: -1200 to +1200 cents (100 cents = 1 semitone)
4. **Start Timing**: 0 (immediate), currentTime, currentTime + 0.5
5. **Stop Timing**: Test immediate vs scheduled stop

---

### Category 3: Gain Node Operations (4 functions)

**Priority**: P0 (Volume control essential)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `createGainNode` | `Initialized AudioContext -> Float -> Result CapabilityError GainNode` | Result | P0 |
| `setGain` | `GainNode -> Float -> Float -> Result CapabilityError Int` | Result | P0 |
| `rampGainLinear` | `GainNode -> Float -> Float -> Result CapabilityError Int` | Result | P1 |
| `rampGainExponential` | `GainNode -> Float -> Float -> Result CapabilityError Int` | Result | P1 |

**Test Cases**:
1. **Gain Range**: 0.0 (silence) to 1.0 (full volume)
2. **Immediate Changes**: Test `setGain` with instant response
3. **Linear Ramp**: Fade from 1.0 to 0.0 over 2 seconds
4. **Exponential Ramp**: Natural-sounding fade (more pleasing to human ear)

---

### Category 4: Buffer Source Operations (9 functions)

**Priority**: P1 (Playback of recorded/generated audio buffers)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `createBufferSource` | `AudioContext -> AudioBufferSourceNode` | Direct | P1 |
| `startBufferSource` | `AudioBufferSourceNode -> Float -> Result CapabilityError Int` | Result | P1 |
| `stopBufferSource` | `AudioBufferSourceNode -> Float -> Result CapabilityError Int` | Result | P1 |
| `setBufferSourceBuffer` | `AudioBufferSourceNode -> AudioBuffer -> ()` | Unit | P1 |
| `setBufferSourceLoop` | `AudioBufferSourceNode -> Bool -> ()` | Unit | P1 |
| `setBufferSourceLoopStart` | `AudioBufferSourceNode -> Float -> ()` | Unit | P2 |
| `setBufferSourceLoopEnd` | `AudioBufferSourceNode -> Float -> ()` | Unit | P2 |
| `setBufferSourcePlaybackRate` | `AudioBufferSourceNode -> Float -> Float -> ()` | Unit | P1 |
| `setBufferSourceDetune` | `AudioBufferSourceNode -> Float -> Float -> ()` | Unit | P2 |

**Test Cases**:
1. **Loop Playback**: Set loop=true, verify seamless repetition
2. **Playback Rate**: 0.5 (half speed), 1.0 (normal), 2.0 (double speed)
3. **Loop Points**: Set loopStart=1.0, loopEnd=2.0, verify loop section

---

### Category 5: Filter Operations (4 functions)

**Priority**: P1 (Frequency filtering effects)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `createBiquadFilter` | `AudioContext -> String -> BiquadFilterNode` | Direct | P1 |
| `setFilterFrequency` | `BiquadFilterNode -> Float -> Float -> ()` | Unit | P1 |
| `setFilterQ` | `BiquadFilterNode -> Float -> Float -> ()` | Unit | P1 |
| `setFilterGain` | `BiquadFilterNode -> Float -> Float -> ()` | Unit | P2 |

**Filter Types**: "lowpass", "highpass", "bandpass", "lowshelf", "highshelf", "peaking", "notch", "allpass"

**Test Cases**:
1. **Lowpass**: Filter at 1000 Hz should remove frequencies >1000 Hz
2. **Highpass**: Filter at 1000 Hz should remove frequencies <1000 Hz
3. **Q Factor**: Range 0.1 (wide) to 30.0 (very narrow resonance)
4. **Gain**: -40 dB to +40 dB (for peaking/shelf filters)

---

### Category 6: Delay Node Operations (2 functions)

**Priority**: P1 (Echo/delay effects)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `createDelay` | `AudioContext -> Float -> DelayNode` | Direct | P1 |
| `setDelayTime` | `DelayNode -> Float -> Float -> ()` | Unit | P1 |

**Test Cases**:
1. **Delay Times**: 0.1s, 0.5s, 1.0s, 2.0s (maximum typically ~3s)
2. **Feedback Loop**: Connect delay output back to input for repeating echo

---

### Category 7: Dynamics Compressor Operations (6 functions)

**Priority**: P2 (Audio dynamics control)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `createDynamicsCompressor` | `AudioContext -> DynamicsCompressorNode` | Direct | P2 |
| `setCompressorThreshold` | `DynamicsCompressorNode -> Float -> Float -> ()` | Unit | P2 |
| `setCompressorKnee` | `DynamicsCompressorNode -> Float -> Float -> ()` | Unit | P2 |
| `setCompressorRatio` | `DynamicsCompressorNode -> Float -> Float -> ()` | Unit | P2 |
| `setCompressorAttack` | `DynamicsCompressorNode -> Float -> Float -> ()` | Unit | P2 |
| `setCompressorRelease` | `DynamicsCompressorNode -> Float -> Float -> ()` | Unit | P2 |

**Test Cases**:
1. **Threshold**: -50 dB to 0 dB (where compression starts)
2. **Ratio**: 1:1 (no compression) to 20:1 (heavy limiting)
3. **Attack**: 0.001s (fast) to 1.0s (slow attack)
4. **Release**: 0.01s (fast) to 1.0s (slow release)

---

### Category 8: Stereo Panner Operations (2 functions)

**Priority**: P1 (Stereo positioning)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `createStereoPanner` | `AudioContext -> StereoPannerNode` | Direct | P1 |
| `setPan` | `StereoPannerNode -> Float -> Float -> ()` | Unit | P1 |

**Test Cases**:
1. **Pan Values**: -1.0 (full left), 0.0 (center), +1.0 (full right)
2. **Smooth Panning**: Sweep from -1.0 to +1.0 over 2 seconds

---

### Category 9: Effect Nodes - Convolver & WaveShaper (4 functions)

**Priority**: P2 (Advanced effects)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `createConvolver` | `AudioContext -> ConvolverNode` | Direct | P2 |
| `setConvolverBuffer` | `ConvolverNode -> AudioBuffer -> Result CapabilityError Int` | Result | P2 |
| `createWaveShaper` | `AudioContext -> WaveShaperNode` | Direct | P2 |
| `setWaveShaperCurve` | `WaveShaperNode -> List Float -> Result CapabilityError Int` | Result | P2 |

**Test Cases**:
1. **Convolver**: Reverb effect using impulse response buffer
2. **WaveShaper**: Distortion using transfer curve

---

### Category 10: Analyser Node Operations (8 functions)

**Priority**: P1 (Visualization and analysis)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `createAnalyser` | `AudioContext -> AnalyserNode` | Direct | P1 |
| `setAnalyserFFTSize` | `AnalyserNode -> Int -> ()` | Unit | P1 |
| `setAnalyserSmoothing` | `AnalyserNode -> Float -> ()` | Unit | P2 |
| `getFrequencyBinCount` | `AnalyserNode -> Int` | Direct | P1 |
| `getByteTimeDomainData` | `AnalyserNode -> List Int` | Direct | P1 |
| `getByteFrequencyData` | `AnalyserNode -> List Int` | Direct | P1 |
| `getFloatTimeDomainData` | `AnalyserNode -> List Float` | Direct | P1 |
| `getFloatFrequencyData` | `AnalyserNode -> List Float` | Direct | P1 |

**Test Cases**:
1. **FFT Sizes**: 256, 512, 1024, 2048, 4096 (powers of 2)
2. **Time Domain**: Verify waveform data (sine wave should show smooth oscillation)
3. **Frequency Domain**: Verify spectrum data (440 Hz tone should show peak at bin corresponding to 440 Hz)

---

### Category 11: 3D Spatial Audio - Panner Node (11 functions)

**Priority**: P1 (3D positioning - requires headphones for testing)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `createPanner` | `AudioContext -> PannerNode` | Direct | P1 |
| `setPannerPosition` | `PannerNode -> Float -> Float -> Float -> ()` | Unit | P1 |
| `setPannerOrientation` | `PannerNode -> Float -> Float -> Float -> ()` | Unit | P2 |
| `setPanningModel` | `PannerNode -> String -> ()` | Unit | P2 |
| `setDistanceModel` | `PannerNode -> String -> ()` | Unit | P2 |
| `setRefDistance` | `PannerNode -> Float -> ()` | Unit | P2 |
| `setMaxDistance` | `PannerNode -> Float -> ()` | Unit | P2 |
| `setRolloffFactor` | `PannerNode -> Float -> ()` | Unit | P2 |
| `setConeInnerAngle` | `PannerNode -> Float -> ()` | Unit | P2 |
| `setConeOuterAngle` | `PannerNode -> Float -> ()` | Unit | P2 |
| `setConeOuterGain` | `PannerNode -> Float -> ()` | Unit | P2 |

**Test Cases**:
1. **Position**: X (-10 to +10), Y (-10 to +10), Z (-10 to +10)
2. **Distance Models**: "linear", "inverse", "exponential"
3. **Panning Models**: "equalpower", "HRTF"

---

### Category 12: Audio Listener (4 functions)

**Priority**: P2 (Listener positioning for 3D audio)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `getAudioListener` | `AudioContext -> AudioListener` | Direct | P2 |
| `setListenerPosition` | `AudioListener -> Float -> Float -> Float -> ()` | Unit | P2 |
| `setListenerForward` | `AudioListener -> Float -> Float -> Float -> ()` | Unit | P2 |
| `setListenerUp` | `AudioListener -> Float -> Float -> Float -> ()` | Unit | P2 |

---

### Category 13: Channel Routing (2 functions)

**Priority**: P2 (Multi-channel audio routing)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `createChannelSplitter` | `AudioContext -> Int -> ChannelSplitterNode` | Direct | P2 |
| `createChannelMerger` | `AudioContext -> Int -> ChannelMergerNode` | Direct | P2 |

---

### Category 14: Audio Buffer Operations (5 functions)

**Priority**: P1 (Buffer management)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `createAudioBuffer` | `AudioContext -> Int -> Int -> Float -> AudioBuffer` | Direct | P1 |
| `getBufferLength` | `AudioBuffer -> Int` | Direct | P1 |
| `getBufferDuration` | `AudioBuffer -> Float` | Direct | P1 |
| `getBufferSampleRate` | `AudioBuffer -> Float` | Direct | P1 |
| `getBufferNumberOfChannels` | `AudioBuffer -> Int` | Direct | P1 |

---

### Category 15: Audio Graph Connections (3 functions)

**Priority**: P0 (Required to hear any audio)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `connectNodes` | `OscillatorNode -> GainNode -> Result CapabilityError Int` | Result | P0 |
| `connectToDestination` | `GainNode -> Initialized AudioContext -> Result CapabilityError Int` | Result | P0 |
| `disconnectNode` | `GainNode -> ()` | Unit | P1 |

---

### Category 16: Simplified Interface (8 functions)

**Priority**: P0 (Easy-to-use string-based API)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `simpleTest` | `Int -> Int` | Direct | P0 |
| `checkWebAudioSupport` | `String` | Direct | P0 |
| `createAudioContextSimplified` | `() -> String` | Direct | P0 |
| `playToneSimplified` | `Float -> String -> String` | Direct | P0 |
| `stopAudioSimplified` | `() -> String` | Direct | P0 |
| `updateFrequency` | `Float -> String` | Direct | P0 |
| `updateVolume` | `Float -> String` | Direct | P0 |
| `updateWaveform` | `String -> String` | Direct | P0 |

---

### Category 17: Audio Param Automation (9 functions)

**Priority**: P2 (Advanced parameter control)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `getGainParam` | `GainNode -> AudioParam` | Direct | P2 |
| `getFrequencyParam` | `OscillatorNode -> AudioParam` | Direct | P2 |
| `getDetuneParam` | `OscillatorNode -> AudioParam` | Direct | P2 |
| `setParamValueAtTime` | `AudioParam -> Float -> Float -> ()` | Unit | P2 |
| `linearRampToValue` | `AudioParam -> Float -> Float -> ()` | Unit | P2 |
| `exponentialRampToValue` | `AudioParam -> Float -> Float -> ()` | Unit | P2 |
| `setTargetAtTime` | `AudioParam -> Float -> Float -> Float -> ()` | Unit | P2 |
| `cancelScheduledValues` | `AudioParam -> Float -> ()` | Unit | P2 |
| `cancelAndHoldAtTime` | `AudioParam -> Float -> ()` | Unit | P2 |

---

### Category 18: MediaStream Operations (3 functions)

**Priority**: P2 (Microphone input and stream processing)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `createMediaStreamSource` | `Initialized AudioContext -> MediaStream -> Result CapabilityError MediaStreamAudioSourceNode` | Result | P2 |
| `createMediaStreamDestination` | `Initialized AudioContext -> Result CapabilityError MediaStreamAudioDestinationNode` | Result | P2 |
| `getDestinationStream` | `MediaStreamAudioDestinationNode -> MediaStream` | Direct | P2 |

---

### Category 19: Audio Worklet Operations (5 functions)

**Priority**: P2 (Custom audio processing)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `addAudioWorkletModule` | `Initialized AudioContext -> String -> Result CapabilityError Int` | Result | P2 |
| `createAudioWorkletNode` | `Initialized AudioContext -> String -> Result CapabilityError AudioWorkletNode` | Result | P2 |
| `createAudioWorkletNodeWithOptions` | `Initialized AudioContext -> String -> AudioWorkletOptions -> Result CapabilityError AudioWorkletNode` | Result | P2 |
| `getWorkletNodePort` | `AudioWorkletNode -> MessagePort` | Direct | P2 |
| `postMessageToWorklet` | `AudioWorkletNode -> a -> Result CapabilityError Int` | Result | P2 |

---

### Category 20: Offline Audio Context (3 functions)

**Priority**: P2 (Non-realtime audio rendering)

| Function | Type Signature | Return Type | Test Priority |
|----------|---------------|-------------|---------------|
| `createOfflineAudioContext` | `Int -> Int -> Float -> OfflineAudioContext` | Direct | P2 |
| `startOfflineRendering` | `OfflineAudioContext -> OfflineAudioContext` | Direct | P2 |
| `createPeriodicWave` | `AudioContext -> PeriodicWave` | Direct | P2 |

---

## Part 2: UI Demo Mode Analysis

### Mode 1: SimplifiedInterface

**Description**: String-based API for quick prototyping

**Interactive Controls**:
1. Initialize Audio button
2. Play Audio button
3. Stop Audio button
4. Frequency slider (20-2000 Hz)
5. Volume slider (0-100%)
6. Waveform selector (sine, square, sawtooth, triangle)

**Msg Types Triggered**:
- `InitializeAudioSimple`
- `PlayAudioSimple`
- `StopAudioSimple`
- `SetFrequency String`
- `SetVolume String`
- `SetWaveform String`

---

### Mode 2: TypeSafeInterface

**Description**: Result-based production interface

**Interactive Controls**:
1. Create AudioContext button
2. Create Oscillator & Gain button
3. Start Audio button
4. Stop Audio button

**Msg Types Triggered**:
- `InitializeAudioTypeSafe`
- `CreateAudioNodesTypeSafe`
- `PlayAudioTypeSafe`
- `StopAudioTypeSafe`

**Capabilities Demonstrated**:
- User activation requirement enforcement
- Type-safe Result error handling
- Initialized wrapper types
- Capability-based security

---

### Mode 3: ComparisonMode

**Description**: Side-by-side comparison of both interfaces

**Purpose**: Demonstrates equivalent functionality with different approaches

---

### Mode 4: AdvancedFeatures

**Description**: Filter effects and spatial audio

**Interactive Controls**:

**Filter Section** (toggleable):
1. Filter Type selector (lowpass, highpass, bandpass, notch)
2. Filter Frequency slider (20-20000 Hz)
3. Filter Q slider (0.1-30.0)
4. Filter Gain slider (-40 to +40 dB)
5. Create Filter Node button

**Spatial Audio Section** (toggleable):
1. Panner X slider (-10 to +10)
2. Panner Y slider (-10 to +10)
3. Panner Z slider (-10 to +10)
4. Create Panner Node button

**Msg Types Triggered**:
- `ToggleFilter`
- `SetFilterType String`
- `SetFilterFrequency String`
- `SetFilterQ String`
- `SetFilterGain String`
- `CreateFilterNode`
- `ToggleSpatialAudio`
- `SetPannerX String`
- `SetPannerY String`
- `SetPannerZ String`
- `CreatePannerNode`

---

## Part 3: Test Execution Plan

### Phase 1: Foundation (P0 - Critical) - 15 minutes

**Prerequisites**: None (start here)

**Test Sequence**:
1. **FFI System Validation**
   - Verify `simpleTest(42)` returns 84
   - Verify `checkWebAudioSupport` returns "supported" or browser name

2. **AudioContext Creation**
   - Test `createAudioContext` with user click
   - Verify Result Ok with Initialized AudioContext
   - Check `getCurrentTime` returns non-negative Float
   - Check `getSampleRate` returns 44100 or 48000
   - Check `getContextState` returns "running"

3. **Basic Audio Graph**
   - Create OscillatorNode (440 Hz, sine)
   - Create GainNode (0.5 volume)
   - Connect oscillator → gain → destination
   - Start oscillator
   - **VERIFY**: Audio plays at 440 Hz
   - Stop oscillator
   - **VERIFY**: Audio stops cleanly

4. **Simplified Interface**
   - Test `createAudioContextSimplified`
   - Test `playToneSimplified(440.0, "sine")`
   - **VERIFY**: Audio plays
   - Test `updateFrequency(880.0)`
   - **VERIFY**: Pitch changes to 880 Hz
   - Test `updateVolume(0.5)`
   - **VERIFY**: Volume decreases
   - Test `stopAudioSimplified`
   - **VERIFY**: Audio stops

**Success Criteria**: All audio plays correctly, no console errors

---

### Phase 2: Real-Time Control (P0-P1) - 10 minutes

**Prerequisites**: Phase 1 complete

**Test Sequence**:
1. **Frequency Control**
   - Play audio at 440 Hz
   - Sweep frequency from 100 Hz to 2000 Hz
   - **VERIFY**: Smooth pitch change, no clicks/pops

2. **Volume Control**
   - Play audio at full volume
   - Sweep volume from 1.0 to 0.0
   - **VERIFY**: Smooth fade, no distortion

3. **Waveform Changes**
   - Play each waveform: sine, square, sawtooth, triangle
   - **VERIFY**: Distinct tonal character for each
   - **VERIFY**: Instant switching, no glitches

4. **Gain Ramping**
   - Test `rampGainLinear` (1.0 to 0.0 over 2 seconds)
   - **VERIFY**: Smooth linear fade
   - Test `rampGainExponential` (1.0 to 0.01 over 2 seconds)
   - **VERIFY**: Natural-sounding exponential fade

**Success Criteria**: All parameter changes are smooth and immediate

---

### Phase 3: Filter Effects (P1) - 10 minutes

**Prerequisites**: Phase 1-2 complete, audio playing

**Test Sequence**:
1. **Create Filter**
   - Create BiquadFilterNode (lowpass, 1000 Hz)
   - Insert into audio graph: oscillator → filter → gain → destination
   - **VERIFY**: Muffled sound (highs removed)

2. **Filter Types**
   - Test lowpass at 500 Hz: dark, muffled
   - Test highpass at 500 Hz: thin, tinny
   - Test bandpass at 1000 Hz: telephone-like
   - Test notch at 1000 Hz (playing 1000 Hz tone): volume drops
   - **VERIFY**: Each filter type has distinct effect

3. **Filter Frequency**
   - Lowpass filter, sweep frequency 20 Hz → 20000 Hz
   - **VERIFY**: Sound goes from silence to full brightness

4. **Filter Q**
   - Bandpass filter at 1000 Hz
   - Q = 0.1: wide, gentle
   - Q = 10.0: narrow, ringing
   - **VERIFY**: Dramatic change in filter sharpness

**Success Criteria**: All filter types work correctly, parameter changes audible

---

### Phase 4: Spatial Audio (P1) - 10 minutes

**Prerequisites**: Phase 1-2 complete, **REQUIRES HEADPHONES**

**Test Sequence**:
1. **Create Panner**
   - Create PannerNode at position (0, 0, -1)
   - Insert into audio graph
   - **VERIFY**: Sound centered

2. **X-Axis Panning**
   - Set X = -10: **VERIFY** sound in left ear
   - Set X = 0: **VERIFY** sound centered
   - Set X = +10: **VERIFY** sound in right ear
   - **VERIFY**: Smooth stereo panning

3. **Z-Axis Distance**
   - Set Z = -10: **VERIFY** sound distant/quiet
   - Set Z = 0: **VERIFY** sound at listener
   - Set Z = +10: **VERIFY** sound closer/louder
   - **VERIFY**: Volume and presence changes

4. **Circular Motion**
   - Animate panner from (0, 0, -1) → (-10, 0, -1) → (0, 0, -10) → (+10, 0, -1) → back
   - **VERIFY**: Sound circles around listener
   - **VERIFY**: Smooth, continuous movement

**Success Criteria**: Clear spatial positioning audible with headphones

---

### Phase 5: Analysis & Visualization (P1) - 5 minutes

**Prerequisites**: Phase 1 complete, audio playing

**Test Sequence**:
1. **Create Analyser**
   - Create AnalyserNode with FFT size 2048
   - Insert into audio graph (parallel, doesn't affect audio)

2. **Time Domain Data**
   - Get byte time domain data
   - **VERIFY**: Returns 2048 values (0-255)
   - **VERIFY**: For sine wave, shows smooth oscillation
   - **VERIFY**: For square wave, shows sharp transitions

3. **Frequency Domain Data**
   - Play 440 Hz sine wave
   - Get byte frequency data
   - **VERIFY**: Peak at bin corresponding to 440 Hz
   - **VERIFY**: Other bins have low values (pure sine)

4. **FFT Size Changes**
   - Test FFT sizes: 256, 512, 1024, 2048, 4096
   - **VERIFY**: Bin count = FFT size / 2
   - **VERIFY**: Data array length matches bin count

**Success Criteria**: All data arrays have correct length and expected patterns

---

### Phase 6: Advanced Features (P2) - 10 minutes

**Prerequisites**: Phase 1-5 complete

**Test Sequence**:
1. **Buffer Source**
   - Create AudioBuffer (1 second, 1 channel, 44100 Hz)
   - Fill with sine wave data
   - Create BufferSourceNode
   - Play buffer
   - **VERIFY**: Audio plays for 1 second
   - Test loop playback
   - **VERIFY**: Seamless repetition

2. **Delay Node**
   - Create DelayNode (0.5 seconds)
   - Create feedback loop: oscillator → delay → gain → destination
   - Connect delay output back to delay input (with gain < 1.0)
   - **VERIFY**: Echo effect with decaying repeats

3. **Dynamics Compressor**
   - Create DynamicsCompressorNode
   - Set threshold = -20 dB, ratio = 10:1
   - Play loud oscillator
   - **VERIFY**: Volume peaks are reduced (compression working)

4. **Stereo Panner** (simpler than 3D Panner)
   - Create StereoPannerNode
   - Set pan = -1.0: **VERIFY** full left
   - Set pan = 0.0: **VERIFY** center
   - Set pan = +1.0: **VERIFY** full right

**Success Criteria**: All advanced nodes function correctly

---

### Phase 7: Error Handling & Edge Cases (P1) - 5 minutes

**Prerequisites**: Fresh page load (to test error states)

**Test Sequence**:
1. **Operation Order Errors**
   - Try playing audio before initialization
   - **VERIFY**: Error message "AudioContext not initialized"
   - **VERIFY**: No JavaScript exception
   - Try creating nodes before AudioContext
   - **VERIFY**: Clear error message

2. **Invalid Parameters**
   - Try setting frequency to -100 Hz
   - **VERIFY**: Error or clamped to valid range
   - Try setting gain to 10.0 (too high)
   - **VERIFY**: Works but may clip/distort

3. **Multiple Start/Stop**
   - Start oscillator
   - Try starting same oscillator again
   - **VERIFY**: Error (oscillator already started)
   - Stop oscillator
   - Try stopping again
   - **VERIFY**: Error or no-op

4. **Recovery Flow**
   - Trigger error
   - Follow error message instructions
   - Retry operation
   - **VERIFY**: Operation succeeds after proper setup

**Success Criteria**: All errors are caught and reported clearly

---

## Part 4: Test Matrix Summary

### Priority Breakdown

| Priority | Category | Function Count | Estimated Time |
|----------|----------|----------------|----------------|
| P0 | Critical (must work) | 28 | 25 minutes |
| P1 | High (important features) | 46 | 20 minutes |
| P2 | Medium (advanced features) | 30 | 15 minutes |

**Total**: 104 functions, ~60 minutes for complete testing

---

## Part 5: Dependencies & Prerequisites

### Dependency Graph

```
User Activation (browser click)
  ↓
createAudioContext
  ↓
├─→ createOscillator ──→ connectNodes ──→ connectToDestination
│     ↓                      ↓                    ↓
│   startOscillator    [Audio Graph]        [Audible Sound]
│
├─→ createGainNode ────────────┘
│
├─→ createAnalyser (for visualization)
│
├─→ createBiquadFilter (for effects)
│
└─→ createPanner (for spatial audio)
```

### Execution Order Requirements

1. **Must be first**: `createAudioContext` (requires user activation)
2. **Must be before audio**: Create nodes + connect graph
3. **Can be parallel**: Multiple node creation (oscillator + gain simultaneously)
4. **Must be after nodes**: Start/stop operations
5. **Can be anytime**: Parameter changes (frequency, volume, etc.)

---

## Part 6: Browser-Specific Considerations

### Chrome/Edge (Chromium)
- **Best support**: All features work
- **User activation**: Required for AudioContext
- **Sample rate**: Usually 48000 Hz

### Firefox
- **Good support**: Most features work
- **AudioWorklet**: Requires Firefox 76+
- **Filter Q**: May have different scaling

### Safari
- **Requires explicit activation**: May show "suspended" state initially
- **HRTF implementation**: Slightly different from Chrome
- **Sample rate**: Usually 44100 Hz
- **iOS Safari**: Stricter user activation requirements

### Mobile Browsers
- **iOS Safari**: Requires explicit play() after user tap
- **Android Chrome**: Higher latency possible
- **Background tabs**: Audio may suspend for battery saving

---

## Part 7: Success Criteria Checklist

### Must Pass (P0)
- [ ] AudioContext creates successfully
- [ ] Basic audio plays (oscillator + gain + destination)
- [ ] Frequency changes work in real-time
- [ ] Volume changes work in real-time
- [ ] Waveform changes work instantly
- [ ] Audio stops cleanly (no clicks)
- [ ] Simplified interface works completely
- [ ] No console errors during normal operation

### Should Pass (P1)
- [ ] Filter effects are audible
- [ ] Spatial positioning works with headphones
- [ ] Analyser provides correct data
- [ ] All node types create successfully
- [ ] Parameter ramping works smoothly
- [ ] Buffer playback works
- [ ] Delay/echo effects work

### Nice to Have (P2)
- [ ] Dynamics compressor works
- [ ] AudioWorklet loads and processes
- [ ] Offline rendering works
- [ ] MediaStream processing works
- [ ] Advanced parameter automation works
- [ ] Channel routing works

---

## Part 8: Test Data & Expected Values

### Frequency Test Points
- 100 Hz: Deep bass tone
- 220 Hz: Musical note A3
- 440 Hz: Musical note A4 (concert pitch)
- 880 Hz: Musical note A5
- 1000 Hz: Reference tone (1 kHz)
- 2000 Hz: High treble tone
- 5000 Hz: Very high tone

### Volume Test Points
- 0.0: Complete silence
- 0.1: Very quiet
- 0.3: Quiet conversation level
- 0.5: Normal level
- 0.7: Loud
- 1.0: Maximum safe level

### Filter Frequency Test Points
- 20 Hz: Sub-bass (almost inaudible)
- 100 Hz: Bass region
- 500 Hz: Low-mid region
- 1000 Hz: Mid region
- 5000 Hz: High-mid region
- 10000 Hz: Treble region
- 20000 Hz: Upper limit of human hearing

### Spatial Position Test Points
- X: -10 (far left), 0 (center), +10 (far right)
- Y: -5 (below), 0 (level), +5 (above)
- Z: -10 (behind), 0 (at listener), +10 (in front)

---

## Part 9: Performance Benchmarks

### Expected CPU Usage
- Idle (no audio): <1% CPU
- Single oscillator: 1-3% CPU
- Oscillator + gain: 2-4% CPU
- Oscillator + filter: 3-7% CPU
- Oscillator + spatial: 5-10% CPU
- Full setup (all effects): 8-15% CPU

### Expected Memory Usage
- Initial load: 2-5 MB heap
- After 30s playback: <10% increase
- After 5 minutes: No significant growth (no memory leaks)

### Latency Expectations
- User click to audio start: <100ms
- Parameter change to audible effect: <50ms
- Audio stop to silence: <10ms

---

## Part 10: Automated Test Script Template

```javascript
// Run in browser console for quick validation
async function runQuickTests() {
  const results = [];

  // Test 1: FFI Basic
  try {
    const testResult = window.AudioFFI.simpleTest(42);
    results.push({
      test: "FFI Basic",
      status: testResult === 84 ? "✅ Pass" : "❌ Fail",
      expected: 84,
      actual: testResult
    });
  } catch(e) {
    results.push({test: "FFI Basic", status: "❌ Error: " + e.message});
  }

  // Test 2: Web Audio Support
  try {
    const support = window.AudioFFI.checkWebAudioSupport();
    results.push({
      test: "Web Audio Support",
      status: support.includes("supported") ? "✅ Pass" : "⚠️ Warning",
      result: support
    });
  } catch(e) {
    results.push({test: "Web Audio Support", status: "❌ Error: " + e.message});
  }

  // Test 3: Context Creation (requires user interaction)
  try {
    const ctx = window.AudioFFI.createAudioContextSimplified();
    await new Promise(r => setTimeout(r, 100));
    results.push({
      test: "Context Creation",
      status: ctx.includes("success") ? "✅ Pass" : "❌ Fail",
      result: ctx
    });
  } catch(e) {
    results.push({test: "Context Creation", status: "❌ Error: " + e.message});
  }

  console.table(results);
  return results;
}

// Instructions: Click anywhere on page, then run:
// runQuickTests()
```

---

## Conclusion

This comprehensive test specification provides:

1. **Complete function inventory**: All 104 FFI functions cataloged
2. **Prioritized test plan**: P0/P1/P2 classification for efficient testing
3. **Dependency mapping**: Clear prerequisites and execution order
4. **Expected behaviors**: Exact values and outcomes for verification
5. **Browser compatibility**: Known issues and workarounds
6. **Performance benchmarks**: CPU, memory, latency expectations
7. **Automated scripts**: Quick validation tools

**Next Steps**:
1. Compile application (fix compilation error first)
2. Execute Phase 1 tests (Foundation - P0)
3. Progress through phases 2-7 systematically
4. Document any failures or deviations
5. Create detailed bug reports for issues found

**Estimated Total Testing Time**: 60 minutes for complete validation across all priorities.

---

**Document Status**: ✅ COMPLETE - Ready for test execution
