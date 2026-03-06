# Plan 14: Compile-Time Accessibility Enforcement

## Priority: MEDIUM — Tier 3
## Effort: 4-5 weeks
## Depends on: Plan 03 (packages — html package)

## Problem

Automated accessibility tools (axe, Lighthouse) detect only ~40% of WCAG issues, and they run after the code is written. Developers treat a11y warnings like lint warnings — ignored until audit time.

The EU Accessibility Act is in force since June 2025. Accessibility is not optional.

A compiler can do what no runtime tool can: **refuse to produce inaccessible HTML**.

## Solution: Typed HTML That Enforces Accessibility

### Mandatory Alt Text

```canopy
-- Current (allows inaccessible code):
img [ src "photo.jpg" ] []  -- No alt text. Compiles fine. Broken for screen readers.

-- New: img REQUIRES alt text as a parameter:
img "A sunset over the ocean" [ src "photo.jpg" ] []  -- Alt text is mandatory
decorativeImg [ src "border.png" ] []  -- Explicit "this is decorative" (sets alt="")
```

The `img` function signature changes from `List (Attribute msg) -> List (Html msg) -> Html msg` to require the alt text as a first argument. There is no way to create an image without specifying its text alternative.

### Heading Hierarchy

```canopy
-- The compiler tracks heading levels in the document tree.
-- Skipping levels is a compile error:

div []
    [ h1 [] [ text "Page Title" ]
    , section []
        [ h3 [] [ text "Section" ]  -- COMPILE ERROR: h3 cannot follow h1 without h2
        ]
    ]
```

Implementation: The `Html` type carries a phantom type tracking the current heading level. `h2` can only appear inside a context where `h1` has been established.

### Form Labels

```canopy
-- Every input MUST have an associated label:

-- This is a compile error:
input [ type_ "text", name "email" ] []

-- This is required:
labeledInput "Email address" [ type_ "text", name "email" ] []

-- Or explicit association:
label [ for "email-input" ] [ text "Email" ]
input [ id "email-input", type_ "text", name "email" ] []
```

### Interactive Elements

```canopy
-- Clickable divs are compile errors:
div [ onClick DoSomething ] [ text "Click me" ]
-- ERROR: div is not an interactive element. Use button or a.

-- Correct:
button [ onClick DoSomething ] [ text "Click me" ]
```

Non-interactive elements (`div`, `span`, `p`) cannot have click handlers without also having `role` and `tabindex` attributes. The compiler enforces this.

### ARIA Requirements

```canopy
-- Modal requires aria-label or aria-labelledby:
Modal.modal
    { label = "Confirm deletion"  -- Required parameter
    , onClose = CloseModal
    , content = [ text "Are you sure?" ]
    }

-- Tabs require proper ARIA structure:
Tabs.tabs
    { selected = model.activeTab
    , onSelect = TabSelected
    , panels =
        [ { label = "Overview", content = viewOverview }
        , { label = "Details", content = viewDetails }
        ]
    }
-- Compiler generates correct role="tablist", role="tab", role="tabpanel",
-- aria-selected, aria-controls, aria-labelledby automatically
```

### Color Contrast (Theme Level)

When using Canopy UI's theme system (Plan 11):

```canopy
-- The Theme type validates contrast ratios at compile time:
theme =
    Theme.custom
        { primary = Color.hex "#336699"
        , onPrimary = Color.hex "#FFFFFF"  -- 4.7:1 contrast ✓
        , background = Color.hex "#FFFFFF"
        , onBackground = Color.hex "#666666"  -- 3.9:1 contrast ✗
        -- COMPILE WARNING: onBackground (#666666) on background (#FFFFFF)
        -- has contrast ratio 3.9:1, below WCAG AA minimum of 4.5:1
        }
```

## Implementation

### Phase 1: Mandatory parameters (Weeks 1-2)

Change the `Html` module API:
- `img` requires alt text as first parameter
- `a` requires either `href` or `role="button"` + keyboard handler
- Form inputs require label association
- Interactive elements require accessible names

These are API changes, not compiler changes. They work through the type system.

### Phase 2: Context tracking (Weeks 3-4)

Add phantom types or compile-time checks for:
- Heading hierarchy (h1 must precede h2)
- ARIA landmark structure (main, nav, aside)
- Focus management (modals must trap focus)
- Live regions (dynamic content must use aria-live)

### Phase 3: Component-level enforcement (Week 5)

Canopy UI components (Plan 11) encode accessibility constraints in their types:
- Modal requires a label
- Tabs generate correct ARIA automatically
- Form components manage label association internally
- Data tables generate proper header/cell associations

## What This Catches (That Lint Tools Miss)

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

## Risks

- **API verbosity**: Requiring alt text on every image adds friction. Mitigate with `decorativeImg` for truly decorative images and good editor autocomplete.
- **False positives**: Some heading hierarchy violations are intentional (e.g., widget headings). Mitigate with an escape hatch: `Accessible.override` that requires explicit justification.
- **Learning curve**: Developers unfamiliar with a11y may be confused by errors. Mitigate with excellent error messages explaining WHY the rule exists.
