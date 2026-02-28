# Plan 36: WebIDL Package Integration

## Priority: LOW
## Effort: Medium (2-3 days)
## Risk: Low — independent package already exists

## Problem

The `canopy-webidl` package has a complete WebIDL implementation (parser, transform, codegen) but it's an independent package that's not integrated into the main build workflow. Users can't easily generate type-safe browser API bindings.

### Key Files
- `packages/canopy-webidl/` — full WebIDL implementation

## Implementation Plan

### Step 1: Audit current WebIDL implementation

Read through the canopy-webidl package to understand:
- What WebIDL features are supported
- How it generates Canopy types
- What the output format is
- Whether it handles modern Web APIs

### Step 2: Create canopy webidl command

**File**: `packages/canopy-terminal/src/WebIDL.hs` (NEW)

```haskell
module WebIDL.Command (run, Flags(..)) where

data Flags = Flags
  { _webidlInput :: ![FilePath]  -- .webidl input files
  , _webidlOutput :: !FilePath   -- output directory
  , _webidlApis :: ![Text]       -- specific APIs to generate (e.g., "fetch", "canvas")
  }

run :: () -> Flags -> IO ()
```

### Step 3: Bundle standard Web API IDL files

Include IDL files for common Web APIs:
- DOM (Document, Element, Event)
- Fetch API
- Canvas 2D
- WebSocket
- Web Audio
- Storage (localStorage, sessionStorage)
- URL

### Step 4: Generate canopy modules from IDL

```bash
canopy webidl --api=fetch --output=src/Web/
# Generates:
#   src/Web/Fetch.can
#   src/Web/Request.can
#   src/Web/Response.can
#   src/Web/Headers.can
```

### Step 5: Documentation

Document how to use generated Web API bindings in Canopy projects.

### Step 6: Tests

- Test IDL parsing for each supported API
- Test generated Canopy module compiles
- Golden tests for generated output

## Dependencies
- None
