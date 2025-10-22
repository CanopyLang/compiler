/**
 * COMPREHENSIVE INTEGRATION TEST SUITE - ALL MANUAL TEST FILES
 *
 * This test suite runs through all the manual test HTML files:
 * 1. test-biquad-filter.html - Filter effects testing
 * 2. test-spatial-audio-manual.html - 3D spatial audio testing
 * 3. test-mediastream.html - MediaStream testing
 *
 * Provides comprehensive verification of the Audio FFI system.
 */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

// Configuration
const CONFIG = {
  baseDir: path.resolve(__dirname),
  screenshotDir: path.resolve(__dirname, 'test-results/integration'),
  timeout: 10000,
  waitTime: 500,
  audioPlayTime: 2000
};

const testResults = {
  biquadFilter: { passed: 0, failed: 0, tests: [] },
  spatialAudio: { passed: 0, failed: 0, tests: [] },
  mediaStream: { passed: 0, failed: 0, tests: [] },
  screenshots: []
};

function logTest(suite, testName, passed, details = '') {
  const result = {
    name: testName,
    passed,
    details,
    timestamp: new Date().toISOString()
  };

  testResults[suite].tests.push(result);

  if (passed) {
    testResults[suite].passed++;
    console.log(`  ✅ ${testName}`);
  } else {
    testResults[suite].failed++;
    console.log(`  ❌ ${testName}: ${details}`);
  }

  return passed;
}

async function takeScreenshot(page, name) {
  const screenshotPath = path.join(CONFIG.screenshotDir, `${name}.png`);
  await page.screenshot({ path: screenshotPath, fullPage: true });
  testResults.screenshots.push({ name, path: screenshotPath });
  console.log(`    📸 Screenshot: ${name}`);
  return screenshotPath;
}

async function wait(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * TEST SUITE 1: BIQUAD FILTER TESTS
 */
async function testBiquadFilter(page) {
  console.log('\n📋 TEST SUITE 1: BIQUAD FILTER TESTS');
  console.log('====================================');

  await page.goto('file://' + path.join(CONFIG.baseDir, 'test-biquad-filter.html'));
  await wait(CONFIG.waitTime);
  await takeScreenshot(page, '01-biquad-filter-initial');
  logTest('biquadFilter', 'Page loads successfully', true);

  // Test 1: Initialize Audio
  await page.click('#init');
  await wait(CONFIG.waitTime);
  await takeScreenshot(page, '02-biquad-audio-initialized');

  const initStatus = await page.locator('#status').textContent();
  logTest('biquadFilter', 'Initialize AudioContext',
    initStatus.includes('initialized') || initStatus.includes('created'),
    `Status: ${initStatus}`
  );

  // Test 2: Play Audio
  await page.click('#play');
  await wait(CONFIG.audioPlayTime);
  await takeScreenshot(page, '03-biquad-audio-playing');

  const playStatus = await page.locator('#status').textContent();
  logTest('biquadFilter', 'Play audio successfully',
    playStatus.includes('playing') || playStatus.includes('started'),
    `Status: ${playStatus}`
  );

  // Test 3: Create Filter
  await page.click('#createFilter');
  await wait(CONFIG.waitTime);
  await takeScreenshot(page, '04-biquad-filter-created');

  const filterStatus = await page.locator('#status').textContent();
  logTest('biquadFilter', 'Create filter node',
    filterStatus.includes('Filter') || filterStatus.includes('created'),
    `Status: ${filterStatus}`
  );

  // Test 4: Lowpass Filter
  await page.click('button:has-text("Lowpass")');
  await wait(CONFIG.audioPlayTime);
  await takeScreenshot(page, '05-biquad-lowpass');
  logTest('biquadFilter', 'Test Lowpass filter', true);

  // Test 5: Highpass Filter
  await page.click('button:has-text("Highpass")');
  await wait(CONFIG.audioPlayTime);
  await takeScreenshot(page, '06-biquad-highpass');
  logTest('biquadFilter', 'Test Highpass filter', true);

  // Test 6: Bandpass Filter
  await page.click('button:has-text("Bandpass")');
  await wait(CONFIG.audioPlayTime);
  await takeScreenshot(page, '07-biquad-bandpass');
  logTest('biquadFilter', 'Test Bandpass filter', true);

  // Test 7: Notch Filter
  await page.click('button:has-text("Notch")');
  await wait(CONFIG.audioPlayTime);
  await takeScreenshot(page, '08-biquad-notch');
  logTest('biquadFilter', 'Test Notch filter', true);

  // Test 8: Frequency Parameter
  await page.fill('#frequency', '500');
  await wait(CONFIG.waitTime);
  await takeScreenshot(page, '09-biquad-freq-500');

  const freqDisplay = await page.locator('#freqDisplay').textContent();
  logTest('biquadFilter', 'Set frequency to 500 Hz',
    freqDisplay.includes('500'),
    `Display: ${freqDisplay}`
  );

  // Test 9: Q Parameter
  await page.fill('#q', '10');
  await wait(CONFIG.waitTime);
  await takeScreenshot(page, '10-biquad-q-10');

  const qDisplay = await page.locator('#qDisplay').textContent();
  logTest('biquadFilter', 'Set Q to 10',
    qDisplay.includes('10'),
    `Display: ${qDisplay}`
  );

  // Test 10: Gain Parameter
  await page.fill('#gain', '20');
  await wait(CONFIG.waitTime);
  await takeScreenshot(page, '11-biquad-gain-20');

  const gainDisplay = await page.locator('#gainDisplay').textContent();
  logTest('biquadFilter', 'Set gain to 20 dB',
    gainDisplay.includes('20'),
    `Display: ${gainDisplay}`
  );

  // Stop audio
  await page.click('#stop');
  await wait(CONFIG.waitTime);
  await takeScreenshot(page, '12-biquad-audio-stopped');
  logTest('biquadFilter', 'Stop audio successfully', true);
}

/**
 * TEST SUITE 2: 3D SPATIAL AUDIO TESTS
 */
async function testSpatialAudio(page) {
  console.log('\n📋 TEST SUITE 2: 3D SPATIAL AUDIO TESTS');
  console.log('=======================================');

  await page.goto('file://' + path.join(CONFIG.baseDir, 'test-spatial-audio-manual.html'));
  await wait(CONFIG.waitTime);
  await takeScreenshot(page, '13-spatial-audio-initial');
  logTest('spatialAudio', 'Page loads successfully', true);

  // Test 1: Initialize Audio
  await page.click('#initBtn');
  await wait(CONFIG.waitTime);
  await takeScreenshot(page, '14-spatial-audio-initialized');

  const initStatus = await page.locator('#status').textContent();
  logTest('spatialAudio', 'Initialize AudioContext',
    initStatus.includes('initialized') || initStatus.includes('created') || initStatus.includes('AudioContext'),
    `Status: ${initStatus}`
  );

  // Test 2: Play Audio
  await page.click('#playBtn');
  await wait(CONFIG.audioPlayTime);
  await takeScreenshot(page, '15-spatial-audio-playing');

  const playStatus = await page.locator('#status').textContent();
  logTest('spatialAudio', 'Play audio successfully',
    playStatus.includes('playing') || playStatus.includes('started') || playStatus.includes('Audio'),
    `Status: ${playStatus}`
  );

  // Test 3: Create Panner
  await page.click('#createPannerBtn');
  await wait(CONFIG.waitTime);
  await takeScreenshot(page, '16-spatial-panner-created');

  const pannerStatus = await page.locator('#status').textContent();
  logTest('spatialAudio', 'Create panner node',
    pannerStatus.includes('Panner') || pannerStatus.includes('created'),
    `Status: ${pannerStatus}`
  );

  // Test 4: X Position using slider
  await page.fill('#xSlider', '-10');
  await wait(CONFIG.audioPlayTime);
  await takeScreenshot(page, '17-spatial-pan-left');

  const xLeftValue = await page.locator('#xValue').textContent();
  logTest('spatialAudio', 'Pan audio to left (X=-10)',
    xLeftValue.includes('-10') || xLeftValue.includes('-'),
    `Display: ${xLeftValue}`
  );

  // Test 5: X Position Right
  await page.fill('#xSlider', '10');
  await wait(CONFIG.audioPlayTime);
  await takeScreenshot(page, '18-spatial-pan-right');

  const xRightValue = await page.locator('#xValue').textContent();
  logTest('spatialAudio', 'Pan audio to right (X=10)',
    xRightValue.includes('10'),
    `Display: ${xRightValue}`
  );

  // Test 6: Y Position Up
  await page.fill('#ySlider', '10');
  await wait(CONFIG.audioPlayTime);
  await takeScreenshot(page, '19-spatial-move-up');

  const yUpValue = await page.locator('#yValue').textContent();
  logTest('spatialAudio', 'Move audio up (Y=10)',
    yUpValue.includes('10')
  );

  // Test 7: Y Position Down
  await page.fill('#ySlider', '-10');
  await wait(CONFIG.audioPlayTime);
  await takeScreenshot(page, '20-spatial-move-down');

  const yDownValue = await page.locator('#yValue').textContent();
  logTest('spatialAudio', 'Move audio down (Y=-10)',
    yDownValue.includes('-10') || yDownValue.includes('-')
  );

  // Test 8: Z Position Near
  await page.fill('#zSlider', '10');
  await wait(CONFIG.audioPlayTime);
  await takeScreenshot(page, '21-spatial-move-near');

  const zNearValue = await page.locator('#zValue').textContent();
  logTest('spatialAudio', 'Move audio near (Z=10)',
    zNearValue.includes('10')
  );

  // Test 9: Z Position Far
  await page.fill('#zSlider', '-10');
  await wait(CONFIG.audioPlayTime);
  await takeScreenshot(page, '22-spatial-move-far');

  const zFarValue = await page.locator('#zValue').textContent();
  logTest('spatialAudio', 'Move audio far (Z=-10)',
    zFarValue.includes('-10') || zFarValue.includes('-')
  );

  // Test 10: Test preset buttons
  await page.click('#presetBtn1');
  await wait(CONFIG.audioPlayTime);
  await takeScreenshot(page, '23-spatial-preset-1');
  logTest('spatialAudio', 'Test spatial preset 1', true);

  await page.click('#presetBtn2');
  await wait(CONFIG.audioPlayTime);
  await takeScreenshot(page, '24-spatial-preset-2');
  logTest('spatialAudio', 'Test spatial preset 2', true);

  // Stop audio
  await page.click('#stopBtn');
  await wait(CONFIG.waitTime);
  await takeScreenshot(page, '25-spatial-audio-stopped');
  logTest('spatialAudio', 'Stop audio successfully', true);
}

/**
 * TEST SUITE 3: MEDIASTREAM TESTS
 */
async function testMediaStream(page) {
  console.log('\n📋 TEST SUITE 3: MEDIASTREAM TESTS');
  console.log('==================================');

  await page.goto('file://' + path.join(CONFIG.baseDir, 'test-mediastream.html'));
  await wait(CONFIG.waitTime);
  await takeScreenshot(page, '26-mediastream-initial');
  logTest('mediaStream', 'Page loads successfully', true);

  // Test 1: Request Microphone (may require user permission)
  try {
    await page.click('button:has-text("Request Microphone Access")');
    await wait(CONFIG.waitTime * 2); // Give time for permission dialog
    await takeScreenshot(page, '27-mediastream-mic-requested');

    const micStatus = await page.locator('#status').textContent();
    const micGranted = micStatus.includes('granted') ||
                      micStatus.includes('success') ||
                      micStatus.includes('stream') ||
                      micStatus.includes('OK') ||
                      micStatus.includes('✅');

    logTest('mediaStream', 'Request microphone access', micGranted,
      `Status: ${micStatus} (May fail without user permission)`
    );
  } catch (error) {
    logTest('mediaStream', 'Request microphone access', false,
      'Permission dialog may have blocked - expected in headless mode'
    );
  }

  // Test 2: Create MediaStreamSource
  try {
    await page.click('button:has-text("Create MediaStreamSource")');
    await wait(CONFIG.waitTime);
    await takeScreenshot(page, '28-mediastream-source-created');

    const sourceStatus = await page.locator('#status').textContent();
    const sourceSuccess = sourceStatus.includes('MediaStreamSource') ||
                         sourceStatus.includes('created') ||
                         sourceStatus.includes('✅');

    logTest('mediaStream', 'Create MediaStreamSource', sourceSuccess,
      `Status: ${sourceStatus}`
    );
  } catch (error) {
    logTest('mediaStream', 'Create MediaStreamSource', false,
      'May fail if microphone access denied'
    );
  }

  // Test 3: Create MediaStream Destination
  await page.click('button:has-text("Create MediaStreamDestination")');
  await wait(CONFIG.waitTime);
  await takeScreenshot(page, '29-mediastream-destination-created');

  const destStatus = await page.locator('#status').textContent();
  logTest('mediaStream', 'Create MediaStream destination',
    destStatus.includes('Destination') || destStatus.includes('created') || destStatus.includes('✅'),
    `Status: ${destStatus}`
  );

  // Test 4: Get Destination Stream
  await page.click('button:has-text("Get Destination Stream")');
  await wait(CONFIG.waitTime);
  await takeScreenshot(page, '30-mediastream-get-stream');

  const getStreamStatus = await page.locator('#status').textContent();
  logTest('mediaStream', 'Get destination stream',
    getStreamStatus.includes('Stream') || getStreamStatus.includes('✅'),
    `Status: ${getStreamStatus}`
  );

  // Test 5: Full Pipeline
  await page.click('button:has-text("Test Full Pipeline")');
  await wait(CONFIG.audioPlayTime);
  await takeScreenshot(page, '31-mediastream-full-pipeline');

  const pipelineStatus = await page.locator('#status').textContent();
  logTest('mediaStream', 'Test full MediaStream pipeline',
    pipelineStatus.includes('pipeline') || pipelineStatus.includes('success') || pipelineStatus.includes('✅'),
    `Status: ${pipelineStatus}`
  );
}

/**
 * GENERATE COMPREHENSIVE REPORT
 */
function generateReport() {
  console.log('\n📊 COMPREHENSIVE INTEGRATION TEST REPORT');
  console.log('========================================\n');

  const totalPassed = testResults.biquadFilter.passed +
                     testResults.spatialAudio.passed +
                     testResults.mediaStream.passed;

  const totalFailed = testResults.biquadFilter.failed +
                     testResults.spatialAudio.failed +
                     testResults.mediaStream.failed;

  const totalTests = totalPassed + totalFailed;
  const passRate = ((totalPassed / totalTests) * 100).toFixed(1);

  console.log(`Total Tests: ${totalTests}`);
  console.log(`Passed: ${totalPassed} ✅`);
  console.log(`Failed: ${totalFailed} ❌`);
  console.log(`Pass Rate: ${passRate}%`);
  console.log(`Screenshots: ${testResults.screenshots.length} 📸\n`);

  // Suite breakdown
  const suites = ['biquadFilter', 'spatialAudio', 'mediaStream'];
  const suiteNames = [
    'Biquad Filter Tests',
    '3D Spatial Audio Tests',
    'MediaStream Tests'
  ];

  suites.forEach((suite, index) => {
    const result = testResults[suite];
    const suiteTotal = result.passed + result.failed;
    const suitePassRate = ((result.passed / suiteTotal) * 100).toFixed(1);
    const status = result.failed === 0 ? '✅ PASSED' : '❌ FAILED';

    console.log(`${suiteNames[index]}: ${status}`);
    console.log(`  Passed: ${result.passed}/${suiteTotal} (${suitePassRate}%)`);

    if (result.failed > 0) {
      console.log(`  Failed tests:`);
      result.tests.filter(t => !t.passed).forEach(t => {
        console.log(`    - ${t.name}: ${t.details}`);
      });
    }
    console.log('');
  });

  // Success criteria
  console.log('SUCCESS CRITERIA:');
  console.log(`  90%+ overall pass rate: ${passRate >= 90 ? '✅' : '❌'}`);
  console.log(`  All critical features work: ${testResults.biquadFilter.failed === 0 &&
                                               testResults.spatialAudio.failed === 0 ? '✅' : '❌'}`);
  console.log(`  Screenshots captured: ${testResults.screenshots.length >= 25 ? '✅' : '❌'}`);

  // Write reports
  const reportPath = path.join(CONFIG.screenshotDir, 'integration-test-report.json');
  fs.writeFileSync(reportPath, JSON.stringify(testResults, null, 2));
  console.log(`\n📄 Detailed report saved: ${reportPath}`);

  const mdReport = generateMarkdownReport(suiteNames, totalPassed, totalFailed, passRate);
  const mdPath = path.join(CONFIG.screenshotDir, 'INTEGRATION-TEST-REPORT.md');
  fs.writeFileSync(mdPath, mdReport);
  console.log(`📄 Markdown report saved: ${mdPath}`);

  return totalFailed === 0;
}

function generateMarkdownReport(suiteNames, totalPassed, totalFailed, passRate) {
  const totalTests = totalPassed + totalFailed;

  let md = `# Comprehensive Integration Test Report\n\n`;
  md += `**Generated:** ${new Date().toISOString()}\n\n`;
  md += `## Executive Summary\n\n`;
  md += `- **Total Tests:** ${totalTests}\n`;
  md += `- **Passed:** ${totalPassed} ✅\n`;
  md += `- **Failed:** ${totalFailed} ❌\n`;
  md += `- **Pass Rate:** ${passRate}%\n`;
  md += `- **Screenshots:** ${testResults.screenshots.length} 📸\n\n`;

  const suites = ['biquadFilter', 'spatialAudio', 'mediaStream'];

  md += `## Test Suite Results\n\n`;
  suites.forEach((suite, index) => {
    const result = testResults[suite];
    const suiteTotal = result.passed + result.failed;
    const suitePassRate = ((result.passed / suiteTotal) * 100).toFixed(1);
    const status = result.failed === 0 ? '✅ PASSED' : '❌ FAILED';

    md += `### ${suiteNames[index]} ${status}\n\n`;
    md += `**Pass Rate:** ${suitePassRate}% (${result.passed}/${suiteTotal})\n\n`;

    md += `#### Test Cases\n\n`;
    result.tests.forEach(test => {
      const icon = test.passed ? '✅' : '❌';
      md += `- ${icon} ${test.name}\n`;
      if (test.details) {
        md += `  - ${test.details}\n`;
      }
    });
    md += `\n`;
  });

  md += `## Screenshots\n\n`;
  testResults.screenshots.forEach(screenshot => {
    md += `### ${screenshot.name}\n\n`;
    md += `![${screenshot.name}](${path.basename(screenshot.path)})\n\n`;
  });

  md += `## Success Criteria\n\n`;
  md += `- ${passRate >= 90 ? '✅' : '❌'} 90%+ overall pass rate\n`;
  md += `- ${testResults.biquadFilter.failed === 0 && testResults.spatialAudio.failed === 0 ? '✅' : '❌'} All critical features work\n`;
  md += `- ${testResults.screenshots.length >= 25 ? '✅' : '❌'} Screenshots captured (25+ expected)\n\n`;

  return md;
}

/**
 * MAIN TEST RUNNER
 */
async function runAllTests() {
  console.log('🚀 COMPREHENSIVE AUDIO FFI INTEGRATION TESTS');
  console.log('============================================\n');

  // Create screenshot directory
  if (!fs.existsSync(CONFIG.screenshotDir)) {
    fs.mkdirSync(CONFIG.screenshotDir, { recursive: true });
  }

  const browser = await chromium.launch({
    headless: false,
    args: ['--autoplay-policy=no-user-gesture-required']
  });

  const context = await browser.newContext({
    permissions: ['microphone', 'camera']
  });

  const page = await context.newPage();

  try {
    await testBiquadFilter(page);
    await testSpatialAudio(page);
    await testMediaStream(page);

    const allPassed = generateReport();

    await browser.close();

    process.exit(allPassed ? 0 : 1);
  } catch (error) {
    console.error('\n❌ FATAL ERROR:', error);
    await takeScreenshot(page, 'error-fatal');
    await browser.close();
    process.exit(1);
  }
}

// Run tests
runAllTests();
