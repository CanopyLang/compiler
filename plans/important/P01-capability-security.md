# Plan 13: Capability-Based Security

## Priority: HIGH — Tier 1 (elevated from Tier 2)
## Effort: 2-3 weeks (reduced from 4-5 — core enforcement already built)
## Depends on: Nothing (packages are complete)

> **Status Update (2026-03-07 audit):** The core capability enforcement system is **fully
> implemented**. `@capability` annotations are parsed, validated, and enforced at compile time.
> Capability manifests are generated. The FFI type system prepends `Capability X ->` to function
> types. 45+ tests cover the system.
>
> What remains is the **supply chain security story**: capability-specific audit command
> (separate from the existing `canopy audit` which is a dependency vulnerability scanner),
> per-dependency capability tracking, and the marketing/documentation layer.
>
> **Important distinction:** `canopy audit` already exists but audits **dependency vulnerabilities**
> (advisory matching, version freshness, license compatibility). The Plan 13 `canopy audit` for
> **capability breakdown per dependency** is a different feature that needs to be added.

## Problem

### The Market Problem

In September 2025, attackers compromised 18 widely-used npm packages with 2.6 billion weekly downloads. The Shai-Hulud worm was self-replicating within npm. A second wave in November 2025 hit 25,000+ GitHub repositories. JavaScript's npm ecosystem is "uniquely vulnerable" due to deep dependency trees and install-time code execution.

Every React, Vue, Angular, and Svelte application was at risk. None of these frameworks can prevent a malicious dependency from exfiltrating data to an attacker's server.

**Canopy can.** A dependency in Canopy cannot access the network, filesystem, camera, microphone, or any browser API without the application explicitly granting that capability. This is enforced at compile time — no runtime overhead, no escape hatches.

## Current State (What's Already Built)

### Fully Implemented

| Component | File | Status |
|-----------|------|--------|
| `@capability` annotation parsing | `FFI/Capability.hs` | Done |
| Capability validation | `FFI/CapabilityEnforcement.hs` | Done — `validateCapabilities`, `findUnusedCapabilities` |
| Runtime guard generation | `FFI/CapabilityEnforcement.hs` | Done — `generateCapabilityRegistry`, `generateCapabilityGuard` |
| Manifest generation | `FFI/Manifest.hs` | Done — `collectCapabilities`, `writeManifest` |
| Type-level enforcement | `Canonicalize/Module/FFI.hs` | Done — `prependCapabilities` adds `Capability X ->` to FFI types |
| Manifest output in build | `Make/Output.hs` | Done — `hasCapabilities` check |
| Capability JS runtime | `packages/canopy/capability/external/capability.js` | Done |
| Capability Canopy API | `packages/canopy/capability/src/Capability.can`, `Capability/Available.can` | Done |
| Test suite | `packages/canopy/capability/tests/Test/Capability.can` | Done |
| All FFI packages annotated | All `external/*.js` files | Done — 284 `@canopy-bind`/`@canopy-type`/`@capability` annotations |
| Dependency vulnerability audit | `compiler/packages/canopy-terminal/src/Audit.hs` | Done — `canopy audit` with JSON output, severity filtering |

### Not Yet Built

| Component | Description |
|-----------|-------------|
| Capability-specific audit | `canopy audit --capabilities` showing per-dependency capability breakdown |
| Deny lists in canopy.json | Current: flat allow-list (`"capabilities": ["geo", "net"]`). Missing: separate `{"allow": [...], "deny": [...]}` syntax |
| New-capability-in-update detection | Warning when a dependency version adds a new capability |
| Per-dependency capability tracking | Which capabilities come from which dependencies |
| Marketing/documentation | Blog post, landing page section, comparison table |

> **Note (2026-03-10 deep audit):** The `capabilities` field in `canopy.json` IS parsed and
> enforced as an allow-list via `validateDeclaredCapabilities` in `Make/Output.hs`. Runtime
> guards are generated. But the allow/deny split syntax and per-dependency tracking are not
> implemented.

## Remaining Work

### Phase 1: Capability Allow/Deny Lists (Week 1)

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

Implementation:
1. Parse `capabilities` field in `Canopy.Outline`
2. After canonicalization, compare collected capabilities against allow/deny
3. Report errors for denied capabilities, warnings for unlisted (in strict mode)

### Phase 2: Capability Audit Command (Week 2)

Extend the existing `canopy audit` command with a `--capabilities` flag (or create `canopy capabilities` as a separate subcommand):

```bash
canopy audit --capabilities
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

**Per-dependency capability tracking:** Track which capabilities come from which dependencies. If a dependency adds a new capability in a version update, warn:

```
-- NEW CAPABILITY IN DEPENDENCY ────────────── canopy.json

The package `my-company/analytics` version 2.1.0 now requires
the `clipboard-write` capability, which was not required in version 2.0.0.

This capability is not in your allow-list.
```

### Phase 3: Marketing and Documentation (Week 3)

1. **Blog post**: "How Canopy Would Have Prevented the September 2025 npm Attack"
2. **Landing page section**: "Supply Chain Security Built Into the Language"
3. **Comparison table**: Show that React/Vue/Angular/Svelte have zero protection
4. **Enterprise pitch**: Capability manifests for compliance (SOC2, GDPR)
5. **Demo**: Live demo showing a malicious dependency failing to compile

### Server/Client Capability Boundaries (Future — with CanopyKit)

For CanopyKit (Plan 05), capabilities enforce the server/client boundary:

```canopy
-- Server capabilities (database, filesystem, env vars)
-- Only available in load functions and API routes

-- Browser capabilities (DOM, localStorage, geolocation)
-- Only available in view/update functions and client code

-- Using a server capability in client code is a compile error
```

## Testing

- [x] Capabilities correctly collected from FFI annotations
- [x] Manifest generation is complete and accurate
- [ ] Denied capabilities produce compile errors
- [ ] Allow-list enforcement works
- [ ] Per-dependency capability tracking works
- [ ] New capability in dependency version triggers warning
- [ ] `canopy audit --capabilities` output is correct

## Definition of Done

- [x] `@capability` annotations parsed and enforced at compile time
- [x] Capability manifest generated during build
- [x] All FFI packages have correct `@capability` annotations
- [x] `canopy audit` exists for dependency vulnerabilities
- [ ] `capabilities.allow/deny` in canopy.json enforced at compile time
- [ ] `canopy audit --capabilities` shows per-dependency capability breakdown
- [ ] New capability in dependency update triggers compile warning
- [ ] Blog post draft: "How Canopy Prevents Supply Chain Attacks"
