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

## Existing Assets (Don't Rebuild What We Have)

The codebase audit reveals infrastructure that plans should leverage:

| Asset | Status | Leverage Point |
|-------|--------|---------------|
| **canopy-query engine** | Built (Salsa-inspired cache, deps, hashes) | Plan 09 is 80% done — integrate, don't rewrite |
| **canopy-lsp** | Built (12 subdirectories, full LSP) | Already have editor support — extend, don't rebuild |
| **canopy-webidl** | Built (with test suite) | Use for typed Web API bindings (Plan 30) |
| **canopy-mcp** | Exists | AI tooling support (Plan 31) |
| **Tree-sitter grammar** | Built | Syntax highlighting ready |
| **VSCode extension** | Built (.vsix) | Editor support ready |
| **3,707 tests passing** | Green | Solid foundation |
| **FFI system** | Production-ready | @canopy-type, @canopy-bind, @capability — fully implemented |
| **Capability system** | Types + static analysis built | Enforcement pipeline needs activation |

---

## Critical Dependency Chain

```
Plan 26a (Quick Ergonomics) ── independent, ship immediately
Plan 02 (Hygiene) ── independent, ship immediately

Plan 01 (ESM Output) ──────────────────────────────────────────┐
    |                                                           |
    +---> Plan 06 (Vite Plugin) ---> Plan 05 (CanopyKit) ------+
    |                                                           |
    +---> Plan 12 (TS Interop) --------------------------------+
    |                                                           |
    +---> Plan 09 (Incremental) --> Plan 06 (Vite HMR speed)   |
                                                                |
Plan 03 (Packages) ────────────────────────────────────────────┘
    |
    +---> Plan 13 (Capability Security)
    +---> Plan 24 (Forms)
    +---> Plan 25 (Data Fetching)
    +---> Plan 14 (A11y)

Plan 26b (Abilities + Derive) ── depends on stable compiler
Plan 27 (Onboarding) ── independent, critical for adoption
Plan 31 (AI DX) ── independent, leverages canopy-mcp
```

**Plan 01 (ESM) and Plan 03 (Packages) are the two gatekeepers. Everything else is blocked on them.**

**Plan 26a (string interpolation + nested records) ships in parallel — pure parser desugaring, no dependencies.**

---

## Tier 0: Foundation (Weeks 1-8)

Fix what's broken. No new features until the base is solid.

| # | Plan | What | Why | Effort |
|---|------|------|-----|--------|
| 02 | [Compiler Hygiene](02-compiler-hygiene.md) | Fix debug stmts, Makefile, -Wall, README | Cannot ship a compiler with issues | 1 wk |
| 26a | [Quick Ergonomics](26a-quick-ergonomics.md) | String interpolation + nested record updates | Biggest Elm complaints, pure desugaring, instant differentiation | 1-2 wks |
| 01 | [ESM Output](01-esm-output.md) | Replace IIFE with native ES modules | **Gates everything.** Unlocks tree shaking, bundler compat, HMR, code splitting. | 2-3 wks |
| 03 | [Package Ecosystem Sprint](03-package-ecosystem.md) | Complete all 15 missing stdlib packages (including canopy/test) | Cannot build any real app without html, http, browser | 4-5 wks |

## Tier 1: Usable Platform (Months 3-6)

Make it work for real applications. A developer should be able to build and ship a production app.

| # | Plan | What | Why | Effort |
|---|------|------|-----|--------|
| 06 | [Vite Plugin + HMR](06-vite-plugin.md) | First-class Vite integration with hot module replacement | 98% developer retention for Vite; table stakes | 2-3 wks |
| 05 | [CanopyKit Meta-Framework](05-canopykit.md) | File-based routing, SSG, dev server (Phase 1); SSR later | No production adoption without this. Period. | 8-12 wks |
| 12 | [TypeScript Interop](12-typescript-interop.md) | Emit .d.ts, Web Component output, consume npm | Elm's #1 adoption killer was JS interop. Gradual adoption story. | 6-8 wks |
| 13 | [Capability Security](13-capability-enforcement.md) | Activate capability system, manifest, supply chain story | Our unique differentiator. Post-npm-apocalypse, this sells itself. | 4-5 wks |
| 26b | [Abilities + Derive](26b-abilities-derive.md) | Type classes (Roc-style), JSON codec deriving | Top reasons devs leave Elm. Non-negotiable. | 8-12 wks |
| 27 | [Developer Onboarding](27-developer-onboarding.md) | Playground, React migration guide, gradual adoption | #1 adoption determinant. Culture Amp lesson. | 6-8 wks |

## Tier 2: Production Ready (Months 6-10)

Make it irresistible. Developers who try Canopy should never want to go back.

| # | Plan | What | Why | Effort |
|---|------|------|-----|--------|
| 09 | [Incremental Compilation](09-incremental-compilation.md) | Salsa-style query system, sub-100ms rebuilds, error recovery | Query engine 80% built. Integrate it. Add partial compilation for LSP. | 4-6 wks |
| 07 | [Streaming SSR](07-ssr-resumability.md) | Server rendering (Phase 1: basic SSR) | SEO + performance requirement | 4-6 wks |
| 08 | [TEA at Scale](08-state-architecture.md) | Route code splitting + nested record updates solve 80% of TEA pain | Simplify — don't add Stores until demand exists | 2-3 wks |
| 24 | [Type-Safe Forms](24-type-safe-forms.md) | Schema-driven forms with compile-time validation | Forms are #1 web dev pain point | 4-5 wks |
| 25 | [Data Fetching & Caching](25-data-fetching.md) | RemoteData, stale-while-revalidate, optimistic updates | TanStack Query is table stakes now | 4-5 wks |
| 31 | [AI Developer Experience](31-ai-developer-experience.md) | MCP server, type-directed completion, AI migration tool | AI-assisted dev is the norm in 2026. We have canopy-mcp already. | 4-6 wks |

## Tier 3: Competitive Advantages (Months 10-14)

Features that make Canopy categorically better — things React/Angular/Vue **cannot** do.

| # | Plan | What | Why | Effort |
|---|------|------|-----|--------|
| 04 | [Fine-Grained Reactivity](04-fine-grained-reactivity.md) | Compile view functions to direct DOM mutations | Eliminate VDOM overhead; match SolidJS/Svelte perf | 6-8 wks |
| 14 | [Compile-Time Accessibility](14-compile-time-a11y.md) | Inaccessible HTML doesn't compile | EU Accessibility Act; compiler > lint | 4-5 wks |
| 19 | [WASM Backend](19-wasm-backend.md) | Hybrid JS+WASM compilation via WasmGC | WasmGC shipped in all browsers (2025). Google Sheets 2x faster on WasmGC. | 12-16 wks |
| 16 | [Effect Annotations](16-algebraic-effects.md) | Inferred effect types visible in signatures, enables SSR auto-splitting | 80% of algebraic effects value without full handlers | 6-8 wks |
| 15 | [Type-Safe CSS](15-type-safe-css.md) | CSS properties only accept valid values | `padding` takes `Length`, not `String` | 4-6 wks |
| 29 | [Local-First & Sync](29-local-first-sync.md) | CRDTs, offline-first, real-time collaboration | Biggest architectural shift in frontend 2025 | 8-10 wks |
| 17 | [Built-in Property Testing](17-property-testing.md) | Auto-derive generators, first-class fuzz | No other web lang has this built in | 3-4 wks |
| 18 | [Type-Safe i18n](18-type-safe-i18n.md) | Missing translations are compile errors | Interpolation checked, plurals validated | 3-4 wks |

## Tier 4: Future-Proofing (Months 14+)

Position Canopy for the next decade.

| # | Plan | What | Why | Effort |
|---|------|------|-----|--------|
| 10 | [Browser DevTools](10-browser-devtools.md) | Component tree, state inspector, time-travel debugging | React DevTools is a daily-driver; need parity | 4-6 wks |
| 11 | [Component Library](11-component-library.md) | 45+ accessible, themed components | Enterprise adoption requires this | 12-16 wks |
| 20 | [Edge Computing Target](20-edge-target.md) | Cloudflare Workers, Deno Deploy, Vercel Edge | Pure functions perfect for edge | 3-4 wks |
| 21 | [Transparent Concurrency](21-transparent-concurrency.md) | Web Workers as compiler optimization | Purity guarantees safe parallelism | 6-8 wks |
| 22 | [Package Registry](22-package-registry.md) | Self-hosted registry with private packages | Enterprise requires private packages | 6-8 wks |
| 23 | [Animation & Motion](23-animation-motion.md) | View Transitions, springs, scroll, gestures | Animation is core UX, not polish | 4-6 wks |
| 28 | [Auth Patterns](28-auth-patterns.md) | OAuth, JWT, protected routes, RBAC | Every production app needs auth | 3-4 wks |
| 30 | [Web API Integration](30-web-api-integration.md) | Navigation API, Temporal, Popover, Container Queries | Use new browser APIs, don't polyfill old ones | 3-4 wks |
| 32 | [Mobile Deployment](32-mobile-deployment.md) | Capacitor/Tauri integration for hybrid mobile apps | Low effort, high perception value for adoption | 2-3 wks |

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
- [ ] String interpolation and JSON codec deriving
- [ ] Capability manifest for security auditing
- [ ] Supply chain security story (packages can't exfiltrate without capability grants)
- [ ] canopy/test package with test runner

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
- [ ] AI-assisted development (MCP server, type-directed completion)

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
