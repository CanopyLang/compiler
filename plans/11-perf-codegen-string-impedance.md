# Plan 11: Codegen String Impedance (language-javascript)

**Priority:** CRITICAL
**Effort:** Medium (1-2 days)
**Risk:** Medium (golden test diffs expected, but semantics preserved)

## Problem

The JavaScript code generation path suffers from severe String impedance mismatch.
Every JS expression and statement goes through multiple unnecessary String
conversions before reaching the final Builder output.

### Current Data Flow (per expression/statement)

```
Name (Utf8 ByteString)
  -> nameToString (LBS.unpack . toLazyByteString . toBuilder)  -- allocates [Char]
  -> JSIdentifier/JSStringLiteral/etc (takes ByteString in the fork!)
  -> renderToString (TL.unpack . decodeUtf8 . toLazyByteString . renderJS)  -- allocates [Char] AGAIN
  -> B.stringUtf8  -- re-encodes [Char] to Builder
```

The forked `language-javascript` library (at `github.com/quintenkasteel/language-javascript`,
commit `9df069c`) already uses **`ByteString`** for `JSIdentifier`, `JSStringLiteral`,
`JSLiteral`, and **`Double`** for `JSDecimal`. The pretty printer's `renderJS` returns
`Blaze.ByteString.Builder.Builder` directly, which is compatible with
`Data.ByteString.Builder`.

Yet `Builder.hs` still converts through `String` at two points:

1. **Input side** (`nameToString`/`builderToString`): 27 call sites convert
   `Name`/`Builder` to `String` before constructing the `language-javascript` AST.
2. **Output side** (`renderToString` + `B.stringUtf8`): 4 call sites convert the
   rendered AST to `String` and then back to `Builder`.

### Affected Files and Line Numbers

**`/home/quinten/fh/canopy/packages/canopy-core/src/Generate/JavaScript/Builder.hs`:**

- Lines 214-215: `nameToString` definition -- converts Name -> String
- Lines 218-219: `builderToString` definition -- converts Builder -> String
- Lines 242-243: `exprToJS` String/Float cases use `builderToString`
- Lines 251-252: `exprToJS` Ref/Access cases use `nameToString`
- Lines 271, 295, 297, 298, 301, 305, 308: `stmtToJS` uses `nameToString` extensively
- Lines 335-336: `lvalueToJS` uses `nameToString`
- Lines 348: `exprToJSWithSpace` String case uses `builderToString`
- Lines 358, 394, 404, 406-407: helper functions use `nameToString`
- Lines 434, 442, 454, 457-458: mode-aware functions use `nameToString`
- Lines 413-414: `stmtToBuilder` calls `renderToString` then `B.stringUtf8`
- Lines 417-418: `exprToBuilder` calls `renderToString` then `B.stringUtf8`
- Lines 421-422: `stmtToBuilderWithMode` same pattern
- Lines 424-425: `exprToBuilderWithMode` same pattern

**`/home/quinten/projects/language-javascript/src/Language/JavaScript/Parser/AST.hs`:**

- Line 320: `JSIdentifier !JSAnnot !ByteString` -- already takes ByteString
- Line 322: `JSDecimal !JSAnnot !Double` -- already takes Double
- Line 323: `JSLiteral !JSAnnot !ByteString` -- already takes ByteString
- Line 332: `JSStringLiteral !JSAnnot !ByteString` -- already takes ByteString

**`/home/quinten/projects/language-javascript/src/Language/JavaScript/Pretty/Printer.hs`:**

- Line 90: `renderJS :: JSAST -> Builder` -- returns Blaze Builder directly
- Line 95-97: `renderToString` goes through `TL.unpack . decodeUtf8 . toLazyByteString`

### Performance Impact

For a project with ~200 modules, each module generates hundreds of JS statements.
Every `nameToString` call allocates a full `[Char]` list, and every `renderToString`
call re-materializes the entire JS output as `[Char]` before converting back. This is
the single largest source of unnecessary allocation in the codegen phase.

## Solution

### Phase 1: Replace `nameToString`/`builderToString` with ByteString conversions

Since the forked `language-javascript` AST already uses `ByteString`, convert
`Name` and `Builder` directly to `ByteString` instead of `String`:

```haskell
-- BEFORE (line 214-215)
nameToString :: Name -> String
nameToString = LBS.unpack . B.toLazyByteString . Name.toBuilder

-- AFTER
nameToByteString :: Name -> ByteString
nameToByteString = LBS.toStrict . B.toLazyByteString . Name.toBuilder

-- BEFORE (line 218-219)
builderToString :: Builder -> String
builderToString = LBS.unpack . B.toLazyByteString

-- AFTER
builderToByteString :: Builder -> ByteString
builderToByteString = LBS.toStrict . B.toLazyByteString
```

Then replace all 27 call sites. For example:

```haskell
-- BEFORE (line 242)
String builder -> JS.JSStringLiteral noAnnot ("'" ++ builderToString builder ++ "'")

-- AFTER
String builder -> JS.JSStringLiteral noAnnot ("'" <> builderToByteString builder <> "'")
```

For `JSDecimal` (which takes `Double` in the fork), `show n` must become
the actual `Double` value or `read`/parse conversion:

```haskell
-- BEFORE (line 244)
Int n -> JS.JSDecimal noAnnot (show n)

-- AFTER: Use JSLiteral for integer display (since JSDecimal takes Double)
Int n -> JS.JSLiteral noAnnot (BS8.pack (show n))
```

### Phase 2: Replace `renderToString` with `renderJS` (Builder output)

The language-javascript fork's `renderJS` returns a `Blaze.ByteString.Builder.Builder`.
Blaze builder's `toLazyByteString` produces `LBS.ByteString`, which can be converted
to a bytestring `Builder` zero-copy:

```haskell
-- BEFORE (line 413-414)
stmtToBuilder :: Stmt -> Builder
stmtToBuilder stmt =
  B.stringUtf8 (JSP.renderToString (JSAstStatement (stmtToJS stmt) noAnnot)) <> B.stringUtf8 "\n"

-- AFTER
stmtToBuilder :: Stmt -> Builder
stmtToBuilder stmt =
  B.lazyByteString (Blaze.toLazyByteString (JSP.renderJS (JSAstStatement (stmtToJS stmt) noAnnot)))
    <> B.char7 '\n'
```

Or even simpler, add a `renderToBuilder` function to the fork:

```haskell
-- In language-javascript Pretty/Printer.hs
renderToBuilder :: JSAST -> Blaze.Builder
renderToBuilder = renderJS
```

### Phase 3: Verify with golden tests

The JS output should be byte-for-byte identical (since we are only changing the
intermediate representation, not the rendering logic). Run golden tests to confirm.

## Files to Modify

| File | Change |
|------|--------|
| `packages/canopy-core/src/Generate/JavaScript/Builder.hs` | Replace all `nameToString`/`builderToString` calls with ByteString conversions; replace `renderToString` with `renderJS` |
| `language-javascript` fork (if needed) | Add `renderToBuilder` convenience export |

## Migration Steps

1. Add `import qualified Data.ByteString.Char8 as BS8` to Builder.hs
2. Add `import Blaze.ByteString.Builder (toLazyByteString)` (or use the re-export from language-javascript)
3. Replace `nameToString` with `nameToByteString` (27 sites)
4. Replace `builderToString` with `builderToByteString` (5 sites)
5. Replace `JSP.renderToString` with `JSP.renderJS` + `toLazyByteString` (4 sites)
6. Handle `JSDecimal` integer case by using `JSLiteral` for integer values
7. Handle string concatenation: replace `"'" ++ x ++ "'"` with `"'" <> x <> "'"`

## Verification

```bash
# Run golden tests to verify byte-for-byte output equivalence
stack test --ta="--pattern JsGen"

# Run full test suite
make test

# Run benchmarks to measure improvement
stack bench --ba="--match prefix Bench.Generate"

# Profile codegen allocation
stack exec -- canopy make +RTS -s -RTS
```

## Expected Impact

- Eliminates ~54 String allocations per JS expression/statement (27 input + 4 output * average reuse)
- For a 200-module project generating ~10,000 statements: eliminates ~540,000 unnecessary `[Char]` list allocations
- Expected 15-30% reduction in codegen phase allocation
- Expected 5-15% wall-clock improvement in codegen phase
