# Plan P05: CanopyKit Meta-Framework

## Priority: HIGH -- Tier 1
## Status: IN-PROGRESS -- ~65% complete
## Effort: 4-6 weeks remaining (down from 8-12; routing, SSG, layouts, errors, API routes all built)
## Depends on: Plan 01 (ESM -- COMPLETE), Plan 06 (Vite plugin -- COMPLETE)

## What's Done (2,419 lines Haskell + 157 lines TypeScript)

### File-Based Routing (fully operational)
- **Scanner** (`Kit/Scanner.hs`, 328L) -- discovers route files, builds route tree
- **Types** (`Kit/Types.hs`, 178L) -- Route, Segment (static, [param] dynamic, [...rest] catch-all), RouteManifest
- **Validate** (`Kit/Validate.hs`, 148L) -- conflict detection, validation rules
- **Generate** (`Kit/Generate.hs`, 228L) -- generates `Routes.can` module (Route type, href helper, parser)
- **ClientNav** (`Kit/ClientNav.hs`, 268L) -- client-side navigation JS (pushState, popstate, link interception, lazy loading)

### CLI Commands (all wired into `canopy` binary)
- **`canopy kit new`** (`Kit/New.hs`, 181L) -- scaffolds full starter project
- **`canopy kit dev`** (`Kit/Dev.hs`, 159L) -- validates routes, scans filesystem, generates Routes.can, starts Vite dev server
- **`canopy kit build`** (`Kit/Build.hs`, 98L) -- compile, SSG, Vite bundle pipeline

### Static Site Generation
- **SSG** (`Kit/SSG.hs`, 103L) -- generates static HTML shells with mount points per route

### Layout System
- **Layouts** (`Kit/Layout.hs`, 52L) -- prefix-based layout resolution, specificity sorting

### Error Boundaries
- **ErrorBoundary** (`Kit/ErrorBoundary.hs`, 83L) -- hierarchy-based error handling per route

### API Routes
- **ApiHandler** (`Kit/ApiHandler.hs`, 227L) -- handler code generation, Express-style HTTP method patterns

### Data Loaders (partial)
- **DataLoader** (`Kit/DataLoader.hs`, 121L) -- types defined, generation code ready
- Detection NOT implemented (`detectLoaders` returns `[]`)

### Vite Integration
- **VitePlugin** (`Kit/VitePlugin.hs`, 199L) -- generates complete `vite.config.ts` + `canopy-plugin.js`

### Error Reporting
- **Exit/Kit.hs** (126L) -- structured error messages for all Kit operations

### Documentation
- **canopykit-guide.md** (542L) -- complete user guide

## What Remains

### 1. Data Loader Detection (~1 week)
- `detectLoaders` currently returns `[]` -- needs module export parsing
- Scan page modules for `load` function exports
- Wire detected loaders into SSG and dev server pipelines
- Generate server-side loader execution code

### 2. SSR -- Server-Side Rendering (~2-3 weeks)
- Node.js server generation (Express or Fastify)
- HTML streaming for `Page.server` routes
- Client-side hydration (inject serialized state, resume on client)
- `Page.server` with `load` function that runs server-side
- `Page.incremental` with revalidation interval (ISR)

### 3. Deployment Adapters (~1 week)
- Node.js adapter (standalone server)
- Static adapter (already partially covered by SSG)
- Edge adapter (Cloudflare Workers / Vercel Edge -- stretch goal)

### 4. `canopy kit preview` Command (~2 days)
- Preview production build locally
- Serve built assets with a local HTTP server
- Simulate production routing behavior

### 5. Request/Response Types for API Routes (~3 days)
- Typed `Request` and `Response` types in Canopy
- Header, cookie, query parameter access
- JSON body parsing with type safety

### 6. HMR Integration with Route Changes (~2 days)
- Detect new/removed/renamed route files during `canopy kit dev`
- Re-scan and regenerate `Routes.can` on filesystem changes
- Hot-reload route manifest without full restart

### 7. Tests (~1 week)
- ZERO tests exist for Kit modules currently
- Unit tests for Scanner, Validate, Generate, Layout, ErrorBoundary
- Integration tests for `kit new`, `kit dev`, `kit build` commands
- Golden tests for generated Routes.can and vite.config.ts

## Dependencies

| Dependency | Status |
|---|---|
| Plan 01 (ESM output) | COMPLETE |
| Plan 06 (Vite plugin) | COMPLETE |
| P06 (Abilities) | COMPLETE (not a hard dependency but useful for typed patterns) |

## Architecture

```
                    canopy kit dev
                         |
                    +----+----+
                    |  Vite   |  (dev server, HMR, bundling)
                    +----+----+
                         |
              +----------+----------+
              |          |          |
         +----+---+ +---+----+ +--+------+
         | Router | |  SSR   | |  Build  |
         | Plugin | | Engine | | Pipeline|
         +----+---+ +---+----+ +--+------+
              |          |         |
              +----------+---------+
                         |
                  +------+------+
                  |   Canopy    |
                  |  Compiler   |
                  +-------------+
```

## Definition of Done

- [x] `canopy kit new my-app && cd my-app && canopy kit dev` works
- [x] File-based routing with static, dynamic [param], and catch-all [...rest] segments
- [x] SSG builds produce static HTML files
- [x] Type-safe links: linking to nonexistent routes is a compile error
- [x] Layouts with prefix-based nesting
- [x] Error boundaries per route hierarchy
- [x] API route handler generation
- [x] Vite plugin configuration generation
- [ ] Data loader detection and execution
- [ ] SSR renders pages on each request with streaming
- [ ] Client-side hydration
- [ ] Code splitting: each route is a separate chunk (lazy loading wired but needs SSR)
- [ ] `canopy kit preview` command
- [ ] Request/Response types for API routes
- [ ] At least one deployment adapter (Node.js)
- [ ] Test coverage for all Kit modules (target: 80%)
