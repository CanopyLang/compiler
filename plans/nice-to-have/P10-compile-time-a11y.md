# Plan 10: Compile-Time Accessibility Enforcement

## Priority: MEDIUM — Tier 3
## Status: ~15% complete (library exists, compiler enforcement not started)
## Effort: 4-5 weeks (compiler work, not library)
## Depends on: Plan 03 (packages — COMPLETE)

## What Already Exists

| Component | Location | Status |
|-----------|----------|--------|
| `canopy/accessible-html` | stdlib package (8 files) | COMPLETE — WAI-ARIA enforcement at library level |
| Runtime a11y helpers | `canopy/accessible-html` | COMPLETE — accessible widget patterns |
| HTML module | `canopy/html` | COMPLETE — standard HTML API |

The `canopy/accessible-html` package provides runtime/library-level accessible HTML helpers: ARIA attribute builders, accessible widget patterns, and recommended usage. This is equivalent to what `elm-community/accessible-html` provides — correct attributes if you remember to use them.

What does NOT exist: compiler-level enforcement that makes inaccessible HTML a compile error.

## What Remains

The gap is between "library that helps you write accessible HTML" and "compiler that refuses to produce inaccessible HTML." The existing `canopy/accessible-html` package gives developers the tools; this plan makes the tools mandatory.

### Phase 1: Mandatory Parameters (Weeks 1-2)

Change the `Html` module API so that inaccessible patterns are unrepresentable:

- `img` requires alt text as first parameter (no way to omit it)
- `decorativeImg` for truly decorative images (sets `alt=""` explicitly)
- `a` requires either `href` or `role="button"` + keyboard handler
- Form inputs require label association via `labeledInput` or explicit `label[for]` + `input[id]` pairing
- Interactive elements require accessible names

These are type-system-level API changes. The compiler enforces them through the type checker — no special a11y pass needed.

### Phase 2: Context Tracking (Weeks 3-4)

Add phantom types or compile-time validation for structural accessibility rules:

- **Heading hierarchy**: `h2` can only appear in a context where `h1` has been established; skipping from `h1` to `h3` is a compile error
- **ARIA landmark structure**: `main`, `nav`, `aside` must be present and unique where required
- **Focus management**: modal components must trap focus (enforced by the Modal API requiring `onClose`)
- **Live regions**: dynamic content updates must use `aria-live` (the compiler detects content that depends on model fields inside non-live regions)

### Phase 3: Component-Level Enforcement (Week 5)

Higher-level widget APIs that encode accessibility constraints in their types:

- Modal requires a label parameter (no unlabeled modals)
- Tabs generate correct `role="tablist"`, `role="tab"`, `role="tabpanel"`, `aria-selected`, `aria-controls` automatically
- Form components manage label association internally
- Data tables generate proper header/cell associations via `scope` attributes

### What This Catches (That Lint Tools Miss)

| Issue | Lint Tool | Canopy Compiler |
|-------|-----------|----------------|
| Missing alt text | Warning (often ignored) | Compile error |
| Heading hierarchy skip | Some tools detect | Compile error |
| Click handler on div | Some tools detect | Compile error |
| Missing form label | Most tools detect | Compile error |
| Color contrast | Some tools detect | Compile warning (theme level) |
| Missing ARIA on custom widgets | Rarely detected | Impossible (API requires it) |
| Focus trap in modal | Never detected automatically | Built into component API |
| Live region for dynamic content | Rarely detected | Built into component API |

## Dependencies

- `canopy/accessible-html` (8 files) — provides the foundation; compiler enforcement builds on top
- `canopy/html` — API changes to core HTML functions happen here
- Type checker — phantom type tracking for heading hierarchy and landmarks

## Risks

- **API verbosity**: Requiring alt text on every image adds friction. Mitigate with `decorativeImg` for purely decorative images and editor autocomplete that pre-fills the parameter.
- **False positives in heading hierarchy**: Some widget headings intentionally skip levels. Mitigate with `Accessible.override` escape hatch that requires explicit justification string.
- **Learning curve**: Developers unfamiliar with a11y will encounter unfamiliar compile errors. Mitigate with error messages that explain WHY the rule exists and link to WCAG criteria.
- **Third-party HTML libraries**: Packages that construct `Html` values may not use the accessible API. Solution: provide migration tooling and make the accessible API the default in `canopy/html` v2.
