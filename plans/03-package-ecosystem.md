# Plan 03: Package Ecosystem Sprint

## Priority: CRITICAL — Tier 0
## Effort: 4-5 weeks
## Blocks: Plans 04, 05, 07, 11, 13 (everything UI-related + capability enforcement)

## Problem

Canopy has 3 packages (core, json, capability). You cannot build a web application without html, virtual-dom, browser, http, and url at minimum. There are 14 missing stdlib packages, plus a testing framework is needed.

No amount of compiler innovation matters if developers can't render HTML or write tests.

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
| canopy/virtual-dom | Missing (CRITICAL) | **10 days** |
| canopy/http | Missing | 3 days |
| canopy/file | Missing | 2 days |
| canopy/html | Missing (CRITICAL) | 2 days |
| canopy/svg | Missing | 1 day |
| canopy/browser | Missing (CRITICAL) | 5 days |
| canopy/test | Missing (NEEDED) | 3 days |

**Total: ~38 days of focused work.**

### Revised virtual-dom estimate

The original 5-day estimate for virtual-dom was too aggressive. The VDOM kernel is ~1000 lines of tightly coupled JavaScript referencing scheduler internals, managing event delegation, and handling server-side rendering stubs. Budget 10 days.

**Important**: Since Plan 04 (Fine-Grained Reactivity) will eventually replace the VDOM, consider keeping the VDOM engine as kernel JS rather than converting it to FFI. The goal is a working VDOM now, not a perfect one. Ship > perfect.

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

### Phase 3: UI packages (Weeks 3-5)

The critical path. These enable building actual applications.

10. **canopy/virtual-dom** — The VDOM engine. Largest kernel (~1000 lines). Source in archive/janitor/virtual-dom/. **Strategy: keep as kernel JS** — Plan 04 replaces this with fine-grained reactivity later. Don't gold-plate something we're deprecating.
11. **canopy/html** — Pure wrapper around virtual-dom. Trivial once virtual-dom exists.
12. **canopy/svg** — Pure wrapper around html/virtual-dom. Trivial.
13. **canopy/browser** — Largest package (11 modules). Navigation, DOM events, animation frames, URLs.

### Phase 4: Testing + Cleanup (Week 5)

14. **canopy/test** — Test runner with assertions, expect API, fuzz support. Required for developers to write tests for their own applications. Models after elm-test but with Canopy FFI for test runner internals.
15. **canopy/capability** — Add missing Capability.Available module, create external/capability.js, fix canopy.json deps
16. Validate all packages compile together
17. Integration test: build a real app using all packages
18. Write tests for the sample app using canopy/test

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

The virtual-dom package is the biggest decision point. Three paths:

**Path A (Conservative):** Port the Elm VDOM as-is. ~1000 lines of kernel JS becomes external/virtual-dom.js with FFI bindings. Works now, can be optimized later.

**Path B (Aggressive):** Skip VDOM entirely, go straight to fine-grained reactivity (Plan 04). Higher risk, higher reward, but blocks on Plan 04 being ready.

**Path C (Pragmatic):** Keep VDOM as kernel JS — don't convert to FFI at all. Wrap the Canopy API in .can files that reference kernel, just like canopy/core does. Plan 04 replaces the entire engine later anyway.

**Recommendation:** Path C. The VDOM engine is tightly coupled to the scheduler/platform runtime (uses `_Scheduler_binding`, `_Platform_sendToSelf`). Converting it to FFI is complex work that gets thrown away when Plan 04 ships. Keep it as kernel, wrap the API in .can files, move on.

## Risk: Testing Framework

Without canopy/test, developers cannot write tests for their applications. This is a hard blocker for any production use. The package needs:
- A test runner (`canopy test` CLI command)
- An assertion/expect API (`Expect.equal`, `Expect.true`, etc.)
- Test organization (`describe`, `test` combinators)
- Fuzz testing support (property-based testing basics)

Source: elm-test provides the design reference. The test runner requires FFI for Node.js process management and exit codes.

## Definition of Done

- All 16 packages compile (15 stdlib + canopy/test)
- A sample application using Html, Browser, Http renders and works
- `canopy test` runs tests written with canopy/test
- All package tests pass
- Virtual-dom kernel JS kept as-is (to be replaced by Plan 04)
- All other kernel JS that should be FFI is converted
