/**
 * Test void FFI function
 * @name voidFunction
 * @canopy-type Int -> ()
 */
function voidFunction(x) {
    console.log("Called with: " + x);
    return 0; // Explicit return matching Elm's Utils_Tuple0
}
