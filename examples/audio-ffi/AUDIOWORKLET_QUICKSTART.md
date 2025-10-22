# AudioWorklet Quick Start Guide

## What is AudioWorklet?

AudioWorklet is the modern Web Audio API interface for custom audio processing. It runs on a dedicated audio thread, providing low-latency, glitch-free audio processing.

## Key Advantages

- **Low Latency**: Runs on audio rendering thread (not main thread)
- **No Glitches**: Not blocked by UI or JavaScript execution
- **High Performance**: Dedicated audio processing with precise timing
- **Standard API**: Replaces deprecated ScriptProcessorNode

## Basic Usage Pattern

### 1. Load Worklet Module

```elm
loadWorklet : Initialized AudioContext -> Cmd Msg
loadWorklet context =
    case addAudioWorkletModule context "external/gain-processor.js" of
        Ok _ ->
            -- Module loaded successfully
            createWorkletNode context

        Err (NotSupportedError msg) ->
            -- AudioWorklet not supported in this browser
            handleError msg

        Err error ->
            -- Other error occurred
            handleError (Debug.toString error)
```

### 2. Create Worklet Node

```elm
createWorklet : Initialized AudioContext -> Result CapabilityError AudioWorkletNode
createWorklet context =
    createAudioWorkletNode context "gain-processor"
```

### 3. Connect to Audio Graph

```elm
setupAudioGraph : Initialized AudioContext -> AudioWorkletNode -> Result CapabilityError Int
setupAudioGraph context workletNode =
    connectToDestination workletNode context
```

### 4. Control via Messages

```elm
setGain : AudioWorkletNode -> Float -> Result CapabilityError Int
setGain workletNode value =
    postMessageToWorklet workletNode
        { type = "setGain"
        , value = value
        }
```

## Available Functions

### addAudioWorkletModule
```elm
addAudioWorkletModule : Initialized AudioContext -> String -> Result CapabilityError Int
```
Load an AudioWorklet processor module from URL.

**Parameters:**
- `context`: Initialized AudioContext
- `moduleURL`: Path to the worklet processor JavaScript file

**Returns:** `Ok 1` on success, `Err` with error details

### createAudioWorkletNode
```elm
createAudioWorkletNode : Initialized AudioContext -> String -> Result CapabilityError AudioWorkletNode
```
Create an AudioWorkletNode for the specified processor.

**Parameters:**
- `context`: Initialized AudioContext
- `processorName`: Name registered in the worklet module

**Returns:** `Ok workletNode` on success, `Err` with error details

### createAudioWorkletNodeWithOptions
```elm
createAudioWorkletNodeWithOptions : Initialized AudioContext -> String -> AudioWorkletOptions -> Result CapabilityError AudioWorkletNode
```
Create an AudioWorkletNode with custom options.

**Parameters:**
- `context`: Initialized AudioContext
- `processorName`: Name registered in the worklet module
- `options`: AudioWorkletOptions (channels, parameters, etc.)

**Returns:** `Ok workletNode` on success, `Err` with error details

### getWorkletNodePort
```elm
getWorkletNodePort : AudioWorkletNode -> MessagePort
```
Get the MessagePort for bidirectional communication.

**Parameters:**
- `workletNode`: The AudioWorkletNode

**Returns:** MessagePort for sending/receiving messages

### postMessageToWorklet
```elm
postMessageToWorklet : AudioWorkletNode -> a -> Result CapabilityError Int
```
Send a message to the worklet processor.

**Parameters:**
- `workletNode`: The AudioWorkletNode
- `message`: Any serializable value

**Returns:** `Ok 1` on success, `Err` with error details

## Example Worklet Processors

### 1. Gain Processor (Simple)

File: `external/gain-processor.js`

```javascript
class GainProcessor extends AudioWorkletProcessor {
    constructor() {
        super();
        this.gain = 1.0;

        this.port.onmessage = (event) => {
            if (event.data.type === 'setGain') {
                this.gain = event.data.value;
            }
        };
    }

    process(inputs, outputs, parameters) {
        const input = inputs[0];
        const output = outputs[0];

        for (let channel = 0; channel < input.length; channel++) {
            const inputChannel = input[channel];
            const outputChannel = output[channel];

            for (let i = 0; i < inputChannel.length; i++) {
                outputChannel[i] = inputChannel[i] * this.gain;
            }
        }

        return true;
    }
}

registerProcessor('gain-processor', GainProcessor);
```

**Usage:**
```elm
-- Load module
addAudioWorkletModule context "external/gain-processor.js"

-- Create node
case createAudioWorkletNode context "gain-processor" of
    Ok node ->
        -- Set gain to 50%
        postMessageToWorklet node { type = "setGain", value = 0.5 }
```

### 2. Bitcrusher Processor (Advanced)

File: `external/bitcrusher-processor.js`

Demonstrates:
- Multiple parameters
- Bidirectional communication
- State management
- Status reporting

**Usage:**
```elm
-- Load module
addAudioWorkletModule context "external/bitcrusher-processor.js"

-- Create node
case createAudioWorkletNode context "bitcrusher-processor" of
    Ok node ->
        -- Set bit depth to 8 bits
        postMessageToWorklet node { type = "setBitDepth", value = 8 }

        -- Set sample rate reduction factor
        postMessageToWorklet node { type = "setSampleRateReduction", value = 4 }

        -- Request status
        postMessageToWorklet node { type = "getStatus" }
```

## Error Handling

All functions return `Result CapabilityError`, with these possible errors:

- **NotSupportedError**: AudioWorklet not supported by browser
- **SecurityError**: CORS or security policy violation
- **InvalidStateError**: Context closed or processor not registered
- **InvalidAccessError**: Processor not found or invalid message
- **RangeError**: Invalid options or parameters
- **QuotaExceededError**: Memory allocation failed
- **DataCloneError**: Message cannot be cloned
- **InitializationRequired**: Generic initialization failure

### Example Error Handling

```elm
handleWorkletCreation : Initialized AudioContext -> Cmd Msg
handleWorkletCreation context =
    case createAudioWorkletNode context "my-processor" of
        Ok node ->
            -- Success
            setupAudioProcessing node

        Err (NotSupportedError msg) ->
            -- Use fallback approach
            useLegacyAudioProcessing context

        Err (InvalidStateError msg) ->
            -- Try reopening context
            reopenAudioContext

        Err (InvalidAccessError msg) ->
            -- Processor not found, load module first
            loadProcessorModule context

        Err error ->
            -- Generic error handling
            showError (Debug.toString error)
```

## Browser Compatibility

AudioWorklet requires:
- Chrome 66+ (April 2018)
- Firefox 76+ (May 2020)
- Safari 14.1+ (April 2021)
- Edge 79+ (January 2020)

Always check for support:
```elm
case addAudioWorkletModule context "processor.js" of
    Err (NotSupportedError _) ->
        -- AudioWorklet not supported
        useFallbackApproach

    Ok _ ->
        -- AudioWorklet supported
        useWorkletApproach
```

## Best Practices

1. **Load modules early**: Load worklet modules during initialization
2. **Check support**: Always handle NotSupportedError
3. **CORS compliance**: Serve worklet files from same origin or with CORS headers
4. **Keep processors simple**: Complex logic can cause audio glitches
5. **Use messages for control**: Don't share state between threads
6. **Return true**: Always return true from process() to keep node alive
7. **Test thoroughly**: Test on different browsers and devices

## Performance Tips

1. **Minimize allocations**: Avoid creating objects in process()
2. **Reuse buffers**: Don't allocate new arrays each frame
3. **Cache values**: Store computed values outside process loop
4. **Avoid conditionals**: Use lookup tables for complex calculations
5. **Profile carefully**: Use Chrome DevTools Performance tab

## Common Patterns

### Pattern 1: Parameter Control
```elm
type Msg
    = SetGain Float
    | SetFrequency Float

update : Msg -> Model -> Model
update msg model =
    case msg of
        SetGain value ->
            case postMessageToWorklet model.worklet { type = "setGain", value = value } of
                Ok _ -> model
                Err _ -> model

        SetFrequency value ->
            case postMessageToWorklet model.worklet { type = "setFrequency", value = value } of
                Ok _ -> model
                Err _ -> model
```

### Pattern 2: Status Monitoring
```javascript
// In worklet processor
this.port.postMessage({
    type: 'status',
    level: currentLevel,
    clipping: isClipping
});
```

```elm
-- In Canopy, listen for messages
port workletStatus : (Value -> msg) -> Sub msg

subscriptions : Model -> Sub Msg
subscriptions model =
    workletStatus GotWorkletStatus
```

### Pattern 3: Effect Chain
```elm
setupEffectChain : Initialized AudioContext -> Result CapabilityError Int
setupEffectChain context =
    case createAudioWorkletNode context "filter" of
        Ok filterNode ->
            case createAudioWorkletNode context "distortion" of
                Ok distortionNode ->
                    -- Connect: source -> filter -> distortion -> destination
                    connectNodes source filterNode
                        |> Result.andThen (\_ -> connectNodes filterNode distortionNode)
                        |> Result.andThen (\_ -> connectToDestination distortionNode context)

                Err error -> Err error
        Err error -> Err error
```

## Debugging

### Enable Logging
```javascript
// In worklet processor
process(inputs, outputs, parameters) {
    // Log every 1000 frames to avoid console spam
    if (this.frameCount++ % 1000 === 0) {
        console.log('Worklet stats:', {
            inputChannels: inputs[0]?.length || 0,
            outputChannels: outputs[0]?.length || 0,
            bufferSize: inputs[0]?.[0]?.length || 0
        });
    }
    // ... rest of processing
}
```

### Check Module Loading
```elm
case addAudioWorkletModule context moduleURL of
    Err error ->
        Debug.log "Failed to load worklet module" {
            url = moduleURL,
            error = error
        }
    Ok _ ->
        Debug.log "Worklet module loaded successfully" moduleURL
```

## Resources

- [MDN: AudioWorklet](https://developer.mozilla.org/en-US/docs/Web/API/AudioWorklet)
- [Enter Audio Worklet](https://developer.chrome.com/blog/audio-worklet/)
- [Web Audio API Spec](https://www.w3.org/TR/webaudio/)
- Example processors in `examples/audio-ffi/external/`

## Support

For issues or questions:
1. Check browser console for errors
2. Verify CORS headers if loading from different origin
3. Test with example processors first
4. Review AUDIOWORKLET_IMPLEMENTATION.md for details
