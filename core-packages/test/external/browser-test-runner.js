/**
 * Canopy Browser Test Runner (async, with Playwright RPC bridge)
 *
 * Runs INSIDE the browser (not Node.js). Receives a BrowserTest value
 * (InBrowser [Test]), walks the test tree, executes each test with real
 * browser APIs, and emits NDJSON results via console.log.
 *
 * PlaywrightStep nodes send RPC requests via console.log and await
 * resolution from the Node.js Playwright launcher. Unit tests run
 * directly in the browser with real APIs.
 *
 * Output protocol: Each test emits one JSON line via console.log:
 *   {"event":"result","status":"passed","name":"...","duration":2}
 * After all tests, a summary line is emitted:
 *   {"event":"summary","passed":N,"failed":N,...,"duration":N}
 * Then window.__canopyTestsDone = true and window.__canopyExitCode = 0|1
 *
 * RPC protocol: PlaywrightStep sends:
 *   {"type":"rpc","id":N,"method":"click","args":["#btn"]}
 * Node.js resolves via page.evaluate:
 *   window.__canopyRpcResolve(id, result)  or
 *   window.__canopyRpcReject(id, errorMessage)
 *
 * @module browser-test-runner
 */

(function() {
  'use strict';

  // ── RPC Bridge ─────────────────────────────────────────────────────

  var rpcPending = {};
  var rpcNextId = 0;
  var RPC_TIMEOUT_MS = 30000;

  /** Resolve a pending RPC call (called from Node.js via page.evaluate). */
  window.__canopyRpcResolve = function(id, result) {
    if (rpcPending[id]) {
      rpcPending[id].resolve(result);
      delete rpcPending[id];
    }
  };

  /** Reject a pending RPC call (called from Node.js via page.evaluate). */
  window.__canopyRpcReject = function(id, error) {
    if (rpcPending[id]) {
      rpcPending[id].reject(new Error(error));
      delete rpcPending[id];
    }
  };

  /**
   * Send an RPC request to the Node.js Playwright launcher via console.log.
   * Returns a Promise that resolves when the launcher executes the command.
   */
  function rpcCall(method, args) {
    return new Promise(function(resolve, reject) {
      var id = rpcNextId++;
      rpcPending[id] = { resolve: resolve, reject: reject };
      var timer = setTimeout(function() {
        if (rpcPending[id]) {
          rpcPending[id].reject(new Error('RPC timeout after ' + RPC_TIMEOUT_MS + 'ms for ' + method));
          delete rpcPending[id];
        }
      }, RPC_TIMEOUT_MS);
      rpcPending[id].timer = timer;
      var origResolve = rpcPending[id].resolve;
      var origReject = rpcPending[id].reject;
      rpcPending[id].resolve = function(v) { clearTimeout(timer); origResolve(v); };
      rpcPending[id].reject = function(e) { clearTimeout(timer); origReject(e); };
      console.log(JSON.stringify({ type: 'rpc', id: id, method: method, args: args }));
    });
  }

  // ── Elm List Conversion ────────────────────────────────────────────

  /**
   * Convert an Elm-style linked list to a JavaScript array.
   * Elm lists in dev mode: { $: '::', a: head, b: tail } / { $: '[]' }
   */
  function listToArray(elmList) {
    var arr = [];
    var current = elmList;
    while (current && current.$ === '::') {
      arr.push(current.a);
      current = current.b;
    }
    return arr;
  }

  // ── Failure Formatting ─────────────────────────────────────────────

  /**
   * Format a failure reason from an Expect.Fail value.
   */
  function formatFailure(result) {
    if (!result || !result.a) return 'Unknown failure';

    var reason = result.a;
    switch (reason.$) {
      case 'StringEqual':
        return 'Expected: ' + reason.a + '\nActual: ' + reason.b;
      case 'IntEqual':
        return 'Expected: ' + reason.a + '\nActual: ' + reason.b;
      case 'FloatEqual':
        return 'Expected: ' + reason.a + '\nActual: ' + reason.b;
      case 'BoolEqual':
        return 'Expected: ' + reason.a + '\nActual: ' + reason.b;
      case 'ListDiff':
        return 'List diff at index ' + reason.a;
      case 'Custom':
        return String(reason.a);
      default:
        if (typeof reason === 'string') return reason;
        return JSON.stringify(reason);
    }
  }

  // ── Playwright Action Dispatch ─────────────────────────────────────

  /**
   * Dispatch a PlaywrightAction to the Node.js RPC bridge.
   * Each action type maps to a Playwright method call.
   */
  function dispatchPlaywrightAction(action) {
    switch (action.$) {
      case 'Visit':       return rpcCall('goto', [action.a]);
      case 'Click':       return rpcCall('click', [action.a]);
      case 'Fill':        return rpcCall('fill', [action.a, action.b]);
      case 'Check':       return rpcCall('check', [action.a]);
      case 'SeeText':     return rpcCall('seeText', [action.a]);
      case 'SeeElement':  return rpcCall('seeElement', [action.a]);
      case 'DontSee':     return rpcCall('dontSee', [action.a]);
      case 'DontSeeElement': return rpcCall('dontSeeElement', [action.a]);
      case 'WaitFor':     return rpcCall('waitForSelector', [action.a]);
      case 'Screenshot':  return rpcCall('screenshot', [action.a]);
      default:
        return Promise.reject(new Error('Unknown PlaywrightAction: ' + action.$));
    }
  }

  /**
   * Describe a PlaywrightAction as a human-readable string.
   */
  function describeAction(action, path) {
    var desc;
    switch (action.$) {
      case 'Visit':       desc = 'visit ' + action.a; break;
      case 'Click':       desc = 'click ' + action.a; break;
      case 'Fill':        desc = 'fill ' + action.a; break;
      case 'Check':       desc = 'check ' + action.a; break;
      case 'SeeText':     desc = 'see text "' + action.a + '"'; break;
      case 'SeeElement':  desc = 'see element ' + action.a; break;
      case 'DontSee':     desc = 'don\'t see "' + action.a + '"'; break;
      case 'DontSeeElement': desc = 'don\'t see element ' + action.a; break;
      case 'WaitFor':     desc = 'wait for ' + action.a; break;
      case 'Screenshot':  desc = 'screenshot ' + action.a; break;
      default:            desc = 'unknown action'; break;
    }
    return path.length > 0 ? path.join(' > ') + ' > ' + desc : desc;
  }

  // ── Test Runner ────────────────────────────────────────────────────

  /**
   * Run a single test node and collect results (async).
   *
   * @param {Object} test - Canopy Test value
   * @param {string[]} path - Ancestor group names for qualified test name
   * @param {Object} report - Mutable report accumulator
   */
  async function runTest(test, path, report) {
    if (!test) return;

    switch (test.$) {
      case 'UnitTest': {
        var testName = path.concat([test.a]).join(' > ');
        var testStart = performance.now();
        try {
          var result = test.b(0);
          var duration = performance.now() - testStart;

          if (result.$ === 'Pass') {
            report.passed++;
            emitResult('passed', testName, duration, null);
          } else {
            report.failed++;
            emitResult('failed', testName, duration, formatFailure(result));
          }
        } catch (e) {
          var dur = performance.now() - testStart;
          report.failed++;
          emitResult('failed', testName, dur, 'Exception: ' + (e.message || String(e)));
        }
        report.total++;
        break;
      }

      case 'TestGroup': {
        var groupPath = path.concat([test.a]);
        var subTests = listToArray(test.b);
        for (var i = 0; i < subTests.length; i++) {
          await runTest(subTests[i], groupPath, report);
        }
        break;
      }

      case 'PlaywrightStep': {
        var action = test.a;
        var stepStart = performance.now();
        try {
          await dispatchPlaywrightAction(action);
          report.passed++;
          report.total++;
          emitResult('passed', describeAction(action, path), performance.now() - stepStart, null);
        } catch (e) {
          report.failed++;
          report.total++;
          emitResult('failed', describeAction(action, path), performance.now() - stepStart, e.message);
        }
        break;
      }

      case 'Skip': {
        var skipName = getTestName(test.a, path);
        report.skipped++;
        report.total++;
        emitResult('skipped', skipName, 0, null);
        break;
      }

      case 'Todo': {
        var todoName = path.concat([test.a]).join(' > ');
        report.todo++;
        report.total++;
        emitResult('todo', todoName, 0, null);
        break;
      }

      case 'Only': {
        await runTest(test.a, path, report);
        break;
      }

      case 'FuzzTest': {
        var fuzzName = path.concat([test.a]).join(' > ');
        report.skipped++;
        report.total++;
        emitResult('skipped', fuzzName, 0, 'Fuzz tests not supported in browser');
        break;
      }

      case 'AsyncTest': {
        var asyncName = path.concat([test.a]).join(' > ');
        report.skipped++;
        report.total++;
        emitResult('skipped', asyncName, 0, 'AsyncTest not supported in browser execution mode');
        break;
      }

      default: {
        report.failed++;
        report.total++;
        emitResult('failed', path.join(' > ') || 'unknown', 0, 'Unknown test type: ' + test.$);
        break;
      }
    }
  }

  /**
   * Get the name of a test node for reporting.
   */
  function getTestName(test, path) {
    if (!test) return path.join(' > ') || 'unknown';
    switch (test.$) {
      case 'UnitTest':
      case 'TestGroup':
      case 'Todo':
      case 'FuzzTest':
      case 'AsyncTest':
        return path.concat([test.a]).join(' > ');
      case 'PlaywrightStep':
        return describeAction(test.a, path);
      case 'Skip':
        return getTestName(test.a, path);
      case 'Only':
        return getTestName(test.a, path);
      default:
        return path.join(' > ') || 'unknown';
    }
  }

  // ── NDJSON Output ──────────────────────────────────────────────────

  /**
   * Emit a single test result as NDJSON via console.log.
   */
  function emitResult(status, name, duration, message) {
    var obj = {
      event: 'result',
      status: status,
      name: name,
      duration: Math.round(duration)
    };
    if (message) {
      obj.message = message;
    }
    console.log(JSON.stringify(obj));
  }

  /**
   * Emit the final summary as NDJSON via console.log.
   */
  function emitSummary(report) {
    console.log(JSON.stringify({
      event: 'summary',
      passed: report.passed,
      failed: report.failed,
      skipped: report.skipped,
      todo: report.todo,
      total: report.total,
      duration: Math.round(report.duration)
    }));
  }

  // ── Entry Point ────────────────────────────────────────────────────

  /**
   * Main entry point (async). Receives the _browserTestMain value,
   * unwraps InBrowser, and runs all tests.
   *
   * @param {Object} browserTestMain - The InBrowser value: { $: 'InBrowser', a: elmList }
   */
  async function run(browserTestMain) {
    var startTime = performance.now();
    var report = {
      passed: 0,
      failed: 0,
      skipped: 0,
      todo: 0,
      total: 0,
      duration: 0
    };

    try {
      var testList = browserTestMain.a;
      var tests = listToArray(testList);

      for (var i = 0; i < tests.length; i++) {
        await runTest(tests[i], [], report);
      }
    } catch (e) {
      report.failed++;
      report.total++;
      emitResult('failed', 'BrowserTest runner', 0, 'Runner error: ' + (e.message || String(e)));
    }

    report.duration = performance.now() - startTime;
    emitSummary(report);

    window.__canopyTestsDone = true;
    window.__canopyExitCode = report.failed > 0 ? 1 : 0;
  }

  window.__canopyBrowserTestRunner = { run: run };
})();
