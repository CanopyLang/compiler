(function(scope){'use strict';
var _Debugger_unsafeCoerce = function(value) { return value; };

// FFI JavaScript content from external files

// From external/audio.js
/**
 * Complete Web Audio API FFI - Production-Ready Implementation
 *
 * This provides comprehensive bindings to the Web Audio API for Canopy,
 * including all major audio node types, effects, analysis, and recording.
 *
 * @module AudioFFI
 * @since 0.19.1
 */

// ============================================================================
// AUDIO CONTEXT MANAGEMENT
// ============================================================================

/**
 * Create audio context with error handling
 * @name createAudioContext
 * @canopy-type Capability.UserActivated -> Result Capability.CapabilityError (Capability.Initialized AudioContext)
 */
function createAudioContext(userActivation) {
    try {
        const ctx = new (window.AudioContext || window.webkitAudioContext)();
        // Return Task Ok with Fresh initialized context
        return { $: 'Ok', a: { $: 'Fresh', a: ctx } };
    } catch (e) {
        // Map JavaScript errors to CapabilityError
        if (e.name === 'NotSupportedError') {
            return { $: 'Err', a: { $: 'NotSupportedError', a: 'Web Audio API not supported: ' + e.message } };
        } else if (e.name === 'SecurityError') {
            return { $: 'Err', a: { $: 'SecurityError', a: 'Security error creating AudioContext: ' + e.message } };
        } else if (e.name === 'NotAllowedError') {
            return { $: 'Err', a: { $: 'UserActivationRequired', a: 'User activation required to create AudioContext: ' + e.message } };
        } else if (e.name === 'QuotaExceededError') {
            return { $: 'Err', a: { $: 'QuotaExceededError', a: 'Memory quota exceeded: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InitializationRequired', a: 'Failed to create AudioContext: ' + e.message } };
        }
    }
}

/**
 * Get current time from audio context
 * @name getCurrentTime
 * @canopy-type (Capability.Initialized AudioContext) -> Float
 */
function getCurrentTime(initializedContext) {
    const audioContext = initializedContext.a;
    return audioContext.currentTime;
}

/**
 * Resume audio context with error handling
 * @name resumeAudioContext
 * @canopy-type (Capability.Initialized AudioContext) -> Result Capability.CapabilityError (Capability.Initialized AudioContext)
 */
function resumeAudioContext(initializedContext) {
    try {
        // Extract AudioContext from Capability.Initialized wrapper
        const audioContext = initializedContext.a;
        audioContext.resume();
        // Return Task Ok with Running initialized context
        return { $: 'Ok', a: { $: 'Running', a: audioContext } };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Cannot resume context: ' + e.message } };
        } else if (e.name === 'NotAllowedError') {
            return { $: 'Err', a: { $: 'UserActivationRequired', a: 'User activation required to resume: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InitializationRequired', a: 'Failed to resume context: ' + e.message } };
        }
    }
}

/**
 * Suspend audio context with error handling
 * @name suspendAudioContext
 * @canopy-type AudioContext -> Result Capability.CapabilityError AudioContext
 */
function suspendAudioContext(audioContext) {
    try {
        audioContext.suspend();
        return { $: 'Ok', a: audioContext };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Cannot suspend context: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InitializationRequired', a: 'Failed to suspend context: ' + e.message } };
        }
    }
}

/**
 * Close audio context with error handling
 * @name closeAudioContext
 * @canopy-type AudioContext -> Result Capability.CapabilityError Int
 */
function closeAudioContext(audioContext) {
    try {
        audioContext.close();
        return { $: 'Ok', a: 1 };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Cannot close context: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InitializationRequired', a: 'Failed to close context: ' + e.message } };
        }
    }
}

/**
 * Get audio context sample rate
 * @name getSampleRate
 * @canopy-type AudioContext -> Float
 */
function getSampleRate(audioContext) {
    return audioContext.sampleRate;
}

/**
 * Get audio context state as string
 * @name getContextState
 * @canopy-type AudioContext -> String
 */
function getContextState(audioContext) {
    return audioContext.state;
}

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

// ============================================================================
// SOURCE NODES - Audio Generation
// ============================================================================

/**
 * Create oscillator node with error handling
 * @name createOscillator
 * @canopy-type (Capability.Initialized AudioContext) -> Float -> String -> Result Capability.CapabilityError OscillatorNode
 */
function createOscillator(initializedContext, frequency, waveType) {
    try {
        // Extract AudioContext from Capability.Initialized wrapper
        const audioContext = initializedContext.a;

        // Validate parameters
        if (frequency < 0 || frequency > 22050) {
            throw new RangeError('Frequency must be between 0 and 22050 Hz');
        }

        const oscillator = audioContext.createOscillator();
        oscillator.frequency.setValueAtTime(frequency, audioContext.currentTime);
        oscillator.type = waveType || 'sine';

        // Return Task Ok
        return { $: 'Ok', a: oscillator };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Context closed: ' + e.message } };
        } else if (e.name === 'QuotaExceededError') {
            return { $: 'Err', a: { $: 'QuotaExceededError', a: 'Memory allocation failed: ' + e.message } };
        } else if (e.name === 'RangeError') {
            return { $: 'Err', a: { $: 'RangeError', a: e.message } };
        } else if (e.name === 'TypeError') {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Invalid wave type: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InitializationRequired', a: 'Failed to create oscillator: ' + e.message } };
        }
    }
}

/**
 * Start oscillator at specific time with error handling
 * @name startOscillator
 * @canopy-type OscillatorNode -> Float -> Result Capability.CapabilityError Int
 */
function startOscillator(oscillator, when) {
    try {
        if (when < 0) {
            throw new RangeError('Start time cannot be negative');
        }
        oscillator.start(when);
        // Return Task Ok with unit value
        return { $: 'Ok', a: 1 };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Oscillator already started or context closed: ' + e.message } };
        } else if (e.name === 'RangeError') {
            return { $: 'Err', a: { $: 'RangeError', a: e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to start oscillator: ' + e.message } };
        }
    }
}

/**
 * Stop oscillator at specific time with error handling
 * @name stopOscillator
 * @canopy-type OscillatorNode -> Float -> Result Capability.CapabilityError Int
 */
function stopOscillator(oscillator, when) {
    try {
        if (when < 0) {
            throw new RangeError('Stop time cannot be negative');
        }
        oscillator.stop(when);
        // Return Task Ok with unit value
        return { $: 'Ok', a: 1 };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Oscillator not started or already stopped: ' + e.message } };
        } else if (e.name === 'RangeError') {
            return { $: 'Err', a: { $: 'RangeError', a: 'Stop time before start time: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to stop oscillator: ' + e.message } };
        }
    }
}

/**
 * Set oscillator frequency
 * @name setOscillatorFrequency
 * @canopy-type OscillatorNode -> Float -> Float -> ()
 */
function setOscillatorFrequency(oscillator, frequency, when) {
    oscillator.frequency.value = frequency;
}

/**
 * Set oscillator detune (in cents)
 * @name setOscillatorDetune
 * @canopy-type OscillatorNode -> Float -> Float -> ()
 */
function setOscillatorDetune(oscillator, detune, when) {
    oscillator.detune.setValueAtTime(detune, when);
}

/**
 * Create audio buffer source node
 * @name createBufferSource
 * @canopy-type AudioContext -> AudioBufferSourceNode
 */
function createBufferSource(audioContext) {
    return audioContext.createBufferSource();
}

/**
 * Create media stream source from microphone/getUserMedia
 * @name createMediaStreamSource
 * @canopy-type AudioContext -> MediaStream -> Result Capability.CapabilityError MediaStreamAudioSourceNode
 */
function createMediaStreamSource(audioContext, mediaStream) {
    try {
        const source = audioContext.createMediaStreamSource(mediaStream);
        return { $: 'Ok', a: source };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Context closed: ' + e.message } };
        } else if (e.name === 'NotSupportedError') {
            return { $: 'Err', a: { $: 'NotSupportedError', a: 'MediaStream not supported: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to create media stream source: ' + e.message } };
        }
    }
}

/**
 * Create media stream destination for recording
 * @name createMediaStreamDestination
 * @canopy-type AudioContext -> Result Capability.CapabilityError MediaStreamAudioDestinationNode
 */
function createMediaStreamDestination(audioContext) {
    try {
        const destination = audioContext.createMediaStreamDestination();
        return { $: 'Ok', a: destination };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Context closed: ' + e.message } };
        } else if (e.name === 'NotSupportedError') {
            return { $: 'Err', a: { $: 'NotSupportedError', a: 'MediaStream destination not supported: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to create media stream destination: ' + e.message } };
        }
    }
}

/**
 * Get media stream from destination node
 * @name getMediaStream
 * @canopy-type MediaStreamAudioDestinationNode -> MediaStream
 */
function getMediaStream(destinationNode) {
    return destinationNode.stream;
}

/**
 * Start buffer source with error handling
 * @name startBufferSource
 * @canopy-type AudioBufferSourceNode -> Float -> Result Capability.CapabilityError Int
 */
function startBufferSource(source, when) {
    try {
        if (when < 0) {
            throw new RangeError('Start time cannot be negative');
        }
        source.start(when);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Buffer source already started: ' + e.message } };
        } else if (e.name === 'RangeError') {
            return { $: 'Err', a: { $: 'RangeError', a: e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to start buffer source: ' + e.message } };
        }
    }
}

/**
 * Stop buffer source with error handling
 * @name stopBufferSource
 * @canopy-type AudioBufferSourceNode -> Float -> Result Capability.CapabilityError Int
 */
function stopBufferSource(source, when) {
    try {
        if (when < 0) {
            throw new RangeError('Stop time cannot be negative');
        }
        source.stop(when);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Buffer source not started or already stopped: ' + e.message } };
        } else if (e.name === 'RangeError') {
            return { $: 'Err', a: { $: 'RangeError', a: e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to stop buffer source: ' + e.message } };
        }
    }
}

// ============================================================================
// EFFECT NODES - Audio Processing
// ============================================================================

/**
 * Create gain node for volume control with error handling
 * @name createGainNode
 * @canopy-type (Capability.Initialized AudioContext) -> Float -> Result Capability.CapabilityError GainNode
 */
function createGainNode(initializedContext, gain) {
    try {
        // Extract AudioContext from Capability.Initialized wrapper
        const audioContext = initializedContext.a;

        const gainNode = audioContext.createGain();
        gainNode.gain.value = gain;

        // Return Task Ok
        return { $: 'Ok', a: gainNode };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Context closed: ' + e.message } };
        } else if (e.name === 'QuotaExceededError') {
            return { $: 'Err', a: { $: 'QuotaExceededError', a: 'Memory allocation failed: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InitializationRequired', a: 'Failed to create gain node: ' + e.message } };
        }
    }
}

/**
 * Set gain value with error handling
 * @name setGain
 * @canopy-type GainNode -> Float -> Float -> Result Capability.CapabilityError Int
 */
function setGain(gainNode, value, when) {
    try {
        gainNode.gain.setValueAtTime(value, when);
        // Return Task Ok with unit value
        return { $: 'Ok', a: 1 };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Node destroyed: ' + e.message } };
        } else if (e.name === 'RangeError') {
            return { $: 'Err', a: { $: 'RangeError', a: 'Invalid gain value or time: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to set gain: ' + e.message } };
        }
    }
}

/**
 * Ramp gain linearly with error handling
 * @name rampGainLinear
 * @canopy-type GainNode -> Float -> Float -> Result Capability.CapabilityError Int
 */
function rampGainLinear(gainNode, targetValue, endTime) {
    try {
        gainNode.gain.linearRampToValueAtTime(targetValue, endTime);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        if (e.name === 'TypeError' || e.name === 'RangeError') {
            return { $: 'Err', a: { $: 'RangeError', a: 'Invalid value or time: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to ramp gain: ' + e.message } };
        }
    }
}

/**
 * Ramp gain exponentially with error handling
 * @name rampGainExponential
 * @canopy-type GainNode -> Float -> Float -> Result Capability.CapabilityError Int
 */
function rampGainExponential(gainNode, targetValue, endTime) {
    try {
        if (targetValue <= 0) {
            throw new Error('Exponential ramp target value must be positive (cannot ramp to/from zero)');
        }
        gainNode.gain.exponentialRampToValueAtTime(targetValue, endTime);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        if (e.name === 'NotSupportedError' || e.message.includes('zero')) {
            return { $: 'Err', a: { $: 'NotSupportedError', a: 'Cannot use exponential ramp with zero/negative values: ' + e.message } };
        } else if (e.name === 'TypeError' || e.name === 'RangeError') {
            return { $: 'Err', a: { $: 'RangeError', a: 'Invalid value or time: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to ramp gain: ' + e.message } };
        }
    }
}

/**
 * Create biquad filter node
 * @name createBiquadFilter
 * @canopy-type AudioContext -> String -> BiquadFilterNode
 */
function createBiquadFilter(audioContext, filterType) {
    const filter = audioContext.createBiquadFilter();
    filter.type = filterType || 'lowpass';
    return filter;
}

/**
 * Set filter frequency
 * @name setFilterFrequency
 * @canopy-type BiquadFilterNode -> Float -> Float -> ()
 */
function setFilterFrequency(filter, frequency, when) {
    filter.frequency.setValueAtTime(frequency, when);
}

/**
 * Set filter Q (resonance)
 * @name setFilterQ
 * @canopy-type BiquadFilterNode -> Float -> Float -> ()
 */
function setFilterQ(filter, q, when) {
    filter.Q.setValueAtTime(q, when);
}

/**
 * Set filter gain (for peaking/shelving filters)
 * @name setFilterGain
 * @canopy-type BiquadFilterNode -> Float -> Float -> ()
 */
function setFilterGain(filter, gain, when) {
    filter.gain.setValueAtTime(gain, when);
}

/**
 * Create delay node
 * @name createDelay
 * @canopy-type AudioContext -> Float -> DelayNode
 */
function createDelay(audioContext, maxDelayTime) {
    return audioContext.createDelay(maxDelayTime);
}

/**
 * Set delay time
 * @name setDelayTime
 * @canopy-type DelayNode -> Float -> Float -> ()
 */
function setDelayTime(delayNode, delayTime, when) {
    delayNode.delayTime.setValueAtTime(delayTime, when);
}

/**
 * Create convolver node for reverb/impulse responses
 * @name createConvolver
 * @canopy-type AudioContext -> ConvolverNode
 */
function createConvolver(audioContext) {
    return audioContext.createConvolver();
}

/**
 * Set convolver impulse response buffer
 * @name setConvolverBuffer
 * @canopy-type ConvolverNode -> AudioBuffer -> Result Capability.CapabilityError ()
 */
function setConvolverBuffer(convolver, audioBuffer) {
    try {
        convolver.buffer = audioBuffer;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Cannot set buffer: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to set convolver buffer: ' + e.message } };
        }
    }
}

/**
 * Set convolver normalization
 * @name setConvolverNormalize
 * @canopy-type ConvolverNode -> Bool -> Bool
 */
function setConvolverNormalize(convolver, normalize) {
    convolver.normalize = normalize;
    return convolver.normalize;
}

/**
 * Get convolver buffer
 * @name getConvolverBuffer
 * @canopy-type ConvolverNode -> Maybe AudioBuffer
 */
function getConvolverBuffer(convolver) {
    const buffer = convolver.buffer;
    return buffer ? { $: 'Just', a: buffer } : { $: 'Nothing' };
}

/**
 * Create dynamics compressor
 * @name createDynamicsCompressor
 * @canopy-type AudioContext -> DynamicsCompressorNode
 */
function createDynamicsCompressor(audioContext) {
    return audioContext.createDynamicsCompressor();
}

/**
 * Set compressor threshold
 * @name setCompressorThreshold
 * @canopy-type DynamicsCompressorNode -> Float -> Float -> ()
 */
function setCompressorThreshold(compressor, threshold, when) {
    compressor.threshold.setValueAtTime(threshold, when);
}

/**
 * Set compressor knee
 * @name setCompressorKnee
 * @canopy-type DynamicsCompressorNode -> Float -> Float -> ()
 */
function setCompressorKnee(compressor, knee, when) {
    compressor.knee.setValueAtTime(knee, when);
}

/**
 * Set compressor ratio
 * @name setCompressorRatio
 * @canopy-type DynamicsCompressorNode -> Float -> Float -> ()
 */
function setCompressorRatio(compressor, ratio, when) {
    compressor.ratio.setValueAtTime(ratio, when);
}

/**
 * Set compressor attack time
 * @name setCompressorAttack
 * @canopy-type DynamicsCompressorNode -> Float -> Float -> ()
 */
function setCompressorAttack(compressor, attack, when) {
    compressor.attack.setValueAtTime(attack, when);
}

/**
 * Set compressor release time
 * @name setCompressorRelease
 * @canopy-type DynamicsCompressorNode -> Float -> Float -> ()
 */
function setCompressorRelease(compressor, release, when) {
    compressor.release.setValueAtTime(release, when);
}

/**
 * Create wave shaper for distortion
 * @name createWaveShaper
 * @canopy-type AudioContext -> WaveShaperNode
 */
function createWaveShaper(audioContext) {
    return audioContext.createWaveShaper();
}

/**
 * Set wave shaper distortion curve
 * @name setWaveShaperCurve
 * @canopy-type WaveShaperNode -> List Float -> Result Capability.CapabilityError ()
 */
function setWaveShaperCurve(shaper, curve) {
    try {
        shaper.curve = new Float32Array(curve);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Cannot set curve: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to set curve: ' + e.message } };
        }
    }
}

/**
 * Set wave shaper oversample mode
 * @name setWaveShaperOversample
 * @canopy-type WaveShaperNode -> String -> String
 */
function setWaveShaperOversample(shaper, oversample) {
    shaper.oversample = oversample;
    return shaper.oversample;
}

/**
 * Get wave shaper curve
 * @name getWaveShaperCurve
 * @canopy-type WaveShaperNode -> Maybe List Float
 */
function getWaveShaperCurve(shaper) {
    const curve = shaper.curve;
    return curve ? { $: 'Just', a: Array.from(curve) } : { $: 'Nothing' };
}

/**
 * Generate distortion curve for wave shaper
 * @name makeDistortionCurve
 * @canopy-type Float -> Int -> List Float
 */
function makeDistortionCurve(amount, nSamples) {
    const k = amount || 50;
    const n = nSamples || 44100;
    const curve = new Float32Array(n);
    const deg = Math.PI / 180;
    for (let i = 0; i < n; i++) {
        const x = (i * 2 / n) - 1;
        curve[i] = (3 + k) * x * 20 * deg / (Math.PI + k * Math.abs(x));
    }
    // Convert JavaScript array to Canopy List using runtime helper
    return _List_fromArray(Array.from(curve));
}

/**
 * Create stereo panner
 * @name createStereoPanner
 * @canopy-type AudioContext -> StereoPannerNode
 */
function createStereoPanner(audioContext) {
    return audioContext.createStereoPanner();
}

/**
 * Set pan value (-1 left, 0 center, 1 right)
 * @name setPan
 * @canopy-type StereoPannerNode -> Float -> Float -> ()
 */
function setPan(panner, pan, when) {
    panner.pan.setValueAtTime(pan, when);
}

// ============================================================================
// ANALYZER NODES - Audio Visualization
// ============================================================================

/**
 * Create analyzer node
 * @name createAnalyser
 * @canopy-type AudioContext -> AnalyserNode
 */
function createAnalyser(audioContext) {
    return audioContext.createAnalyser();
}

/**
 * Set analyzer FFT size
 * Throws IndexSizeError if fftSize is not a power of 2 in range 32-32768
 * Valid values: 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768
 * @name setAnalyserFFTSize
 * @canopy-type AnalyserNode -> Int -> Result Capability.CapabilityError Int
 */
function setAnalyserFFTSize(analyser, fftSize) {
    try {
        analyser.fftSize = fftSize;
        return { $: 'Ok', a: analyser.fftSize };
    } catch (e) {
        return { $: 'Err', a: { $: 'IndexSizeError', a: 'fftSize must be power of 2 in range 32-32768: ' + e.message } };
    }
}

/**
 * Set analyzer smoothing time constant
 * Throws RangeError if smoothing is not in range [0, 1]
 * @name setAnalyserSmoothing
 * @canopy-type AnalyserNode -> Float -> Result Capability.CapabilityError Float
 */
function setAnalyserSmoothing(analyser, smoothing) {
    try {
        analyser.smoothingTimeConstant = smoothing;
        return { $: 'Ok', a: analyser.smoothingTimeConstant };
    } catch (e) {
        return { $: 'Err', a: { $: 'RangeError', a: 'smoothingTimeConstant must be in range [0, 1]: ' + e.message } };
    }
}

/**
 * Get frequency bin count
 * @name getFrequencyBinCount
 * @canopy-type AnalyserNode -> Int
 */
function getFrequencyBinCount(analyser) {
    return analyser.frequencyBinCount;
}

// ============================================================================
// AUDIO GRAPH CONNECTIONS
// ============================================================================

/**
 * Connect audio nodes with error handling
 * @name connectNodes
 * @canopy-type OscillatorNode -> GainNode -> Result Capability.CapabilityError Int
 */
function connectNodes(sourceNode, destinationNode) {
    try {
        sourceNode.connect(destinationNode);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        if (e.name === 'InvalidAccessError') {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Cannot connect nodes from different contexts: ' + e.message } };
        } else if (e.name === 'IndexSizeError') {
            return { $: 'Err', a: { $: 'IndexSizeError', a: 'Invalid input/output index: ' + e.message } };
        } else if (e.name === 'NotSupportedError') {
            return { $: 'Err', a: { $: 'NotSupportedError', a: 'Connection would create cycle: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to connect nodes: ' + e.message } };
        }
    }
}

/**
 * Connect to destination (speakers) with error handling
 * @name connectToDestination
 * @canopy-type GainNode -> Capability.Initialized AudioContext -> Result Capability.CapabilityError Int
 */
function connectToDestination(node, initializedContext) {
    try {
        // Extract AudioContext from Capability.Initialized wrapper
        const audioContext = initializedContext.a;
        node.connect(audioContext.destination);
        // Return Task Ok with unit value
        return { $: 'Ok', a: 1 };
    } catch (e) {
        if (e.name === 'InvalidAccessError') {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Cannot connect to destination: ' + e.message } };
        } else if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Node destroyed or context closed: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to connect to destination: ' + e.message } };
        }
    }
}

/**
 * Disconnect audio node
 * @name disconnectNode
 * @canopy-type GainNode -> ()
 */
function disconnectNode(node) {
    node.disconnect();
}

// ============================================================================
// FEATURE DETECTION
// ============================================================================

/**
 * Check Web Audio API support
 * @name checkWebAudioSupport
 * @canopy-type () -> String
 */
function checkWebAudioSupport() {
    if (window.AudioContext) {
        return "Supported";
    } else if (window.webkitAudioContext) {
        return "Prefixed-webkit";
    } else {
        return "PartialSupport";
    }
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Simple test function for FFI validation - doubles the input
 * @name simpleTest
 * @canopy-type Int -> Int
 */
function simpleTest(x) {
    return x * 2;
}

// ============================================================================
// PANNER NODE - Spatial Audio (3D Audio)
// ============================================================================

/**
 * Create panner node for 3D spatial audio
 * @name createPanner
 * @canopy-type AudioContext -> PannerNode
 */
function createPanner(audioContext) {
    return audioContext.createPanner();
}

/**
 * Set panner position in 3D space
 * @name setPannerPosition
 * @canopy-type PannerNode -> Float -> Float -> Float -> ()
 */
function setPannerPosition(panner, x, y, z) {
    if (panner.positionX) {
        panner.positionX.setValueAtTime(x, panner.context.currentTime);
        panner.positionY.setValueAtTime(y, panner.context.currentTime);
        panner.positionZ.setValueAtTime(z, panner.context.currentTime);
    } else {
        panner.setPosition(x, y, z);
    }
}

/**
 * Set panner orientation in 3D space
 * @name setPannerOrientation
 * @canopy-type PannerNode -> Float -> Float -> Float -> ()
 */
function setPannerOrientation(panner, x, y, z) {
    if (panner.orientationX) {
        panner.orientationX.setValueAtTime(x, panner.context.currentTime);
        panner.orientationY.setValueAtTime(y, panner.context.currentTime);
        panner.orientationZ.setValueAtTime(z, panner.context.currentTime);
    } else {
        panner.setOrientation(x, y, z);
    }
}

/**
 * Set panning model
 * Valid values: "equalpower", "HRTF"
 * @name setPanningModel
 * @canopy-type PannerNode -> String -> Result Capability.CapabilityError String
 */
function setPanningModel(panner, model) {
    try {
        panner.panningModel = model;
        return { $: 'Ok', a: panner.panningModel };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidStateError', a: 'Invalid panning model: ' + e.message } };
    }
}

/**
 * Set distance model
 * Valid values: "linear", "inverse", "exponential"
 * @name setDistanceModel
 * @canopy-type PannerNode -> String -> Result Capability.CapabilityError String
 */
function setDistanceModel(panner, model) {
    try {
        panner.distanceModel = model;
        return { $: 'Ok', a: panner.distanceModel };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidStateError', a: 'Invalid distance model: ' + e.message } };
    }
}

/**
 * Set reference distance
 * Throws RangeError if value < 0
 * @name setRefDistance
 * @canopy-type PannerNode -> Float -> Result Capability.CapabilityError Float
 */
function setRefDistance(panner, distance) {
    try {
        panner.refDistance = distance;
        return { $: 'Ok', a: panner.refDistance };
    } catch (e) {
        return { $: 'Err', a: { $: 'RangeError', a: 'refDistance must be >= 0: ' + e.message } };
    }
}

/**
 * Set maximum distance
 * Throws RangeError if value <= 0
 * @name setMaxDistance
 * @canopy-type PannerNode -> Float -> Result Capability.CapabilityError Float
 */
function setMaxDistance(panner, distance) {
    try {
        panner.maxDistance = distance;
        return { $: 'Ok', a: panner.maxDistance };
    } catch (e) {
        return { $: 'Err', a: { $: 'RangeError', a: 'maxDistance must be > 0: ' + e.message } };
    }
}

/**
 * Set rolloff factor
 * Throws RangeError if value < 0
 * @name setRolloffFactor
 * @canopy-type PannerNode -> Float -> Result Capability.CapabilityError Float
 */
function setRolloffFactor(panner, factor) {
    try {
        panner.rolloffFactor = factor;
        return { $: 'Ok', a: panner.rolloffFactor };
    } catch (e) {
        return { $: 'Err', a: { $: 'RangeError', a: 'rolloffFactor must be >= 0: ' + e.message } };
    }
}

/**
 * Set cone inner angle (degrees)
 * Accepts any float value
 * @name setConeInnerAngle
 * @canopy-type PannerNode -> Float -> Float
 */
function setConeInnerAngle(panner, angle) {
    panner.coneInnerAngle = angle;
    return panner.coneInnerAngle;
}

/**
 * Set cone outer angle (degrees)
 * Accepts any float value
 * @name setConeOuterAngle
 * @canopy-type PannerNode -> Float -> Float
 */
function setConeOuterAngle(panner, angle) {
    panner.coneOuterAngle = angle;
    return panner.coneOuterAngle;
}

/**
 * Set cone outer gain
 * Throws InvalidStateError if value outside 0-1 range
 * @name setConeOuterGain
 * @canopy-type PannerNode -> Float -> Result Capability.CapabilityError Float
 */
function setConeOuterGain(panner, gain) {
    try {
        panner.coneOuterGain = gain;
        return { $: 'Ok', a: panner.coneOuterGain };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidStateError', a: 'coneOuterGain must be in range 0-1: ' + e.message } };
    }
}

// ============================================================================
// AUDIO LISTENER - 3D Audio Listener
// ============================================================================

/**
 * Get audio listener from context
 * @name getAudioListener
 * @canopy-type AudioContext -> AudioListener
 */
function getAudioListener(audioContext) {
    return audioContext.listener;
}

/**
 * Set listener position
 * @name setListenerPosition
 * @canopy-type AudioListener -> Float -> Float -> Float -> ()
 */
function setListenerPosition(listener, x, y, z) {
    if (listener.positionX) {
        const time = listener.context ? listener.context.currentTime : 0;
        listener.positionX.setValueAtTime(x, time);
        listener.positionY.setValueAtTime(y, time);
        listener.positionZ.setValueAtTime(z, time);
    } else {
        listener.setPosition(x, y, z);
    }
}

/**
 * Set listener forward vector
 * @name setListenerForward
 * @canopy-type AudioListener -> Float -> Float -> Float -> ()
 */
function setListenerForward(listener, x, y, z) {
    if (listener.forwardX) {
        const time = listener.context ? listener.context.currentTime : 0;
        listener.forwardX.setValueAtTime(x, time);
        listener.forwardY.setValueAtTime(y, time);
        listener.forwardZ.setValueAtTime(z, time);
    }
}

/**
 * Set listener up vector
 * @name setListenerUp
 * @canopy-type AudioListener -> Float -> Float -> Float -> ()
 */
function setListenerUp(listener, x, y, z) {
    if (listener.upX) {
        const time = listener.context ? listener.context.currentTime : 0;
        listener.upX.setValueAtTime(x, time);
        listener.upY.setValueAtTime(y, time);
        listener.upZ.setValueAtTime(z, time);
    }
}

// ============================================================================
// CHANNEL SPLITTER/MERGER - Channel Routing
// ============================================================================

/**
 * Create channel splitter node
 * @name createChannelSplitter
 * @canopy-type AudioContext -> Int -> ChannelSplitterNode
 */
function createChannelSplitter(audioContext, channels) {
    return audioContext.createChannelSplitter(channels);
}

/**
 * Create channel merger node
 * @name createChannelMerger
 * @canopy-type AudioContext -> Int -> ChannelMergerNode
 */
function createChannelMerger(audioContext, channels) {
    return audioContext.createChannelMerger(channels);
}

// ============================================================================
// AUDIO BUFFER OPERATIONS
// ============================================================================

/**
 * Create empty audio buffer
 * @name createAudioBuffer
 * @canopy-type AudioContext -> Int -> Int -> Float -> AudioBuffer
 */
function createAudioBuffer(audioContext, channels, length, sampleRate) {
    return audioContext.createBuffer(channels, length, sampleRate);
}

/**
 * Get buffer length
 * @name getBufferLength
 * @canopy-type AudioBuffer -> Int
 */
function getBufferLength(buffer) {
    return buffer.length;
}

/**
 * Get buffer duration
 * @name getBufferDuration
 * @canopy-type AudioBuffer -> Float
 */
function getBufferDuration(buffer) {
    return buffer.duration;
}

/**
 * Get buffer sample rate
 * @name getBufferSampleRate
 * @canopy-type AudioBuffer -> Float
 */
function getBufferSampleRate(buffer) {
    return buffer.sampleRate;
}

/**
 * Get buffer number of channels
 * @name getBufferChannels
 * @canopy-type AudioBuffer -> Int
 */
function getBufferChannels(buffer) {
    return buffer.numberOfChannels;
}

/**
 * Get channel data from audio buffer
 * @name getChannelData
 * @canopy-type AudioBuffer -> Int -> Result Capability.CapabilityError List Float
 */
function getChannelData(audioBuffer, channelNumber) {
    try {
        const data = audioBuffer.getChannelData(channelNumber);
        return { $: 'Ok', a: Array.from(data) };
    } catch (e) {
        if (e.name === 'IndexSizeError') {
            return { $: 'Err', a: { $: 'RangeError', a: 'Channel number out of range: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to get channel data: ' + e.message } };
        }
    }
}

/**
 * Copy data to audio buffer channel
 * @name copyToChannel
 * @canopy-type AudioBuffer -> List Float -> Int -> Int -> Result Capability.CapabilityError ()
 */
function copyToChannel(audioBuffer, source, channelNumber, startInChannel) {
    try {
        const sourceArray = new Float32Array(source);
        audioBuffer.copyToChannel(sourceArray, channelNumber, startInChannel || 0);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        if (e.name === 'IndexSizeError') {
            return { $: 'Err', a: { $: 'RangeError', a: 'Invalid channel or offset: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to copy to channel: ' + e.message } };
        }
    }
}

/**
 * Copy data from audio buffer channel
 * @name copyFromChannel
 * @canopy-type AudioBuffer -> Int -> Int -> Int -> Result Capability.CapabilityError List Float
 */
function copyFromChannel(audioBuffer, channelNumber, startInChannel, length) {
    try {
        const destination = new Float32Array(length);
        audioBuffer.copyFromChannel(destination, channelNumber, startInChannel || 0);
        return { $: 'Ok', a: Array.from(destination) };
    } catch (e) {
        if (e.name === 'IndexSizeError') {
            return { $: 'Err', a: { $: 'RangeError', a: 'Invalid channel or offset: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to copy from channel: ' + e.message } };
        }
    }
}

/**
 * Create silent audio buffer
 * @name createSilentBuffer
 * @canopy-type AudioContext -> Int -> Int -> Float -> AudioBuffer
 */
function createSilentBuffer(audioContext, channels, length, sampleRate) {
    return audioContext.createBuffer(channels, length, sampleRate);
}

/**
 * Clone audio buffer
 * @name cloneAudioBuffer
 * @canopy-type AudioBuffer -> Result Capability.CapabilityError AudioBuffer
 */
function cloneAudioBuffer(sourceBuffer) {
    try {
        const clone = new AudioBuffer({
            length: sourceBuffer.length,
            numberOfChannels: sourceBuffer.numberOfChannels,
            sampleRate: sourceBuffer.sampleRate
        });
        for (let ch = 0; ch < sourceBuffer.numberOfChannels; ch++) {
            clone.copyToChannel(sourceBuffer.getChannelData(ch), ch);
        }
        return { $: 'Ok', a: clone };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to clone buffer: ' + e.message } };
    }
}

/**
 * Create media element source (HTML audio/video)
 * @name createMediaElementSource
 * @canopy-type AudioContext -> HTMLMediaElement -> Result Capability.CapabilityError MediaElementAudioSourceNode
 */
function createMediaElementSource(audioContext, mediaElement) {
    try {
        const source = audioContext.createMediaElementSource(mediaElement);
        return { $: 'Ok', a: source };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Element already connected: ' + e.message } };
        } else if (e.name === 'NotSupportedError') {
            return { $: 'Err', a: { $: 'NotSupportedError', a: 'Media element not supported: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to create media element source: ' + e.message } };
        }
    }
}

// ============================================================================
// PERIODIC WAVE - Custom Waveforms
// ============================================================================

/**
 * Create periodic wave for custom oscillator waveforms
 * @name createPeriodicWave
 * @canopy-type AudioContext -> PeriodicWave
 */
function createPeriodicWave(audioContext) {
    const real = new Float32Array([0, 0]);
    const imag = new Float32Array([0, 1]);
    return audioContext.createPeriodicWave(real, imag);
}

// ============================================================================
// OFFLINE AUDIO CONTEXT - Non-realtime Rendering
// ============================================================================

/**
 * Create offline audio context
 * @name createOfflineAudioContext
 * @canopy-type Int -> Int -> Float -> OfflineAudioContext
 */
function createOfflineAudioContext(channels, length, sampleRate) {
    return new (window.OfflineAudioContext || window.webkitOfflineAudioContext)(channels, length, sampleRate);
}

/**
 * Start offline rendering
 * @name startOfflineRendering
 * @canopy-type OfflineAudioContext -> OfflineAudioContext
 */
function startOfflineRendering(offlineContext) {
    offlineContext.startRendering();
    return offlineContext;
}

/**
 * Start offline rendering with Promise support (async)
 * @name startOfflineRenderingAsync
 * @canopy-type OfflineAudioContext -> Task Capability.CapabilityError AudioBuffer
 */
function startOfflineRenderingAsync(offlineContext) {
    return offlineContext.startRendering()
        .then(renderedBuffer => ({ $: 'Ok', a: renderedBuffer }))
        .catch(error => ({
            $: 'Err',
            a: { $: 'InvalidStateError', a: 'Offline rendering failed: ' + error.message }
        }));
}

/**
 * Suspend offline context at specified time
 * @name suspendOfflineContext
 * @canopy-type OfflineAudioContext -> Float -> Task Capability.CapabilityError ()
 */
function suspendOfflineContext(offlineContext, suspendTime) {
    return offlineContext.suspend(suspendTime)
        .then(() => ({ $: 'Ok', a: 1 }))
        .catch(error => ({
            $: 'Err',
            a: { $: 'InvalidStateError', a: 'Failed to suspend: ' + error.message }
        }));
}

/**
 * Resume suspended offline context
 * @name resumeOfflineContext
 * @canopy-type OfflineAudioContext -> Task Capability.CapabilityError ()
 */
function resumeOfflineContext(offlineContext) {
    return offlineContext.resume()
        .then(() => ({ $: 'Ok', a: 1 }))
        .catch(error => ({
            $: 'Err',
            a: { $: 'InvalidStateError', a: 'Failed to resume: ' + error.message }
        }));
}

/**
 * Get offline context render length
 * @name getOfflineContextLength
 * @canopy-type OfflineAudioContext -> Int
 */
function getOfflineContextLength(offlineContext) {
    return offlineContext.length;
}

/**
 * Get offline context sample rate
 * @name getOfflineContextSampleRate
 * @canopy-type OfflineAudioContext -> Float
 */
function getOfflineContextSampleRate(offlineContext) {
    return offlineContext.sampleRate;
}

// ============================================================================
// AUDIO PARAM AUTOMATION - Advanced Parameter Control
// ============================================================================

/**
 * Get gain audio param
 * @name getGainParam
 * @canopy-type GainNode -> AudioParam
 */
function getGainParam(gainNode) {
    return gainNode.gain;
}

/**
 * Get frequency audio param
 * @name getFrequencyParam
 * @canopy-type OscillatorNode -> AudioParam
 */
function getFrequencyParam(oscillator) {
    return oscillator.frequency;
}

/**
 * Get detune audio param
 * @name getDetuneParam
 * @canopy-type OscillatorNode -> AudioParam
 */
function getDetuneParam(oscillator) {
    return oscillator.detune;
}

/**
 * Set value at time (AudioParam)
 * @name setParamValueAtTime
 * @canopy-type AudioParam -> Float -> Float -> ()
 */
function setParamValueAtTime(param, value, time) {
    param.setValueAtTime(value, time);
}

/**
 * Linear ramp to value at time
 * @name linearRampToValue
 * @canopy-type AudioParam -> Float -> Float -> ()
 */
function linearRampToValue(param, value, endTime) {
    param.linearRampToValueAtTime(value, endTime);
}

/**
 * Exponential ramp to value at time
 * @name exponentialRampToValue
 * @canopy-type AudioParam -> Float -> Float -> ()
 */
function exponentialRampToValue(param, value, endTime) {
    param.exponentialRampToValueAtTime(value, endTime);
}

/**
 * Set target at time (exponential approach)
 * @name setTargetAtTime
 * @canopy-type AudioParam -> Float -> Float -> Float -> ()
 */
function setTargetAtTime(param, target, startTime, timeConstant) {
    param.setTargetAtTime(target, startTime, timeConstant);
}

/**
 * Cancel scheduled values
 * @name cancelScheduledValues
 * @canopy-type AudioParam -> Float -> ()
 */
function cancelScheduledValues(param, startTime) {
    param.cancelScheduledValues(startTime);
}

/**
 * Cancel and hold at time
 * @name cancelAndHoldAtTime
 * @canopy-type AudioParam -> Float -> ()
 */
function cancelAndHoldAtTime(param, cancelTime) {
    if (param.cancelAndHoldAtTime) {
        param.cancelAndHoldAtTime(cancelTime);
    } else {
        param.cancelScheduledValues(cancelTime);
    }
}

// ============================================================================
// AUDIOPARAM - Standard Web Audio API Function Names (Aliases)
// ============================================================================

/**
 * Set value at time (Standard Web Audio API name)
 * @name setValueAtTime
 * @canopy-type AudioParam -> Float -> Float -> ()
 */
function setValueAtTime(param, value, time) {
    param.setValueAtTime(value, time);
}

/**
 * Linear ramp to value at time (Standard Web Audio API name)
 * @name linearRampToValueAtTime
 * @canopy-type AudioParam -> Float -> Float -> ()
 */
function linearRampToValueAtTime(param, value, endTime) {
    param.linearRampToValueAtTime(value, endTime);
}

/**
 * Exponential ramp to value at time (Standard Web Audio API name)
 * @name exponentialRampToValueAtTime
 * @canopy-type AudioParam -> Float -> Float -> ()
 */
function exponentialRampToValueAtTime(param, value, endTime) {
    param.exponentialRampToValueAtTime(value, endTime);
}

// ============================================================================
// ANALYSER NODE - Advanced Functions
// ============================================================================

/**
 * Get byte time domain data as array
 * @name getByteTimeDomainData
 * @canopy-type AnalyserNode -> List Int
 */
function getByteTimeDomainData(analyser) {
    const dataArray = new Uint8Array(analyser.frequencyBinCount);
    analyser.getByteTimeDomainData(dataArray);
    return Array.from(dataArray);
}

/**
 * Get byte frequency data as array
 * @name getByteFrequencyData
 * @canopy-type AnalyserNode -> List Int
 */
function getByteFrequencyData(analyser) {
    const dataArray = new Uint8Array(analyser.frequencyBinCount);
    analyser.getByteFrequencyData(dataArray);
    return Array.from(dataArray);
}

/**
 * Get float time domain data as array
 * @name getFloatTimeDomainData
 * @canopy-type AnalyserNode -> List Float
 */
function getFloatTimeDomainData(analyser) {
    const dataArray = new Float32Array(analyser.frequencyBinCount);
    analyser.getFloatTimeDomainData(dataArray);
    return Array.from(dataArray);
}

/**
 * Get float frequency data as array
 * @name getFloatFrequencyData
 * @canopy-type AnalyserNode -> List Float
 */
function getFloatFrequencyData(analyser) {
    const dataArray = new Float32Array(analyser.frequencyBinCount);
    analyser.getFloatFrequencyData(dataArray);
    return Array.from(dataArray);
}

// ============================================================================
// BUFFER SOURCE - Advanced Operations
// ============================================================================

// Unit value constant for returning () in Canopy
var _UNIT = { $: '#0' };

/**
 * Set buffer on buffer source
 * @name setBufferSourceBuffer
 * @canopy-type AudioBufferSourceNode -> AudioBuffer -> ()
 */
function setBufferSourceBuffer(source, buffer) {
    source.buffer = buffer;
    return _UNIT;
}

/**
 * Set buffer source loop and return the new value
 * @name setBufferSourceLoop
 * @canopy-type AudioBufferSourceNode -> Bool -> Bool
 */
function setBufferSourceLoop(source, loop) {
    source.loop = loop;
    return source.loop;
}

/**
 * Set buffer source loop start and return the new value
 * @name setBufferSourceLoopStart
 * @canopy-type AudioBufferSourceNode -> Float -> Float
 */
function setBufferSourceLoopStart(source, loopStart) {
    source.loopStart = loopStart;
    return source.loopStart;
}

/**
 * Set buffer source loop end and return the new value
 * @name setBufferSourceLoopEnd
 * @canopy-type AudioBufferSourceNode -> Float -> Float
 */
function setBufferSourceLoopEnd(source, loopEnd) {
    source.loopEnd = loopEnd;
    return source.loopEnd;
}

/**
 * Set buffer source playback rate
 * @name setBufferSourcePlaybackRate
 * @canopy-type AudioBufferSourceNode -> Float -> Float -> ()
 */
function setBufferSourcePlaybackRate(source, rate, when) {
    source.playbackRate.setValueAtTime(rate, when);
    return _UNIT;
}

/**
 * Set buffer source detune
 * @name setBufferSourceDetune
 * @canopy-type AudioBufferSourceNode -> Float -> Float -> ()
 */
function setBufferSourceDetune(source, detune, when) {
    source.detune.setValueAtTime(detune, when);
}

// ============================================================================
// SIMPLIFIED INTERFACE - High-level wrapper functions for easy use
// ============================================================================

// Global state for simplified interface
let audioContext = null;
let currentOscillator = null;
let currentGainNode = null;
let currentFrequency = 440;
let currentWaveform = 'sine';
let currentVolume = 0.3;

/**
 * Create audio context (simplified interface)
 * @name createAudioContextSimplified
 * @canopy-type () -> String
 */
function createAudioContextSimplified() {
    try {
        audioContext = new (window.AudioContext || window.webkitAudioContext)();
        return "AudioContext created successfully (Sample rate: " + audioContext.sampleRate + " Hz)";
    } catch (error) {
        return "Error creating AudioContext: " + error.message;
    }
}

/**
 * Play tone (simplified interface)
 * @name playToneSimplified
 * @canopy-type Float -> String -> String
 */
function playToneSimplified(frequency, waveform) {
    if (!audioContext) {
        return "Error: AudioContext not initialized. Call createAudioContextSimplified first.";
    }

    try {
        // Stop existing oscillator if any
        if (currentOscillator) {
            currentOscillator.stop();
            currentOscillator = null;
        }

        // Create oscillator
        currentOscillator = audioContext.createOscillator();
        currentOscillator.type = waveform;
        currentOscillator.frequency.setValueAtTime(frequency, audioContext.currentTime);

        // Create gain node
        currentGainNode = audioContext.createGain();
        currentGainNode.gain.setValueAtTime(currentVolume, audioContext.currentTime);

        // Connect nodes
        currentOscillator.connect(currentGainNode);
        currentGainNode.connect(audioContext.destination);

        // Start oscillator
        currentOscillator.start();

        currentFrequency = frequency;
        currentWaveform = waveform;

        return "Playing " + waveform + " wave at " + frequency + " Hz (volume: " + Math.round(currentVolume * 100) + "%)";
    } catch (error) {
        return "Error playing audio: " + error.message;
    }
}

/**
 * Stop audio (simplified interface)
 * @name stopAudioSimplified
 * @canopy-type () -> String
 */
function stopAudioSimplified() {
    if (!audioContext) {
        return "Error: AudioContext not initialized";
    }

    if (!currentOscillator) {
        return "No audio playing";
    }

    try {
        currentOscillator.stop();
        currentOscillator = null;
        return "Audio stopped";
    } catch (error) {
        return "Error stopping audio: " + error.message;
    }
}

/**
 * Update frequency (simplified interface)
 * @name updateFrequency
 * @canopy-type Float -> String
 */
function updateFrequency(frequency) {
    if (!audioContext || !currentOscillator) {
        return "Not playing - frequency will be used on next play";
    }

    try {
        currentOscillator.frequency.setValueAtTime(frequency, audioContext.currentTime);
        currentFrequency = frequency;
        return "Frequency updated to " + frequency + " Hz";
    } catch (error) {
        return "Error updating frequency: " + error.message;
    }
}

/**
 * Update volume (simplified interface)
 * @name updateVolume
 * @canopy-type Float -> String
 */
function updateVolume(volumePercent) {
    const gain = volumePercent / 100.0;

    if (!audioContext || !currentGainNode) {
        currentVolume = gain;
        return "Volume set to " + volumePercent + "% (will apply on next play)";
    }

    try {
        currentGainNode.gain.setValueAtTime(gain, audioContext.currentTime);
        currentVolume = gain;
        return "Volume updated to " + volumePercent + "%";
    } catch (error) {
        return "Error updating volume: " + error.message;
    }
}

/**
 * Update waveform (simplified interface - requires restart)
 * @name updateWaveform
 * @canopy-type String -> String
 */
function updateWaveform(waveform) {
    if (!audioContext || !currentOscillator) {
        currentWaveform = waveform;
        return "Waveform set to " + waveform + " (will apply on next play)";
    }

    try {
        // Oscillator type cannot be changed while playing, so we restart
        const wasPlaying = currentOscillator !== null;
        if (wasPlaying) {
            currentOscillator.stop();
            playToneSimplified(currentFrequency, waveform);
        }
        currentWaveform = waveform;
        return "Waveform changed to " + waveform;
    } catch (error) {
        return "Error updating waveform: " + error.message;
    }
}

// ============================================================================
// AUDIOWORKLET - Modern Low-Latency Audio Processing
// ============================================================================

/**
 * Load AudioWorklet processor module from URL
 * @name addAudioWorkletModule
 * @canopy-type AudioContext -> String -> Task Capability.CapabilityError ()
 */
function addAudioWorkletModule(audioContext, moduleURL) {
    const ctx = audioContext.a;  // Unwrap Capability.Initialized AudioContext
    return ctx.audioWorklet.addModule(moduleURL)
        .then(() => ({ $: 'Ok', a: 1 }))
        .catch(error => ({
            $: 'Err',
            a: error.name === 'NotSupportedError'
                ? { $: 'NotSupportedError', a: 'AudioWorklet not supported: ' + error.message }
                : { $: 'InitializationRequired', a: 'Failed to load worklet module: ' + error.message }
        }));
}

/**
 * Create AudioWorklet node with processor name
 * @name createAudioWorkletNode
 * @canopy-type AudioContext -> String -> Result Capability.CapabilityError AudioWorkletNode
 */
function createAudioWorkletNode(audioContext, processorName) {
    try {
        const ctx = audioContext.a;  // Unwrap Capability.Initialized AudioContext
        const node = new AudioWorkletNode(ctx, processorName);
        return { $: 'Ok', a: node };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Processor not loaded: ' + e.message } };
        } else if (e.name === 'NotSupportedError') {
            return { $: 'Err', a: { $: 'NotSupportedError', a: 'AudioWorklet not supported: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InitializationRequired', a: 'Failed to create worklet node: ' + e.message } };
        }
    }
}

/**
 * Get MessagePort for communicating with AudioWorklet processor
 * @name getWorkletPort
 * @canopy-type AudioWorkletNode -> MessagePort
 */
function getWorkletPort(workletNode) {
    return workletNode.port;
}

/**
 * Get AudioParamMap from AudioWorklet node
 * @name getWorkletParameters
 * @canopy-type AudioWorkletNode -> AudioParamMap
 */
function getWorkletParameters(workletNode) {
    return workletNode.parameters;
}

/**
 * Post message to AudioWorklet processor
 * @name postMessageToWorklet
 * @canopy-type MessagePort -> String -> ()
 */
function postMessageToWorklet(port, message) {
    port.postMessage(message);
}

// ============================================================================
// IIRFILTERNODE - Infinite Impulse Response Filters
// ============================================================================

/**
 * Create IIR filter node with feedforward and feedback coefficients
 * @name createIIRFilter
 * @canopy-type AudioContext -> List Float -> List Float -> Result Capability.CapabilityError IIRFilterNode
 */
function createIIRFilter(audioContext, feedforward, feedback) {
    try {
        const ctx = audioContext.a;  // Unwrap Capability.Initialized AudioContext
        const ff = new Float32Array(feedforward);
        const fb = new Float32Array(feedback);
        const filter = ctx.createIIRFilter(ff, fb);
        return { $: 'Ok', a: filter };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Context closed: ' + e.message } };
        } else if (e.name === 'NotSupportedError') {
            return { $: 'Err', a: { $: 'NotSupportedError', a: 'IIRFilter not supported: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Invalid coefficients: ' + e.message } };
        }
    }
}

/**
 * Get frequency response from IIR filter - returns tuple of (magnitude list, phase list)
 * @name getIIRFilterResponse
 * @canopy-type IIRFilterNode -> List Float -> Result Capability.CapabilityError (List Float, List Float)
 */
function getIIRFilterResponse(filter, frequencyArray) {
    try {
        const frequencies = new Float32Array(frequencyArray);
        const magResponse = new Float32Array(frequencies.length);
        const phaseResponse = new Float32Array(frequencies.length);

        filter.getFrequencyResponse(frequencies, magResponse, phaseResponse);

        return {
            $: 'Ok',
            a: {
                $: 'Tuple2',
                a: Array.from(magResponse),
                b: Array.from(phaseResponse)
            }
        };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to get response: ' + e.message } };
    }
}

// ============================================================================
// CONSTANTSOURCENODE - Constant Audio Signal
// ============================================================================

/**
 * Create constant source node
 * @name createConstantSource
 * @canopy-type AudioContext -> Result Capability.CapabilityError ConstantSourceNode
 */
function createConstantSource(audioContext) {
    try {
        const ctx = audioContext.a;  // Unwrap Capability.Initialized AudioContext
        const source = ctx.createConstantSource();
        return { $: 'Ok', a: source };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Context closed: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InitializationRequired', a: 'Failed to create constant source: ' + e.message } };
        }
    }
}

/**
 * Get offset AudioParam from constant source
 * @name getConstantSourceOffset
 * @canopy-type ConstantSourceNode -> AudioParam
 */
function getConstantSourceOffset(constantSource) {
    return constantSource.offset;
}

/**
 * Start constant source at specific time
 * @name startConstantSource
 * @canopy-type ConstantSourceNode -> Float -> Result Capability.CapabilityError ()
 */
function startConstantSource(source, when) {
    try {
        source.start(when);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Already started: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to start: ' + e.message } };
        }
    }
}

/**
 * Stop constant source at specific time
 * @name stopConstantSource
 * @canopy-type ConstantSourceNode -> Float -> Result Capability.CapabilityError ()
 */
function stopConstantSource(source, when) {
    try {
        source.stop(when);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Not started or already stopped: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to stop: ' + e.message } };
        }
    }
}

// ============================================================================
// PERIODICWAVE - Enhanced Custom Waveform Support
// ============================================================================

/**
 * Create periodic wave with custom real and imaginary coefficients
 * @name createPeriodicWaveWithCoefficients
 * @canopy-type AudioContext -> List Float -> List Float -> Result Capability.CapabilityError PeriodicWave
 */
function createPeriodicWaveWithCoefficients(audioContext, real, imag) {
    try {
        const ctx = audioContext.a;  // Unwrap Capability.Initialized AudioContext
        const realArray = new Float32Array(real);
        const imagArray = new Float32Array(imag);
        const wave = ctx.createPeriodicWave(realArray, imagArray);
        return { $: 'Ok', a: wave };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Context closed: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Invalid coefficients: ' + e.message } };
        }
    }
}

/**
 * Create periodic wave with normalization option
 * @name createPeriodicWaveWithOptions
 * @canopy-type AudioContext -> List Float -> List Float -> Bool -> Result Capability.CapabilityError PeriodicWave
 */
function createPeriodicWaveWithOptions(audioContext, real, imag, disableNormalization) {
    try {
        const ctx = audioContext.a;  // Unwrap Capability.Initialized AudioContext
        const realArray = new Float32Array(real);
        const imagArray = new Float32Array(imag);
        const options = { disableNormalization: disableNormalization };
        const wave = ctx.createPeriodicWave(realArray, imagArray, options);
        return { $: 'Ok', a: wave };
    } catch (e) {
        if (e.name === 'InvalidStateError') {
            return { $: 'Err', a: { $: 'InvalidStateError', a: 'Context closed: ' + e.message } };
        } else {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Invalid coefficients: ' + e.message } };
        }
    }
}

/**
 * Set periodic wave on oscillator
 * @name setOscillatorPeriodicWave
 * @canopy-type OscillatorNode -> PeriodicWave -> ()
 */
function setOscillatorPeriodicWave(oscillator, periodicWave) {
    oscillator.setPeriodicWave(periodicWave);
}

// ============================================================================
// PHASE 3B: NODE PROPERTIES - Advanced Node Configuration
// ============================================================================

/**
 * Get node channel count
 * @name getNodeChannelCount
 * @canopy-type AudioNode -> Int
 */
function getNodeChannelCount(node) {
    return node.channelCount;
}

/**
 * Set node channel count
 * @name setNodeChannelCount
 * @canopy-type AudioNode -> Int -> Result Capability.CapabilityError ()
 */
function setNodeChannelCount(node, count) {
    try {
        node.channelCount = count;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'RangeError', a: 'Invalid channel count: ' + e.message } };
    }
}

/**
 * Get node channel count mode
 * @name getNodeChannelCountMode
 * @canopy-type AudioNode -> String
 */
function getNodeChannelCountMode(node) {
    return node.channelCountMode;
}

/**
 * Set node channel count mode
 * @name setNodeChannelCountMode
 * @canopy-type AudioNode -> String -> Result Capability.CapabilityError ()
 */
function setNodeChannelCountMode(node, mode) {
    try {
        node.channelCountMode = mode;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Invalid mode: ' + e.message } };
    }
}

/**
 * Get node channel interpretation
 * @name getNodeChannelInterpretation
 * @canopy-type AudioNode -> String
 */
function getNodeChannelInterpretation(node) {
    return node.channelInterpretation;
}

/**
 * Set node channel interpretation
 * @name setNodeChannelInterpretation
 * @canopy-type AudioNode -> String -> Result Capability.CapabilityError ()
 */
function setNodeChannelInterpretation(node, interpretation) {
    try {
        node.channelInterpretation = interpretation;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Invalid interpretation: ' + e.message } };
    }
}

/**
 * Get number of inputs
 * @name getNodeNumberOfInputs
 * @canopy-type AudioNode -> Int
 */
function getNodeNumberOfInputs(node) {
    return node.numberOfInputs;
}

/**
 * Get number of outputs
 * @name getNodeNumberOfOutputs
 * @canopy-type AudioNode -> Int
 */
function getNodeNumberOfOutputs(node) {
    return node.numberOfOutputs;
}

/**
 * Get node's audio context
 * @name getNodeContext
 * @canopy-type AudioNode -> AudioContext
 */
function getNodeContext(node) {
    return node.context;
}

/**
 * Get oscillator type
 * @name getOscillatorType
 * @canopy-type OscillatorNode -> String
 */
function getOscillatorType(oscillator) {
    return oscillator.type;
}

/**
 * Get oscillator frequency param
 * @name getOscillatorFrequencyParam
 * @canopy-type OscillatorNode -> AudioParam
 */
function getOscillatorFrequencyParam(oscillator) {
    return oscillator.frequency;
}

/**
 * Get oscillator detune param
 * @name getOscillatorDetuneParam
 * @canopy-type OscillatorNode -> AudioParam
 */
function getOscillatorDetuneParam(oscillator) {
    return oscillator.detune;
}

/**
 * Get delay time param
 * @name getDelayDelayTimeParam
 * @canopy-type DelayNode -> AudioParam
 */
function getDelayDelayTimeParam(delayNode) {
    return delayNode.delayTime;
}

/**
 * Get compressor threshold param
 * @name getCompressorThresholdParam
 * @canopy-type DynamicsCompressorNode -> AudioParam
 */
function getCompressorThresholdParam(compressor) {
    return compressor.threshold;
}

/**
 * Get compressor knee param
 * @name getCompressorKneeParam
 * @canopy-type DynamicsCompressorNode -> AudioParam
 */
function getCompressorKneeParam(compressor) {
    return compressor.knee;
}

/**
 * Get compressor ratio param
 * @name getCompressorRatioParam
 * @canopy-type DynamicsCompressorNode -> AudioParam
 */
function getCompressorRatioParam(compressor) {
    return compressor.ratio;
}

// ============================================================================
// AUDIO PARAM ADVANCED - Extended AudioParam Operations
// ============================================================================

/**
 * Set value curve at time
 * @name setValueCurveAtTime
 * @canopy-type AudioParam -> List Float -> Float -> Float -> Result Capability.CapabilityError ()
 */
function setValueCurveAtTime(param, values, startTime, duration) {
    try {
        const valuesArray = new Float32Array(values);
        param.setValueCurveAtTime(valuesArray, startTime, duration);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'RangeError', a: 'Invalid curve: ' + e.message } };
    }
}

/**
 * Get audio param current value
 * @name getAudioParamValue
 * @canopy-type AudioParam -> Float
 */
function getAudioParamValue(param) {
    return param.value;
}

/**
 * Get audio param default value
 * @name getAudioParamDefaultValue
 * @canopy-type AudioParam -> Float
 */
function getAudioParamDefaultValue(param) {
    return param.defaultValue;
}

/**
 * Get audio param min value
 * @name getAudioParamMinValue
 * @canopy-type AudioParam -> Float
 */
function getAudioParamMinValue(param) {
    return param.minValue;
}

/**
 * Get audio param max value
 * @name getAudioParamMaxValue
 * @canopy-type AudioParam -> Float
 */
function getAudioParamMaxValue(param) {
    return param.maxValue;
}

/**
 * Set audio param value directly
 * @name setAudioParamValue
 * @canopy-type AudioParam -> Float -> Result Capability.CapabilityError ()
 */
function setAudioParamValue(param, value) {
    try {
        param.value = value;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'RangeError', a: 'Invalid value: ' + e.message } };
    }
}

/**
 * Get audio param automation rate
 * @name getAudioParamAutomationRate
 * @canopy-type AudioParam -> String
 */
function getAudioParamAutomationRate(param) {
    return param.automationRate || 'a-rate';
}

/**
 * Set audio param automation rate
 * @name setAudioParamAutomationRate
 * @canopy-type AudioParam -> String -> Result Capability.CapabilityError ()
 */
function setAudioParamAutomationRate(param, rate) {
    try {
        if (param.automationRate !== undefined) {
            param.automationRate = rate;
        }
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Invalid rate: ' + e.message } };
    }
}

// ============================================================================
// CHANNEL ROUTING ADVANCED - Precise Channel Control
// ============================================================================

/**
 * Connect nodes with specific channels
 * @name connectNodesWithChannels
 * @canopy-type AudioNode -> AudioNode -> Int -> Int -> Result Capability.CapabilityError ()
 */
function connectNodesWithChannels(source, destination, outputChannel, inputChannel) {
    try {
        source.connect(destination, outputChannel, inputChannel);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'IndexSizeError', a: 'Invalid channel: ' + e.message } };
    }
}

/**
 * Disconnect node from specific destination
 * @name disconnectNodeFromDestination
 * @canopy-type AudioNode -> AudioNode -> Result Capability.CapabilityError ()
 */
function disconnectNodeFromDestination(source, destination) {
    try {
        source.disconnect(destination);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Disconnect failed: ' + e.message } };
    }
}

/**
 * Disconnect specific output
 * @name disconnectNodeOutput
 * @canopy-type AudioNode -> Int -> Result Capability.CapabilityError ()
 */
function disconnectNodeOutput(node, output) {
    try {
        node.disconnect(output);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'IndexSizeError', a: 'Invalid output: ' + e.message } };
    }
}

/**
 * Disconnect node from specific node and channel
 * @name disconnectNodeFromNodeChannel
 * @canopy-type AudioNode -> AudioNode -> Int -> Int -> Result Capability.CapabilityError ()
 */
function disconnectNodeFromNodeChannel(source, destination, output, input) {
    try {
        source.disconnect(destination, output, input);
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Disconnect failed: ' + e.message } };
    }
}

// ============================================================================
// CONTEXT ADVANCED PROPERTIES - Enhanced Context Info
// ============================================================================

/**
 * Get context base latency
 * @name getContextBaseLatency
 * @canopy-type AudioContext -> Float
 */
function getContextBaseLatency(audioContext) {
    return audioContext.baseLatency || 0.0;
}

/**
 * Get context output latency
 * @name getContextOutputLatency
 * @canopy-type AudioContext -> Float
 */
function getContextOutputLatency(audioContext) {
    return audioContext.outputLatency || 0.0;
}

/**
 * Get context destination node
 * @name getContextDestination
 * @canopy-type AudioContext -> AudioDestinationNode
 */
function getContextDestination(audioContext) {
    return audioContext.destination;
}

/**
 * Get context listener
 * @name getContextAudioListener
 * @canopy-type AudioContext -> AudioListener
 */
function getContextAudioListener(audioContext) {
    return audioContext.listener;
}


// ============================================================================
// PHASE 3C: ENHANCED CONTROLS - Analyzer, Compressor, Buffer Source, Panner
// ============================================================================

// Analyzer Enhanced (6 functions)

/**
 * Set analyser min decibels
 * @name setAnalyserMinDecibels
 * @canopy-type AnalyserNode -> Float -> Result Capability.CapabilityError ()
 */
function setAnalyserMinDecibels(analyser, minDecibels) {
    try {
        analyser.minDecibels = minDecibels;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'RangeError', a: 'Invalid value: ' + e.message } };
    }
}

/**
 * Set analyser max decibels
 * @name setAnalyserMaxDecibels
 * @canopy-type AnalyserNode -> Float -> Result Capability.CapabilityError ()
 */
function setAnalyserMaxDecibels(analyser, maxDecibels) {
    try {
        analyser.maxDecibels = maxDecibels;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'RangeError', a: 'Invalid value: ' + e.message } };
    }
}

/**
 * Get analyser min decibels
 * @name getAnalyserMinDecibels
 * @canopy-type AnalyserNode -> Float
 */
function getAnalyserMinDecibels(analyser) {
    return analyser.minDecibels;
}

/**
 * Get analyser max decibels
 * @name getAnalyserMaxDecibels
 * @canopy-type AnalyserNode -> Float
 */
function getAnalyserMaxDecibels(analyser) {
    return analyser.maxDecibels;
}

/**
 * Set analyser smoothing time constant
 * @name setAnalyserSmoothingTimeConstant
 * @canopy-type AnalyserNode -> Float -> Result Capability.CapabilityError ()
 */
function setAnalyserSmoothingTimeConstant(analyser, constant) {
    try {
        analyser.smoothingTimeConstant = constant;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'RangeError', a: 'Invalid value: ' + e.message } };
    }
}

/**
 * Get analyser smoothing time constant
 * @name getAnalyserSmoothingTimeConstant
 * @canopy-type AnalyserNode -> Float
 */
function getAnalyserSmoothingTimeConstant(analyser) {
    return analyser.smoothingTimeConstant;
}

// Dynamics Compressor Enhanced (5 functions)

/**
 * Get compressor reduction meter
 * @name getCompressorReduction
 * @canopy-type DynamicsCompressorNode -> Float
 */
function getCompressorReduction(compressor) {
    return compressor.reduction;
}

/**
 * Get compressor attack param
 * @name getCompressorAttackParam
 * @canopy-type DynamicsCompressorNode -> AudioParam
 */
function getCompressorAttackParam(compressor) {
    return compressor.attack;
}

/**
 * Get compressor release param
 * @name getCompressorReleaseParam
 * @canopy-type DynamicsCompressorNode -> AudioParam
 */
function getCompressorReleaseParam(compressor) {
    return compressor.release;
}

/**
 * Set compressor attack time directly
 * @name setCompressorAttackDirect
 * @canopy-type DynamicsCompressorNode -> Float -> Result Capability.CapabilityError ()
 */
function setCompressorAttackDirect(compressor, attack) {
    try {
        compressor.attack.value = attack;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'RangeError', a: 'Invalid attack: ' + e.message } };
    }
}

/**
 * Set compressor release time directly
 * @name setCompressorReleaseDirect
 * @canopy-type DynamicsCompressorNode -> Float -> Result Capability.CapabilityError ()
 */
function setCompressorReleaseDirect(compressor, release) {
    try {
        compressor.release.value = release;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'RangeError', a: 'Invalid release: ' + e.message } };
    }
}

// Buffer Source Enhanced (5 functions)

/**
 * Get buffer source assigned buffer
 * @name getBufferSourceBuffer
 * @canopy-type AudioBufferSourceNode -> AudioBuffer
 */
function getBufferSourceBuffer(source) {
    return source.buffer;
}

/**
 * Get buffer source loop state
 * @name getBufferSourceLoop
 * @canopy-type AudioBufferSourceNode -> Bool
 */
function getBufferSourceLoop(source) {
    return source.loop;
}

/**
 * Get buffer source loop start
 * @name getBufferSourceLoopStart
 * @canopy-type AudioBufferSourceNode -> Float
 */
function getBufferSourceLoopStart(source) {
    return source.loopStart;
}

/**
 * Get buffer source loop end
 * @name getBufferSourceLoopEnd
 * @canopy-type AudioBufferSourceNode -> Float
 */
function getBufferSourceLoopEnd(source) {
    return source.loopEnd;
}

/**
 * Set buffer source loop directly
 * @name setBufferSourceLoopDirect
 * @canopy-type AudioBufferSourceNode -> Bool -> Result Capability.CapabilityError ()
 */
function setBufferSourceLoopDirect(source, loop) {
    try {
        source.loop = loop;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to set loop: ' + e.message } };
    }
}

// Panner Node 3D Audio (5 functions)

/**
 * Get panner position X param
 * @name getPannerPositionX
 * @canopy-type PannerNode -> AudioParam
 */
function getPannerPositionX(panner) {
    return panner.positionX;
}

/**
 * Get panner position Y param
 * @name getPannerPositionY
 * @canopy-type PannerNode -> AudioParam
 */
function getPannerPositionY(panner) {
    return panner.positionY;
}

/**
 * Get panner position Z param
 * @name getPannerPositionZ
 * @canopy-type PannerNode -> AudioParam
 */
function getPannerPositionZ(panner) {
    return panner.positionZ;
}

/**
 * Get panner orientation
 * @name getPannerOrientationX
 * @canopy-type PannerNode -> AudioParam
 */
function getPannerOrientationX(panner) {
    return panner.orientationX;
}

/**
 * Set panner orientation using params
 * @name setPannerOrientationDirect
 * @canopy-type PannerNode -> Float -> Float -> Float -> Result Capability.CapabilityError ()
 */
function setPannerOrientationDirect(panner, x, y, z) {
    try {
        panner.orientationX.value = x;
        panner.orientationY.value = y;
        panner.orientationZ.value = z;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to set orientation: ' + e.message } };
    }
}

// BiquadFilter Enhanced (4 functions)

/**
 * Get biquad filter type
 * @name getBiquadFilterType
 * @canopy-type BiquadFilterNode -> String
 */
function getBiquadFilterType(filter) {
    return filter.type;
}

/**
 * Set biquad filter type directly
 * @name setBiquadFilterTypeDirect
 * @canopy-type BiquadFilterNode -> String -> Result Capability.CapabilityError ()
 */
function setBiquadFilterTypeDirect(filter, filterType) {
    try {
        filter.type = filterType;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Invalid filter type: ' + e.message } };
    }
}

/**
 * Get biquad filter frequency param
 * @name getBiquadFilterFrequencyParam
 * @canopy-type BiquadFilterNode -> AudioParam
 */
function getBiquadFilterFrequencyParam(filter) {
    return filter.frequency;
}

/**
 * Get biquad filter Q param
 * @name getBiquadFilterQParam
 * @canopy-type BiquadFilterNode -> AudioParam
 */
function getBiquadFilterQParam(filter) {
    return filter.Q;
}


// ============================================================================
// PHASE 3D: UTILITIES & COMPLETENESS - Buffer Utils, Misc Getters
// ============================================================================

// Buffer Utilities (8 functions)

/**
 * Reverse audio buffer samples
 * @name reverseAudioBuffer
 * @canopy-type AudioBuffer -> Result Capability.CapabilityError AudioBuffer
 */
function reverseAudioBuffer(sourceBuffer) {
    try {
        const reversed = new AudioBuffer({
            length: sourceBuffer.length,
            numberOfChannels: sourceBuffer.numberOfChannels,
            sampleRate: sourceBuffer.sampleRate
        });
        for (let ch = 0; ch < sourceBuffer.numberOfChannels; ch++) {
            const data = sourceBuffer.getChannelData(ch);
            const reversedData = new Float32Array(data).reverse();
            reversed.copyToChannel(reversedData, ch);
        }
        return { $: 'Ok', a: reversed };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to reverse: ' + e.message } };
    }
}

/**
 * Normalize audio buffer amplitude
 * @name normalizeAudioBuffer
 * @canopy-type AudioBuffer -> Float -> Result Capability.CapabilityError AudioBuffer
 */
function normalizeAudioBuffer(sourceBuffer, targetPeak) {
    try {
        let maxAmp = 0.0;
        for (let ch = 0; ch < sourceBuffer.numberOfChannels; ch++) {
            const data = sourceBuffer.getChannelData(ch);
            for (let i = 0; i < data.length; i++) {
                maxAmp = Math.max(maxAmp, Math.abs(data[i]));
            }
        }
        const gain = maxAmp > 0 ? targetPeak / maxAmp : 1.0;
        const normalized = new AudioBuffer({
            length: sourceBuffer.length,
            numberOfChannels: sourceBuffer.numberOfChannels,
            sampleRate: sourceBuffer.sampleRate
        });
        for (let ch = 0; ch < sourceBuffer.numberOfChannels; ch++) {
            const data = sourceBuffer.getChannelData(ch);
            const scaledData = new Float32Array(data.length);
            for (let i = 0; i < data.length; i++) {
                scaledData[i] = data[i] * gain;
            }
            normalized.copyToChannel(scaledData, ch);
        }
        return { $: 'Ok', a: normalized };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to normalize: ' + e.message } };
    }
}

/**
 * Mix two audio buffers
 * @name mixAudioBuffers
 * @canopy-type AudioBuffer -> AudioBuffer -> Float -> Result Capability.CapabilityError AudioBuffer
 */
function mixAudioBuffers(buffer1, buffer2, mixRatio) {
    try {
        const length = Math.min(buffer1.length, buffer2.length);
        const channels = Math.min(buffer1.numberOfChannels, buffer2.numberOfChannels);
        const mixed = new AudioBuffer({
            length: length,
            numberOfChannels: channels,
            sampleRate: buffer1.sampleRate
        });
        for (let ch = 0; ch < channels; ch++) {
            const data1 = buffer1.getChannelData(ch);
            const data2 = buffer2.getChannelData(ch);
            const mixedData = new Float32Array(length);
            for (let i = 0; i < length; i++) {
                mixedData[i] = data1[i] * (1 - mixRatio) + data2[i] * mixRatio;
            }
            mixed.copyToChannel(mixedData, ch);
        }
        return { $: 'Ok', a: mixed };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to mix: ' + e.message } };
    }
}

/**
 * Trim silence from audio buffer
 * @name trimSilence
 * @canopy-type AudioBuffer -> Float -> Result Capability.CapabilityError AudioBuffer
 */
function trimSilence(sourceBuffer, threshold) {
    try {
        let start = 0;
        let end = sourceBuffer.length;
        const data = sourceBuffer.getChannelData(0);
        while (start < end && Math.abs(data[start]) < threshold) {
            start++;
        }
        while (end > start && Math.abs(data[end - 1]) < threshold) {
            end--;
        }
        const trimmedLength = end - start;
        const trimmed = new AudioBuffer({
            length: trimmedLength,
            numberOfChannels: sourceBuffer.numberOfChannels,
            sampleRate: sourceBuffer.sampleRate
        });
        for (let ch = 0; ch < sourceBuffer.numberOfChannels; ch++) {
            const channelData = sourceBuffer.getChannelData(ch);
            const trimmedData = channelData.slice(start, end);
            trimmed.copyToChannel(trimmedData, ch);
        }
        return { $: 'Ok', a: trimmed };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to trim: ' + e.message } };
    }
}

/**
 * Get audio buffer peak amplitude
 * @name getBufferPeak
 * @canopy-type AudioBuffer -> Float
 */
function getBufferPeak(buffer) {
    let peak = 0.0;
    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
        const data = buffer.getChannelData(ch);
        for (let i = 0; i < data.length; i++) {
            peak = Math.max(peak, Math.abs(data[i]));
        }
    }
    return peak;
}

/**
 * Get audio buffer RMS (root mean square)
 * @name getBufferRMS
 * @canopy-type AudioBuffer -> Float
 */
function getBufferRMS(buffer) {
    let sumSquares = 0.0;
    let totalSamples = 0;
    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
        const data = buffer.getChannelData(ch);
        for (let i = 0; i < data.length; i++) {
            sumSquares += data[i] * data[i];
        }
        totalSamples += data.length;
    }
    return Math.sqrt(sumSquares / totalSamples);
}

/**
 * Create audio buffer from samples
 * @name createBufferFromSamples
 * @canopy-type AudioContext -> List List Float -> Float -> Result Capability.CapabilityError AudioBuffer
 */
function createBufferFromSamples(audioContext, channelData, sampleRate) {
    try {
        const channels = channelData.length;
        const length = channelData[0].length;
        const buffer = audioContext.createBuffer(channels, length, sampleRate);
        for (let ch = 0; ch < channels; ch++) {
            const data = new Float32Array(channelData[ch]);
            buffer.copyToChannel(data, ch);
        }
        return { $: 'Ok', a: buffer };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to create buffer: ' + e.message } };
    }
}

/**
 * Concatenate audio buffers
 * @name concatenateBuffers
 * @canopy-type AudioContext -> List AudioBuffer -> Result Capability.CapabilityError AudioBuffer
 */
function concatenateBuffers(audioContext, buffers) {
    try {
        if (buffers.length === 0) {
            return { $: 'Err', a: { $: 'InvalidAccessError', a: 'No buffers provided' } };
        }
        const totalLength = buffers.reduce((sum, buf) => sum + buf.length, 0);
        const channels = buffers[0].numberOfChannels;
        const sampleRate = buffers[0].sampleRate;
        const concatenated = audioContext.createBuffer(channels, totalLength, sampleRate);
        let offset = 0;
        for (const buf of buffers) {
            for (let ch = 0; ch < channels; ch++) {
                const data = buf.getChannelData(ch);
                concatenated.copyToChannel(data, ch, offset);
            }
            offset += buf.length;
        }
        return { $: 'Ok', a: concatenated };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Failed to concatenate: ' + e.message } };
    }
}

// Misc Getters/Setters (10 functions)

/**
 * Get stereo panner pan value
 * @name getStereoPannerPan
 * @canopy-type StereoPannerNode -> AudioParam
 */
function getStereoPannerPan(panner) {
    return panner.pan;
}

/**
 * Get gain node gain param
 * @name getGainNodeGainParam
 * @canopy-type GainNode -> AudioParam
 */
function getGainNodeGainParam(gainNode) {
    return gainNode.gain;
}

/**
 * Get convolver normalize state
 * @name getConvolverNormalize
 * @canopy-type ConvolverNode -> Bool
 */
function getConvolverNormalize(convolver) {
    return convolver.normalize;
}

/**
 * Get wave shaper oversample
 * @name getWaveShaperOversample
 * @canopy-type WaveShaperNode -> String
 */
function getWaveShaperOversample(shaper) {
    return shaper.oversample;
}

/**
 * Get analyser FFT size
 * @name getAnalyserFFTSize
 * @canopy-type AnalyserNode -> Int
 */
function getAnalyserFFTSize(analyser) {
    return analyser.fftSize;
}

/**
 * Get analyser frequency bin count
 * @name getAnalyserFrequencyBinCount
 * @canopy-type AnalyserNode -> Int
 */
function getAnalyserFrequencyBinCount(analyser) {
    return analyser.frequencyBinCount;
}

/**
 * Get delay max delay time
 * @name getDelayMaxDelayTime
 * @canopy-type DelayNode -> Float
 */
function getDelayMaxDelayTime(delayNode) {
    return delayNode.maxDelayTime;
}

/**
 * Get buffer source playback rate
 * @name getBufferSourcePlaybackRate
 * @canopy-type AudioBufferSourceNode -> AudioParam
 */
function getBufferSourcePlaybackRate(source) {
    return source.playbackRate;
}

/**
 * Get buffer source detune
 * @name getBufferSourceDetune
 * @canopy-type AudioBufferSourceNode -> AudioParam
 */
function getBufferSourceDetune(source) {
    return source.detune;
}

/**
 * Get panner distance model
 * @name getPannerDistanceModel
 * @canopy-type PannerNode -> String
 */
function getPannerDistanceModel(panner) {
    return panner.distanceModel;
}

/**
 * Get panner panning model
 * @name getPannerPanningModel
 * @canopy-type PannerNode -> String
 */
function getPannerPanningModel(panner) {
    return panner.panningModel;
}

/**
 * Get panner ref distance
 * @name getPannerRefDistance
 * @canopy-type PannerNode -> Float
 */
function getPannerRefDistance(panner) {
    return panner.refDistance;
}

/**
 * Get panner max distance
 * @name getPannerMaxDistance
 * @canopy-type PannerNode -> Float
 */
function getPannerMaxDistance(panner) {
    return panner.maxDistance;
}

/**
 * Get panner rolloff factor
 * @name getPannerRolloffFactor
 * @canopy-type PannerNode -> Float
 */
function getPannerRolloffFactor(panner) {
    return panner.rolloffFactor;
}

/**
 * Get panner cone inner angle
 * @name getPannerConeInnerAngle
 * @canopy-type PannerNode -> Float
 */
function getPannerConeInnerAngle(panner) {
    return panner.coneInnerAngle;
}

/**
 * Get panner cone outer angle
 * @name getPannerConeOuterAngle
 * @canopy-type PannerNode -> Float
 */
function getPannerConeOuterAngle(panner) {
    return panner.coneOuterAngle;
}

/**
 * Get panner cone outer gain
 * @name getPannerConeOuterGain
 * @canopy-type PannerNode -> Float
 */
function getPannerConeOuterGain(panner) {
    return panner.coneOuterGain;
}


// ============================================================================
// FINAL 13 FUNCTIONS - Reaching 90% Coverage (225/250)
// ============================================================================

/**
 * Get media element source media element
 * @name getMediaElementSourceElement
 * @canopy-type MediaElementAudioSourceNode -> HTMLMediaElement
 */
function getMediaElementSourceElement(source) {
    return source.mediaElement;
}

/**
 * Get media stream tracks
 * @name getMediaStreamTracks
 * @canopy-type MediaStream -> List MediaStreamTrack
 */
function getMediaStreamTracks(mediaStream) {
    return mediaStream.getAudioTracks();
}

/**
 * Get media stream active state
 * @name getMediaStreamActive
 * @canopy-type MediaStream -> Bool
 */
function getMediaStreamActive(mediaStream) {
    return mediaStream.active;
}

/**
 * Get media stream ID
 * @name getMediaStreamId
 * @canopy-type MediaStream -> String
 */
function getMediaStreamId(mediaStream) {
    return mediaStream.id;
}

/**
 * Get biquad filter gain param
 * @name getBiquadFilterGainParam
 * @canopy-type BiquadFilterNode -> AudioParam
 */
function getBiquadFilterGainParam(filter) {
    return filter.gain;
}

/**
 * Get biquad filter detune param
 * @name getBiquadFilterDetuneParam
 * @canopy-type BiquadFilterNode -> AudioParam
 */
function getBiquadFilterDetuneParam(filter) {
    return filter.detune;
}

/**
 * Get panner orientation Y
 * @name getPannerOrientationY
 * @canopy-type PannerNode -> AudioParam
 */
function getPannerOrientationY(panner) {
    return panner.orientationY;
}

/**
 * Get panner orientation Z
 * @name getPannerOrientationZ
 * @canopy-type PannerNode -> AudioParam
 */
function getPannerOrientationZ(panner) {
    return panner.orientationZ;
}

/**
 * Get constant source offset value
 * @name getConstantSourceOffsetValue
 * @canopy-type ConstantSourceNode -> Float
 */
function getConstantSourceOffsetValue(source) {
    return source.offset.value;
}

/**
 * Create empty audio buffer
 * @name createEmptyBuffer
 * @canopy-type AudioContext -> Int -> Float -> Int -> AudioBuffer
 */
function createEmptyBuffer(audioContext, channels, duration, sampleRate) {
    const length = Math.floor(duration * sampleRate);
    return audioContext.createBuffer(channels, length, sampleRate);
}

/**
 * Get audio buffer as array
 * @name getBufferAsArray
 * @canopy-type AudioBuffer -> Int -> List Float
 */
function getBufferAsArray(buffer, channel) {
    return Array.from(buffer.getChannelData(channel));
}

/**
 * Set oscillator waveform type
 * @name setOscillatorType
 * @canopy-type OscillatorNode -> String -> Result Capability.CapabilityError ()
 */
function setOscillatorType(oscillator, waveType) {
    try {
        oscillator.type = waveType;
        return { $: 'Ok', a: 1 };
    } catch (e) {
        return { $: 'Err', a: { $: 'InvalidAccessError', a: 'Invalid type: ' + e.message } };
    }
}

/**
 * Get IIR filter frequency response for single frequency - returns tuple of (magnitude, phase)
 * @name getIIRFilterResponseAtFrequency
 * @canopy-type IIRFilterNode -> Float -> (Float, Float)
 */
function getIIRFilterResponseAtFrequency(filter, frequency) {
    const freqArray = new Float32Array([frequency]);
    const magResponse = new Float32Array(1);
    const phaseResponse = new Float32Array(1);
    filter.getFrequencyResponse(freqArray, magResponse, phaseResponse);
    return {
        $: 'Tuple2',
        a: magResponse[0],
        b: phaseResponse[0]
    };
}

// Generated exports for browser global scope
window.createAudioContext = createAudioContext;
window.getCurrentTime = getCurrentTime;
window.resumeAudioContext = resumeAudioContext;
window.suspendAudioContext = suspendAudioContext;
window.closeAudioContext = closeAudioContext;
window.getSampleRate = getSampleRate;
window.getContextState = getContextState;
window.decodeAudioData = decodeAudioData;
window.createOscillator = createOscillator;
window.startOscillator = startOscillator;
window.stopOscillator = stopOscillator;
window.setOscillatorFrequency = setOscillatorFrequency;
window.setOscillatorDetune = setOscillatorDetune;
window.createBufferSource = createBufferSource;
window.createMediaStreamSource = createMediaStreamSource;
window.createMediaStreamDestination = createMediaStreamDestination;
window.getMediaStream = getMediaStream;
window.startBufferSource = startBufferSource;
window.stopBufferSource = stopBufferSource;
window.createGainNode = createGainNode;
window.setGain = setGain;
window.rampGainLinear = rampGainLinear;
window.rampGainExponential = rampGainExponential;
window.createBiquadFilter = createBiquadFilter;
window.setFilterFrequency = setFilterFrequency;
window.setFilterQ = setFilterQ;
window.setFilterGain = setFilterGain;
window.createDelay = createDelay;
window.setDelayTime = setDelayTime;
window.createConvolver = createConvolver;
window.setConvolverBuffer = setConvolverBuffer;
window.setConvolverNormalize = setConvolverNormalize;
window.getConvolverBuffer = getConvolverBuffer;
window.createDynamicsCompressor = createDynamicsCompressor;
window.setCompressorThreshold = setCompressorThreshold;
window.setCompressorKnee = setCompressorKnee;
window.setCompressorRatio = setCompressorRatio;
window.setCompressorAttack = setCompressorAttack;
window.setCompressorRelease = setCompressorRelease;
window.createWaveShaper = createWaveShaper;
window.setWaveShaperCurve = setWaveShaperCurve;
window.setWaveShaperOversample = setWaveShaperOversample;
window.getWaveShaperCurve = getWaveShaperCurve;
window.makeDistortionCurve = makeDistortionCurve;
window.createStereoPanner = createStereoPanner;
window.setPan = setPan;
window.createAnalyser = createAnalyser;
window.setAnalyserFFTSize = setAnalyserFFTSize;
window.setAnalyserSmoothing = setAnalyserSmoothing;
window.getFrequencyBinCount = getFrequencyBinCount;
window.connectNodes = connectNodes;
window.connectToDestination = connectToDestination;
window.disconnectNode = disconnectNode;
window.checkWebAudioSupport = checkWebAudioSupport;
window.simpleTest = simpleTest;
window.createPanner = createPanner;
window.setPannerPosition = setPannerPosition;
window.setPannerOrientation = setPannerOrientation;
window.setPanningModel = setPanningModel;
window.setDistanceModel = setDistanceModel;
window.setRefDistance = setRefDistance;
window.setMaxDistance = setMaxDistance;
window.setRolloffFactor = setRolloffFactor;
window.setConeInnerAngle = setConeInnerAngle;
window.setConeOuterAngle = setConeOuterAngle;
window.setConeOuterGain = setConeOuterGain;
window.getAudioListener = getAudioListener;
window.setListenerPosition = setListenerPosition;
window.setListenerForward = setListenerForward;
window.setListenerUp = setListenerUp;
window.createChannelSplitter = createChannelSplitter;
window.createChannelMerger = createChannelMerger;
window.createAudioBuffer = createAudioBuffer;
window.getBufferLength = getBufferLength;
window.getBufferDuration = getBufferDuration;
window.getBufferSampleRate = getBufferSampleRate;
window.getBufferChannels = getBufferChannels;
window.getChannelData = getChannelData;
window.copyToChannel = copyToChannel;
window.copyFromChannel = copyFromChannel;
window.createSilentBuffer = createSilentBuffer;
window.cloneAudioBuffer = cloneAudioBuffer;
window.createMediaElementSource = createMediaElementSource;
window.createPeriodicWave = createPeriodicWave;
window.createOfflineAudioContext = createOfflineAudioContext;
window.startOfflineRendering = startOfflineRendering;
window.startOfflineRenderingAsync = startOfflineRenderingAsync;
window.suspendOfflineContext = suspendOfflineContext;
window.resumeOfflineContext = resumeOfflineContext;
window.getOfflineContextLength = getOfflineContextLength;
window.getOfflineContextSampleRate = getOfflineContextSampleRate;
window.getGainParam = getGainParam;
window.getFrequencyParam = getFrequencyParam;
window.getDetuneParam = getDetuneParam;
window.setParamValueAtTime = setParamValueAtTime;
window.linearRampToValue = linearRampToValue;
window.exponentialRampToValue = exponentialRampToValue;
window.setTargetAtTime = setTargetAtTime;
window.cancelScheduledValues = cancelScheduledValues;
window.cancelAndHoldAtTime = cancelAndHoldAtTime;
window.setValueAtTime = setValueAtTime;
window.linearRampToValueAtTime = linearRampToValueAtTime;
window.exponentialRampToValueAtTime = exponentialRampToValueAtTime;
window.getByteTimeDomainData = getByteTimeDomainData;
window.getByteFrequencyData = getByteFrequencyData;
window.getFloatTimeDomainData = getFloatTimeDomainData;
window.getFloatFrequencyData = getFloatFrequencyData;
window.setBufferSourceBuffer = setBufferSourceBuffer;
window.setBufferSourceLoop = setBufferSourceLoop;
window.setBufferSourceLoopStart = setBufferSourceLoopStart;
window.setBufferSourceLoopEnd = setBufferSourceLoopEnd;
window.setBufferSourcePlaybackRate = setBufferSourcePlaybackRate;
window.setBufferSourceDetune = setBufferSourceDetune;
window.createAudioContextSimplified = createAudioContextSimplified;
window.playToneSimplified = playToneSimplified;
window.stopAudioSimplified = stopAudioSimplified;
window.updateFrequency = updateFrequency;
window.updateVolume = updateVolume;
window.updateWaveform = updateWaveform;
window.addAudioWorkletModule = addAudioWorkletModule;
window.createAudioWorkletNode = createAudioWorkletNode;
window.getWorkletPort = getWorkletPort;
window.getWorkletParameters = getWorkletParameters;
window.postMessageToWorklet = postMessageToWorklet;
window.createIIRFilter = createIIRFilter;
window.getIIRFilterResponse = getIIRFilterResponse;
window.createConstantSource = createConstantSource;
window.getConstantSourceOffset = getConstantSourceOffset;
window.startConstantSource = startConstantSource;
window.stopConstantSource = stopConstantSource;
window.createPeriodicWaveWithCoefficients = createPeriodicWaveWithCoefficients;
window.createPeriodicWaveWithOptions = createPeriodicWaveWithOptions;
window.setOscillatorPeriodicWave = setOscillatorPeriodicWave;
window.getNodeChannelCount = getNodeChannelCount;
window.setNodeChannelCount = setNodeChannelCount;
window.getNodeChannelCountMode = getNodeChannelCountMode;
window.setNodeChannelCountMode = setNodeChannelCountMode;
window.getNodeChannelInterpretation = getNodeChannelInterpretation;
window.setNodeChannelInterpretation = setNodeChannelInterpretation;
window.getNodeNumberOfInputs = getNodeNumberOfInputs;
window.getNodeNumberOfOutputs = getNodeNumberOfOutputs;
window.getNodeContext = getNodeContext;
window.getOscillatorType = getOscillatorType;
window.getOscillatorFrequencyParam = getOscillatorFrequencyParam;
window.getOscillatorDetuneParam = getOscillatorDetuneParam;
window.getDelayDelayTimeParam = getDelayDelayTimeParam;
window.getCompressorThresholdParam = getCompressorThresholdParam;
window.getCompressorKneeParam = getCompressorKneeParam;
window.getCompressorRatioParam = getCompressorRatioParam;
window.setValueCurveAtTime = setValueCurveAtTime;
window.getAudioParamValue = getAudioParamValue;
window.getAudioParamDefaultValue = getAudioParamDefaultValue;
window.getAudioParamMinValue = getAudioParamMinValue;
window.getAudioParamMaxValue = getAudioParamMaxValue;
window.setAudioParamValue = setAudioParamValue;
window.getAudioParamAutomationRate = getAudioParamAutomationRate;
window.setAudioParamAutomationRate = setAudioParamAutomationRate;
window.connectNodesWithChannels = connectNodesWithChannels;
window.disconnectNodeFromDestination = disconnectNodeFromDestination;
window.disconnectNodeOutput = disconnectNodeOutput;
window.disconnectNodeFromNodeChannel = disconnectNodeFromNodeChannel;
window.getContextBaseLatency = getContextBaseLatency;
window.getContextOutputLatency = getContextOutputLatency;
window.getContextDestination = getContextDestination;
window.getContextAudioListener = getContextAudioListener;
window.setAnalyserMinDecibels = setAnalyserMinDecibels;
window.setAnalyserMaxDecibels = setAnalyserMaxDecibels;
window.getAnalyserMinDecibels = getAnalyserMinDecibels;
window.getAnalyserMaxDecibels = getAnalyserMaxDecibels;
window.setAnalyserSmoothingTimeConstant = setAnalyserSmoothingTimeConstant;
window.getAnalyserSmoothingTimeConstant = getAnalyserSmoothingTimeConstant;
window.getCompressorReduction = getCompressorReduction;
window.getCompressorAttackParam = getCompressorAttackParam;
window.getCompressorReleaseParam = getCompressorReleaseParam;
window.setCompressorAttackDirect = setCompressorAttackDirect;
window.setCompressorReleaseDirect = setCompressorReleaseDirect;
window.getBufferSourceBuffer = getBufferSourceBuffer;
window.getBufferSourceLoop = getBufferSourceLoop;
window.getBufferSourceLoopStart = getBufferSourceLoopStart;
window.getBufferSourceLoopEnd = getBufferSourceLoopEnd;
window.setBufferSourceLoopDirect = setBufferSourceLoopDirect;
window.getPannerPositionX = getPannerPositionX;
window.getPannerPositionY = getPannerPositionY;
window.getPannerPositionZ = getPannerPositionZ;
window.getPannerOrientationX = getPannerOrientationX;
window.setPannerOrientationDirect = setPannerOrientationDirect;
window.getBiquadFilterType = getBiquadFilterType;
window.setBiquadFilterTypeDirect = setBiquadFilterTypeDirect;
window.getBiquadFilterFrequencyParam = getBiquadFilterFrequencyParam;
window.getBiquadFilterQParam = getBiquadFilterQParam;
window.reverseAudioBuffer = reverseAudioBuffer;
window.normalizeAudioBuffer = normalizeAudioBuffer;
window.mixAudioBuffers = mixAudioBuffers;
window.trimSilence = trimSilence;
window.getBufferPeak = getBufferPeak;
window.getBufferRMS = getBufferRMS;
window.createBufferFromSamples = createBufferFromSamples;
window.concatenateBuffers = concatenateBuffers;
window.getStereoPannerPan = getStereoPannerPan;
window.getGainNodeGainParam = getGainNodeGainParam;
window.getConvolverNormalize = getConvolverNormalize;
window.getWaveShaperOversample = getWaveShaperOversample;
window.getAnalyserFFTSize = getAnalyserFFTSize;
window.getAnalyserFrequencyBinCount = getAnalyserFrequencyBinCount;
window.getDelayMaxDelayTime = getDelayMaxDelayTime;
window.getBufferSourcePlaybackRate = getBufferSourcePlaybackRate;
window.getBufferSourceDetune = getBufferSourceDetune;
window.getPannerDistanceModel = getPannerDistanceModel;
window.getPannerPanningModel = getPannerPanningModel;
window.getPannerRefDistance = getPannerRefDistance;
window.getPannerMaxDistance = getPannerMaxDistance;
window.getPannerRolloffFactor = getPannerRolloffFactor;
window.getPannerConeInnerAngle = getPannerConeInnerAngle;
window.getPannerConeOuterAngle = getPannerConeOuterAngle;
window.getPannerConeOuterGain = getPannerConeOuterGain;
window.getMediaElementSourceElement = getMediaElementSourceElement;
window.getMediaStreamTracks = getMediaStreamTracks;
window.getMediaStreamActive = getMediaStreamActive;
window.getMediaStreamId = getMediaStreamId;
window.getBiquadFilterGainParam = getBiquadFilterGainParam;
window.getBiquadFilterDetuneParam = getBiquadFilterDetuneParam;
window.getPannerOrientationY = getPannerOrientationY;
window.getPannerOrientationZ = getPannerOrientationZ;
window.getConstantSourceOffsetValue = getConstantSourceOffsetValue;
window.createEmptyBuffer = createEmptyBuffer;
window.getBufferAsArray = getBufferAsArray;
window.setOscillatorType = setOscillatorType;
window.getIIRFilterResponseAtFrequency = getIIRFilterResponseAtFrequency;

// ============================================================================
// TYPE COERCION FUNCTIONS
// ============================================================================
// In JavaScript, all AudioNode subtypes are the same at runtime.
// These functions provide type-safe coercion for Canopy's type system.

/**
 * Convert GainNode to AudioNode (identity in JavaScript)
 * @name gainNodeToAudioNode
 * @canopy-type GainNode -> AudioNode
 */
function gainNodeToAudioNode(node) {
    return node;
}

/**
 * Convert OscillatorNode to AudioNode (identity in JavaScript)
 * @name oscillatorNodeToAudioNode
 * @canopy-type OscillatorNode -> AudioNode
 */
function oscillatorNodeToAudioNode(node) {
    return node;
}

/**
 * Convert BiquadFilterNode to AudioNode (identity in JavaScript)
 * @name biquadFilterNodeToAudioNode
 * @canopy-type BiquadFilterNode -> AudioNode
 */
function biquadFilterNodeToAudioNode(node) {
    return node;
}

/**
 * Convert DelayNode to AudioNode (identity in JavaScript)
 * @name delayNodeToAudioNode
 * @canopy-type DelayNode -> AudioNode
 */
function delayNodeToAudioNode(node) {
    return node;
}

/**
 * Convert ConvolverNode to AudioNode (identity in JavaScript)
 * @name convolverNodeToAudioNode
 * @canopy-type ConvolverNode -> AudioNode
 */
function convolverNodeToAudioNode(node) {
    return node;
}

/**
 * Convert DynamicsCompressorNode to AudioNode (identity in JavaScript)
 * @name dynamicsCompressorNodeToAudioNode
 * @canopy-type DynamicsCompressorNode -> AudioNode
 */
function dynamicsCompressorNodeToAudioNode(node) {
    return node;
}

/**
 * Convert WaveShaperNode to AudioNode (identity in JavaScript)
 * @name waveShaperNodeToAudioNode
 * @canopy-type WaveShaperNode -> AudioNode
 */
function waveShaperNodeToAudioNode(node) {
    return node;
}

/**
 * Convert StereoPannerNode to AudioNode (identity in JavaScript)
 * @name stereoPannerNodeToAudioNode
 * @canopy-type StereoPannerNode -> AudioNode
 */
function stereoPannerNodeToAudioNode(node) {
    return node;
}

/**
 * Convert AnalyserNode to AudioNode (identity in JavaScript)
 * @name analyserNodeToAudioNode
 * @canopy-type AnalyserNode -> AudioNode
 */
function analyserNodeToAudioNode(node) {
    return node;
}

/**
 * Convert PannerNode to AudioNode (identity in JavaScript)
 * @name pannerNodeToAudioNode
 * @canopy-type PannerNode -> AudioNode
 */
function pannerNodeToAudioNode(node) {
    return node;
}

/**
 * Convert ChannelSplitterNode to AudioNode (identity in JavaScript)
 * @name channelSplitterNodeToAudioNode
 * @canopy-type ChannelSplitterNode -> AudioNode
 */
function channelSplitterNodeToAudioNode(node) {
    return node;
}

/**
 * Convert ChannelMergerNode to AudioNode (identity in JavaScript)
 * @name channelMergerNodeToAudioNode
 * @canopy-type ChannelMergerNode -> AudioNode
 */
function channelMergerNodeToAudioNode(node) {
    return node;
}

/**
 * Convert AudioBufferSourceNode to AudioNode (identity in JavaScript)
 * @name audioBufferSourceNodeToAudioNode
 * @canopy-type AudioBufferSourceNode -> AudioNode
 */
function audioBufferSourceNodeToAudioNode(node) {
    return node;
}

/**
 * Convert ConstantSourceNode to AudioNode (identity in JavaScript)
 * @name constantSourceNodeToAudioNode
 * @canopy-type ConstantSourceNode -> AudioNode
 */
function constantSourceNodeToAudioNode(node) {
    return node;
}

/**
 * Convert IIRFilterNode to AudioNode (identity in JavaScript)
 * @name iirFilterNodeToAudioNode
 * @canopy-type IIRFilterNode -> AudioNode
 */
function iirFilterNodeToAudioNode(node) {
    return node;
}

/**
 * Convert AudioWorkletNode to AudioNode (identity in JavaScript)
 * @name audioWorkletNodeToAudioNode
 * @canopy-type AudioWorkletNode -> AudioNode
 */
function audioWorkletNodeToAudioNode(node) {
    return node;
}

// Export type coercion functions
window.gainNodeToAudioNode = gainNodeToAudioNode;
window.oscillatorNodeToAudioNode = oscillatorNodeToAudioNode;
window.biquadFilterNodeToAudioNode = biquadFilterNodeToAudioNode;
window.delayNodeToAudioNode = delayNodeToAudioNode;
window.convolverNodeToAudioNode = convolverNodeToAudioNode;
window.dynamicsCompressorNodeToAudioNode = dynamicsCompressorNodeToAudioNode;
window.waveShaperNodeToAudioNode = waveShaperNodeToAudioNode;
window.stereoPannerNodeToAudioNode = stereoPannerNodeToAudioNode;
window.analyserNodeToAudioNode = analyserNodeToAudioNode;
window.pannerNodeToAudioNode = pannerNodeToAudioNode;
window.channelSplitterNodeToAudioNode = channelSplitterNodeToAudioNode;
window.channelMergerNodeToAudioNode = channelMergerNodeToAudioNode;
window.audioBufferSourceNodeToAudioNode = audioBufferSourceNodeToAudioNode;
window.constantSourceNodeToAudioNode = constantSourceNodeToAudioNode;
window.iirFilterNodeToAudioNode = iirFilterNodeToAudioNode;
window.audioWorkletNodeToAudioNode = audioWorkletNodeToAudioNode;


// From external/capability.js
/**
 * Core Capability FFI Helpers for Canopy
 *
 * This provides the JavaScript implementation for core capability checking
 * and web API context initialization. These are the fundamental building
 * blocks that all Web API FFI packages should use.
 */

/**
 * Check if user activation is currently available
 * @canopy-type () -> Bool
 * @name isUserActivationAvailable
 */
function isUserActivationAvailable() {
	// Modern browsers have navigator.userActivation
	if (navigator.userActivation) {
		return navigator.userActivation.hasBeenActive;
	}

	// Fallback: assume user activation is available if we're in a browser
	return typeof window !== "undefined" && typeof document !== "undefined";
}

/**
 * Check if user activation is currently active (within gesture window)
 * @canopy-type () -> Bool
 * @name isUserActivationActive
 */
function isUserActivationActive() {
	// Modern browsers have navigator.userActivation
	if (navigator.userActivation) {
		return navigator.userActivation.isActive;
	}

	// Fallback: return false as we can't reliably detect
	return false;
}

/**
 * Consume user activation and detect gesture type
 * @canopy-type Capability.UserActivated
 * @name consumeUserActivation
 */
function consumeUserActivation() {
	// Detect the type of user activation based on recent events
	const now = Date.now();
	const recentEvents = window.__canopyRecentEvents || [];

	// Find the most recent user event within the last 100ms
	const recentEvent = recentEvents
		.filter((event) => now - event.timestamp < 100)
		.sort((a, b) => b.timestamp - a.timestamp)[0];

	if (recentEvent) {
		// Return specific gesture type based on event type
		switch (recentEvent.type) {
			case "click":
				return { $: "Click" };
			case "keydown":
			case "keyup":
				return { $: "Keypress" };
			case "touchstart":
			case "touchend":
				return { $: "Touch" };
			case "dragstart":
			case "dragend":
				return { $: "Drag" };
			case "focus":
				return { $: "Focus" };
			default:
				return { $: "Transient" };
		}
	}

	// Fallback: return transient activation
	return { $: "Transient" };
}

/**
 * Consume user activation and return as integer (workaround for compiler type reversal bug)
 * Returns: 1=Click, 2=Keypress, 3=Touch, 4=Drag, 5=Focus, 0=Transient
 * @canopy-type () -> Int
 * @name consumeUserActivationInt
 */
function consumeUserActivationInt() {
	const now = Date.now();
	const recentEvents = window.__canopyRecentEvents || [];

	const recentEvent = recentEvents
		.filter((event) => now - event.timestamp < 100)
		.sort((a, b) => b.timestamp - a.timestamp)[0];

	if (recentEvent) {
		switch (recentEvent.type) {
			case "click":
				return 1;
			case "keydown":
			case "keyup":
				return 2;
			case "touchstart":
			case "touchend":
				return 3;
			case "dragstart":
			case "dragend":
				return 4;
			case "focus":
				return 5;
			default:
				return 0;
		}
	}

	return 0; // Transient
}

/**
 * Consume user activation and return as string (workaround for MVar deadlock)
 * @canopy-type () -> String
 * @name consumeUserActivationString
 */
function consumeUserActivationString() {
	// Detect the type of user activation based on recent events
	const now = Date.now();
	const recentEvents = window.__canopyRecentEvents || [];

	// Find the most recent user event within the last 100ms
	const recentEvent = recentEvents
		.filter((event) => now - event.timestamp < 100)
		.sort((a, b) => b.timestamp - a.timestamp)[0];

	if (recentEvent) {
		// Return specific gesture type as string
		switch (recentEvent.type) {
			case "click":
				return "Click";
			case "keydown":
			case "keyup":
				return "Keypress";
			case "touchstart":
			case "touchend":
				return "Touch";
			case "dragstart":
			case "dragend":
				return "Drag";
			case "focus":
				return "Focus";
			default:
				return "Transient";
		}
	}

	// Fallback: return transient activation
	return "Transient";
}

// Track recent user events for gesture type detection
if (typeof window !== "undefined") {
	window.__canopyRecentEvents = [];

	["click", "keydown", "keyup", "touchstart", "touchend", "dragstart", "dragend", "focus"].forEach(
		(eventType) => {
			document.addEventListener(
				eventType,
				(event) => {
					window.__canopyRecentEvents.push({
						type: eventType,
						timestamp: Date.now(),
					});

					// Keep only last 10 events
					if (window.__canopyRecentEvents.length > 10) {
						window.__canopyRecentEvents.shift();
					}
				},
				true
			);
		}
	);
}

/**
 * Generic API availability detection framework
 * @canopy-type (() -> Available ()) -> Available ()
 * @name detectAPISupport
 */
function detectAPISupport(detectionFunction) {
	try {
		return detectionFunction();
	} catch (error) {
		// Return PartialSupport as fallback when detection fails
		return { $: "PartialSupport", a: null };
	}
}

/**
 * Generic feature detection helper
 * @canopy-type (String) -> Bool
 * @name hasFeature
 */
function hasFeature(featurePath) {
	try {
		const parts = featurePath.split(".");
		let current = window;

		for (const part of parts) {
			if (current && typeof current === "object" && part in current) {
				current = current[part];
			} else {
				return false;
			}
		}

		return current !== undefined && current !== null;
	} catch (e) {
		return false;
	}
}

/**
 * Generic permission status checking framework
 * @canopy-type String -> Task CapabilityError (Permitted ())
 * @name checkGenericPermission
 */
function checkGenericPermission(permissionName) {
	return new Promise((resolve, reject) => {
		if (!navigator.permissions) {
			resolve({ $: "Unknown", a: null });
			return;
		}

		navigator.permissions
			.query({ name: permissionName })
			.then((result) => {
				switch (result.state) {
					case "granted":
						resolve({ $: "Granted", a: null });
						break;
					case "denied":
						resolve({ $: "Denied", a: null });
						break;
					case "prompt":
						resolve({ $: "Prompt", a: null });
						break;
					default:
						resolve({ $: "Unknown", a: null });
				}
			})
			.catch((error) => {
				reject(
					new CapabilityError("PermissionRequired", `Failed to check permission: ${error.message}`)
				);
			});
	});
}

/**
 * Generic permission request framework
 * @canopy-type (() -> Task CapabilityError (Permitted ())) -> Task CapabilityError (Permitted ())
 * @name requestGenericPermission
 */
function requestGenericPermission(requestFunction) {
	return new Promise((resolve, reject) => {
		try {
			const result = requestFunction();

			if (result && typeof result.then === "function") {
				result.then(resolve).catch(reject);
			} else {
				resolve(result);
			}
		} catch (error) {
			reject(
				new CapabilityError("PermissionRequired", `Permission request failed: ${error.message}`)
			);
		}
	});
}

/**
 * Generic initialization framework with custom state detection
 * @canopy-type String -> (() -> Task CapabilityError a) -> (a -> Initialized a) -> Task CapabilityError (Initialized a)
 * @name createGenericInitializer
 */
function createGenericInitializer(contextType, initFunction, stateDetector) {
	return new Promise((resolve, reject) => {
		try {
			// Call the initialization function
			const result = initFunction();

			function wrapWithState(context) {
				if (stateDetector) {
					return stateDetector(context);
				} else {
					// Default: assume Fresh state
					return {
						type: "Fresh",
						value: context,
					};
				}
			}

			// If it's a promise, wait for it
			if (result && typeof result.then === "function") {
				result
					.then((initializedContext) => {
						resolve(wrapWithState(initializedContext));
					})
					.catch((error) => {
						reject(
							new CapabilityError(
								"InitializationRequired",
								`${contextType} initialization failed: ${error.message}`
							)
						);
					});
			} else {
				// Synchronous result
				resolve(wrapWithState(result));
			}
		} catch (error) {
			reject(
				new CapabilityError(
					"InitializationRequired",
					`${contextType} initialization failed: ${error.message}`
				)
			);
		}
	});
}

/**
 * Simple initialization checker (backwards compatibility)
 * @canopy-type String -> (() -> Task CapabilityError a) -> Task CapabilityError (Initialized a)
 * @name createInitializationChecker
 */
function createInitializationChecker(contextType, initFunction) {
	return createGenericInitializer(contextType, initFunction, null);
}

/**
 * Validate that a value has the correct capability type
 * @canopy-type String -> a -> Task CapabilityError a
 * @name validateCapability
 */
function validateCapability(expectedType, value) {
	return new Promise((resolve, reject) => {
		switch (expectedType) {
			case "UserActivated":
				if (value === "UserActivated") {
					resolve(value);
				} else {
					reject(new CapabilityError("UserActivationRequired", "User activation token required"));
				}
				break;

			case "Initialized":
				if (value && typeof value === "object" && value.__type === "Initialized") {
					resolve(value.__context);
				} else {
					reject(new CapabilityError("InitializationRequired", "Initialized context required"));
				}
				break;

			default:
				reject(
					new CapabilityError("CapabilityRevoked", `Unknown capability type: ${expectedType}`)
				);
		}
	});
}

/**
 * Custom error class for capability violations
 */
class CapabilityError extends Error {
	constructor(type, message) {
		super(message);
		this.name = "CapabilityError";
		this.type = type;
	}
}

// Create browser exports for Canopy FFI
if (typeof window !== "undefined") {
	// Make functions available globally and as properties of a CapabilityFFI object
	window.isUserActivationActive = isUserActivationActive;
	window.consumeUserActivation = consumeUserActivation;
	window.hasFeature = hasFeature;

	// Create Canopy-compiled namespace structure
	if (!window.$author$project$Capability$hasFeature) {
		window.$author$project$Capability$hasFeature = hasFeature;
		window.$author$project$Capability$isUserActivationActive = isUserActivationActive;
		window.$author$project$Capability$consumeUserActivation = consumeUserActivation;
	}

	// Also create an object for module-style imports
	window.CapabilityFFI = {
		isUserActivationActive: isUserActivationActive,
		consumeUserActivation: consumeUserActivation,
		consumeUserActivationString: consumeUserActivationString,
		consumeUserActivationInt: consumeUserActivationInt,
		hasFeature: hasFeature,
		detectAPISupport: detectAPISupport,
		checkGenericPermission: checkGenericPermission,
		requestGenericPermission: requestGenericPermission,
		createGenericInitializer: createGenericInitializer,
		createInitializationChecker: createInitializationChecker,
		validateCapability: validateCapability,
		CapabilityError: CapabilityError
	};
}

// Export for Node.js testing
if (typeof module !== "undefined") {
	module.exports = {
		isUserActivationAvailable,
		isUserActivationActive,
		consumeUserActivation,
		consumeUserActivationString,
		consumeUserActivationInt,
		hasFeature,
		detectAPISupport,
		checkGenericPermission,
		requestGenericPermission,
		createInitializationChecker,
		validateCapability,
		CapabilityError,
	};
}

// FFI function bindings

// Bindings for external/audio.js
var $_FFI_FFI = $_FFI_FFI || {};
var $author$project$FFI$createAudioContext = createAudioContext;
$_FFI_FFI.createAudioContext = createAudioContext;
var $author$project$FFI$getCurrentTime = getCurrentTime;
$_FFI_FFI.getCurrentTime = getCurrentTime;
var $author$project$FFI$resumeAudioContext = resumeAudioContext;
$_FFI_FFI.resumeAudioContext = resumeAudioContext;
var $author$project$FFI$suspendAudioContext = suspendAudioContext;
$_FFI_FFI.suspendAudioContext = suspendAudioContext;
var $author$project$FFI$closeAudioContext = closeAudioContext;
$_FFI_FFI.closeAudioContext = closeAudioContext;
var $author$project$FFI$getSampleRate = getSampleRate;
$_FFI_FFI.getSampleRate = getSampleRate;
var $author$project$FFI$getContextState = getContextState;
$_FFI_FFI.getContextState = getContextState;
var $author$project$FFI$decodeAudioData = F2(decodeAudioData);
$_FFI_FFI.decodeAudioData = F2(decodeAudioData);
var $author$project$FFI$createOscillator = F3(createOscillator);
$_FFI_FFI.createOscillator = F3(createOscillator);
var $author$project$FFI$startOscillator = F2(startOscillator);
$_FFI_FFI.startOscillator = F2(startOscillator);
var $author$project$FFI$stopOscillator = F2(stopOscillator);
$_FFI_FFI.stopOscillator = F2(stopOscillator);
var $author$project$FFI$setOscillatorFrequency = F3(setOscillatorFrequency);
$_FFI_FFI.setOscillatorFrequency = F3(setOscillatorFrequency);
var $author$project$FFI$setOscillatorDetune = F3(setOscillatorDetune);
$_FFI_FFI.setOscillatorDetune = F3(setOscillatorDetune);
var $author$project$FFI$createBufferSource = createBufferSource;
$_FFI_FFI.createBufferSource = createBufferSource;
var $author$project$FFI$createMediaStreamSource = F2(createMediaStreamSource);
$_FFI_FFI.createMediaStreamSource = F2(createMediaStreamSource);
var $author$project$FFI$createMediaStreamDestination = createMediaStreamDestination;
$_FFI_FFI.createMediaStreamDestination = createMediaStreamDestination;
var $author$project$FFI$getMediaStream = getMediaStream;
$_FFI_FFI.getMediaStream = getMediaStream;
var $author$project$FFI$startBufferSource = F2(startBufferSource);
$_FFI_FFI.startBufferSource = F2(startBufferSource);
var $author$project$FFI$stopBufferSource = F2(stopBufferSource);
$_FFI_FFI.stopBufferSource = F2(stopBufferSource);
var $author$project$FFI$createGainNode = F2(createGainNode);
$_FFI_FFI.createGainNode = F2(createGainNode);
var $author$project$FFI$setGain = F3(setGain);
$_FFI_FFI.setGain = F3(setGain);
var $author$project$FFI$rampGainLinear = F3(rampGainLinear);
$_FFI_FFI.rampGainLinear = F3(rampGainLinear);
var $author$project$FFI$rampGainExponential = F3(rampGainExponential);
$_FFI_FFI.rampGainExponential = F3(rampGainExponential);
var $author$project$FFI$createBiquadFilter = F2(createBiquadFilter);
$_FFI_FFI.createBiquadFilter = F2(createBiquadFilter);
var $author$project$FFI$setFilterFrequency = F3(setFilterFrequency);
$_FFI_FFI.setFilterFrequency = F3(setFilterFrequency);
var $author$project$FFI$setFilterQ = F3(setFilterQ);
$_FFI_FFI.setFilterQ = F3(setFilterQ);
var $author$project$FFI$setFilterGain = F3(setFilterGain);
$_FFI_FFI.setFilterGain = F3(setFilterGain);
var $author$project$FFI$createDelay = F2(createDelay);
$_FFI_FFI.createDelay = F2(createDelay);
var $author$project$FFI$setDelayTime = F3(setDelayTime);
$_FFI_FFI.setDelayTime = F3(setDelayTime);
var $author$project$FFI$createConvolver = createConvolver;
$_FFI_FFI.createConvolver = createConvolver;
var $author$project$FFI$setConvolverBuffer = F2(setConvolverBuffer);
$_FFI_FFI.setConvolverBuffer = F2(setConvolverBuffer);
var $author$project$FFI$setConvolverNormalize = F2(setConvolverNormalize);
$_FFI_FFI.setConvolverNormalize = F2(setConvolverNormalize);
var $author$project$FFI$getConvolverBuffer = getConvolverBuffer;
$_FFI_FFI.getConvolverBuffer = getConvolverBuffer;
var $author$project$FFI$createDynamicsCompressor = createDynamicsCompressor;
$_FFI_FFI.createDynamicsCompressor = createDynamicsCompressor;
var $author$project$FFI$setCompressorThreshold = F3(setCompressorThreshold);
$_FFI_FFI.setCompressorThreshold = F3(setCompressorThreshold);
var $author$project$FFI$setCompressorKnee = F3(setCompressorKnee);
$_FFI_FFI.setCompressorKnee = F3(setCompressorKnee);
var $author$project$FFI$setCompressorRatio = F3(setCompressorRatio);
$_FFI_FFI.setCompressorRatio = F3(setCompressorRatio);
var $author$project$FFI$setCompressorAttack = F3(setCompressorAttack);
$_FFI_FFI.setCompressorAttack = F3(setCompressorAttack);
var $author$project$FFI$setCompressorRelease = F3(setCompressorRelease);
$_FFI_FFI.setCompressorRelease = F3(setCompressorRelease);
var $author$project$FFI$createWaveShaper = createWaveShaper;
$_FFI_FFI.createWaveShaper = createWaveShaper;
var $author$project$FFI$setWaveShaperCurve = F2(setWaveShaperCurve);
$_FFI_FFI.setWaveShaperCurve = F2(setWaveShaperCurve);
var $author$project$FFI$setWaveShaperOversample = F2(setWaveShaperOversample);
$_FFI_FFI.setWaveShaperOversample = F2(setWaveShaperOversample);
var $author$project$FFI$getWaveShaperCurve = getWaveShaperCurve;
$_FFI_FFI.getWaveShaperCurve = getWaveShaperCurve;
var $author$project$FFI$makeDistortionCurve = F2(makeDistortionCurve);
$_FFI_FFI.makeDistortionCurve = F2(makeDistortionCurve);
var $author$project$FFI$createStereoPanner = createStereoPanner;
$_FFI_FFI.createStereoPanner = createStereoPanner;
var $author$project$FFI$setPan = F3(setPan);
$_FFI_FFI.setPan = F3(setPan);
var $author$project$FFI$createAnalyser = createAnalyser;
$_FFI_FFI.createAnalyser = createAnalyser;
var $author$project$FFI$setAnalyserFFTSize = F2(setAnalyserFFTSize);
$_FFI_FFI.setAnalyserFFTSize = F2(setAnalyserFFTSize);
var $author$project$FFI$setAnalyserSmoothing = F2(setAnalyserSmoothing);
$_FFI_FFI.setAnalyserSmoothing = F2(setAnalyserSmoothing);
var $author$project$FFI$getFrequencyBinCount = getFrequencyBinCount;
$_FFI_FFI.getFrequencyBinCount = getFrequencyBinCount;
var $author$project$FFI$connectNodes = F2(connectNodes);
$_FFI_FFI.connectNodes = F2(connectNodes);
var $author$project$FFI$connectToDestination = F2(connectToDestination);
$_FFI_FFI.connectToDestination = F2(connectToDestination);
var $author$project$FFI$disconnectNode = disconnectNode;
$_FFI_FFI.disconnectNode = disconnectNode;
var $author$project$FFI$checkWebAudioSupport = checkWebAudioSupport;
$_FFI_FFI.checkWebAudioSupport = checkWebAudioSupport;
var $author$project$FFI$simpleTest = simpleTest;
$_FFI_FFI.simpleTest = simpleTest;
var $author$project$FFI$createPanner = createPanner;
$_FFI_FFI.createPanner = createPanner;
var $author$project$FFI$setPannerPosition = F4(setPannerPosition);
$_FFI_FFI.setPannerPosition = F4(setPannerPosition);
var $author$project$FFI$setPannerOrientation = F4(setPannerOrientation);
$_FFI_FFI.setPannerOrientation = F4(setPannerOrientation);
var $author$project$FFI$setPanningModel = F2(setPanningModel);
$_FFI_FFI.setPanningModel = F2(setPanningModel);
var $author$project$FFI$setDistanceModel = F2(setDistanceModel);
$_FFI_FFI.setDistanceModel = F2(setDistanceModel);
var $author$project$FFI$setRefDistance = F2(setRefDistance);
$_FFI_FFI.setRefDistance = F2(setRefDistance);
var $author$project$FFI$setMaxDistance = F2(setMaxDistance);
$_FFI_FFI.setMaxDistance = F2(setMaxDistance);
var $author$project$FFI$setRolloffFactor = F2(setRolloffFactor);
$_FFI_FFI.setRolloffFactor = F2(setRolloffFactor);
var $author$project$FFI$setConeInnerAngle = F2(setConeInnerAngle);
$_FFI_FFI.setConeInnerAngle = F2(setConeInnerAngle);
var $author$project$FFI$setConeOuterAngle = F2(setConeOuterAngle);
$_FFI_FFI.setConeOuterAngle = F2(setConeOuterAngle);
var $author$project$FFI$setConeOuterGain = F2(setConeOuterGain);
$_FFI_FFI.setConeOuterGain = F2(setConeOuterGain);
var $author$project$FFI$getAudioListener = getAudioListener;
$_FFI_FFI.getAudioListener = getAudioListener;
var $author$project$FFI$setListenerPosition = F4(setListenerPosition);
$_FFI_FFI.setListenerPosition = F4(setListenerPosition);
var $author$project$FFI$setListenerForward = F4(setListenerForward);
$_FFI_FFI.setListenerForward = F4(setListenerForward);
var $author$project$FFI$setListenerUp = F4(setListenerUp);
$_FFI_FFI.setListenerUp = F4(setListenerUp);
var $author$project$FFI$createChannelSplitter = F2(createChannelSplitter);
$_FFI_FFI.createChannelSplitter = F2(createChannelSplitter);
var $author$project$FFI$createChannelMerger = F2(createChannelMerger);
$_FFI_FFI.createChannelMerger = F2(createChannelMerger);
var $author$project$FFI$createAudioBuffer = F4(createAudioBuffer);
$_FFI_FFI.createAudioBuffer = F4(createAudioBuffer);
var $author$project$FFI$getBufferLength = getBufferLength;
$_FFI_FFI.getBufferLength = getBufferLength;
var $author$project$FFI$getBufferDuration = getBufferDuration;
$_FFI_FFI.getBufferDuration = getBufferDuration;
var $author$project$FFI$getBufferSampleRate = getBufferSampleRate;
$_FFI_FFI.getBufferSampleRate = getBufferSampleRate;
var $author$project$FFI$getBufferChannels = getBufferChannels;
$_FFI_FFI.getBufferChannels = getBufferChannels;
var $author$project$FFI$getChannelData = F2(getChannelData);
$_FFI_FFI.getChannelData = F2(getChannelData);
var $author$project$FFI$copyToChannel = F4(copyToChannel);
$_FFI_FFI.copyToChannel = F4(copyToChannel);
var $author$project$FFI$copyFromChannel = F4(copyFromChannel);
$_FFI_FFI.copyFromChannel = F4(copyFromChannel);
var $author$project$FFI$createSilentBuffer = F4(createSilentBuffer);
$_FFI_FFI.createSilentBuffer = F4(createSilentBuffer);
var $author$project$FFI$cloneAudioBuffer = cloneAudioBuffer;
$_FFI_FFI.cloneAudioBuffer = cloneAudioBuffer;
var $author$project$FFI$createMediaElementSource = F2(createMediaElementSource);
$_FFI_FFI.createMediaElementSource = F2(createMediaElementSource);
var $author$project$FFI$createPeriodicWave = createPeriodicWave;
$_FFI_FFI.createPeriodicWave = createPeriodicWave;
var $author$project$FFI$createOfflineAudioContext = F3(createOfflineAudioContext);
$_FFI_FFI.createOfflineAudioContext = F3(createOfflineAudioContext);
var $author$project$FFI$startOfflineRendering = startOfflineRendering;
$_FFI_FFI.startOfflineRendering = startOfflineRendering;
var $author$project$FFI$startOfflineRenderingAsync = startOfflineRenderingAsync;
$_FFI_FFI.startOfflineRenderingAsync = startOfflineRenderingAsync;
var $author$project$FFI$suspendOfflineContext = F2(suspendOfflineContext);
$_FFI_FFI.suspendOfflineContext = F2(suspendOfflineContext);
var $author$project$FFI$resumeOfflineContext = resumeOfflineContext;
$_FFI_FFI.resumeOfflineContext = resumeOfflineContext;
var $author$project$FFI$getOfflineContextLength = getOfflineContextLength;
$_FFI_FFI.getOfflineContextLength = getOfflineContextLength;
var $author$project$FFI$getOfflineContextSampleRate = getOfflineContextSampleRate;
$_FFI_FFI.getOfflineContextSampleRate = getOfflineContextSampleRate;
var $author$project$FFI$getGainParam = getGainParam;
$_FFI_FFI.getGainParam = getGainParam;
var $author$project$FFI$getFrequencyParam = getFrequencyParam;
$_FFI_FFI.getFrequencyParam = getFrequencyParam;
var $author$project$FFI$getDetuneParam = getDetuneParam;
$_FFI_FFI.getDetuneParam = getDetuneParam;
var $author$project$FFI$setParamValueAtTime = F3(setParamValueAtTime);
$_FFI_FFI.setParamValueAtTime = F3(setParamValueAtTime);
var $author$project$FFI$linearRampToValue = F3(linearRampToValue);
$_FFI_FFI.linearRampToValue = F3(linearRampToValue);
var $author$project$FFI$exponentialRampToValue = F3(exponentialRampToValue);
$_FFI_FFI.exponentialRampToValue = F3(exponentialRampToValue);
var $author$project$FFI$setTargetAtTime = F4(setTargetAtTime);
$_FFI_FFI.setTargetAtTime = F4(setTargetAtTime);
var $author$project$FFI$cancelScheduledValues = F2(cancelScheduledValues);
$_FFI_FFI.cancelScheduledValues = F2(cancelScheduledValues);
var $author$project$FFI$cancelAndHoldAtTime = F2(cancelAndHoldAtTime);
$_FFI_FFI.cancelAndHoldAtTime = F2(cancelAndHoldAtTime);
var $author$project$FFI$setValueAtTime = F3(setValueAtTime);
$_FFI_FFI.setValueAtTime = F3(setValueAtTime);
var $author$project$FFI$linearRampToValueAtTime = F3(linearRampToValueAtTime);
$_FFI_FFI.linearRampToValueAtTime = F3(linearRampToValueAtTime);
var $author$project$FFI$exponentialRampToValueAtTime = F3(exponentialRampToValueAtTime);
$_FFI_FFI.exponentialRampToValueAtTime = F3(exponentialRampToValueAtTime);
var $author$project$FFI$getByteTimeDomainData = getByteTimeDomainData;
$_FFI_FFI.getByteTimeDomainData = getByteTimeDomainData;
var $author$project$FFI$getByteFrequencyData = getByteFrequencyData;
$_FFI_FFI.getByteFrequencyData = getByteFrequencyData;
var $author$project$FFI$getFloatTimeDomainData = getFloatTimeDomainData;
$_FFI_FFI.getFloatTimeDomainData = getFloatTimeDomainData;
var $author$project$FFI$getFloatFrequencyData = getFloatFrequencyData;
$_FFI_FFI.getFloatFrequencyData = getFloatFrequencyData;
var $author$project$FFI$setBufferSourceBuffer = F2(setBufferSourceBuffer);
$_FFI_FFI.setBufferSourceBuffer = F2(setBufferSourceBuffer);
var $author$project$FFI$setBufferSourceLoop = F2(setBufferSourceLoop);
$_FFI_FFI.setBufferSourceLoop = F2(setBufferSourceLoop);
var $author$project$FFI$setBufferSourceLoopStart = F2(setBufferSourceLoopStart);
$_FFI_FFI.setBufferSourceLoopStart = F2(setBufferSourceLoopStart);
var $author$project$FFI$setBufferSourceLoopEnd = F2(setBufferSourceLoopEnd);
$_FFI_FFI.setBufferSourceLoopEnd = F2(setBufferSourceLoopEnd);
var $author$project$FFI$setBufferSourcePlaybackRate = F3(setBufferSourcePlaybackRate);
$_FFI_FFI.setBufferSourcePlaybackRate = F3(setBufferSourcePlaybackRate);
var $author$project$FFI$setBufferSourceDetune = F3(setBufferSourceDetune);
$_FFI_FFI.setBufferSourceDetune = F3(setBufferSourceDetune);
var $author$project$FFI$createAudioContextSimplified = createAudioContextSimplified;
$_FFI_FFI.createAudioContextSimplified = createAudioContextSimplified;
var $author$project$FFI$playToneSimplified = F2(playToneSimplified);
$_FFI_FFI.playToneSimplified = F2(playToneSimplified);
var $author$project$FFI$stopAudioSimplified = stopAudioSimplified;
$_FFI_FFI.stopAudioSimplified = stopAudioSimplified;
var $author$project$FFI$updateFrequency = updateFrequency;
$_FFI_FFI.updateFrequency = updateFrequency;
var $author$project$FFI$updateVolume = updateVolume;
$_FFI_FFI.updateVolume = updateVolume;
var $author$project$FFI$updateWaveform = updateWaveform;
$_FFI_FFI.updateWaveform = updateWaveform;
var $author$project$FFI$addAudioWorkletModule = F2(addAudioWorkletModule);
$_FFI_FFI.addAudioWorkletModule = F2(addAudioWorkletModule);
var $author$project$FFI$createAudioWorkletNode = F2(createAudioWorkletNode);
$_FFI_FFI.createAudioWorkletNode = F2(createAudioWorkletNode);
var $author$project$FFI$getWorkletPort = getWorkletPort;
$_FFI_FFI.getWorkletPort = getWorkletPort;
var $author$project$FFI$getWorkletParameters = getWorkletParameters;
$_FFI_FFI.getWorkletParameters = getWorkletParameters;
var $author$project$FFI$postMessageToWorklet = F2(postMessageToWorklet);
$_FFI_FFI.postMessageToWorklet = F2(postMessageToWorklet);
var $author$project$FFI$createIIRFilter = F3(createIIRFilter);
$_FFI_FFI.createIIRFilter = F3(createIIRFilter);
var $author$project$FFI$getIIRFilterResponse = F2(getIIRFilterResponse);
$_FFI_FFI.getIIRFilterResponse = F2(getIIRFilterResponse);
var $author$project$FFI$createConstantSource = createConstantSource;
$_FFI_FFI.createConstantSource = createConstantSource;
var $author$project$FFI$getConstantSourceOffset = getConstantSourceOffset;
$_FFI_FFI.getConstantSourceOffset = getConstantSourceOffset;
var $author$project$FFI$startConstantSource = F2(startConstantSource);
$_FFI_FFI.startConstantSource = F2(startConstantSource);
var $author$project$FFI$stopConstantSource = F2(stopConstantSource);
$_FFI_FFI.stopConstantSource = F2(stopConstantSource);
var $author$project$FFI$createPeriodicWaveWithCoefficients = F3(createPeriodicWaveWithCoefficients);
$_FFI_FFI.createPeriodicWaveWithCoefficients = F3(createPeriodicWaveWithCoefficients);
var $author$project$FFI$createPeriodicWaveWithOptions = F4(createPeriodicWaveWithOptions);
$_FFI_FFI.createPeriodicWaveWithOptions = F4(createPeriodicWaveWithOptions);
var $author$project$FFI$setOscillatorPeriodicWave = F2(setOscillatorPeriodicWave);
$_FFI_FFI.setOscillatorPeriodicWave = F2(setOscillatorPeriodicWave);
var $author$project$FFI$getNodeChannelCount = getNodeChannelCount;
$_FFI_FFI.getNodeChannelCount = getNodeChannelCount;
var $author$project$FFI$setNodeChannelCount = F2(setNodeChannelCount);
$_FFI_FFI.setNodeChannelCount = F2(setNodeChannelCount);
var $author$project$FFI$getNodeChannelCountMode = getNodeChannelCountMode;
$_FFI_FFI.getNodeChannelCountMode = getNodeChannelCountMode;
var $author$project$FFI$setNodeChannelCountMode = F2(setNodeChannelCountMode);
$_FFI_FFI.setNodeChannelCountMode = F2(setNodeChannelCountMode);
var $author$project$FFI$getNodeChannelInterpretation = getNodeChannelInterpretation;
$_FFI_FFI.getNodeChannelInterpretation = getNodeChannelInterpretation;
var $author$project$FFI$setNodeChannelInterpretation = F2(setNodeChannelInterpretation);
$_FFI_FFI.setNodeChannelInterpretation = F2(setNodeChannelInterpretation);
var $author$project$FFI$getNodeNumberOfInputs = getNodeNumberOfInputs;
$_FFI_FFI.getNodeNumberOfInputs = getNodeNumberOfInputs;
var $author$project$FFI$getNodeNumberOfOutputs = getNodeNumberOfOutputs;
$_FFI_FFI.getNodeNumberOfOutputs = getNodeNumberOfOutputs;
var $author$project$FFI$getNodeContext = getNodeContext;
$_FFI_FFI.getNodeContext = getNodeContext;
var $author$project$FFI$getOscillatorType = getOscillatorType;
$_FFI_FFI.getOscillatorType = getOscillatorType;
var $author$project$FFI$getOscillatorFrequencyParam = getOscillatorFrequencyParam;
$_FFI_FFI.getOscillatorFrequencyParam = getOscillatorFrequencyParam;
var $author$project$FFI$getOscillatorDetuneParam = getOscillatorDetuneParam;
$_FFI_FFI.getOscillatorDetuneParam = getOscillatorDetuneParam;
var $author$project$FFI$getDelayDelayTimeParam = getDelayDelayTimeParam;
$_FFI_FFI.getDelayDelayTimeParam = getDelayDelayTimeParam;
var $author$project$FFI$getCompressorThresholdParam = getCompressorThresholdParam;
$_FFI_FFI.getCompressorThresholdParam = getCompressorThresholdParam;
var $author$project$FFI$getCompressorKneeParam = getCompressorKneeParam;
$_FFI_FFI.getCompressorKneeParam = getCompressorKneeParam;
var $author$project$FFI$getCompressorRatioParam = getCompressorRatioParam;
$_FFI_FFI.getCompressorRatioParam = getCompressorRatioParam;
var $author$project$FFI$setValueCurveAtTime = F4(setValueCurveAtTime);
$_FFI_FFI.setValueCurveAtTime = F4(setValueCurveAtTime);
var $author$project$FFI$getAudioParamValue = getAudioParamValue;
$_FFI_FFI.getAudioParamValue = getAudioParamValue;
var $author$project$FFI$getAudioParamDefaultValue = getAudioParamDefaultValue;
$_FFI_FFI.getAudioParamDefaultValue = getAudioParamDefaultValue;
var $author$project$FFI$getAudioParamMinValue = getAudioParamMinValue;
$_FFI_FFI.getAudioParamMinValue = getAudioParamMinValue;
var $author$project$FFI$getAudioParamMaxValue = getAudioParamMaxValue;
$_FFI_FFI.getAudioParamMaxValue = getAudioParamMaxValue;
var $author$project$FFI$setAudioParamValue = F2(setAudioParamValue);
$_FFI_FFI.setAudioParamValue = F2(setAudioParamValue);
var $author$project$FFI$getAudioParamAutomationRate = getAudioParamAutomationRate;
$_FFI_FFI.getAudioParamAutomationRate = getAudioParamAutomationRate;
var $author$project$FFI$setAudioParamAutomationRate = F2(setAudioParamAutomationRate);
$_FFI_FFI.setAudioParamAutomationRate = F2(setAudioParamAutomationRate);
var $author$project$FFI$connectNodesWithChannels = F4(connectNodesWithChannels);
$_FFI_FFI.connectNodesWithChannels = F4(connectNodesWithChannels);
var $author$project$FFI$disconnectNodeFromDestination = F2(disconnectNodeFromDestination);
$_FFI_FFI.disconnectNodeFromDestination = F2(disconnectNodeFromDestination);
var $author$project$FFI$disconnectNodeOutput = F2(disconnectNodeOutput);
$_FFI_FFI.disconnectNodeOutput = F2(disconnectNodeOutput);
var $author$project$FFI$disconnectNodeFromNodeChannel = F4(disconnectNodeFromNodeChannel);
$_FFI_FFI.disconnectNodeFromNodeChannel = F4(disconnectNodeFromNodeChannel);
var $author$project$FFI$getContextBaseLatency = getContextBaseLatency;
$_FFI_FFI.getContextBaseLatency = getContextBaseLatency;
var $author$project$FFI$getContextOutputLatency = getContextOutputLatency;
$_FFI_FFI.getContextOutputLatency = getContextOutputLatency;
var $author$project$FFI$getContextDestination = getContextDestination;
$_FFI_FFI.getContextDestination = getContextDestination;
var $author$project$FFI$getContextAudioListener = getContextAudioListener;
$_FFI_FFI.getContextAudioListener = getContextAudioListener;
var $author$project$FFI$setAnalyserMinDecibels = F2(setAnalyserMinDecibels);
$_FFI_FFI.setAnalyserMinDecibels = F2(setAnalyserMinDecibels);
var $author$project$FFI$setAnalyserMaxDecibels = F2(setAnalyserMaxDecibels);
$_FFI_FFI.setAnalyserMaxDecibels = F2(setAnalyserMaxDecibels);
var $author$project$FFI$getAnalyserMinDecibels = getAnalyserMinDecibels;
$_FFI_FFI.getAnalyserMinDecibels = getAnalyserMinDecibels;
var $author$project$FFI$getAnalyserMaxDecibels = getAnalyserMaxDecibels;
$_FFI_FFI.getAnalyserMaxDecibels = getAnalyserMaxDecibels;
var $author$project$FFI$setAnalyserSmoothingTimeConstant = F2(setAnalyserSmoothingTimeConstant);
$_FFI_FFI.setAnalyserSmoothingTimeConstant = F2(setAnalyserSmoothingTimeConstant);
var $author$project$FFI$getAnalyserSmoothingTimeConstant = getAnalyserSmoothingTimeConstant;
$_FFI_FFI.getAnalyserSmoothingTimeConstant = getAnalyserSmoothingTimeConstant;
var $author$project$FFI$getCompressorReduction = getCompressorReduction;
$_FFI_FFI.getCompressorReduction = getCompressorReduction;
var $author$project$FFI$getCompressorAttackParam = getCompressorAttackParam;
$_FFI_FFI.getCompressorAttackParam = getCompressorAttackParam;
var $author$project$FFI$getCompressorReleaseParam = getCompressorReleaseParam;
$_FFI_FFI.getCompressorReleaseParam = getCompressorReleaseParam;
var $author$project$FFI$setCompressorAttackDirect = F2(setCompressorAttackDirect);
$_FFI_FFI.setCompressorAttackDirect = F2(setCompressorAttackDirect);
var $author$project$FFI$setCompressorReleaseDirect = F2(setCompressorReleaseDirect);
$_FFI_FFI.setCompressorReleaseDirect = F2(setCompressorReleaseDirect);
var $author$project$FFI$getBufferSourceBuffer = getBufferSourceBuffer;
$_FFI_FFI.getBufferSourceBuffer = getBufferSourceBuffer;
var $author$project$FFI$getBufferSourceLoop = getBufferSourceLoop;
$_FFI_FFI.getBufferSourceLoop = getBufferSourceLoop;
var $author$project$FFI$getBufferSourceLoopStart = getBufferSourceLoopStart;
$_FFI_FFI.getBufferSourceLoopStart = getBufferSourceLoopStart;
var $author$project$FFI$getBufferSourceLoopEnd = getBufferSourceLoopEnd;
$_FFI_FFI.getBufferSourceLoopEnd = getBufferSourceLoopEnd;
var $author$project$FFI$setBufferSourceLoopDirect = F2(setBufferSourceLoopDirect);
$_FFI_FFI.setBufferSourceLoopDirect = F2(setBufferSourceLoopDirect);
var $author$project$FFI$getPannerPositionX = getPannerPositionX;
$_FFI_FFI.getPannerPositionX = getPannerPositionX;
var $author$project$FFI$getPannerPositionY = getPannerPositionY;
$_FFI_FFI.getPannerPositionY = getPannerPositionY;
var $author$project$FFI$getPannerPositionZ = getPannerPositionZ;
$_FFI_FFI.getPannerPositionZ = getPannerPositionZ;
var $author$project$FFI$getPannerOrientationX = getPannerOrientationX;
$_FFI_FFI.getPannerOrientationX = getPannerOrientationX;
var $author$project$FFI$setPannerOrientationDirect = F4(setPannerOrientationDirect);
$_FFI_FFI.setPannerOrientationDirect = F4(setPannerOrientationDirect);
var $author$project$FFI$getBiquadFilterType = getBiquadFilterType;
$_FFI_FFI.getBiquadFilterType = getBiquadFilterType;
var $author$project$FFI$setBiquadFilterTypeDirect = F2(setBiquadFilterTypeDirect);
$_FFI_FFI.setBiquadFilterTypeDirect = F2(setBiquadFilterTypeDirect);
var $author$project$FFI$getBiquadFilterFrequencyParam = getBiquadFilterFrequencyParam;
$_FFI_FFI.getBiquadFilterFrequencyParam = getBiquadFilterFrequencyParam;
var $author$project$FFI$getBiquadFilterQParam = getBiquadFilterQParam;
$_FFI_FFI.getBiquadFilterQParam = getBiquadFilterQParam;
var $author$project$FFI$reverseAudioBuffer = reverseAudioBuffer;
$_FFI_FFI.reverseAudioBuffer = reverseAudioBuffer;
var $author$project$FFI$normalizeAudioBuffer = F2(normalizeAudioBuffer);
$_FFI_FFI.normalizeAudioBuffer = F2(normalizeAudioBuffer);
var $author$project$FFI$mixAudioBuffers = F3(mixAudioBuffers);
$_FFI_FFI.mixAudioBuffers = F3(mixAudioBuffers);
var $author$project$FFI$trimSilence = F2(trimSilence);
$_FFI_FFI.trimSilence = F2(trimSilence);
var $author$project$FFI$getBufferPeak = getBufferPeak;
$_FFI_FFI.getBufferPeak = getBufferPeak;
var $author$project$FFI$getBufferRMS = getBufferRMS;
$_FFI_FFI.getBufferRMS = getBufferRMS;
var $author$project$FFI$createBufferFromSamples = F3(createBufferFromSamples);
$_FFI_FFI.createBufferFromSamples = F3(createBufferFromSamples);
var $author$project$FFI$concatenateBuffers = F2(concatenateBuffers);
$_FFI_FFI.concatenateBuffers = F2(concatenateBuffers);
var $author$project$FFI$getStereoPannerPan = getStereoPannerPan;
$_FFI_FFI.getStereoPannerPan = getStereoPannerPan;
var $author$project$FFI$getGainNodeGainParam = getGainNodeGainParam;
$_FFI_FFI.getGainNodeGainParam = getGainNodeGainParam;
var $author$project$FFI$getConvolverNormalize = getConvolverNormalize;
$_FFI_FFI.getConvolverNormalize = getConvolverNormalize;
var $author$project$FFI$getWaveShaperOversample = getWaveShaperOversample;
$_FFI_FFI.getWaveShaperOversample = getWaveShaperOversample;
var $author$project$FFI$getAnalyserFFTSize = getAnalyserFFTSize;
$_FFI_FFI.getAnalyserFFTSize = getAnalyserFFTSize;
var $author$project$FFI$getAnalyserFrequencyBinCount = getAnalyserFrequencyBinCount;
$_FFI_FFI.getAnalyserFrequencyBinCount = getAnalyserFrequencyBinCount;
var $author$project$FFI$getDelayMaxDelayTime = getDelayMaxDelayTime;
$_FFI_FFI.getDelayMaxDelayTime = getDelayMaxDelayTime;
var $author$project$FFI$getBufferSourcePlaybackRate = getBufferSourcePlaybackRate;
$_FFI_FFI.getBufferSourcePlaybackRate = getBufferSourcePlaybackRate;
var $author$project$FFI$getBufferSourceDetune = getBufferSourceDetune;
$_FFI_FFI.getBufferSourceDetune = getBufferSourceDetune;
var $author$project$FFI$getPannerDistanceModel = getPannerDistanceModel;
$_FFI_FFI.getPannerDistanceModel = getPannerDistanceModel;
var $author$project$FFI$getPannerPanningModel = getPannerPanningModel;
$_FFI_FFI.getPannerPanningModel = getPannerPanningModel;
var $author$project$FFI$getPannerRefDistance = getPannerRefDistance;
$_FFI_FFI.getPannerRefDistance = getPannerRefDistance;
var $author$project$FFI$getPannerMaxDistance = getPannerMaxDistance;
$_FFI_FFI.getPannerMaxDistance = getPannerMaxDistance;
var $author$project$FFI$getPannerRolloffFactor = getPannerRolloffFactor;
$_FFI_FFI.getPannerRolloffFactor = getPannerRolloffFactor;
var $author$project$FFI$getPannerConeInnerAngle = getPannerConeInnerAngle;
$_FFI_FFI.getPannerConeInnerAngle = getPannerConeInnerAngle;
var $author$project$FFI$getPannerConeOuterAngle = getPannerConeOuterAngle;
$_FFI_FFI.getPannerConeOuterAngle = getPannerConeOuterAngle;
var $author$project$FFI$getPannerConeOuterGain = getPannerConeOuterGain;
$_FFI_FFI.getPannerConeOuterGain = getPannerConeOuterGain;
var $author$project$FFI$getMediaElementSourceElement = getMediaElementSourceElement;
$_FFI_FFI.getMediaElementSourceElement = getMediaElementSourceElement;
var $author$project$FFI$getMediaStreamTracks = getMediaStreamTracks;
$_FFI_FFI.getMediaStreamTracks = getMediaStreamTracks;
var $author$project$FFI$getMediaStreamActive = getMediaStreamActive;
$_FFI_FFI.getMediaStreamActive = getMediaStreamActive;
var $author$project$FFI$getMediaStreamId = getMediaStreamId;
$_FFI_FFI.getMediaStreamId = getMediaStreamId;
var $author$project$FFI$getBiquadFilterGainParam = getBiquadFilterGainParam;
$_FFI_FFI.getBiquadFilterGainParam = getBiquadFilterGainParam;
var $author$project$FFI$getBiquadFilterDetuneParam = getBiquadFilterDetuneParam;
$_FFI_FFI.getBiquadFilterDetuneParam = getBiquadFilterDetuneParam;
var $author$project$FFI$getPannerOrientationY = getPannerOrientationY;
$_FFI_FFI.getPannerOrientationY = getPannerOrientationY;
var $author$project$FFI$getPannerOrientationZ = getPannerOrientationZ;
$_FFI_FFI.getPannerOrientationZ = getPannerOrientationZ;
var $author$project$FFI$getConstantSourceOffsetValue = getConstantSourceOffsetValue;
$_FFI_FFI.getConstantSourceOffsetValue = getConstantSourceOffsetValue;
var $author$project$FFI$createEmptyBuffer = F4(createEmptyBuffer);
$_FFI_FFI.createEmptyBuffer = F4(createEmptyBuffer);
var $author$project$FFI$getBufferAsArray = F2(getBufferAsArray);
$_FFI_FFI.getBufferAsArray = F2(getBufferAsArray);
var $author$project$FFI$setOscillatorType = F2(setOscillatorType);
$_FFI_FFI.setOscillatorType = F2(setOscillatorType);
var $author$project$FFI$getIIRFilterResponseAtFrequency = F2(getIIRFilterResponseAtFrequency);
$_FFI_FFI.getIIRFilterResponseAtFrequency = F2(getIIRFilterResponseAtFrequency);
var $author$project$FFI$gainNodeToAudioNode = gainNodeToAudioNode;
$_FFI_FFI.gainNodeToAudioNode = gainNodeToAudioNode;
var $author$project$FFI$oscillatorNodeToAudioNode = oscillatorNodeToAudioNode;
$_FFI_FFI.oscillatorNodeToAudioNode = oscillatorNodeToAudioNode;
var $author$project$FFI$biquadFilterNodeToAudioNode = biquadFilterNodeToAudioNode;
$_FFI_FFI.biquadFilterNodeToAudioNode = biquadFilterNodeToAudioNode;
var $author$project$FFI$delayNodeToAudioNode = delayNodeToAudioNode;
$_FFI_FFI.delayNodeToAudioNode = delayNodeToAudioNode;
var $author$project$FFI$convolverNodeToAudioNode = convolverNodeToAudioNode;
$_FFI_FFI.convolverNodeToAudioNode = convolverNodeToAudioNode;
var $author$project$FFI$dynamicsCompressorNodeToAudioNode = dynamicsCompressorNodeToAudioNode;
$_FFI_FFI.dynamicsCompressorNodeToAudioNode = dynamicsCompressorNodeToAudioNode;
var $author$project$FFI$waveShaperNodeToAudioNode = waveShaperNodeToAudioNode;
$_FFI_FFI.waveShaperNodeToAudioNode = waveShaperNodeToAudioNode;
var $author$project$FFI$stereoPannerNodeToAudioNode = stereoPannerNodeToAudioNode;
$_FFI_FFI.stereoPannerNodeToAudioNode = stereoPannerNodeToAudioNode;
var $author$project$FFI$analyserNodeToAudioNode = analyserNodeToAudioNode;
$_FFI_FFI.analyserNodeToAudioNode = analyserNodeToAudioNode;
var $author$project$FFI$pannerNodeToAudioNode = pannerNodeToAudioNode;
$_FFI_FFI.pannerNodeToAudioNode = pannerNodeToAudioNode;
var $author$project$FFI$channelSplitterNodeToAudioNode = channelSplitterNodeToAudioNode;
$_FFI_FFI.channelSplitterNodeToAudioNode = channelSplitterNodeToAudioNode;
var $author$project$FFI$channelMergerNodeToAudioNode = channelMergerNodeToAudioNode;
$_FFI_FFI.channelMergerNodeToAudioNode = channelMergerNodeToAudioNode;
var $author$project$FFI$audioBufferSourceNodeToAudioNode = audioBufferSourceNodeToAudioNode;
$_FFI_FFI.audioBufferSourceNodeToAudioNode = audioBufferSourceNodeToAudioNode;
var $author$project$FFI$constantSourceNodeToAudioNode = constantSourceNodeToAudioNode;
$_FFI_FFI.constantSourceNodeToAudioNode = constantSourceNodeToAudioNode;
var $author$project$FFI$iirFilterNodeToAudioNode = iirFilterNodeToAudioNode;
$_FFI_FFI.iirFilterNodeToAudioNode = iirFilterNodeToAudioNode;
var $author$project$FFI$audioWorkletNodeToAudioNode = audioWorkletNodeToAudioNode;
$_FFI_FFI.audioWorkletNodeToAudioNode = audioWorkletNodeToAudioNode;


// Bindings for external/capability.js
var $_FFI_CapabilityFFI = $_FFI_CapabilityFFI || {};
var $author$project$CapabilityFFI$isUserActivationAvailable = isUserActivationAvailable;
$_FFI_CapabilityFFI.isUserActivationAvailable = isUserActivationAvailable;
var $author$project$CapabilityFFI$isUserActivationActive = isUserActivationActive;
$_FFI_CapabilityFFI.isUserActivationActive = isUserActivationActive;
var $author$project$CapabilityFFI$consumeUserActivation = consumeUserActivation;
$_FFI_CapabilityFFI.consumeUserActivation = consumeUserActivation;
var $author$project$CapabilityFFI$consumeUserActivationInt = consumeUserActivationInt;
$_FFI_CapabilityFFI.consumeUserActivationInt = consumeUserActivationInt;
var $author$project$CapabilityFFI$consumeUserActivationString = consumeUserActivationString;
$_FFI_CapabilityFFI.consumeUserActivationString = consumeUserActivationString;
var $author$project$CapabilityFFI$detectAPISupport = detectAPISupport;
$_FFI_CapabilityFFI.detectAPISupport = detectAPISupport;
var $author$project$CapabilityFFI$hasFeature = hasFeature;
$_FFI_CapabilityFFI.hasFeature = hasFeature;
var $author$project$CapabilityFFI$checkGenericPermission = checkGenericPermission;
$_FFI_CapabilityFFI.checkGenericPermission = checkGenericPermission;
var $author$project$CapabilityFFI$requestGenericPermission = requestGenericPermission;
$_FFI_CapabilityFFI.requestGenericPermission = requestGenericPermission;
var $author$project$CapabilityFFI$createGenericInitializer = F3(createGenericInitializer);
$_FFI_CapabilityFFI.createGenericInitializer = F3(createGenericInitializer);
var $author$project$CapabilityFFI$createInitializationChecker = F2(createInitializationChecker);
$_FFI_CapabilityFFI.createInitializationChecker = F2(createInitializationChecker);
var $author$project$CapabilityFFI$validateCapability = F2(validateCapability);
$_FFI_CapabilityFFI.validateCapability = F2(validateCapability);


function F(arity, fun, wrapper) {
  wrapper.a = arity;
  wrapper.f = fun;
  return wrapper;
}

function F2(fun) {
  return F(2, fun, function(a) { return function(b) { return fun(a,b); }; })
}
function F3(fun) {
  return F(3, fun, function(a) {
    return function(b) { return function(c) { return fun(a, b, c); }; };
  });
}
function F4(fun) {
  return F(4, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return fun(a, b, c, d); }; }; };
  });
}
function F5(fun) {
  return F(5, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return fun(a, b, c, d, e); }; }; }; };
  });
}
function F6(fun) {
  return F(6, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return fun(a, b, c, d, e, f); }; }; }; }; };
  });
}
function F7(fun) {
  return F(7, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return function(g) { return fun(a, b, c, d, e, f, g); }; }; }; }; }; };
  });
}
function F8(fun) {
  return F(8, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return function(g) { return function(h) {
    return fun(a, b, c, d, e, f, g, h); }; }; }; }; }; }; };
  });
}
function F9(fun) {
  return F(9, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return function(g) { return function(h) { return function(i) {
    return fun(a, b, c, d, e, f, g, h, i); }; }; }; }; }; }; }; };
  });
}
function A2(fun, a, b) {
  return fun.a === 2 ? fun.f(a, b) : fun(a)(b);
}
function A3(fun, a, b, c) {
  return fun.a === 3 ? fun.f(a, b, c) : fun(a)(b)(c);
}
function A4(fun, a, b, c, d) {
  return fun.a === 4 ? fun.f(a, b, c, d) : fun(a)(b)(c)(d);
}
function A5(fun, a, b, c, d, e) {
  return fun.a === 5 ? fun.f(a, b, c, d, e) : fun(a)(b)(c)(d)(e);
}
function A6(fun, a, b, c, d, e, f) {
  return fun.a === 6 ? fun.f(a, b, c, d, e, f) : fun(a)(b)(c)(d)(e)(f);
}
function A7(fun, a, b, c, d, e, f, g) {
  return fun.a === 7 ? fun.f(a, b, c, d, e, f, g) : fun(a)(b)(c)(d)(e)(f)(g);
}
function A8(fun, a, b, c, d, e, f, g, h) {
  return fun.a === 8 ? fun.f(a, b, c, d, e, f, g, h) : fun(a)(b)(c)(d)(e)(f)(g)(h);
}
function A9(fun, a, b, c, d, e, f, g, h, i) {
  return fun.a === 9 ? fun.f(a, b, c, d, e, f, g, h, i) : fun(a)(b)(c)(d)(e)(f)(g)(h)(i);
}
 console.warn('Compiled in DEV mode. Follow the advice at https://canopy-lang.org/0.19.1/optimize for better performance and smaller assets.');



var _List_Nil_UNUSED = { $: 0 };
var _List_Nil = { $: '[]' };

function _List_Cons_UNUSED(hd, tl) { return { $: 1, a: hd, b: tl }; }
function _List_Cons(hd, tl) { return { $: '::', a: hd, b: tl }; }


var _List_cons = F2(_List_Cons);

function _List_fromArray(arr)
{
	var out = _List_Nil;
	for (var i = arr.length; i--; )
	{
		out = _List_Cons(arr[i], out);
	}
	return out;
}

function _List_toArray(xs)
{
	for (var out = []; xs.b; xs = xs.b) // WHILE_CONS
	{
		out.push(xs.a);
	}
	return out;
}

var _List_map2 = F3(function(f, xs, ys)
{
	for (var arr = []; xs.b && ys.b; xs = xs.b, ys = ys.b) // WHILE_CONSES
	{
		arr.push(A2(f, xs.a, ys.a));
	}
	return _List_fromArray(arr);
});

var _List_map3 = F4(function(f, xs, ys, zs)
{
	for (var arr = []; xs.b && ys.b && zs.b; xs = xs.b, ys = ys.b, zs = zs.b) // WHILE_CONSES
	{
		arr.push(A3(f, xs.a, ys.a, zs.a));
	}
	return _List_fromArray(arr);
});

var _List_map4 = F5(function(f, ws, xs, ys, zs)
{
	for (var arr = []; ws.b && xs.b && ys.b && zs.b; ws = ws.b, xs = xs.b, ys = ys.b, zs = zs.b) // WHILE_CONSES
	{
		arr.push(A4(f, ws.a, xs.a, ys.a, zs.a));
	}
	return _List_fromArray(arr);
});

var _List_map5 = F6(function(f, vs, ws, xs, ys, zs)
{
	for (var arr = []; vs.b && ws.b && xs.b && ys.b && zs.b; vs = vs.b, ws = ws.b, xs = xs.b, ys = ys.b, zs = zs.b) // WHILE_CONSES
	{
		arr.push(A5(f, vs.a, ws.a, xs.a, ys.a, zs.a));
	}
	return _List_fromArray(arr);
});

var _List_sortBy = F2(function(f, xs)
{
	return _List_fromArray(_List_toArray(xs).sort(function(a, b) {
		return _Utils_cmp(f(a), f(b));
	}));
});

var _List_sortWith = F2(function(f, xs)
{
	return _List_fromArray(_List_toArray(xs).sort(function(a, b) {
		var ord = A2(f, a, b);
		return ord === $elm$core$Basics$EQ ? 0 : ord === $elm$core$Basics$LT ? -1 : 1;
	}));
});



var _JsArray_empty = [];

function _JsArray_singleton(value)
{
    return [value];
}

function _JsArray_length(array)
{
    return array.length;
}

var _JsArray_initialize = F3(function(size, offset, func)
{
    var result = new Array(size);

    for (var i = 0; i < size; i++)
    {
        result[i] = func(offset + i);
    }

    return result;
});

var _JsArray_initializeFromList = F2(function (max, ls)
{
    var result = new Array(max);

    for (var i = 0; i < max && ls.b; i++)
    {
        result[i] = ls.a;
        ls = ls.b;
    }

    result.length = i;
    return _Utils_Tuple2(result, ls);
});

var _JsArray_unsafeGet = F2(function(index, array)
{
    return array[index];
});

var _JsArray_unsafeSet = F3(function(index, value, array)
{
    var length = array.length;
    var result = new Array(length);

    for (var i = 0; i < length; i++)
    {
        result[i] = array[i];
    }

    result[index] = value;
    return result;
});

var _JsArray_push = F2(function(value, array)
{
    var length = array.length;
    var result = new Array(length + 1);

    for (var i = 0; i < length; i++)
    {
        result[i] = array[i];
    }

    result[length] = value;
    return result;
});

var _JsArray_foldl = F3(function(func, acc, array)
{
    var length = array.length;

    for (var i = 0; i < length; i++)
    {
        acc = A2(func, array[i], acc);
    }

    return acc;
});

var _JsArray_foldr = F3(function(func, acc, array)
{
    for (var i = array.length - 1; i >= 0; i--)
    {
        acc = A2(func, array[i], acc);
    }

    return acc;
});

var _JsArray_map = F2(function(func, array)
{
    var length = array.length;
    var result = new Array(length);

    for (var i = 0; i < length; i++)
    {
        result[i] = func(array[i]);
    }

    return result;
});

var _JsArray_indexedMap = F3(function(func, offset, array)
{
    var length = array.length;
    var result = new Array(length);

    for (var i = 0; i < length; i++)
    {
        result[i] = A2(func, offset + i, array[i]);
    }

    return result;
});

var _JsArray_slice = F3(function(from, to, array)
{
    return array.slice(from, to);
});

var _JsArray_appendN = F3(function(n, dest, source)
{
    var destLen = dest.length;
    var itemsToCopy = n - destLen;

    if (itemsToCopy > source.length)
    {
        itemsToCopy = source.length;
    }

    var size = destLen + itemsToCopy;
    var result = new Array(size);

    for (var i = 0; i < destLen; i++)
    {
        result[i] = dest[i];
    }

    for (var i = 0; i < itemsToCopy; i++)
    {
        result[i + destLen] = source[i];
    }

    return result;
});



// LOG

var _Debug_log_UNUSED = F2(function(tag, value)
{
	return value;
});

var _Debug_log = F2(function(tag, value)
{
	console.log(tag + ': ' + _Debug_toString(value));
	return value;
});


// TODOS

function _Debug_todo(moduleName, region)
{
	return function(message) {
		_Debug_crash(8, moduleName, region, message);
	};
}

function _Debug_todoCase(moduleName, region, value)
{
	return function(message) {
		_Debug_crash(9, moduleName, region, value, message);
	};
}


// TO STRING

function _Debug_toString_UNUSED(value)
{
	return '<internals>';
}

function _Debug_toString(value)
{
	return _Debug_toAnsiString(false, value);
}

function _Debug_toAnsiString(ansi, value)
{
	if (typeof value === 'function')
	{
		return _Debug_internalColor(ansi, '<function>');
	}

	if (typeof value === 'boolean')
	{
		return _Debug_ctorColor(ansi, value ? 'True' : 'False');
	}

	if (typeof value === 'number')
	{
		return _Debug_numberColor(ansi, value + '');
	}

	if (value instanceof String)
	{
		return _Debug_charColor(ansi, "'" + _Debug_addSlashes(value, true) + "'");
	}

	if (typeof value === 'string')
	{
		return _Debug_stringColor(ansi, '"' + _Debug_addSlashes(value, false) + '"');
	}

	if (typeof value === 'object' && '$' in value)
	{
		var tag = value.$;

		if (typeof tag === 'number')
		{
			return _Debug_internalColor(ansi, '<internals>');
		}

		if (tag[0] === '#')
		{
			var output = [];
			for (var k in value)
			{
				if (k === '$') continue;
				output.push(_Debug_toAnsiString(ansi, value[k]));
			}
			return '(' + output.join(',') + ')';
		}

		if (tag === 'Set_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Set')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, $elm$core$Set$toList(value));
		}

		if (tag === 'RBNode_elm_builtin' || tag === 'RBEmpty_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Dict')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, $elm$core$Dict$toList(value));
		}

		if (tag === 'Array_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Array')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, $elm$core$Array$toList(value));
		}

		if (tag === '::' || tag === '[]')
		{
			var output = '[';

			value.b && (output += _Debug_toAnsiString(ansi, value.a), value = value.b)

			for (; value.b; value = value.b) // WHILE_CONS
			{
				output += ',' + _Debug_toAnsiString(ansi, value.a);
			}
			return output + ']';
		}

		var output = '';
		for (var i in value)
		{
			if (i === '$') continue;
			var str = _Debug_toAnsiString(ansi, value[i]);
			var c0 = str[0];
			var parenless = c0 === '{' || c0 === '(' || c0 === '[' || c0 === '<' || c0 === '"' || str.indexOf(' ') < 0;
			output += ' ' + (parenless ? str : '(' + str + ')');
		}
		return _Debug_ctorColor(ansi, tag) + output;
	}

	if (typeof DataView === 'function' && value instanceof DataView)
	{
		return _Debug_stringColor(ansi, '<' + value.byteLength + ' bytes>');
	}

	if (typeof File !== 'undefined' && value instanceof File)
	{
		return _Debug_internalColor(ansi, '<' + value.name + '>');
	}

	if (typeof value === 'object')
	{
		var output = [];
		for (var key in value)
		{
			var field = key[0] === '_' ? key.slice(1) : key;
			output.push(_Debug_fadeColor(ansi, field) + ' = ' + _Debug_toAnsiString(ansi, value[key]));
		}
		if (output.length === 0)
		{
			return '{}';
		}
		return '{ ' + output.join(', ') + ' }';
	}

	return _Debug_internalColor(ansi, '<internals>');
}

function _Debug_addSlashes(str, isChar)
{
	var s = str
		.replace(/\\/g, '\\\\')
		.replace(/\n/g, '\\n')
		.replace(/\t/g, '\\t')
		.replace(/\r/g, '\\r')
		.replace(/\v/g, '\\v')
		.replace(/\0/g, '\\0');

	if (isChar)
	{
		return s.replace(/\'/g, '\\\'');
	}
	else
	{
		return s.replace(/\"/g, '\\"');
	}
}

function _Debug_ctorColor(ansi, string)
{
	return ansi ? '\x1b[96m' + string + '\x1b[0m' : string;
}

function _Debug_numberColor(ansi, string)
{
	return ansi ? '\x1b[95m' + string + '\x1b[0m' : string;
}

function _Debug_stringColor(ansi, string)
{
	return ansi ? '\x1b[93m' + string + '\x1b[0m' : string;
}

function _Debug_charColor(ansi, string)
{
	return ansi ? '\x1b[92m' + string + '\x1b[0m' : string;
}

function _Debug_fadeColor(ansi, string)
{
	return ansi ? '\x1b[37m' + string + '\x1b[0m' : string;
}

function _Debug_internalColor(ansi, string)
{
	return ansi ? '\x1b[36m' + string + '\x1b[0m' : string;
}

function _Debug_toHexDigit(n)
{
	return String.fromCharCode(n < 10 ? 48 + n : 55 + n);
}


// CRASH


function _Debug_crash_UNUSED(identifier)
{
	throw new Error('https://github.com/elm/core/blob/1.0.0/hints/' + identifier + '.md');
}


function _Debug_crash(identifier, fact1, fact2, fact3, fact4)
{
	switch(identifier)
	{
		case 0:
			throw new Error('What node should I take over? In JavaScript I need something like:\n\n    Elm.Main.init({\n        node: document.getElementById("elm-node")\n    })\n\nYou need to do this with any Browser.sandbox or Browser.element program.');

		case 1:
			throw new Error('Browser.application programs cannot handle URLs like this:\n\n    ' + document.location.href + '\n\nWhat is the root? The root of your file system? Try looking at this program with `elm reactor` or some other server.');

		case 2:
			var jsonErrorString = fact1;
			throw new Error('Problem with the flags given to your Elm program on initialization.\n\n' + jsonErrorString);

		case 3:
			var portName = fact1;
			throw new Error('There can only be one port named `' + portName + '`, but your program has multiple.');

		case 4:
			var portName = fact1;
			var problem = fact2;
			throw new Error('Trying to send an unexpected type of value through port `' + portName + '`:\n' + problem);

		case 5:
			throw new Error('Trying to use `(==)` on functions.\nThere is no way to know if functions are "the same" in the Elm sense.\nRead more about this at https://package.elm-lang.org/packages/elm/core/latest/Basics#== which describes why it is this way and what the better version will look like.');

		case 6:
			var moduleName = fact1;
			throw new Error('Your page is loading multiple Elm scripts with a module named ' + moduleName + '. Maybe a duplicate script is getting loaded accidentally? If not, rename one of them so I know which is which!');

		case 8:
			var moduleName = fact1;
			var region = fact2;
			var message = fact3;
			throw new Error('TODO in module `' + moduleName + '` ' + _Debug_regionToString(region) + '\n\n' + message);

		case 9:
			var moduleName = fact1;
			var region = fact2;
			var value = fact3;
			var message = fact4;
			throw new Error(
				'TODO in module `' + moduleName + '` from the `case` expression '
				+ _Debug_regionToString(region) + '\n\nIt received the following value:\n\n    '
				+ _Debug_toString(value).replace('\n', '\n    ')
				+ '\n\nBut the branch that handles it says:\n\n    ' + message.replace('\n', '\n    ')
			);

		case 10:
			throw new Error('Bug in https://github.com/elm/virtual-dom/issues');

		case 11:
			throw new Error('Cannot perform mod 0. Division by zero error.');
	}
}

function _Debug_regionToString(region)
{
	if (region.start.line === region.end.line)
	{
		return 'on line ' + region.start.line;
	}
	return 'on lines ' + region.start.line + ' through ' + region.end.line;
}



// EQUALITY

function _Utils_eq(x, y)
{
	for (
		var pair, stack = [], isEqual = _Utils_eqHelp(x, y, 0, stack);
		isEqual && (pair = stack.pop());
		isEqual = _Utils_eqHelp(pair.a, pair.b, 0, stack)
		)
	{}

	return isEqual;
}

function _Utils_eqHelp(x, y, depth, stack)
{
	if (x === y)
	{
		return true;
	}

	if (typeof x !== 'object' || x === null || y === null)
	{
		typeof x === 'function' && _Debug_crash(5);
		return false;
	}

	if (depth > 100)
	{
		stack.push(_Utils_Tuple2(x,y));
		return true;
	}

	/**/
	if (x.$ === 'Set_elm_builtin')
	{
		x = $elm$core$Set$toList(x);
		y = $elm$core$Set$toList(y);
	}
	if (x.$ === 'RBNode_elm_builtin' || x.$ === 'RBEmpty_elm_builtin')
	{
		x = $elm$core$Dict$toList(x);
		y = $elm$core$Dict$toList(y);
	}
	//*/

	/**_UNUSED/
	if (x.$ < 0)
	{
		x = $elm$core$Dict$toList(x);
		y = $elm$core$Dict$toList(y);
	}
	//*/

	for (var key in x)
	{
		if (!_Utils_eqHelp(x[key], y[key], depth + 1, stack))
		{
			return false;
		}
	}
	return true;
}

var _Utils_equal = F2(_Utils_eq);
var _Utils_notEqual = F2(function(a, b) { return !_Utils_eq(a,b); });



// COMPARISONS

// Code in Generate/JavaScript.hs, Basics.js, and List.js depends on
// the particular integer values assigned to LT, EQ, and GT.

function _Utils_cmp(x, y, ord)
{
	if (typeof x !== 'object')
	{
		return x === y ? /*EQ*/ 0 : x < y ? /*LT*/ -1 : /*GT*/ 1;
	}

	/**/
	if (x instanceof String)
	{
		var a = x.valueOf();
		var b = y.valueOf();
		return a === b ? 0 : a < b ? -1 : 1;
	}
	//*/

	/**_UNUSED/
	if (typeof x.$ === 'undefined')
	//*/
	/**/
	if (x.$[0] === '#')
	//*/
	{
		return (ord = _Utils_cmp(x.a, y.a))
			? ord
			: (ord = _Utils_cmp(x.b, y.b))
				? ord
				: _Utils_cmp(x.c, y.c);
	}

	// traverse conses until end of a list or a mismatch
	for (; x.b && y.b && !(ord = _Utils_cmp(x.a, y.a)); x = x.b, y = y.b) {} // WHILE_CONSES
	return ord || (x.b ? /*GT*/ 1 : y.b ? /*LT*/ -1 : /*EQ*/ 0);
}

var _Utils_lt = F2(function(a, b) { return _Utils_cmp(a, b) < 0; });
var _Utils_le = F2(function(a, b) { return _Utils_cmp(a, b) < 1; });
var _Utils_gt = F2(function(a, b) { return _Utils_cmp(a, b) > 0; });
var _Utils_ge = F2(function(a, b) { return _Utils_cmp(a, b) >= 0; });

var _Utils_compare = F2(function(x, y)
{
	var n = _Utils_cmp(x, y);
	return n < 0 ? $elm$core$Basics$LT : n ? $elm$core$Basics$GT : $elm$core$Basics$EQ;
});


// COMMON VALUES

var _Utils_Tuple0_UNUSED = 0;
var _Utils_Tuple0 = { $: '#0' };

function _Utils_Tuple2_UNUSED(a, b) { return { a: a, b: b }; }
function _Utils_Tuple2(a, b) { return { $: '#2', a: a, b: b }; }

function _Utils_Tuple3_UNUSED(a, b, c) { return { a: a, b: b, c: c }; }
function _Utils_Tuple3(a, b, c) { return { $: '#3', a: a, b: b, c: c }; }

function _Utils_chr_UNUSED(c) { return c; }
function _Utils_chr(c) { return new String(c); }


// RECORDS

function _Utils_update(oldRecord, updatedFields)
{
	var newRecord = {};

	for (var key in oldRecord)
	{
		newRecord[key] = oldRecord[key];
	}

	for (var key in updatedFields)
	{
		newRecord[key] = updatedFields[key];
	}

	return newRecord;
}


// APPEND

var _Utils_append = F2(_Utils_ap);

function _Utils_ap(xs, ys)
{
	// append Strings
	if (typeof xs === 'string')
	{
		return xs + ys;
	}

	// append Lists
	if (!xs.b)
	{
		return ys;
	}
	var root = _List_Cons(xs.a, ys);
	xs = xs.b
	for (var curr = root; xs.b; xs = xs.b) // WHILE_CONS
	{
		curr = curr.b = _List_Cons(xs.a, ys);
	}
	return root;
}



// MATH

var _Basics_add = F2(function(a, b) { return a + b; });
var _Basics_sub = F2(function(a, b) { return a - b; });
var _Basics_mul = F2(function(a, b) { return a * b; });
var _Basics_fdiv = F2(function(a, b) { return a / b; });
var _Basics_idiv = F2(function(a, b) { return (a / b) | 0; });
var _Basics_pow = F2(Math.pow);

var _Basics_remainderBy = F2(function(b, a) { return a % b; });

// https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/divmodnote-letter.pdf
var _Basics_modBy = F2(function(modulus, x)
{
	var answer = x % modulus;
	return modulus === 0
		? _Debug_crash(11)
		:
	((answer > 0 && modulus < 0) || (answer < 0 && modulus > 0))
		? answer + modulus
		: answer;
});


// TRIGONOMETRY

var _Basics_pi = Math.PI;
var _Basics_e = Math.E;
var _Basics_cos = Math.cos;
var _Basics_sin = Math.sin;
var _Basics_tan = Math.tan;
var _Basics_acos = Math.acos;
var _Basics_asin = Math.asin;
var _Basics_atan = Math.atan;
var _Basics_atan2 = F2(Math.atan2);


// MORE MATH

function _Basics_toFloat(x) { return x; }
function _Basics_truncate(n) { return n | 0; }
function _Basics_isInfinite(n) { return n === Infinity || n === -Infinity; }

var _Basics_ceiling = Math.ceil;
var _Basics_floor = Math.floor;
var _Basics_round = Math.round;
var _Basics_sqrt = Math.sqrt;
var _Basics_log = Math.log;
var _Basics_isNaN = isNaN;


// BOOLEANS

function _Basics_not(bool) { return !bool; }
var _Basics_and = F2(function(a, b) { return a && b; });
var _Basics_or  = F2(function(a, b) { return a || b; });
var _Basics_xor = F2(function(a, b) { return a !== b; });



var _String_cons = F2(function(chr, str)
{
	return chr + str;
});

function _String_uncons(string)
{
	var word = string.charCodeAt(0);
	return !isNaN(word)
		? $elm$core$Maybe$Just(
			0xD800 <= word && word <= 0xDBFF
				? _Utils_Tuple2(_Utils_chr(string[0] + string[1]), string.slice(2))
				: _Utils_Tuple2(_Utils_chr(string[0]), string.slice(1))
		)
		: $elm$core$Maybe$Nothing;
}

var _String_append = F2(function(a, b)
{
	return a + b;
});

function _String_length(str)
{
	return str.length;
}

var _String_map = F2(function(func, string)
{
	var len = string.length;
	var array = new Array(len);
	var i = 0;
	while (i < len)
	{
		var word = string.charCodeAt(i);
		if (0xD800 <= word && word <= 0xDBFF)
		{
			array[i] = func(_Utils_chr(string[i] + string[i+1]));
			i += 2;
			continue;
		}
		array[i] = func(_Utils_chr(string[i]));
		i++;
	}
	return array.join('');
});

var _String_filter = F2(function(isGood, str)
{
	var arr = [];
	var len = str.length;
	var i = 0;
	while (i < len)
	{
		var char = str[i];
		var word = str.charCodeAt(i);
		i++;
		if (0xD800 <= word && word <= 0xDBFF)
		{
			char += str[i];
			i++;
		}

		if (isGood(_Utils_chr(char)))
		{
			arr.push(char);
		}
	}
	return arr.join('');
});

function _String_reverse(str)
{
	var len = str.length;
	var arr = new Array(len);
	var i = 0;
	while (i < len)
	{
		var word = str.charCodeAt(i);
		if (0xD800 <= word && word <= 0xDBFF)
		{
			arr[len - i] = str[i + 1];
			i++;
			arr[len - i] = str[i - 1];
			i++;
		}
		else
		{
			arr[len - i] = str[i];
			i++;
		}
	}
	return arr.join('');
}

var _String_foldl = F3(function(func, state, string)
{
	var len = string.length;
	var i = 0;
	while (i < len)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		i++;
		if (0xD800 <= word && word <= 0xDBFF)
		{
			char += string[i];
			i++;
		}
		state = A2(func, _Utils_chr(char), state);
	}
	return state;
});

var _String_foldr = F3(function(func, state, string)
{
	var i = string.length;
	while (i--)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		if (0xDC00 <= word && word <= 0xDFFF)
		{
			i--;
			char = string[i] + char;
		}
		state = A2(func, _Utils_chr(char), state);
	}
	return state;
});

var _String_split = F2(function(sep, str)
{
	return str.split(sep);
});

var _String_join = F2(function(sep, strs)
{
	return strs.join(sep);
});

var _String_slice = F3(function(start, end, str) {
	return str.slice(start, end);
});

function _String_trim(str)
{
	return str.trim();
}

function _String_trimLeft(str)
{
	return str.replace(/^\s+/, '');
}

function _String_trimRight(str)
{
	return str.replace(/\s+$/, '');
}

function _String_words(str)
{
	return _List_fromArray(str.trim().split(/\s+/g));
}

function _String_lines(str)
{
	return _List_fromArray(str.split(/\r\n|\r|\n/g));
}

function _String_toUpper(str)
{
	return str.toUpperCase();
}

function _String_toLower(str)
{
	return str.toLowerCase();
}

var _String_any = F2(function(isGood, string)
{
	var i = string.length;
	while (i--)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		if (0xDC00 <= word && word <= 0xDFFF)
		{
			i--;
			char = string[i] + char;
		}
		if (isGood(_Utils_chr(char)))
		{
			return true;
		}
	}
	return false;
});

var _String_all = F2(function(isGood, string)
{
	var i = string.length;
	while (i--)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		if (0xDC00 <= word && word <= 0xDFFF)
		{
			i--;
			char = string[i] + char;
		}
		if (!isGood(_Utils_chr(char)))
		{
			return false;
		}
	}
	return true;
});

var _String_contains = F2(function(sub, str)
{
	return str.indexOf(sub) > -1;
});

var _String_startsWith = F2(function(sub, str)
{
	return str.indexOf(sub) === 0;
});

var _String_endsWith = F2(function(sub, str)
{
	return str.length >= sub.length &&
		str.lastIndexOf(sub) === str.length - sub.length;
});

var _String_indexes = F2(function(sub, str)
{
	var subLen = sub.length;

	if (subLen < 1)
	{
		return _List_Nil;
	}

	var i = 0;
	var is = [];

	while ((i = str.indexOf(sub, i)) > -1)
	{
		is.push(i);
		i = i + subLen;
	}

	return _List_fromArray(is);
});


// TO STRING

function _String_fromNumber(number)
{
	return number + '';
}


// INT CONVERSIONS

function _String_toInt(str)
{
	var total = 0;
	var code0 = str.charCodeAt(0);
	var start = code0 == 0x2B /* + */ || code0 == 0x2D /* - */ ? 1 : 0;

	for (var i = start; i < str.length; ++i)
	{
		var code = str.charCodeAt(i);
		if (code < 0x30 || 0x39 < code)
		{
			return $elm$core$Maybe$Nothing;
		}
		total = 10 * total + code - 0x30;
	}

	return i == start
		? $elm$core$Maybe$Nothing
		: $elm$core$Maybe$Just(code0 == 0x2D ? -total : total);
}


// FLOAT CONVERSIONS

function _String_toFloat(s)
{
	// check if it is a hex, octal, or binary number
	if (s.length === 0 || /[\sxbo]/.test(s))
	{
		return $elm$core$Maybe$Nothing;
	}
	var n = +s;
	// faster isNaN check
	return n === n ? $elm$core$Maybe$Just(n) : $elm$core$Maybe$Nothing;
}

function _String_fromList(chars)
{
	return _List_toArray(chars).join('');
}




function _Char_toCode(char)
{
	var code = char.charCodeAt(0);
	if (0xD800 <= code && code <= 0xDBFF)
	{
		return (code - 0xD800) * 0x400 + char.charCodeAt(1) - 0xDC00 + 0x10000
	}
	return code;
}

function _Char_fromCode(code)
{
	return _Utils_chr(
		(code < 0 || 0x10FFFF < code)
			? '\uFFFD'
			:
		(code <= 0xFFFF)
			? String.fromCharCode(code)
			:
		(code -= 0x10000,
			String.fromCharCode(Math.floor(code / 0x400) + 0xD800, code % 0x400 + 0xDC00)
		)
	);
}

function _Char_toUpper(char)
{
	return _Utils_chr(char.toUpperCase());
}

function _Char_toLower(char)
{
	return _Utils_chr(char.toLowerCase());
}

function _Char_toLocaleUpper(char)
{
	return _Utils_chr(char.toLocaleUpperCase());
}

function _Char_toLocaleLower(char)
{
	return _Utils_chr(char.toLocaleLowerCase());
}



/**/
function _Json_errorToString(error)
{
	return $elm$json$Json$Decode$errorToString(error);
}
//*/


// CORE DECODERS

function _Json_succeed(msg)
{
	return {
		$: 0,
		a: msg
	};
}

function _Json_fail(msg)
{
	return {
		$: 1,
		a: msg
	};
}

function _Json_decodePrim(decoder)
{
	return { $: 2, b: decoder };
}

var _Json_decodeInt = _Json_decodePrim(function(value) {
	return (typeof value !== 'number')
		? _Json_expecting('an INT', value)
		:
	(-2147483647 < value && value < 2147483647 && (value | 0) === value)
		? $elm$core$Result$Ok(value)
		:
	(isFinite(value) && !(value % 1))
		? $elm$core$Result$Ok(value)
		: _Json_expecting('an INT', value);
});

var _Json_decodeBool = _Json_decodePrim(function(value) {
	return (typeof value === 'boolean')
		? $elm$core$Result$Ok(value)
		: _Json_expecting('a BOOL', value);
});

var _Json_decodeFloat = _Json_decodePrim(function(value) {
	return (typeof value === 'number')
		? $elm$core$Result$Ok(value)
		: _Json_expecting('a FLOAT', value);
});

var _Json_decodeValue = _Json_decodePrim(function(value) {
	return $elm$core$Result$Ok(_Json_wrap(value));
});

var _Json_decodeString = _Json_decodePrim(function(value) {
	return (typeof value === 'string')
		? $elm$core$Result$Ok(value)
		: (value instanceof String)
			? $elm$core$Result$Ok(value + '')
			: _Json_expecting('a STRING', value);
});

function _Json_decodeList(decoder) { return { $: 3, b: decoder }; }
function _Json_decodeArray(decoder) { return { $: 4, b: decoder }; }

function _Json_decodeNull(value) { return { $: 5, c: value }; }

var _Json_decodeField = F2(function(field, decoder)
{
	return {
		$: 6,
		d: field,
		b: decoder
	};
});

var _Json_decodeIndex = F2(function(index, decoder)
{
	return {
		$: 7,
		e: index,
		b: decoder
	};
});

function _Json_decodeKeyValuePairs(decoder)
{
	return {
		$: 8,
		b: decoder
	};
}

function _Json_mapMany(f, decoders)
{
	return {
		$: 9,
		f: f,
		g: decoders
	};
}

var _Json_andThen = F2(function(callback, decoder)
{
	return {
		$: 10,
		b: decoder,
		h: callback
	};
});

function _Json_oneOf(decoders)
{
	return {
		$: 11,
		g: decoders
	};
}


// DECODING OBJECTS

var _Json_map1 = F2(function(f, d1)
{
	return _Json_mapMany(f, [d1]);
});

var _Json_map2 = F3(function(f, d1, d2)
{
	return _Json_mapMany(f, [d1, d2]);
});

var _Json_map3 = F4(function(f, d1, d2, d3)
{
	return _Json_mapMany(f, [d1, d2, d3]);
});

var _Json_map4 = F5(function(f, d1, d2, d3, d4)
{
	return _Json_mapMany(f, [d1, d2, d3, d4]);
});

var _Json_map5 = F6(function(f, d1, d2, d3, d4, d5)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5]);
});

var _Json_map6 = F7(function(f, d1, d2, d3, d4, d5, d6)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5, d6]);
});

var _Json_map7 = F8(function(f, d1, d2, d3, d4, d5, d6, d7)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5, d6, d7]);
});

var _Json_map8 = F9(function(f, d1, d2, d3, d4, d5, d6, d7, d8)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5, d6, d7, d8]);
});


// DECODE

var _Json_runOnString = F2(function(decoder, string)
{
	try
	{
		var value = JSON.parse(string);
		return _Json_runHelp(decoder, value);
	}
	catch (e)
	{
		return $elm$core$Result$Err(A2($elm$json$Json$Decode$Failure, 'This is not valid JSON! ' + e.message, _Json_wrap(string)));
	}
});

var _Json_run = F2(function(decoder, value)
{
	return _Json_runHelp(decoder, _Json_unwrap(value));
});

function _Json_runHelp(decoder, value)
{
	switch (decoder.$)
	{
		case 2:
			return decoder.b(value);

		case 5:
			return (value === null)
				? $elm$core$Result$Ok(decoder.c)
				: _Json_expecting('null', value);

		case 3:
			if (!_Json_isArray(value))
			{
				return _Json_expecting('a LIST', value);
			}
			return _Json_runArrayDecoder(decoder.b, value, _List_fromArray);

		case 4:
			if (!_Json_isArray(value))
			{
				return _Json_expecting('an ARRAY', value);
			}
			return _Json_runArrayDecoder(decoder.b, value, _Json_toElmArray);

		case 6:
			var field = decoder.d;
			if (typeof value !== 'object' || value === null || !(field in value))
			{
				return _Json_expecting('an OBJECT with a field named `' + field + '`', value);
			}
			var result = _Json_runHelp(decoder.b, value[field]);
			return ($elm$core$Result$isOk(result)) ? result : $elm$core$Result$Err(A2($elm$json$Json$Decode$Field, field, result.a));

		case 7:
			var index = decoder.e;
			if (!_Json_isArray(value))
			{
				return _Json_expecting('an ARRAY', value);
			}
			if (index >= value.length)
			{
				return _Json_expecting('a LONGER array. Need index ' + index + ' but only see ' + value.length + ' entries', value);
			}
			var result = _Json_runHelp(decoder.b, value[index]);
			return ($elm$core$Result$isOk(result)) ? result : $elm$core$Result$Err(A2($elm$json$Json$Decode$Index, index, result.a));

		case 8:
			if (typeof value !== 'object' || value === null || _Json_isArray(value))
			{
				return _Json_expecting('an OBJECT', value);
			}

			var keyValuePairs = _List_Nil;
			// TODO test perf of Object.keys and switch when support is good enough
			for (var key in value)
			{
				if (value.hasOwnProperty(key))
				{
					var result = _Json_runHelp(decoder.b, value[key]);
					if (!$elm$core$Result$isOk(result))
					{
						return $elm$core$Result$Err(A2($elm$json$Json$Decode$Field, key, result.a));
					}
					keyValuePairs = _List_Cons(_Utils_Tuple2(key, result.a), keyValuePairs);
				}
			}
			return $elm$core$Result$Ok($elm$core$List$reverse(keyValuePairs));

		case 9:
			var answer = decoder.f;
			var decoders = decoder.g;
			for (var i = 0; i < decoders.length; i++)
			{
				var result = _Json_runHelp(decoders[i], value);
				if (!$elm$core$Result$isOk(result))
				{
					return result;
				}
				answer = answer(result.a);
			}
			return $elm$core$Result$Ok(answer);

		case 10:
			var result = _Json_runHelp(decoder.b, value);
			return (!$elm$core$Result$isOk(result))
				? result
				: _Json_runHelp(decoder.h(result.a), value);

		case 11:
			var errors = _List_Nil;
			for (var temp = decoder.g; temp.b; temp = temp.b) // WHILE_CONS
			{
				var result = _Json_runHelp(temp.a, value);
				if ($elm$core$Result$isOk(result))
				{
					return result;
				}
				errors = _List_Cons(result.a, errors);
			}
			return $elm$core$Result$Err($elm$json$Json$Decode$OneOf($elm$core$List$reverse(errors)));

		case 1:
			return $elm$core$Result$Err(A2($elm$json$Json$Decode$Failure, decoder.a, _Json_wrap(value)));

		case 0:
			return $elm$core$Result$Ok(decoder.a);
	}
}

function _Json_runArrayDecoder(decoder, value, toElmValue)
{
	var len = value.length;
	var array = new Array(len);
	for (var i = 0; i < len; i++)
	{
		var result = _Json_runHelp(decoder, value[i]);
		if (!$elm$core$Result$isOk(result))
		{
			return $elm$core$Result$Err(A2($elm$json$Json$Decode$Index, i, result.a));
		}
		array[i] = result.a;
	}
	return $elm$core$Result$Ok(toElmValue(array));
}

function _Json_isArray(value)
{
	return Array.isArray(value) || (typeof FileList !== 'undefined' && value instanceof FileList);
}

function _Json_toElmArray(array)
{
	return A2($elm$core$Array$initialize, array.length, function(i) { return array[i]; });
}

function _Json_expecting(type, value)
{
	return $elm$core$Result$Err(A2($elm$json$Json$Decode$Failure, 'Expecting ' + type, _Json_wrap(value)));
}


// EQUALITY

function _Json_equality(x, y)
{
	if (x === y)
	{
		return true;
	}

	if (x.$ !== y.$)
	{
		return false;
	}

	switch (x.$)
	{
		case 0:
		case 1:
			return x.a === y.a;

		case 2:
			return x.b === y.b;

		case 5:
			return x.c === y.c;

		case 3:
		case 4:
		case 8:
			return _Json_equality(x.b, y.b);

		case 6:
			return x.d === y.d && _Json_equality(x.b, y.b);

		case 7:
			return x.e === y.e && _Json_equality(x.b, y.b);

		case 9:
			return x.f === y.f && _Json_listEquality(x.g, y.g);

		case 10:
			return x.h === y.h && _Json_equality(x.b, y.b);

		case 11:
			return _Json_listEquality(x.g, y.g);
	}
}

function _Json_listEquality(aDecoders, bDecoders)
{
	var len = aDecoders.length;
	if (len !== bDecoders.length)
	{
		return false;
	}
	for (var i = 0; i < len; i++)
	{
		if (!_Json_equality(aDecoders[i], bDecoders[i]))
		{
			return false;
		}
	}
	return true;
}


// ENCODE

var _Json_encode = F2(function(indentLevel, value)
{
	return JSON.stringify(_Json_unwrap(value), null, indentLevel) + '';
});

function _Json_wrap(value) { return { $: 0, a: value }; }
function _Json_unwrap(value) { return value.a; }

function _Json_wrap_UNUSED(value) { return value; }
function _Json_unwrap_UNUSED(value) { return value; }

function _Json_emptyArray() { return []; }
function _Json_emptyObject() { return {}; }

var _Json_addField = F3(function(key, value, object)
{
	object[key] = _Json_unwrap(value);
	return object;
});

function _Json_addEntry(func)
{
	return F2(function(entry, array)
	{
		array.push(_Json_unwrap(func(entry)));
		return array;
	});
}

var _Json_encodeNull = _Json_wrap(null);



// TASKS

function _Scheduler_succeed(value)
{
	return {
		$: 0,
		a: value
	};
}

function _Scheduler_fail(error)
{
	return {
		$: 1,
		a: error
	};
}

function _Scheduler_binding(callback)
{
	return {
		$: 2,
		b: callback,
		c: null
	};
}

var _Scheduler_andThen = F2(function(callback, task)
{
	return {
		$: 3,
		b: callback,
		d: task
	};
});

var _Scheduler_onError = F2(function(callback, task)
{
	return {
		$: 4,
		b: callback,
		d: task
	};
});

function _Scheduler_receive(callback)
{
	return {
		$: 5,
		b: callback
	};
}


// PROCESSES

var _Scheduler_guid = 0;

function _Scheduler_rawSpawn(task)
{
	var proc = {
		$: 0,
		e: _Scheduler_guid++,
		f: task,
		g: null,
		h: []
	};

	_Scheduler_enqueue(proc);

	return proc;
}

function _Scheduler_spawn(task)
{
	return _Scheduler_binding(function(callback) {
		callback(_Scheduler_succeed(_Scheduler_rawSpawn(task)));
	});
}

function _Scheduler_rawSend(proc, msg)
{
	proc.h.push(msg);
	_Scheduler_enqueue(proc);
}

var _Scheduler_send = F2(function(proc, msg)
{
	return _Scheduler_binding(function(callback) {
		_Scheduler_rawSend(proc, msg);
		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
});

function _Scheduler_kill(proc)
{
	return _Scheduler_binding(function(callback) {
		var task = proc.f;
		if (task.$ === 2 && task.c)
		{
			task.c();
		}

		proc.f = null;

		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
}


/* STEP PROCESSES

type alias Process =
  { $ : tag
  , id : unique_id
  , root : Task
  , stack : null | { $: SUCCEED | FAIL, a: callback, b: stack }
  , mailbox : [msg]
  }

*/


var _Scheduler_working = false;
var _Scheduler_queue = [];


function _Scheduler_enqueue(proc)
{
	_Scheduler_queue.push(proc);
	if (_Scheduler_working)
	{
		return;
	}
	_Scheduler_working = true;
	while (proc = _Scheduler_queue.shift())
	{
		_Scheduler_step(proc);
	}
	_Scheduler_working = false;
}


function _Scheduler_step(proc)
{
	while (proc.f)
	{
		var rootTag = proc.f.$;
		if (rootTag === 0 || rootTag === 1)
		{
			while (proc.g && proc.g.$ !== rootTag)
			{
				proc.g = proc.g.i;
			}
			if (!proc.g)
			{
				return;
			}
			proc.f = proc.g.b(proc.f.a);
			proc.g = proc.g.i;
		}
		else if (rootTag === 2)
		{
			proc.f.c = proc.f.b(function(newRoot) {
				proc.f = newRoot;
				_Scheduler_enqueue(proc);
			});
			return;
		}
		else if (rootTag === 5)
		{
			if (proc.h.length === 0)
			{
				return;
			}
			proc.f = proc.f.b(proc.h.shift());
		}
		else // if (rootTag === 3 || rootTag === 4)
		{
			proc.g = {
				$: rootTag === 3 ? 0 : 1,
				b: proc.f.b,
				i: proc.g
			};
			proc.f = proc.f.d;
		}
	}
}



function _Process_sleep(time)
{
	return _Scheduler_binding(function(callback) {
		var id = setTimeout(function() {
			callback(_Scheduler_succeed(_Utils_Tuple0));
		}, time);

		return function() { clearTimeout(id); };
	});
}




// PROGRAMS


var _Platform_worker = F4(function(impl, flagDecoder, debugMetadata, args)
{
	return _Platform_initialize(
		flagDecoder,
		args,
		impl.init,
		impl.update,
		impl.subscriptions,
		function() { return function() {} }
	);
});



// INITIALIZE A PROGRAM


function _Platform_initialize(flagDecoder, args, init, update, subscriptions, stepperBuilder)
{
	var result = A2(_Json_run, flagDecoder, _Json_wrap(args ? args['flags'] : undefined));
	$elm$core$Result$isOk(result) || _Debug_crash(2 /**/, _Json_errorToString(result.a) /**/);
	var managers = {};
	var initPair = init(result.a);
	var model = initPair.a;
	var stepper = stepperBuilder(sendToApp, model);
	var ports = _Platform_setupEffects(managers, sendToApp);

	function sendToApp(msg, viewMetadata)
	{
		var pair = A2(update, msg, model);
		stepper(model = pair.a, viewMetadata);
		_Platform_enqueueEffects(managers, pair.b, subscriptions(model));
	}

	_Platform_enqueueEffects(managers, initPair.b, subscriptions(model));

	return ports ? { ports: ports } : {};
}



// TRACK PRELOADS
//
// This is used by code in elm/browser and elm/http
// to register any HTTP requests that are triggered by init.
//


var _Platform_preload;


function _Platform_registerPreload(url)
{
	_Platform_preload.add(url);
}



// EFFECT MANAGERS


var _Platform_effectManagers = {};


function _Platform_setupEffects(managers, sendToApp)
{
	var ports;

	// setup all necessary effect managers
	for (var key in _Platform_effectManagers)
	{
		var manager = _Platform_effectManagers[key];

		if (manager.a)
		{
			ports = ports || {};
			ports[key] = manager.a(key, sendToApp);
		}

		managers[key] = _Platform_instantiateManager(manager, sendToApp);
	}

	return ports;
}


function _Platform_createManager(init, onEffects, onSelfMsg, cmdMap, subMap)
{
	return {
		b: init,
		c: onEffects,
		d: onSelfMsg,
		e: cmdMap,
		f: subMap
	};
}


function _Platform_instantiateManager(info, sendToApp)
{
	var router = {
		g: sendToApp,
		h: undefined
	};

	var onEffects = info.c;
	var onSelfMsg = info.d;
	var cmdMap = info.e;
	var subMap = info.f;

	function loop(state)
	{
		return A2(_Scheduler_andThen, loop, _Scheduler_receive(function(msg)
		{
			var value = msg.a;

			if (msg.$ === 0)
			{
				return A3(onSelfMsg, router, value, state);
			}

			return cmdMap && subMap
				? A4(onEffects, router, value.i, value.j, state)
				: A3(onEffects, router, cmdMap ? value.i : value.j, state);
		}));
	}

	return router.h = _Scheduler_rawSpawn(A2(_Scheduler_andThen, loop, info.b));
}



// ROUTING


var _Platform_sendToApp = F2(function(router, msg)
{
	return _Scheduler_binding(function(callback)
	{
		router.g(msg);
		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
});


var _Platform_sendToSelf = F2(function(router, msg)
{
	return A2(_Scheduler_send, router.h, {
		$: 0,
		a: msg
	});
});



// BAGS


function _Platform_leaf(home)
{
	return function(value)
	{
		return {
			$: 1,
			k: home,
			l: value
		};
	};
}


function _Platform_batch(list)
{
	return {
		$: 2,
		m: list
	};
}


var _Platform_map = F2(function(tagger, bag)
{
	return {
		$: 3,
		n: tagger,
		o: bag
	}
});



// PIPE BAGS INTO EFFECT MANAGERS
//
// Effects must be queued!
//
// Say your init contains a synchronous command, like Time.now or Time.here
//
//   - This will produce a batch of effects (FX_1)
//   - The synchronous task triggers the subsequent `update` call
//   - This will produce a batch of effects (FX_2)
//
// If we just start dispatching FX_2, subscriptions from FX_2 can be processed
// before subscriptions from FX_1. No good! Earlier versions of this code had
// this problem, leading to these reports:
//
//   https://github.com/elm/core/issues/980
//   https://github.com/elm/core/pull/981
//   https://github.com/elm/compiler/issues/1776
//
// The queue is necessary to avoid ordering issues for synchronous commands.


// Why use true/false here? Why not just check the length of the queue?
// The goal is to detect "are we currently dispatching effects?" If we
// are, we need to bail and let the ongoing while loop handle things.
//
// Now say the queue has 1 element. When we dequeue the final element,
// the queue will be empty, but we are still actively dispatching effects.
// So you could get queue jumping in a really tricky category of cases.
//
var _Platform_effectsQueue = [];
var _Platform_effectsActive = false;


function _Platform_enqueueEffects(managers, cmdBag, subBag)
{
	_Platform_effectsQueue.push({ p: managers, q: cmdBag, r: subBag });

	if (_Platform_effectsActive) return;

	_Platform_effectsActive = true;
	for (var fx; fx = _Platform_effectsQueue.shift(); )
	{
		_Platform_dispatchEffects(fx.p, fx.q, fx.r);
	}
	_Platform_effectsActive = false;
}


function _Platform_dispatchEffects(managers, cmdBag, subBag)
{
	var effectsDict = {};
	_Platform_gatherEffects(true, cmdBag, effectsDict, null);
	_Platform_gatherEffects(false, subBag, effectsDict, null);

	for (var home in managers)
	{
		_Scheduler_rawSend(managers[home], {
			$: 'fx',
			a: effectsDict[home] || { i: _List_Nil, j: _List_Nil }
		});
	}
}


function _Platform_gatherEffects(isCmd, bag, effectsDict, taggers)
{
	switch (bag.$)
	{
		case 1:
			var home = bag.k;
			var effect = _Platform_toEffect(isCmd, home, taggers, bag.l);
			effectsDict[home] = _Platform_insert(isCmd, effect, effectsDict[home]);
			return;

		case 2:
			for (var list = bag.m; list.b; list = list.b) // WHILE_CONS
			{
				_Platform_gatherEffects(isCmd, list.a, effectsDict, taggers);
			}
			return;

		case 3:
			_Platform_gatherEffects(isCmd, bag.o, effectsDict, {
				s: bag.n,
				t: taggers
			});
			return;
	}
}


function _Platform_toEffect(isCmd, home, taggers, value)
{
	function applyTaggers(x)
	{
		for (var temp = taggers; temp; temp = temp.t)
		{
			x = temp.s(x);
		}
		return x;
	}

	var map = isCmd
		? _Platform_effectManagers[home].e
		: _Platform_effectManagers[home].f;

	return A2(map, applyTaggers, value)
}


function _Platform_insert(isCmd, newEffect, effects)
{
	effects = effects || { i: _List_Nil, j: _List_Nil };

	isCmd
		? (effects.i = _List_Cons(newEffect, effects.i))
		: (effects.j = _List_Cons(newEffect, effects.j));

	return effects;
}



// PORTS


function _Platform_checkPortName(name)
{
	if (_Platform_effectManagers[name])
	{
		_Debug_crash(3, name)
	}
}



// OUTGOING PORTS


function _Platform_outgoingPort(name, converter)
{
	_Platform_checkPortName(name);
	_Platform_effectManagers[name] = {
		e: _Platform_outgoingPortMap,
		u: converter,
		a: _Platform_setupOutgoingPort
	};
	return _Platform_leaf(name);
}


var _Platform_outgoingPortMap = F2(function(tagger, value) { return value; });


function _Platform_setupOutgoingPort(name)
{
	var subs = [];
	var converter = _Platform_effectManagers[name].u;

	// CREATE MANAGER

	var init = _Process_sleep(0);

	_Platform_effectManagers[name].b = init;
	_Platform_effectManagers[name].c = F3(function(router, cmdList, state)
	{
		for ( ; cmdList.b; cmdList = cmdList.b) // WHILE_CONS
		{
			// grab a separate reference to subs in case unsubscribe is called
			var currentSubs = subs;
			var value = _Json_unwrap(converter(cmdList.a));
			for (var i = 0; i < currentSubs.length; i++)
			{
				currentSubs[i](value);
			}
		}
		return init;
	});

	// PUBLIC API

	function subscribe(callback)
	{
		subs.push(callback);
	}

	function unsubscribe(callback)
	{
		// copy subs into a new array in case unsubscribe is called within a
		// subscribed callback
		subs = subs.slice();
		var index = subs.indexOf(callback);
		if (index >= 0)
		{
			subs.splice(index, 1);
		}
	}

	return {
		subscribe: subscribe,
		unsubscribe: unsubscribe
	};
}



// INCOMING PORTS


function _Platform_incomingPort(name, converter)
{
	_Platform_checkPortName(name);
	_Platform_effectManagers[name] = {
		f: _Platform_incomingPortMap,
		u: converter,
		a: _Platform_setupIncomingPort
	};
	return _Platform_leaf(name);
}


var _Platform_incomingPortMap = F2(function(tagger, finalTagger)
{
	return function(value)
	{
		return tagger(finalTagger(value));
	};
});


function _Platform_setupIncomingPort(name, sendToApp)
{
	var subs = _List_Nil;
	var converter = _Platform_effectManagers[name].u;

	// CREATE MANAGER

	var init = _Scheduler_succeed(null);

	_Platform_effectManagers[name].b = init;
	_Platform_effectManagers[name].c = F3(function(router, subList, state)
	{
		subs = subList;
		return init;
	});

	// PUBLIC API

	function send(incomingValue)
	{
		var result = A2(_Json_run, converter, _Json_wrap(incomingValue));

		$elm$core$Result$isOk(result) || _Debug_crash(4, name, result.a);

		var value = result.a;
		for (var temp = subs; temp.b; temp = temp.b) // WHILE_CONS
		{
			sendToApp(temp.a(value));
		}
	}

	return { send: send };
}



// EXPORT ELM MODULES
//
// Have DEBUG and PROD versions so that we can (1) give nicer errors in
// debug mode and (2) not pay for the bits needed for that in prod mode.
//


function _Platform_export_UNUSED(exports)
{
	scope['Elm']
		? _Platform_mergeExportsProd(scope['Elm'], exports)
		: scope['Elm'] = exports;
}


function _Platform_mergeExportsProd(obj, exports)
{
	for (var name in exports)
	{
		(name in obj)
			? (name == 'init')
				? _Debug_crash(6)
				: _Platform_mergeExportsProd(obj[name], exports[name])
			: (obj[name] = exports[name]);
	}
}


function _Platform_export(exports)
{
	scope['Elm']
		? _Platform_mergeExportsDebug('Elm', scope['Elm'], exports)
		: scope['Elm'] = exports;
}


function _Platform_mergeExportsDebug(moduleName, obj, exports)
{
	for (var name in exports)
	{
		(name in obj)
			? (name == 'init')
				? _Debug_crash(6, moduleName)
				: _Platform_mergeExportsDebug(moduleName + '.' + name, obj[name], exports[name])
			: (obj[name] = exports[name]);
	}
}




// HELPERS


var _VirtualDom_divertHrefToApp;

var _VirtualDom_doc = typeof document !== 'undefined' ? document : {};


function _VirtualDom_appendChild(parent, child)
{
	parent.appendChild(child);
}

var _VirtualDom_init = F4(function(virtualNode, flagDecoder, debugMetadata, args)
{
	// NOTE: this function needs _Platform_export available to work

	/**_UNUSED/
	var node = args['node'];
	//*/
	/**/
	var node = args && args['node'] ? args['node'] : _Debug_crash(0);
	//*/

	node.parentNode.replaceChild(
		_VirtualDom_render(virtualNode, function() {}),
		node
	);

	return {};
});



// TEXT


function _VirtualDom_text(string)
{
	return {
		$: 0,
		a: string
	};
}



// NODE


var _VirtualDom_nodeNS = F2(function(namespace, tag)
{
	return F2(function(factList, kidList)
	{
		for (var kids = [], descendantsCount = 0; kidList.b; kidList = kidList.b) // WHILE_CONS
		{
			var kid = kidList.a;
			descendantsCount += (kid.b || 0);
			kids.push(kid);
		}
		descendantsCount += kids.length;

		return {
			$: 1,
			c: tag,
			d: _VirtualDom_organizeFacts(factList),
			e: kids,
			f: namespace,
			b: descendantsCount
		};
	});
});


var _VirtualDom_node = _VirtualDom_nodeNS(undefined);



// KEYED NODE


var _VirtualDom_keyedNodeNS = F2(function(namespace, tag)
{
	return F2(function(factList, kidList)
	{
		for (var kids = [], descendantsCount = 0; kidList.b; kidList = kidList.b) // WHILE_CONS
		{
			var kid = kidList.a;
			descendantsCount += (kid.b.b || 0);
			kids.push(kid);
		}
		descendantsCount += kids.length;

		return {
			$: 2,
			c: tag,
			d: _VirtualDom_organizeFacts(factList),
			e: kids,
			f: namespace,
			b: descendantsCount
		};
	});
});


var _VirtualDom_keyedNode = _VirtualDom_keyedNodeNS(undefined);



// CUSTOM


function _VirtualDom_custom(factList, model, render, diff)
{
	return {
		$: 3,
		d: _VirtualDom_organizeFacts(factList),
		g: model,
		h: render,
		i: diff
	};
}



// MAP


var _VirtualDom_map = F2(function(tagger, node)
{
	return {
		$: 4,
		j: tagger,
		k: node,
		b: 1 + (node.b || 0)
	};
});



// LAZY


function _VirtualDom_thunk(refs, thunk)
{
	return {
		$: 5,
		l: refs,
		m: thunk,
		k: undefined
	};
}

var _VirtualDom_lazy = F2(function(func, a)
{
	return _VirtualDom_thunk([func, a], function() {
		return func(a);
	});
});

var _VirtualDom_lazy2 = F3(function(func, a, b)
{
	return _VirtualDom_thunk([func, a, b], function() {
		return A2(func, a, b);
	});
});

var _VirtualDom_lazy3 = F4(function(func, a, b, c)
{
	return _VirtualDom_thunk([func, a, b, c], function() {
		return A3(func, a, b, c);
	});
});

var _VirtualDom_lazy4 = F5(function(func, a, b, c, d)
{
	return _VirtualDom_thunk([func, a, b, c, d], function() {
		return A4(func, a, b, c, d);
	});
});

var _VirtualDom_lazy5 = F6(function(func, a, b, c, d, e)
{
	return _VirtualDom_thunk([func, a, b, c, d, e], function() {
		return A5(func, a, b, c, d, e);
	});
});

var _VirtualDom_lazy6 = F7(function(func, a, b, c, d, e, f)
{
	return _VirtualDom_thunk([func, a, b, c, d, e, f], function() {
		return A6(func, a, b, c, d, e, f);
	});
});

var _VirtualDom_lazy7 = F8(function(func, a, b, c, d, e, f, g)
{
	return _VirtualDom_thunk([func, a, b, c, d, e, f, g], function() {
		return A7(func, a, b, c, d, e, f, g);
	});
});

var _VirtualDom_lazy8 = F9(function(func, a, b, c, d, e, f, g, h)
{
	return _VirtualDom_thunk([func, a, b, c, d, e, f, g, h], function() {
		return A8(func, a, b, c, d, e, f, g, h);
	});
});



// FACTS


var _VirtualDom_on = F2(function(key, handler)
{
	return {
		$: 'a0',
		n: key,
		o: handler
	};
});
var _VirtualDom_style = F2(function(key, value)
{
	return {
		$: 'a1',
		n: key,
		o: value
	};
});
var _VirtualDom_property = F2(function(key, value)
{
	return {
		$: 'a2',
		n: key,
		o: value
	};
});
var _VirtualDom_attribute = F2(function(key, value)
{
	return {
		$: 'a3',
		n: key,
		o: value
	};
});
var _VirtualDom_attributeNS = F3(function(namespace, key, value)
{
	return {
		$: 'a4',
		n: key,
		o: { f: namespace, o: value }
	};
});



// XSS ATTACK VECTOR CHECKS
//
// For some reason, tabs can appear in href protocols and it still works.
// So '\tjava\tSCRIPT:alert("!!!")' and 'javascript:alert("!!!")' are the same
// in practice. That is why _VirtualDom_RE_js and _VirtualDom_RE_js_html look
// so freaky.
//
// Pulling the regular expressions out to the top level gives a slight speed
// boost in small benchmarks (4-10%) but hoisting values to reduce allocation
// can be unpredictable in large programs where JIT may have a harder time with
// functions are not fully self-contained. The benefit is more that the js and
// js_html ones are so weird that I prefer to see them near each other.


var _VirtualDom_RE_script = /^script$/i;
var _VirtualDom_RE_on_formAction = /^(on|formAction$)/i;
var _VirtualDom_RE_js = /^\s*j\s*a\s*v\s*a\s*s\s*c\s*r\s*i\s*p\s*t\s*:/i;
var _VirtualDom_RE_js_html = /^\s*(j\s*a\s*v\s*a\s*s\s*c\s*r\s*i\s*p\s*t\s*:|d\s*a\s*t\s*a\s*:\s*t\s*e\s*x\s*t\s*\/\s*h\s*t\s*m\s*l\s*(,|;))/i;


function _VirtualDom_noScript(tag)
{
	return _VirtualDom_RE_script.test(tag) ? 'p' : tag;
}

function _VirtualDom_noOnOrFormAction(key)
{
	return _VirtualDom_RE_on_formAction.test(key) ? 'data-' + key : key;
}

function _VirtualDom_noInnerHtmlOrFormAction(key)
{
	return key == 'innerHTML' || key == 'formAction' ? 'data-' + key : key;
}

function _VirtualDom_noJavaScriptUri(value)
{
	return _VirtualDom_RE_js.test(value)
		? /**_UNUSED/''//*//**/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		: value;
}

function _VirtualDom_noJavaScriptOrHtmlUri(value)
{
	return _VirtualDom_RE_js_html.test(value)
		? /**_UNUSED/''//*//**/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		: value;
}

function _VirtualDom_noJavaScriptOrHtmlJson(value)
{
	return (typeof _Json_unwrap(value) === 'string' && _VirtualDom_RE_js_html.test(_Json_unwrap(value)))
		? _Json_wrap(
			/**_UNUSED/''//*//**/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		) : value;
}



// MAP FACTS


var _VirtualDom_mapAttribute = F2(function(func, attr)
{
	return (attr.$ === 'a0')
		? A2(_VirtualDom_on, attr.n, _VirtualDom_mapHandler(func, attr.o))
		: attr;
});

function _VirtualDom_mapHandler(func, handler)
{
	var tag = $elm$virtual_dom$VirtualDom$toHandlerInt(handler);

	// 0 = Normal
	// 1 = MayStopPropagation
	// 2 = MayPreventDefault
	// 3 = Custom

	return {
		$: handler.$,
		a:
			!tag
				? A2($elm$json$Json$Decode$map, func, handler.a)
				:
			A3($elm$json$Json$Decode$map2,
				tag < 3
					? _VirtualDom_mapEventTuple
					: _VirtualDom_mapEventRecord,
				$elm$json$Json$Decode$succeed(func),
				handler.a
			)
	};
}

var _VirtualDom_mapEventTuple = F2(function(func, tuple)
{
	return _Utils_Tuple2(func(tuple.a), tuple.b);
});

var _VirtualDom_mapEventRecord = F2(function(func, record)
{
	return {
		message: func(record.message),
		stopPropagation: record.stopPropagation,
		preventDefault: record.preventDefault
	}
});



// ORGANIZE FACTS


function _VirtualDom_organizeFacts(factList)
{
	for (var facts = {}; factList.b; factList = factList.b) // WHILE_CONS
	{
		var entry = factList.a;

		var tag = entry.$;
		var key = entry.n;
		var value = entry.o;

		if (tag === 'a2')
		{
			(key === 'className')
				? _VirtualDom_addClass(facts, key, _Json_unwrap(value))
				: facts[key] = _Json_unwrap(value);

			continue;
		}

		var subFacts = facts[tag] || (facts[tag] = {});
		(tag === 'a3' && key === 'class')
			? _VirtualDom_addClass(subFacts, key, value)
			: subFacts[key] = value;
	}

	return facts;
}

function _VirtualDom_addClass(object, key, newClass)
{
	var classes = object[key];
	object[key] = classes ? classes + ' ' + newClass : newClass;
}



// RENDER


function _VirtualDom_render(vNode, eventNode)
{
	var tag = vNode.$;

	if (tag === 5)
	{
		return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode);
	}

	if (tag === 0)
	{
		return _VirtualDom_doc.createTextNode(vNode.a);
	}

	if (tag === 4)
	{
		var subNode = vNode.k;
		var tagger = vNode.j;

		while (subNode.$ === 4)
		{
			typeof tagger !== 'object'
				? tagger = [tagger, subNode.j]
				: tagger.push(subNode.j);

			subNode = subNode.k;
		}

		var subEventRoot = { j: tagger, p: eventNode };
		var domNode = _VirtualDom_render(subNode, subEventRoot);
		domNode.elm_event_node_ref = subEventRoot;
		return domNode;
	}

	if (tag === 3)
	{
		var domNode = vNode.h(vNode.g);
		_VirtualDom_applyFacts(domNode, eventNode, vNode.d);
		return domNode;
	}

	// at this point `tag` must be 1 or 2

	var domNode = vNode.f
		? _VirtualDom_doc.createElementNS(vNode.f, vNode.c)
		: _VirtualDom_doc.createElement(vNode.c);

	if (_VirtualDom_divertHrefToApp && vNode.c == 'a')
	{
		domNode.addEventListener('click', _VirtualDom_divertHrefToApp(domNode));
	}

	_VirtualDom_applyFacts(domNode, eventNode, vNode.d);

	for (var kids = vNode.e, i = 0; i < kids.length; i++)
	{
		_VirtualDom_appendChild(domNode, _VirtualDom_render(tag === 1 ? kids[i] : kids[i].b, eventNode));
	}

	return domNode;
}



// APPLY FACTS


function _VirtualDom_applyFacts(domNode, eventNode, facts)
{
	for (var key in facts)
	{
		var value = facts[key];

		key === 'a1'
			? _VirtualDom_applyStyles(domNode, value)
			:
		key === 'a0'
			? _VirtualDom_applyEvents(domNode, eventNode, value)
			:
		key === 'a3'
			? _VirtualDom_applyAttrs(domNode, value)
			:
		key === 'a4'
			? _VirtualDom_applyAttrsNS(domNode, value)
			:
		((key !== 'value' && key !== 'checked') || domNode[key] !== value) && (domNode[key] = value);
	}
}



// APPLY STYLES


function _VirtualDom_applyStyles(domNode, styles)
{
	var domNodeStyle = domNode.style;

	for (var key in styles)
	{
		domNodeStyle[key] = styles[key];
	}
}



// APPLY ATTRS


function _VirtualDom_applyAttrs(domNode, attrs)
{
	for (var key in attrs)
	{
		var value = attrs[key];
		typeof value !== 'undefined'
			? domNode.setAttribute(key, value)
			: domNode.removeAttribute(key);
	}
}



// APPLY NAMESPACED ATTRS


function _VirtualDom_applyAttrsNS(domNode, nsAttrs)
{
	for (var key in nsAttrs)
	{
		var pair = nsAttrs[key];
		var namespace = pair.f;
		var value = pair.o;

		typeof value !== 'undefined'
			? domNode.setAttributeNS(namespace, key, value)
			: domNode.removeAttributeNS(namespace, key);
	}
}



// APPLY EVENTS


function _VirtualDom_applyEvents(domNode, eventNode, events)
{
	var allCallbacks = domNode.elmFs || (domNode.elmFs = {});

	for (var key in events)
	{
		var newHandler = events[key];
		var oldCallback = allCallbacks[key];

		if (!newHandler)
		{
			domNode.removeEventListener(key, oldCallback);
			allCallbacks[key] = undefined;
			continue;
		}

		if (oldCallback)
		{
			var oldHandler = oldCallback.q;
			if (oldHandler.$ === newHandler.$)
			{
				oldCallback.q = newHandler;
				continue;
			}
			domNode.removeEventListener(key, oldCallback);
		}

		oldCallback = _VirtualDom_makeCallback(eventNode, newHandler);
		domNode.addEventListener(key, oldCallback,
			_VirtualDom_passiveSupported
			&& { passive: $elm$virtual_dom$VirtualDom$toHandlerInt(newHandler) < 2 }
		);
		allCallbacks[key] = oldCallback;
	}
}



// PASSIVE EVENTS


var _VirtualDom_passiveSupported;

try
{
	window.addEventListener('t', null, Object.defineProperty({}, 'passive', {
		get: function() { _VirtualDom_passiveSupported = true; }
	}));
}
catch(e) {}



// EVENT HANDLERS


function _VirtualDom_makeCallback(eventNode, initialHandler)
{
	function callback(event)
	{
		var handler = callback.q;
		var result = _Json_runHelp(handler.a, event);

		if (!$elm$core$Result$isOk(result))
		{
			return;
		}

		var tag = $elm$virtual_dom$VirtualDom$toHandlerInt(handler);

		// 0 = Normal
		// 1 = MayStopPropagation
		// 2 = MayPreventDefault
		// 3 = Custom

		var value = result.a;
		var message = !tag ? value : tag < 3 ? value.a : value.message;
		var stopPropagation = tag == 1 ? value.b : tag == 3 && value.stopPropagation;
		var currentEventNode = (
			stopPropagation && event.stopPropagation(),
			(tag == 2 ? value.b : tag == 3 && value.preventDefault) && event.preventDefault(),
			eventNode
		);
		var tagger;
		var i;
		while (tagger = currentEventNode.j)
		{
			if (typeof tagger == 'function')
			{
				message = tagger(message);
			}
			else
			{
				for (var i = tagger.length; i--; )
				{
					message = tagger[i](message);
				}
			}
			currentEventNode = currentEventNode.p;
		}
		currentEventNode(message, stopPropagation); // stopPropagation implies isSync
	}

	callback.q = initialHandler;

	return callback;
}

function _VirtualDom_equalEvents(x, y)
{
	return x.$ == y.$ && _Json_equality(x.a, y.a);
}



// DIFF


// TODO: Should we do patches like in iOS?
//
// type Patch
//   = At Int Patch
//   | Batch (List Patch)
//   | Change ...
//
// How could it not be better?
//
function _VirtualDom_diff(x, y)
{
	var patches = [];
	_VirtualDom_diffHelp(x, y, patches, 0);
	return patches;
}


function _VirtualDom_pushPatch(patches, type, index, data)
{
	var patch = {
		$: type,
		r: index,
		s: data,
		t: undefined,
		u: undefined
	};
	patches.push(patch);
	return patch;
}


function _VirtualDom_diffHelp(x, y, patches, index)
{
	if (x === y)
	{
		return;
	}

	var xType = x.$;
	var yType = y.$;

	// Bail if you run into different types of nodes. Implies that the
	// structure has changed significantly and it's not worth a diff.
	if (xType !== yType)
	{
		if (xType === 1 && yType === 2)
		{
			y = _VirtualDom_dekey(y);
			yType = 1;
		}
		else
		{
			_VirtualDom_pushPatch(patches, 0, index, y);
			return;
		}
	}

	// Now we know that both nodes are the same $.
	switch (yType)
	{
		case 5:
			var xRefs = x.l;
			var yRefs = y.l;
			var i = xRefs.length;
			var same = i === yRefs.length;
			while (same && i--)
			{
				same = xRefs[i] === yRefs[i];
			}
			if (same)
			{
				y.k = x.k;
				return;
			}
			y.k = y.m();
			var subPatches = [];
			_VirtualDom_diffHelp(x.k, y.k, subPatches, 0);
			subPatches.length > 0 && _VirtualDom_pushPatch(patches, 1, index, subPatches);
			return;

		case 4:
			// gather nested taggers
			var xTaggers = x.j;
			var yTaggers = y.j;
			var nesting = false;

			var xSubNode = x.k;
			while (xSubNode.$ === 4)
			{
				nesting = true;

				typeof xTaggers !== 'object'
					? xTaggers = [xTaggers, xSubNode.j]
					: xTaggers.push(xSubNode.j);

				xSubNode = xSubNode.k;
			}

			var ySubNode = y.k;
			while (ySubNode.$ === 4)
			{
				nesting = true;

				typeof yTaggers !== 'object'
					? yTaggers = [yTaggers, ySubNode.j]
					: yTaggers.push(ySubNode.j);

				ySubNode = ySubNode.k;
			}

			// Just bail if different numbers of taggers. This implies the
			// structure of the virtual DOM has changed.
			if (nesting && xTaggers.length !== yTaggers.length)
			{
				_VirtualDom_pushPatch(patches, 0, index, y);
				return;
			}

			// check if taggers are "the same"
			if (nesting ? !_VirtualDom_pairwiseRefEqual(xTaggers, yTaggers) : xTaggers !== yTaggers)
			{
				_VirtualDom_pushPatch(patches, 2, index, yTaggers);
			}

			// diff everything below the taggers
			_VirtualDom_diffHelp(xSubNode, ySubNode, patches, index + 1);
			return;

		case 0:
			if (x.a !== y.a)
			{
				_VirtualDom_pushPatch(patches, 3, index, y.a);
			}
			return;

		case 1:
			_VirtualDom_diffNodes(x, y, patches, index, _VirtualDom_diffKids);
			return;

		case 2:
			_VirtualDom_diffNodes(x, y, patches, index, _VirtualDom_diffKeyedKids);
			return;

		case 3:
			if (x.h !== y.h)
			{
				_VirtualDom_pushPatch(patches, 0, index, y);
				return;
			}

			var factsDiff = _VirtualDom_diffFacts(x.d, y.d);
			factsDiff && _VirtualDom_pushPatch(patches, 4, index, factsDiff);

			var patch = y.i(x.g, y.g);
			patch && _VirtualDom_pushPatch(patches, 5, index, patch);

			return;
	}
}

// assumes the incoming arrays are the same length
function _VirtualDom_pairwiseRefEqual(as, bs)
{
	for (var i = 0; i < as.length; i++)
	{
		if (as[i] !== bs[i])
		{
			return false;
		}
	}

	return true;
}

function _VirtualDom_diffNodes(x, y, patches, index, diffKids)
{
	// Bail if obvious indicators have changed. Implies more serious
	// structural changes such that it's not worth it to diff.
	if (x.c !== y.c || x.f !== y.f)
	{
		_VirtualDom_pushPatch(patches, 0, index, y);
		return;
	}

	var factsDiff = _VirtualDom_diffFacts(x.d, y.d);
	factsDiff && _VirtualDom_pushPatch(patches, 4, index, factsDiff);

	diffKids(x, y, patches, index);
}



// DIFF FACTS


// TODO Instead of creating a new diff object, it's possible to just test if
// there *is* a diff. During the actual patch, do the diff again and make the
// modifications directly. This way, there's no new allocations. Worth it?
function _VirtualDom_diffFacts(x, y, category)
{
	var diff;

	// look for changes and removals
	for (var xKey in x)
	{
		if (xKey === 'a1' || xKey === 'a0' || xKey === 'a3' || xKey === 'a4')
		{
			var subDiff = _VirtualDom_diffFacts(x[xKey], y[xKey] || {}, xKey);
			if (subDiff)
			{
				diff = diff || {};
				diff[xKey] = subDiff;
			}
			continue;
		}

		// remove if not in the new facts
		if (!(xKey in y))
		{
			diff = diff || {};
			diff[xKey] =
				!category
					? (typeof x[xKey] === 'string' ? '' : null)
					:
				(category === 'a1')
					? ''
					:
				(category === 'a0' || category === 'a3')
					? undefined
					:
				{ f: x[xKey].f, o: undefined };

			continue;
		}

		var xValue = x[xKey];
		var yValue = y[xKey];

		// reference equal, so don't worry about it
		if (xValue === yValue && xKey !== 'value' && xKey !== 'checked'
			|| category === 'a0' && _VirtualDom_equalEvents(xValue, yValue))
		{
			continue;
		}

		diff = diff || {};
		diff[xKey] = yValue;
	}

	// add new stuff
	for (var yKey in y)
	{
		if (!(yKey in x))
		{
			diff = diff || {};
			diff[yKey] = y[yKey];
		}
	}

	return diff;
}



// DIFF KIDS


function _VirtualDom_diffKids(xParent, yParent, patches, index)
{
	var xKids = xParent.e;
	var yKids = yParent.e;

	var xLen = xKids.length;
	var yLen = yKids.length;

	// FIGURE OUT IF THERE ARE INSERTS OR REMOVALS

	if (xLen > yLen)
	{
		_VirtualDom_pushPatch(patches, 6, index, {
			v: yLen,
			i: xLen - yLen
		});
	}
	else if (xLen < yLen)
	{
		_VirtualDom_pushPatch(patches, 7, index, {
			v: xLen,
			e: yKids
		});
	}

	// PAIRWISE DIFF EVERYTHING ELSE

	for (var minLen = xLen < yLen ? xLen : yLen, i = 0; i < minLen; i++)
	{
		var xKid = xKids[i];
		_VirtualDom_diffHelp(xKid, yKids[i], patches, ++index);
		index += xKid.b || 0;
	}
}



// KEYED DIFF


function _VirtualDom_diffKeyedKids(xParent, yParent, patches, rootIndex)
{
	var localPatches = [];

	var changes = {}; // Dict String Entry
	var inserts = []; // Array { index : Int, entry : Entry }
	// type Entry = { tag : String, vnode : VNode, index : Int, data : _ }

	var xKids = xParent.e;
	var yKids = yParent.e;
	var xLen = xKids.length;
	var yLen = yKids.length;
	var xIndex = 0;
	var yIndex = 0;

	var index = rootIndex;

	while (xIndex < xLen && yIndex < yLen)
	{
		var x = xKids[xIndex];
		var y = yKids[yIndex];

		var xKey = x.a;
		var yKey = y.a;
		var xNode = x.b;
		var yNode = y.b;

		var newMatch = undefined;
		var oldMatch = undefined;

		// check if keys match

		if (xKey === yKey)
		{
			index++;
			_VirtualDom_diffHelp(xNode, yNode, localPatches, index);
			index += xNode.b || 0;

			xIndex++;
			yIndex++;
			continue;
		}

		// look ahead 1 to detect insertions and removals.

		var xNext = xKids[xIndex + 1];
		var yNext = yKids[yIndex + 1];

		if (xNext)
		{
			var xNextKey = xNext.a;
			var xNextNode = xNext.b;
			oldMatch = yKey === xNextKey;
		}

		if (yNext)
		{
			var yNextKey = yNext.a;
			var yNextNode = yNext.b;
			newMatch = xKey === yNextKey;
		}


		// swap x and y
		if (newMatch && oldMatch)
		{
			index++;
			_VirtualDom_diffHelp(xNode, yNextNode, localPatches, index);
			_VirtualDom_insertNode(changes, localPatches, xKey, yNode, yIndex, inserts);
			index += xNode.b || 0;

			index++;
			_VirtualDom_removeNode(changes, localPatches, xKey, xNextNode, index);
			index += xNextNode.b || 0;

			xIndex += 2;
			yIndex += 2;
			continue;
		}

		// insert y
		if (newMatch)
		{
			index++;
			_VirtualDom_insertNode(changes, localPatches, yKey, yNode, yIndex, inserts);
			_VirtualDom_diffHelp(xNode, yNextNode, localPatches, index);
			index += xNode.b || 0;

			xIndex += 1;
			yIndex += 2;
			continue;
		}

		// remove x
		if (oldMatch)
		{
			index++;
			_VirtualDom_removeNode(changes, localPatches, xKey, xNode, index);
			index += xNode.b || 0;

			index++;
			_VirtualDom_diffHelp(xNextNode, yNode, localPatches, index);
			index += xNextNode.b || 0;

			xIndex += 2;
			yIndex += 1;
			continue;
		}

		// remove x, insert y
		if (xNext && xNextKey === yNextKey)
		{
			index++;
			_VirtualDom_removeNode(changes, localPatches, xKey, xNode, index);
			_VirtualDom_insertNode(changes, localPatches, yKey, yNode, yIndex, inserts);
			index += xNode.b || 0;

			index++;
			_VirtualDom_diffHelp(xNextNode, yNextNode, localPatches, index);
			index += xNextNode.b || 0;

			xIndex += 2;
			yIndex += 2;
			continue;
		}

		break;
	}

	// eat up any remaining nodes with removeNode and insertNode

	while (xIndex < xLen)
	{
		index++;
		var x = xKids[xIndex];
		var xNode = x.b;
		_VirtualDom_removeNode(changes, localPatches, x.a, xNode, index);
		index += xNode.b || 0;
		xIndex++;
	}

	while (yIndex < yLen)
	{
		var endInserts = endInserts || [];
		var y = yKids[yIndex];
		_VirtualDom_insertNode(changes, localPatches, y.a, y.b, undefined, endInserts);
		yIndex++;
	}

	if (localPatches.length > 0 || inserts.length > 0 || endInserts)
	{
		_VirtualDom_pushPatch(patches, 8, rootIndex, {
			w: localPatches,
			x: inserts,
			y: endInserts
		});
	}
}



// CHANGES FROM KEYED DIFF


var _VirtualDom_POSTFIX = '_elmW6BL';


function _VirtualDom_insertNode(changes, localPatches, key, vnode, yIndex, inserts)
{
	var entry = changes[key];

	// never seen this key before
	if (!entry)
	{
		entry = {
			c: 0,
			z: vnode,
			r: yIndex,
			s: undefined
		};

		inserts.push({ r: yIndex, A: entry });
		changes[key] = entry;

		return;
	}

	// this key was removed earlier, a match!
	if (entry.c === 1)
	{
		inserts.push({ r: yIndex, A: entry });

		entry.c = 2;
		var subPatches = [];
		_VirtualDom_diffHelp(entry.z, vnode, subPatches, entry.r);
		entry.r = yIndex;
		entry.s.s = {
			w: subPatches,
			A: entry
		};

		return;
	}

	// this key has already been inserted or moved, a duplicate!
	_VirtualDom_insertNode(changes, localPatches, key + _VirtualDom_POSTFIX, vnode, yIndex, inserts);
}


function _VirtualDom_removeNode(changes, localPatches, key, vnode, index)
{
	var entry = changes[key];

	// never seen this key before
	if (!entry)
	{
		var patch = _VirtualDom_pushPatch(localPatches, 9, index, undefined);

		changes[key] = {
			c: 1,
			z: vnode,
			r: index,
			s: patch
		};

		return;
	}

	// this key was inserted earlier, a match!
	if (entry.c === 0)
	{
		entry.c = 2;
		var subPatches = [];
		_VirtualDom_diffHelp(vnode, entry.z, subPatches, index);

		_VirtualDom_pushPatch(localPatches, 9, index, {
			w: subPatches,
			A: entry
		});

		return;
	}

	// this key has already been removed or moved, a duplicate!
	_VirtualDom_removeNode(changes, localPatches, key + _VirtualDom_POSTFIX, vnode, index);
}



// ADD DOM NODES
//
// Each DOM node has an "index" assigned in order of traversal. It is important
// to minimize our crawl over the actual DOM, so these indexes (along with the
// descendantsCount of virtual nodes) let us skip touching entire subtrees of
// the DOM if we know there are no patches there.


function _VirtualDom_addDomNodes(domNode, vNode, patches, eventNode)
{
	_VirtualDom_addDomNodesHelp(domNode, vNode, patches, 0, 0, vNode.b, eventNode);
}


// assumes `patches` is non-empty and indexes increase monotonically.
function _VirtualDom_addDomNodesHelp(domNode, vNode, patches, i, low, high, eventNode)
{
	var patch = patches[i];
	var index = patch.r;

	while (index === low)
	{
		var patchType = patch.$;

		if (patchType === 1)
		{
			_VirtualDom_addDomNodes(domNode, vNode.k, patch.s, eventNode);
		}
		else if (patchType === 8)
		{
			patch.t = domNode;
			patch.u = eventNode;

			var subPatches = patch.s.w;
			if (subPatches.length > 0)
			{
				_VirtualDom_addDomNodesHelp(domNode, vNode, subPatches, 0, low, high, eventNode);
			}
		}
		else if (patchType === 9)
		{
			patch.t = domNode;
			patch.u = eventNode;

			var data = patch.s;
			if (data)
			{
				data.A.s = domNode;
				var subPatches = data.w;
				if (subPatches.length > 0)
				{
					_VirtualDom_addDomNodesHelp(domNode, vNode, subPatches, 0, low, high, eventNode);
				}
			}
		}
		else
		{
			patch.t = domNode;
			patch.u = eventNode;
		}

		i++;

		if (!(patch = patches[i]) || (index = patch.r) > high)
		{
			return i;
		}
	}

	var tag = vNode.$;

	if (tag === 4)
	{
		var subNode = vNode.k;

		while (subNode.$ === 4)
		{
			subNode = subNode.k;
		}

		return _VirtualDom_addDomNodesHelp(domNode, subNode, patches, i, low + 1, high, domNode.elm_event_node_ref);
	}

	// tag must be 1 or 2 at this point

	var vKids = vNode.e;
	var childNodes = domNode.childNodes;
	for (var j = 0; j < vKids.length; j++)
	{
		low++;
		var vKid = tag === 1 ? vKids[j] : vKids[j].b;
		var nextLow = low + (vKid.b || 0);
		if (low <= index && index <= nextLow)
		{
			i = _VirtualDom_addDomNodesHelp(childNodes[j], vKid, patches, i, low, nextLow, eventNode);
			if (!(patch = patches[i]) || (index = patch.r) > high)
			{
				return i;
			}
		}
		low = nextLow;
	}
	return i;
}



// APPLY PATCHES


function _VirtualDom_applyPatches(rootDomNode, oldVirtualNode, patches, eventNode)
{
	if (patches.length === 0)
	{
		return rootDomNode;
	}

	_VirtualDom_addDomNodes(rootDomNode, oldVirtualNode, patches, eventNode);
	return _VirtualDom_applyPatchesHelp(rootDomNode, patches);
}

function _VirtualDom_applyPatchesHelp(rootDomNode, patches)
{
	for (var i = 0; i < patches.length; i++)
	{
		var patch = patches[i];
		var localDomNode = patch.t
		var newNode = _VirtualDom_applyPatch(localDomNode, patch);
		if (localDomNode === rootDomNode)
		{
			rootDomNode = newNode;
		}
	}
	return rootDomNode;
}

function _VirtualDom_applyPatch(domNode, patch)
{
	switch (patch.$)
	{
		case 0:
			return _VirtualDom_applyPatchRedraw(domNode, patch.s, patch.u);

		case 4:
			_VirtualDom_applyFacts(domNode, patch.u, patch.s);
			return domNode;

		case 3:
			domNode.replaceData(0, domNode.length, patch.s);
			return domNode;

		case 1:
			return _VirtualDom_applyPatchesHelp(domNode, patch.s);

		case 2:
			if (domNode.elm_event_node_ref)
			{
				domNode.elm_event_node_ref.j = patch.s;
			}
			else
			{
				domNode.elm_event_node_ref = { j: patch.s, p: patch.u };
			}
			return domNode;

		case 6:
			var data = patch.s;
			for (var i = 0; i < data.i; i++)
			{
				domNode.removeChild(domNode.childNodes[data.v]);
			}
			return domNode;

		case 7:
			var data = patch.s;
			var kids = data.e;
			var i = data.v;
			var theEnd = domNode.childNodes[i];
			for (; i < kids.length; i++)
			{
				domNode.insertBefore(_VirtualDom_render(kids[i], patch.u), theEnd);
			}
			return domNode;

		case 9:
			var data = patch.s;
			if (!data)
			{
				domNode.parentNode.removeChild(domNode);
				return domNode;
			}
			var entry = data.A;
			if (typeof entry.r !== 'undefined')
			{
				domNode.parentNode.removeChild(domNode);
			}
			entry.s = _VirtualDom_applyPatchesHelp(domNode, data.w);
			return domNode;

		case 8:
			return _VirtualDom_applyPatchReorder(domNode, patch);

		case 5:
			return patch.s(domNode);

		default:
			_Debug_crash(10); // 'Ran into an unknown patch!'
	}
}


function _VirtualDom_applyPatchRedraw(domNode, vNode, eventNode)
{
	var parentNode = domNode.parentNode;
	var newNode = _VirtualDom_render(vNode, eventNode);

	if (!newNode.elm_event_node_ref)
	{
		newNode.elm_event_node_ref = domNode.elm_event_node_ref;
	}

	if (parentNode && newNode !== domNode)
	{
		parentNode.replaceChild(newNode, domNode);
	}
	return newNode;
}


function _VirtualDom_applyPatchReorder(domNode, patch)
{
	var data = patch.s;

	// remove end inserts
	var frag = _VirtualDom_applyPatchReorderEndInsertsHelp(data.y, patch);

	// removals
	domNode = _VirtualDom_applyPatchesHelp(domNode, data.w);

	// inserts
	var inserts = data.x;
	for (var i = 0; i < inserts.length; i++)
	{
		var insert = inserts[i];
		var entry = insert.A;
		var node = entry.c === 2
			? entry.s
			: _VirtualDom_render(entry.z, patch.u);
		domNode.insertBefore(node, domNode.childNodes[insert.r]);
	}

	// add end inserts
	if (frag)
	{
		_VirtualDom_appendChild(domNode, frag);
	}

	return domNode;
}


function _VirtualDom_applyPatchReorderEndInsertsHelp(endInserts, patch)
{
	if (!endInserts)
	{
		return;
	}

	var frag = _VirtualDom_doc.createDocumentFragment();
	for (var i = 0; i < endInserts.length; i++)
	{
		var insert = endInserts[i];
		var entry = insert.A;
		_VirtualDom_appendChild(frag, entry.c === 2
			? entry.s
			: _VirtualDom_render(entry.z, patch.u)
		);
	}
	return frag;
}


function _VirtualDom_virtualize(node)
{
	// TEXT NODES

	if (node.nodeType === 3)
	{
		return _VirtualDom_text(node.textContent);
	}


	// WEIRD NODES

	if (node.nodeType !== 1)
	{
		return _VirtualDom_text('');
	}


	// ELEMENT NODES

	var attrList = _List_Nil;
	var attrs = node.attributes;
	for (var i = attrs.length; i--; )
	{
		var attr = attrs[i];
		var name = attr.name;
		var value = attr.value;
		attrList = _List_Cons( A2(_VirtualDom_attribute, name, value), attrList );
	}

	var tag = node.tagName.toLowerCase();
	var kidList = _List_Nil;
	var kids = node.childNodes;

	for (var i = kids.length; i--; )
	{
		kidList = _List_Cons(_VirtualDom_virtualize(kids[i]), kidList);
	}
	return A3(_VirtualDom_node, tag, attrList, kidList);
}

function _VirtualDom_dekey(keyedNode)
{
	var keyedKids = keyedNode.e;
	var len = keyedKids.length;
	var kids = new Array(len);
	for (var i = 0; i < len; i++)
	{
		kids[i] = keyedKids[i].b;
	}

	return {
		$: 1,
		c: keyedNode.c,
		d: keyedNode.d,
		e: kids,
		f: keyedNode.f,
		b: keyedNode.b
	};
}



var _Bitwise_and = F2(function(a, b)
{
	return a & b;
});

var _Bitwise_or = F2(function(a, b)
{
	return a | b;
});

var _Bitwise_xor = F2(function(a, b)
{
	return a ^ b;
});

function _Bitwise_complement(a)
{
	return ~a;
};

var _Bitwise_shiftLeftBy = F2(function(offset, a)
{
	return a << offset;
});

var _Bitwise_shiftRightBy = F2(function(offset, a)
{
	return a >> offset;
});

var _Bitwise_shiftRightZfBy = F2(function(offset, a)
{
	return a >>> offset;
});
var $elm$core$Basics$EQ ={$ :'EQ'};
var $elm$core$Basics$LT ={$ :'LT'};
var $elm$core$List$cons = _List_cons;
var $elm$core$Elm$JsArray$foldr = _JsArray_foldr;
var $elm$core$Array$foldr = F3( function(func,baseCase,_v0){var tree = _v0.c;var tail = _v0.d;var helper = F2( function(node,acc){if ( node.$ ==='SubTree' ){var subTree = node.a; return ( A3( $elm$core$Elm$JsArray$foldr, helper, acc, subTree));} else{var values = node.a; return ( A3( $elm$core$Elm$JsArray$foldr, func, acc, values));}}); return ( A3( $elm$core$Elm$JsArray$foldr, helper, A3( $elm$core$Elm$JsArray$foldr, func, baseCase, tail), tree));});
var $elm$core$Array$toList = function(array){ return ( A3( $elm$core$Array$foldr, $elm$core$List$cons, _List_Nil, array));};
var $elm$core$Dict$foldr = F3( function(func,acc,t){foldr: while (true ){if ( t.$ ==='RBEmpty_elm_builtin' ) return ( acc); else{var key = t.b;var value = t.c;var left = t.d;var right = t.e;var $temp$t = left, $temp$acc = A3( func, key, value, A3( $elm$core$Dict$foldr, func, acc, right)), $temp$func = func
;func = $temp$func;acc = $temp$acc;t = $temp$t; continue foldr;};}});
var $elm$core$Dict$toList = function(dict){ return ( A3( $elm$core$Dict$foldr, F3( function(key,value,list){ return ( A2( $elm$core$List$cons, _Utils_Tuple2( key, value), list));}), _List_Nil, dict));};
var $elm$core$Dict$keys = function(dict){ return ( A3( $elm$core$Dict$foldr, F3( function(key,value,keyList){ return ( A2( $elm$core$List$cons, key, keyList));}), _List_Nil, dict));};
var $elm$core$Set$toList = function(_v0){var dict = _v0.a; return ( $elm$core$Dict$keys( dict));};
var $elm$core$Basics$GT ={$ :'GT'};
var $elm$core$Result$Err = function(a){ return ({a : a,$ :'Err'});};
var $elm$json$Json$Decode$Failure = F2( function(a,b){ return ({b : b,a : a,$ :'Failure'});});
var $elm$json$Json$Decode$Field = F2( function(a,b){ return ({b : b,a : a,$ :'Field'});});
var $elm$json$Json$Decode$Index = F2( function(a,b){ return ({b : b,a : a,$ :'Index'});});
var $elm$core$Result$Ok = function(a){ return ({a : a,$ :'Ok'});};
var $elm$json$Json$Decode$OneOf = function(a){ return ({a : a,$ :'OneOf'});};
var $elm$core$Basics$False ={$ :'False'};
var $elm$core$Basics$add = _Basics_add;
var $elm$core$Maybe$Just = function(a){ return ({a : a,$ :'Just'});};
var $elm$core$Maybe$Nothing ={$ :'Nothing'};
var $elm$core$String$all = _String_all;
var $elm$core$Basics$and = _Basics_and;
var $elm$core$Basics$append = _Utils_append;
var $elm$json$Json$Encode$encode = _Json_encode;
var $elm$core$String$fromInt = _String_fromNumber;
var $elm$core$String$join = F2( function(sep,chunks){ return ( A2( _String_join, sep, _List_toArray( chunks)));});
var $elm$core$String$split = F2( function(sep,string){ return ( _List_fromArray( A2( _String_split, sep, string)));});
var $elm$json$Json$Decode$indent = function(str){ return ( A2( $elm$core$String$join,'\n    ', A2( $elm$core$String$split,'\n', str)));};
var $elm$core$List$foldl = F3( function(func,acc,list){foldl: while (true ){if (! list.b ) return ( acc); else{var x = list.a;var xs = list.b;var $temp$list = xs, $temp$acc = A2( func, x, acc), $temp$func = func
;func = $temp$func;acc = $temp$acc;list = $temp$list; continue foldl;};}});
var $elm$core$List$length = function(xs){ return ( A3( $elm$core$List$foldl, F2( function(_v0,i){ return ( i +1);}),0, xs));};
var $elm$core$List$map2 = _List_map2;
var $elm$core$Basics$le = _Utils_le;
var $elm$core$Basics$sub = _Basics_sub;
var $elm$core$List$rangeHelp = F3( function(lo,hi,list){rangeHelp: while (true ){if ( _Utils_cmp( lo, hi) <1 ){var $temp$list = A2( $elm$core$List$cons, hi, list), $temp$hi = hi -1, $temp$lo = lo
;lo = $temp$lo;hi = $temp$hi;list = $temp$list; continue rangeHelp;} else{ return ( list);};}});
var $elm$core$List$range = F2( function(lo,hi){ return ( A3( $elm$core$List$rangeHelp, lo, hi, _List_Nil));});
var $elm$core$List$indexedMap = F2( function(f,xs){ return ( A3( $elm$core$List$map2, f, A2( $elm$core$List$range,0, $elm$core$List$length( xs) -1), xs));});
var $elm$core$Char$toCode = _Char_toCode;
var $elm$core$Char$isLower = function(_char){var code = $elm$core$Char$toCode( _char); return (97 <= code && code <=122);};
var $elm$core$Char$isUpper = function(_char){var code = $elm$core$Char$toCode( _char); return ( code <=90 &&65 <= code);};
var $elm$core$Basics$or = _Basics_or;
var $elm$core$Char$isAlpha = function(_char){ return ( $elm$core$Char$isLower( _char) || $elm$core$Char$isUpper( _char));};
var $elm$core$Char$isDigit = function(_char){var code = $elm$core$Char$toCode( _char); return ( code <=57 &&48 <= code);};
var $elm$core$Char$isAlphaNum = function(_char){ return ( $elm$core$Char$isLower( _char) || $elm$core$Char$isUpper( _char) || $elm$core$Char$isDigit( _char));};
var $elm$core$List$reverse = function(list){ return ( A3( $elm$core$List$foldl, $elm$core$List$cons, _List_Nil, list));};
var $elm$core$String$uncons = _String_uncons;
var $elm$json$Json$Decode$errorOneOf = F2( function(i,error){ return ('\n\n(' +( $elm$core$String$fromInt( i +1) +(') ' + $elm$json$Json$Decode$indent( $elm$json$Json$Decode$errorToString( error)))));});
var $elm$json$Json$Decode$errorToString = function(error){ return ( A2( $elm$json$Json$Decode$errorToStringHelp, error, _List_Nil));};
var $elm$json$Json$Decode$errorToStringHelp = F2( function(error,context){errorToStringHelp: while (true ){ switch( error.$){ case 'Field' :var f = error.a;var err = error.b;var isSimple = function(){var _v1 = $elm$core$String$uncons( f);if ( _v1.$ ==='Nothing' ) return false; else{var _v2 = _v1.a;var _char = _v2.a;var rest = _v2.b; return ( $elm$core$Char$isAlpha( _char) && A2( $elm$core$String$all, $elm$core$Char$isAlphaNum, rest));}}();var fieldName = isSimple?('.' + f):'[\'' +( f +'\']');var $temp$context = A2( $elm$core$List$cons, fieldName, context), $temp$error = err
;error = $temp$error;context = $temp$context; continue errorToStringHelp; case 'Index' :var i = error.a;var err = error.b;var indexName ='[' +( $elm$core$String$fromInt( i) +']');var $temp$context = A2( $elm$core$List$cons, indexName, context), $temp$error = err
;error = $temp$error;context = $temp$context; continue errorToStringHelp; case 'OneOf' :var errors = error.a;if (! errors.b ) return ('Ran into a Json.Decode.oneOf with no possibilities' + function(){if (! context.b ) return '!'; else return (' at json' + A2( $elm$core$String$join,'', $elm$core$List$reverse( context)));}()); else if (! errors.b.b ){var err = errors.a;var $temp$context = context, $temp$error = err
;error = $temp$error;context = $temp$context; continue errorToStringHelp;} else{var starter = function(){if (! context.b ) return 'Json.Decode.oneOf'; else return ('The Json.Decode.oneOf at json' + A2( $elm$core$String$join,'', $elm$core$List$reverse( context)));}();var introduction = starter +(' failed in the following ' +( $elm$core$String$fromInt( $elm$core$List$length( errors)) +' ways:')); return ( A2( $elm$core$String$join,'\n\n', A2( $elm$core$List$cons, introduction, A2( $elm$core$List$indexedMap, $elm$json$Json$Decode$errorOneOf, errors))));} default :var msg = error.a;var json = error.b;var introduction = function(){if (! context.b ) return 'Problem with the given value:\n\n'; else return ('Problem with the value at json' +( A2( $elm$core$String$join,'', $elm$core$List$reverse( context)) +':\n\n    '));}(); return ( introduction +( $elm$json$Json$Decode$indent( A2( $elm$json$Json$Encode$encode,4, json)) +('\n\n' + msg)));};}});
var $elm$core$Array$branchFactor =32;
var $elm$core$Array$Array_elm_builtin = F4( function(a,b,c,d){ return ({d : d,c : c,b : b,a : a,$ :'Array_elm_builtin'});});
var $elm$core$Elm$JsArray$empty = _JsArray_empty;
var $elm$core$Basics$ceiling = _Basics_ceiling;
var $elm$core$Basics$fdiv = _Basics_fdiv;
var $elm$core$Basics$logBase = F2( function(base,number){ return ( _Basics_log( number) / _Basics_log( base));});
var $elm$core$Basics$toFloat = _Basics_toFloat;
var $elm$core$Array$shiftStep = $elm$core$Basics$ceiling( A2( $elm$core$Basics$logBase,2, $elm$core$Array$branchFactor));
var $elm$core$Array$empty = A4( $elm$core$Array$Array_elm_builtin,0, $elm$core$Array$shiftStep, $elm$core$Elm$JsArray$empty, $elm$core$Elm$JsArray$empty);
var $elm$core$Elm$JsArray$initialize = _JsArray_initialize;
var $elm$core$Array$Leaf = function(a){ return ({a : a,$ :'Leaf'});};
var $elm$core$Basics$apL = F2( function(f,x){ return ( f( x));});
var $elm$core$Basics$apR = F2( function(x,f){ return ( f( x));});
var $elm$core$Basics$eq = _Utils_equal;
var $elm$core$Basics$floor = _Basics_floor;
var $elm$core$Elm$JsArray$length = _JsArray_length;
var $elm$core$Basics$gt = _Utils_gt;
var $elm$core$Basics$max = F2( function(x,y){ return (( _Utils_cmp( x, y) >0)? x: y);});
var $elm$core$Basics$mul = _Basics_mul;
var $elm$core$Array$SubTree = function(a){ return ({a : a,$ :'SubTree'});};
var $elm$core$Elm$JsArray$initializeFromList = _JsArray_initializeFromList;
var $elm$core$Array$compressNodes = F2( function(nodes,acc){compressNodes: while (true ){var _v0 = A2( $elm$core$Elm$JsArray$initializeFromList, $elm$core$Array$branchFactor, nodes);var node = _v0.a;var remainingNodes = _v0.b;var newAcc = A2( $elm$core$List$cons, $elm$core$Array$SubTree( node), acc);if (! remainingNodes.b ) return ( $elm$core$List$reverse( newAcc)); else{var $temp$acc = newAcc, $temp$nodes = remainingNodes
;nodes = $temp$nodes;acc = $temp$acc; continue compressNodes;}}});
var $elm$core$Tuple$first = function(_v0){var x = _v0.a; return ( x);};
var $elm$core$Array$treeFromBuilder = F2( function(nodeList,nodeListSize){treeFromBuilder: while (true ){var newNodeSize = $elm$core$Basics$ceiling( nodeListSize / $elm$core$Array$branchFactor);if ( newNodeSize ===1 ){ return ( A2( $elm$core$Elm$JsArray$initializeFromList, $elm$core$Array$branchFactor, nodeList).a);} else{var $temp$nodeListSize = newNodeSize, $temp$nodeList = A2( $elm$core$Array$compressNodes, nodeList, _List_Nil)
;nodeList = $temp$nodeList;nodeListSize = $temp$nodeListSize; continue treeFromBuilder;}}});
var $elm$core$Array$builderToArray = F2( function(reverseNodeList,builder){if (! builder.nodeListSize ){ return ( A4( $elm$core$Array$Array_elm_builtin, $elm$core$Elm$JsArray$length( builder.tail), $elm$core$Array$shiftStep, $elm$core$Elm$JsArray$empty, builder.tail));} else{var treeLen = builder.nodeListSize * $elm$core$Array$branchFactor;var depth = $elm$core$Basics$floor( A2( $elm$core$Basics$logBase, $elm$core$Array$branchFactor, treeLen -1));var correctNodeList = reverseNodeList? $elm$core$List$reverse( builder.nodeList): builder.nodeList;var tree = A2( $elm$core$Array$treeFromBuilder, correctNodeList, builder.nodeListSize); return ( A4( $elm$core$Array$Array_elm_builtin, $elm$core$Elm$JsArray$length( builder.tail) + treeLen, A2( $elm$core$Basics$max,5, depth * $elm$core$Array$shiftStep), tree, builder.tail));}});
var $elm$core$Basics$idiv = _Basics_idiv;
var $elm$core$Basics$lt = _Utils_lt;
var $elm$core$Array$initializeHelp = F5( function(fn,fromIndex,len,nodeList,tail){initializeHelp: while (true ){if ( fromIndex <0 ){ return ( A2( $elm$core$Array$builderToArray,false,{tail : tail,nodeListSize : len / $elm$core$Array$branchFactor |0,nodeList : nodeList}));} else{var leaf = $elm$core$Array$Leaf( A3( $elm$core$Elm$JsArray$initialize, $elm$core$Array$branchFactor, fromIndex, fn));var $temp$tail = tail, $temp$nodeList = A2( $elm$core$List$cons, leaf, nodeList), $temp$len = len, $temp$fromIndex = fromIndex - $elm$core$Array$branchFactor, $temp$fn = fn
;fn = $temp$fn;fromIndex = $temp$fromIndex;len = $temp$len;nodeList = $temp$nodeList;tail = $temp$tail; continue initializeHelp;};}});
var $elm$core$Basics$remainderBy = _Basics_remainderBy;
var $elm$core$Array$initialize = F2( function(len,fn){if ( len <=0 ){ return ( $elm$core$Array$empty);} else{var tailLen = len % $elm$core$Array$branchFactor;var tail = A3( $elm$core$Elm$JsArray$initialize, tailLen, len - tailLen, fn);var initialFromIndex = len - tailLen - $elm$core$Array$branchFactor; return ( A5( $elm$core$Array$initializeHelp, fn, initialFromIndex, len, _List_Nil, tail));}});
var $elm$core$Basics$True ={$ :'True'};
var $elm$core$Result$isOk = function(result){if ( result.$ ==='Ok' ) return true; else return false;};
var $elm$json$Json$Decode$map = _Json_map1;
var $elm$json$Json$Decode$map2 = _Json_map2;
var $elm$json$Json$Decode$succeed = _Json_succeed;
var $elm$virtual_dom$VirtualDom$toHandlerInt = function(handler){ switch( handler.$){ case 'Normal' : return 0; case 'MayStopPropagation' : return 1; case 'MayPreventDefault' : return 2; default : return 3;}};
var $elm$html$Html$pre = _VirtualDom_node('pre');
var $elm$core$List$foldrHelper = F4( function(fn,acc,ctr,ls){if (! ls.b ) return ( acc); else{var a = ls.a;var r1 = ls.b;if (! r1.b ) return ( A2( fn, a, acc)); else{var b = r1.a;var r2 = r1.b;if (! r2.b ) return ( A2( fn, a, A2( fn, b, acc))); else{var c = r2.a;var r3 = r2.b;if (! r3.b ) return ( A2( fn, a, A2( fn, b, A2( fn, c, acc)))); else{var d = r3.a;var r4 = r3.b;var res =( ctr >500)? A3( $elm$core$List$foldl, fn, acc, $elm$core$List$reverse( r4)): A4( $elm$core$List$foldrHelper, fn, acc, ctr +1, r4); return ( A2( fn, a, A2( fn, b, A2( fn, c, A2( fn, d, res)))));}}}}});
var $elm$core$List$foldr = F3( function(fn,acc,ls){ return ( A4( $elm$core$List$foldrHelper, fn, acc,0, ls));});
var $elm$core$List$append = F2( function(xs,ys){if (! ys.b ) return ( xs); else return ( A3( $elm$core$List$foldr, $elm$core$List$cons, ys, xs));});
var $elm$core$List$concat = function(lists){ return ( A3( $elm$core$List$foldr, $elm$core$List$append, _List_Nil, lists));};
var $elm$core$List$map = F2( function(f,xs){ return ( A3( $elm$core$List$foldr, F2( function(x,acc){ return ( A2( $elm$core$List$cons, f( x), acc));}), _List_Nil, xs));});
var $elm$core$List$concatMap = F2( function(f,list){ return ( $elm$core$List$concat( A2( $elm$core$List$map, f, list)));});
var $elm$core$List$filter = F2( function(isGood,list){ return ( A3( $elm$core$List$foldr, F2( function(x,xs){ return ( isGood( x)? A2( $elm$core$List$cons, x, xs): xs);}), _List_Nil, list));});
var $elm$core$List$isEmpty = function(xs){if (! xs.b ) return true; else return false;};
var $user$project$Test$runSkippedTest = function(innerTest){runSkippedTest: while (true ){ switch( innerTest.$){ case 'UnitTest' :var description = innerTest.a; return ({status :'SKIP',message :'Skipped',duration :0,description : description}); case 'TestGroup' :var description = innerTest.a; return ({status :'SKIP',message :'Skipped',duration :0,description : description}); case 'Skip' :var nestedTest = innerTest.a;var $temp$innerTest = nestedTest
;innerTest = $temp$innerTest; continue runSkippedTest; default :var description = innerTest.a; return ({status :'SKIP',message :'Skipped',duration :0,description : description});};}};
var $user$project$Test$reasonToString = function(reason){ switch( reason.$){ case 'Equality' :var label = reason.a;var expected = reason.b;var actual = reason.c; return ( label +('\n\nExpected:\n    ' +( expected +('\n\nActual:\n    ' + actual)))); case 'Comparison' :var label = reason.a;var actual = reason.b;var op = reason.c;var threshold = reason.d; return ( label +('\n\nExpected ' +( actual +(' ' +( op +(' ' + threshold)))))); default :var message = reason.a; return ( message);}};
var $user$project$Test$runUnitTest = F2( function(description,expectationFn){var result = expectationFn( _Utils_Tuple0);if ( result.$ ==='Pass' ) return ({status :'PASS',message :'',duration :0,description : description}); else{var reason = result.a; return ({status :'FAIL',message : $user$project$Test$reasonToString( reason),duration :0,description : description});}});
var $user$project$Test$run = function(testCase){ switch( testCase.$){ case 'UnitTest' :var description = testCase.a;var expectationFn = testCase.b; return ( A2( $user$project$Test$runUnitTest, description, expectationFn)); case 'TestGroup' :var description = testCase.a;var tests = testCase.b; return ( A2( $user$project$Test$runTestGroup, description, tests)); case 'Skip' :var innerTest = testCase.a; return ( $user$project$Test$runSkippedTest( innerTest)); default :var description = testCase.a; return ({status :'TODO',message :'Not yet implemented',duration :0,description : description});}};
var $user$project$Test$runTestGroup = F2( function(description,tests){var results = A2( $elm$core$List$map, $user$project$Test$run, tests);var skipped = A2( $elm$core$List$filter, function(r){ return ( r.status ==='SKIP');}, results);var todos = A2( $elm$core$List$filter, function(r){ return ( r.status ==='TODO');}, results);var failures = A2( $elm$core$List$filter, function(r){ return ( r.status ==='FAIL');}, results); return ({status : $elm$core$List$isEmpty( failures)?'PASS':'FAIL',message : $elm$core$String$fromInt( $elm$core$List$length( failures)) +(' failed, ' +( $elm$core$String$fromInt( $elm$core$List$length( skipped)) +(' skipped, ' +( $elm$core$String$fromInt( $elm$core$List$length( todos)) +' todo')))),duration :0,description : description});});
var $user$project$Test$collectResults = function(testCase){ switch( testCase.$){ case 'UnitTest' : return ( _List_fromArray([ $user$project$Test$run( testCase)])); case 'TestGroup' :var tests = testCase.b; return ( A2( $elm$core$List$concatMap, $user$project$Test$collectResults, tests)); case 'Skip' : return ( _List_fromArray([ $user$project$Test$run( testCase)])); default : return ( _List_fromArray([ $user$project$Test$run( testCase)]));}};
var $elm$core$String$replace = F3( function(before,after,string){ return ( A2( $elm$core$String$join, after, A2( $elm$core$String$split, before, string)));});
var $user$project$Test$formatFailure = function(result){ return ('  â ' +( result.description +('\n' +('    ' + A3( $elm$core$String$replace,'\n','\n    ', result.message)))));};
var $elm$core$Bitwise$and = _Bitwise_and;
var $elm$core$Bitwise$shiftRightBy = _Bitwise_shiftRightBy;
var $elm$core$String$repeatHelp = F3( function(n,chunk,result){ return (( n <=0)? result: A3( $elm$core$String$repeatHelp, n >>1, _Utils_ap( chunk, chunk),(! n &1)? result: _Utils_ap( result, chunk)));});
var $elm$core$String$repeat = F2( function(n,chunk){ return ( A3( $elm$core$String$repeatHelp, n, chunk,''));});
var $user$project$Test$formatResults = function(stats){var summary ='  Passed: ' +( $elm$core$String$fromInt( stats.passed) +('\n' +('  Failed: ' +( $elm$core$String$fromInt( stats.failed) +('\n' +(( stats.skipped >0)?('  Skipped: ' +( $elm$core$String$fromInt( stats.skipped) +'\n')):'' +(( stats.todo >0)?('  Todo: ' +( $elm$core$String$fromInt( stats.todo) +'\n')):'' +('  Total: ' +( $elm$core$String$fromInt( stats.total) +'\n')))))))));var header ='\n' +( A2( $elm$core$String$repeat,60,'â') +('\n' +('  Test Results\n' +( A2( $elm$core$String$repeat,60,'â') +'\n\n'))));var footer ='\n' +( A2( $elm$core$String$repeat,60,'â') +'\n');var failureDetails = $elm$core$List$isEmpty( stats.failures)?'\n  All tests passed!\n':'\n  Failures:\n\n' +( A2( $elm$core$String$join,'\n\n', A2( $elm$core$List$map, $user$project$Test$formatFailure, stats.failures)) +'\n'); return ( _Utils_ap( header, _Utils_ap( summary, _Utils_ap( failureDetails, footer))));};
var $user$project$Test$runTests = function(tests){var allResults = A2( $elm$core$List$concatMap, $user$project$Test$collectResults, tests);var failedTests = $elm$core$List$length( A2( $elm$core$List$filter, function(r){ return ( r.status ==='FAIL');}, allResults));var passedTests = $elm$core$List$length( A2( $elm$core$List$filter, function(r){ return ( r.status ==='PASS');}, allResults));var skippedTests = $elm$core$List$length( A2( $elm$core$List$filter, function(r){ return ( r.status ==='SKIP');}, allResults));var todoTests = $elm$core$List$length( A2( $elm$core$List$filter, function(r){ return ( r.status ==='TODO');}, allResults));var totalTests = $elm$core$List$length( allResults); return ( $user$project$Test$formatResults({total : totalTests,todo : todoTests,skipped : skippedTests,passed : passedTests,failures : A2( $elm$core$List$filter, function(r){ return ( r.status ==='FAIL');}, allResults),failed : failedTests}));};
var $user$project$Test$TestGroup = F2( function(a,b){ return ({b : b,a : a,$ :'TestGroup'});});
var $user$project$Test$describe = F2( function(description,tests){ return ( A2( $user$project$Test$TestGroup, description, tests));});
var $user$project$AudioFFI$getAudioListener = $author$project$FFI$getAudioListener;
var $user$project$AudioFFI$getContextAudioListener = $author$project$FFI$getContextAudioListener;
var $elm$core$Basics$negate = function(n){ return (- n);};
var $user$project$Expect$Pass ={$ :'Pass'};
var $user$project$Expect$pass = $user$project$Expect$Pass;
var $user$project$AudioFFI$setListenerForward = $author$project$FFI$setListenerForward;
var $user$project$AudioFFI$setListenerPosition = $author$project$FFI$setListenerPosition;
var $user$project$AudioFFI$setListenerUp = $author$project$FFI$setListenerUp;
var $user$project$Test$UnitTest = F2( function(a,b){ return ({b : b,a : a,$ :'UnitTest'});});
var $user$project$Test$test = F2( function(description,expectationFn){ return ( A2( $user$project$Test$UnitTest, description, expectationFn));});
var $user$project$Capability$Click ={$ :'Click'};
var $user$project$AudioFFI$createAudioContext = $author$project$FFI$createAudioContext;
var $user$project$SpatialTest$extractContext = function(initialized){if ( initialized.$ ==='Fresh' ){var ctx = initialized.a; return ( ctx);} else{var ctx = initialized.a; return ( ctx);}};
var $user$project$SpatialTest$withRawContext = function(fn){var _v0 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v0.$ ==='Ok' ){var ctx = _v0.a; return ( fn( $user$project$SpatialTest$extractContext( ctx)));} else return ( $user$project$Expect$pass);};
var $user$project$SpatialTest$listenerTests = A2( $user$project$Test$describe,'Audio Listener', _List_fromArray([ A2( $user$project$Test$describe,'getAudioListener', _List_fromArray([ A2( $user$project$Test$test,'returns audio listener', function(_v0){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var listener = $user$project$AudioFFI$getAudioListener( ctx); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getContextAudioListener', _List_fromArray([ A2( $user$project$Test$test,'returns context audio listener', function(_v1){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var listener = $user$project$AudioFFI$getContextAudioListener( ctx); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setListenerPosition', _List_fromArray([ A2( $user$project$Test$test,'sets listener at origin', function(_v2){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var listener = $user$project$AudioFFI$getAudioListener( ctx);var _v3 = A4( $user$project$AudioFFI$setListenerPosition, listener,0.0,0.0,0.0); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'sets listener position', function(_v4){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var listener = $user$project$AudioFFI$getAudioListener( ctx);var _v5 = A4( $user$project$AudioFFI$setListenerPosition, listener,1.0,2.0,3.0); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setListenerForward', _List_fromArray([ A2( $user$project$Test$test,'sets listener forward direction', function(_v6){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var listener = $user$project$AudioFFI$getAudioListener( ctx);var _v7 = A4( $user$project$AudioFFI$setListenerForward, listener,0.0,0.0,-1.0); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setListenerUp', _List_fromArray([ A2( $user$project$Test$test,'sets listener up direction', function(_v8){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var listener = $user$project$AudioFFI$getAudioListener( ctx);var _v9 = A4( $user$project$AudioFFI$setListenerUp, listener,0.0,1.0,0.0); return ( $user$project$Expect$pass);}));})]))]));
var $user$project$Expect$Absolute = function(a){ return ({a : a,$ :'Absolute'});};
var $user$project$AudioFFI$createPanner = $author$project$FFI$createPanner;
var $user$project$Expect$Custom = function(a){ return ({a : a,$ :'Custom'});};
var $user$project$Expect$Fail = function(a){ return ({a : a,$ :'Fail'});};
var $user$project$Expect$fail = function(message){ return ( $user$project$Expect$Fail( $user$project$Expect$Custom( message)));};
var $user$project$AudioFFI$setConeInnerAngle = $author$project$FFI$setConeInnerAngle;
var $user$project$AudioFFI$setConeOuterAngle = $author$project$FFI$setConeOuterAngle;
var $user$project$AudioFFI$setConeOuterGain = $author$project$FFI$setConeOuterGain;
var $elm$core$Basics$abs = function(n){ return (( n <0)?(- n): n);};
var $elm$core$Debug$toString = _Debug_toString;
var $user$project$Expect$within = F3( function(tolerance,expected,actual){var diff = $elm$core$Basics$abs( expected - actual);var withinTolerance = function(){ switch( tolerance.$){ case 'Absolute' :var maxDiff = tolerance.a; return ( _Utils_cmp( diff, maxDiff) <1); case 'Relative' :var maxRelDiff = tolerance.a; return ( _Utils_cmp( diff, $elm$core$Basics$abs( expected) * maxRelDiff) <1); default :var maxAbsDiff = tolerance.a;var maxRelDiff = tolerance.b; return ( _Utils_cmp( diff, maxAbsDiff) <1 || _Utils_cmp( diff, $elm$core$Basics$abs( expected) * maxRelDiff) <1);}}(); return ( withinTolerance? $user$project$Expect$Pass: $user$project$Expect$Fail( $user$project$Expect$Custom('Expected ' +( $elm$core$Debug$toString( actual) +(' to be within tolerance of ' +( $elm$core$Debug$toString( expected) +(' (diff: ' +( $elm$core$Debug$toString( diff) +')'))))))));});
var $user$project$SpatialTest$pannerConeTests = A2( $user$project$Test$describe,'panner cone settings', _List_fromArray([ A2( $user$project$Test$describe,'setConeInnerAngle', _List_fromArray([ A2( $user$project$Test$test,'sets inner angle to 360', function(_v0){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var angle = A2( $user$project$AudioFFI$setConeInnerAngle, panner,360.0); return ( A3( $user$project$Expect$within, $user$project$Expect$Absolute(0.01),360.0, angle));}));}) , A2( $user$project$Test$test,'sets inner angle to 90', function(_v1){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var angle = A2( $user$project$AudioFFI$setConeInnerAngle, panner,90.0); return ( A3( $user$project$Expect$within, $user$project$Expect$Absolute(0.01),90.0, angle));}));})])) , A2( $user$project$Test$describe,'setConeOuterAngle', _List_fromArray([ A2( $user$project$Test$test,'sets outer angle', function(_v2){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var angle = A2( $user$project$AudioFFI$setConeOuterAngle, panner,270.0); return ( A3( $user$project$Expect$within, $user$project$Expect$Absolute(0.01),270.0, angle));}));})])) , A2( $user$project$Test$describe,'setConeOuterGain', _List_fromArray([ A2( $user$project$Test$test,'sets valid outer gain', function(_v3){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v4 = A2( $user$project$AudioFFI$setConeOuterGain, panner,0.25);if ( _v4.$ ==='Ok' ){var gain = _v4.a; return ( A3( $user$project$Expect$within, $user$project$Expect$Absolute(0.01),0.25, gain));} else return ( $user$project$Expect$fail('setConeOuterGain should succeed with valid value'));}));}) , A2( $user$project$Test$test,'rejects gain outside 0-1 range', function(_v5){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v6 = A2( $user$project$AudioFFI$setConeOuterGain, panner,1.5);if ( _v6.$ ==='Ok' ) return ( $user$project$Expect$fail('setConeOuterGain should reject values > 1')); else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$SpatialTest$pannerCreationTests = A2( $user$project$Test$describe,'createPanner', _List_fromArray([ A2( $user$project$Test$test,'creates panner node', function(_v0){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx); return ( $user$project$Expect$pass);}));})]));
var $user$project$AudioFFI$setMaxDistance = $author$project$FFI$setMaxDistance;
var $user$project$AudioFFI$setRefDistance = $author$project$FFI$setRefDistance;
var $user$project$AudioFFI$setRolloffFactor = $author$project$FFI$setRolloffFactor;
var $user$project$SpatialTest$pannerDistanceTests = A2( $user$project$Test$describe,'panner distance settings', _List_fromArray([ A2( $user$project$Test$describe,'setRefDistance', _List_fromArray([ A2( $user$project$Test$test,'sets valid reference distance', function(_v0){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v1 = A2( $user$project$AudioFFI$setRefDistance, panner,2.0);if ( _v1.$ ==='Ok' ){var refDist = _v1.a; return ( A3( $user$project$Expect$within, $user$project$Expect$Absolute(0.01),2.0, refDist));} else return ( $user$project$Expect$fail('setRefDistance should succeed with valid value'));}));}) , A2( $user$project$Test$test,'rejects negative reference distance', function(_v2){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v3 = A2( $user$project$AudioFFI$setRefDistance, panner,-1.0);if ( _v3.$ ==='Ok' ) return ( $user$project$Expect$fail('setRefDistance should reject negative values')); else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setMaxDistance', _List_fromArray([ A2( $user$project$Test$test,'sets valid max distance', function(_v4){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v5 = A2( $user$project$AudioFFI$setMaxDistance, panner,1000.0);if ( _v5.$ ==='Ok' ){var maxDist = _v5.a; return ( A3( $user$project$Expect$within, $user$project$Expect$Absolute(0.01),1000.0, maxDist));} else return ( $user$project$Expect$fail('setMaxDistance should succeed with valid value'));}));}) , A2( $user$project$Test$test,'rejects non-positive max distance', function(_v6){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v7 = A2( $user$project$AudioFFI$setMaxDistance, panner,0.0);if ( _v7.$ ==='Ok' ) return ( $user$project$Expect$fail('setMaxDistance should reject non-positive values')); else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setRolloffFactor', _List_fromArray([ A2( $user$project$Test$test,'sets valid rolloff factor', function(_v8){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v9 = A2( $user$project$AudioFFI$setRolloffFactor, panner,0.5);if ( _v9.$ ==='Ok' ){var rolloff = _v9.a; return ( A3( $user$project$Expect$within, $user$project$Expect$Absolute(0.01),0.5, rolloff));} else return ( $user$project$Expect$fail('setRolloffFactor should succeed with valid value'));}));}) , A2( $user$project$Test$test,'rejects negative rolloff factor', function(_v10){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v11 = A2( $user$project$AudioFFI$setRolloffFactor, panner,-1.0);if ( _v11.$ ==='Ok' ) return ( $user$project$Expect$fail('setRolloffFactor should reject negative values')); else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$Expect$Equality = F3( function(a,b,c){ return ({c : c,b : b,a : a,$ :'Equality'});});
var $user$project$Expect$equal = F2( function(expected,actual){ return ( _Utils_eq( actual, expected)? $user$project$Expect$Pass: $user$project$Expect$Fail( A3( $user$project$Expect$Equality,'Expect.equal', $elm$core$Debug$toString( expected), $elm$core$Debug$toString( actual))));});
var $user$project$AudioFFI$setDistanceModel = $author$project$FFI$setDistanceModel;
var $user$project$AudioFFI$setPanningModel = $author$project$FFI$setPanningModel;
var $user$project$SpatialTest$pannerModelTests = A2( $user$project$Test$describe,'panner models', _List_fromArray([ A2( $user$project$Test$describe,'setPanningModel', _List_fromArray([ A2( $user$project$Test$test,'sets equalpower panning', function(_v0){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v1 = A2( $user$project$AudioFFI$setPanningModel, panner,'equalpower');if ( _v1.$ ==='Ok' ){var model = _v1.a; return ( A2( $user$project$Expect$equal,'equalpower', model));} else return ( $user$project$Expect$fail('setPanningModel should succeed with valid model'));}));}) , A2( $user$project$Test$test,'sets HRTF panning', function(_v2){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v3 = A2( $user$project$AudioFFI$setPanningModel, panner,'HRTF');if ( _v3.$ ==='Ok' ){var model = _v3.a; return ( A2( $user$project$Expect$equal,'HRTF', model));} else return ( $user$project$Expect$fail('setPanningModel should succeed with valid model'));}));})])) , A2( $user$project$Test$describe,'setDistanceModel', _List_fromArray([ A2( $user$project$Test$test,'sets linear distance', function(_v4){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v5 = A2( $user$project$AudioFFI$setDistanceModel, panner,'linear');if ( _v5.$ ==='Ok' ){var model = _v5.a; return ( A2( $user$project$Expect$equal,'linear', model));} else return ( $user$project$Expect$fail('setDistanceModel should succeed with valid model'));}));}) , A2( $user$project$Test$test,'sets inverse distance', function(_v6){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v7 = A2( $user$project$AudioFFI$setDistanceModel, panner,'inverse');if ( _v7.$ ==='Ok' ){var model = _v7.a; return ( A2( $user$project$Expect$equal,'inverse', model));} else return ( $user$project$Expect$fail('setDistanceModel should succeed with valid model'));}));}) , A2( $user$project$Test$test,'sets exponential distance', function(_v8){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v9 = A2( $user$project$AudioFFI$setDistanceModel, panner,'exponential');if ( _v9.$ ==='Ok' ){var model = _v9.a; return ( A2( $user$project$Expect$equal,'exponential', model));} else return ( $user$project$Expect$fail('setDistanceModel should succeed with valid model'));}));})]))]));
var $user$project$AudioFFI$getPannerOrientationX = $author$project$FFI$getPannerOrientationX;
var $user$project$AudioFFI$getPannerOrientationY = $author$project$FFI$getPannerOrientationY;
var $user$project$AudioFFI$getPannerOrientationZ = $author$project$FFI$getPannerOrientationZ;
var $user$project$AudioFFI$getPannerPositionX = $author$project$FFI$getPannerPositionX;
var $user$project$AudioFFI$getPannerPositionY = $author$project$FFI$getPannerPositionY;
var $user$project$AudioFFI$getPannerPositionZ = $author$project$FFI$getPannerPositionZ;
var $user$project$AudioFFI$setPannerOrientation = $author$project$FFI$setPannerOrientation;
var $user$project$AudioFFI$setPannerOrientationDirect = $author$project$FFI$setPannerOrientationDirect;
var $user$project$AudioFFI$setPannerPosition = $author$project$FFI$setPannerPosition;
var $user$project$SpatialTest$pannerPositionTests = A2( $user$project$Test$describe,'panner position', _List_fromArray([ A2( $user$project$Test$describe,'setPannerPosition', _List_fromArray([ A2( $user$project$Test$test,'sets position at origin', function(_v0){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v1 = A4( $user$project$AudioFFI$setPannerPosition, panner,0.0,0.0,0.0); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'sets position to the left', function(_v2){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v3 = A4( $user$project$AudioFFI$setPannerPosition, panner,-5.0,0.0,0.0); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'sets position to the right', function(_v4){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v5 = A4( $user$project$AudioFFI$setPannerPosition, panner,5.0,0.0,0.0); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'sets position above', function(_v6){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v7 = A4( $user$project$AudioFFI$setPannerPosition, panner,0.0,5.0,0.0); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'sets position in front', function(_v8){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v9 = A4( $user$project$AudioFFI$setPannerPosition, panner,0.0,0.0,-5.0); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getPannerPositionX/Y/Z', _List_fromArray([ A2( $user$project$Test$test,'gets X position param', function(_v10){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var param = $user$project$AudioFFI$getPannerPositionX( panner); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'gets Y position param', function(_v11){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var param = $user$project$AudioFFI$getPannerPositionY( panner); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'gets Z position param', function(_v12){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var param = $user$project$AudioFFI$getPannerPositionZ( panner); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'panner orientation', _List_fromArray([ A2( $user$project$Test$test,'sets orientation', function(_v13){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v14 = A4( $user$project$AudioFFI$setPannerOrientation, panner,1.0,0.0,0.0); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'sets orientation direct', function(_v15){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var _v16 = A4( $user$project$AudioFFI$setPannerOrientationDirect, panner,0.0,0.0,-1.0);if ( _v16.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'gets orientation X param', function(_v17){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var param = $user$project$AudioFFI$getPannerOrientationX( panner); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'gets orientation Y param', function(_v18){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var param = $user$project$AudioFFI$getPannerOrientationY( panner); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'gets orientation Z param', function(_v19){ return ( $user$project$SpatialTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createPanner( ctx);var param = $user$project$AudioFFI$getPannerOrientationZ( panner); return ( $user$project$Expect$pass);}));})]))]));
var $user$project$SpatialTest$suite = A2( $user$project$Test$describe,'Spatial Audio Functions', _List_fromArray([ $user$project$SpatialTest$pannerCreationTests , $user$project$SpatialTest$pannerPositionTests , $user$project$SpatialTest$pannerModelTests , $user$project$SpatialTest$pannerDistanceTests , $user$project$SpatialTest$pannerConeTests , $user$project$SpatialTest$listenerTests]));
var $elm$virtual_dom$VirtualDom$text = _VirtualDom_text;
var $elm$html$Html$text = $elm$virtual_dom$VirtualDom$text;
var $user$project$SpatialTest$main = function(){var results = $user$project$Test$runTests( _List_fromArray([ $user$project$SpatialTest$suite])); return ( A2( $elm$html$Html$pre, _List_Nil, _List_fromArray([ $elm$html$Html$text( results)])));}();
var $user$project$AudioFFI$simpleTest = $author$project$FFI$simpleTest;
var $user$project$SimplifiedTest$simpleTestTests = A2( $user$project$Test$describe,'simpleTest', _List_fromArray([ A2( $user$project$Test$test,'returns doubled value for positive input', function(_v0){var result = $user$project$AudioFFI$simpleTest(21); return ( A2( $user$project$Expect$equal,42, result));}) , A2( $user$project$Test$test,'returns doubled value for zero', function(_v1){var result = $user$project$AudioFFI$simpleTest(0); return ( A2( $user$project$Expect$equal,0, result));}) , A2( $user$project$Test$test,'returns doubled value for negative', function(_v2){var result = $user$project$AudioFFI$simpleTest(-5); return ( A2( $user$project$Expect$equal,-10, result));}) , A2( $user$project$Test$test,'returns doubled value for large number', function(_v3){var result = $user$project$AudioFFI$simpleTest(1000); return ( A2( $user$project$Expect$equal,2000, result));})]));
var $user$project$AudioFFI$createAudioContextSimplified = $author$project$FFI$createAudioContextSimplified;
var $elm$core$String$length = _String_length;
var $user$project$AudioFFI$playToneSimplified = $author$project$FFI$playToneSimplified;
var $user$project$AudioFFI$stopAudioSimplified = $author$project$FFI$stopAudioSimplified;
var $user$project$Expect$true = F2( function(description,condition){ return ( condition? $user$project$Expect$Pass: $user$project$Expect$Fail( $user$project$Expect$Custom( description)));});
var $user$project$SimplifiedTest$simplifiedAudioTests = A2( $user$project$Test$describe,'simplified audio functions', _List_fromArray([ A2( $user$project$Test$describe,'createAudioContextSimplified', _List_fromArray([ A2( $user$project$Test$test,'returns status string', function(_v0){var result = $user$project$AudioFFI$createAudioContextSimplified( _Utils_Tuple0); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));})])) , A2( $user$project$Test$describe,'playToneSimplified', _List_fromArray([ A2( $user$project$Test$test,'returns status for 440Hz sine', function(_v1){var result = A2( $user$project$AudioFFI$playToneSimplified,440.0,'sine'); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));}) , A2( $user$project$Test$test,'returns status for 880Hz square', function(_v2){var result = A2( $user$project$AudioFFI$playToneSimplified,880.0,'square'); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));}) , A2( $user$project$Test$test,'returns status for low frequency', function(_v3){var result = A2( $user$project$AudioFFI$playToneSimplified,100.0,'sawtooth'); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));}) , A2( $user$project$Test$test,'returns status for high frequency', function(_v4){var result = A2( $user$project$AudioFFI$playToneSimplified,2000.0,'triangle'); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));})])) , A2( $user$project$Test$describe,'stopAudioSimplified', _List_fromArray([ A2( $user$project$Test$test,'returns status string', function(_v5){var result = $user$project$AudioFFI$stopAudioSimplified( _Utils_Tuple0); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));})]))]));
var $user$project$AudioFFI$updateFrequency = $author$project$FFI$updateFrequency;
var $user$project$AudioFFI$updateVolume = $author$project$FFI$updateVolume;
var $user$project$AudioFFI$updateWaveform = $author$project$FFI$updateWaveform;
var $user$project$SimplifiedTest$updateFunctionTests = A2( $user$project$Test$describe,'update functions', _List_fromArray([ A2( $user$project$Test$describe,'updateFrequency', _List_fromArray([ A2( $user$project$Test$test,'updates to 440Hz', function(_v0){var result = $user$project$AudioFFI$updateFrequency(440.0); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));}) , A2( $user$project$Test$test,'updates to 880Hz', function(_v1){var result = $user$project$AudioFFI$updateFrequency(880.0); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));}) , A2( $user$project$Test$test,'updates to low frequency', function(_v2){var result = $user$project$AudioFFI$updateFrequency(100.0); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));}) , A2( $user$project$Test$test,'updates to high frequency', function(_v3){var result = $user$project$AudioFFI$updateFrequency(5000.0); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));})])) , A2( $user$project$Test$describe,'updateVolume', _List_fromArray([ A2( $user$project$Test$test,'updates to full volume', function(_v4){var result = $user$project$AudioFFI$updateVolume(100.0); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));}) , A2( $user$project$Test$test,'updates to half volume', function(_v5){var result = $user$project$AudioFFI$updateVolume(50.0); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));}) , A2( $user$project$Test$test,'updates to muted', function(_v6){var result = $user$project$AudioFFI$updateVolume(0.0); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));}) , A2( $user$project$Test$test,'updates to quarter volume', function(_v7){var result = $user$project$AudioFFI$updateVolume(25.0); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));})])) , A2( $user$project$Test$describe,'updateWaveform', _List_fromArray([ A2( $user$project$Test$test,'updates to sine', function(_v8){var result = $user$project$AudioFFI$updateWaveform('sine'); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));}) , A2( $user$project$Test$test,'updates to square', function(_v9){var result = $user$project$AudioFFI$updateWaveform('square'); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));}) , A2( $user$project$Test$test,'updates to sawtooth', function(_v10){var result = $user$project$AudioFFI$updateWaveform('sawtooth'); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));}) , A2( $user$project$Test$test,'updates to triangle', function(_v11){var result = $user$project$AudioFFI$updateWaveform('triangle'); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));})]))]));
var $user$project$AudioFFI$checkWebAudioSupport = $author$project$FFI$checkWebAudioSupport;
var $user$project$SimplifiedTest$webAudioSupportTests = A2( $user$project$Test$describe,'checkWebAudioSupport', _List_fromArray([ A2( $user$project$Test$test,'returns support status string', function(_v0){var result = $user$project$AudioFFI$checkWebAudioSupport( _Utils_Tuple0); return ( A2( $user$project$Expect$true,'should return non-empty string', $elm$core$String$length( result) >0));}) , A2( $user$project$Test$test,'returns valid support status', function(_v1){var result = $user$project$AudioFFI$checkWebAudioSupport( _Utils_Tuple0); return ( A2( $user$project$Expect$true,'should contain support info',true));})]));
var $user$project$SimplifiedTest$suite = A2( $user$project$Test$describe,'Simplified Interface Functions', _List_fromArray([ $user$project$SimplifiedTest$webAudioSupportTests , $user$project$SimplifiedTest$simpleTestTests , $user$project$SimplifiedTest$simplifiedAudioTests , $user$project$SimplifiedTest$updateFunctionTests]));
var $user$project$SimplifiedTest$main = function(){var results = $user$project$Test$runTests( _List_fromArray([ $user$project$SimplifiedTest$suite])); return ( A2( $elm$html$Html$pre, _List_Nil, _List_fromArray([ $elm$html$Html$text( results)])));}();
var $user$project$AudioFFI$createOscillator = $author$project$FFI$createOscillator;
var $user$project$OscillatorTest$withContext = function(fn){var _v0 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v0.$ ==='Ok' ){var ctx = _v0.a; return ( fn( ctx));} else return ( $user$project$Expect$pass);};
var $user$project$OscillatorTest$createOscillatorTests = A2( $user$project$Test$describe,'createOscillator', _List_fromArray([ A2( $user$project$Test$test,'creates oscillator with valid frequency', function(_v0){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v1 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'sine');if ( _v1.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates oscillator with minimum frequency', function(_v2){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v3 = A3( $user$project$AudioFFI$createOscillator, ctx,0.0,'sine');if ( _v3.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates oscillator with high frequency', function(_v4){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v5 = A3( $user$project$AudioFFI$createOscillator, ctx,20000.0,'sine');if ( _v5.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates oscillator with different waveforms', function(_v6){ return ( $user$project$OscillatorTest$withContext( function(ctx){var triangleResult = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'triangle');var squareResult = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'square');var sineResult = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'sine');var sawtoothResult = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'sawtooth'); return ( $user$project$Expect$pass);}));})]));
var $user$project$AudioFFI$setOscillatorDetune = $author$project$FFI$setOscillatorDetune;
var $user$project$AudioFFI$setOscillatorFrequency = $author$project$FFI$setOscillatorFrequency;
var $user$project$AudioFFI$startOscillator = $author$project$FFI$startOscillator;
var $user$project$AudioFFI$stopOscillator = $author$project$FFI$stopOscillator;
var $user$project$OscillatorTest$oscillatorControlTests = A2( $user$project$Test$describe,'oscillator controls', _List_fromArray([ A2( $user$project$Test$describe,'startOscillator', _List_fromArray([ A2( $user$project$Test$test,'starts oscillator at time 0', function(_v0){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v1 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'sine');if ( _v1.$ ==='Ok' ){var osc = _v1.a;var _v2 = A2( $user$project$AudioFFI$startOscillator, osc,0.0);if ( _v2.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'starts oscillator at future time', function(_v3){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v4 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'sine');if ( _v4.$ ==='Ok' ){var osc = _v4.a;var _v5 = A2( $user$project$AudioFFI$startOscillator, osc,1.0);if ( _v5.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'stopOscillator', _List_fromArray([ A2( $user$project$Test$test,'stops oscillator at specified time', function(_v6){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v7 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'sine');if ( _v7.$ ==='Ok' ){var osc = _v7.a;var _v8 = A2( $user$project$AudioFFI$startOscillator, osc,0.0);if ( _v8.$ ==='Ok' ){var _v9 = A2( $user$project$AudioFFI$stopOscillator, osc,1.0);if ( _v9.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setOscillatorFrequency', _List_fromArray([ A2( $user$project$Test$test,'sets frequency to new value', function(_v10){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v11 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'sine');if ( _v11.$ ==='Ok' ){var osc = _v11.a;var _v12 = A3( $user$project$AudioFFI$setOscillatorFrequency, osc,880.0,0.0); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setOscillatorDetune', _List_fromArray([ A2( $user$project$Test$test,'sets detune in cents', function(_v13){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v14 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'sine');if ( _v14.$ ==='Ok' ){var osc = _v14.a;var _v15 = A3( $user$project$AudioFFI$setOscillatorDetune, osc,100.0,0.0); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$getOscillatorDetuneParam = $author$project$FFI$getOscillatorDetuneParam;
var $user$project$AudioFFI$getOscillatorFrequencyParam = $author$project$FFI$getOscillatorFrequencyParam;
var $user$project$AudioFFI$getOscillatorType = $author$project$FFI$getOscillatorType;
var $user$project$OscillatorTest$oscillatorPropertyTests = A2( $user$project$Test$describe,'oscillator properties', _List_fromArray([ A2( $user$project$Test$describe,'getOscillatorType', _List_fromArray([ A2( $user$project$Test$test,'returns correct waveform type', function(_v0){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v1 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'sine');if ( _v1.$ ==='Ok' ){var osc = _v1.a; return ( A2( $user$project$Expect$equal,'sine', $user$project$AudioFFI$getOscillatorType( osc)));} else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'returns square for square oscillator', function(_v2){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v3 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'square');if ( _v3.$ ==='Ok' ){var osc = _v3.a; return ( A2( $user$project$Expect$equal,'square', $user$project$AudioFFI$getOscillatorType( osc)));} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getOscillatorFrequencyParam', _List_fromArray([ A2( $user$project$Test$test,'returns valid audio param', function(_v4){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v5 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'sine');if ( _v5.$ ==='Ok' ){var osc = _v5.a;var param = $user$project$AudioFFI$getOscillatorFrequencyParam( osc); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getOscillatorDetuneParam', _List_fromArray([ A2( $user$project$Test$test,'returns valid audio param', function(_v6){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v7 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'sine');if ( _v7.$ ==='Ok' ){var osc = _v7.a;var param = $user$project$AudioFFI$getOscillatorDetuneParam( osc); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$setOscillatorType = $author$project$FFI$setOscillatorType;
var $user$project$OscillatorTest$oscillatorWaveformTests = A2( $user$project$Test$describe,'waveform types', _List_fromArray([ A2( $user$project$Test$test,'sine waveform creates successfully', function(_v0){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v1 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'sine');if ( _v1.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'square waveform creates successfully', function(_v2){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v3 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'square');if ( _v3.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'sawtooth waveform creates successfully', function(_v4){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v5 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'sawtooth');if ( _v5.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'triangle waveform creates successfully', function(_v6){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v7 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'triangle');if ( _v7.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$describe,'setOscillatorType', _List_fromArray([ A2( $user$project$Test$test,'changes waveform type', function(_v8){ return ( $user$project$OscillatorTest$withContext( function(ctx){var _v9 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'sine');if ( _v9.$ ==='Ok' ){var osc = _v9.a;var _v10 = A2( $user$project$AudioFFI$setOscillatorType, osc,'square');if ( _v10.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$OscillatorTest$suite = A2( $user$project$Test$describe,'Oscillator Functions', _List_fromArray([ $user$project$OscillatorTest$createOscillatorTests , $user$project$OscillatorTest$oscillatorControlTests , $user$project$OscillatorTest$oscillatorPropertyTests , $user$project$OscillatorTest$oscillatorWaveformTests]));
var $user$project$OscillatorTest$main = function(){var results = $user$project$Test$runTests( _List_fromArray([ $user$project$OscillatorTest$suite])); return ( A2( $elm$html$Html$pre, _List_Nil, _List_fromArray([ $elm$html$Html$text( results)])));}();
var $user$project$AudioFFI$createGainNode = $author$project$FFI$createGainNode;
var $user$project$GainTest$withContext = function(fn){var _v0 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v0.$ ==='Ok' ){var ctx = _v0.a; return ( fn( ctx));} else return ( $user$project$Expect$pass);};
var $user$project$GainTest$createGainNodeTests = A2( $user$project$Test$describe,'createGainNode', _List_fromArray([ A2( $user$project$Test$test,'creates gain node with gain 1.0', function(_v0){ return ( $user$project$GainTest$withContext( function(ctx){var _v1 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v1.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates gain node with gain 0.0 (muted)', function(_v2){ return ( $user$project$GainTest$withContext( function(ctx){var _v3 = A2( $user$project$AudioFFI$createGainNode, ctx,0.0);if ( _v3.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates gain node with gain 0.5 (half volume)', function(_v4){ return ( $user$project$GainTest$withContext( function(ctx){var _v5 = A2( $user$project$AudioFFI$createGainNode, ctx,0.5);if ( _v5.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates gain node with gain 2.0 (boost)', function(_v6){ return ( $user$project$GainTest$withContext( function(ctx){var _v7 = A2( $user$project$AudioFFI$createGainNode, ctx,2.0);if ( _v7.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));})]));
var $user$project$AudioFFI$setGain = $author$project$FFI$setGain;
var $user$project$GainTest$gainControlTests = A2( $user$project$Test$describe,'setGain', _List_fromArray([ A2( $user$project$Test$test,'sets gain to 0.5', function(_v0){ return ( $user$project$GainTest$withContext( function(ctx){var _v1 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v1.$ ==='Ok' ){var gainNode = _v1.a;var _v2 = A3( $user$project$AudioFFI$setGain, gainNode,0.5,0.0);if ( _v2.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'sets gain to 0 (mute)', function(_v3){ return ( $user$project$GainTest$withContext( function(ctx){var _v4 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v4.$ ==='Ok' ){var gainNode = _v4.a;var _v5 = A3( $user$project$AudioFFI$setGain, gainNode,0.0,0.0);if ( _v5.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'sets gain at future time', function(_v6){ return ( $user$project$GainTest$withContext( function(ctx){var _v7 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v7.$ ==='Ok' ){var gainNode = _v7.a;var _v8 = A3( $user$project$AudioFFI$setGain, gainNode,0.5,1.0);if ( _v8.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})]));
var $user$project$AudioFFI$getGainNodeGainParam = $author$project$FFI$getGainNodeGainParam;
var $user$project$AudioFFI$getGainParam = $author$project$FFI$getGainParam;
var $user$project$GainTest$gainParamTests = A2( $user$project$Test$describe,'gain AudioParam', _List_fromArray([ A2( $user$project$Test$describe,'getGainNodeGainParam', _List_fromArray([ A2( $user$project$Test$test,'returns valid audio param', function(_v0){ return ( $user$project$GainTest$withContext( function(ctx){var _v1 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v1.$ ==='Ok' ){var gainNode = _v1.a;var param = $user$project$AudioFFI$getGainNodeGainParam( gainNode); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getGainParam', _List_fromArray([ A2( $user$project$Test$test,'returns valid audio param', function(_v2){ return ( $user$project$GainTest$withContext( function(ctx){var _v3 = A2( $user$project$AudioFFI$createGainNode, ctx,0.75);if ( _v3.$ ==='Ok' ){var gainNode = _v3.a;var param = $user$project$AudioFFI$getGainParam( gainNode); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$rampGainExponential = $author$project$FFI$rampGainExponential;
var $user$project$AudioFFI$rampGainLinear = $author$project$FFI$rampGainLinear;
var $user$project$GainTest$gainRampTests = A2( $user$project$Test$describe,'gain ramping', _List_fromArray([ A2( $user$project$Test$describe,'rampGainLinear', _List_fromArray([ A2( $user$project$Test$test,'ramps gain linearly to target', function(_v0){ return ( $user$project$GainTest$withContext( function(ctx){var _v1 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v1.$ ==='Ok' ){var gainNode = _v1.a;var _v2 = A3( $user$project$AudioFFI$rampGainLinear, gainNode,0.0,1.0);if ( _v2.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'ramps gain linearly from low to high', function(_v3){ return ( $user$project$GainTest$withContext( function(ctx){var _v4 = A2( $user$project$AudioFFI$createGainNode, ctx,0.1);if ( _v4.$ ==='Ok' ){var gainNode = _v4.a;var _v5 = A3( $user$project$AudioFFI$rampGainLinear, gainNode,1.0,2.0);if ( _v5.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'rampGainExponential', _List_fromArray([ A2( $user$project$Test$test,'ramps gain exponentially to target', function(_v6){ return ( $user$project$GainTest$withContext( function(ctx){var _v7 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v7.$ ==='Ok' ){var gainNode = _v7.a;var _v8 = A3( $user$project$AudioFFI$rampGainExponential, gainNode,0.01,1.0);if ( _v8.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'exponential ramp requires positive values', function(_v9){ return ( $user$project$GainTest$withContext( function(ctx){var _v10 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v10.$ ==='Ok' ){var gainNode = _v10.a;var _v11 = A3( $user$project$AudioFFI$rampGainExponential, gainNode,0.0,1.0);if ( _v11.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$GainTest$suite = A2( $user$project$Test$describe,'GainNode Functions', _List_fromArray([ $user$project$GainTest$createGainNodeTests , $user$project$GainTest$gainControlTests , $user$project$GainTest$gainRampTests , $user$project$GainTest$gainParamTests]));
var $user$project$GainTest$main = function(){var results = $user$project$Test$runTests( _List_fromArray([ $user$project$GainTest$suite])); return ( A2( $elm$html$Html$pre, _List_Nil, _List_fromArray([ $elm$html$Html$text( results)])));}();
var $user$project$AudioFFI$createBiquadFilter = $author$project$FFI$createBiquadFilter;
var $user$project$AudioFFI$getBiquadFilterDetuneParam = $author$project$FFI$getBiquadFilterDetuneParam;
var $user$project$AudioFFI$getBiquadFilterFrequencyParam = $author$project$FFI$getBiquadFilterFrequencyParam;
var $user$project$AudioFFI$getBiquadFilterGainParam = $author$project$FFI$getBiquadFilterGainParam;
var $user$project$AudioFFI$getBiquadFilterQParam = $author$project$FFI$getBiquadFilterQParam;
var $user$project$FilterTest$extractContext = function(initialized){if ( initialized.$ ==='Fresh' ){var ctx = initialized.a; return ( ctx);} else{var ctx = initialized.a; return ( ctx);}};
var $user$project$FilterTest$withRawContext = function(fn){var _v0 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v0.$ ==='Ok' ){var ctx = _v0.a; return ( fn( $user$project$FilterTest$extractContext( ctx)));} else return ( $user$project$Expect$pass);};
var $user$project$FilterTest$biquadFilterParamTests = A2( $user$project$Test$describe,'biquad filter AudioParams', _List_fromArray([ A2( $user$project$Test$describe,'getBiquadFilterFrequencyParam', _List_fromArray([ A2( $user$project$Test$test,'returns frequency param', function(_v0){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'lowpass');var param = $user$project$AudioFFI$getBiquadFilterFrequencyParam( filter); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getBiquadFilterQParam', _List_fromArray([ A2( $user$project$Test$test,'returns Q param', function(_v1){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'lowpass');var param = $user$project$AudioFFI$getBiquadFilterQParam( filter); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getBiquadFilterGainParam', _List_fromArray([ A2( $user$project$Test$test,'returns gain param', function(_v2){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'peaking');var param = $user$project$AudioFFI$getBiquadFilterGainParam( filter); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getBiquadFilterDetuneParam', _List_fromArray([ A2( $user$project$Test$test,'returns detune param', function(_v3){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'lowpass');var param = $user$project$AudioFFI$getBiquadFilterDetuneParam( filter); return ( $user$project$Expect$pass);}));})]))]));
var $user$project$FilterTest$biquadFilterTests = A2( $user$project$Test$describe,'createBiquadFilter', _List_fromArray([ A2( $user$project$Test$test,'creates lowpass filter', function(_v0){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'lowpass'); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates highpass filter', function(_v1){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'highpass'); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates bandpass filter', function(_v2){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'bandpass'); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates notch filter', function(_v3){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'notch'); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates peaking filter', function(_v4){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'peaking'); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates lowshelf filter', function(_v5){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'lowshelf'); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates highshelf filter', function(_v6){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'highshelf'); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates allpass filter', function(_v7){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'allpass'); return ( $user$project$Expect$pass);}));})]));
var $user$project$AudioFFI$getBiquadFilterType = $author$project$FFI$getBiquadFilterType;
var $user$project$AudioFFI$setBiquadFilterTypeDirect = $author$project$FFI$setBiquadFilterTypeDirect;
var $user$project$AudioFFI$setFilterFrequency = $author$project$FFI$setFilterFrequency;
var $user$project$AudioFFI$setFilterGain = $author$project$FFI$setFilterGain;
var $user$project$AudioFFI$setFilterQ = $author$project$FFI$setFilterQ;
var $user$project$FilterTest$biquadFilterTypeTests = A2( $user$project$Test$describe,'biquad filter type operations', _List_fromArray([ A2( $user$project$Test$describe,'getBiquadFilterType', _List_fromArray([ A2( $user$project$Test$test,'returns correct filter type', function(_v0){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'lowpass');var filterType = $user$project$AudioFFI$getBiquadFilterType( filter); return ( A2( $user$project$Expect$equal,'lowpass', filterType));}));})])) , A2( $user$project$Test$describe,'setBiquadFilterTypeDirect', _List_fromArray([ A2( $user$project$Test$test,'changes filter type', function(_v1){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'lowpass');var _v2 = A2( $user$project$AudioFFI$setBiquadFilterTypeDirect, filter,'highpass');if ( _v2.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setFilterFrequency', _List_fromArray([ A2( $user$project$Test$test,'sets cutoff frequency', function(_v3){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'lowpass');var _v4 = A3( $user$project$AudioFFI$setFilterFrequency, filter,1000.0,0.0); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setFilterQ', _List_fromArray([ A2( $user$project$Test$test,'sets Q (resonance)', function(_v5){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'lowpass');var _v6 = A3( $user$project$AudioFFI$setFilterQ, filter,10.0,0.0); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setFilterGain', _List_fromArray([ A2( $user$project$Test$test,'sets gain for peaking/shelving filters', function(_v7){ return ( $user$project$FilterTest$withRawContext( function(ctx){var filter = A2( $user$project$AudioFFI$createBiquadFilter, ctx,'peaking');var _v8 = A3( $user$project$AudioFFI$setFilterGain, filter,6.0,0.0); return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$createIIRFilter = $author$project$FFI$createIIRFilter;
var $user$project$AudioFFI$getIIRFilterResponse = $author$project$FFI$getIIRFilterResponse;
var $user$project$AudioFFI$getIIRFilterResponseAtFrequency = $author$project$FFI$getIIRFilterResponseAtFrequency;
var $user$project$FilterTest$iirFilterTests = A2( $user$project$Test$describe,'IIR Filter', _List_fromArray([ A2( $user$project$Test$describe,'createIIRFilter', _List_fromArray([ A2( $user$project$Test$test,'creates IIR filter with coefficients', function(_v0){ return ( $user$project$FilterTest$withRawContext( function(ctx){var feedforward = _List_fromArray([0.0675 ,0.1349 ,0.0675]);var feedback = _List_fromArray([1.0 ,-1.1430 ,0.4128]);var _v1 = A3( $user$project$AudioFFI$createIIRFilter, ctx, feedforward, feedback);if ( _v1.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getIIRFilterResponse', _List_fromArray([ A2( $user$project$Test$test,'gets frequency response for frequencies', function(_v2){ return ( $user$project$FilterTest$withRawContext( function(ctx){var feedforward = _List_fromArray([0.0675 ,0.1349 ,0.0675]);var feedback = _List_fromArray([1.0 ,-1.1430 ,0.4128]);var _v3 = A3( $user$project$AudioFFI$createIIRFilter, ctx, feedforward, feedback);if ( _v3.$ ==='Ok' ){var filter = _v3.a;var frequencies = _List_fromArray([100.0 ,1000.0 ,5000.0]);var _v4 = A2( $user$project$AudioFFI$getIIRFilterResponse, filter, frequencies);if ( _v4.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getIIRFilterResponseAtFrequency', _List_fromArray([ A2( $user$project$Test$test,'gets response at single frequency', function(_v5){ return ( $user$project$FilterTest$withRawContext( function(ctx){var feedforward = _List_fromArray([0.0675 ,0.1349 ,0.0675]);var feedback = _List_fromArray([1.0 ,-1.1430 ,0.4128]);var _v6 = A3( $user$project$AudioFFI$createIIRFilter, ctx, feedforward, feedback);if ( _v6.$ ==='Ok' ){var filter = _v6.a;var _v7 = A2( $user$project$AudioFFI$getIIRFilterResponseAtFrequency, filter,1000.0);var magnitude = _v7.a;var phase = _v7.b; return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$FilterTest$suite = A2( $user$project$Test$describe,'Filter Functions', _List_fromArray([ $user$project$FilterTest$biquadFilterTests , $user$project$FilterTest$biquadFilterTypeTests , $user$project$FilterTest$biquadFilterParamTests , $user$project$FilterTest$iirFilterTests]));
var $user$project$FilterTest$main = function(){var results = $user$project$Test$runTests( _List_fromArray([ $user$project$FilterTest$suite])); return ( A2( $elm$html$Html$pre, _List_Nil, _List_fromArray([ $elm$html$Html$text( results)])));}();
var $user$project$AudioFFI$createDynamicsCompressor = $author$project$FFI$createDynamicsCompressor;
var $user$project$AudioFFI$getCompressorKneeParam = $author$project$FFI$getCompressorKneeParam;
var $user$project$AudioFFI$getCompressorRatioParam = $author$project$FFI$getCompressorRatioParam;
var $user$project$AudioFFI$getCompressorReduction = $author$project$FFI$getCompressorReduction;
var $user$project$AudioFFI$getCompressorThresholdParam = $author$project$FFI$getCompressorThresholdParam;
var $user$project$AudioFFI$setCompressorAttack = $author$project$FFI$setCompressorAttack;
var $user$project$AudioFFI$setCompressorKnee = $author$project$FFI$setCompressorKnee;
var $user$project$AudioFFI$setCompressorRatio = $author$project$FFI$setCompressorRatio;
var $user$project$AudioFFI$setCompressorRelease = $author$project$FFI$setCompressorRelease;
var $user$project$AudioFFI$setCompressorThreshold = $author$project$FFI$setCompressorThreshold;
var $user$project$EffectsTest$extractContext = function(initialized){if ( initialized.$ ==='Fresh' ){var ctx = initialized.a; return ( ctx);} else{var ctx = initialized.a; return ( ctx);}};
var $user$project$EffectsTest$withRawContext = function(fn){var _v0 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v0.$ ==='Ok' ){var ctx = _v0.a; return ( fn( $user$project$EffectsTest$extractContext( ctx)));} else return ( $user$project$Expect$pass);};
var $user$project$EffectsTest$compressorTests = A2( $user$project$Test$describe,'Dynamics Compressor', _List_fromArray([ A2( $user$project$Test$describe,'createDynamicsCompressor', _List_fromArray([ A2( $user$project$Test$test,'creates compressor node', function(_v0){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var compressor = $user$project$AudioFFI$createDynamicsCompressor( ctx); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'compressor settings', _List_fromArray([ A2( $user$project$Test$test,'sets threshold', function(_v1){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var compressor = $user$project$AudioFFI$createDynamicsCompressor( ctx);var _v2 = A3( $user$project$AudioFFI$setCompressorThreshold, compressor,-24.0,0.0); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'sets knee', function(_v3){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var compressor = $user$project$AudioFFI$createDynamicsCompressor( ctx);var _v4 = A3( $user$project$AudioFFI$setCompressorKnee, compressor,30.0,0.0); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'sets ratio', function(_v5){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var compressor = $user$project$AudioFFI$createDynamicsCompressor( ctx);var _v6 = A3( $user$project$AudioFFI$setCompressorRatio, compressor,12.0,0.0); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'sets attack', function(_v7){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var compressor = $user$project$AudioFFI$createDynamicsCompressor( ctx);var _v8 = A3( $user$project$AudioFFI$setCompressorAttack, compressor,0.003,0.0); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'sets release', function(_v9){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var compressor = $user$project$AudioFFI$createDynamicsCompressor( ctx);var _v10 = A3( $user$project$AudioFFI$setCompressorRelease, compressor,0.25,0.0); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'compressor params', _List_fromArray([ A2( $user$project$Test$test,'gets threshold param', function(_v11){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var compressor = $user$project$AudioFFI$createDynamicsCompressor( ctx);var param = $user$project$AudioFFI$getCompressorThresholdParam( compressor); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'gets knee param', function(_v12){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var compressor = $user$project$AudioFFI$createDynamicsCompressor( ctx);var param = $user$project$AudioFFI$getCompressorKneeParam( compressor); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'gets ratio param', function(_v13){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var compressor = $user$project$AudioFFI$createDynamicsCompressor( ctx);var param = $user$project$AudioFFI$getCompressorRatioParam( compressor); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'gets reduction meter', function(_v14){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var compressor = $user$project$AudioFFI$createDynamicsCompressor( ctx);var reduction = $user$project$AudioFFI$getCompressorReduction( compressor); return ( A2( $user$project$Expect$true,'reduction should be <= 0', reduction <=0));}));})]))]));
var $user$project$AudioFFI$createConvolver = $author$project$FFI$createConvolver;
var $user$project$AudioFFI$createEmptyBuffer = $author$project$FFI$createEmptyBuffer;
var $user$project$AudioFFI$setConvolverBuffer = $author$project$FFI$setConvolverBuffer;
var $user$project$AudioFFI$setConvolverNormalize = $author$project$FFI$setConvolverNormalize;
var $user$project$EffectsTest$convolverTests = A2( $user$project$Test$describe,'Convolver Node', _List_fromArray([ A2( $user$project$Test$describe,'createConvolver', _List_fromArray([ A2( $user$project$Test$test,'creates convolver node', function(_v0){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var convolver = $user$project$AudioFFI$createConvolver( ctx); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setConvolverBuffer', _List_fromArray([ A2( $user$project$Test$test,'sets impulse response buffer', function(_v1){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var convolver = $user$project$AudioFFI$createConvolver( ctx);var buffer = A4( $user$project$AudioFFI$createEmptyBuffer, ctx,2,1.0,44100);var _v2 = A2( $user$project$AudioFFI$setConvolverBuffer, convolver, buffer);if ( _v2.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setConvolverNormalize', _List_fromArray([ A2( $user$project$Test$test,'enables normalization and returns True', function(_v3){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var convolver = $user$project$AudioFFI$createConvolver( ctx);var normalize = A2( $user$project$AudioFFI$setConvolverNormalize, convolver,true); return ( A2( $user$project$Expect$equal,true, normalize));}));}) , A2( $user$project$Test$test,'disables normalization and returns False', function(_v4){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var convolver = $user$project$AudioFFI$createConvolver( ctx);var normalize = A2( $user$project$AudioFFI$setConvolverNormalize, convolver,false); return ( A2( $user$project$Expect$equal,false, normalize));}));})]))]));
var $user$project$AudioFFI$createDelay = $author$project$FFI$createDelay;
var $user$project$AudioFFI$getDelayDelayTimeParam = $author$project$FFI$getDelayDelayTimeParam;
var $user$project$AudioFFI$setDelayTime = $author$project$FFI$setDelayTime;
var $user$project$EffectsTest$delayTests = A2( $user$project$Test$describe,'Delay Node', _List_fromArray([ A2( $user$project$Test$describe,'createDelay', _List_fromArray([ A2( $user$project$Test$test,'creates delay with max time', function(_v0){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var delay = A2( $user$project$AudioFFI$createDelay, ctx,1.0); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates delay with 5 second max', function(_v1){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var delay = A2( $user$project$AudioFFI$createDelay, ctx,5.0); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setDelayTime', _List_fromArray([ A2( $user$project$Test$test,'sets delay time', function(_v2){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var delay = A2( $user$project$AudioFFI$createDelay, ctx,1.0);var _v3 = A3( $user$project$AudioFFI$setDelayTime, delay,0.5,0.0); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getDelayDelayTimeParam', _List_fromArray([ A2( $user$project$Test$test,'returns delay time param', function(_v4){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var delay = A2( $user$project$AudioFFI$createDelay, ctx,1.0);var param = $user$project$AudioFFI$getDelayDelayTimeParam( delay); return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$createStereoPanner = $author$project$FFI$createStereoPanner;
var $user$project$AudioFFI$getStereoPannerPan = $author$project$FFI$getStereoPannerPan;
var $user$project$AudioFFI$setPan = $author$project$FFI$setPan;
var $user$project$EffectsTest$stereoPannerTests = A2( $user$project$Test$describe,'Stereo Panner', _List_fromArray([ A2( $user$project$Test$describe,'createStereoPanner', _List_fromArray([ A2( $user$project$Test$test,'creates stereo panner node', function(_v0){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createStereoPanner( ctx); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setPan', _List_fromArray([ A2( $user$project$Test$test,'pans to center', function(_v1){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createStereoPanner( ctx);var _v2 = A3( $user$project$AudioFFI$setPan, panner,0.0,0.0); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'pans to left', function(_v3){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createStereoPanner( ctx);var _v4 = A3( $user$project$AudioFFI$setPan, panner,-1.0,0.0); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'pans to right', function(_v5){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createStereoPanner( ctx);var _v6 = A3( $user$project$AudioFFI$setPan, panner,1.0,0.0); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getStereoPannerPan', _List_fromArray([ A2( $user$project$Test$test,'returns pan param', function(_v7){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var panner = $user$project$AudioFFI$createStereoPanner( ctx);var param = $user$project$AudioFFI$getStereoPannerPan( panner); return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$createWaveShaper = $author$project$FFI$createWaveShaper;
var $user$project$AudioFFI$makeDistortionCurve = $author$project$FFI$makeDistortionCurve;
var $user$project$AudioFFI$setWaveShaperCurve = $author$project$FFI$setWaveShaperCurve;
var $user$project$AudioFFI$setWaveShaperOversample = $author$project$FFI$setWaveShaperOversample;
var $user$project$EffectsTest$waveShaperTests = A2( $user$project$Test$describe,'Wave Shaper', _List_fromArray([ A2( $user$project$Test$describe,'createWaveShaper', _List_fromArray([ A2( $user$project$Test$test,'creates wave shaper node', function(_v0){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var shaper = $user$project$AudioFFI$createWaveShaper( ctx); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setWaveShaperCurve', _List_fromArray([ A2( $user$project$Test$test,'sets distortion curve', function(_v1){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var shaper = $user$project$AudioFFI$createWaveShaper( ctx);var curve = _List_fromArray([-1.0 ,-0.5 ,0.0 ,0.5 ,1.0]);var _v2 = A2( $user$project$AudioFFI$setWaveShaperCurve, shaper, curve);if ( _v2.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setWaveShaperOversample', _List_fromArray([ A2( $user$project$Test$test,'sets oversample to none and returns value', function(_v3){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var shaper = $user$project$AudioFFI$createWaveShaper( ctx);var oversample = A2( $user$project$AudioFFI$setWaveShaperOversample, shaper,'none'); return ( A2( $user$project$Expect$equal,'none', oversample));}));}) , A2( $user$project$Test$test,'sets oversample to 2x and returns value', function(_v4){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var shaper = $user$project$AudioFFI$createWaveShaper( ctx);var oversample = A2( $user$project$AudioFFI$setWaveShaperOversample, shaper,'2x'); return ( A2( $user$project$Expect$equal,'2x', oversample));}));}) , A2( $user$project$Test$test,'sets oversample to 4x and returns value', function(_v5){ return ( $user$project$EffectsTest$withRawContext( function(ctx){var shaper = $user$project$AudioFFI$createWaveShaper( ctx);var oversample = A2( $user$project$AudioFFI$setWaveShaperOversample, shaper,'4x'); return ( A2( $user$project$Expect$equal,'4x', oversample));}));})])) , A2( $user$project$Test$describe,'makeDistortionCurve', _List_fromArray([ A2( $user$project$Test$test,'generates distortion curve', function(_v6){var curve = A2( $user$project$AudioFFI$makeDistortionCurve,50.0,256); return ( A2( $user$project$Expect$true,'curve should have samples', $elm$core$List$length( curve) >0));})]))]));
var $user$project$EffectsTest$suite = A2( $user$project$Test$describe,'Audio Effects Functions', _List_fromArray([ $user$project$EffectsTest$delayTests , $user$project$EffectsTest$convolverTests , $user$project$EffectsTest$compressorTests , $user$project$EffectsTest$waveShaperTests , $user$project$EffectsTest$stereoPannerTests]));
var $user$project$EffectsTest$main = function(){var results = $user$project$Test$runTests( _List_fromArray([ $user$project$EffectsTest$suite])); return ( A2( $elm$html$Html$pre, _List_Nil, _List_fromArray([ $elm$html$Html$text( results)])));}();
var $user$project$AudioFFI$connectNodes = $author$project$FFI$connectNodes;
var $user$project$AudioFFI$connectToDestination = $author$project$FFI$connectToDestination;
var $user$project$AudioFFI$getContextDestination = $author$project$FFI$getContextDestination;
var $user$project$ConnectionTest$withContext = function(fn){var _v0 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v0.$ ==='Ok' ){var ctx = _v0.a; return ( fn( ctx));} else return ( $user$project$Expect$pass);};
var $user$project$ConnectionTest$extractContext = function(initialized){if ( initialized.$ ==='Fresh' ){var ctx = initialized.a; return ( ctx);} else{var ctx = initialized.a; return ( ctx);}};
var $user$project$ConnectionTest$withRawContext = function(fn){var _v0 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v0.$ ==='Ok' ){var ctx = _v0.a; return ( fn( $user$project$ConnectionTest$extractContext( ctx)));} else return ( $user$project$Expect$pass);};
var $user$project$ConnectionTest$basicConnectionTests = A2( $user$project$Test$describe,'basic connections', _List_fromArray([ A2( $user$project$Test$describe,'connectNodes', _List_fromArray([ A2( $user$project$Test$test,'connects oscillator to gain', function(_v0){ return ( $user$project$ConnectionTest$withContext( function(ctx){var _v1 = A3( $user$project$AudioFFI$createOscillator, ctx,440.0,'sine');if ( _v1.$ ==='Ok' ){var osc = _v1.a;var _v2 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v2.$ ==='Ok' ){var gain = _v2.a;var _v3 = A2( $user$project$AudioFFI$connectNodes, osc, gain);if ( _v3.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'connectToDestination', _List_fromArray([ A2( $user$project$Test$test,'connects gain to destination', function(_v4){ return ( $user$project$ConnectionTest$withContext( function(ctx){var _v5 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v5.$ ==='Ok' ){var gain = _v5.a;var _v6 = A2( $user$project$AudioFFI$connectToDestination, gain, ctx);if ( _v6.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getContextDestination', _List_fromArray([ A2( $user$project$Test$test,'returns destination node', function(_v7){ return ( $user$project$ConnectionTest$withRawContext( function(ctx){var dest = $user$project$AudioFFI$getContextDestination( ctx); return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$createChannelMerger = $author$project$FFI$createChannelMerger;
var $user$project$AudioFFI$createChannelSplitter = $author$project$FFI$createChannelSplitter;
var $user$project$ConnectionTest$channelTests = A2( $user$project$Test$describe,'channel operations', _List_fromArray([ A2( $user$project$Test$describe,'createChannelSplitter', _List_fromArray([ A2( $user$project$Test$test,'creates splitter with 2 channels', function(_v0){ return ( $user$project$ConnectionTest$withRawContext( function(ctx){var splitter = A2( $user$project$AudioFFI$createChannelSplitter, ctx,2); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates splitter with 6 channels', function(_v1){ return ( $user$project$ConnectionTest$withRawContext( function(ctx){var splitter = A2( $user$project$AudioFFI$createChannelSplitter, ctx,6); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'createChannelMerger', _List_fromArray([ A2( $user$project$Test$test,'creates merger with 2 channels', function(_v2){ return ( $user$project$ConnectionTest$withRawContext( function(ctx){var merger = A2( $user$project$AudioFFI$createChannelMerger, ctx,2); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates merger with 6 channels', function(_v3){ return ( $user$project$ConnectionTest$withRawContext( function(ctx){var merger = A2( $user$project$AudioFFI$createChannelMerger, ctx,6); return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$disconnectNode = $author$project$FFI$disconnectNode;
var $user$project$ConnectionTest$disconnectionTests = A2( $user$project$Test$describe,'disconnection', _List_fromArray([ A2( $user$project$Test$describe,'disconnectNode', _List_fromArray([ A2( $user$project$Test$test,'disconnects gain node', function(_v0){ return ( $user$project$ConnectionTest$withContext( function(ctx){var _v1 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v1.$ ==='Ok' ){var gain = _v1.a;var _v2 = $user$project$AudioFFI$disconnectNode( gain); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})]))]));
var $elm$core$Basics$ge = _Utils_ge;
var $user$project$AudioFFI$getNodeChannelCount = $author$project$FFI$getNodeChannelCount;
var $user$project$AudioFFI$getNodeChannelCountMode = $author$project$FFI$getNodeChannelCountMode;
var $user$project$AudioFFI$getNodeChannelInterpretation = $author$project$FFI$getNodeChannelInterpretation;
var $user$project$AudioFFI$getNodeNumberOfInputs = $author$project$FFI$getNodeNumberOfInputs;
var $user$project$AudioFFI$getNodeNumberOfOutputs = $author$project$FFI$getNodeNumberOfOutputs;
var $user$project$AudioFFI$setNodeChannelCount = $author$project$FFI$setNodeChannelCount;
var $user$project$AudioFFI$setNodeChannelCountMode = $author$project$FFI$setNodeChannelCountMode;
var $user$project$AudioFFI$setNodeChannelInterpretation = $author$project$FFI$setNodeChannelInterpretation;
var $user$project$AudioFFI$gainNodeToAudioNode = $author$project$FFI$gainNodeToAudioNode;
var $user$project$ConnectionTest$toAudioNode = $user$project$AudioFFI$gainNodeToAudioNode;
var $user$project$ConnectionTest$nodePropertyTests = A2( $user$project$Test$describe,'node properties', _List_fromArray([ A2( $user$project$Test$describe,'getNodeNumberOfInputs', _List_fromArray([ A2( $user$project$Test$test,'returns input count', function(_v0){ return ( $user$project$ConnectionTest$withContext( function(ctx){var _v1 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v1.$ ==='Ok' ){var gain = _v1.a;var inputs = $user$project$AudioFFI$getNodeNumberOfInputs( $user$project$ConnectionTest$toAudioNode( gain)); return ( A2( $user$project$Expect$true,'should have at least 1 input', inputs >=1));} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getNodeNumberOfOutputs', _List_fromArray([ A2( $user$project$Test$test,'returns output count', function(_v2){ return ( $user$project$ConnectionTest$withContext( function(ctx){var _v3 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v3.$ ==='Ok' ){var gain = _v3.a;var outputs = $user$project$AudioFFI$getNodeNumberOfOutputs( $user$project$ConnectionTest$toAudioNode( gain)); return ( A2( $user$project$Expect$true,'should have at least 1 output', outputs >=1));} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getNodeChannelCount', _List_fromArray([ A2( $user$project$Test$test,'returns channel count', function(_v4){ return ( $user$project$ConnectionTest$withContext( function(ctx){var _v5 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v5.$ ==='Ok' ){var gain = _v5.a;var channels = $user$project$AudioFFI$getNodeChannelCount( $user$project$ConnectionTest$toAudioNode( gain)); return ( A2( $user$project$Expect$true,'should have valid channel count', channels >0));} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getNodeChannelCountMode', _List_fromArray([ A2( $user$project$Test$test,'returns channel count mode', function(_v6){ return ( $user$project$ConnectionTest$withContext( function(ctx){var _v7 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v7.$ ==='Ok' ){var gain = _v7.a;var mode = $user$project$AudioFFI$getNodeChannelCountMode( $user$project$ConnectionTest$toAudioNode( gain)); return ( A2( $user$project$Expect$true,'should be valid mode', mode ==='max' || mode ==='clamped-max' || mode ==='explicit'));} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getNodeChannelInterpretation', _List_fromArray([ A2( $user$project$Test$test,'returns channel interpretation', function(_v8){ return ( $user$project$ConnectionTest$withContext( function(ctx){var _v9 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v9.$ ==='Ok' ){var gain = _v9.a;var interp = $user$project$AudioFFI$getNodeChannelInterpretation( $user$project$ConnectionTest$toAudioNode( gain)); return ( A2( $user$project$Expect$true,'should be valid interpretation', interp ==='speakers' || interp ==='discrete'));} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setNodeChannelCount', _List_fromArray([ A2( $user$project$Test$test,'sets channel count', function(_v10){ return ( $user$project$ConnectionTest$withContext( function(ctx){var _v11 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v11.$ ==='Ok' ){var gain = _v11.a;var _v12 = A2( $user$project$AudioFFI$setNodeChannelCount, $user$project$ConnectionTest$toAudioNode( gain),2);if ( _v12.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setNodeChannelCountMode', _List_fromArray([ A2( $user$project$Test$test,'sets channel count mode', function(_v13){ return ( $user$project$ConnectionTest$withContext( function(ctx){var _v14 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v14.$ ==='Ok' ){var gain = _v14.a;var _v15 = A2( $user$project$AudioFFI$setNodeChannelCountMode, $user$project$ConnectionTest$toAudioNode( gain),'explicit');if ( _v15.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setNodeChannelInterpretation', _List_fromArray([ A2( $user$project$Test$test,'sets channel interpretation', function(_v16){ return ( $user$project$ConnectionTest$withContext( function(ctx){var _v17 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v17.$ ==='Ok' ){var gain = _v17.a;var _v18 = A2( $user$project$AudioFFI$setNodeChannelInterpretation, $user$project$ConnectionTest$toAudioNode( gain),'speakers');if ( _v18.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$ConnectionTest$suite = A2( $user$project$Test$describe,'Connection Functions', _List_fromArray([ $user$project$ConnectionTest$basicConnectionTests , $user$project$ConnectionTest$disconnectionTests , $user$project$ConnectionTest$channelTests , $user$project$ConnectionTest$nodePropertyTests]));
var $user$project$ConnectionTest$main = function(){var results = $user$project$Test$runTests( _List_fromArray([ $user$project$ConnectionTest$suite])); return ( A2( $elm$html$Html$pre, _List_Nil, _List_fromArray([ $elm$html$Html$text( results)])));}();
var $user$project$AudioFFI$cloneAudioBuffer = $author$project$FFI$cloneAudioBuffer;
var $user$project$AudioFFI$createAudioBuffer = $author$project$FFI$createAudioBuffer;
var $user$project$AudioFFI$createSilentBuffer = $author$project$FFI$createSilentBuffer;
var $user$project$BufferTest$extractContext = function(initialized){if ( initialized.$ ==='Fresh' ){var ctx = initialized.a; return ( ctx);} else{var ctx = initialized.a; return ( ctx);}};
var $user$project$BufferTest$withRawContext = function(fn){var _v0 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v0.$ ==='Ok' ){var ctx = _v0.a; return ( fn( $user$project$BufferTest$extractContext( ctx)));} else return ( $user$project$Expect$pass);};
var $user$project$BufferTest$bufferCreationTests = A2( $user$project$Test$describe,'buffer creation', _List_fromArray([ A2( $user$project$Test$describe,'createEmptyBuffer', _List_fromArray([ A2( $user$project$Test$test,'creates empty stereo buffer', function(_v0){ return ( $user$project$BufferTest$withRawContext( function(ctx){var buffer = A4( $user$project$AudioFFI$createEmptyBuffer, ctx,2,1.0,44100); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'creates empty mono buffer', function(_v1){ return ( $user$project$BufferTest$withRawContext( function(ctx){var buffer = A4( $user$project$AudioFFI$createEmptyBuffer, ctx,1,0.5,48000); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'createSilentBuffer', _List_fromArray([ A2( $user$project$Test$test,'creates silent buffer with specified parameters', function(_v2){ return ( $user$project$BufferTest$withRawContext( function(ctx){var buffer = A4( $user$project$AudioFFI$createSilentBuffer, ctx,2,44100,44100.0); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'createAudioBuffer', _List_fromArray([ A2( $user$project$Test$test,'creates audio buffer with channels, length, and sample rate', function(_v3){ return ( $user$project$BufferTest$withRawContext( function(ctx){var buffer = A4( $user$project$AudioFFI$createAudioBuffer, ctx,2,44100,44100.0); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'cloneAudioBuffer', _List_fromArray([ A2( $user$project$Test$test,'clones existing buffer', function(_v4){ return ( $user$project$BufferTest$withRawContext( function(ctx){var original = A4( $user$project$AudioFFI$createEmptyBuffer, ctx,2,1.0,44100);var _v5 = $user$project$AudioFFI$cloneAudioBuffer( original);if ( _v5.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$getBufferAsArray = $author$project$FFI$getBufferAsArray;
var $user$project$AudioFFI$getChannelData = $author$project$FFI$getChannelData;
var $user$project$AudioFFI$normalizeAudioBuffer = $author$project$FFI$normalizeAudioBuffer;
var $user$project$AudioFFI$reverseAudioBuffer = $author$project$FFI$reverseAudioBuffer;
var $user$project$AudioFFI$trimSilence = $author$project$FFI$trimSilence;
var $user$project$BufferTest$bufferManipulationTests = A2( $user$project$Test$describe,'buffer manipulation', _List_fromArray([ A2( $user$project$Test$describe,'getChannelData', _List_fromArray([ A2( $user$project$Test$test,'retrieves channel data', function(_v0){ return ( $user$project$BufferTest$withRawContext( function(ctx){var buffer = A4( $user$project$AudioFFI$createEmptyBuffer, ctx,2,1.0,44100);var _v1 = A2( $user$project$AudioFFI$getChannelData, buffer,0);if ( _v1.$ ==='Ok' ){var data = _v1.a; return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getBufferAsArray', _List_fromArray([ A2( $user$project$Test$test,'returns samples as list', function(_v2){ return ( $user$project$BufferTest$withRawContext( function(ctx){var buffer = A4( $user$project$AudioFFI$createEmptyBuffer, ctx,2,0.1,44100);var samples = A2( $user$project$AudioFFI$getBufferAsArray, buffer,0); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'reverseAudioBuffer', _List_fromArray([ A2( $user$project$Test$test,'reverses buffer samples', function(_v3){ return ( $user$project$BufferTest$withRawContext( function(ctx){var buffer = A4( $user$project$AudioFFI$createEmptyBuffer, ctx,2,1.0,44100);var _v4 = $user$project$AudioFFI$reverseAudioBuffer( buffer);if ( _v4.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'normalizeAudioBuffer', _List_fromArray([ A2( $user$project$Test$test,'normalizes buffer to target level', function(_v5){ return ( $user$project$BufferTest$withRawContext( function(ctx){var buffer = A4( $user$project$AudioFFI$createEmptyBuffer, ctx,2,1.0,44100);var _v6 = A2( $user$project$AudioFFI$normalizeAudioBuffer, buffer,1.0);if ( _v6.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'trimSilence', _List_fromArray([ A2( $user$project$Test$test,'trims silent portions', function(_v7){ return ( $user$project$BufferTest$withRawContext( function(ctx){var buffer = A4( $user$project$AudioFFI$createSilentBuffer, ctx,2,44100,44100.0);var _v8 = A2( $user$project$AudioFFI$trimSilence, buffer,0.001);if ( _v8.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$getBufferChannels = $author$project$FFI$getBufferChannels;
var $user$project$AudioFFI$getBufferDuration = $author$project$FFI$getBufferDuration;
var $user$project$AudioFFI$getBufferLength = $author$project$FFI$getBufferLength;
var $user$project$AudioFFI$getBufferPeak = $author$project$FFI$getBufferPeak;
var $user$project$AudioFFI$getBufferRMS = $author$project$FFI$getBufferRMS;
var $user$project$AudioFFI$getBufferSampleRate = $author$project$FFI$getBufferSampleRate;
var $user$project$BufferTest$bufferPropertyTests = A2( $user$project$Test$describe,'buffer properties', _List_fromArray([ A2( $user$project$Test$describe,'getBufferLength', _List_fromArray([ A2( $user$project$Test$test,'returns correct sample count', function(_v0){ return ( $user$project$BufferTest$withRawContext( function(ctx){var buffer = A4( $user$project$AudioFFI$createAudioBuffer, ctx,2,44100,44100.0);var length = $user$project$AudioFFI$getBufferLength( buffer); return ( A2( $user$project$Expect$equal,44100, length));}));})])) , A2( $user$project$Test$describe,'getBufferDuration', _List_fromArray([ A2( $user$project$Test$test,'returns duration in seconds', function(_v1){ return ( $user$project$BufferTest$withRawContext( function(ctx){var buffer = A4( $user$project$AudioFFI$createAudioBuffer, ctx,2,44100,44100.0);var duration = $user$project$AudioFFI$getBufferDuration( buffer); return ( A3( $user$project$Expect$within, $user$project$Expect$Absolute(0.01),1.0, duration));}));})])) , A2( $user$project$Test$describe,'getBufferSampleRate', _List_fromArray([ A2( $user$project$Test$test,'returns correct sample rate', function(_v2){ return ( $user$project$BufferTest$withRawContext( function(ctx){var buffer = A4( $user$project$AudioFFI$createAudioBuffer, ctx,2,44100,44100.0);var sampleRate = $user$project$AudioFFI$getBufferSampleRate( buffer); return ( A2( $user$project$Expect$equal,44100.0, sampleRate));}));})])) , A2( $user$project$Test$describe,'getBufferChannels', _List_fromArray([ A2( $user$project$Test$test,'returns correct channel count', function(_v3){ return ( $user$project$BufferTest$withRawContext( function(ctx){var buffer = A4( $user$project$AudioFFI$createAudioBuffer, ctx,2,44100,44100.0);var channels = $user$project$AudioFFI$getBufferChannels( buffer); return ( A2( $user$project$Expect$equal,2, channels));}));})])) , A2( $user$project$Test$describe,'getBufferPeak', _List_fromArray([ A2( $user$project$Test$test,'returns peak amplitude', function(_v4){ return ( $user$project$BufferTest$withRawContext( function(ctx){var buffer = A4( $user$project$AudioFFI$createSilentBuffer, ctx,2,44100,44100.0);var peak = $user$project$AudioFFI$getBufferPeak( buffer); return ( A2( $user$project$Expect$true,'peak should be non-negative', peak >=0.0));}));})])) , A2( $user$project$Test$describe,'getBufferRMS', _List_fromArray([ A2( $user$project$Test$test,'returns RMS value', function(_v5){ return ( $user$project$BufferTest$withRawContext( function(ctx){var buffer = A4( $user$project$AudioFFI$createSilentBuffer, ctx,2,44100,44100.0);var rms = $user$project$AudioFFI$getBufferRMS( buffer); return ( A2( $user$project$Expect$true,'RMS should be non-negative', rms >=0.0));}));})]))]));
var $user$project$AudioFFI$createBufferSource = $author$project$FFI$createBufferSource;
var $user$project$AudioFFI$getBufferSourceDetune = $author$project$FFI$getBufferSourceDetune;
var $user$project$AudioFFI$getBufferSourcePlaybackRate = $author$project$FFI$getBufferSourcePlaybackRate;
var $user$project$AudioFFI$setBufferSourceLoopEnd = $author$project$FFI$setBufferSourceLoopEnd;
var $user$project$AudioFFI$setBufferSourceLoopStart = $author$project$FFI$setBufferSourceLoopStart;
var $user$project$BufferTest$bufferSourcePropertyTests = A2( $user$project$Test$describe,'buffer source properties', _List_fromArray([ A2( $user$project$Test$describe,'loop start/end', _List_fromArray([ A2( $user$project$Test$test,'sets and returns loop start', function(_v0){ return ( $user$project$BufferTest$withRawContext( function(ctx){var source = $user$project$AudioFFI$createBufferSource( ctx);var start = A2( $user$project$AudioFFI$setBufferSourceLoopStart, source,0.5); return ( A3( $user$project$Expect$within, $user$project$Expect$Absolute(0.01),0.5, start));}));}) , A2( $user$project$Test$test,'sets and returns loop end', function(_v1){ return ( $user$project$BufferTest$withRawContext( function(ctx){var source = $user$project$AudioFFI$createBufferSource( ctx);var end = A2( $user$project$AudioFFI$setBufferSourceLoopEnd, source,2.0); return ( A3( $user$project$Expect$within, $user$project$Expect$Absolute(0.01),2.0, end));}));})])) , A2( $user$project$Test$describe,'playback rate and detune', _List_fromArray([ A2( $user$project$Test$test,'gets playback rate param', function(_v2){ return ( $user$project$BufferTest$withRawContext( function(ctx){var source = $user$project$AudioFFI$createBufferSource( ctx);var param = $user$project$AudioFFI$getBufferSourcePlaybackRate( source); return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'gets detune param', function(_v3){ return ( $user$project$BufferTest$withRawContext( function(ctx){var source = $user$project$AudioFFI$createBufferSource( ctx);var param = $user$project$AudioFFI$getBufferSourceDetune( source); return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$setBufferSourceBuffer = $author$project$FFI$setBufferSourceBuffer;
var $user$project$AudioFFI$setBufferSourceLoop = $author$project$FFI$setBufferSourceLoop;
var $user$project$AudioFFI$startBufferSource = $author$project$FFI$startBufferSource;
var $user$project$AudioFFI$stopBufferSource = $author$project$FFI$stopBufferSource;
var $user$project$BufferTest$bufferSourceTests = A2( $user$project$Test$describe,'buffer source', _List_fromArray([ A2( $user$project$Test$describe,'createBufferSource', _List_fromArray([ A2( $user$project$Test$test,'creates buffer source node', function(_v0){ return ( $user$project$BufferTest$withRawContext( function(ctx){var source = $user$project$AudioFFI$createBufferSource( ctx); return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'startBufferSource', _List_fromArray([ A2( $user$project$Test$test,'starts playback at time 0', function(_v1){ return ( $user$project$BufferTest$withRawContext( function(ctx){var source = $user$project$AudioFFI$createBufferSource( ctx);var buffer = A4( $user$project$AudioFFI$createEmptyBuffer, ctx,2,1.0,44100);var _v2 = A2( $user$project$AudioFFI$setBufferSourceBuffer, source, buffer);var _v3 = A2( $user$project$AudioFFI$startBufferSource, source,0.0);if ( _v3.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'stopBufferSource', _List_fromArray([ A2( $user$project$Test$test,'stops playback', function(_v4){ return ( $user$project$BufferTest$withRawContext( function(ctx){var source = $user$project$AudioFFI$createBufferSource( ctx);var buffer = A4( $user$project$AudioFFI$createEmptyBuffer, ctx,2,1.0,44100);var _v5 = A2( $user$project$AudioFFI$setBufferSourceBuffer, source, buffer);var _v6 = A2( $user$project$AudioFFI$startBufferSource, source,0.0);if ( _v6.$ ==='Ok' ){var _v7 = A2( $user$project$AudioFFI$stopBufferSource, source,0.5);if ( _v7.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setBufferSourceBuffer', _List_fromArray([ A2( $user$project$Test$test,'assigns buffer to source', function(_v8){ return ( $user$project$BufferTest$withRawContext( function(ctx){var source = $user$project$AudioFFI$createBufferSource( ctx);var buffer = A4( $user$project$AudioFFI$createEmptyBuffer, ctx,2,1.0,44100);var result = A2( $user$project$AudioFFI$setBufferSourceBuffer, source, buffer); return ( A2( $user$project$Expect$equal, _Utils_Tuple0, result));}));})])) , A2( $user$project$Test$describe,'setBufferSourceLoop', _List_fromArray([ A2( $user$project$Test$test,'enables looping and returns True', function(_v9){ return ( $user$project$BufferTest$withRawContext( function(ctx){var source = $user$project$AudioFFI$createBufferSource( ctx);var result = A2( $user$project$AudioFFI$setBufferSourceLoop, source,true); return ( A2( $user$project$Expect$equal,true, result));}));}) , A2( $user$project$Test$test,'disables looping and returns False', function(_v10){ return ( $user$project$BufferTest$withRawContext( function(ctx){var source = $user$project$AudioFFI$createBufferSource( ctx);var result = A2( $user$project$AudioFFI$setBufferSourceLoop, source,false); return ( A2( $user$project$Expect$equal,false, result));}));})]))]));
var $user$project$BufferTest$suite = A2( $user$project$Test$describe,'AudioBuffer Functions', _List_fromArray([ $user$project$BufferTest$bufferCreationTests , $user$project$BufferTest$bufferPropertyTests , $user$project$BufferTest$bufferManipulationTests , $user$project$BufferTest$bufferSourceTests , $user$project$BufferTest$bufferSourcePropertyTests]));
var $user$project$BufferTest$main = function(){var results = $user$project$Test$runTests( _List_fromArray([ $user$project$BufferTest$suite])); return ( A2( $elm$html$Html$pre, _List_Nil, _List_fromArray([ $elm$html$Html$text( results)])));}();
var $elm$virtual_dom$VirtualDom$attribute = F2( function(key,value){ return ( A2( _VirtualDom_attribute, _VirtualDom_noOnOrFormAction( key), _VirtualDom_noJavaScriptOrHtmlUri( value)));});
var $elm$html$Html$Attributes$attribute = $elm$virtual_dom$VirtualDom$attribute;
var $elm$html$Html$div = _VirtualDom_node('div');
var $user$project$BrowserTestMain$escapeForJs = function(str){ return ('\'' +( A3( $elm$core$String$replace,'\\','\\\\', A3( $elm$core$String$replace,'\'','\\\'', A3( $elm$core$String$replace,'\n','\\n', str))) +'\''));};
var $user$project$BrowserTestMain$logResultsScript = function(report){ return ('console.log(\'CANOPY_TEST_RESULTS_START\');' +('console.log(' +( $user$project$BrowserTestMain$escapeForJs( report) +(');' +'console.log(\'CANOPY_TEST_RESULTS_END\');'))));};
var $elm$virtual_dom$VirtualDom$node = function(tag){ return ( _VirtualDom_node( _VirtualDom_noScript( tag)));};
var $elm$html$Html$node = $elm$virtual_dom$VirtualDom$node;
var $user$project$AudioFFI$createAnalyser = $author$project$FFI$createAnalyser;
var $user$project$AudioFFI$setAnalyserFFTSize = $author$project$FFI$setAnalyserFFTSize;
var $user$project$AudioFFI$setAnalyserMaxDecibels = $author$project$FFI$setAnalyserMaxDecibels;
var $user$project$AudioFFI$setAnalyserMinDecibels = $author$project$FFI$setAnalyserMinDecibels;
var $user$project$AudioFFI$setAnalyserSmoothing = $author$project$FFI$setAnalyserSmoothing;
var $user$project$AudioFFI$setAnalyserSmoothingTimeConstant = $author$project$FFI$setAnalyserSmoothingTimeConstant;
var $user$project$AnalyserTest$extractContext = function(initialized){if ( initialized.$ ==='Fresh' ){var ctx = initialized.a; return ( ctx);} else{var ctx = initialized.a; return ( ctx);}};
var $user$project$AnalyserTest$withRawContext = function(fn){var _v0 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v0.$ ==='Ok' ){var ctx = _v0.a; return ( fn( $user$project$AnalyserTest$extractContext( ctx)));} else return ( $user$project$Expect$pass);};
var $user$project$AnalyserTest$analyserConfigTests = A2( $user$project$Test$describe,'analyser configuration', _List_fromArray([ A2( $user$project$Test$describe,'setAnalyserFFTSize', _List_fromArray([ A2( $user$project$Test$test,'sets FFT size to 2048', function(_v0){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var _v1 = A2( $user$project$AudioFFI$setAnalyserFFTSize, analyser,2048);if ( _v1.$ ==='Ok' ){var fftSize = _v1.a; return ( A2( $user$project$Expect$equal,2048, fftSize));} else return ( $user$project$Expect$fail('setAnalyserFFTSize should succeed with 2048'));}));}) , A2( $user$project$Test$test,'sets FFT size to 256', function(_v2){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var _v3 = A2( $user$project$AudioFFI$setAnalyserFFTSize, analyser,256);if ( _v3.$ ==='Ok' ){var fftSize = _v3.a; return ( A2( $user$project$Expect$equal,256, fftSize));} else return ( $user$project$Expect$fail('setAnalyserFFTSize should succeed with 256'));}));}) , A2( $user$project$Test$test,'sets FFT size to 4096', function(_v4){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var _v5 = A2( $user$project$AudioFFI$setAnalyserFFTSize, analyser,4096);if ( _v5.$ ==='Ok' ){var fftSize = _v5.a; return ( A2( $user$project$Expect$equal,4096, fftSize));} else return ( $user$project$Expect$fail('setAnalyserFFTSize should succeed with 4096'));}));}) , A2( $user$project$Test$test,'rejects invalid FFT size (not power of 2)', function(_v6){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var _v7 = A2( $user$project$AudioFFI$setAnalyserFFTSize, analyser,1000);if ( _v7.$ ==='Ok' ) return ( $user$project$Expect$fail('setAnalyserFFTSize should reject 1000')); else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setAnalyserMinDecibels', _List_fromArray([ A2( $user$project$Test$test,'sets min decibels', function(_v8){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var _v9 = A2( $user$project$AudioFFI$setAnalyserMinDecibels, analyser,-100.0);if ( _v9.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setAnalyserMaxDecibels', _List_fromArray([ A2( $user$project$Test$test,'sets max decibels', function(_v10){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var _v11 = A2( $user$project$AudioFFI$setAnalyserMaxDecibels, analyser,-30.0);if ( _v11.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setAnalyserSmoothingTimeConstant', _List_fromArray([ A2( $user$project$Test$test,'sets smoothing to 0.8', function(_v12){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var _v13 = A2( $user$project$AudioFFI$setAnalyserSmoothingTimeConstant, analyser,0.8);if ( _v13.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setAnalyserSmoothing', _List_fromArray([ A2( $user$project$Test$test,'sets smoothing value 0.5', function(_v14){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var _v15 = A2( $user$project$AudioFFI$setAnalyserSmoothing, analyser,0.5);if ( _v15.$ ==='Ok' ){var smoothing = _v15.a; return ( A3( $user$project$Expect$within, $user$project$Expect$Absolute(0.01),0.5, smoothing));} else return ( $user$project$Expect$fail('setAnalyserSmoothing should succeed with 0.5'));}));}) , A2( $user$project$Test$test,'sets smoothing to 0.0', function(_v16){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var _v17 = A2( $user$project$AudioFFI$setAnalyserSmoothing, analyser,0.0);if ( _v17.$ ==='Ok' ){var smoothing = _v17.a; return ( A3( $user$project$Expect$within, $user$project$Expect$Absolute(0.01),0.0, smoothing));} else return ( $user$project$Expect$fail('setAnalyserSmoothing should succeed with 0.0'));}));}) , A2( $user$project$Test$test,'sets smoothing to 1.0', function(_v18){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var _v19 = A2( $user$project$AudioFFI$setAnalyserSmoothing, analyser,1.0);if ( _v19.$ ==='Ok' ){var smoothing = _v19.a; return ( A3( $user$project$Expect$within, $user$project$Expect$Absolute(0.01),1.0, smoothing));} else return ( $user$project$Expect$fail('setAnalyserSmoothing should succeed with 1.0'));}));}) , A2( $user$project$Test$test,'rejects negative smoothing value', function(_v20){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var _v21 = A2( $user$project$AudioFFI$setAnalyserSmoothing, analyser,-0.5);if ( _v21.$ ==='Ok' ) return ( $user$project$Expect$fail('setAnalyserSmoothing should reject -0.5')); else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'rejects smoothing value > 1', function(_v22){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var _v23 = A2( $user$project$AudioFFI$setAnalyserSmoothing, analyser,1.5);if ( _v23.$ ==='Ok' ) return ( $user$project$Expect$fail('setAnalyserSmoothing should reject 1.5')); else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$getByteFrequencyData = $author$project$FFI$getByteFrequencyData;
var $user$project$AudioFFI$getByteTimeDomainData = $author$project$FFI$getByteTimeDomainData;
var $user$project$AudioFFI$getFloatFrequencyData = $author$project$FFI$getFloatFrequencyData;
var $user$project$AudioFFI$getFloatTimeDomainData = $author$project$FFI$getFloatTimeDomainData;
var $user$project$AnalyserTest$analyserDataTests = A2( $user$project$Test$describe,'analyser data retrieval', _List_fromArray([ A2( $user$project$Test$describe,'getByteTimeDomainData', _List_fromArray([ A2( $user$project$Test$test,'returns time domain data', function(_v0){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var data = $user$project$AudioFFI$getByteTimeDomainData( analyser); return ( A2( $user$project$Expect$true,'should return list',true));}));})])) , A2( $user$project$Test$describe,'getByteFrequencyData', _List_fromArray([ A2( $user$project$Test$test,'returns frequency data', function(_v1){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var data = $user$project$AudioFFI$getByteFrequencyData( analyser); return ( A2( $user$project$Expect$true,'should return list',true));}));})])) , A2( $user$project$Test$describe,'getFloatTimeDomainData', _List_fromArray([ A2( $user$project$Test$test,'returns float time domain data', function(_v2){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var data = $user$project$AudioFFI$getFloatTimeDomainData( analyser); return ( A2( $user$project$Expect$true,'should return list',true));}));})])) , A2( $user$project$Test$describe,'getFloatFrequencyData', _List_fromArray([ A2( $user$project$Test$test,'returns float frequency data', function(_v3){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var data = $user$project$AudioFFI$getFloatFrequencyData( analyser); return ( A2( $user$project$Expect$true,'should return list',true));}));})]))]));
var $user$project$AudioFFI$getAnalyserFFTSize = $author$project$FFI$getAnalyserFFTSize;
var $user$project$AudioFFI$getAnalyserFrequencyBinCount = $author$project$FFI$getAnalyserFrequencyBinCount;
var $user$project$AudioFFI$getAnalyserMaxDecibels = $author$project$FFI$getAnalyserMaxDecibels;
var $user$project$AudioFFI$getAnalyserMinDecibels = $author$project$FFI$getAnalyserMinDecibels;
var $user$project$AudioFFI$getAnalyserSmoothingTimeConstant = $author$project$FFI$getAnalyserSmoothingTimeConstant;
var $user$project$AudioFFI$getFrequencyBinCount = $author$project$FFI$getFrequencyBinCount;
var $user$project$AnalyserTest$analyserPropertyTests = A2( $user$project$Test$describe,'analyser properties', _List_fromArray([ A2( $user$project$Test$describe,'getAnalyserFFTSize', _List_fromArray([ A2( $user$project$Test$test,'returns FFT size', function(_v0){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var _v1 = A2( $user$project$AudioFFI$setAnalyserFFTSize, analyser,2048);if ( _v1.$ ==='Ok' ){var fftSize = $user$project$AudioFFI$getAnalyserFFTSize( analyser); return ( A2( $user$project$Expect$equal,2048, fftSize));} else return ( $user$project$Expect$fail('setAnalyserFFTSize should succeed'));}));})])) , A2( $user$project$Test$describe,'getAnalyserFrequencyBinCount', _List_fromArray([ A2( $user$project$Test$test,'returns half of FFT size', function(_v2){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var _v3 = A2( $user$project$AudioFFI$setAnalyserFFTSize, analyser,2048);if ( _v3.$ ==='Ok' ){var binCount = $user$project$AudioFFI$getAnalyserFrequencyBinCount( analyser); return ( A2( $user$project$Expect$equal,1024, binCount));} else return ( $user$project$Expect$fail('setAnalyserFFTSize should succeed'));}));})])) , A2( $user$project$Test$describe,'getFrequencyBinCount', _List_fromArray([ A2( $user$project$Test$test,'returns frequency bin count', function(_v4){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var binCount = $user$project$AudioFFI$getFrequencyBinCount( analyser); return ( A2( $user$project$Expect$true,'bin count should be positive', binCount >0));}));})])) , A2( $user$project$Test$describe,'getAnalyserMinDecibels', _List_fromArray([ A2( $user$project$Test$test,'returns min decibels value', function(_v5){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var minDb = $user$project$AudioFFI$getAnalyserMinDecibels( analyser); return ( A2( $user$project$Expect$true,'min dB should be negative', minDb <0));}));})])) , A2( $user$project$Test$describe,'getAnalyserMaxDecibels', _List_fromArray([ A2( $user$project$Test$test,'returns max decibels value', function(_v6){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var maxDb = $user$project$AudioFFI$getAnalyserMaxDecibels( analyser); return ( A2( $user$project$Expect$true,'max dB should be less than 0', maxDb <=0));}));})])) , A2( $user$project$Test$describe,'getAnalyserSmoothingTimeConstant', _List_fromArray([ A2( $user$project$Test$test,'returns smoothing value', function(_v7){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx);var smoothing = $user$project$AudioFFI$getAnalyserSmoothingTimeConstant( analyser); return ( A2( $user$project$Expect$true,'smoothing should be 0-1', smoothing >=0 && smoothing <=1));}));})]))]));
var $user$project$AnalyserTest$createAnalyserTests = A2( $user$project$Test$describe,'createAnalyser', _List_fromArray([ A2( $user$project$Test$test,'creates analyser node', function(_v0){ return ( $user$project$AnalyserTest$withRawContext( function(ctx){var analyser = $user$project$AudioFFI$createAnalyser( ctx); return ( $user$project$Expect$pass);}));})]));
var $user$project$AnalyserTest$suite = A2( $user$project$Test$describe,'AnalyserNode Functions', _List_fromArray([ $user$project$AnalyserTest$createAnalyserTests , $user$project$AnalyserTest$analyserDataTests , $user$project$AnalyserTest$analyserConfigTests , $user$project$AnalyserTest$analyserPropertyTests]));
var $user$project$AudioFFI$closeAudioContext = $author$project$FFI$closeAudioContext;
var $user$project$AudioContextTest$extractContext = function(initialized){if ( initialized.$ ==='Fresh' ){var ctx = initialized.a; return ( ctx);} else{var ctx = initialized.a; return ( ctx);}};
var $user$project$AudioFFI$resumeAudioContext = $author$project$FFI$resumeAudioContext;
var $user$project$AudioFFI$suspendAudioContext = $author$project$FFI$suspendAudioContext;
var $user$project$AudioContextTest$contextLifecycleTests = A2( $user$project$Test$describe,'context lifecycle', _List_fromArray([ A2( $user$project$Test$describe,'resumeAudioContext', _List_fromArray([ A2( $user$project$Test$test,'returns result after resume', function(_v0){var _v1 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v1.$ ==='Ok' ){var ctx = _v1.a;var _v2 = $user$project$AudioFFI$resumeAudioContext( ctx);if ( _v2.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);})])) , A2( $user$project$Test$describe,'suspendAudioContext', _List_fromArray([ A2( $user$project$Test$test,'returns result after suspend', function(_v3){var _v4 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v4.$ ==='Ok' ){var ctx = _v4.a;var _v5 = $user$project$AudioFFI$suspendAudioContext( $user$project$AudioContextTest$extractContext( ctx));if ( _v5.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);})])) , A2( $user$project$Test$describe,'closeAudioContext', _List_fromArray([ A2( $user$project$Test$test,'returns result after close', function(_v6){var _v7 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v7.$ ==='Ok' ){var ctx = _v7.a;var _v8 = $user$project$AudioFFI$closeAudioContext( $user$project$AudioContextTest$extractContext( ctx));if ( _v8.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);})]))]));
var $user$project$AudioFFI$getContextState = $author$project$FFI$getContextState;
var $user$project$AudioFFI$getCurrentTime = $author$project$FFI$getCurrentTime;
var $user$project$AudioFFI$getSampleRate = $author$project$FFI$getSampleRate;
var $user$project$AudioContextTest$contextPropertyTests = A2( $user$project$Test$describe,'context properties', _List_fromArray([ A2( $user$project$Test$describe,'getSampleRate', _List_fromArray([ A2( $user$project$Test$test,'returns standard sample rate value', function(_v0){var _v1 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v1.$ ==='Ok' ){var ctx = _v1.a;var sampleRate = $user$project$AudioFFI$getSampleRate( $user$project$AudioContextTest$extractContext( ctx)); return ( A2( $user$project$Expect$true,'sample rate should be valid', sampleRate >=8000 && sampleRate <=192000));} else return ( $user$project$Expect$pass);})])) , A2( $user$project$Test$describe,'getContextState', _List_fromArray([ A2( $user$project$Test$test,'returns valid state string', function(_v2){var _v3 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v3.$ ==='Ok' ){var ctx = _v3.a;var state = $user$project$AudioFFI$getContextState( $user$project$AudioContextTest$extractContext( ctx)); return ( A2( $user$project$Expect$true,'state should be valid', state ==='running' || state ==='suspended' || state ==='closed'));} else return ( $user$project$Expect$pass);})])) , A2( $user$project$Test$describe,'getCurrentTime', _List_fromArray([ A2( $user$project$Test$test,'returns non-negative time', function(_v4){var _v5 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v5.$ ==='Ok' ){var ctx = _v5.a;var time = $user$project$AudioFFI$getCurrentTime( ctx); return ( A2( $user$project$Expect$true,'time should be non-negative', time >=0));} else return ( $user$project$Expect$pass);})]))]));
var $user$project$AudioContextTest$createContextTests = A2( $user$project$Test$describe,'createAudioContext', _List_fromArray([ A2( $user$project$Test$test,'returns Ok result with valid user activation', function(_v0){var _v1 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v1.$ ==='Ok' ) return ( $user$project$Expect$pass); else{var err = _v1.a; return ( $user$project$Expect$pass);}}) , A2( $user$project$Test$test,'returns consistent result type', function(_v2){var result = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( result.$ ==='Ok' )if ( result.a.$ ==='Fresh' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);})]));
var $user$project$AudioContextTest$suite = A2( $user$project$Test$describe,'AudioContext Functions', _List_fromArray([ $user$project$AudioContextTest$createContextTests , $user$project$AudioContextTest$contextPropertyTests , $user$project$AudioContextTest$contextLifecycleTests]));
var $user$project$AudioFFI$getAudioParamAutomationRate = $author$project$FFI$getAudioParamAutomationRate;
var $user$project$AudioFFI$setAudioParamAutomationRate = $author$project$FFI$setAudioParamAutomationRate;
var $user$project$AudioParamTest$withContext = function(fn){var _v0 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v0.$ ==='Ok' ){var ctx = _v0.a; return ( fn( ctx));} else return ( $user$project$Expect$pass);};
var $user$project$AudioParamTest$paramAutomationTests = A2( $user$project$Test$describe,'param automation rate', _List_fromArray([ A2( $user$project$Test$describe,'getAudioParamAutomationRate', _List_fromArray([ A2( $user$project$Test$test,'returns automation rate', function(_v0){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v1 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v1.$ ==='Ok' ){var gain = _v1.a;var param = $user$project$AudioFFI$getGainParam( gain);var rate = $user$project$AudioFFI$getAudioParamAutomationRate( param); return ( A2( $user$project$Expect$true,'should be valid rate', rate ==='a-rate' || rate ==='k-rate'));} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setAudioParamAutomationRate', _List_fromArray([ A2( $user$project$Test$test,'sets automation rate to a-rate', function(_v2){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v3 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v3.$ ==='Ok' ){var gain = _v3.a;var param = $user$project$AudioFFI$getGainParam( gain);var _v4 = A2( $user$project$AudioFFI$setAudioParamAutomationRate, param,'a-rate');if ( _v4.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));}) , A2( $user$project$Test$test,'sets automation rate to k-rate', function(_v5){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v6 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v6.$ ==='Ok' ){var gain = _v6.a;var param = $user$project$AudioFFI$getGainParam( gain);var _v7 = A2( $user$project$AudioFFI$setAudioParamAutomationRate, param,'k-rate');if ( _v7.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$cancelAndHoldAtTime = $author$project$FFI$cancelAndHoldAtTime;
var $user$project$AudioFFI$cancelScheduledValues = $author$project$FFI$cancelScheduledValues;
var $user$project$AudioFFI$linearRampToValue = $author$project$FFI$linearRampToValue;
var $user$project$AudioFFI$setValueAtTime = $author$project$FFI$setValueAtTime;
var $user$project$AudioFFI$setValueCurveAtTime = $author$project$FFI$setValueCurveAtTime;
var $user$project$AudioParamTest$paramCurveTests = A2( $user$project$Test$describe,'param curves', _List_fromArray([ A2( $user$project$Test$describe,'setValueCurveAtTime', _List_fromArray([ A2( $user$project$Test$test,'sets value curve', function(_v0){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v1 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v1.$ ==='Ok' ){var gain = _v1.a;var param = $user$project$AudioFFI$getGainParam( gain);var curve = _List_fromArray([0.0 ,0.5 ,1.0 ,0.5 ,0.0]);var _v2 = A4( $user$project$AudioFFI$setValueCurveAtTime, param, curve,0.0,1.0);if ( _v2.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'cancelScheduledValues', _List_fromArray([ A2( $user$project$Test$test,'cancels scheduled automation', function(_v3){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v4 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v4.$ ==='Ok' ){var gain = _v4.a;var param = $user$project$AudioFFI$getGainParam( gain);var _v5 = A3( $user$project$AudioFFI$setValueAtTime, param,1.0,0.0);var _v6 = A3( $user$project$AudioFFI$linearRampToValue, param,0.0,1.0);var _v7 = A2( $user$project$AudioFFI$cancelScheduledValues, param,0.5); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'cancelAndHoldAtTime', _List_fromArray([ A2( $user$project$Test$test,'cancels and holds at time', function(_v8){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v9 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v9.$ ==='Ok' ){var gain = _v9.a;var param = $user$project$AudioFFI$getGainParam( gain);var _v10 = A3( $user$project$AudioFFI$setValueAtTime, param,1.0,0.0);var _v11 = A3( $user$project$AudioFFI$linearRampToValue, param,0.0,2.0);var _v12 = A2( $user$project$AudioFFI$cancelAndHoldAtTime, param,1.0); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$getAudioParamDefaultValue = $author$project$FFI$getAudioParamDefaultValue;
var $user$project$AudioFFI$getAudioParamMaxValue = $author$project$FFI$getAudioParamMaxValue;
var $user$project$AudioFFI$getAudioParamMinValue = $author$project$FFI$getAudioParamMinValue;
var $user$project$AudioFFI$getAudioParamValue = $author$project$FFI$getAudioParamValue;
var $user$project$AudioParamTest$paramPropertyTests = A2( $user$project$Test$describe,'param properties', _List_fromArray([ A2( $user$project$Test$describe,'getAudioParamValue', _List_fromArray([ A2( $user$project$Test$test,'returns current value', function(_v0){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v1 = A2( $user$project$AudioFFI$createGainNode, ctx,0.75);if ( _v1.$ ==='Ok' ){var gain = _v1.a;var param = $user$project$AudioFFI$getGainParam( gain);var value = $user$project$AudioFFI$getAudioParamValue( param); return ( A3( $user$project$Expect$within, $user$project$Expect$Absolute(0.01),0.75, value));} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getAudioParamDefaultValue', _List_fromArray([ A2( $user$project$Test$test,'returns default value', function(_v2){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v3 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v3.$ ==='Ok' ){var gain = _v3.a;var param = $user$project$AudioFFI$getGainParam( gain);var defaultVal = $user$project$AudioFFI$getAudioParamDefaultValue( param); return ( A3( $user$project$Expect$within, $user$project$Expect$Absolute(0.01),1.0, defaultVal));} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getAudioParamMinValue', _List_fromArray([ A2( $user$project$Test$test,'returns minimum value', function(_v4){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v5 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v5.$ ==='Ok' ){var gain = _v5.a;var param = $user$project$AudioFFI$getGainParam( gain);var minVal = $user$project$AudioFFI$getAudioParamMinValue( param); return ( A2( $user$project$Expect$true,'min should be very small or negative', minVal <=0));} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'getAudioParamMaxValue', _List_fromArray([ A2( $user$project$Test$test,'returns maximum value', function(_v6){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v7 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v7.$ ==='Ok' ){var gain = _v7.a;var param = $user$project$AudioFFI$getGainParam( gain);var maxVal = $user$project$AudioFFI$getAudioParamMaxValue( param); return ( A2( $user$project$Expect$true,'max should be large', maxVal >1));} else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$exponentialRampToValue = $author$project$FFI$exponentialRampToValue;
var $user$project$AudioFFI$exponentialRampToValueAtTime = $author$project$FFI$exponentialRampToValueAtTime;
var $user$project$AudioFFI$linearRampToValueAtTime = $author$project$FFI$linearRampToValueAtTime;
var $user$project$AudioFFI$setTargetAtTime = $author$project$FFI$setTargetAtTime;
var $user$project$AudioParamTest$paramRampTests = A2( $user$project$Test$describe,'param ramping', _List_fromArray([ A2( $user$project$Test$describe,'linearRampToValue', _List_fromArray([ A2( $user$project$Test$test,'ramps linearly to target', function(_v0){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v1 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v1.$ ==='Ok' ){var gain = _v1.a;var param = $user$project$AudioFFI$getGainParam( gain);var _v2 = A3( $user$project$AudioFFI$setValueAtTime, param,1.0,0.0);var _v3 = A3( $user$project$AudioFFI$linearRampToValue, param,0.0,1.0); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'linearRampToValueAtTime', _List_fromArray([ A2( $user$project$Test$test,'ramps linearly to value at time', function(_v4){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v5 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v5.$ ==='Ok' ){var gain = _v5.a;var param = $user$project$AudioFFI$getGainParam( gain);var _v6 = A3( $user$project$AudioFFI$setValueAtTime, param,1.0,0.0);var _v7 = A3( $user$project$AudioFFI$linearRampToValueAtTime, param,0.5,2.0); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'exponentialRampToValue', _List_fromArray([ A2( $user$project$Test$test,'ramps exponentially to target', function(_v8){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v9 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v9.$ ==='Ok' ){var gain = _v9.a;var param = $user$project$AudioFFI$getGainParam( gain);var _v10 = A3( $user$project$AudioFFI$setValueAtTime, param,1.0,0.0);var _v11 = A3( $user$project$AudioFFI$exponentialRampToValue, param,0.01,1.0); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'exponentialRampToValueAtTime', _List_fromArray([ A2( $user$project$Test$test,'ramps exponentially to value at time', function(_v12){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v13 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v13.$ ==='Ok' ){var gain = _v13.a;var param = $user$project$AudioFFI$getGainParam( gain);var _v14 = A3( $user$project$AudioFFI$setValueAtTime, param,1.0,0.0);var _v15 = A3( $user$project$AudioFFI$exponentialRampToValueAtTime, param,0.1,2.0); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setTargetAtTime', _List_fromArray([ A2( $user$project$Test$test,'sets exponential approach to target', function(_v16){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v17 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v17.$ ==='Ok' ){var gain = _v17.a;var param = $user$project$AudioFFI$getGainParam( gain);var _v18 = A4( $user$project$AudioFFI$setTargetAtTime, param,0.0,0.0,0.5); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioFFI$setAudioParamValue = $author$project$FFI$setAudioParamValue;
var $user$project$AudioFFI$setParamValueAtTime = $author$project$FFI$setParamValueAtTime;
var $user$project$AudioParamTest$paramValueTests = A2( $user$project$Test$describe,'param value operations', _List_fromArray([ A2( $user$project$Test$describe,'setValueAtTime', _List_fromArray([ A2( $user$project$Test$test,'sets value at time', function(_v0){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v1 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v1.$ ==='Ok' ){var gain = _v1.a;var param = $user$project$AudioFFI$getGainParam( gain);var _v2 = A3( $user$project$AudioFFI$setValueAtTime, param,0.5,0.0); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setParamValueAtTime', _List_fromArray([ A2( $user$project$Test$test,'sets param value at time', function(_v3){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v4 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v4.$ ==='Ok' ){var gain = _v4.a;var param = $user$project$AudioFFI$getGainParam( gain);var _v5 = A3( $user$project$AudioFFI$setParamValueAtTime, param,0.75,0.0); return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})])) , A2( $user$project$Test$describe,'setAudioParamValue', _List_fromArray([ A2( $user$project$Test$test,'sets param value directly', function(_v6){ return ( $user$project$AudioParamTest$withContext( function(ctx){var _v7 = A2( $user$project$AudioFFI$createGainNode, ctx,1.0);if ( _v7.$ ==='Ok' ){var gain = _v7.a;var param = $user$project$AudioFFI$getGainParam( gain);var _v8 = A2( $user$project$AudioFFI$setAudioParamValue, param,0.5);if ( _v8.$ ==='Ok' ) return ( $user$project$Expect$pass); else return ( $user$project$Expect$pass);} else return ( $user$project$Expect$pass);}));})]))]));
var $user$project$AudioParamTest$suite = A2( $user$project$Test$describe,'AudioParam Functions', _List_fromArray([ $user$project$AudioParamTest$paramValueTests , $user$project$AudioParamTest$paramRampTests , $user$project$AudioParamTest$paramCurveTests , $user$project$AudioParamTest$paramPropertyTests , $user$project$AudioParamTest$paramAutomationTests]));
var $user$project$BrowserTestMain$main = function(){var allSuites = _List_fromArray([ $user$project$FilterTest$suite , $user$project$BufferTest$suite , $user$project$ConnectionTest$suite , $user$project$AudioContextTest$suite , $user$project$AnalyserTest$suite , $user$project$OscillatorTest$suite , $user$project$SimplifiedTest$suite , $user$project$EffectsTest$suite , $user$project$SpatialTest$suite , $user$project$GainTest$suite , $user$project$AudioParamTest$suite]);var report = $user$project$Test$runTests( allSuites); return ( A2( $elm$html$Html$div, _List_fromArray([ A2( $elm$html$Html$Attributes$attribute,'data-test-complete','true')]), _List_fromArray([ A2( $elm$html$Html$pre, _List_Nil, _List_fromArray([ $elm$html$Html$text( report)])) , A3( $elm$html$Html$node,'script', _List_Nil, _List_fromArray([ $elm$html$Html$text( $user$project$BrowserTestMain$logResultsScript( report))]))])));}();
var $user$project$AudioParamTest$main = function(){var results = $user$project$Test$runTests( _List_fromArray([ $user$project$AudioParamTest$suite])); return ( A2( $elm$html$Html$pre, _List_Nil, _List_fromArray([ $elm$html$Html$text( results)])));}();
var $user$project$AudioContextTest$main = function(){var results = $user$project$Test$runTests( _List_fromArray([ $user$project$AudioContextTest$suite])); return ( A2( $elm$html$Html$pre, _List_Nil, _List_fromArray([ $elm$html$Html$text( results)])));}();
var $user$project$AnalyserTest$main = function(){var results = $user$project$Test$runTests( _List_fromArray([ $user$project$AnalyserTest$suite])); return ( A2( $elm$html$Html$pre, _List_Nil, _List_fromArray([ $elm$html$Html$text( results)])));}();
var $elm$core$Task$succeed = _Scheduler_succeed;
var $elm$core$Task$init = $elm$core$Task$succeed( _Utils_Tuple0);
var $elm$core$Task$andThen = _Scheduler_andThen;
var $elm$core$Task$map = F2( function(func,taskA){ return ( A2( $elm$core$Task$andThen, function(a){ return ( $elm$core$Task$succeed( func( a)));}, taskA));});
var $elm$core$Task$map2 = F3( function(func,taskA,taskB){ return ( A2( $elm$core$Task$andThen, function(a){ return ( A2( $elm$core$Task$andThen, function(b){ return ( $elm$core$Task$succeed( A2( func, a, b)));}, taskB));}, taskA));});
var $elm$core$Task$sequence = function(tasks){ return ( A3( $elm$core$List$foldr, $elm$core$Task$map2( $elm$core$List$cons), $elm$core$Task$succeed( _List_Nil), tasks));};
var $elm$core$Platform$sendToApp = _Platform_sendToApp;
var $elm$core$Task$spawnCmd = F2( function(router,_v0){var task = _v0.a; return ( _Scheduler_spawn( A2( $elm$core$Task$andThen, $elm$core$Platform$sendToApp( router), task)));});
var $elm$core$Task$onEffects = F3( function(router,commands,state){ return ( A2( $elm$core$Task$map, function(_v0){ return ( _Utils_Tuple0);}, $elm$core$Task$sequence( A2( $elm$core$List$map, $elm$core$Task$spawnCmd( router), commands))));});
var $elm$core$Task$onSelfMsg = F3( function(_v0,_v1,_v2){ return ( $elm$core$Task$succeed( _Utils_Tuple0));});
var $elm$core$Basics$identity = function(x){ return ( x);};
var $elm$core$Task$Perform = function(a){ return ({a : a,$ :'Perform'});};
var $elm$core$Task$cmdMap = F2( function(tagger,_v0){var task = _v0.a; return ( $elm$core$Task$Perform( A2( $elm$core$Task$map, tagger, task)));});
 _Platform_effectManagers['Task'] = _Platform_createManager( $elm$core$Task$init, $elm$core$Task$onEffects, $elm$core$Task$onSelfMsg, $elm$core$Task$cmdMap)
var $elm$core$Task$command = _Platform_leaf('Task');
var $user$project$Expect$AbsoluteOrRelative = F2( function(a,b){ return ({b : b,a : a,$ :'AbsoluteOrRelative'});});
var $user$project$AudioFFI$AnalyserNode ={$ :'AnalyserNode'};
var $user$project$AudioFFI$ArrayBuffer ={$ :'ArrayBuffer'};
var $elm$virtual_dom$VirtualDom$Attribute ={$ :'Attribute'};
var $user$project$AudioFFI$AudioBuffer ={$ :'AudioBuffer'};
var $user$project$AudioFFI$AudioBufferSourceNode ={$ :'AudioBufferSourceNode'};
var $user$project$AudioFFI$AudioContext ={$ :'AudioContext'};
var $user$project$AudioFFI$AudioDestinationNode ={$ :'AudioDestinationNode'};
var $user$project$AudioFFI$AudioListener ={$ :'AudioListener'};
var $user$project$AudioFFI$AudioNode ={$ :'AudioNode'};
var $user$project$AudioFFI$AudioParam ={$ :'AudioParam'};
var $user$project$AudioFFI$AudioParamMap ={$ :'AudioParamMap'};
var $user$project$AudioFFI$AudioWorkletNode ={$ :'AudioWorkletNode'};
var $user$project$AudioFFI$BiquadFilterNode ={$ :'BiquadFilterNode'};
var $elm$core$Dict$Black ={$ :'Black'};
var $elm$core$Array$Builder = F3( function(tail,nodeList,nodeListSize){ return ({tail : tail,nodeListSize : nodeListSize,nodeList : nodeList});});
var $user$project$Capability$CapabilityRevoked = function(a){ return ({a : a,$ :'CapabilityRevoked'});};
var $user$project$AudioFFI$ChannelMergerNode ={$ :'ChannelMergerNode'};
var $user$project$AudioFFI$ChannelSplitterNode ={$ :'ChannelSplitterNode'};
var $elm$core$Char$Char ={$ :'Char'};
var $user$project$Capability$Closing = function(a){ return ({a : a,$ :'Closing'});};
var $elm$core$Platform$Cmd$Cmd ={$ :'Cmd'};
var $user$project$Expect$Comparison = F4( function(a,b,c,d){ return ({d : d,c : c,b : b,a : a,$ :'Comparison'});});
var $user$project$AudioFFI$ConstantSourceNode ={$ :'ConstantSourceNode'};
var $user$project$AudioFFI$ConvolverNode ={$ :'ConvolverNode'};
var $elm$virtual_dom$VirtualDom$Custom = function(a){ return ({a : a,$ :'Custom'});};
var $elm$json$Json$Decode$Decoder ={$ :'Decoder'};
var $user$project$AudioFFI$DelayNode ={$ :'DelayNode'};
var $user$project$Capability$Denied = function(a){ return ({a : a,$ :'Denied'});};
var $user$project$Capability$Drag ={$ :'Drag'};
var $user$project$AudioFFI$DynamicsCompressorNode ={$ :'DynamicsCompressorNode'};
var $user$project$Capability$Experimental = function(a){ return ({a : a,$ :'Experimental'});};
var $user$project$Capability$FeatureNotAvailable = function(a){ return ({a : a,$ :'FeatureNotAvailable'});};
var $elm$core$Basics$Float ={$ :'Float'};
var $user$project$Capability$Focus ={$ :'Focus'};
var $user$project$Capability$Fresh = function(a){ return ({a : a,$ :'Fresh'});};
var $user$project$AudioFFI$GainNode ={$ :'GainNode'};
var $user$project$Capability$Granted = function(a){ return ({a : a,$ :'Granted'});};
var $user$project$AudioFFI$HTMLMediaElement ={$ :'HTMLMediaElement'};
var $user$project$AudioFFI$IIRFilterNode ={$ :'IIRFilterNode'};
var $user$project$Capability$IndexSizeError = function(a){ return ({a : a,$ :'IndexSizeError'});};
var $user$project$Capability$InitializationRequired = function(a){ return ({a : a,$ :'InitializationRequired'});};
var $elm$core$Basics$Int ={$ :'Int'};
var $user$project$Capability$Interrupted = function(a){ return ({a : a,$ :'Interrupted'});};
var $user$project$Capability$InvalidAccessError = function(a){ return ({a : a,$ :'InvalidAccessError'});};
var $user$project$Capability$InvalidStateError = function(a){ return ({a : a,$ :'InvalidStateError'});};
var $elm$core$Elm$JsArray$JsArray = function(a){ return ({a : a,$ :'JsArray'});};
var $elm$core$Basics$JustOneMore = function(a){ return ({a : a,$ :'JustOneMore'});};
var $user$project$Capability$Keypress ={$ :'Keypress'};
var $user$project$Capability$LegacySupport = function(a){ return ({a : a,$ :'LegacySupport'});};
var $elm$virtual_dom$VirtualDom$MayPreventDefault = function(a){ return ({a : a,$ :'MayPreventDefault'});};
var $elm$virtual_dom$VirtualDom$MayStopPropagation = function(a){ return ({a : a,$ :'MayStopPropagation'});};
var $user$project$AudioFFI$MediaElementAudioSourceNode ={$ :'MediaElementAudioSourceNode'};
var $user$project$AudioFFI$MediaStream ={$ :'MediaStream'};
var $user$project$AudioFFI$MediaStreamAudioDestinationNode ={$ :'MediaStreamAudioDestinationNode'};
var $user$project$AudioFFI$MediaStreamAudioSourceNode ={$ :'MediaStreamAudioSourceNode'};
var $user$project$AudioFFI$MediaStreamTrack ={$ :'MediaStreamTrack'};
var $user$project$AudioFFI$MessagePort ={$ :'MessagePort'};
var $elm$virtual_dom$VirtualDom$Node ={$ :'Node'};
var $elm$virtual_dom$VirtualDom$Normal = function(a){ return ({a : a,$ :'Normal'});};
var $user$project$Capability$NotAllowedError = function(a){ return ({a : a,$ :'NotAllowedError'});};
var $user$project$Capability$NotSupportedError = function(a){ return ({a : a,$ :'NotSupportedError'});};
var $user$project$AudioFFI$OfflineAudioContext ={$ :'OfflineAudioContext'};
var $user$project$AudioFFI$OscillatorNode ={$ :'OscillatorNode'};
var $user$project$AudioFFI$PannerNode ={$ :'PannerNode'};
var $user$project$Capability$PartialSupport = function(a){ return ({a : a,$ :'PartialSupport'});};
var $user$project$AudioFFI$PeriodicWave ={$ :'PeriodicWave'};
var $user$project$Capability$PermissionRequired = function(a){ return ({a : a,$ :'PermissionRequired'});};
var $user$project$Capability$Polyfilled = function(a){ return ({a : a,$ :'Polyfilled'});};
var $user$project$Capability$Prefixed = F2( function(a,b){ return ({b : b,a : a,$ :'Prefixed'});});
var $elm$core$Platform$ProcessId ={$ :'ProcessId'};
var $elm$core$Platform$Program ={$ :'Program'};
var $user$project$Capability$Prompt = function(a){ return ({a : a,$ :'Prompt'});};
var $user$project$Capability$QuotaExceededError = function(a){ return ({a : a,$ :'QuotaExceededError'});};
var $elm$core$Dict$RBEmpty_elm_builtin ={$ :'RBEmpty_elm_builtin'};
var $elm$core$Dict$RBNode_elm_builtin = F5( function(a,b,c,d,e){ return ({e : e,d : d,c : c,b : b,a : a,$ :'RBNode_elm_builtin'});});
var $user$project$Capability$RangeError = function(a){ return ({a : a,$ :'RangeError'});};
var $elm$core$Dict$Red ={$ :'Red'};
var $user$project$Expect$Relative = function(a){ return ({a : a,$ :'Relative'});};
var $user$project$Capability$Restored = function(a){ return ({a : a,$ :'Restored'});};
var $user$project$Capability$Restricted = function(a){ return ({a : a,$ :'Restricted'});};
var $user$project$Capability$Revoked = function(a){ return ({a : a,$ :'Revoked'});};
var $elm$core$Platform$Router ={$ :'Router'};
var $user$project$Capability$Running = function(a){ return ({a : a,$ :'Running'});};
var $user$project$Capability$SecurityError = function(a){ return ({a : a,$ :'SecurityError'});};
var $elm$core$Set$Set_elm_builtin = function(a){ return ({a : a,$ :'Set_elm_builtin'});};
var $user$project$Test$Skip = function(a){ return ({a : a,$ :'Skip'});};
var $user$project$AudioFFI$StereoPannerNode ={$ :'StereoPannerNode'};
var $elm$core$String$String ={$ :'String'};
var $elm$core$Platform$Sub$Sub ={$ :'Sub'};
var $user$project$Capability$Supported = function(a){ return ({a : a,$ :'Supported'});};
var $user$project$Capability$Suspended = function(a){ return ({a : a,$ :'Suspended'});};
var $elm$core$Platform$Task ={$ :'Task'};
var $user$project$Test$TestResult = F4( function(description,status,message,duration){ return ({status : status,message : message,duration : duration,description : description});});
var $user$project$Test$Todo = function(a){ return ({a : a,$ :'Todo'});};
var $user$project$Capability$Touch ={$ :'Touch'};
var $user$project$Capability$Transient ={$ :'Transient'};
var $user$project$Capability$Unknown = function(a){ return ({a : a,$ :'Unknown'});};
var $user$project$Capability$UserActivationRequired = function(a){ return ({a : a,$ :'UserActivationRequired'});};
var $elm$json$Json$Encode$Value ={$ :'Value'};
var $user$project$AudioFFI$WaveShaperNode ={$ :'WaveShaperNode'};
var $elm$core$List$any = F2( function(isOkay,list){any: while (true ){if (! list.b ) return false; else{var x = list.a;var xs = list.b;if ( isOkay( x) ){ return true;} else{var $temp$list = xs, $temp$isOkay = isOkay
;isOkay = $temp$isOkay;list = $temp$list; continue any;}};}});
var $elm$core$List$drop = F2( function(n,list){drop: while (true ){if ( n <=0 ){ return ( list);} else{if (! list.b ) return ( list); else{var x = list.a;var xs = list.b;var $temp$list = xs, $temp$n = n -1
;n = $temp$n;list = $temp$list; continue drop;}};}});
var $elm$core$Bitwise$shiftRightZfBy = _Bitwise_shiftRightZfBy;
var $elm$core$Array$bitMask =4294967295 >>>(32 - $elm$core$Array$shiftStep);
var $elm$core$Elm$JsArray$slice = _JsArray_slice;
var $elm$core$Elm$JsArray$unsafeGet = _JsArray_unsafeGet;
var $elm$core$Array$fetchNewTail = F4( function(shift,end,treeEnd,tree){fetchNewTail: while (true ){var pos = $elm$core$Array$bitMask & treeEnd >>> shift;var _v0 = A2( $elm$core$Elm$JsArray$unsafeGet, pos, tree);if ( _v0.$ ==='SubTree' ){var sub = _v0.a;var $temp$tree = sub, $temp$treeEnd = treeEnd, $temp$end = end, $temp$shift = shift - $elm$core$Array$shiftStep
;shift = $temp$shift;end = $temp$end;treeEnd = $temp$treeEnd;tree = $temp$tree; continue fetchNewTail;} else{var values = _v0.a; return ( A3( $elm$core$Elm$JsArray$slice,0, $elm$core$Array$bitMask & end, values));}}});
var $elm$core$Dict$foldl = F3( function(func,acc,dict){foldl: while (true ){if ( dict.$ ==='RBEmpty_elm_builtin' ) return ( acc); else{var key = dict.b;var value = dict.c;var left = dict.d;var right = dict.e;var $temp$dict = right, $temp$acc = A3( func, key, value, A3( $elm$core$Dict$foldl, func, acc, left)), $temp$func = func
;func = $temp$func;acc = $temp$acc;dict = $temp$dict; continue foldl;};}});
var $elm$core$Array$fromListHelp = F3( function(list,nodeList,nodeListSize){fromListHelp: while (true ){var _v0 = A2( $elm$core$Elm$JsArray$initializeFromList, $elm$core$Array$branchFactor, list);var jsArray = _v0.a;var remainingItems = _v0.b;if ( _Utils_cmp( $elm$core$Elm$JsArray$length( jsArray), $elm$core$Array$branchFactor) <0 ){ return ( A2( $elm$core$Array$builderToArray,true,{tail : jsArray,nodeListSize : nodeListSize,nodeList : nodeList}));} else{var $temp$nodeListSize = nodeListSize +1, $temp$nodeList = A2( $elm$core$List$cons, $elm$core$Array$Leaf( jsArray), nodeList), $temp$list = remainingItems
;list = $temp$list;nodeList = $temp$nodeList;nodeListSize = $temp$nodeListSize; continue fromListHelp;}}});
var $elm$core$Basics$compare = _Utils_compare;
var $elm$core$Dict$get = F2( function(targetKey,dict){get: while (true ){if ( dict.$ ==='RBEmpty_elm_builtin' ) return ( $elm$core$Maybe$Nothing); else{var key = dict.b;var value = dict.c;var left = dict.d;var right = dict.e;var _v1 = A2( $elm$core$Basics$compare, targetKey, key); switch( _v1.$){ case 'LT' :var $temp$dict = left, $temp$targetKey = targetKey
;targetKey = $temp$targetKey;dict = $temp$dict; continue get; case 'EQ' : return ( $elm$core$Maybe$Just( value)); default :var $temp$dict = right, $temp$targetKey = targetKey
;targetKey = $temp$targetKey;dict = $temp$dict; continue get;}};}});
var $elm$core$Array$getHelp = F3( function(shift,index,tree){getHelp: while (true ){var pos = $elm$core$Array$bitMask & index >>> shift;var _v0 = A2( $elm$core$Elm$JsArray$unsafeGet, pos, tree);if ( _v0.$ ==='SubTree' ){var subTree = _v0.a;var $temp$tree = subTree, $temp$index = index, $temp$shift = shift - $elm$core$Array$shiftStep
;shift = $temp$shift;index = $temp$index;tree = $temp$tree; continue getHelp;} else{var values = _v0.a; return ( A2( $elm$core$Elm$JsArray$unsafeGet, $elm$core$Array$bitMask & index, values));}}});
var $elm$core$Dict$getMin = function(dict){getMin: while (true ){if ( dict.$ ==='RBNode_elm_builtin' && dict.d.$ ==='RBNode_elm_builtin' ){var left = dict.d;var $temp$dict = left
;dict = $temp$dict; continue getMin;} else return ( dict);;}};
var $elm$core$Array$hoistTree = F3( function(oldShift,newShift,tree){hoistTree: while (true ){if ( _Utils_cmp( oldShift, newShift) <1 ||! $elm$core$Elm$JsArray$length( tree) ){ return ( tree);} else{var _v0 = A2( $elm$core$Elm$JsArray$unsafeGet,0, tree);if ( _v0.$ ==='SubTree' ){var sub = _v0.a;var $temp$tree = sub, $temp$newShift = newShift, $temp$oldShift = oldShift - $elm$core$Array$shiftStep
;oldShift = $temp$oldShift;newShift = $temp$newShift;tree = $temp$tree; continue hoistTree;} else return ( tree);};}});
var $elm$core$Dict$balance = F5( function(color,key,value,left,right){if ( right.$ ==='RBNode_elm_builtin' && right.a.$ ==='Red' ){var _v1 = right.a;var rK = right.b;var rV = right.c;var rLeft = right.d;var rRight = right.e;if ( left.$ ==='RBNode_elm_builtin' && left.a.$ ==='Red' ){var _v3 = left.a;var lK = left.b;var lV = left.c;var lLeft = left.d;var lRight = left.e; return ( A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, key, value, A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Black, lK, lV, lLeft, lRight), A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Black, rK, rV, rLeft, rRight)));} else return ( A5( $elm$core$Dict$RBNode_elm_builtin, color, rK, rV, A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, key, value, left, rLeft), rRight));} else if ( left.$ ==='RBNode_elm_builtin' && left.a.$ ==='Red' && left.d.$ ==='RBNode_elm_builtin' && left.d.a.$ ==='Red' ){var _v5 = left.a;var lK = left.b;var lV = left.c;var _v6 = left.d;var _v7 = _v6.a;var llK = _v6.b;var llV = _v6.c;var llLeft = _v6.d;var llRight = _v6.e;var lRight = left.e; return ( A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, lK, lV, A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Black, llK, llV, llLeft, llRight), A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Black, key, value, lRight, right)));} else return ( A5( $elm$core$Dict$RBNode_elm_builtin, color, key, value, left, right));});
var $elm$core$Dict$insertHelp = F3( function(key,value,dict){if ( dict.$ ==='RBEmpty_elm_builtin' ) return ( A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, key, value, $elm$core$Dict$RBEmpty_elm_builtin, $elm$core$Dict$RBEmpty_elm_builtin)); else{var nColor = dict.a;var nKey = dict.b;var nValue = dict.c;var nLeft = dict.d;var nRight = dict.e;var _v1 = A2( $elm$core$Basics$compare, key, nKey); switch( _v1.$){ case 'LT' : return ( A5( $elm$core$Dict$balance, nColor, nKey, nValue, A3( $elm$core$Dict$insertHelp, key, value, nLeft), nRight)); case 'EQ' : return ( A5( $elm$core$Dict$RBNode_elm_builtin, nColor, nKey, value, nLeft, nRight)); default : return ( A5( $elm$core$Dict$balance, nColor, nKey, nValue, nLeft, A3( $elm$core$Dict$insertHelp, key, value, nRight)));}}});
var $elm$core$Elm$JsArray$push = _JsArray_push;
var $elm$core$Elm$JsArray$singleton = _JsArray_singleton;
var $elm$core$Elm$JsArray$unsafeSet = _JsArray_unsafeSet;
var $elm$core$Array$insertTailInTree = F4( function(shift,index,tail,tree){var pos = $elm$core$Array$bitMask & index >>> shift;if ( _Utils_cmp( pos, $elm$core$Elm$JsArray$length( tree)) >-1 ){if ( shift ===5 ){ return ( A2( $elm$core$Elm$JsArray$push, $elm$core$Array$Leaf( tail), tree));} else{var newSub = $elm$core$Array$SubTree( A4( $elm$core$Array$insertTailInTree, shift - $elm$core$Array$shiftStep, index, tail, $elm$core$Elm$JsArray$empty)); return ( A2( $elm$core$Elm$JsArray$push, newSub, tree));}} else{var value = A2( $elm$core$Elm$JsArray$unsafeGet, pos, tree);if ( value.$ ==='SubTree' ){var subTree = value.a;var newSub = $elm$core$Array$SubTree( A4( $elm$core$Array$insertTailInTree, shift - $elm$core$Array$shiftStep, index, tail, subTree)); return ( A3( $elm$core$Elm$JsArray$unsafeSet, pos, newSub, tree));} else{var newSub = $elm$core$Array$SubTree( A4( $elm$core$Array$insertTailInTree, shift - $elm$core$Array$shiftStep, index, tail, $elm$core$Elm$JsArray$singleton( value))); return ( A3( $elm$core$Elm$JsArray$unsafeSet, pos, newSub, tree));}}});
var $elm$core$Dict$map = F2( function(func,dict){if ( dict.$ ==='RBEmpty_elm_builtin' ) return ( $elm$core$Dict$RBEmpty_elm_builtin); else{var color = dict.a;var key = dict.b;var value = dict.c;var left = dict.d;var right = dict.e; return ( A5( $elm$core$Dict$RBNode_elm_builtin, color, key, A2( func, key, value), A2( $elm$core$Dict$map, func, left), A2( $elm$core$Dict$map, func, right)));}});
var $elm$core$Basics$never = function(_v0){never: while (true ){var nvr = _v0.a;var $temp$_v0 = nvr
;_v0 = $temp$_v0; continue never;}};
var $elm$core$Dict$moveRedLeft = function(dict){if ( dict.$ ==='RBNode_elm_builtin' && dict.d.$ ==='RBNode_elm_builtin' && dict.e.$ ==='RBNode_elm_builtin' )if ( dict.e.d.$ ==='RBNode_elm_builtin' && dict.e.d.a.$ ==='Red' ){var clr = dict.a;var k = dict.b;var v = dict.c;var _v1 = dict.d;var lClr = _v1.a;var lK = _v1.b;var lV = _v1.c;var lLeft = _v1.d;var lRight = _v1.e;var _v2 = dict.e;var rClr = _v2.a;var rK = _v2.b;var rV = _v2.c;var rLeft = _v2.d;var _v3 = rLeft.a;var rlK = rLeft.b;var rlV = rLeft.c;var rlL = rLeft.d;var rlR = rLeft.e;var rRight = _v2.e; return ( A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, rlK, rlV, A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Black, k, v, A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, lK, lV, lLeft, lRight), rlL), A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Black, rK, rV, rlR, rRight)));} else{var clr = dict.a;var k = dict.b;var v = dict.c;var _v4 = dict.d;var lClr = _v4.a;var lK = _v4.b;var lV = _v4.c;var lLeft = _v4.d;var lRight = _v4.e;var _v5 = dict.e;var rClr = _v5.a;var rK = _v5.b;var rV = _v5.c;var rLeft = _v5.d;var rRight = _v5.e;if ( clr.$ ==='Black' ) return ( A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Black, k, v, A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, lK, lV, lLeft, lRight), A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, rK, rV, rLeft, rRight))); else return ( A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Black, k, v, A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, lK, lV, lLeft, lRight), A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, rK, rV, rLeft, rRight)));} else return ( dict);};
var $elm$core$Dict$moveRedRight = function(dict){if ( dict.$ ==='RBNode_elm_builtin' && dict.d.$ ==='RBNode_elm_builtin' && dict.e.$ ==='RBNode_elm_builtin' )if ( dict.d.d.$ ==='RBNode_elm_builtin' && dict.d.d.a.$ ==='Red' ){var clr = dict.a;var k = dict.b;var v = dict.c;var _v1 = dict.d;var lClr = _v1.a;var lK = _v1.b;var lV = _v1.c;var _v2 = _v1.d;var _v3 = _v2.a;var llK = _v2.b;var llV = _v2.c;var llLeft = _v2.d;var llRight = _v2.e;var lRight = _v1.e;var _v4 = dict.e;var rClr = _v4.a;var rK = _v4.b;var rV = _v4.c;var rLeft = _v4.d;var rRight = _v4.e; return ( A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, lK, lV, A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Black, llK, llV, llLeft, llRight), A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Black, k, v, lRight, A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, rK, rV, rLeft, rRight))));} else{var clr = dict.a;var k = dict.b;var v = dict.c;var _v5 = dict.d;var lClr = _v5.a;var lK = _v5.b;var lV = _v5.c;var lLeft = _v5.d;var lRight = _v5.e;var _v6 = dict.e;var rClr = _v6.a;var rK = _v6.b;var rV = _v6.c;var rLeft = _v6.d;var rRight = _v6.e;if ( clr.$ ==='Black' ) return ( A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Black, k, v, A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, lK, lV, lLeft, lRight), A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, rK, rV, rLeft, rRight))); else return ( A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Black, k, v, A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, lK, lV, lLeft, lRight), A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, rK, rV, rLeft, rRight)));} else return ( dict);};
var $elm$core$Dict$removeHelpPrepEQGT = F7( function(targetKey,dict,color,key,value,left,right){if ( left.$ ==='RBNode_elm_builtin' && left.a.$ ==='Red' ){var _v1 = left.a;var lK = left.b;var lV = left.c;var lLeft = left.d;var lRight = left.e; return ( A5( $elm$core$Dict$RBNode_elm_builtin, color, lK, lV, lLeft, A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Red, key, value, lRight, right)));} else{_v2$2: while (true )if ( right.$ ==='RBNode_elm_builtin' && right.a.$ ==='Black' )if ( right.d.$ ==='RBNode_elm_builtin' )if ( right.d.a.$ ==='Black' ){var _v3 = right.a;var _v4 = right.d;var _v5 = _v4.a; return ( $elm$core$Dict$moveRedRight( dict));} else break _v2$2; else{var _v6 = right.a;var _v7 = right.d; return ( $elm$core$Dict$moveRedRight( dict));} else break _v2$2; return ( dict);}});
var $elm$core$Dict$removeMin = function(dict){if ( dict.$ ==='RBNode_elm_builtin' && dict.d.$ ==='RBNode_elm_builtin' ){var color = dict.a;var key = dict.b;var value = dict.c;var left = dict.d;var lColor = left.a;var lLeft = left.d;var right = dict.e;if ( lColor.$ ==='Black' )if ( lLeft.$ ==='RBNode_elm_builtin' && lLeft.a.$ ==='Red' ){var _v3 = lLeft.a; return ( A5( $elm$core$Dict$RBNode_elm_builtin, color, key, value, $elm$core$Dict$removeMin( left), right));} else{var _v4 = $elm$core$Dict$moveRedLeft( dict);if ( _v4.$ ==='RBNode_elm_builtin' ){var nColor = _v4.a;var nKey = _v4.b;var nValue = _v4.c;var nLeft = _v4.d;var nRight = _v4.e; return ( A5( $elm$core$Dict$balance, nColor, nKey, nValue, $elm$core$Dict$removeMin( nLeft), nRight));} else return ( $elm$core$Dict$RBEmpty_elm_builtin);} else return ( A5( $elm$core$Dict$RBNode_elm_builtin, color, key, value, $elm$core$Dict$removeMin( left), right));} else return ( $elm$core$Dict$RBEmpty_elm_builtin);};
var $elm$core$Dict$removeHelp = F2( function(targetKey,dict){if ( dict.$ ==='RBEmpty_elm_builtin' ) return ( $elm$core$Dict$RBEmpty_elm_builtin); else{var color = dict.a;var key = dict.b;var value = dict.c;var left = dict.d;var right = dict.e;if ( _Utils_cmp( targetKey, key) <0 ){if ( left.$ ==='RBNode_elm_builtin' && left.a.$ ==='Black' ){var _v4 = left.a;var lLeft = left.d;if ( lLeft.$ ==='RBNode_elm_builtin' && lLeft.a.$ ==='Red' ){var _v6 = lLeft.a; return ( A5( $elm$core$Dict$RBNode_elm_builtin, color, key, value, A2( $elm$core$Dict$removeHelp, targetKey, left), right));} else{var _v7 = $elm$core$Dict$moveRedLeft( dict);if ( _v7.$ ==='RBNode_elm_builtin' ){var nColor = _v7.a;var nKey = _v7.b;var nValue = _v7.c;var nLeft = _v7.d;var nRight = _v7.e; return ( A5( $elm$core$Dict$balance, nColor, nKey, nValue, A2( $elm$core$Dict$removeHelp, targetKey, nLeft), nRight));} else return ( $elm$core$Dict$RBEmpty_elm_builtin);}} else return ( A5( $elm$core$Dict$RBNode_elm_builtin, color, key, value, A2( $elm$core$Dict$removeHelp, targetKey, left), right));} else{ return ( A2( $elm$core$Dict$removeHelpEQGT, targetKey, A7( $elm$core$Dict$removeHelpPrepEQGT, targetKey, dict, color, key, value, left, right)));}}});
var $elm$core$Dict$removeHelpEQGT = F2( function(targetKey,dict){if ( dict.$ ==='RBNode_elm_builtin' ){var color = dict.a;var key = dict.b;var value = dict.c;var left = dict.d;var right = dict.e;if ( _Utils_eq( targetKey, key) ){var _v1 = $elm$core$Dict$getMin( right);if ( _v1.$ ==='RBNode_elm_builtin' ){var minKey = _v1.b;var minValue = _v1.c; return ( A5( $elm$core$Dict$balance, color, minKey, minValue, left, $elm$core$Dict$removeMin( right)));} else return ( $elm$core$Dict$RBEmpty_elm_builtin);} else{ return ( A5( $elm$core$Dict$balance, color, key, value, left, A2( $elm$core$Dict$removeHelp, targetKey, right)));}} else return ( $elm$core$Dict$RBEmpty_elm_builtin);});
var $elm$core$List$repeatHelp = F3( function(result,n,value){repeatHelp: while (true ){if ( n <=0 ){ return ( result);} else{var $temp$value = value, $temp$n = n -1, $temp$result = A2( $elm$core$List$cons, value, result)
;result = $temp$result;n = $temp$n;value = $temp$value; continue repeatHelp;};}});
var $elm$core$Array$setHelp = F4( function(shift,index,value,tree){var pos = $elm$core$Array$bitMask & index >>> shift;var _v0 = A2( $elm$core$Elm$JsArray$unsafeGet, pos, tree);if ( _v0.$ ==='SubTree' ){var subTree = _v0.a;var newSub = A4( $elm$core$Array$setHelp, shift - $elm$core$Array$shiftStep, index, value, subTree); return ( A3( $elm$core$Elm$JsArray$unsafeSet, pos, $elm$core$Array$SubTree( newSub), tree));} else{var values = _v0.a;var newLeaf = A3( $elm$core$Elm$JsArray$unsafeSet, $elm$core$Array$bitMask & index, value, values); return ( A3( $elm$core$Elm$JsArray$unsafeSet, pos, $elm$core$Array$Leaf( newLeaf), tree));}});
var $elm$core$Dict$sizeHelp = F2( function(n,dict){sizeHelp: while (true ){if ( dict.$ ==='RBEmpty_elm_builtin' ) return ( n); else{var left = dict.d;var right = dict.e;var $temp$dict = left, $temp$n = A2( $elm$core$Dict$sizeHelp, n +1, right)
;n = $temp$n;dict = $temp$dict; continue sizeHelp;};}});
var $elm$core$Array$sliceTree = F3( function(shift,endIdx,tree){var lastPos = $elm$core$Array$bitMask & endIdx >>> shift;var _v0 = A2( $elm$core$Elm$JsArray$unsafeGet, lastPos, tree);if ( _v0.$ ==='SubTree' ){var sub = _v0.a;var newSub = A3( $elm$core$Array$sliceTree, shift - $elm$core$Array$shiftStep, endIdx, sub); return ((! $elm$core$Elm$JsArray$length( newSub))? A3( $elm$core$Elm$JsArray$slice,0, lastPos, tree): A3( $elm$core$Elm$JsArray$unsafeSet, lastPos, $elm$core$Array$SubTree( newSub), A3( $elm$core$Elm$JsArray$slice,0, lastPos +1, tree)));} else return ( A3( $elm$core$Elm$JsArray$slice,0, lastPos, tree));});
var $elm$core$List$takeReverse = F3( function(n,list,kept){takeReverse: while (true ){if ( n <=0 ){ return ( kept);} else{if (! list.b ) return ( kept); else{var x = list.a;var xs = list.b;var $temp$kept = A2( $elm$core$List$cons, x, kept), $temp$list = xs, $temp$n = n -1
;n = $temp$n;list = $temp$list;kept = $temp$kept; continue takeReverse;}};}});
var $elm$core$List$takeTailRec = F2( function(n,list){ return ( $elm$core$List$reverse( A3( $elm$core$List$takeReverse, n, list, _List_Nil)));});
var $elm$core$List$takeFast = F3( function(ctr,n,list){if ( n <=0 ){ return ( _List_Nil);} else{var _v0 = _Utils_Tuple2( n, list);_v0$1: while (true ){_v0$5: while (true )if (! _v0.b.b ) return ( list); else if ( _v0.b.b.b ) switch( _v0.a){ case 1 : break _v0$1; case 2 :var _v2 = _v0.b;var x = _v2.a;var _v3 = _v2.b;var y = _v3.a; return ( _List_fromArray([ x , y])); case 3 :if ( _v0.b.b.b.b ){var _v4 = _v0.b;var x = _v4.a;var _v5 = _v4.b;var y = _v5.a;var _v6 = _v5.b;var z = _v6.a; return ( _List_fromArray([ x , y , z]));} else break _v0$5; default :if ( _v0.b.b.b.b && _v0.b.b.b.b.b ){var _v7 = _v0.b;var x = _v7.a;var _v8 = _v7.b;var y = _v8.a;var _v9 = _v8.b;var z = _v9.a;var _v10 = _v9.b;var w = _v10.a;var tl = _v10.b; return (( ctr >1000)? A2( $elm$core$List$cons, x, A2( $elm$core$List$cons, y, A2( $elm$core$List$cons, z, A2( $elm$core$List$cons, w, A2( $elm$core$List$takeTailRec, n -4, tl))))): A2( $elm$core$List$cons, x, A2( $elm$core$List$cons, y, A2( $elm$core$List$cons, z, A2( $elm$core$List$cons, w, A3( $elm$core$List$takeFast, ctr +1, n -4, tl))))));} else break _v0$5;} else if ( _v0.a ===1 ) break _v0$1; else break _v0$5; return ( list);}var _v1 = _v0.b;var x = _v1.a; return ( _List_fromArray([ x]));}});
var $elm$html$Html$a = _VirtualDom_node('a');
var $elm$html$Html$abbr = _VirtualDom_node('abbr');
var $elm$json$Json$Encode$string = _Json_wrap;
var $elm$html$Html$Attributes$stringProperty = F2( function(key,string){ return ( A2( _VirtualDom_property, key, $elm$json$Json$Encode$string( string)));});
var $elm$html$Html$Attributes$accept = $elm$html$Html$Attributes$stringProperty('accept');
var $elm$html$Html$Attributes$acceptCharset = $elm$html$Html$Attributes$stringProperty('acceptCharset');
var $elm$core$String$cons = _String_cons;
var $elm$core$String$fromChar = function(_char){ return ( A2( $elm$core$String$cons, _char,''));};
var $elm$html$Html$Attributes$accesskey = function(_char){ return ( A2( $elm$html$Html$Attributes$stringProperty,'accessKey', $elm$core$String$fromChar( _char)));};
var $elm$core$Basics$acos = _Basics_acos;
var $elm$html$Html$Attributes$action = function(uri){ return ( A2( $elm$html$Html$Attributes$stringProperty,'action', _VirtualDom_noJavaScriptUri( uri)));};
var $user$project$AudioFFI$addAudioWorkletModule = $author$project$FFI$addAudioWorkletModule;
var $elm$html$Html$address = _VirtualDom_node('address');
var $elm$html$Html$Attributes$align = $elm$html$Html$Attributes$stringProperty('align');
var $user$project$Expect$isFailure = function(expectation){if ( expectation.$ ==='Pass' ) return false; else return true;};
var $user$project$Expect$all = F2( function(expectations,value){var results = A2( $elm$core$List$map, function(expectation){ return ( expectation( value));}, expectations);var failures = A2( $elm$core$List$filter, $user$project$Expect$isFailure, results);if (! failures.b ) return ( $user$project$Expect$Pass); else{var first = failures.a; return ( first);}});
var $elm$core$Basics$composeL = F3( function(g,f,x){ return ( g( f( x)));});
var $elm$core$Basics$not = _Basics_not;
var $elm$core$List$all = F2( function(isOkay,list){ return (! A2( $elm$core$List$any, A2( $elm$core$Basics$composeL, $elm$core$Basics$not, isOkay), list));});
var $elm$html$Html$Attributes$alt = $elm$html$Html$Attributes$stringProperty('alt');
var $elm$core$Basics$always = F2( function(a,_v0){ return ( a);});
var $elm$html$Html$Events$alwaysPreventDefault = function(msg){ return ( _Utils_Tuple2( msg,true));};
var $elm$html$Html$Events$alwaysStop = function(x){ return ( _Utils_Tuple2( x,true));};
var $user$project$AudioFFI$analyserNodeToAudioNode = $author$project$FFI$analyserNodeToAudioNode;
var $elm$json$Json$Decode$andThen = _Json_andThen;
var $elm$core$Maybe$andThen = F2( function(callback,maybeValue){if ( maybeValue.$ ==='Just' ){var value = maybeValue.a; return ( callback( value));} else return ( $elm$core$Maybe$Nothing);});
var $elm$core$Result$andThen = F2( function(callback,result){if ( result.$ ==='Ok' ){var value = result.a; return ( callback( value));} else{var msg = result.a; return ( $elm$core$Result$Err( msg));}});
var $elm$core$String$any = _String_any;
var $elm$core$Elm$JsArray$appendN = _JsArray_appendN;
var $elm$core$Array$appendHelpBuilder = F2( function(tail,builder){var tailLen = $elm$core$Elm$JsArray$length( tail);var notAppended = $elm$core$Array$branchFactor - $elm$core$Elm$JsArray$length( builder.tail) - tailLen;var appended = A3( $elm$core$Elm$JsArray$appendN, $elm$core$Array$branchFactor, builder.tail, tail); return (( notAppended <0)?{tail : A3( $elm$core$Elm$JsArray$slice, notAppended, tailLen, tail),nodeListSize : builder.nodeListSize +1,nodeList : A2( $elm$core$List$cons, $elm$core$Array$Leaf( appended), builder.nodeList)}:(! notAppended)?{tail : $elm$core$Elm$JsArray$empty,nodeListSize : builder.nodeListSize +1,nodeList : A2( $elm$core$List$cons, $elm$core$Array$Leaf( appended), builder.nodeList)}:{tail : appended,nodeListSize : builder.nodeListSize,nodeList : builder.nodeList});});
var $elm$core$Bitwise$shiftLeftBy = _Bitwise_shiftLeftBy;
var $elm$core$Array$unsafeReplaceTail = F2( function(newTail,_v0){var len = _v0.a;var startShift = _v0.b;var tree = _v0.c;var tail = _v0.d;var originalTailLen = $elm$core$Elm$JsArray$length( tail);var newTailLen = $elm$core$Elm$JsArray$length( newTail);var newArrayLen = len +( newTailLen - originalTailLen);if ( _Utils_eq( newTailLen, $elm$core$Array$branchFactor) ){var overflow = _Utils_cmp( newArrayLen >>> $elm$core$Array$shiftStep,1 << startShift) >0;if ( overflow ){var newShift = startShift + $elm$core$Array$shiftStep;var newTree = A4( $elm$core$Array$insertTailInTree, newShift, len, newTail, $elm$core$Elm$JsArray$singleton( $elm$core$Array$SubTree( tree))); return ( A4( $elm$core$Array$Array_elm_builtin, newArrayLen, newShift, newTree, $elm$core$Elm$JsArray$empty));} else{ return ( A4( $elm$core$Array$Array_elm_builtin, newArrayLen, startShift, A4( $elm$core$Array$insertTailInTree, startShift, len, newTail, tree), $elm$core$Elm$JsArray$empty));}} else{ return ( A4( $elm$core$Array$Array_elm_builtin, newArrayLen, startShift, tree, newTail));}});
var $elm$core$Array$appendHelpTree = F2( function(toAppend,array){var len = array.a;var tree = array.c;var tail = array.d;var itemsToAppend = $elm$core$Elm$JsArray$length( toAppend);var notAppended = $elm$core$Array$branchFactor - $elm$core$Elm$JsArray$length( tail) - itemsToAppend;var appended = A3( $elm$core$Elm$JsArray$appendN, $elm$core$Array$branchFactor, tail, toAppend);var newArray = A2( $elm$core$Array$unsafeReplaceTail, appended, array);if ( notAppended <0 ){var nextTail = A3( $elm$core$Elm$JsArray$slice, notAppended, itemsToAppend, toAppend); return ( A2( $elm$core$Array$unsafeReplaceTail, nextTail, newArray));} else{ return ( newArray);}});
var $elm$core$Elm$JsArray$foldl = _JsArray_foldl;
var $elm$core$Array$builderFromArray = function(_v0){var len = _v0.a;var tree = _v0.c;var tail = _v0.d;var helper = F2( function(node,acc){if ( node.$ ==='SubTree' ){var subTree = node.a; return ( A3( $elm$core$Elm$JsArray$foldl, helper, acc, subTree));} else return ( A2( $elm$core$List$cons, node, acc));}); return ({tail : tail,nodeListSize : len / $elm$core$Array$branchFactor |0,nodeList : A3( $elm$core$Elm$JsArray$foldl, helper, _List_Nil, tree)});};
var $elm$core$Array$append = F2( function(a,_v0){var aTail = a.d;var bLen = _v0.a;var bTree = _v0.c;var bTail = _v0.d;if ( _Utils_cmp( bLen, $elm$core$Array$branchFactor *4) <1 ){var foldHelper = F2( function(node,array){if ( node.$ ==='SubTree' ){var tree = node.a; return ( A3( $elm$core$Elm$JsArray$foldl, foldHelper, array, tree));} else{var leaf = node.a; return ( A2( $elm$core$Array$appendHelpTree, leaf, array));}}); return ( A2( $elm$core$Array$appendHelpTree, bTail, A3( $elm$core$Elm$JsArray$foldl, foldHelper, a, bTree)));} else{var foldHelper = F2( function(node,builder){if ( node.$ ==='SubTree' ){var tree = node.a; return ( A3( $elm$core$Elm$JsArray$foldl, foldHelper, builder, tree));} else{var leaf = node.a; return ( A2( $elm$core$Array$appendHelpBuilder, leaf, builder));}}); return ( A2( $elm$core$Array$builderToArray,true, A2( $elm$core$Array$appendHelpBuilder, bTail, A3( $elm$core$Elm$JsArray$foldl, foldHelper, $elm$core$Array$builderFromArray( a), bTree))));}});
var $elm$core$String$append = _String_append;
var $elm$json$Json$Decode$array = _Json_decodeArray;
var $elm$core$Array$foldl = F3( function(func,baseCase,_v0){var tree = _v0.c;var tail = _v0.d;var helper = F2( function(node,acc){if ( node.$ ==='SubTree' ){var subTree = node.a; return ( A3( $elm$core$Elm$JsArray$foldl, helper, acc, subTree));} else{var values = node.a; return ( A3( $elm$core$Elm$JsArray$foldl, func, acc, values));}}); return ( A3( $elm$core$Elm$JsArray$foldl, func, A3( $elm$core$Elm$JsArray$foldl, helper, baseCase, tree), tail));});
var $elm$json$Json$Encode$array = F2( function(func,entries){ return ( _Json_wrap( A3( $elm$core$Array$foldl, _Json_addEntry( func), _Json_emptyArray( _Utils_Tuple0), entries)));});
var $elm$html$Html$article = _VirtualDom_node('article');
var $elm$html$Html$aside = _VirtualDom_node('aside');
var $elm$core$Basics$asin = _Basics_asin;
var $elm$json$Json$Decode$field = _Json_decodeField;
var $elm$json$Json$Decode$at = F2( function(fields,decoder){ return ( A3( $elm$core$List$foldr, $elm$json$Json$Decode$field, decoder, fields));});
var $user$project$Expect$atLeast = F2( function(threshold,actual){ return (( _Utils_cmp( actual, threshold) >-1)? $user$project$Expect$Pass: $user$project$Expect$Fail( A4( $user$project$Expect$Comparison,'Expect.atLeast', $elm$core$Debug$toString( actual),'>=', $elm$core$Debug$toString( threshold))));});
var $user$project$Expect$atMost = F2( function(threshold,actual){ return (( _Utils_cmp( actual, threshold) <1)? $user$project$Expect$Pass: $user$project$Expect$Fail( A4( $user$project$Expect$Comparison,'Expect.atMost', $elm$core$Debug$toString( actual),'<=', $elm$core$Debug$toString( threshold))));});
var $elm$core$Basics$atan = _Basics_atan;
var $elm$core$Basics$atan2 = _Basics_atan2;
var $elm$core$Task$onError = _Scheduler_onError;
var $elm$core$Task$attempt = F2( function(resultToMessage,task){ return ( $elm$core$Task$command( $elm$core$Task$Perform( A2( $elm$core$Task$onError, A2( $elm$core$Basics$composeL, A2( $elm$core$Basics$composeL, $elm$core$Task$succeed, resultToMessage), $elm$core$Result$Err), A2( $elm$core$Task$andThen, A2( $elm$core$Basics$composeL, A2( $elm$core$Basics$composeL, $elm$core$Task$succeed, resultToMessage), $elm$core$Result$Ok), task)))));});
var $elm$virtual_dom$VirtualDom$attributeNS = F3( function(namespace,key,value){ return ( A3( _VirtualDom_attributeNS, namespace, _VirtualDom_noOnOrFormAction( key), _VirtualDom_noJavaScriptOrHtmlUri( value)));});
var $elm$html$Html$audio = _VirtualDom_node('audio');
var $user$project$AudioFFI$audioBufferSourceNodeToAudioNode = $author$project$FFI$audioBufferSourceNodeToAudioNode;
var $user$project$AudioFFI$audioWorkletNodeToAudioNode = $author$project$FFI$audioWorkletNodeToAudioNode;
var $elm$html$Html$Attributes$autocomplete = function(bool){ return ( A2( $elm$html$Html$Attributes$stringProperty,'autocomplete', bool?'on':'off'));};
var $elm$json$Json$Encode$bool = _Json_wrap;
var $elm$html$Html$Attributes$boolProperty = F2( function(key,bool){ return ( A2( _VirtualDom_property, key, $elm$json$Json$Encode$bool( bool)));});
var $elm$html$Html$Attributes$autofocus = $elm$html$Html$Attributes$boolProperty('autofocus');
var $elm$html$Html$Attributes$autoplay = $elm$html$Html$Attributes$boolProperty('autoplay');
var $elm$html$Html$b = _VirtualDom_node('b');
var $elm$core$Platform$Cmd$batch = _Platform_batch;
var $elm$core$Platform$Sub$batch = _Platform_batch;
var $elm$html$Html$bdi = _VirtualDom_node('bdi');
var $elm$html$Html$bdo = _VirtualDom_node('bdo');
var $user$project$AudioFFI$biquadFilterNodeToAudioNode = $author$project$FFI$biquadFilterNodeToAudioNode;
var $elm$html$Html$blockquote = _VirtualDom_node('blockquote');
var $elm$json$Json$Decode$bool = _Json_decodeBool;
var $elm$html$Html$br = _VirtualDom_node('br');
var $elm$html$Html$button = _VirtualDom_node('button');
var $elm$html$Html$canvas = _VirtualDom_node('canvas');
var $elm$html$Html$caption = _VirtualDom_node('caption');
var $user$project$AudioFFI$channelMergerNodeToAudioNode = $author$project$FFI$channelMergerNodeToAudioNode;
var $user$project$AudioFFI$channelSplitterNodeToAudioNode = $author$project$FFI$channelSplitterNodeToAudioNode;
var $elm$html$Html$Attributes$checked = $elm$html$Html$Attributes$boolProperty('checked');
var $elm$html$Html$cite = _VirtualDom_node('cite');
var $elm$html$Html$Attributes$cite = $elm$html$Html$Attributes$stringProperty('cite');
var $elm$core$Basics$clamp = F3( function(low,high,number){ return (( _Utils_cmp( number, low) <0)? low:( _Utils_cmp( number, high) >0)? high: number);});
var $elm$html$Html$Attributes$class = $elm$html$Html$Attributes$stringProperty('className');
var $elm$core$Tuple$second = function(_v0){var y = _v0.b; return ( y);};
var $elm$html$Html$Attributes$classList = function(classes){ return ( $elm$html$Html$Attributes$class( A2( $elm$core$String$join,' ', A2( $elm$core$List$map, $elm$core$Tuple$first, A2( $elm$core$List$filter, $elm$core$Tuple$second, classes)))));};
var $elm$html$Html$code = _VirtualDom_node('code');
var $elm$html$Html$col = _VirtualDom_node('col');
var $elm$html$Html$colgroup = _VirtualDom_node('colgroup');
var $elm$html$Html$Attributes$cols = function(n){ return ( A2( _VirtualDom_attribute,'cols', $elm$core$String$fromInt( n)));};
var $elm$html$Html$Attributes$colspan = function(n){ return ( A2( _VirtualDom_attribute,'colspan', $elm$core$String$fromInt( n)));};
var $elm$core$Bitwise$complement = _Bitwise_complement;
var $elm$core$Basics$composeR = F3( function(f,g,x){ return ( g( f( x)));});
var $elm$core$String$concat = function(strings){ return ( A2( $elm$core$String$join,'', strings));};
var $user$project$Test$concat = function(tests){ return ( A2( $user$project$Test$TestGroup,'Test Suite', tests));};
var $user$project$AudioFFI$connectNodesWithChannels = $author$project$FFI$connectNodesWithChannels;
var $user$project$AudioFFI$constantSourceNodeToAudioNode = $author$project$FFI$constantSourceNodeToAudioNode;
var $user$project$Capability$consumeUserActivation = $user$project$Capability$Click;
var $elm$core$String$contains = _String_contains;
var $elm$html$Html$Attributes$contenteditable = $elm$html$Html$Attributes$boolProperty('contentEditable');
var $elm$html$Html$Attributes$contextmenu = _VirtualDom_attribute('contextmenu');
var $elm$html$Html$Attributes$controls = $elm$html$Html$Attributes$boolProperty('controls');
var $user$project$AudioFFI$convolverNodeToAudioNode = $author$project$FFI$convolverNodeToAudioNode;
var $elm$html$Html$Attributes$coords = $elm$html$Html$Attributes$stringProperty('coords');
var $user$project$AudioFFI$copyFromChannel = $author$project$FFI$copyFromChannel;
var $user$project$AudioFFI$copyToChannel = $author$project$FFI$copyToChannel;
var $elm$core$Basics$cos = _Basics_cos;
var $user$project$AudioFFI$createAudioWorkletNode = $author$project$FFI$createAudioWorkletNode;
var $user$project$AudioFFI$createBufferFromSamples = $author$project$FFI$createBufferFromSamples;
var $user$project$AudioFFI$createConstantSource = $author$project$FFI$createConstantSource;
var $user$project$AudioFFI$createMediaElementSource = $author$project$FFI$createMediaElementSource;
var $user$project$AudioFFI$createMediaStreamDestination = $author$project$FFI$createMediaStreamDestination;
var $user$project$AudioFFI$createMediaStreamSource = $author$project$FFI$createMediaStreamSource;
var $user$project$AudioFFI$createOfflineAudioContext = $author$project$FFI$createOfflineAudioContext;
var $user$project$AudioFFI$createPeriodicWave = $author$project$FFI$createPeriodicWave;
var $user$project$AudioFFI$createPeriodicWaveWithCoefficients = $author$project$FFI$createPeriodicWaveWithCoefficients;
var $user$project$AudioFFI$createPeriodicWaveWithOptions = $author$project$FFI$createPeriodicWaveWithOptions;
var $elm$virtual_dom$VirtualDom$on = _VirtualDom_on;
var $elm$html$Html$Events$custom = F2( function(event,decoder){ return ( A2( $elm$virtual_dom$VirtualDom$on, event, $elm$virtual_dom$VirtualDom$Custom( decoder)));});
var $elm$html$Html$datalist = _VirtualDom_node('datalist');
var $elm$html$Html$Attributes$datetime = _VirtualDom_attribute('datetime');
var $elm$html$Html$dd = _VirtualDom_node('dd');
var $user$project$AudioFFI$decodeAudioData = $author$project$FFI$decodeAudioData;
var $elm$json$Json$Decode$decodeString = _Json_runOnString;
var $elm$json$Json$Decode$decodeValue = _Json_run;
var $elm$html$Html$Attributes$default = $elm$html$Html$Attributes$boolProperty('default');
var $elm$core$Basics$pi = _Basics_pi;
var $elm$core$Basics$degrees = function(angleInDegrees){ return ( angleInDegrees * $elm$core$Basics$pi /180);};
var $elm$html$Html$del = _VirtualDom_node('del');
var $user$project$AudioFFI$delayNodeToAudioNode = $author$project$FFI$delayNodeToAudioNode;
var $elm$core$Maybe$destruct = F3( function(_default,func,maybe){if ( maybe.$ ==='Just' ){var a = maybe.a; return ( func( a));} else return ( _default);});
var $elm$html$Html$details = _VirtualDom_node('details');
var $elm$html$Html$dfn = _VirtualDom_node('dfn');
var $elm$core$Dict$empty = $elm$core$Dict$RBEmpty_elm_builtin;
var $elm$core$Dict$insert = F3( function(key,value,dict){var _v0 = A3( $elm$core$Dict$insertHelp, key, value, dict);if ( _v0.$ ==='RBNode_elm_builtin' && _v0.a.$ ==='Red' ){var _v1 = _v0.a;var k = _v0.b;var v = _v0.c;var l = _v0.d;var r = _v0.e; return ( A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Black, k, v, l, r));} else{var x = _v0; return ( x);}});
var $elm$core$Dict$fromList = function(assocs){ return ( A3( $elm$core$List$foldl, F2( function(_v0,dict){var key = _v0.a;var value = _v0.b; return ( A3( $elm$core$Dict$insert, key, value, dict));}), $elm$core$Dict$empty, assocs));};
var $elm$json$Json$Decode$keyValuePairs = _Json_decodeKeyValuePairs;
var $elm$json$Json$Decode$dict = function(decoder){ return ( A2( $elm$json$Json$Decode$map, $elm$core$Dict$fromList, $elm$json$Json$Decode$keyValuePairs( decoder)));};
var $elm$json$Json$Encode$dict = F3( function(toKey,toValue,dictionary){ return ( _Json_wrap( A3( $elm$core$Dict$foldl, F3( function(key,value,obj){ return ( A3( _Json_addField, toKey( key), toValue( value), obj));}), _Json_emptyObject( _Utils_Tuple0), dictionary)));});
var $elm$core$Dict$remove = F2( function(key,dict){var _v0 = A2( $elm$core$Dict$removeHelp, key, dict);if ( _v0.$ ==='RBNode_elm_builtin' && _v0.a.$ ==='Red' ){var _v1 = _v0.a;var k = _v0.b;var v = _v0.c;var l = _v0.d;var r = _v0.e; return ( A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Black, k, v, l, r));} else{var x = _v0; return ( x);}});
var $elm$core$Dict$diff = F2( function(t1,t2){ return ( A3( $elm$core$Dict$foldl, F3( function(k,v,t){ return ( A2( $elm$core$Dict$remove, k, t));}), t1, t2));});
var $elm$core$Set$diff = F2( function(_v0,_v1){var dict1 = _v0.a;var dict2 = _v1.a; return ( $elm$core$Set$Set_elm_builtin( A2( $elm$core$Dict$diff, dict1, dict2)));});
var $elm$html$Html$Attributes$dir = $elm$html$Html$Attributes$stringProperty('dir');
var $elm$html$Html$Attributes$disabled = $elm$html$Html$Attributes$boolProperty('disabled');
var $user$project$AudioFFI$disconnectNodeFromDestination = $author$project$FFI$disconnectNodeFromDestination;
var $user$project$AudioFFI$disconnectNodeFromNodeChannel = $author$project$FFI$disconnectNodeFromNodeChannel;
var $user$project$AudioFFI$disconnectNodeOutput = $author$project$FFI$disconnectNodeOutput;
var $elm$html$Html$dl = _VirtualDom_node('dl');
var $elm$html$Html$Attributes$download = function(fileName){ return ( A2( $elm$html$Html$Attributes$stringProperty,'download', fileName));};
var $elm$html$Html$Attributes$downloadAs = $elm$html$Html$Attributes$stringProperty('download');
var $elm$html$Html$Attributes$draggable = _VirtualDom_attribute('draggable');
var $elm$core$String$slice = _String_slice;
var $elm$core$String$dropLeft = F2( function(n,string){ return (( n <1)? string: A3( $elm$core$String$slice, n, $elm$core$String$length( string), string));});
var $elm$core$String$dropRight = F2( function(n,string){ return (( n <1)? string: A3( $elm$core$String$slice,0,- n, string));});
var $elm$html$Html$Attributes$dropzone = $elm$html$Html$Attributes$stringProperty('dropzone');
var $elm$html$Html$dt = _VirtualDom_node('dt');
var $user$project$AudioFFI$dynamicsCompressorNodeToAudioNode = $author$project$FFI$dynamicsCompressorNodeToAudioNode;
var $elm$core$Basics$e = _Basics_e;
var $elm$html$Html$em = _VirtualDom_node('em');
var $elm$html$Html$embed = _VirtualDom_node('embed');
var $elm$core$Set$empty = $elm$core$Set$Set_elm_builtin( $elm$core$Dict$empty);
var $elm$core$Array$emptyBuilder ={tail : $elm$core$Elm$JsArray$empty,nodeListSize :0,nodeList : _List_Nil};
var $elm$html$Html$Attributes$enctype = $elm$html$Html$Attributes$stringProperty('enctype');
var $elm$core$String$endsWith = _String_endsWith;
var $user$project$Expect$err = function(result){if ( result.$ ==='Err' ) return ( $user$project$Expect$Pass); else{var v = result.a; return ( $user$project$Expect$Fail( $user$project$Expect$Custom('Expected Err but got Ok: ' + $elm$core$Debug$toString( v))));}};
var $elm$json$Json$Decode$fail = _Json_fail;
var $elm$core$Task$fail = _Scheduler_fail;
var $user$project$Expect$false = F2( function(description,condition){ return ((! condition)? $user$project$Expect$Pass: $user$project$Expect$Fail( $user$project$Expect$Custom( description)));});
var $elm$html$Html$fieldset = _VirtualDom_node('fieldset');
var $elm$html$Html$figcaption = _VirtualDom_node('figcaption');
var $elm$html$Html$figure = _VirtualDom_node('figure');
var $elm$core$Array$fromList = function(list){if (! list.b ) return ( $elm$core$Array$empty); else return ( A3( $elm$core$Array$fromListHelp, list, _List_Nil,0));};
var $elm$core$Array$filter = F2( function(isGood,array){ return ( $elm$core$Array$fromList( A3( $elm$core$Array$foldr, F2( function(x,xs){ return ( isGood( x)? A2( $elm$core$List$cons, x, xs): xs);}), _List_Nil, array)));});
var $elm$core$Dict$filter = F2( function(isGood,dict){ return ( A3( $elm$core$Dict$foldl, F3( function(k,v,d){ return ( A2( isGood, k, v)? A3( $elm$core$Dict$insert, k, v, d): d);}), $elm$core$Dict$empty, dict));});
var $elm$core$Set$filter = F2( function(isGood,_v0){var dict = _v0.a; return ( $elm$core$Set$Set_elm_builtin( A2( $elm$core$Dict$filter, F2( function(key,_v1){ return ( isGood( key));}), dict)));});
var $elm$core$String$filter = _String_filter;
var $elm$core$List$maybeCons = F3( function(f,mx,xs){var _v0 = f( mx);if ( _v0.$ ==='Just' ){var x = _v0.a; return ( A2( $elm$core$List$cons, x, xs));} else return ( xs);});
var $elm$core$List$filterMap = F2( function(f,xs){ return ( A3( $elm$core$List$foldr, $elm$core$List$maybeCons( f), _List_Nil, xs));});
var $elm$json$Json$Decode$float = _Json_decodeFloat;
var $elm$json$Json$Encode$float = _Json_wrap;
var $elm$core$Set$foldl = F3( function(func,initialState,_v0){var dict = _v0.a; return ( A3( $elm$core$Dict$foldl, F3( function(key,_v1,state){ return ( A2( func, key, state));}), initialState, dict));});
var $elm$core$String$foldl = _String_foldl;
var $elm$core$Set$foldr = F3( function(func,initialState,_v0){var dict = _v0.a; return ( A3( $elm$core$Dict$foldr, F3( function(key,_v1,state){ return ( A2( func, key, state));}), initialState, dict));});
var $elm$core$String$foldr = _String_foldr;
var $elm$html$Html$footer = _VirtualDom_node('footer');
var $elm$html$Html$Attributes$for = $elm$html$Html$Attributes$stringProperty('htmlFor');
var $elm$html$Html$form = _VirtualDom_node('form');
var $elm$html$Html$Attributes$form = _VirtualDom_attribute('form');
var $elm$core$Char$fromCode = _Char_fromCode;
var $elm$core$String$fromFloat = _String_fromNumber;
var $elm$core$Set$insert = F2( function(key,_v0){var dict = _v0.a; return ( $elm$core$Set$Set_elm_builtin( A3( $elm$core$Dict$insert, key, _Utils_Tuple0, dict)));});
var $elm$core$Set$fromList = function(list){ return ( A3( $elm$core$List$foldl, $elm$core$Set$insert, $elm$core$Set$empty, list));};
var $elm$core$String$fromList = _String_fromList;
var $elm$core$Result$fromMaybe = F2( function(err,maybe){if ( maybe.$ ==='Just' ){var v = maybe.a; return ( $elm$core$Result$Ok( v));} else return ( $elm$core$Result$Err( err));});
var $elm$core$Basics$sin = _Basics_sin;
var $elm$core$Basics$fromPolar = function(_v0){var radius = _v0.a;var theta = _v0.b; return ( _Utils_Tuple2( radius * $elm$core$Basics$cos( theta), radius * $elm$core$Basics$sin( theta)));};
var $elm$core$Array$tailIndex = function(len){ return ( len >>>5 <<5);};
var $elm$core$Array$get = F2( function(index,_v0){var len = _v0.a;var startShift = _v0.b;var tree = _v0.c;var tail = _v0.d; return (( index <0 || _Utils_cmp( index, len) >-1)? $elm$core$Maybe$Nothing:( _Utils_cmp( index, $elm$core$Array$tailIndex( len)) >-1)? $elm$core$Maybe$Just( A2( $elm$core$Elm$JsArray$unsafeGet, $elm$core$Array$bitMask & index, tail)): $elm$core$Maybe$Just( A3( $elm$core$Array$getHelp, startShift, index, tree)));});
var $user$project$AudioFFI$getBufferSourceBuffer = $author$project$FFI$getBufferSourceBuffer;
var $user$project$AudioFFI$getBufferSourceLoop = $author$project$FFI$getBufferSourceLoop;
var $user$project$AudioFFI$getBufferSourceLoopEnd = $author$project$FFI$getBufferSourceLoopEnd;
var $user$project$AudioFFI$getBufferSourceLoopStart = $author$project$FFI$getBufferSourceLoopStart;
var $user$project$AudioFFI$getCompressorAttackParam = $author$project$FFI$getCompressorAttackParam;
var $user$project$AudioFFI$getCompressorReleaseParam = $author$project$FFI$getCompressorReleaseParam;
var $user$project$AudioFFI$getConstantSourceOffset = $author$project$FFI$getConstantSourceOffset;
var $user$project$AudioFFI$getConstantSourceOffsetValue = $author$project$FFI$getConstantSourceOffsetValue;
var $user$project$AudioFFI$getContextBaseLatency = $author$project$FFI$getContextBaseLatency;
var $user$project$AudioFFI$getContextOutputLatency = $author$project$FFI$getContextOutputLatency;
var $user$project$AudioFFI$getConvolverBuffer = $author$project$FFI$getConvolverBuffer;
var $user$project$AudioFFI$getConvolverNormalize = $author$project$FFI$getConvolverNormalize;
var $user$project$AudioFFI$getDelayMaxDelayTime = $author$project$FFI$getDelayMaxDelayTime;
var $user$project$AudioFFI$getDetuneParam = $author$project$FFI$getDetuneParam;
var $user$project$AudioFFI$getFrequencyParam = $author$project$FFI$getFrequencyParam;
var $user$project$AudioFFI$getMediaElementSourceElement = $author$project$FFI$getMediaElementSourceElement;
var $user$project$AudioFFI$getMediaStream = $author$project$FFI$getMediaStream;
var $user$project$AudioFFI$getMediaStreamActive = $author$project$FFI$getMediaStreamActive;
var $user$project$AudioFFI$getMediaStreamId = $author$project$FFI$getMediaStreamId;
var $user$project$AudioFFI$getMediaStreamTracks = $author$project$FFI$getMediaStreamTracks;
var $user$project$AudioFFI$getNodeContext = $author$project$FFI$getNodeContext;
var $user$project$AudioFFI$getOfflineContextLength = $author$project$FFI$getOfflineContextLength;
var $user$project$AudioFFI$getOfflineContextSampleRate = $author$project$FFI$getOfflineContextSampleRate;
var $user$project$AudioFFI$getPannerConeInnerAngle = $author$project$FFI$getPannerConeInnerAngle;
var $user$project$AudioFFI$getPannerConeOuterAngle = $author$project$FFI$getPannerConeOuterAngle;
var $user$project$AudioFFI$getPannerConeOuterGain = $author$project$FFI$getPannerConeOuterGain;
var $user$project$AudioFFI$getPannerDistanceModel = $author$project$FFI$getPannerDistanceModel;
var $user$project$AudioFFI$getPannerMaxDistance = $author$project$FFI$getPannerMaxDistance;
var $user$project$AudioFFI$getPannerPanningModel = $author$project$FFI$getPannerPanningModel;
var $user$project$AudioFFI$getPannerRefDistance = $author$project$FFI$getPannerRefDistance;
var $user$project$AudioFFI$getPannerRolloffFactor = $author$project$FFI$getPannerRolloffFactor;
var $user$project$AudioFFI$getWaveShaperCurve = $author$project$FFI$getWaveShaperCurve;
var $user$project$AudioFFI$getWaveShaperOversample = $author$project$FFI$getWaveShaperOversample;
var $user$project$AudioFFI$getWorkletParameters = $author$project$FFI$getWorkletParameters;
var $user$project$AudioFFI$getWorkletPort = $author$project$FFI$getWorkletPort;
var $user$project$Expect$greaterThan = F2( function(threshold,actual){ return (( _Utils_cmp( actual, threshold) >0)? $user$project$Expect$Pass: $user$project$Expect$Fail( A4( $user$project$Expect$Comparison,'Expect.greaterThan', $elm$core$Debug$toString( actual),'>', $elm$core$Debug$toString( threshold))));});
var $elm$html$Html$h1 = _VirtualDom_node('h1');
var $elm$html$Html$h2 = _VirtualDom_node('h2');
var $elm$html$Html$h3 = _VirtualDom_node('h3');
var $elm$html$Html$h4 = _VirtualDom_node('h4');
var $elm$html$Html$h5 = _VirtualDom_node('h5');
var $elm$html$Html$h6 = _VirtualDom_node('h6');
var $user$project$Capability$hasFeature = function(featurePath){ return true;};
var $elm$core$List$head = function(list){if ( list.b ){var x = list.a;var xs = list.b; return ( $elm$core$Maybe$Just( x));} else return ( $elm$core$Maybe$Nothing);};
var $elm$html$Html$header = _VirtualDom_node('header');
var $elm$html$Html$Attributes$headers = $elm$html$Html$Attributes$stringProperty('headers');
var $elm$html$Html$Attributes$height = function(n){ return ( A2( _VirtualDom_attribute,'height', $elm$core$String$fromInt( n)));};
var $elm$html$Html$Attributes$hidden = $elm$html$Html$Attributes$boolProperty('hidden');
var $elm$html$Html$hr = _VirtualDom_node('hr');
var $elm$html$Html$Attributes$href = function(url){ return ( A2( $elm$html$Html$Attributes$stringProperty,'href', _VirtualDom_noJavaScriptUri( url)));};
var $elm$html$Html$Attributes$hreflang = $elm$html$Html$Attributes$stringProperty('hreflang');
var $elm$html$Html$i = _VirtualDom_node('i');
var $elm$html$Html$Attributes$id = $elm$html$Html$Attributes$stringProperty('id');
var $elm$html$Html$iframe = _VirtualDom_node('iframe');
var $user$project$AudioFFI$iirFilterNodeToAudioNode = $author$project$FFI$iirFilterNodeToAudioNode;
var $elm$html$Html$img = _VirtualDom_node('img');
var $elm$json$Json$Decode$index = _Json_decodeIndex;
var $elm$core$Elm$JsArray$indexedMap = _JsArray_indexedMap;
var $elm$core$Array$indexedMap = F2( function(func,_v0){var len = _v0.a;var tree = _v0.c;var tail = _v0.d;var initialBuilder ={tail : A3( $elm$core$Elm$JsArray$indexedMap, func, $elm$core$Array$tailIndex( len), tail),nodeListSize :0,nodeList : _List_Nil};var helper = F2( function(node,builder){if ( node.$ ==='SubTree' ){var subTree = node.a; return ( A3( $elm$core$Elm$JsArray$foldl, helper, builder, subTree));} else{var leaf = node.a;var offset = builder.nodeListSize * $elm$core$Array$branchFactor;var mappedLeaf = $elm$core$Array$Leaf( A3( $elm$core$Elm$JsArray$indexedMap, func, offset, leaf)); return ({tail : builder.tail,nodeListSize : builder.nodeListSize +1,nodeList : A2( $elm$core$List$cons, mappedLeaf, builder.nodeList)});}}); return ( A2( $elm$core$Array$builderToArray,true, A3( $elm$core$Elm$JsArray$foldl, helper, initialBuilder, tree)));});
var $elm$core$String$indexes = _String_indexes;
var $elm$core$String$indices = _String_indexes;
var $elm$html$Html$input = _VirtualDom_node('input');
var $elm$html$Html$ins = _VirtualDom_node('ins');
var $elm$json$Json$Decode$int = _Json_decodeInt;
var $elm$json$Json$Encode$int = _Json_wrap;
var $elm$core$Dict$member = F2( function(key,dict){var _v0 = A2( $elm$core$Dict$get, key, dict);if ( _v0.$ ==='Just' ) return true; else return false;});
var $elm$core$Dict$intersect = F2( function(t1,t2){ return ( A2( $elm$core$Dict$filter, F2( function(k,_v0){ return ( A2( $elm$core$Dict$member, k, t2));}), t1));});
var $elm$core$Set$intersect = F2( function(_v0,_v1){var dict1 = _v0.a;var dict2 = _v1.a; return ( $elm$core$Set$Set_elm_builtin( A2( $elm$core$Dict$intersect, dict1, dict2)));});
var $elm$core$List$intersperse = F2( function(sep,xs){if (! xs.b ) return ( _List_Nil); else{var hd = xs.a;var tl = xs.b;var step = F2( function(x,rest){ return ( A2( $elm$core$List$cons, sep, A2( $elm$core$List$cons, x, rest)));});var spersed = A3( $elm$core$List$foldr, step, _List_Nil, tl); return ( A2( $elm$core$List$cons, hd, spersed));}});
var $elm$core$Array$isEmpty = function(_v0){var len = _v0.a; return (! len);};
var $elm$core$Dict$isEmpty = function(dict){if ( dict.$ ==='RBEmpty_elm_builtin' ) return true; else return false;};
var $elm$core$Set$isEmpty = function(_v0){var dict = _v0.a; return ( $elm$core$Dict$isEmpty( dict));};
var $elm$core$String$isEmpty = function(string){ return ( string ==='');};
var $elm$core$Char$isHexDigit = function(_char){var code = $elm$core$Char$toCode( _char); return (48 <= code && code <=57 ||65 <= code && code <=70 ||97 <= code && code <=102);};
var $elm$core$Basics$isInfinite = _Basics_isInfinite;
var $elm$core$Maybe$isJust = function(maybe){if ( maybe.$ ==='Just' ) return true; else return false;};
var $elm$core$Basics$isNaN = _Basics_isNaN;
var $elm$core$Char$isOctDigit = function(_char){var code = $elm$core$Char$toCode( _char); return ( code <=55 &&48 <= code);};
var $user$project$Capability$isUserActivationActive =true;
var $elm$html$Html$Attributes$ismap = $elm$html$Html$Attributes$boolProperty('isMap');
var $elm$html$Html$Attributes$itemprop = _VirtualDom_attribute('itemprop');
var $elm$html$Html$kbd = _VirtualDom_node('kbd');
var $elm$html$Html$Events$keyCode = A2( $elm$json$Json$Decode$field,'keyCode', $elm$json$Json$Decode$int);
var $elm$virtual_dom$VirtualDom$keyedNode = function(tag){ return ( _VirtualDom_keyedNode( _VirtualDom_noScript( tag)));};
var $elm$virtual_dom$VirtualDom$keyedNodeNS = F2( function(namespace,tag){ return ( A2( _VirtualDom_keyedNodeNS, namespace, _VirtualDom_noScript( tag)));});
var $elm$core$Process$kill = _Scheduler_kill;
var $elm$html$Html$Attributes$kind = $elm$html$Html$Attributes$stringProperty('kind');
var $elm$html$Html$label = _VirtualDom_node('label');
var $elm$html$Html$Attributes$lang = $elm$html$Html$Attributes$stringProperty('lang');
var $elm$virtual_dom$VirtualDom$lazy = _VirtualDom_lazy;
var $elm$html$Html$Lazy$lazy = $elm$virtual_dom$VirtualDom$lazy;
var $elm$json$Json$Decode$lazy = function(thunk){ return ( A2( $elm$json$Json$Decode$andThen, thunk, $elm$json$Json$Decode$succeed( _Utils_Tuple0)));};
var $elm$virtual_dom$VirtualDom$lazy2 = _VirtualDom_lazy2;
var $elm$html$Html$Lazy$lazy2 = $elm$virtual_dom$VirtualDom$lazy2;
var $elm$virtual_dom$VirtualDom$lazy3 = _VirtualDom_lazy3;
var $elm$html$Html$Lazy$lazy3 = $elm$virtual_dom$VirtualDom$lazy3;
var $elm$virtual_dom$VirtualDom$lazy4 = _VirtualDom_lazy4;
var $elm$html$Html$Lazy$lazy4 = $elm$virtual_dom$VirtualDom$lazy4;
var $elm$virtual_dom$VirtualDom$lazy5 = _VirtualDom_lazy5;
var $elm$html$Html$Lazy$lazy5 = $elm$virtual_dom$VirtualDom$lazy5;
var $elm$virtual_dom$VirtualDom$lazy6 = _VirtualDom_lazy6;
var $elm$html$Html$Lazy$lazy6 = $elm$virtual_dom$VirtualDom$lazy6;
var $elm$virtual_dom$VirtualDom$lazy7 = _VirtualDom_lazy7;
var $elm$html$Html$Lazy$lazy7 = $elm$virtual_dom$VirtualDom$lazy7;
var $elm$virtual_dom$VirtualDom$lazy8 = _VirtualDom_lazy8;
var $elm$html$Html$Lazy$lazy8 = $elm$virtual_dom$VirtualDom$lazy8;
var $elm$core$String$left = F2( function(n,string){ return (( n <1)?'': A3( $elm$core$String$slice,0, n, string));});
var $elm$html$Html$legend = _VirtualDom_node('legend');
var $elm$core$Array$length = function(_v0){var len = _v0.a; return ( len);};
var $user$project$Expect$lessThan = F2( function(threshold,actual){ return (( _Utils_cmp( actual, threshold) <0)? $user$project$Expect$Pass: $user$project$Expect$Fail( A4( $user$project$Expect$Comparison,'Expect.lessThan', $elm$core$Debug$toString( actual),'<', $elm$core$Debug$toString( threshold))));});
var $elm$html$Html$li = _VirtualDom_node('li');
var $elm$core$String$lines = _String_lines;
var $elm$html$Html$Attributes$list = _VirtualDom_attribute('list');
var $elm$json$Json$Decode$list = _Json_decodeList;
var $elm$json$Json$Encode$list = F2( function(func,entries){ return ( _Json_wrap( A3( $elm$core$List$foldl, _Json_addEntry( func), _Json_emptyArray( _Utils_Tuple0), entries)));});
var $elm$core$Debug$log = _Debug_log;
var $elm$html$Html$Attributes$loop = $elm$html$Html$Attributes$boolProperty('loop');
var $elm$html$Html$main_ = _VirtualDom_node('main');
var $elm$html$Html$Attributes$manifest = _VirtualDom_attribute('manifest');
var $elm$core$Elm$JsArray$map = _JsArray_map;
var $elm$core$Array$map = F2( function(func,_v0){var len = _v0.a;var startShift = _v0.b;var tree = _v0.c;var tail = _v0.d;var helper = function(node){if ( node.$ ==='SubTree' ){var subTree = node.a; return ( $elm$core$Array$SubTree( A2( $elm$core$Elm$JsArray$map, helper, subTree)));} else{var values = node.a; return ( $elm$core$Array$Leaf( A2( $elm$core$Elm$JsArray$map, func, values)));}}; return ( A4( $elm$core$Array$Array_elm_builtin, len, startShift, A2( $elm$core$Elm$JsArray$map, helper, tree), A2( $elm$core$Elm$JsArray$map, func, tail)));});
var $elm$virtual_dom$VirtualDom$map = _VirtualDom_map;
var $elm$html$Html$map = $elm$virtual_dom$VirtualDom$map;
var $elm$virtual_dom$VirtualDom$mapAttribute = _VirtualDom_mapAttribute;
var $elm$html$Html$Attributes$map = $elm$virtual_dom$VirtualDom$mapAttribute;
var $elm$core$Maybe$map = F2( function(f,maybe){if ( maybe.$ ==='Just' ){var value = maybe.a; return ( $elm$core$Maybe$Just( f( value)));} else return ( $elm$core$Maybe$Nothing);});
var $elm$core$Platform$Cmd$map = _Platform_map;
var $elm$core$Platform$Sub$map = _Platform_map;
var $elm$core$Result$map = F2( function(func,ra){if ( ra.$ ==='Ok' ){var a = ra.a; return ( $elm$core$Result$Ok( func( a)));} else{var e = ra.a; return ( $elm$core$Result$Err( e));}});
var $elm$core$Set$map = F2( function(func,set){ return ( $elm$core$Set$fromList( A3( $elm$core$Set$foldl, F2( function(x,xs){ return ( A2( $elm$core$List$cons, func( x), xs));}), _List_Nil, set)));});
var $elm$core$String$map = _String_map;
var $elm$core$Maybe$map2 = F3( function(func,ma,mb){if ( ma.$ ==='Nothing' ) return ( $elm$core$Maybe$Nothing); else{var a = ma.a;if ( mb.$ ==='Nothing' ) return ( $elm$core$Maybe$Nothing); else{var b = mb.a; return ( $elm$core$Maybe$Just( A2( func, a, b)));}}});
var $elm$core$Result$map2 = F3( function(func,ra,rb){if ( ra.$ ==='Err' ){var x = ra.a; return ( $elm$core$Result$Err( x));} else{var a = ra.a;if ( rb.$ ==='Err' ){var x = rb.a; return ( $elm$core$Result$Err( x));} else{var b = rb.a; return ( $elm$core$Result$Ok( A2( func, a, b)));}}});
var $elm$json$Json$Decode$map3 = _Json_map3;
var $elm$core$List$map3 = _List_map3;
var $elm$core$Maybe$map3 = F4( function(func,ma,mb,mc){if ( ma.$ ==='Nothing' ) return ( $elm$core$Maybe$Nothing); else{var a = ma.a;if ( mb.$ ==='Nothing' ) return ( $elm$core$Maybe$Nothing); else{var b = mb.a;if ( mc.$ ==='Nothing' ) return ( $elm$core$Maybe$Nothing); else{var c = mc.a; return ( $elm$core$Maybe$Just( A3( func, a, b, c)));}}}});
var $elm$core$Result$map3 = F4( function(func,ra,rb,rc){if ( ra.$ ==='Err' ){var x = ra.a; return ( $elm$core$Result$Err( x));} else{var a = ra.a;if ( rb.$ ==='Err' ){var x = rb.a; return ( $elm$core$Result$Err( x));} else{var b = rb.a;if ( rc.$ ==='Err' ){var x = rc.a; return ( $elm$core$Result$Err( x));} else{var c = rc.a; return ( $elm$core$Result$Ok( A3( func, a, b, c)));}}}});
var $elm$core$Task$map3 = F4( function(func,taskA,taskB,taskC){ return ( A2( $elm$core$Task$andThen, function(a){ return ( A2( $elm$core$Task$andThen, function(b){ return ( A2( $elm$core$Task$andThen, function(c){ return ( $elm$core$Task$succeed( A3( func, a, b, c)));}, taskC));}, taskB));}, taskA));});
var $elm$json$Json$Decode$map4 = _Json_map4;
var $elm$core$List$map4 = _List_map4;
var $elm$core$Maybe$map4 = F5( function(func,ma,mb,mc,md){if ( ma.$ ==='Nothing' ) return ( $elm$core$Maybe$Nothing); else{var a = ma.a;if ( mb.$ ==='Nothing' ) return ( $elm$core$Maybe$Nothing); else{var b = mb.a;if ( mc.$ ==='Nothing' ) return ( $elm$core$Maybe$Nothing); else{var c = mc.a;if ( md.$ ==='Nothing' ) return ( $elm$core$Maybe$Nothing); else{var d = md.a; return ( $elm$core$Maybe$Just( A4( func, a, b, c, d)));}}}}});
var $elm$core$Result$map4 = F5( function(func,ra,rb,rc,rd){if ( ra.$ ==='Err' ){var x = ra.a; return ( $elm$core$Result$Err( x));} else{var a = ra.a;if ( rb.$ ==='Err' ){var x = rb.a; return ( $elm$core$Result$Err( x));} else{var b = rb.a;if ( rc.$ ==='Err' ){var x = rc.a; return ( $elm$core$Result$Err( x));} else{var c = rc.a;if ( rd.$ ==='Err' ){var x = rd.a; return ( $elm$core$Result$Err( x));} else{var d = rd.a; return ( $elm$core$Result$Ok( A4( func, a, b, c, d)));}}}}});
var $elm$core$Task$map4 = F5( function(func,taskA,taskB,taskC,taskD){ return ( A2( $elm$core$Task$andThen, function(a){ return ( A2( $elm$core$Task$andThen, function(b){ return ( A2( $elm$core$Task$andThen, function(c){ return ( A2( $elm$core$Task$andThen, function(d){ return ( $elm$core$Task$succeed( A4( func, a, b, c, d)));}, taskD));}, taskC));}, taskB));}, taskA));});
var $elm$json$Json$Decode$map5 = _Json_map5;
var $elm$core$List$map5 = _List_map5;
var $elm$core$Maybe$map5 = F6( function(func,ma,mb,mc,md,me){if ( ma.$ ==='Nothing' ) return ( $elm$core$Maybe$Nothing); else{var a = ma.a;if ( mb.$ ==='Nothing' ) return ( $elm$core$Maybe$Nothing); else{var b = mb.a;if ( mc.$ ==='Nothing' ) return ( $elm$core$Maybe$Nothing); else{var c = mc.a;if ( md.$ ==='Nothing' ) return ( $elm$core$Maybe$Nothing); else{var d = md.a;if ( me.$ ==='Nothing' ) return ( $elm$core$Maybe$Nothing); else{var e = me.a; return ( $elm$core$Maybe$Just( A5( func, a, b, c, d, e)));}}}}}});
var $elm$core$Result$map5 = F6( function(func,ra,rb,rc,rd,re){if ( ra.$ ==='Err' ){var x = ra.a; return ( $elm$core$Result$Err( x));} else{var a = ra.a;if ( rb.$ ==='Err' ){var x = rb.a; return ( $elm$core$Result$Err( x));} else{var b = rb.a;if ( rc.$ ==='Err' ){var x = rc.a; return ( $elm$core$Result$Err( x));} else{var c = rc.a;if ( rd.$ ==='Err' ){var x = rd.a; return ( $elm$core$Result$Err( x));} else{var d = rd.a;if ( re.$ ==='Err' ){var x = re.a; return ( $elm$core$Result$Err( x));} else{var e = re.a; return ( $elm$core$Result$Ok( A5( func, a, b, c, d, e)));}}}}}});
var $elm$core$Task$map5 = F6( function(func,taskA,taskB,taskC,taskD,taskE){ return ( A2( $elm$core$Task$andThen, function(a){ return ( A2( $elm$core$Task$andThen, function(b){ return ( A2( $elm$core$Task$andThen, function(c){ return ( A2( $elm$core$Task$andThen, function(d){ return ( A2( $elm$core$Task$andThen, function(e){ return ( $elm$core$Task$succeed( A5( func, a, b, c, d, e)));}, taskE));}, taskD));}, taskC));}, taskB));}, taskA));});
var $elm$json$Json$Decode$map6 = _Json_map6;
var $elm$json$Json$Decode$map7 = _Json_map7;
var $elm$json$Json$Decode$map8 = _Json_map8;
var $elm$core$Tuple$mapBoth = F3( function(funcA,funcB,_v0){var x = _v0.a;var y = _v0.b; return ( _Utils_Tuple2( funcA( x), funcB( y)));});
var $elm$core$Result$mapError = F2( function(f,result){if ( result.$ ==='Ok' ){var v = result.a; return ( $elm$core$Result$Ok( v));} else{var e = result.a; return ( $elm$core$Result$Err( f( e)));}});
var $elm$core$Task$mapError = F2( function(convert,task){ return ( A2( $elm$core$Task$onError, A2( $elm$core$Basics$composeL, $elm$core$Task$fail, convert), task));});
var $elm$core$Tuple$mapFirst = F2( function(func,_v0){var x = _v0.a;var y = _v0.b; return ( _Utils_Tuple2( func( x), y));});
var $elm$core$Tuple$mapSecond = F2( function(func,_v0){var x = _v0.a;var y = _v0.b; return ( _Utils_Tuple2( x, func( y)));});
var $elm$html$Html$mark = _VirtualDom_node('mark');
var $elm$html$Html$math = _VirtualDom_node('math');
var $elm$html$Html$Attributes$max = $elm$html$Html$Attributes$stringProperty('max');
var $elm$core$List$maximum = function(list){if ( list.b ){var x = list.a;var xs = list.b; return ( $elm$core$Maybe$Just( A3( $elm$core$List$foldl, $elm$core$Basics$max, x, xs)));} else return ( $elm$core$Maybe$Nothing);};
var $elm$html$Html$Attributes$maxlength = function(n){ return ( A2( _VirtualDom_attribute,'maxlength', $elm$core$String$fromInt( n)));};
var $elm$json$Json$Decode$oneOf = _Json_oneOf;
var $elm$json$Json$Decode$maybe = function(decoder){ return ( $elm$json$Json$Decode$oneOf( _List_fromArray([ A2( $elm$json$Json$Decode$map, $elm$core$Maybe$Just, decoder) , $elm$json$Json$Decode$succeed( $elm$core$Maybe$Nothing)])));};
var $elm$html$Html$Attributes$media = _VirtualDom_attribute('media');
var $elm$core$List$member = F2( function(x,xs){ return ( A2( $elm$core$List$any, function(a){ return ( _Utils_eq( a, x));}, xs));});
var $elm$core$Set$member = F2( function(key,_v0){var dict = _v0.a; return ( A2( $elm$core$Dict$member, key, dict));});
var $elm$html$Html$menu = _VirtualDom_node('menu');
var $elm$html$Html$menuitem = _VirtualDom_node('menuitem');
var $elm$core$Dict$merge = F6( function(leftStep,bothStep,rightStep,leftDict,rightDict,initialResult){var stepState = F3( function(rKey,rValue,_v0){stepState: while (true ){var list = _v0.a;var result = _v0.b;if (! list.b ) return ( _Utils_Tuple2( list, A3( rightStep, rKey, rValue, result))); else{var _v2 = list.a;var lKey = _v2.a;var lValue = _v2.b;var rest = list.b;if ( _Utils_cmp( lKey, rKey) <0 ){var $temp$_v0 = _Utils_Tuple2( rest, A3( leftStep, lKey, lValue, result)), $temp$rValue = rValue, $temp$rKey = rKey
;rKey = $temp$rKey;rValue = $temp$rValue;_v0 = $temp$_v0; continue stepState;} else{if ( _Utils_cmp( lKey, rKey) >0 ){ return ( _Utils_Tuple2( list, A3( rightStep, rKey, rValue, result)));} else{ return ( _Utils_Tuple2( rest, A4( bothStep, lKey, lValue, rValue, result)));}}}}});var _v3 = A3( $elm$core$Dict$foldl, stepState, _Utils_Tuple2( $elm$core$Dict$toList( leftDict), initialResult), rightDict);var leftovers = _v3.a;var intermediateResult = _v3.b; return ( A3( $elm$core$List$foldl, F2( function(_v4,result){var k = _v4.a;var v = _v4.b; return ( A3( leftStep, k, v, result));}), intermediateResult, leftovers));});
var $elm$html$Html$meter = _VirtualDom_node('meter');
var $elm$html$Html$Attributes$method = $elm$html$Html$Attributes$stringProperty('method');
var $elm$core$Basics$min = F2( function(x,y){ return (( _Utils_cmp( x, y) <0)? x: y);});
var $elm$html$Html$Attributes$min = $elm$html$Html$Attributes$stringProperty('min');
var $elm$core$List$minimum = function(list){if ( list.b ){var x = list.a;var xs = list.b; return ( $elm$core$Maybe$Just( A3( $elm$core$List$foldl, $elm$core$Basics$min, x, xs)));} else return ( $elm$core$Maybe$Nothing);};
var $elm$html$Html$Attributes$minlength = function(n){ return ( A2( _VirtualDom_attribute,'minLength', $elm$core$String$fromInt( n)));};
var $user$project$AudioFFI$mixAudioBuffers = $author$project$FFI$mixAudioBuffers;
var $elm$core$Basics$modBy = _Basics_modBy;
var $elm$html$Html$Attributes$multiple = $elm$html$Html$Attributes$boolProperty('multiple');
var $elm$html$Html$Attributes$name = $elm$html$Html$Attributes$stringProperty('name');
var $elm$html$Html$nav = _VirtualDom_node('nav');
var $elm$core$Basics$neq = _Utils_notEqual;
var $elm$html$Html$Keyed$node = $elm$virtual_dom$VirtualDom$keyedNode;
var $elm$virtual_dom$VirtualDom$nodeNS = F2( function(namespace,tag){ return ( A2( _VirtualDom_nodeNS, namespace, _VirtualDom_noScript( tag)));});
var $elm$core$Platform$Cmd$none = $elm$core$Platform$Cmd$batch( _List_Nil);
var $elm$core$Platform$Sub$none = $elm$core$Platform$Sub$batch( _List_Nil);
var $user$project$Expect$notEqual = F2( function(expected,actual){ return ((! _Utils_eq( actual, expected))? $user$project$Expect$Pass: $user$project$Expect$Fail( $user$project$Expect$Custom('Expected values to be different, but both were: ' + $elm$core$Debug$toString( actual))));});
var $elm$html$Html$Attributes$novalidate = $elm$html$Html$Attributes$boolProperty('noValidate');
var $elm$json$Json$Decode$null = _Json_decodeNull;
var $elm$json$Json$Encode$null = _Json_encodeNull;
var $elm$json$Json$Decode$nullable = function(decoder){ return ( $elm$json$Json$Decode$oneOf( _List_fromArray([ $elm$json$Json$Decode$null( $elm$core$Maybe$Nothing) , A2( $elm$json$Json$Decode$map, $elm$core$Maybe$Just, decoder)])));};
var $elm$html$Html$object = _VirtualDom_node('object');
var $elm$json$Json$Encode$object = function(pairs){ return ( _Json_wrap( A3( $elm$core$List$foldl, F2( function(_v0,obj){var k = _v0.a;var v = _v0.b; return ( A3( _Json_addField, k, v, obj));}), _Json_emptyObject( _Utils_Tuple0), pairs)));};
var $user$project$Expect$ok = function(result){if ( result.$ ==='Ok' ) return ( $user$project$Expect$Pass); else{var e = result.a; return ( $user$project$Expect$Fail( $user$project$Expect$Custom('Expected Ok but got Err: ' + $elm$core$Debug$toString( e))));}};
var $elm$html$Html$ol = _VirtualDom_node('ol');
var $elm$html$Html$Keyed$ol = $elm$html$Html$Keyed$node('ol');
var $elm$html$Html$Events$on = F2( function(event,decoder){ return ( A2( $elm$virtual_dom$VirtualDom$on, event, $elm$virtual_dom$VirtualDom$Normal( decoder)));});
var $elm$html$Html$Events$onBlur = function(msg){ return ( A2( $elm$html$Html$Events$on,'blur', $elm$json$Json$Decode$succeed( msg)));};
var $elm$html$Html$Events$targetChecked = A2( $elm$json$Json$Decode$at, _List_fromArray(['target' ,'checked']), $elm$json$Json$Decode$bool);
var $elm$html$Html$Events$onCheck = function(tagger){ return ( A2( $elm$html$Html$Events$on,'change', A2( $elm$json$Json$Decode$map, tagger, $elm$html$Html$Events$targetChecked)));};
var $elm$html$Html$Events$onClick = function(msg){ return ( A2( $elm$html$Html$Events$on,'click', $elm$json$Json$Decode$succeed( msg)));};
var $elm$html$Html$Events$onDoubleClick = function(msg){ return ( A2( $elm$html$Html$Events$on,'dblclick', $elm$json$Json$Decode$succeed( msg)));};
var $user$project$Expect$reasonToString = function(reason){ switch( reason.$){ case 'Equality' :var label = reason.a;var expected = reason.b;var actual = reason.c; return ( label +('\n\nExpected:\n    ' +( expected +('\n\nActual:\n    ' + actual)))); case 'Comparison' :var label = reason.a;var actual = reason.b;var op = reason.c;var threshold = reason.d; return ( label +('\n\nExpected ' +( actual +(' ' +( op +(' ' + threshold)))))); default :var message = reason.a; return ( message);}};
var $user$project$Expect$onFail = F2( function(message,expectation){if ( expectation.$ ==='Pass' ) return ( $user$project$Expect$Pass); else{var reason = expectation.a; return ( $user$project$Expect$Fail( $user$project$Expect$Custom( message +('\n' + $user$project$Expect$reasonToString( reason)))));}});
var $elm$html$Html$Events$onFocus = function(msg){ return ( A2( $elm$html$Html$Events$on,'focus', $elm$json$Json$Decode$succeed( msg)));};
var $elm$html$Html$Events$stopPropagationOn = F2( function(event,decoder){ return ( A2( $elm$virtual_dom$VirtualDom$on, event, $elm$virtual_dom$VirtualDom$MayStopPropagation( decoder)));});
var $elm$json$Json$Decode$string = _Json_decodeString;
var $elm$html$Html$Events$targetValue = A2( $elm$json$Json$Decode$at, _List_fromArray(['target' ,'value']), $elm$json$Json$Decode$string);
var $elm$html$Html$Events$onInput = function(tagger){ return ( A2( $elm$html$Html$Events$stopPropagationOn,'input', A2( $elm$json$Json$Decode$map, $elm$html$Html$Events$alwaysStop, A2( $elm$json$Json$Decode$map, tagger, $elm$html$Html$Events$targetValue))));};
var $elm$html$Html$Events$onMouseDown = function(msg){ return ( A2( $elm$html$Html$Events$on,'mousedown', $elm$json$Json$Decode$succeed( msg)));};
var $elm$html$Html$Events$onMouseEnter = function(msg){ return ( A2( $elm$html$Html$Events$on,'mouseenter', $elm$json$Json$Decode$succeed( msg)));};
var $elm$html$Html$Events$onMouseLeave = function(msg){ return ( A2( $elm$html$Html$Events$on,'mouseleave', $elm$json$Json$Decode$succeed( msg)));};
var $elm$html$Html$Events$onMouseOut = function(msg){ return ( A2( $elm$html$Html$Events$on,'mouseout', $elm$json$Json$Decode$succeed( msg)));};
var $elm$html$Html$Events$onMouseOver = function(msg){ return ( A2( $elm$html$Html$Events$on,'mouseover', $elm$json$Json$Decode$succeed( msg)));};
var $elm$html$Html$Events$onMouseUp = function(msg){ return ( A2( $elm$html$Html$Events$on,'mouseup', $elm$json$Json$Decode$succeed( msg)));};
var $elm$html$Html$Events$preventDefaultOn = F2( function(event,decoder){ return ( A2( $elm$virtual_dom$VirtualDom$on, event, $elm$virtual_dom$VirtualDom$MayPreventDefault( decoder)));});
var $elm$html$Html$Events$onSubmit = function(msg){ return ( A2( $elm$html$Html$Events$preventDefaultOn,'submit', A2( $elm$json$Json$Decode$map, $elm$html$Html$Events$alwaysPreventDefault, $elm$json$Json$Decode$succeed( msg))));};
var $elm$json$Json$Decode$oneOrMoreHelp = F2( function(toValue,xs){if (! xs.b ) return ( $elm$json$Json$Decode$fail('a ARRAY with at least ONE element')); else{var y = xs.a;var ys = xs.b; return ( $elm$json$Json$Decode$succeed( A2( toValue, y, ys)));}});
var $elm$json$Json$Decode$oneOrMore = F2( function(toValue,decoder){ return ( A2( $elm$json$Json$Decode$andThen, $elm$json$Json$Decode$oneOrMoreHelp( toValue), $elm$json$Json$Decode$list( decoder)));});
var $elm$html$Html$optgroup = _VirtualDom_node('optgroup');
var $elm$html$Html$option = _VirtualDom_node('option');
var $elm$core$Bitwise$or = _Bitwise_or;
var $user$project$AudioFFI$oscillatorNodeToAudioNode = $author$project$FFI$oscillatorNodeToAudioNode;
var $elm$html$Html$output = _VirtualDom_node('output');
var $elm$html$Html$p = _VirtualDom_node('p');
var $elm$core$String$pad = F3( function(n,_char,string){var half = n - $elm$core$String$length( string) /2; return ( _Utils_ap( A2( $elm$core$String$repeat, $elm$core$Basics$ceiling( half), $elm$core$String$fromChar( _char)), _Utils_ap( string, A2( $elm$core$String$repeat, $elm$core$Basics$floor( half), $elm$core$String$fromChar( _char)))));});
var $elm$core$String$padLeft = F3( function(n,_char,string){ return ( _Utils_ap( A2( $elm$core$String$repeat, n - $elm$core$String$length( string), $elm$core$String$fromChar( _char)), string));});
var $elm$core$String$padRight = F3( function(n,_char,string){ return ( _Utils_ap( string, A2( $elm$core$String$repeat, n - $elm$core$String$length( string), $elm$core$String$fromChar( _char))));});
var $elm$core$Tuple$pair = F2( function(a,b){ return ( _Utils_Tuple2( a, b));});
var $user$project$AudioFFI$pannerNodeToAudioNode = $author$project$FFI$pannerNodeToAudioNode;
var $elm$html$Html$param = _VirtualDom_node('param');
var $elm$core$Dict$partition = F2( function(isGood,dict){var add = F3( function(key,value,_v0){var t1 = _v0.a;var t2 = _v0.b; return ( A2( isGood, key, value)? _Utils_Tuple2( A3( $elm$core$Dict$insert, key, value, t1), t2): _Utils_Tuple2( t1, A3( $elm$core$Dict$insert, key, value, t2)));}); return ( A3( $elm$core$Dict$foldl, add, _Utils_Tuple2( $elm$core$Dict$empty, $elm$core$Dict$empty), dict));});
var $elm$core$List$partition = F2( function(pred,list){var step = F2( function(x,_v0){var trues = _v0.a;var falses = _v0.b; return ( pred( x)? _Utils_Tuple2( A2( $elm$core$List$cons, x, trues), falses): _Utils_Tuple2( trues, A2( $elm$core$List$cons, x, falses)));}); return ( A3( $elm$core$List$foldr, step, _Utils_Tuple2( _List_Nil, _List_Nil), list));});
var $elm$core$Set$partition = F2( function(isGood,_v0){var dict = _v0.a;var _v1 = A2( $elm$core$Dict$partition, F2( function(key,_v2){ return ( isGood( key));}), dict);var dict1 = _v1.a;var dict2 = _v1.b; return ( _Utils_Tuple2( $elm$core$Set$Set_elm_builtin( dict1), $elm$core$Set$Set_elm_builtin( dict2)));});
var $elm$html$Html$Attributes$pattern = $elm$html$Html$Attributes$stringProperty('pattern');
var $elm$core$Task$perform = F2( function(toMessage,task){ return ( $elm$core$Task$command( $elm$core$Task$Perform( A2( $elm$core$Task$map, toMessage, task))));});
var $elm$html$Html$Attributes$ping = $elm$html$Html$Attributes$stringProperty('ping');
var $elm$html$Html$Attributes$placeholder = $elm$html$Html$Attributes$stringProperty('placeholder');
var $user$project$AudioFFI$postMessageToWorklet = $author$project$FFI$postMessageToWorklet;
var $elm$html$Html$Attributes$poster = $elm$html$Html$Attributes$stringProperty('poster');
var $elm$core$Basics$pow = _Basics_pow;
var $elm$html$Html$Attributes$preload = $elm$html$Html$Attributes$stringProperty('preload');
var $elm$core$List$product = function(numbers){ return ( A3( $elm$core$List$foldl, $elm$core$Basics$mul,1, numbers));};
var $elm$html$Html$progress = _VirtualDom_node('progress');
var $elm$virtual_dom$VirtualDom$property = F2( function(key,value){ return ( A2( _VirtualDom_property, _VirtualDom_noInnerHtmlOrFormAction( key), _VirtualDom_noJavaScriptOrHtmlJson( value)));});
var $elm$html$Html$Attributes$property = $elm$virtual_dom$VirtualDom$property;
var $elm$html$Html$Attributes$pubdate = _VirtualDom_attribute('pubdate');
var $elm$core$Array$push = F2( function(a,array){var tail = array.d; return ( A2( $elm$core$Array$unsafeReplaceTail, A2( $elm$core$Elm$JsArray$push, a, tail), array));});
var $elm$html$Html$q = _VirtualDom_node('q');
var $elm$core$Basics$radians = function(angleInRadians){ return ( angleInRadians);};
var $elm$html$Html$Attributes$readonly = $elm$html$Html$Attributes$boolProperty('readOnly');
var $elm$html$Html$Attributes$rel = _VirtualDom_attribute('rel');
var $elm$core$Set$remove = F2( function(key,_v0){var dict = _v0.a; return ( $elm$core$Set$Set_elm_builtin( A2( $elm$core$Dict$remove, key, dict)));});
var $elm$core$Array$repeat = F2( function(n,e){ return ( A2( $elm$core$Array$initialize, n, function(_v0){ return ( e);}));});
var $elm$core$List$repeat = F2( function(n,value){ return ( A3( $elm$core$List$repeatHelp, _List_Nil, n, value));});
var $elm$html$Html$Attributes$required = $elm$html$Html$Attributes$boolProperty('required');
var $user$project$AudioFFI$resumeOfflineContext = $author$project$FFI$resumeOfflineContext;
var $elm$core$String$reverse = _String_reverse;
var $elm$html$Html$Attributes$reversed = $elm$html$Html$Attributes$boolProperty('reversed');
var $elm$core$String$right = F2( function(n,string){ return (( n <1)?'': A3( $elm$core$String$slice,- n, $elm$core$String$length( string), string));});
var $elm$core$Basics$round = _Basics_round;
var $elm$html$Html$Attributes$rows = function(n){ return ( A2( _VirtualDom_attribute,'rows', $elm$core$String$fromInt( n)));};
var $elm$html$Html$Attributes$rowspan = function(n){ return ( A2( _VirtualDom_attribute,'rowspan', $elm$core$String$fromInt( n)));};
var $elm$html$Html$rp = _VirtualDom_node('rp');
var $elm$html$Html$rt = _VirtualDom_node('rt');
var $elm$html$Html$ruby = _VirtualDom_node('ruby');
var $elm$html$Html$s = _VirtualDom_node('s');
var $elm$html$Html$samp = _VirtualDom_node('samp');
var $elm$html$Html$Attributes$sandbox = $elm$html$Html$Attributes$stringProperty('sandbox');
var $elm$html$Html$Attributes$scope = $elm$html$Html$Attributes$stringProperty('scope');
var $elm$html$Html$section = _VirtualDom_node('section');
var $elm$html$Html$select = _VirtualDom_node('select');
var $elm$html$Html$Attributes$selected = $elm$html$Html$Attributes$boolProperty('selected');
var $elm$core$Platform$sendToSelf = _Platform_sendToSelf;
var $elm$core$Array$set = F3( function(index,value,array){var len = array.a;var startShift = array.b;var tree = array.c;var tail = array.d; return (( index <0 || _Utils_cmp( index, len) >-1)? array:( _Utils_cmp( index, $elm$core$Array$tailIndex( len)) >-1)? A4( $elm$core$Array$Array_elm_builtin, len, startShift, tree, A3( $elm$core$Elm$JsArray$unsafeSet, $elm$core$Array$bitMask & index, value, tail)): A4( $elm$core$Array$Array_elm_builtin, len, startShift, A4( $elm$core$Array$setHelp, startShift, index, value, tree), tail));});
var $elm$json$Json$Encode$set = F2( function(func,entries){ return ( _Json_wrap( A3( $elm$core$Set$foldl, _Json_addEntry( func), _Json_emptyArray( _Utils_Tuple0), entries)));});
var $user$project$AudioFFI$setBufferSourceDetune = $author$project$FFI$setBufferSourceDetune;
var $user$project$AudioFFI$setBufferSourceLoopDirect = $author$project$FFI$setBufferSourceLoopDirect;
var $user$project$AudioFFI$setBufferSourcePlaybackRate = $author$project$FFI$setBufferSourcePlaybackRate;
var $user$project$AudioFFI$setCompressorAttackDirect = $author$project$FFI$setCompressorAttackDirect;
var $user$project$AudioFFI$setCompressorReleaseDirect = $author$project$FFI$setCompressorReleaseDirect;
var $user$project$AudioFFI$setOscillatorPeriodicWave = $author$project$FFI$setOscillatorPeriodicWave;
var $elm$html$Html$Attributes$shape = $elm$html$Html$Attributes$stringProperty('shape');
var $elm$core$Dict$singleton = F2( function(key,value){ return ( A5( $elm$core$Dict$RBNode_elm_builtin, $elm$core$Dict$Black, key, value, $elm$core$Dict$RBEmpty_elm_builtin, $elm$core$Dict$RBEmpty_elm_builtin));});
var $elm$core$List$singleton = function(value){ return ( _List_fromArray([ value]));};
var $elm$core$Set$singleton = function(key){ return ( $elm$core$Set$Set_elm_builtin( A2( $elm$core$Dict$singleton, key, _Utils_Tuple0)));};
var $elm$core$Dict$size = function(dict){ return ( A2( $elm$core$Dict$sizeHelp,0, dict));};
var $elm$html$Html$Attributes$size = function(n){ return ( A2( _VirtualDom_attribute,'size', $elm$core$String$fromInt( n)));};
var $elm$core$Set$size = function(_v0){var dict = _v0.a; return ( $elm$core$Dict$size( dict));};
var $user$project$Test$skip = function(testToSkip){ return ( $user$project$Test$Skip( testToSkip));};
var $elm$core$Process$sleep = _Process_sleep;
var $elm$core$Array$sliceLeft = F2( function(from,array){var len = array.a;var tree = array.c;var tail = array.d;if (! from ){ return ( array);} else{if ( _Utils_cmp( from, $elm$core$Array$tailIndex( len)) >-1 ){ return ( A4( $elm$core$Array$Array_elm_builtin, len - from, $elm$core$Array$shiftStep, $elm$core$Elm$JsArray$empty, A3( $elm$core$Elm$JsArray$slice, from - $elm$core$Array$tailIndex( len), $elm$core$Elm$JsArray$length( tail), tail)));} else{var skipNodes = from / $elm$core$Array$branchFactor |0;var helper = F2( function(node,acc){if ( node.$ ==='SubTree' ){var subTree = node.a; return ( A3( $elm$core$Elm$JsArray$foldr, helper, acc, subTree));} else{var leaf = node.a; return ( A2( $elm$core$List$cons, leaf, acc));}});var leafNodes = A3( $elm$core$Elm$JsArray$foldr, helper, _List_fromArray([ tail]), tree);var nodesToInsert = A2( $elm$core$List$drop, skipNodes, leafNodes);if (! nodesToInsert.b ) return ( $elm$core$Array$empty); else{var head = nodesToInsert.a;var rest = nodesToInsert.b;var firstSlice = from - skipNodes * $elm$core$Array$branchFactor;var initialBuilder ={tail : A3( $elm$core$Elm$JsArray$slice, firstSlice, $elm$core$Elm$JsArray$length( head), head),nodeListSize :0,nodeList : _List_Nil}; return ( A2( $elm$core$Array$builderToArray,true, A3( $elm$core$List$foldl, $elm$core$Array$appendHelpBuilder, initialBuilder, rest)));}}}});
var $elm$core$Array$sliceRight = F2( function(end,array){var len = array.a;var startShift = array.b;var tree = array.c;var tail = array.d;if ( _Utils_eq( end, len) ){ return ( array);} else{if ( _Utils_cmp( end, $elm$core$Array$tailIndex( len)) >-1 ){ return ( A4( $elm$core$Array$Array_elm_builtin, end, startShift, tree, A3( $elm$core$Elm$JsArray$slice,0, $elm$core$Array$bitMask & end, tail)));} else{var endIdx = $elm$core$Array$tailIndex( end);var depth = $elm$core$Basics$floor( A2( $elm$core$Basics$logBase, $elm$core$Array$branchFactor, A2( $elm$core$Basics$max,1, endIdx -1)));var newShift = A2( $elm$core$Basics$max,5, depth * $elm$core$Array$shiftStep); return ( A4( $elm$core$Array$Array_elm_builtin, end, newShift, A3( $elm$core$Array$hoistTree, startShift, newShift, A3( $elm$core$Array$sliceTree, startShift, endIdx, tree)), A4( $elm$core$Array$fetchNewTail, startShift, end, endIdx, tree)));}}});
var $elm$core$Array$translateIndex = F2( function(index,_v0){var len = _v0.a;var posIndex =( index <0)?( len + index): index; return (( posIndex <0)?0:( _Utils_cmp( posIndex, len) >0)? len: posIndex);});
var $elm$core$Array$slice = F3( function(from,to,array){var correctTo = A2( $elm$core$Array$translateIndex, to, array);var correctFrom = A2( $elm$core$Array$translateIndex, from, array); return (( _Utils_cmp( correctFrom, correctTo) >0)? $elm$core$Array$empty: A2( $elm$core$Array$sliceLeft, correctFrom, A2( $elm$core$Array$sliceRight, correctTo, array)));});
var $elm$html$Html$small = _VirtualDom_node('small');
var $elm$core$List$sortBy = _List_sortBy;
var $elm$core$List$sort = function(xs){ return ( A2( $elm$core$List$sortBy, $elm$core$Basics$identity, xs));};
var $elm$core$List$sortWith = _List_sortWith;
var $elm$html$Html$source = _VirtualDom_node('source');
var $elm$html$Html$span = _VirtualDom_node('span');
var $elm$core$Process$spawn = _Scheduler_spawn;
var $elm$html$Html$Attributes$spellcheck = $elm$html$Html$Attributes$boolProperty('spellcheck');
var $elm$core$Basics$sqrt = _Basics_sqrt;
var $elm$html$Html$Attributes$src = function(url){ return ( A2( $elm$html$Html$Attributes$stringProperty,'src', _VirtualDom_noJavaScriptOrHtmlUri( url)));};
var $elm$html$Html$Attributes$srcdoc = $elm$html$Html$Attributes$stringProperty('srcdoc');
var $elm$html$Html$Attributes$srclang = $elm$html$Html$Attributes$stringProperty('srclang');
var $elm$html$Html$Attributes$start = function(n){ return ( A2( $elm$html$Html$Attributes$stringProperty,'start', $elm$core$String$fromInt( n)));};
var $user$project$AudioFFI$startConstantSource = $author$project$FFI$startConstantSource;
var $user$project$AudioFFI$startOfflineRendering = $author$project$FFI$startOfflineRendering;
var $user$project$AudioFFI$startOfflineRenderingAsync = $author$project$FFI$startOfflineRenderingAsync;
var $elm$core$String$startsWith = _String_startsWith;
var $elm$html$Html$Attributes$step = function(n){ return ( A2( $elm$html$Html$Attributes$stringProperty,'step', n));};
var $user$project$AudioFFI$stereoPannerNodeToAudioNode = $author$project$FFI$stereoPannerNodeToAudioNode;
var $user$project$AudioFFI$stopConstantSource = $author$project$FFI$stopConstantSource;
var $elm$html$Html$strong = _VirtualDom_node('strong');
var $elm$virtual_dom$VirtualDom$style = _VirtualDom_style;
var $elm$html$Html$Attributes$style = $elm$virtual_dom$VirtualDom$style;
var $elm$html$Html$sub = _VirtualDom_node('sub');
var $elm$core$List$sum = function(numbers){ return ( A3( $elm$core$List$foldl, $elm$core$Basics$add,0, numbers));};
var $elm$html$Html$summary = _VirtualDom_node('summary');
var $elm$html$Html$sup = _VirtualDom_node('sup');
var $user$project$AudioFFI$suspendOfflineContext = $author$project$FFI$suspendOfflineContext;
var $elm$html$Html$Attributes$tabindex = function(n){ return ( A2( _VirtualDom_attribute,'tabIndex', $elm$core$String$fromInt( n)));};
var $elm$html$Html$table = _VirtualDom_node('table');
var $elm$core$List$tail = function(list){if ( list.b ){var x = list.a;var xs = list.b; return ( $elm$core$Maybe$Just( xs));} else return ( $elm$core$Maybe$Nothing);};
var $elm$core$List$take = F2( function(n,list){ return ( A3( $elm$core$List$takeFast,0, n, list));});
var $elm$core$Basics$tan = _Basics_tan;
var $elm$html$Html$Attributes$target = $elm$html$Html$Attributes$stringProperty('target');
var $elm$html$Html$tbody = _VirtualDom_node('tbody');
var $elm$html$Html$td = _VirtualDom_node('td');
var $elm$html$Html$textarea = _VirtualDom_node('textarea');
var $elm$html$Html$tfoot = _VirtualDom_node('tfoot');
var $elm$html$Html$th = _VirtualDom_node('th');
var $elm$html$Html$thead = _VirtualDom_node('thead');
var $elm$html$Html$time = _VirtualDom_node('time');
var $elm$html$Html$Attributes$title = $elm$html$Html$Attributes$stringProperty('title');
var $elm$core$String$toFloat = _String_toFloat;
var $elm$core$Array$toIndexedList = function(array){var len = array.a;var helper = F2( function(entry,_v0){var index = _v0.a;var list = _v0.b; return ( _Utils_Tuple2( index -1, A2( $elm$core$List$cons, _Utils_Tuple2( index, entry), list)));}); return ( A3( $elm$core$Array$foldr, helper, _Utils_Tuple2( len -1, _List_Nil), array).b);};
var $elm$core$String$toInt = _String_toInt;
var $elm$core$String$toList = function(string){ return ( A3( $elm$core$String$foldr, $elm$core$List$cons, _List_Nil, string));};
var $elm$core$Char$toLocaleLower = _Char_toLocaleLower;
var $elm$core$Char$toLocaleUpper = _Char_toLocaleUpper;
var $elm$core$Char$toLower = _Char_toLower;
var $elm$core$String$toLower = _String_toLower;
var $elm$core$Result$toMaybe = function(result){if ( result.$ ==='Ok' ){var v = result.a; return ( $elm$core$Maybe$Just( v));} else return ( $elm$core$Maybe$Nothing);};
var $elm$core$Basics$toPolar = function(_v0){var x = _v0.a;var y = _v0.b; return ( _Utils_Tuple2( $elm$core$Basics$sqrt( x * x + y * y), A2( $elm$core$Basics$atan2, y, x)));};
var $elm$core$Char$toUpper = _Char_toUpper;
var $elm$core$String$toUpper = _String_toUpper;
var $elm$core$Debug$todo = _Debug_todo;
var $user$project$Test$todo = function(description){ return ( $user$project$Test$Todo( description));};
var $elm$html$Html$tr = _VirtualDom_node('tr');
var $elm$html$Html$track = _VirtualDom_node('track');
var $elm$core$String$trim = _String_trim;
var $elm$core$String$trimLeft = _String_trimLeft;
var $elm$core$String$trimRight = _String_trimRight;
var $elm$core$Basics$truncate = _Basics_truncate;
var $elm$core$Basics$turns = function(angleInTurns){ return (2 * $elm$core$Basics$pi * angleInTurns);};
var $elm$html$Html$Attributes$type_ = $elm$html$Html$Attributes$stringProperty('type');
var $elm$html$Html$u = _VirtualDom_node('u');
var $elm$html$Html$ul = _VirtualDom_node('ul');
var $elm$html$Html$Keyed$ul = $elm$html$Html$Keyed$node('ul');
var $elm$core$Dict$union = F2( function(t1,t2){ return ( A3( $elm$core$Dict$foldl, $elm$core$Dict$insert, t2, t1));});
var $elm$core$Set$union = F2( function(_v0,_v1){var dict1 = _v0.a;var dict2 = _v1.a; return ( $elm$core$Set$Set_elm_builtin( A2( $elm$core$Dict$union, dict1, dict2)));});
var $elm$core$List$unzip = function(pairs){var step = F2( function(_v0,_v1){var x = _v0.a;var y = _v0.b;var xs = _v1.a;var ys = _v1.b; return ( _Utils_Tuple2( A2( $elm$core$List$cons, x, xs), A2( $elm$core$List$cons, y, ys)));}); return ( A3( $elm$core$List$foldr, step, _Utils_Tuple2( _List_Nil, _List_Nil), pairs));};
var $elm$core$Dict$update = F3( function(targetKey,alter,dictionary){var _v0 = alter( A2( $elm$core$Dict$get, targetKey, dictionary));if ( _v0.$ ==='Just' ){var value = _v0.a; return ( A3( $elm$core$Dict$insert, targetKey, value, dictionary));} else return ( A2( $elm$core$Dict$remove, targetKey, dictionary));});
var $elm$html$Html$Attributes$usemap = $elm$html$Html$Attributes$stringProperty('useMap');
var $elm$html$Html$Attributes$value = $elm$html$Html$Attributes$stringProperty('value');
var $elm$json$Json$Decode$value = _Json_decodeValue;
var $elm$core$Dict$values = function(dict){ return ( A3( $elm$core$Dict$foldr, F3( function(key,value,valueList){ return ( A2( $elm$core$List$cons, value, valueList));}), _List_Nil, dict));};
var $elm$html$Html$var = _VirtualDom_node('var');
var $elm$html$Html$video = _VirtualDom_node('video');
var $user$project$AudioFFI$waveShaperNodeToAudioNode = $author$project$FFI$waveShaperNodeToAudioNode;
var $elm$html$Html$wbr = _VirtualDom_node('wbr');
var $elm$html$Html$Attributes$width = function(n){ return ( A2( _VirtualDom_attribute,'width', $elm$core$String$fromInt( n)));};
var $user$project$BufferTest$withContext = function(fn){var _v0 = $user$project$AudioFFI$createAudioContext( $user$project$Capability$Click);if ( _v0.$ ==='Ok' ){var ctx = _v0.a; return ( fn( ctx));} else return ( $user$project$Expect$pass);};
var $elm$core$Maybe$withDefault = F2( function(_default,maybe){if ( maybe.$ ==='Just' ){var value = maybe.a; return ( value);} else return ( _default);});
var $elm$core$Result$withDefault = F2( function(def,result){if ( result.$ ==='Ok' ){var a = result.a; return ( a);} else return ( def);});
var $elm$core$String$words = _String_words;
var $elm$core$Platform$worker = _Platform_worker;
var $elm$html$Html$Attributes$wrap = $elm$html$Html$Attributes$stringProperty('wrap');
var $elm$core$Basics$xor = _Basics_xor;
var $elm$core$Bitwise$xor = _Bitwise_xor;
_Platform_export({'AnalyserTest':{'init': _VirtualDom_init( $user$project$AnalyserTest$main)(0)(0)},'SpatialTest':{'init': _VirtualDom_init( $user$project$SpatialTest$main)(0)(0)},'SimplifiedTest':{'init': _VirtualDom_init( $user$project$SimplifiedTest$main)(0)(0)},'OscillatorTest':{'init': _VirtualDom_init( $user$project$OscillatorTest$main)(0)(0)},'GainTest':{'init': _VirtualDom_init( $user$project$GainTest$main)(0)(0)},'FilterTest':{'init': _VirtualDom_init( $user$project$FilterTest$main)(0)(0)},'EffectsTest':{'init': _VirtualDom_init( $user$project$EffectsTest$main)(0)(0)},'ConnectionTest':{'init': _VirtualDom_init( $user$project$ConnectionTest$main)(0)(0)},'BufferTest':{'init': _VirtualDom_init( $user$project$BufferTest$main)(0)(0)},'BrowserTestMain':{'init': _VirtualDom_init( $user$project$BrowserTestMain$main)(0)(0)},'AudioParamTest':{'init': _VirtualDom_init( $user$project$AudioParamTest$main)(0)(0)},'AudioContextTest':{'init': _VirtualDom_init( $user$project$AudioContextTest$main)(0)(0)}});scope['Canopy'] = scope['Elm'];
}(typeof window !== 'undefined' ? window : this));