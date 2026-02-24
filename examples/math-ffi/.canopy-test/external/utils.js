/**
 * Utility functions FFI for testing multiple imports
 * @name randomInt
 * @canopy-type Int -> Int
 */
function randomInt(max) {
    return Math.floor(Math.random() * max);
}

/**
 * @name getCurrentTimestamp
 * @canopy-type Int
 */
var getCurrentTimestamp = Date.now();

/**
 * @name consoleLog
 * @canopy-type String -> ()
 */
function consoleLog(message) {
    console.log(message);
}
