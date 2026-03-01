# Plan 09: FFI Codegen String Elimination

**Priority**: HIGH
**Effort**: Small (1 day)
**Risk**: Low
**Audit Finding**: `Generate/JavaScript/FFI.hs` has 10+ functions using `:: String` in the codegen hot path

---

## Problem

While Plan 11 (previous audit) converted the main JS generation pipeline from `String` to `ByteString/Builder`, the FFI code generation module was not converted. These functions remain on `[Char]`:

| Function | File | Signature |
|----------|------|-----------|
| `escapeJsString` | FFI.hs:409 | `String -> String` |
| `isValidJsIdentifier` | FFI.hs:388 | `String -> Bool` |
| `trim` | FFI.hs:375 | `String -> String` |
| `extractReturnType` | FFI.hs:326 | `String -> String` |
| `generateSimpleBinding` | FFI.hs:293 | `String -> String -> String -> Int -> [Builder]` |
| `generateValidatedBinding` | FFI.hs:304 | `String -> String -> String -> Int -> String -> String -> [Builder]` |
| `collectValidators` | FFI.hs:150 | `String -> FFIInfo -> [Builder] -> [Builder]` |
| `formatFFIFileFromInfo` | FFI.hs:184 | `String -> FFIInfo -> [Builder] -> [Builder]` |
| `typeToValidator` | FFI.hs:341 | `String -> Builder` |
| `tokenizeChars` | FFI/TypeParser.hs:70 | `String -> [Token]` |
| `parseWordType` | FFI/TypeParser.hs:193 | `String -> FFIType` |

Every FFI function compiled goes through these, creating `[Char]` linked lists that are immediately converted to `Builder`.

---

## Solution

Convert all `String` functions to `ByteString` or `Text` (matching the rest of the codegen pipeline).

---

## Implementation

### Step 1: Convert FFI.hs Core Functions

**File: `packages/canopy-core/src/Generate/JavaScript/FFI.hs`**

```haskell
-- Before
escapeJsString :: String -> String
isValidJsIdentifier :: String -> Bool
trim :: String -> String

-- After
escapeJsString :: ByteString -> ByteString
isValidJsIdentifier :: ByteString -> Bool
trim :: ByteString -> ByteString
```

For `escapeJsString`, use `ByteString` operations:

```haskell
escapeJsString :: ByteString -> ByteString
escapeJsString = BS.concatMap escapeChar
  where
    escapeChar c
      | c == 0x27 = "\\'"     -- single quote
      | c == 0x5C = "\\\\"    -- backslash
      | c == 0x0A = "\\n"     -- newline
      | c == 0x0D = "\\r"     -- carriage return
      | c < 0x20  = hexEscape c
      | otherwise = BS.singleton c
```

For `isValidJsIdentifier`:

```haskell
isValidJsIdentifier :: ByteString -> Bool
isValidJsIdentifier bs =
  not (BS.null bs)
    && isJsIdentStart (BS.index bs 0)
    && BS.all isJsIdentChar (BS.drop 1 bs)
```

For `trim`:

```haskell
trim :: ByteString -> ByteString
trim = BS.dropWhile isSpace . BS.reverse . BS.dropWhile isSpace . BS.reverse
-- Or use strip from bytestring if available
```

### Step 2: Convert Binding Generators

```haskell
-- Before: String parameters
generateSimpleBinding :: String -> String -> String -> Int -> [Builder]

-- After: ByteString parameters
generateSimpleBinding :: ByteString -> ByteString -> ByteString -> Int -> [Builder]
```

### Step 3: Convert FFI/TypeParser.hs

```haskell
-- Before
tokenizeChars :: String -> [Token]
parseWordType :: String -> FFIType

-- After
tokenizeChars :: ByteString -> [Token]
parseWordType :: ByteString -> FFIType
```

### Step 4: Update Call Sites

All callers that pass `String` to these functions need to use `ByteString` instead. The main caller is `Generate/JavaScript/FFIRuntime.hs` and `Foreign/FFI.hs`.

---

## Validation

```bash
make build
make test

# Verify no String signatures remain in FFI codegen
grep ":: String" packages/canopy-core/src/Generate/JavaScript/FFI.hs
# Should be empty

grep ":: String" packages/canopy-core/src/FFI/TypeParser.hs
# Should be empty

# Golden tests verify output unchanged
stack test --ta="--pattern JsGen"
```

---

## Success Criteria

- [ ] Zero `:: String` signatures in `Generate/JavaScript/FFI.hs`
- [ ] Zero `:: String` signatures in `FFI/TypeParser.hs`
- [ ] All FFI codegen uses `ByteString` or `Builder`
- [ ] Golden test output unchanged (byte-for-byte identical)
- [ ] `make build` passes with zero warnings
- [ ] `make test` passes
