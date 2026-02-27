# Plan 11 — Fix unsafeCoerce in Argument Parser

**Priority:** Tier 2 (Type Safety)
**Effort:** 4 hours
**Risk:** Low (completion code path only)
**Files:** `packages/canopy-terminal/impl/Terminal/Chomp/Arguments.hs`

---

## Problem

Line 388 of `Arguments.hs` uses `unsafeCoerce ()` to produce a value of arbitrary type `a`:

```haskell
then (combineCompletions (map generateCompletions revSuggest), Right (unsafeCoerce ()))
```

This coerces `()` into any type `a` for the `Right a` branch. If this code path is reached when `a` is anything other than `()`, the caller receives a corrupt value. This is a type safety violation — the type system says `Right a` but the runtime value is `Right ()`.

## Analysis

The `unsafeCoerce` exists because the completion path needs to return `Either Error a` but doesn't have an actual `a` value when it's only generating completions (not parsing). The type parameter `a` is existentially quantified somewhere in the arg-parser combinator chain.

## Implementation

### Step 1: Understand the type flow

Read the function and its callers to understand what `a` is constrained to:

```bash
grep -n "unsafeCoerce" packages/canopy-terminal/impl/Terminal/Chomp/Arguments.hs
```

Read the surrounding function signature and the combinator that calls it.

### Step 2: Use a proper sum type

The completion path should not return `Right a` at all. Instead, separate the completion result from the parse result:

**Option A: Use `Maybe` for the parse result in completion mode**

```haskell
data ChompResult a
  = Completed [String]           -- shell completions
  | Parsed a                     -- actual parsed value
  | ChompError Error             -- parse error
```

**Option B: Use `Left` for completions too (if the caller treats Left as "stop processing")**

If the caller pattern-matches `Left _` as "no value, just completions", return `Left (CompletionResult completions)` instead of `Right (unsafeCoerce ())`.

**Option C: Constrain `a` to have a default**

If `a` always has a sensible default in the completion context, use that default instead of `unsafeCoerce`.

### Step 3: Remove unsafeCoerce import

After fixing, remove the `import Unsafe.Coerce` if no other uses remain in the file.

### Step 4: Search for other unsafeCoerce uses

```bash
grep -rn "unsafeCoerce" packages/
```

Fix any other occurrences.

## Validation

```bash
make build && make test
```

Additionally test shell completion:

```bash
canopy make --<TAB>   # Should still produce completions
canopy init <TAB>     # Should still produce completions
```

## Acceptance Criteria

- Zero `unsafeCoerce` calls in `packages/canopy-terminal/`
- Shell completion still works correctly
- `make build && make test` passes
