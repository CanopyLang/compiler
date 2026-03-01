# Plan 06: FFI Codegen Injection Prevention

**Priority:** HIGH
**Effort:** Small (≤8 hours)
**Risk:** Low

## Problem

FFI binding generation in `Generate/JavaScript.hs` (lines 186–288) uses raw string concatenation to build JavaScript code. The `alias` and `funcName` values are injected into `var` declarations, property accesses, and string literals without validation:

- Line 195: `var <alias> = <alias> || {};` — alias injected as JS variable name
- Line 253: `$author$project$<alias>$<funcName>` — used as JS variable name
- Line 254: `'<alias>.<funcName>'` — used in string literal without escaping

The `funcName` comes from `@name` annotations parsed with a simple `takeWhile` (line 244) that does not exclude JS-special characters like `;`, `}`, `"`.

## Files to Modify

### `packages/canopy-core/src/Generate/JavaScript.hs`

1. **Add `isValidJsIdentifier :: String -> Bool`**:
   ```haskell
   isValidJsIdentifier s = case s of
     [] -> False
     (c:cs) -> isValidFirst c && all isValidRest cs
     where
       isValidFirst c = Char.isAlpha c || c == '_' || c == '$'
       isValidRest c = Char.isAlphaNum c || c == '_' || c == '$'
   ```

2. **Validate `funcName`** in `extractFFIFunctionBindings` (line 199) — reject names that fail `isValidJsIdentifier`

3. **Validate `alias`** in `generateFFIBindingsFromInfo` (line 186) — reject aliases that fail validation

4. **Escape string literals** in `callPath` construction (line 254) — escape `'` and `\` characters:
   ```haskell
   callPath = "'" ++ escapeJsString (alias ++ "." ++ funcName) ++ "'"
   ```

5. **Consider using the `language-javascript` AST** (already imported in the codebase) for FFI binding generation instead of raw string concatenation, which would make injection structurally impossible.

### `packages/canopy-core/src/Canonicalize/Module/FFI.hs`

Tighten the `@name` annotation parser:
- Line 248: `parseNameAnnotation` should validate the extracted name against `isValidJsIdentifier`
- Reject annotations with names containing `;`, `}`, `"`, `'`, newlines

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Add test: FFI file with `@name` containing `;` is rejected with clear error
4. Add test: FFI file with valid `@name` generates correct binding
