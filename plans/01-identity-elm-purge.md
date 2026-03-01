# Plan 01: Elm Identity Purge

**Priority:** CRITICAL
**Effort:** Large (3–5 days)
**Risk:** Medium — touches many files, requires careful testing of package resolution

## Problem

Canopy presents itself as an independent language but 100+ locations still reference "elm" as the primary identity. This causes:

1. **`canopy new` creates broken projects** — scaffolded `canopy.json` references `elm/core`, `elm/browser`, `elm/html` (New.hs:320–328)
2. **Registry points to Elm** — `registryBase = "https://package.elm-lang.org"` (Fetch.hs:135), `registryUrl = "https://package.elm-lang.org/all-packages"` (Registry.hs:131)
3. **Generated JS exports to `scope['Elm']` as primary** — Kernel.hs:297, CodeSplit/Generate.hs:502, Html.hs:65,127 all set `scope['Canopy'] = scope['Elm']` (backward — Elm is the primary)
4. **Error messages link to elm-lang.org** — JavaScript.hs:390,403
5. **Standard library packages authored as "elm"** — Package.hs:141–176 defines `core = toName elm "core"`, etc.

## Changes Required

### A. Package Author Identity (Package.hs)

**File:** `packages/canopy-core/src/Canopy/Package.hs`

1. Add `canopy :: Author` at line ~197: `canopy = Utf8.fromChars "canopy"`
2. Add `canopyExplorations :: Author`: `canopyExplorations = Utf8.fromChars "canopy-explorations"`
3. Change all standard package definitions (lines 141–185) from `toName elm` to `toName canopy`:
   - `core = toName canopy "core"`
   - `browser = toName canopy "browser"`
   - `virtualDom = toName canopy "virtual-dom"`
   - `html = toName canopy "html"`
   - `json = toName canopy "json"`
   - `http = toName canopy "http"`
   - `url = toName canopy "url"`
   - `webgl = toName canopyExplorations "webgl"`
   - `linearAlgebra = toName canopyExplorations "linear-algebra"`
   - `random = toName canopy "random"`, `time = toName canopy "time"`, `file = toName canopy "file"` (line 222–224)
4. Update `isKernel` (line 98) to check `canopy` as primary, keep `elm` as compat
5. Keep `elm :: Author` exported for backward compatibility fallback paths

### B. Project Scaffolding (New.hs)

**File:** `packages/canopy-terminal/src/New.hs`

Replace all 8 `elm/` package references in `canopyJsonContent` (lines 320–349):
- `"elm/core": "1.0.5"` → `"canopy/core": "1.0.5"`
- `"elm/browser": "1.0.2"` → `"canopy/browser": "1.0.2"`
- `"elm/html": "1.0.0"` → `"canopy/html": "1.0.0"`
- `"elm/json": "1.1.3"` → `"canopy/json": "1.1.3"`
- `"elm/time": "1.0.0"` → `"canopy/time": "1.0.0"`
- `"elm/url": "1.0.0"` → `"canopy/url": "1.0.0"`
- `"elm/virtual-dom": "1.0.3"` → `"canopy/virtual-dom": "1.0.3"`
- `"elm/core": "1.0.0 <= v < 2.0.0"` → `"canopy/core": "1.0.0 <= v < 2.0.0"`

### C. Registry URLs

| File | Line | Change |
|------|------|--------|
| `PackageCache/Fetch.hs` | 135 | `registryBase = "https://package.canopy-lang.org"` |
| `Deps/Registry.hs` | 131 | `registryUrl = "https://package.canopy-lang.org/all-packages"` |
| `Deps/Diff.hs` | 300 | `Website.route "https://package.canopy-lang.org"` |

Keep the `Http.hs` fallback logic (lines 273–279) that converts `canopy-lang.org` → `elm-lang.org` for backward compatibility.

### D. Generated JavaScript/HTML

| File | Line | Current | Change To |
|------|------|---------|-----------|
| `Generate/JavaScript.hs` | 373 | `global.Elm = scope['Elm']` | Remove this line entirely |
| `Generate/JavaScript/Kernel.hs` | 297 | `scope['Canopy'] = scope['Elm']` | `scope['Elm'] = scope['Canopy']` |
| `Generate/JavaScript/CodeSplit/Generate.hs` | 502 | `scope['Canopy'] = scope['Elm']` | `scope['Elm'] = scope['Canopy']` |
| `Generate/Html.hs` | 65 | `window.Canopy = window.Elm` | `window.Elm = window.Canopy` |
| `Generate/Html.hs` | 127 | `window.Canopy = window.Elm` | `window.Elm = window.Canopy` |

The direction must be: Canopy is the primary, Elm is the backward-compat alias.

### E. Error Messages

| File | Line | Change |
|------|------|--------|
| `Generate/JavaScript.hs` | 390 | `"https://canopy-lang.org/0.19.1/optimize"` |
| `Generate/JavaScript.hs` | 403 | `"https://canopy-lang.org/0.19.1/optimize"` |
| `Setup.hs` | 138 | `canopy install canopy/core` |

### F. FFI Resolve

**File:** `packages/canopy-core/src/FFI/Resolve.hs`
- Line 164: `isTrustedPackage` must accept both `"canopy"` and `"elm"` authors

### G. Comments and Documentation

Update all Haddock comments that reference "Elm" where "Canopy" is correct. Key files:
- `PackageCache/Fetch.hs` (lines 10, 19, 81, 131, 139)
- `Deps/Registry.hs` (lines 6, 129, 364)
- `Test.hs` (line 235)
- `Publish.hs` (line 231)
- `Deps/CustomRepositoryDataIO.hs` (lines 6–7, 21)

### H. TypeScript/LSP Files

| File | Line | Change |
|------|------|--------|
| `canopy-lsp/src/compiler/elmPackageCache.ts` | 211 | `"https://package.canopy-lang.org/all-packages/"` |
| `editors/vscode/client/src/node/canopyPackage.ts` | 37 | `"https://package.canopy-lang.org/all-packages"` |
| `editors/vscode/client/src/node/canopyPackage.ts` | 101,107 | `"https://package.canopy-lang.org/packages/"` |
| `editors/vscode/schemas/canopy.schema.json` | 3 | `"title": "JSON schema for canopy.json configuration files"` |

### I. Core Packages Runtime (Platform.js)

**File:** `core-packages/core/src/Elm/Kernel/Platform.js`
- Lines 484–486, 505–507: Change `scope['Elm']` to `scope['Canopy']` as primary export, add `scope['Elm'] = scope['Canopy']` as backward-compat alias

### J. Test Fixtures

Update all test assertions that check for `elm/core`, `elm/html`, `package.elm-lang.org`, etc. to match the new values. Key files:
- `test/Unit/MakeTest.hs` (lines 54–62)
- `test/Unit/NewTest.hs` (lines 174–182)
- `test/Unit/Builder/PackageCacheTest.hs`
- `test/Unit/Deps/RegistryTest.hs` (line 37)
- `test/Unit/VendorTest.hs` (line 195)
- `test/Golden/` expected output files — must be regenerated

## What NOT to Change

- Keep `elm.json` fallback in `Outline.read` (backward compatibility for existing projects)
- Keep `~/.elm/0.19.1/packages` cache fallback paths (users may have packages there)
- Keep `elm :: Author` exported from Package.hs (needed for fallback/compat checks)
- Keep `Http.hs` canopy-lang.org → elm-lang.org fallback (registry may not be live yet)

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. `canopy new test-app` — verify generated canopy.json references `canopy/*` packages
4. Grep for remaining `"elm/"` in source (should only be in backward-compat paths)
