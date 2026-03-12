# Post-Implementation Audit: Remediation Plan

## Date: 2026-03-12
## Scope: P01-P06 audit after bulk implementation pass
## Auditor: Claude (brutal mode)

---

## Audit Verdict

| Plan | Claimed | Actual | Action |
|------|---------|--------|--------|
| **P01** | Done | **Done** | Moved to `done/` |
| **P02** | Done | **95%** | Moved to `done/` — 1 integration test missing (trivial) |
| **P03** | Phases 2-3 done | **Code exists, 0% wired** | Needs pipeline integration |
| **P04** | Done | **Done** | Moved to `done/` |
| **P05** | 65% done | **50-55%** | SSR broken, loaders broken, adapters orphaned |
| **P06** | Done | **Done** | Already in `done/` |

---

## What's Actually Broken

### Critical: Orphaned Code (exists but never called)

These modules were written but **no build pipeline step invokes them**. They are libraries on a shelf.

| Module | Function | Lines | Callers |
|--------|----------|-------|---------|
| `FFI/Resolve.hs` | `resolveNpmModule` | 363 | **0** |
| `Generate/JavaScript/NpmWrapper.hs` | `generateNpmWrapper` | 199 | **0** |
| `Generate/JavaScript/WebComponent.hs` | `generateWebComponent` | 315 | **0** |
| `Kit/Deploy/Vercel.hs` | `deployVercel` | 56 | **0** |
| `Kit/Deploy/Netlify.hs` | `deployNetlify` | 50 | **0** |
| `Kit/Deploy/Node.hs` | `deployNode` | 144 | **0** |
| `Kit/Deploy/Static.hs` | `deployStatic` | 40 | **0** |
| `Kit/SSR.hs` | `renderStaticRoutes` | ~120 | Called but **non-functional** |

### Critical: Broken Implementations

| Module | Problem |
|--------|---------|
| `Kit/DataLoader.hs` | Text regex detection — multi-line type signatures fail silently |
| `Kit/SSR.hs` | Template code — assumes wrong JS structure, `Ssr.renderPage` undefined |
| `NpmWrapper.hs` line 184 | Generates broken JS: `p0.$` syntax error in UnwrapMaybe |
| `WebComponent.hs` disconnectedCallback | Doesn't unsubscribe ports → memory leak |

### Moderate: Missing Integration Points

| What | Where it should be wired |
|------|--------------------------|
| Route validation | `Kit/Build.hs` should call `Validate.validateManifest` before generating |
| Deploy target flag | `Kit/Build.hs` needs `--target` flag dispatching to adapters |
| Web Component build step | `Make/Output.hs` or `Generate/` should call `generateWebComponent` for tagged modules |
| npm wrapper build step | FFI pipeline should detect npm imports → resolve → parse .d.ts → generate wrapper |
| Vite HMR trigger | `Kit/Dev.hs` watches files but doesn't notify Vite of route changes |

### Moderate: Weak Tests

| Test File | Problem | Fix |
|-----------|---------|-----|
| `Kit/DataLoaderTest.hs` | `isInfixOf`/`isPrefixOf` only | Use exact `@?=` on parsed structures |
| `Kit/Route/GenerateTest.hs` | All substring matching | Golden test or exact output comparison |
| `Kit/SSGTest.hs` | Content checks use substrings | Verify HTML structure properly |

### Minor: Missing Tests

| What | Needed |
|------|--------|
| P02 route→code-split integration | 1 test verifying lazy imports produce chunks |
| `Kit/Build.hs` | End-to-end pipeline test |
| `Kit/SSR.hs` | Any test at all |
| `Kit/Deploy/*` | Any test at all |
| `Kit/Preview.hs` | Any test at all |
| `Kit/Dev.hs` | File watcher integration test |

---

## Remediation Tasks

### Phase A: Fix What's Broken (3-4 days)

These are bugs and broken code that must be fixed before anything else.

#### A1: Fix DataLoader detection (1 day)

**File:** `packages/canopy-terminal/src/Kit/DataLoader.hs`

**Problem:** Fragile single-line regex matching. Multi-line type signatures fail silently.

**Fix:**
1. Parse the source file properly using the existing Canopy parser (`Parse.Module`)
2. Check the module's export list for a `load` function
3. Read the parsed type annotation to classify Static vs Dynamic
4. Fall back to source scanning only if parsing fails (dev mode speed)

**Verify:** Write test with multi-line `load` signature → must detect it.

#### A2: Fix SSR rendering (1.5 days)

**File:** `packages/canopy-terminal/src/Kit/SSR.hs`

**Problem:** Generated render script assumes wrong compiled JS structure. `Ssr.renderPage` is never defined.

**Fix:**
1. Study actual compiled Canopy ESM output structure (what `canopy make --output-format=esm` produces)
2. Rewrite `generateSsrScript` to import the actual compiled module correctly
3. Use the module's `init` and `view` exports properly
4. Generate the SSR entry point (`ssr-entry.js`) that the Node deploy adapter expects
5. Add error handling around Node.js invocation

**Verify:** `canopy kit build` on a project with 1 static route → produces correct HTML with content.

#### A3: Fix NpmWrapper bug (0.5 day)

**File:** `packages/canopy-core/src/Generate/JavaScript/NpmWrapper.hs`

**Problem:** Line 184 generates broken JS for `UnwrapMaybe` conversion.

**Fix:** Remove extra `$` concatenation in `convertParam`.

**Verify:** Unit test for UnwrapMaybe generates valid JS.

#### A4: Fix WebComponent memory leak (0.5 day)

**File:** `packages/canopy-core/src/Generate/JavaScript/WebComponent.hs`

**Problem:** `disconnectedCallback` doesn't unsubscribe from ports.

**Fix:** Generate `this._app.ports.<name>.unsubscribe(...)` for each subscribed port in disconnectedCallback.

**Verify:** Generated JS includes unsubscribe calls.

### Phase B: Wire Orphaned Code (4-5 days)

These modules exist and mostly work — they just need to be called from the right place.

#### B1: Wire deploy adapters with --target flag (1.5 days)

**Files:**
- `packages/canopy-terminal/src/Kit/Build.hs`
- `packages/canopy-terminal/src/Kit/Types.hs`

**Steps:**
1. Add `DeployTarget` sum type to `Kit/Types.hs`: `Static | Node | Vercel | Netlify`
2. Add `_kbTarget :: DeployTarget` field to `KitBuildFlags`
3. Add `--target` flag parsing in CLI
4. After Vite build step in `executeBuildPipeline`, dispatch to the correct adapter:
   ```
   Static  → Deploy.Static.deployStatic
   Node    → Deploy.Node.deployNode + SSR.generateSsrEntry
   Vercel  → Deploy.Vercel.deployVercel
   Netlify → Deploy.Netlify.deployNetlify
   ```
5. For Node/Vercel/Netlify targets, also generate SSR entry point

**Verify:** `canopy kit build --target node` produces `build/server.js`.

#### B2: Wire route validation in build pipeline (0.5 day)

**File:** `packages/canopy-terminal/src/Kit/Build.hs`

**Steps:**
1. After `Scanner.scanRoutes`, call `Validate.validateManifest`
2. On `Left err` → report via `Exit.Kit` error and abort
3. On `Right manifest` → continue pipeline

**Verify:** Duplicate route files → build fails with clear error.

#### B3: Wire npm wrapper pipeline (2 days)

**Files:**
- `packages/canopy-core/src/FFI/Resolve.hs` (already has `resolveNpmModule`)
- `packages/canopy-core/src/Generate/JavaScript/NpmWrapper.hs` (already has `generateNpmWrapper`)
- `packages/canopy-core/src/Generate/TypeScript/Parser.hs` (already parses .d.ts)
- New: integration function that chains them

**Steps:**
1. Create `FFI/NpmPipeline.hs` that:
   - Takes an FFI import referencing an npm package
   - Calls `resolveNpmModule` to find `.d.ts` + `.js` paths
   - Calls the `.d.ts` parser to extract type info
   - Calls `validateFFIAgainstDts` to check compatibility
   - Calls `generateNpmWrapper` to produce the `.ffi.js` wrapper
2. Add logic to determine `ParamConversion` and `ReturnConversion` from parsed types
3. Wire into FFI processing in the build pipeline (likely in `Make/Output.hs` or `Generate/JavaScript.hs`)

**Verify:** FFI import referencing `date-fns` → produces working `.ffi.js` wrapper.

#### B4: Wire Web Component generation (1 day)

**Files:**
- `packages/canopy-core/src/Generate/JavaScript/WebComponent.hs`
- Build pipeline (likely `Make/Output.hs` or `Generate/JavaScript.hs`)

**Steps:**
1. Read `_appWebComponents` from the project outline
2. For each listed module, extract `Flags` type fields → `FlagAttr` list
3. Extract port definitions → `PortEvent` list
4. Call `generateWebComponent` with the config
5. Write the generated JS alongside the module output
6. Fix disconnectedCallback to unsubscribe ports (A4)

**Verify:** Module listed in `web-components` config → `.js` output includes Custom Element class.

### Phase C: Fix Tests (2-3 days)

#### C1: Rewrite weak Kit tests (1.5 days)

Replace `isInfixOf`/`isPrefixOf` with exact `@?=` comparisons or golden tests:

- `Kit/DataLoaderTest.hs` → parse generated output, verify structure
- `Kit/Route/GenerateTest.hs` → golden test comparing full generated `Routes.can`
- `Kit/SSGTest.hs` → verify complete HTML structure, not substrings

#### C2: Add missing tests (1.5 days)

- `Kit/Build.hs` → integration test with temp directory
- `Kit/SSR.hs` → test generated render script content (after A2 fix)
- Deploy adapters → verify generated config files (exact content)
- P02 integration → lazy imports in Routes.can → code split chunks produced

### Phase D: Vite HMR integration (1 day)

**File:** `packages/canopy-terminal/src/Kit/Dev.hs`

**Problem:** File watcher detects route changes and regenerates `Routes.can` but doesn't tell Vite.

**Fix:**
1. After regenerating `Routes.can`, touch a sentinel file that Vite watches
2. Or use Vite's `server.hot.send()` API via a WebSocket message
3. Simplest: write a `.canopy-routes-changed` file that the Vite plugin watches

**Verify:** Add new route file during `canopy kit dev` → browser shows new route without restart.

---

## Execution Order

```
Day 1:  A1 (fix data loaders) + A3 (fix NpmWrapper bug) + A4 (fix WC leak)
Day 2:  A2 (fix SSR rendering)
Day 3:  B1 (wire deploy adapters) + B2 (wire route validation)
Day 4:  B3 (wire npm pipeline — start)
Day 5:  B3 (wire npm pipeline — finish) + B4 (wire Web Components)
Day 6:  C1 (rewrite weak tests)
Day 7:  C2 (add missing tests) + D (Vite HMR)
```

**Total: ~7 working days** to go from "code exists" to "everything is wired and tested."

---

## Definition of Done

After remediation, these must all be true:

- [ ] `canopy kit build` on a project with data loaders → loaders detected and executed
- [ ] `canopy kit build --target node` → produces working `server.js` with SSR
- [ ] `canopy kit build --target vercel` → produces `vercel.json` + serverless functions
- [ ] `canopy kit build` with duplicate routes → fails with clear error
- [ ] FFI import referencing npm package → wrapper generated, types validated
- [ ] Module in `web-components` config → Custom Element JS generated with typed attributes
- [ ] `canopy kit dev` + add route file → HMR picks it up
- [ ] All Kit tests use exact comparisons, no `isInfixOf`
- [ ] Zero callers = 0 for any exported Kit/FFI function
- [ ] All 4,000+ tests pass
- [ ] `make build` clean (no warnings)

---

## Files Changed Summary

| Category | Files |
|----------|-------|
| **Fix** | `Kit/DataLoader.hs`, `Kit/SSR.hs`, `NpmWrapper.hs`, `WebComponent.hs` |
| **Wire** | `Kit/Build.hs`, `Kit/Types.hs`, `Make/Output.hs`, CLI flag parsing |
| **New** | `FFI/NpmPipeline.hs` |
| **Tests** | `DataLoaderTest.hs`, `GenerateTest.hs`, `SSGTest.hs`, + new test files |
| **Plans** | This file, updated P03, updated P05 |
