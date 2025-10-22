# Visual Tests - Quick Start Guide

## 🚀 Run Tests in 3 Steps

### 1️⃣ Install Dependencies

```bash
cd /home/quinten/fh/canopy/examples/audio-ffi/visual-tests
npm install
npm run install-browsers
```

### 2️⃣ Start Server (Terminal 1)

```bash
cd /home/quinten/fh/canopy/examples/audio-ffi
npx http-server . -p 8080 -c-1
```

### 3️⃣ Run Tests (Terminal 2)

```bash
cd /home/quinten/fh/canopy/examples/audio-ffi/visual-tests
npm test
```

## 📸 View Results

Screenshots saved to: `./screenshots/`

All 20 screenshots:
- Initial load
- All 4 waveforms
- Frequency changes
- Volume changes
- Button states
- 3 viewport sizes
- Section details

## 📊 View Report

Open the detailed test report:
```bash
cat VISUAL_TEST_REPORT.md
# or
less VISUAL_TEST_REPORT.md
# or open in your favorite editor
```

## 🎯 Expected Results

✅ **20 screenshots** captured (6.8 MB total)
✅ **All UI sections** visible and styled correctly
✅ **All buttons** functional with proper colors
✅ **All sliders** working with value display
✅ **Responsive design** works across 3 viewport sizes
✅ **Test completes** in ~120 seconds

## ⚠️ Known Issues

1. **"Web Audio Support: undefined"** - FFI detection needs fix
2. **"AudioContext not initialized"** - Expected in automated tests (browser security)

Both are cosmetic and don't affect functionality.

## 🔧 Troubleshooting

**Port 8080 already in use?**
```bash
# Use different port
npx http-server . -p 8081 -c-1

# Update BASE_URL in playwright-visual-test.js:
# const BASE_URL = 'http://localhost:8081';
```

**Playwright not installed?**
```bash
npm run install-browsers
```

**Screenshots missing?**
Check that:
- Server is running on port 8080
- index.html exists in parent directory
- You have write permissions

## 📚 Full Documentation

- `README.md` - Complete test suite documentation
- `VISUAL_TEST_REPORT.md` - Detailed test results and findings
- `playwright-visual-test.js` - Test script (20 scenarios)

## 🎬 One-Liner Test

Run everything at once:
```bash
cd /home/quinten/fh/canopy/examples/audio-ffi/visual-tests && npm install && npm run install-browsers && (cd .. && npx http-server . -p 8080 -c-1 &) && sleep 3 && npm test
```

---

**Questions?** Read the full README.md or check VISUAL_TEST_REPORT.md
