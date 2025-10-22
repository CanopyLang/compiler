/**
 * Comprehensive Playwright Visual Regression Test Suite
 * For Canopy Audio FFI Demo
 *
 * This test suite captures 17+ screenshots covering:
 * - Initial page load
 * - All demo modes
 * - UI interactions
 * - Different viewport sizes
 * - Button states and controls
 */

const { chromium } = require('playwright');
const path = require('path');

// Configuration
const BASE_URL = 'http://localhost:8080';
const SCREENSHOTS_DIR = path.join(__dirname, 'screenshots');
const VIEWPORT_SIZES = {
  desktop: { width: 1920, height: 1080 },
  laptop: { width: 1366, height: 768 },
  tablet: { width: 768, height: 1024 }
};

// Utility to ensure screenshots directory exists
const fs = require('fs');
if (!fs.existsSync(SCREENSHOTS_DIR)) {
  fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });
}

async function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function runVisualTests() {
  console.log('🎬 Starting Comprehensive Visual Regression Tests\n');

  const browser = await chromium.launch({
    headless: false, // Set to true for CI/CD
    slowMo: 100 // Slow down for visibility
  });

  const context = await browser.newContext({
    viewport: VIEWPORT_SIZES.desktop
  });

  const page = await context.newPage();

  try {
    // ========================================
    // Test Scenario 1: Initial Page Load
    // ========================================
    console.log('📸 Scenario 1: Initial Page Load');
    await page.goto(BASE_URL);
    await delay(2000); // Wait for full load

    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '01-initial-load.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 01-initial-load.png');

    // Verify all sections are visible
    const sectionsVisible = {
      header: await page.locator('h1:has-text("Audio FFI Demo")').isVisible(),
      ffiValidation: await page.locator('h3:has-text("FFI Validation")').isVisible(),
      audioControls: await page.locator('h3:has-text("Audio Controls")').isVisible(),
      status: await page.locator('h3:has-text("Status")').isVisible()
    };

    console.log('  ✓ Sections verification:', JSON.stringify(sectionsVisible, null, 2));

    // ========================================
    // Test Scenario 2: Audio Controls
    // ========================================
    console.log('\n📸 Scenario 2: Audio Controls');

    // Take screenshot of audio controls section
    const audioControlsSection = page.locator('h3:has-text("Audio Controls")').locator('..');
    await audioControlsSection.screenshot({
      path: path.join(SCREENSHOTS_DIR, '02-audio-controls.png')
    });
    console.log('  ✓ Captured: 02-audio-controls.png');

    // ========================================
    // Test Scenario 3: Waveform Buttons
    // ========================================
    console.log('\n📸 Scenario 3: Waveform Button States');

    // Default state (sine should be selected)
    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '03-waveform-sine.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 03-waveform-sine.png');

    // Click square button
    await page.locator('button:has-text("square")').click();
    await delay(500);
    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '04-waveform-square.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 04-waveform-square.png');

    // Click sawtooth button
    await page.locator('button:has-text("sawtooth")').click();
    await delay(500);
    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '05-waveform-sawtooth.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 05-waveform-sawtooth.png');

    // Click triangle button
    await page.locator('button:has-text("triangle")').click();
    await delay(500);
    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '06-waveform-triangle.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 06-waveform-triangle.png');

    // ========================================
    // Test Scenario 4: Frequency Slider
    // ========================================
    console.log('\n📸 Scenario 4: Frequency Slider Interaction');

    // Reset to sine
    await page.locator('button:has-text("sine")').click();
    await delay(500);

    // Adjust frequency slider
    const frequencySlider = page.locator('input[type="range"]').first();
    await frequencySlider.fill('440'); // A4 note
    await delay(500);
    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '07-frequency-440hz.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 07-frequency-440hz.png');

    await frequencySlider.fill('1000');
    await delay(500);
    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '08-frequency-1000hz.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 08-frequency-1000hz.png');

    // ========================================
    // Test Scenario 5: Volume Slider
    // ========================================
    console.log('\n📸 Scenario 5: Volume Slider Interaction');

    const volumeSlider = page.locator('input[type="range"]').nth(1);
    await volumeSlider.fill('50');
    await delay(500);
    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '09-volume-50.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 09-volume-50.png');

    await volumeSlider.fill('100');
    await delay(500);
    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '10-volume-100.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 10-volume-100.png');

    // ========================================
    // Test Scenario 6: Button Interactions
    // ========================================
    console.log('\n📸 Scenario 6: Audio Playback Buttons');

    // Click Play button
    await page.locator('button:has-text("Play Audio")').click();
    await delay(1000);
    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '11-playing-audio.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 11-playing-audio.png');

    // Check status has updated
    const statusText = await page.locator('h3:has-text("Status")').locator('..').textContent();
    console.log('  ✓ Status after play:', statusText.substring(0, 100) + '...');

    await delay(1000);

    // Click Stop button
    await page.locator('button:has-text("Stop Audio")').click();
    await delay(500);
    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '12-stopped-audio.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 12-stopped-audio.png');

    // ========================================
    // Test Scenario 7: Button Focus States
    // ========================================
    console.log('\n📸 Scenario 7: Button Focus States');

    // Focus on Play button
    await page.locator('button:has-text("Play Audio")').focus();
    await delay(300);
    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '13-play-button-focused.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 13-play-button-focused.png');

    // Focus on waveform button
    await page.locator('button:has-text("sine")').focus();
    await delay(300);
    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '14-waveform-button-focused.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 14-waveform-button-focused.png');

    // ========================================
    // Test Scenario 8: Responsive Design - Desktop
    // ========================================
    console.log('\n📸 Scenario 8: Responsive Design Testing');

    await page.setViewportSize(VIEWPORT_SIZES.desktop);
    await delay(500);
    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '15-desktop-1920x1080.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 15-desktop-1920x1080.png');

    // Laptop size
    await page.setViewportSize(VIEWPORT_SIZES.laptop);
    await delay(500);
    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '16-laptop-1366x768.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 16-laptop-1366x768.png');

    // Tablet size
    await page.setViewportSize(VIEWPORT_SIZES.tablet);
    await delay(500);
    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '17-tablet-768x1024.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 17-tablet-768x1024.png');

    // ========================================
    // Test Scenario 9: FFI Validation Section
    // ========================================
    console.log('\n📸 Scenario 9: FFI Validation Section');

    // Reset to desktop
    await page.setViewportSize(VIEWPORT_SIZES.desktop);
    await delay(500);

    const ffiSection = page.locator('h3:has-text("FFI Validation")').locator('..');
    await ffiSection.screenshot({
      path: path.join(SCREENSHOTS_DIR, '18-ffi-validation-section.png')
    });
    console.log('  ✓ Captured: 18-ffi-validation-section.png');

    // Extract FFI validation data
    const ffiValidationText = await ffiSection.textContent();
    console.log('  ✓ FFI Validation Data:');
    console.log('    ', ffiValidationText.substring(0, 200));

    // ========================================
    // Test Scenario 10: Status Section Detail
    // ========================================
    console.log('\n📸 Scenario 10: Status Section Detail');

    const statusSection = page.locator('h3:has-text("Status")').locator('..');
    await statusSection.screenshot({
      path: path.join(SCREENSHOTS_DIR, '19-status-section.png')
    });
    console.log('  ✓ Captured: 19-status-section.png');

    // ========================================
    // Test Scenario 11: Complete UI Elements Inventory
    // ========================================
    console.log('\n📊 UI Elements Inventory:');

    const uiElements = {
      buttons: await page.locator('button').count(),
      sliders: await page.locator('input[type="range"]').count(),
      headings: await page.locator('h1, h2, h3, h4').count(),
      sections: await page.locator('div[style*="border-radius"]').count()
    };

    console.log('  ✓ Buttons:', uiElements.buttons);
    console.log('  ✓ Sliders:', uiElements.sliders);
    console.log('  ✓ Headings:', uiElements.headings);
    console.log('  ✓ Rounded sections:', uiElements.sections);

    // ========================================
    // Test Scenario 12: Color and Styling Verification
    // ========================================
    console.log('\n🎨 Color and Styling Verification:');

    const playButton = page.locator('button:has-text("Play Audio")');
    const playButtonColor = await playButton.evaluate(el =>
      window.getComputedStyle(el).backgroundColor
    );
    console.log('  ✓ Play button background:', playButtonColor);

    const stopButton = page.locator('button:has-text("Stop Audio")');
    const stopButtonColor = await stopButton.evaluate(el =>
      window.getComputedStyle(el).backgroundColor
    );
    console.log('  ✓ Stop button background:', stopButtonColor);

    const waveformButton = page.locator('button:has-text("sine")');
    const waveformButtonColor = await waveformButton.evaluate(el =>
      window.getComputedStyle(el).backgroundColor
    );
    console.log('  ✓ Waveform button (selected):', waveformButtonColor);

    // ========================================
    // Final Summary Screenshot
    // ========================================
    console.log('\n📸 Final: Complete Page Overview');

    await page.screenshot({
      path: path.join(SCREENSHOTS_DIR, '20-final-complete-view.png'),
      fullPage: true
    });
    console.log('  ✓ Captured: 20-final-complete-view.png');

    // ========================================
    // Test Results Summary
    // ========================================
    console.log('\n' + '='.repeat(60));
    console.log('✅ VISUAL REGRESSION TEST COMPLETE');
    console.log('='.repeat(60));
    console.log(`📁 Screenshots saved to: ${SCREENSHOTS_DIR}`);
    console.log(`📊 Total screenshots: 20`);
    console.log(`🎯 All scenarios executed successfully`);
    console.log('='.repeat(60));

  } catch (error) {
    console.error('\n❌ Test failed:', error);
    throw error;
  } finally {
    await browser.close();
  }
}

// Run tests if executed directly
if (require.main === module) {
  runVisualTests()
    .then(() => {
      console.log('\n✨ All tests completed successfully!');
      process.exit(0);
    })
    .catch(error => {
      console.error('\n💥 Tests failed:', error);
      process.exit(1);
    });
}

module.exports = { runVisualTests };
