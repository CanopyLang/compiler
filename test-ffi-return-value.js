/**
 * Explicitly returns 0
 * @name explicitReturnZero
 * @canopy-type Int -> ()
 */
function explicitReturnZero(x) {
    console.log("Explicit return 0: " + x);
    return 0;
}

/**
 * Implicitly returns undefined
 * @name implicitReturn
 * @canopy-type Int -> ()
 */
function implicitReturn(x) {
    console.log("Implicit return (undefined): " + x);
}
