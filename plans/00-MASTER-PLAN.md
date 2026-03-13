# Canopy Master Plan: Beat React, Angular, and Vue

## Mission

Make Canopy the obvious choice for building web applications. Not competitive -- **dominant**. When teams evaluate React/Angular/Vue vs Canopy, the answer should be self-evident.

## Why This Is Possible

A purpose-built compiler for a pure functional language has **strictly more information** than any JavaScript runtime framework:

- **Purity** -- the compiler knows every data dependency, enabling fine-grained DOM updates no framework can match
- **Strong types** -- the compiler can mangle properties, eliminate dead code, and verify correctness at levels Closure Compiler could only dream of
- **Immutability** -- the compiler can prove sharing is safe, enabling zero-cost parallelism and optimal transfer to Web Workers
- **Explicit effects** -- the compiler knows what each function does, enabling automatic SSR/client splitting

React is a runtime library that **guesses** what changed. Canopy is a compiler that **knows**.

---

## Completed Plans

These are done and archived in `done/`:

| Plan | Completed | Notes |
|------|-----------|-------|
| [ESM Output](done/01-esm-output.md) | 2026-03-10 | Per-module ES modules, `/*#__PURE__*/` |
| [Compiler Hygiene](done/02-compiler-hygiene.md) | 2026-03-11 | -Wall -Werror clean, README, CONTRIBUTING |
| Package Ecosystem (72 packages) | 2026-03-10 | All `.can` with FFI JS |
| [Vite Plugin + Granular HMR](done/06-vite-plugin.md) | 2026-03-11 | Model hash, state preservation |
| [Quick Ergonomics](done/26a-quick-ergonomics.md) | 2026-03-11 | Interpolation + nested records |
| [P01 Capability Security](done/important/P01-capability-security.md) | 2026-03-12 | Deny lists wired, per-package tracking, install warnings |
| [P02 TEA at Scale](done/important/P02-tea-at-scale.md) | 2026-03-12 | Platform.Delegate, lazy imports in routes, code splitting |
| [P03 TypeScript Interop](done/important/P03-typescript-interop.md) | 2026-03-13 | .d.ts gen, FFI validation, Web Components with ARIA, npm pipeline |
| [P04 Developer Onboarding](done/important/P04-developer-onboarding.md) | 2026-03-12 | 8 docs, CLI ref, from-React guide |
| [P05 CanopyKit](done/important/P05-canopykit.md) | 2026-03-13 | Route scanner, SSR/SSG, 5 deploy targets, hydration, DataLoader |
| [P06 Abilities + Derive](done/important/P06-abilities-derive.md) | 2026-03-11 | Dictionary-passing JS, 150+ tests |
| [P07 Incremental Compilation](done/important/P07-incremental-compilation.md) | 2026-03-13 | Query engine, disk persistence, worker pool, content-hash invalidation |
| [P08 Data Fetching & Caching](done/important/P08-data-fetching.md) | 2026-03-13 | canopy/http-data, canopy/query, canopy/graphql -- full library suite |
| [P09 Type-Safe Forms](done/important/P09-type-safe-forms.md) | 2026-03-13 | canopy/form with wizard, list fields, validators, headless views |
| [Audit Remediation](done/important/AUDIT-REMEDIATION.md) | 2026-03-12 | Fixed 4 bugs, wired 8 orphaned modules, 46 new tests |
| [P13 Type-Safe i18n](done/nice-to-have/P13-type-safe-i18n.md) | 2026-03-13 | canopy/i18n library complete (10 src, 14 test); compile-time validation future |
| [P15 Animation & Motion](done/nice-to-have/P15-animation-motion.md) | 2026-03-13 | canopy/animation library complete (7 src, 7 test); View Transitions future |
| [P25 Auth Patterns](done/nice-to-have/P25-auth-patterns.md) | 2026-03-13 | canopy/auth + canopy/webauthn complete (10 src, 10 test); Page.protected future |

---

## Current Status: LAUNCH-READY

All essential and important plans (P01-P09) are complete. The compiler is production-ready with:

- **4,472 tests passing** (verified 2026-03-13)
- **Zero warnings** with `-Wall -Werror`
- **Full build pipeline** operational

---

## Future Plans -- Nice-to-Have

### Phase 4: Competitive Advantages

| # | Plan | What | Effort |
|---|------|------|--------|
| **P10** | [Compile-Time Accessibility](nice-to-have/P10-compile-time-a11y.md) | Inaccessible HTML doesn't compile | 4-5 wks |
| **P11** | [Type-Safe CSS](nice-to-have/P11-type-safe-css.md) | CSS properties only accept valid values | 4-6 wks |
| **P12** | [Fine-Grained Reactivity](nice-to-have/P12-fine-grained-reactivity.md) | Compile view functions to direct DOM mutations | 6-8 wks |
| **P14** | [Built-in Property Testing](nice-to-have/P14-property-testing.md) | Auto-derive generators from types | 3-4 wks |
| **P16** | [AI Developer Experience](nice-to-have/P16-ai-developer-experience.md) | Enhanced typed holes, migration tool | 2-3 wks |
| **P17** | [Effect Annotations](nice-to-have/P17-effect-annotations.md) | Inferred effect types visible in signatures | 6-8 wks |

### Phase 5: Future-Proofing

| # | Plan | What | Effort |
|---|------|------|--------|
| **P18** | [WASM Backend](nice-to-have/P18-wasm-backend.md) | Hybrid JS+WASM via WasmGC | 12-16 wks |
| **P19** | [Package Registry](nice-to-have/P19-package-registry.md) | Frontend portal, CDN, private scopes | 3-4 wks |
| **P20** | [Browser DevTools](nice-to-have/P20-browser-devtools.md) | Component tree, message timeline, perf | 3-4 wks |
| **P21** | [Component Library](nice-to-have/P21-component-library.md) | Themed wrappers, docs site | 8-10 wks |
| **P22** | [Edge Computing Target](nice-to-have/P22-edge-target.md) | Cloudflare Workers, Deno Deploy | 3-4 wks |
| **P23** | [Transparent Concurrency](nice-to-have/P23-transparent-concurrency.md) | Compiler-verified parallelism | 5-6 wks |
| **P24** | [Local-First & Sync](nice-to-have/P24-local-first-sync.md) | CRDTs, sync protocol | 6-8 wks |
| **P26** | [Web API Integration](nice-to-have/P26-web-api-integration.md) | Navigation API, Temporal, Popover | 2-3 wks |
| **P27** | [Mobile Deployment](nice-to-have/P27-mobile-deployment.md) | Capacitor/Tauri templates | 2-3 wks |

---

## Existing Assets (Audited 2026-03-13)

| Asset | Status |
|-------|--------|
| 72 stdlib packages | DONE |
| ESM output | DONE |
| canopy test CLI | DONE |
| Capability enforcement (with deny lists) | DONE |
| canopy audit | DONE |
| String interpolation | DONE |
| Nested record updates | DONE |
| Ability system (P06) | DONE |
| Code splitting (5-module pipeline) | DONE |
| Vite plugin + granular HMR | DONE |
| .d.ts generation | DONE |
| FFI TS validation | DONE |
| npm FFI pipeline (resolve + parse + wrap) | DONE |
| Web Component generation (with ARIA) | DONE |
| Deploy adapters (5 targets, wired) | DONE |
| SSR/SSG rendering (JSDOM-based) | DONE |
| Data loader detection (multi-line) | DONE |
| Route validation (in build pipeline) | DONE |
| CanopyKit meta-framework | DONE |
| Incremental compilation (query engine + persistence) | DONE |
| Data fetching libraries (http-data, query, graphql) | DONE |
| Type-safe forms (canopy/form) | DONE |
| TypeScript interop (full pipeline) | DONE |
| Platform.Delegate | DONE |
| Developer documentation (8 guides) | DONE |
| canopy-mcp (12 tools) | DONE |
| canopy-lsp | DONE |
| Playground | DONE |
| Debugger (Chrome extension) | DONE |
| canopy-webidl | DONE |
| Tree-sitter grammar | DONE |
| VSCode extension | DONE |
| Package registry server | DONE |
| Source maps | DONE |
| canopy/i18n (10 src, 14 test) | DONE |
| canopy/animation (7 src, 7 test) | DONE |
| canopy/auth + canopy/webauthn (10 src, 10 test) | DONE |
| canopy/css (9 src, 8 test) | DONE |
| 4,472 tests | GREEN |

---

## Success Criteria

### Must achieve to compete:

- [ ] Sub-2KB hello world bundle (gzipped) — **measured: ~79KB gzipped IIFE** (needs P12 fine-grained reactivity + dead code elimination of runtime)
- [ ] Sub-100ms incremental rebuild — **measured: ~118ms wall clock** (close; P07 query engine brings this down further with warm cache)
- [x] SSR with data loaders working end-to-end
- [x] Vite HMR with state preservation
- [x] TypeScript .d.ts generation
- [x] File-based routing meta-framework (CanopyKit)
- [x] Type-safe forms with schema validation
- [x] Data fetching with RemoteData enforcement
- [x] Gradual adoption path (npm consumption + Web Components in build pipeline)
- [x] String interpolation
- [x] JSON codec deriving (via ability system)
- [x] Capability manifest for security auditing
- [x] Supply chain security story
- [x] canopy test CLI with test runner
- [x] Ability system (type classes) with derive
- [x] Code splitting with lazy imports
- [x] 72 stdlib packages
- [x] Language server + VSCode + Neovim
- [x] MCP server (12 tools)
- [x] Deployment adapters wired (Vercel, Netlify, Node)
- [x] "Canopy for React Devs" onboarding guide
- [x] Incremental compilation with disk cache

---

## What We Learned From Others' Failures

| Language/Framework | What Went Wrong | Our Fix |
|---|---|---|
| **Elm** | No releases since 2019, hostile governance, crippled JS interop, no SSR, no private packages, no type classes, verbose JSON codecs, no string interpolation | Active dev, TypeScript interop, SSR, registry, abilities, derive, interpolation |
| **SolidJS** | Best perf 5 years, 10% adoption -- no meta-framework, tiny ecosystem | CanopyKit, component library, ecosystem-first |
| **Svelte** | Compile-time reactivity but ecosystem 1/10th React after 8 years | Component library sprint, Web Component interop |
| **PureScript** | Excellent type system, steep learning curve, niche adoption | Elm-like simplicity with power under the hood |
| **ReScript** | Good React interop but confused identity | Clear identity, clear mission, clear docs |

## Open Governance Commitment

Elm died from governance, not technology. Canopy commits to:
- **Public roadmap** (this document)
- **Open contribution process** (CONTRIBUTING.md with clear guidelines)
- **Community RFC process** for language changes
- **Semantic versioning** with backwards compatibility guarantees
- **No kernel code lockout** -- FFI is available to all developers equally
- **Multiple maintainers** -- no single point of failure
