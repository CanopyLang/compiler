/**
 * Web Audio API FFI for Canopy
 *
 * Provides type-safe bindings to the Web Audio API with capability-based security.
 */

// Audio Context Management

/**
 * Create a new AudioContext
 * @canopy-type () -> Task AudioError (AudioContext ())
 * @name createContext
 * @returns {AudioContext} A new audio context
 */
function createContext() {
    try {
        return new AudioContext();
    } catch (e) {
        throw new AudioError(`Failed to create AudioContext: ${e.message}`);
    }
}

/**
 * Suspend the audio context
 * @canopy-type AudioContext a -> Task AudioError ()
 * @name suspendContext
 * @param {AudioContext} ctx - The audio context to suspend
 * @returns {Promise<void>}
 */
async function suspendContext(ctx) {
    try {
        await ctx.suspend();
    } catch (e) {
        throw new AudioError(`Failed to suspend context: ${e.message}`);
    }
}

/**
 * Resume the audio context
 * @canopy-type AudioContext a -> Task AudioError ()
 * @name resumeContext
 * @param {AudioContext} ctx - The audio context to resume
 * @returns {Promise<void>}
 */
async function resumeContext(ctx) {
    try {
        await ctx.resume();
    } catch (e) {
        throw new AudioError(`Failed to resume context: ${e.message}`);
    }
}

/**
 * Close the audio context
 * @canopy-type AudioContext a -> Task AudioError ()
 * @name closeContext
 * @param {AudioContext} ctx - The audio context to close
 * @returns {Promise<void>}
 */
async function closeContext(ctx) {
    try {
        await ctx.close();
    } catch (e) {
        throw new AudioError(`Failed to close context: ${e.message}`);
    }
}

/**
 * Get the audio context state
 * @canopy-type AudioContext a -> String
 * @name getContextState
 * @param {AudioContext} ctx - The audio context
 * @returns {string} "suspended", "running", or "closed"
 */
function getContextState(ctx) {
    return ctx.state;
}

/**
 * Get the sample rate of the audio context
 * @canopy-type AudioContext a -> Float
 * @name getSampleRate
 * @param {AudioContext} ctx - The audio context
 * @returns {number} The sample rate in Hz
 */
function getSampleRate(ctx) {
    return ctx.sampleRate;
}

/**
 * Get the current time of the audio context
 * @canopy-type AudioContext a -> Float
 * @name getCurrentTime
 * @param {AudioContext} ctx - The audio context
 * @returns {number} The current time in seconds
 */
function getCurrentTime(ctx) {
    return ctx.currentTime;
}

// Oscillator Node

/**
 * Create an oscillator node
 * @canopy-type AudioContext a -> OscillatorNode
 * @name createOscillator
 * @param {AudioContext} ctx - The audio context
 * @returns {OscillatorNode} A new oscillator node
 */
function createOscillator(ctx) {
    return ctx.createOscillator();
}

/**
 * Set oscillator frequency
 * @canopy-type OscillatorNode -> Float -> OscillatorNode
 * @name setOscillatorFrequency
 * @param {OscillatorNode} osc - The oscillator node
 * @param {number} freq - Frequency in Hz
 * @returns {OscillatorNode} The same oscillator node
 */
function setOscillatorFrequency(osc, freq) {
    osc.frequency.value = freq;
    return osc;
}

/**
 * Set oscillator type
 * @canopy-type OscillatorNode -> String -> OscillatorNode
 * @name setOscillatorType
 * @param {OscillatorNode} osc - The oscillator node
 * @param {string} type - "sine", "square", "sawtooth", or "triangle"
 * @returns {OscillatorNode} The same oscillator node
 */
function setOscillatorType(osc, type) {
    osc.type = type;
    return osc;
}

/**
 * Start an oscillator
 * @canopy-type OscillatorNode -> Float -> ()
 * @name startOscillator
 * @param {OscillatorNode} osc - The oscillator node
 * @param {number} when - When to start (in seconds, 0 = now)
 */
function startOscillator(osc, when) {
    osc.start(when);
}

/**
 * Stop an oscillator
 * @canopy-type OscillatorNode -> Float -> ()
 * @name stopOscillator
 * @param {OscillatorNode} osc - The oscillator node
 * @param {number} when - When to stop (in seconds, 0 = now)
 */
function stopOscillator(osc, when) {
    osc.stop(when);
}

// Gain Node

/**
 * Create a gain node
 * @canopy-type AudioContext a -> GainNode
 * @name createGain
 * @param {AudioContext} ctx - The audio context
 * @returns {GainNode} A new gain node
 */
function createGain(ctx) {
    return ctx.createGain();
}

/**
 * Set gain value
 * @canopy-type GainNode -> Float -> GainNode
 * @name setGainValue
 * @param {GainNode} gain - The gain node
 * @param {number} value - Gain value (0.0 to 1.0 for normal volume)
 * @returns {GainNode} The same gain node
 */
function setGainValue(gain, value) {
    gain.gain.value = value;
    return gain;
}

/**
 * Ramp gain to value over time
 * @canopy-type GainNode -> Float -> Float -> GainNode
 * @name rampGainTo
 * @param {GainNode} gain - The gain node
 * @param {number} value - Target gain value
 * @param {number} endTime - End time in seconds
 * @returns {GainNode} The same gain node
 */
function rampGainTo(gain, value, endTime) {
    gain.gain.linearRampToValueAtTime(value, endTime);
    return gain;
}

// Node Connections

/**
 * Connect two audio nodes
 * @canopy-type AudioNode a -> AudioNode b -> ()
 * @name connectNodes
 * @param {AudioNode} source - Source node
 * @param {AudioNode} destination - Destination node
 */
function connectNodes(source, destination) {
    source.connect(destination);
}

/**
 * Connect a node to the context destination (speakers)
 * @canopy-type AudioContext a -> AudioNode b -> ()
 * @name connectToDestination
 * @param {AudioContext} ctx - The audio context
 * @param {AudioNode} node - The node to connect
 */
function connectToDestination(ctx, node) {
    node.connect(ctx.destination);
}

/**
 * Disconnect an audio node
 * @canopy-type AudioNode a -> ()
 * @name disconnectNode
 * @param {AudioNode} node - The node to disconnect
 */
function disconnectNode(node) {
    node.disconnect();
}

// Analyser Node

/**
 * Create an analyser node
 * @canopy-type AudioContext a -> AnalyserNode
 * @name createAnalyser
 * @param {AudioContext} ctx - The audio context
 * @returns {AnalyserNode} A new analyser node
 */
function createAnalyser(ctx) {
    return ctx.createAnalyser();
}

/**
 * Set analyser FFT size
 * @canopy-type AnalyserNode -> Int -> AnalyserNode
 * @name setAnalyserFftSize
 * @param {AnalyserNode} analyser - The analyser node
 * @param {number} size - FFT size (power of 2, 32-32768)
 * @returns {AnalyserNode} The same analyser node
 */
function setAnalyserFftSize(analyser, size) {
    analyser.fftSize = size;
    return analyser;
}

/**
 * Get frequency data from analyser
 * @canopy-type AnalyserNode -> List Int
 * @name getFrequencyData
 * @param {AnalyserNode} analyser - The analyser node
 * @returns {Array<number>} Frequency data array
 */
function getFrequencyData(analyser) {
    const data = new Uint8Array(analyser.frequencyBinCount);
    analyser.getByteFrequencyData(data);
    return Array.from(data);
}

/**
 * Get time domain data from analyser
 * @canopy-type AnalyserNode -> List Int
 * @name getTimeDomainData
 * @param {AnalyserNode} analyser - The analyser node
 * @returns {Array<number>} Time domain data array
 */
function getTimeDomainData(analyser) {
    const data = new Uint8Array(analyser.fftSize);
    analyser.getByteTimeDomainData(data);
    return Array.from(data);
}

// Delay Node

/**
 * Create a delay node
 * @canopy-type AudioContext a -> Float -> DelayNode
 * @name createDelay
 * @param {AudioContext} ctx - The audio context
 * @param {number} maxDelay - Maximum delay time in seconds
 * @returns {DelayNode} A new delay node
 */
function createDelay(ctx, maxDelay) {
    return ctx.createDelay(maxDelay);
}

/**
 * Set delay time
 * @canopy-type DelayNode -> Float -> DelayNode
 * @name setDelayTime
 * @param {DelayNode} delay - The delay node
 * @param {number} time - Delay time in seconds
 * @returns {DelayNode} The same delay node
 */
function setDelayTime(delay, time) {
    delay.delayTime.value = time;
    return delay;
}

// Biquad Filter Node

/**
 * Create a biquad filter node
 * @canopy-type AudioContext a -> BiquadFilterNode
 * @name createBiquadFilter
 * @param {AudioContext} ctx - The audio context
 * @returns {BiquadFilterNode} A new biquad filter node
 */
function createBiquadFilter(ctx) {
    return ctx.createBiquadFilter();
}

/**
 * Set filter type
 * @canopy-type BiquadFilterNode -> String -> BiquadFilterNode
 * @name setFilterType
 * @param {BiquadFilterNode} filter - The filter node
 * @param {string} type - "lowpass", "highpass", "bandpass", etc.
 * @returns {BiquadFilterNode} The same filter node
 */
function setFilterType(filter, type) {
    filter.type = type;
    return filter;
}

/**
 * Set filter frequency
 * @canopy-type BiquadFilterNode -> Float -> BiquadFilterNode
 * @name setFilterFrequency
 * @param {BiquadFilterNode} filter - The filter node
 * @param {number} freq - Frequency in Hz
 * @returns {BiquadFilterNode} The same filter node
 */
function setFilterFrequency(filter, freq) {
    filter.frequency.value = freq;
    return filter;
}

/**
 * Set filter Q value
 * @canopy-type BiquadFilterNode -> Float -> BiquadFilterNode
 * @name setFilterQ
 * @param {BiquadFilterNode} filter - The filter node
 * @param {number} q - Q value
 * @returns {BiquadFilterNode} The same filter node
 */
function setFilterQ(filter, q) {
    filter.Q.value = q;
    return filter;
}

// Error handling

/**
 * Custom error class for audio operations
 */
class AudioError extends Error {
    constructor(message) {
        super(message);
        this.name = 'AudioError';
    }
}

// Export for Node.js testing
if (typeof module !== 'undefined') {
    module.exports = {
        createContext, suspendContext, resumeContext, closeContext,
        getContextState, getSampleRate, getCurrentTime,
        createOscillator, setOscillatorFrequency, setOscillatorType,
        startOscillator, stopOscillator,
        createGain, setGainValue, rampGainTo,
        connectNodes, connectToDestination, disconnectNode,
        createAnalyser, setAnalyserFftSize, getFrequencyData, getTimeDomainData,
        createDelay, setDelayTime,
        createBiquadFilter, setFilterType, setFilterFrequency, setFilterQ,
        AudioError
    };
}
