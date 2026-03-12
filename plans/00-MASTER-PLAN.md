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

## The Five Gaps That Kill Alternatives

Research shows that technical superiority accounts for ~20% of adoption. SolidJS has had the highest satisfaction rating for five consecutive years and only 10% usage. The other 80% is:

| Gap | Status | Notes |
|-----|--------|-------|
| **1. Ecosystem breadth** | LARGELY CLOSED | 72 stdlib packages (core, html, json, http, browser, router, ssr, graphql, auth, etc.). 49+ Web API packages. All `.can` with FFI JS. |
| **2. Meta-framework story** | 60-70% DONE | CanopyKit has file-based routing, SSG, layouts, error boundaries, API routes, scaffolding, dev server, build pipeline. Missing: SSR data loader detection, deployment adapters. |
| **3. Incremental adoption** | PHASE 1 DONE | .d.ts generation complete. Web Components basic version done. Phases 2-4 (npm consumption, enhanced WC, integration testing) remain. |
| **4. Language ergonomics** | CLOSED | Ability system production-ready (150+ tests). String interpolation done. Nested record updates done. JSON codec deriving via abilities. |
| **5. Supply chain security** | 90% DONE | Compile-time capability enforcement, 284 FFI annotations, manifests, runtime guards, 45+ tests. Deny list parsed but not wired. Per-package tracking infrastructure exists but empty. |

## Existing Assets (Audited 2026-03-11)

| Asset | Status | Notes |
|-------|--------|-------|
| **72 stdlib packages** | DONE | All `.can`, FFI JS, canopy.json. 49+ Web API packages. Zero `.elm` files. |
| **ESM output** | DONE | Per-module ES modules, `/*#__PURE__*/` annotations, `canopy-runtime.js`, `--output-format=esm` (default). |
| **canopy test CLI** | DONE | Discovery, compilation, Playwright, NDJSON, --filter/--watch/--headed |
| **Capability enforcement** | DONE | Compile-time validation, manifests, type-level enforcement, canopy.json allow-list, runtime guards, 45+ tests |
| **canopy audit** | DONE | Dependency vulnerability auditing with advisory matching, JSON output |
| **String interpolation** | DONE | Backtick template literals `` `Hello ${name}!` `` fully working. |
| **Nested record updates** | DONE | `{ model \| user.name = x }` syntax -- parser + canonicalizer + golden tests |
| **Ability system (P06)** | DONE | Parse, canonicalize, type-constrain, optimize, codegen. Dictionary-passing JS. 150+ tests. |
| **Code splitting** | DONE | 5-module pipeline: analyze, types, generate, manifest, runtime (1,547 lines) |
| **Vite plugin + granular HMR** | DONE | Model type hashing, state preservation, full reload on Model type change |
| **.d.ts generation** | DONE | 4 modules, golden tests, auto on build |
| **FFI TS validation** | DONE | TypeScriptValidation.hs, 181 lines, 32 tests |
| **Web Component generation** | BASIC DONE | WebComponent.hs, 177 lines |
| **canopy-mcp** | DONE | MCP server with 12 tools |
| **canopy-lsp** | DONE | Full TypeScript LSP: code actions, diagnostics, completion, hover, rename, formatting |
| **Playground** | DONE | React/Vite/Monaco app with editor, preview, errors, sharing |
| **Debugger** | DONE | Chrome extension (Manifest v3) with Vite/React |
| **canopy-query engine** | 60-65% DONE | Parse caching, some dependency tracking. Multi-phase cache and full invalidation remain. |
| **canopy-webidl** | DONE | WebIDL parser + Canopy type codegen with tests |
| **Tree-sitter grammar** | DONE | Multi-language bindings (Node, C, Python, Go, Swift, Rust, WASM) |
| **VSCode extension** | DONE | Published .vsix with LSP integration, tree-sitter highlighting |
| **Neovim support** | DONE | Plugin configuration files present |
| **FFI system** | DONE | @canopy-type, @canopy-bind, @capability -- 284 annotations across packages |
| **Compiler hygiene** | DONE | Zero debug/trace, -Wall -Werror clean, README, CONTRIBUTING, comprehensive Makefile |
| **Package registry server** | DONE | Haskell/Yesod web app with auth, search, storage, analytics, Docker |
| **Source maps** | DONE | V3 spec, auto in dev mode |
| **CanopyKit** | 60-70% DONE | File-based routing, SSG, layouts, error boundaries, API routes, scaffolding, dev server, build pipeline |
| **6 example apps** | DONE | Demonstrating various features and patterns |
| **3,957 tests** | GREEN | All passing across unit, integration, property, golden, benchmark |

---

## Completed Plans

These are done and archived in `done/`:

| Old # | Plan | Completed |
|-------|------|-----------|
| 01 | [ESM Output](done/01-esm-output.md) | 2026-03-10 |
| 02 | [Compiler Hygiene](done/02-compiler-hygiene.md) | 2026-03-11 |
| 03 | Package Ecosystem (72 packages) | 2026-03-10 |
| 06 | [Vite Plugin + Granular HMR](done/06-vite-plugin.md) | 2026-03-11 |
| P06 | Abilities + Derive (production-ready) | 2026-03-11 |
| 26a | [Quick Ergonomics (interpolation + nested records)](done/26a-quick-ergonomics.md) | 2026-03-11 |

---

## Active Plans -- Renumbered and Reprioritized

All plans below are renumbered cleanly from P01 upward. Old numbers shown for reference.

### What's Actually Left: The True Blockers

The compiler is 98%+ complete. The language works. The tooling exists. What blocks launch is:

1. **CanopyKit SSR + deployment** -- SSR data loader detection, deployment adapters (Vercel, Cloudflare, Netlify), production SSR runtime
2. **TypeScript interop phases 2-4** -- npm package consumption is the gradual adoption story
3. **Developer onboarding** -- docs, guides, example apps, migration paths
4. **Capability deny list wiring** -- parsed but dead code, needs 1 week to complete
5. **Delegation helpers** -- ~50 lines of library code, not a compiler change

### Dependency Chain

```
P01 (Capability polish) -- independent, 1 wk ─────────────────────┐
P02 (TEA at Scale) -- independent, 3-4 days                       │
P03 (TS Interop phases 2-4) -- independent, 3-4 wks ──┐           │
P04 (Developer Onboarding) -- independent, 4-6 wks    ├──> P05    │
                                                        │  (Kit)   │
P05 (CanopyKit completion) -- depends on nothing ──────┤           │
    │                                                   │           │
    +──> P08 (Data Fetching SSR bridge)                 │           │
    +──> P02 integration (delegation + routing)         │           │
                                                                    │
P07 (Incremental Compilation) -- improves all dev XP               │
P08 (Data Fetching) -- depends on P05 for SSR prefetch             │
```

---

### Phase 1: Finish Line (Weeks 1-3) -- Complete what's 90%+ done

These are days of work, not weeks. Highest ROI items in the entire plan.

| # | Plan | What Remains | Effort |
|---|------|-------------|--------|
| **P01** | [Capability Security Polish](important/P01-capability-security.md) | Wire deny list in Make/Output.hs, populate _manifestByPackage, new-capability detection | 1 wk |
| **P02** | [TEA at Scale](important/P02-tea-at-scale.md) | Platform.Delegate library module (~50 lines), CanopyKit router integration, docs | 3-4 days |

### Phase 2: Adoption Enablers (Weeks 2-8) -- People need to be able to USE Canopy

| # | Plan | What | Effort |
|---|------|------|--------|
| **P03** | [TypeScript Interop (Phases 2-4)](important/P03-typescript-interop.md) | npm package consumption, enhanced Web Components, integration testing | 3-4 wks |
| **P04** | [Developer Onboarding](important/P04-developer-onboarding.md) | "Canopy for React Devs" guide, example apps, migration codemods, deploy playground | 4-6 wks |
| **P05** | [CanopyKit Completion](important/P05-canopykit.md) | SSR data loader detection, deployment adapters, production SSR runtime | 3-4 wks |

### Phase 3: Production Ready (Weeks 6-16) -- Make real apps possible

| # | Plan | What | Effort |
|---|------|------|--------|
| **P07** | [Incremental Compilation](important/P07-incremental-compilation.md) | Persistence, dependency tracking, shared worker cache, file watching, error recovery | 5-6 wks |
| **P08** | [Data Fetching & Caching](important/P08-data-fetching.md) | SSR cache bridge, DataLoader detection, request dedup (libraries already exist) | 2-3 wks |
| **P09** | [Type-Safe Forms](important/P09-type-safe-forms.md) | Dynamic fields, multi-step wizards, schema-driven codegen (canopy/form already exists) | 3-4 wks |

### Phase 4: Competitive Advantages (Weeks 16-32) -- Things React/Vue/Angular CANNOT do

| # | Plan | What | Effort |
|---|------|------|--------|
| **P10** | [Compile-Time Accessibility](nice-to-have/P10-compile-time-a11y.md) | Inaccessible HTML doesn't compile: alt text, headings, labels, ARIA | 4-5 wks |
| **P11** | [Type-Safe CSS](nice-to-have/P11-type-safe-css.md) | CSS properties only accept valid values, compile-time extraction | 4-6 wks |
| **P12** | [Fine-Grained Reactivity](nice-to-have/P12-fine-grained-reactivity.md) | Compile view functions to direct DOM mutations, no VDOM | 6-8 wks |
| **P13** | [Type-Safe i18n](nice-to-have/P13-type-safe-i18n.md) | Missing translations are compile errors (canopy/i18n exists) | 2-3 wks |
| **P14** | [Built-in Property Testing](nice-to-have/P14-property-testing.md) | Auto-derive generators from types (canopy/test exists) | 3-4 wks |
| **P15** | [Animation & Motion](nice-to-have/P15-animation-motion.md) | View Transitions, scroll-driven, gestures (canopy/animation exists) | 2-3 wks |
| **P16** | [AI Developer Experience](nice-to-have/P16-ai-developer-experience.md) | Enhanced typed holes, migration tool (MCP + LSP exist) | 2-3 wks |
| **P17** | [Effect Annotations](nice-to-have/P17-effect-annotations.md) | Inferred effect types visible in signatures | 6-8 wks |

### Phase 5: Future-Proofing (Weeks 32+)

| # | Plan | What | Effort |
|---|------|------|--------|
| **P18** | [WASM Backend](nice-to-have/P18-wasm-backend.md) | Hybrid JS+WASM via WasmGC, WASI target | 12-16 wks |
| **P19** | [Package Registry](nice-to-have/P19-package-registry.md) | Frontend portal, CDN, private scopes (backend already exists) | 3-4 wks |
| **P20** | [Browser DevTools](nice-to-have/P20-browser-devtools.md) | Component tree, message timeline, perf (extension already exists) | 3-4 wks |
| **P21** | [Component Library](nice-to-have/P21-component-library.md) | Themed wrappers, docs site (headless-ui + 6 component packages exist) | 8-10 wks |
| **P22** | [Edge Computing Target](nice-to-have/P22-edge-target.md) | Cloudflare Workers, Deno Deploy, Vercel Edge | 3-4 wks |
| **P23** | [Transparent Concurrency](nice-to-have/P23-transparent-concurrency.md) | Compiler-verified parallelism (canopy/web-worker exists) | 5-6 wks |
| **P24** | [Local-First & Sync](nice-to-have/P24-local-first-sync.md) | CRDTs, sync protocol (indexed-db + websocket exist) | 6-8 wks |
| **P25** | [Auth Patterns](nice-to-have/P25-auth-patterns.md) | CanopyKit Page.protected (canopy/auth already exists) | 1-2 wks |
| **P26** | [Web API Integration](nice-to-have/P26-web-api-integration.md) | Navigation API, Temporal, Popover, Container Queries | 2-3 wks |
| **P27** | [Mobile Deployment](nice-to-have/P27-mobile-deployment.md) | Capacitor/Tauri templates (canopy/pwa exists) | 2-3 wks |

---

## Critical Path to Launch

The minimum viable launch requires completing Phases 1 and 2. Here is the realistic critical path:

```
Week 1:   P01 (capability deny wiring) + P02 (delegation helpers)
Week 2-3: P03 begins (TS interop phase 2) + P04 begins (onboarding docs)
Week 3-4: P05 (CanopyKit SSR + deploy adapters)
Week 5-6: P03 continues (TS interop phase 3-4) + P04 continues
Week 6-8: P03 wraps up + P04 wraps up + P05 wraps up
          --------- LAUNCH-READY ---------
Week 8+:  Phase 3 begins (SSR streaming, incremental compilation, data fetching)
```

**Total time to launch-ready: 6-8 weeks** assuming focused execution.

The true blockers are not compiler work -- they are:
1. **CanopyKit SSR data loader detection** -- the router needs to know which routes fetch data
2. **Deployment adapters** -- `canopy kit build --target vercel` must produce deployable output
3. **Onboarding documentation** -- without "Canopy for React Devs", nobody will try it
4. **npm package consumption (P03 Phase 2)** -- without this, the gradual adoption story is theoretical

## Priority Rationale

### Why this ordering?

**Phase 1 first** because P01 and P02 are days of work, not weeks. Capability deny list is parsed but the validation function is dead code -- wiring it is a one-day task. Platform.Delegate is ~50 lines of library code.

**Phase 2 before Phase 3** because without onboarding docs, example apps, and CanopyKit deployment, nobody will use the production features we build in Phase 3. TypeScript interop Phase 2 (npm consumption) is THE gradual adoption story -- it's how teams try Canopy without rewriting.

**Phase 3 in parallel with late Phase 2** because streaming SSR, data fetching, and forms are what production apps actually need. These can begin once CanopyKit routing is complete.

**Phase 4 is the moat** -- compile-time accessibility, type-safe CSS, and fine-grained reactivity are things JavaScript frameworks structurally cannot do.

**Phase 5 is future-proofing** -- WASM, effects, edge computing. Important but not adoption-critical today.

---

## Mapping: Old Numbers to New Numbers

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
| 26b | P06 | Abilities + Derive (DONE) |
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
- [x] File-based routing meta-framework (CanopyKit)
- [ ] Type-safe forms with schema validation
- [ ] Data fetching with RemoteData enforcement
- [ ] Gradual adoption path (use Canopy inside React projects)
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
- [ ] canopy/test library package for developers
- [ ] Deployment adapters (Vercel, Cloudflare, Netlify)
- [ ] "Canopy for React Devs" onboarding guide

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
- [x] AI-assisted development (MCP server with 12 tools)

---

## What We Learned From Others' Failures

| Language/Framework | What Went Wrong | Our Fix |
|---|---|---|
| **Elm** | No releases since 2019, hostile governance, crippled JS interop, no SSR, no private packages, no type classes, verbose JSON codecs, no string interpolation | Active dev, TypeScript interop, SSR, registry, abilities, derive, interpolation |
| **SolidJS** | Best perf 5 years, 10% adoption -- no meta-framework, tiny ecosystem | CanopyKit, component library, ecosystem-first |
| **Svelte** | Compile-time reactivity but ecosystem 1/10th React after 8 years | Component library sprint, Web Component interop |
| **PureScript** | Excellent type system, steep learning curve, niche adoption | Elm-like simplicity with power under the hood |
| **ReScript** | Good React interop but confused identity | Clear identity, clear mission, clear docs |
| **Gren** | Elm fork focusing on syntax/data structures, no FFI, no capability security | We have FFI + capabilities + meta-framework -- broader vision |
| **Roc** | Ambitious type system, not 1.0, not frontend-focused, rewriting compiler from Rust to Zig | We're frontend-first with a working compiler |

## What We Learned From TypeScript's Success

1. **Every existing project is valid** -- gradual adoption with zero rewrite
2. **Frameworks chose it** -- Angular, Next.js defaulted to TS
3. **Tooling was first-class** -- VS Code built in TS
4. **Measurable ROI** -- 40% reduction in maintenance costs
5. **AI reinforcement** -- AI tools prefer typed code

**Our adaptation**: We can't be a superset of JS, but we CAN:
- Emit Web Components usable from React/Vue/Angular (gradual adoption)
- Provide TypeScript type definitions for all Canopy outputs
- Ship the best tooling in the industry (LSP, DevTools, MCP server all built)
- Demonstrate measurable wins (zero runtime crashes, smaller bundles, faster loads)
- Make Canopy the most AI-friendly language (strong types + explicit effects + precise errors + MCP server)

## What We Learned From the September 2025 npm Attack

The "Shai-Hulud" worm compromised chalk, debug, ansi-styles, and strip-ansi -- packages downloaded 2.6 billion times per week. A second wave in November 2025 hit 25,000+ GitHub repositories. JavaScript's npm ecosystem is "uniquely vulnerable" due to deep dependency trees and install-time code execution.

**This is our marketing moment.** In Canopy:
- A dependency cannot access the network without the app granting `network` capability
- A dependency cannot read the filesystem without `filesystem` capability
- A dependency cannot access the camera, microphone, or geolocation without explicit `permission` grants
- The capability manifest shows every browser API the app uses, traceable to exact source locations
- CI pipelines can enforce capability allow/deny lists at compile time

No other frontend language offers this. React, Vue, Angular, Svelte -- none of them can prevent a malicious dependency from exfiltrating data. Canopy can.

## Open Governance Commitment

Elm died from governance, not technology. Canopy commits to:
- **Public roadmap** (this document)
- **Open contribution process** (CONTRIBUTING.md with clear guidelines)
- **Community RFC process** for language changes
- **Semantic versioning** with backwards compatibility guarantees
- **No kernel code lockout** -- FFI is available to all developers equally
- **Multiple maintainers** -- no single point of failure
