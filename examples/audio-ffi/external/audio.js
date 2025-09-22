/**
 * Web Audio API FFI Implementation for Canopy
 *
 * This demonstrates how to build API-specific FFI on top of the core
 * capability system. It implements Web Audio API functionality using
 * the generic capability checking framework.
 */

/**
 * AudioContext type for FFI
 * @typedef {AudioContext} AudioContext
 */

/**
 * OscillatorNode type for FFI
 * @typedef {OscillatorNode} OscillatorNode
 */

/**
 * Create a new AudioContext with proper capability validation
 * @canopy-type () -> Task CapabilityError AudioContext
 * @name createAudioContext
 */
function createAudioContext() {
    return new Promise((resolve, reject) => {
        try {
            // Use the best available AudioContext constructor
            const AudioContextClass = window.AudioContext || window.webkitAudioContext;

            if (!AudioContextClass) {
                reject(new CapabilityError("FeatureNotAvailable", "Web Audio API not supported"));
                return;
            }

            const context = new AudioContextClass();

            // Web Audio contexts often start suspended and need user activation
            if (context.state === 'suspended') {
                context.resume().then(() => {
                    resolve(context);
                }).catch(error => {
                    reject(new CapabilityError("InitializationRequired", `Failed to resume AudioContext: ${error.message}`));
                });
            } else {
                resolve(context);
            }
        } catch (error) {
            reject(new CapabilityError("InitializationRequired", `Failed to create AudioContext: ${error.message}`));
        }
    });
}

/**
 * Get the current state of an AudioContext
 * @canopy-type AudioContext -> String
 * @name getContextState
 */
function getContextState(context) {
    return context.state || "unknown";
}

/**
 * Resume a suspended AudioContext
 * @canopy-type AudioContext -> Task CapabilityError AudioContext
 * @name resumeContext
 */
function resumeContext(context) {
    return new Promise((resolve, reject) => {
        if (context.state === 'suspended') {
            context.resume().then(() => {
                resolve(context);
            }).catch(error => {
                reject(new CapabilityError("InitializationRequired", `Failed to resume AudioContext: ${error.message}`));
            });
        } else {
            resolve(context);
        }
    });
}

/**
 * Create an oscillator node
 * @canopy-type AudioContext -> Task CapabilityError OscillatorNode
 * @name createOscillator
 */
function createOscillator(context) {
    return new Promise((resolve, reject) => {
        try {
            if (context.state === 'closed') {
                reject(new CapabilityError("InitializationRequired", "AudioContext is closed"));
                return;
            }

            const oscillator = context.createOscillator();
            const gainNode = context.createGain();

            // Configure oscillator
            oscillator.type = 'sine';
            oscillator.frequency.setValueAtTime(440, context.currentTime); // A4 note

            // Configure gain (volume)
            gainNode.gain.setValueAtTime(0.1, context.currentTime); // Low volume

            // Connect nodes
            oscillator.connect(gainNode);
            gainNode.connect(context.destination);

            // Store references for cleanup
            oscillator._gainNode = gainNode;
            oscillator._context = context;

            resolve(oscillator);
        } catch (error) {
            reject(new CapabilityError("InitializationRequired", `Failed to create oscillator: ${error.message}`));
        }
    });
}

/**
 * Play a tone using an oscillator
 * @canopy-type OscillatorNode -> Task CapabilityError ()
 * @name playTone
 */
function playTone(oscillator) {
    return new Promise((resolve, reject) => {
        try {
            if (oscillator._isStarted) {
                reject(new CapabilityError("InvalidOperation", "Oscillator already started"));
                return;
            }

            oscillator.start();
            oscillator._isStarted = true;

            resolve(null);
        } catch (error) {
            reject(new CapabilityError("InvalidOperation", `Failed to start oscillator: ${error.message}`));
        }
    });
}

/**
 * Stop a playing tone
 * @canopy-type OscillatorNode -> Task CapabilityError ()
 * @name stopTone
 */
function stopTone(oscillator) {
    return new Promise((resolve, reject) => {
        try {
            if (!oscillator._isStarted) {
                reject(new CapabilityError("InvalidOperation", "Oscillator not started"));
                return;
            }

            oscillator.stop();
            resolve(null);
        } catch (error) {
            reject(new CapabilityError("InvalidOperation", `Failed to stop oscillator: ${error.message}`));
        }
    });
}

/**
 * Request audio permissions (for microphone access as a proxy for audio capabilities)
 * @canopy-type () -> Task CapabilityError (Permitted ())
 * @name requestAudioPermission
 */
function requestAudioPermission() {
    return new Promise((resolve, reject) => {
        // For audio playback, we don't need explicit permission
        // But for microphone access (which is often associated with audio apps), we do
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
            reject(new CapabilityError("FeatureNotAvailable", "MediaDevices API not supported"));
            return;
        }

        navigator.mediaDevices.getUserMedia({ audio: true })
            .then(stream => {
                // Permission granted, clean up the stream immediately
                stream.getTracks().forEach(track => track.stop());
                resolve({ type: 'Granted', value: null });
            })
            .catch(error => {
                switch (error.name) {
                    case 'NotAllowedError':
                        resolve({ type: 'Denied', value: null });
                        break;
                    case 'NotFoundError':
                        reject(new CapabilityError("FeatureNotAvailable", "No audio input devices found"));
                        break;
                    case 'NotSupportedError':
                        reject(new CapabilityError("FeatureNotAvailable", "Audio input not supported"));
                        break;
                    default:
                        reject(new CapabilityError("PermissionRequired", `Audio permission error: ${error.message}`));
                }
            });
    });
}

/**
 * Detect Web Audio API support with rich information
 * @canopy-type () -> Available ()
 * @name detectWebAudioSupport
 */
function detectWebAudioSupport() {
    if (window.AudioContext) {
        return { type: 'Supported', value: null };
    } else if (window.webkitAudioContext) {
        return { type: 'Prefixed', value: null, prefix: 'webkit' };
    } else if (window.Audio && window.Audio.prototype.play) {
        // Basic HTML5 audio support
        return { type: 'PartialSupport', value: null };
    } else {
        return { type: 'NotAvailable' };
    }
}

/**
 * Check if Web Audio API features are available
 * @canopy-type String -> Bool
 * @name hasWebAudioFeature
 */
function hasWebAudioFeature(featureName) {
    switch (featureName) {
        case 'AudioContext':
            return !!(window.AudioContext || window.webkitAudioContext);
        case 'OfflineAudioContext':
            return !!(window.OfflineAudioContext || window.webkitOfflineAudioContext);
        case 'AudioWorklet':
            return !!(window.AudioContext && window.AudioContext.prototype.audioWorklet);
        case 'MediaStreamAudioSourceNode':
            return !!(window.AudioContext && window.AudioContext.prototype.createMediaStreamSource);
        default:
            return false;
    }
}

/**
 * Custom error class for Web Audio specific errors
 */
class WebAudioError extends Error {
    constructor(type, message) {
        super(message);
        this.name = 'WebAudioError';
        this.type = type;
    }
}

// Re-export CapabilityError for consistency
if (typeof CapabilityError === 'undefined') {
    class CapabilityError extends Error {
        constructor(type, message) {
            super(message);
            this.name = 'CapabilityError';
            this.type = type;
        }
    }
    window.CapabilityError = CapabilityError;
}

// Export for Node.js testing
if (typeof module !== 'undefined') {
    module.exports = {
        createAudioContext, getContextState, resumeContext,
        createOscillator, playTone, stopTone,
        requestAudioPermission, detectWebAudioSupport,
        hasWebAudioFeature, WebAudioError
    };
}