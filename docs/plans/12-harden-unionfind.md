# Plan 12 — Harden UnionFind Partial Patterns

**Priority:** Tier 2 (Type Safety)
**Effort:** 4 hours
**Risk:** Low (adding safety checks, not changing algorithm)
**Files:** `packages/canopy-core/src/Type/UnionFind.hs`

---

## Problem

`UnionFind.hs` line 129-130 uses irrefutable pattern matching in `union`:

```haskell
union :: Point a -> Point a -> a -> IO ()
union p1 p2 newDesc = do
  point1@(Pt ref1) <- repr p1
  point2@(Pt ref2) <- repr p2
  Info w1 d1 <- readIORef ref1   -- PARTIAL: crashes if Link
  Info w2 d2 <- readIORef ref2   -- PARTIAL: crashes if Link
```

After `repr`, both points should be canonical (`Info` nodes). In correct usage this invariant holds. However, if `repr` ever returns a `Link` node due to a bug (e.g., concurrent modification, or a logic error in path compression), this crashes with an uninformative `Non-exhaustive patterns in pattern binding` message.

Additionally, similar patterns exist in `get`, `set`, `modify`, and `equivalent` — all assume `repr` returns an `Info` node without checking.

## Implementation

### Step 1: Add -Wall

This file lacks `{-# OPTIONS_GHC -Wall #-}`. Add it (as part of Plan 06) so GHC can warn about incomplete patterns.

### Step 2: Replace irrefutable patterns with explicit matching

Replace each irrefutable `Info` pattern with an explicit `case` that uses `InternalError.report` for the impossible `Link` case:

```haskell
union :: Point a -> Point a -> a -> IO ()
union p1 p2 newDesc = do
  (Pt ref1) <- repr p1
  (Pt ref2) <- repr p2
  desc1 <- readIORef ref1
  desc2 <- readIORef ref2
  case (desc1, desc2) of
    (Info w1 _d1, Info w2 _d2) ->
      if w1 >= w2
        then do
          writeIORef ref2 (Link p1)
          writeIORef ref1 (Info (w1 + w2) newDesc)
        else do
          writeIORef ref1 (Link p2)
          writeIORef ref2 (Info (w1 + w2) newDesc)
    _ ->
      InternalError.report
        "Type.UnionFind.union"
        "repr returned a Link node"
        ["This indicates a bug in path compression or concurrent modification."]
```

### Step 3: Apply same pattern to get, set, modify

For each function that reads after `repr`:

```haskell
get :: Point a -> IO a
get point = do
  (Pt ref) <- repr point
  desc <- readIORef ref
  case desc of
    Info _w d -> pure d
    Link _ ->
      InternalError.report
        "Type.UnionFind.get"
        "repr returned a Link node"
        []

set :: Point a -> a -> IO ()
set point newDesc = do
  (Pt ref) <- repr point
  desc <- readIORef ref
  case desc of
    Info w _ -> writeIORef ref (Info w newDesc)
    Link _ ->
      InternalError.report
        "Type.UnionFind.set"
        "repr returned a Link node"
        []
```

### Step 4: Consider adding an assertion mode

For development, add a debug assertion that verifies the `repr` post-condition:

```haskell
-- | Like repr but asserts the result is Info.
reprAssert :: String -> Point a -> IO (Point a)
reprAssert caller point = do
  result@(Pt ref) <- repr point
  desc <- readIORef ref
  case desc of
    Info _ _ -> pure result
    Link _ ->
      InternalError.report
        ("Type.UnionFind." <> caller)
        "repr postcondition violated"
        []
```

This can be used in debug builds and elided in release builds if performance is a concern.

## Validation

```bash
make build && make test
```

All 2,376 tests must pass. The type solver exercises these code paths heavily — any regression will surface immediately.

## Acceptance Criteria

- Zero irrefutable patterns on `Info`/`Link` in `UnionFind.hs`
- Every `readIORef` after `repr` has an explicit `Link` case with `InternalError.report`
- `{-# OPTIONS_GHC -Wall #-}` present
- `make build && make test` passes
