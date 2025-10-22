# Audio FFI Visual Regression Test Suite

Comprehensive Playwright-based visual regression testing for the Canopy Audio FFI Demo.

## 🎯 Test Coverage

This suite captures **20+ screenshots** across multiple scenarios:

### Test Scenarios

1. **Initial Page Load** - Full page screenshot with all sections visible
2. **Audio Controls** - Focused view of control panel
3. **Waveform Buttons** - All 4 waveform types (sine, square, sawtooth, triangle)
4. **Frequency Slider** - Multiple frequency values (440Hz, 1000Hz)
5. **Volume Slider** - Different volume levels (50%, 100%)
6. **Audio Playback** - Playing and stopped states
7. **Button Focus States** - Keyboard navigation states
8. **Responsive Design** - 3 viewport sizes (desktop, laptop, tablet)
9. **FFI Validation** - Verification section detail
10. **Status Section** - Status display detail
11. **UI Elements Inventory** - Complete element count
12. **Color Verification** - Button styling validation

## 📋 Prerequisites

- Node.js 16+ installed
- npm or yarn package manager

## 🚀 Quick Start

### 1. Install Dependencies

```bash
cd /home/quinten/fh/canopy/examples/audio-ffi/visual-tests
npm install
```

### 2. Install Playwright Browsers

```bash
npm run install-browsers
```

### 3. Run Tests

**Option A: With Separate Server (Recommended)**

Terminal 1 - Start server:
```bash
npm run serve
```

Terminal 2 - Run tests:
```bash
npm test
```

**Option B: Automated (CI/CD)**

```bash
npm run test:ci
```

**Option C: Headed Mode (See Browser)**

```bash
npm run test:headed
```

## 📸 Screenshot Output

All screenshots are saved to: `./screenshots/`

### Screenshot Naming Convention

- `01-initial-load.png` - Full page initial state
- `02-audio-controls.png` - Audio controls section
- `03-waveform-sine.png` through `06-waveform-triangle.png` - Waveform states
- `07-frequency-440hz.png`, `08-frequency-1000hz.png` - Frequency changes
- `09-volume-50.png`, `10-volume-100.png` - Volume changes
- `11-playing-audio.png`, `12-stopped-audio.png` - Playback states
- `13-play-button-focused.png`, `14-waveform-button-focused.png` - Focus states
- `15-desktop-1920x1080.png` - Desktop viewport
- `16-laptop-1366x768.png` - Laptop viewport
- `17-tablet-768x1024.png` - Tablet viewport
- `18-ffi-validation-section.png` - FFI section detail
- `19-status-section.png` - Status section detail
- `20-final-complete-view.png` - Final overview

## 🔍 What Gets Validated

### UI Elements
- ✅ Header with title
- ✅ FFI validation section with results
- ✅ Audio controls section
- ✅ Play/Stop buttons
- ✅ Frequency slider (20-2000 Hz)
- ✅ Volume slider (0-100%)
- ✅ 4 waveform selector buttons
- ✅ Status display section

### Visual States
- ✅ Button normal state
- ✅ Button focused state
- ✅ Button active/selected state
- ✅ Slider value changes
- ✅ Dynamic status updates

### Responsive Behavior
- ✅ Desktop layout (1920x1080)
- ✅ Laptop layout (1366x768)
- ✅ Tablet layout (768x1024)

### Color Verification
- ✅ Play button: Green background
- ✅ Stop button: Red background
- ✅ Waveform selected: Gold background
- ✅ Waveform unselected: Transparent background

## 🛠 Configuration

Edit `playwright-visual-test.js` to customize:

- `BASE_URL` - Server URL (default: http://localhost:8080)
- `SCREENSHOTS_DIR` - Output directory
- `VIEWPORT_SIZES` - Responsive breakpoints
- `headless` - Browser visibility (true/false)
- `slowMo` - Slow down automation (milliseconds)

## 📊 Test Output

The test suite provides:

1. **Console Output**
   - Progress for each test scenario
   - UI element counts
   - Color verification results
   - Status updates

2. **Screenshots**
   - PNG images for visual comparison
   - Full page and element-specific captures
   - Multiple viewport sizes

3. **Exit Codes**
   - `0` - All tests passed
   - `1` - Tests failed

## 🐛 Troubleshooting

### Server Not Running

Error: `net::ERR_CONNECTION_REFUSED`

**Solution:**
```bash
# Start server in background
npm run serve &
# Wait a moment
sleep 3
# Run tests
npm test
```

### Playwright Not Installed

Error: `browserType.launch: Executable doesn't exist`

**Solution:**
```bash
npm run install-browsers
```

### Screenshots Missing

**Check:**
1. Server is running on port 8080
2. index.html exists in parent directory
3. Write permissions in screenshots directory

## 🔄 CI/CD Integration

### GitHub Actions Example

```yaml
name: Visual Regression Tests

on: [push, pull_request]

jobs:
  visual-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - name: Install dependencies
        run: |
          cd examples/audio-ffi/visual-tests
          npm install
          npm run install-browsers
      - name: Run tests
        run: |
          cd examples/audio-ffi/visual-tests
          npm run test:ci
      - name: Upload screenshots
        uses: actions/upload-artifact@v3
        with:
          name: screenshots
          path: examples/audio-ffi/visual-tests/screenshots/
```

## 📝 Extending Tests

To add new test scenarios:

1. Add new test section in `playwright-visual-test.js`
2. Follow naming convention: `##-description.png`
3. Update this README with new scenario
4. Document expected behavior

Example:
```javascript
// New test scenario
console.log('\n📸 Scenario X: Custom Test');
await page.locator('selector').click();
await delay(500);
await page.screenshot({
  path: path.join(SCREENSHOTS_DIR, '21-custom-test.png'),
  fullPage: true
});
console.log('  ✓ Captured: 21-custom-test.png');
```

## 📚 Resources

- [Playwright Documentation](https://playwright.dev/)
- [Visual Testing Best Practices](https://playwright.dev/docs/test-snapshots)
- [Canopy Compiler Documentation](https://github.com/yourusername/canopy)

## 🤝 Contributing

When adding visual tests:

1. Ensure tests are deterministic
2. Use consistent delays for animations
3. Name screenshots descriptively
4. Update documentation
5. Verify across all viewport sizes

## 📄 License

MIT License - See parent project for details
