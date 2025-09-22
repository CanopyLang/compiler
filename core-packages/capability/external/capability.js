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
    return typeof window !== 'undefined' && typeof document !== 'undefined';
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
 * @canopy-type UserActivated
 * @name consumeUserActivation
 */
function consumeUserActivation() {
    // Detect the type of user activation based on recent events
    const now = Date.now();
    const recentEvents = window.__canopyRecentEvents || [];

    // Find the most recent user event within the last 100ms
    const recentEvent = recentEvents
        .filter(event => now - event.timestamp < 100)
        .sort((a, b) => b.timestamp - a.timestamp)[0];

    if (recentEvent) {
        // Return specific gesture type based on event type
        switch (recentEvent.type) {
            case 'click':
                return { $: 'Click' };
            case 'keydown':
            case 'keyup':
                return { $: 'Keypress' };
            case 'touchstart':
            case 'touchend':
                return { $: 'Touch' };
            case 'dragstart':
            case 'dragend':
                return { $: 'Drag' };
            case 'focus':
                return { $: 'Focus' };
            default:
                return { $: 'Transient' };
        }
    }

    // Fallback: return transient activation
    return { $: 'Transient' };
}

// Track recent user events for gesture type detection
if (typeof window !== 'undefined') {
    window.__canopyRecentEvents = [];

    ['click', 'keydown', 'keyup', 'touchstart', 'touchend', 'dragstart', 'dragend', 'focus'].forEach(eventType => {
        document.addEventListener(eventType, (event) => {
            window.__canopyRecentEvents.push({
                type: eventType,
                timestamp: Date.now()
            });

            // Keep only last 10 events
            if (window.__canopyRecentEvents.length > 10) {
                window.__canopyRecentEvents.shift();
            }
        }, true);
    });
}

/**
 * Generic API availability detection framework
 * @canopy-type (() -> Capability.Available ()) -> Capability.Available ()
 * @name detectAPISupport
 */
function detectAPISupport(detectionFunction) {
    try {
        return detectionFunction();
    } catch (error) {
        // Return PartialSupport as fallback when detection fails
        return { $: 'PartialSupport', a: null };
    }
}

/**
 * Generic feature detection helper
 * @canopy-type String -> Bool
 * @name hasFeature
 */
function hasFeature(featurePath) {
    try {
        const parts = featurePath.split('.');
        let current = window;

        for (const part of parts) {
            if (current && typeof current === 'object' && part in current) {
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
 * @canopy-type String -> Task Capability.CapabilityError (Capability.Permitted ())
 * @name checkGenericPermission
 */
function checkGenericPermission(permissionName) {
    return new Promise((resolve, reject) => {
        if (!navigator.permissions) {
            resolve({ $: 'Unknown', a: null });
            return;
        }

        navigator.permissions.query({ name: permissionName })
            .then(result => {
                switch (result.state) {
                    case 'granted':
                        resolve({ $: 'Granted', a: null });
                        break;
                    case 'denied':
                        resolve({ $: 'Denied', a: null });
                        break;
                    case 'prompt':
                        resolve({ $: 'Prompt', a: null });
                        break;
                    default:
                        resolve({ $: 'Unknown', a: null });
                }
            })
            .catch(error => {
                reject(new CapabilityError("PermissionRequired", `Failed to check permission: ${error.message}`));
            });
    });
}

/**
 * Generic permission request framework
 * @canopy-type (() -> Task Capability.CapabilityError (Capability.Permitted ())) -> Task Capability.CapabilityError (Capability.Permitted ())
 * @name requestGenericPermission
 */
function requestGenericPermission(requestFunction) {
    return new Promise((resolve, reject) => {
        try {
            const result = requestFunction();

            if (result && typeof result.then === 'function') {
                result.then(resolve).catch(reject);
            } else {
                resolve(result);
            }
        } catch (error) {
            reject(new CapabilityError("PermissionRequired", `Permission request failed: ${error.message}`));
        }
    });
}

/**
 * Generic initialization framework with custom state detection
 * @canopy-type String -> (() -> Task Capability.CapabilityError a) -> (a -> Capability.Initialized a) -> Task Capability.CapabilityError (Capability.Initialized a)
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
                        type: 'Fresh',
                        value: context
                    };
                }
            }

            // If it's a promise, wait for it
            if (result && typeof result.then === 'function') {
                result
                    .then(initializedContext => {
                        resolve(wrapWithState(initializedContext));
                    })
                    .catch(error => {
                        reject(new CapabilityError("InitializationRequired", `${contextType} initialization failed: ${error.message}`));
                    });
            } else {
                // Synchronous result
                resolve(wrapWithState(result));
            }
        } catch (error) {
            reject(new CapabilityError("InitializationRequired", `${contextType} initialization failed: ${error.message}`));
        }
    });
}

/**
 * Simple initialization checker (backwards compatibility)
 * @canopy-type String -> (() -> Task Capability.CapabilityError a) -> Task Capability.CapabilityError (Capability.Initialized a)
 * @name createInitializationChecker
 */
function createInitializationChecker(contextType, initFunction) {
    return createGenericInitializer(contextType, initFunction, null);
}

/**
 * Validate that a value has the correct capability type
 * @canopy-type String -> a -> Task Capability.CapabilityError a
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
                if (value && typeof value === 'object' && value.__type === "Initialized") {
                    resolve(value.__context);
                } else {
                    reject(new CapabilityError("InitializationRequired", "Initialized context required"));
                }
                break;

            default:
                reject(new CapabilityError("CapabilityRevoked", `Unknown capability type: ${expectedType}`));
        }
    });
}

/**
 * Custom error class for capability violations
 */
class CapabilityError extends Error {
    constructor(type, message) {
        super(message);
        this.name = 'CapabilityError';
        this.type = type;
    }
}

// Export for Node.js testing
if (typeof module !== 'undefined') {
    module.exports = {
        isUserActivationAvailable, isUserActivationActive, consumeUserActivation,
        isAPIAvailable, checkPermission, requestPermission,
        createInitializationChecker, validateCapability, CapabilityError
    };
}