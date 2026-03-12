# P01: Capability-Based Security Polish

## Priority: HIGH -- Phase 1 (Finish Line)
## Effort: 1 week
## Depends on: Nothing (core enforcement fully built)

## Status Overview

The capability security system is **95% complete**. Core enforcement, type-level integration, manifest generation, runtime guards, and the allow-list are all production-ready with 45+ tests. What remains is wiring three pieces of dead/incomplete code into the build pipeline.

| Component | Status |
|-----------|--------|
| `@capability` annotation parsing | DONE |
| Capability validation (allow-list) | DONE |
| Runtime guard generation | DONE |
| Type-level enforcement (`Capability X ->`) | DONE |
| Manifest generation | DONE (by-capability) |
| Per-package manifest tracking | INFRASTRUCTURE EXISTS, data hardcoded to empty |
| Deny list parsing | DONE (Canopy/Outline.hs parses allow/deny) |
| Deny list enforcement | CODE EXISTS but never called |
| New-capability-in-update detection | NOT BUILT |
| `canopy audit` (vulnerability) | DONE |
| `canopy audit --capabilities` | EXISTS but limited (empty by-package data) |

## What's Done (with file references)

### Core Enforcement (45+ tests, 284 FFI annotations)

- **`FFI/Capability.hs`** -- `@capability` annotation parsing from FFI JS files
- **`FFI/CapabilityEnforcement.hs`** -- `validateCapabilities` (called in build), `validateCapabilitiesWithDeny` (exists but dead code), `findUnusedCapabilities`, `generateCapabilityRegistry`, `generateCapabilityGuard`
- **`FFI/Manifest.hs`** -- `collectCapabilities`, `writeManifest`. The `_manifestByPackage` field exists in the manifest type but is hardcoded to `[]`
- **`Canonicalize/Module/FFI.hs`** -- `prependCapabilities` adds `Capability X ->` to FFI function types at the type level
- **`Make/Output.hs`** -- calls `validateCapabilities` (allow-list only) during build, calls `hasCapabilities` to trigger manifest output
- **`Canopy/Outline.hs`** -- parses both `capabilities.allow` and `capabilities.deny` from canopy.json correctly
- **`packages/canopy/capability/`** -- Canopy API (`Capability.can`, `Capability/Available.can`), JS runtime, test suite
- **All 72 stdlib packages** -- 284 `@canopy-bind`/`@canopy-type`/`@capability` annotations

### Existing Audit Command

- **`canopy-terminal/src/Audit.hs`** -- `canopy audit` with advisory matching, severity filtering, JSON output. This audits dependency vulnerabilities, not capabilities.

## What Remains

### Task 1: Wire deny list validation in Make/Output.hs (1 day)

`validateCapabilitiesWithDeny` exists in `FFI/CapabilityEnforcement.hs` but is never called. The build pipeline in `Make/Output.hs` calls only `validateCapabilities` (allow-list). The fix is to replace the `validateCapabilities` call with `validateCapabilitiesWithDeny` when the outline contains a deny list, or to unify both functions.

**Key files:**
- `FFI/CapabilityEnforcement.hs` -- has `validateCapabilitiesWithDeny` (dead code today)
- `Make/Output.hs` -- calls `validateCapabilities`, needs to also call deny validation
- `Canopy/Outline.hs` -- already parses allow/deny correctly

### Task 2: Populate _manifestByPackage in Manifest.hs (2 days)

The manifest type has a `_manifestByPackage` field but `collectCapabilities` in `FFI/Manifest.hs` always sets it to `[]`. The infrastructure for per-package tracking exists -- the manifest type, the JSON serialization, the audit command's display logic -- but the actual collection logic that maps capabilities to their originating packages is not implemented.

**Key files:**
- `FFI/Manifest.hs` -- `_manifestByPackage` hardcoded to `[]`, needs real collection
- `Make/Output.hs` -- passes package info to manifest generation (may need to thread dependency graph)

### Task 3: Add new-capability detection during install/upgrade (2 days)

When a dependency version adds a new capability that the previous version did not require, the build should warn the developer. This requires comparing the current dependency's capabilities against a cached baseline (the previously-built manifest or a stored capability snapshot).

**Key files:**
- `FFI/Manifest.hs` -- needs capability diffing logic
- Build pipeline -- needs to load previous manifest for comparison

### Task 4: Tests for deny + per-package (1 day)

- Denied capabilities produce compile errors
- Per-dependency capability breakdown is accurate
- New capability in dependency update triggers warning
- `canopy audit --capabilities` shows correct per-package data

## Dependencies

None. All prerequisite work (packages, FFI annotations, core enforcement) is complete.

## Definition of Done

- [x] `@capability` annotations parsed and enforced at compile time
- [x] Capability manifest generated during build
- [x] All FFI packages have correct `@capability` annotations (284 annotations)
- [x] `canopy audit` exists for dependency vulnerabilities
- [x] Allow-list enforcement works (`validateCapabilities` in build pipeline)
- [x] Runtime guard generation works
- [x] Type-level enforcement works (`Capability X ->` prepended to FFI types)
- [ ] Deny list enforced at compile time (`validateCapabilitiesWithDeny` wired into Make/Output.hs)
- [ ] `_manifestByPackage` populated with real per-package capability data
- [ ] New capability in dependency update triggers compile warning
- [ ] Tests cover deny list, per-package tracking, and new-capability detection
- [ ] `canopy audit --capabilities` shows accurate per-dependency breakdown

## Server/Client Capability Boundaries (Future -- with CanopyKit)

For CanopyKit (P05), capabilities enforce the server/client boundary:

- Server capabilities (database, filesystem, env vars) -- only available in load functions and API routes
- Browser capabilities (DOM, localStorage, geolocation) -- only available in view/update functions and client code
- Using a server capability in client code is a compile error

This is future work that depends on CanopyKit SSR, not part of this plan.
