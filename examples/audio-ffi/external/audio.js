/**
 * External Audio FFI - Test file for external FFI imports
 *
 * This file tests the MVar deadlock fix for external file imports.
 * Previously, importing this file with:
 * `foreign import javascript "external/audio.js" as AudioFFI`
 * would cause "thread blocked indefinitely in an MVar operation"
 */

/**
 * Create audio context
 * @name createAudioContext
 * @canopy-type UserActivated -> Task CapabilityError (Initialized AudioContext)
 */
function createAudioContext(userActivation) {
    return new (window.AudioContext || window.webkitAudioContext)();
}

/**
 * Play a tone
 * @name playTone
 * @canopy-type AudioContext -> Float -> Float -> ()
 */
function playTone(audioContext, frequency, duration) {
    const oscillator = audioContext.createOscillator();
    const gainNode = audioContext.createGain();

    oscillator.connect(gainNode);
    gainNode.connect(audioContext.destination);

    oscillator.frequency.setValueAtTime(frequency, audioContext.currentTime);
    gainNode.gain.setValueAtTime(0.3, audioContext.currentTime);
    gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + duration);

    oscillator.start(audioContext.currentTime);
    oscillator.stop(audioContext.currentTime + duration);
}

/**
 * Create oscillator node
 * @name createOscillator
 * @canopy-type Initialized AudioContext -> Float -> String -> Task CapabilityError OscillatorNode
 */
function createOscillator(audioContext, frequency, waveType) {
    const oscillator = audioContext.createOscillator();
    oscillator.frequency.setValueAtTime(frequency, audioContext.currentTime);
    oscillator.type = waveType || 'sine';
    return oscillator;
}

/**
 * Create gain node
 * @name createGainNode
 * @canopy-type Initialized AudioContext -> Float -> Task CapabilityError GainNode
 */
function createGainNode(audioContext, gain) {
    const gainNode = audioContext.createGain();
    gainNode.gain.setValueAtTime(gain, audioContext.currentTime);
    return gainNode;
}

/**
 * Connect audio nodes
 * @name connectNodes
 * @canopy-type a -> b -> Task CapabilityError ()
 */
function connectNodes(sourceNode, destinationNode) {
    sourceNode.connect(destinationNode);
}

/**
 * Connect to destination
 * @name connectToDestination
 * @canopy-type GainNode -> Initialized AudioContext -> Task CapabilityError ()
 */
function connectToDestination(gainNode, audioContext) {
    gainNode.connect(audioContext.destination);
}

/**
 * Start oscillator
 * @name startOscillator
 * @canopy-type OscillatorNode -> Float -> Task CapabilityError ()
 */
function startOscillator(oscillator, when) {
    oscillator.start(when);
}

/**
 * Stop oscillator
 * @name stopOscillator
 * @canopy-type OscillatorNode -> Float -> Task CapabilityError ()
 */
function stopOscillator(oscillator, when) {
    oscillator.stop(when);
}

/**
 * Set gain value
 * @name setGain
 * @canopy-type GainNode -> Float -> Float -> Task CapabilityError ()
 */
function setGain(gainNode, value, when) {
    gainNode.gain.setValueAtTime(value, when);
}

/**
 * Get current time
 * @name getCurrentTime
 * @canopy-type Initialized AudioContext -> Float
 */
function getCurrentTime(audioContext) {
    return audioContext.currentTime;
}

/**
 * Resume audio context
 * @name resumeAudioContext
 * @canopy-type Initialized AudioContext -> Task CapabilityError (Initialized AudioContext)
 */
function resumeAudioContext(audioContext) {
    return audioContext.resume().then(() => audioContext);
}

/**
 * Check Web Audio support
 * @name checkWebAudioSupport
 * @canopy-type Available ()
 */
function checkWebAudioSupport() {
    if (window.AudioContext) {
        return { $: "Supported", a: null };
    } else if (window.webkitAudioContext) {
        return { $: "Prefixed", a: "webkit" };
    } else {
        return { $: "PartialSupport", a: null };
    }
}
