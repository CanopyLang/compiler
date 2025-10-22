# Audio FFI Test Execution Summary

**Quick Reference Guide for Browser Testing**

---

## Fast Stats

```
Total FFI Functions:     104
Demo Modes:             4
Interactive Controls:   27
Test Phases:           7
Estimated Time:        60 minutes
Priority Breakdown:
  - P0 Critical:       28 functions (25 min)
  - P1 High:          46 functions (20 min)
  - P2 Medium:        30 functions (15 min)
```

---

## Test Execution Order

### Phase 1: Foundation (P0) - 15 min ⚡
**Start Here - Nothing Else Works Without This**

```
1. Click page (user activation)
2. Test simpleTest(42) → expect 84
3. Create AudioContext
4. Create Oscillator (440 Hz) + Gain (0.5)
5. Connect: Oscillator → Gain → Destination
6. Start oscillator → VERIFY AUDIO PLAYS
7. Stop oscillator → VERIFY AUDIO STOPS
```

**Critical Success**: You hear a 440 Hz tone

---

### Phase 2: Real-Time Control (P0-P1) - 10 min

```
1. Play audio
2. Frequency: 100 Hz → 2000 Hz (smooth pitch change)
3. Volume: 1.0 → 0.0 (smooth fade)
4. Waveforms: sine → square → sawtooth → triangle
5. Test rampGainLinear (2 second fade)
```

**Critical Success**: All parameter changes are smooth, no clicks

---

### Phase 3: Filter Effects (P1) - 10 min

```
1. Create BiquadFilter (lowpass, 1000 Hz)
2. Test filter types:
   - Lowpass @ 500 Hz → muffled sound
   - Highpass @ 500 Hz → tinny sound
   - Bandpass @ 1000 Hz → telephone quality
   - Notch @ 1000 Hz → volume drops
3. Sweep filter frequency 20 Hz → 20000 Hz
4. Change Q: 0.1 (wide) → 10.0 (narrow/ringing)
```

**Critical Success**: Each filter type sounds distinctly different

---

### Phase 4: Spatial Audio (P1) - 10 min
**REQUIRES HEADPHONES**

```
1. Create PannerNode at (0, 0, -1)
2. X-axis: -10 (left) → 0 (center) → +10 (right)
3. Z-axis: -10 (far) → 0 (at listener) → +10 (close)
4. Circular motion: trace circle around listener
```

**Critical Success**: Clear stereo positioning with headphones

---

### Phase 5: Analysis (P1) - 5 min

```
1. Create AnalyserNode (FFT 2048)
2. Get time domain data → verify array length 2048
3. Play 440 Hz sine → verify peak at correct bin
4. Test FFT sizes: 256, 512, 1024, 2048, 4096
```

**Critical Success**: Data arrays have correct length and expected patterns

---

### Phase 6: Advanced (P2) - 10 min

```
1. BufferSource: create buffer, play, test loop
2. Delay: create 0.5s delay with feedback
3. Compressor: test -20 dB threshold
4. StereoPanner: test -1.0 (left) to +1.0 (right)
```

**Critical Success**: All advanced nodes function correctly

---

### Phase 7: Error Handling (P1) - 5 min

```
1. Refresh page
2. Try playing without init → verify error message
3. Try invalid params → verify error/clamp
4. Double-start oscillator → verify error
5. Follow error instructions → verify recovery
```

**Critical Success**: All errors caught and reported clearly

---

## One-Command Test

Open browser console and run:

```javascript
// Quick validation (requires user click first)
async function quickTest() {
  const r = [];

  // Test 1: FFI
  try {
    r.push({test: "FFI", pass: window.AudioFFI.simpleTest(42) === 84});
  } catch(e) { r.push({test: "FFI", pass: false, error: e.message}); }

  // Test 2: Support
  try {
    const s = window.AudioFFI.checkWebAudioSupport();
    r.push({test: "Support", pass: s.includes("supported"), info: s});
  } catch(e) { r.push({test: "Support", pass: false, error: e.message}); }

  // Test 3: Context
  try {
    const c = window.AudioFFI.createAudioContextSimplified();
    r.push({test: "Context", pass: c.includes("success"), info: c});
  } catch(e) { r.push({test: "Context", pass: false, error: e.message}); }

  console.table(r);
  const passed = r.filter(x => x.pass).length;
  console.log(`Result: ${passed}/${r.length} tests passed`);
  return r;
}

// Click page, then run: quickTest()
```

---

## Demo Mode Quick Reference

### Mode 1: SimplifiedInterface
**What**: Easy string-based API
**Test**: All basic controls (freq, vol, waveform)
**Time**: 5 minutes

### Mode 2: TypeSafeInterface
**What**: Result-based production API
**Test**: Step-by-step: Context → Nodes → Connect → Play
**Time**: 5 minutes

### Mode 3: ComparisonMode
**What**: Side-by-side comparison
**Test**: Verify both work identically
**Time**: 2 minutes

### Mode 4: AdvancedFeatures
**What**: Filters + Spatial audio
**Test**: All filter types + 3D positioning
**Time**: 15 minutes

---

## Common Issues Quick Fix

### No Sound?
1. Check browser console for errors
2. Check system volume (not muted)
3. Click page before initializing (user activation)
4. Check AudioContext state (should be "running", not "suspended")

### CORS Errors?
```bash
# NEVER use file:// protocol
# ALWAYS use HTTP server:
cd examples/audio-ffi
python3 -m http.server 8000
open http://localhost:8000
```

### Distorted Audio?
- Lower volume (gain > 1.0 causes clipping)
- Check CPU usage (close other tabs if high)

### Safari Not Working?
```javascript
// Run in console:
audioContext.resume().then(() => console.log("Resumed"));
```

---

## Success Checklist

**Must Pass (P0)**
- [ ] Audio plays at 440 Hz
- [ ] Frequency changes work
- [ ] Volume changes work
- [ ] Waveform changes work
- [ ] Audio stops cleanly
- [ ] No console errors

**Should Pass (P1)**
- [ ] Filters are audible
- [ ] Spatial positioning works
- [ ] Analyser provides data
- [ ] Parameter ramping smooth

**Nice to Have (P2)**
- [ ] Compressor works
- [ ] AudioWorklet loads
- [ ] Offline rendering works

---

## Expected Performance

```
CPU Usage:
  Idle:              < 1%
  Basic playback:    1-3%
  With filter:       3-7%
  With spatial:      5-10%
  Full setup:        8-15%

Memory:
  Initial:           2-5 MB
  After 30s:         < 10% growth
  After 5 min:       Stable (no leaks)

Latency:
  Click to audio:    < 100ms
  Parameter change:  < 50ms
  Stop to silence:   < 10ms
```

---

## Browser Support Matrix

| Feature | Chrome | Firefox | Safari | Edge |
|---------|--------|---------|--------|------|
| AudioContext | ✅ | ✅ | ✅ | ✅ |
| Oscillator | ✅ | ✅ | ✅ | ✅ |
| Filters | ✅ | ✅ | ✅ | ✅ |
| Spatial | ✅ | ✅ | ✅ | ✅ |
| AudioWorklet | ✅ | ✅ 76+ | ⚠️ 14.1+ | ✅ |

---

## Test Values Quick Reference

**Frequencies**: 100 Hz (bass), 440 Hz (A4), 1000 Hz (reference), 2000 Hz (treble)
**Volumes**: 0.0 (silence), 0.5 (normal), 1.0 (max)
**Pan**: -1.0 (full left), 0.0 (center), +1.0 (full right)
**Spatial X**: -10 (left), 0 (center), +10 (right)
**Spatial Z**: -10 (far), 0 (at listener), +10 (close)
**Filter Q**: 0.1 (wide), 1.0 (normal), 10.0 (narrow/ringing)

---

## Category Overview (All 104 Functions)

```
1.  Audio Context         (7)   P0  - createAudioContext, getCurrentTime...
2.  Oscillator           (5)   P0  - createOscillator, startOscillator...
3.  Gain                 (4)   P0  - createGainNode, setGain, ramp...
4.  Buffer Source        (9)   P1  - createBufferSource, setLoop...
5.  Filter               (4)   P1  - createBiquadFilter, setFrequency...
6.  Delay                (2)   P1  - createDelay, setDelayTime
7.  Compressor           (6)   P2  - createCompressor, setThreshold...
8.  Stereo Panner        (2)   P1  - createStereoPanner, setPan
9.  Effect Nodes         (4)   P2  - Convolver, WaveShaper
10. Analyser             (8)   P1  - createAnalyser, getFrequencyData...
11. 3D Panner           (11)   P1  - createPanner, setPosition...
12. Audio Listener       (4)   P2  - getListener, setPosition...
13. Channel Routing      (2)   P2  - Splitter, Merger
14. Audio Buffer         (5)   P1  - createBuffer, getLength...
15. Connections          (3)   P0  - connectNodes, connectToDestination
16. Simplified API       (8)   P0  - simpleTest, playToneSimplified...
17. Param Automation     (9)   P2  - getParam, setValueAtTime...
18. MediaStream          (3)   P2  - createStreamSource, getStream...
19. AudioWorklet         (5)   P2  - addModule, createWorkletNode...
20. Offline Context      (3)   P2  - createOffline, startRendering...
```

---

## Final Note

This is a **complete** specification. All 104 functions are documented with:
- Exact type signatures
- Expected behaviors
- Test priorities
- Dependencies
- Success criteria

See `COMPREHENSIVE_TEST_SPECIFICATION.md` for full details.

**Ready to test!** Start with Phase 1 and work through sequentially.
