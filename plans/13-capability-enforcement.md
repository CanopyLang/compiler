# Plan 13: Capability Enforcement

## Priority: HIGH — Tier 2
## Effort: 3-4 weeks
## Depends on: Plan 03 (packages — especially capability package)

## Problem

Canopy's capability system is designed but not enforced. The `@capability` annotations are parsed and stored but don't produce warnings, manifests, or runtime checks. This is Canopy's unique security story — no other frontend language has this. Ship it.

## Current State

- `@capability` annotations parsed in FFI JSDoc comments
- Types exist: `UserActivated`, `Initialized`, `Permitted`, `Available`
- `FFI/Capability.hs` and `FFI/CapabilityEnforcement.hs` have the framework
- Nothing is actually enforced

## Solution: Three-Level Enforcement

### Level 1: Compile-Time Warnings (Week 1)

When compiling, collect all capabilities required by FFI imports used in the project. Emit warnings listing them:

```
── CAPABILITY REQUIREMENTS ──────────────── src/App.can

This application requires the following browser capabilities:

  Geolocation (via Maps.getCurrentLocation)
    @capability permission geolocation

  Camera (via Scanner.openCamera)
    @capability permission camera
    @capability userActivation Click

  Notifications (via Alerts.requestPermission)
    @capability permission notifications
    @capability initialization notification-api

Consider adding a capability manifest (canopy build --emit-manifest).
```

Implementation:
1. During canonicalization, when resolving FFI imports, collect `@capability` annotations
2. Thread capabilities through the compilation pipeline
3. In the terminal output phase, format and display the summary

### Level 2: Manifest Generation (Week 2)

`canopy build --emit-manifest` generates `capabilities.json`:

```json
{
  "application": "my-app",
  "version": "1.0.0",
  "capabilities": {
    "permissions": [
      {
        "name": "geolocation",
        "usage": [
          { "module": "Maps", "function": "getCurrentLocation", "file": "src/Maps.can", "line": 42 }
        ]
      },
      {
        "name": "camera",
        "usage": [
          { "module": "Scanner", "function": "openCamera", "file": "src/Scanner.can", "line": 15 }
        ]
      }
    ],
    "userActivations": [
      {
        "type": "Click",
        "usage": [
          { "module": "Scanner", "function": "openCamera", "file": "src/Scanner.can", "line": 15 }
        ]
      }
    ],
    "initializations": [
      {
        "name": "notification-api",
        "usage": [
          { "module": "Alerts", "function": "requestPermission", "file": "src/Alerts.can", "line": 8 }
        ]
      }
    ]
  }
}
```

This manifest enables:
- CI systems checking capabilities against an allow-list
- Security audits knowing exactly what browser APIs the app uses
- App stores / enterprise IT reviewing permissions before deployment

### Level 3: Compile-Time Enforcement (Weeks 3-4)

Add a `capabilities` field to `canopy.json`:

```json
{
  "capabilities": {
    "allow": ["geolocation", "camera"],
    "deny": ["microphone", "clipboard-write"]
  }
}
```

The compiler refuses to build if the code uses a denied capability or a capability not in the allow-list:

```
── DENIED CAPABILITY ──────────────── src/Recorder.can

This module uses the `microphone` capability, which is denied in canopy.json:

    15│  foreign import javascript "external/recorder.js"
    16│      startRecording : Task Error AudioStream
    17│      -- @capability permission microphone

The `capabilities.deny` list in canopy.json includes "microphone".

To allow this capability, add "microphone" to the `capabilities.allow` list.
```

### Server/Client Capability Boundaries

For CanopyKit (Plan 05), capabilities enforce the server/client boundary:

```canopy
-- Server capabilities (database, filesystem, env vars)
-- Only available in load functions and API routes

-- Browser capabilities (DOM, localStorage, geolocation)
-- Only available in view/update functions and client code

-- Using a server capability in client code is a compile error:
view model =
    div [] [ text (Database.query "SELECT 1") ]  -- COMPILE ERROR
    -- Error: Database.query requires ServerCapability,
    -- but view runs in BrowserContext
```

## Implementation Details

### Capability Collection

Add a `capabilities` field to the compilation context:

```haskell
data Capabilities = Capabilities
    { permissions :: Map PermissionName [Usage]
    , userActivations :: Map ActivationType [Usage]
    , initializations :: Map InitName [Usage]
    }

data Usage = Usage
    { usageModule :: ModuleName.Canonical
    , usageFunction :: Name.Name
    , usageRegion :: Region
    }
```

During canonicalization, when processing `foreign import` declarations:
1. Look up the FFI source file
2. Parse `@capability` annotations
3. Record in the `Capabilities` accumulator

### Manifest Output

New module: `Generate/Capabilities.hs`
- Takes collected `Capabilities`
- Formats as JSON
- Writes to `capabilities.json` alongside build output

### Enforcement

New validation pass after canonicalization:
1. Load `canopy.json` capability config
2. Compare collected capabilities against allow/deny lists
3. Report errors for denied capabilities
4. Report warnings for unlisted capabilities (if strict mode)

## Testing

- Test that capabilities are correctly collected from FFI annotations
- Test that manifests are complete and accurate
- Test that denied capabilities produce compile errors
- Test server/client boundary enforcement
- Property test: every FFI import with @capability appears in the manifest

## Definition of Done

- [ ] `canopy build` warns about required capabilities
- [ ] `canopy build --emit-manifest` generates capabilities.json
- [ ] `capabilities.allow/deny` in canopy.json enforced at compile time
- [ ] Server/client capability boundaries enforced in CanopyKit
- [ ] All existing FFI packages have correct @capability annotations
