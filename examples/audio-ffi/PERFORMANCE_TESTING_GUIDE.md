# Performance Testing Guide - Canopy Audio FFI

## Overview

Comprehensive performance and resource usage testing suite for the Canopy Audio FFI application using Playwright automation.

## Test Scenarios

### 1. Page Load Performance
- Measures page load time
- Tracks time to interactive
- Records First Contentful Paint (FCP)
- Monitors DOM Content Loaded event

### 2. JavaScript Bundle Size Analysis
- Analyzes total JavaScript size
- Counts network requests
- Identifies large bundles
- Measures HTML document size

### 3. Memory Usage - Baseline
- Establishes baseline memory consumption
- Measures JS heap usage
- Records heap limits

### 4. Memory Usage - Audio Playing
- Compares memory during audio playback
- Detects memory increases
- Identifies potential leaks
- Calculates percentage change

### 5. CPU Usage Monitoring
- Monitors CPU during idle state
- Tracks CPU during audio playback
- Detects long tasks (>50ms)
- Calculates total blocking time

### 6. Stress Testing
- Performs 20 rapid operations
- Clicks buttons rapidly
- Changes filters repeatedly
- Monitors for errors and crashes
- Tracks memory trends

### 7. Long-Running Stability Test
- Runs for 5 minutes continuously
- Samples memory every second
- Detects memory leak patterns
- Analyzes stability trends

## Installation

```bash
# Install dependencies
npm install

# Install Playwright browsers
npx playwright install chromium
```

## Running Tests

### Full Test Suite (Recommended)
```bash
npm run test:performance
```

This runs all 7 test scenarios and generates a comprehensive report.

### Quick Test (Development)
For faster iteration during development:
```bash
# Modify CONFIG.longRunningMinutes to 1 in performance-tests.js
node performance-tests.js
```

## Output

Tests generate two report formats:

### 1. JSON Report
- Location: `performance-results/performance-report-[timestamp].json`
- Contains all raw metrics and data
- Suitable for programmatic analysis
- Includes all sample points

### 2. Markdown Report
- Location: `performance-results/performance-report-[timestamp].md`
- Human-readable summary
- Key metrics and assessments
- Actionable recommendations

## Console Output

Real-time progress is shown in the console:

```
🚀 Starting Comprehensive Performance Tests
======================================================================

📊 Test 1: Page Load Performance
  ✓ Total Load Time: 245ms
  ✓ DOM Content Loaded: 12.50ms
  ✓ First Contentful Paint: 156.30ms
  ✓ Time to Interactive: 189.20ms

📦 Test 2: JavaScript Bundle Size Analysis
  ✓ HTML Size: 8.1 KB
  ✓ Total JavaScript Size: 39 KB
  ✓ Number of Requests: 2
  JavaScript Files:
    - audio.js: 39 KB

💾 Test 3: Memory Usage - Baseline
  Waiting 5s for baseline measurement...
  ✓ Used JS Heap: 4.52 MB
  ✓ Total JS Heap: 8.00 MB
  ✓ Heap Limit: 2.10 GB

... [additional test output]

======================================================================
📋 PERFORMANCE TEST SUMMARY
======================================================================

🎯 Key Metrics:
  Page Load Time: 245ms
  First Contentful Paint: 156.30ms
  Time to Interactive: 189.20ms
  JavaScript Bundle: 39 KB
  Baseline Memory: 4.52 MB

📊 Assessment:
  Performance: EXCELLENT
  Stability: EXCELLENT
  Memory Leaks: NONE DETECTED
  Stress Test Errors: 0

💡 Recommendations:
  ✅ All metrics are within acceptable ranges.

======================================================================
```

## Understanding Results

### Performance Assessment
- **EXCELLENT**: Load time < 2s, FCP < 1s
- **GOOD**: Load time < 5s, FCP < 2s
- **NEEDS IMPROVEMENT**: Above thresholds

### Stability Assessment
- **EXCELLENT**: 0 errors during stress test
- **GOOD**: < 5 errors during stress test
- **POOR**: ≥ 5 errors during stress test

### Memory Leak Detection
- **NONE DETECTED**: Stable or decreasing memory over time
- **MINIMAL**: < 20% memory increase over 5 minutes
- **POTENTIAL LEAK**: > 20% memory increase over 5 minutes

## Customization

Edit `performance-tests.js` to adjust test parameters:

```javascript
const CONFIG = {
  url: 'file://' + path.resolve(__dirname, 'test-mediastream.html'),
  outputDir: path.resolve(__dirname, 'performance-results'),
  viewport: { width: 1280, height: 720 },
  stressTestIterations: 20,        // Adjust stress test duration
  longRunningMinutes: 5,           // Adjust stability test duration
  samplingIntervalMs: 1000,        // Memory sampling frequency
};
```

## Interpreting Metrics

### Page Load Metrics
- **DOM Content Loaded**: HTML parsed, DOMContentLoaded event fired
- **Load Complete**: All resources loaded
- **First Paint**: Browser first renders pixels
- **First Contentful Paint**: First text/image rendered
- **Time to Interactive**: Page becomes fully interactive

### Memory Metrics
- **usedJSHeapSize**: Currently allocated heap memory
- **totalJSHeapSize**: Total heap size (can grow)
- **jsHeapSizeLimit**: Maximum heap size

### CPU Metrics
- **Long Tasks**: Tasks taking > 50ms (block main thread)
- **Total Blocking Time**: Sum of blocking time from all long tasks

## Troubleshooting

### Microphone Permission Issues
Tests use `--use-fake-ui-for-media-stream` to auto-grant permissions. If issues occur:
- Ensure Chromium is installed: `npx playwright install chromium`
- Check browser console for permission errors
- Verify the test HTML file exists

### Memory API Not Available
If you see "Memory API not available":
- Tests automatically use `--enable-precise-memory-info` flag
- Some metrics may not be available in all environments
- Results will note when metrics are unavailable

### Test Timeout
For slow machines, increase timeouts:
```javascript
await page.goto(CONFIG.url, {
  waitUntil: 'networkidle',
  timeout: 60000  // Increase from default 30s
});
```

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Performance Tests

on: [push, pull_request]

jobs:
  performance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - run: npm install
      - run: npx playwright install chromium
      - run: npm run test:performance
      - uses: actions/upload-artifact@v3
        with:
          name: performance-reports
          path: examples/audio-ffi/performance-results/
```

## Performance Budget

Recommended thresholds:

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| Page Load | < 1s | < 3s | > 5s |
| FCP | < 500ms | < 1.5s | > 2.5s |
| TTI | < 1.5s | < 4s | > 6s |
| Bundle Size | < 100KB | < 300KB | > 500KB |
| Memory Baseline | < 10MB | < 50MB | > 100MB |
| Memory Increase | < 10% | < 30% | > 50% |
| Long Tasks | 0 | < 5 | > 10 |

## Best Practices

1. **Run regularly**: Execute tests on every commit or PR
2. **Compare results**: Track metrics over time to spot regressions
3. **Test on real devices**: Supplement with manual testing on actual hardware
4. **Monitor production**: Use Real User Monitoring (RUM) for production metrics
5. **Set budgets**: Define and enforce performance budgets in CI

## Advanced Usage

### Custom Test Scenarios
Add custom tests by creating new functions:

```javascript
async function testCustomScenario(page) {
  console.log('\n🔬 Test: Custom Scenario');

  // Your test logic here
  await page.evaluate(() => {
    // Interact with page
  });

  // Measure metrics
  const memory = await getMemoryMetrics(page);

  // Store results
  results.scenarios.customTest = {
    // Your results
  };
}
```

### Profiling with Chrome DevTools
For deeper analysis, enable tracing:

```javascript
await page.tracing.start({ screenshots: true, snapshots: true });
// Run tests
await page.tracing.stop({ path: 'trace.json' });
```

Load `trace.json` in Chrome DevTools (chrome://tracing) for detailed analysis.

## References

- [Playwright Documentation](https://playwright.dev/)
- [Web Performance API](https://developer.mozilla.org/en-US/docs/Web/API/Performance_API)
- [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/)
- [Web Audio API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API)

## Support

For issues or questions:
1. Check console output for error messages
2. Review the generated JSON report for detailed metrics
3. Consult Playwright documentation for browser automation issues
4. Check Canopy Audio FFI documentation for application-specific questions

---

**Last Updated:** 2025-10-22
**Version:** 1.0.0
