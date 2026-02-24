# canopy/web-audio

Type-safe Web Audio API bindings with capability-based security for Canopy.

## Installation

During development with local dependencies:

```bash
canopy package link ../core-packages/web-audio
```

## Usage

```canopy
import WebAudio
import WebAudio.Effect as Effect

-- Create an audio context (requires capability)
context : Capability -> WebAudio.AudioContext
context capability =
    WebAudio.createContext capability

-- Play a tone
playA4 : Effect.Effect
playA4 =
    Effect.playTone 440 1.0
```

## Modules

- `WebAudio` - Main module with context management
- `WebAudio.Context` - Low-level context operations
- `WebAudio.Node` - Audio node types and operations
- `WebAudio.Effect` - Effect system for audio side effects

## License

BSD-3-Clause
