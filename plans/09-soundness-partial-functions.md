# Plan 09: Partial Function Elimination

**Priority:** MEDIUM
**Effort:** Medium (1–3 days)
**Risk:** Low

## Problem

The codebase contains 70+ `InternalError.report` call sites (which call `error` internally), a raw `error` call in `Generate/JavaScript.hs:636`, 24 uses of `head` in WebIDL tests, and 2 unguarded `maximum`/`minimum` calls. While `InternalError.report` is a deliberate design choice for "impossible" states, the raw `error` and partial test functions are defects.

## Files to Modify (Priority Order)

### 1. Raw `error` in Production Code

**`packages/canopy-core/src/Generate/JavaScript.hs:636`**
```haskell
reportMissingGlobal :: Graph -> Opt.Global -> Opt.Global -> Opt.Node
reportMissingGlobal graph currentGlobal altGlobal =
  ... in error errorMsg  -- RAW ERROR, no Either/Maybe
```

Change return type to `Either InternalError Opt.Node` or use `InternalError.report` for consistency with the rest of the codebase. The caller (`addGlobal`) must handle the error case.

### 2. Partial `head` in Tests

**`packages/canopy-webidl/test/Unit/WebIDL/ParserTest.hs`** — 20+ locations
**`packages/canopy-webidl/test/Unit/WebIDL/TransformTest.hs`** — 4 locations

Replace all `case head (intfMembers intf) of` with pattern matching:
```haskell
-- BEFORE (partial):
case head (intfMembers intf) of
  IntfAttribute attr -> ...

-- AFTER (total):
case intfMembers intf of
  (IntfAttribute attr : _) -> ...
  [] -> assertFailure "expected at least one member"
  (other : _) -> assertFailure ("unexpected member: " ++ show other)
```

### 3. Unguarded `maximum`/`minimum`

**`packages/canopy-terminal/src/Bench.hs:181–182`**:
```haskell
let minTime = minimum times  -- crashes on empty list
    maxTime = maximum times
```
Guard with: `case NE.nonEmpty times of Nothing -> ...; Just ne -> ...`

**`packages/canopy-builder/src/Build/Parallel/Instrumented.hs:97`**:
```haskell
maximum $ map ...  -- crashes on empty list
```
Same fix: use `NE.nonEmpty` or provide a default.

### 4. `SourceMap.hs:281` — Partial Indexing (Existing)

The `!!` on `base64Alphabet` is bounded by the 6-bit VLQ mask, but should use safe indexing:
```haskell
-- BEFORE:
BB.word8 (base64Alphabet !! n)
-- AFTER:
BB.word8 (fromMaybe (error "VLQ: index out of range") (Safe.atMay base64Alphabet n))
```
Or better: use a `Vector` and `Vector.!` with bounds checking.

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Grep for `Prelude.head`, `Prelude.tail`, `Prelude.!!` in packages/ — should return zero results
4. Grep for bare `error` (not `InternalError.report`) in packages/ — should return zero results outside of `InternalError.hs` itself
