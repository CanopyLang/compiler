# Plan 21: Component Library

## Priority: LOW -- Tier 4
## Status: ~30% complete
## Effort: 8-10 weeks (revised down from 12-16 -- headless primitives already exist)
## Depends on: Plan 03 (packages -- COMPLETE), Plan 04 (reactivity) or working VDOM (VDOM exists)

## What Already Exists

### Headless UI Components (`canopy/headless-ui` -- 10 files)
- `Dialog` -- modal dialog with focus trap
- `Menu` -- dropdown menu
- `Listbox` -- select/listbox
- `Switch` -- toggle switch
- `Disclosure` -- expandable/collapsible section
- `Tabs` -- tab navigation
- `Combobox` -- searchable select
- `RadioGroup` -- radio button group
- `Popover` -- positioned overlay
- `Transition` -- enter/leave animations

### Related Packages (COMPLETE)
- `canopy/accessible-html` -- ARIA attributes and accessible markup helpers
- `canopy/form` -- form handling and validation
- `canopy/table` -- data table primitives
- `canopy/toast` -- notification toasts
- `canopy/error-boundary` -- error boundary component
- `canopy/virtual-list` -- virtualized list rendering for large datasets
- `canopy/chart` -- chart components (bar, line, pie via SVG)

### Foundation
- 72 stdlib packages covering browser APIs, styling, layout
- Capability system for API restrictions
- Builder-pattern API conventions established across existing packages

## What Remains

### Phase 1: Design System Foundation (Weeks 1-2)
- Theme system: CSS custom properties for all visual tokens (colors, spacing, typography, radii)
- Dark/light mode with `prefers-color-scheme` support
- Theme provider component that injects CSS variables
- Design token specification (Material-inspired or Tailwind-inspired)

### Phase 2: Styled Layout Components (Weeks 3-4)
- `Box` -- generic container with spacing/padding props
- `Stack` -- vertical/horizontal flex layout
- `Grid` -- responsive CSS grid
- `Card` -- content container with header/body/footer
- `Divider` -- visual separator
- `Text` -- styled text with variants (body, caption, overline)
- `Heading` -- h1-h6 with automatic hierarchy validation

### Phase 3: Styled Input Components (Weeks 5-6)
- Themed wrappers around headless-ui primitives (Dialog, Menu, Listbox, etc.)
- `Button` -- primary/secondary/ghost/danger variants, loading state, icon support
- `TextInput` -- with validation states, helper text, error display
- `Textarea`, `NumberInput`, `SearchInput`, `DatePicker`, `FileUpload`
- `Slider`, `MultiSelect` with chips

### Phase 4: Data Display and Feedback (Weeks 7-8)
- `DataTable` -- sortable, filterable, paginated (wrapping `canopy/table`)
- `Avatar`, `Tag`, `Badge`, `EmptyState`
- `Alert` -- inline alert/banner messages
- `ProgressBar` -- determinate/indeterminate
- `Spinner` -- loading indicator
- `Breadcrumbs`, `Sidebar`, `Pagination`

### Phase 5: Documentation Site and Showcase (Weeks 9-10)
- Storybook-like component explorer built in Canopy
- Live interactive examples for every component
- API reference generated from type signatures
- Accessibility audit results per component
- Visual regression test suite (screenshot comparison)

## Design Principles

1. **Accessible by default**: WCAG 2.2 AA compliance. Built on `canopy/headless-ui` and `canopy/accessible-html`.
2. **Themeable**: CSS custom properties for all visual tokens. Dark/light mode built in.
3. **Composable**: Small, focused components that compose. Builder-pattern API.
4. **Type-safe**: Invalid configurations are compile errors.
5. **Zero runtime overhead**: Components compile to direct DOM operations.

## API Design

Every component follows the builder pattern established by existing packages:

```canopy
Button.button "Save"
    |> Button.primary
    |> Button.onClick SaveClicked
    |> Button.toHtml
```

## Risks

- **Design taste**: A component library is a design product, not just an engineering product. Needs design review.
- **Maintenance burden**: 45+ components each need ongoing accessibility testing, browser compat, and updates.
- **Bundle size**: Must tree-shake aggressively. Unused components should add zero bytes.
