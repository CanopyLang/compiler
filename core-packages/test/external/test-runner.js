/**
 * Canopy Test Framework - JavaScript Test Runner
 *
 * This module provides the JavaScript implementation for the Canopy test framework.
 * It supports both synchronous unit tests and asynchronous browser tests.
 *
 * Output protocol: NDJSON (newline-delimited JSON). Each test result and the
 * final summary are emitted as one JSON object per line on stdout. The Haskell
 * side reads line-by-line and formats with ColorQQ for TTY-aware output.
 *
 * Browser reuse: when a test suite contains BrowserTest nodes, a single
 * Playwright browser + context + page is launched via playwrightBindings.launch()
 * before the tree walk and closed after all tests complete. Every
 * BrowserTest reuses the same page — since each test starts with `visit`
 * (full navigation with `waitUntil: 'networkidle'`), DOM and JS state are
 * reset automatically. Route handlers are cleaned up via `unrouteAll()`
 * between tests.
 *
 * Test Types:
 *   - UnitTest: Synchronous test with immediate expectation
 *   - TestGroup: Group of tests (describe block)
 *   - BrowserTest: Async browser test with Playwright steps
 *   - AsyncTest: Generic async test returning Task<Expectation>
 *   - Skip: Skipped test
 *   - Todo: Placeholder test
 *
 * @module test-runner
 */

// Synchronous file descriptor writes for unbuffered NDJSON output
var _fs = require('fs');

// Import task executor for async tests
var taskExecutor;
try {
    taskExecutor = require('./task-executor.js');
} catch (e) {
    taskExecutor = null;
}

// Import playwright bindings for browser tests
var playwrightBindings;
try {
    playwrightBindings = require('./playwright.js');
} catch (e) {
    playwrightBindings = null;
}

/**
 * Check if a test suite contains async tests.
 *
 * @param {Object} testSuite - Canopy Test value
 * @returns {boolean} True if suite contains BrowserTest or AsyncTest
 */
function hasAsyncTests(testSuite) {
    if (!testSuite) return false;

    switch (testSuite.$) {
        case 'BrowserTest':
        case 'AsyncTest':
            return true;

        case 'TestGroup':
            var subTests = listToArray(testSuite.b);
            return subTests.some(hasAsyncTests);

        case 'Skip':
            return hasAsyncTests(testSuite.a);

        default:
            return false;
    }
}

/**
 * Check if a test suite contains browser tests (BrowserTest nodes).
 *
 * @param {Object} testSuite - Canopy Test value
 * @returns {boolean} True if suite contains at least one BrowserTest
 */
function hasBrowserTests(testSuite) {
    if (!testSuite) return false;

    switch (testSuite.$) {
        case 'BrowserTest':
            return true;

        case 'TestGroup':
            var subTests = listToArray(testSuite.b);
            return subTests.some(hasBrowserTests);

        case 'Skip':
            return hasBrowserTests(testSuite.a);

        default:
            return false;
    }
}

/**
 * Emit a single test result as NDJSON to stdout.
 *
 * @param {Object} result - Internal result object ({$, a, b, c})
 */
function emitResult(result) {
    var obj = { event: 'result' };
    switch (result.$) {
        case 'Passed':
            obj.status = 'passed';
            obj.name = result.a;
            obj.duration = result.b;
            break;
        case 'Failed':
            obj.status = 'failed';
            obj.name = result.a;
            obj.message = result.b;
            obj.duration = result.c;
            break;
        case 'Skipped':
            obj.status = 'skipped';
            obj.name = result.a;
            break;
        case 'Todo':
            obj.status = 'todo';
            obj.name = result.a;
            break;
    }
    _fs.writeSync(1, JSON.stringify(obj) + '\n');
}

/**
 * Emit the final summary as NDJSON to stdout.
 *
 * @param {Object} report - Report object with summary and duration
 */
function emitSummary(report) {
    _fs.writeSync(1, JSON.stringify({
        event: 'summary',
        passed: report.summary.passed,
        failed: report.summary.failed,
        skipped: report.summary.skipped,
        todo: report.summary.todo,
        total: report.summary.total,
        duration: report.duration
    }) + '\n');
}

/**
 * Execute a test suite and return results.
 * Automatically detects if async execution is needed.
 *
 * @canopy-type Test -> Report
 * @name runTests
 * @param {Object} testSuite - The Canopy test suite to execute
 * @returns {Object|Promise<Object>} Report with results, summary, and duration
 */
function runTests(testSuite) {
    if (hasAsyncTests(testSuite)) {
        return runTestsAsync(testSuite);
    }
    return runTestsSync(testSuite);
}

/**
 * Run tests synchronously (for unit tests only).
 * Emits NDJSON result events as each test completes.
 *
 * @param {Object} testSuite - Test suite
 * @returns {Object} Report
 */
function runTestsSync(testSuite) {
    var results = [];
    var startTime = performance.now();

    function pushAndEmit(result) {
        results.push(result);
        emitResult(result);
    }

    function runTest(test, path) {
        var testStart = performance.now();

        try {
            switch (test.$) {
                case 'UnitTest':
                    var testName = path.concat([test.a]).join(' > ');
                    var result = test.b();
                    var duration = performance.now() - testStart;

                    if (result.$ === 'Pass') {
                        pushAndEmit({ $: 'Passed', a: testName, b: duration });
                    } else {
                        pushAndEmit({ $: 'Failed', a: testName, b: formatFailure(result), c: duration });
                    }
                    break;

                case 'TestGroup':
                    var subTests = listToArray(test.b);
                    var groupPath = path.concat([test.a]);
                    for (var i = 0; i < subTests.length; i++) {
                        runTest(subTests[i], groupPath);
                    }
                    break;

                case 'Skip':
                    var skippedName = getSkippedTestName(test.a, path);
                    pushAndEmit({ $: 'Skipped', a: skippedName });
                    break;

                case 'Todo':
                    pushAndEmit({ $: 'Todo', a: path.concat([test.a]).join(' > ') });
                    break;

                default:
                    console.warn('Unknown test type (sync): ' + test.$);
                    pushAndEmit({
                        $: 'Passed',
                        a: path.join(' > ') + ' (unknown type: ' + test.$ + ')',
                        b: performance.now() - testStart
                    });
            }
        } catch (e) {
            var errorName = path.length > 0 ? path.join(' > ') : 'Test';
            pushAndEmit({
                $: 'Failed',
                a: errorName,
                b: 'Exception: ' + e.message + '\n' + (e.stack || ''),
                c: performance.now() - testStart
            });
        }
    }

    runTest(testSuite, []);

    return buildReport(results, startTime);
}

/**
 * Run tests asynchronously (for browser and async tests).
 * Launches a single shared browser when the suite contains BrowserTest nodes.
 * Emits NDJSON result events as each test completes.
 *
 * @param {Object} testSuite - Test suite
 * @returns {Promise<Object>} Promise of Report
 */
async function runTestsAsync(testSuite) {
    var results = [];
    var startTime = performance.now();
    var sharedHandle = null;

    function pushAndEmit(result) {
        results.push(result);
        emitResult(result);
    }

    if (hasBrowserTests(testSuite) && playwrightBindings) {
        try {
            sharedHandle = await playwrightBindings.launch(
                applyRuntimeConfig(getDefaultBrowserConfig())
            );
        } catch (e) {
            process.stderr.write('Failed to launch shared browser: ' + e.message + '\n');
        }
    }

    async function runTest(test, path) {
        var testStart = performance.now();

        try {
            switch (test.$) {
                case 'UnitTest':
                    var testName = path.concat([test.a]).join(' > ');
                    var result = test.b();
                    var duration = performance.now() - testStart;

                    if (result.$ === 'Pass') {
                        pushAndEmit({ $: 'Passed', a: testName, b: duration });
                    } else {
                        pushAndEmit({ $: 'Failed', a: testName, b: formatFailure(result), c: duration });
                    }
                    break;

                case 'TestGroup':
                    var subTests = listToArray(test.b);
                    var groupPath = path.concat([test.a]);
                    for (var i = 0; i < subTests.length; i++) {
                        await runTest(subTests[i], groupPath);
                    }
                    break;

                case 'BrowserTest':
                    await runBrowserTest(test, path, pushAndEmit, sharedHandle);
                    break;

                case 'AsyncTest':
                    await runAsyncTest(test, path, pushAndEmit);
                    break;

                case 'Skip':
                    var skippedName = getSkippedTestName(test.a, path);
                    pushAndEmit({ $: 'Skipped', a: skippedName });
                    break;

                case 'Todo':
                    pushAndEmit({ $: 'Todo', a: path.concat([test.a]).join(' > ') });
                    break;

                default:
                    console.warn('Unknown test type (async): ' + test.$);
                    pushAndEmit({
                        $: 'Passed',
                        a: path.join(' > ') + ' (unknown: ' + test.$ + ')',
                        b: performance.now() - testStart
                    });
            }
        } catch (e) {
            var errorName = path.length > 0 ? path.join(' > ') : 'Test';
            pushAndEmit({
                $: 'Failed',
                a: errorName,
                b: 'Exception: ' + e.message + '\n' + (e.stack || ''),
                c: performance.now() - testStart
            });
        }
    }

    try {
        await runTest(testSuite, []);
    } finally {
        if (sharedHandle) {
            try {
                await playwrightBindings.close(sharedHandle);
            } catch (e) {
                // Ignore close errors
            }
        }
    }

    return buildReport(results, startTime);
}

/**
 * Run a browser test with Playwright.
 * When a shared handle is provided, reuses its existing page — every
 * browser test starts with `visit` which does a full navigation
 * (`waitUntil: 'networkidle'`), resetting DOM and JS state. Route
 * handlers are cleaned up via `unrouteAll()` after each test. Falls
 * back to launching a dedicated browser when no shared handle exists.
 *
 * @param {Object} test - BrowserTest value
 * @param {Array} path - Test path
 * @param {Function} pushAndEmit - Callback to record and emit a result
 * @param {Object|null} sharedHandle - Shared Playwright handle from playwrightBindings.launch(), or null
 */
async function runBrowserTest(test, path, pushAndEmit, sharedHandle) {
    var testStart = performance.now();
    var testName = path.concat([test.a]).join(' > ');

    if (!playwrightBindings) {
        pushAndEmit({
            $: 'Failed',
            a: testName,
            b: 'Playwright not available. Install with: npm install playwright',
            c: performance.now() - testStart
        });
        return;
    }

    var config = test.b || getDefaultBrowserConfig();
    config = applyRuntimeConfig(config);

    var browserHandle = null;
    var ownHandle = false;

    try {
        if (sharedHandle) {
            sharedHandle._page.setDefaultTimeout(config.timeout || 30000);
            browserHandle = {
                _browser: sharedHandle._browser,
                _context: sharedHandle._context,
                _page: sharedHandle._page,
                _config: config
            };
        } else {
            browserHandle = await playwrightBindings.launch(config);
            ownHandle = true;
        }

        var steps = listToArray(test.c || []);
        for (var i = 0; i < steps.length; i++) {
            var step = steps[i];
            var stepTask = step(browserHandle);
            browserHandle = await taskExecutor.executeTask(stepTask);
        }

        pushAndEmit({
            $: 'Passed',
            a: testName,
            b: performance.now() - testStart
        });
    } catch (e) {
        pushAndEmit({
            $: 'Failed',
            a: testName,
            b: formatBrowserError(e),
            c: performance.now() - testStart
        });
    } finally {
        if (sharedHandle && browserHandle) {
            try {
                await browserHandle._page.unrouteAll();
            } catch (e) {
                // Ignore cleanup errors
            }
        } else if (ownHandle && browserHandle) {
            try {
                await playwrightBindings.close(browserHandle);
            } catch (e) {
                // Ignore close errors
            }
        }
    }
}

/**
 * Run an async test (Task-based).
 *
 * @param {Object} test - AsyncTest value
 * @param {Array} path - Test path
 * @param {Function} pushAndEmit - Callback to record and emit a result
 */
async function runAsyncTest(test, path, pushAndEmit) {
    var testStart = performance.now();
    var testName = path.concat([test.a]).join(' > ');

    if (!taskExecutor) {
        pushAndEmit({
            $: 'Failed',
            a: testName,
            b: 'Task executor not available',
            c: performance.now() - testStart
        });
        return;
    }

    try {
        var expectation = await taskExecutor.executeTask(test.b);
        var duration = performance.now() - testStart;

        if (expectation.$ === 'Pass') {
            pushAndEmit({ $: 'Passed', a: testName, b: duration });
        } else {
            pushAndEmit({ $: 'Failed', a: testName, b: formatFailure(expectation), c: duration });
        }
    } catch (e) {
        pushAndEmit({
            $: 'Failed',
            a: testName,
            b: 'Async test error: ' + (e.message || String(e)),
            c: performance.now() - testStart
        });
    }
}

/**
 * Get default browser configuration.
 */
function getDefaultBrowserConfig() {
    return {
        browser: 'chromium',
        headless: true,
        slowMo: 0,
        viewport: { width: 1280, height: 720 },
        timeout: 30000,
        recordVideo: false
    };
}

/**
 * Apply runtime configuration from TEST_CONFIG (set by --headed, --slowmo flags).
 *
 * TEST_CONFIG.headed=true means show the browser, which maps to headless=false.
 * Runtime flags override compile-time defaults from the Canopy test definition.
 */
function applyRuntimeConfig(config) {
    if (typeof TEST_CONFIG === 'undefined') return config;
    var result = Object.assign({}, config);
    if (TEST_CONFIG.headed) {
        result.headless = false;
    }
    if (TEST_CONFIG.slowMo) {
        result.slowMo = TEST_CONFIG.slowMo;
    }
    return result;
}

/**
 * Format a browser error into a readable message.
 */
function formatBrowserError(error) {
    if (typeof error === 'string') {
        return error;
    }

    if (error && error.$) {
        switch (error.$) {
            case 'LaunchError':
                return 'Browser launch failed: ' + error.a;
            case 'NavigationError':
                return 'Navigation failed: ' + error.a;
            case 'ElementNotFound':
                return 'Element not found: ' + error.a;
            case 'TimeoutError':
                return 'Timeout: ' + error.a;
            case 'EvaluationError':
                return 'JavaScript evaluation failed: ' + error.a;
            case 'ScreenshotError':
                return 'Screenshot failed: ' + error.a;
            case 'NetworkError':
                return 'Network error: ' + error.a;
            default:
                return 'Browser error (' + error.$ + '): ' + (error.a || JSON.stringify(error));
        }
    }

    if (error instanceof Error) {
        return error.message + (error.stack ? '\n' + error.stack : '');
    }

    return String(error);
}

/**
 * Build a report from results.
 */
function buildReport(results, startTime) {
    var totalDuration = performance.now() - startTime;

    var passed = results.filter(function(r) { return r.$ === 'Passed'; }).length;
    var failed = results.filter(function(r) { return r.$ === 'Failed'; }).length;
    var skipped = results.filter(function(r) { return r.$ === 'Skipped'; }).length;
    var todo = results.filter(function(r) { return r.$ === 'Todo'; }).length;

    return {
        results: arrayToList(results),
        summary: {
            total: results.length,
            passed: passed,
            failed: failed,
            skipped: skipped,
            todo: todo
        },
        duration: totalDuration
    };
}

/**
 * Format a failure result into a readable string.
 */
function formatFailure(result) {
    if (!result.a) return 'Unknown failure';

    switch (result.a.$) {
        case 'Equality':
            return result.a.a + '\n\nExpected:\n    ' + result.a.b +
                   '\n\nActual:\n    ' + result.a.c;
        case 'Comparison':
            return result.a.a + '\n\nExpected ' + result.a.b +
                   ' ' + result.a.c + ' ' + result.a.d;
        case 'Custom':
            return result.a.a;
        default:
            return 'Unknown failure type: ' + JSON.stringify(result.a);
    }
}

/**
 * Get the test name from a test node.
 */
function getTestName(test, path) {
    if (test && (test.$ === 'UnitTest' || test.$ === 'FuzzTest' || test.$ === 'Todo' ||
                 test.$ === 'BrowserTest' || test.$ === 'AsyncTest')) {
        return path.concat([test.a]).join(' > ');
    }
    if (test && test.$ === 'TestGroup') {
        return path.concat([test.a]).join(' > ');
    }
    return path.join(' > ');
}

/**
 * Get the name of a skipped test.
 */
function getSkippedTestName(test, path) {
    if (!test) return path.join(' > ') + ' (skipped)';

    switch (test.$) {
        case 'UnitTest':
        case 'BrowserTest':
        case 'AsyncTest':
            return path.concat([test.a]).join(' > ');
        case 'TestGroup':
            return path.concat([test.a]).join(' > ');
        case 'Skip':
            return getSkippedTestName(test.a, path);
        case 'Todo':
            return path.concat([test.a]).join(' > ');
        default:
            return path.join(' > ') + ' (skipped)';
    }
}

/**
 * Format report for console output.
 * Kept for backwards compatibility.
 *
 * @canopy-type Report -> String
 * @name formatConsole
 */
function formatConsole(report) {
    var output = [];
    var results = listToArray(report.results);
    var summary = report.summary;

    output.push('\n' + repeat('─', 60));
    output.push('  Test Results');
    output.push(repeat('─', 60) + '\n');

    results.forEach(function(result) {
        switch (result.$) {
            case 'Passed':
                output.push('  ✓ ' + result.a + ' (' + result.b.toFixed(1) + 'ms)');
                break;
            case 'Failed':
                output.push('  ✗ ' + result.a + ' (' + result.c.toFixed(1) + 'ms)');
                output.push('    ' + result.b.replace(/\n/g, '\n    '));
                break;
            case 'Skipped':
                output.push('  ○ ' + result.a + ' (skipped)');
                break;
            case 'Todo':
                output.push('  ◌ ' + result.a + ' (todo)');
                break;
        }
    });

    output.push('\n' + repeat('─', 60));

    var summaryParts = [
        summary.passed + ' passed',
        summary.failed + ' failed'
    ];
    if (summary.skipped > 0) summaryParts.push(summary.skipped + ' skipped');
    if (summary.todo > 0) summaryParts.push(summary.todo + ' todo');

    output.push('  ' + summaryParts.join(', ') + ' (' + summary.total + ' total)');
    output.push('  Duration: ' + report.duration.toFixed(1) + 'ms');
    output.push(repeat('─', 60) + '\n');

    return output.join('\n');
}

/**
 * Format report as JSON.
 * Kept for backwards compatibility.
 *
 * @canopy-type Report -> String
 * @name formatJson
 */
function formatJson(report) {
    var results = listToArray(report.results);
    var jsonResults = results.map(function(r) {
        switch (r.$) {
            case 'Passed':
                return { status: 'passed', name: r.a, duration: r.b };
            case 'Failed':
                return { status: 'failed', name: r.a, message: r.b, duration: r.c };
            case 'Skipped':
                return { status: 'skipped', name: r.a };
            case 'Todo':
                return { status: 'todo', name: r.a };
            default:
                return { status: 'unknown', name: 'Unknown' };
        }
    });

    return JSON.stringify({
        results: jsonResults,
        summary: report.summary,
        duration: report.duration
    }, null, 2);
}

/**
 * Print results to console and exit with appropriate code.
 * Kept for backwards compatibility.
 *
 * @canopy-type Report -> ()
 * @name reportAndExit
 */
function reportAndExit(report) {
    var output = formatConsole(report);
    console.log(output);

    if (typeof process !== 'undefined' && process.exit) {
        process.exit(report.summary.failed > 0 ? 1 : 0);
    }
}

/**
 * Run tests and report via NDJSON streaming.
 * This is the main entry point for test execution.
 *
 * Individual result events are emitted during the tree walk (via pushAndEmit).
 * After all tests complete, a summary event is emitted and the process exits.
 *
 * @canopy-type Test -> Task Never ()
 * @name runAndReport
 */
async function runAndReport(testSuite) {
    var report = await runTests(testSuite);
    emitSummary(report);

    if (typeof process !== 'undefined' && process.exit) {
        process.exit(report.summary.failed > 0 ? 1 : 0);
    }
}

// Helper functions

function listToArray(list) {
    var result = [];
    var current = list;
    while (current && (current.$ === '::' || current.$ === 'Cons')) {
        result.push(current.a);
        current = current.b;
    }
    return result;
}

function arrayToList(arr) {
    var result = { $: '[]' };
    for (var i = arr.length - 1; i >= 0; i--) {
        result = { $: '::', a: arr[i], b: result };
    }
    return result;
}

function repeat(str, n) {
    return new Array(n + 1).join(str);
}

// Export for Node.js and browser
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        runTests: runTests,
        runTestsSync: runTestsSync,
        runTestsAsync: runTestsAsync,
        hasAsyncTests: hasAsyncTests,
        hasBrowserTests: hasBrowserTests,
        formatConsole: formatConsole,
        formatJson: formatJson,
        reportAndExit: reportAndExit,
        runAndReport: runAndReport
    };
}

// Make functions available globally for FFI
if (typeof window !== 'undefined') {
    window.CanopyTestRunner = {
        runTests: runTests,
        runTestsSync: runTestsSync,
        runTestsAsync: runTestsAsync,
        hasAsyncTests: hasAsyncTests,
        hasBrowserTests: hasBrowserTests,
        formatConsole: formatConsole,
        formatJson: formatJson,
        reportAndExit: reportAndExit,
        runAndReport: runAndReport
    };

    if (window.CanopyTaskExecutor && !taskExecutor) {
        taskExecutor = window.CanopyTaskExecutor;
    }

    if (window.CanopyPlaywright && !playwrightBindings) {
        playwrightBindings = window.CanopyPlaywright;
    }
}
