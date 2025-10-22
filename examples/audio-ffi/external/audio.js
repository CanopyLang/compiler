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
 * @canopy-type UserActivated -> Result Capability.CapabilityError (Initialized AudioContext)
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
 * @canopy-type Initialized AudioContext -> Float
 */
function getCurrentTime(initializedContext) {
    const audioContext = initializedContext.a;
    return audioContext.currentTime;
}

/**
 * Resume audio context with error handling
 * @name resumeAudioContext
 * @canopy-type Initialized AudioContext -> Result Capability.CapabilityError (Initialized AudioContext)
 */
function resumeAudioContext(initializedContext) {
    try {
        // Extract AudioContext from Initialized wrapper
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
 * @canopy-type AudioContext -> Result Capability.CapabilityError Basics.Int
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

// ============================================================================
// SOURCE NODES - Audio Generation
// ============================================================================

/**
 * Create oscillator node with error handling
 * @name createOscillator
 * @canopy-type Initialized AudioContext -> Float -> String -> Result Capability.CapabilityError OscillatorNode
 */
function createOscillator(initializedContext, frequency, waveType) {
    try {
        // Extract AudioContext from Initialized wrapper
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
 * @canopy-type OscillatorNode -> Float -> Result Capability.CapabilityError Basics.Int
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
 * @canopy-type OscillatorNode -> Float -> Result Capability.CapabilityError Basics.Int
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
 * Start buffer source with error handling
 * @name startBufferSource
 * @canopy-type AudioBufferSourceNode -> Float -> Result Capability.CapabilityError Basics.Int
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
 * @canopy-type AudioBufferSourceNode -> Float -> Result Capability.CapabilityError Basics.Int
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
 * @canopy-type Initialized AudioContext -> Float -> Result Capability.CapabilityError GainNode
 */
function createGainNode(initializedContext, gain) {
    try {
        // Extract AudioContext from Initialized wrapper
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
 * @canopy-type GainNode -> Float -> Float -> Result Capability.CapabilityError Basics.Int
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
 * @canopy-type GainNode -> Float -> Float -> Result Capability.CapabilityError Basics.Int
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
 * @canopy-type GainNode -> Float -> Float -> Result Capability.CapabilityError Basics.Int
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
 * @canopy-type OscillatorNode -> GainNode -> Result Capability.CapabilityError Basics.Int
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
 * @canopy-type GainNode -> Initialized AudioContext -> Result Capability.CapabilityError Basics.Int
 */
function connectToDestination(node, initializedContext) {
    try {
        // Extract AudioContext from Initialized wrapper
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
 * Check Web Audio support
 * @name checkWebAudioSupport
 * @canopy-type String
 */
var checkWebAudioSupport = (function() {
    if (window.AudioContext) {
        return "Supported";
    } else if (window.webkitAudioContext) {
        return "Prefixed-webkit";
    } else {
        return "PartialSupport";
    }
})();

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Simple test function for FFI validation
 * @name simpleTest
 * @canopy-type Int -> Int
 */
function simpleTest(x) {
    return x + 1;
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
// ANALYSER NODE - Advanced Functions
// ============================================================================

/**
 * Get byte time domain data
 * @name getByteTimeDomainData
 * @canopy-type AnalyserNode -> Int
 */
function getByteTimeDomainData(analyser) {
    const dataArray = new Uint8Array(analyser.frequencyBinCount);
    analyser.getByteTimeDomainData(dataArray);
    return dataArray[0];
}

/**
 * Get byte frequency data
 * @name getByteFrequencyData
 * @canopy-type AnalyserNode -> Int
 */
function getByteFrequencyData(analyser) {
    const dataArray = new Uint8Array(analyser.frequencyBinCount);
    analyser.getByteFrequencyData(dataArray);
    return dataArray[0];
}

/**
 * Get float time domain data
 * @name getFloatTimeDomainData
 * @canopy-type AnalyserNode -> Float
 */
function getFloatTimeDomainData(analyser) {
    const dataArray = new Float32Array(analyser.frequencyBinCount);
    analyser.getFloatTimeDomainData(dataArray);
    return dataArray[0];
}

/**
 * Get float frequency data
 * @name getFloatFrequencyData
 * @canopy-type AnalyserNode -> Float
 */
function getFloatFrequencyData(analyser) {
    const dataArray = new Float32Array(analyser.frequencyBinCount);
    analyser.getFloatFrequencyData(dataArray);
    return dataArray[0];
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
