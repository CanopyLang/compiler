/**
 * Comprehensive Performance and Resource Usage Testing Suite
 * For Canopy Audio FFI Application
 *
 * Tests:
 * 1. Page Load Performance
 * 2. JavaScript Bundle Size Analysis
 * 3. Memory Usage - Baseline
 * 4. Memory Usage - Audio Playing
 * 5. CPU Usage Monitoring
 * 6. Stress Testing
 * 7. Long-Running Stability
 */

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

// Configuration
const CONFIG = {
  url: 'file://' + path.resolve(__dirname, 'test-mediastream.html'),
  outputDir: path.resolve(__dirname, 'performance-results'),
  viewport: { width: 1280, height: 720 },
  stressTestIterations: 20,
  longRunningMinutes: 5,
  samplingIntervalMs: 1000,
};

// Test Results Storage
const results = {
  timestamp: new Date().toISOString(),
  testUrl: CONFIG.url,
  scenarios: {},
  summary: {},
};

/**
 * Utility: Format bytes to human-readable
 */
function formatBytes(bytes) {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

/**
 * Utility: Calculate statistics
 */
function calculateStats(values) {
  if (values.length === 0) return null;

  const sorted = [...values].sort((a, b) => a - b);
  const sum = values.reduce((a, b) => a + b, 0);

  return {
    min: sorted[0],
    max: sorted[sorted.length - 1],
    avg: sum / values.length,
    median: sorted[Math.floor(sorted.length / 2)],
    p95: sorted[Math.floor(sorted.length * 0.95)],
    p99: sorted[Math.floor(sorted.length * 0.99)],
  };
}

/**
 * Utility: Wait with progress
 */
async function waitWithProgress(seconds, label) {
  console.log(`  Waiting ${seconds}s for ${label}...`);
  for (let i = 0; i < seconds; i++) {
    await new Promise(resolve => setTimeout(resolve, 1000));
    process.stdout.write(`  Progress: ${i + 1}/${seconds}s\r`);
  }
  console.log(`  ✓ Completed ${label}                    `);
}

/**
 * Utility: Get memory metrics from browser
 */
async function getMemoryMetrics(page) {
  return await page.evaluate(() => {
    if (performance.memory) {
      return {
        usedJSHeapSize: performance.memory.usedJSHeapSize,
        totalJSHeapSize: performance.memory.totalJSHeapSize,
        jsHeapSizeLimit: performance.memory.jsHeapSizeLimit,
      };
    }
    return null;
  });
}

/**
 * Utility: Monitor CPU usage via Performance API
 */
async function monitorCPU(page, durationSeconds, label) {
  console.log(`  Monitoring CPU for ${durationSeconds}s during: ${label}`);

  const samples = [];
  const startTime = Date.now();

  while ((Date.now() - startTime) < durationSeconds * 1000) {
    const cpuMetrics = await page.evaluate(() => {
      const entries = performance.getEntriesByType('measure');
      const lastEntry = entries[entries.length - 1];
      return {
        timestamp: Date.now(),
        duration: lastEntry ? lastEntry.duration : 0,
      };
    });

    samples.push(cpuMetrics);
    await new Promise(resolve => setTimeout(resolve, 100));
  }

  return samples;
}

/**
 * Test Scenario 1: Page Load Performance
 */
async function testPageLoadPerformance(page) {
  console.log('\n📊 Test 1: Page Load Performance');

  const startTime = Date.now();

  // Navigate and wait for load
  await page.goto(CONFIG.url, { waitUntil: 'networkidle' });

  const loadTime = Date.now() - startTime;

  // Get performance metrics
  const metrics = await page.evaluate(() => {
    const perf = performance.getEntriesByType('navigation')[0];
    const paint = performance.getEntriesByType('paint');

    return {
      navigationStart: perf.startTime,
      domContentLoaded: perf.domContentLoadedEventEnd - perf.domContentLoadedEventStart,
      loadComplete: perf.loadEventEnd - perf.loadEventStart,
      domInteractive: perf.domInteractive - perf.fetchStart,
      firstPaint: paint.find(p => p.name === 'first-paint')?.startTime || 0,
      firstContentfulPaint: paint.find(p => p.name === 'first-contentful-paint')?.startTime || 0,
      transferSize: perf.transferSize,
      encodedBodySize: perf.encodedBodySize,
      decodedBodySize: perf.decodedBodySize,
    };
  });

  results.scenarios.pageLoad = {
    totalLoadTime: loadTime,
    metrics,
  };

  console.log(`  ✓ Total Load Time: ${loadTime}ms`);
  console.log(`  ✓ DOM Content Loaded: ${metrics.domContentLoaded.toFixed(2)}ms`);
  console.log(`  ✓ First Contentful Paint: ${metrics.firstContentfulPaint.toFixed(2)}ms`);
  console.log(`  ✓ Time to Interactive: ${metrics.domInteractive.toFixed(2)}ms`);
}

/**
 * Test Scenario 2: JavaScript Bundle Size
 */
async function testBundleSize(page) {
  console.log('\n📦 Test 2: JavaScript Bundle Size Analysis');

  // Monitor network requests
  const resources = [];

  page.on('response', async (response) => {
    const url = response.url();
    const type = response.request().resourceType();

    if (type === 'script' || type === 'document') {
      try {
        const size = (await response.body()).length;
        resources.push({
          url: url.split('/').pop(),
          type,
          size,
          status: response.status(),
        });
      } catch (e) {
        // Ignore errors for resources we can't access
      }
    }
  });

  // Reload to capture all resources
  await page.reload({ waitUntil: 'networkidle' });

  // Calculate totals
  const jsResources = resources.filter(r => r.type === 'script');
  const totalJsSize = jsResources.reduce((sum, r) => sum + r.size, 0);
  const htmlSize = resources.filter(r => r.type === 'document')[0]?.size || 0;

  results.scenarios.bundleSize = {
    resources: jsResources,
    totalJavaScriptSize: totalJsSize,
    htmlSize,
    requestCount: resources.length,
  };

  console.log(`  ✓ HTML Size: ${formatBytes(htmlSize)}`);
  console.log(`  ✓ Total JavaScript Size: ${formatBytes(totalJsSize)}`);
  console.log(`  ✓ Number of Requests: ${resources.length}`);
  console.log(`  JavaScript Files:`);
  jsResources.forEach(r => {
    console.log(`    - ${r.url}: ${formatBytes(r.size)}`);
  });
}

/**
 * Test Scenario 3: Memory Usage - Baseline
 */
async function testBaselineMemory(page) {
  console.log('\n💾 Test 3: Memory Usage - Baseline');

  await waitWithProgress(5, 'baseline measurement');

  const memory = await getMemoryMetrics(page);

  results.scenarios.baselineMemory = memory;

  if (memory) {
    console.log(`  ✓ Used JS Heap: ${formatBytes(memory.usedJSHeapSize)}`);
    console.log(`  ✓ Total JS Heap: ${formatBytes(memory.totalJSHeapSize)}`);
    console.log(`  ✓ Heap Limit: ${formatBytes(memory.jsHeapSizeLimit)}`);
  } else {
    console.log(`  ⚠ Memory API not available (need --enable-precise-memory-info)`);
  }

  return memory;
}

/**
 * Test Scenario 4: Memory Usage - Audio Playing
 */
async function testAudioMemory(page, baselineMemory) {
  console.log('\n🎵 Test 4: Memory Usage - Audio Playing');

  try {
    // Request microphone (will need user interaction in real browser)
    console.log('  Note: This test requires microphone permission');
    console.log('  Measuring memory with audio simulation...');

    // Simulate audio activity
    await page.evaluate(() => {
      // Click the full pipeline test button
      const button = document.querySelector('button[onclick="testFullPipeline()"]');
      if (button) button.click();
    });

    await waitWithProgress(30, 'audio playing');

    const memory = await getMemoryMetrics(page);

    if (memory && baselineMemory) {
      const increase = memory.usedJSHeapSize - baselineMemory.usedJSHeapSize;
      const percentIncrease = (increase / baselineMemory.usedJSHeapSize * 100).toFixed(2);

      results.scenarios.audioMemory = {
        memory,
        baselineComparison: {
          increase,
          percentIncrease: parseFloat(percentIncrease),
        },
      };

      console.log(`  ✓ Used JS Heap: ${formatBytes(memory.usedJSHeapSize)}`);
      console.log(`  ✓ Increase from Baseline: ${formatBytes(increase)} (${percentIncrease}%)`);

      if (increase < 0) {
        console.log(`  ✓ Memory decreased (garbage collection occurred)`);
      } else if (percentIncrease < 10) {
        console.log(`  ✓ Low memory increase - Good efficiency`);
      } else if (percentIncrease < 50) {
        console.log(`  ⚠ Moderate memory increase`);
      } else {
        console.log(`  ⚠ High memory increase - potential leak`);
      }
    }
    return memory;
  } catch (error) {
    console.log(`  ⚠ Error during audio memory test: ${error.message}`);
    results.scenarios.audioMemory = { error: error.message };
    return null;
  }
}

/**
 * Test Scenario 5: CPU Usage Monitoring
 */
async function testCPUUsage(page) {
  console.log('\n⚡ Test 5: CPU Usage Monitoring');

  const scenarios = [
    { name: 'Idle (no audio)', duration: 5, setup: null },
    {
      name: 'Audio playing',
      duration: 5,
      setup: async () => {
        await page.evaluate(() => {
          const btn = document.querySelector('button[onclick="testFullPipeline()"]');
          if (btn) btn.click();
        });
      }
    },
  ];

  const cpuResults = {};

  for (const scenario of scenarios) {
    console.log(`\n  Testing: ${scenario.name}`);

    if (scenario.setup) {
      await scenario.setup();
      await new Promise(resolve => setTimeout(resolve, 1000));
    }

    // Measure long tasks via Performance Observer
    const longTasks = await page.evaluate(async (duration) => {
      return new Promise((resolve) => {
        const tasks = [];

        const observer = new PerformanceObserver((list) => {
          for (const entry of list.getEntries()) {
            tasks.push({
              name: entry.name,
              duration: entry.duration,
              startTime: entry.startTime,
            });
          }
        });

        // Observe long tasks (if supported)
        try {
          observer.observe({ entryTypes: ['longtask'] });
        } catch (e) {
          console.log('Long task API not available');
        }

        setTimeout(() => {
          observer.disconnect();
          resolve(tasks);
        }, duration * 1000);
      });
    }, scenario.duration);

    await waitWithProgress(scenario.duration, scenario.name);

    cpuResults[scenario.name] = {
      longTasks,
      taskCount: longTasks.length,
      totalBlockingTime: longTasks.reduce((sum, t) => sum + Math.max(0, t.duration - 50), 0),
    };

    console.log(`  ✓ Long Tasks Detected: ${longTasks.length}`);
    if (longTasks.length > 0) {
      const avgDuration = longTasks.reduce((sum, t) => sum + t.duration, 0) / longTasks.length;
      console.log(`  ✓ Average Task Duration: ${avgDuration.toFixed(2)}ms`);
    }
  }

  results.scenarios.cpuUsage = cpuResults;
}

/**
 * Test Scenario 6: Stress Test
 */
async function testStress(page) {
  console.log('\n🔥 Test 6: Stress Testing');

  const iterations = CONFIG.stressTestIterations;
  const memorySnapshots = [];
  const errors = [];

  console.log(`  Running ${iterations} rapid operations...`);

  const startMemory = await getMemoryMetrics(page);

  for (let i = 0; i < iterations; i++) {
    try {
      // Rapid button clicking
      await page.evaluate(() => {
        const buttons = document.querySelectorAll('button');
        buttons.forEach((btn, idx) => {
          if (idx % 2 === 0) btn.click();
        });
      });

      // Take periodic memory snapshots
      if (i % 5 === 0) {
        const memory = await getMemoryMetrics(page);
        if (memory) {
          memorySnapshots.push({
            iteration: i,
            usedJSHeapSize: memory.usedJSHeapSize,
          });
        }
      }

      // Check for JavaScript errors
      page.on('pageerror', (error) => {
        errors.push({
          iteration: i,
          message: error.message,
        });
      });

      await new Promise(resolve => setTimeout(resolve, 50));

      if ((i + 1) % 5 === 0) {
        process.stdout.write(`  Progress: ${i + 1}/${iterations}\r`);
      }
    } catch (error) {
      errors.push({
        iteration: i,
        message: error.message,
      });
    }
  }

  console.log(`  ✓ Completed ${iterations} iterations                    `);

  const endMemory = await getMemoryMetrics(page);

  results.scenarios.stressTest = {
    iterations,
    errors,
    memorySnapshots,
    startMemory,
    endMemory,
  };

  if (startMemory && endMemory) {
    const increase = endMemory.usedJSHeapSize - startMemory.usedJSHeapSize;
    console.log(`  ✓ Memory Change: ${formatBytes(increase)}`);
  }

  console.log(`  ✓ Errors Detected: ${errors.length}`);
  console.log(`  ✓ Memory Snapshots: ${memorySnapshots.length}`);

  // Analyze memory trend
  if (memorySnapshots.length > 2) {
    const firstHalf = memorySnapshots.slice(0, Math.floor(memorySnapshots.length / 2));
    const secondHalf = memorySnapshots.slice(Math.floor(memorySnapshots.length / 2));

    const firstAvg = firstHalf.reduce((sum, s) => sum + s.usedJSHeapSize, 0) / firstHalf.length;
    const secondAvg = secondHalf.reduce((sum, s) => sum + s.usedJSHeapSize, 0) / secondHalf.length;

    if (secondAvg > firstAvg * 1.2) {
      console.log(`  ⚠ Memory trend: INCREASING (potential leak)`);
    } else if (secondAvg < firstAvg * 0.8) {
      console.log(`  ✓ Memory trend: DECREASING (good GC)`);
    } else {
      console.log(`  ✓ Memory trend: STABLE`);
    }
  }
}

/**
 * Test Scenario 7: Long-Running Stability
 */
async function testLongRunning(page) {
  console.log('\n⏱️  Test 7: Long-Running Stability Test');

  const durationSeconds = CONFIG.longRunningMinutes * 60;
  const samplingInterval = CONFIG.samplingIntervalMs;
  const samples = [];

  console.log(`  Running for ${CONFIG.longRunningMinutes} minutes...`);
  console.log(`  Sampling every ${samplingInterval}ms`);

  // Start audio simulation
  await page.evaluate(() => {
    const btn = document.querySelector('button[onclick="testFullPipeline()"]');
    if (btn) btn.click();
  });

  const startTime = Date.now();
  const endTime = startTime + (durationSeconds * 1000);

  while (Date.now() < endTime) {
    const elapsed = Date.now() - startTime;
    const memory = await getMemoryMetrics(page);

    if (memory) {
      samples.push({
        timestamp: elapsed,
        usedJSHeapSize: memory.usedJSHeapSize,
        totalJSHeapSize: memory.totalJSHeapSize,
      });
    }

    // Progress indicator
    const percentComplete = (elapsed / (durationSeconds * 1000) * 100).toFixed(1);
    const minutesElapsed = (elapsed / 60000).toFixed(1);
    process.stdout.write(`  Progress: ${percentComplete}% (${minutesElapsed}/${CONFIG.longRunningMinutes} min)\r`);

    await new Promise(resolve => setTimeout(resolve, samplingInterval));
  }

  console.log(`  ✓ Completed ${CONFIG.longRunningMinutes} minute test                              `);

  // Analyze results
  const memoryValues = samples.map(s => s.usedJSHeapSize);
  const stats = calculateStats(memoryValues);

  // Detect trend
  const firstQuarter = samples.slice(0, Math.floor(samples.length / 4));
  const lastQuarter = samples.slice(-Math.floor(samples.length / 4));

  const firstAvg = firstQuarter.reduce((sum, s) => sum + s.usedJSHeapSize, 0) / firstQuarter.length;
  const lastAvg = lastQuarter.reduce((sum, s) => sum + s.usedJSHeapSize, 0) / lastQuarter.length;

  const trend = lastAvg > firstAvg ? 'INCREASING' : lastAvg < firstAvg ? 'DECREASING' : 'STABLE';
  const trendPercent = ((lastAvg - firstAvg) / firstAvg * 100).toFixed(2);

  results.scenarios.longRunning = {
    durationMinutes: CONFIG.longRunningMinutes,
    sampleCount: samples.length,
    memoryStats: stats,
    trend: {
      direction: trend,
      percentChange: parseFloat(trendPercent),
      firstAvg,
      lastAvg,
    },
    samples,
  };

  console.log(`\n  Memory Statistics:`);
  console.log(`    Min: ${formatBytes(stats.min)}`);
  console.log(`    Max: ${formatBytes(stats.max)}`);
  console.log(`    Avg: ${formatBytes(stats.avg)}`);
  console.log(`    Median: ${formatBytes(stats.median)}`);

  console.log(`\n  Memory Trend: ${trend} (${trendPercent}%)`);

  if (trend === 'INCREASING' && Math.abs(parseFloat(trendPercent)) > 20) {
    console.log(`  ⚠ WARNING: Significant memory increase detected - possible memory leak`);
  } else if (trend === 'STABLE' || trend === 'DECREASING') {
    console.log(`  ✓ Memory usage stable - no leaks detected`);
  }
}

/**
 * Generate Summary Report
 */
function generateSummary() {
  console.log('\n\n' + '='.repeat(70));
  console.log('📋 PERFORMANCE TEST SUMMARY');
  console.log('='.repeat(70));

  const summary = {
    testDate: results.timestamp,
    testUrl: results.testUrl,

    // Page Load
    pageLoadTime: results.scenarios.pageLoad?.totalLoadTime,
    firstContentfulPaint: results.scenarios.pageLoad?.metrics?.firstContentfulPaint,
    timeToInteractive: results.scenarios.pageLoad?.metrics?.domInteractive,

    // Bundle Size
    totalJavaScriptSize: results.scenarios.bundleSize?.totalJavaScriptSize,
    totalRequests: results.scenarios.bundleSize?.requestCount,

    // Memory
    baselineMemory: results.scenarios.baselineMemory?.usedJSHeapSize,
    audioMemoryIncrease: results.scenarios.audioMemory?.baselineComparison?.percentIncrease,

    // Stress Test
    stressTestErrors: results.scenarios.stressTest?.errors?.length || 0,

    // Long Running
    longRunningTrend: results.scenarios.longRunning?.trend?.direction,
    longRunningMemoryChange: results.scenarios.longRunning?.trend?.percentChange,

    // Assessment
    performance: 'UNKNOWN',
    stability: 'UNKNOWN',
    memoryLeaks: 'UNKNOWN',
  };

  // Performance Assessment
  if (summary.pageLoadTime < 2000 && summary.firstContentfulPaint < 1000) {
    summary.performance = 'EXCELLENT';
  } else if (summary.pageLoadTime < 5000 && summary.firstContentfulPaint < 2000) {
    summary.performance = 'GOOD';
  } else {
    summary.performance = 'NEEDS IMPROVEMENT';
  }

  // Stability Assessment
  if (summary.stressTestErrors === 0) {
    summary.stability = 'EXCELLENT';
  } else if (summary.stressTestErrors < 5) {
    summary.stability = 'GOOD';
  } else {
    summary.stability = 'POOR';
  }

  // Memory Leak Assessment
  const memoryIncreaseThreshold = 20; // 20% increase considered potential leak
  if (summary.longRunningTrend === 'STABLE' || summary.longRunningTrend === 'DECREASING') {
    summary.memoryLeaks = 'NONE DETECTED';
  } else if (Math.abs(summary.longRunningMemoryChange) < memoryIncreaseThreshold) {
    summary.memoryLeaks = 'MINIMAL';
  } else {
    summary.memoryLeaks = 'POTENTIAL LEAK DETECTED';
  }

  results.summary = summary;

  // Print Summary
  console.log('\n🎯 Key Metrics:');
  console.log(`  Page Load Time: ${summary.pageLoadTime}ms`);
  console.log(`  First Contentful Paint: ${summary.firstContentfulPaint?.toFixed(2)}ms`);
  console.log(`  Time to Interactive: ${summary.timeToInteractive?.toFixed(2)}ms`);
  console.log(`  JavaScript Bundle: ${formatBytes(summary.totalJavaScriptSize)}`);
  console.log(`  Baseline Memory: ${formatBytes(summary.baselineMemory)}`);

  console.log('\n📊 Assessment:');
  console.log(`  Performance: ${summary.performance}`);
  console.log(`  Stability: ${summary.stability}`);
  console.log(`  Memory Leaks: ${summary.memoryLeaks}`);
  console.log(`  Stress Test Errors: ${summary.stressTestErrors}`);

  console.log('\n💡 Recommendations:');

  if (summary.performance !== 'EXCELLENT') {
    console.log('  - Consider code splitting to reduce initial bundle size');
    console.log('  - Optimize JavaScript loading strategy');
  }

  if (summary.memoryLeaks !== 'NONE DETECTED') {
    console.log('  - Review event listener cleanup');
    console.log('  - Check for circular references');
    console.log('  - Verify AudioContext and node disposal');
  }

  if (summary.stressTestErrors > 0) {
    console.log('  - Add error boundaries for robustness');
    console.log('  - Implement rate limiting for user actions');
  }

  console.log('\n' + '='.repeat(70));
}

/**
 * Save Results to File
 */
function saveResults() {
  // Create output directory
  if (!fs.existsSync(CONFIG.outputDir)) {
    fs.mkdirSync(CONFIG.outputDir, { recursive: true });
  }

  // Save JSON results
  const jsonPath = path.join(CONFIG.outputDir, `performance-report-${Date.now()}.json`);
  fs.writeFileSync(jsonPath, JSON.stringify(results, null, 2));
  console.log(`\n💾 Results saved to: ${jsonPath}`);

  // Save Markdown report
  const mdPath = path.join(CONFIG.outputDir, `performance-report-${Date.now()}.md`);
  const markdown = generateMarkdownReport();
  fs.writeFileSync(mdPath, markdown);
  console.log(`📄 Markdown report saved to: ${mdPath}`);
}

/**
 * Generate Markdown Report
 */
function generateMarkdownReport() {
  const s = results.summary;

  return `# Performance Test Report

**Date:** ${new Date(results.timestamp).toLocaleString()}
**Test URL:** ${results.testUrl}

## Summary

| Metric | Value | Assessment |
|--------|-------|------------|
| Performance | ${s.performance} | ${getEmoji(s.performance)} |
| Stability | ${s.stability} | ${getEmoji(s.stability)} |
| Memory Leaks | ${s.memoryLeaks} | ${s.memoryLeaks === 'NONE DETECTED' ? '✅' : '⚠️'} |

## Detailed Results

### 1. Page Load Performance

- **Total Load Time:** ${s.pageLoadTime}ms
- **First Contentful Paint:** ${s.firstContentfulPaint?.toFixed(2)}ms
- **Time to Interactive:** ${s.timeToInteractive?.toFixed(2)}ms

### 2. JavaScript Bundle Size

- **Total JavaScript:** ${formatBytes(s.totalJavaScriptSize)}
- **Total Requests:** ${s.totalRequests}

### 3. Memory Usage

- **Baseline Memory:** ${formatBytes(s.baselineMemory)}
- **Audio Memory Increase:** ${s.audioMemoryIncrease?.toFixed(2)}%

### 4. Long-Running Stability

- **Memory Trend:** ${s.longRunningTrend}
- **Memory Change:** ${s.longRunningMemoryChange?.toFixed(2)}%

### 5. Stress Testing

- **Errors Detected:** ${s.stressTestErrors}

## Recommendations

${generateRecommendations(s)}

---
*Generated by Canopy Audio FFI Performance Test Suite*
`;
}

function getEmoji(assessment) {
  if (assessment === 'EXCELLENT' || assessment === 'NONE DETECTED') return '✅';
  if (assessment === 'GOOD' || assessment === 'MINIMAL') return '👍';
  return '⚠️';
}

function generateRecommendations(summary) {
  const recommendations = [];

  if (summary.performance !== 'EXCELLENT') {
    recommendations.push('- **Performance:** Consider code splitting and lazy loading');
  }

  if (summary.memoryLeaks !== 'NONE DETECTED') {
    recommendations.push('- **Memory:** Review resource cleanup and AudioContext disposal');
  }

  if (summary.stressTestErrors > 0) {
    recommendations.push('- **Stability:** Add error boundaries and rate limiting');
  }

  if (recommendations.length === 0) {
    return '✅ All metrics are within acceptable ranges. No immediate action required.';
  }

  return recommendations.join('\n');
}

/**
 * Main Test Runner
 */
async function runPerformanceTests() {
  console.log('🚀 Starting Comprehensive Performance Tests');
  console.log('='.repeat(70));

  const browser = await chromium.launch({
    headless: true,
    args: [
      '--enable-precise-memory-info',
      '--disable-dev-shm-usage',
      '--no-sandbox',
      '--use-fake-ui-for-media-stream', // Auto-grant microphone permission
      '--use-fake-device-for-media-stream',
    ],
  });

  const context = await browser.newContext({
    viewport: CONFIG.viewport,
    permissions: ['microphone'],
  });

  const page = await context.newPage();

  try {
    // Run all test scenarios
    await testPageLoadPerformance(page);
    await testBundleSize(page);
    const baselineMemory = await testBaselineMemory(page);
    await testAudioMemory(page, baselineMemory);
    await testCPUUsage(page);
    await testStress(page);
    await testLongRunning(page);

    // Generate and save results
    generateSummary();
    saveResults();

  } catch (error) {
    console.error('\n❌ Test execution error:', error);
    results.error = error.message;
  } finally {
    await browser.close();
  }

  console.log('\n✅ Performance testing completed!');
}

// Run tests
runPerformanceTests().catch(console.error);
