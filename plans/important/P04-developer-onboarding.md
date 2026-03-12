# Plan P04: Developer Onboarding & Adoption

## Priority: CRITICAL -- Tier 1
## Status: IN-PROGRESS -- ~65% complete
## Effort: 3-4 weeks remaining (down from 4-6; substantial assets already exist)
## Depends on: Plan 06 (Vite plugin)

## What's Done

### Documentation Website (37 guides)
- **Location:** `docs/website/src/`
- Getting started, first app, type system, functions, modules, pattern matching
- Architecture (TEA), JSON, HTTP, FFI, do-notation, testing, error handling
- Comparison guides: vs Elm, vs TypeScript, vs ReScript
- API reference: Core, Browser, Html, Json, Http, Platform
- `canopy-for-react-developers.md` exists at `~/projects/canopy/docs/`

### Example Apps (11 total)
- **In docs (5):** Counter, Todo, HTTP, Forms, Routing
- **In `~/projects/canopy/examples/` (6):** blog, dashboard, audio-ffi, math-ffi, test-core, test-ffi

### Editor Tooling (fully operational)
- **VSCode extension** (`editor/vscode/`) -- published .vsix, LSP integration, tree-sitter highlighting, JSON schemas
- **Neovim** (`editor/nvim/`) -- LSP config files
- **Editor setup guide** covering VSCode, Neovim, Helix, Zed, Emacs, Sublime
- **Tree-sitter grammar** (`editor/tree-sitter/`) -- C, Rust, WASM, Node, Python, Go, Swift bindings + test suite

### Language Server
- **Location:** `language-server/canopy-language-server/`
- Full TypeScript LSP: 15+ providers (diagnostics, completions, go-to-definition, find references, hover, rename, workspace symbols, code actions, formatting)

### Developer Tools
- **MCP server** (`mcp/`) -- `@canopy/mcp-server` v0.19.2 with 12 tools + 3 prompts (build, check, getType, findDefinition, getDocs, etc.)
- **Playground** (`tools/playground/`) -- React/Vite/Monaco app with resizable panels, LZ-string URL sharing, live preview
- **Browser debugger** (`tools/canopy-debugger/`) -- Chrome/Firefox extension (Manifest v3), React/Zustand/Tailwind

### Other
- `CONTRIBUTING.md` with setup instructions
- `canopykit-guide.md` (542 lines)
- 71 stdlib packages with canopy.json manifests

## What Remains

### 1. Playground Deployment (~3 days)
- Deploy playground to `play.canopy-lang.org`
- Verify shareable links work in production
- Add interactive step-by-step tutorial mode (inspired by Svelte tutorial, Go Tour)

### 2. Abilities Documentation (~2 days)
- User-facing documentation for the ability system (P06 is production-ready)
- Add ability examples to guides and playground

### 3. Production Example Apps (~1 week)
- E-commerce app (forms, cart, checkout, auth)
- Chat app (WebSocket, real-time sync, presence)
- Admin panel (CRUD, pagination, filtering)
- Each with line-by-line annotations, React comparisons, deployment guide

### 4. Deployment Guides (~2 days)
- Netlify, Vercel, Docker deployment walkthroughs
- One-command deploy examples for each platform

### 5. Video Tutorials (~1 week)
- "Build your first Canopy app" (5-10 min)
- "Canopy for React developers" walkthrough
- "Adding Canopy to an existing React project" (gradual adoption)

### 6. Community & Ecosystem (~2 days)
- Community project showcase page
- Package publishing guide
- Troubleshooting/debugging guide beyond FAQ

### 7. Migration Codemods (~1 week, lower priority)
- Basic React-to-Canopy component converter
- TypeScript type-to-Canopy type converter
- Gets developers 60-70% of the way; manual review for effects/state/interop

## Dependencies

| Dependency | Status |
|---|---|
| Plan 01 (ESM output) | COMPLETE |
| Plan 06 (Vite plugin) | COMPLETE |
| P06 (Abilities) | COMPLETE (needs user-facing docs) |
| CanopyKit (P05) | 60-70% done (examples should use Kit where possible) |

## Definition of Done

- [ ] Playground deployed at play.canopy-lang.org with interactive tutorial
- [ ] Abilities system documented in user-facing guides
- [ ] 3+ production-scale example apps with annotations and deployment guides
- [ ] Deployment guides for Netlify, Vercel, Docker
- [ ] Video tutorials published (at least 2)
- [ ] Package publishing guide available
- [ ] Troubleshooting/debugging guide written
- [ ] A React developer can build and deploy a working Canopy app within 1 day
- [ ] Error messages include "Coming from React?" hints for common mistakes
- [ ] Gradual adoption works (Canopy modules in React projects via Vite)
