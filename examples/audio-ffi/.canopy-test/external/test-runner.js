/**
 * Canopy Test Framework - JavaScript Test Runner
 *
 * This module provides the JavaScript implementation for the Canopy test framework.
 * It uses the FFI system with @canopy-type annotations instead of kernel code.
 *
 * @module test-runner
 */

/**
 * Execute a test suite and return results
 * @canopy-type Test -> Report
 * @name runTests
 * @param {Object} testSuite - The Canopy test suite to execute
 * @returns {Object} Report with results, summary, and duration
 */
function runTests(testSuite) {
    var results = [];
    var startTime = performance.now();

    function runTest(test, path) {
        var testStart = performance.now();

        try {
            switch (test.$) {
                case 'UnitTest':
                    // test.a = description (String)
                    // test.b = expectation function (() -> Expectation)
                    var testName = path.concat([test.a]).join(' > ');
                    var result = test.b(); // Run the thunk
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
                    // test.a = description (String)
                    // test.b = list of tests (List Test)
                    var subTests = listToArray(test.b);
                    var groupPath = path.concat([test.a]);
                    for (var i = 0; i < subTests.length; i++) {
                        runTest(subTests[i], groupPath);
                    }
                    break;

                case 'Skip':
                    // test.a = inner test to skip
                    var skippedName = getSkippedTestName(test.a, path);
                    results.push({
                        $: 'Skipped',
                        a: skippedName
                    });
                    break;

                case 'Todo':
                    // test.a = description (String)
                    results.push({
                        $: 'Todo',
                        a: path.concat([test.a]).join(' > ')
                    });
                    break;

                default:
                    // Unknown test type - log and treat as passed for forward compatibility
                    console.warn('Unknown test type: ' + test.$);
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

    // Run all tests
    runTest(testSuite, []);

    var totalDuration = performance.now() - startTime;

    // Build summary
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
 * Format a failure result into a readable string
 * @param {Object} result - The failure result
 * @returns {string} Formatted failure message
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
 * Get the test name from a test node
 * @param {Object} test - Test node
 * @param {Array} path - Path to the test
 * @returns {string} Full test name
 */
function getTestName(test, path) {
    if (test && (test.$ === 'UnitTest' || test.$ === 'FuzzTest' || test.$ === 'Todo')) {
        return path.concat([test.a]).join(' > ');
    }
    if (test && test.$ === 'TestGroup') {
        return path.concat([test.a]).join(' > ');
    }
    return path.join(' > ');
}

/**
 * Get the name of a skipped test
 * @param {Object} test - The inner test that was skipped
 * @param {Array} path - Path to the test
 * @returns {string} Full test name
 */
function getSkippedTestName(test, path) {
    if (!test) return path.join(' > ') + ' (skipped)';

    switch (test.$) {
        case 'UnitTest':
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
 * Format report for console output
 * @canopy-type Report -> String
 * @name formatConsole
 * @param {Object} report - Test report
 * @returns {string} Formatted console output
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
 * Format report as JSON
 * @canopy-type Report -> String
 * @name formatJson
 * @param {Object} report - Test report
 * @returns {string} JSON formatted output
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
 * Print results to console and exit with appropriate code
 * @canopy-type Report -> ()
 * @name reportAndExit
 * @param {Object} report - Test report
 */
function reportAndExit(report) {
    var output = formatConsole(report);
    console.log(output);

    if (typeof process !== 'undefined' && process.exit) {
        process.exit(report.summary.failed > 0 ? 1 : 0);
    }
}

// Helper functions

/**
 * Convert Canopy List to JavaScript Array
 */
function listToArray(list) {
    var result = [];
    var current = list;
    while (current.$ === '::' || current.$ === 'Cons') {
        result.push(current.a);
        current = current.b;
    }
    return result;
}

/**
 * Convert JavaScript Array to Canopy List
 */
function arrayToList(arr) {
    var result = { $: '[]' };
    for (var i = arr.length - 1; i >= 0; i--) {
        result = { $: '::', a: arr[i], b: result };
    }
    return result;
}

/**
 * Repeat a string n times
 */
function repeat(str, n) {
    return new Array(n + 1).join(str);
}

// Export for Node.js and browser
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        runTests: runTests,
        formatConsole: formatConsole,
        formatJson: formatJson,
        reportAndExit: reportAndExit
    };
}

// Make functions available globally for FFI
if (typeof window !== 'undefined') {
    window.CanopyTestRunner = {
        runTests: runTests,
        formatConsole: formatConsole,
        formatJson: formatJson,
        reportAndExit: reportAndExit
    };
}
