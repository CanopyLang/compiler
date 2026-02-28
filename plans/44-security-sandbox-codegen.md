# Plan 44: Code Generation Security Hardening

## Priority: MEDIUM
## Effort: Small (4-8 hours)
## Risk: Low — defensive additions to codegen

## Problem

Generated JavaScript runs in user browsers and Node.js. The code generator should defensively prevent common XSS and injection patterns in generated output.

### Key Files
- `packages/canopy-core/src/Generate/JavaScript/Expression.hs`
- `packages/canopy-core/src/Generate/JavaScript.hs`
- `packages/canopy-core/src/Generate/Html.hs`

## Implementation Plan

### Step 1: Audit string escaping in JS codegen

Verify that all string literals in generated JS are properly escaped:
- Backslash sequences
- Quote characters
- Unicode escapes
- Template literal backticks
- Null bytes

### Step 2: Verify HTML escaping

In `Generate/Html.hs`, verify that user-provided strings are HTML-escaped before insertion:
- `<`, `>`, `&`, `"`, `'` must be escaped
- Attribute values must be quoted
- No raw HTML injection

### Step 3: Add Content-Security-Policy headers

When generating HTML pages (e.g., `canopy make --output=html`), include CSP headers:

```html
<meta http-equiv="Content-Security-Policy"
      content="default-src 'self'; script-src 'self'">
```

### Step 4: Audit eval-like patterns

Search generated JS for any `eval`, `Function()`, or `innerHTML` usage:
- Replace with safer alternatives
- Document any necessary exceptions

### Step 5: Add security-focused golden tests

Create test modules that include user-controlled strings and verify the generated JS properly escapes them.

### Step 6: Tests

- Golden test: string with `<script>` tags properly escaped
- Golden test: string with backslashes properly escaped
- Golden test: HTML attributes properly quoted
- Test CSP header presence in HTML output

## Dependencies
- None
