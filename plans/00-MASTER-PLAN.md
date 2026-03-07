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

## Existing Assets (Audited 2026-03-07)

The codebase audit reveals substantial infrastructure already built:

| Asset | Status | Notes |
|-------|--------|-------|
| **All 16 stdlib packages** | DONE | All `.can`, FFI JS, canopy.json, tests. Zero `.elm` files. |
| **canopy test CLI** | DONE | Discovery, compilation, Playwright, NDJSON, --filter/--watch/--headed |
| **Capability enforcement** | DONE | Compile-time validation, manifests, type-level enforcement, 45+ tests |
| **canopy audit** | DONE | Dependency vulnerability auditing with advisory matching, JSON output |
| **String interpolation** | 90% DONE | `[i\|Hello #{name}!\|]` fully works. Only `${}` syntax in regular strings missing. |
| **Code splitting** | DONE | 5-module pipeline: analyze, types, generate, manifest, runtime |
| **canopy-mcp** | DONE | 5 MCP tools: build, check, getType, findDefinition, getDocs |
| **canopy-lsp** | DONE | Full TypeScript LSP: 25+ code actions, diagnostics, completion, hover, etc. |
| **Playground** | DONE | React/Vite app with editor, preview, errors, examples, sharing |
| **Debugger** | DONE | Vite-based debugging tool |
| **canopy-query engine** | 40% DONE | Parse caching works. No dependency tracking, no multi-phase cache. |
| **canopy-webidl** | DONE | Web API type generation with tests |
| **Tree-sitter grammar** | DONE | Syntax highlighting ready |
| **VSCode extension** | DONE | Editor support with .vsix |
| **FFI system** | DONE | @canopy-type, @canopy-bind, @capability — 284 annotations across packages |
| **3,707+ tests** | GREEN | Solid foundation |

---

## Critical Dependency Chain

```
Plan 26a (${}  interpolation + nested records) ── independent, ship immediately
Plan 02 (Hygiene) ── independent, ship immediately

Plan 01 (ESM Output) ──────────────────────────────────────────┐
    |                                                           |
    +---> Plan 06 (Vite Plugin) ---> Plan 05 (CanopyKit) ------+
    |                                                           |
    +---> Plan 12 (TS Interop) --------------------------------+
    |                                                           |
    +---> Plan 09 (Incremental) --> Plan 06 (Vite HMR speed)   |
                                                                |
Plan 13 (Capability Supply Chain) ── independent (core done)   |
Plan 27 (Onboarding) ── independent, critical for adoption     |
Plan 31 (AI DX) ── independent (MCP server exists)             |
                                                                |
Plan 26b (Abilities + Derive) ── depends on stable compiler    |
```

**Plan 01 (ESM) is the single gatekeeper. Everything downstream is blocked on it.**

**Plan 03 (Packages) is COMPLETE — no longer a blocker.**

---

## Tier 0: Foundation (Weeks 1-4)

Fix what's broken. No new features until the base is solid.

| # | Plan | What | Status | Effort |
|---|------|------|--------|--------|
| 02 | [Compiler Hygiene](02-compiler-hygiene.md) | Fix debug stmts, Makefile, -Wall, README | Needs audit | 1 wk |
| 26a | [Quick Ergonomics](26a-quick-ergonomics.md) | `${}` interpolation in strings + nested record updates | Interpolation 90% done, nested records needed | 1 wk |
| 01 | [ESM Output](01-esm-output.md) | Replace IIFE with native ES modules | **Not started — gates everything** | 2-3 wks |
| 03 | [Package Ecosystem](03-package-ecosystem.md) | ~~Complete all 16 stdlib packages~~ | **DONE** — only canopy/test library remains | 3-5 days |

## Tier 1: Usable Platform (Months 2-5)

Make it work for real applications. A developer should be able to build and ship a production app.

| # | Plan | What | Status | Effort |
|---|------|------|--------|--------|
| 06 | [Vite Plugin + HMR](06-vite-plugin.md) | First-class Vite integration with hot module replacement | Not started | 2-3 wks |
| 05 | [CanopyKit Meta-Framework](05-canopykit.md) | File-based routing, SSG, dev server | Not started | 8-12 wks |
| 12 | [TypeScript Interop](12-typescript-interop.md) | Emit .d.ts, Web Component output, consume npm | Not started | 6-8 wks |
| 13 | [Capability Security](13-capability-enforcement.md) | ~~Activate capability system~~ Supply chain story + allow/deny lists | Core enforcement DONE | 2-3 wks |
| 26b | [Abilities + Derive](26b-abilities-derive.md) | Type classes (Roc-style), JSON codec deriving | Not started | 8-12 wks |
| 27 | [Developer Onboarding](27-developer-onboarding.md) | Playground, React migration guide, gradual adoption | Playground DONE | 4-6 wks |

## Tier 2: Production Ready (Months 5-9)

Make it irresistible. Developers who try Canopy should never want to go back.

| # | Plan | What | Status | Effort |
|---|------|------|--------|--------|
| 09 | [Incremental Compilation](09-incremental-compilation.md) | Salsa-style query system, sub-100ms rebuilds, error recovery | Query engine 40% built | 5-7 wks |
| 07 | [Streaming SSR](07-ssr-resumability.md) | Server rendering (Phase 1: basic SSR) | Not started | 4-6 wks |
| 08 | [TEA at Scale](08-state-architecture.md) | Route code splitting + delegation helpers | Code splitting infrastructure DONE | 1-2 wks |
| 24 | [Type-Safe Forms](24-type-safe-forms.md) | Schema-driven forms with compile-time validation | Not started | 4-5 wks |
| 25 | [Data Fetching & Caching](25-data-fetching.md) | RemoteData, stale-while-revalidate, optimistic updates | Not started | 4-5 wks |
| 31 | [AI Developer Experience](31-ai-developer-experience.md) | MCP server enhancement, typed holes, migration tool | MCP server with 5 tools DONE | 3-4 wks |

## Tier 3: Competitive Advantages (Months 9-13)

Features that make Canopy categorically better — things React/Angular/Vue **cannot** do.

| # | Plan | What | Status | Effort |
|---|------|------|--------|--------|
| 04 | [Fine-Grained Reactivity](04-fine-grained-reactivity.md) | Compile view functions to direct DOM mutations | Not started | 6-8 wks |
| 14 | [Compile-Time Accessibility](14-compile-time-a11y.md) | Inaccessible HTML doesn't compile | Not started | 4-5 wks |
| 19 | [WASM Backend](19-wasm-backend.md) | Hybrid JS+WASM compilation via WasmGC | Not started | 12-16 wks |
| 16 | [Effect Annotations](16-algebraic-effects.md) | Inferred effect types visible in signatures | Not started | 6-8 wks |
| 15 | [Type-Safe CSS](15-type-safe-css.md) | CSS properties only accept valid values | Not started | 4-6 wks |
| 29 | [Local-First & Sync](29-local-first-sync.md) | CRDTs, offline-first, real-time collaboration | Not started | 8-10 wks |
| 17 | [Built-in Property Testing](17-property-testing.md) | Auto-derive generators, first-class fuzz | Not started | 3-4 wks |
| 18 | [Type-Safe i18n](18-type-safe-i18n.md) | Missing translations are compile errors | Not started | 3-4 wks |

## Tier 4: Future-Proofing (Months 13+)

Position Canopy for the next decade.

| # | Plan | What | Status | Effort |
|---|------|------|--------|--------|
| 10 | [Browser DevTools](10-browser-devtools.md) | Component tree, state inspector, time-travel debugging | Debugger tool exists | 4-6 wks |
| 11 | [Component Library](11-component-library.md) | 45+ accessible, themed components | Not started | 12-16 wks |
| 20 | [Edge Computing Target](20-edge-target.md) | Cloudflare Workers, Deno Deploy, Vercel Edge | Not started | 3-4 wks |
| 21 | [Transparent Concurrency](21-transparent-concurrency.md) | Web Workers as compiler optimization | Not started | 6-8 wks |
| 22 | [Package Registry](22-package-registry.md) | Self-hosted registry with private packages | Not started | 6-8 wks |
| 23 | [Animation & Motion](23-animation-motion.md) | View Transitions, springs, scroll, gestures | Not started | 4-6 wks |
| 28 | [Auth Patterns](28-auth-patterns.md) | OAuth, JWT, protected routes, RBAC | Not started | 3-4 wks |
| 30 | [Web API Integration](30-web-api-integration.md) | Navigation API, Temporal, Popover, Container Queries | canopy-webidl exists | 3-4 wks |
| 32 | [Mobile Deployment](32-mobile-deployment.md) | Capacitor/Tauri integration for hybrid mobile apps | Not started | 2-3 wks |

---

## Success Criteria

### Must achieve to compete:
- [ ] Sub-2KB hello world bundle (gzipped)
- [ ] Sub-100ms incremental rebuild
- [ ] Streaming SSR
- [ ] Vite HMR with state preservation
- [ ] TypeScript .d.ts generation
- [ ] File-based routing meta-framework
- [ ] Type-safe forms with schema validation
- [ ] Data fetching with RemoteData enforcement
- [ ] Gradual adoption path (use Canopy inside React projects)
- [x] String interpolation (`[i|...|]` syntax — `${}` pending)
- [ ] JSON codec deriving
- [x] Capability manifest for security auditing
- [x] Supply chain security story (packages can't exfiltrate without capability grants)
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
