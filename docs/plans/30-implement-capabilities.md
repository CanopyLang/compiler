# Plan 30 — Implement FFI Capability Enforcement

**Priority:** Tier 5 (Hardening)
**Effort:** 5 days
**Risk:** High (new compiler feature)
**Files:** ~10 files across canopy-core and canopy-terminal

---

## Problem

The capability system (`FFI/Capability.hs`) parses `@capability` annotations from JSDoc but never enforces them. The module documentation says it is "for future runtime validation features." Users see capability annotations but the compiler does nothing with them — this is a broken promise.

## Design

### What capabilities model

```javascript
/**
 * @canopy-type AudioContext -> Task Error AudioBuffer
 * @capability permission microphone
 * @capability initialization AudioContext
 */
```

This declares that `decodeAudio` requires microphone permission and AudioContext initialization.

### Enforcement levels

**Level 1 (Compile-time warning) — implement first:**
When a module uses an FFI function with capability requirements, the compiler emits a warning listing the required capabilities. This is informational — it doesn't block compilation but makes capabilities visible.

**Level 2 (Manifest generation):**
Generate a `capabilities.json` manifest alongside the compiled output listing all capabilities required by the application. CI systems can check this manifest against an allow-list.

**Level 3 (Runtime enforcement) — future:**
Inject capability checks at the FFI call sites that verify browser APIs are available before calling the JS function.

## Implementation (Level 1)

### Step 1: Collect capabilities during canonicalization

In `Canonicalize/Module.hs`, when processing FFI imports, collect the capabilities:

```haskell
data ModuleCapabilities = ModuleCapabilities
  { _mcModuleName :: !ModuleName.Canonical
  , _mcCapabilities :: ![CapabilityConstraint]
  , _mcFunctions :: ![(JsFunctionName, [CapabilityConstraint])]
  } deriving (Show)
```

### Step 2: Thread capabilities through compilation

Add `_moduleCapabilities` to `Can.Module`:

```haskell
data Module = Module
  { ...
  , _moduleCapabilities :: ![CapabilityConstraint]
  }
```

### Step 3: Emit warnings

In the warning system (`Reporting/Warning.hs`), add:

```haskell
data Warning
  = ...
  | FFICapabilityRequired !ModuleName.Canonical !JsFunctionName ![CapabilityConstraint]
```

Render it as:

```
-- CAPABILITY NOTICE -- src/Audio.can

This module uses FFI functions that require:

  microphone permission (via decodeAudio)
  AudioContext initialization (via decodeAudio)

These capabilities must be available at runtime. See
https://guide.canopy-lang.org/capabilities for details.
```

### Step 4: Generate capabilities manifest

In `Generate/JavaScript.hs`, after code generation, write `capabilities.json`:

```json
{
  "required": {
    "permissions": ["microphone", "geolocation"],
    "initialization": ["AudioContext"],
    "userActivation": ["payment"]
  },
  "by-module": {
    "Audio": {
      "permissions": ["microphone"],
      "functions": {
        "decodeAudio": ["permission:microphone", "init:AudioContext"]
      }
    }
  }
}
```

## Validation

```bash
make build && make test

# Test with an FFI module that has capabilities:
canopy make src/Audio.can
# Should show capability notice
cat canopy-stuff/capabilities.json
# Should list required capabilities
```

## Acceptance Criteria

- `@capability` annotations produce compile-time warnings listing requirements
- `capabilities.json` manifest is generated alongside compiled output
- Capabilities are traceable to specific FFI functions and modules
- No runtime enforcement yet (documented as future work)
- `make build && make test` passes
