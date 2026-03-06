# Plan 11: Component Library

## Priority: HIGH — Tier 2
## Effort: 12-16 weeks (ongoing)
## Depends on: Plan 03 (packages), Plan 04 (reactivity) or working VDOM

## Problem

React has 20+ production component libraries. MUI alone has 5.8M weekly downloads. Enterprise teams will not adopt a technology without pre-built, accessible, themed components.

Svelte took ~6 years to build an adequate component ecosystem. SolidJS still hasn't. We cannot wait — the component library must be first-party.

### Minimum Viable Components (Enterprise Non-Negotiable)

Based on UXPin's enterprise checklist and real-world adoption requirements:

## Solution: Canopy UI

A first-party, accessible, themeable component library. Ships with Canopy. Not optional.

### Design Principles

1. **Accessible by default**: WCAG 2.2 AA compliance. Every component handles focus, ARIA, keyboard navigation, screen readers.
2. **Themeable**: CSS custom properties for all visual tokens. Dark/light mode built in.
3. **Composable**: Small, focused components that compose into larger patterns.
4. **Type-safe**: Props are Canopy types. Invalid configurations are compile errors.
5. **Zero runtime overhead**: Components compile to direct DOM operations (Plan 04).

### Component Inventory

#### Phase 1: Foundation (Weeks 1-4) — 15 components

**Layout:**
- `Box` — generic container with spacing/padding props
- `Stack` — vertical/horizontal flex layout
- `Grid` — responsive CSS grid
- `Card` — content container with header/body/footer
- `Divider` — visual separator

**Typography:**
- `Text` — styled text with variants (body, caption, overline)
- `Heading` — h1-h6 with automatic hierarchy validation

**Input:**
- `Button` — primary/secondary/ghost variants, loading state, icon support
- `TextInput` — with validation, error states, helper text
- `Checkbox` — with indeterminate state
- `RadioGroup` — accessible radio button group
- `Toggle` — on/off switch
- `Select` — single select dropdown with search

**Feedback:**
- `Spinner` — loading indicator
- `Badge` — notification count/status indicator

#### Phase 2: Core (Weeks 5-8) — 12 components

**Input:**
- `Textarea` — multiline text input
- `NumberInput` — with increment/decrement, min/max validation
- `SearchInput` — with autocomplete suggestions
- `DatePicker` — calendar-based date selection
- `FileUpload` — drag-and-drop, file type validation

**Navigation:**
- `Tabs` — horizontal tab navigation
- `Breadcrumbs` — hierarchical path display
- `Sidebar` — collapsible sidebar navigation
- `Pagination` — page navigation controls

**Feedback:**
- `Toast` — notification toasts with auto-dismiss (aria-live)
- `Alert` — inline alert/banner messages
- `ProgressBar` — determinate/indeterminate progress

#### Phase 3: Advanced (Weeks 9-12) — 10 components

**Layout:**
- `Modal` — dialog with focus trap, Escape key, backdrop
- `Drawer` — slide-in panel
- `Popover` — positioned overlay content
- `Tooltip` — hover/focus information overlay

**Data Display:**
- `DataTable` — sortable, filterable, paginated table
- `Avatar` — user image with fallback
- `Tag` — categorization label, removable
- `EmptyState` — placeholder for no-data states

**Input:**
- `MultiSelect` — multi-select with chips
- `Slider` — range input

#### Phase 4: Enterprise (Weeks 13-16) — 8 components

- `Form` — form container with validation orchestration
- `Stepper` — multi-step form/wizard
- `TreeView` — hierarchical expandable tree
- `Accordion` — collapsible content sections
- `CommandPalette` — keyboard-driven command search (Cmd+K)
- `RichTextEditor` — basic rich text editing
- `Chart` — basic chart types (bar, line, pie) via SVG
- `Calendar` — full calendar view

### API Design

Every component follows the same pattern:

```canopy
module Canopy.UI.Button exposing
    ( Button
    , button
    , primary, secondary, ghost, danger
    , small, medium, large
    , withIcon, withLoading, disabled
    , onClick
    )

{-| A button component with variants, sizes, and states.

    Button.button "Save"
        |> Button.primary
        |> Button.onClick SaveClicked
        |> Button.toHtml

-}

type Button msg

button : String -> Button msg
primary : Button msg -> Button msg
secondary : Button msg -> Button msg
onClick : msg -> Button msg -> Button msg
disabled : Bool -> Button msg -> Button msg
withLoading : Bool -> Button msg -> Button msg
toHtml : Button msg -> Html msg
```

Builder pattern. Type-safe. Impossible to create an invalid button.

### Theming

```canopy
module Canopy.UI.Theme exposing (Theme, light, dark, custom)

type alias Theme =
    { colors :
        { primary : Color
        , secondary : Color
        , background : Color
        , surface : Color
        , error : Color
        , onPrimary : Color
        , onBackground : Color
        }
    , spacing :
        { xs : Length
        , sm : Length
        , md : Length
        , lg : Length
        , xl : Length
        }
    , typography :
        { fontFamily : String
        , fontSize : { sm : Length, md : Length, lg : Length }
        }
    , borderRadius : { sm : Length, md : Length, lg : Length }
    }
```

Theme is passed via a provider pattern:

```canopy
view model =
    Canopy.UI.Theme.provider Theme.light
        [ viewApp model ]
```

Components read theme values through CSS custom properties (zero JS overhead).

### Accessibility

Every component includes:
- **ARIA attributes**: Correct roles, labels, descriptions
- **Keyboard navigation**: Tab order, arrow keys, Escape, Enter/Space
- **Focus management**: Focus trap in modals, focus restoration
- **Screen reader support**: Live regions for dynamic content
- **Motion**: `prefers-reduced-motion` respected
- **Color contrast**: Validated against WCAG 2.2 AA (4.5:1 text, 3:1 UI)

### Testing

Each component has:
- Unit tests (renders correctly, responds to interactions)
- Accessibility tests (automated WCAG checks)
- Visual regression tests (screenshot comparison)
- Keyboard navigation tests
- Screen reader compatibility tests

## Definition of Done

- [ ] 45+ components implemented and documented
- [ ] WCAG 2.2 AA compliance verified for all components
- [ ] Light and dark themes
- [ ] Keyboard navigation for all interactive components
- [ ] Storybook-style component explorer
- [ ] npm package published (`@canopy/ui`)
