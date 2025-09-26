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
 * @canopy-type String
 */
function checkWebAudioSupport() {
    if (window.AudioContext) {
        return "Full Web Audio API support detected";
    } else if (window.webkitAudioContext) {
        return "WebKit Web Audio API support detected";
    } else {
        return "No Web Audio API support detected";
    }
}

/**
 * Simple test function
 * @name simpleTest
 * @canopy-type Int -> Int
 */
function simpleTest(x) {
    return x + 1;
}

// ============================================================================
// SIMPLIFIED AUDIO FUNCTIONS FOR EASY FFI INTEGRATION
// ============================================================================
// These wrapper functions provide simplified interfaces that work with
// Canopy's type system while still providing real audio functionality

// Global audio context and current oscillator for management
let globalAudioContext = null;
let currentOscillator = null;
let currentGainNode = null;

/**
 * Create audio context (simplified version)
 * @name createAudioContextSimplified
 * @canopy-type String
 */
function createAudioContextSimplified() {
    try {
        if (!globalAudioContext) {
            globalAudioContext = new (window.AudioContext || window.webkitAudioContext)();
        }

        // Resume context if suspended (required by browsers for user activation)
        if (globalAudioContext.state === 'suspended') {
            globalAudioContext.resume().then(() => {
                console.log('Audio context resumed');
            });
        }

        return "Audio context created and ready for use. State: " + globalAudioContext.state;
    } catch (error) {
        return "Error creating audio context: " + error.message;
    }
}

/**
 * Play a tone with real audio (simplified interface)
 * @name playToneSimplified
 * @canopy-type Float -> String -> String
 */
function playToneSimplified(frequency, waveform) {
    try {
        // Create context if it doesn't exist
        if (!globalAudioContext) {
            createAudioContextSimplified();
        }

        // Stop any currently playing oscillator
        if (currentOscillator) {
            stopAudioSimplified();
        }

        // Create oscillator and gain node
        currentOscillator = globalAudioContext.createOscillator();
        currentGainNode = globalAudioContext.createGain();

        // Set up audio graph
        currentOscillator.connect(currentGainNode);
        currentGainNode.connect(globalAudioContext.destination);

        // Configure oscillator
        currentOscillator.frequency.setValueAtTime(frequency, globalAudioContext.currentTime);
        currentOscillator.type = waveform || 'sine';

        // Configure gain (volume)
        currentGainNode.gain.setValueAtTime(0.1, globalAudioContext.currentTime);

        // Start oscillator
        currentOscillator.start(globalAudioContext.currentTime);

        return "Playing " + waveform + " wave at " + frequency.toFixed(1) + " Hz (REAL AUDIO)";

    } catch (error) {
        return "Error playing tone: " + error.message;
    }
}

/**
 * Stop audio playback (simplified interface)
 * @name stopAudioSimplified
 * @canopy-type String
 */
function stopAudioSimplified() {
    try {
        if (currentOscillator) {
            currentOscillator.stop(globalAudioContext.currentTime);
            currentOscillator.disconnect();
            currentOscillator = null;
        }

        if (currentGainNode) {
            currentGainNode.disconnect();
            currentGainNode = null;
        }

        return "Audio stopped successfully (REAL AUDIO STOPPED)";

    } catch (error) {
        return "Error stopping audio: " + error.message;
    }
}

/**
 * Update frequency in real-time (for interactive controls)
 * @name updateFrequency
 * @canopy-type Float -> String
 */
function updateFrequency(frequency) {
    try {
        if (currentOscillator && globalAudioContext) {
            currentOscillator.frequency.setValueAtTime(frequency, globalAudioContext.currentTime);
            return "Frequency updated to " + frequency.toFixed(1) + " Hz";
        } else {
            return "No active oscillator to update";
        }
    } catch (error) {
        return "Error updating frequency: " + error.message;
    }
}

/**
 * Update volume in real-time (for interactive controls)
 * @name updateVolume
 * @canopy-type Float -> String
 */
function updateVolume(volume) {
    try {
        if (currentGainNode && globalAudioContext) {
            // Convert 0-100 range to 0-0.3 for reasonable volume
            const gain = (volume / 100) * 0.3;
            currentGainNode.gain.setValueAtTime(gain, globalAudioContext.currentTime);
            return "Volume updated to " + volume.toFixed(0) + "%";
        } else {
            return "No active gain node to update";
        }
    } catch (error) {
        return "Error updating volume: " + error.message;
    }
}

/**
 * Update waveform in real-time (for interactive controls)
 * @name updateWaveform
 * @canopy-type String -> String
 */
function updateWaveform(waveform) {
    try {
        if (currentOscillator) {
            currentOscillator.type = waveform;
            return "Waveform updated to " + waveform;
        } else {
            return "No active oscillator to update";
        }
    } catch (error) {
        return "Error updating waveform: " + error.message;
    }
}

/**
 * Check if audio is currently playing
 * @name isAudioPlaying
 * @canopy-type String
 */
function isAudioPlaying() {
    if (currentOscillator && globalAudioContext) {
        return "Audio is currently playing";
    } else {
        return "Audio is not playing";
    }
}
