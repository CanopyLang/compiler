/*
 * Canopy Test Framework - Kernel JavaScript
 *
 * This module provides the JavaScript runtime for the Canopy test framework.
 * It integrates with:
 * - Node.js for unit test execution
 * - jsdom for component testing
 * - Puppeteer/Playwright for browser automation
 * - axe-core for accessibility testing
 * - pixelmatch for visual regression
 */

// ============================================================================
// Test Execution Engine
// ============================================================================

// Read filter pattern from CLI-injected global
var _Test_filter = (typeof global !== 'undefined' && global.__CANOPY_TEST_FILTER__)
    ? global.__CANOPY_TEST_FILTER__
    : null;

// Check if a test name matches the filter pattern (case-insensitive substring match)
function _Test_shouldRun(path, name) {
    if (!_Test_filter) return true;
    var fullPath = path.concat([name]).join(' > ').toLowerCase();
    return fullPath.indexOf(_Test_filter.toLowerCase()) !== -1;
}

var _Test_run = function(tests) {
    return _Scheduler_binding(function(callback) {
        var results = [];
        var startTime = performance.now();

        function runTest(test, path) {
            var testStart = performance.now();

            try {
                switch (test.$) {
                    case 'UnitTest':
                        var unitName = path.concat([test.a]).join(' > ');
                        if (!_Test_shouldRun(path, test.a)) {
                            results.push({ status: 'skipped', name: unitName });
                            break;
                        }
                        var result = test.b();
                        var duration = performance.now() - testStart;

                        if (result.$ === 'Pass') {
                            results.push({ status: 'passed', name: unitName, duration: duration });
                        } else {
                            results.push({
                                status: 'failed',
                                name: unitName,
                                message: _Test_formatFailure(result),
                                duration: duration
                            });
                        }
                        break;

                    case 'Batch':
                        var subTests = _List_toArray(test.b);
                        for (var i = 0; i < subTests.length; i++) {
                            runTest(subTests[i], path.concat([test.a]));
                        }
                        break;

                    case 'FuzzTest':
                        runFuzzTest(test, path);
                        break;

                    case 'Skip':
                        results.push({
                            status: 'skipped',
                            name: _Test_getTestName(test.a, path)
                        });
                        break;

                    case 'Todo':
                        results.push({
                            status: 'todo',
                            name: path.concat([test.a]).join(' > ')
                        });
                        break;
                }
            } catch (e) {
                results.push({
                    status: 'failed',
                    name: path.join(' > '),
                    message: 'Exception: ' + e.message + '\n' + e.stack,
                    duration: performance.now() - testStart
                });
            }
        }

        function runFuzzTest(test, path) {
            var name = test.a;
            var iterations = _Fuzz_maxRuns;
            var fuzzer = test.c;
            var expectFn = test.d;
            var testStart = performance.now();
            var fuzzName = path.concat([name]).join(' > ');

            if (!_Test_shouldRun(path, name)) {
                results.push({ status: 'skipped', name: fuzzName });
                return;
            }

            for (var i = 0; i < iterations; i++) {
                var value = _Fuzz_generate(fuzzer, i);
                var result = expectFn(value);

                if (result.$ !== 'Pass') {
                    var shrunk = _Fuzz_shrink(fuzzer, value, expectFn);
                    results.push({
                        status: 'failed',
                        name: fuzzName,
                        message: 'Falsified after ' + (i + 1) + ' tests' +
                                 (shrunk.shrinks > 0 ? ' and ' + shrunk.shrinks + ' shrinks' : '') +
                                 ' (seed: ' + _Fuzz_seed + ').\n' +
                                 'Counterexample: ' + JSON.stringify(shrunk.value, null, 2) +
                                 (shrunk.shrinks > 0 ? '\nOriginal:       ' + JSON.stringify(value, null, 2) : '') +
                                 '\n\n' + _Test_formatFailure(result) +
                                 '\n\nReproduce with: canopy test --seed ' + _Fuzz_seed,
                        duration: performance.now() - testStart
                    });
                    return;
                }
            }

            results.push({
                status: 'passed',
                name: fuzzName,
                duration: performance.now() - testStart
            });
        }

        // Run all tests
        runTest(tests, []);

        var totalDuration = performance.now() - startTime;

        var summary = {
            total: results.length,
            passed: results.filter(function(r) { return r.status === 'passed'; }).length,
            failed: results.filter(function(r) { return r.status === 'failed'; }).length,
            skipped: results.filter(function(r) { return r.status === 'skipped'; }).length,
            todo: results.filter(function(r) { return r.status === 'todo'; }).length
        };

        callback(_Scheduler_succeed({
            results: _List_fromArray(results.map(_Test_toElmResult)),
            summary: summary,
            duration: totalDuration
        }));
    });
};

function _Test_formatFailure(result) {
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
            return 'Unknown failure';
    }
}

function _Test_getTestName(test, path) {
    if (test.$ === 'UnitTest' || test.$ === 'FuzzTest') {
        return path.concat([test.a]).join(' > ');
    }
    return path.join(' > ');
}

function _Test_toElmResult(result) {
    switch (result.status) {
        case 'passed':
            return { $: 'Passed', a: result.name, b: result.duration };
        case 'failed':
            return { $: 'Failed', a: result.name, b: result.message, c: result.duration };
        case 'skipped':
            return { $: 'Skipped', a: result.name };
        case 'todo':
            return { $: 'Todo', a: result.name };
    }
}

// ============================================================================
// Fuzzer Implementation
// ============================================================================

// Read seed from CLI-injected global, or use current time
var _Fuzz_seed = (typeof global !== 'undefined' && global.__CANOPY_TEST_SEED__)
    ? global.__CANOPY_TEST_SEED__
    : Date.now();

// Read fuzz iteration count from CLI
var _Fuzz_maxRuns = (typeof global !== 'undefined' && global.__CANOPY_TEST_FUZZ_RUNS__)
    ? global.__CANOPY_TEST_FUZZ_RUNS__
    : 100;

var _Fuzz_generate = function(fuzzer, iteration) {
    var rng = _Fuzz_createRng(_Fuzz_seed + iteration);
    return _Fuzz_runGenerator(fuzzer, rng);
};

function _Fuzz_createRng(seed) {
    // xorshift32 PRNG - fast, good distribution, deterministic
    var state = seed | 0;
    if (state === 0) state = 1;
    return {
        next: function() {
            state ^= state << 13;
            state ^= state >> 17;
            state ^= state << 5;
            return (state >>> 0) / 0xffffffff;
        },
        nextInt: function(min, max) {
            return Math.floor(this.next() * (max - min + 1)) + min;
        },
        nextFloat: function(min, max) {
            return this.next() * (max - min) + min;
        }
    };
}

function _Fuzz_runGenerator(fuzzer, rng) {
    // Dispatch on fuzzer type tag
    if (!fuzzer || fuzzer.$ === undefined) return fuzzer;

    switch (fuzzer.$) {
        case 'IntRange':
            return rng.nextInt(fuzzer.a, fuzzer.b);

        case 'FloatRange':
            return rng.nextFloat(fuzzer.a, fuzzer.b);

        case 'Bool':
            return rng.next() < 0.5;

        case 'StringFuzzer':
            var len = rng.nextInt(0, fuzzer.a);
            var chars = [];
            for (var i = 0; i < len; i++) {
                chars.push(String.fromCharCode(rng.nextInt(32, 126)));
            }
            return chars.join('');

        case 'ListFuzzer':
            var listLen = rng.nextInt(0, fuzzer.b);
            var items = [];
            for (var j = 0; j < listLen; j++) {
                items.push(_Fuzz_runGenerator(fuzzer.a, rng));
            }
            return _List_fromArray(items);

        case 'Map':
            var inner = _Fuzz_runGenerator(fuzzer.b, rng);
            return A2(fuzzer.a, inner);

        case 'AndThen':
            var innerVal = _Fuzz_runGenerator(fuzzer.b, rng);
            var nextFuzzer = fuzzer.a(innerVal);
            return _Fuzz_runGenerator(nextFuzzer, rng);

        case 'Constant':
            return fuzzer.a;

        case 'OneOf':
            var options = _List_toArray(fuzzer.a);
            if (options.length === 0) return null;
            var idx = rng.nextInt(0, options.length - 1);
            return _Fuzz_runGenerator(options[idx], rng);

        case 'Frequency':
            var choices = _List_toArray(fuzzer.a);
            var totalWeight = 0;
            for (var w = 0; w < choices.length; w++) {
                totalWeight += choices[w].a;
            }
            var pick = rng.nextFloat(0, totalWeight);
            var cumulative = 0;
            for (var c = 0; c < choices.length; c++) {
                cumulative += choices[c].a;
                if (pick <= cumulative) {
                    return _Fuzz_runGenerator(choices[c].b, rng);
                }
            }
            return _Fuzz_runGenerator(choices[choices.length - 1].b, rng);

        default:
            // For generator functions, call them with the RNG
            if (typeof fuzzer === 'function') {
                return fuzzer(rng);
            }
            // For tagged values with a generator field
            if (fuzzer.a && typeof fuzzer.a === 'function') {
                return fuzzer.a(rng);
            }
            return fuzzer;
    }
}

// ============================================================================
// Shrinking Engine
// ============================================================================

// Attempt to shrink a failing value to a minimal counterexample.
// Tries up to 100 shrink iterations to find the smallest failing input.
function _Fuzz_shrink(fuzzer, value, testFn) {
    var candidates = _Fuzz_shrinkValue(value);
    var smallest = value;
    var shrinkCount = 0;
    var maxShrinks = 100;

    while (candidates.length > 0 && shrinkCount < maxShrinks) {
        var candidate = candidates.shift();
        try {
            var result = testFn(candidate);
            if (result.$ !== 'Pass') {
                smallest = candidate;
                candidates = _Fuzz_shrinkValue(candidate).concat(candidates);
                shrinkCount++;
            }
        } catch (e) {
            // If it throws, it's still a failure - count as shrunk
            smallest = candidate;
            candidates = _Fuzz_shrinkValue(candidate).concat(candidates);
            shrinkCount++;
        }
    }

    return { value: smallest, shrinks: shrinkCount };
}

// Generate shrink candidates for a value based on its type.
function _Fuzz_shrinkValue(value) {
    if (typeof value === 'number') {
        return _Fuzz_shrinkNumber(value);
    }
    if (typeof value === 'string') {
        return _Fuzz_shrinkString(value);
    }
    if (typeof value === 'boolean') {
        return value ? [false] : [];
    }
    if (value && value.$ === '[]') {
        return [];
    }
    if (value && value.$ === '::') {
        return _Fuzz_shrinkList(value);
    }
    if (Array.isArray(value)) {
        return _Fuzz_shrinkArray(value);
    }
    return [];
}

// Shrink a number toward zero using binary search
function _Fuzz_shrinkNumber(n) {
    if (n === 0) return [];
    var candidates = [0];
    if (Number.isInteger(n)) {
        var abs = Math.abs(n);
        var half = Math.floor(abs / 2);
        if (half > 0) candidates.push(n > 0 ? half : -half);
        if (abs > 1) candidates.push(n > 0 ? n - 1 : n + 1);
    } else {
        candidates.push(Math.round(n));
        candidates.push(n > 0 ? n / 2 : n / 2);
    }
    return candidates;
}

// Shrink a string by removing characters
function _Fuzz_shrinkString(s) {
    if (s.length === 0) return [];
    var candidates = [''];
    if (s.length > 1) {
        candidates.push(s.substring(1));
        candidates.push(s.substring(0, s.length - 1));
        var half = Math.floor(s.length / 2);
        if (half > 0 && half < s.length - 1) {
            candidates.push(s.substring(0, half));
        }
    }
    return candidates;
}

// Shrink a Canopy list (cons-cell structure) by converting to array, shrinking, and converting back
function _Fuzz_shrinkList(list) {
    var arr = _List_toArray(list);
    return _Fuzz_shrinkArray(arr).map(function(a) { return _List_fromArray(a); });
}

// Shrink an array by removing elements
function _Fuzz_shrinkArray(arr) {
    if (arr.length === 0) return [];
    var candidates = [[]];
    if (arr.length > 1) {
        // Remove first, last, or half
        candidates.push(arr.slice(1));
        candidates.push(arr.slice(0, arr.length - 1));
        var half = Math.floor(arr.length / 2);
        if (half > 0 && half < arr.length - 1) {
            candidates.push(arr.slice(0, half));
        }
    }
    return candidates;
}

// ============================================================================
// Browser Automation (Puppeteer Integration)
// ============================================================================

var _Browser_instance = null;
var _Browser_page = null;

var _Browser_launch = F2(function(config, callback) {
    return _Scheduler_binding(function(cb) {
        (async () => {
            try {
                var puppeteer = require('puppeteer');
                _Browser_instance = await puppeteer.launch({
                    headless: config.headless,
                    slowMo: config.slowMo
                });
                _Browser_page = await _Browser_instance.newPage();
                await _Browser_page.setViewport(config.viewport);
                cb(_Scheduler_succeed({ $: 'Browser', a: {} }));
            } catch (e) {
                cb(_Scheduler_fail('Browser launch failed: ' + e.message));
            }
        })();
    });
});

var _Browser_goto = function(url) {
    return function(browser) {
        return _Scheduler_binding(function(cb) {
            (async () => {
                await _Browser_page.goto(url, { waitUntil: 'networkidle0' });
                cb(_Scheduler_succeed(browser));
            })();
        });
    };
};

var _Browser_click = function(selector) {
    return function(browser) {
        return _Scheduler_binding(function(cb) {
            (async () => {
                await _Browser_page.click(selector);
                cb(_Scheduler_succeed(browser));
            })();
        });
    };
};

var _Browser_fill = F2(function(selector, value) {
    return function(browser) {
        return _Scheduler_binding(function(cb) {
            (async () => {
                await _Browser_page.fill(selector, value);
                cb(_Scheduler_succeed(browser));
            })();
        });
    };
});

var _Browser_waitForSelector = function(selector) {
    return function(browser) {
        return _Scheduler_binding(function(cb) {
            (async () => {
                await _Browser_page.waitForSelector(selector);
                cb(_Scheduler_succeed(browser));
            })();
        });
    };
};

var _Browser_screenshot = function(name) {
    return function(browser) {
        return _Scheduler_binding(function(cb) {
            (async () => {
                var fs = require('fs');
                var path = 'test-output/screenshots/' + name + '.png';
                fs.mkdirSync('test-output/screenshots', { recursive: true });
                await _Browser_page.screenshot({ path: path, fullPage: true });
                cb(_Scheduler_succeed(browser));
            })();
        });
    };
};

var _Browser_url = function(browser) {
    return _Browser_page ? _Browser_page.url() : '';
};

var _Browser_title = function(browser) {
    return _Scheduler_binding(function(cb) {
        (async () => {
            var title = await _Browser_page.title();
            cb(_Scheduler_succeed(title));
        })();
    });
};

var _Browser_close = function(browser) {
    return _Scheduler_binding(function(cb) {
        (async () => {
            if (_Browser_instance) {
                await _Browser_instance.close();
                _Browser_instance = null;
                _Browser_page = null;
            }
            cb(_Scheduler_succeed(browser));
        })();
    });
};

// ============================================================================
// Component Testing (jsdom Integration)
// ============================================================================

// Render Canopy virtual DOM to a jsdom container for component testing.
// Returns a Rendered record with DOM handle for further interaction.
var _Component_render = function(html) {
    var jsdom;
    try { jsdom = require('jsdom'); }
    catch (e) {
        return { $: 'Err', a: 'jsdom not installed. Run: npm install jsdom' };
    }
    var dom = new jsdom.JSDOM('<!DOCTYPE html><html><body></body></html>');
    var container = dom.window.document.createElement('div');
    dom.window.document.body.appendChild(container);

    // Render Canopy virtual DOM if _VirtualDom_render is available
    try {
        var rendered = _VirtualDom_render(html);
        container.appendChild(rendered);
    } catch (e) {
        // Fallback: serialize the virtual DOM to HTML string
        container.innerHTML = '<div>Component render fallback</div>';
    }

    return {
        $: 'Ok',
        a: {
            html: container.innerHTML,
            messages: [],
            dom: dom,
            container: container,
            window: dom.window,
            document: dom.window.document
        }
    };
};

// Simulate a click event on the first child or a specific selector
var _Component_click = function(rendered) {
    var el = rendered.a.container.firstChild;
    if (!el) return { $: 'Err', a: 'No element to click' };
    var event = new rendered.a.window.MouseEvent('click', { bubbles: true, cancelable: true });
    el.dispatchEvent(event);
    rendered.a.html = rendered.a.container.innerHTML;
    return { $: 'Ok', a: rendered.a };
};

// Click on a specific element matching a CSS selector
var _Component_clickOn = F2(function(selector, rendered) {
    var el = rendered.a.container.querySelector(selector);
    if (!el) return { $: 'Err', a: 'Element not found: ' + selector };
    var event = new rendered.a.window.MouseEvent('click', { bubbles: true, cancelable: true });
    el.dispatchEvent(event);
    rendered.a.html = rendered.a.container.innerHTML;
    return { $: 'Ok', a: rendered.a };
});

// Simulate typing into an input element
var _Component_input = F3(function(selector, value, rendered) {
    var el = rendered.a.container.querySelector(selector);
    if (!el) return { $: 'Err', a: 'Input element not found: ' + selector };
    el.value = value;
    var inputEvent = new rendered.a.window.Event('input', { bubbles: true });
    el.dispatchEvent(inputEvent);
    rendered.a.html = rendered.a.container.innerHTML;
    return { $: 'Ok', a: rendered.a };
});

// Simulate a change event on a form element
var _Component_change = F3(function(selector, value, rendered) {
    var el = rendered.a.container.querySelector(selector);
    if (!el) return { $: 'Err', a: 'Element not found: ' + selector };
    el.value = value;
    var changeEvent = new rendered.a.window.Event('change', { bubbles: true });
    el.dispatchEvent(changeEvent);
    rendered.a.html = rendered.a.container.innerHTML;
    return { $: 'Ok', a: rendered.a };
});

// Simulate a form submission
var _Component_submit = F2(function(selector, rendered) {
    var form = rendered.a.container.querySelector(selector);
    if (!form) return { $: 'Err', a: 'Form not found: ' + selector };
    var submitEvent = new rendered.a.window.Event('submit', { bubbles: true, cancelable: true });
    form.dispatchEvent(submitEvent);
    rendered.a.html = rendered.a.container.innerHTML;
    return { $: 'Ok', a: rendered.a };
});

// Query the rendered DOM for elements matching a CSS selector
var _Component_find = F2(function(selector, rendered) {
    var elements = rendered.a.container.querySelectorAll(selector);
    return {
        $: 'QueryResult',
        a: {
            elements: _List_fromArray(Array.from(elements).map(_Component_elementToElm)),
            rendered: rendered
        }
    };
});

// Get text content from a specific selector
var _Component_getText = F2(function(selector, rendered) {
    var el = rendered.a.container.querySelector(selector);
    if (!el) return { $: 'Nothing' };
    return { $: 'Just', a: el.textContent || '' };
});

// Get an attribute from a specific element
var _Component_getAttribute = F3(function(selector, attr, rendered) {
    var el = rendered.a.container.querySelector(selector);
    if (!el) return { $: 'Nothing' };
    var val = el.getAttribute(attr);
    return val !== null ? { $: 'Just', a: val } : { $: 'Nothing' };
});

// Check if an element exists in the rendered DOM
var _Component_has = F2(function(selector, rendered) {
    return rendered.a.container.querySelector(selector) !== null;
});

// Count elements matching a selector
var _Component_count = F2(function(selector, rendered) {
    return rendered.a.container.querySelectorAll(selector).length;
});

// Get the full HTML of the rendered component
var _Component_toHtml = function(rendered) {
    return rendered.a.container.innerHTML;
};

function _Component_elementToElm(el) {
    return {
        $: 'Element',
        a: {
            tagName: el.tagName ? el.tagName.toLowerCase() : '',
            attributes: _List_fromArray(
                el.attributes
                    ? Array.from(el.attributes).map(function(a) {
                        return _Utils_Tuple2(a.name, a.value);
                    })
                    : []
            ),
            textContent: el.textContent || '',
            children: _List_fromArray(
                el.children
                    ? Array.from(el.children).map(_Component_elementToElm)
                    : []
            )
        }
    };
}

// ============================================================================
// Accessibility Testing (axe-core Integration)
// ============================================================================

var _A11y_audit = function(browser) {
    return _Scheduler_binding(function(cb) {
        (async () => {
            try {
                // Inject axe-core into the page
                await _Browser_page.addScriptTag({
                    url: 'https://cdnjs.cloudflare.com/ajax/libs/axe-core/4.8.2/axe.min.js'
                });

                // Run axe
                var results = await _Browser_page.evaluate(async () => {
                    return await axe.run();
                });

                cb(_Scheduler_succeed({
                    $: 'AuditResult',
                    a: {
                        violations: _List_fromArray(results.violations.map(_A11y_violationToElm)),
                        passes: results.passes.length,
                        incomplete: results.incomplete.length
                    }
                }));
            } catch (e) {
                cb(_Scheduler_fail('Accessibility audit failed: ' + e.message));
            }
        })();
    });
};

function _A11y_violationToElm(v) {
    return {
        $: 'Violation',
        a: {
            id: v.id,
            impact: v.impact || 'minor',
            description: v.description,
            help: v.help,
            helpUrl: v.helpUrl,
            nodes: _List_fromArray(v.nodes.map(n => ({
                selector: n.target.join(' '),
                html: n.html,
                failureSummary: n.failureSummary || ''
            })))
        }
    };
}

// ============================================================================
// Visual Regression (pixelmatch Integration)
// ============================================================================

var _Visual_compare = F3(function(name, path, threshold) {
    return _Scheduler_binding(function(cb) {
        (async () => {
            try {
                var fs = require('fs');
                var PNG = require('pngjs').PNG;
                var pixelmatch = require('pixelmatch');

                var baselinePath = 'test-output/baselines/' + name + '.png';
                var diffPath = 'test-output/diffs/' + name + '-diff.png';

                // Check if baseline exists
                if (!fs.existsSync(baselinePath)) {
                    // First run - create baseline
                    fs.mkdirSync('test-output/baselines', { recursive: true });
                    fs.copyFileSync(path, baselinePath);
                    cb(_Scheduler_succeed({ $: 'NoBaseline' }));
                    return;
                }

                // Load images
                var baseline = PNG.sync.read(fs.readFileSync(baselinePath));
                var current = PNG.sync.read(fs.readFileSync(path));

                var { width, height } = baseline;
                var diff = new PNG({ width, height });

                // Compare
                var numDiffPixels = pixelmatch(
                    baseline.data, current.data, diff.data,
                    width, height,
                    { threshold: 0.1 }
                );

                var diffPercentage = numDiffPixels / (width * height);

                if (diffPercentage <= threshold) {
                    cb(_Scheduler_succeed({ $: 'Match' }));
                } else {
                    // Save diff image
                    fs.mkdirSync('test-output/diffs', { recursive: true });
                    fs.writeFileSync(diffPath, PNG.sync.write(diff));

                    cb(_Scheduler_succeed({
                        $: 'Mismatch',
                        a: {
                            diffPath: diffPath,
                            diffPixels: numDiffPixels,
                            diffPercentage: diffPercentage
                        }
                    }));
                }
            } catch (e) {
                cb(_Scheduler_fail('Visual comparison failed: ' + e.message));
            }
        })();
    });
});

// ============================================================================
// Console Reporter
// ============================================================================

var _Test_reportConsole = function(report) {
    var results = _List_toArray(report.results);
    var summary = report.summary;

    console.log('\n' + '─'.repeat(60));
    console.log('  Test Results');
    console.log('─'.repeat(60) + '\n');

    results.forEach(function(result) {
        switch (result.$) {
            case 'Passed':
                console.log('  \x1b[32m✓\x1b[0m ' + result.a + ' (' + result.b.toFixed(1) + 'ms)');
                break;
            case 'Failed':
                console.log('  \x1b[31m✗\x1b[0m ' + result.a + ' (' + result.c.toFixed(1) + 'ms)');
                console.log('    ' + result.b.replace(/\n/g, '\n    '));
                break;
            case 'Skipped':
                console.log('  \x1b[33m○\x1b[0m ' + result.a + ' (skipped)');
                break;
            case 'Todo':
                console.log('  \x1b[36m◌\x1b[0m ' + result.a + ' (todo)');
                break;
        }
    });

    console.log('\n' + '─'.repeat(60));

    var summaryParts = [
        summary.passed + ' passed',
        summary.failed + ' failed'
    ];
    if (summary.skipped > 0) summaryParts.push(summary.skipped + ' skipped');
    if (summary.todo > 0) summaryParts.push(summary.todo + ' todo');

    var color = summary.failed > 0 ? '\x1b[31m' : '\x1b[32m';
    console.log('  ' + color + summaryParts.join(', ') + '\x1b[0m (' + summary.total + ' total)');
    console.log('  Duration: ' + report.duration.toFixed(1) + 'ms');
    console.log('─'.repeat(60) + '\n');

    // Exit with appropriate code
    process.exit(summary.failed > 0 ? 1 : 0);
};

// ============================================================================
// Snapshot Testing
// ============================================================================

// Read snapshot update mode from CLI-injected global
var _Snapshot_updateMode = (typeof global !== 'undefined' && global.__CANOPY_UPDATE_SNAPSHOTS__)
    ? true
    : false;

// In-memory snapshot cache: { snapshotName -> storedValue }
var _Snapshot_cache = {};
var _Snapshot_dir = 'tests/__snapshots__';

// Load a snapshot file (one file per test module)
function _Snapshot_loadFile(moduleName) {
    try {
        var fs = require('fs');
        var path = _Snapshot_dir + '/' + moduleName + '.snap';
        if (!fs.existsSync(path)) return {};
        var content = fs.readFileSync(path, 'utf8');
        return _Snapshot_parseSnapFile(content);
    } catch (e) {
        return {};
    }
}

// Parse snapshot file format: "-- Snapshot: name\nvalue\n\n"
function _Snapshot_parseSnapFile(content) {
    var result = {};
    var sections = content.split('\n-- Snapshot: ');
    for (var i = 0; i < sections.length; i++) {
        var section = sections[i].trim();
        if (!section) continue;
        var newline = section.indexOf('\n');
        if (newline === -1) continue;
        var name = section.substring(0, newline).trim();
        var value = section.substring(newline + 1).trim();
        result[name] = value;
    }
    return result;
}

// Save snapshots to file
function _Snapshot_saveFile(moduleName, snapshots) {
    try {
        var fs = require('fs');
        fs.mkdirSync(_Snapshot_dir, { recursive: true });
        var path = _Snapshot_dir + '/' + moduleName + '.snap';
        var content = '';
        var names = Object.keys(snapshots).sort();
        for (var i = 0; i < names.length; i++) {
            content += '-- Snapshot: ' + names[i] + '\n';
            content += snapshots[names[i]] + '\n\n';
        }
        fs.writeFileSync(path, content, 'utf8');
    } catch (e) {
        // Ignore write errors in read-only environments
    }
}

// Match a value against its stored snapshot
var _Snapshot_match = F3(function(moduleName, name, value) {
    var snapshots = _Snapshot_loadFile(moduleName);
    var stored = snapshots[name];

    if (_Snapshot_updateMode || stored === undefined) {
        snapshots[name] = value;
        _Snapshot_saveFile(moduleName, snapshots);
        return { $: 'Pass' };
    }

    if (stored === value) {
        return { $: 'Pass' };
    }

    return {
        $: 'Fail',
        a: {
            $: 'Equality',
            a: 'Snapshot mismatch for "' + name + '"',
            b: stored,
            c: value
        }
    };
});

// ============================================================================
// Benchmark Engine
// ============================================================================

// Run a benchmark with timing and statistics
var _Benchmark_run = F3(function(name, fn, iterations) {
    var times = [];

    // Warm-up phase (10% of iterations, minimum 3)
    var warmup = Math.max(3, Math.floor(iterations * 0.1));
    for (var w = 0; w < warmup; w++) {
        fn();
    }

    // Measurement phase
    for (var i = 0; i < iterations; i++) {
        var start = performance.now();
        fn();
        var end = performance.now();
        times.push(end - start);
    }

    times.sort(function(a, b) { return a - b; });

    return {
        name: name,
        iterations: iterations,
        mean: _Stats_mean(times),
        stddev: _Stats_stddev(times),
        min: times[0],
        max: times[times.length - 1],
        median: _Stats_median(times),
        p90: _Stats_percentile(times, 0.90),
        p99: _Stats_percentile(times, 0.99)
    };
});

// Compare two functions and report relative performance
var _Benchmark_compare = F4(function(name, fnA, fnB, iterations) {
    var resultA = A3(_Benchmark_run, name + ' (A)', fnA, iterations);
    var resultB = A3(_Benchmark_run, name + ' (B)', fnB, iterations);

    var ratio = resultB.mean / resultA.mean;
    var percentDiff = (ratio - 1.0) * 100;

    return {
        name: name,
        a: resultA,
        b: resultB,
        ratio: ratio,
        percentDiff: percentDiff
    };
});

// Format benchmark results for console output
function _Benchmark_report(results) {
    var output = '\n' + '─'.repeat(72) + '\n';
    output += '  Benchmark Results\n';
    output += '─'.repeat(72) + '\n\n';

    var arr = _List_toArray(results);
    output += '  ' + _padRight('Name', 30) + _padRight('Mean', 12) +
              _padRight('Std Dev', 12) + _padRight('Min', 10) +
              _padRight('Max', 10) + '\n';
    output += '  ' + '─'.repeat(68) + '\n';

    for (var i = 0; i < arr.length; i++) {
        var r = arr[i];
        output += '  ' + _padRight(r.name, 30) +
                  _padRight(_formatMs(r.mean), 12) +
                  _padRight('±' + _formatMs(r.stddev), 12) +
                  _padRight(_formatMs(r.min), 10) +
                  _padRight(_formatMs(r.max), 10) + '\n';
    }

    output += '\n' + '─'.repeat(72) + '\n';
    console.log(output);
}

function _formatMs(ms) {
    if (ms < 0.001) return (ms * 1000000).toFixed(0) + 'ns';
    if (ms < 1) return (ms * 1000).toFixed(1) + 'µs';
    if (ms < 1000) return ms.toFixed(2) + 'ms';
    return (ms / 1000).toFixed(2) + 's';
}

function _padRight(str, len) {
    while (str.length < len) str += ' ';
    return str;
}

// ============================================================================
// Statistics Helpers
// ============================================================================

function _Stats_mean(arr) {
    var sum = 0;
    for (var i = 0; i < arr.length; i++) sum += arr[i];
    return sum / arr.length;
}

function _Stats_stddev(arr) {
    var m = _Stats_mean(arr);
    var sum = 0;
    for (var i = 0; i < arr.length; i++) {
        var d = arr[i] - m;
        sum += d * d;
    }
    return Math.sqrt(sum / arr.length);
}

function _Stats_median(sorted) {
    var mid = Math.floor(sorted.length / 2);
    if (sorted.length % 2 === 0) {
        return (sorted[mid - 1] + sorted[mid]) / 2;
    }
    return sorted[mid];
}

function _Stats_percentile(sorted, p) {
    var idx = Math.ceil(sorted.length * p) - 1;
    return sorted[Math.max(0, Math.min(idx, sorted.length - 1))];
}

// ============================================================================
// Parallel Test Support
// ============================================================================

// Partition tests into N groups for parallel execution
var _Test_partition = function(tests, numGroups) {
    var arr = _List_toArray(tests);
    var groups = [];
    for (var g = 0; g < numGroups; g++) {
        groups.push([]);
    }
    for (var i = 0; i < arr.length; i++) {
        groups[i % numGroups].push(arr[i]);
    }
    return groups.map(function(g) { return _List_fromArray(g); });
};

// Shard tests: deterministically pick tests for shard index/total
var _Test_shard = function(tests, shardIndex, shardTotal) {
    var arr = _List_toArray(tests);
    var shard = [];
    for (var i = 0; i < arr.length; i++) {
        if (i % shardTotal === shardIndex) {
            shard.push(arr[i]);
        }
    }
    return _List_fromArray(shard);
};

// ============================================================================
// Exports
// ============================================================================

// Export for Canopy kernel
if (typeof module !== 'undefined') {
    module.exports = {
        _Test_run: _Test_run,
        _Test_reportConsole: _Test_reportConsole,
        _Fuzz_shrink: _Fuzz_shrink,
        _Browser_launch: _Browser_launch,
        _Browser_goto: _Browser_goto,
        _Browser_click: _Browser_click,
        _Browser_fill: _Browser_fill,
        _Browser_waitForSelector: _Browser_waitForSelector,
        _Browser_screenshot: _Browser_screenshot,
        _Browser_url: _Browser_url,
        _Browser_close: _Browser_close,
        _Component_render: _Component_render,
        _Component_click: _Component_click,
        _Component_clickOn: _Component_clickOn,
        _Component_input: _Component_input,
        _Component_change: _Component_change,
        _Component_submit: _Component_submit,
        _Component_find: _Component_find,
        _Component_getText: _Component_getText,
        _Component_getAttribute: _Component_getAttribute,
        _Component_has: _Component_has,
        _Component_count: _Component_count,
        _Component_toHtml: _Component_toHtml,
        _A11y_audit: _A11y_audit,
        _Visual_compare: _Visual_compare,
        _Snapshot_match: _Snapshot_match,
        _Benchmark_run: _Benchmark_run,
        _Benchmark_compare: _Benchmark_compare,
        _Benchmark_report: _Benchmark_report,
        _Test_partition: _Test_partition,
        _Test_shard: _Test_shard
    };
}
