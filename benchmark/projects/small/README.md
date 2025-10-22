# Small Test Project

A minimal Canopy application for baseline performance testing.

## Stats

- **Modules:** 1
- **Lines of Code:** 10
- **Dependencies:** elm/core, elm/html

## Structure

```
small/
├── canopy.json
└── src/
    └── Main.canopy
```

## Compile

```bash
stack exec -- canopy make src/Main.canopy --output=/tmp/small.js
```

## What It Tests

- Basic HTML rendering
- Minimal compilation overhead
- Single-module compilation
- Baseline performance metrics
