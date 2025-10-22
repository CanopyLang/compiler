# Performance Testing - Quick Reference Card

## 🚀 Quick Start

```bash
cd examples/audio-ffi
npm install
npm run test:performance
```

## 📊 Test Results Summary

| Test | Status | Value | Issue |
|------|--------|-------|-------|
| Page Load | ✅ EXCELLENT | 516ms | None |
| Bundle Size | ✅ EXCELLENT | 38.93KB | None |
| Baseline Memory | ✅ EXCELLENT | 1.44MB | None |
| CPU Usage | ✅ EXCELLENT | 0 long tasks | None |
| **Stability** | ⛔ **POOR** | **590 errors** | **CRITICAL** |
| **Memory Leak** | ⛔ **DETECTED** | **+28.52%** | **HIGH** |

## 🔴 Critical Issues Found

### Issue #1: Stress Test Errors (590 errors)
**Severity:** CRITICAL
**Impact:** Application crashes or becomes unresponsive under load

**Quick Fix Checklist:**
- [ ] Add try-catch around `getUserMedia()` calls
- [ ] Add error boundary for async operations
- [ ] Rate limit button clicks (debounce/throttle)
- [ ] Check AudioContext state before operations
- [ ] Add retry logic with backoff

**Test Command:**
```bash
# Re-test after fixes
npm run test:performance
```

### Issue #2: Memory Leak (+28.52% over 5 min)
**Severity:** HIGH
**Impact:** App slows down over time, eventually crashes

**Quick Fix Checklist:**
- [ ] Remove event listeners on cleanup
- [ ] Disconnect audio nodes: `node.disconnect()`
- [ ] Stop MediaStream tracks: `track.stop()`
- [ ] Close AudioContext: `ctx.close()`
- [ ] Break circular references

**Debug Command:**
```bash
# Profile memory
node --inspect --expose-gc your-app.js
# Then open chrome://inspect in Chrome
```

## 🎯 Performance Budget Status

| Metric | Budget | Actual | Status |
|--------|--------|--------|--------|
| Load Time | <1s | 516ms | ✅ 48% used |
| FCP | <500ms | 32ms | ✅ 6% used |
| Bundle | <100KB | 38.93KB | ✅ 39% used |
| Errors | 0 | 590 | ⛔ **VIOLATED** |
| Memory Growth | <10% | 28.52% | ⛔ **VIOLATED** |

## 🔍 Quick Diagnostic Commands

### Check for Memory Leaks
```javascript
// Add to your code
setInterval(() => {
  if (performance.memory) {
    console.log('Memory:',
      (performance.memory.usedJSHeapSize / 1024 / 1024).toFixed(2), 'MB');
  }
}, 5000);
```

### Enable Error Logging
```javascript
window.addEventListener('error', (e) => {
  console.error('Error:', e.message, e.filename, e.lineno);
});

window.addEventListener('unhandledrejection', (e) => {
  console.error('Unhandled Promise:', e.reason);
});
```

### Check AudioContext State
```javascript
console.log('AudioContext state:', audioContext.state);
// Should be: 'running', 'suspended', or 'closed'
```

## 🛠️ Common Fixes

### Fix #1: Prevent getUserMedia Errors
```javascript
// BAD
getUserMedia(userActivation).then(...)

// GOOD
try {
  const result = await getUserMedia(userActivation);
  if (result.$ === 'Ok') {
    // Handle success
  } else {
    console.error('getUserMedia failed:', result.a);
  }
} catch (error) {
  console.error('getUserMedia error:', error);
}
```

### Fix #2: Clean Up Audio Resources
```javascript
// Add cleanup function
function cleanup() {
  // Stop MediaStream tracks
  if (mediaStream) {
    mediaStream.getTracks().forEach(track => track.stop());
    mediaStream = null;
  }

  // Disconnect audio nodes
  if (streamSource) {
    streamSource.disconnect();
    streamSource = null;
  }

  if (streamDestination) {
    streamDestination.disconnect();
    streamDestination = null;
  }

  // Close AudioContext
  if (audioContext && audioContext.state !== 'closed') {
    audioContext.close();
    audioContext = null;
  }
}

// Call on unload
window.addEventListener('beforeunload', cleanup);
```

### Fix #3: Rate Limit Button Clicks
```javascript
// Simple debounce
let isProcessing = false;

async function testFullPipeline() {
  if (isProcessing) {
    console.log('Already processing, please wait...');
    return;
  }

  isProcessing = true;
  try {
    // Your test code here
  } finally {
    isProcessing = false;
  }
}
```

## 📋 Testing Checklist

Before committing code:
- [ ] Run performance test suite
- [ ] Stress test errors < 5 (currently 590)
- [ ] Memory increase < 10% (currently 28.52%)
- [ ] No console errors during normal use
- [ ] Resource cleanup on page unload
- [ ] Event listeners removed properly

## 🔄 Re-Testing After Fixes

```bash
# 1. Apply fixes
# 2. Re-run tests
npm run test:performance

# 3. Check for improvements
cat performance-results/performance-report-*.md

# 4. Look for:
#    - Errors < 5
#    - Memory increase < 10%
#    - Stable memory trend
```

## 📈 Success Criteria

**Tests pass when:**
- ✅ Page load < 1s
- ✅ Bundle size < 100KB
- ✅ Stress test errors < 5
- ✅ Memory increase < 10% over 5 min
- ✅ No long tasks > 50ms
- ✅ Memory trend: STABLE or DECREASING

## 📚 Resources

- **Full Report:** `PERFORMANCE_TEST_SUMMARY.md`
- **Testing Guide:** `PERFORMANCE_TESTING_GUIDE.md`
- **Raw Data:** `performance-results/*.json`
- **Playwright Docs:** https://playwright.dev/
- **Memory Profiling:** https://developer.chrome.com/docs/devtools/memory-problems/

## 🆘 Need Help?

1. Check console for error messages
2. Review `PERFORMANCE_TEST_SUMMARY.md` for detailed analysis
3. Use Chrome DevTools Memory Profiler
4. Check for event listener leaks: Chrome DevTools > Memory > Detached DOM

## ⚡ Quick Wins

Want to improve scores quickly?

1. **Fix errors first** (biggest impact)
   - Add error handling to getUserMedia
   - Check AudioContext state before use
   - Add rate limiting

2. **Fix memory leak** (prevents crashes)
   - Call `.disconnect()` on audio nodes
   - Call `.stop()` on media tracks
   - Call `.close()` on AudioContext

3. **Re-test and verify**
   - Run test suite again
   - Confirm errors < 5
   - Confirm memory < 10% increase

---

**Last Updated:** 2025-10-22
**Status:** 🔴 NOT PRODUCTION READY
**Action Required:** Fix critical issues above
