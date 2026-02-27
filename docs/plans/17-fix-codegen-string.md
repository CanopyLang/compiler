# Plan 17 — Replace String Intermediates in Code Generation

**Priority:** Tier 3 (Performance)
**Effort:** 2 days
**Risk:** High (core codegen path, must preserve exact output)
**Files:** `packages/canopy-core/src/Generate/JavaScript/Builder.hs`, `Generate/JavaScript/Expression.hs`, `Generate/JavaScript.hs`, `Generate/JavaScript/Functions.hs`

---

## Problem

Every JavaScript statement goes through a triple representation:

```
Stmt → JSStatement (language-javascript AST) → String (renderToString) → Builder (stringUtf8)
```

The bottleneck is `renderToString` which materializes a full Haskell `String` (`[Char]` linked list) for every statement before `B.stringUtf8` re-encodes it to bytes. Additional `String` intermediates:

- `nameToString`: `LBS.unpack . B.toLazyByteString . Name.toBuilder`
- `builderToString`: same pattern for float/string literals
- Every integer literal: `show n` allocates a String
- FFI binding generation uses `++` string concatenation throughout

For 10,000 AST nodes: tens of thousands of intermediate `String` allocations.

## Design Options

### Option A: Direct Builder emission (preferred)

Bypass the `language-javascript` AST entirely and emit `Builder` values directly from the Canopy AST. This is the approach the original code comment (Builder.hs:73-84) says was "neutral for performance" — but that may have been before the codebase grew.

```haskell
-- Instead of:
stmtToBuilder stmt = B.stringUtf8 (renderToString (stmtToJS stmt))

-- Emit directly:
stmtToBuilder :: Stmt -> Builder
stmtToBuilder (Assign name expr) =
  Name.toBuilder name <> " = " <> exprToBuilder expr <> ";\n"
```

This eliminates both the `JSStatement` intermediate and the `String` intermediate.

### Option B: Use language-javascript's Builder output

If `language-javascript` supports rendering to `Builder` or `ByteString` directly (via a custom printer), use that instead of `renderToString`. This keeps the `JSStatement` intermediate but eliminates the `String` step.

### Option C: Targeted String elimination

Keep the current architecture but replace the worst `String` intermediates:

- Replace `show n` with `BB.intDec n` for integer literals
- Replace `nameToString` with `Name.toBuilder` used directly
- Replace `builderToString` with direct `Builder` usage
- Replace `String` concatenation in FFI generation with `Builder` composition

## Implementation (Option C — lowest risk, immediate wins)

### Step 1: Replace integer literal rendering

```haskell
-- Before (Builder.hs ~line 240):
intToJS n = B.stringUtf8 (show n)

-- After:
intToJS n = BB.intDec n
```

### Step 2: Replace nameToString with Builder

```haskell
-- Before:
nameToString name = LBS.unpack (B.toLazyByteString (Name.toBuilder name))
-- Then used as: B.stringUtf8 (nameToString name)

-- After: Use Name.toBuilder directly
-- Every call site: replace B.stringUtf8 (nameToString x) with Name.toBuilder x
```

### Step 3: Replace float literal rendering

```haskell
-- Before:
floatToJS f = B.stringUtf8 (show f)

-- After:
floatToJS f = BB.doubleDec f
```

### Step 4: Replace String concatenation in FFI generation

In `Generate/JavaScript.hs` lines 230-360, replace `++` patterns:

```haskell
-- Before:
let binding = "var " ++ jsVarName ++ " = " ++ funcBody ++ ";"

-- After:
let binding = "var " <> BB.stringUtf8 jsVarName <> " = " <> BB.stringUtf8 funcBody <> ";"
```

### Step 5: Golden test validation

The JS output must not change by even a single byte. Compare against golden files:

```bash
make test-golden
```

### Step 6: Optional — Profile before/after

```bash
# Build with profiling
stack build --profile canopy-core
# Run on a large module
canopy make +RTS -p -h large-module.can
# Compare allocation counts
```

## Validation

```bash
make build && make test
make test-golden  # Must produce identical JS output
```

## Acceptance Criteria

- Zero `show n` for integer literals in codegen (replaced with `BB.intDec`)
- Zero `nameToString` → `stringUtf8` round-trips (use `toBuilder` directly)
- Zero `++` string concatenation in `Generate/JavaScript.hs` FFI generation
- Golden test output is byte-for-byte identical
- `make build && make test` passes
