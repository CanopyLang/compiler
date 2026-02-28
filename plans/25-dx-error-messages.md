# Plan 25: Error Message Quality Improvements

## Priority: HIGH
## Effort: Medium (2-3 days)
## Risk: Low — improvements to existing error rendering

## Problem

Error messages in Canopy inherit Elm's excellent error format but have gaps:
- FFI errors lack context about which JS file and function caused the issue
- Type errors in interpolation (`StringConcat`) don't explain the String requirement clearly
- Build errors don't suggest common fixes
- Some errors show internal names (e.g., canonical module names) instead of user-facing names

### Key Files
- `packages/canopy-core/src/Reporting/Error/Syntax.hs`
- `packages/canopy-core/src/Reporting/Error/Type.hs`
- `packages/canopy-core/src/Reporting/Error/Canonicalize.hs`
- `packages/canopy-core/src/Reporting/Render/Type.hs`

## Implementation Plan

### Step 1: Improve FFI error messages

Add source location and JS file path to FFI validation errors:

```
-- FFI TYPE MISMATCH -------- src/MyModule.can

The FFI function `fetchData` in `src/MyModule.ffi.js` returns a value
that doesn't match its declared type.

    Declared: Task Http.Error String
    Actual:   The JS function returns a raw Promise

Hint: FFI functions must return Canopy-compatible types. Use the
`Task` type for async operations.
```

### Step 2: Improve interpolation error messages

When `StringConcat` type checking fails, explain that interpolation requires String:

```
-- TYPE MISMATCH -------- src/Main.can

The interpolation hole on line 15 expects a String, but got:

    Int

    15| greeting = [i|Hello #{count}!|]
                               ^^^^^

Hint: Use `String.fromInt` to convert the Int to a String:

    greeting = [i|Hello #{String.fromInt count}!|]
```

### Step 3: Add "Did you mean?" suggestions

For name resolution errors, suggest similar names:

```
-- NAME NOT FOUND -------- src/Main.can

I cannot find `Stirng.toInt`.

    42| result = Stirng.toInt input
                 ^^^^^^

Did you mean one of these?

    String.toInt
    String.toFloat
```

### Step 4: Improve build system errors

Add actionable suggestions to common build errors:

```
-- MISSING DEPENDENCY -------- canopy.json

The module `Http` is imported but `elm/http` is not in your dependencies.

To fix this, run:

    canopy install elm/http
```

### Step 5: Colorize and format consistently

Ensure all error paths use the `Reporting.Doc.ColorQQ` quasiquoter for consistent formatting.

### Step 6: Golden tests for error messages

Add golden tests for every error variant to prevent regressions in message quality.

## Dependencies
- None
