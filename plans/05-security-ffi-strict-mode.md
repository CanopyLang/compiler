# Plan 05: FFI Strict Mode CLI Integration

## Priority: HIGH
## Effort: Small (2-4 hours)
## Risk: Low — infrastructure exists, just needs wiring

## Problem

`FFI/Validator.hs` defines `ValidatorConfig` with `_configStrictMode`, `_configValidateOpaque`, and `_configDebugMode` fields, plus a `defaultConfig` with `_configStrictMode = True`. However, this config is never instantiated from CLI flags — strict mode is always on by default with no way to toggle it.

### Current Code (packages/canopy-core/src/FFI/Validator.hs)

```haskell
-- Lines 54-70
data ValidatorConfig = ValidatorConfig
  { _configStrictMode :: !Bool
  , _configValidateOpaque :: !Bool
  , _configDebugMode :: !Bool
  }

defaultConfig :: ValidatorConfig
defaultConfig = ValidatorConfig
  { _configStrictMode = True
  , _configValidateOpaque = True
  , _configDebugMode = False
  }
```

## Implementation Plan

### Step 1: Add CLI flags

**File**: `packages/canopy-terminal/src/CLI/Commands.hs`

Add flags to `make` and `build` commands:
- `--ffi-strict` (default: enabled) — strict FFI validation
- `--ffi-debug` — verbose FFI validation logging
- `--no-ffi-strict` — disable strict mode for legacy compatibility

### Step 2: Thread config through compilation

**File**: `packages/canopy-terminal/src/Make.hs`

Pass `ValidatorConfig` from CLI flags through to the compilation pipeline.

**File**: `packages/canopy-builder/src/Compiler.hs`

Accept `ValidatorConfig` in compilation options and pass to canonicalization.

### Step 3: Document strict mode behavior

Add Haddock docs explaining what strict mode validates:
- Opaque type enforcement
- Return type validation
- Argument type checking
- Path security validation

### Step 4: Tests

- Test that `--no-ffi-strict` allows previously-rejected FFI modules
- Test that `--ffi-debug` produces verbose output
- Test default behavior (strict mode on)

## Dependencies
- None
