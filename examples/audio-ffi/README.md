# Audio FFI Example

A clean, production-ready example demonstrating Web Audio API integration in Canopy with proper error handling.

## What This Example Does

This example demonstrates a complete audio synthesis application using Canopy's Foreign Function Interface (FFI) to access the Web Audio API. It showcases:

- **Result-based error handling**: Every audio operation that can fail returns a `Result` type
- **Capability system**: Proper handling of user activation requirements and initialization states
- **Real-time audio control**: Interactive oscillator with frequency, volume, and waveform controls
- **Error recovery**: Graceful error handling with meaningful user feedback
- **Proper qualified imports**: Following Canopy coding standards

## Features

- Initialize audio context with user activation
- Play/stop audio oscillator
- Real-time frequency control (20 Hz - 2000 Hz)
- Real-time volume control (0% - 100%)
- Multiple waveforms (sine, square, sawtooth, triangle)
- Comprehensive error reporting
- FFI validation tests

## How to Compile

From the project root directory:

```bash
# Build the Canopy compiler first (if not already built)
stack build

# Compile the audio-ffi example
stack exec canopy make examples/audio-ffi/src/Main.can --output=examples/audio-ffi/main.js
```

Or from the examples/audio-ffi directory:

```bash
# Compile Main.can
canopy make src/Main.can --output=main.js
```

## How to Run

1. **Open in browser**: Simply open `index.html` in a modern web browser

   ```bash
   # From examples/audio-ffi directory
   open index.html  # macOS
   # or
   xdg-open index.html  # Linux
   # or
   start index.html  # Windows
   ```

2. **Use a local server** (recommended for development):

   ```bash
   # Python 3
   python3 -m http.server 8000

   # Python 2
   python -m SimpleHTTPServer 8000

   # Node.js (if you have http-server installed)
   npx http-server
   ```

   Then navigate to `http://localhost:8000/index.html`

## Usage Instructions

1. **Initialize Audio**: Click "Initialize Audio" button (requires user interaction)
2. **Play Sound**: Click "Play Sound" to start the oscillator
3. **Adjust Controls**: Use sliders and buttons to modify sound in real-time
4. **Stop Sound**: Click "Stop Sound" to stop playback
5. **Monitor Status**: Watch the status display for feedback and error messages

## Task-Based Error Handling Pattern

This example demonstrates proper Result/Task-based error handling:

### Pattern 1: Chained Result handling

```canopy
handleInitialize : Model -> Model
handleInitialize model =
    let
        userActivation = Capability.consumeUserActivation
        createResult = AudioFFI.createAudioContext userActivation
    in
    case createResult of
        Ok initializedContext ->
            extractContext initializedContext model

        Err capError ->
            { model
                | audioState = Error (formatError capError)
                , statusMessage = "Failed: " ++ formatError capError
            }
```

### Pattern 2: Sequential error checking

```canopy
playAudioChain : AudioFFI.AudioContext -> Model -> Model
playAudioChain ctx model =
    let
        initializedCtx = Capability.Fresh ctx
        oscResult = AudioFFI.createOscillator initializedCtx model.frequency model.waveform
    in
    case oscResult of
        Ok oscillator ->
            continuePlayChain ctx oscillator model

        Err capError ->
            { model
                | audioState = Error (formatError capError)
                , statusMessage = "Failed: " ++ formatError capError
            }
```

### Pattern 3: Comprehensive error formatting

```canopy
formatError : Capability.CapabilityError -> String
formatError err =
    case err of
        Capability.UserActivationRequired msg ->
            "User activation required: " ++ msg

        Capability.InvalidStateError msg ->
            "Invalid state: " ++ msg

        -- ... handle all error types
```

## Architecture

### File Structure

```
audio-ffi/
├── src/
│   ├── Main.can           # Main application with error handling
│   ├── AudioFFI.can       # Web Audio API FFI bindings
│   └── Capability.can     # Capability system types and functions
├── external/
│   ├── audio.js           # JavaScript FFI implementation
│   └── capability.js      # Capability checking implementation
├── canopy.json            # Package configuration
├── index.html             # Simple HTML loader
└── README.md              # This file
```

### State Management

The application uses a clean state machine:

```canopy
type AudioState
    = NotInitialized                                          -- Initial state
    | Ready AudioFFI.AudioContext                             -- Context ready
    | Playing AudioFFI.AudioContext                           -- Audio playing
              AudioFFI.OscillatorNode
              AudioFFI.GainNode
    | Error String                                            -- Error state
```

### Error Types

All audio operations use the capability error system:

```canopy
type CapabilityError
    = UserActivationRequired String
    | PermissionRequired String
    | InitializationRequired String
    | FeatureNotAvailable String
    | CapabilityRevoked String
    | InvalidStateError String
    | InvalidAccessError String
    | IndexSizeError String
    | QuotaExceededError String
    | RangeError String
    | NotAllowedError String
    | SecurityError String
    | NotSupportedError String
```

## Key Concepts Demonstrated

### 1. Proper Qualified Imports

```canopy
import qualified AudioFFI
import qualified Capability

-- Type signatures use unqualified types
handleInitialize : Model -> Model

-- Function calls use qualified functions
AudioFFI.createAudioContext userActivation
Capability.consumeUserActivation
```

### 2. Result-Based Error Handling

Every fallible operation returns `Result CapabilityError a`:

```canopy
createAudioContext : UserActivated -> Result CapabilityError (Initialized AudioContext)
createOscillator : Initialized AudioContext -> Float -> String -> Result CapabilityError OscillatorNode
```

### 3. Capability System

The example properly uses the capability system to ensure:
- User activation for audio context creation
- Proper initialization state tracking
- Permission handling

### 4. Type Safety

All Web Audio objects are opaque types:

```canopy
type AudioContext = AudioContext
type OscillatorNode = OscillatorNode
type GainNode = GainNode
```

This prevents mixing incompatible audio nodes and ensures type safety.

## Browser Compatibility

This example requires:
- Modern browser with Web Audio API support
- User gesture for audio context creation (security requirement)

Tested on:
- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

## Troubleshooting

### Audio doesn't play
- Ensure you click "Initialize Audio" first
- Check browser console for errors
- Verify your browser supports Web Audio API
- Make sure you're not blocking audio in browser settings

### Compilation errors
- Ensure Canopy compiler is built: `stack build`
- Check that all dependencies are in canopy.json
- Verify file paths are correct

### FFI not working
- Check that external/audio.js loads before main.js
- Verify capability.js loads before audio.js
- Look for JavaScript errors in browser console

## Learning Resources

- [Web Audio API Documentation](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API)
- [Canopy FFI Guide](../../docs/FFI.md)
- [Capability System](../../docs/CAPABILITY_SYSTEM.md)

## Next Steps

After understanding this example, try:
1. Adding audio effects (filter, delay, reverb)
2. Implementing audio visualization with AnalyserNode
3. Loading and playing audio files
4. Creating more complex synthesis chains
5. Adding MIDI input support

## License

This example is part of the Canopy project. See project LICENSE for details.
