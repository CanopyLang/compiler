# Plan 03: Package Ecosystem Sprint

## Priority: CRITICAL — Tier 0
## Effort: 3-4 weeks
## Blocks: Plans 04, 05, 07, 11 (everything UI-related)

## Problem

Canopy has 3 packages (core, json, capability). You cannot build a web application without html, virtual-dom, browser, http, and url at minimum. There are 14 missing stdlib packages.

No amount of compiler innovation matters if developers can't render HTML.

## Current State

| Package | Status | Effort |
|---------|--------|--------|
| canopy/core | Done | — |
| canopy/json | Exists, needs .elm→.can + FFI | 2 days |
| canopy/capability | Incomplete (missing module + JS) | 2 days |
| canopy/url | Missing | 1 day |
| canopy/time | Missing | 2 days |
| canopy/regex | Missing | 1 day |
| canopy/parser | Missing | 1 day |
| canopy/bytes | Missing | 2 days |
| canopy/random | Missing | 1 day |
| canopy/virtual-dom | Missing (CRITICAL) | 5 days |
| canopy/http | Missing | 3 days |
| canopy/file | Missing | 2 days |
| canopy/html | Missing (CRITICAL) | 2 days |
| canopy/svg | Missing | 1 day |
| canopy/browser | Missing (CRITICAL) | 5 days |

**Total: ~30 days of focused work.**

## Conversion Strategy

Use **Hybrid approach** (Option B from PACKAGE-CONVERSION-GUIDE.md):
- FFI JS exposes leaf browser APIs (fetch, DOM, Date, etc.)
- Effect manager plumbing stays in pure Canopy code
- Platform/Scheduler/Process bindings remain as kernel internals

### Phase 1: Leaf packages (Week 1)

No non-core dependencies. Can be done in parallel.

1. **canopy/json** — Convert .elm→.can, create external/json.js
2. **canopy/url** — Pure + tiny kernel (percentEncode/Decode)
3. **canopy/regex** — Small kernel (107 lines)
4. **canopy/parser** — Small kernel (134 lines)
5. **canopy/bytes** — Medium kernel (185 lines)
6. **canopy/time** — Small kernel, effect module

### Phase 2: Middle tier (Week 2)

Depend on Phase 1 packages.

7. **canopy/random** — No kernel JS, depends on time
8. **canopy/file** — Medium kernel (188 lines), FileReader
9. **canopy/http** — Effect module, XMLHttpRequest wrapper

### Phase 3: UI packages (Weeks 3-4)

The critical path. These enable building actual applications.

10. **canopy/virtual-dom** — The VDOM engine. Largest kernel (~1000 lines). Source in archive/janitor/virtual-dom/
11. **canopy/html** — Pure wrapper around virtual-dom. Trivial once virtual-dom exists.
12. **canopy/svg** — Pure wrapper around html/virtual-dom. Trivial.
13. **canopy/browser** — Largest package (11 modules). Navigation, DOM events, animation frames, URLs.

### Phase 4: Cleanup (Week 4)

14. **canopy/capability** — Add missing Capability.Available module, create external/capability.js, fix canopy.json deps
15. Validate all packages compile together
16. Integration test: build a real app using all packages

## Source Material

All source code exists in `archive/elm/` (from GitHub elm/* repos) and `archive/janitor/` (previous Canopy fork). This is conversion work, not green-field development.

## Per-Package Process

1. Copy from archive source
2. Rename .elm → .can
3. Update module declarations (`module Elm.X` → `module Canopy.X` or just `module X`)
4. Convert kernel JS to FFI where appropriate (external/*.js + foreign import)
5. Update canopy.json with correct dependencies
6. Write/update tests
7. Verify compilation

## Risk: Virtual DOM Strategy

The virtual-dom package is the biggest decision point. Two paths:

**Path A (Conservative):** Port the Elm VDOM as-is. ~1000 lines of kernel JS becomes external/virtual-dom.js with FFI bindings. Works now, can be optimized later.

**Path B (Aggressive):** Skip VDOM entirely, go straight to fine-grained reactivity (Plan 04). Higher risk, higher reward, but blocks on Plan 04 being ready.

**Recommendation:** Path A first. Get a working VDOM now. Plan 04 replaces it later. Ship > perfect.

## Definition of Done

- All 15 packages compile
- A sample application using Html, Browser, Http renders and works
- All package tests pass
- No kernel JS that should be FFI remains unconverted
