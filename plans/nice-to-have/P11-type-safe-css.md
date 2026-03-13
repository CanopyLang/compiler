# Plan 11: Type-Safe CSS

## Priority: MEDIUM — Tier 3
## Status: ~35% complete (CSS utility library exists with 9 source files and 8 test files, compile-time extraction not started)
## Effort: 4-6 weeks
## Depends on: Plan 03 (packages — COMPLETE)

## What Already Exists

| Component | Location | Status |
|-----------|----------|--------|
| `canopy/css` | stdlib package (9 source files, 8 test files) | COMPLETE — CSS utility library |
| CSS property helpers | `canopy/css` | COMPLETE — typed property functions |
| Inline style API | `canopy/html` | COMPLETE — `style` attribute support |

The `canopy/css` package provides typed CSS property functions at the library level. Developers can build CSS values with type-checked helpers rather than raw strings. This catches some errors (e.g., passing a color where a length is expected) but has two limitations:

1. **Runtime overhead**: styles are computed and applied via JavaScript at runtime
2. **No static extraction**: CSS cannot be extracted to a `.css` file at build time

## What Remains

### Phase 1: Core Types and Properties (Weeks 1-2)

Extend the existing `canopy/css` type system to cover the full CSS property surface:

- `Length`, `Color`, `Display`, `Position`, `FlexDirection`, `GridTemplate`, etc. as proper algebraic types
- The 50 most-used CSS properties as typed functions that accept only valid value types
- CSS value validation (hex string format, RGB 0-255 ranges, percentage bounds)
- `rawProperty : String -> String -> Style` escape hatch for properties not yet covered

What the existing library provides serves as the API design foundation. The compiler work is about making these types participate in static extraction.

### Phase 2: Compile-Time Extraction (Weeks 3-4)

New compiler pass that eliminates CSS runtime overhead entirely:

1. Walk the AST and collect all `css [...]` expressions
2. Generate content-hashed class names for each unique style combination
3. Emit a static `.css` file containing all extracted styles
4. Replace `css [...]` expressions with `class "c_a7f3b2"` in the generated JavaScript

This means zero CSS-in-JS runtime. The output is a plain `.css` file that the browser caches independently.

Dynamic styles (values that depend on `model` fields) cannot be extracted statically. These emit inline styles at runtime. The compiler warns when a style is dynamic and suggests CSS custom properties as an alternative.

### Phase 3: Advanced Features (Weeks 5-6)

- **Responsive breakpoints**: `responsive { md = [...], lg = [...] }` compiles to `@media` queries in the static CSS
- **Pseudo-classes**: `hover [...]`, `focus [...]`, `active [...]`, `disabled [...]` compile to CSS pseudo-class selectors
- **Keyframe animations**: `keyframes [...]` compiles to `@keyframes` blocks in static CSS
- **CSS custom properties**: `var "--color-primary" (Hex "#336699")` for runtime theming (dark mode) while keeping base styles static
- **Grid and flexbox layout helpers**: higher-level layout combinators that generate correct CSS

### What This Prevents

```canopy
-- All compile errors:
padding (Hex "#red")           -- Hex is not a Length
color (Px 16)                  -- Px is not a Color
fontSize "1rem"                -- String is not a Length
display "flexbox"              -- String is not a Display
gridTemplateColumns (Rem 1)    -- needs a List
zIndex (Px 10)                 -- zIndex takes Int, not Length
```

## Dependencies

- `canopy/css` (9 source files, 8 test files) — provides the type definitions and API surface
- Compiler optimization pass — new `Optimize/CSS.hs` module for style extraction
- Code generation — `Generate/JavaScript.hs` modifications to emit `.css` file alongside `.js`

## Risks

- **CSS coverage**: CSS has hundreds of properties. The `rawProperty` escape hatch handles uncovered properties while the typed surface grows incrementally.
- **Dynamic styles**: Styles depending on runtime values cannot be extracted. The compiler should clearly communicate when a style falls back to inline application and suggest CSS custom properties where applicable.
- **Specificity conflicts**: Content-hashed class names avoid naming conflicts, but the order of rules in the generated `.css` file matters. The compiler must emit rules in a deterministic order matching source order.
