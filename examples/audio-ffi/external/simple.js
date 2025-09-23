/**
 * Simple test function
 * @canopy-type UserActivated
 * @name getActivation
 */
function getActivation() {
    return { $: 'Click' };
}

/**
 * Simple message function for testing FFI
 * @canopy-type String
 * @name getMessage
 */
function getMessage() {
    return "Hello from JavaScript FFI!";
}

// Export for FFI access
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        getActivation,
        getMessage
    };
}