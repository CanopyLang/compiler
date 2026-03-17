# Plan 35: Auto-Convert Elm Packages

## Priority: HIGH -- Tier 2
## Status: NOT STARTED
## Effort: 4-6 weeks
## Depends on: ESM Output (COMPLETE), Package Registry (COMPLETE)

## Problem

The Elm ecosystem has ~1,600 published packages on package.elm-lang.org. Canopy is syntactically compatible with Elm 0.19 but diverges in:
- File extension (`.elm` -> `.can`)
- `elm.json` -> `canopy.json`
- Kernel JS (restricted) -> FFI JS (open)
- Port modules -> `foreign import javascript`

A tool that can automatically convert most Elm packages would instantly give Canopy a massive ecosystem -- the single biggest barrier to adoption.

## What Already Exists

### Elm Archive
- `/home/quinten/projects/canopy/archive/elm/` -- Historical Elm reference files
- Benchmark apps in `.elm` format at `/home/quinten/projects/canopy/benchmark/apps/`

### Migration Guide
- `MIGRATION.md` at project root documents manual migration steps

### No Automated Converter
- No `canopy convert` command
- No batch conversion tooling
- No registry import pipeline

## Conversion Categories

### Category A: Pure Elm Packages (~60% of registry)
Packages with **no kernel JS, no ports, no effects**. These are purely algorithmic libraries.
- Conversion: Rename `.elm` -> `.can`, convert `elm.json` -> `canopy.json`, done.
- Examples: elm-community/list-extra, NoRedInk/elm-json-decode-pipeline, rtfeldman/elm-css
- **Fully automatable**

### Category B: Port-Based Packages (~15%)
Packages that use ports for JS interop.
- Conversion: Rename files + convert ports to `foreign import javascript` + generate FFI JS stubs
- **Mostly automatable** (FFI JS stubs need manual review)

### Category C: Effect Manager Packages (~10%)
Packages that use the Elm effect manager system (Http, Random, Time, etc.).
- Conversion: Complex. Effect managers map to Canopy's Task/Cmd system differently.
- **Partially automatable** (structure can be converted, effect wiring needs manual work)

### Category D: Kernel JS Packages (~15%)
Packages that depend on Elm kernel modules (elm/core, elm/browser, elm/html, etc.).
- These are already replaced by Canopy's stdlib (canopy/core, canopy/browser, etc.)
- Conversion: Rewrite imports to use canopy/* equivalents
- **Import mapping automatable**, but API differences may require manual fixes

## Architecture

### CLI Tool: `canopy convert`

```
canopy convert <elm-package-dir>          -- Convert single package in-place
canopy convert --output <dir> <source>    -- Convert to new directory
canopy convert --registry <package-name>  -- Fetch from Elm registry and convert
canopy convert --batch <package-list>     -- Batch convert multiple packages
canopy convert --dry-run <dir>            -- Report what would change without modifying
canopy convert --report <dir>            -- Detailed conversion report with confidence scores
```

### Compiler Module Structure

```
compiler/packages/canopy-terminal/src/
  Convert.hs                    -- CLI entry point
  Convert/ElmJson.hs            -- elm.json -> canopy.json conversion
  Convert/Source.hs              -- .elm -> .can source transformation
  Convert/Imports.hs             -- Elm module -> Canopy module import mapping
  Convert/Ports.hs               -- Port declarations -> foreign import javascript
  Convert/EffectManager.hs       -- Effect manager conversion (best-effort)
  Convert/KernelMap.hs           -- Elm kernel function -> Canopy FFI mapping
  Convert/Registry.hs            -- Fetch packages from package.elm-lang.org
  Convert/Batch.hs               -- Batch conversion orchestration
  Convert/Report.hs              -- Conversion confidence scoring
```

## Implementation Plan

### Phase 1: Pure Package Converter (Week 1-2)

**elm.json -> canopy.json:**
```json
// elm.json
{
    "type": "package",
    "name": "author/package",
    "version": "1.2.3",
    "elm-version": "0.19.0 <= v < 0.20.0",
    "dependencies": {
        "elm/core": "1.0.0 <= v < 2.0.0",
        "elm/json": "1.0.0 <= v < 2.0.0"
    }
}

// canopy.json (converted)
{
    "type": "package",
    "name": "author/package",
    "version": "1.2.3",
    "canopy-version": "0.19.0 <= v < 0.20.0",
    "dependencies": {
        "canopy/core": "1.0.0 <= v < 2.0.0",
        "canopy/json": "1.0.0 <= v < 2.0.0"
    }
}
```

**Source transformation:**
1. Rename `.elm` -> `.can`
2. No syntax changes needed (Canopy is Elm-compatible)
3. Rewrite imports using dependency mapping table:

| Elm Package | Canopy Package | Notes |
|-------------|---------------|-------|
| elm/core | canopy/core | API-compatible |
| elm/html | canopy/html | API-compatible |
| elm/browser | canopy/browser | API-compatible |
| elm/json | canopy/json | API-compatible |
| elm/http | canopy/http | Minor API differences |
| elm/url | canopy/url | API-compatible |
| elm/time | canopy/time | API-compatible |
| elm/random | canopy/random | API-compatible |
| elm/file | canopy/file | Needs UserGesture (Plan 33) |
| elm/bytes | canopy/bytes | API-compatible |
| elm/regex | canopy/regex | API-compatible |
| elm/parser | canopy/parser | API-compatible |
| elm/svg | canopy/svg | API-compatible |
| elm/virtual-dom | canopy/virtual-dom | API-compatible |
| elm/markdown | canopy/markdown | Minor differences |

4. Compile with `canopy build` to verify conversion

### Phase 2: Port Conversion (Week 2-3)

Convert port modules to FFI:

```elm
-- BEFORE (Elm)
port module MyModule exposing (..)
port sendToJs : String -> Cmd msg
port receiveFromJs : (String -> msg) -> Sub msg
```

```canopy
-- AFTER (Canopy)
module MyModule exposing (..)

foreign import javascript "external/my-module.js" as MyModuleFFI

sendToJs : String -> Cmd msg
sendToJs = MyModuleFFI.sendToJs

receiveFromJs : (String -> msg) -> Sub msg
receiveFromJs = MyModuleFFI.receiveFromJs
```

Auto-generate `external/my-module.js`:
```javascript
// Auto-generated FFI for port module MyModule
// @canopy-type String -> Cmd msg
// @canopy-bind method postMessage
function sendToJs(value) {
    // TODO: Implement JS side (was an Elm port)
    window.postMessage({ type: "MyModule.sendToJs", data: value }, "*");
}

// @canopy-type (String -> msg) -> Sub msg
function receiveFromJs(callback) {
    // TODO: Implement JS side (was an Elm subscription port)
    window.addEventListener("message", function(event) {
        if (event.data && event.data.type === "MyModule.receiveFromJs") {
            callback(event.data.data);
        }
    });
}
```

### Phase 3: Older Elm Version Support (Week 3-4)

Support converting packages from older Elm versions:

**Elm 0.18:**
- Different module syntax: `module MyModule exposing (..)` vs `module MyModule where`
- Different import syntax
- `Signal` -> removed (convert to `Sub`)
- Different effect system
- Type inference differences

**Elm 0.17:**
- `StartApp` -> `Browser.element`
- Very different architecture

**Strategy**: Focus on 0.19 first (majority of packages). Add 0.18 support as best-effort with manual review flags.

### Phase 4: Registry Import Pipeline (Week 4-5)

Bulk conversion from the Elm package registry:

1. **Fetch**: Download package source from package.elm-lang.org API
2. **Convert**: Run converter on each package
3. **Verify**: Attempt `canopy build` on converted package
4. **Score**: Rate conversion confidence (0-100%)
   - 100%: Compiles clean, all tests pass
   - 80%+: Compiles clean, some tests need manual fix
   - 50-80%: Some compilation errors, mostly fixable
   - <50%: Major manual work needed
5. **Publish**: Auto-publish packages scoring 80%+ to Canopy registry
6. **Flag**: Generate issues for packages scoring < 80%

### Phase 5: Continuous Sync (Week 5-6)

- Watch Elm registry for new package versions
- Auto-convert and test new versions
- Dashboard showing conversion status of all ~1,600 packages
- Community contribution workflow for fixing conversion failures

## Conversion Confidence Scoring

```
Score Components:
  +30  Category A (pure package)
  +20  Category B (ports, auto-convertible)
  +10  Category C (effects, partial)
  +0   Category D (kernel, needs mapping)
  +20  Compiles successfully after conversion
  +15  All tests pass after conversion
  +10  No manual TODO markers in generated code
  +5   All dependencies also converted successfully
  -10  Per compilation error
  -5   Per warning
  -20  Uses effect managers
  -30  Uses kernel JS directly
```

## Definition of Done

- [ ] `canopy convert` CLI command with single/batch/registry modes
- [ ] Pure package conversion: rename + elm.json -> canopy.json + import remapping
- [ ] Port module conversion: port -> foreign import javascript with FFI stub generation
- [ ] Older Elm version support (0.18 best-effort, 0.19 full)
- [ ] Registry fetch and batch conversion pipeline
- [ ] Confidence scoring with detailed reports
- [ ] Dashboard showing conversion status
- [ ] 80%+ of pure Elm packages (Category A) auto-convert and compile
- [ ] Test suite for converter covering edge cases

## Risks

- **API drift**: Some Elm packages use APIs that differ between elm/* and canopy/*. The import mapper handles direct equivalents but not behavioral differences.
- **Effect managers**: Elm's effect manager system is unique and complex. Automatic conversion of effect-based packages will be low-confidence.
- **Licensing**: Must respect original package licenses when republishing converted packages. Include original license and attribution.
- **Maintenance**: Auto-converted packages may have subtle bugs. Need community review process.
- **Registry load**: Fetching and converting 1,600 packages is compute-intensive. Use CI pipeline with caching.
