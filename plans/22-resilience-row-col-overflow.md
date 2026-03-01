# Plan 22: Word16 Row/Col Overflow

**Priority:** MEDIUM
**Effort:** Medium (1-2d)
**Risk:** Medium -- Pervasive type change across parser, error reporting, and annotation modules

## Problem

The parser uses `Word16` for row and column tracking, which overflows silently at 65,535. Files with more than 65,535 lines or columns will wrap around to 0, producing incorrect source locations in error messages, diagnostics, and the annotation system.

### Type Definitions

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Parse/Primitives.hs` (lines 70-72)

```haskell
type Row = Word16
type Col = Word16
```

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Reporting/Annotation.hs` (lines 48-52)

```haskell
data Position
  = Position
      {-# UNPACK #-} !Word16
      {-# UNPACK #-} !Word16
  deriving (Eq, Show)
```

`Position` stores both row and column as `Word16`, which is the type backing `Row` and `Col`.

### Where Row/Col Are Incremented

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Parse/Space.hs`

Line 130 -- Column increment: `eatSpaces (plusPtr pos 1) end row (col + 1)`
Line 133 -- Row increment: `eatSpaces (plusPtr pos 1) end (row + 1) 1`
Line 170 -- Column increment in comment: `eatLineComment newPos end row (col + 1)`
Line 218 -- Row increment in multi-comment: `eatMultiCommentHelp (plusPtr pos 1) end (row + 1) 1 openComments`

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Parse/Primitives.hs`

Line 298 -- `word1`: `State src (plusPtr pos 1) end indent row (col + 1)`
Line 309 -- `word2`: `State src (plusPtr pos 2) end indent row (col + 2)`

All of these use plain `+` on `Word16`, which wraps on overflow without any error.

### Where Row/Col Are Consumed (34 files)

The `Row` and `Col` types are imported and used across the entire parser and error reporting infrastructure. Grep results show 34 files importing from `Parse.Primitives`:

```
packages/canopy-core/src/Json/Decode.hs
packages/canopy-core/src/Json/Decode/Parser.hs
packages/canopy-core/src/Json/Decode/Combinators.hs
packages/canopy-core/src/Json/Decode/AST.hs
packages/canopy-core/src/Parse/Keyword.hs
packages/canopy-core/src/Parse/String.hs
packages/canopy-core/src/Parse/Number.hs
packages/canopy-core/src/Parse/Symbol.hs
packages/canopy-core/src/Parse/Variable.hs
packages/canopy-core/src/Parse/Space.hs
packages/canopy-core/src/Parse/Shader.hs
packages/canopy-core/src/Parse/Interpolation.hs
packages/canopy-core/src/Canopy/Package.hs
packages/canopy-core/src/Canopy/Docs.hs
packages/canopy-core/src/Canopy/Constraint.hs
packages/canopy-core/src/Canopy/Version.hs
packages/canopy-core/src/Canopy/ModuleName.hs
packages/canopy-core/src/Reporting/Render/Code.hs
packages/canopy-core/src/Reporting/Error/Docs.hs
packages/canopy-core/src/Reporting/Error/Syntax/Type.hs
packages/canopy-core/src/Reporting/Error/Syntax/Expression.hs
packages/canopy-core/src/Reporting/Error/Syntax/Literal.hs
packages/canopy-core/src/Reporting/Error/Syntax/Pattern.hs
packages/canopy-core/src/Reporting/Error/Syntax/Types.hs
packages/canopy-core/src/Reporting/Error/Syntax/Helpers.hs
packages/canopy-core/src/Reporting/Error/Syntax/Module.hs
packages/canopy-core/src/Reporting/Error/Syntax/Expression/Sequence.hs
packages/canopy-core/src/Reporting/Error/Syntax/Expression/If.hs
packages/canopy-core/src/Reporting/Error/Syntax/Expression/Function.hs
packages/canopy-core/src/Reporting/Error/Syntax/Expression/Case.hs
packages/canopy-core/src/Reporting/Error/Syntax/Expression/Let.hs
packages/canopy-core/src/Reporting/Error/Syntax/Expression/Record.hs
packages/canopy-core/src/Reporting/Error/Syntax/Declaration/DeclStart.hs
packages/canopy-core/src/Reporting/Error/Syntax/Declaration/DeclBody.hs
```

### Serialization Impact

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Reporting/Annotation.hs` (lines 78-84)

```haskell
instance Binary Region where
  put (Region a b) = put a >> put b
  get = liftM2 Region get get

instance Binary Position where
  put (Position a b) = put a >> put b
  get = liftM2 Position get get
```

The `Binary` instance serializes `Position` as two `Word16` values. Changing to `Word32` would double the serialized size of every `Position` (4 bytes -> 8 bytes) and every `Region` (8 bytes -> 16 bytes). This affects:
- `.elmi` interface files (cached compilation artifacts)
- Any binary serialization of canonical/optimized ASTs

### Real-World Overflow Scenarios

1. **Generated code**: Code generators often produce files with >65K columns (single-line minified output)
2. **Large modules**: Elm/Canopy files rarely exceed 65K lines, but generated `.can` files might
3. **Long string literals**: A single string literal with >65K characters on one line
4. **Minified JSON**: `canopy.json` files could theoretically have long lines

The `maxSourceFileBytes` limit (`Canopy.Limits`) bounds file size but does not bound line count or column width.

## Proposed Solution: Word32 Migration

### Analysis: Word32 vs Word16

| Metric | Word16 | Word32 |
|--------|--------|--------|
| Max row | 65,535 | 4,294,967,295 |
| Max col | 65,535 | 4,294,967,295 |
| Position size | 4 bytes | 8 bytes |
| Region size | 8 bytes | 16 bytes |
| Parser State size | ~50 bytes | ~58 bytes |
| .elmi size impact | baseline | ~2x for position data |

`Word32` is sufficient for any realistic source file. A 4-billion-line file would be ~80GB assuming 20 chars/line.

### Performance Impact Assessment

The parser `State` struct is the hottest data structure in the compiler. It is created and consumed billions of times during parsing. Key concerns:

1. **State struct size**: Adding 8 bytes (2x Word16 -> 2x Word32) for row/col plus 2 bytes for indent. The `{-# UNPACK #-}` pragmas on `Position` fields will keep them unboxed.

2. **Unboxed tuple returns**: Functions like `eatSpaces` return `(# Status, Ptr Word8, Row, Col #)`. Changing `Row`/`Col` from `Word16` to `Word32` increases the return tuple size but since these are already unboxed, the overhead is minimal (register allocation rather than heap).

3. **Binary serialization**: `.elmi` files contain many `Region` values. Each grows by 8 bytes. For a module with ~1000 annotated nodes, that is ~8KB additional per file -- negligible.

4. **Memory**: Every AST node carries a `Region`. A large module with 10K nodes uses 80KB for positions at Word16, 160KB at Word32. This is well within acceptable bounds.

**Recommendation:** The performance impact of Word32 is minimal and the safety improvement is significant.

### Phase 1: Change Type Aliases

#### Step 1.1: Update Parse.Primitives

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Parse/Primitives.hs` (lines 70-72)

```haskell
-- Before:
type Row = Word16
type Col = Word16

-- After:
type Row = Word32
type Col = Word32
```

Add `import Data.Word (Word32, Word8)` (replacing `Word16` with `Word32` in the import).

#### Step 1.2: Update Reporting.Annotation

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Reporting/Annotation.hs` (lines 48-52)

```haskell
-- Before:
data Position
  = Position
      {-# UNPACK #-} !Word16
      {-# UNPACK #-} !Word16

-- After:
data Position
  = Position
      {-# UNPACK #-} !Word32
      {-# UNPACK #-} !Word32
```

Update import: `import Data.Word (Word32)`.

#### Step 1.3: Update State indent field

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Parse/Primitives.hs` (line 65)

```haskell
-- Before:
_indent :: !Word16,

-- After:
_indent :: !Word32,  -- or keep Word16 since indent depth is always small
```

The indent field tracks column-level indentation. Since indentation depth never exceeds a few hundred, `Word16` is fine. But for consistency and to avoid mixed-width arithmetic, changing to `Word32` is cleaner.

### Phase 2: Fix All Downstream Consumers

#### Step 2.1: Update Parse.Space

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Parse/Space.hs`

Line 17: Change `import Data.Word (Word8, Word16)` to `import Data.Word (Word8, Word32)`.

Line 210: `eatMultiCommentHelp` takes `Word16` for `openComments` -- this can stay `Word16` since nesting depth is bounded.

Line 69: `checkAligned` takes `(Word16 -> Row -> Col -> x)` -- must update to `(Word32 -> Row -> Col -> x)`.

#### Step 2.2: Update Error Reporting Modules

All 34 consumer files use `Row` and `Col` as type aliases, so they will automatically pick up the change. However, any file that explicitly uses `Word16` instead of the `Row`/`Col` aliases must be updated.

Files that directly use `Word16` (found via grep):

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Reporting/Error/Syntax/Types.hs` (line 59)
**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Reporting/Error/Syntax/Helpers.hs` (line 35)

These import `Word16` from `Data.Word` and use it alongside `Row`/`Col`. They may need to update if they construct `Position` values directly.

#### Step 2.3: Update Diagnostic.hs

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Reporting/Diagnostic.hs` (line 47)

```haskell
-- Before:
import Data.Word (Word16)
newtype ErrorCode = ErrorCode Word16

-- ErrorCode is unrelated to Row/Col -- keep as Word16
```

The `ErrorCode` type in Diagnostic.hs uses `Word16` for error codes, which is unrelated to row/col. No change needed.

#### Step 2.4: Update encodeRegion in Diagnostic.hs

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Reporting/Diagnostic.hs` (lines 365-377)

```haskell
encodeRegion (Ann.Region (Ann.Position sr sc) (Ann.Position er ec)) =
  Encode.object
    [ "start" ==> Encode.object
        [ "line" ==> Encode.int (fromIntegral sr),    -- fromIntegral Word32 -> Int is fine
          "column" ==> Encode.int (fromIntegral sc)
        ],
      ...
    ]
```

`fromIntegral` from `Word32` to `Int` works correctly on all 64-bit platforms.

### Phase 3: Update Binary Serialization

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Reporting/Annotation.hs` (lines 82-84)

The `Binary` instance for `Position` uses `put`/`get` from the `Binary` class, which will automatically serialize `Word32` instead of `Word16` after the type change. However, this makes the format incompatible with old `.elmi` files.

**Cache invalidation strategy:** Increment the cache version so old `.elmi` files are regenerated. The project already has a cache versioning mechanism.

### Phase 4: Add Overflow Protection (Optional)

For defense-in-depth, add a check in `eatSpaces` or `fromByteString`:

```haskell
-- At the start of parsing, check if file could overflow
-- A 10MB file with very long lines could have col > 65535
-- With Word32 this is no longer a concern
```

With Word32, overflow is not a practical concern. No file will have 4 billion lines or columns. This phase can be skipped.

## Files to Modify

| File | Change | Lines |
|------|--------|-------|
| `packages/canopy-core/src/Parse/Primitives.hs` | `Word16` -> `Word32` for Row, Col, indent | 38, 65, 70-72 |
| `packages/canopy-core/src/Reporting/Annotation.hs` | `Word16` -> `Word32` for Position | 21, 48-52 |
| `packages/canopy-core/src/Parse/Space.hs` | Update Word16 import, `checkAligned` signature | 17, 69, 210 |
| `packages/canopy-core/src/Reporting/Error/Syntax/Types.hs` | Update Word16 import if used for positions | 59 |
| `packages/canopy-core/src/Reporting/Error/Syntax/Helpers.hs` | Update Word16 import if used for positions | 35 |
| `packages/canopy-core/src/Parse/String.hs` | Update if uses Word16 for positions | 17 |
| `packages/canopy-core/src/Canopy/Version.hs` | Keep Word16 for version components (unrelated) | N/A |
| `packages/canopy-core/src/Canopy/Package.hs` | Keep Word16 for package-specific uses (unrelated) | N/A |

## Verification

```bash
# 1. All code compiles without warnings
make build 2>&1 | grep -c "warning"  # should be 0

# 2. All tests pass
make test

# 3. Verify no remaining Word16 references for Row/Col
grep -rn "Word16" packages/canopy-core/src/Parse/Primitives.hs
# Should only show the import (no longer used for Row/Col)

grep -rn "Word16" packages/canopy-core/src/Reporting/Annotation.hs
# Should not appear (Position uses Word32 now)

# 4. Performance benchmark -- parser should not regress >5%
make bench
# Compare with baseline

# 5. Create a large file test
python3 -c "
lines = ['-- line ' + str(i) for i in range(70000)]
print('module BigModule exposing (..)')
print('x = 1')
for l in lines:
    print(l)
" > /tmp/big-module.can
# canopy make /tmp/big-module.can  # should work with Word32, would overflow with Word16

# 6. Binary format compatibility
# Clear cache and rebuild
rm -rf canopy-stuff elm-stuff
make build
make test
```

## Notes

The Elm compiler (from which Canopy is forked) also uses `Word16` for row/col. This was a deliberate performance optimization in Elm's parser, accepting the overflow limitation. Canopy can make a different tradeoff since:

1. Canopy supports string interpolation and FFI, leading to more complex generated code
2. The performance difference between Word16 and Word32 is negligible on 64-bit architectures
3. Silent overflow producing wrong error locations is worse than a small memory increase
