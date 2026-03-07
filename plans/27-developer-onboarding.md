# Plan 27: Developer Onboarding & Adoption

## Priority: CRITICAL — Tier 1
## Effort: 4-6 weeks (reduced — playground already exists)
## Depends on: Plan 06 (Vite plugin)

> **Status Update (2026-03-07 audit):** Several onboarding assets already exist:
>
> - **Playground** (`compiler/tools/playground/`) — Full React/Vite/TypeScript app with:
>   CodeMirror-style editor, live preview, error panel, example picker, file tabs,
>   output tabs, share modal, keyboard shortcuts, status bar
> - **MCP server** (`canopy-mcp`) — AI integration with 5 tools for Claude/Copilot
> - **VSCode extension** — Editor support ready
> - **All packages complete** — Plan 03 dependency removed
>
> Remaining work: documentation, migration guide, example apps, deployment.

## Problem

Culture Amp retired Elm because "new hires couldn't be productive quickly." SolidJS has 10% usage despite highest satisfaction. The hiring/learning problem kills languages.

TypeScript won because every JS file is valid TS. Elm lost because it demanded a complete rewrite.

Developer onboarding is not a nice-to-have. It's the #1 adoption determinant.

## Solution: Multi-Layered Onboarding

### 1. Interactive Browser Playground

A browser-based REPL and tutorial at **play.canopy-lang.org**:

- Live code editor with syntax highlighting
- Instant compilation feedback (compile in browser via WASM compiler)
- Step-by-step tutorial (inspired by Svelte tutorial, Go Tour)
- Share links for code snippets
- Pre-loaded examples for every concept

### 2. "Canopy for React Developers" Guide

Not a language reference — a **translation guide**:

```
React                          → Canopy
─────                            ──────
useState(0)                    → { count = 0 }
setCount(c => c + 1)           → { model | count = model.count + 1 }
useEffect(() => {...}, [])     → subscriptions model = ...
<div className="foo">          → div [ class "foo" ] [ ... ]
{items.map(i => <Li item={i}/>)} → List.map viewItem items
fetch('/api/users')            → Http.get { url = "/api/users", ... }
try { ... } catch (e) { ... }  → case result of Ok v -> ... ; Err e -> ...
```

### 3. Gradual Adoption Path (The TypeScript Playbook)

Teams must be able to adopt Canopy **without rewriting anything**:

**Step 1**: Install Vite plugin, write ONE Canopy module, import from TypeScript
```typescript
import { formatCurrency } from './utils/Currency.can'
```

**Step 2**: Build ONE component in Canopy, embed as Web Component
```html
<canopy-price-calculator initial-amount="100" />
```

**Step 3**: Build a new page/route entirely in Canopy within existing app

**Step 4**: Migrate more pages as confidence grows

**Step 5**: Full CanopyKit app (optional — the old React app can stay)

At no point is a "big bang rewrite" required.

### 4. Migration Codemods

Automated tools that convert React/TypeScript patterns to Canopy:

```bash
canopy migrate ./src/components/UserCard.tsx
# Generates: ./src/components/UserCard.can
# With: type-safe props, view function, basic event handlers
# Manual review needed for: effects, state management, JS interop
```

Not perfect — but gets developers 60-70% of the way, reducing the manual effort dramatically.

### 5. Error Messages That Teach

Canopy already inherits Elm's excellent error messages. Extend them:

```
── TYPE MISMATCH ──────────────── src/App.can

The `onClick` attribute expects a message, but you gave it a function:

    15│  button [ onClick (\_ -> DoSomething) ] [ text "Click" ]
                           ^^^^^^^^^^^^^^^^^^^
    I was expecting a `Msg` value, not a function.

    Hint: In Canopy, event handlers take a message value directly,
    not a callback function. Try:

        button [ onClick DoSomething ] [ text "Click" ]

    If you need the event data, use `onClickWith`:

        button [ onClickWith (\event -> DoSomething event.target) ] [ text "Click" ]

    Coming from React? See: https://canopy-lang.org/from-react#events
```

Every error message for common React-developer mistakes should include a "Coming from React?" link.

### 6. Real-World Example Applications

Not toy demos. Production-scale examples:

| Example | What It Demonstrates |
|---------|---------------------|
| **Blog** | SSR, routing, data fetching, markdown rendering |
| **Dashboard** | Charts, data tables, real-time updates, stores |
| **E-commerce** | Forms, cart, checkout, auth, payment integration |
| **Chat** | WebSocket, real-time sync, presence, message history |
| **Admin Panel** | CRUD, pagination, filtering, role-based access |

Each example includes:
- Full source code
- Line-by-line annotations
- "How this would look in React" comparisons
- Deployment guide

### 7. AI Training Corpus

Provide structured examples optimized for LLM code generation:

- Annotated code examples in a machine-readable format
- MCP server for Claude/Copilot integration with Canopy projects
- Well-documented AST for code generation tools

## Implementation

### Phase 1: Documentation and guides (Weeks 1-3)
- "Canopy for React Developers" guide
- Quick start tutorial
- API reference for core packages
- Error message improvements for common React-isms

### Phase 2: Browser playground (Weeks 4-5)
- **Playground already exists** (`compiler/tools/playground/`) — needs deployment to play.canopy-lang.org
- Add step-by-step interactive tutorial mode
- Ensure shareable code snippets work in production

### Phase 3: Example applications (Weeks 6-7)
- Blog and Dashboard examples (full-stack with CanopyKit)
- Annotated source code
- Deployment guides

### Phase 4: Migration tooling (Week 8)
- Basic React-to-Canopy codemod
- TypeScript type-to-Canopy type converter
- Component structure analyzer

## Definition of Done

- [ ] A React developer can build and deploy a working Canopy app within 1 day
- [ ] Browser playground at play.canopy-lang.org
- [ ] "Canopy for React Developers" guide
- [ ] 3+ real-world example applications with full source
- [ ] Error messages include "Coming from React?" hints
- [ ] Gradual adoption works (Canopy modules in React projects via Vite)
