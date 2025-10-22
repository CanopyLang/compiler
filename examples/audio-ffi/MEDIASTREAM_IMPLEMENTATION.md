# MediaStream Audio Nodes Implementation

## Summary

Successfully implemented complete MediaStream support for Web Audio API FFI bindings in Canopy, enabling live audio input/output and recording capabilities.

## Implementation Details

### 1. JavaScript Functions (external/audio.js)

Added MEDIASTREAM NODES section at line 806 with four core functions:

#### `createMediaStreamSource`
- **Type**: `Initialized AudioContext -> MediaStream -> Result Capability.CapabilityError MediaStreamAudioSourceNode`
- **Purpose**: Create audio source node from MediaStream (microphone, etc.)
- **Error Handling**: InvalidStateError, NotSupportedError, TypeError, InitializationRequired

#### `createMediaStreamDestination`
- **Type**: `Initialized AudioContext -> Result Capability.CapabilityError MediaStreamAudioDestinationNode`
- **Purpose**: Create destination node for recording/capturing audio output
- **Error Handling**: InvalidStateError, NotSupportedError, InitializationRequired

#### `getDestinationStream`
- **Type**: `MediaStreamAudioDestinationNode -> MediaStream`
- **Purpose**: Extract MediaStream from destination node for recording
- **Returns**: MediaStream object that can be used with MediaRecorder API

#### `getUserMedia`
- **Type**: `UserActivated -> Task Capability.CapabilityError MediaStream`
- **Purpose**: Request microphone access from user
- **Error Handling**:
  - NotAllowedError → UserActivationRequired
  - NotFoundError → FeatureNotAvailable
  - NotReadableError → InvalidAccessError
  - OverconstrainedError → NotSupportedError
  - SecurityError → SecurityError
  - Generic → InitializationRequired

### 2. Canopy Type Definitions (src/AudioFFI.can)

Added three opaque types:
```elm
type MediaStreamAudioSourceNode = MediaStreamAudioSourceNode
type MediaStreamAudioDestinationNode = MediaStreamAudioDestinationNode
type MediaStream = MediaStream
```

Added four function signatures:
```elm
createMediaStreamSource : Initialized AudioContext -> MediaStream -> Result CapabilityError MediaStreamAudioSourceNode
createMediaStreamDestination : Initialized AudioContext -> Result CapabilityError MediaStreamAudioDestinationNode
getDestinationStream : MediaStreamAudioDestinationNode -> MediaStream
getUserMedia : UserActivated -> Task CapabilityError MediaStream
```

## Features

### Live Audio Input
- Microphone access with proper user permission handling
- MediaStream source node creation
- Full error reporting for permission denied, device not found, etc.

### Audio Recording/Output
- MediaStream destination node for capturing audio
- Stream extraction for use with MediaRecorder API
- Support for routing audio to multiple destinations

### Security & Capabilities
- Requires UserActivated capability for getUserMedia
- Requires Initialized AudioContext for node creation
- Comprehensive error types mapped to CapabilityError variants

## Usage Example

```elm
-- Request microphone access
getUserMedia userActivation
    |> Task.andThen (\stream ->
        -- Create audio context
        case createAudioContext userActivation of
            Ok ctx ->
                -- Create source from microphone
                case createMediaStreamSource ctx stream of
                    Ok source ->
                        -- Create destination for recording
                        case createMediaStreamDestination ctx of
                            Ok destination ->
                                -- Connect and get output stream
                                let outputStream = getDestinationStream destination
                                in Task.succeed (source, destination, outputStream)
                            Err err -> Task.fail err
                    Err err -> Task.fail err
            Err err -> Task.fail err
    )
```

## Testing

### Test File: test-mediastream.html

Created comprehensive test suite demonstrating:
1. getUserMedia - Microphone permission request
2. createMediaStreamSource - Live input node creation
3. createMediaStreamDestination - Recording node creation
4. getDestinationStream - Stream extraction
5. Full pipeline - Complete microphone → processing → recording chain

### Compilation Success

```bash
cd /home/quinten/fh/canopy/examples/audio-ffi
canopy make src/Main.can
# Success! Compiled 1 module to index.html
```

All four functions verified in compiled output:
- ✓ createMediaStreamSource
- ✓ createMediaStreamDestination
- ✓ getDestinationStream
- ✓ getUserMedia

## Integration Points

### Browser API Coverage
- navigator.mediaDevices.getUserMedia
- AudioContext.createMediaStreamSource
- AudioContext.createMediaStreamDestination
- MediaStreamAudioDestinationNode.stream property

### Error Mapping
Complete mapping of Web Audio API errors to Canopy CapabilityError variants:
- InvalidStateError
- NotSupportedError
- TypeError → InvalidAccessError
- NotAllowedError → UserActivationRequired
- NotFoundError → FeatureNotAvailable
- SecurityError
- InitializationRequired (catch-all)

## Files Modified

1. `/home/quinten/fh/canopy/examples/audio-ffi/external/audio.js`
   - Added MEDIASTREAM NODES section (lines 806-900)
   - 4 new functions with full error handling

2. `/home/quinten/fh/canopy/examples/audio-ffi/src/AudioFFI.can`
   - Added 3 opaque types (lines 40-42)
   - Added 4 function signatures (lines 512-526)

3. Created `/home/quinten/fh/canopy/examples/audio-ffi/test-mediastream.html`
   - Standalone test suite for MediaStream functionality

## Implementation Quality

### Type Safety
- All functions return Result or Task types for error handling
- Initialized capability required for AudioContext operations
- UserActivated capability required for getUserMedia

### Error Handling
- Comprehensive error type coverage
- Detailed error messages with context
- Proper JavaScript exception → Canopy error mapping

### Documentation
- JSDoc comments with @name and @canopy-type annotations
- Complete type signatures in Canopy
- Test suite demonstrating all functionality

## Next Steps

Developers can now build Canopy applications that:
- Record audio from microphone
- Process live audio input in real-time
- Route audio to multiple destinations
- Implement voice chat applications
- Create audio analysis tools with live input
- Build recording applications with Web Audio processing

## Verification

Run test-mediastream.html in browser to verify:
1. Microphone permission prompts work correctly
2. MediaStream nodes can be created successfully
3. Audio routing works as expected
4. Error handling reports appropriate messages
5. Full pipeline connects microphone → processing → recording
