# Plan 05: `escapeJsString` Completeness

- **Priority**: MEDIUM
- **Effort**: Small (2-3h)
- **Risk**: Low

## Problem

The `escapeJsString` function in `Generate.JavaScript.FFI` escapes only four
characters: backslash, single quote, newline, and carriage return. It is missing
several characters that are dangerous in JavaScript string literals:

1. **Null byte (`\0`)**: Terminates strings in some JS engines and can truncate
   content, leading to logic errors or injection.

2. **U+2028 LINE SEPARATOR**: A valid Unicode character that acts as a line
   terminator in JavaScript (pre-ES2019). In a single-quoted string literal,
   it would terminate the string, potentially allowing injection.

3. **U+2029 PARAGRAPH SEPARATOR**: Same issue as U+2028.

Additionally, `sanitizeScriptElementString` in `Generate.JavaScript.Builder`
handles `</script>` and `<!--` injection for HTML-embedded scripts, but does
NOT handle U+2028/U+2029 (which are relevant even in non-HTML contexts).

### Current Code

**File**: `/home/quinten/fh/canopy/packages/canopy-core/src/Generate/JavaScript/FFI.hs`

At lines 394-401, `escapeJsString` handles only four characters:

```haskell
escapeJsString :: String -> String
escapeJsString = concatMap escapeJsChar
  where
    escapeJsChar '\\' = "\\\\"
    escapeJsChar '\'' = "\\'"
    escapeJsChar '\n' = "\\n"
    escapeJsChar '\r' = "\\r"
    escapeJsChar c = [c]
```

Missing escape cases:
- `'\0'` (null) -- should become `"\\0"`
- `'\x2028'` (LINE SEPARATOR) -- should become `"\\u2028"`
- `'\x2029'` (PARAGRAPH SEPARATOR) -- should become `"\\u2029"`

### Where `escapeJsString` Is Called

**File**: `/home/quinten/fh/canopy/packages/canopy-core/src/Generate/JavaScript/FFI.hs`

At line 280, used to escape the FFI call path string:

```haskell
callPath = "'" ++ escapeJsString (alias ++ "." ++ funcName) ++ "'"
```

This is the only call site. The string is placed inside a single-quoted JS
literal, so the missing characters are directly exploitable if a crafted alias
or function name contains them.

### The `sanitizeScriptElementString` Function

**File**: `/home/quinten/fh/canopy/packages/canopy-core/src/Generate/JavaScript/Builder.hs`

At lines 64-71, `sanitizeScriptElementString` handles `</script>` and `<!--`:

```haskell
sanitizeScriptElementString :: ES.String -> ES.String
sanitizeScriptElementString = sanitizeHtmlComment . sanitizeScriptTag

sanitizeScriptTag :: ES.String -> ES.String
sanitizeScriptTag str = Utf8.joinConsecutivePairSep (backslash, forwardslash) (Utf8.split forwardslash str)

sanitizeHtmlComment :: ES.String -> ES.String
sanitizeHtmlComment str = Utf8.joinConsecutivePairSep (backslash, exclamationMark) (Utf8.split exclamationMark str)
```

This operates on `ES.String` (the internal `Canopy.String` UTF-8 type), not
`String`. It is a different function serving a different purpose (HTML context
safety vs. JS string literal safety). U+2028/U+2029 are not relevant here
because `sanitizeScriptElementString` operates on the outer script element
content, not inside string literals.

### Golden Tests

**File**: `/home/quinten/fh/canopy/test/Golden/SecurityGolden.hs`

There are existing golden tests for JS escaping (`EscapeScriptTag`,
`EscapeBackslash`). These test the codegen pipeline end-to-end. A new golden
test should cover the null byte and Unicode line separator cases, though these
are harder to inject through the Canopy source language. The primary risk is
through FFI alias names, so a unit test of `escapeJsString` itself is more
appropriate.

## Files to Modify

### 1. `Generate/JavaScript/FFI.hs` (lines 394-401)

**Current**:
```haskell
escapeJsString :: String -> String
escapeJsString = concatMap escapeJsChar
  where
    escapeJsChar '\\' = "\\\\"
    escapeJsChar '\'' = "\\'"
    escapeJsChar '\n' = "\\n"
    escapeJsChar '\r' = "\\r"
    escapeJsChar c = [c]
```

**Proposed**:
```haskell
escapeJsString :: String -> String
escapeJsString = concatMap escapeJsChar
  where
    escapeJsChar '\\' = "\\\\"
    escapeJsChar '\'' = "\\'"
    escapeJsChar '"' = "\\\""
    escapeJsChar '\n' = "\\n"
    escapeJsChar '\r' = "\\r"
    escapeJsChar '\0' = "\\0"
    escapeJsChar '\x2028' = "\\u2028"
    escapeJsChar '\x2029' = "\\u2029"
    escapeJsChar c = [c]
```

Characters added:
- `'"'` -> `"\\\""` -- double quote, defense-in-depth for contexts where the
  string might end up in double quotes
- `'\0'` -> `"\\0"` -- null byte
- `'\x2028'` -> `"\\u2028"` -- LINE SEPARATOR
- `'\x2029'` -> `"\\u2029"` -- PARAGRAPH SEPARATOR

### 2. Update Haddock documentation

Update the function documentation (lines 388-393) to list all escaped characters:

```haskell
-- | Escape a string for safe inclusion in a JavaScript string literal.
--
-- Escapes all characters that could break out of or corrupt a JS string:
--
-- * Backslash (@\\@) -- escape character itself
-- * Single quote (@'@) -- string delimiter
-- * Double quote (@\"@) -- defense-in-depth for double-quoted contexts
-- * Newline (@\\n@) -- line terminator
-- * Carriage return (@\\r@) -- line terminator
-- * Null byte (@\\0@) -- string terminator in some engines
-- * U+2028 LINE SEPARATOR -- JS line terminator (pre-ES2019)
-- * U+2029 PARAGRAPH SEPARATOR -- JS line terminator (pre-ES2019)
--
-- @since 0.19.2
```

## Verification

### Unit Tests

Add tests in the existing FFI test module or a new
`test/Unit/Generate/JavaScript/FFITest.hs`:

```haskell
testEscapeJsString :: TestTree
testEscapeJsString = testGroup "escapeJsString"
  [ testCase "escapes backslash" $
      FFI.escapeJsString "a\\b" @?= "a\\\\b"
  , testCase "escapes single quote" $
      FFI.escapeJsString "it's" @?= "it\\'s"
  , testCase "escapes double quote" $
      FFI.escapeJsString "say \"hi\"" @?= "say \\\"hi\\\""
  , testCase "escapes newline" $
      FFI.escapeJsString "a\nb" @?= "a\\nb"
  , testCase "escapes carriage return" $
      FFI.escapeJsString "a\rb" @?= "a\\rb"
  , testCase "escapes null byte" $
      FFI.escapeJsString "a\0b" @?= "a\\0b"
  , testCase "escapes U+2028 LINE SEPARATOR" $
      FFI.escapeJsString "a\x2028b" @?= "a\\u2028b"
  , testCase "escapes U+2029 PARAGRAPH SEPARATOR" $
      FFI.escapeJsString "a\x2029b" @?= "a\\u2029b"
  , testCase "leaves normal characters unchanged" $
      FFI.escapeJsString "hello.world" @?= "hello.world"
  , testCase "handles empty string" $
      FFI.escapeJsString "" @?= ""
  , testCase "handles multiple special characters" $
      FFI.escapeJsString "'\\\n\0" @?= "\\'\\\\\\n\\0"
  ]
```

### Commands

```bash
# Build
stack build

# Run all tests
stack test

# Run FFI-specific tests
stack test --ta="--pattern FFI"

# Run golden security tests to verify no regressions
stack test --ta="--pattern Security"
```
