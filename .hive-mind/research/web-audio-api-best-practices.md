# Web Audio API Best Practices Research
## Implementation Guidelines for Canopy FFI

**Research Date**: 2025-10-22
**Purpose**: Document Web Audio API patterns, gotchas, and best practices for FFI implementation

---

## 1. AudioContext Best Practices

### Context Creation
```javascript
// ✅ GOOD: Handle user activation requirement
function createAudioContext(userActivation) {
    try {
        const ctx = new (window.AudioContext || window.webkitAudioContext)();
        return { $: 'Ok', a: { $: 'Fresh', a: ctx } };
    } catch (e) {
        // Map specific errors
        if (e.name === 'NotAllowedError') {
            return { $: 'Err', a: { $: 'UserActivationRequired', a: e.message } };
        }
        // ... other error types
    }
}
```

### Context State Management
**States**: `suspended`, `running`, `closed`

**Key Rules**:
1. Context starts in `suspended` state (autoplay policy)
2. Must call `resume()` after user gesture
3. Cannot reopen a `closed` context
4. Monitor `onstatechange` event for state transitions

```javascript
// ✅ GOOD: Check state before operations
if (audioContext.state === 'suspended') {
    await audioContext.resume();
}
```

### Performance Tips
- **One context per application** (contexts are heavyweight)
- **Reuse nodes when possible** (except one-shot sources)
- **Close context when done** (frees system resources)
- **Use OfflineAudioContext for non-realtime** (faster processing)

---

## 2. AudioBufferSourceNode Best Practices

### Critical Constraints
⚠️ **ONE-SHOT NODES**: AudioBufferSourceNode can only be started ONCE
- After calling `stop()`, node is permanently unusable
- Must create new node for each playback
- Cannot restart or reuse

```javascript
// ❌ WRONG: Trying to reuse source
const source = audioContext.createBufferSource();
source.buffer = myBuffer;
source.connect(destination);
source.start(0);
source.stop(1);
source.start(2); // ❌ ERROR: InvalidStateError

// ✅ CORRECT: Create new source each time
function playBuffer(buffer, destination) {
    const source = audioContext.createBufferSource();
    source.buffer = buffer;
    source.connect(destination);
    source.start(0);
    return source;
}
```

### Loop Configuration
```javascript
// ✅ GOOD: Configure before starting
source.loop = true;
source.loopStart = 0.5;  // Start loop at 0.5 seconds
source.loopEnd = 2.0;    // End loop at 2.0 seconds
source.start(0);
```

### Playback Rate
```javascript
// Normal playback
source.playbackRate.value = 1.0;

// Double speed
source.playbackRate.value = 2.0;

// Reverse (not supported - workaround: reverse buffer data)
```

### Timing Precision
```javascript
// ✅ GOOD: Use context.currentTime for precise timing
const now = audioContext.currentTime;
source.start(now + 0.1);  // Start in 100ms
source.stop(now + 1.0);   // Stop after 1 second
```

---

## 3. BiquadFilterNode Best Practices

### Filter Types
- `lowpass` - Remove high frequencies (most common)
- `highpass` - Remove low frequencies
- `bandpass` - Keep frequency range, remove rest
- `lowshelf` - Boost/cut below frequency
- `highshelf` - Boost/cut above frequency
- `peaking` - Boost/cut around frequency (EQ)
- `notch` - Remove specific frequency
- `allpass` - Phase shift without amplitude change

### Parameter Ranges
```javascript
// Frequency: 10 Hz to (sampleRate / 2)
filter.frequency.value = 1000; // 1 kHz

// Q (quality factor): 0.0001 to 1000
// Low Q = wide band, High Q = narrow band
filter.Q.value = 1.0; // Default, reasonable

// Gain (for peaking, lowshelf, highshelf): -40 dB to 40 dB
filter.gain.value = 6; // +6 dB boost
```

### Common Patterns
```javascript
// ✅ Standard low-pass filter (smooth/warm sound)
filter.type = 'lowpass';
filter.frequency.value = 2000;
filter.Q.value = 1.0;

// ✅ Resonant filter (synth-style)
filter.type = 'lowpass';
filter.frequency.value = 1000;
filter.Q.value = 10; // High resonance

// ✅ EQ band
filter.type = 'peaking';
filter.frequency.value = 1000;
filter.Q.value = 1.0;
filter.gain.value = 6; // +6 dB at 1kHz
```

### Frequency Response Analysis
```javascript
// ✅ GOOD: Calculate filter response
function getFilterResponse(filter, frequency) {
    const magResponse = new Float32Array(1);
    const phaseResponse = new Float32Array(1);
    const freqArray = new Float32Array([frequency]);
    filter.getFrequencyResponse(freqArray, magResponse, phaseResponse);
    return {
        magnitude: magResponse[0],  // Gain multiplier
        magnitudeDB: 20 * Math.log10(magResponse[0]), // dB
        phase: phaseResponse[0]     // Radians
    };
}
```

---

## 4. DelayNode Best Practices

### Max Delay Time
⚠️ **CRITICAL**: `maxDelayTime` sets buffer size at creation
- Cannot be changed after creation
- Larger values use more memory
- `delayTime` must be ≤ `maxDelayTime`

```javascript
// ✅ GOOD: Set maxDelayTime appropriately
const delay = audioContext.createDelay(2.0); // Max 2 seconds
delay.delayTime.value = 0.5; // Actual delay: 500ms

// ❌ WRONG: Exceeding max delay
delay.delayTime.value = 3.0; // ❌ ERROR: Value too large
```

### Feedback Loops
⚠️ **FEEDBACK DANGER**: Can create extremely loud signals

```javascript
// ✅ SAFE: Use gain to control feedback
const delay = audioContext.createDelay(1.0);
const feedback = audioContext.createGain();
feedback.gain.value = 0.3; // 30% feedback (safe)

input.connect(delay);
delay.connect(output);
delay.connect(feedback);
feedback.connect(delay); // Feedback loop

// ❌ DANGEROUS: 100% feedback or higher
feedback.gain.value = 1.0; // Infinite echo, volume grows!
```

### Common Effects
```javascript
// ✅ Echo effect
delay.delayTime.value = 0.5; // 500ms delay
feedback.gain.value = 0.3;   // 30% feedback

// ✅ Slapback delay (rockabilly)
delay.delayTime.value = 0.1; // 100ms
feedback.gain.value = 0.2;   // Single repeat

// ✅ Chorus (short delay with modulation)
delay.delayTime.value = 0.02; // 20ms
// + LFO modulation on delayTime
```

---

## 5. ConvolverNode Best Practices

### Purpose
Applies **impulse response** convolution
- **Reverb**: Room/hall acoustics
- **Speaker simulation**: Cabinet/amp response
- **Special effects**: Unusual spaces (pipes, caves)

### Critical Setup
⚠️ **MUST SET BUFFER**: ConvolverNode is useless without impulse response

```javascript
// ✅ GOOD: Load and set impulse response
async function setupReverb(audioContext, url) {
    const response = await fetch(url);
    const arrayBuffer = await response.arrayBuffer();
    const impulseResponse = await audioContext.decodeAudioData(arrayBuffer);

    const convolver = audioContext.createConvolver();
    convolver.buffer = impulseResponse;
    convolver.normalize = true; // Normalize volume
    return convolver;
}
```

### Normalize Property
```javascript
// normalize = true (default): Scales impulse response to prevent clipping
convolver.normalize = true;

// normalize = false: Use raw impulse response (for precise emulation)
convolver.normalize = false;
```

### Performance
⚠️ **CPU INTENSIVE**: Convolution is expensive
- Longer impulse responses = more CPU
- Typical reverb: 2-4 seconds at 44.1kHz = ~180,000 samples per channel
- Consider shorter responses for mobile
- Use mono impulse response when possible

### Common Patterns
```javascript
// ✅ Small room reverb
// Use short impulse response (0.5-1 second)

// ✅ Concert hall reverb
// Use long impulse response (2-4 seconds)

// ✅ Plate reverb (vintage effect)
// Use plate reverb impulse response

// ✅ Dry/wet mix
const dry = audioContext.createGain();
const wet = audioContext.createGain();
const output = audioContext.createGain();

input.connect(dry);
input.connect(convolver);
convolver.connect(wet);

dry.gain.value = 0.7;   // 70% dry
wet.gain.value = 0.3;   // 30% wet

dry.connect(output);
wet.connect(output);
```

---

## 6. DynamicsCompressorNode Best Practices

### Parameters Explained

#### Threshold (dB)
Signal level above which compression starts
- Range: -100 to 0 dB
- Typical: -24 to -12 dB
- Lower = more compression

#### Knee (dB)
Smoothness of compression curve
- Range: 0 to 40 dB
- 0 = hard knee (instant compression)
- 30-40 = soft knee (gradual compression)

#### Ratio (x:1)
Amount of compression applied
- Range: 1 to 20
- 1:1 = no compression
- 4:1 = gentle compression
- 10:1+ = heavy compression
- 20:1 = limiting (peak control)

#### Attack (seconds)
How quickly compression starts
- Range: 0 to 1 second
- 0.001-0.003 = fast (drums, transients)
- 0.01-0.03 = medium (vocals)
- 0.05-0.1 = slow (bass, subtle)

#### Release (seconds)
How quickly compression stops
- Range: 0 to 1 second
- 0.05-0.1 = fast (pumping effect)
- 0.15-0.25 = medium (natural)
- 0.3-0.5 = slow (smooth)

### Common Presets
```javascript
// ✅ Gentle compression (mastering)
compressor.threshold.value = -24;
compressor.knee.value = 30;
compressor.ratio.value = 4;
compressor.attack.value = 0.003;
compressor.release.value = 0.25;

// ✅ Vocal compression
compressor.threshold.value = -18;
compressor.knee.value = 12;
compressor.ratio.value = 8;
compressor.attack.value = 0.003;
compressor.release.value = 0.15;

// ✅ Drum bus compression
compressor.threshold.value = -12;
compressor.knee.value = 6;
compressor.ratio.value = 12;
compressor.attack.value = 0.001;
compressor.release.value = 0.1;

// ✅ Limiter (peak control)
compressor.threshold.value = -3;
compressor.knee.value = 0;
compressor.ratio.value = 20;
compressor.attack.value = 0.001;
compressor.release.value = 0.05;
```

### Reduction Metering
```javascript
// ✅ GOOD: Monitor gain reduction for VU meter
function getGainReduction(compressor) {
    return compressor.reduction; // Current reduction in dB (negative)
}

// Example: compressor.reduction = -6.3 (reducing by 6.3 dB)
```

---

## 7. WaveShaperNode Best Practices

### Purpose
Applies **non-linear waveshaping** (distortion)
- Soft clipping
- Hard clipping
- Saturation
- Bit crushing

### Critical Setup
⚠️ **MUST SET CURVE**: WaveShaperNode is useless without transfer curve

```javascript
// ✅ GOOD: Create and apply distortion curve
function makeDistortionCurve(amount) {
    const samples = 44100;
    const curve = new Float32Array(samples);
    const deg = Math.PI / 180;
    const k = amount;

    for (let i = 0; i < samples; i++) {
        const x = (i * 2 / samples) - 1; // -1 to +1
        curve[i] = (3 + k) * x * 20 * deg / (Math.PI + k * Math.abs(x));
    }
    return curve;
}

const shaper = audioContext.createWaveShaper();
shaper.curve = makeDistortionCurve(50);
shaper.oversample = '4x'; // Reduce aliasing
```

### Oversample Options
```javascript
shaper.oversample = 'none'; // No oversampling (fast, aliasing)
shaper.oversample = '2x';   // 2x oversampling (good quality)
shaper.oversample = '4x';   // 4x oversampling (best quality, CPU intensive)
```

### Common Curve Types

#### Soft Clipping (Tube-style)
```javascript
function softClip(amount) {
    const samples = 44100;
    const curve = new Float32Array(samples);
    for (let i = 0; i < samples; i++) {
        const x = (i * 2 / samples) - 1;
        curve[i] = Math.tanh(amount * x);
    }
    return curve;
}
```

#### Hard Clipping
```javascript
function hardClip(threshold) {
    const samples = 44100;
    const curve = new Float32Array(samples);
    for (let i = 0; i < samples; i++) {
        const x = (i * 2 / samples) - 1;
        curve[i] = Math.max(-threshold, Math.min(threshold, x));
    }
    return curve;
}
```

#### Bit Crusher
```javascript
function bitCrush(bits) {
    const samples = 44100;
    const curve = new Float32Array(samples);
    const levels = Math.pow(2, bits);
    for (let i = 0; i < samples; i++) {
        const x = (i * 2 / samples) - 1;
        curve[i] = Math.round(x * levels) / levels;
    }
    return curve;
}
```

---

## 8. AnalyserNode Best Practices

### FFT Size
**Must be power of 2**: 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768

```javascript
// ✅ GOOD: Choose appropriate FFT size
analyser.fftSize = 2048; // Default, good balance
analyser.fftSize = 8192; // High resolution, more CPU
analyser.fftSize = 512;  // Low resolution, fast
```

**Frequency Bins**: `frequencyBinCount = fftSize / 2`

### Smoothing
```javascript
// smoothingTimeConstant: 0 to 1
analyser.smoothingTimeConstant = 0.8; // Default, smooth
analyser.smoothingTimeConstant = 0.0; // No smoothing, instant
analyser.smoothingTimeConstant = 0.95; // Very smooth
```

### Decibel Range
```javascript
// minDecibels to maxDecibels: Scale for visualization
analyser.minDecibels = -90; // Default
analyser.maxDecibels = -10; // Default

// ✅ GOOD: Adjust for better visualization
analyser.minDecibels = -100; // Show quieter sounds
analyser.maxDecibels = 0;    // Show full range
```

### Data Extraction
⚠️ **CURRENT ISSUE**: Implementation only returns first element

```javascript
// ❌ WRONG: Current implementation
function getByteFrequencyData(analyser) {
    const dataArray = new Uint8Array(analyser.frequencyBinCount);
    analyser.getByteFrequencyData(dataArray);
    return dataArray[0]; // Only first element!
}

// ✅ CORRECT: Should return full array
function getByteFrequencyData(analyser) {
    const dataArray = new Uint8Array(analyser.frequencyBinCount);
    analyser.getByteFrequencyData(dataArray);
    return Array.from(dataArray); // Full array
}
```

### Visualization Patterns
```javascript
// ✅ Frequency bars (spectrum analyzer)
const bufferLength = analyser.frequencyBinCount;
const dataArray = new Uint8Array(bufferLength);

function draw() {
    analyser.getByteFrequencyData(dataArray);
    // Draw bars: each dataArray[i] is 0-255
    // Frequency: i * (sampleRate / fftSize)
}

// ✅ Waveform (oscilloscope)
const bufferLength = analyser.fftSize;
const dataArray = new Uint8Array(bufferLength);

function draw() {
    analyser.getByteTimeDomainData(dataArray);
    // Draw waveform: each dataArray[i] is 0-255 (128 = center)
}

// ✅ VU meter (peak level)
function getAveragePeak(analyser) {
    const dataArray = new Uint8Array(analyser.frequencyBinCount);
    analyser.getByteFrequencyData(dataArray);
    const sum = dataArray.reduce((a, b) => a + b, 0);
    return sum / dataArray.length;
}
```

---

## 9. PannerNode (3D Audio) Best Practices

### Coordinate System
- **Right-handed**: X = left/right, Y = up/down, Z = forward/back
- **Listener at origin** (0, 0, 0) by default
- **Looking down -Z axis** (forward = negative Z)

```javascript
// ✅ GOOD: Position audio in 3D space
panner.setPosition(x, y, z);
panner.setOrientation(x, y, z); // Direction sound points

// Examples:
panner.setPosition(1, 0, 0);   // 1 meter to the right
panner.setPosition(0, 1, 0);   // 1 meter above
panner.setPosition(0, 0, -1);  // 1 meter forward
```

### Panning Models
```javascript
// 'equalpower' - Simple stereo panning (default, low CPU)
panner.panningModel = 'equalpower';

// 'HRTF' - Head-related transfer function (realistic 3D, high CPU)
panner.panningModel = 'HRTF';
```

### Distance Models
```javascript
// 'linear' - Linear rolloff
panner.distanceModel = 'linear';
// Volume = 1 - rolloffFactor * (distance - refDistance) / (maxDistance - refDistance)

// 'inverse' - Inverse rolloff (realistic, default)
panner.distanceModel = 'inverse';
// Volume = refDistance / (refDistance + rolloffFactor * (distance - refDistance))

// 'exponential' - Exponential rolloff
panner.distanceModel = 'exponential';
// Volume = (distance / refDistance) ^ (-rolloffFactor)
```

### Distance Parameters
```javascript
panner.refDistance = 1;      // Reference distance (full volume)
panner.maxDistance = 10000;  // Maximum distance (for linear model)
panner.rolloffFactor = 1;    // How quickly volume decreases
```

### Cone Parameters (Directional Sound)
```javascript
// Sound cone (like flashlight beam)
panner.coneInnerAngle = 60;  // Full volume within this angle (degrees)
panner.coneOuterAngle = 90;  // Volume reduction outside this angle
panner.coneOuterGain = 0.3;  // Volume multiplier outside outer angle
```

### Common Patterns
```javascript
// ✅ Simple stereo panning
panner.panningModel = 'equalpower';
panner.setPosition(x, 0, 0); // -1 (left) to +1 (right)

// ✅ 3D game audio
panner.panningModel = 'HRTF';
panner.distanceModel = 'inverse';
panner.refDistance = 1;
panner.rolloffFactor = 1;

// Update every frame:
panner.setPosition(entity.x, entity.y, entity.z);
listener.setPosition(camera.x, camera.y, camera.z);
```

---

## 10. AudioListener Best Practices

### Positioning
```javascript
// ✅ GOOD: Update listener with camera
const listener = audioContext.listener;
listener.setPosition(camera.x, camera.y, camera.z);
```

### Orientation
```javascript
// Set forward and up vectors
listener.forwardX.value = forward.x;
listener.forwardY.value = forward.y;
listener.forwardZ.value = forward.z;

listener.upX.value = up.x;
listener.upY.value = up.y;
listener.upZ.value = up.z;
```

### Integration with 3D Camera
```javascript
// ✅ GOOD: Sync with camera every frame
function updateAudioListener(camera, listener) {
    listener.setPosition(camera.position.x, camera.position.y, camera.position.z);

    const forward = camera.getWorldDirection();
    listener.forwardX.value = forward.x;
    listener.forwardY.value = forward.y;
    listener.forwardZ.value = forward.z;

    const up = camera.up;
    listener.upX.value = up.x;
    listener.upY.value = up.y;
    listener.upZ.value = up.z;
}
```

---

## 11. AudioParam Automation Best Practices

### Automation Methods (In Order of Priority)
1. **setValueAtTime** - Instant change
2. **linearRampToValueAtTime** - Linear fade
3. **exponentialRampToValueAtTime** - Exponential curve (natural)
4. **setTargetAtTime** - Exponential approach
5. **setValueCurveAtTime** - Custom curve (not implemented)

### Timing Rules
⚠️ **CRITICAL**: All automation times are in **AudioContext time**
```javascript
const now = audioContext.currentTime;
param.setValueAtTime(value, now); // Immediate
param.linearRampToValueAtTime(target, now + 1.0); // 1 second from now
```

### Ramp Constraints
```javascript
// ✅ GOOD: Set initial value before ramping
param.setValueAtTime(0.0, now);
param.linearRampToValueAtTime(1.0, now + 1.0);

// ❌ WRONG: Exponential ramp to/from zero
param.exponentialRampToValueAtTime(0, now + 1.0); // ERROR: Can't reach zero

// ✅ GOOD: Use tiny value instead of zero
param.exponentialRampToValueAtTime(0.0001, now + 1.0); // Almost silence
```

### Common Patterns

#### Fade In
```javascript
gain.gain.setValueAtTime(0, now);
gain.gain.linearRampToValueAtTime(1, now + 2.0); // 2 second fade in
```

#### Fade Out
```javascript
gain.gain.setValueAtTime(1, now);
gain.gain.linearRampToValueAtTime(0, now + 2.0); // 2 second fade out
```

#### Exponential Fade (More Natural)
```javascript
gain.gain.setValueAtTime(1, now);
gain.gain.exponentialRampToValueAtTime(0.0001, now + 2.0); // Smooth fade
```

#### Frequency Sweep
```javascript
// ✅ Linear sweep
osc.frequency.setValueAtTime(100, now);
osc.frequency.linearRampToValueAtTime(2000, now + 2.0);

// ✅ Exponential sweep (perceptually even)
osc.frequency.setValueAtTime(100, now);
osc.frequency.exponentialRampToValueAtTime(2000, now + 2.0);
```

#### Envelope (ADSR)
```javascript
// Attack-Decay-Sustain-Release
const attackTime = 0.1;
const decayTime = 0.2;
const sustainLevel = 0.7;
const releaseTime = 0.5;

// Attack
gain.gain.setValueAtTime(0, now);
gain.gain.linearRampToValueAtTime(1, now + attackTime);

// Decay
gain.gain.linearRampToValueAtTime(sustainLevel, now + attackTime + decayTime);

// Sustain (hold at sustainLevel)
// ...

// Release (when note ends)
const releaseStart = now + 2.0; // Example: 2 seconds later
gain.gain.setValueAtTime(sustainLevel, releaseStart);
gain.gain.linearRampToValueAtTime(0, releaseStart + releaseTime);
```

#### LFO (Vibrato/Tremolo)
```javascript
// Use oscillator to modulate parameter
const lfo = audioContext.createOscillator();
const lfoGain = audioContext.createGain();

lfo.frequency.value = 5; // 5 Hz LFO
lfoGain.gain.value = 10; // ±10 Hz vibrato depth

lfo.connect(lfoGain);
lfoGain.connect(osc.frequency);

osc.frequency.value = 440; // Base frequency
lfo.start();
```

### Cancel Automation
```javascript
// Cancel all future automation
param.cancelScheduledValues(now);

// Cancel and hold at current value
param.cancelAndHoldAtTime(now);
```

---

## 12. Memory Management Best Practices

### Node Lifecycle
```javascript
// ✅ GOOD: Clean up nodes
function cleanupNode(node) {
    node.disconnect();
    // Clear heavy references
    if (node.buffer) node.buffer = null;
    if (node.curve) node.curve = null;
}

// ✅ GOOD: One-shot sources auto-cleanup
source.onended = () => {
    source.disconnect();
};
```

### Buffer Management
```javascript
// ⚠️ AudioBuffer holds large amounts of memory
// 1 minute stereo at 44.1kHz = ~10 MB

// ✅ GOOD: Release when done
function releaseBuffer(buffer) {
    buffer = null; // Let GC collect
}

// ✅ GOOD: Use shorter buffers for mobile
const duration = isMobile ? 30 : 60; // 30s vs 60s
```

### Node Count Limits
```javascript
// ⚠️ Too many nodes = performance issues
// Recommendation: < 100 active nodes

const MAX_NODES = 100;
let activeNodes = 0;

function createNodeWithLimit(createFn) {
    if (activeNodes >= MAX_NODES) {
        throw new Error('Node limit exceeded');
    }
    activeNodes++;
    return createFn();
}
```

---

## 13. Performance Optimization

### Node Reuse
```javascript
// ✅ GOOD: Reuse effect nodes
const reverbNode = audioContext.createConvolver(); // Create once
// Reuse for all sounds

// ❌ WRONG: Create per sound
function playSound(buffer) {
    const convolver = audioContext.createConvolver(); // Wasteful!
}
```

### Batch Operations
```javascript
// ✅ GOOD: Connect multiple sources to same chain
const effectChain = {
    gain: audioContext.createGain(),
    filter: audioContext.createBiquadFilter(),
    reverb: audioContext.createConvolver()
};

// Chain once
effectChain.gain.connect(effectChain.filter);
effectChain.filter.connect(effectChain.reverb);
effectChain.reverb.connect(audioContext.destination);

// Reuse for multiple sources
source1.connect(effectChain.gain);
source2.connect(effectChain.gain);
source3.connect(effectChain.gain);
```

### OfflineAudioContext for Processing
```javascript
// ✅ GOOD: Use offline context for non-realtime
const offlineCtx = new OfflineAudioContext(2, 44100 * 10, 44100);
// Process faster than realtime
const renderedBuffer = await offlineCtx.startRendering();
```

---

## 14. Error Handling Patterns

### Comprehensive Error Types
```javascript
const ERROR_TYPES = {
    'NotSupportedError': 'FeatureNotAvailable',
    'NotAllowedError': 'UserActivationRequired',
    'InvalidStateError': 'InvalidStateError',
    'QuotaExceededError': 'QuotaExceededError',
    'InvalidAccessError': 'InvalidAccessError',
    'IndexSizeError': 'IndexSizeError',
    'RangeError': 'RangeError',
    'SecurityError': 'SecurityError',
    'TypeError': 'InvalidAccessError'
};

function mapError(e) {
    const errorType = ERROR_TYPES[e.name] || 'InitializationRequired';
    return { $: 'Err', a: { $: errorType, a: e.message } };
}
```

### Validation Before Operation
```javascript
// ✅ GOOD: Validate parameters
function setFrequency(osc, freq, when) {
    try {
        if (freq < 0 || freq > 22050) {
            throw new RangeError('Frequency out of range: 0-22050 Hz');
        }
        if (when < 0) {
            throw new RangeError('Time cannot be negative');
        }
        osc.frequency.setValueAtTime(freq, when);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return mapError(e);
    }
}
```

---

## 15. Browser Compatibility

### Feature Detection
```javascript
// ✅ GOOD: Check features before use
const hasAudioContext = !!(window.AudioContext || window.webkitAudioContext);
const hasAudioWorklet = hasAudioContext && ('audioWorklet' in AudioContext.prototype);
const hasMediaStreamSource = hasAudioContext && ('createMediaStreamSource' in AudioContext.prototype);
```

### Webkit Prefixes
```javascript
const AudioContext = window.AudioContext || window.webkitAudioContext;
const OfflineAudioContext = window.OfflineAudioContext || window.webkitOfflineAudioContext;
```

### Legacy API Fallbacks
```javascript
// Modern API (AudioParam)
if (panner.positionX) {
    panner.positionX.value = x;
    panner.positionY.value = y;
    panner.positionZ.value = z;
} else {
    // Legacy API (deprecated)
    panner.setPosition(x, y, z);
}
```

---

## 16. Common Gotchas and Solutions

### 1. Context Starts Suspended
```javascript
// ❌ PROBLEM: No audio plays
const ctx = new AudioContext();
// ctx.state === 'suspended' (autoplay policy)

// ✅ SOLUTION: Resume on user gesture
button.addEventListener('click', async () => {
    await ctx.resume();
    // Now audio works
});
```

### 2. BufferSource One-Shot
```javascript
// ❌ PROBLEM: Can't restart source
source.start();
source.stop();
source.start(); // ERROR!

// ✅ SOLUTION: Create new source
function playBuffer(buffer) {
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.connect(destination);
    source.start();
}
```

### 3. Exponential Ramp Zero
```javascript
// ❌ PROBLEM: Can't ramp to zero
param.exponentialRampToValueAtTime(0, when); // ERROR!

// ✅ SOLUTION: Use near-zero value
param.exponentialRampToValueAtTime(0.0001, when);
```

### 4. Timing Precision
```javascript
// ❌ PROBLEM: Using Date.now() for timing
const now = Date.now();
source.start(now); // WRONG! Wrong time base

// ✅ SOLUTION: Use AudioContext.currentTime
const now = audioContext.currentTime;
source.start(now);
```

### 5. Node Connection Cycles
```javascript
// ❌ PROBLEM: Connecting node to itself
node.connect(node); // ERROR!

// ❌ PROBLEM: Creating cycle without delay
nodeA.connect(nodeB);
nodeB.connect(nodeA); // ERROR!

// ✅ SOLUTION: Use delay node for feedback
nodeA.connect(delay);
delay.connect(nodeB);
nodeB.connect(nodeA); // OK with delay
```

---

## 17. Testing Strategies

### Unit Testing Audio
```javascript
// ✅ Test node creation
test('createGainNode returns Ok', () => {
    const result = createGainNode(ctx, 0.5);
    expect(result.$).toBe('Ok');
});

// ✅ Test error handling
test('negative frequency returns error', () => {
    const result = createOscillator(ctx, -100, 'sine');
    expect(result.$).toBe('Err');
    expect(result.a.$).toBe('RangeError');
});

// ✅ Test audio pipeline
test('can connect source to destination', () => {
    const osc = createOscillator(ctx, 440, 'sine');
    const gain = createGainNode(ctx, 0.5);
    expect(connectNodes(osc, gain).$).toBe('Ok');
    expect(connectToDestination(gain, ctx).$).toBe('Ok');
});
```

### Integration Testing
```javascript
// ✅ Test complete audio flow
test('can play oscillator through gain', async () => {
    const ctx = await createAudioContext('Click');
    const osc = createOscillator(ctx, 440, 'sine');
    const gain = createGainNode(ctx, 0.1);

    connectNodes(osc, gain);
    connectToDestination(gain, ctx);

    startOscillator(osc, ctx.currentTime);
    await delay(100);
    stopOscillator(osc, ctx.currentTime);
});
```

---

## 18. Documentation Requirements

### JSDoc Standards
```javascript
/**
 * Create biquad filter node for frequency filtering
 *
 * @name createBiquadFilter
 * @canopy-type Initialized AudioContext -> String -> Result.Result Capability.CapabilityError BiquadFilterNode
 *
 * @param {AudioContext} audioContext - The audio context
 * @param {string} filterType - Filter type: 'lowpass', 'highpass', 'bandpass', etc.
 * @returns {Result} Ok with BiquadFilterNode or Err with CapabilityError
 *
 * @example
 * ```canopy
 * case createBiquadFilter ctx "lowpass" of
 *     Ok filter ->
 *         setFilterFrequency filter 1000.0 (getCurrentTime ctx)
 *     Err error ->
 *         Debug.log "Filter creation failed" error
 * ```
 *
 * @see https://developer.mozilla.org/en-US/docs/Web/API/BiquadFilterNode
 */
```

### Parameter Ranges in Docs
```javascript
/**
 * Set filter frequency
 *
 * @param filter {BiquadFilterNode} - The filter to modify
 * @param frequency {number} - Frequency in Hz (10 to sampleRate/2)
 * @param when {number} - AudioContext time to apply change
 *
 * @throws {RangeError} If frequency is outside valid range
 */
```

---

## Conclusion

This comprehensive guide covers the essential patterns, gotchas, and best practices for Web Audio API implementation in Canopy FFI. Key takeaways:

1. **Always handle user activation** for AudioContext
2. **Remember one-shot constraints** for BufferSource
3. **Set buffers/curves** for Convolver/WaveShaper
4. **Use AudioContext.currentTime** for all timing
5. **Clean up nodes** to prevent memory leaks
6. **Validate parameters** before API calls
7. **Return full arrays** from Analyser (fix current implementation)
8. **Test all error paths** comprehensively

---

**Last Updated**: 2025-10-22
**Next Review**: When implementing missing features
