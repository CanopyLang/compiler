/**
 * Advanced Math Operations for Canopy FFI
 *
 * This demonstrates clean FFI integration with mathematical operations
 * that aren't available in standard Elm/Canopy.
 */

/**
 * Calculate the factorial of a number
 * @canopy-type Int -> Int
 * @name factorial
 * @param {number} n - Non-negative integer
 * @returns {number} The factorial of n
 * @throws {MathError} When n is negative or not an integer
 */
function factorial(n) {
    if (!Number.isInteger(n) || n < 0) {
        throw new MathError(`factorial: input must be a non-negative integer, got ${n}`);
    }

    if (n === 0 || n === 1) return 1;

    let result = 1;
    for (let i = 2; i <= n; i++) {
        result *= i;
    }
    return result;
}

/**
 * Calculate the greatest common divisor of two integers
 * @canopy-type Int -> Int -> Int
 * @name gcd
 * @param {number} a - First integer
 * @param {number} b - Second integer
 * @returns {number} The GCD of a and b
 */
function gcd(a, b) {
    a = Math.abs(a);
    b = Math.abs(b);

    while (b !== 0) {
        let temp = b;
        b = a % b;
        a = temp;
    }
    return a;
}

/**
 * Calculate the least common multiple of two integers
 * @canopy-type Int -> Int -> Int
 * @name lcm
 * @param {number} a - First integer
 * @param {number} b - Second integer
 * @returns {number} The LCM of a and b
 */
function lcm(a, b) {
    if (a === 0 || b === 0) return 0;
    return Math.abs(a * b) / gcd(a, b);
}

/**
 * Check if a number is prime
 * @canopy-type Int -> Bool
 * @name isPrime
 * @param {number} n - Integer to test
 * @returns {boolean} True if n is prime
 */
function isPrime(n) {
    if (!Number.isInteger(n) || n < 2) return false;
    if (n === 2) return true;
    if (n % 2 === 0) return false;

    const sqrt = Math.sqrt(n);
    for (let i = 3; i <= sqrt; i += 2) {
        if (n % i === 0) return false;
    }
    return true;
}

/**
 * Generate Fibonacci number at position n
 * @canopy-type Int -> Int
 * @name fibonacci
 * @param {number} n - Position in Fibonacci sequence (0-indexed)
 * @returns {number} The nth Fibonacci number
 * @throws {MathError} When n is negative
 */
function fibonacci(n) {
    if (!Number.isInteger(n) || n < 0) {
        throw new MathError(`fibonacci: input must be a non-negative integer, got ${n}`);
    }

    if (n <= 1) return n;

    let a = 0, b = 1;
    for (let i = 2; i <= n; i++) {
        let temp = a + b;
        a = b;
        b = temp;
    }
    return b;
}

/**
 * Calculate the power of a number with integer exponent
 * @canopy-type Float -> Int -> Float
 * @name power
 * @param {number} base - The base number
 * @param {number} exponent - Integer exponent
 * @returns {number} base raised to the power of exponent
 */
function power(base, exponent) {
    if (!Number.isInteger(exponent)) {
        throw new MathError(`power: exponent must be an integer, got ${exponent}`);
    }

    if (exponent === 0) return 1;
    if (exponent === 1) return base;

    if (exponent < 0) {
        return 1 / power(base, -exponent);
    }

    let result = 1;
    while (exponent > 0) {
        if (exponent % 2 === 1) {
            result *= base;
        }
        base *= base;
        exponent = Math.floor(exponent / 2);
    }
    return result;
}

/**
 * Calculate the square root using Newton's method
 * @canopy-type Float -> Result MathError Float
 * @name sqrt
 * @param {number} x - Non-negative number
 * @returns {number} Square root of x
 * @throws {MathError} When x is negative
 */
function sqrt(x) {
    if (typeof x !== 'number' || x < 0) {
        throw new MathError(`sqrt: input must be a non-negative number, got ${x}`);
    }

    if (x === 0) return 0;
    if (x === 1) return 1;

    // Newton's method for better precision than Math.sqrt
    let guess = x / 2;
    const epsilon = 1e-15;

    while (true) {
        const newGuess = (guess + x / guess) / 2;
        if (Math.abs(guess - newGuess) < epsilon) {
            return newGuess;
        }
        guess = newGuess;
    }
}

/**
 * Convert degrees to radians
 * @canopy-type Float -> Float
 * @name degreesToRadians
 * @param {number} degrees - Angle in degrees
 * @returns {number} Angle in radians
 */
function degreesToRadians(degrees) {
    return degrees * (Math.PI / 180);
}

/**
 * Convert radians to degrees
 * @canopy-type Float -> Float
 * @name radiansToDegrees
 * @param {number} radians - Angle in radians
 * @returns {number} Angle in degrees
 */
function radiansToDegrees(radians) {
    return radians * (180 / Math.PI);
}

/**
 * Calculate the distance between two 2D points
 * @canopy-type Float -> Float -> Float -> Float -> Float
 * @name distance2D
 * @param {number} x1 - X coordinate of first point
 * @param {number} y1 - Y coordinate of first point
 * @param {number} x2 - X coordinate of second point
 * @param {number} y2 - Y coordinate of second point
 * @returns {number} Euclidean distance between the points
 */
function distance2D(x1, y1, x2, y2) {
    const dx = x2 - x1;
    const dy = y2 - y1;
    return Math.sqrt(dx * dx + dy * dy);
}

/**
 * Custom error class for mathematical operations
 */
class MathError extends Error {
    constructor(message) {
        super(message);
        this.name = 'MathError';
    }
}

// Export for Node.js testing
if (typeof module !== 'undefined') {
    module.exports = {
        factorial, gcd, lcm, isPrime, fibonacci, power, sqrt,
        degreesToRadians, radiansToDegrees, distance2D, MathError
    };
}