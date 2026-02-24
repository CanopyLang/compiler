// Test wrapper for MathTest
const fs = require('fs');
const path = require('path');

// Set up global scope for Canopy IIFE
global.window = global;
global.document = {
  body: { appendChild: () => {} },
  createElement: () => ({ style: {} }),
  createTextNode: () => ({}),
  createComment: () => ({}),
  createDocumentFragment: () => ({ appendChild: () => {} }),
  head: { appendChild: () => {} }
};

// Load and execute the compiled test (IIFE assigns to global.Elm/global.Canopy)
const jsPath = path.join(__dirname, 'MathTest.js');
require(jsPath);

// Find the exported module
const Elm = global.Elm || global.Canopy;
if (!Elm) {
  console.error('No Elm/Canopy export found');
  process.exit(1);
}

const moduleName = 'MathTest';
const mod = Elm[moduleName];
if (!mod) {
  console.error('Module ' + moduleName + ' not found in exports');
  console.error('Available modules:', Object.keys(Elm));
  process.exit(1);
}

// Initialize the app
try {
  const app = mod.init({ node: null });
  // Give tests time to run and print output
  setTimeout(() => {
    process.exit(0);
  }, 2000);
} catch (e) {
  console.error('Test execution error:', e.message);
  console.error(e.stack);
  process.exit(1);
}
