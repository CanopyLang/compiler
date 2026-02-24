// Canopy Browser Test Runner - Playwright
const path = require('path');

// Find playwright installation
let playwright;
const playwrightPaths = [
  path.join('/home/quinten/fh/canopy/examples/audio-ffi', 'node_modules', 'playwright'),
  path.join(process.cwd(), 'node_modules', 'playwright'),
  'playwright'
];

for (const p of playwrightPaths) {
  try {
    playwright = require(p);
    break;
  } catch (e) {
    // continue
  }
}

if (!playwright) {
  console.error('Error: Playwright not found. Install with: npm install playwright');
  process.exit(1);
}

const { chromium } = playwright;

(async () => {
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext();
    const page = await context.newPage();

    // Collect console output
    let testOutput = '';
    let captureOutput = false;
    let allOutput = [];

    page.on('console', msg => {
      const text = msg.text();
      allOutput.push(text);
      if (text === 'CANOPY_TEST_RESULTS_START') {
        captureOutput = true;
      } else if (text === 'CANOPY_TEST_RESULTS_END') {
        captureOutput = false;
      } else if (captureOutput) {
        testOutput += text;
      }
    });

    page.on('pageerror', error => {
      console.error('Page error:', error.message);
    });

    // Navigate to test page
    await page.goto('file:///home/quinten/fh/canopy/examples/audio-ffi/.canopy-test-browser/test.html');

    // Wait for tests to complete (marked by data-test-complete attribute)
    try {
      await page.waitForSelector('[data-test-complete]', { timeout: 120000 });
    } catch (e) {
      // Timeout - output what we have
      console.error('Test timeout after 120000ms');
    }

    // Small delay to ensure all output is captured
    await page.waitForTimeout(500);

    // Output the captured test results
    if (testOutput) {
      console.log(testOutput);
    } else {
      // Fall back to extracting from page content
      const content = await page.textContent('pre');
      if (content) {
        console.log(content);
      } else {
        console.log('All console output:');
        allOutput.forEach(o => console.log(o));
      }
    }

  } catch (error) {
    console.error('Playwright error:', error.message);
    process.exit(1);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
})();
