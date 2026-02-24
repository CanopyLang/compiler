/**
 * Canopy Visual Regression Testing FFI (pixelmatch)
 *
 * This module provides visual regression testing capabilities using pixelmatch.
 * All functions follow Canopy FFI conventions with @canopy-type annotations.
 *
 * Features:
 * - Screenshot comparison against baselines
 * - Configurable difference thresholds
 * - Automatic baseline creation
 * - Diff image generation
 * - Multiple viewport testing
 *
 * @module visual
 */

const fs = require('fs');
const path = require('path');

// Default directories
const BASELINE_DIR = 'test-output/baselines';
const DIFF_DIR = 'test-output/diffs';
const SCREENSHOT_DIR = 'test-output/screenshots';

// ============================================================================
// Screenshot Comparison
// ============================================================================

/**
 * Compare screenshot against baseline
 * @canopy-type String -> String -> Float -> Task CompareError CompareResult
 * @name compare
 * @param {string} name - Baseline name
 * @param {string} screenshotPath - Path to current screenshot
 * @param {number} threshold - Difference threshold (0-1, e.g., 0.01 = 1%)
 * @returns {Promise<Object>} Comparison result
 */
async function compare(name, screenshotPath, threshold) {
    const PNG = require('pngjs').PNG;
    const pixelmatch = require('pixelmatch');

    const baselinePath = path.join(BASELINE_DIR, name + '.png');

    // Create baseline if doesn't exist
    if (!fs.existsSync(baselinePath)) {
        fs.mkdirSync(BASELINE_DIR, { recursive: true });
        fs.copyFileSync(screenshotPath, baselinePath);
        return {
            type: 'BaselineCreated',
            baselinePath: baselinePath
        };
    }

    // Load images
    const baseline = PNG.sync.read(fs.readFileSync(baselinePath));
    const current = PNG.sync.read(fs.readFileSync(screenshotPath));

    // Check dimensions match
    if (baseline.width !== current.width || baseline.height !== current.height) {
        return {
            type: 'DimensionMismatch',
            baseline: { width: baseline.width, height: baseline.height },
            current: { width: current.width, height: current.height }
        };
    }

    const { width, height } = baseline;
    const diff = new PNG({ width, height });

    // Compare pixels
    const numDiffPixels = pixelmatch(
        baseline.data,
        current.data,
        diff.data,
        width,
        height,
        { threshold: 0.1 }  // pixelmatch threshold (color sensitivity)
    );

    const totalPixels = width * height;
    const diffPercent = numDiffPixels / totalPixels;

    if (diffPercent <= threshold) {
        return { type: 'Match' };
    } else {
        // Save diff image
        fs.mkdirSync(DIFF_DIR, { recursive: true });
        const diffPath = path.join(DIFF_DIR, name + '-diff.png');
        fs.writeFileSync(diffPath, PNG.sync.write(diff));

        // Also save the current screenshot for comparison
        const currentPath = path.join(DIFF_DIR, name + '-current.png');
        fs.copyFileSync(screenshotPath, currentPath);

        return {
            type: 'Mismatch',
            diffPath: diffPath,
            currentPath: currentPath,
            baselinePath: baselinePath,
            diffPixels: numDiffPixels,
            totalPixels: totalPixels,
            diffPercent: diffPercent
        };
    }
}

/**
 * Compare with default threshold (1%)
 * @canopy-type String -> String -> Task CompareError CompareResult
 * @name compareDefault
 * @param {string} name - Baseline name
 * @param {string} screenshotPath - Path to current screenshot
 * @returns {Promise<Object>} Comparison result
 */
async function compareDefault(name, screenshotPath) {
    return compare(name, screenshotPath, 0.01);
}

/**
 * Compare with strict threshold (0.1%)
 * @canopy-type String -> String -> Task CompareError CompareResult
 * @name compareStrict
 * @param {string} name - Baseline name
 * @param {string} screenshotPath - Path to current screenshot
 * @returns {Promise<Object>} Comparison result
 */
async function compareStrict(name, screenshotPath) {
    return compare(name, screenshotPath, 0.001);
}

/**
 * Compare with lenient threshold (5%)
 * @canopy-type String -> String -> Task CompareError CompareResult
 * @name compareLenient
 * @param {string} name - Baseline name
 * @param {string} screenshotPath - Path to current screenshot
 * @returns {Promise<Object>} Comparison result
 */
async function compareLenient(name, screenshotPath) {
    return compare(name, screenshotPath, 0.05);
}

// ============================================================================
// Baseline Management
// ============================================================================

/**
 * Update baseline with current screenshot
 * @canopy-type String -> String -> Task UpdateError ()
 * @name updateBaseline
 * @param {string} name - Baseline name
 * @param {string} screenshotPath - Path to current screenshot
 * @returns {Promise<void>}
 */
async function updateBaseline(name, screenshotPath) {
    fs.mkdirSync(BASELINE_DIR, { recursive: true });
    const baselinePath = path.join(BASELINE_DIR, name + '.png');
    fs.copyFileSync(screenshotPath, baselinePath);
}

/**
 * Delete a baseline
 * @canopy-type String -> Task DeleteError ()
 * @name deleteBaseline
 * @param {string} name - Baseline name
 * @returns {Promise<void>}
 */
async function deleteBaseline(name) {
    const baselinePath = path.join(BASELINE_DIR, name + '.png');
    if (fs.existsSync(baselinePath)) {
        fs.unlinkSync(baselinePath);
    }
}

/**
 * Check if baseline exists
 * @canopy-type String -> Bool
 * @name baselineExists
 * @param {string} name - Baseline name
 * @returns {boolean} True if baseline exists
 */
function baselineExists(name) {
    const baselinePath = path.join(BASELINE_DIR, name + '.png');
    return fs.existsSync(baselinePath);
}

/**
 * List all baselines
 * @canopy-type () -> List String
 * @name listBaselines
 * @returns {string[]} List of baseline names (without extension)
 */
function listBaselines() {
    if (!fs.existsSync(BASELINE_DIR)) {
        return [];
    }
    return fs.readdirSync(BASELINE_DIR)
        .filter(f => f.endsWith('.png'))
        .map(f => f.replace('.png', ''));
}

/**
 * Clean all diffs
 * @canopy-type () -> Task CleanError ()
 * @name cleanDiffs
 * @returns {Promise<void>}
 */
async function cleanDiffs() {
    if (fs.existsSync(DIFF_DIR)) {
        const files = fs.readdirSync(DIFF_DIR);
        for (const file of files) {
            fs.unlinkSync(path.join(DIFF_DIR, file));
        }
    }
}

// ============================================================================
// Full Visual Test Flow
// ============================================================================

/**
 * Take screenshot and compare to baseline (combined operation)
 * @canopy-type String -> Browser -> Float -> Task VisualError VisualResult
 * @name snapshot
 * @param {string} name - Snapshot name
 * @param {Object} browser - Browser handle from playwright.js
 * @param {number} threshold - Difference threshold (0-1)
 * @returns {Promise<Object>} Visual test result
 */
async function snapshot(name, browser, threshold) {
    // Take screenshot
    fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
    const screenshotPath = path.join(SCREENSHOT_DIR, name + '-current.png');
    await browser._page.screenshot({ path: screenshotPath, fullPage: true });

    // Compare to baseline
    return compare(name, screenshotPath, threshold);
}

/**
 * Take element screenshot and compare to baseline
 * @canopy-type String -> String -> Browser -> Float -> Task VisualError VisualResult
 * @name snapshotElement
 * @param {string} selector - CSS selector
 * @param {string} name - Snapshot name
 * @param {Object} browser - Browser handle
 * @param {number} threshold - Difference threshold
 * @returns {Promise<Object>} Visual test result
 */
async function snapshotElement(selector, name, browser, threshold) {
    // Take element screenshot
    fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
    const screenshotPath = path.join(SCREENSHOT_DIR, name + '-current.png');

    const element = await browser._page.$(selector);
    if (!element) {
        throw new Error(`Element not found: ${selector}`);
    }

    await element.screenshot({ path: screenshotPath });

    // Compare to baseline
    return compare(name, screenshotPath, threshold);
}

/**
 * Snapshot with default threshold
 * @canopy-type String -> Browser -> Task VisualError VisualResult
 * @name snapshotDefault
 * @param {string} name - Snapshot name
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Visual test result
 */
async function snapshotDefault(name, browser) {
    return snapshot(name, browser, 0.01);
}

// ============================================================================
// Viewport Presets
// ============================================================================

/**
 * Standard viewport presets
 */
const viewports = {
    mobile: { width: 375, height: 667 },
    mobileLandscape: { width: 667, height: 375 },
    tablet: { width: 768, height: 1024 },
    tabletLandscape: { width: 1024, height: 768 },
    desktop: { width: 1280, height: 720 },
    desktopLarge: { width: 1920, height: 1080 },
    desktopUltra: { width: 2560, height: 1440 }
};

/**
 * Get mobile viewport dimensions
 * @canopy-type () -> { width : Int, height : Int }
 * @name viewportMobile
 * @returns {Object} Viewport dimensions
 */
function viewportMobile() {
    return viewports.mobile;
}

/**
 * Get tablet viewport dimensions
 * @canopy-type () -> { width : Int, height : Int }
 * @name viewportTablet
 * @returns {Object} Viewport dimensions
 */
function viewportTablet() {
    return viewports.tablet;
}

/**
 * Get desktop viewport dimensions
 * @canopy-type () -> { width : Int, height : Int }
 * @name viewportDesktop
 * @returns {Object} Viewport dimensions
 */
function viewportDesktop() {
    return viewports.desktop;
}

/**
 * Get large desktop viewport dimensions
 * @canopy-type () -> { width : Int, height : Int }
 * @name viewportDesktopLarge
 * @returns {Object} Viewport dimensions
 */
function viewportDesktopLarge() {
    return viewports.desktopLarge;
}

/**
 * Snapshot at multiple viewports
 * @canopy-type String -> Browser -> Float -> Task VisualError (List VisualResult)
 * @name snapshotResponsive
 * @param {string} name - Base snapshot name
 * @param {Object} browser - Browser handle
 * @param {number} threshold - Difference threshold
 * @returns {Promise<Object[]>} Results for each viewport
 */
async function snapshotResponsive(name, browser, threshold) {
    const results = [];
    const viewportNames = ['mobile', 'tablet', 'desktop'];

    for (const vpName of viewportNames) {
        const vp = viewports[vpName];
        await browser._page.setViewportSize(vp);
        await browser._page.waitForTimeout(100); // Let page reflow

        const result = await snapshot(`${name}-${vpName}`, browser, threshold);
        results.push({
            viewport: vpName,
            dimensions: vp,
            result: result
        });
    }

    return results;
}

// ============================================================================
// Result Helpers
// ============================================================================

/**
 * Check if comparison result is a match
 * @canopy-type CompareResult -> Bool
 * @name isMatch
 * @param {Object} result - Compare result
 * @returns {boolean} True if match
 */
function isMatch(result) {
    return result.type === 'Match';
}

/**
 * Check if comparison result is a mismatch
 * @canopy-type CompareResult -> Bool
 * @name isMismatch
 * @param {Object} result - Compare result
 * @returns {boolean} True if mismatch
 */
function isMismatch(result) {
    return result.type === 'Mismatch';
}

/**
 * Check if baseline was created
 * @canopy-type CompareResult -> Bool
 * @name isBaselineCreated
 * @param {Object} result - Compare result
 * @returns {boolean} True if baseline was created
 */
function isBaselineCreated(result) {
    return result.type === 'BaselineCreated';
}

/**
 * Format comparison result as string
 * @canopy-type CompareResult -> String
 * @name formatResult
 * @param {Object} result - Compare result
 * @returns {string} Formatted result
 */
function formatResult(result) {
    switch (result.type) {
        case 'Match':
            return 'Visual comparison: MATCH';

        case 'BaselineCreated':
            return `Visual comparison: Baseline created at ${result.baselinePath}`;

        case 'Mismatch':
            const pct = (result.diffPercent * 100).toFixed(2);
            return [
                `Visual comparison: MISMATCH`,
                `  Difference: ${pct}% (${result.diffPixels} pixels)`,
                `  Diff image: ${result.diffPath}`,
                `  Current: ${result.currentPath}`,
                `  Baseline: ${result.baselinePath}`
            ].join('\n');

        case 'DimensionMismatch':
            return [
                `Visual comparison: DIMENSION MISMATCH`,
                `  Baseline: ${result.baseline.width}x${result.baseline.height}`,
                `  Current: ${result.current.width}x${result.current.height}`
            ].join('\n');

        default:
            return `Visual comparison: Unknown result type: ${result.type}`;
    }
}

// ============================================================================
// Module Exports
// ============================================================================

module.exports = {
    // Comparison
    compare,
    compareDefault,
    compareStrict,
    compareLenient,

    // Baseline management
    updateBaseline,
    deleteBaseline,
    baselineExists,
    listBaselines,
    cleanDiffs,

    // Full flow
    snapshot,
    snapshotElement,
    snapshotDefault,
    snapshotResponsive,

    // Viewports
    viewportMobile,
    viewportTablet,
    viewportDesktop,
    viewportDesktopLarge,

    // Result helpers
    isMatch,
    isMismatch,
    isBaselineCreated,
    formatResult
};
