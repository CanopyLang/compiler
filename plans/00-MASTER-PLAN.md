# Canopy Master Plan: Beat React, Angular, and Vue

## Mission

Make Canopy the obvious choice for building web applications. Not competitive — **dominant**. When teams evaluate React/Angular/Vue vs Canopy, the answer should be self-evident.

## Why This Is Possible

A purpose-built compiler for a pure functional language has **strictly more information** than any JavaScript runtime framework:

- **Purity** → the compiler knows every data dependency, enabling fine-grained DOM updates no framework can match
- **Strong types** → the compiler can mangle properties, eliminate dead code, and verify correctness at levels Closure Compiler could only dream of
- **Immutability** → the compiler can prove sharing is safe, enabling zero-cost parallelism and optimal transfer to Web Workers
- **Explicit effects** → the compiler knows what each function does, enabling automatic SSR/client splitting

React is a runtime library that **guesses** what changed. Canopy is a compiler that **knows**.

## The Five Gaps That Kill Alternatives

Research shows that technical superiority accounts for ~20% of adoption. SolidJS has had the highest satisfaction rating for five consecutive years and only 10% usage. The other 80% is:

1. **Ecosystem breadth** — React has 206,885 npm dependents, 20+ production component libraries, and answers to every problem
2. **Meta-framework story** — Raw framework projects barely exist; Next.js/Nuxt/SvelteKit are the actual products teams adopt
3. **Incremental adoption** — TypeScript won because every JS file is valid TS; Elm lost because it demanded a complete rewrite
4. **Language ergonomics** — Elm lost developers to boilerplate: no type classes, no derive, no string interpolation, verbose JSON codecs
5. **Supply chain security** — The September 2025 npm attack (chalk, debug, ansi-styles — 2.6B weekly downloads compromised) proved JavaScript's dependency model is fundamentally unsafe. Canopy's capability system is the language-level answer.

Canopy must solve all five, not just build a better compiler.

## Existing Assets (Audited 2026-03-11)

| Asset | Status | Notes |
|-------|--------|-------|
| **71 stdlib packages** | DONE (DRAFT) | All `.can`, FFI JS, canopy.json. 49+ Web API packages. Zero `.elm` files. |
| **ESM output** | DONE | Per-module ES modules, `/*#__PURE__*/` annotations, `canopy-runtime.js`, `--output-format=esm` (default). |
| **canopy test CLI** | DONE | Discovery, compilation, Playwright, NDJSON, --filter/--watch/--headed |
| **Capability enforcement** | DONE | Compile-time validation, manifests, type-level enforcement, canopy.json allow-list, runtime guards, 150+ tests |
| **canopy audit** | DONE | Dependency vulnerability auditing with advisory matching, JSON output |
| **String interpolation** | DONE | Backtick template literals `` `Hello ${name}!` `` fully working. |
| **Nested record updates** | DONE | `{ model \| user.name = x }` syntax — parser + canonicalizer + golden tests |
| **Code splitting** | DONE | 5-module pipeline: analyze, types, generate, manifest, runtime (1,547 lines) |
| **Vite plugin + granular HMR** | DONE | Model type hashing, `__canopy_getModel__`/`__canopy_hotSwap__`, state preservation, full reload on Model type change |
| **.d.ts generation** | DONE | 4 modules, golden tests, auto on build |
| **canopy-mcp** | DONE | MCP server with tools: build, check, getType, findDefinition, getDocs |
| **canopy-lsp** | DONE | Full TypeScript LSP: code actions, diagnostics, completion, hover, rename, formatting |
| **Playground** | DONE | React/Vite/Monaco app with editor, preview, errors, sharing |
| **Debugger** | DONE | Chrome extension (Manifest v3) with Vite/React |
| **canopy-query engine** | 40% DONE | Parse caching works. No dependency tracking, no multi-phase cache. |
| **canopy-webidl** | DONE | WebIDL parser + Canopy type codegen with tests |
| **Tree-sitter grammar** | DONE | Multi-language bindings (Node, C, Python, Go, Swift, Rust, WASM) |
| **VSCode extension** | DONE | Published .vsix with LSP integration, tree-sitter highlighting |
| **Neovim support** | DONE | Plugin configuration files present |
| **FFI system** | DONE | @canopy-type, @canopy-bind, @capability — 284 annotations across packages |
| **Compiler hygiene** | DONE | Zero debug/trace, -Wall -Werror clean, README, CONTRIBUTING, comprehensive Makefile |
| **Backend server** | DONE | Yesod web app with auth, search, storage, analytics, Docker |
| **3,914+ tests** | GREEN | 173 test modules covering unit, integration, property, golden, benchmark |
| **Source maps** | DONE | V3 spec, auto in dev mode |

---

## Completed Plans

These are done and archived in `done/`:

| Old # | Plan | Completed |
|-------|------|-----------|
| 01 | [ESM Output](done/01-esm-output.md) | 2026-03-10 |
| 02 | [Compiler Hygiene](done/02-compiler-hygiene.md) | 2026-03-11 |
| 03 | Package Ecosystem (71 packages) | 2026-03-10 |
| 06 | [Vite Plugin + Granular HMR](done/06-vite-plugin.md) | 2026-03-11 |
| 26a | [Quick Ergonomics (interpolation + nested records)](done/26a-quick-ergonomics.md) | 2026-03-11 |

---

## Active Plans — Renumbered & Reprioritized

All plans below are renumbered cleanly from P01 upward. Old numbers shown for reference.

### Dependency Chain

```
P01 (Capability polish) ── independent, 2 wks
P02 (TEA at Scale) ── independent, 1-2 wks
P03 (TS Interop phases 2-4) ── independent, 4-5 wks ──┐
P04 (Developer Onboarding) ── independent, 4-6 wks     ├──→ P05 (CanopyKit)
                                                         │
P05 (CanopyKit) ── depends on nothing critical ──────────┤
    │                                                     │
    +──→ P07 (Streaming SSR)                              │
    +──→ P02 integration (delegation + routing)           │
                                                          │
P06 (Abilities + Derive) ── depends on stable compiler   │
P08 (Incremental Compilation) ── improves all dev XP     │
P09 (Data Fetching) ── depends on P05 for SSR prefetch   │
P10 (Type-Safe Forms) ── depends on packages             │
```

---

### Phase 1: Quick Wins (Weeks 1-4) — Finish what's 80%+ done

These have the highest ROI because most of the work is already done.

| # | Old # | Plan | What Remains | Effort |
|---|-------|------|-------------|--------|
| **P01** | 13 | [Capability Security Polish](important/P01-capability-security.md) | Deny lists, per-dep audit tracking, new-capability detection alerts | 2 wks |
| **P02** | 08 | [TEA at Scale](important/P02-tea-at-scale.md) | Delegation helper library, CanopyKit router integration stub | 1-2 wks |
| **P03** | 12 | [TypeScript Interop (Phases 2-4)](important/P03-typescript-interop.md) | npm package consumption, Web Component output, tsconfig integration | 4-5 wks |

### Phase 2: Adoption Enablers (Weeks 3-12) — People need to be able to USE Canopy

These are the difference between "cool compiler" and "tool people actually adopt."

| # | Old # | Plan | What | Effort |
|---|-------|------|------|--------|
| **P04** | 27 | [Developer Onboarding](important/P04-developer-onboarding.md) | "Canopy for React Devs" guide, 3+ example apps, migration codemods, deploy playground | 4-6 wks |
| **P05** | 05 | [CanopyKit Meta-Framework](important/P05-canopykit.md) | File-based routing, SSG/SSR modes, data loading, layouts, API routes, `canopy kit` CLI | 8-12 wks |
| **P06** | 26b | [Abilities + Derive](important/P06-abilities-derive.md) | Roc-style type classes, `ability`/`impl` keywords, JSON codec deriving, Eq/Ord/Show/Encode/Decode | 8-12 wks |

### Phase 3: Production Ready (Weeks 10-20) — Make real apps possible

| # | Old # | Plan | What | Effort |
|---|-------|------|------|--------|
| **P07** | 07 | [Streaming SSR](important/P07-streaming-ssr.md) | Dual compilation, HTML string gen, resumability, streaming chunks, model serialization | 4-6 wks |
| **P08** | 09 | [Incremental Compilation](important/P08-incremental-compilation.md) | Salsa-style queries, dependency tracking, multi-phase cache, error recovery, disk persistence | 5-7 wks |
| **P09** | 25 | [Data Fetching & Caching](important/P09-data-fetching.md) | RemoteData, Query/Mutation, dedup, stale-while-revalidate, optimistic updates, pagination | 4-5 wks |
| **P10** | 24 | [Type-Safe Forms](important/P10-type-safe-forms.md) | Schema-driven forms, auto-generated UI, compile-time validation, multi-step wizards | 4-5 wks |

### Phase 4: Competitive Advantages (Weeks 20-36) — Things React/Vue/Angular CANNOT do

| # | Old # | Plan | What | Effort |
|---|-------|------|------|--------|
| **P11** | 14 | [Compile-Time Accessibility](nice-to-have/P11-compile-time-a11y.md) | Inaccessible HTML doesn't compile: alt text, headings, labels, ARIA | 4-5 wks |
| **P12** | 15 | [Type-Safe CSS](nice-to-have/P12-type-safe-css.md) | CSS properties only accept valid values, compile-time extraction | 4-6 wks |
| **P13** | 04 | [Fine-Grained Reactivity](nice-to-have/P13-fine-grained-reactivity.md) | Compile view functions to direct DOM mutations, no VDOM | 6-8 wks |
| **P14** | 18 | [Type-Safe i18n](nice-to-have/P14-type-safe-i18n.md) | Missing translations are compile errors | 3-4 wks |
| **P15** | 17 | [Built-in Property Testing](nice-to-have/P15-property-testing.md) | Auto-derive generators from types, first-class fuzz | 3-4 wks |
| **P16** | 23 | [Animation & Motion](nice-to-have/P16-animation-motion.md) | View Transitions API, springs, scroll-driven, gestures | 4-6 wks |
| **P17** | 31 | [AI Developer Experience](nice-to-have/P17-ai-developer-experience.md) | Enhanced typed holes, migration tool, MCP server improvements | 3-4 wks |

### Phase 5: Future-Proofing (Weeks 36+)

| # | Old # | Plan | What | Effort |
|---|-------|------|------|--------|
| **P18** | 16 | [Effect Annotations](nice-to-have/P18-effect-annotations.md) | Inferred effect types visible in signatures (Phase 1) | 6-8 wks |
| **P19** | 19 | [WASM Backend](nice-to-have/P19-wasm-backend.md) | Hybrid JS+WASM via WasmGC, WASI target | 12-16 wks |
| **P20** | 22 | [Package Registry](nice-to-have/P20-package-registry.md) | Self-hosted registry, private packages, security advisories | 6-8 wks |
| **P21** | 10 | [Browser DevTools](nice-to-have/P21-browser-devtools.md) | Component tree, state inspector, time-travel debugging | 4-6 wks |
| **P22** | 11 | [Component Library](nice-to-have/P22-component-library.md) | 45+ accessible, themed components | 12-16 wks |
| **P23** | 20 | [Edge Computing Target](nice-to-have/P23-edge-target.md) | Cloudflare Workers, Deno Deploy, Vercel Edge | 3-4 wks |
| **P24** | 21 | [Transparent Concurrency](nice-to-have/P24-transparent-concurrency.md) | Web Workers as compiler optimization | 6-8 wks |
| **P25** | 29 | [Local-First & Sync](nice-to-have/P25-local-first-sync.md) | CRDTs, offline-first, real-time collaboration | 8-10 wks |
| **P26** | 28 | [Auth Patterns](nice-to-have/P26-auth-patterns.md) | OAuth, JWT, protected routes, RBAC | 3-4 wks |
| **P27** | 30 | [Web API Integration](nice-to-have/P27-web-api-integration.md) | Navigation API, Temporal, Popover, Container Queries | 3-4 wks |
| **P28** | 32 | [Mobile Deployment](nice-to-have/P28-mobile-deployment.md) | Capacitor/Tauri integration | 2-3 wks |

---

## Priority Rationale

### Why this ordering?

**Phase 1 first** because P01-P03 are nearly done. Finishing them costs 2-5 weeks each and delivers huge value. Capability polish completes our security story. TEA at Scale is 90% done. TypeScript Interop phases 2-4 enable the gradual adoption story.

**Phase 2 before Phase 3** because without onboarding docs, example apps, and a meta-framework, nobody will use the production features we build in Phase 3. CanopyKit (P05) is THE product — file-based routing is table stakes in 2026. Abilities (P06) eliminates Elm's #1 pain point (JSON boilerplate).

**Phase 3 in parallel with late Phase 2** because streaming SSR, data fetching, and forms are what production apps actually need. These can begin once CanopyKit routing is scaffolded.

**Phase 4 is the moat** — compile-time accessibility, type-safe CSS, and fine-grained reactivity are things JavaScript frameworks structurally cannot do. These are the "Canopy is categorically better" features.

**Phase 5 is future-proofing** — WASM, effects, edge computing. Important but not adoption-critical today.

### What moved up?

- **Developer Onboarding (P04)** — elevated from Tier 2 to Phase 2. Without docs and examples, nothing else matters.
- **Type-Safe i18n (P14)** — elevated from Tier 3 to Phase 4. Compile-time translation checking is a strong differentiator and relatively low effort.

### What moved down?

- **Animation & Motion (P16)** — demoted from important/ to Phase 4. CSS animations and View Transitions API are usable without compiler support. Not an adoption blocker.
- **AI Developer Experience (P17)** — MCP server already works. Enhancements are nice-to-have, not critical path.
- **Browser DevTools (P21)** — Chrome extension exists. Full component tree/time-travel is impressive but not what blocks adoption.

---

## Mapping: Old Numbers → New Numbers

| Old # | New # | Plan |
|-------|-------|------|
| 04 | P13 | Fine-Grained Reactivity |
| 05 | P05 | CanopyKit Meta-Framework |
| 07 | P07 | Streaming SSR |
| 08 | P02 | TEA at Scale |
| 09 | P08 | Incremental Compilation |
| 10 | P21 | Browser DevTools |
| 11 | P22 | Component Library |
| 12 | P03 | TypeScript Interop |
| 13 | P01 | Capability Security |
| 14 | P11 | Compile-Time Accessibility |
| 15 | P12 | Type-Safe CSS |
| 16 | P18 | Effect Annotations |
| 17 | P15 | Built-in Property Testing |
| 18 | P14 | Type-Safe i18n |
| 19 | P19 | WASM Backend |
| 20 | P23 | Edge Computing |
| 21 | P24 | Transparent Concurrency |
| 22 | P20 | Package Registry |
| 23 | P16 | Animation & Motion |
| 24 | P10 | Type-Safe Forms |
| 25 | P09 | Data Fetching & Caching |
| 26b | P06 | Abilities + Derive |
| 27 | P04 | Developer Onboarding |
| 28 | P26 | Auth Patterns |
| 29 | P25 | Local-First & Sync |
| 30 | P27 | Web API Integration |
| 31 | P17 | AI Developer Experience |
| 32 | P28 | Mobile Deployment |

---

## Success Criteria

### Must achieve to compete:
- [ ] Sub-2KB hello world bundle (gzipped)
- [ ] Sub-100ms incremental rebuild
- [ ] Streaming SSR
- [x] Vite HMR with state preservation
- [x] TypeScript .d.ts generation
- [ ] File-based routing meta-framework
- [ ] Type-safe forms with schema validation
- [ ] Data fetching with RemoteData enforcement
- [ ] Gradual adoption path (use Canopy inside React projects)
- [x] String interpolation
- [ ] JSON codec deriving
- [x] Capability manifest for security auditing
- [x] Supply chain security story
- [x] canopy test CLI with test runner
- [ ] canopy/test library package for developers

### Must achieve to dominate:
- [ ] Inaccessible HTML doesn't compile
- [ ] CSS type errors caught at compile time
- [ ] Missing translations are compile errors
- [ ] Effect types visible in every function signature
- [ ] Zero-config Web Worker parallelism
- [ ] WASM backend for compute-heavy modules (WasmGC)
- [ ] Edge deployment with `canopy build --target edge`
- [ ] Property-based testing from type signatures
- [ ] Local-first sync with CRDTs
- [ ] Privacy-preserving capabilities (GDPR consent at type level)
- [ ] View Transitions API integrated with router
- [ ] Abilities system (type classes) with derive
- [x] AI-assisted development (MCP server with 5 tools)

---

## What We Learned From Others' Failures

| Language/Framework | What Went Wrong | Our Fix |
|---|---|---|
| **Elm** | No releases since 2019, hostile governance, crippled JS interop, no SSR, no private packages, no type classes, verbose JSON codecs, no string interpolation | Active dev, TypeScript interop, SSR, registry, abilities, derive, interpolation |
| **SolidJS** | Best perf 5 years, 10% adoption — no meta-framework, tiny ecosystem | CanopyKit, component library, ecosystem-first |
| **Svelte** | Compile-time reactivity but ecosystem 1/10th React after 8 years | Component library sprint, Web Component interop |
| **PureScript** | Excellent type system, steep learning curve, niche adoption | Elm-like simplicity with power under the hood |
| **ReScript** | Good React interop but confused identity | Clear identity, clear mission, clear docs |
| **Gren** | Elm fork focusing on syntax/data structures, no FFI, no capability security | We have FFI + capabilities + meta-framework — broader vision |
| **Roc** | Ambitious type system, not 1.0, not frontend-focused, rewriting compiler from Rust to Zig | We're frontend-first with a working compiler |

## What We Learned From TypeScript's Success

1. **Every existing project is valid** — gradual adoption with zero rewrite
2. **Frameworks chose it** — Angular, Next.js defaulted to TS
3. **Tooling was first-class** — VS Code built in TS
4. **Measurable ROI** — 40% reduction in maintenance costs
5. **AI reinforcement** — AI tools prefer typed code

**Our adaptation**: We can't be a superset of JS, but we CAN:
- Emit Web Components usable from React/Vue/Angular (gradual adoption)
- Provide TypeScript type definitions for all Canopy outputs
- Ship the best tooling in the industry (LSP already built, DevTools coming)
- Demonstrate measurable wins (zero runtime crashes, smaller bundles, faster loads)
- Make Canopy the most AI-friendly language (strong types + explicit effects + precise errors + MCP server)

## What We Learned From the September 2025 npm Attack

The "Shai-Hulud" worm compromised chalk, debug, ansi-styles, and strip-ansi — packages downloaded 2.6 billion times per week. A second wave in November 2025 hit 25,000+ GitHub repositories. JavaScript's npm ecosystem is "uniquely vulnerable" due to deep dependency trees and install-time code execution.

**This is our marketing moment.** In Canopy:
- A dependency cannot access the network without the app granting `network` capability
- A dependency cannot read the filesystem without `filesystem` capability
- A dependency cannot access the camera, microphone, or geolocation without explicit `permission` grants
- The capability manifest shows every browser API the app uses, traceable to exact source locations
- CI pipelines can enforce capability allow/deny lists at compile time

No other frontend language offers this. React, Vue, Angular, Svelte — none of them can prevent a malicious dependency from exfiltrating data. Canopy can.

## Open Governance Commitment

Elm died from governance, not technology. Canopy commits to:
- **Public roadmap** (this document)
- **Open contribution process** (CONTRIBUTING.md with clear guidelines)
- **Community RFC process** for language changes
- **Semantic versioning** with backwards compatibility guarantees
- **No kernel code lockout** — FFI is available to all developers equally
- **Multiple maintainers** — no single point of failure
