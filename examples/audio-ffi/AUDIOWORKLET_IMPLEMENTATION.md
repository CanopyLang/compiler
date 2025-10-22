# AudioWorkletNode Implementation

## Overview

This implementation adds comprehensive AudioWorkletNode support to the Canopy Web Audio FFI bindings. AudioWorkletNode is the modern replacement for the deprecated ScriptProcessorNode and enables custom audio processing in JavaScript with low latency.

## Implementation Details

### JavaScript Functions (audio.js)

Added in the `AUDIO WORKLET - Custom Audio Processing` section (lines 1070-1195):

1. **addAudioWorkletModule**: Load an AudioWorklet processor module
   - Type: `Initialized AudioContext -> String -> Result CapabilityError Int`
   - Loads a worklet module from a URL
   - Returns synchronously but module loads asynchronously
   - Error handling: NotSupportedError, SecurityError, InvalidStateError

2. **createAudioWorkletNode**: Create a worklet node with a registered processor
   - Type: `Initialized AudioContext -> String -> Result CapabilityError AudioWorkletNode`
   - Creates an AudioWorkletNode for the specified processor name
   - Error handling: NotSupportedError, InvalidStateError, NotFoundError, QuotaExceededError

3. **createAudioWorkletNodeWithOptions**: Create worklet node with custom options
   - Type: `Initialized AudioContext -> String -> AudioWorkletOptions -> Result CapabilityError AudioWorkletNode`
   - Supports custom channel counts, parameters, and processor options
   - Additional error handling: RangeError for invalid options

4. **getWorkletNodePort**: Get the MessagePort for communication
   - Type: `AudioWorkletNode -> MessagePort`
   - Returns the port for bidirectional messaging with the processor

5. **postMessageToWorklet**: Send messages to the worklet processor
   - Type: `AudioWorkletNode -> a -> Result CapabilityError Int`
   - Posts messages to the worklet's audio thread
   - Error handling: DataCloneError, InvalidAccessError

### Canopy FFI Bindings (AudioFFI.can)

Added three opaque types:
```elm
type AudioWorkletNode = AudioWorkletNode
type MessagePort = MessagePort
type AudioWorkletOptions = AudioWorkletOptions
```

Added five function bindings in the `AUDIO WORKLET OPERATIONS` section:
```elm
addAudioWorkletModule : Initialized AudioContext -> String -> Result CapabilityError Int
createAudioWorkletNode : Initialized AudioContext -> String -> Result CapabilityError AudioWorkletNode
createAudioWorkletNodeWithOptions : Initialized AudioContext -> String -> AudioWorkletOptions -> Result CapabilityError AudioWorkletNode
getWorkletNodePort : AudioWorkletNode -> MessagePort
postMessageToWorklet : AudioWorkletNode -> a -> Result CapabilityError Int
```

## Example Worklet Processor

Created `external/gain-processor.js` demonstrating a simple gain processor:

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

## Usage Example

```elm
-- Load the worklet module
case addAudioWorkletModule context "external/gain-processor.js" of
    Ok _ ->
        -- Create the worklet node
        case createAudioWorkletNode context "gain-processor" of
            Ok workletNode ->
                -- Connect to audio graph
                connectToDestination workletNode context

                -- Send messages to control the processor
                postMessageToWorklet workletNode
                    { type = "setGain", value = 0.5 }

            Err error ->
                -- Handle error
                Debug.log "Failed to create worklet node" error

    Err error ->
        -- Handle error
        Debug.log "Failed to load worklet module" error
```

## Key Features

1. **Type Safety**: Full Result-based error handling with specific error types
2. **Capability System**: Requires Initialized AudioContext for creation
3. **Comprehensive Error Handling**: Covers all Web Audio API error scenarios
4. **Browser Compatibility**: Checks for AudioWorklet support before use
5. **Bidirectional Communication**: MessagePort support for control and feedback
6. **Options Support**: Can configure channel counts and custom parameters

## Error Handling

All functions return proper Result types with the following error variants:

- **NotSupportedError**: AudioWorklet not supported by browser
- **SecurityError**: CORS or security policy violation
- **InvalidStateError**: Context closed or processor not registered
- **InvalidAccessError**: Processor not found or invalid message
- **RangeError**: Invalid options or parameters
- **QuotaExceededError**: Memory allocation failed
- **DataCloneError**: Message cannot be cloned
- **InitializationRequired**: Generic initialization failure

## Browser Compatibility

AudioWorklet is supported in:
- Chrome 66+
- Firefox 76+
- Safari 14.1+
- Edge 79+

The implementation includes feature detection and will return NotSupportedError on older browsers.

## Performance Benefits

Compared to ScriptProcessorNode:
- **Lower Latency**: Runs on audio thread, not main thread
- **No Glitches**: Not affected by main thread blocking
- **Better Performance**: Dedicated audio processing thread
- **More Control**: Access to exact sample timing

## Testing

To test the implementation:

1. Ensure the audio-ffi example is built
2. Load the HTML page in a modern browser
3. The gain-processor.js worklet should be available
4. Test with the Canopy FFI functions

## Files Modified

- `/home/quinten/fh/canopy/examples/audio-ffi/external/audio.js` (added lines 1070-1195)
- `/home/quinten/fh/canopy/examples/audio-ffi/src/AudioFFI.can` (added types and functions)
- `/home/quinten/fh/canopy/examples/audio-ffi/external/gain-processor.js` (new file)

## Next Steps

Potential enhancements:
1. Add AudioParam support for worklet parameters
2. Create more example processors (filters, effects, synthesizers)
3. Add SharedArrayBuffer support for large data transfers
4. Implement worklet-based analysis nodes
5. Add automated tests for the worklet functionality

## References

- [MDN: AudioWorkletNode](https://developer.mozilla.org/en-US/docs/Web/API/AudioWorkletNode)
- [MDN: AudioWorkletProcessor](https://developer.mozilla.org/en-US/docs/Web/API/AudioWorkletProcessor)
- [Web Audio API Spec](https://www.w3.org/TR/webaudio/)
- [Enter Audio Worklet (Google Developers)](https://developer.chrome.com/blog/audio-worklet/)
