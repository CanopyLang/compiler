# canopy/capability

Core capability detection for Canopy applications.

This package provides runtime detection of browser capabilities needed for Canopy applications, particularly audio and multimedia features.

## Usage

```canopy
import Capability.Available exposing (webAudio, Available(..))

main =
    let
        audioCapabilities = webAudio
    in
    if audioCapabilities.audioContext == Available then
        text "Web Audio API is available!"
    else
        text "Web Audio API is not available."
```

## Features

- **Web Audio API Detection**: Detect availability of AudioContext, AnalyserNode, OscillatorNode, and GainNode
- **Runtime Detection**: All checks are performed at runtime for accurate results
- **Type-Safe**: Uses Canopy's type system to provide safe capability checking

## Installation

This package is designed for use with the canopy-package-overrides system during local development.

## License

BSD-3-Clause