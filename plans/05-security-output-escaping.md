# Plan 05: HTML/JS Output Escaping

**Priority:** HIGH
**Effort:** Small (≤8 hours)
**Risk:** Low

## Problem

Module names are injected into HTML `<title>` tags and JavaScript execution context without any escaping in `Generate/Html.hs`:
- Line 49: `name` injected raw into `<title>` tag
- Line 68: `name` injected raw into JavaScript property access `Canopy.<name>.init(...)`
- Lines 101–131: Same pattern in `sandwichWithPrefetch`

The `escapeHtmlAttr` function exists (line 177) but is only used for prefetch filenames, never for module names.

## Files to Modify

### `packages/canopy-core/src/Generate/Html.hs`

1. **Create `escapeForHtml :: Name.Name -> Builder`** — escape `<`, `>`, `&`, `"`, `'` in the module name before inserting into `<title>`

2. **Create `escapeForJsIdentifier :: Name.Name -> Builder`** — validate that the name matches `[A-Za-z_$][A-Za-z0-9_$.]*` before inserting into JavaScript context. If validation fails, use a safe fallback.

3. **Apply to `sandwich`** (line 42):
   ```haskell
   sandwich moduleName javascript =
     let htmlName = escapeForHtml moduleName
         jsName = escapeForJsIdentifier moduleName
     in ... <> htmlName <> ... <> jsName <> ...
   ```

4. **Apply to `sandwichWithPrefetch`** (line 101): same pattern

### `packages/canopy-core/src/Generate/JavaScript.hs`

Apply JavaScript identifier validation to any module name injected into generated JS code (REPL generation, etc.).

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Add golden test: module name containing special characters produces safely escaped output
4. Verify `escapeForHtml` handles `</title><script>alert(1)</script>`
5. Verify `escapeForJsIdentifier` rejects `};alert(1);//`
