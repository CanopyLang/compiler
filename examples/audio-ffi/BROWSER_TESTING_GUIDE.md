# Browser Testing Guide for Audio FFI Example

This guide provides complete instructions for testing the Canopy Web Audio API FFI implementation in a browser environment.

## Quick Start

### Option 1: Direct File Access (May Have CORS Issues)

```bash
# Open directly in default browser
open examples/audio-ffi/index.html

# Or manually open in specific browser
# Chrome: Right-click index.html → Open With → Google Chrome
# Firefox: Right-click index.html → Open With → Firefox
# Safari: Right-click index.html → Open With → Safari
```

**⚠️ Note**: Modern browsers block file:// access to external JavaScript files for security. If you see CORS errors in console, use Option 2.

### Option 2: Local HTTP Server (Recommended)

```bash
# Navigate to audio-ffi directory
cd examples/audio-ffi

# Start Python HTTP server (Python 3)
python3 -m http.server 8000

# Or Python 2
python -m SimpleHTTPServer 8000

# Or use Node.js http-server
npx http-server -p 8000

# Then open in browser
open http://localhost:8000
```

## Testing Checklist

### 1. Basic Audio Interface (Simplified)

This tests the high-level, user-friendly audio API.

#### Initialization
- [ ] **Click "Initialize Audio"**
  - Expected: "Audio initialized successfully!" message appears in green
  - Console: Should show "Audio initialized"
  - If fails: May need user interaction first (click anywhere on page)

#### Basic Playback
- [ ] **Click "Play Audio"**
  - Expected: Hear a steady tone at 440 Hz (musical note A4)
  - Duration: Continuous until stopped
  - Volume: Should be audible but not too loud
  - Console: "Audio started"

- [ ] **Click "Stop Audio"**
  - Expected: Tone stops immediately
  - No residual sound or clicks
  - Console: "Audio stopped"

#### Real-Time Parameter Control

- [ ] **Frequency Slider** (Range: 100-2000 Hz)
  - Start audio playing
  - Move slider slowly from left to right
  - Expected: Pitch smoothly rises from low to high
  - At 100 Hz: Deep, bass-like tone
  - At 440 Hz: Middle A note (default)
  - At 1000 Hz: High-pitched tone
  - At 2000 Hz: Very high-pitched tone
  - Changes should be smooth, no clicking or popping

- [ ] **Volume Slider** (Range: 0.0-1.0)
  - Start audio playing
  - Move slider from right to left
  - Expected: Volume smoothly decreases to silence
  - At 1.0: Full volume
  - At 0.5: Half volume
  - At 0.0: Complete silence
  - No distortion at any volume level

- [ ] **Waveform Selection** (Dropdown)
  - Start audio playing at 440 Hz
  - Test each waveform type:
    - **Sine**: Pure, smooth tone (like a tuning fork)
    - **Square**: Harsh, hollow tone (like old video games)
    - **Sawtooth**: Bright, buzzy tone (like a brass instrument)
    - **Triangle**: Soft, flute-like tone (between sine and square)
  - Expected: Immediate change in tone character
  - Frequency and volume should remain constant

### 2. Type-Safe Interface (Advanced)

This tests the low-level, type-safe FFI with explicit Result types.

#### Context Creation
- [ ] **Click "Create AudioContext"**
  - Expected: Status shows "AudioContext: Initialized"
  - Console: "Created AudioContext"
  - State indicator changes from red to green

#### Node Creation
- [ ] **Click "Create Oscillator & Gain"**
  - Expected: Two status lines appear:
    - "OscillatorNode: Created"
    - "GainNode: Created"
  - Console: "Created OscillatorNode" and "Created GainNode"
  - Must be done after AudioContext creation

#### Audio Playback
- [ ] **Click "Start Audio"**
  - Expected: Tone plays at 440 Hz
  - Status: "Audio: Playing"
  - Console: "Started audio"
  - Must have created nodes first

- [ ] **Click "Stop Audio"**
  - Expected: Tone stops
  - Status: "Audio: Stopped"
  - Console: "Stopped audio"

#### Result Type Verification
- [ ] **Check Operation Log**
  - Each operation should show Result type:
    - `Ok: [value]` for success
    - `Err: [message]` for failure
  - Example: "Create Context → Ok: AudioContext"

### 3. Advanced Features - Filter Effects

This tests the BiquadFilterNode API for frequency filtering.

#### Filter Initialization
- [ ] **Toggle "Filter Effects" Section**
  - Click to expand filter controls
  - Expected: Three sliders and type selector appear

- [ ] **Click "Create Filter Node"**
  - Expected: "FilterNode: Created" status
  - Console: "Created BiquadFilterNode"
  - Must have AudioContext and audio nodes created

#### Filter Types

- [ ] **Lowpass Filter**
  - Select "lowpass" from dropdown
  - Start audio at 1000 Hz
  - Set filter frequency to 500 Hz
  - Expected: Muffled sound (high frequencies removed)
  - Increase cutoff: Sound becomes brighter
  - Decrease cutoff: Sound becomes darker

- [ ] **Highpass Filter**
  - Select "highpass" from dropdown
  - Start audio at 1000 Hz
  - Set filter frequency to 500 Hz
  - Expected: Thin, tinny sound (low frequencies removed)
  - Increase cutoff: Sound becomes thinner
  - Decrease cutoff: Sound becomes fuller

- [ ] **Bandpass Filter**
  - Select "bandpass" from dropdown
  - Start audio at 1000 Hz
  - Set filter frequency to 1000 Hz
  - Expected: Telephone-like quality (only middle frequencies)
  - Adjust Q: Narrows or widens the frequency band

- [ ] **Notch Filter**
  - Select "notch" from dropdown
  - Start audio at 1000 Hz
  - Set filter frequency to 1000 Hz
  - Expected: Volume drops dramatically at 1000 Hz
  - Move away from 1000 Hz: Sound returns

#### Filter Parameters

- [ ] **Filter Frequency Slider** (20-20000 Hz)
  - Start audio with lowpass filter at 1000 Hz
  - Move slider left to right
  - Expected: Gradual opening of high frequencies
  - At 20 Hz: Almost complete silence
  - At 5000 Hz: Bright, full sound
  - At 20000 Hz: No filtering (full spectrum)

- [ ] **Filter Q Slider** (0.1-10.0)
  - Use bandpass filter at 1000 Hz
  - Set Q to 0.1: Wide, gentle filter
  - Set Q to 5.0: Narrow, sharp filter
  - Set Q to 10.0: Very narrow, ringing filter
  - Expected: Dramatic change in filter character

- [ ] **Filter Gain Slider** (-40 to +40 dB)
  - Only affects peaking, lowshelf, highshelf types
  - Use peaking filter at 1000 Hz
  - Set gain to +20 dB: Frequency boost
  - Set gain to -20 dB: Frequency cut
  - Expected: Volume change at filter frequency

### 4. Advanced Features - 3D Spatial Audio

This tests the PannerNode API for spatial positioning.

#### Spatial Initialization
- [ ] **Toggle "Spatial Audio (3D)" Section**
  - Click to expand spatial controls
  - Expected: Three position sliders appear

- [ ] **Click "Create Panner Node"**
  - Expected: "PannerNode: Created" status
  - Console: "Created PannerNode"
  - Must have AudioContext and audio nodes created

#### Position Testing

**⚠️ Best tested with headphones for accurate spatial perception**

- [ ] **X-Axis Slider** (-10 to +10, Left-Right)
  - Start audio playing
  - Set X to -10: Sound in left ear/speaker
  - Set X to 0: Sound centered
  - Set X to +10: Sound in right ear/speaker
  - Expected: Smooth panning from left to right
  - Use headphones to verify proper stereo imaging

- [ ] **Y-Axis Slider** (-10 to +10, Down-Up)
  - Start audio playing
  - Set Y to -10: Sound appears lower
  - Set Y to 0: Sound at neutral height
  - Set Y to +10: Sound appears higher
  - Expected: Subtle timbral changes
  - Effect more noticeable with complex sounds

- [ ] **Z-Axis Slider** (-10 to +10, Behind-Front)
  - Start audio playing
  - Set Z to -10: Sound appears behind listener
  - Set Z to 0: Sound at listener position
  - Set Z to +10: Sound appears in front
  - Expected: Volume and frequency changes
  - At -10: Quieter, more distant
  - At +10: Louder, more present

#### Combined Spatial Effects
- [ ] **Circular Motion**
  - Start audio at 440 Hz
  - Slowly move X from -10 to +10
  - Simultaneously move Z from +10 to -10
  - Expected: Sound circles around listener
  - Smooth, continuous spatial movement

### 5. Error Handling

This verifies that errors are caught and reported properly.

#### Order of Operations Errors
- [ ] **Try Playing Before Initialization**
  - Refresh page (clear all state)
  - Click "Play Audio" immediately
  - Expected: Error message in red
  - Message: "Audio not initialized" or similar
  - No JavaScript exceptions in console

- [ ] **Try Creating Nodes Before Context**
  - Refresh page
  - Click "Create Oscillator & Gain"
  - Expected: Error about missing AudioContext
  - Console: Proper error message, not crash

#### Invalid Parameter Errors
- [ ] **Check Operation Log**
  - Every failed operation should show:
    - Clear error message
    - Err Result type
    - Helpful suggestion for fix
  - Example: "Create Oscillator → Err: No AudioContext"

#### Recovery Testing
- [ ] **Error Recovery Flow**
  - Trigger an error (e.g., play before init)
  - Follow error message instructions
  - Initialize properly
  - Try operation again
  - Expected: Operation succeeds after proper setup

## Browser Compatibility

### Fully Supported Browsers

| Browser | Minimum Version | Release Date | Notes |
|---------|----------------|--------------|-------|
| Chrome | 66+ | April 2018 | Full Web Audio API support |
| Firefox | 76+ | May 2020 | AudioWorklet support added |
| Safari | 14.1+ | April 2021 | Full spatial audio support |
| Edge | 79+ | January 2020 | Chromium-based Edge |
| Opera | 53+ | May 2018 | Chromium-based |

### Feature Support by Browser

| Feature | Chrome | Firefox | Safari | Edge |
|---------|--------|---------|--------|------|
| AudioContext | ✅ | ✅ | ✅ | ✅ |
| OscillatorNode | ✅ | ✅ | ✅ | ✅ |
| GainNode | ✅ | ✅ | ✅ | ✅ |
| BiquadFilterNode | ✅ | ✅ | ✅ | ✅ |
| PannerNode | ✅ | ✅ | ✅ | ✅ |
| AudioWorklet | ✅ | ✅ | ⚠️ 14.1+ | ✅ |

### Known Browser Issues

#### Safari
- Requires user interaction before AudioContext activation
- May show "suspended" state initially (click page to activate)
- Spatial audio may have slightly different HRTF implementation

#### Firefox
- Older versions (<76) lack AudioWorklet support
- Filter Q parameter may have different scaling

#### Mobile Browsers
- iOS Safari: Requires explicit play() call after user tap
- Android Chrome: May have higher latency
- Background tab audio may be suspended for battery saving

### Testing on Mobile

```bash
# Use your computer's IP address
python3 -m http.server 8000

# On mobile browser, navigate to:
http://[YOUR_IP]:8000

# Example: http://192.168.1.100:8000
```

## Performance Testing

### CPU Usage Monitoring

#### Chrome DevTools
1. Open DevTools (F12 or Cmd+Option+I)
2. Go to "Performance" tab
3. Click record button (●)
4. Interact with audio (play, change parameters)
5. Stop recording after 10 seconds
6. Analyze CPU usage:
   - **Basic synthesis**: 1-5% CPU
   - **With filter**: 3-7% CPU
   - **With spatial audio**: 5-10% CPU
   - **All effects**: 8-15% CPU

#### Expected Performance
- **Idle** (no audio): <1% CPU
- **Single oscillator**: 1-3% CPU
- **Oscillator + filter**: 3-5% CPU
- **Full setup** (osc + filter + panner): 5-10% CPU
- **Multiple voices** (4 oscillators): 10-20% CPU

### Memory Usage Monitoring

#### Chrome DevTools Memory Tab
1. Open DevTools → "Memory" tab
2. Select "Heap snapshot"
3. Click "Take snapshot" (with audio stopped)
4. Start audio and wait 30 seconds
5. Take another snapshot
6. Compare memory usage:
   - Initial snapshot: ~2-5 MB
   - After 30s playing: Should be within 10% of initial
   - After 5 minutes: No significant growth

#### Memory Leak Detection
```javascript
// Run in browser console while audio playing
let snapshots = [];
for (let i = 0; i < 10; i++) {
  await new Promise(r => setTimeout(r, 5000));
  snapshots.push(performance.memory.usedJSHeapSize);
}
console.log("Heap sizes:", snapshots);
// Should be relatively stable, not growing linearly
```

### Audio Glitch Detection

#### Listen for Artifacts
- [ ] **No clicking or popping** when changing parameters
- [ ] **No dropouts** during continuous playback
- [ ] **Smooth transitions** between waveforms
- [ ] **Clean silence** when stopped (no residual noise)

#### Buffer Underrun Check
Open console and check for warnings:
- "AudioContext buffer underrun"
- "Glitch detected in audio rendering"

If glitches occur:
- Reduce browser load (close other tabs)
- Check system CPU usage
- Try increasing buffer size (advanced)

## Troubleshooting

### No Sound

#### Checklist
1. **Browser Console Errors**
   - Open DevTools (F12)
   - Check Console tab for red errors
   - Look for "AudioContext" or "NotAllowedError"

2. **AudioContext State**
   - Check status indicator
   - Should show "running", not "suspended"
   - If suspended: Click page, then try again

3. **System Audio**
   - Check computer volume (not muted)
   - Check browser tab is not muted (right-click tab)
   - Try playing YouTube/Spotify to verify audio works

4. **User Activation**
   - Many browsers require user gesture before audio
   - Click anywhere on page before initializing
   - Reload page and click "Initialize Audio" immediately

#### Safari-Specific No Sound
```javascript
// Check AudioContext state in console
console.log(audioContext.state);
// If "suspended":
audioContext.resume().then(() => console.log("Resumed!"));
```

### CORS Errors

#### Symptoms
- Console shows: "Cross-Origin Request Blocked"
- Status: "Failed to load resource"
- Audio files or JS files not loading

#### Solution
```bash
# NEVER use file:// protocol
# ❌ file:///Users/you/canopy/examples/audio-ffi/index.html

# ✅ ALWAYS use HTTP server
cd examples/audio-ffi
python3 -m http.server 8000
open http://localhost:8000
```

### FFI Errors

#### "Capability not found"
- **Cause**: external/audio.js not loaded
- **Fix**: Check network tab, verify audio.js loads
- **Verify**: `window.AudioCapability` should exist in console

#### "Cannot read property 'createOscillator' of undefined"
- **Cause**: AudioContext not created properly
- **Fix**: Click "Create AudioContext" before other operations
- **Verify**: Check status shows "AudioContext: Initialized"

#### "Result type mismatch"
- **Cause**: FFI returning unexpected type
- **Fix**: Check console for detailed error
- **Report**: This may be a bug - note the exact operation

### Distorted Audio

#### Clipping (Distortion at High Volume)
- **Cause**: Gain too high (>1.0)
- **Fix**: Reduce volume slider
- **Prevent**: Set maximum gain to 0.8 in production

#### Aliasing (High-Frequency Artifacts)
- **Cause**: Sample rate issues
- **Not fixable**: Browser limitation
- **Workaround**: Use lower frequencies (<5000 Hz)

### Performance Issues

#### High CPU Usage
- **Normal**: 5-15% CPU for full audio setup
- **High**: >30% CPU indicates problem
- **Solutions**:
  - Close other browser tabs
  - Disable browser extensions
  - Update graphics drivers
  - Use hardware acceleration (chrome://settings → "System")

#### Stuttering Audio
- **Cause**: CPU overload or buffer underruns
- **Solutions**:
  - Reduce simultaneous audio nodes
  - Simplify filter settings
  - Close resource-heavy applications
  - Check for system updates

## Expected Results Reference

### Visual Indicators

#### Successful Initialization
```
Status Display:
┌─────────────────────────────────┐
│ ✓ AudioContext: Initialized      │
│ ✓ OscillatorNode: Created        │
│ ✓ GainNode: Created              │
│ ▶ Audio: Playing at 440 Hz       │
└─────────────────────────────────┘
```

#### Error State
```
Status Display:
┌─────────────────────────────────┐
│ ✗ Error: AudioContext not found  │
│ → Please create AudioContext     │
│   before creating nodes          │
└─────────────────────────────────┘
```

### Console Output Examples

#### Successful Flow
```
[AudioFFI] Initialized AudioContext
[AudioFFI] Created OscillatorNode (sine, 440 Hz)
[AudioFFI] Created GainNode (volume: 0.5)
[AudioFFI] Connected: Oscillator → Gain → Destination
[AudioFFI] Started oscillator
```

#### Error Flow
```
[AudioFFI] Error: Attempted to create oscillator without context
[AudioFFI] Hint: Call createAudioContext() first
```

## Common Testing Pitfalls

### 1. Testing Too Quickly
**Problem**: Clicking buttons rapidly before audio initializes
**Result**: Errors due to race conditions
**Solution**: Wait for status indicators to update between operations

### 2. Not Using Headphones
**Problem**: Testing spatial audio with laptop speakers
**Result**: Can't perceive 3D positioning
**Solution**: Use quality headphones for spatial tests

### 3. Ignoring Console
**Problem**: Only looking at UI, missing error details
**Result**: Can't diagnose failures
**Solution**: Keep DevTools console open during all testing

### 4. Not Testing Edge Cases
**Problem**: Only testing "happy path"
**Result**: Bugs in error handling
**Solution**: Deliberately trigger errors (play before init, etc.)

### 5. Testing Only One Browser
**Problem**: Assuming all browsers behave the same
**Result**: Safari/Firefox bugs not caught
**Solution**: Test on Chrome, Firefox, Safari minimum

## Automated Testing Scripts

### Quick Validation Script

Run in browser console:

```javascript
// Automated test sequence
async function runTests() {
  const results = [];

  // Test 1: Initialization
  try {
    window.initializeAudio();
    await new Promise(r => setTimeout(r, 100));
    results.push({test: "Init", status: "✅ Pass"});
  } catch(e) {
    results.push({test: "Init", status: "❌ Fail: " + e});
  }

  // Test 2: Play audio
  try {
    window.playAudio();
    await new Promise(r => setTimeout(r, 500));
    results.push({test: "Play", status: "✅ Pass"});
  } catch(e) {
    results.push({test: "Play", status: "❌ Fail: " + e});
  }

  // Test 3: Change frequency
  try {
    window.setFrequency(880);
    await new Promise(r => setTimeout(r, 200));
    results.push({test: "Frequency", status: "✅ Pass"});
  } catch(e) {
    results.push({test: "Frequency", status: "❌ Fail: " + e});
  }

  // Test 4: Stop
  try {
    window.stopAudio();
    await new Promise(r => setTimeout(r, 100));
    results.push({test: "Stop", status: "✅ Pass"});
  } catch(e) {
    results.push({test: "Stop", status: "❌ Fail: " + e});
  }

  console.table(results);
  return results;
}

// Run tests
runTests();
```

## Reporting Issues

When reporting bugs, include:

1. **Browser**: Name and exact version
2. **OS**: Operating system and version
3. **Steps**: Exact sequence to reproduce
4. **Expected**: What should happen
5. **Actual**: What actually happened
6. **Console**: Copy full console output
7. **Screenshot**: Visual evidence of issue

Example bug report:
```
Browser: Chrome 120.0.6099.129 (Official Build) (arm64)
OS: macOS 14.2.1 (Sonoma)
Steps:
  1. Open http://localhost:8000
  2. Click "Initialize Audio"
  3. Click "Create Oscillator & Gain"
  4. Click "Start Audio"
Expected: Audio plays at 440 Hz
Actual: No sound, console shows "AudioContext is null"
Console output:
  [Error] Uncaught TypeError: Cannot read property 'createOscillator' of null
      at startAudio (main.js:45)
Screenshot: [attached]
```

## Success Criteria

A successful test session should verify:

✅ All basic operations work (init, play, stop)
✅ Real-time parameter changes are smooth
✅ All waveforms sound different
✅ Filter effects audibly change the sound
✅ Spatial positioning affects stereo image
✅ Error messages are clear and helpful
✅ No console errors during normal operation
✅ CPU usage remains reasonable (<15%)
✅ Memory usage stays stable over time
✅ Works in Chrome, Firefox, and Safari

## Additional Resources

- [Web Audio API Specification](https://www.w3.org/TR/webaudio/)
- [MDN Web Audio Guide](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API)
- [Can I Use - Web Audio](https://caniuse.com/audio-api)
- [Chrome Audio Debugging](https://developer.chrome.com/docs/devtools/media-panel/)

---

**Version**: 1.0.0
**Last Updated**: 2025-10-22
**Tested Browsers**: Chrome 120, Firefox 121, Safari 17
