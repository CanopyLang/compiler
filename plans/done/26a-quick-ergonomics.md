# Plan 26a: Quick Ergonomics (String Interpolation + Nested Records)

## Priority: CRITICAL — Tier 0
## Effort: 1 week (reduced — interpolation infrastructure 90% built)
## Depends on: Nothing (pure parser desugaring)
## Split from: Plan 26 (Language Ergonomics)

> **Status Update (2026-03-07 audit):** String interpolation is **90% implemented**. The full
> pipeline exists:
>
> - `AST.Source.Interpolation [InterpolationSegment]` — source AST node
> - `AST.Source.InterpolationSegment` — `IStr` (literal) and `IExpr` (expression) variants
> - `AST.Canonical.Types.StringConcat [Expr]` — canonical AST node
> - `Parse/Interpolation.hs` — full parser for `[i|Hello #{name}!|]` syntax
> - `Canonicalize/Expression.hs` — `canonicalizeInterpolation` desugaring to `String.concat`
> - `Format.hs` — `formatInterpolation` and `formatSegment`
> - `Reporting/Error/Syntax/Types.hs` — `EndlessInterpolation` error
> - Integrated into `Parse/Expression.hs` term parser
>
> **Current syntax:** `[i|Hello #{name}!|]` (quasi-quoter style)
>
> **What remains:** Add `${}` syntax inside regular double-quoted strings as an alternative
> (more familiar to JS/TS developers). The desugaring pipeline, AST nodes, canonicalization,
> formatting, and error reporting all exist and can be reused.
>
> Nested record updates are NOT yet implemented — parser and canonicalization changes still needed.

## Feature 1: String Interpolation — `${}` Syntax

### Current State

The `[i|Hello #{name}!|]` quasi-quoter syntax is fully functional:
- Parser: `Parse/Interpolation.hs` handles `[i|...|]` with `#{expr}` holes
- Desugaring: `Canonicalize/Expression.hs:canonicalizeInterpolation` converts to `String.concat`
- Formatting: `Format.hs:formatInterpolation` round-trips correctly
- Error handling: `EndlessInterpolation` error for unclosed interpolations

### What's Missing: `${}` in Regular Strings

Add `${}` detection inside regular double-quoted strings for a more familiar syntax:

```canopy
-- Existing (works now):
greeting = [i|Hello #{user.name}! You have #{String.fromInt count} messages.|]

-- New (to be added):
greeting = "Hello ${user.name}! You have ${String.fromInt count} messages."
```

### Implementation

**Parser change** (`Parse/String.hs` — `singleString` function):
1. When scanning a string literal, detect `$` followed by `{`
2. Parse the expression inside `${...}` using the standard expression parser
3. Emit `Src.Interpolation` nodes (reusing the existing AST)
4. Handle `\$` as an escape for literal `$`

**Everything downstream is already built:**
- `Src.Interpolation [InterpolationSegment]` AST node exists
- `canonicalizeInterpolation` desugaring exists
- `StringConcat` canonical node exists
- Type checking, optimization, and code generation all handle it
- Formatter handles it
- Error messages exist

### Rules

- Only expressions that return `String` are allowed inside `${}`
- Non-String expressions require explicit conversion (`String.fromInt`, etc.)
- Compile-time transformation, NOT runtime template processing
- Old string concatenation with `++` continues to work
- `[i|...|]` syntax continues to work alongside `"...${...}..."`
- `\$` escapes a literal dollar sign

### Estimated effort: 1-2 days

## Feature 2: Nested Record Updates

### Current State

Single-level record updates work: `{ model | name = x }`

The optimized AST has `Opt.Field Name Path` for nested field access, but the parser does NOT support dot-separated paths in record update syntax.

### Syntax

```canopy
-- Current (invalid):
{ model | user.name = newName }

-- New:
{ model | user.name = newName }
{ model | settings.theme.primaryColor = blue }
```

### Implementation

**Parser change** (`Parse/Expression.hs`):
1. In the record update parser, allow dot-separated field names
2. Produce an AST node with a list of field segments instead of a single field name

**Canonicalization** (`Canonicalize/Expression.hs`):
1. Desugar nested updates to the verbose form using `let` bindings

```canopy
-- { model | user.name = newName }
-- desugars to:
let _oldUser = model.user
in { model | user = { _oldUser | name = newName } }

-- { model | settings.theme.primaryColor = blue }
-- desugars to:
let _oldSettings = model.settings
    _oldTheme = _oldSettings.theme
in { model | settings = { _oldSettings | theme = { _oldTheme | primaryColor = blue } } }
```

**Type checking**: No changes needed. The desugared form is already valid Canopy.

### Estimated effort: 3-4 days

## Testing

### String Interpolation (`${}`)
- Parser tests: `${}` with simple variables, function calls, nested parens, escaped `$`
- Verify `[i|...|]` syntax still works unchanged
- Verify desugaring reuses existing `canonicalizeInterpolation` path
- Golden tests: generated JS matches existing interpolation output

### Nested Record Updates
- Parser tests: single-level (unchanged), two-level, three-level nesting
- Canonicalization tests: correct desugaring with proper scoping
- Type check tests: mismatched field types produce clear errors
- Edge cases: multiple nested updates in one expression, mixing nested and flat updates

## Timeline

### Days 1-2: `${}` String Interpolation
- Parser changes in `Parse/String.hs`
- Tests verifying reuse of existing desugaring pipeline
- Update formatter to handle both syntaxes

### Days 3-5: Nested Record Updates
- Parser changes in `Parse/Expression.hs`
- Canonicalization desugaring in `Canonicalize/Expression.hs`
- Tests and golden tests

## Definition of Done

- [x] `[i|Hello #{name}!|]` parses and compiles correctly
- [ ] `"Hello ${name}!"` parses and compiles correctly
- [ ] Non-String interpolation expressions produce clear type errors with both syntaxes
- [ ] `{ model | user.name = x }` parses and compiles correctly
- [ ] Three-level nesting works: `{ model | a.b.c = x }`
- [ ] All existing tests pass (no regressions)
- [ ] LSP provides completions inside `${}` and after dots in record updates
- [ ] Formatter handles both features correctly
