# Plan 15: Type-Safe CSS

## Priority: MEDIUM — Tier 3
## Effort: 4-6 weeks
## Depends on: Plan 03 (packages — COMPLETE)

## Problem

CSS bugs are silent. `padding: "red"` doesn't error — it just doesn't work. CSS-in-JS adds runtime overhead. Utility classes (Tailwind) trade type safety for convention.

A typed language should catch CSS errors at compile time.

## Solution: Canopy.CSS — Type-Safe CSS with Zero Runtime

### API Design

```canopy
module Canopy.CSS exposing (..)

-- Properties accept only valid value types:
padding : Length -> Style
color : Color -> Style
display : Display -> Style
fontSize : Length -> Style
fontWeight : FontWeight -> Style

-- Length is a real type, not a string:
type Length
    = Px Float
    | Rem Float
    | Em Float
    | Percent Float
    | Vh Float
    | Vw Float

-- Color is a real type:
type Color
    = Hex String      -- validated at parse time
    | Rgb Int Int Int  -- 0-255 enforced by refinement
    | Hsl Float Float Float
    | CurrentColor
    | Transparent

-- Display is an enum:
type Display = Block | Flex | Grid | InlineBlock | Inline | None

-- FontWeight is an enum:
type FontWeight = Thin | Light | Normal | Medium | Bold | Black | Weight Int
```

### Usage in Components

```canopy
view model =
    div
        [ css
            [ display Flex
            , padding (Rem 1.5)
            , gap (Rem 1)
            , backgroundColor (Hex "#f5f5f5")
            , borderRadius (Px 8)
            ]
        ]
        [ text "Hello" ]
```

### Compile-Time Extraction

The compiler extracts CSS at build time — zero runtime overhead:

1. Analyze all `css [...]` expressions in the codebase
2. Generate unique class names (content-hashed)
3. Emit a static `.css` file with all styles
4. Replace `css [...]` in the HTML with `class "generated-class-name"`

```css
/* Generated: styles.css */
.c_a7f3b2 { display: flex; padding: 1.5rem; gap: 1rem; background-color: #f5f5f5; border-radius: 8px; }
```

```javascript
// Generated JS (no runtime CSS)
div([class("c_a7f3b2")], [text("Hello")])
```

### Responsive Design

```canopy
view model =
    div
        [ css
            [ display Grid
            , gridTemplateColumns [ Fr 1 ]
            , responsive
                { md = [ gridTemplateColumns [ Fr 1, Fr 1 ] ]
                , lg = [ gridTemplateColumns [ Fr 1, Fr 1, Fr 1 ] ]
                }
            ]
        ]
        [ ... ]
```

Generates:

```css
.c_b8e4c3 { display: grid; grid-template-columns: 1fr; }
@media (min-width: 768px) { .c_b8e4c3 { grid-template-columns: 1fr 1fr; } }
@media (min-width: 1024px) { .c_b8e4c3 { grid-template-columns: 1fr 1fr 1fr; } }
```

### Pseudo-Classes and States

```canopy
buttonStyle =
    [ backgroundColor (Hex "#336699")
    , color (Hex "#ffffff")
    , hover [ backgroundColor (Hex "#264d73") ]
    , focus [ outline (Px 2) Solid (Hex "#ffcc00"), outlineOffset (Px 2) ]
    , active [ transform [ Scale 0.98 ] ]
    , disabled [ opacity 0.5, cursor NotAllowed ]
    ]
```

### CSS Custom Properties for Theming

```canopy
-- Define theme tokens:
themeStyles =
    [ var "--color-primary" (Hex "#336699")
    , var "--color-bg" (Hex "#ffffff")
    , var "--spacing-md" (Rem 1)
    ]

-- Use them:
cardStyle =
    [ backgroundColor (CSSVar "--color-bg")
    , padding (CSSVar "--spacing-md")
    , color (CSSVar "--color-primary")
    ]
```

CSS custom properties enable runtime theming (dark mode toggle) while keeping the base styles static.

### Animations

```canopy
fadeIn : Animation
fadeIn =
    keyframes
        [ ( 0, [ opacity 0, transform [ TranslateY (Px 10) ] ] )
        , ( 100, [ opacity 1, transform [ TranslateY (Px 0) ] ] )
        ]

cardStyle =
    [ animation fadeIn (Ms 300) EaseOut
    ]
```

## Implementation

### Phase 1: Core types and properties (Weeks 1-2)
- Define `Length`, `Color`, `Display`, `Position`, `FlexDirection`, etc.
- Implement the 50 most-used CSS properties as typed functions
- CSS value validation (Hex string format, RGB ranges, etc.)

### Phase 2: Compile-time extraction (Weeks 3-4)
- New compiler pass: walk AST, collect all `css [...]` expressions
- Content-hash class name generation
- CSS file emission
- Replace `css [...]` with `class "..."` in generated HTML

### Phase 3: Advanced features (Weeks 5-6)
- Responsive breakpoints
- Pseudo-classes (hover, focus, active, etc.)
- Keyframe animations
- CSS custom properties
- Grid and flexbox layout helpers

## What This Prevents

```canopy
-- These are all compile errors:
padding (Hex "#red")           -- Hex is not a Length
color (Px 16)                  -- Px is not a Color
fontSize "1rem"                -- String is not a Length
display "flexbox"              -- String is not a Display
gridTemplateColumns (Rem 1)    -- needs a List
zIndex (Px 10)                 -- zIndex takes Int, not Length
```

## Risks

- **CSS coverage**: CSS has hundreds of properties. We don't need all of them day one — cover the top 50, provide a `rawProperty : String -> String -> Style` escape hatch for the rest.
- **Dynamic styles**: Some styles depend on runtime values (e.g., `width` based on data). These can't be extracted at compile time. Solution: emit inline styles for dynamic values, static CSS for everything else.
