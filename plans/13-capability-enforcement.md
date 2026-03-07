# Plan 13: Capability-Based Security

## Priority: HIGH — Tier 1 (elevated from Tier 2)
## Effort: 4-5 weeks (expanded from 3-4)
## Depends on: Plan 03 (packages — especially capability package)

> **Note (revised):** This plan was originally "Capability Enforcement" in Tier 2 with 3-4 weeks
> effort. It has been elevated to Tier 1 and expanded because the September 2025 npm supply chain
> attack (chalk, debug, ansi-styles — 2.6B weekly downloads compromised by the "Shai-Hulud" worm)
> proved that JavaScript's dependency model is fundamentally unsafe. Canopy's capability system is
> the **language-level answer** to this problem. No other frontend language has this. This is our
> strongest marketing story and our biggest competitive advantage.

## Problem

### The Technical Problem

Canopy's capability system is designed but not enforced. The `@capability` annotations are parsed and stored but don't produce warnings, manifests, or runtime checks.

### The Market Problem

In September 2025, attackers compromised 18 widely-used npm packages with 2.6 billion weekly downloads. The Shai-Hulud worm was self-replicating within npm. A second wave in November 2025 hit 25,000+ GitHub repositories. JavaScript's npm ecosystem is "uniquely vulnerable" due to deep dependency trees and install-time code execution.

Every React, Vue, Angular, and Svelte application was at risk. None of these frameworks can prevent a malicious dependency from exfiltrating data to an attacker's server.

**Canopy can.** A dependency in Canopy cannot access the network, filesystem, camera, microphone, or any browser API without the application explicitly granting that capability. This is enforced at compile time — no runtime overhead, no escape hatches.

## Current State

- `@capability` annotations parsed in FFI JSDoc comments
- Types exist: `UserActivated`, `Initialized`, `Permitted`, `Available`
- `FFI/Capability.hs` and `FFI/CapabilityEnforcement.hs` have the framework
- Nothing is actually enforced

## Solution: Four-Level Enforcement

### Level 1: Compile-Time Warnings (Week 1)

When compiling, collect all capabilities required by FFI imports used in the project. Emit warnings listing them:

```
-- CAPABILITY REQUIREMENTS ────────────── src/App.can

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
    ],
    "network": [
      {
        "usage": [
          { "module": "Api", "function": "fetchUsers", "file": "src/Api.can", "line": 12 }
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
- Diff-based review: any PR that adds a new capability shows up in the manifest diff

### Level 3: Compile-Time Enforcement (Weeks 3-4)

Add a `capabilities` field to `canopy.json`:

```json
{
  "capabilities": {
    "allow": ["geolocation", "camera", "network"],
    "deny": ["microphone", "clipboard-write"]
  }
}
```

The compiler refuses to build if the code uses a denied capability or a capability not in the allow-list:

```
-- DENIED CAPABILITY ────────────── src/Recorder.can

This module uses the `microphone` capability, which is denied in canopy.json:

    15| foreign import javascript "external/recorder.js"
    16|     startRecording : Task Error AudioStream
    17|     -- @capability permission microphone

The `capabilities.deny` list in canopy.json includes "microphone".

To allow this capability, add "microphone" to the `capabilities.allow` list.
```

### Level 4: Supply Chain Security Story (Week 5)

This is the marketing and documentation layer that turns the technical feature into an adoption driver.

**Supply chain audit command:**

```bash
canopy audit
```

Output:

```
-- DEPENDENCY CAPABILITY AUDIT ────────────── my-app

canopy/core .................. no capabilities required
canopy/http .................. network
canopy/browser ............... dom, navigation
my-company/analytics ......... network
my-company/maps .............. geolocation, network

Total capabilities required by dependencies:
  dom, geolocation, navigation, network

Your canopy.json allows:
  geolocation, network, dom, navigation

Status: ALL DEPENDENCIES WITHIN ALLOWED CAPABILITIES
```

**Per-dependency capability tracking:**

The manifest tracks which capabilities come from which dependencies. If a dependency adds a new capability in a version update, the compiler warns:

```
-- NEW CAPABILITY IN DEPENDENCY ────────────── canopy.json

The package `my-company/analytics` version 2.1.0 now requires
the `clipboard-write` capability, which was not required in version 2.0.0.

This capability is not in your allow-list.

    Hint: Review why this package needs clipboard access before adding
    "clipboard-write" to your capabilities.allow list.
```

This is the feature that would have caught the September 2025 npm attack. A malicious package that suddenly starts accessing the network would trigger a compilation failure.

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
    , network :: [Usage]
    , dom :: [Usage]
    }

data Usage = Usage
    { usageModule :: ModuleName.Canonical
    , usageFunction :: Name.Name
    , usageRegion :: Region
    , usagePackage :: Package.Name
    }
```

During canonicalization, when processing `foreign import` declarations:
1. Look up the FFI source file
2. Parse `@capability` annotations
3. Record in the `Capabilities` accumulator
4. Track which package each capability comes from

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
5. Track capabilities per dependency for supply chain auditing

### Audit Command

New CLI command: `canopy audit`
- Scans all dependencies and their FFI imports
- Collects capability requirements per package
- Compares against allow-list
- Reports status

## Testing

- Test that capabilities are correctly collected from FFI annotations
- Test that manifests are complete and accurate
- Test that denied capabilities produce compile errors
- Test server/client boundary enforcement
- Test per-dependency capability tracking
- Test that adding a new capability in a dependency version triggers a warning
- Property test: every FFI import with @capability appears in the manifest

## Marketing and Documentation

This feature needs dedicated marketing material:

1. **Blog post**: "How Canopy Would Have Prevented the September 2025 npm Attack"
2. **Landing page section**: "Supply Chain Security Built Into the Language"
3. **Comparison table**: Show that React/Vue/Angular/Svelte have zero protection
4. **Enterprise pitch**: Capability manifests for compliance (SOC2, GDPR)
5. **Demo**: Live demo showing a malicious dependency failing to compile

## Definition of Done

- [ ] `canopy build` warns about required capabilities
- [ ] `canopy build --emit-manifest` generates capabilities.json
- [ ] `capabilities.allow/deny` in canopy.json enforced at compile time
- [ ] `canopy audit` shows per-dependency capability breakdown
- [ ] New capability in dependency update triggers compile warning
- [ ] Server/client capability boundaries enforced in CanopyKit
- [ ] All existing FFI packages have correct @capability annotations
- [ ] Blog post draft: "How Canopy Prevents Supply Chain Attacks"
