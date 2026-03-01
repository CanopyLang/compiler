# Plan 15: FFI String-to-Text Migration

**Priority:** HIGH
**Effort:** Medium (1–3 days)
**Risk:** Medium — touches 30+ functions across 2 files

## Problem

The FFI subsystem operates almost entirely on `String` (`[Char]`) instead of `Text`. This affects 30+ functions across `Generate/JavaScript.hs` and `Canonicalize/Module/FFI.hs`. Every FFI compilation involves:
- `Text.unpack` (6+ times in JavaScript.hs) to convert `Text` → `String`
- String processing (parsing, concatenation, manipulation)
- `BB.stringUtf8` to convert `String` → `Builder`

This is O(n) extra allocation per FFI file on every compilation, where n is the file content size.

## Files to Modify

### `packages/canopy-core/src/FFI/Types.hs`

Change the 3 newtypes from `String` to `Text`:
```haskell
-- Line 101: newtype JsSourcePath = JsSourcePath { unJsSourcePath :: String }
-- Change to:
newtype JsSourcePath = JsSourcePath { unJsSourcePath :: Text }

-- Line 110: newtype JsSource = JsSource { unJsSource :: String }
-- Change to:
newtype JsSource = JsSource { unJsSource :: Text }

-- Line 119: newtype FFIFuncName = FFIFuncName { unFFIFuncName :: String }
-- Change to:
newtype FFIFuncName = FFIFuncName { unFFIFuncName :: Text }
```

### `packages/canopy-core/src/Generate/JavaScript.hs`

Migrate these 16 functions from `String` to `Text`:

| Line | Function | Current Signature |
|------|----------|-------------------|
| 102 | `extractFFIAliases` | `Map String FFIInfo -> ...` |
| 111 | `generateFFIContent` | `... -> Map String FFIInfo -> Builder` |
| 133 | `generateFFIValidators` | `... -> Map String FFIInfo -> Builder` |
| 145 | `collectValidators` | `String -> FFIInfo -> ...` |
| 178 | `formatFFIFileFromInfo` | `String -> FFIInfo -> ...` |
| 186 | `generateFFIBindingsFromInfo` | `... -> String -> FFIInfo -> ...` |
| 199 | `extractFFIFunctionBindings` | `... -> String -> String -> String -> [Builder]` |
| 206 | `extractCanopyTypeFunctions` | `[String] -> [(String, String)]` |
| 217 | `extractCanopyType` | `String -> Maybe String` |
| 227 | `findFunctionName` | `[String] -> Maybe String` |
| 250 | `generateFunctionBinding` | `... -> String -> (String, String) -> [Builder]` |
| 260 | `generateSimpleBinding` | `String -> String -> String -> Int -> [Builder]` |
| 271 | `generateValidatedBinding` | `String -> String -> String -> Int -> String -> String -> [Builder]` |
| 291 | `extractReturnType` | `String -> String` |
| 306 | `typeToValidator` | `String -> Builder` |
| 338 | `trim` | `String -> String` |

Replace `BB.stringUtf8 ...` with `BB.byteString (Text.encodeUtf8 ...)` to avoid the double conversion.

### `packages/canopy-core/src/Canonicalize/Module/FFI.hs`

Migrate these 15 functions from `String` to `Text`:

| Line | Function | Key Change |
|------|----------|------------|
| 118 | `loadFFIFile` | Use `Data.Text.IO.readFile` |
| 183 | `parseJavaScriptContentPure` | `Text -> Text -> Either Text [FFIBinding]` |
| 190 | `extractFunctionsWithTypes` | `[Text] -> [FFIBinding]` |
| 206 | `isJSDocStart` | `Text -> Bool` (use `Text.isPrefixOf`) |
| 221 | `isJSDocEnd` | `Text -> Bool` |
| 248 | `parseNameAnnotation` | `Text -> Maybe Text` |
| 256 | `strip` | Use `Text.strip` (built-in) |
| 262 | `parseCanopyTypeAnnotation` | `Text -> Maybe Text` |
| 486 | `splitOnDot` | Use `Text.splitOn "."` |

Replace `lines`, `isPrefixOf`, `isInfixOf`, `dropWhile`, `drop . length` with `Text` equivalents.

## Migration Strategy

1. Change `FFI/Types.hs` newtypes first
2. Fix compilation errors working outward from the type changes
3. Replace `String` operations with `Text` operations one function at a time
4. Run `make build` after each file to catch errors incrementally

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Grep for `Text.unpack` in `Generate/JavaScript.hs` — should be zero or near-zero
4. Grep for `BB.stringUtf8` in FFI-related functions — should be replaced with `BB.byteString . Text.encodeUtf8`
5. Compile a project with FFI declarations — verify output is identical
