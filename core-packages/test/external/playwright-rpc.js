/**
 * Canopy Playwright RPC Dispatcher
 *
 * Runs in Node.js alongside the Playwright launcher. Listens for
 * console.log messages from the browser page, intercepts RPC requests
 * from the browser-test-runner.js, executes Playwright commands on the
 * test iframe, and resolves/rejects the browser-side promises.
 *
 * NDJSON result events are forwarded to stdout for the Haskell test
 * runner to consume.
 *
 * RPC protocol:
 *   Browser sends:  {"type":"rpc","id":N,"method":"click","args":["#btn"]}
 *   Node resolves:  page.evaluate(() => window.__canopyRpcResolve(id, result))
 *   Node rejects:   page.evaluate(() => window.__canopyRpcReject(id, error))
 *
 * @module playwright-rpc
 */

'use strict';

/**
 * Set up the RPC bridge on a Playwright page.
 *
 * @param {import('playwright').Page} page - The Playwright page instance
 * @param {function(string): void} forwardNdjson - Callback to forward NDJSON lines to stdout
 */
function setup(page, forwardNdjson) {
  page.on('console', async function(msg) {
    if (msg.type() !== 'log') return;

    var text;
    try {
      text = msg.text();
    } catch (e) {
      return;
    }

    var parsed;
    try {
      parsed = JSON.parse(text);
    } catch (e) {
      return; // not JSON, ignore
    }

    if (parsed.type === 'rpc') {
      try {
        var result = await executeCommand(page, parsed.method, parsed.args);
        await page.evaluate(
          function(data) { window.__canopyRpcResolve(data[0], data[1]); },
          [parsed.id, result]
        );
      } catch (e) {
        await page.evaluate(
          function(data) { window.__canopyRpcReject(data[0], data[1]); },
          [parsed.id, e.message || String(e)]
        );
      }
    } else if (parsed.event) {
      // Normal NDJSON test result/summary — forward to stdout
      forwardNdjson(text);
    }
  });
}

/**
 * Execute a Playwright command targeting the test iframe.
 *
 * The iframe with id="test-target" is the target for navigation
 * and interaction commands. This keeps the parent frame (which hosts
 * the test runner and RPC bridge) stable across navigations.
 *
 * @param {import('playwright').Page} page - The Playwright page
 * @param {string} method - The RPC method name
 * @param {Array} args - Arguments for the method
 * @returns {Promise<*>} Result of the command
 */
async function executeCommand(page, method, args) {
  switch (method) {
    case 'goto': {
      var iframe = page.locator('#test-target');
      var contentFrame = await iframe.contentFrame();
      if (!contentFrame) throw new Error('Could not access iframe content frame');
      await contentFrame.goto(args[0], { waitUntil: 'networkidle' });
      return null;
    }

    case 'click': {
      var frame = await getTestFrame(page);
      await frame.locator(args[0]).click();
      return null;
    }

    case 'fill': {
      var frame = await getTestFrame(page);
      await frame.locator(args[0]).fill(args[1]);
      return null;
    }

    case 'check': {
      var frame = await getTestFrame(page);
      await frame.locator(args[0]).check();
      return null;
    }

    case 'seeText': {
      var frame = await getTestFrame(page);
      var bodyText = await frame.locator('body').innerText();
      if (!bodyText.includes(args[0])) {
        throw new Error('Text not found on page: "' + args[0] + '"');
      }
      return null;
    }

    case 'seeElement': {
      var frame = await getTestFrame(page);
      var count = await frame.locator(args[0]).count();
      if (count === 0) {
        throw new Error('Element not found: ' + args[0]);
      }
      return null;
    }

    case 'dontSee': {
      var frame = await getTestFrame(page);
      var bodyText = await frame.locator('body').innerText();
      if (bodyText.includes(args[0])) {
        throw new Error('Text should not be visible but was found: "' + args[0] + '"');
      }
      return null;
    }

    case 'dontSeeElement': {
      var frame = await getTestFrame(page);
      var count = await frame.locator(args[0]).count();
      if (count > 0) {
        throw new Error('Element should not exist but was found: ' + args[0]);
      }
      return null;
    }

    case 'waitForSelector': {
      var frame = await getTestFrame(page);
      await frame.locator(args[0]).waitFor({ state: 'visible', timeout: 10000 });
      return null;
    }

    case 'screenshot': {
      var name = args[0] || 'screenshot';
      await page.screenshot({
        path: 'test-output/screenshots/' + name + '.png',
        fullPage: true
      });
      return name;
    }

    default:
      throw new Error('Unknown RPC method: ' + method);
  }
}

/**
 * Get the content frame of the test iframe.
 * Falls back to the main page if no iframe exists (for tests that
 * don't use navigation steps).
 */
async function getTestFrame(page) {
  var iframe = page.locator('#test-target');
  var count = await iframe.count();
  if (count > 0) {
    var contentFrame = await iframe.contentFrame();
    if (contentFrame) return contentFrame;
  }
  return page;
}

module.exports = { setup: setup };
