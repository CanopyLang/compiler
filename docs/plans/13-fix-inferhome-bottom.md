# Plan 13 — Fix inferHome error/bottom Value

**Priority:** Tier 2 (Type Safety)
**Effort:** 2 hours
**Risk:** Low
**Files:** `packages/canopy-core/src/Generate/JavaScript/CodeSplit/Analyze.hs`

---

## Problem

Line 282 of `Analyze.hs`:

```haskell
inferHome :: Set Opt.Global -> ModuleName.Canonical
inferHome globals =
  case Set.lookupMin globals of
    Just (Opt.Global home _) -> home
    Nothing -> ModuleName.Canonical (error "inferHome: empty set") "empty"
```

This creates a `ModuleName.Canonical` with a bottom `_package` field. It uses bare `Prelude.error` (not even `InternalError.report`). The value is partially constructed — the error is deferred until `_package` is forced, which could be far from the construction site, making debugging extremely difficult.

## Implementation

### Step 1: Make inferHome return Maybe

```haskell
inferHome :: Set Opt.Global -> Maybe ModuleName.Canonical
inferHome globals =
  case Set.lookupMin globals of
    Just (Opt.Global home _) -> Just home
    Nothing -> Nothing
```

### Step 2: Update all callers

Find every call site:

```bash
grep -n "inferHome" packages/canopy-core/src/Generate/JavaScript/CodeSplit/Analyze.hs
```

Update each caller to handle `Nothing` explicitly. The caller should either:
- Skip the empty-set case (if it's a degenerate lazy boundary with no globals)
- Report an internal error with proper context via `InternalError.report`
- Filter out empty sets before calling `inferHome`

Example:

```haskell
-- Before:
let home = inferHome reachable
-- After:
case inferHome reachable of
  Nothing ->
    InternalError.report
      "CodeSplit.Analyze"
      "inferHome called with empty global set"
      ["LazyRoot had no reachable globals"]
  Just home -> ...
```

### Step 3: Search for similar patterns

```bash
grep -rn "error \"" packages/canopy-core/src/ | grep -v InternalError
```

Fix any other bare `Prelude.error` calls found (there should be ~5).

## Validation

```bash
make build && make test
```

## Acceptance Criteria

- `inferHome` returns `Maybe ModuleName.Canonical`
- Zero bare `error "..."` calls in `CodeSplit/Analyze.hs`
- All callers handle `Nothing` explicitly
- `make build && make test` passes
