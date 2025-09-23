/**
 * Simple Audio FFI with only basic types for testing
 */

/**
 * Check if Web Audio API is supported
 * @canopy-type () -> Bool
 * @name isWebAudioSupported
 */
function isWebAudioSupported() {
    return !!(window.AudioContext || window.webkitAudioContext);
}

/**
 * Check if user activation is available
 * @canopy-type () -> Bool
 * @name isUserActivationAvailable
 */
function isUserActivationAvailable() {
    if (navigator.userActivation) {
        return navigator.userActivation.hasBeenActive;
    }
    return typeof window !== "undefined" && typeof document !== "undefined";
}

/**
 * Create and play a simple beep sound
 * @canopy-type () -> String
 * @name playSimpleBeep
 */
function playSimpleBeep() {
    try {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext;
        if (!AudioContextClass) {
            return "Error: Web Audio API not supported";
        }

        const context = new AudioContextClass();
        const oscillator = context.createOscillator();
        const gainNode = context.createGain();

        oscillator.type = 'sine';
        oscillator.frequency.setValueAtTime(440, context.currentTime);
        gainNode.gain.setValueAtTime(0.1, context.currentTime);

        oscillator.connect(gainNode);
        gainNode.connect(context.destination);

        oscillator.start();
        oscillator.stop(context.currentTime + 0.2);

        return "Beep played successfully";
    } catch (error) {
        return "Error: " + error.message;
    }
}

/**
 * Get audio context state as string
 * @canopy-type () -> String
 * @name getAudioContextState
 */
function getAudioContextState() {
    try {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext;
        if (!AudioContextClass) {
            return "not_supported";
        }

        const context = new AudioContextClass();
        return context.state || "unknown";
    } catch (error) {
        return "error";
    }
}

// Export for Node.js testing
if (typeof module !== 'undefined') {
    module.exports = {
        isWebAudioSupported, isUserActivationAvailable,
        playSimpleBeep, getAudioContextState
    };
}