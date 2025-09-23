/**
 * Test function with a single complex type
 * @canopy-type UserActivated
 * @name getCurrentGesture
 */
function getCurrentGesture() {
    return { $: "Click" };
}

/**
 * Test function with Available type
 * @canopy-type Available ()
 * @name getAudioSupport
 */
function getAudioSupport() {
    return { type: "Supported", value: null };
}