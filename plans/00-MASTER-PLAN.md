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

## The Three Gaps That Kill Alternatives

Research shows that technical superiority accounts for ~20% of adoption. SolidJS has had the highest satisfaction rating for five consecutive years and only 10% usage. The other 80% is:

1. **Ecosystem breadth** — React has 206,885 npm dependents, 20+ production component libraries, and answers to every problem
2. **Meta-framework story** — Raw framework projects barely exist; Next.js/Nuxt/SvelteKit are the actual products teams adopt
3. **Incremental adoption** — TypeScript won because every JS file is valid TS; Elm lost because it demanded a complete rewrite

Canopy must solve all three, not just build a better compiler.

---

## Tier 0: Foundation (Weeks 1-4)

Fix what's broken. No new features until the base is solid.

| # | Plan | What | Why |
|---|------|------|-----|
| 01 | [ESM Output](01-esm-output.md) | Replace IIFE with native ES modules | Unlocks tree shaking, bundler compat, HMR, code splitting. **Single most important change.** |
| 02 | [Compiler Hygiene](02-compiler-hygiene.md) | Fix debug stmts, Makefile, dead code, -Wall | Cannot ship a compiler with HTTP_DEBUG in the output |
| 03 | [Package Ecosystem Sprint](03-package-ecosystem.md) | Complete all 14 missing stdlib packages | Cannot build any real app without html, http, browser |

## Tier 1: Core Platform (Months 2-4)

Make it work for real applications. A developer should be able to build and ship a production app.

| # | Plan | What | Why |
|---|------|------|-----|
| 04 | [Fine-Grained Reactivity](04-fine-grained-reactivity.md) | Compile view functions to direct DOM mutations | Eliminate VDOM overhead; match SolidJS/Svelte performance |
| 05 | [CanopyKit Meta-Framework](05-canopykit.md) | File-based routing, SSR, SSG, data loading, deployment | No production adoption without this. Period. |
| 06 | [Vite Plugin + HMR](06-vite-plugin.md) | First-class Vite integration with hot module replacement | 98% developer retention for Vite; table stakes |
| 07 | [Streaming SSR + Resumability](07-ssr-resumability.md) | Server rendering with Qwik-style resume, no hydration cost | SEO + performance; O(1) startup regardless of app size |
| 08 | [State Architecture](08-state-architecture.md) | Domain-split stores, signals, subscriptions beyond TEA | TEA fails at scale (documented). Need polyglot state. |

## Tier 2: Developer Experience (Months 4-7)

Make it irresistible. Developers who try Canopy should never want to go back.

| # | Plan | What | Why |
|---|------|------|-----|
| 09 | [Incremental Compilation](09-incremental-compilation.md) | Salsa-style query system, sub-100ms rebuilds | Developers expect Vite-speed feedback loops |
| 10 | [Browser DevTools](10-browser-devtools.md) | Component tree, state inspector, time-travel debugging | React DevTools is a daily-driver tool; we need parity |
| 11 | [Component Library](11-component-library.md) | 40+ accessible, themed components | Enterprise adoption requires this. No shortcuts. |
| 12 | [TypeScript Interop](12-typescript-interop.md) | Consume npm packages, emit .d.ts for consumers | Elm's #1 adoption killer was JS interop friction |
| 13 | [Capability Enforcement](13-capability-enforcement.md) | Activate the capability system end-to-end | Our unique security story; no other framework has this |

## Tier 3: Competitive Advantages (Months 7-10)

Features that make Canopy categorically better — things React/Angular/Vue **cannot** do.

| # | Plan | What | Why |
|---|------|------|-----|
| 14 | [Compile-Time Accessibility](14-compile-time-a11y.md) | Inaccessible HTML doesn't compile | EU Accessibility Act in force; compiler enforcement > lint rules |
| 15 | [Type-Safe CSS](15-type-safe-css.md) | CSS properties that only accept valid values | `padding` takes `Length`, not `String`. Eliminate CSS bugs at compile time. |
| 16 | [Algebraic Effects](16-algebraic-effects.md) | Replace Cmd/Sub with composable, typed effects | Better than monads. Visible in types, swappable in tests. |
| 17 | [Built-in Property Testing](17-property-testing.md) | Auto-derive generators from types, first-class fuzz | No other web language has this built in |
| 18 | [Type-Safe i18n](18-type-safe-i18n.md) | Missing translations are compile errors | Interpolation vars type-checked, plural rules validated |

## Tier 4: Future-Proofing (Months 10-14)

Position Canopy for the next decade.

| # | Plan | What | Why |
|---|------|------|-----|
| 19 | [WASM Backend](19-wasm-backend.md) | Hybrid JS+WASM compilation, WASI for server | WasmGC shipped everywhere; compute in WASM, view in JS |
| 20 | [Edge Computing Target](20-edge-target.md) | Compile for Cloudflare Workers, Deno Deploy, Vercel Edge | Pure functions are perfect for edge; enforce WinterTC at type level |
| 21 | [Transparent Concurrency](21-transparent-concurrency.md) | Web Workers as compiler optimization | Purity guarantees safe parallelism; zero developer boilerplate |
| 22 | [Package Registry](22-package-registry.md) | Self-hosted registry with private packages | Enterprise adoption requires private packages (Elm never had this) |

---

## Success Criteria

### Must achieve to compete:
- [ ] Sub-2KB hello world bundle (gzipped)
- [ ] Sub-100ms incremental rebuild
- [ ] Streaming SSR with resumability
- [ ] 40+ accessible components
- [ ] Vite HMR with state preservation
- [ ] TypeScript .d.ts generation
- [ ] File-based routing meta-framework
- [ ] Browser DevTools extension

### Must achieve to dominate:
- [ ] Inaccessible HTML doesn't compile
- [ ] CSS type errors caught at compile time
- [ ] Missing translations are compile errors
- [ ] Effect types visible in every function signature
- [ ] Zero-config Web Worker parallelism
- [ ] WASM backend for compute-heavy modules
- [ ] Edge deployment with `canopy build --target edge`
- [ ] Property-based testing from type signatures

---

## What We Learned From Others' Failures

| Language/Framework | What Went Wrong | Our Fix |
|---|---|---|
| **Elm** | No releases since 2019, hostile governance, crippled JS interop, no SSR, no private packages | Active development, TypeScript interop, SSR built-in, private registry |
| **SolidJS** | Best performance for 5 years, 10% adoption — no meta-framework, tiny ecosystem | CanopyKit meta-framework, component library, ecosystem-first |
| **Svelte** | Compile-time reactivity but ecosystem 1/10th of React's after 8 years | Component library sprint, Web Component output for React interop |
| **PureScript** | Excellent type system, steep learning curve, niche adoption | Elm-like simplicity with PureScript-like power under the hood |
| **ReScript** | Good React interop but confused identity (Reason → ReScript → ?) | Clear identity, clear mission, clear docs |

## What We Learned From TypeScript's Success

TypeScript is the only compile-to-JS language that achieved mass adoption. The playbook:

1. **Every existing project is valid** — gradual adoption with zero rewrite
2. **Frameworks chose it** — Angular, Next.js defaulted to TS
3. **Tooling was first-class** — VS Code built in TS, provides best-in-class support
4. **Measurable ROI** — 40% reduction in maintenance costs (Airbnb, Slack data)
5. **AI reinforcement** — AI tools prefer typed code

**Our adaptation**: We can't be a superset of JS, but we CAN:
- Emit Web Components usable from React/Vue/Angular (gradual adoption)
- Provide TypeScript type definitions for all Canopy outputs (ecosystem integration)
- Ship the best tooling in the industry (LSP, DevTools, error messages)
- Demonstrate measurable wins (zero runtime crashes, smaller bundles, faster loads)
