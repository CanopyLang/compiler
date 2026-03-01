# Plan 16: Codegen Double Materialization Fix

**Priority:** MEDIUM
**Effort:** Small (≤8 hours)
**Risk:** Low

## Problem

`Generate/JavaScript.hs:688–694` materializes the entire `Builder` as `LazyByteString` just to count `\n` characters, then discards it. The same Builder is materialized again when the final JS output is written. This doubles allocation for every code fragment. `countNewlines` is called on every kernel chunk (`addKernelChunks`, line 677) and every statement builder (`addBuilder`, line 685).

```haskell
countNewlines :: Builder -> Int
countNewlines b =
  BL.foldl' countNL 0 (BB.toLazyByteString b)
```

The same pattern exists in `Generate/JavaScript/CodeSplit/Generate.hs:486–490`.

## Solution

Track newline counts during Builder construction instead of counting after.

### Option A: CountingBuilder Wrapper (Preferred)

Create a `CountingBuilder` that wraps `Builder` and tracks newlines:

```haskell
data CountingBuilder = CountingBuilder
  { _cbBuilder :: !Builder
  , _cbNewlines :: !Int
  }

singleton :: Char -> CountingBuilder
singleton '\n' = CountingBuilder (BB.char7 '\n') 1
singleton c = CountingBuilder (BB.char7 c) 0

append :: CountingBuilder -> CountingBuilder -> CountingBuilder
append (CountingBuilder b1 n1) (CountingBuilder b2 n2) =
  CountingBuilder (b1 <> b2) (n1 + n2)
```

### Option B: Cache Materialized Bytes

Less intrusive: when `countNewlines` is called, store both the count AND the materialized bytes, so the Builder doesn't need to be materialized again:

```haskell
data MaterializedFragment = MaterializedFragment
  { _mfBytes :: !BL.ByteString
  , _mfNewlines :: !Int
  }

materialize :: Builder -> MaterializedFragment
materialize b =
  let bytes = BB.toLazyByteString b
      count = BL.foldl' countNL 0 bytes
  in MaterializedFragment bytes count
```

### Files to Modify

- `packages/canopy-core/src/Generate/JavaScript.hs` — lines 677, 685, 688–694
- `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Generate.hs` — lines 486–490
- Potentially `packages/canopy-core/src/Generate/JavaScript/Builder.hs` if adding `CountingBuilder`

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Golden tests unchanged — output is byte-for-byte identical
4. Source map line numbers are correct (this is what `countNewlines` is used for)
