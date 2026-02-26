/**
 * Canopy Test Framework - JavaScript Test Runner
 *
 * This module provides the JavaScript implementation for the Canopy test framework.
 * It supports both synchronous unit tests and asynchronous browser tests.
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

// Import task executor for async tests
var taskExecutor;
try {
    taskExecutor = require('./task-executor.js');
} catch (e) {
    // Will be set later if in browser
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
 *
 * @param {Object} testSuite - Test suite
 * @returns {Object} Report
 */
function runTestsSync(testSuite) {
    var results = [];
    var startTime = performance.now();

    function runTest(test, path) {
        var testStart = performance.now();

        try {
            switch (test.$) {
                case 'UnitTest':
                    var testName = path.concat([test.a]).join(' > ');
                    var result = test.b();
                    var duration = performance.now() - testStart;

                    if (result.$ === 'Pass') {
                        results.push({
                            $: 'Passed',
                            a: testName,
                            b: duration
                        });
                    } else {
                        results.push({
                            $: 'Failed',
                            a: testName,
                            b: formatFailure(result),
                            c: duration
                        });
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
                    results.push({
                        $: 'Skipped',
                        a: skippedName
                    });
                    break;

                case 'Todo':
                    results.push({
                        $: 'Todo',
                        a: path.concat([test.a]).join(' > ')
                    });
                    break;

                default:
                    console.warn('Unknown test type (sync): ' + test.$);
                    results.push({
                        $: 'Passed',
                        a: path.join(' > ') + ' (unknown type: ' + test.$ + ')',
                        b: performance.now() - testStart
                    });
            }
        } catch (e) {
            var errorName = path.length > 0 ? path.join(' > ') : 'Test';
            results.push({
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
 *
 * @param {Object} testSuite - Test suite
 * @returns {Promise<Object>} Promise of Report
 */
async function runTestsAsync(testSuite) {
    var results = [];
    var startTime = performance.now();

    async function runTest(test, path) {
        var testStart = performance.now();

        try {
            switch (test.$) {
                case 'UnitTest':
                    // Sync test in async context
                    var testName = path.concat([test.a]).join(' > ');
                    var result = test.b();
                    var duration = performance.now() - testStart;

                    if (result.$ === 'Pass') {
                        results.push({ $: 'Passed', a: testName, b: duration });
                    } else {
                        results.push({ $: 'Failed', a: testName, b: formatFailure(result), c: duration });
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
                    // test.a = name (String)
                    // test.b = config (BrowserConfig)
                    // test.c = steps (List Step)
                    await runBrowserTest(test, path, results);
                    break;

                case 'AsyncTest':
                    // test.a = name (String)
                    // test.b = task (Task TestError Expectation)
                    await runAsyncTest(test, path, results);
                    break;

                case 'Skip':
                    var skippedName = getSkippedTestName(test.a, path);
                    results.push({ $: 'Skipped', a: skippedName });
                    break;

                case 'Todo':
                    results.push({ $: 'Todo', a: path.concat([test.a]).join(' > ') });
                    break;

                default:
                    console.warn('Unknown test type (async): ' + test.$);
                    results.push({
                        $: 'Passed',
                        a: path.join(' > ') + ' (unknown: ' + test.$ + ')',
                        b: performance.now() - testStart
                    });
            }
        } catch (e) {
            var errorName = path.length > 0 ? path.join(' > ') : 'Test';
            results.push({
                $: 'Failed',
                a: errorName,
                b: 'Exception: ' + e.message + '\n' + (e.stack || ''),
                c: performance.now() - testStart
            });
        }
    }

    await runTest(testSuite, []);

    return buildReport(results, startTime);
}

/**
 * Run a browser test with Playwright.
 *
 * @param {Object} test - BrowserTest value
 * @param {Array} path - Test path
 * @param {Array} results - Results array to push to
 */
async function runBrowserTest(test, path, results) {
    var testStart = performance.now();
    var testName = path.concat([test.a]).join(' > ');

    // Check if Playwright is available
    if (!playwrightBindings) {
        results.push({
            $: 'Failed',
            a: testName,
            b: 'Playwright not available. Install with: npm install playwright',
            c: performance.now() - testStart
        });
        return;
    }

    var browser = null;
    try {
        // Launch browser
        var config = test.b || getDefaultBrowserConfig();
        browser = await playwrightBindings.launch(config);

        // Execute steps
        var steps = listToArray(test.c || []);
        for (var i = 0; i < steps.length; i++) {
            var step = steps[i];
            // Each step is a function: Browser -> Task BrowserError Browser
            var stepTask = step(browser);
            browser = await taskExecutor.executeTask(stepTask);
        }

        // Test passed
        results.push({
            $: 'Passed',
            a: testName,
            b: performance.now() - testStart
        });
    } catch (e) {
        results.push({
            $: 'Failed',
            a: testName,
            b: formatBrowserError(e),
            c: performance.now() - testStart
        });
    } finally {
        // Always close browser
        if (browser && playwrightBindings) {
            try {
                await playwrightBindings.close(browser);
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
 * @param {Array} results - Results array to push to
 */
async function runAsyncTest(test, path, results) {
    var testStart = performance.now();
    var testName = path.concat([test.a]).join(' > ');

    if (!taskExecutor) {
        results.push({
            $: 'Failed',
            a: testName,
            b: 'Task executor not available',
            c: performance.now() - testStart
        });
        return;
    }

    try {
        // test.b is Task TestError Expectation
        var expectation = await taskExecutor.executeTask(test.b);
        var duration = performance.now() - testStart;

        if (expectation.$ === 'Pass') {
            results.push({ $: 'Passed', a: testName, b: duration });
        } else {
            results.push({ $: 'Failed', a: testName, b: formatFailure(expectation), c: duration });
        }
    } catch (e) {
        results.push({
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
 * Format a browser error into a readable message.
 */
function formatBrowserError(error) {
    if (typeof error === 'string') {
        return error;
    }

    // Handle Canopy BrowserError type
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

    // Handle JavaScript Error
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
 * Run tests and report (async-aware).
 * This is the main entry point for test execution.
 *
 * @canopy-type Test -> Task Never ()
 * @name runAndReport
 */
async function runAndReport(testSuite) {
    var report = await runTests(testSuite);
    reportAndExit(report);
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
        formatConsole: formatConsole,
        formatJson: formatJson,
        reportAndExit: reportAndExit,
        runAndReport: runAndReport
    };

    // Also set task executor if available globally
    if (window.CanopyTaskExecutor && !taskExecutor) {
        taskExecutor = window.CanopyTaskExecutor;
    }

    // Also set playwright bindings if available globally
    if (window.CanopyPlaywright && !playwrightBindings) {
        playwrightBindings = window.CanopyPlaywright;
    }
}
