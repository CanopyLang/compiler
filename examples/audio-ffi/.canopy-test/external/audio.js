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
 * @canopy-type ConvolverNode -> Bool -> ()
 */
function setConvolverNormalize(convolver, normalize) {
    convolver.normalize = normalize;
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
 * @canopy-type WaveShaperNode -> String -> ()
 */
function setWaveShaperOversample(shaper, oversample) {
    shaper.oversample = oversample;
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
 * @name setAnalyserFFTSize
 * @canopy-type AnalyserNode -> Int -> ()
 */
function setAnalyserFFTSize(analyser, fftSize) {
    analyser.fftSize = fftSize;
}

/**
 * Set analyzer smoothing time constant
 * @name setAnalyserSmoothing
 * @canopy-type AnalyserNode -> Float -> ()
 */
function setAnalyserSmoothing(analyser, smoothing) {
    analyser.smoothingTimeConstant = smoothing;
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
 * @name setPanningModel
 * @canopy-type PannerNode -> String -> ()
 */
function setPanningModel(panner, model) {
    panner.panningModel = model;
}

/**
 * Set distance model
 * @name setDistanceModel
 * @canopy-type PannerNode -> String -> ()
 */
function setDistanceModel(panner, model) {
    panner.distanceModel = model;
}

/**
 * Set reference distance
 * @name setRefDistance
 * @canopy-type PannerNode -> Float -> ()
 */
function setRefDistance(panner, distance) {
    panner.refDistance = distance;
}

/**
 * Set maximum distance
 * @name setMaxDistance
 * @canopy-type PannerNode -> Float -> ()
 */
function setMaxDistance(panner, distance) {
    panner.maxDistance = distance;
}

/**
 * Set rolloff factor
 * @name setRolloffFactor
 * @canopy-type PannerNode -> Float -> ()
 */
function setRolloffFactor(panner, factor) {
    panner.rolloffFactor = factor;
}

/**
 * Set cone inner angle
 * @name setConeInnerAngle
 * @canopy-type PannerNode -> Float -> ()
 */
function setConeInnerAngle(panner, angle) {
    panner.coneInnerAngle = angle;
}

/**
 * Set cone outer angle
 * @name setConeOuterAngle
 * @canopy-type PannerNode -> Float -> ()
 */
function setConeOuterAngle(panner, angle) {
    panner.coneOuterAngle = angle;
}

/**
 * Set cone outer gain
 * @name setConeOuterGain
 * @canopy-type PannerNode -> Float -> ()
 */
function setConeOuterGain(panner, gain) {
    panner.coneOuterGain = gain;
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

/**
 * Set buffer on buffer source
 * @name setBufferSourceBuffer
 * @canopy-type AudioBufferSourceNode -> AudioBuffer -> ()
 */
function setBufferSourceBuffer(source, buffer) {
    source.buffer = buffer;
}

/**
 * Set buffer source loop
 * @name setBufferSourceLoop
 * @canopy-type AudioBufferSourceNode -> Bool -> ()
 */
function setBufferSourceLoop(source, loop) {
    source.loop = loop;
}

/**
 * Set buffer source loop start
 * @name setBufferSourceLoopStart
 * @canopy-type AudioBufferSourceNode -> Float -> ()
 */
function setBufferSourceLoopStart(source, loopStart) {
    source.loopStart = loopStart;
}

/**
 * Set buffer source loop end
 * @name setBufferSourceLoopEnd
 * @canopy-type AudioBufferSourceNode -> Float -> ()
 */
function setBufferSourceLoopEnd(source, loopEnd) {
    source.loopEnd = loopEnd;
}

/**
 * Set buffer source playback rate
 * @name setBufferSourcePlaybackRate
 * @canopy-type AudioBufferSourceNode -> Float -> Float -> ()
 */
function setBufferSourcePlaybackRate(source, rate, when) {
    source.playbackRate.setValueAtTime(rate, when);
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
