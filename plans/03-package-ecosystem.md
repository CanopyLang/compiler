# Plan 03: Package Ecosystem Sprint

## Priority: CRITICAL — Tier 0
## Status: COMPLETE (except canopy/test library)
## Effort: ~1 week remaining (canopy/test library only)
## Blocks: Plans 04, 05, 07, 11, 13 (everything UI-related + capability enforcement)

> **Status Update (2026-03-07 audit):** This plan is **essentially complete**. All 16 stdlib
> packages have been fully migrated to `.can` with FFI external JS files, `canopy.json` manifests,
> and test suites. Zero `.elm` files remain in the packages directory.
>
> The only remaining gap is a **canopy/test library package** — the `canopy test` CLI command exists
> (with `--filter`, `--watch`, `--headed`, NDJSON output, Playwright integration) but there is no
> `packages/canopy/test/` library for developers to write tests against.

## Completed Work

All packages below are fully migrated with `.can` source files, FFI external JS, `canopy.json`, and test suites:

| Package | Status | FFI JS | Tests |
|---------|--------|--------|-------|
| canopy/core | Done | 14 external JS files | 12 test modules |
| canopy/json | Done | external/json.js (31 annotations) | Test/Json.can |
| canopy/capability | Done | external/capability.js | Test/Capability.can |
| canopy/url | Done | external/url.js | Test/Url.can |
| canopy/time | Done | external/time.js | Test/Time.can |
| canopy/regex | Done | external/regex.js | Test/Regex.can |
| canopy/parser | Done | external/parser.js | Test/Parser.can |
| canopy/bytes | Done | external/bytes.js | Test/Bytes.can |
| canopy/random | Done | (pure) | Test/Random.can |
| canopy/virtual-dom | Done | external/virtual-dom.js | Test/VirtualDom.can |
| canopy/http | Done | external/http.js | Test/Http.can |
| canopy/file | Done | external/file.js | Test/File.can |
| canopy/html | Done | (wraps virtual-dom) | Test/Html.can |
| canopy/svg | Done | (wraps html) | Test/Svg.can |
| canopy/browser | Done | external/browser.js | Test/Browser.can |
| canopy/project-metadata-utils | Done | (pure) | Test/ProjectMetadata.can |

**Total: 90+ `.can` source files, 27 external FFI JS files, 29 test modules, zero `.elm` files.**

## Remaining Work: Publish canopy/test as a Package

The test framework is **fully built** but lives at `compiler/core-packages/test/` instead of `packages/canopy/test/`. It includes 15 `.can` modules:

| Module | Purpose |
|--------|---------|
| `Test.can` | Core test types (unit, group, async, skip, todo, only, fuzz) |
| `Expect.can` | Assertions (equal, true, notEqual, etc.) |
| `Fuzz.can` | Property-based testing generators |
| `Test/Runner.can` | Test runner infrastructure |
| `Browser.can` | Browser test support |
| `Browser/Test.can` | Browser test types |
| `Browser/Expect.can` | Browser assertions |
| `Browser/Element.can` | Element queries |
| `Browser/Page.can` | Page-level operations |
| `Component.can` | Component testing |
| `Benchmark.can` | Performance benchmarks |
| `Snapshot.can` | Snapshot testing |
| `Visual.can` | Visual regression testing |
| `Accessibility.can` | A11y testing |

The CLI runner also exists (`compiler/packages/canopy-terminal/src/Test.hs`) with discovery, compilation, Playwright integration, NDJSON output, and `--filter`/`--watch`/`--headed` flags.

### Estimated effort: 1-2 days

The library is fully built. It just needs to be packaged:
1. Copy/symlink from `compiler/core-packages/test/` to `packages/canopy/test/`
2. Add `canopy.json` manifest
3. Verify all package tests import from the correct location

## Definition of Done

- [x] All 16 stdlib packages compile with `.can` source and FFI
- [x] All packages have `canopy.json` manifests
- [x] All packages have test suites
- [x] `canopy test` CLI command works
- [x] Virtual-dom kept as kernel JS (external/virtual-dom.js)
- [ ] `packages/canopy/test/` library package exists with test authoring API
- [ ] Sample application using Html, Browser, Http renders and works
- [ ] Integration test: build a real app using all packages
