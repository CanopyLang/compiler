# Plan 26a: Quick Ergonomics (String Interpolation + Nested Records)

## Priority: CRITICAL — Tier 0
## Effort: 1-2 weeks
## Depends on: Nothing (pure parser desugaring)
## Split from: Plan 26 (Language Ergonomics)

## Why This Is Tier 0

String interpolation and nested record updates are the two most-requested Elm features. They require zero type system changes — just parser recognition and desugaring during canonicalization. They can ship in parallel with Plan 01 (ESM) and Plan 03 (Packages).

These two features instantly differentiate Canopy from Elm for anyone who tries it.

## Feature 1: String Interpolation

### Syntax

```canopy
-- Current (verbose):
greeting = "Hello, " ++ user.name ++ "! You have " ++ String.fromInt count ++ " messages."

-- New:
greeting = "Hello, ${user.name}! You have ${String.fromInt count} messages."
```

### Rules

- Only expressions that return `String` are allowed inside `${}`
- Non-String expressions require explicit conversion (`String.fromInt`, etc.)
- This is a compile-time transformation, NOT runtime template processing
- Old string concatenation with `++` continues to work
- Backtick strings are NOT used — this uses regular double-quoted strings with `${}` syntax

### Implementation

**Parser change** (`Parse/Expression.hs`):
1. When parsing a string literal, check for `${` sequences
2. Parse the expression inside `${...}` using the standard expression parser
3. Produce an AST node representing the interpolated string

**Canonicalization** (`Canonicalize/Expression.hs`):
1. Desugar interpolated strings to `String.concat [...]`
2. Each `${}` expression becomes an element of the list
3. Static text segments become string literals in the list

```canopy
-- "Hello, ${user.name}! You have ${String.fromInt count} messages."
-- desugars to:
String.concat [ "Hello, ", user.name, "! You have ", String.fromInt count, " messages." ]
```

**Type checking**: No changes needed. `String.concat` already requires `List String`. If the expression inside `${}` doesn't return `String`, the type checker catches it with a clear error message.

**Error message**: If a non-String expression is used, emit a helpful error:

```
-- TYPE MISMATCH ────────────────── src/App.can

The expression inside ${...} must return a String, but this returns an Int:

    15| greeting = "Count: ${count}"
                            ^^^^^
                            count : Int

Hint: Use String.fromInt to convert:

    greeting = "Count: ${String.fromInt count}"
```

### Testing

- Parser tests: interpolation with simple variables, function calls, nested parens, escaped `$`
- Canonicalization tests: correct desugaring to `String.concat`
- Type check tests: non-String expressions produce clear errors
- Golden tests: generated JS is correct
- Edge cases: empty interpolation `${}`, adjacent interpolations `${a}${b}`, `$` without `{`

## Feature 2: Nested Record Updates

### Syntax

```canopy
-- Current (invalid in Elm):
{ model | user.name = newName }

-- New:
{ model | user.name = newName }
{ model | settings.theme.primaryColor = blue }
```

### Rules

- Dot-separated paths in record update syntax desugar to nested updates
- Arbitrarily deep nesting is supported
- Multiple nested updates in one expression work correctly
- This is purely additive — existing single-field updates are unchanged

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

### Testing

- Parser tests: single-level (unchanged), two-level, three-level nesting
- Canonicalization tests: correct desugaring with proper scoping
- Type check tests: mismatched field types produce clear errors
- Golden tests: generated JS matches hand-written nested updates
- Edge cases: multiple nested updates in one expression, mixing nested and flat updates

## Timeline

### Week 1: String Interpolation
- Day 1-2: Parser changes + tests
- Day 3: Canonicalization desugaring + tests
- Day 4: Error messages + golden tests
- Day 5: LSP/formatter updates

### Week 2: Nested Record Updates
- Day 1-2: Parser changes + tests
- Day 3: Canonicalization desugaring + tests
- Day 4: Error messages + golden tests
- Day 5: LSP/formatter updates + integration testing

## Definition of Done

- [ ] `"Hello, ${name}!"` parses and compiles correctly
- [ ] Non-String interpolation expressions produce clear type errors
- [ ] `{ model | user.name = x }` parses and compiles correctly
- [ ] Three-level nesting works: `{ model | a.b.c = x }`
- [ ] All existing tests pass (no regressions)
- [ ] LSP provides completions inside `${}` and after dots in record updates
- [ ] Formatter handles both features correctly
