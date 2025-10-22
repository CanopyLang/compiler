# AudioWorklet Support

Modern, low-latency custom audio processing for Canopy Web Audio FFI.

## Quick Example

```elm
import AudioFFI exposing (..)
import Capability exposing (Initialized)

-- 1. Load processor module
loadProcessor : Initialized AudioContext -> Result CapabilityError Int
loadProcessor context =
    addAudioWorkletModule context "external/gain-processor.js"

-- 2. Create worklet node
createProcessor : Initialized AudioContext -> Result CapabilityError AudioWorkletNode
createProcessor context =
    createAudioWorkletNode context "gain-processor"

-- 3. Control via messages
setGain : AudioWorkletNode -> Float -> Result CapabilityError Int
setGain worklet value =
    postMessageToWorklet worklet { type = "setGain", value = value }
```

## Why AudioWorklet?

- **Low Latency**: ~3ms vs ScriptProcessorNode's 10-50ms
- **No Glitches**: Runs on dedicated audio thread
- **Better Performance**: Not blocked by main thread operations
- **Modern Standard**: Replaces deprecated ScriptProcessorNode

## Available Functions

| Function | Purpose |
|----------|---------|
| `addAudioWorkletModule` | Load processor module from URL |
| `createAudioWorkletNode` | Create worklet node |
| `createAudioWorkletNodeWithOptions` | Create with custom options |
| `getWorkletNodePort` | Get MessagePort for communication |
| `postMessageToWorklet` | Send control messages |

## Example Processors

### Gain Processor (Simple)
```bash
external/gain-processor.js
```
Basic gain control demonstrating parameter updates.

### Bitcrusher (Advanced)
```bash
external/bitcrusher-processor.js
```
Lo-fi distortion effect with multiple parameters and status reporting.

## Documentation

- **[Quick Start Guide](AUDIOWORKLET_QUICKSTART.md)** - Getting started, examples, patterns
- **[Implementation Details](AUDIOWORKLET_IMPLEMENTATION.md)** - Technical documentation
- **[Summary](IMPLEMENTATION_SUMMARY.md)** - Complete implementation overview

## Browser Support

- Chrome 66+ (April 2018)
- Firefox 76+ (May 2020)
- Safari 14.1+ (April 2021)
- Edge 79+ (January 2020)

## Error Handling

All functions return `Result CapabilityError`:

```elm
case createAudioWorkletNode context "processor-name" of
    Ok worklet ->
        -- Success
        setupAudioProcessing worklet

    Err (NotSupportedError msg) ->
        -- AudioWorklet not supported
        useFallbackApproach

    Err (InvalidAccessError msg) ->
        -- Processor not found
        loadProcessorModule context

    Err error ->
        -- Other error
        handleError error
```

## Creating Custom Processors

```javascript
// my-processor.js
class MyProcessor extends AudioWorkletProcessor {
    constructor() {
        super();
        // Initialize state

        // Listen for messages
        this.port.onmessage = (event) => {
            // Handle control messages
        };
    }

    process(inputs, outputs, parameters) {
        // Process audio samples
        const input = inputs[0];
        const output = outputs[0];

        // Your processing logic here

        return true; // Keep processor alive
    }
}

registerProcessor('my-processor', MyProcessor);
```

## Common Patterns

### Load and Initialize
```elm
initWorklet : Initialized AudioContext -> Cmd Msg
initWorklet context =
    addAudioWorkletModule context "processor.js"
        |> Result.andThen (\_ -> createAudioWorkletNode context "processor-name")
        |> Result.andThen (\worklet -> connectToDestination worklet context)
        |> Result.map (\_ -> Cmd.none)
        |> Result.withDefault (Task.perform ErrorOccurred (Task.fail error))
```

### Parameter Control
```elm
type Msg = SetParameter String Float

updateProcessor : Msg -> AudioWorkletNode -> Cmd Msg
updateProcessor msg worklet =
    case msg of
        SetParameter name value ->
            postMessageToWorklet worklet
                { parameter = name, value = value }
                |> Result.map (\_ -> Cmd.none)
                |> Result.withDefault Cmd.none
```

## Best Practices

1. ✅ Load modules during initialization, not during audio playback
2. ✅ Check for AudioWorklet support before use
3. ✅ Keep process() function simple and fast
4. ✅ Avoid allocations in process() loop
5. ✅ Use messages for parameter updates
6. ✅ Always return true from process() to keep node alive
7. ✅ Handle CORS properly for external modules

## Performance Tips

- Cache computed values outside process loop
- Reuse buffers, don't allocate in process()
- Use lookup tables for complex calculations
- Profile with Chrome DevTools if issues occur
- Test on target devices/browsers

## Debugging

Enable logging in your processor:
```javascript
process(inputs, outputs, parameters) {
    if (this.frameCount++ % 1000 === 0) {
        console.log('Processor status:', {
            inputs: inputs[0]?.length || 0,
            outputs: outputs[0]?.length || 0
        });
    }
    // ... rest of processing
}
```

## Getting Help

1. Read [AUDIOWORKLET_QUICKSTART.md](AUDIOWORKLET_QUICKSTART.md) for detailed examples
2. Test with provided example processors
3. Check browser console for errors
4. Verify CORS headers if loading external modules
5. Review [MDN AudioWorklet docs](https://developer.mozilla.org/en-US/docs/Web/API/AudioWorklet)

## Implementation Status

✅ **Complete and Ready for Production**

- All core functions implemented
- Comprehensive error handling
- Type-safe FFI bindings
- Example processors included
- Full documentation provided

---

**Last Updated**: October 22, 2025
