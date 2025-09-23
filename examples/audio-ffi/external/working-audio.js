/**
 * Working Audio FFI with types the current Canopy compiler can handle
 *
 * This uses only basic types and Result types which the current parser supports.
 * Complex capability types will be added once the compiler's parseBasicType
 * function is enhanced to handle custom types properly.
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
 * Check if user activation is currently active
 * @canopy-type () -> Bool
 * @name isUserActivationActive
 */
function isUserActivationActive() {
    if (navigator.userActivation) {
        return navigator.userActivation.isActive;
    }
    return false;
}

/**
 * Get a description of current user gesture type
 * @canopy-type () -> String
 * @name getCurrentUserGesture
 */
function getCurrentUserGesture() {
    // Detect the type of user activation based on recent events
    const now = Date.now();
    const recentEvents = window.__canopyRecentEvents || [];

    // Find the most recent user event within the last 100ms
    const recentEvent = recentEvents
        .filter((event) => now - event.timestamp < 100)
        .sort((a, b) => b.timestamp - a.timestamp)[0];

    if (recentEvent) {
        switch (recentEvent.type) {
            case "click": return "Click";
            case "keydown":
            case "keyup": return "Keypress";
            case "touchstart":
            case "touchend": return "Touch";
            case "dragstart":
            case "dragend": return "Drag";
            case "focus": return "Focus";
            default: return "Transient";
        }
    }

    return "Transient";
}

/**
 * Get Web Audio API support level as string
 * @canopy-type () -> String
 * @name getWebAudioSupportLevel
 */
function getWebAudioSupportLevel() {
    if (window.AudioContext) {
        return "Supported";
    } else if (window.webkitAudioContext) {
        return "Prefixed";
    } else if (window.Audio && window.Audio.prototype.play) {
        return "PartialSupport";
    } else {
        return "NotAvailable";
    }
}

/**
 * Create an AudioContext and return status
 * @canopy-type () -> String
 * @name createAudioContext
 */
function createAudioContext() {
    try {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext;
        if (!AudioContextClass) {
            return "Error: Web Audio API not supported";
        }

        const context = new AudioContextClass();

        // Store context globally for other functions to use
        window.__canopyAudioContext = context;

        return "Success: AudioContext created, state: " + (context.state || "unknown");
    } catch (error) {
        return "Error: " + error.message;
    }
}

/**
 * Resume the audio context if suspended
 * @canopy-type () -> String
 * @name resumeAudioContext
 */
function resumeAudioContext() {
    if (!window.__canopyAudioContext) {
        return "Error: No AudioContext created";
    }

    const context = window.__canopyAudioContext;

    if (context.state === 'suspended') {
        context.resume().then(() => {
            return "Success: AudioContext resumed";
        }).catch(error => {
            return "Error: Failed to resume: " + error.message;
        });
    }

    return "Info: AudioContext state is " + context.state;
}

/**
 * Create and play a simple beep
 * @canopy-type () -> String
 * @name playBeep
 */
function playBeep() {
    if (!window.__canopyAudioContext) {
        return "Error: No AudioContext created. Call createAudioContext first.";
    }

    try {
        const context = window.__canopyAudioContext;

        if (context.state === 'suspended') {
            return "Error: AudioContext suspended. Call resumeAudioContext first.";
        }

        const oscillator = context.createOscillator();
        const gainNode = context.createGain();

        oscillator.type = 'sine';
        oscillator.frequency.setValueAtTime(440, context.currentTime); // A4 note
        gainNode.gain.setValueAtTime(0.1, context.currentTime); // Low volume

        oscillator.connect(gainNode);
        gainNode.connect(context.destination);

        oscillator.start();
        oscillator.stop(context.currentTime + 0.2); // 200ms beep

        return "Success: Beep played (440Hz for 200ms)";
    } catch (error) {
        return "Error: " + error.message;
    }
}

/**
 * Get current audio context state
 * @canopy-type () -> String
 * @name getAudioContextState
 */
function getAudioContextState() {
    if (!window.__canopyAudioContext) {
        return "No AudioContext created";
    }

    return window.__canopyAudioContext.state || "unknown";
}

/**
 * Test complete audio workflow
 * @canopy-type () -> String
 * @name testCompleteAudioWorkflow
 */
function testCompleteAudioWorkflow() {
    let result = "=== COMPLETE AUDIO WORKFLOW TEST ===\n";

    // Step 1: Check support
    result += "1. Web Audio Support: " + getWebAudioSupportLevel() + "\n";

    // Step 2: Check user activation
    result += "2. User Activation Available: " + isUserActivationAvailable() + "\n";
    result += "3. User Activation Active: " + isUserActivationActive() + "\n";
    result += "4. Current Gesture: " + getCurrentUserGesture() + "\n";

    // Step 3: Create context
    result += "5. Create AudioContext: " + createAudioContext() + "\n";

    // Step 4: Resume if needed
    result += "6. Resume Context: " + resumeAudioContext() + "\n";

    // Step 5: Play sound
    result += "7. Play Beep: " + playBeep() + "\n";

    // Step 6: Final state
    result += "8. Final State: " + getAudioContextState() + "\n";

    return result;
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

// Export for Node.js testing
if (typeof module !== 'undefined') {
    module.exports = {
        isWebAudioSupported, isUserActivationAvailable, isUserActivationActive,
        getCurrentUserGesture, getWebAudioSupportLevel, createAudioContext,
        resumeAudioContext, playBeep, getAudioContextState, testCompleteAudioWorkflow
    };
}