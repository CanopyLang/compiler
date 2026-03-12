# Plan P05: CanopyKit Meta-Framework

## Priority: HIGH -- Tier 1
## Status: IN-PROGRESS -- ~80% functional (post-remediation)
## Effort: 1-2 weeks remaining (end-to-end verification + preview server)
## Depends on: Plan 01 (ESM -- COMPLETE), Plan 06 (Vite plugin -- COMPLETE)

## Post-Remediation Status (2026-03-12)

The audit remediation fixed all broken components and wired all orphaned modules. Previous estimate was 50-55%. Now **~80%** with all core pipeline functional.

| Component | Status | Notes |
|-----------|--------|-------|
| Route scanner | **DONE** | Working |
| Route validation | **DONE** | Now called in build pipeline |
| Route generation (Routes.can) | **DONE** | Working, includes lazy imports |
| CLI commands (kit new/dev/build/preview) | **DONE** | Wired into binary |
| SSG (static HTML shells) | **DONE** | Working |
| Layouts + error boundaries | **DONE** | Working |
| API routes | **DONE** | Working |
| Vite integration | **DONE** | Working |
| Data loader detection | **FIXED** | Multi-line signatures now supported |
| SSR rendering | **FIXED** | Uses JSDOM + correct ESM paths |
| Deploy adapters (4 targets) | **WIRED** | --target flag dispatches to correct adapter |
| File watcher (dev mode) | **FIXED** | Sentinel file triggers Vite HMR |
| Web Component build step | **WIRED** | Reads outline, generates Custom Element JS |
| Kit tests | **FIXED** | All use exact @?= assertions |
| Preview server | **PARTIAL** | Works for static, Node target untested end-to-end |

## What's Done (working in production)

### File-Based Routing (fully operational)
- **Scanner** (`Kit/Route/Scanner.hs`, 328L) -- discovers routes, builds tree
- **Types** (`Kit/Route/Types.hs`, 178L) -- Route, Segment, RouteManifest
- **Validate** (`Kit/Route/Validate.hs`, 148L) -- conflict detection, wired in build pipeline
- **Generate** (`Kit/Route/Generate.hs`, 226L) -- generates Routes.can with lazy imports
- **ClientNav** (`Kit/ClientNav.hs`, 268L) -- client-side navigation JS

### CLI Commands (all wired)
- `canopy kit new` (`Kit/New.hs`, 181L) -- scaffolds project
- `canopy kit dev` (`Kit/Dev.hs`) -- dev server with file watching + HMR sentinel
- `canopy kit build` (`Kit/Build.hs`) -- compile + SSG + SSR + Vite + deploy adapter
- `canopy kit preview` (`Kit/Preview.hs`) -- preview built output

### Build Pipeline (fully wired)
- Scan routes -> validate -> generate Routes.can -> detect loaders -> compile -> SSG -> SSR -> Web Components -> Vite -> deploy adapter
- Deploy targets: Static (default), Node, Vercel, Netlify via `--target` flag
- `DeployTarget` sum type in `Kit/Types.hs` with CLI flag parsing

### Static Site Generation
- `Kit/SSG.hs` (103L) -- HTML shells with mount points

### Data Loaders (fixed)
- `Kit/DataLoader.hs` -- multi-line type signature detection
- Classifies Static vs Dynamic based on `Task` in return type

### SSR (fixed)
- `Kit/SSR.hs` -- JSDOM-based rendering with correct ESM module imports
- Generates `ssr-entry.js` for Node deploy adapter

### Layout System + Error Boundaries
- `Kit/Layout.hs` (52L) -- prefix-based layout resolution
- `Kit/ErrorBoundary.hs` (83L) -- hierarchy-based error handling

### API Routes
- `Kit/ApiHandler.hs` (227L) -- handler code generation

### Tests (fixed + new)
- All Kit tests use exact `@?=` assertions (no `isInfixOf`)
- New test suites: SSRTest (6), DeployTest (11), WebComponentTest (11)
- 46 new tests added across Kit modules

## What Remains

### 1. End-to-end verification (2-3 days)

The pipeline is wired but needs real-project testing:
- Create a sample Kit project with data loaders, SSR routes, and static routes
- Run `canopy kit build --target node` and verify `server.js` works
- Run `canopy kit build --target vercel` and verify output structure
- Test `canopy kit dev` with hot route addition

### 2. Preview server for non-static targets (1 day)

- `Kit/Preview.hs` works for static builds
- Needs to start Node server for `--target node` builds
- Needs to simulate edge functions for Vercel/Netlify targets

### 3. Hydration and client-side resumption (2 days)

- SSR generates HTML but client-side hydration path is untested
- Need to verify `init` receives server-rendered state correctly
- May need hydration markers in generated HTML

## Dependencies

| Dependency | Status |
|---|---|
| Plan 01 (ESM output) | COMPLETE |
| Plan 06 (Vite plugin) | COMPLETE |
| Audit Remediation | COMPLETE |

## Definition of Done

- [x] `canopy kit new my-app && cd my-app && canopy kit dev` works
- [x] File-based routing with static, dynamic, catch-all segments
- [x] SSG builds produce static HTML files
- [x] Type-safe links (compile error for nonexistent routes)
- [x] Layouts with prefix-based nesting
- [x] Error boundaries per route hierarchy
- [x] API route handler generation
- [x] Vite plugin configuration generation
- [x] Data loader detection works on multi-line type signatures
- [x] SSR renders pages correctly (JSDOM + correct ESM paths)
- [x] Deploy adapters wired with --target flag
- [x] Route validation called in build pipeline (duplicates caught)
- [x] Dev mode file watcher triggers Vite HMR
- [x] All Kit tests use exact comparisons (no `isInfixOf`)
- [x] Test coverage for SSR, Deploy, WebComponent modules
- [ ] End-to-end verification with real Kit project
- [ ] Preview server works for Node target
- [ ] Client-side hydration path verified
