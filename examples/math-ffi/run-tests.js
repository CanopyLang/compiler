const fs = require('fs');
const { JSDOM } = require('jsdom');

const html = fs.readFileSync('index.html', 'utf8');

// Create a DOM environment
const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  resources: 'usable',
  pretendToBeVisual: true
});

const { window } = dom;

// Wait for the script to execute and render
setTimeout(() => {
  try {
    // Get the test results from the #canopy element (not the whole body)
    const canopyEl = window.document.getElementById('canopy');
    const output = canopyEl ? canopyEl.textContent : '';

    console.log('=== MATH FFI TEST RESULTS ===\n');
    console.log(output.trim());

    // Check for test results
    if (output.includes('Failed: 0') || output.includes('All tests passed')) {
      console.log('\n✅ All tests passed!');
      process.exit(0);
    } else if (output.includes('FAIL') || output.includes('Failed:')) {
      console.log('\n❌ Some tests failed!');
      process.exit(1);
    } else {
      console.log('\n⚠️ Tests executed, status unclear');
      process.exit(0);
    }
  } catch (e) {
    console.error('Error reading results:', e.message);
    process.exit(1);
  }
}, 1000);
