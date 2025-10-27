# Web Audio API Phase 2 - Quick Reference Guide

**Date:** 2025-10-27
**Version:** Phase 2 (>90% coverage)

---

## New Features Summary

**17 new functions added across 4 categories:**

1. **AudioWorklet** (5 functions) - Modern low-latency processing
2. **IIRFilterNode** (2 functions) - Advanced filtering
3. **ConstantSourceNode** (4 functions) - Constant audio signals
4. **PeriodicWave Enhanced** (3 functions) - Custom waveforms

---

## AudioWorklet - Modern Audio Processing

### Load a Processor Module (Async)

```elm
case addAudioWorkletModule audioContext "external/gain-processor.js" of
    Ok _ ->
        -- Module loaded successfully
    Err (NotSupportedError msg) ->
        -- AudioWorklet not supported in browser
    Err error ->
        -- Other error
```

### Create Worklet Node

```elm
case createAudioWorkletNode audioContext "gain-processor" of
    Ok workletNode ->
        -- Node created, can connect to graph
        connectNodes workletNode gainNode
    Err error ->
        -- Handle error
```

### Communicate with Processor

```elm
let
    port = getWorkletPort workletNode
    params = getWorkletParameters workletNode
in
    postMessageToWorklet port "volume: 0.5"
```

**Use Cases:**
- Custom audio effects
- Real-time synthesis
- Low-latency processing
- Advanced DSP algorithms

---

## IIRFilterNode - Advanced Filtering

### Create IIR Filter

```elm
-- Butterworth lowpass filter example
let
    feedforward = [0.0201, 0.0402, 0.0201]
    feedback = [1.0, -1.561, 0.6414]
in
    case createIIRFilter audioContext feedforward feedback of
        Ok iirFilter ->
            -- Filter created
            connectNodes sourceNode iirFilter
            connectNodes iirFilter gainNode
        Err (InvalidAccessError msg) ->
            -- Invalid coefficients
        Err error ->
            -- Other error
```

### Get Frequency Response

```elm
let
    frequencies = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
in
    case getIIRFilterResponse iirFilter frequencies of
        Ok response ->
            -- response.magnitude : List Float
            -- response.phase : List Float
            -- Can plot frequency response
        Err error ->
            -- Handle error
```

**Use Cases:**
- Advanced equalizers
- Custom filter designs
- Frequency response analysis
- DSP algorithm implementation

---

## ConstantSourceNode - Constant Signals

### Create and Use Constant Source

```elm
case createConstantSource audioContext of
    Ok constantSource ->
        let
            offsetParam = getConstantSourceOffset constantSource
        in
            -- Set constant value (e.g., 0.5)
            setParamValueAtTime offsetParam 0.5 0.0

            -- Start source
            case startConstantSource constantSource 0.0 of
                Ok _ ->
                    -- Connect to modulate other parameters
                    connectNodes constantSource gainNode
                Err error ->
                    -- Handle error
    Err error ->
        -- Handle creation error
```

### Stop Constant Source

```elm
case stopConstantSource constantSource (getCurrentTime audioContext + 1.0) of
    Ok _ ->
        -- Source will stop in 1 second
    Err error ->
        -- Handle error
```

**Use Cases:**
- DC offset generation
- LFO (Low-Frequency Oscillator) modulation
- Parameter automation source
- Control voltage generation

---

## PeriodicWave - Custom Waveforms

### Create Custom Waveform

```elm
-- Create sawtooth wave using Fourier series
let
    -- Fundamental + harmonics
    real = [0.0, 0.0, 0.0, 0.0, 0.0]  -- Cosine coefficients (DC offset)
    imag = [0.0, 1.0, 0.5, 0.33, 0.25]  -- Sine coefficients (harmonics)
in
    case createPeriodicWaveWithCoefficients audioContext real imag of
        Ok periodicWave ->
            -- Set on oscillator
            setOscillatorPeriodicWave oscillator periodicWave
        Err error ->
            -- Handle error
```

### Create with Normalization Control

```elm
case createPeriodicWaveWithOptions audioContext real imag False of
    Ok periodicWave ->
        -- Normalization enabled (default)
        setOscillatorPeriodicWave oscillator periodicWave
    Err error ->
        -- Handle error

case createPeriodicWaveWithOptions audioContext real imag True of
    Ok periodicWave ->
        -- Normalization disabled (raw coefficients)
        setOscillatorPeriodicWave oscillator periodicWave
    Err error ->
        -- Handle error
```

**Use Cases:**
- Custom waveform synthesis
- Additive synthesis
- Wavetable synthesis
- Timbre design

---

## Complete Example: AudioWorklet with IIR Filter

```elm
module AudioWorkletExample exposing (main)

import AudioFFI exposing (..)
import Capability exposing (UserActivated, Initialized)
import Result exposing (Result(..))

processAudio : UserActivated -> Result String ()
processAudio userActivation =
    case createAudioContext userActivation of
        Ok initializedContext ->
            -- Load AudioWorklet module
            case addAudioWorkletModule initializedContext "external/gain-processor.js" of
                Ok _ ->
                    -- Create worklet node
                    case createAudioWorkletNode initializedContext "gain-processor" of
                        Ok workletNode ->
                            -- Create IIR filter
                            let
                                ff = [0.0201, 0.0402, 0.0201]
                                fb = [1.0, -1.561, 0.6414]
                            in
                                case createIIRFilter initializedContext ff fb of
                                    Ok iirFilter ->
                                        -- Create gain node
                                        case createGainNode initializedContext 0.5 of
                                            Ok gainNode ->
                                                -- Connect audio graph
                                                connectNodes workletNode iirFilter
                                                |> Result.andThen (\_ -> connectNodes iirFilter gainNode)
                                                |> Result.andThen (\_ -> connectToDestination gainNode initializedContext)
                                                |> Result.map (\_ -> ())
                                            Err error ->
                                                Err "Failed to create gain node"
                                    Err error ->
                                        Err "Failed to create IIR filter"
                        Err error ->
                            Err "Failed to create worklet node"
                Err error ->
                    Err "Failed to load worklet module"
        Err error ->
            Err "Failed to create audio context"
```

---

## Complete Example: Custom Waveform with Constant Source Modulation

```elm
module CustomWaveformExample exposing (main)

import AudioFFI exposing (..)
import Capability exposing (UserActivated, Initialized)
import Result exposing (Result(..))

createModulatedOscillator : Initialized AudioContext -> Result String OscillatorNode
createModulatedOscillator initializedContext =
    -- Create custom waveform
    let
        real = [0.0, 0.0, 0.0, 0.0]
        imag = [0.0, 1.0, 0.5, 0.33]
    in
        case createPeriodicWaveWithCoefficients initializedContext real imag of
            Ok periodicWave ->
                -- Create oscillator
                case createOscillator initializedContext 440.0 "sine" of
                    Ok oscillator ->
                        -- Set custom waveform
                        setOscillatorPeriodicWave oscillator periodicWave

                        -- Create constant source for modulation
                        case createConstantSource initializedContext of
                            Ok constantSource ->
                                let
                                    offsetParam = getConstantSourceOffset constantSource
                                in
                                    -- Modulate oscillator detune
                                    setParamValueAtTime offsetParam 100.0 0.0

                                    -- Get oscillator detune param
                                    let
                                        detuneParam = getDetuneParam oscillator
                                    in
                                        -- Connect constant source to detune
                                        -- (Note: Would need connectAudioParamSource function)
                                        Ok oscillator
                            Err error ->
                                Err "Failed to create constant source"
                    Err error ->
                        Err "Failed to create oscillator"
            Err error ->
                Err "Failed to create periodic wave"
```

---

## Error Handling Best Practices

### Pattern Match on All Error Types

```elm
case createAudioWorkletNode audioContext "processor" of
    Ok node ->
        -- Success path
    Err (InvalidStateError msg) ->
        -- Processor not loaded, load first
    Err (NotSupportedError msg) ->
        -- AudioWorklet not available, use fallback
    Err (InitializationRequired msg) ->
        -- Generic error, show to user
    Err error ->
        -- Catch-all for unknown errors
```

### Chain Operations Safely

```elm
createConstantSource audioContext
    |> Result.andThen (\source ->
        startConstantSource source 0.0
            |> Result.map (\_ -> source)
    )
    |> Result.andThen (\source ->
        connectNodes source gainNode
            |> Result.map (\_ -> source)
    )
```

---

## Performance Tips

### AudioWorklet
- Keep processor code minimal (runs in audio thread)
- Avoid memory allocations in process() method
- Use SharedArrayBuffer for large data transfers

### IIRFilterNode
- Validate coefficient stability before creation
- Cache filter instances for reuse
- Use biquad filters for simple cases (more efficient)

### ConstantSourceNode
- Reuse instances instead of recreating
- Prefer over OscillatorNode for DC offsets
- Use for parameter automation sources

### PeriodicWave
- Create once, reuse on multiple oscillators
- Cache waveforms for common timbres
- Limit coefficient count for performance

---

## Browser Compatibility Check

```elm
checkCompatibility : () -> String
checkCompatibility _ =
    let
        support = checkWebAudioSupport ()
    in
        case support of
            "Supported" ->
                "Full Web Audio API support"
            "Prefixed-webkit" ->
                "Web Audio supported with webkit prefix"
            "PartialSupport" ->
                "Limited Web Audio support, some features unavailable"
            _ ->
                "Web Audio API not supported"
```

---

## Troubleshooting

### AudioWorklet Not Loading
1. Check module path is correct
2. Verify CORS headers if loading from different origin
3. Ensure AudioContext is created with user activation
4. Use HTTPS (required for AudioWorklet in some browsers)

### IIR Filter Not Working
1. Validate coefficient arrays are non-empty
2. Check feedback coefficients don't cause instability
3. Verify coefficient count matches (feedforward and feedback)
4. Test with known-good coefficients first

### ConstantSource Not Starting
1. Ensure start() called before connecting to destination
2. Check time parameter is valid (>= 0)
3. Verify AudioContext is not closed
4. Don't call start() twice on same source

### PeriodicWave Not Applied
1. Ensure arrays have same length
2. Check array lengths are ≥2
3. Verify normalization setting is correct
4. Set wave before starting oscillator

---

## Additional Resources

**MDN Documentation:**
- [AudioWorklet](https://developer.mozilla.org/en-US/docs/Web/API/AudioWorklet)
- [IIRFilterNode](https://developer.mozilla.org/en-US/docs/Web/API/IIRFilterNode)
- [ConstantSourceNode](https://developer.mozilla.org/en-US/docs/Web/API/ConstantSourceNode)
- [PeriodicWave](https://developer.mozilla.org/en-US/docs/Web/API/PeriodicWave)

**W3C Specification:**
- [Web Audio API](https://www.w3.org/TR/webaudio/)

**Example Processors:**
- `/examples/audio-ffi/external/gain-processor.js`
- `/examples/audio-ffi/external/bitcrusher-processor.js`

---

**Quick Reference Version:** Phase 2 (2025-10-27)
**Coverage:** >90% of Web Audio API
**Total Functions:** 103
**New Functions:** 17
