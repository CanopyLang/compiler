/**
 * Complete Audio FFI JavaScript Module
 * Provides comprehensive Web Audio API integration with capability-based types
 *
 * This module implements all audio functionality needed for the Canopy FFI demo:
 * - Audio support detection with Available types
 * - User activation management with UserActivated types
 * - Permission handling with Permitted types
 * - AudioContext lifecycle with Initialized types
 * - Oscillator management and tone generation
 * - Complete audio workflow integration
 */

// Global state for audio components
let globalAudioContext = null;
let globalOscillator = null;
let currentTone = null;

/**
 * Detects Web Audio API support and returns capability status
 * @canopy-type Available ()
 * @name detectWebAudioSupport
 */
function detectWebAudioSupport() {
    if (window.AudioContext) {
        return { tag: "Supported", values: [null] };
    } else if (window.webkitAudioContext) {
        return { tag: "Prefixed", values: [null, "webkit"] };
    } else if (window.mozAudioContext) {
        return { tag: "Prefixed", values: [null, "moz"] };
    } else if (window.msAudioContext) {
        return { tag: "Prefixed", values: [null, "ms"] };
    } else {
        // Check for older implementations or polyfills
        if (typeof window.Audio !== 'undefined') {
            return { tag: "PartialSupport", values: [null] };
        }
        return { tag: "Experimental", values: [null] };
    }
}

/**
 * Checks if user activation is currently available
 * @canopy-type Bool
 * @name isUserActivationAvailable
 */
function isUserActivationAvailable() {
    if ('userActivation' in navigator) {
        return navigator.userActivation.hasBeenActive;
    }
    // Fallback: assume available if recent user interaction
    return document.hasStoredUserActivation || false;
}

/**
 * Checks if user activation is currently active (not consumed)
 * @canopy-type Bool
 * @name isUserActivationActive
 */
function isUserActivationActive() {
    if ('userActivation' in navigator) {
        return navigator.userActivation.isActive;
    }
    // Fallback: assume active if recently activated
    return document.userGestureActive || false;
}

/**
 * Consumes user activation and returns the type of gesture
 * @canopy-type UserActivated
 * @name consumeUserActivation
 */
function consumeUserActivation() {
    // Store that we've consumed activation
    if ('userActivation' in navigator) {
        document.userGestureActive = navigator.userActivation.isActive;
    }

    // Return the most recent user gesture type
    if (document.lastUserGesture) {
        const gesture = document.lastUserGesture;
        document.lastUserGesture = null; // Consume it
        return { tag: gesture, values: [] };
    }

    // Default to Click if we don't have specific gesture info
    return { tag: "Click", values: [] };
}

/**
 * Requests audio permission from the user
 * @canopy-type Permitted ()
 * @name requestAudioPermission
 */
function requestAudioPermission() {
    if (navigator.permissions) {
        return navigator.permissions.query({ name: 'microphone' })
            .then(permission => {
                switch (permission.state) {
                    case 'granted':
                        return { tag: "Granted", values: [null] };
                    case 'denied':
                        return { tag: "Denied", values: [null] };
                    case 'prompt':
                        return { tag: "Prompt", values: [null] };
                    default:
                        return { tag: "Unknown", values: [null] };
                }
            })
            .catch(() => {
                // Fallback: assume granted for audio playback (not recording)
                return { tag: "Granted", values: [null] };
            });
    } else {
        // No permissions API - assume granted for basic audio
        return { tag: "Granted", values: [null] };
    }
}

/**
 * Creates an AudioContext with user activation
 * @canopy-type UserActivated -> Initialized AudioContext
 * @name createAudioContext
 */
function createAudioContext(userActivation) {
    try {
        // Get the appropriate AudioContext constructor
        const AudioContextClass = window.AudioContext ||
                                 window.webkitAudioContext ||
                                 window.mozAudioContext ||
                                 window.msAudioContext;

        if (!AudioContextClass) {
            return { tag: "Interrupted", values: [null] };
        }

        // Create new AudioContext
        globalAudioContext = new AudioContextClass();

        // Check initial state
        if (globalAudioContext.state === 'running') {
            return { tag: "Running", values: [globalAudioContext] };
        } else if (globalAudioContext.state === 'suspended') {
            // Try to resume with user activation
            globalAudioContext.resume().then(() => {
                console.log('AudioContext resumed successfully');
            }).catch(err => {
                console.warn('Failed to resume AudioContext:', err);
            });
            return { tag: "Suspended", values: [globalAudioContext] };
        } else {
            return { tag: "Fresh", values: [globalAudioContext] };
        }

    } catch (error) {
        console.error('Failed to create AudioContext:', error);
        return { tag: "Interrupted", values: [null] };
    }
}

/**
 * Gets the current global AudioContext
 * @canopy-type AudioContext
 * @name getAudioContext
 */
function getAudioContext() {
    return globalAudioContext;
}

/**
 * Creates an OscillatorNode from an AudioContext
 * @canopy-type AudioContext -> Initialized OscillatorNode
 * @name createOscillator
 */
function createOscillator(audioContext) {
    try {
        if (!audioContext || typeof audioContext.createOscillator !== 'function') {
            return { tag: "Interrupted", values: [null] };
        }

        // Create new oscillator
        const oscillator = audioContext.createOscillator();
        const gainNode = audioContext.createGain();

        // Configure oscillator
        oscillator.type = 'sine';
        oscillator.frequency.setValueAtTime(440, audioContext.currentTime); // Default A4

        // Configure gain for smooth volume control
        gainNode.gain.setValueAtTime(0.1, audioContext.currentTime);

        // Connect: oscillator -> gain -> destination
        oscillator.connect(gainNode);
        gainNode.connect(audioContext.destination);

        // Store references
        globalOscillator = { oscillator, gainNode, audioContext };

        return { tag: "Fresh", values: [oscillator] };

    } catch (error) {
        console.error('Failed to create oscillator:', error);
        return { tag: "Interrupted", values: [null] };
    }
}

/**
 * Gets the current global OscillatorNode
 * @canopy-type OscillatorNode
 * @name getOscillator
 */
function getOscillator() {
    return globalOscillator ? globalOscillator.oscillator : null;
}

/**
 * Plays a tone at the specified frequency
 * @canopy-type AudioContext -> OscillatorNode -> Int -> Initialized ()
 * @name playTone
 */
function playTone(audioContext, oscillatorNode, frequency) {
    try {
        if (!globalOscillator || !audioContext) {
            return { tag: "Interrupted", values: [null] };
        }

        // Stop any currently playing tone
        if (currentTone) {
            stopTone(audioContext, oscillatorNode);
        }

        // Create new oscillator for this tone
        const oscillator = audioContext.createOscillator();
        const gainNode = audioContext.createGain();

        // Configure oscillator
        oscillator.type = 'sine';
        oscillator.frequency.setValueAtTime(frequency, audioContext.currentTime);

        // Configure gain with smooth attack
        gainNode.gain.setValueAtTime(0, audioContext.currentTime);
        gainNode.gain.linearRampToValueAtTime(0.1, audioContext.currentTime + 0.01);

        // Connect audio graph
        oscillator.connect(gainNode);
        gainNode.connect(audioContext.destination);

        // Start oscillator
        oscillator.start(audioContext.currentTime);

        // Store current tone info
        currentTone = { oscillator, gainNode, frequency, startTime: audioContext.currentTime };

        console.log(`Playing tone: ${frequency}Hz`);
        return { tag: "Running", values: [null] };

    } catch (error) {
        console.error('Failed to play tone:', error);
        return { tag: "Interrupted", values: [null] };
    }
}

/**
 * Stops the currently playing tone
 * @canopy-type AudioContext -> OscillatorNode -> Initialized ()
 * @name stopTone
 */
function stopTone(audioContext, oscillatorNode) {
    try {
        if (!currentTone) {
            return { tag: "Suspended", values: [null] };
        }

        const { oscillator, gainNode } = currentTone;

        // Smooth release to avoid clicks
        const releaseTime = 0.01;
        gainNode.gain.setValueAtTime(gainNode.gain.value, audioContext.currentTime);
        gainNode.gain.linearRampToValueAtTime(0, audioContext.currentTime + releaseTime);

        // Stop oscillator after release
        oscillator.stop(audioContext.currentTime + releaseTime);

        console.log(`Stopped tone: ${currentTone.frequency}Hz`);
        currentTone = null;

        return { tag: "Closing", values: [null] };

    } catch (error) {
        console.error('Failed to stop tone:', error);
        return { tag: "Interrupted", values: [null] };
    }
}

// Event listeners for user interaction tracking
document.addEventListener('click', () => {
    document.lastUserGesture = 'Click';
    document.userGestureActive = true;
    document.hasStoredUserActivation = true;
});

document.addEventListener('keypress', () => {
    document.lastUserGesture = 'Keypress';
    document.userGestureActive = true;
    document.hasStoredUserActivation = true;
});

document.addEventListener('touchstart', () => {
    document.lastUserGesture = 'Touch';
    document.userGestureActive = true;
    document.hasStoredUserActivation = true;
});

document.addEventListener('focus', () => {
    document.lastUserGesture = 'Focus';
    document.userGestureActive = true;
}, true);

// Reset user gesture state after short delay
setInterval(() => {
    document.userGestureActive = false;
}, 1000);

// Export all functions for FFI access
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        detectWebAudioSupport,
        isUserActivationAvailable,
        isUserActivationActive,
        consumeUserActivation,
        requestAudioPermission,
        createAudioContext,
        getAudioContext,
        createOscillator,
        getOscillator,
        playTone,
        stopTone
    };
}

console.log('Complete Audio FFI Module loaded - all functions available for Canopy FFI');